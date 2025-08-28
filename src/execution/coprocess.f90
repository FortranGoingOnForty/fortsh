! ==============================================================================
! Module: coprocess
! Purpose: Coprocess management for bidirectional communication
! ==============================================================================
module coprocess
  use shell_types
  use system_interface
  use iso_c_binding, only: c_int
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Coprocess type
  type :: coproc_t
    character(len=256) :: name = ''
    character(len=1024) :: command = ''
    integer(c_pid_t) :: pid = 0
    integer :: read_fd = -1   ! Shell reads from coprocess
    integer :: write_fd = -1  ! Shell writes to coprocess
    logical :: active = .false.
    logical :: eof_reached = .false.
  end type coproc_t

  ! Global coprocess registry
  type(coproc_t), save :: coprocs(10)
  integer, save :: num_coprocs = 0

  interface
    function pipe_c(fds) bind(C, name="pipe")
      import :: c_int
      integer(c_int) :: pipe_c
      integer(c_int), intent(out) :: fds(2)
    end function

    function fork_c() bind(C, name="fork") result(pid)
      import :: c_pid_t
      integer(c_pid_t) :: pid
    end function

    function dup2_c(oldfd, newfd) bind(C, name="dup2") result(ret)
      import :: c_int
      integer(c_int), value :: oldfd, newfd
      integer(c_int) :: ret
    end function

    function close_c(fd) bind(C, name="close") result(ret)
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: ret
    end function

    function waitpid_c(pid, status, options) bind(C, name="waitpid") result(ret)
      import :: c_pid_t, c_int
      integer(c_pid_t), value :: pid
      integer(c_int), intent(out) :: status
      integer(c_int), value :: options
      integer(c_pid_t) :: ret
    end function
  end interface

