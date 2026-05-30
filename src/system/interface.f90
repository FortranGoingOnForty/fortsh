! ==============================================================================
! Module: system_interface
! Purpose: C function interfaces and system call wrappers
! ==============================================================================
module system_interface
  use iso_c_binding
  use shell_types
  implicit none

  ! Signal numbers (platform-specific)
#if defined(__APPLE__) || defined(__FreeBSD__)
  ! macOS/FreeBSD/BSD signal numbers
  integer(c_int), parameter :: SIGINT = 2
  integer(c_int), parameter :: SIGPIPE = 13
  integer(c_int), parameter :: SIGTSTP = 18
  integer(c_int), parameter :: SIGCHLD = 20
  integer(c_int), parameter :: SIGCONT = 19
  integer(c_int), parameter :: SIGTTIN = 21
  integer(c_int), parameter :: SIGTTOU = 22
#else
  ! Linux signal numbers
  integer(c_int), parameter :: SIGINT = 2
  integer(c_int), parameter :: SIGPIPE = 13
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
#if defined(__APPLE__) || defined(__FreeBSD__)
  ! macOS/FreeBSD: NCCS=20
  integer(c_int), parameter :: NCCS = 20
  ! ioctl request for terminal size (BSD)
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

  ! poll(2) descriptor — { int fd; short events; short revents; } is identical
  ! on Linux x86_64/aarch64, macOS, and FreeBSD, and POLLIN == 0x0001 on all of
  ! them, so no per-platform layout is required (unlike struct termios/stat).
  type, bind(c) :: pollfd_t
    integer(c_int)   :: fd
    integer(c_short) :: events
    integer(c_short) :: revents
  end type pollfd_t
  integer(c_short), parameter :: POLLIN = int(z'0001', c_short)

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
#elif defined(__FreeBSD__)
    ! FreeBSD: tcflag_t is unsigned int (4 bytes), NCCS=20, no c_line field
    integer(c_int) :: c_iflag       ! input flags (4 bytes)
    integer(c_int) :: c_oflag       ! output flags (4 bytes)
    integer(c_int) :: c_cflag       ! control flags (4 bytes)
    integer(c_int) :: c_lflag       ! local flags (4 bytes)
    character(c_char) :: c_cc(20)   ! control characters (20 bytes)
    integer(c_int) :: c_ispeed      ! input speed (4 bytes)
    integer(c_int) :: c_ospeed      ! output speed (4 bytes)
    ! Total: 44 bytes (matches actual FreeBSD struct termios)
#else
    ! Linux: tcflag_t is unsigned int (4 bytes)
    integer(c_int) :: c_iflag       ! input flags (4 bytes)
    integer(c_int) :: c_oflag       ! output flags (4 bytes)
    integer(c_int) :: c_cflag       ! control flags (4 bytes)
    integer(c_int) :: c_lflag       ! local flags (4 bytes)
    character(c_char) :: c_line     ! line discipline (1 byte)
    character(c_char) :: c_cc(NCCS) ! control characters (32 bytes)
    character(c_char) :: padding(3) ! padding for alignment (3 bytes)
    integer(c_int) :: c_ispeed      ! input speed (4 bytes)
    integer(c_int) :: c_ospeed      ! output speed (4 bytes)
    ! Total: 60 bytes (matches actual Linux struct termios)
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
#elif defined(__FreeBSD__)
  ! FreeBSD values from sys/_termios.h - BSD values, c_int to match tcflag_t
  integer(c_int), parameter :: ICANON = int(z'00000100', c_int)  ! canonical input
  integer(c_int), parameter :: ECHO   = int(z'00000008', c_int)  ! enable echo
  integer(c_int), parameter :: ECHOE  = int(z'00000002', c_int)  ! echo erase character
  integer(c_int), parameter :: ECHOK  = int(z'00000004', c_int)  ! echo kill character
  integer(c_int), parameter :: ECHONL = int(z'00000010', c_int)  ! echo NL even if ECHO is off
  integer(c_int), parameter :: IEXTEN = int(z'00000400', c_int)  ! extended input processing
  integer(c_int), parameter :: ISIG   = int(z'00000080', c_int)  ! enable signals
#else
  ! Linux values from bits/termios.h - use c_int to match tcflag_t
  integer(c_int), parameter :: ICANON = int(z'00000002', c_int)  ! canonical input
  integer(c_int), parameter :: ECHO   = int(z'00000008', c_int)  ! enable echo
  integer(c_int), parameter :: ECHOE  = int(z'00000010', c_int)  ! echo erase character
  integer(c_int), parameter :: ECHOK  = int(z'00000020', c_int)  ! echo kill character
  integer(c_int), parameter :: ECHONL = int(z'00000040', c_int)  ! echo NL even if ECHO is off
  integer(c_int), parameter :: IEXTEN = int(z'00008000', c_int)  ! extended input processing
  integer(c_int), parameter :: ISIG   = int(z'00000001', c_int)  ! enable signals
#endif

  ! Control character indices (platform-specific)
