! ==============================================================================
! Module: system_interface
! Purpose: C function interfaces and system call wrappers
! ==============================================================================
module system_interface
  use iso_c_binding
  use shell_types
  implicit none

  ! Signal numbers (platform-specific)
#ifdef __APPLE__
  ! macOS/Darwin signal numbers
  integer(c_int), parameter :: SIGINT = 2
  integer(c_int), parameter :: SIGTSTP = 18
  integer(c_int), parameter :: SIGCHLD = 20
  integer(c_int), parameter :: SIGCONT = 19
  integer(c_int), parameter :: SIGTTIN = 21
  integer(c_int), parameter :: SIGTTOU = 22
#else
  ! Linux signal numbers
  integer(c_int), parameter :: SIGINT = 2
  integer(c_int), parameter :: SIGTSTP = 20
  integer(c_int), parameter :: SIGCHLD = 17
  integer(c_int), parameter :: SIGCONT = 18
  integer(c_int), parameter :: SIGTTIN = 21
  integer(c_int), parameter :: SIGTTOU = 22
#endif

  ! Wait options
  integer(c_int), parameter :: WNOHANG = 1
  integer(c_int), parameter :: WUNTRACED = 2

  ! Terminal control structures and constants
#ifdef __APPLE__
  ! macOS has NCCS=20 and uses 8-byte tcflag_t
  integer(c_int), parameter :: NCCS = 20
  ! ioctl request for terminal size (macOS)
  integer(c_long), parameter :: TIOCGWINSZ = int(z'40087468', c_long)
#else
  ! Linux has NCCS=32 and uses 4-byte tcflag_t
  integer(c_int), parameter :: NCCS = 32
  ! ioctl request for terminal size (Linux)
  integer(c_long), parameter :: TIOCGWINSZ = int(z'5413', c_long)
#endif

  ! Window size structure for terminal dimensions
  type, bind(c) :: winsize_t
    integer(c_short) :: ws_row      ! Number of rows
    integer(c_short) :: ws_col      ! Number of columns
    integer(c_short) :: ws_xpixel   ! Horizontal pixels
    integer(c_short) :: ws_ypixel   ! Vertical pixels
  end type winsize_t

  ! termios structure - must match C struct termios exactly
  type, bind(c) :: termios_t
#ifdef __APPLE__
    ! macOS: tcflag_t is unsigned long (8 bytes)
    integer(c_long) :: c_iflag    ! input flags (8 bytes)
    integer(c_long) :: c_oflag    ! output flags (8 bytes)
    integer(c_long) :: c_cflag    ! control flags (8 bytes)
    integer(c_long) :: c_lflag    ! local flags (8 bytes)
    character(c_char) :: c_cc(20) ! control characters (20 bytes)
    character(c_char) :: padding(4) ! padding for alignment (4 bytes)
    integer(c_long) :: c_ispeed   ! input speed (8 bytes)
    integer(c_long) :: c_ospeed   ! output speed (8 bytes)
    ! Total: 72 bytes
#else
    ! Linux: tcflag_t is unsigned int (4 bytes)
    integer(c_int) :: c_iflag     ! input flags (4 bytes)
    integer(c_int) :: c_oflag     ! output flags (4 bytes)
    integer(c_int) :: c_cflag     ! control flags (4 bytes)
    integer(c_int) :: c_lflag     ! local flags (4 bytes)
    character(c_char) :: c_cc(NCCS) ! control characters (32 bytes)
    ! Total: 48 bytes
#endif
  end type termios_t
  
  ! Terminal flags (platform-specific values)
