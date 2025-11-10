module command_capture
  use iso_c_binding
  use iso_fortran_env, only: error_unit
  use shell_types
  use system_interface
  implicit none

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
    function c_fsync(fd) bind(c, name='fsync')
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: c_fsync
    end function
  end interface

contains

  ! Set the execution callback
  subroutine set_execute_callback(callback)
    procedure(execute_callback) :: callback
    execute_command_ptr => callback
  end subroutine set_execute_callback

  subroutine execute_command_and_capture(shell, command, output)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command
    character(len=*), intent(out) :: output

    character(len=256) :: temp_file
    integer :: unit_num, ios, exit_status
    integer :: saved_stdout, new_stdout
    character(len=4096) :: line
    integer :: total_len
    logical :: success

    output = ''

    ! Check if callback is set
    if (.not. associated(execute_command_ptr)) then
      ! Fallback to empty if no callback (shouldn't happen after init)
      shell%last_exit_status = 127
      return
    end if

    ! Create a temporary file for capturing output
    call get_temp_filename(temp_file)

    ! Open the temp file and get its file descriptor
    open(newunit=unit_num, file=temp_file, status='replace', &
         action='write', iostat=ios)
    if (ios /= 0) then
      shell%last_exit_status = 1
      return
    end if

    ! Get the file descriptor
    inquire(unit=unit_num, number=new_stdout)

    ! Save current stdout
    saved_stdout = dup(1)

    ! Redirect stdout to our temp file
    if (dup2(new_stdout, 1) < 0) then
      close(unit_num)
      success = remove_file(temp_file)
      shell%last_exit_status = 1
      return
    end if

    ! Flush and close the Fortran unit (but keep the fd open via dup2)
    close(unit_num)

    ! Execute the command using the callback
    call execute_command_ptr(shell, command, exit_status)

    ! Flush stdout to ensure all output is written
    ios = c_fsync(1)

    ! Restore original stdout
    if (dup2(saved_stdout, 1) < 0) then
      ! Try to restore anyway
    end if
    ios = close(saved_stdout)

    ! Read the captured output
    open(newunit=unit_num, file=temp_file, status='old', &
         action='read', iostat=ios)
    if (ios == 0) then
      output = ''
      total_len = 0
      do
        read(unit_num, '(A)', iostat=ios) line
        if (ios /= 0) exit
        if (total_len > 0) then
          ! Add newline between lines
          if (total_len + 1 <= len(output)) then
            output(total_len+1:total_len+1) = char(10)
            total_len = total_len + 1
          end if
        end if
        ! Add the line
        if (total_len + len_trim(line) <= len(output)) then
          output(total_len+1:total_len+len_trim(line)) = trim(line)
          total_len = total_len + len_trim(line)
        else
          exit
        end if
      end do
      close(unit_num)
    end if

    ! Clean up temp file
    success = remove_file(temp_file)

    ! Preserve exit status
    shell%last_exit_status = exit_status
  end subroutine execute_command_and_capture

  subroutine get_temp_filename(filename)
    character(len=*), intent(out) :: filename
    character(len=8) :: date_str
    character(len=10) :: time_str
    integer :: pid

    call date_and_time(date_str, time_str)
    pid = getpid()

    write(filename, '(A,A,A,I0,A)') '/tmp/fortsh_', &
           trim(time_str), '_', pid, '.tmp'
  end subroutine get_temp_filename

end module command_capture