#if defined(__APPLE__) || defined(__FreeBSD__)
  ! macOS/FreeBSD control character indices
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
  ! Linux control character indices
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
#elif defined(__FreeBSD__)
    ! FreeBSD stat structure layout (FreeBSD 12+)
    ! Use C stat helpers (USE_C_STAT) for actual operations; this struct
    ! exists only to satisfy compilation of the type definition.
    integer(c_long)  :: st_dev       ! Device (8 bytes) - offset 0
    integer(c_long)  :: st_ino       ! Inode (8 bytes) - offset 8
    integer(c_long)  :: st_nlink     ! Number of hard links (8 bytes) - offset 16
    integer(c_short) :: st_mode      ! File type and mode (2 bytes) - offset 24
    integer(c_short) :: st_bsdflags  ! BSD flags (2 bytes) - offset 26
    integer(c_int)   :: st_uid       ! User ID (4 bytes) - offset 28
    integer(c_int)   :: st_gid       ! Group ID (4 bytes) - offset 32
    integer(c_int)   :: st_padding1  ! Padding (4 bytes) - offset 36
    integer(c_long)  :: st_rdev      ! Device type (8 bytes) - offset 40
    ! Timespec structures (16 bytes each)
    integer(c_long)  :: st_atime     ! Access time seconds - offset 48
    integer(c_long)  :: st_atime_nsec ! Access time nanoseconds - offset 56
    integer(c_long)  :: st_mtime     ! Modification time seconds - offset 64
    integer(c_long)  :: st_mtime_nsec ! Modification time nanoseconds - offset 72
    integer(c_long)  :: st_ctime     ! Status change time seconds - offset 80
    integer(c_long)  :: st_ctime_nsec ! Status change time nanoseconds - offset 88
    integer(c_long)  :: st_birthtimespec_sec  ! Birth time seconds - offset 96
    integer(c_long)  :: st_birthtimespec_nsec ! Birth time nanoseconds - offset 104
    integer(c_long)  :: st_size      ! Total size in bytes (8 bytes) - offset 112
    integer(c_long)  :: st_blocks    ! Number of 512-byte blocks (8 bytes) - offset 120
    integer(c_int)   :: st_blksize   ! Optimal block size (4 bytes) - offset 128
    integer(c_int)   :: st_flags     ! User defined flags (4 bytes) - offset 132
    integer(c_long)  :: st_gen       ! File generation number (8 bytes) - offset 136
    integer(c_long)  :: st_spare(10) ! Reserved - offset 144
    ! Total: 224 bytes
#elif defined(__aarch64__)
    ! Linux aarch64 stat structure layout (glibc generic 64-bit)
    ! Field order and sizes differ from x86_64: mode/nlink swapped, nlink is 4B not 8B
    integer(c_long)  :: st_dev       ! Device (8 bytes) - offset 0
    integer(c_long)  :: st_ino       ! Inode (8 bytes) - offset 8
    integer(c_int)   :: st_mode      ! File type and mode (4 bytes) - offset 16
    integer(c_int)   :: st_nlink     ! Number of hard links (4 bytes) - offset 20
    integer(c_int)   :: st_uid       ! User ID (4 bytes) - offset 24
    integer(c_int)   :: st_gid       ! Group ID (4 bytes) - offset 28
    integer(c_long)  :: st_rdev      ! Device type (8 bytes) - offset 32
    integer(c_long)  :: pad1         ! __pad1 (8 bytes) - offset 40
    integer(c_long)  :: st_size      ! Total size in bytes (8 bytes) - offset 48
    integer(c_int)   :: st_blksize   ! Optimal block size (4 bytes) - offset 56
    integer(c_int)   :: pad2         ! __pad2 (4 bytes) - offset 60
    integer(c_long)  :: st_blocks    ! Number of 512-byte blocks (8 bytes) - offset 64
    ! Time fields (struct timespec = 16 bytes each)
    integer(c_long)  :: st_atime     ! Access time seconds - offset 72
    integer(c_long)  :: st_atime_nsec ! Access time nanoseconds - offset 80
    integer(c_long)  :: st_mtime     ! Modification time seconds - offset 88
    integer(c_long)  :: st_mtime_nsec ! Modification time nanoseconds - offset 96
    integer(c_long)  :: st_ctime     ! Status change time seconds - offset 104
    integer(c_long)  :: st_ctime_nsec ! Status change time nanoseconds - offset 112
    integer(c_int)   :: glibc_reserved(2) ! Reserved (8 bytes) - offset 120
    ! Total: 128 bytes
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
#if defined(__APPLE__) || defined(__FreeBSD__)
  ! BSD uses different constant values than Linux for these
  integer(c_int), parameter :: RLIMIT_MEMLOCK = 6
  integer(c_int), parameter :: RLIMIT_NPROC = 7
  integer(c_int), parameter :: RLIMIT_NOFILE = 8
  integer(c_int), parameter :: RLIMIT_AS = 5         ! Same as RSS on BSD
#else
  integer(c_int), parameter :: RLIMIT_NPROC = 6
  integer(c_int), parameter :: RLIMIT_NOFILE = 7
  integer(c_int), parameter :: RLIMIT_MEMLOCK = 8
  integer(c_int), parameter :: RLIMIT_AS = 9
  integer(c_int), parameter :: RLIMIT_LOCKS = 10
  integer(c_int), parameter :: RLIMIT_SIGPENDING = 11
#endif
  integer(c_int), parameter :: RLIMIT_MSGQUEUE = 12  ! Maximum bytes in POSIX message queues

  ! Infinite limit value
#if defined(__APPLE__) || defined(__FreeBSD__)
  integer(c_long), parameter :: RLIM_INFINITY = 9223372036854775807_c_long  ! 0x7FFFFFFFFFFFFFFF on BSD
#else
  integer(c_long), parameter :: RLIM_INFINITY = -1  ! (unsigned long)-1 on Linux
