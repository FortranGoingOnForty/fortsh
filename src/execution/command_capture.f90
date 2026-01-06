module command_capture
  use iso_c_binding
  use iso_fortran_env, only: error_unit
  use shell_types
  use system_interface
  implicit none

  ! Define c_ssize_t if not available
  integer, parameter :: c_ssize_t = c_long

  ! Interface for the command execution callback
  abstract interface
    subroutine execute_callback(shell, command, exit_status)
      import :: shell_state_t
      type(shell_state_t), intent(inout) :: shell
      character(len=*), intent(in) :: command
      integer, intent(out) :: exit_status
    end subroutine execute_callback
  end interface

  ! Module variable to store the callback
  procedure(execute_callback), pointer :: execute_command_ptr => null()

  interface
    function pipe(fds) bind(c, name='pipe')
      import :: c_int
      integer(c_int), dimension(2), intent(out) :: fds
      integer(c_int) :: pipe
    end function
    function dup(fd) bind(c, name='dup')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: dup
    end function
    function dup2(oldfd, newfd) bind(c, name='dup2')
      import :: c_int
      integer(c_int), value :: oldfd, newfd
      integer(c_int) :: dup2
    end function
    function close(fd) bind(c, name='close')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: close
    end function
    function fork() bind(c, name='fork')
      import :: c_pid_t
      integer(c_pid_t) :: fork
    end function
    function waitpid(pid, stat_loc, options) bind(c, name='waitpid')
      import :: c_pid_t, c_int, c_ptr
      integer(c_pid_t), value :: pid
      type(c_ptr), value :: stat_loc
      integer(c_int), value :: options
      integer(c_pid_t) :: waitpid
    end function
    function fdopen(fd, mode) bind(c, name='fdopen')
      import :: c_int, c_ptr, c_char
      integer(c_int), value :: fd
      character(kind=c_char), dimension(*) :: mode
      type(c_ptr) :: fdopen
    end function
    function read(fd, buf, count) bind(c, name='read')
      import :: c_int, c_ptr, c_size_t, c_ssize_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_ssize_t) :: read
    end function
  end interface

contains

  ! Set the execution callback
  subroutine set_execute_callback(callback)
    procedure(execute_callback) :: callback
    execute_command_ptr => callback
  end subroutine set_execute_callback

  subroutine execute_command_and_capture(shell, command, output, output_len)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command
    character(len=*), intent(out) :: output
    integer, intent(out), optional :: output_len  ! Actual content length

    integer(c_int) :: pipe_fds(2)
    integer(c_int) :: ret, exit_status
    integer(c_pid_t) :: pid
    character(kind=c_char), target :: buffer(4096)
    integer(c_ssize_t) :: bytes_read
    integer :: total_len, i
    integer(c_int), target :: wstatus
    type(c_ptr) :: wstatus_ptr

    output = ''
    if (present(output_len)) output_len = 0

    ! Check if callback is set
    if (.not. associated(execute_command_ptr)) then
      shell%last_exit_status = 127
      return
    end if

    ! Create a pipe
    ret = pipe(pipe_fds)
    if (ret /= 0) then
      shell%last_exit_status = 1
      return
    end if

    ! Fork a child process
    pid = fork()

    if (pid < 0) then
      ! Fork failed
      ret = close(pipe_fds(1))  ! Close read end
      ret = close(pipe_fds(2))  ! Close write end
      shell%last_exit_status = 1
      return
    else if (pid == 0) then
      ! Child process
      ! Close read end of pipe
      ret = close(pipe_fds(1))

      ! Redirect stdout to pipe write end
      ret = dup2(pipe_fds(2), 1)

      ! Close the original pipe write end
      ret = close(pipe_fds(2))

      ! Mark that we're in a capture child (suppress errexit messages)
      shell%in_capture_child = .true.

      ! POSIX: errexit (set -e) IS inherited in command substitution subshells
      ! When errexit triggers in the subshell, it exits with the failing status

      ! Execute the command
      call execute_command_ptr(shell, command, exit_status)

      ! Exit child with the command's exit status
      call c_exit(exit_status)
    else
      ! Parent process
      ! Close write end of pipe
      ret = close(pipe_fds(2))

      ! Read output from pipe
      total_len = 0
      do
        bytes_read = read(pipe_fds(1), c_loc(buffer), int(size(buffer), c_size_t))
        if (bytes_read <= 0) exit

        ! Copy buffer to output
        do i = 1, int(bytes_read)
          if (total_len < len(output)) then
            total_len = total_len + 1
            output(total_len:total_len) = buffer(i)
          end if
        end do
      end do

      ! Close read end
      ret = close(pipe_fds(1))

      ! Wait for child to complete
      wstatus_ptr = c_loc(wstatus)
      pid = waitpid(pid, wstatus_ptr, 0)

      ! Extract exit status (WEXITSTATUS macro equivalent)
      if (pid > 0) then
        shell%last_exit_status = iand(ishft(wstatus, -8), 255)
      else
        shell%last_exit_status = 1
      end if
    end if

    ! Remove trailing newlines for command substitution
    do while (total_len > 0 .and. output(total_len:total_len) == char(10))
      total_len = total_len - 1
    end do
    if (total_len < len(output)) then
      output = output(1:total_len)
    end if

    ! Return the actual content length (preserves trailing whitespace info)
    if (present(output_len)) output_len = total_len

  end subroutine execute_command_and_capture

end module command_capture