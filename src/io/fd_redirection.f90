! ==============================================================================
! Module: fd_redirection  
! Purpose: POSIX file descriptor redirection support
! ==============================================================================
module fd_redirection
  use shell_types
  use system_interface, only: get_environment_var, c_null_char, create_pipe
  use iso_fortran_env, only: output_unit, error_unit
  use io_helpers, only: write_stderr
  use iso_c_binding, only: c_int, c_ptr, c_size_t, c_intptr_t, c_loc
  implicit none

  interface
    ! C wrapper functions for file descriptor manipulation
    ! (Using wrappers to work around Fortran C binding mode_t bug)
    function c_open(pathname, flags, mode) bind(C, name="fortsh_open")
      use iso_c_binding
      character(kind=c_char), intent(in) :: pathname(*)
      integer(c_int), value :: flags, mode
      integer(c_int) :: c_open
    end function c_open

    function c_close(fd) bind(C, name="fortsh_close")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_close
    end function c_close

    function c_dup2(oldfd, newfd) bind(C, name="fortsh_dup2")
      use iso_c_binding
      integer(c_int), value :: oldfd, newfd
      integer(c_int) :: c_dup2
    end function c_dup2

    function c_dup(fd) bind(C, name="fortsh_dup")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_dup
    end function c_dup

    function c_write(fd, buf, count) bind(C, name="write")
      use iso_c_binding
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_intptr_t) :: c_write
    end function c_write

    function c_get_errno() bind(C, name="fortsh_get_errno")
      use iso_c_binding
      integer(c_int) :: c_get_errno
    end function c_get_errno

    function c_strerror(errnum) bind(C, name="fortsh_strerror")
      use iso_c_binding
      integer(c_int), value :: errnum
      type(c_ptr) :: c_strerror
    end function c_strerror
  end interface

  ! File access flags (from fcntl.h) - use local names to avoid conflicts
  integer, parameter :: FD_FD_O_RDONLY = int(Z'00000000')
  integer, parameter :: FD_O_WRONLY = int(Z'00000001')
  integer, parameter :: FD_O_RDWR = int(Z'00000002')
  ! Platform-specific O_* flags
#if defined(__APPLE__) || defined(__FreeBSD__)
  integer, parameter :: FD_O_CREAT = 512   ! 0x200 on BSD
  integer, parameter :: FD_O_TRUNC = 1024  ! 0x400 on BSD
  integer, parameter :: FD_O_APPEND = 8    ! 0x8 on BSD
#else
  ! Linux values
  integer, parameter :: FD_O_CREAT = 64    ! 0x40 on Linux
  integer, parameter :: FD_O_TRUNC = 512   ! 0x200 on Linux
  integer, parameter :: FD_O_APPEND = 1024 ! 0x400 on Linux
#endif

  ! Standard file descriptors - use local names to avoid conflicts
  integer, parameter :: FD_STDIN = 0
  integer, parameter :: FD_STDOUT = 1 
  integer, parameter :: FD_STDERR = 2

  ! Saved file descriptors for restoration
  type :: saved_fd_t
    integer :: fd = -1
    integer :: saved_fd = -1
    logical :: is_saved = .false.
  end type saved_fd_t
  
  type(saved_fd_t) :: saved_fds(20)
  integer :: num_saved_fds = 0

  public :: save_fd_mark, restore_fds_to_mark