#endif

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

    function c_strlen(s) bind(C, name="strlen")
      import :: c_ptr, c_size_t
      type(c_ptr), value :: s
      integer(c_size_t) :: c_strlen
    end function

    function c_user_home(name) bind(C, name="fortsh_user_home")
      import :: c_ptr, c_char
      character(kind=c_char), intent(in) :: name(*)
      type(c_ptr) :: c_user_home
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
      import :: c_int, c_ptr, c_size_t, c_intptr_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_intptr_t) :: c_write  ! ssize_t is signed, returns -1 on error
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

    ! Write a null-terminated string to a stream (shift phase Sprint 5:
    ! used to pipe text into clipboard tools like pbcopy via popen("w")).
    function c_fputs(s, stream) bind(C, name="fputs")
      import :: c_ptr, c_int
      type(c_ptr), value :: s
      type(c_ptr), value :: stream
      integer(c_int) :: c_fputs
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

    ! poll(2): nfds_t is unsigned long (Linux) / unsigned int (BSD/macOS);
    ! passing a small positive c_int for nfds is ABI-safe by integer promotion.
    function c_poll(fds, nfds, timeout) bind(C, name="poll")
      import :: c_int, c_ptr
      type(c_ptr), value :: fds
      integer(c_int), value :: nfds
      integer(c_int), value :: timeout
      integer(c_int) :: c_poll
    end function

    ! Native directory enumeration (src/c_interop/fortsh_dir.c) — replaces
    ! shelling out to `ls`. The C side owns the platform-specific struct dirent.
    function c_opendir(path) bind(C, name="fortsh_opendir")
      import :: c_ptr, c_char
      character(kind=c_char), intent(in) :: path(*)
      type(c_ptr) :: c_opendir
    end function

    function c_readdir(dirp, name_buf, buf_len, is_dir) bind(C, name="fortsh_readdir")
      import :: c_ptr, c_char, c_int
      type(c_ptr), value :: dirp
      character(kind=c_char), intent(inout) :: name_buf(*)
      integer(c_int), value :: buf_len
      integer(c_int), intent(out) :: is_dir
      integer(c_int) :: c_readdir
    end function

    subroutine c_closedir(dirp) bind(C, name="fortsh_closedir")
      import :: c_ptr
      type(c_ptr), value :: dirp
    end subroutine

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

    ! Portable stat helpers — bypass Fortran struct stat layout across architectures
    function fortsh_stat_mode(pathname) bind(C, name="fortsh_stat_mode")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int) :: fortsh_stat_mode
    end function

    function fortsh_lstat_mode(pathname) bind(C, name="fortsh_lstat_mode")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int) :: fortsh_lstat_mode
    end function

    function fortsh_stat_size(pathname) bind(C, name="fortsh_stat_size")
      import :: c_ptr, c_long_long
      type(c_ptr), value :: pathname
      integer(c_long_long) :: fortsh_stat_size
    end function

    function fortsh_stat_uid(pathname) bind(C, name="fortsh_stat_uid")
      import :: c_ptr, c_int
      type(c_ptr), value :: pathname
      integer(c_int) :: fortsh_stat_uid
    end function

    function fortsh_stat_mtime(pathname) bind(C, name="fortsh_stat_mtime")
      import :: c_ptr, c_long_long
      type(c_ptr), value :: pathname
      integer(c_long_long) :: fortsh_stat_mtime
    end function

    function fortsh_stat_dev(pathname) bind(C, name="fortsh_stat_dev")
      import :: c_ptr, c_long_long
      type(c_ptr), value :: pathname
      integer(c_long_long) :: fortsh_stat_dev
    end function

    function fortsh_stat_ino(pathname) bind(C, name="fortsh_stat_ino")
      import :: c_ptr, c_long_long
      type(c_ptr), value :: pathname
      integer(c_long_long) :: fortsh_stat_ino
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

    ! C wrapper for getting terminal size
    function get_term_size_c(rows, cols) bind(C, name="get_term_size_c")
      import :: c_int
      integer(c_int) :: rows, cols
      integer(c_int) :: get_term_size_c
    end function

    ! Get environ pointer (array of environment strings)
    function c_get_environ_ptr(idx) bind(C, name="get_environ_ptr")
      import :: c_ptr, c_int
      integer(c_int), value :: idx
      type(c_ptr) :: c_get_environ_ptr
    end function
  end interface

  ! Signal handler types (initialized in module initialization)
  type(c_funptr) :: SIG_DFL, SIG_IGN

  ! File flags for open() - platform-specific values
  integer(c_int), parameter :: O_RDONLY = 0
  integer(c_int), parameter :: O_WRONLY = 1
  ! macOS/Darwin values (TODO: add Linux support)
  integer(c_int), parameter :: O_CREAT = 512   ! 0x200 on macOS, 0x40 on Linux
  integer(c_int), parameter :: O_TRUNC = 1024  ! 0x400 on macOS, 0x200 on Linux
  integer(c_int), parameter :: O_APPEND = 8    ! 0x8 on macOS, 0x400 on Linux

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
    integer :: i, vlen
    character(len=256), target :: c_var_name

    c_var_name = trim(var_name)//c_null_char
    c_value_ptr = c_getenv(c_loc(c_var_name))

    if (c_associated(c_value_ptr)) then
      ! Map the exact C-string length (strlen) — a fixed MAX_ENV_LEN window
      ! both capped long values and over-claimed the pointer extent.
      vlen = int(c_strlen(c_value_ptr))
      allocate(character(len=vlen) :: value)
      if (vlen > 0) then
        call c_f_pointer(c_value_ptr, c_value, [vlen])
        do i = 1, vlen
          value(i:i) = c_value(i)
        end do
      end if
    else
      allocate(character(len=0) :: value)
    end if
  end function

  ! Home directory for a named user via getpwnam (for ~user expansion).
  ! Returns '' if the user does not exist (caller leaves ~user literal).
  function get_user_home(username) result(home)
    character(len=*), intent(in) :: username
    character(len=:), allocatable :: home
    type(c_ptr) :: p
    character(kind=c_char), pointer :: cs(:)
    character(kind=c_char), dimension(:), allocatable, target :: cname
    integer :: i, n

    home = ''
    n = len_trim(username)
    if (n == 0) return
    allocate(cname(n + 1))
    do i = 1, n
      cname(i) = username(i:i)
    end do
    cname(n + 1) = c_null_char

    p = c_user_home(cname)
    if (c_associated(p)) then
      n = int(c_strlen(p))
      if (allocated(home)) deallocate(home)
      allocate(character(len=n) :: home)
      if (n > 0) then
        call c_f_pointer(p, cs, [n])
        do i = 1, n
          home(i:i) = cs(i)
        end do
      end if
    end if
  end function

  function set_environment_var(var_name, var_value) result(success)
    character(len=*), intent(in) :: var_name, var_value
    logical :: success
    integer :: ret, i, nlen, vlen
    ! Allocatable c_char targets sized to the actual strings — fixed buffers
    ! truncated long exported values (e.g. a big PATH) at 4096 bytes.
    character(kind=c_char), dimension(:), allocatable, target :: c_var_name, c_var_value

    nlen = len_trim(var_name)
    vlen = len_trim(var_value)
    allocate(c_var_name(nlen + 1), c_var_value(vlen + 1))
    do i = 1, nlen
      c_var_name(i) = var_name(i:i)
    end do
    c_var_name(nlen + 1) = c_null_char
    do i = 1, vlen
      c_var_value(i) = var_value(i:i)
    end do
    c_var_value(vlen + 1) = c_null_char

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

  ! Get environment entry by index (for iterating through all env vars)
  ! Returns empty string when index is beyond end of environ array
  function get_environ_entry(idx) result(entry)
    integer, intent(in) :: idx
    character(len=:), allocatable :: entry
    type(c_ptr) :: c_entry_ptr
    character(kind=c_char), pointer :: c_entry(:)
    integer :: i

    c_entry_ptr = c_get_environ_ptr(int(idx, c_int))

    if (c_associated(c_entry_ptr)) then
      call c_f_pointer(c_entry_ptr, c_entry, [MAX_ENV_LEN])

      do i = 1, MAX_ENV_LEN
        if (c_entry(i) == c_null_char) exit
      end do

      allocate(character(len=i-1) :: entry)
      do i = 1, len(entry)
        entry(i:i) = c_entry(i)
      end do
    else
      allocate(character(len=0) :: entry)
    end if
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

  function WIFSIGNALED(status) result(signaled)
    integer(c_int), intent(in) :: status
    logical :: signaled
    integer :: low7
    low7 = iand(status, 127)
    ! Process was killed by a signal if low 7 bits are non-zero and not 0x7f (stopped)
    signaled = (low7 /= 0) .and. (low7 /= 127)
  end function

  function WTERMSIG(status) result(sig)
    integer(c_int), intent(in) :: status
    integer :: sig
    sig = iand(status, 127)
  end function

  function WSTOPSIG(status) result(sig)
    integer(c_int), intent(in) :: status
    integer :: sig
    sig = iand(ishft(status, -8), 255)
  end function

  function execute_and_capture(command) result(output)
    character(len=*), intent(in) :: command
    character(len=:), allocatable :: output

    type(c_ptr) :: pipe_ptr
    character(kind=c_char), target :: buffer(4096)  ! one fgets chunk
    character(len=4096) :: chunk                     ! collapsed chunk (<= one read)
    type(c_ptr) :: ret_ptr
    integer :: i, clen, cmdlen
    ! Allocatable command/output — fixed buffers truncated the command at 256B
    ! and the output at 64KB.
    character(kind=c_char), dimension(:), allocatable, target :: c_command
    character(len=4), target :: c_mode

    output = ''

    cmdlen = len_trim(command)
    allocate(c_command(cmdlen + 1))
    do i = 1, cmdlen
      c_command(i) = command(i:i)
    end do
    c_command(cmdlen + 1) = c_null_char
    c_mode = 'r'//c_null_char

    pipe_ptr = c_popen(c_loc(c_command), c_loc(c_mode))
    if (.not. c_associated(pipe_ptr)) return

    ! Read the whole output, collapsing runs of newlines to single spaces,
    ! growing an allocatable accumulator (append per chunk, not per char).
    do
      buffer = c_null_char
      ret_ptr = c_fgets(c_loc(buffer), int(4096, c_int), pipe_ptr)
      if (.not. c_associated(ret_ptr)) exit

      clen = 0
      do i = 1, 4096
        if (buffer(i) == c_null_char) exit
        if (buffer(i) /= char(10)) then
          clen = clen + 1
          chunk(clen:clen) = buffer(i)
        else
          ! newline -> single space, unless the previous kept char is a space
          if (clen > 0) then
            if (chunk(clen:clen) /= ' ') then
              clen = clen + 1; chunk(clen:clen) = ' '
            end if
          else if (len(output) > 0) then
            if (output(len(output):len(output)) /= ' ') output = output // ' '
          end if
        end if
      end do
      if (clen > 0) output = output // chunk(1:clen)
    end do

    i = c_pclose(pipe_ptr)
  end function

  ! Like execute_and_capture but converts newlines to tabs instead of spaces.
  ! This preserves filenames with spaces for completion parsing.
  function execute_and_capture_tabs(command) result(output)
    character(len=*), intent(in) :: command
    character(len=:), allocatable :: output

    type(c_ptr) :: pipe_ptr
    character(kind=c_char), target :: buffer(4096)
    character(len=4096) :: chunk
    type(c_ptr) :: ret_ptr
    integer :: i, clen, cmdlen
    ! Allocatable command/output — fixed buffers capped command at 256B / output at 64KB
    character(kind=c_char), dimension(:), allocatable, target :: c_command
    character(len=4), target :: c_mode

    output = ''

    cmdlen = len_trim(command)
    allocate(c_command(cmdlen + 1))
    do i = 1, cmdlen
      c_command(i) = command(i:i)
    end do
    c_command(cmdlen + 1) = c_null_char
    c_mode = 'r'//c_null_char

    pipe_ptr = c_popen(c_loc(c_command), c_loc(c_mode))
    if (.not. c_associated(pipe_ptr)) return

    ! Collapse runs of newlines to single tabs (preserves spaces in filenames),
    ! growing an allocatable accumulator.
    do
      buffer = c_null_char
      ret_ptr = c_fgets(c_loc(buffer), int(4096, c_int), pipe_ptr)
      if (.not. c_associated(ret_ptr)) exit

      clen = 0
      do i = 1, 4096
        if (buffer(i) == c_null_char) exit
        if (buffer(i) == char(10)) then
          if (clen > 0) then
            if (chunk(clen:clen) /= char(9)) then
              clen = clen + 1; chunk(clen:clen) = char(9)
            end if
          else if (len(output) > 0) then
            if (output(len(output):len(output)) /= char(9)) output = output // char(9)
          end if
        else
          clen = clen + 1
          chunk(clen:clen) = buffer(i)
        end if
      end do
      if (clen > 0) output = output // chunk(1:clen)
    end do

    i = c_pclose(pipe_ptr)
  end function

  ! Terminal control functions
  function enable_raw_mode(original_termios) result(success)
    use iso_fortran_env, only: output_unit, error_unit
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
#elif defined(__FreeBSD__)
    ! FreeBSD: BSD flag values, c_int type (IXON=0x200, IXOFF=0x400)
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000600', c_int)))  ! IXON | IXOFF
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000800', c_int)))  ! IXANY
    raw_termios%c_iflag = iand(raw_termios%c_iflag, not(int(z'00000002', c_int)))  ! BRKINT
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
#elif defined(__FreeBSD__)
    ! FreeBSD ECHOCTL flag (0x40, same as macOS)
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(int(z'00000040', c_int)))
#else
    ! Linux ECHOCTL flag (typically 0x200)
    raw_termios%c_lflag = iand(raw_termios%c_lflag, not(int(z'00000200', c_int)))
