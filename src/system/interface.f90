! ==============================================================================
! Module: system_interface
! Purpose: C function interfaces and system call wrappers
! ==============================================================================
module system_interface
  use iso_c_binding
  use shell_types
  implicit none

  ! Signal numbers
  integer(c_int), parameter :: SIGINT = 2
  integer(c_int), parameter :: SIGTSTP = 20
  integer(c_int), parameter :: SIGCHLD = 17
  integer(c_int), parameter :: SIGCONT = 18
  integer(c_int), parameter :: SIGTTIN = 21
  integer(c_int), parameter :: SIGTTOU = 22

  ! Wait options
  integer(c_int), parameter :: WNOHANG = 1
  integer(c_int), parameter :: WUNTRACED = 2

  ! C function interfaces
  interface
    function c_fork() bind(C, name="fork")
      import :: c_pid_t
      integer(c_pid_t) :: c_fork
    end function
    
    function c_execvp(file, argv) bind(C, name="execvp")
      import :: c_ptr, c_int
      type(c_ptr), value :: file, argv
      integer(c_int) :: c_execvp
    end function
    
    function c_waitpid(pid, status, options) bind(C, name="waitpid")
      import :: c_pid_t, c_ptr, c_int
      integer(c_pid_t), value :: pid
      type(c_ptr), value :: status
      integer(c_int), value :: options
      integer(c_pid_t) :: c_waitpid
    end function
    
    function c_gethostname(name, len) bind(C, name="gethostname")
      import :: c_ptr, c_size_t, c_int
      type(c_ptr), value :: name
      integer(c_size_t), value :: len
      integer(c_int) :: c_gethostname
    end function
    
    function c_getenv(name) bind(C, name="getenv")
      import :: c_ptr
      type(c_ptr), value :: name
      type(c_ptr) :: c_getenv
    end function
    
    function c_setenv(name, value, overwrite) bind(C, name="setenv")
      import :: c_ptr, c_int
      type(c_ptr), value :: name, value
      integer(c_int), value :: overwrite
      integer(c_int) :: c_setenv
    end function
    
    function c_chdir(path) bind(C, name="chdir")
      import :: c_ptr, c_int
      type(c_ptr), value :: path
      integer(c_int) :: c_chdir
    end function
    
    function c_getcwd(buf, size) bind(C, name="getcwd")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: buf
      integer(c_size_t), value :: size
      type(c_ptr) :: c_getcwd
    end function
    
    function c_open(pathname, flags, mode) bind(C, name="open")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int), value :: flags, mode
      integer(c_int) :: c_open
    end function
    
    function c_close(fd) bind(C, name="close")
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: c_close
    end function
    
    function c_dup2(oldfd, newfd) bind(C, name="dup2")
      import :: c_int
      integer(c_int), value :: oldfd, newfd
      integer(c_int) :: c_dup2
    end function
    
    function c_pipe(pipefd) bind(C, name="pipe")
      import :: c_ptr, c_int
      type(c_ptr), value :: pipefd
      integer(c_int) :: c_pipe
    end function
    
    function c_getpid() bind(C, name="getpid")
      import :: c_pid_t
      integer(c_pid_t) :: c_getpid
    end function
    
    function c_getpgid(pid) bind(C, name="getpgid")
      import :: c_pid_t
      integer(c_pid_t), value :: pid
      integer(c_pid_t) :: c_getpgid
    end function
    
    function c_setpgid(pid, pgid) bind(C, name="setpgid")
      import :: c_pid_t, c_int
      integer(c_pid_t), value :: pid, pgid
      integer(c_int) :: c_setpgid
    end function
    
    function c_tcgetpgrp(fd) bind(C, name="tcgetpgrp")
      import :: c_int, c_pid_t
      integer(c_int), value :: fd
      integer(c_pid_t) :: c_tcgetpgrp
    end function
    
    function c_tcsetpgrp(fd, pgrp) bind(C, name="tcsetpgrp")
      import :: c_int, c_pid_t
      integer(c_int), value :: fd
      integer(c_pid_t), value :: pgrp
      integer(c_int) :: c_tcsetpgrp
    end function
    
    function c_kill(pid, sig) bind(C, name="kill")
      import :: c_pid_t, c_int
      integer(c_pid_t), value :: pid
      integer(c_int), value :: sig
      integer(c_int) :: c_kill
    end function
    
    function c_signal(signum, handler) bind(C, name="signal")
      import :: c_int, c_funptr
      integer(c_int), value :: signum
      type(c_funptr), value :: handler
      type(c_funptr) :: c_signal
    end function
    
    function c_isatty(fd) bind(C, name="isatty")
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: c_isatty
    end function
    
    function c_write(fd, buf, count) bind(C, name="write")
      import :: c_int, c_ptr, c_size_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: c_write
    end function
    
    function c_popen(command, type) bind(C, name="popen")
      import :: c_ptr
      type(c_ptr), value :: command, type
      type(c_ptr) :: c_popen
    end function
    
    function c_pclose(stream) bind(C, name="pclose")
      import :: c_ptr, c_int
      type(c_ptr), value :: stream
      integer(c_int) :: c_pclose
    end function
    
    function c_fgets(s, size, stream) bind(C, name="fgets")
      import :: c_ptr, c_int
      type(c_ptr), value :: s
      integer(c_int), value :: size
      type(c_ptr), value :: stream
      type(c_ptr) :: c_fgets
    end function
    
    subroutine c_exit(status) bind(C, name="exit")
      import :: c_int
      integer(c_int), value :: status
    end subroutine
  end interface

  ! Signal handler types
  type(c_funptr) :: SIG_DFL, SIG_IGN

  ! File flags for open()
  integer(c_int), parameter :: O_RDONLY = 0
  integer(c_int), parameter :: O_WRONLY = 1
  integer(c_int), parameter :: O_CREAT = 64
  integer(c_int), parameter :: O_TRUNC = 512
  integer(c_int), parameter :: O_APPEND = 1024

  ! File descriptors
  integer(c_int), parameter :: STDIN_FD = 0
  integer(c_int), parameter :: STDOUT_FD = 1
  integer(c_int), parameter :: STDERR_FD = 2