contains

  function get_errno_message() result(msg)
    use iso_c_binding
    character(len=256) :: msg
    type(c_ptr) :: cptr
    character(kind=c_char), pointer :: cstr(:)
    integer :: errno_val, slen, ci
    errno_val = c_get_errno()
    cptr = c_strerror(errno_val)
    if (.not. c_associated(cptr)) then
      msg = 'Unknown error'
      return
    end if
    call c_f_pointer(cptr, cstr, [256])
    slen = 0
    do ci = 1, 256
      if (cstr(ci) == c_null_char) exit
      slen = slen + 1
    end do
    msg = ''
    do ci = 1, slen
      msg(ci:ci) = cstr(ci)
    end do
  end function get_errno_message

  ! Apply all redirections for a command
  subroutine apply_redirections(cmd, success)
    type(command_t), intent(in) :: cmd
    logical, intent(out) :: success
    integer :: i
    
    success = .true.
    
    do i = 1, cmd%num_redirections
      call apply_single_redirection(cmd%redirections(i), success)
      if (.not. success) return
    end do
  end subroutine

  ! Apply a single redirection
  ! permanent: if true, don't save original fd (for exec redirections)
  subroutine apply_single_redirection(redir, success, noclobber, permanent, shell)
    use iso_c_binding, only: c_int
    use system_interface, only: file_exists, file_is_regular, move_fd_high
    use variables, only: set_shell_variable, get_shell_variable
    type(redirection_t), intent(in) :: redir
    logical, intent(out) :: success
    logical, intent(in), optional :: noclobber
    logical, intent(in), optional :: permanent
    type(shell_state_t), intent(inout), optional :: shell
    integer(c_int) :: file_fd, flags, mode
    character(len=:), allocatable :: filename_c
    logical :: check_noclobber, is_permanent

    success = .true.
    check_noclobber = .false.
    is_permanent = .false.
    if (present(noclobber)) check_noclobber = noclobber
    if (present(permanent)) is_permanent = permanent

    select case (redir%type)
      case (REDIR_IN)
        ! < file (redirect stdin from file)
        filename_c = trim(redir%filename) // c_null_char
        file_fd = c_open(filename_c, FD_FD_O_RDONLY, 0)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (redir%is_varassign .and. present(shell)) then
          file_fd = move_fd_high(file_fd)
          block
            character(len=16) :: fd_str
            write(fd_str, '(I0)') file_fd
            call set_shell_variable(shell, trim(redir%varassign_name), trim(fd_str))
          end block
        else
          if (.not. is_permanent) call save_fd(FD_STDIN)
          if (c_dup2(file_fd, FD_STDIN) < 0) then
            success = .false.
          end if
          if (c_close(file_fd) < 0) then
          end if
        end if

      case (REDIR_OUT)
        ! > file (redirect stdout to file)
        ! Check noclobber option (set -C) - prevents overwriting existing files
        if (check_noclobber .and. .not. redir%force_clobber .and. file_is_regular(trim(redir%filename))) then
          write(error_unit, '(a)') 'fortsh: cannot overwrite existing file: ' // trim(redir%filename)
          success = .false.
          return
        end if

        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! 0644 octal = 420 decimal = rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_TRUNC)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (redir%is_varassign .and. present(shell)) then
          ! {VAR}>file: move fd high and assign number to variable
          file_fd = move_fd_high(file_fd)
          block
            character(len=16) :: fd_str
            write(fd_str, '(I0)') file_fd
            call set_shell_variable(shell, trim(redir%varassign_name), trim(fd_str))
          end block
        else
          if (.not. is_permanent) call save_fd(FD_STDOUT)
          if (c_dup2(file_fd, FD_STDOUT) < 0) then
            success = .false.
          end if
          if (c_close(file_fd) < 0) then
            ! Error closing file descriptor
          end if
        end if

      case (REDIR_APPEND)
        ! >> file (append stdout to file)
        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! 0644 octal = 420 decimal = rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_APPEND)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (redir%is_varassign .and. present(shell)) then
          file_fd = move_fd_high(file_fd)
          block
            character(len=16) :: fd_str
            write(fd_str, '(I0)') file_fd
            call set_shell_variable(shell, trim(redir%varassign_name), trim(fd_str))
          end block
        else
          if (.not. is_permanent) call save_fd(FD_STDOUT)
          if (c_dup2(file_fd, FD_STDOUT) < 0) then
            success = .false.
          end if
          if (c_close(file_fd) < 0) then
          end if
        end if

      case (REDIR_FD_IN)
        ! n< file (redirect fd n from file)
        filename_c = trim(redir%filename) // c_null_char
        file_fd = c_open(filename_c, 0, 0)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(redir%fd)
        ! Only dup2 if the file_fd is different from target fd
        ! If they're the same, we're already done (the file is open on the desired FD)
        if (file_fd /= redir%fd) then
          if (c_dup2(file_fd, redir%fd) < 0) then
            success = .false.
          end if
          ! Close the original file_fd since we dup'd it
          if (c_close(file_fd) < 0) then
            ! Error closing file descriptor
          end if
        end if
        ! If file_fd == redir%fd, don't close it - it's already on the right FD!
        
      case (REDIR_FD_OUT)
        ! n> file (redirect fd n to file)
        ! Check noclobber option (set -C)
        if (check_noclobber .and. .not. redir%force_clobber .and. file_is_regular(trim(redir%filename))) then
          write(error_unit, '(a)') 'fortsh: cannot overwrite existing file: ' // trim(redir%filename)
          success = .false.
          return
        end if

        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_TRUNC)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(redir%fd)
        ! Only dup2 if the file_fd is different from target fd
        if (file_fd /= redir%fd) then
          if (c_dup2(file_fd, redir%fd) < 0) then
            success = .false.
          end if
          if (c_close(file_fd) < 0) then
            ! Error closing file descriptor
          end if
        end if

      case (REDIR_FD_APPEND)
        ! n>> file (append fd n to file)
        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_APPEND)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(redir%fd)
        ! Only dup2 if the file_fd is different from target fd
        if (file_fd /= redir%fd) then
          if (c_dup2(file_fd, redir%fd) < 0) then
            success = .false.
          end if
          if (c_close(file_fd) < 0) then
            ! Error closing file descriptor
          end if
        end if

      case (REDIR_DUP_IN)
        ! n<&m (duplicate fd m to fd n, default n=0)
        if (redir%fd < 0) then
          if (.not. is_permanent) call save_fd(FD_STDIN)
          if (c_dup2(redir%target_fd, FD_STDIN) < 0) then
            block
              character(len=32) :: fd_str
              write(fd_str, '(i0)') redir%target_fd
              call write_stderr('sh: ' // trim(fd_str) // ': Bad file descriptor')
            end block
            success = .false.
          end if
        else
          if (.not. is_permanent) call save_fd(redir%fd)
          if (c_dup2(redir%target_fd, redir%fd) < 0) then
            block
              character(len=32) :: fd_str
              write(fd_str, '(i0)') redir%target_fd
              call write_stderr('sh: ' // trim(fd_str) // ': Bad file descriptor')
            end block
            success = .false.
          end if
        end if

      case (REDIR_DUP_OUT)
        ! n>&m (duplicate fd m to fd n, default n=1)
        if (redir%fd < 0) then
          if (.not. is_permanent) call save_fd(FD_STDOUT)
          if (c_dup2(redir%target_fd, FD_STDOUT) < 0) then
            block
              character(len=32) :: fd_str
              write(fd_str, '(i0)') redir%target_fd
              call write_stderr('sh: ' // trim(fd_str) // ': Bad file descriptor')
            end block
            success = .false.
          end if
        else
          if (.not. is_permanent) call save_fd(redir%fd)
          if (c_dup2(redir%target_fd, redir%fd) < 0) then
            block
              character(len=32) :: fd_str
              write(fd_str, '(i0)') redir%target_fd
              call write_stderr('sh: ' // trim(fd_str) // ': Bad file descriptor')
            end block
            success = .false.
          end if
        end if
        
      case (REDIR_CLOSE)
        ! n>&- or {VAR}>&- (close fd)
        if (redir%is_varassign .and. present(shell)) then
          ! Look up fd number from shell variable
          block
            character(len=:), allocatable :: var_val
            integer :: close_fd, ios
            var_val = get_shell_variable(shell, trim(redir%varassign_name))
            if (len_trim(var_val) > 0) then
              read(var_val, *, iostat=ios) close_fd
              if (ios == 0 .and. close_fd >= 0) then
                if (.not. is_permanent) call save_fd(close_fd)
                if (c_close(close_fd) < 0) success = .false.
              end if
            end if
          end block
        else
          if (.not. is_permanent) call save_fd(redir%fd)
          if (c_close(redir%fd) < 0) then
            success = .false.
          end if
        end if

      case (REDIR_READWRITE)
        ! <> file (open for read/write, default fd=0)
        ! POSIX: Create file if it doesn't exist
        if (allocated(redir%filename)) then
          filename_c = trim(redir%filename)//c_null_char
          flags = ior(FD_O_RDWR, FD_O_CREAT)
          file_fd = c_open(filename_c, flags, 420)  ! mode 0644
          if (file_fd < 0) then
            write(error_unit, '(a)') 'fortsh: ' // trim(redir%filename) // ': ' // trim(get_errno_message())
            success = .false.
          else
            if (redir%fd < 0) then
              if (.not. is_permanent) call save_fd(FD_STDIN)
              if (c_dup2(file_fd, FD_STDIN) < 0) then
                success = .false.
              end if
              ! Close original only if it's different from target
              if (file_fd /= FD_STDIN) then
                if (c_close(file_fd) < 0) then
                  ! Error closing file descriptor
                end if
              end if
            else
              if (.not. is_permanent) call save_fd(redir%fd)
              if (c_dup2(file_fd, redir%fd) < 0) then
                success = .false.
              end if
              ! Close original only if it's different from target
              if (file_fd /= redir%fd) then
                if (c_close(file_fd) < 0) then
                  ! Error closing file descriptor
                end if
              end if
            end if
          end if
        end if

      case (REDIR_HERE_STRING)
        ! <<< string (here-string) - redirect string content to stdin
        if (allocated(redir%filename)) then
          block
            integer(c_int) :: read_fd, write_fd
            character(len=:), allocatable, target :: content
            integer(c_intptr_t) :: bytes_written

            ! Create pipe for here-string
            if (.not. create_pipe(read_fd, write_fd)) then
              write(error_unit, '(a)') 'fortsh: cannot create pipe for here-string'
              success = .false.
            else
              ! Write content to pipe (with trailing newline)
              content = redir%filename // char(10)
              bytes_written = c_write(write_fd, c_loc(content), int(len(content), c_size_t))
              if (bytes_written < 0) then
                write(error_unit, '(a)') 'fortsh: error writing to here-string pipe'
                success = .false.
              end if

              ! Close write end
              if (c_close(write_fd) < 0) then
                ! Error closing write end
              end if

              ! Redirect stdin from read end
              if (.not. is_permanent) call save_fd(FD_STDIN)
              if (c_dup2(read_fd, FD_STDIN) < 0) then
                success = .false.
              end if

              ! Close original read fd
              if (c_close(read_fd) < 0) then
                ! Error closing read end
              end if
            end if
          end block
        else
          write(error_unit, '(a)') 'fortsh: here-string missing content'
          success = .false.
        end if

      case (REDIR_HERE_DOC)
        ! << delimiter (here-document) - redirect heredoc content to stdin
        if (allocated(redir%filename)) then
          block
            integer(c_int) :: read_fd, write_fd
            character(len=:), allocatable, target :: content
            integer(c_intptr_t) :: bytes_written

            ! Create pipe for heredoc
            if (.not. create_pipe(read_fd, write_fd)) then
              write(error_unit, '(a)') &
                'fortsh: cannot create pipe for heredoc'
              success = .false.
            else
              ! Write content to pipe (content already has newlines)
              content = redir%filename
              bytes_written = c_write(write_fd, &
                c_loc(content), &
                int(len(content), c_size_t))
              if (bytes_written < 0) then
                write(error_unit, '(a)') &
                  'fortsh: error writing to heredoc pipe'
                success = .false.
              end if

              ! Close write end
              if (c_close(write_fd) < 0) then
              end if

              ! Redirect stdin from read end
              if (.not. is_permanent) call save_fd(FD_STDIN)
              if (c_dup2(read_fd, FD_STDIN) < 0) then
                success = .false.
              end if

              ! Close original read fd
              if (c_close(read_fd) < 0) then
              end if
            end if
          end block
        else
          write(error_unit, '(a)') &
            'fortsh: heredoc missing content'
          success = .false.
        end if

      case default
        write(error_unit, '(a,i15)') 'fortsh: unknown redirection type: ', redir%type
        success = .false.
    end select
  end subroutine

  ! Save a file descriptor for later restoration
  subroutine save_fd(fd)
    integer, intent(in) :: fd
    integer :: target_fd

    ! Save new fd using dup2 to a high fd number (100+)
    ! This prevents saved fds from conflicting with redirections
    if (num_saved_fds < size(saved_fds)) then
      num_saved_fds = num_saved_fds + 1
      saved_fds(num_saved_fds)%fd = fd
      ! Use dup2 to target fd >= 100 to avoid conflicts
      target_fd = 100 + num_saved_fds - 1
      if (c_dup2(fd, target_fd) >= 0) then
        saved_fds(num_saved_fds)%saved_fd = target_fd
        saved_fds(num_saved_fds)%is_saved = .true.
      else
        ! dup2 failed, fall back to dup
        saved_fds(num_saved_fds)%saved_fd = c_dup(fd)
        saved_fds(num_saved_fds)%is_saved = .true.
      end if
    end if
  end subroutine

  ! Restore all saved file descriptors
  subroutine restore_fds()
    call restore_fds_to_mark(0)
  end subroutine

  ! Return current saved fd stack depth (for scoped restore)
  function save_fd_mark() result(mark)
    integer :: mark
    mark = num_saved_fds
  end function

  ! Restore saved file descriptors back to a given mark (reverse order)
  subroutine restore_fds_to_mark(mark)
    integer, intent(in) :: mark
    integer :: i

    do i = num_saved_fds, mark + 1, -1
      if (saved_fds(i)%is_saved) then
        if (c_dup2(saved_fds(i)%saved_fd, saved_fds(i)%fd) < 0) then
          ! Error restoring file descriptor
        end if
        if (c_close(saved_fds(i)%saved_fd) < 0) then
          ! Error closing saved file descriptor
        end if
        saved_fds(i)%is_saved = .false.
      end if
    end do

    num_saved_fds = mark
  end subroutine

  ! Parse redirection from token (e.g., "2>file", ">&1", "3<&-")
  subroutine parse_redirection_token(token, redir, success)
    character(len=*), intent(in) :: token
    type(redirection_t), intent(out) :: redir
    logical, intent(out) :: success
    
    integer :: i, fd_num, target_num, iostat
    character(len=256) :: fd_str, filename
    
    success = .true.
    redir%fd = -1
    redir%target_fd = -1
    redir%type = 0
    
    ! Parse patterns like "2>", ">&1", "<&0", "3>>"
    if (index(token, '>&-') > 0) then
      ! Close fd: n>&-
      i = index(token, '>&-')
      if (i > 1) then
        fd_str = token(1:i-1)
        read(fd_str, *, iostat=iostat) fd_num
        if (iostat == 0) then
          redir%type = REDIR_CLOSE
          redir%fd = fd_num
        else
          success = .false.
        end if
      else
        success = .false.
      end if
      
    else if (index(token, '>&') > 0) then
      ! Duplicate output: >&n or n>&m
      i = index(token, '>&')
      if (i == 1) then
        ! >&n (stdout to fd n)
        fd_str = token(3:)
        read(fd_str, *, iostat=iostat) target_num
        if (iostat == 0) then
          redir%type = REDIR_DUP_OUT
          redir%fd = FD_STDOUT
          redir%target_fd = target_num
        else
          success = .false.
        end if
      else
        ! n>&m (fd n to fd m)
        fd_str = token(1:i-1)
        read(fd_str, *, iostat=iostat) fd_num
        if (iostat == 0) then
          fd_str = token(i+2:)
          read(fd_str, *, iostat=iostat) target_num
          if (iostat == 0) then
            redir%type = REDIR_DUP_OUT
            redir%fd = fd_num
            redir%target_fd = target_num
          else
            success = .false.
          end if
        else
          success = .false.
        end if
      end if
      
    else if (index(token, '<&') > 0) then
      ! Duplicate input: <&n or n<&m
      i = index(token, '<&')
      if (i == 1) then
        ! <&n (stdin from fd n)
        fd_str = token(3:)
        read(fd_str, *, iostat=iostat) target_num
        if (iostat == 0) then
          redir%type = REDIR_DUP_IN
          redir%fd = FD_STDIN
          redir%target_fd = target_num
        else
          success = .false.
        end if
      else
        success = .false.  ! n<&m not standard
      end if
      
    else if (index(token, '>>') > 0) then
      ! Append: >> or n>>
      i = index(token, '>>')
      if (i == 1) then
        ! >>file (append stdout)
        filename = token(3:)
        redir%type = REDIR_APPEND
        redir%fd = FD_STDOUT
        allocate(redir%filename, source=trim(filename))
      else
        ! n>>file (append fd n)
        fd_str = token(1:i-1)
        read(fd_str, *, iostat=iostat) fd_num
        if (iostat == 0) then
          filename = token(i+2:)
          redir%type = REDIR_FD_APPEND
          redir%fd = fd_num
          allocate(redir%filename, source=trim(filename))
        else
          success = .false.
        end if
      end if
      
    else if (index(token, '>') > 0) then
      ! Output: > or n>
      i = index(token, '>')
      if (i == 1) then
        ! >file (redirect stdout)
        filename = token(2:)
        redir%type = REDIR_OUT
        redir%fd = FD_STDOUT
        allocate(redir%filename, source=trim(filename))
      else
        ! n>file (redirect fd n)
        fd_str = token(1:i-1)
        read(fd_str, *, iostat=iostat) fd_num
        if (iostat == 0) then
          filename = token(i+1:)
          redir%type = REDIR_FD_OUT
          redir%fd = fd_num
          allocate(redir%filename, source=trim(filename))
        else
          success = .false.
        end if
      end if
      
    else if (index(token, '<') > 0) then
      ! Input: < or n<
      i = index(token, '<')
      if (i == 1) then
        ! <file (redirect stdin)
        filename = token(2:)
        redir%type = REDIR_IN
        redir%fd = FD_STDIN
        allocate(redir%filename, source=trim(filename))
      else
        ! n<file (redirect fd n)
        fd_str = token(1:i-1)
        read(fd_str, *, iostat=iostat) fd_num
        if (iostat == 0) then
          filename = token(i+1:)
          redir%type = REDIR_FD_IN
          redir%fd = fd_num
          allocate(redir%filename, source=trim(filename))
        else
          success = .false.
        end if
      end if
      
    else
      ! Not a redirection token
      success = .false.
    end if
  end subroutine

end module fd_redirection