#endif

    ! Set minimum characters and timeout for read
    raw_termios%c_cc(VMIN + 1) = char(1)  ! Read at least 1 character
    raw_termios%c_cc(VTIME + 1) = char(0) ! No timeout

#if defined(__APPLE__) || defined(__FreeBSD__)
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

    ! Enable bracketed paste mode (if raw mode succeeded).
    ! FORTSH_NO_BRACKETED_PASTE=1 disables the emit — a kill switch for
    ! bug triage on terminals that mishandle the mode (pattern #20).
    if (success) then
      block
        character(len=8) :: no_bp_env
        integer :: bp_stat
        logical :: bp_disabled
        call get_environment_variable('FORTSH_NO_BRACKETED_PASTE', no_bp_env, status=bp_stat)
        bp_disabled = (bp_stat == 0 .and. trim(no_bp_env) == '1')
        if (.not. bp_disabled) then
          ! ESC[?2004h = Enable bracketed paste
          ! Terminal will wrap pasted text in ESC[200~ ... ESC[201~
          write(output_unit, '(A)', advance='no') char(27) // '[?2004h'
          flush(output_unit)
        end if
      end block

      ! Debug: Check if FORTSH_DEBUG_PASTE is set
      block
        character(len=16) :: debug_paste
        integer :: stat
        call get_environment_variable('FORTSH_DEBUG_PASTE', debug_paste, status=stat)
        if (stat == 0 .and. len_trim(debug_paste) > 0) then
          write(error_unit, '(A)') '[DEBUG: Bracketed paste mode ENABLED]'
        end if
      end block
    end if

    ! DEBUG: Commented out - too noisy
    ! if (success) then
    ! else
    ! end if
  end function
  
  function restore_terminal(original_termios) result(success)
    use iso_fortran_env, only: output_unit
    type(termios_t), intent(in) :: original_termios
    logical :: success
    integer :: ret
    character(len=8) :: no_bp_env
    integer :: bp_stat
    logical :: bp_disabled

    ! Disable bracketed paste mode before restoring terminal,
    ! unless FORTSH_NO_BRACKETED_PASTE=1 (we never enabled it).
    call get_environment_variable('FORTSH_NO_BRACKETED_PASTE', no_bp_env, status=bp_stat)
    bp_disabled = (bp_stat == 0 .and. trim(no_bp_env) == '1')
    if (.not. bp_disabled) then
      ! ESC[?2004l = Disable bracketed paste
      write(output_unit, '(A)', advance='no') char(27) // '[?2004l'
      flush(output_unit)
    end if

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
    else
      ch = char(0)
    end if
  end function

  ! Read a complete UTF-8 character (1-4 bytes)
  ! Returns the character in utf8_char and the number of bytes read
  function read_utf8_char(utf8_char, num_bytes) result(success)
    character(len=4), intent(out) :: utf8_char
    integer, intent(out) :: num_bytes
    logical :: success
    character(c_char), target :: bytes(4)
    integer(c_size_t) :: bytes_read
    integer :: lead_byte_val, i, expected_bytes

    ! Initialize output
    utf8_char = ''
    num_bytes = 0

    ! Read first byte
    bytes_read = c_read(STDIN_FD, c_loc(bytes(1)), 1_c_size_t)
    if (bytes_read /= 1) then
      success = .false.
      return
    end if

    ! Get value of first byte (0-255)
    lead_byte_val = iand(iachar(bytes(1)), 255)

    ! Determine how many bytes this UTF-8 character should have
    if (lead_byte_val < 128) then
      ! ASCII character (0x00-0x7F): 1 byte
      expected_bytes = 1
    else if (iand(lead_byte_val, 224) == 192) then
      ! 2-byte UTF-8 (0xC0-0xDF)
      expected_bytes = 2
    else if (iand(lead_byte_val, 240) == 224) then
      ! 3-byte UTF-8 (0xE0-0xEF)
      expected_bytes = 3
    else if (iand(lead_byte_val, 248) == 240) then
      ! 4-byte UTF-8 (0xF0-0xF7)
      expected_bytes = 4
    else
      ! Invalid UTF-8 lead byte - treat as single byte
      expected_bytes = 1
    end if

    ! Read continuation bytes if needed
    if (expected_bytes > 1) then
      do i = 2, expected_bytes
        bytes_read = c_read(STDIN_FD, c_loc(bytes(i)), 1_c_size_t)
        if (bytes_read /= 1) then
          ! Failed to read continuation byte - return what we have
          success = .false.
          return
        end if
      end do
    end if

    ! Copy bytes to output string
    do i = 1, expected_bytes
      utf8_char(i:i) = bytes(i)
    end do

    num_bytes = expected_bytes
    success = .true.
  end function read_utf8_char

  ! Non-blocking check for bytes already queued on stdin. Used by the readline
  ! loop to coalesce a burst (paste / fast typing) into a single redraw: while
  ! this returns .true. the loop keeps consuming input and defers the redraw.
  ! poll() with timeout 0 returns immediately; at EOF/hangup it reports POLLHUP
  ! (not POLLIN), so this yields .false. and the caller falls through to a
  ! normal blocking read that returns 0 bytes and exits cleanly.
  function input_pending() result(pending)
    logical :: pending
    type(pollfd_t), target :: pfd
    integer(c_int) :: ret

    pfd%fd = STDIN_FD
    pfd%events = POLLIN
    pfd%revents = 0_c_short

    ret = c_poll(c_loc(pfd), 1_c_int, 0_c_int)
    pending = (ret > 0 .and. iand(int(pfd%revents), int(POLLIN)) /= 0)
  end function input_pending

  ! Native directory listing via opendir/readdir (no `ls` subprocess).
  ! Fills the caller's names()/is_dir_flags() arrays (up to their size) with the
  ! raw directory entries — including "." and ".." — leaving any pattern
  ! matching to the caller. `count` is the number of entries returned.
  subroutine list_directory(path, names, is_dir_flags, count)
    character(len=*), intent(in)    :: path
    character(len=*), intent(inout) :: names(:)
    logical,          intent(out)   :: is_dir_flags(:)
    integer,          intent(out)   :: count

    integer, parameter :: NAME_BUF_LEN = 1024
    type(c_ptr) :: dirp
    character(kind=c_char) :: cpath(len_trim(path) + 1)
    character(kind=c_char) :: namebuf(NAME_BUF_LEN)
    integer(c_int) :: is_dir, rc
    integer :: i, plen, maxn, namelen

    count = 0
    maxn = min(size(names), size(is_dir_flags))
    if (maxn <= 0) return

    ! Build a NUL-terminated C path
    plen = len_trim(path)
    do i = 1, plen
      cpath(i) = path(i:i)
    end do
    cpath(plen + 1) = c_null_char

    dirp = c_opendir(cpath)
    if (.not. c_associated(dirp)) return

    do
      if (count >= maxn) exit
      rc = c_readdir(dirp, namebuf, int(NAME_BUF_LEN, c_int), is_dir)
      if (rc /= 1) exit

      ! Length of the NUL-terminated name returned by C
      namelen = 0
      do i = 1, NAME_BUF_LEN
        if (namebuf(i) == c_null_char) exit
        namelen = namelen + 1
      end do

      count = count + 1
      names(count) = ''
      do i = 1, min(namelen, len(names(count)))
        names(count)(i:i) = namebuf(i)
      end do
      is_dir_flags(count) = (is_dir /= 0)
    end do

    call c_closedir(dirp)
  end subroutine list_directory

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
  ! On aarch64 Linux, struct stat layout differs from x86_64 (mode/nlink swapped,
  ! different field sizes). USE_C_STAT routes through C helpers that use system headers.
  function file_exists(path) result(exists)
    character(len=*), intent(in) :: path
    logical :: exists
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    exists = (mode >= 0)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    exists = (ret == 0)
#endif
  end function

  function file_is_regular(path) result(is_reg)
    character(len=*), intent(in) :: path
    logical :: is_reg
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_reg = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFREG)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_reg = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFREG)
#endif
  end function

  function file_is_directory(path) result(is_dir)
    character(len=*), intent(in) :: path
    logical :: is_dir
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_dir = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFDIR)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_dir = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFDIR)
#endif
  end function

  function file_is_symlink(path) result(is_link)
    character(len=*), intent(in) :: path
    logical :: is_link
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_lstat_mode(c_loc(c_path))
    is_link = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFLNK)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_lstat(c_loc(c_path), statbuf)
    is_link = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFLNK)
