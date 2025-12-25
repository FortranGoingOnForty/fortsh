! ==============================================================================
! Module: fd_redirection  
! Purpose: POSIX file descriptor redirection support
! ==============================================================================
module fd_redirection
  use shell_types
  use system_interface, only: get_environment_var, c_null_char
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding, only: c_int
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
  end interface

  ! File access flags (from fcntl.h) - use local names to avoid conflicts
  integer, parameter :: FD_FD_O_RDONLY = int(Z'00000000')
  integer, parameter :: FD_O_WRONLY = int(Z'00000001')
  integer, parameter :: FD_O_RDWR = int(Z'00000002')
  ! Platform-specific O_* flags
#ifdef __APPLE__
  integer, parameter :: FD_O_CREAT = 512   ! 0x200 on macOS
  integer, parameter :: FD_O_TRUNC = 1024  ! 0x400 on macOS
  integer, parameter :: FD_O_APPEND = 8    ! 0x8 on macOS
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

contains

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
  subroutine apply_single_redirection(redir, success, noclobber, permanent)
    use iso_c_binding, only: c_int
    use system_interface, only: file_exists
    type(redirection_t), intent(in) :: redir
    logical, intent(out) :: success
    logical, intent(in), optional :: noclobber
    logical, intent(in), optional :: permanent
    integer(c_int) :: file_fd, flags, mode
    character(len=1024) :: filename_c
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
          write(error_unit, '(a)') 'fortsh: cannot open ' // trim(redir%filename) // ': No such file or directory'
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(FD_STDIN)
        if (c_dup2(file_fd, FD_STDIN) < 0) then
          success = .false.
        end if
        if (c_close(file_fd) < 0) then
          ! Error closing file descriptor
        end if

      case (REDIR_OUT)
        ! > file (redirect stdout to file)
        ! Check noclobber option (set -C) - prevents overwriting existing files
        if (check_noclobber .and. .not. redir%force_clobber .and. file_exists(trim(redir%filename))) then
          write(error_unit, '(a)') 'fortsh: cannot overwrite existing file: ' // trim(redir%filename)
          success = .false.
          return
        end if

        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! 0644 octal = 420 decimal = rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_TRUNC)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: cannot create ' // trim(redir%filename)
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(FD_STDOUT)
        if (c_dup2(file_fd, FD_STDOUT) < 0) then
          success = .false.
        end if
        if (c_close(file_fd) < 0) then
          ! Error closing file descriptor
        end if
        
      case (REDIR_APPEND)
        ! >> file (append stdout to file)
        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! 0644 octal = 420 decimal = rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_APPEND)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: cannot create ' // trim(redir%filename)
          success = .false.
          return
        end if
        if (.not. is_permanent) call save_fd(FD_STDOUT)
        if (c_dup2(file_fd, FD_STDOUT) < 0) then
          success = .false.
        end if
        if (c_close(file_fd) < 0) then
          ! Error closing file descriptor
        end if
        
      case (REDIR_FD_IN)
        ! n< file (redirect fd n from file)
        filename_c = trim(redir%filename) // c_null_char
        file_fd = c_open(filename_c, 0, 0)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: cannot open ' // trim(redir%filename)
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
        if (check_noclobber .and. .not. redir%force_clobber .and. file_exists(trim(redir%filename))) then
          write(error_unit, '(a)') 'fortsh: cannot overwrite existing file: ' // trim(redir%filename)
          success = .false.
          return
        end if

        filename_c = trim(redir%filename) // c_null_char
        mode = 420  ! rw-r--r--
        flags = ior(ior(FD_O_WRONLY, FD_O_CREAT), FD_O_TRUNC)
        file_fd = c_open(filename_c, flags, mode)
        if (file_fd < 0) then
          write(error_unit, '(a)') 'fortsh: cannot create ' // trim(redir%filename)
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
          write(error_unit, '(a)') 'fortsh: cannot create ' // trim(redir%filename)
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
            write(error_unit, '(a,i0,a)') 'sh: ', redir%target_fd, ': Bad file descriptor'
            success = .false.
          end if
        else
          if (.not. is_permanent) call save_fd(redir%fd)
          if (c_dup2(redir%target_fd, redir%fd) < 0) then
            write(error_unit, '(a,i0,a)') 'sh: ', redir%target_fd, ': Bad file descriptor'
            success = .false.
          end if
        end if

      case (REDIR_DUP_OUT)
        ! n>&m (duplicate fd m to fd n, default n=1)
        if (redir%fd < 0) then
          if (.not. is_permanent) call save_fd(FD_STDOUT)
          if (c_dup2(redir%target_fd, FD_STDOUT) < 0) then
            write(error_unit, '(a,i0,a)') 'sh: ', redir%target_fd, ': Bad file descriptor'
            success = .false.
          end if
        else
          if (.not. is_permanent) call save_fd(redir%fd)
          if (c_dup2(redir%target_fd, redir%fd) < 0) then
            write(error_unit, '(a,i0,a)') 'sh: ', redir%target_fd, ': Bad file descriptor'
            success = .false.
          end if
        end if
        
      case (REDIR_CLOSE)
        ! n>&- (close fd n)
        if (.not. is_permanent) call save_fd(redir%fd)
        if (c_close(redir%fd) < 0) then
          success = .false.
        end if

      case (REDIR_READWRITE)
        ! <> file (open for read/write, default fd=0)
        if (allocated(redir%filename)) then
          filename_c = trim(redir%filename)//c_null_char
          flags = FD_O_RDWR
          file_fd = c_open(filename_c, flags, 420)  ! mode 0644
          if (file_fd < 0) then
            write(error_unit, '(3a)') 'fortsh: cannot open file: ', trim(redir%filename)
            success = .false.
          else
            if (redir%fd < 0) then
              if (.not. is_permanent) call save_fd(FD_STDIN)
              if (c_dup2(file_fd, FD_STDIN) < 0) then
                success = .false.
              end if
            else
              if (.not. is_permanent) call save_fd(redir%fd)
              if (c_dup2(file_fd, redir%fd) < 0) then
                success = .false.
              end if
            end if
            if (c_close(file_fd) < 0) then
              ! Error closing file descriptor
            end if
          end if
        end if

      case default
        write(error_unit, '(a,i15)') 'fortsh: unknown redirection type: ', redir%type
        success = .false.
    end select
  end subroutine

  ! Save a file descriptor for later restoration
  subroutine save_fd(fd)
    integer, intent(in) :: fd
    integer :: i, target_fd

    ! Check if already saved
    do i = 1, num_saved_fds
      if (saved_fds(i)%fd == fd) return
    end do

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
    integer :: i
    
    do i = 1, num_saved_fds
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
    
    num_saved_fds = 0
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