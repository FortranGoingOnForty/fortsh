! ==============================================================================
! Module: signal_handling
! Purpose: POSIX signal handling for trap builtin
! ==============================================================================
module signal_handling
  use iso_c_binding
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Signal constants (POSIX standard)
  integer(c_int), parameter :: SIGHUP    = 1
  integer(c_int), parameter :: SIGINT    = 2
  integer(c_int), parameter :: SIGQUIT   = 3
  integer(c_int), parameter :: SIGILL    = 4
  integer(c_int), parameter :: SIGTRAP   = 5
  integer(c_int), parameter :: SIGABRT   = 6
  integer(c_int), parameter :: SIGBUS    = 7
  integer(c_int), parameter :: SIGFPE    = 8
  integer(c_int), parameter :: SIGKILL   = 9
  integer(c_int), parameter :: SIGUSR1   = 10
  integer(c_int), parameter :: SIGSEGV   = 11
  integer(c_int), parameter :: SIGUSR2   = 12
  integer(c_int), parameter :: SIGPIPE   = 13
  integer(c_int), parameter :: SIGALRM   = 14
  integer(c_int), parameter :: SIGTERM   = 15
  integer(c_int), parameter :: SIGSTKFLT = 16
  integer(c_int), parameter :: SIGCHLD   = 17
  integer(c_int), parameter :: SIGCONT   = 18
  integer(c_int), parameter :: SIGSTOP   = 19
  integer(c_int), parameter :: SIGTSTP   = 20
  integer(c_int), parameter :: SIGTTIN   = 21
  integer(c_int), parameter :: SIGTTOU   = 22

  ! Special trap signals (bash extensions)
  integer, parameter :: TRAP_EXIT  = 0    ! EXIT pseudo-signal
  integer, parameter :: TRAP_DEBUG = -1   ! DEBUG pseudo-signal
  integer, parameter :: TRAP_ERR   = -2   ! ERR pseudo-signal
  integer, parameter :: TRAP_RETURN = -3  ! RETURN pseudo-signal

  ! Signal handler type (void (*handler)(int))
  type, bind(C) :: c_sighandler_t
    type(c_funptr) :: handler
  end type

  ! sigaction structure (simplified for Linux)
  type, bind(C) :: sigaction_t
    type(c_funptr) :: sa_handler     ! Signal handler function pointer
    integer(c_long) :: sa_mask(16)   ! Signal mask (sigset_t, typically 128 bytes / 8 = 16 longs)
    integer(c_int) :: sa_flags       ! Flags
    type(c_funptr) :: sa_restorer    ! Obsolete
  end type

  ! C interface for signal functions
  interface
    ! int sigaction(int signum, const struct sigaction *act, struct sigaction *oldact)
    function c_sigaction(signum, act, oldact) bind(C, name="sigaction")
      use iso_c_binding
      import :: sigaction_t
      integer(c_int), value :: signum
      type(sigaction_t), intent(in) :: act
      type(sigaction_t), intent(out) :: oldact
      integer(c_int) :: c_sigaction
    end function c_sigaction

    ! int raise(int sig)
    function c_raise(sig) bind(C, name="raise")
      use iso_c_binding
      integer(c_int), value :: sig
      integer(c_int) :: c_raise
    end function c_raise
  end interface

  ! Special signal handler constants
  type(c_funptr), parameter :: SIG_DFL = c_null_funptr  ! Default action
  ! SIG_IGN needs to be set to (void(*)(int))1 but we'll handle this specially

  ! Module-level variable to store shell state pointer for signal handlers
  ! Note: This is a simplification - in production, we'd need thread-safe access
  type(shell_state_t), pointer, save :: global_shell_state => null()

  ! Pending signals array - set by signal handlers, checked by shell
  logical, save :: pending_signals(32) = .false.