#endif
  end function

  function file_is_block_device(path) result(is_blk)
    character(len=*), intent(in) :: path
    logical :: is_blk
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_blk = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFBLK)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_blk = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFBLK)
#endif
  end function

  function file_is_char_device(path) result(is_chr)
    character(len=*), intent(in) :: path
    logical :: is_chr
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_chr = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFCHR)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_chr = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFCHR)
#endif
  end function

  function file_is_fifo(path) result(is_fifo)
    character(len=*), intent(in) :: path
    logical :: is_fifo
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_fifo = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFIFO)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_fifo = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFIFO)
#endif
  end function

  function file_is_socket(path) result(is_sock)
    character(len=*), intent(in) :: path
    logical :: is_sock
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_sock = (mode >= 0 .and. iand(mode, S_IFMT) == S_IFSOCK)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_sock = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_IFMT) == S_IFSOCK)
#endif
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
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    has_suid = (mode >= 0 .and. iand(mode, S_ISUID) /= 0)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_suid = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_ISUID) /= 0)
#endif
  end function

  function file_has_sgid(path) result(has_sgid)
    character(len=*), intent(in) :: path
    logical :: has_sgid
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    has_sgid = (mode >= 0 .and. iand(mode, S_ISGID) /= 0)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_sgid = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_ISGID) /= 0)
#endif
  end function

  function file_has_sticky(path) result(has_sticky)
    character(len=*), intent(in) :: path
    logical :: has_sticky
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    c_path = trim(path)//c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    has_sticky = (mode >= 0 .and. iand(mode, S_ISVTX) /= 0)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_sticky = (ret == 0 .and. iand(int(statbuf%st_mode, c_int), S_ISVTX) /= 0)
#endif
  end function

  function file_has_size(path) result(has_size)
    character(len=*), intent(in) :: path
    logical :: has_size
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer(c_long_long) :: sz
    c_path = trim(path)//c_null_char
    sz = fortsh_stat_size(c_loc(c_path))
    has_size = (sz > 0)
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    has_size = (ret == 0 .and. statbuf%st_size > 0)
#endif
  end function

  function file_owned_by_euid(path) result(is_owned)
    character(len=*), intent(in) :: path
    logical :: is_owned
    character(len=256), target :: c_path