#ifdef __APPLE__
  ! macOS/Darwin values from sys/termios.h - use c_long to match tcflag_t
  integer(c_long), parameter :: ICANON = int(z'00000100', c_long)  ! canonical input
  integer(c_long), parameter :: ECHO   = int(z'00000008', c_long)  ! enable echo
  integer(c_long), parameter :: ECHOE  = int(z'00000002', c_long)  ! echo erase character
  integer(c_long), parameter :: ECHOK  = int(z'00000004', c_long)  ! echo kill character
  integer(c_long), parameter :: ECHONL = int(z'00000010', c_long)  ! echo NL even if ECHO is off
  integer(c_long), parameter :: IEXTEN = int(z'00000400', c_long)  ! extended input processing
  integer(c_long), parameter :: ISIG   = int(z'00000080', c_long)  ! enable signals

  ! Control character indices (macOS)
  integer(c_int), parameter :: VEOF   = 0   ! EOF character (Ctrl-D)
  integer(c_int), parameter :: VEOL   = 1   ! EOL character
  integer(c_int), parameter :: VEOL2  = 2   ! EOL2 character
  integer(c_int), parameter :: VERASE = 3   ! ERASE character
  integer(c_int), parameter :: VWERASE = 4  ! WERASE character
  integer(c_int), parameter :: VKILL  = 5   ! KILL character
  integer(c_int), parameter :: VREPRINT = 6 ! REPRINT character
  integer(c_int), parameter :: VINTR  = 8   ! INTR character (Ctrl-C)
  integer(c_int), parameter :: VQUIT  = 9   ! QUIT character
  integer(c_int), parameter :: VSUSP  = 10  ! SUSP character (Ctrl-Z)
  integer(c_int), parameter :: VDSUSP = 11  ! DSUSP character
  integer(c_int), parameter :: VSTART = 12  ! START character (Ctrl-Q)
  integer(c_int), parameter :: VSTOP  = 13  ! STOP character (Ctrl-S)
  integer(c_int), parameter :: VLNEXT = 14  ! LNEXT character
  integer(c_int), parameter :: VDISCARD = 15 ! DISCARD character
  integer(c_int), parameter :: VMIN  = 16  ! minimum chars for noncanonical read
  integer(c_int), parameter :: VTIME = 17  ! timeout for noncanonical read
#else
  ! Linux values from bits/termios.h - use c_int to match tcflag_t
  integer(c_int), parameter :: ICANON = int(z'00000002', c_int)  ! canonical input
  integer(c_int), parameter :: ECHO   = int(z'00000008', c_int)  ! enable echo
  integer(c_int), parameter :: ECHOE  = int(z'00000010', c_int)  ! echo erase character
  integer(c_int), parameter :: ECHOK  = int(z'00000020', c_int)  ! echo kill character
  integer(c_int), parameter :: ECHONL = int(z'00000040', c_int)  ! echo NL even if ECHO is off
  integer(c_int), parameter :: IEXTEN = int(z'00008000', c_int)  ! extended input processing
  integer(c_int), parameter :: ISIG   = int(z'00000001', c_int)  ! enable signals

  ! Control character indices (Linux)
  integer(c_int), parameter :: VMIN  = 6   ! minimum chars for noncanonical read
  integer(c_int), parameter :: VTIME = 5   ! timeout for noncanonical read
#endif

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
  character(len=*), parameter :: ESC_HIDE_CURSOR = char(27) // '[?25l'
  character(len=*), parameter :: ESC_SHOW_CURSOR = char(27) // '[?25h'

  ! stat structure (must be defined before interface block)
  ! Platform-specific layouts - field order matters!
  type, bind(c) :: stat_t
#ifdef __APPLE__
    ! macOS ARM64/x86_64 stat structure layout
    integer(c_int)   :: st_dev      ! Device (4 bytes) - offset 0
    integer(c_short) :: st_mode     ! File type and mode (2 bytes) - offset 4
    integer(c_short) :: st_nlink    ! Number of hard links (2 bytes) - offset 6
    integer(c_long)  :: st_ino      ! Inode (8 bytes) - offset 8
    integer(c_int)   :: st_uid      ! User ID (4 bytes) - offset 16
    integer(c_int)   :: st_gid      ! Group ID (4 bytes) - offset 20
    integer(c_int)   :: st_rdev     ! Device type (4 bytes) - offset 24
    ! Timespec structures (16 bytes each = 8 bytes + 8 bytes)
    integer(c_long)  :: st_atimespec_sec    ! Access time seconds
    integer(c_long)  :: st_atimespec_nsec   ! Access time nanoseconds
    integer(c_long)  :: st_mtimespec_sec    ! Modification time seconds
    integer(c_long)  :: st_mtimespec_nsec   ! Modification time nanoseconds
    integer(c_long)  :: st_ctimespec_sec    ! Status change time seconds
    integer(c_long)  :: st_ctimespec_nsec   ! Status change time nanoseconds
    integer(c_long)  :: st_birthtimespec_sec ! Birth time seconds
    integer(c_long)  :: st_birthtimespec_nsec ! Birth time nanoseconds
    integer(c_long)  :: st_size      ! Total size in bytes (8 bytes)
    integer(c_long)  :: st_blocks    ! Number of 512-byte blocks (8 bytes)
    integer(c_int)   :: st_blksize   ! Optimal block size (4 bytes)
    integer(c_int)   :: st_flags     ! User defined flags (4 bytes)
    integer(c_int)   :: st_gen       ! File generation number (4 bytes)
    integer(c_int)   :: st_lspare    ! Reserved (4 bytes)
    integer(c_long)  :: st_qspare(2) ! Reserved (16 bytes)
