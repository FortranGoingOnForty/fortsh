! ==============================================================================
! Module: signal_handler
! Purpose: Enhanced signal handling and process control
! ==============================================================================
module signal_handler
  use iso_c_binding
  use system_interface
  use shell_types
  implicit none

  ! Additional signal constants not in system_interface
  integer, parameter :: SIGHUP = 1
  integer, parameter :: SIGQUIT = 3
  integer, parameter :: SIGKILL = 9
  integer, parameter :: SIGTERM = 15
  integer, parameter :: SIGALRM = 14

#ifdef __APPLE__
  ! macOS/BSD: SIGWINCH = 28
  integer, parameter :: SIGWINCH = 28
#else
  ! Linux: SIGWINCH = 28 (same on Linux)
  integer, parameter :: SIGWINCH = 28
#endif

  ! Timeout support
  type :: timeout_t
    integer :: seconds = 0
    logical :: active = .false.
    integer(c_pid_t) :: target_pid = 0
    character(len=256) :: command = ''
  end type timeout_t

  type(timeout_t), save :: active_timeout

  ! Global flag for terminal resize detection
  ! volatile ensures compiler doesn't optimize away checks
  logical, save, volatile :: g_terminal_resized = .false.

  interface
    function kill_c(pid, sig) bind(C, name="kill") result(ret)
      import :: c_int, c_pid_t
      integer(c_pid_t), value :: pid
      integer(c_int), value :: sig
      integer(c_int) :: ret
    end function

    function alarm_c(seconds) bind(C, name="alarm") result(ret)
      import :: c_int
      integer(c_int), value :: seconds
      integer(c_int) :: ret
    end function

    function setpgid_c(pid, pgid) bind(C, name="setpgid") result(ret)
      import :: c_int, c_pid_t
      integer(c_pid_t), value :: pid, pgid
      integer(c_int) :: ret
    end function

    function getpgrp_c() bind(C, name="getpgrp") result(pgid)
      import :: c_pid_t
      integer(c_pid_t) :: pgid
    end function
  end interface

contains

  subroutine setup_signal_handlers()
    use iso_fortran_env, only: error_unit
    type(c_funptr) :: old_handler

    ! Initialize signal constants first
    call init_signal_constants()

    ! CRITICAL: Set SIGCHLD to default handler
    ! If inherited as SIG_IGN from parent shell, children are auto-reaped on macOS/BSD
    ! This prevents waitpid from working correctly
    old_handler = c_signal(SIGCHLD, SIG_DFL)

    ! Ignore interactive signals for shell itself
    old_handler = c_signal(SIGINT, SIG_IGN)
#ifndef __APPLE__
    ! On Linux/other platforms, ignore SIGTSTP like other shells
    old_handler = c_signal(SIGTSTP, SIG_IGN)
