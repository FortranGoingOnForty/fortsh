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
  private :: kill_c  ! Make kill_c private to avoid conflicts

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

    function read_c(fd, buf, count) bind(C, name="read") result(bytes_read)
      import :: c_int, c_ptr, c_size_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: bytes_read
    end function

    function write_c(fd, buf, count) bind(C, name="write") result(bytes_written)
      import :: c_int, c_ptr, c_size_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: bytes_written
    end function

    function kill_c(pid, sig) bind(C, name="kill") result(ret)
      import :: c_pid_t, c_int
      integer(c_pid_t), value :: pid
      integer(c_int), value :: sig
      integer(c_int) :: ret
    end function

    function execlp_c(file, arg) bind(C, name="execlp")
      import :: c_int, c_ptr
      type(c_ptr), value :: file
      type(c_ptr), value :: arg
      integer(c_int) :: execlp_c
    end function
  end interface

  ! C system() binding (avoid duplicate - use from system_interface if available)
  interface
    function system_c(command) bind(C, name="system")
      import :: c_int, c_char
      character(kind=c_char), intent(in) :: command(*)
      integer(c_int) :: system_c
    end function
  end interface

  integer, parameter :: SIGTERM = 15
  integer, parameter :: SIGKILL = 9

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

      ! Execute command using shell
      call execute_command_in_shell(command)
      
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

    character(kind=c_char), target :: c_data(len(data)+1)
    integer(c_size_t) :: bytes_written
    integer :: i

    success = .false.

    if (coproc_id < 1 .or. coproc_id > size(coprocs)) return
    if (.not. coprocs(coproc_id)%active) return
    if (coprocs(coproc_id)%write_fd < 0) return

    ! Convert to C string
    do i = 1, len(data)
      c_data(i) = data(i:i)
    end do
    c_data(len(data)+1) = c_null_char

    ! Write to coprocess stdin
    bytes_written = write_c(coprocs(coproc_id)%write_fd, c_loc(c_data), int(len(data), c_size_t))

    if (bytes_written > 0) then
      success = .true.
    else
      write(error_unit, '(a,a)') 'coprocess: write failed to ', trim(coprocs(coproc_id)%name)
    end if
  end function

  ! Read from coprocess
  function read_from_coprocess(coproc_id, timeout_ms) result(data)
    integer, intent(in) :: coproc_id
    integer, intent(in), optional :: timeout_ms
    character(len=4096) :: data

    character(kind=c_char), target :: c_buffer(4096)
    integer(c_size_t) :: bytes_read
    integer :: i

    data = ''

    if (coproc_id < 1 .or. coproc_id > size(coprocs)) return
    if (.not. coprocs(coproc_id)%active) return
    if (coprocs(coproc_id)%eof_reached) return
    if (coprocs(coproc_id)%read_fd < 0) return

    ! Read from coprocess stdout
    bytes_read = read_c(coprocs(coproc_id)%read_fd, c_loc(c_buffer), int(4096, c_size_t))

    if (bytes_read > 0) then
      ! Convert C buffer to Fortran string
      do i = 1, int(bytes_read)
        data(i:i) = c_buffer(i)
      end do
    else if (bytes_read == 0) then
      ! EOF reached
      coprocs(coproc_id)%eof_reached = .true.
    else
      ! Read error
      write(error_unit, '(a,a)') 'coprocess: read failed from ', trim(coprocs(coproc_id)%name)
    end if
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
    
    ! Kill process if still running
    if (coprocs(coproc_id)%pid > 0) then
      ! Try SIGTERM first (graceful)
      ret = kill_c(coprocs(coproc_id)%pid, SIGTERM)
      ! Wait briefly and check if process is still alive
      ret = waitpid_c(coprocs(coproc_id)%pid, status, 1) ! WNOHANG = 1
      if (ret == 0) then
        ! Process still running, force kill
        ret = kill_c(coprocs(coproc_id)%pid, SIGKILL)
        ret = waitpid_c(coprocs(coproc_id)%pid, status, 0)
      end if
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

    character(kind=c_char), target :: c_command(len(command)+1)
    integer(c_int) :: exit_status
    integer :: i

    ! Convert command to C string
    do i = 1, len(command)
      c_command(i) = command(i:i)
    end do
    c_command(len(command)+1) = c_null_char

    ! Execute command using system()
    ! This runs the command in a subshell (via /bin/sh -c)
    exit_status = system_c(c_command)

    ! Exit with the command's exit status (use c_exit from iso_c_binding)
    call c_exit(int(exit_status / 256, c_int))  ! Extract exit code from wait status
  end subroutine

end module coprocess