#else
    ! Linux x86_64 stat structure layout
    integer(c_long)  :: st_dev       ! Device (8 bytes)
    integer(c_long)  :: st_ino       ! Inode (8 bytes)
    integer(c_long)  :: st_nlink     ! Number of hard links (8 bytes)
    integer(c_int)   :: st_mode      ! File type and mode (4 bytes)
    integer(c_int)   :: st_uid       ! User ID (4 bytes)
    integer(c_int)   :: st_gid       ! Group ID (4 bytes)
    integer(c_int)   :: pad0         ! Padding (4 bytes)
    integer(c_long)  :: st_rdev      ! Device type (8 bytes)
    integer(c_long)  :: st_size      ! Total size in bytes (8 bytes)
    integer(c_long)  :: st_blksize   ! Optimal block size (8 bytes)
    integer(c_long)  :: st_blocks    ! Number of 512-byte blocks (8 bytes)
    ! Time fields
    integer(c_long)  :: st_atime     ! Access time seconds
    integer(c_long)  :: st_atime_nsec ! Access time nanoseconds
    integer(c_long)  :: st_mtime     ! Modification time seconds
    integer(c_long)  :: st_mtime_nsec ! Modification time nanoseconds
    integer(c_long)  :: st_ctime     ! Status change time seconds
    integer(c_long)  :: st_ctime_nsec ! Status change time nanoseconds
    integer(c_long)  :: glibc_reserved(3) ! Reserved