#ifdef USE_C_STAT
    integer :: uid
    c_path = trim(path)//c_null_char
    uid = fortsh_stat_uid(c_loc(c_path))
    is_owned = (uid >= 0 .and. uid == c_geteuid())
#else
    integer :: ret
    type(stat_t) :: statbuf
    c_path = trim(path)//c_null_char
    ret = c_stat(c_loc(c_path), statbuf)
    is_owned = (ret == 0 .and. statbuf%st_uid == c_geteuid())
#endif
  end function

  function file_owned_by_egid(path) result(is_owned)
    character(len=*), intent(in) :: path
    logical :: is_owned
    ! Note: getegid() not declared yet, so we'll skip this check for now
    ! This should be added when getegid() is available
    is_owned = .false.
    if (.false.) print *, path  ! Silence unused warning
  end function

  function file_is_newer(file1, file2) result(is_newer)
    character(len=*), intent(in) :: file1, file2
    logical :: is_newer
    character(len=256), target :: c_path1, c_path2
#ifdef USE_C_STAT
    integer(c_long_long) :: mt1, mt2
    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    mt1 = fortsh_stat_mtime(c_loc(c_path1))
    mt2 = fortsh_stat_mtime(c_loc(c_path2))
    is_newer = (mt1 >= 0 .and. mt2 >= 0 .and. mt1 > mt2)