contains

  ! Start a coprocess with optional name
  function start_coprocess(command, name) result(coproc_id)
    character(len=*), intent(in) :: command
    character(len=*), intent(in), optional :: name
    integer :: coproc_id
    
    integer(c_int) :: pipe_to_child(2), pipe_from_child(2)
    integer(c_pid_t) :: pid
    integer :: i, ret
    character(len=256) :: coproc_name
    
    coproc_id = -1
    
    ! Find available slot
    do i = 1, size(coprocs)
      if (.not. coprocs(i)%active) then
        coproc_id = i
        exit
      end if
    end do
    
    if (coproc_id == -1) then
      write(error_unit, '(a)') 'coprocess: maximum number of coprocesses reached'
      return
    end if
    
    ! Create pipes
    ret = pipe_c(pipe_to_child)
    if (ret /= 0) then
      write(error_unit, '(a)') 'coprocess: failed to create pipe to child'
      return
    end if
    
    ret = pipe_c(pipe_from_child)
    if (ret /= 0) then
      write(error_unit, '(a)') 'coprocess: failed to create pipe from child'
      ret = close_c(pipe_to_child(1))
      ret = close_c(pipe_to_child(2))
      return
    end if
    
    ! Fork process
    pid = fork_c()
    
    if (pid == 0) then
      ! Child process
      
      ! Redirect stdin to read from parent
      ret = dup2_c(pipe_to_child(1), 0)
      ret = close_c(pipe_to_child(1))
      ret = close_c(pipe_to_child(2))
      
      ! Redirect stdout to write to parent
      ret = dup2_c(pipe_from_child(2), 1)
      ret = close_c(pipe_from_child(1))
      ret = close_c(pipe_from_child(2))
      
      ! Execute command - placeholder
      stop 0
      
    else if (pid > 0) then
      ! Parent process
      
      ! Close child ends of pipes
      ret = close_c(pipe_to_child(1))
      ret = close_c(pipe_from_child(2))
      
      ! Set up coprocess structure
      if (present(name)) then
        coproc_name = name
      else
        write(coproc_name, '(a,I0)') 'COPROC', coproc_id
      end if
      
      coprocs(coproc_id)%name = coproc_name
      coprocs(coproc_id)%command = command
      coprocs(coproc_id)%pid = pid
      coprocs(coproc_id)%write_fd = pipe_to_child(2)    ! Shell writes here
      coprocs(coproc_id)%read_fd = pipe_from_child(1)   ! Shell reads here
      coprocs(coproc_id)%active = .true.
      coprocs(coproc_id)%eof_reached = .false.
      
      num_coprocs = max(num_coprocs, coproc_id)
      
      write(output_unit, '(a,a,a,I0)') '[', trim(coproc_name), '] ', pid
      
    else
      ! Fork failed
      write(error_unit, '(a)') 'coprocess: fork failed'
      ret = close_c(pipe_to_child(1))
      ret = close_c(pipe_to_child(2))
      ret = close_c(pipe_from_child(1))
      ret = close_c(pipe_from_child(2))
      coproc_id = -1
    end if
  end function

  ! Write to coprocess
  function write_to_coprocess(coproc_id, data) result(success)
    integer, intent(in) :: coproc_id
    character(len=*), intent(in) :: data
    logical :: success
    
    integer :: unit, iostat
    
    success = .false.
    
    if (coproc_id < 1 .or. coproc_id > size(coprocs)) return
    if (.not. coprocs(coproc_id)%active) return
    
    ! Write to coprocess stdin - simplified approach
    success = .true.  ! Placeholder implementation
    
    if (.not. success) then
      write(error_unit, '(a,a)') 'coprocess: write failed to ', trim(coprocs(coproc_id)%name)
    end if
  end function

  ! Read from coprocess
  function read_from_coprocess(coproc_id, timeout_ms) result(data)
    integer, intent(in) :: coproc_id
    integer, intent(in), optional :: timeout_ms
    character(len=4096) :: data
    
    integer :: unit, iostat
    character(len=256) :: line
    
    data = ''
    
    if (coproc_id < 1 .or. coproc_id > size(coprocs)) return
    if (.not. coprocs(coproc_id)%active) return
    if (coprocs(coproc_id)%eof_reached) return
    
    ! Read from coprocess stdout - simplified approach
    data = ''  ! Placeholder implementation
  end function

  ! Find coprocess by name
  function find_coprocess(name) result(coproc_id)
    character(len=*), intent(in) :: name
    integer :: coproc_id
    integer :: i
    
    coproc_id = -1
    
    do i = 1, num_coprocs
      if (coprocs(i)%active .and. trim(coprocs(i)%name) == trim(name)) then
        coproc_id = i
        exit
      end if
    end do
  end function

  ! Kill and cleanup coprocess
  subroutine kill_coprocess(coproc_id)
    integer, intent(in) :: coproc_id
    
    integer :: ret, status
    
    if (coproc_id < 1 .or. coproc_id > size(coprocs)) return
    if (.not. coprocs(coproc_id)%active) return
    
    ! Close file descriptors
    if (coprocs(coproc_id)%read_fd >= 0) then
      ret = close_c(coprocs(coproc_id)%read_fd)
    end if
    
    if (coprocs(coproc_id)%write_fd >= 0) then
      ret = close_c(coprocs(coproc_id)%write_fd)
    end if
    
    ! Kill process if still running - placeholder
    if (coprocs(coproc_id)%pid > 0) then
      ret = 0  ! Placeholder
    end if
    
    ! Mark as inactive
    coprocs(coproc_id)%active = .false.
    coprocs(coproc_id)%name = ''
    coprocs(coproc_id)%command = ''
    coprocs(coproc_id)%pid = 0
    coprocs(coproc_id)%read_fd = -1
    coprocs(coproc_id)%write_fd = -1
    coprocs(coproc_id)%eof_reached = .false.
  end subroutine

  ! List active coprocesses
  subroutine list_coprocesses()
    integer :: i
    logical :: found_any
    
    found_any = .false.
    
    do i = 1, num_coprocs
      if (coprocs(i)%active) then
        if (.not. found_any) then
          write(output_unit, '(a)') 'Active coprocesses:'
          found_any = .true.
        end if
        write(output_unit, '(a,I2,a,a,a,I0,a,a)') '[', i, '] ', &
          trim(coprocs(i)%name), ' PID:', coprocs(i)%pid, ' CMD: ', trim(coprocs(i)%command)
      end if
    end do
    
    if (.not. found_any) then
      write(output_unit, '(a)') 'No active coprocesses'
    end if
  end subroutine

  ! Cleanup all coprocesses
  subroutine cleanup_all_coprocesses()
    integer :: i
    
    do i = 1, num_coprocs
      if (coprocs(i)%active) then
        call kill_coprocess(i)
      end if
    end do
    
    num_coprocs = 0
  end subroutine

  function int_to_string(val) result(str)
    integer, intent(in) :: val
    character(len=32) :: str
    
    write(str, '(I0)') val
  end function

  subroutine execute_command_in_shell(command)
    character(len=*), intent(in) :: command
    
    ! Simple command execution - placeholder implementation
  end subroutine

end module coprocess