#endif
  end type stat_t

  ! timeval structure for getrusage
  type, bind(c) :: timeval_t
    integer(c_long) :: tv_sec      ! Seconds
    integer(c_long) :: tv_usec     ! Microseconds
  end type timeval_t

  ! rusage structure for getrusage
  type, bind(c) :: rusage_t
    type(timeval_t) :: ru_utime    ! User CPU time used
    type(timeval_t) :: ru_stime    ! System CPU time used
    integer(c_long) :: ru_maxrss   ! Maximum resident set size
    integer(c_long) :: ru_ixrss    ! Integral shared memory size
    integer(c_long) :: ru_idrss    ! Integral unshared data size
    integer(c_long) :: ru_isrss    ! Integral unshared stack size
    integer(c_long) :: ru_minflt   ! Page reclaims (soft page faults)
    integer(c_long) :: ru_majflt   ! Page faults (hard page faults)
    integer(c_long) :: ru_nswap    ! Swaps
    integer(c_long) :: ru_inblock  ! Block input operations
    integer(c_long) :: ru_oublock  ! Block output operations
    integer(c_long) :: ru_msgsnd   ! IPC messages sent
    integer(c_long) :: ru_msgrcv   ! IPC messages received
    integer(c_long) :: ru_nsignals ! Signals received
    integer(c_long) :: ru_nvcsw    ! Voluntary context switches
    integer(c_long) :: ru_nivcsw   ! Involuntary context switches
  end type rusage_t

  ! getrusage who parameter values
  integer(c_int), parameter :: RUSAGE_SELF = 0
  integer(c_int), parameter :: RUSAGE_CHILDREN = -1

  ! rlimit structure for getrlimit/setrlimit
  type, bind(c) :: rlimit_t
    integer(c_long) :: rlim_cur    ! Current (soft) limit
    integer(c_long) :: rlim_max    ! Maximum (hard) limit
  end type rlimit_t

  ! Resource limit constants
  integer(c_int), parameter :: RLIMIT_CPU = 0        ! CPU time in seconds
  integer(c_int), parameter :: RLIMIT_FSIZE = 1      ! Maximum file size
  integer(c_int), parameter :: RLIMIT_DATA = 2       ! Maximum data segment size
  integer(c_int), parameter :: RLIMIT_STACK = 3      ! Maximum stack size
  integer(c_int), parameter :: RLIMIT_CORE = 4       ! Maximum core file size
  integer(c_int), parameter :: RLIMIT_RSS = 5        ! Maximum resident set size
  integer(c_int), parameter :: RLIMIT_NOFILE = 7     ! Maximum number of open files
  integer(c_int), parameter :: RLIMIT_AS = 9         ! Address space (virtual memory) limit
  integer(c_int), parameter :: RLIMIT_NPROC = 6      ! Maximum number of processes
  integer(c_int), parameter :: RLIMIT_MEMLOCK = 8    ! Maximum locked-in-memory address space
  integer(c_int), parameter :: RLIMIT_LOCKS = 10     ! Maximum file locks
  integer(c_int), parameter :: RLIMIT_SIGPENDING = 11 ! Maximum pending signals
  integer(c_int), parameter :: RLIMIT_MSGQUEUE = 12  ! Maximum bytes in POSIX message queues

  ! Infinite limit value
  integer(c_long), parameter :: RLIM_INFINITY = -1

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

    function c_unsetenv(name) bind(C, name="unsetenv")
      import :: c_ptr, c_int
      type(c_ptr), value :: name
      integer(c_int) :: c_unsetenv
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

    function c_dup(fd) bind(C, name="dup")
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: c_dup
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

    subroutine c_perror(s) bind(C, name="perror")
      import :: c_ptr
      type(c_ptr), value :: s
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

    function c_getuid() bind(C, name="getuid")
      import :: c_int
      integer(c_int) :: c_getuid
    end function

    function c_geteuid() bind(C, name="geteuid")
      import :: c_int
      integer(c_int) :: c_geteuid
    end function

    function c_stat(pathname, statbuf) bind(C, name="stat")
      import :: c_ptr, c_int, stat_t
      type(c_ptr), value :: pathname
      type(stat_t), intent(out) :: statbuf
      integer(c_int) :: c_stat
    end function

    function c_lstat(pathname, statbuf) bind(C, name="lstat")
      import :: c_ptr, c_int, stat_t
      type(c_ptr), value :: pathname
      type(stat_t), intent(out) :: statbuf
      integer(c_int) :: c_lstat
    end function

    function c_access(pathname, mode) bind(C, name="access")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int), value :: mode
      integer(c_int) :: c_access
    end function

    function c_umask(mask) bind(C, name="umask")
      import :: c_int
      integer(c_int), value :: mask
      integer(c_int) :: c_umask
    end function

    function c_getrusage(who, usage) bind(C, name="getrusage")
      import :: c_int, rusage_t
      integer(c_int), value :: who
      type(rusage_t), intent(out) :: usage
      integer(c_int) :: c_getrusage
    end function

    function c_getrlimit(resource, rlim) bind(C, name="getrlimit")
      import :: c_int, rlimit_t
      integer(c_int), value :: resource
      type(rlimit_t), intent(out) :: rlim
      integer(c_int) :: c_getrlimit
    end function

    function c_setrlimit(resource, rlim) bind(C, name="setrlimit")
      import :: c_int, rlimit_t
      integer(c_int), value :: resource
      type(rlimit_t), intent(in) :: rlim
      integer(c_int) :: c_setrlimit
    end function

    function c_mkfifo(pathname, mode) bind(C, name="mkfifo")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int), value :: mode
      integer(c_int) :: c_mkfifo
    end function

    function c_unlink(pathname) bind(C, name="unlink")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int) :: c_unlink
    end function

    function c_ioctl(fd, request, argp) bind(C, name="ioctl")
      import :: c_int, c_long, c_ptr
      integer(c_int), value :: fd
      integer(c_long), value :: request
      type(c_ptr), value :: argp
      integer(c_int) :: c_ioctl
    end function
  end interface

  ! Signal handler types (initialized in module initialization)
  type(c_funptr) :: SIG_DFL, SIG_IGN

  ! File flags for open() - macOS values
  integer(c_int), parameter :: O_RDONLY = 0
  integer(c_int), parameter :: O_WRONLY = 1
  integer(c_int), parameter :: O_CREAT = 512   ! 0x200 on macOS
  integer(c_int), parameter :: O_TRUNC = 1024  ! 0x400 on macOS
  integer(c_int), parameter :: O_APPEND = 8    ! 0x8 on macOS

  ! File descriptors
  integer(c_int), parameter :: STDIN_FD = 0
  integer(c_int), parameter :: STDOUT_FD = 1
  integer(c_int), parameter :: STDERR_FD = 2

  ! File mode bits (for stat st_mode field)
  integer(c_int), parameter :: S_IFMT   = int(o'170000', c_int)  ! File type mask
  integer(c_int), parameter :: S_IFREG  = int(o'100000', c_int)  ! Regular file
  integer(c_int), parameter :: S_IFDIR  = int(o'040000', c_int)  ! Directory
  integer(c_int), parameter :: S_IFLNK  = int(o'120000', c_int)  ! Symbolic link
  integer(c_int), parameter :: S_IFBLK  = int(o'060000', c_int)  ! Block device
  integer(c_int), parameter :: S_IFCHR  = int(o'020000', c_int)  ! Character device
  integer(c_int), parameter :: S_IFIFO  = int(o'010000', c_int)  ! FIFO (named pipe)
  integer(c_int), parameter :: S_IFSOCK = int(o'140000', c_int)  ! Socket

  integer(c_int), parameter :: S_ISUID  = int(o'004000', c_int)  ! Set UID bit
  integer(c_int), parameter :: S_ISGID  = int(o'002000', c_int)  ! Set GID bit
  integer(c_int), parameter :: S_ISVTX  = int(o'001000', c_int)  ! Sticky bit

  integer(c_int), parameter :: S_IRUSR  = int(o'000400', c_int)  ! Owner read
  integer(c_int), parameter :: S_IWUSR  = int(o'000200', c_int)  ! Owner write
  integer(c_int), parameter :: S_IXUSR  = int(o'000100', c_int)  ! Owner execute
  integer(c_int), parameter :: S_IRGRP  = int(o'000040', c_int)  ! Group read
  integer(c_int), parameter :: S_IWGRP  = int(o'000020', c_int)  ! Group write
  integer(c_int), parameter :: S_IXGRP  = int(o'000010', c_int)  ! Group execute
  integer(c_int), parameter :: S_IROTH  = int(o'000004', c_int)  ! Others read
  integer(c_int), parameter :: S_IWOTH  = int(o'000002', c_int)  ! Others write
  integer(c_int), parameter :: S_IXOTH  = int(o'000001', c_int)  ! Others execute

  ! Access mode flags
  integer(c_int), parameter :: F_OK = 0  ! File exists
  integer(c_int), parameter :: R_OK = 4  ! Read permission
  integer(c_int), parameter :: W_OK = 2  ! Write permission
  integer(c_int), parameter :: X_OK = 1  ! Execute permission

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

  subroutine unset_environment_var(var_name)
    character(len=*), intent(in) :: var_name
    integer :: ret
    character(len=256), target :: c_var_name

    c_var_name = trim(var_name)//c_null_char
    ret = c_unsetenv(c_loc(c_var_name))
    ! Ignore return value - unsetenv doesn't typically fail
  end subroutine

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
    character(kind=c_char), target :: buffer(4096)  ! Larger buffer per read
    character(len=65536) :: temp_output  ! 64KB buffer
    type(c_ptr) :: ret_ptr
    integer :: i, pos, bytes_read
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

    ! Read output with larger buffer
    do
      ! Initialize buffer for this read
      buffer = c_null_char

      ret_ptr = c_fgets(c_loc(buffer), int(4096, c_int), pipe_ptr)
      if (.not. c_associated(ret_ptr)) exit

      ! Convert to Fortran string
      bytes_read = 0
      do i = 1, 4096
        if (buffer(i) == c_null_char) exit
        bytes_read = bytes_read + 1
        if (pos > len(temp_output)) exit  ! Buffer full

        if (buffer(i) /= char(10)) then  ! Skip newlines
          temp_output(pos:pos) = buffer(i)
          pos = pos + 1
        else if (pos > 1 .and. temp_output(pos-1:pos-1) /= ' ') then
          temp_output(pos:pos) = ' '
          pos = pos + 1
        end if
      end do

      ! Debug: Check if we should continue reading
      ! Exit if we read less than expected OR hit buffer limit
      if (pos > len(temp_output)) exit
      if (bytes_read == 0) exit
    end do

    ! Close pipe
    i = c_pclose(pipe_ptr)

    ! Return output (deallocate first if already allocated, which shouldn't happen but prevents crash)
    if (allocated(output)) deallocate(output)
    allocate(character(len=pos-1) :: output)
    output = temp_output(:pos-1)
  end function

  ! Terminal control functions
  function enable_raw_mode(original_termios) result(success)
    type(termios_t), intent(out) :: original_termios
    logical :: success
    type(termios_t) :: raw_termios
    integer :: ret
    logical :: mode_ok  ! Workaround for potential LLVM Flang compiler bug
    integer, save :: call_count = 0

    success = .false.
    mode_ok = .false.

    call_count = call_count + 1

    ! Verify stdin is actually a TTY
    if (c_isatty(STDIN_FD) == 0) then
      return
    end if

    ! Get current terminal settings
    ret = c_tcgetattr(STDIN_FD, original_termios)
    if (ret /= 0) then
      write(*, '(a,i15)') '[ERROR: tcgetattr failed: ', ret, ']'
      return
    end if

    ! Copy to modify for raw mode
    raw_termios = original_termios

    ! DEBUG: Commented out - too noisy for normal use

    ! Disable input processing that might consume control chars
#ifdef __APPLE__
    ! macOS: Disable IXON (Ctrl-S/Q flow control), IXOFF, IXANY, BRKINT
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000600', c_long)))  ! IXON | IXOFF
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000800', c_long)))  ! IXANY
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000002', c_long)))  ! BRKINT
#else
    ! Linux: Disable flow control
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000400', c_int)))  ! IXON
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00001000', c_int)))  ! IXOFF
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000800', c_int)))  ! IXANY
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000002', c_int)))  ! BRKINT
#endif

    ! Disable canonical mode, echo, and signals
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(ior(ior(ICANON, ECHO), ior(ECHOE, ECHOK))))
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(ior(ior(ECHONL, IEXTEN), ISIG)))

    ! Also disable ECHOCTL which echoes control chars as ^C