#endif
    ! On macOS, setting SIGTSTP to SIG_IGN breaks waitpid by causing
    ! children to be auto-reaped, so we leave it at default
    old_handler = c_signal(SIGTTIN, SIG_IGN)
    old_handler = c_signal(SIGTTOU, SIG_IGN)

    ! Handle alarm for timeouts
    old_handler = c_signal(SIGALRM, c_funloc(sigalrm_handler))

    ! Handle terminal window resize
    old_handler = c_signal(SIGWINCH, c_funloc(sigwinch_handler))
  end subroutine

  subroutine sigchld_handler() bind(C)
    ! Child process terminated - will be handled by job control
  end subroutine

  subroutine sigalrm_handler() bind(C)
    ! Timeout occurred
    if (active_timeout%active .and. active_timeout%target_pid > 0) then
      ! Kill the timed-out process
      call send_signal_to_process(active_timeout%target_pid, SIGTERM)
      active_timeout%active = .false.
    end if
  end subroutine

  subroutine sigwinch_handler() bind(C)
    ! Terminal window size changed
    ! Set flag to trigger re-query of terminal dimensions
    g_terminal_resized = .true.
  end subroutine

  ! Enhanced process group management
  function create_process_group(pid) result(success)
    integer(c_pid_t), intent(in) :: pid
    logical :: success
    integer :: ret
    
    ret = setpgid_c(pid, pid)
    success = (ret == 0)
  end function

  function set_process_group(pid, pgid) result(success)
    integer(c_pid_t), intent(in) :: pid, pgid
    logical :: success
    integer :: ret
    
    ret = setpgid_c(pid, pgid)
    success = (ret == 0)
  end function

  function get_shell_process_group() result(pgid)
    integer(c_pid_t) :: pgid
    
    pgid = getpgrp_c()
  end function

  ! Send signal to process or process group
  subroutine send_signal_to_process(pid, signal)
    integer(c_pid_t), intent(in) :: pid
    integer, intent(in) :: signal
    integer :: ret
    
    ret = kill_c(pid, signal)
  end subroutine

  function send_signal_to_group(pgid, signal) result(success)
    integer(c_pid_t), intent(in) :: pgid
    integer, intent(in) :: signal
    logical :: success
    integer :: ret
    
    ! Negative PID sends signal to process group
    ret = kill_c(-pgid, signal)
    success = (ret == 0)
  end function

  ! Enhanced trap handling with multiple signals
  subroutine install_trap(signals, command, shell)
    character(len=*), intent(in) :: signals
    character(len=*), intent(in) :: command  
    type(shell_state_t), intent(inout) :: shell
    
    character(len=32) :: signal_names(20)
    integer :: signal_count, i
    
    ! Parse space-separated signal list
    call parse_signal_list(signals, signal_names, signal_count)
    
    do i = 1, signal_count
      call install_single_trap(signal_names(i), command, shell)
    end do
  end subroutine

  subroutine install_single_trap(signal_name, command, shell)
    character(len=*), intent(in) :: signal_name, command
    type(shell_state_t), intent(inout) :: shell
    
    integer :: signal_num, i, empty_slot
    
    signal_num = get_signal_number(signal_name)
    if (signal_num == 0) return
    
    empty_slot = -1
    
    ! Find existing trap or empty slot
    do i = 1, size(shell%traps)
      if (shell%traps(i)%signal == signal_num) then
        ! Update existing trap
        shell%traps(i)%command = command
        shell%traps(i)%active = (len_trim(command) > 0)
        return
      else if (shell%traps(i)%signal == 0 .and. empty_slot == -1) then
        empty_slot = i
      end if
    end do
    
    ! Install new trap
    if (empty_slot > 0) then
      shell%traps(empty_slot)%signal = signal_num
      shell%traps(empty_slot)%command = command
      shell%traps(empty_slot)%active = (len_trim(command) > 0)
      shell%num_traps = max(shell%num_traps, empty_slot)
    end if
  end subroutine

  function get_signal_number(signal_name) result(signal_num)
    character(len=*), intent(in) :: signal_name
    integer :: signal_num
    
    character(len=32) :: name_upper
    
    name_upper = to_upper(signal_name)
    
    select case (trim(name_upper))
    case ('HUP', 'SIGHUP', '1')
      signal_num = SIGHUP
    case ('INT', 'SIGINT', '2')
      signal_num = 2
    case ('QUIT', 'SIGQUIT', '3')
      signal_num = SIGQUIT
    case ('KILL', 'SIGKILL', '9')
      signal_num = SIGKILL
    case ('TERM', 'SIGTERM', '15')
      signal_num = SIGTERM
    case ('TSTP', 'SIGTSTP')
      signal_num = SIGTSTP
    case ('CONT', 'SIGCONT')
      signal_num = SIGCONT
    case ('EXIT', '0')
      signal_num = 0  ! Special case for exit trap
    case default
      signal_num = 0
    end select
  end function

  subroutine parse_signal_list(signals, signal_names, count)
    character(len=*), intent(in) :: signals
    character(len=32), intent(out) :: signal_names(20)
    integer, intent(out) :: count
    
    integer :: pos, start_pos
    
    count = 0
    pos = 1
    start_pos = 1
    
    do while (pos <= len_trim(signals))
      if (signals(pos:pos) == ' ') then
        if (pos > start_pos .and. count < 20) then
          count = count + 1
          signal_names(count) = signals(start_pos:pos-1)
        end if
        start_pos = pos + 1
      end if
      pos = pos + 1
    end do
    
    ! Handle last signal
    if (start_pos <= len_trim(signals) .and. count < 20) then
      count = count + 1
      signal_names(count) = signals(start_pos:)
    end if
  end subroutine

  ! Command timeout support
  subroutine set_command_timeout(pid, seconds, command)
    integer(c_pid_t), intent(in) :: pid
    integer, intent(in) :: seconds
    character(len=*), intent(in) :: command
    
    integer :: ret
    
    active_timeout%target_pid = pid
    active_timeout%seconds = seconds
    active_timeout%command = command
    active_timeout%active = .true.
    
    ret = alarm_c(seconds)
  end subroutine

  subroutine clear_command_timeout()
    integer :: ret
    
    ret = alarm_c(0)  ! Cancel alarm
    active_timeout%active = .false.
    active_timeout%target_pid = 0
  end subroutine

  function to_upper(str) result(upper_str)
    character(len=*), intent(in) :: str
    character(len=len(str)) :: upper_str
    integer :: i
    
    upper_str = str
    do i = 1, len_trim(str)
      if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
        upper_str(i:i) = char(ichar(str(i:i)) - 32)
      end if
    end do
  end function

end module signal_handler