#else
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
#endif
  end function

  function file_is_older(file1, file2) result(is_older)
    character(len=*), intent(in) :: file1, file2
    logical :: is_older
    character(len=256), target :: c_path1, c_path2
#ifdef USE_C_STAT
    integer(c_long_long) :: mt1, mt2
    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    mt1 = fortsh_stat_mtime(c_loc(c_path1))
    mt2 = fortsh_stat_mtime(c_loc(c_path2))
    is_older = (mt1 >= 0 .and. mt2 >= 0 .and. mt1 < mt2)
#else
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
#endif
  end function

  function file_same_as(file1, file2) result(is_same)
    character(len=*), intent(in) :: file1, file2
    logical :: is_same
    character(len=256), target :: c_path1, c_path2
#ifdef USE_C_STAT
    integer(c_long_long) :: dev1, dev2, ino1, ino2
    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    dev1 = fortsh_stat_dev(c_loc(c_path1))
    dev2 = fortsh_stat_dev(c_loc(c_path2))
    ino1 = fortsh_stat_ino(c_loc(c_path1))
    ino2 = fortsh_stat_ino(c_loc(c_path2))
    ! Check for stat failure (-1) rather than >= 0, because dev_t can be
    ! unsigned and overflow to negative when cast to signed long long (FreeBSD)
    is_same = (dev1 /= -1_c_long_long .and. dev2 /= -1_c_long_long .and. &
               dev1 == dev2 .and. ino1 == ino2)
#else
    integer :: ret1, ret2
    type(stat_t) :: stat1, stat2
    c_path1 = trim(file1)//c_null_char
    c_path2 = trim(file2)//c_null_char
    ret1 = c_stat(c_loc(c_path1), stat1)
    ret2 = c_stat(c_loc(c_path2), stat2)
    is_same = (ret1 == 0 .and. ret2 == 0 .and. &
               stat1%st_dev == stat2%st_dev .and. &
               stat1%st_ino == stat2%st_ino)