#ifdef __APPLE__
    ! macOS ECHOCTL flag (0x40)
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(int(z'00000040', c_long)))
#else
    ! Linux ECHOCTL flag (typically 0x200)
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(int(z'00000200', c_int)))
#endif

    ! Set minimum characters and timeout for read
    raw_termios%c_cc(VMIN + 1) = char(1)  ! Read at least 1 character
    raw_termios%c_cc(VTIME + 1) = char(0) ! No timeout

#ifdef __APPLE__
    ! Disable special character mappings that might intercept control chars
    ! With ISIG and ICANON disabled, most of these shouldn't matter, but
    ! explicitly clearing them ensures no control chars are intercepted
    raw_termios%c_cc(VINTR + 1) = char(0)   ! Disable Ctrl-C (we handle it ourselves)
    raw_termios%c_cc(VQUIT + 1) = char(0)   ! Disable Ctrl-\ quit
    raw_termios%c_cc(VSUSP + 1) = char(0)   ! Disable Ctrl-Z suspend
    raw_termios%c_cc(VDSUSP + 1) = char(0)  ! Disable delayed suspend
    raw_termios%c_cc(VSTART + 1) = char(0)  ! Disable Ctrl-Q start (XON)
    raw_termios%c_cc(VSTOP + 1) = char(0)   ! Disable Ctrl-S stop (XOFF)
    raw_termios%c_cc(VLNEXT + 1) = char(0)  ! Disable literal next (Ctrl-V)
    raw_termios%c_cc(VDISCARD + 1) = char(0) ! Disable output discard
    raw_termios%c_cc(VWERASE + 1) = char(0) ! Disable word erase
    raw_termios%c_cc(VREPRINT + 1) = char(0) ! Disable reprint line
    ! Don't disable VEOF, VERASE, VKILL - we may want to check them