contains

  ! Generic signal handler (BIND(C) so it can be called from C)
  subroutine generic_signal_handler(signum) bind(C, name="fortsh_signal_handler")
    integer(c_int), value :: signum

    ! Just set the flag - don't do anything complex in a signal handler
    if (signum > 0 .and. signum <= 32) then
      pending_signals(signum) = .true.
    end if
  end subroutine

  ! Initialize signal handling module with shell state
  subroutine init_signal_handling(shell)
    type(shell_state_t), target, intent(inout) :: shell
    global_shell_state => shell
  end subroutine

  ! Convert signal name to signal number
  function signal_name_to_number(name) result(signum)
    character(len=*), intent(in) :: name
    integer :: signum
    character(len=256) :: upper_name
    integer :: i

    ! Convert to uppercase
    upper_name = name
    do i = 1, len_trim(upper_name)
      if (upper_name(i:i) >= 'a' .and. upper_name(i:i) <= 'z') then
        upper_name(i:i) = char(ichar(upper_name(i:i)) - 32)
      end if
    end do

    ! Strip SIG prefix if present
    if (upper_name(1:3) == 'SIG') then
      upper_name = upper_name(4:)
    end if

    select case(trim(upper_name))
    case('HUP', '1')
      signum = SIGHUP
    case('INT', '2')
      signum = SIGINT
    case('QUIT', '3')
      signum = SIGQUIT
    case('ILL', '4')
      signum = SIGILL
    case('TRAP', '5')
      signum = SIGTRAP
    case('ABRT', '6', 'IOT')
      signum = SIGABRT
    case('BUS', '7')
      signum = SIGBUS
    case('FPE', '8')
      signum = SIGFPE
    case('KILL', '9')
      signum = SIGKILL
    case('USR1', '10')
      signum = SIGUSR1
    case('SEGV', '11')
      signum = SIGSEGV
    case('USR2', '12')
      signum = SIGUSR2
    case('PIPE', '13')
      signum = SIGPIPE
    case('ALRM', '14')
      signum = SIGALRM
    case('TERM', '15')
      signum = SIGTERM
    case('STKFLT', '16')
      signum = SIGSTKFLT
    case('CHLD', 'CLD', '17')
      signum = SIGCHLD
    case('CONT', '18')
      signum = SIGCONT
    case('STOP', '19')
      signum = SIGSTOP
    case('TSTP', '20')
      signum = SIGTSTP
    case('TTIN', '21')
      signum = SIGTTIN
    case('TTOU', '22')
      signum = SIGTTOU
    ! Bash extensions
    case('EXIT', '0')
      signum = TRAP_EXIT
    case('DEBUG')
      signum = TRAP_DEBUG
    case('ERR')
      signum = TRAP_ERR
    case('RETURN')
      signum = TRAP_RETURN
    case default
      signum = -999  ! Invalid signal
    end select
  end function

  ! Convert signal number to signal name
  function signal_number_to_name(signum) result(name)
    integer, intent(in) :: signum
    character(len=16) :: name

    select case(signum)
    case(SIGHUP)
      name = 'HUP'
    case(SIGINT)
      name = 'INT'
    case(SIGQUIT)
      name = 'QUIT'
    case(SIGILL)
      name = 'ILL'
    case(SIGTRAP)
      name = 'TRAP'
    case(SIGABRT)
      name = 'ABRT'
    case(SIGBUS)
      name = 'BUS'
    case(SIGFPE)
      name = 'FPE'
    case(SIGKILL)
      name = 'KILL'
    case(SIGUSR1)
      name = 'USR1'
    case(SIGSEGV)
      name = 'SEGV'
    case(SIGUSR2)
      name = 'USR2'
    case(SIGPIPE)
      name = 'PIPE'
    case(SIGALRM)
      name = 'ALRM'
    case(SIGTERM)
      name = 'TERM'
    case(SIGSTKFLT)
      name = 'STKFLT'
    case(SIGCHLD)
      name = 'CHLD'
    case(SIGCONT)
      name = 'CONT'
    case(SIGSTOP)
      name = 'STOP'
    case(SIGTSTP)
      name = 'TSTP'
    case(SIGTTIN)
      name = 'TTIN'
    case(SIGTTOU)
      name = 'TTOU'
    case(TRAP_EXIT)
      name = 'EXIT'
    case(TRAP_DEBUG)
      name = 'DEBUG'
    case(TRAP_ERR)
      name = 'ERR'
    case(TRAP_RETURN)
      name = 'RETURN'
    case default
      write(name, '(i0)') signum
    end select
  end function

  ! Set a signal trap
  subroutine set_signal_trap(shell, signum, command)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    character(len=*), intent(in) :: command
    integer :: i, free_slot
    logical :: found
    type(sigaction_t) :: sa, old_sa
    integer(c_int) :: ret

    ! Find existing trap or free slot
    found = .false.
    free_slot = -1
    do i = 1, size(shell%traps)
      if (shell%traps(i)%signal == signum .and. shell%traps(i)%active) then
        ! Update existing trap
        shell%traps(i)%command = command
        found = .true.
        exit
      else if (.not. shell%traps(i)%active .and. free_slot == -1) then
        free_slot = i
      end if
    end do

    if (.not. found) then
      if (free_slot == -1) then
        write(error_unit, '(a)') 'trap: too many traps'
        return
      end if

      ! Add new trap
      shell%traps(free_slot)%signal = signum
      shell%traps(free_slot)%command = command
      shell%traps(free_slot)%active = .true.
      shell%num_traps = shell%num_traps + 1
    end if

    ! For real signals (not pseudo-signals like EXIT), register signal handler
    if (signum > 0 .and. signum <= 31) then
      ! Initialize sigaction structure
      sa%sa_handler = c_funloc(generic_signal_handler)
      sa%sa_mask = 0
      sa%sa_flags = 0  ! Could add SA_RESTART for automatic syscall restart
      sa%sa_restorer = c_null_funptr

      ! Register the signal handler
      ret = c_sigaction(int(signum, c_int), sa, old_sa)
      if (ret /= 0) then
        write(error_unit, '(a,i0)') 'trap: failed to set signal handler for signal ', signum
      end if
    end if
  end subroutine

  ! Remove a signal trap
  subroutine remove_signal_trap(shell, signum)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    integer :: i
    type(sigaction_t) :: sa, old_sa
    integer(c_int) :: ret

    ! Find and deactivate trap
    do i = 1, size(shell%traps)
      if (shell%traps(i)%signal == signum .and. shell%traps(i)%active) then
        shell%traps(i)%active = .false.
        shell%traps(i)%command = ''
        shell%num_traps = shell%num_traps - 1

        ! Reset signal to default handler
        if (signum > 0 .and. signum <= 31) then
          sa%sa_handler = SIG_DFL
          sa%sa_mask = 0
          sa%sa_flags = 0
          sa%sa_restorer = c_null_funptr

          ret = c_sigaction(int(signum, c_int), sa, old_sa)
          if (ret /= 0) then
            write(error_unit, '(a,i0)') 'trap: failed to reset signal handler for signal ', signum
          end if
        end if

        exit
      end if
    end do
  end subroutine

  ! List all active traps
  subroutine list_traps(shell)
    type(shell_state_t), intent(in) :: shell
    integer :: i
    character(len=16) :: sig_name

    do i = 1, size(shell%traps)
      if (shell%traps(i)%active) then
        sig_name = signal_number_to_name(shell%traps(i)%signal)
        write(output_unit, '(a)') 'trap -- ' // "'" // trim(shell%traps(i)%command) // &
                                  "' " // trim(sig_name)
      end if
    end do
  end subroutine

  ! Get trap command for a signal (returns empty string if no trap set)
  function get_trap_command(shell, signum) result(command)
    type(shell_state_t), intent(in) :: shell
    integer, intent(in) :: signum
    character(len=4096) :: command
    integer :: i

    command = ''

    ! Find the trap command for this signal
    do i = 1, size(shell%traps)
      if (shell%traps(i)%signal == signum .and. shell%traps(i)%active) then
        command = trim(shell%traps(i)%command)
        exit
      end if
    end do
  end function

  ! Get pending trap signals and clear flags
  ! Returns array of signal numbers that have pending traps (0-terminated)
  subroutine get_pending_trap_signals(signals, count)
    integer, intent(out) :: signals(32)
    integer, intent(out) :: count
    integer :: signum

    count = 0
    signals = 0

    ! Check each signal
    do signum = 1, 32
      if (pending_signals(signum)) then
        ! Clear the flag
        pending_signals(signum) = .false.

        ! Add to list
        count = count + 1
        signals(count) = signum
      end if
    end do
  end subroutine

  ! Check if a signal can be trapped
  function is_trappable_signal(signum) result(trappable)
    integer, intent(in) :: signum
    logical :: trappable

    ! SIGKILL and SIGSTOP cannot be caught or ignored
    trappable = (signum /= SIGKILL .and. signum /= SIGSTOP)
  end function

  ! Execute a trap command
  ! Returns .true. if trap was executed, .false. if no trap was set
  function execute_trap(shell, signum, saved_exit_status) result(executed)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: signum
    integer, intent(in), optional :: saved_exit_status
    logical :: executed
    character(len=4096) :: trap_cmd
    integer :: original_status

    ! Prevent recursive trap execution (traps don't trigger traps)
    if (shell%executing_trap) then
      executed = .false.
      return
    end if

    ! Get the trap command
    trap_cmd = get_trap_command(shell, signum)

    if (len_trim(trap_cmd) == 0) then
      executed = .false.
      return
    end if

    ! Save current exit status
    original_status = shell%last_exit_status

    ! If saved_exit_status provided (for ERR trap), use it
    if (present(saved_exit_status)) then
      original_status = saved_exit_status
    end if

    ! Store the trap command for execution by the caller (executor module)
    ! This avoids circular dependency between signal_handling and executor modules
    ! The executor will parse and execute the trap command using execute_eval style
    shell%pending_trap_command = trim(trap_cmd)
    shell%pending_trap_signal = signum

    ! Restore original exit status (traps don't affect $?)
    shell%last_exit_status = original_status

    executed = .true.
  end function

end module signal_handling
