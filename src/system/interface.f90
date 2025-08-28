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

  ! Terminal control structures and constants
  integer(c_int), parameter :: NCCS = 32
  
  ! termios structure - simplified version matching C struct termios
  type, bind(c) :: termios_t
    integer(c_int) :: c_iflag    ! input flags
    integer(c_int) :: c_oflag    ! output flags  
    integer(c_int) :: c_cflag    ! control flags
    integer(c_int) :: c_lflag    ! local flags
    character(c_char) :: c_cc(NCCS) ! control characters
  end type termios_t
  
  ! Terminal flags
  integer(c_int), parameter :: ICANON = int(z'00000002', c_int)  ! canonical input
  integer(c_int), parameter :: ECHO   = int(z'00000008', c_int)  ! enable echo
  integer(c_int), parameter :: ECHOE  = int(z'00000010', c_int)  ! echo erase character
  integer(c_int), parameter :: ECHOK  = int(z'00000020', c_int)  ! echo kill character
  integer(c_int), parameter :: ECHONL = int(z'00000040', c_int)  ! echo NL even if ECHO is off
  integer(c_int), parameter :: IEXTEN = int(z'00008000', c_int)  ! extended input processing
  integer(c_int), parameter :: ISIG   = int(z'00000001', c_int)  ! enable signals
  
  ! Control character indices
  integer(c_int), parameter :: VMIN  = 6   ! minimum chars for noncanonical read
  integer(c_int), parameter :: VTIME = 5   ! timeout for noncanonical read
  
  ! tcsetattr options
  integer(c_int), parameter :: TCSANOW   = 0  ! change immediately
  integer(c_int), parameter :: TCSADRAIN = 1  ! change after output drained
  integer(c_int), parameter :: TCSAFLUSH = 2  ! change after output drained and input flushed

  ! ANSI escape sequences for cursor control
  character(len=*), parameter :: ESC_CLEAR_LINE = char(27) // '[K'
  character(len=*), parameter :: ESC_MOVE_BOL = char(13)  ! Carriage return  
  character(len=*), parameter :: ESC_CURSOR_LEFT = char(27) // '[D'
  character(len=*), parameter :: ESC_CURSOR_RIGHT = char(27) // '[C'
  character(len=*), parameter :: ESC_SAVE_CURSOR = char(27) // '[s'
  character(len=*), parameter :: ESC_RESTORE_CURSOR = char(27) // '[u'

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
    
    ! Terminal control functions
    function c_tcgetattr(fd, termios_p) bind(C, name="tcgetattr")
      import :: c_int, termios_t
      integer(c_int), value :: fd
      type(termios_t), intent(out) :: termios_p
      integer(c_int) :: c_tcgetattr
    end function
    
    function c_tcsetattr(fd, optional_actions, termios_p) bind(C, name="tcsetattr")
      import :: c_int, termios_t
      integer(c_int), value :: fd, optional_actions
      type(termios_t), intent(in) :: termios_p
      integer(c_int) :: c_tcsetattr
    end function
    
    function c_read(fd, buf, count) bind(C, name="read")
      import :: c_int, c_ptr, c_size_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: c_read
    end function
    
    subroutine c_cfmakeraw(termios_p) bind(C, name="cfmakeraw")
      import :: termios_t
      type(termios_t), intent(inout) :: termios_p
    end subroutine
    
    function c_getppid() bind(C, name="getppid")
      import :: c_pid_t
      integer(c_pid_t) :: c_getppid
    end function
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

  ! Terminal control functions
  function enable_raw_mode(original_termios) result(success)
    type(termios_t), intent(out) :: original_termios
    logical :: success
    type(termios_t) :: raw_termios
    integer :: ret
    
    success = .false.
    
    ! Get current terminal settings
    ret = c_tcgetattr(STDIN_FD, original_termios)
    if (ret /= 0) return
    
    ! Copy to modify for raw mode
    raw_termios = original_termios
    
    ! Disable canonical mode and echo
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(ior(ior(ICANON, ECHO), ior(ECHOE, ECHOK))))
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(ior(ECHONL, IEXTEN)))
    
    ! Set minimum characters and timeout for read
    raw_termios%c_cc(VMIN + 1) = char(1)  ! Read at least 1 character
    raw_termios%c_cc(VTIME + 1) = char(0) ! No timeout
    
    ! Apply raw mode settings
    ret = c_tcsetattr(STDIN_FD, TCSANOW, raw_termios)
    success = (ret == 0)
  end function
  
  function restore_terminal(original_termios) result(success)
    type(termios_t), intent(in) :: original_termios
    logical :: success
    integer :: ret
    
    ret = c_tcsetattr(STDIN_FD, TCSANOW, original_termios)
    success = (ret == 0)
  end function
  
  function read_single_char(ch) result(success)
    character, intent(out) :: ch
    logical :: success
    character(c_char), target :: c_ch
    integer(c_size_t) :: bytes_read
    
    bytes_read = c_read(STDIN_FD, c_loc(c_ch), 1_c_size_t)
    success = (bytes_read == 1)
    if (success) then
      ch = c_ch
    else
      ch = char(0)
    end if
  end function

  ! Get current process ID
  function get_pid() result(pid)
    integer(c_pid_t) :: pid
    pid = c_getpid()
  end function

  ! Get parent process ID
  function get_ppid() result(ppid)
    integer(c_pid_t) :: ppid
    ppid = c_getppid()
  end function

end module system_interface