#endif

    ! Apply raw mode settings - use TCSAFLUSH to discard pending input
    ! TCSAFLUSH is critical on macOS to ensure settings actually take effect
    ret = c_tcsetattr(STDIN_FD, TCSAFLUSH, raw_termios)
    ! DEBUG: Commented out - too noisy
    mode_ok = (ret == 0)
    ! DEBUG: Commented out - too noisy
    ! if (mode_ok) then
    ! else
    ! end if

    ! Verify flags were actually set
    ret = c_tcgetattr(STDIN_FD, raw_termios)
    if (ret == 0) then
      if (iand(raw_termios%c_lflag, ISIG) /= 0) then
        write(*, '(a)') '[BUG: ISIG still SET after tcsetattr!]'
      ! else
      end if
      if (iand(raw_termios%c_lflag, ICANON) /= 0) then
        write(*, '(a)') '[BUG: ICANON still SET!]'
      ! else
      end if
      ! DEBUG: Commented out - too noisy

#ifdef __APPLE__
      ! DEBUG: Commented out - too noisy
#endif
    end if

    ! Assign to result variable at the very end
    success = mode_ok
    ! DEBUG: Commented out - too noisy
    ! if (success) then
    ! else
    ! end if
  end function
  
  function restore_terminal(original_termios) result(success)
    type(termios_t), intent(in) :: original_termios
    logical :: success
    integer :: ret

    ret = c_tcsetattr(STDIN_FD, TCSANOW, original_termios)
    success = (ret == 0)
  end function
  
  function read_single_char(ch) result(success)
    use iso_fortran_env, only: error_unit
    character, intent(out) :: ch
    logical :: success
    character(c_char), target :: c_ch
    integer(c_size_t) :: bytes_read


    bytes_read = c_read(STDIN_FD, c_loc(c_ch), 1_c_size_t)

    success = (bytes_read == 1)
    if (success) then
      ch = c_ch
      ! DEBUG: Commented out - too noisy for normal use
      ! write(*, '(a,i15)') '[read_single_char: got char ', ichar(ch), ']'
    else
      ch = char(0)
      write(*, '(a,i15)') '[read_single_char: FAILED, bytes_read=', int(bytes_read), ']'
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

  function get_uid() result(uid)
    integer :: uid
    uid = int(c_getuid())
  end function

  function get_euid() result(euid)
    integer :: euid
    euid = int(c_geteuid())
  end function

  ! File test functions for test builtin support
  function file_exists(path) result(exists)
    character(len=*), intent(in) :: path
    logical :: exists
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    exists = (ret == 0)
  end function

  function file_is_regular(path) result(is_reg)
    character(len=*), intent(in) :: path
    logical :: is_reg
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_reg = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFREG)
  end function

  function file_is_directory(path) result(is_dir)
    character(len=*), intent(in) :: path
    logical :: is_dir
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_dir = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFDIR)
  end function

  function file_is_symlink(path) result(is_link)
    character(len=*), intent(in) :: path
    logical :: is_link
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_lstat(c_loc(c_path), statbuf)  ! lstat for symlinks
    is_link = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFLNK)
  end function

  function file_is_block_device(path) result(is_blk)
    character(len=*), intent(in) :: path
    logical :: is_blk
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_blk = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFBLK)
  end function

  function file_is_char_device(path) result(is_chr)
    character(len=*), intent(in) :: path
    logical :: is_chr
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_chr = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFCHR)
  end function

  function file_is_fifo(path) result(is_fifo)
    character(len=*), intent(in) :: path
    logical :: is_fifo
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_fifo = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFIFO)
  end function

  function file_is_socket(path) result(is_sock)
    character(len=*), intent(in) :: path
    logical :: is_sock
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_sock = (ret == 0 .and. iand(statbuf%st_mode, S_IFMT) == S_IFSOCK)
  end function

  function file_is_readable(path) result(is_readable)
    character(len=*), intent(in) :: path
    logical :: is_readable
    character(len=256), target :: c_path
    integer :: ret

    c_path = trim(path)//c_null_char
    ret = c_access(c_loc(c_path), R_OK)
    is_readable = (ret == 0)
  end function

  function file_is_writable(path) result(is_writable)
    character(len=*), intent(in) :: path
    logical :: is_writable
    character(len=256), target :: c_path
    integer :: ret

    c_path = trim(path)//c_null_char
    ret = c_access(c_loc(c_path), W_OK)
    is_writable = (ret == 0)
  end function

  function file_is_executable(path) result(is_exec)
    character(len=*), intent(in) :: path
    logical :: is_exec
    character(len=256), target :: c_path
    integer :: ret

    c_path = trim(path)//c_null_char
    ret = c_access(c_loc(c_path), X_OK)
    is_exec = (ret == 0)
  end function

  function file_has_suid(path) result(has_suid)
    character(len=*), intent(in) :: path
    logical :: has_suid
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_suid = (ret == 0 .and. iand(statbuf%st_mode, S_ISUID) /= 0)
  end function

  function file_has_sgid(path) result(has_sgid)
    character(len=*), intent(in) :: path
    logical :: has_sgid
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_sgid = (ret == 0 .and. iand(statbuf%st_mode, S_ISGID) /= 0)
  end function

  function file_has_sticky(path) result(has_sticky)
    character(len=*), intent(in) :: path
    logical :: has_sticky
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_sticky = (ret == 0 .and. iand(statbuf%st_mode, S_ISVTX) /= 0)
  end function

  function file_has_size(path) result(has_size)
    character(len=*), intent(in) :: path
    logical :: has_size
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_size = (ret == 0 .and. statbuf%st_size > 0)
  end function

  function file_owned_by_euid(path) result(is_owned)
    character(len=*), intent(in) :: path
    logical :: is_owned
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_owned = (ret == 0 .and. statbuf%st_uid == c_geteuid())
  end function

  function file_owned_by_egid(path) result(is_owned)
    character(len=*), intent(in) :: path
    logical :: is_owned
    character(len=256), target :: c_path
    integer :: ret
    type(stat_t) :: statbuf
    integer(c_int) :: egid

    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)

    ! Note: getegid() not declared yet, so we'll skip this check for now
    ! This should be added when getegid() is available
    is_owned = .false.
  end function

  function file_is_newer(file1, file2) result(is_newer)
    character(len=*), intent(in) :: file1, file2
    logical :: is_newer
    character(len=256), target :: c_path1, c_path2
    integer :: ret1, ret2
    type(stat_t) :: stat1, stat2

    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    ret1 = c_stat(c_loc(c_path1), stat1)
    ret2 = c_stat(c_loc(c_path2), stat2)