contains

  function get_environment_var(var_name) result(value)
    character(len=*), intent(in) :: var_name
    character(len=:), allocatable :: value
    type(c_ptr) :: c_value_ptr
    character(kind=c_char), pointer :: c_value(:)
    integer :: i
    character(len=256), target :: c_var_name
    
    c_var_name = trim(var_name)//c_null_char
    c_value_ptr = c_getenv(c_loc(c_var_name))
    
    if (c_associated(c_value_ptr)) then
      call c_f_pointer(c_value_ptr, c_value, [MAX_ENV_LEN])
      
      do i = 1, MAX_ENV_LEN
        if (c_value(i) == c_null_char) exit
      end do
      
      allocate(character(len=i-1) :: value)
      do i = 1, len(value)
        value(i:i) = c_value(i)
      end do
    else
      allocate(character(len=0) :: value)
    end if
  end function

  function set_environment_var(var_name, var_value) result(success)
    character(len=*), intent(in) :: var_name, var_value
    logical :: success
    integer :: ret
    character(len=256), target :: c_var_name, c_var_value
    
    c_var_name = trim(var_name)//c_null_char
    c_var_value = trim(var_value)//c_null_char
    ret = c_setenv(c_loc(c_var_name), c_loc(c_var_value), 1_c_int)
    success = (ret == 0)
  end function

  function change_directory(path) result(success)
    character(len=*), intent(in) :: path
    logical :: success
    integer :: ret
    character(len=256), target :: c_path
    
    c_path = trim(path)//c_null_char
    ret = c_chdir(c_loc(c_path))
    success = (ret == 0)
  end function

  function get_current_directory() result(path)
    character(len=:), allocatable :: path
    character(kind=c_char), target :: c_path(MAX_PATH_LEN)
    type(c_ptr) :: ret_ptr
    integer :: i
    
    ret_ptr = c_getcwd(c_loc(c_path), int(MAX_PATH_LEN, c_size_t))
    
    if (c_associated(ret_ptr)) then
      do i = 1, MAX_PATH_LEN
        if (c_path(i) == c_null_char) exit
      end do
      
      allocate(character(len=i-1) :: path)
      do i = 1, len(path)
        path(i:i) = c_path(i)
      end do
    else
      allocate(character(len=0) :: path)
    end if
  end function

  function create_pipe(read_fd, write_fd) result(success)
    integer(c_int), intent(out) :: read_fd, write_fd
    logical :: success
    integer(c_int), target :: pipefd(2)
    integer :: ret
    
    ret = c_pipe(c_loc(pipefd))
    if (ret == 0) then
      read_fd = pipefd(1)
      write_fd = pipefd(2)
      success = .true.
    else
      success = .false.
    end if
  end function

  ! Check process status macros
  function WIFEXITED(status) result(exited)
    integer(c_int), intent(in) :: status
    logical :: exited
    exited = (iand(status, 127) == 0)
  end function

  function WIFSTOPPED(status) result(stopped)
    integer(c_int), intent(in) :: status
    logical :: stopped
    stopped = (iand(status, 255) == 127)
  end function

  function WEXITSTATUS(status) result(exit_status)
    integer(c_int), intent(in) :: status
    integer :: exit_status
    exit_status = ishft(iand(status, 65280), -8)
  end function

  function execute_and_capture(command) result(output)
    character(len=*), intent(in) :: command
    character(len=:), allocatable :: output
    
    type(c_ptr) :: pipe_ptr
    character(kind=c_char), target :: buffer(1024)
    character(len=MAX_TOKEN_LEN*10) :: temp_output
    type(c_ptr) :: ret_ptr
    integer :: i, pos
    character(len=256), target :: c_command
    character(len=4), target :: c_mode
    
    ! Convert strings to proper format  
    c_command = trim(command)//c_null_char
    c_mode = 'r'//c_null_char
    
    ! Open pipe to command
    pipe_ptr = c_popen(c_loc(c_command), c_loc(c_mode))
    
    if (.not. c_associated(pipe_ptr)) then
      allocate(character(len=0) :: output)
      return
    end if
    
    temp_output = ''
    pos = 1
    
    ! Read output
    do
      ret_ptr = c_fgets(c_loc(buffer), 1024, pipe_ptr)
      if (.not. c_associated(ret_ptr)) exit
      
      ! Convert to Fortran string
      do i = 1, 1024
        if (buffer(i) == c_null_char) exit
        if (buffer(i) /= char(10)) then  ! Skip newlines
          temp_output(pos:pos) = buffer(i)
          pos = pos + 1
        else if (pos > 1 .and. temp_output(pos-1:pos-1) /= ' ') then
          temp_output(pos:pos) = ' '
          pos = pos + 1
        end if
      end do
    end do
    
    ! Close pipe
    i = c_pclose(pipe_ptr)
    
    ! Return output
    allocate(character(len=pos-1) :: output)
    output = temp_output(:pos-1)
  end function

end module system_interface