#endif
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
    use iso_fortran_env, only: error_unit
    integer, intent(out) :: rows, cols
    logical :: success
    type(winsize_t), target :: ws
    integer(c_int) :: ret, c_rows, c_cols
    character(len=16) :: debug_env
    integer :: stat

    ! Try using C wrapper first (more reliable)
    c_rows = 0
    c_cols = 0
    ret = get_term_size_c(c_rows, c_cols)

    call get_environment_variable('FORTSH_DEBUG_WINSIZE', debug_env, status=stat)
    if (stat == 0 .and. len_trim(debug_env) > 0) then
      write(error_unit, '(A,I0,A,I0,A,I0)') '[DEBUG: C wrapper ret=', ret, ' rows=', c_rows, ' cols=', c_cols
    end if

    if (ret == 0 .and. c_rows > 0 .and. c_cols > 0) then
      rows = int(c_rows)
      cols = int(c_cols)
      success = .true.
      return
    end if

    ! Fallback to direct ioctl if C wrapper fails
    ! Initialize structure to zero
    ws%ws_row = 0
    ws%ws_col = 0
    ws%ws_xpixel = 0
    ws%ws_ypixel = 0

    ! Debug: Check if FDs are actually TTYs
    call get_environment_variable('FORTSH_DEBUG_WINSIZE', debug_env, status=stat)
    if (stat == 0 .and. len_trim(debug_env) > 0) then
      write(error_unit, '(A,I0,A,I0,A,I0)') '[DEBUG: isatty(0)=', c_isatty(STDIN_FD), &
            ' isatty(1)=', c_isatty(STDOUT_FD), ' isatty(2)=', c_isatty(STDERR_FD)
    end if

    ! Try to get window size using ioctl
    ! Try stdout first, then stderr if stdout gives 0 dimensions
    ret = c_ioctl(STDOUT_FD, TIOCGWINSZ, c_loc(ws))

    ! Debug output
    call get_environment_variable('FORTSH_DEBUG_WINSIZE', debug_env, status=stat)
    if (stat == 0 .and. len_trim(debug_env) > 0) then
      write(error_unit, '(A,I0,A,I0,A,I0)') '[DEBUG: ioctl(STDOUT) ret=', ret, ' rows=', ws%ws_row, ' cols=', ws%ws_col
    end if

    ! If stdout doesn't give valid dimensions, try stderr
    if (ret /= 0 .or. ws%ws_row == 0 .or. ws%ws_col == 0) then
      ws%ws_row = 0
      ws%ws_col = 0
      ret = c_ioctl(STDERR_FD, TIOCGWINSZ, c_loc(ws))

      call get_environment_variable('FORTSH_DEBUG_WINSIZE', debug_env, status=stat)
      if (stat == 0 .and. len_trim(debug_env) > 0) then
        write(error_unit, '(A,I0,A,I0,A,I0)') '[DEBUG: ioctl(STDERR) ret=', ret, ' rows=', ws%ws_row, ' cols=', ws%ws_col
      end if
    end if

    ! If stderr also doesn't work, try stdin
    if (ret /= 0 .or. ws%ws_row == 0 .or. ws%ws_col == 0) then
      ws%ws_row = 0
      ws%ws_col = 0
      ret = c_ioctl(STDIN_FD, TIOCGWINSZ, c_loc(ws))

      call get_environment_variable('FORTSH_DEBUG_WINSIZE', debug_env, status=stat)
      if (stat == 0 .and. len_trim(debug_env) > 0) then
        write(error_unit, '(A,I0,A,I0,A,I0)') '[DEBUG: ioctl(STDIN) ret=', ret, ' rows=', ws%ws_row, ' cols=', ws%ws_col
      end if
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

  ! Check if a path is a directory
  function test_is_directory(path) result(is_dir)
    character(len=*), intent(in) :: path
    logical :: is_dir
    character(len=len(path)+1), target :: c_path
#ifdef USE_C_STAT
    integer :: mode
    is_dir = .false.
    c_path = trim(path) // c_null_char
    mode = fortsh_stat_mode(c_loc(c_path))
    is_dir = (mode >= 0 .and. iand(mode, S_IFDIR) /= 0)
#else
    integer :: stat_result
    type(stat_t) :: file_stat
    is_dir = .false.
    c_path = trim(path) // c_null_char
    stat_result = c_stat(c_loc(c_path), file_stat)
    if (stat_result == 0) then
      is_dir = iand(int(file_stat%st_mode, c_int), S_IFDIR) /= 0
    end if
#endif
  end function

  ! Set terminal title using OSC sequences
  ! OSC 0 ; title BEL sets both icon and window title
  subroutine set_terminal_title(title)
    use iso_fortran_env, only: output_unit
    character(len=*), intent(in) :: title
    ! ESC ] 0 ; title BEL
    write(output_unit, '(A)', advance='no') char(27) // ']0;' // trim(title) // char(7)
    flush(output_unit)
  end subroutine

  ! Check if terminal supports ANSI escape codes
  function terminal_supports_ansi() result(supports)
    logical :: supports
    character(len=256) :: term_type
    integer :: status

    call get_environment_variable('TERM', term_type, status=status)

    if (status /= 0 .or. len_trim(term_type) == 0) then
      ! No TERM set - assume dumb terminal
      supports = .false.
      return
    end if

    ! Known dumb/non-ANSI terminals
    select case (trim(term_type))
    case ('dumb', 'unknown', 'cons25')
      supports = .false.
    case default
      supports = .true.
    end select
  end function terminal_supports_ansi

end module system_interface