#ifdef __APPLE__
    is_newer = (ret1 == 0 .and. ret2 == 0 .and. stat1%st_mtimespec_sec > stat2%st_mtimespec_sec)
#else
    is_newer = (ret1 == 0 .and. ret2 == 0 .and. stat1%st_mtime > stat2%st_mtime)
#endif
  end function

  function file_is_older(file1, file2) result(is_older)
    character(len=*), intent(in) :: file1, file2
    logical :: is_older
    character(len=256), target :: c_path1, c_path2
    integer :: ret1, ret2
    type(stat_t) :: stat1, stat2

    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    ret1 = c_stat(c_loc(c_path1), stat1)
    ret2 = c_stat(c_loc(c_path2), stat2)
#ifdef __APPLE__
    is_older = (ret1 == 0 .and. ret2 == 0 .and. stat1%st_mtimespec_sec < stat2%st_mtimespec_sec)
#else
    is_older = (ret1 == 0 .and. ret2 == 0 .and. stat1%st_mtime < stat2%st_mtime)
#endif
  end function

  function file_same_as(file1, file2) result(is_same)
    character(len=*), intent(in) :: file1, file2
    logical :: is_same
    character(len=256), target :: c_path1, c_path2
    integer :: ret1, ret2
    type(stat_t) :: stat1, stat2

    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    ret1 = c_stat(c_loc(c_path1), stat1)
    ret2 = c_stat(c_loc(c_path2), stat2)
    is_same = (ret1 == 0 .and. ret2 == 0 .and. &
               stat1%st_dev == stat2%st_dev .and. &
               stat1%st_ino == stat2%st_ino)
  end function

  ! Create a named pipe (FIFO)
  function create_fifo(path, mode) result(success)
    character(len=*), intent(in) :: path
    integer, intent(in), optional :: mode
    logical :: success
    character(len=256), target :: c_path
    integer(c_int) :: ret
    integer(c_int) :: fifo_mode

    ! Default mode is 0600 (read/write for owner only)
    if (present(mode)) then
      fifo_mode = int(mode, c_int)
    else
      fifo_mode = ior(S_IRUSR, S_IWUSR)
    end if

    c_path = trim(path)//c_null_char
    ret = c_mkfifo(c_loc(c_path), fifo_mode)
    success = (ret == 0)
  end function

  ! Remove a file or FIFO
  function remove_file(path) result(success)
    character(len=*), intent(in) :: path
    logical :: success
    character(len=256), target :: c_path
    integer :: ret

    c_path = trim(path)//c_null_char
    ret = c_unlink(c_loc(c_path))
    success = (ret == 0)
  end function

  ! Initialize signal handler constants
  ! Must be called before using SIG_DFL or SIG_IGN
  subroutine init_signal_constants()
    ! SIG_DFL is (void(*)())0 which is c_null_funptr
    SIG_DFL = c_null_funptr
    ! SIG_IGN is (void(*)())1, use transfer to convert integer to c_funptr
    SIG_IGN = transfer(1_c_intptr_t, SIG_IGN)
  end subroutine

  ! Get terminal size (rows and columns)
  function get_terminal_size(rows, cols) result(success)
    integer, intent(out) :: rows, cols
    logical :: success
    type(winsize_t), target :: ws
    integer(c_int) :: ret

    ! Initialize structure to zero
    ws%ws_row = 0
    ws%ws_col = 0
    ws%ws_xpixel = 0
    ws%ws_ypixel = 0

    ! Try to get window size using ioctl
    ! Try stdout first, then stderr if stdout gives 0 dimensions
    ret = c_ioctl(STDOUT_FD, TIOCGWINSZ, c_loc(ws))

    ! If stdout doesn't give valid dimensions, try stderr
    if (ret /= 0 .or. ws%ws_row == 0 .or. ws%ws_col == 0) then
      ws%ws_row = 0
      ws%ws_col = 0
      ret = c_ioctl(STDERR_FD, TIOCGWINSZ, c_loc(ws))
    end if

    ! If stderr also doesn't work, try stdin
    if (ret /= 0 .or. ws%ws_row == 0 .or. ws%ws_col == 0) then
      ws%ws_row = 0
      ws%ws_col = 0
      ret = c_ioctl(STDIN_FD, TIOCGWINSZ, c_loc(ws))
    end if

    if (ret == 0 .and. ws%ws_row > 0 .and. ws%ws_col > 0) then
      rows = int(ws%ws_row)
      cols = int(ws%ws_col)
      success = .true.
    else
      ! Fallback to common defaults if ioctl fails
      rows = 24
      cols = 80
      success = .false.
    end if
  end function

end module system_interface