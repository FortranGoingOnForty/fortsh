! ==============================================================================
! Module: shell_types
! Purpose: Common type definitions and constants
! ==============================================================================
module shell_types
  use iso_c_binding
  implicit none
  
  integer, parameter :: MAX_PATH_LEN = 4096
  integer, parameter :: MAX_TOKEN_LEN = 256
  integer, parameter :: MAX_TOKENS = 100
  integer, parameter :: MAX_ENV_LEN = 32768
  integer, parameter :: MAX_PIPELINE = 10
  integer, parameter :: MAX_JOBS = 100
  integer, parameter :: MAX_HEREDOC_LEN = 65536
  
  ! Command separator types
  integer, parameter :: SEP_NONE = 0
  integer, parameter :: SEP_SEMICOLON = 1    ! ;
  integer, parameter :: SEP_AND = 2          ! &&
  integer, parameter :: SEP_OR = 3           ! ||
  integer, parameter :: SEP_PIPE = 4         ! |
  integer, parameter :: SEP_BACKGROUND = 5   ! &
  
  ! Job states
  integer, parameter :: JOB_RUNNING = 1
  integer, parameter :: JOB_STOPPED = 2
  integer, parameter :: JOB_DONE = 3
  
  type :: command_t
    character(len=:), allocatable :: tokens(:)
    integer :: num_tokens = 0
    character(len=:), allocatable :: input_file
    character(len=:), allocatable :: output_file
    character(len=:), allocatable :: error_file
    character(len=:), allocatable :: heredoc_delimiter
    character(len=:), allocatable :: heredoc_content
    logical :: append_output = .false.
    logical :: append_error = .false.
    logical :: redirect_stderr_to_stdout = .false.
    logical :: background = .false.
    integer :: separator = SEP_NONE
  end type command_t
  
  type :: pipeline_t
    type(command_t), allocatable :: commands(:)
    integer :: num_commands = 0
  end type pipeline_t
  
  type :: job_t
    integer :: job_id = 0
    integer(c_pid_t) :: pgid = 0
    integer(c_pid_t), allocatable :: pids(:)
    integer :: num_pids = 0
    character(len=256) :: command_line
    integer :: state = JOB_RUNNING
    logical :: notified = .false.
    logical :: foreground = .true.
  end type job_t
  
  type :: shell_state_t
    character(len=256) :: username
    character(len=256) :: hostname
    character(len=MAX_PATH_LEN) :: cwd
    integer :: last_exit_status = 0
    integer(c_pid_t) :: last_pid = 0
    integer(c_pid_t) :: shell_pgid = 0
    integer :: shell_terminal = 0
    logical :: is_interactive = .false.
    logical :: running = .true.
    type(job_t) :: jobs(MAX_JOBS)
    integer :: num_jobs = 0
    integer :: next_job_id = 1
  end type shell_state_t
  
end module shell_types

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
      import :: c_int, c_ptr, c_size_t, c_ssize_t
      integer(c_int), value :: fd
      type(c_ptr), value :: buf
      integer(c_size_t), value :: count
      integer(c_ssize_t) :: c_write
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
    
    c_value_ptr = c_getenv(trim(var_name)//c_null_char)
    
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
    
    ret = c_setenv(trim(var_name)//c_null_char, &
                   trim(var_value)//c_null_char, 1_c_int)
    success = (ret == 0)
  end function
  
  function change_directory(path) result(success)
    character(len=*), intent(in) :: path
    logical :: success
    integer :: ret
    
    ret = c_chdir(trim(path)//c_null_char)
    success = (ret == 0)
  end function
  
  function get_current_directory() result(path)
    character(len=:), allocatable :: path
    character(kind=c_char) :: c_path(MAX_PATH_LEN)
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
    integer(c_int) :: pipefd(2)
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
    character(kind=c_char) :: buffer(1024)
    character(len=MAX_TOKEN_LEN*10) :: temp_output
    type(c_ptr) :: ret_ptr
    integer :: i, pos
    
    ! Open pipe to command
    pipe_ptr = c_popen(trim(command)//c_null_char, 'r'//c_null_char)
    
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

! ==============================================================================
! Module: signal_handler
! Purpose: Signal handling for job control
! ==============================================================================
module signal_handler
  use iso_c_binding
  use system_interface
  implicit none
  
contains
  
  subroutine setup_signal_handlers()
    type(c_funptr) :: old_handler
    
    ! Ignore interactive signals for shell itself
    SIG_IGN = c_null_funptr
    old_handler = c_signal(SIGINT, SIG_IGN)
    old_handler = c_signal(SIGTSTP, SIG_IGN)
    old_handler = c_signal(SIGTTIN, SIG_IGN)
    old_handler = c_signal(SIGTTOU, SIG_IGN)
  end subroutine
  
end module signal_handler

! ==============================================================================
! Module: job_control
! Purpose: Job control management
! ==============================================================================
module job_control
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  implicit none
  
contains
  
  function add_job(shell, pgid, command_line, foreground) result(job_id)
    type(shell_state_t), intent(inout) :: shell
    integer(c_pid_t), intent(in) :: pgid
    character(len=*), intent(in) :: command_line
    logical, intent(in) :: foreground
    integer :: job_id
    
    integer :: i
    
    ! Find empty slot or add new job
    job_id = 0
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == 0) then
        job_id = shell%next_job_id
        shell%next_job_id = shell%next_job_id + 1
        shell%jobs(i)%job_id = job_id
        shell%jobs(i)%pgid = pgid
        shell%jobs(i)%command_line = command_line
        shell%jobs(i)%state = JOB_RUNNING
        shell%jobs(i)%foreground = foreground
        shell%jobs(i)%notified = .false.
        allocate(shell%jobs(i)%pids(1))
        shell%jobs(i)%pids(1) = pgid
        shell%jobs(i)%num_pids = 1
        exit
      end if
    end do
    
    if (job_id > 0) shell%num_jobs = shell%num_jobs + 1
  end function
  
  subroutine remove_job(shell, job_id)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    integer :: i
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        if (allocated(shell%jobs(i)%pids)) deallocate(shell%jobs(i)%pids)
        shell%jobs(i)%job_id = 0
        shell%num_jobs = shell%num_jobs - 1
        exit
      end if
    end do
  end subroutine
  
  subroutine update_job_status(shell)
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j
    integer(c_int) :: status
    integer(c_pid_t) :: pid
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0) then
        do j = 1, shell%jobs(i)%num_pids
          pid = c_waitpid(shell%jobs(i)%pids(j), c_loc(status), WNOHANG + WUNTRACED)
          
          if (pid > 0) then
            if (WIFEXITED(status)) then
              shell%jobs(i)%state = JOB_DONE
              shell%last_exit_status = WEXITSTATUS(status)
            else if (WIFSTOPPED(status)) then
              shell%jobs(i)%state = JOB_STOPPED
            end if
          end if
        end do
      end if
    end do
  end subroutine
  
  subroutine notify_job_status(shell)
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0 .and. .not. shell%jobs(i)%notified) then
        if (shell%jobs(i)%state == JOB_DONE) then
          write(output_unit, '(a,i0,a,a)') '[', shell%jobs(i)%job_id, ']  Done                    ', &
                trim(shell%jobs(i)%command_line)
          shell%jobs(i)%notified = .true.
          call remove_job(shell, shell%jobs(i)%job_id)
        else if (shell%jobs(i)%state == JOB_STOPPED) then
          write(output_unit, '(a,i0,a,a)') '[', shell%jobs(i)%job_id, ']  Stopped                 ', &
                trim(shell%jobs(i)%command_line)
          shell%jobs(i)%notified = .true.
        end if
      end if
    end do
  end subroutine
  
  subroutine put_job_foreground(shell, job_id, cont)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    logical, intent(in) :: cont
    
    integer :: i, ret
    integer(c_int) :: status
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        ! Give terminal to job
        ret = c_tcsetpgrp(shell%shell_terminal, shell%jobs(i)%pgid)
        
        ! Continue job if necessary
        if (cont .and. shell%jobs(i)%state == JOB_STOPPED) then
          ret = c_kill(-shell%jobs(i)%pgid, SIGCONT)
          shell%jobs(i)%state = JOB_RUNNING
        end if
        
        ! Wait for job
        shell%jobs(i)%foreground = .true.
        ret = c_waitpid(-shell%jobs(i)%pgid, c_loc(status), WUNTRACED)
        
        ! Take back terminal
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
        
        ! Update status
        if (WIFEXITED(status)) then
          shell%jobs(i)%state = JOB_DONE
          shell%last_exit_status = WEXITSTATUS(status)
          call remove_job(shell, job_id)
        else if (WIFSTOPPED(status)) then
          shell%jobs(i)%state = JOB_STOPPED
          write(output_unit, '(a)') 'Stopped'
        end if
        
        exit
      end if
    end do
  end subroutine
  
  subroutine put_job_background(shell, job_id, cont)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: job_id
    logical, intent(in) :: cont
    
    integer :: i, ret
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id == job_id) then
        shell%jobs(i)%foreground = .false.
        
        if (cont .and. shell%jobs(i)%state == JOB_STOPPED) then
          ret = c_kill(-shell%jobs(i)%pgid, SIGCONT)
          shell%jobs(i)%state = JOB_RUNNING
        end if
        
        exit
      end if
    end do
  end subroutine
  
end module job_control

! ==============================================================================
! Module: parser
! Purpose: Command line parsing and tokenization
! ==============================================================================
module parser
  use shell_types
  use system_interface
  use iso_fortran_env, only: error_unit, input_unit
  implicit none
  
contains
  
  subroutine parse_pipeline(input, pipeline)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline
    
    character(len=len(input)) :: working_input
    integer :: pos, start, cmd_count
    integer :: i
    type(command_t), allocatable :: temp_commands(:)
    logical :: background
    
    allocate(temp_commands(MAX_PIPELINE))
    working_input = input
    cmd_count = 0
    start = 1
    background = .false.
    
    ! Check for background execution (&)
    if (len_trim(working_input) > 0) then
      if (working_input(len_trim(working_input):len_trim(working_input)) == '&') then
        background = .true.
        working_input = working_input(:len_trim(working_input)-1)
      end if
    end if
    
    ! Parse commands and separators
    i = 1
    do while (i <= len_trim(working_input))
      ! Check for operators
      if (i <= len_trim(working_input) - 1) then
        if (working_input(i:i+1) == '&&') then
          cmd_count = cmd_count + 1
          if (cmd_count <= MAX_PIPELINE) then
            call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
            temp_commands(cmd_count)%separator = SEP_AND
          end if
          start = i + 2
          i = i + 2
          cycle
        else if (working_input(i:i+1) == '||') then
          cmd_count = cmd_count + 1
          if (cmd_count <= MAX_PIPELINE) then
            call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
            temp_commands(cmd_count)%separator = SEP_OR
          end if
          start = i + 2
          i = i + 2
          cycle
        end if
      end if
      
      if (working_input(i:i) == '|' .and. &
          (i == 1 .or. working_input(i-1:i-1) /= '|') .and. &
          (i == len_trim(working_input) .or. working_input(i+1:i+1) /= '|')) then
        cmd_count = cmd_count + 1
        if (cmd_count <= MAX_PIPELINE) then
          call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
          temp_commands(cmd_count)%separator = SEP_PIPE
        end if
        start = i + 1
      else if (working_input(i:i) == ';') then
        cmd_count = cmd_count + 1
        if (cmd_count <= MAX_PIPELINE) then
          call parse_single_command(working_input(start:i-1), temp_commands(cmd_count))
          temp_commands(cmd_count)%separator = SEP_SEMICOLON
        end if
        start = i + 1
      end if
      
      i = i + 1
    end do
    
    ! Don't forget the last command
    if (start <= len_trim(working_input)) then
      cmd_count = cmd_count + 1
      if (cmd_count <= MAX_PIPELINE) then
        call parse_single_command(working_input(start:), temp_commands(cmd_count))
        temp_commands(cmd_count)%separator = SEP_NONE
      end if
    end if
    
    ! Set background flag for last command
    if (cmd_count > 0 .and. background) then
      temp_commands(cmd_count)%background = .true.
    end if
    
    ! Copy to pipeline
    pipeline%num_commands = cmd_count
    if (cmd_count > 0) then
      allocate(pipeline%commands(cmd_count))
      do i = 1, cmd_count
        pipeline%commands(i) = temp_commands(i)
      end do
    end if
    
    deallocate(temp_commands)
  end subroutine
  
  subroutine parse_single_command(input, cmd)
    character(len=*), intent(in) :: input
    type(command_t), intent(out) :: cmd
    
    character(len=len(input)) :: working_input
    integer :: pos, end_pos
    character(len=MAX_TOKEN_LEN) :: temp_str
    
    working_input = adjustl(input)
    
    ! Check for here document (<<)
    pos = index(working_input, '<<')
    if (pos > 0) then
      call extract_word(working_input(pos+2:), temp_str)
      cmd%heredoc_delimiter = trim(temp_str)
      working_input = working_input(:pos-1)
    end if
    
    ! Check for 2>&1 (must come before other redirections)
    pos = index(working_input, '2>&1')
    if (pos > 0) then
      cmd%redirect_stderr_to_stdout = .true.
      working_input = working_input(:pos-1) // ' ' // working_input(pos+4:)
    end if
    
    ! Check for error redirection (2>>)
    pos = index(working_input, '2>>')
    if (pos > 0) then
      cmd%append_error = .true.
      call extract_filename(working_input(pos+3:), temp_str)
      cmd%error_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for error redirection (2>)
      pos = index(working_input, '2>')
      if (pos > 0) then
        cmd%append_error = .false.
        call extract_filename(working_input(pos+2:), temp_str)
        cmd%error_file = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for output redirection (>>)
    pos = index(working_input, '>>')
    if (pos > 0) then
      cmd%append_output = .true.
      call extract_filename(working_input(pos+2:), temp_str)
      cmd%output_file = trim(temp_str)
      working_input = working_input(:pos-1)
    else
      ! Check for output redirection (>)
      pos = index(working_input, '>')
      if (pos > 0) then
        cmd%append_output = .false.
        call extract_filename(working_input(pos+1:), temp_str)
        cmd%output_file = trim(temp_str)
        working_input = working_input(:pos-1)
      end if
    end if
    
    ! Check for input redirection (<)
    pos = index(working_input, '<')
    if (pos > 0) then
      call extract_filename(working_input(pos+1:), temp_str)
      cmd%input_file = trim(temp_str)
      working_input = working_input(:pos-1)
    end if
    
    ! Tokenize the remaining command
    call tokenize_with_substitution(trim(working_input), cmd%tokens, cmd%num_tokens)
    
  end subroutine
  
  subroutine extract_filename(input, filename)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: filename
    integer :: i
    
    filename = adjustl(input)
    
    do i = 1, len_trim(filename)
      if (filename(i:i) == ' ' .or. filename(i:i) == char(9)) then
        filename = filename(:i-1)
        exit
      end if
    end do
  end subroutine
  
  subroutine extract_word(input, word)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: word
    integer :: i
    
    word = adjustl(input)
    
    do i = 1, len_trim(word)
      if (word(i:i) == ' ' .or. word(i:i) == char(9) .or. &
          word(i:i) == '<' .or. word(i:i) == '>' .or. &
          word(i:i) == '|' .or. word(i:i) == '&' .or. &
          word(i:i) == ';') then
        word = word(:i-1)
        exit
      end if
    end do
  end subroutine
  
  subroutine tokenize_with_substitution(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens
    
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    character(len=MAX_TOKEN_LEN) :: current_token
    character(len=:), allocatable :: subst_result
    integer :: i, token_len, subst_start, paren_depth
    logical :: in_single_quote, in_double_quote, in_backtick
    character :: ch
    
    allocate(temp_tokens(MAX_TOKENS))
    num_tokens = 0
    current_token = ''
    token_len = 0
    in_single_quote = .false.
    in_double_quote = .false.
    in_backtick = .false.
    
    i = 1
    do while (i <= len_trim(input))
      ch = input(i:i)
      
      ! Handle command substitution $()
      if (i <= len_trim(input) - 1 .and. input(i:i+1) == '$(' &
          .and. .not. in_single_quote) then
        subst_start = i + 2
        i = i + 2
        paren_depth = 1
        
        ! Find matching )
        do while (i <= len_trim(input) .and. paren_depth > 0)
          if (input(i:i) == '(') then
            paren_depth = paren_depth + 1
          else if (input(i:i) == ')') then
            paren_depth = paren_depth - 1
          end if
          i = i + 1
        end do
        
        ! Execute substitution
        subst_result = execute_and_capture(input(subst_start:i-2))
        current_token(token_len+1:token_len+len(subst_result)) = subst_result
        token_len = token_len + len(subst_result)
        
      ! Handle backticks
      else if (ch == '`' .and. .not. in_single_quote) then
        if (in_backtick) then
          ! End of backtick substitution
          subst_result = execute_and_capture(current_token(:token_len))
          current_token = ''
          token_len = 0
          current_token(1:len(subst_result)) = subst_result
          token_len = len(subst_result)
          in_backtick = .false.
        else
          ! Start of backtick substitution
          if (token_len > 0) then
            num_tokens = num_tokens + 1
            temp_tokens(num_tokens) = current_token(:token_len)
            current_token = ''
            token_len = 0
          end if
          in_backtick = .true.
        end if
        i = i + 1
        
      else if (in_backtick) then
        token_len = token_len + 1
        current_token(token_len:token_len) = ch
        i = i + 1
        
      else if (ch == "'" .and. .not. in_double_quote) then
        in_single_quote = .not. in_single_quote
        i = i + 1
        
      else if (ch == '"' .and. .not. in_single_quote) then
        in_double_quote = .not. in_double_quote
        i = i + 1
        
      else if ((ch == ' ' .or. ch == char(9)) .and. &
               .not. in_single_quote .and. .not. in_double_quote) then
        if (token_len > 0) then
          num_tokens = num_tokens + 1
          temp_tokens(num_tokens) = current_token(:token_len)
          current_token = ''
          token_len = 0
        end if
        i = i + 1
        
      else
        token_len = token_len + 1
        current_token(token_len:token_len) = ch
        i = i + 1
      end if
    end do
    
    ! Add last token if any
    if (token_len > 0) then
      num_tokens = num_tokens + 1
      temp_tokens(num_tokens) = current_token(:token_len)
    end if
    
    ! Copy to output array
    if (num_tokens > 0) then
      allocate(character(len=MAX_TOKEN_LEN) :: tokens(num_tokens))
      do i = 1, num_tokens
        tokens(i) = trim(temp_tokens(i))
      end do
    end if
    
    deallocate(temp_tokens)
  end subroutine
  
  subroutine expand_variables(token, expanded, shell)
    character(len=*), intent(in) :: token
    character(len=:), allocatable, intent(out) :: expanded
    type(shell_state_t), intent(in) :: shell
    
    character(len=MAX_TOKEN_LEN) :: result
    integer :: i, j, var_start, brace_depth
    character(len=MAX_TOKEN_LEN) :: var_name
    character(len=:), allocatable :: var_value
    character(len=20) :: pid_str
    
    result = ''
    i = 1
    j = 1
    
    do while (i <= len_trim(token))
      if (token(i:i) == '$' .and. i < len_trim(token)) then
        i = i + 1
        
        ! Check for special variables
        if (token(i:i) == '?') then
          write(result(j:), '(i0)') shell%last_exit_status
          j = j + len_trim(result(j:))
          i = i + 1
        else if (token(i:i) == '$') then
          write(pid_str, '(i0)') c_getpid()
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (token(i:i) == '!') then
          write(pid_str, '(i0)') shell%last_pid
          result(j:j+len_trim(pid_str)-1) = trim(pid_str)
          j = j + len_trim(pid_str)
          i = i + 1
        else if (token(i:i) == '{') then
          ! ${VAR} syntax
          i = i + 1
          var_start = i
          brace_depth = 1
          
          do while (i <= len_trim(token) .and. brace_depth > 0)
            if (token(i:i) == '{') then
              brace_depth = brace_depth + 1
            else if (token(i:i) == '}') then
              brace_depth = brace_depth - 1
            end if
            i = i + 1
          end do
          
          var_name = token(var_start:i-2)
          var_value = get_environment_var(trim(var_name))
          
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len(var_value)-1) = var_value
            j = j + len(var_value)
          end if
        else
          ! Simple $VAR syntax
          var_start = i
          do while (i <= len_trim(token))
            if (.not. (is_alnum(token(i:i)) .or. token(i:i) == '_')) exit
            i = i + 1
          end do
          
          var_name = token(var_start:i-1)
          var_value = get_environment_var(trim(var_name))
          
          if (allocated(var_value) .and. len(var_value) > 0) then
            result(j:j+len(var_value)-1) = var_value
            j = j + len(var_value)
          end if
        end if
      else
        result(j:j) = token(i:i)
        i = i + 1
        j = j + 1
      end if
    end do
    
    expanded = trim(result)
    
  contains
    
    function is_alnum(ch) result(res)
      character, intent(in) :: ch
      logical :: res
      res = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9')
    end function
    
  end subroutine
  
  subroutine read_heredoc(delimiter, content)
    character(len=*), intent(in) :: delimiter
    character(len=:), allocatable, intent(out) :: content
    
    character(len=MAX_TOKEN_LEN) :: line
    character(len=MAX_HEREDOC_LEN) :: buffer
    integer :: iostat, pos
    
    buffer = ''
    pos = 1
    
    write(*, '(a)', advance='no') '> '
    
    do
      read(*, '(a)', iostat=iostat) line
      if (iostat /= 0) exit
      
      if (trim(line) == trim(delimiter)) exit
      
      if (pos > 1) then
        buffer(pos:pos) = char(10)  ! newline
        pos = pos + 1
      end if
      
      buffer(pos:pos+len_trim(line)-1) = trim(line)
      pos = pos + len_trim(line)
      
      write(*, '(a)', advance='no') '> '
    end do
    
    allocate(character(len=pos-1) :: content)
    content = buffer(:pos-1)
  end subroutine
  
end module parser

! ==============================================================================
! Module: builtins (Extended with job control)
! ==============================================================================
module builtins
  use shell_types
  use system_interface
  use job_control
  use iso_fortran_env, only: output_unit, error_unit
  implicit none
  
contains
  
  function is_builtin(cmd_name) result(is_built)
    character(len=*), intent(in) :: cmd_name
    logical :: is_built
    
    is_built = (trim(cmd_name) == 'exit' .or. &
                trim(cmd_name) == 'cd' .or. &
                trim(cmd_name) == 'pwd' .or. &
                trim(cmd_name) == 'export' .or. &
                trim(cmd_name) == 'echo' .or. &
                trim(cmd_name) == 'jobs' .or. &
                trim(cmd_name) == 'fg' .or. &
                trim(cmd_name) == 'bg' .or. &
                trim(cmd_name) == 'source' .or. &
                trim(cmd_name) == '.')
  end function
  
  subroutine execute_builtin(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    select case(trim(cmd%tokens(1)))
    case('exit')
      call builtin_exit(cmd, shell)
    case('cd')
      call builtin_cd(cmd, shell)
    case('pwd')
      call builtin_pwd(cmd, shell)
    case('export')
      call builtin_export(cmd, shell)
    case('echo')
      call builtin_echo(cmd, shell)
    case('jobs')
      call builtin_jobs(cmd, shell)
    case('fg')
      call builtin_fg(cmd, shell)
    case('bg')
      call builtin_bg(cmd, shell)
    case('source', '.')
      call builtin_source(cmd, shell)
    end select
  end subroutine
  
  subroutine builtin_exit(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    shell%running = .false.
    if (cmd%num_tokens > 1) then
      read(cmd%tokens(2), *, iostat=shell%last_exit_status) shell%last_exit_status
    end if
  end subroutine
  
  subroutine builtin_cd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: target_dir
    
    if (cmd%num_tokens == 1) then
      target_dir = get_environment_var('HOME')
    else
      target_dir = trim(cmd%tokens(2))
    end if
    
    if (change_directory(target_dir)) then
      shell%cwd = get_current_directory()
      shell%last_exit_status = 0
    else
      write(error_unit, '(3a)') 'cd: ', trim(target_dir), ': No such file or directory'
      shell%last_exit_status = 1
    end if
  end subroutine
  
  subroutine builtin_pwd(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    write(output_unit, '(a)') trim(shell%cwd)
    shell%last_exit_status = 0
  end subroutine
  
  subroutine builtin_export(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=MAX_TOKEN_LEN) :: var_name, var_value
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
      return
    end if
    
    eq_pos = index(cmd%tokens(2), '=')
    if (eq_pos > 0) then
      var_name = cmd%tokens(2)(:eq_pos-1)
      var_value = cmd%tokens(2)(eq_pos+1:)
      
      if (set_environment_var(trim(var_name), trim(var_value))) then
        shell%last_exit_status = 0
      else
        write(error_unit, '(a)') 'export: failed to set variable'
        shell%last_exit_status = 1
      end if
    else
      write(error_unit, '(a)') 'export: usage: export VAR=value'
      shell%last_exit_status = 1
    end if
  end subroutine
  
  subroutine builtin_echo(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    logical :: first
    
    first = .true.
    do i = 2, cmd%num_tokens
      if (.not. first) write(output_unit, '(a)', advance='no') ' '
      write(output_unit, '(a)', advance='no') trim(cmd%tokens(i))
      first = .false.
    end do
    write(output_unit, '(a)') ''
    
    shell%last_exit_status = 0
  end subroutine
  
  subroutine builtin_jobs(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i
    character(len=20) :: status_str
    
    do i = 1, MAX_JOBS
      if (shell%jobs(i)%job_id > 0) then
        select case(shell%jobs(i)%state)
        case(JOB_RUNNING)
          status_str = 'Running'
        case(JOB_STOPPED)
          status_str = 'Stopped'
        case(JOB_DONE)
          status_str = 'Done'
        end select
        
        write(output_unit, '(a,i0,a,a,a,a)') '[', shell%jobs(i)%job_id, ']  ', &
              status_str, '                 ', trim(shell%jobs(i)%command_line)
      end if
    end do
    
    shell%last_exit_status = 0
  end subroutine
  
  subroutine builtin_fg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Bring most recent job to foreground
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'fg: no current job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'fg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call put_job_foreground(shell, job_id, .true.)
    shell%last_exit_status = 0
  end subroutine
  
  subroutine builtin_bg(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: job_id, iostat, i
    
    if (cmd%num_tokens < 2) then
      ! Continue most recent stopped job in background
      job_id = 0
      do i = MAX_JOBS, 1, -1
        if (shell%jobs(i)%job_id > 0 .and. &
            shell%jobs(i)%state == JOB_STOPPED) then
          job_id = shell%jobs(i)%job_id
          exit
        end if
      end do
      
      if (job_id == 0) then
        write(error_unit, '(a)') 'bg: no stopped job'
        shell%last_exit_status = 1
        return
      end if
    else
      ! Parse job number (handle %n syntax)
      if (cmd%tokens(2)(1:1) == '%') then
        read(cmd%tokens(2)(2:), *, iostat=iostat) job_id
      else
        read(cmd%tokens(2), *, iostat=iostat) job_id
      end if
      
      if (iostat /= 0) then
        write(error_unit, '(a)') 'bg: invalid job id'
        shell%last_exit_status = 1
        return
      end if
    end if
    
    call put_job_background(shell, job_id, .true.)
    shell%last_exit_status = 0
  end subroutine
  
  subroutine builtin_source(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    
    ! Simplified version - would need file reading implementation
    write(error_unit, '(a)') 'source: not yet implemented'
    shell%last_exit_status = 1
  end subroutine
  
end module builtins

! ==============================================================================
! Module: executor (Extended with job control)
! ==============================================================================
module executor
  use shell_types
  use system_interface
  use builtins
  use parser
  use job_control
  use iso_fortran_env, only: error_unit, input_unit
  use iso_c_binding
  implicit none
  
contains
  
  subroutine execute_pipeline(pipeline, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer :: i
    logical :: should_continue
    
    should_continue = .true.
    i = 1
    
    do while (i <= pipeline%num_commands .and. should_continue)
      select case(pipeline%commands(i)%separator)
      case(SEP_PIPE)
        call execute_pipe_chain(pipeline, i, shell, original_input)
        do while (i <= pipeline%num_commands)
          if (pipeline%commands(i)%separator /= SEP_PIPE) exit
          i = i + 1
        end do
        
      case(SEP_SEMICOLON, SEP_NONE)
        call execute_single(pipeline%commands(i), shell, original_input)
        i = i + 1
        
      case(SEP_AND)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status == 0)
        i = i + 1
        
      case(SEP_OR)
        call execute_single(pipeline%commands(i), shell, original_input)
        should_continue = (shell%last_exit_status /= 0)
        i = i + 1
      end select
    end do
  end subroutine
  
  subroutine execute_pipe_chain(pipeline, start_idx, shell, original_input)
    type(pipeline_t), intent(inout) :: pipeline
    integer, intent(in) :: start_idx
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer :: i, pipe_count, end_idx
    integer(c_int), allocatable :: pipefd(:,:)
    integer(c_pid_t), allocatable :: pids(:)
    integer(c_pid_t) :: pgid
    integer(c_int) :: status
    integer :: ret, job_id
    logical :: foreground
    
    ! Count pipes in chain
    pipe_count = 0
    end_idx = start_idx
    do i = start_idx, pipeline%num_commands - 1
      if (pipeline%commands(i)%separator == SEP_PIPE) then
        pipe_count = pipe_count + 1
        end_idx = i + 1
      else
        exit
      end if
    end do
    
    if (pipe_count == 0) then
      call execute_single(pipeline%commands(start_idx), shell, original_input)
      return
    end if
    
    foreground = .not. pipeline%commands(end_idx)%background
    
    allocate(pipefd(2, pipe_count))
    allocate(pids(pipe_count + 1))
    
    ! Create all pipes
    do i = 1, pipe_count
      if (.not. create_pipe(pipefd(1,i), pipefd(2,i))) then
        write(error_unit, '(a)') 'Error: Failed to create pipe'
        shell%last_exit_status = 1
        return
      end if
    end do
    
    pgid = 0
    
    ! Fork all processes
    do i = start_idx, end_idx
      pids(i - start_idx + 1) = c_fork()
      
      if (pids(i - start_idx + 1) == 0) then
        ! Child process
        
        ! Set process group
        if (pgid == 0) pgid = c_getpid()
        ret = c_setpgid(0, pgid)
        
        ! Reset signal handlers
        SIG_DFL = c_null_funptr
        ret = c_signal(SIGINT, SIG_DFL)
        ret = c_signal(SIGTSTP, SIG_DFL)
        ret = c_signal(SIGTTIN, SIG_DFL)
        ret = c_signal(SIGTTOU, SIG_DFL)
        
        ! Set up pipes
        if (i > start_idx) then
          ret = c_dup2(pipefd(1, i - start_idx), STDIN_FD)
        end if
        
        if (i < end_idx) then
          ret = c_dup2(pipefd(2, i - start_idx + 1), STDOUT_FD)
        end if
        
        ! Close all pipe FDs
        do ret = 1, pipe_count
          ret = c_close(pipefd(1, ret))
          ret = c_close(pipefd(2, ret))
        end do
        
        ! Handle here document
        call handle_heredoc(pipeline%commands(i))
        
        ! Expand variables and execute
        call expand_tokens(pipeline%commands(i), shell)
        
        if (is_builtin(pipeline%commands(i)%tokens(1))) then
          call execute_builtin(pipeline%commands(i), shell)
          call c_exit(int(shell%last_exit_status, c_int))
        else
          call setup_redirections(pipeline%commands(i))
          call exec_child(pipeline%commands(i)%tokens, pipeline%commands(i)%num_tokens)
          call c_exit(127)
        end if
      else if (pids(i - start_idx + 1) > 0) then
        ! Parent: set process group
        if (pgid == 0) pgid = pids(1)
        ret = c_setpgid(pids(i - start_idx + 1), pgid)
      end if
    end do
    
    ! Parent: close all pipes
    do i = 1, pipe_count
      ret = c_close(pipefd(1, i))
      ret = c_close(pipefd(2, i))
    end do
    
    ! Add job to job list
    if (.not. foreground) then
      job_id = add_job(shell, pgid, original_input, .false.)
      write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pgid
      shell%last_pid = pgid
    else if (shell%is_interactive) then
      ! Give terminal to job
      ret = c_tcsetpgrp(shell%shell_terminal, pgid)
    end if
    
    ! Wait for all children (if foreground)
    if (foreground) then
      do i = 1, pipe_count + 1
        ret = c_waitpid(pids(i), c_loc(status), WUNTRACED)
      end do
      
      ! Take back terminal
      if (shell%is_interactive) then
        ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
      end if
      
      shell%last_exit_status = WEXITSTATUS(status)
    end if
    
    deallocate(pipefd)
    deallocate(pids)
  end subroutine
  
  subroutine execute_single(cmd, shell, original_input)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    if (cmd%num_tokens == 0) return
    
    ! Handle here document input
    if (allocated(cmd%heredoc_delimiter)) then
      call read_heredoc(cmd%heredoc_delimiter, cmd%heredoc_content)
    end if
    
    ! Expand variables in all tokens
    call expand_tokens(cmd, shell)
    
    ! Check if it's a builtin
    if (is_builtin(cmd%tokens(1))) then
      call execute_builtin(cmd, shell)
    else
      call execute_external(cmd, shell, original_input)
    end if
  end subroutine
  
  subroutine expand_tokens(cmd, shell)
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(in) :: shell
    integer :: i
    character(len=:), allocatable :: expanded
    
    do i = 1, cmd%num_tokens
      call expand_variables(cmd%tokens(i), expanded, shell)
      cmd%tokens(i) = expanded
    end do
  end subroutine
  
  subroutine execute_external(cmd, shell, original_input)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: original_input
    
    integer(c_pid_t) :: pid, pgid
    integer(c_int) :: wait_status
    integer :: ret, job_id
    logical :: foreground
    
    foreground = .not. cmd%background
    pid = c_fork()
    
    if (pid < 0) then
      write(error_unit, '(a)') 'Error: fork failed'
      shell%last_exit_status = 1
    else if (pid == 0) then
      ! Child process
      
      ! Set process group
      pgid = c_getpid()
      ret = c_setpgid(0, pgid)
      
      ! Reset signal handlers
      SIG_DFL = c_null_funptr
      ret = c_signal(SIGINT, SIG_DFL)
      ret = c_signal(SIGTSTP, SIG_DFL)
      ret = c_signal(SIGTTIN, SIG_DFL)
      ret = c_signal(SIGTTOU, SIG_DFL)
      
      ! Handle here document
      call handle_heredoc(cmd)
      
      ! Set up redirections
      call setup_redirections(cmd)
      
      ! Execute
      call exec_child(cmd%tokens, cmd%num_tokens)
      write(error_unit, '(3a)') 'fsh: command not found: ', trim(cmd%tokens(1))
      call c_exit(127)
    else
      ! Parent process
      shell%last_pid = pid
      pgid = pid
      ret = c_setpgid(pid, pgid)
      
      if (foreground) then
        ! Give terminal to child
        if (shell%is_interactive) then
          ret = c_tcsetpgrp(shell%shell_terminal, pgid)
        end if
        
        ! Wait for child
        ret = c_waitpid(pid, c_loc(wait_status), WUNTRACED)
        
        ! Take back terminal
        if (shell%is_interactive) then
          ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
        end if
        
        if (WIFEXITED(wait_status)) then
          shell%last_exit_status = WEXITSTATUS(wait_status)
        else if (WIFSTOPPED(wait_status)) then
          job_id = add_job(shell, pgid, original_input, .true.)
          write(output_unit, '(a)') 'Stopped'
        end if
      else
        ! Background job
        job_id = add_job(shell, pgid, original_input, .false.)
        write(output_unit, '(a,i0,a,i0)') '[', job_id, '] ', pid
      end if
    end if
  end subroutine
  
  subroutine handle_heredoc(cmd)
    type(command_t), intent(in) :: cmd
    integer :: pipefd(2), ret
    integer(c_ssize_t) :: bytes_written
    character(kind=c_char), target :: c_content(MAX_HEREDOC_LEN)
    integer :: i
    
    if (allocated(cmd%heredoc_content)) then
      ! Create pipe for heredoc
      ret = c_pipe(c_loc(pipefd))
      if (ret == 0) then
        ! Convert content to C string
        do i = 1, len(cmd%heredoc_content)
          c_content(i) = cmd%heredoc_content(i:i)
        end do
        c_content(len(cmd%heredoc_content)+1) = c_null_char
        
        ! Write content to pipe
        bytes_written = c_write(pipefd(2), c_loc(c_content), &
                               int(len(cmd%heredoc_content), c_size_t))
        
        ! Close write end and redirect stdin to read end
        ret = c_close(pipefd(2))
        ret = c_dup2(pipefd(1), STDIN_FD)
        ret = c_close(pipefd(1))
      end if
    end if
  end subroutine
  
  subroutine setup_redirections(cmd)
    type(command_t), intent(in) :: cmd
    integer :: fd, ret
    integer :: flags
    
    ! Handle input redirection
    if (allocated(cmd%input_file)) then
      fd = c_open(trim(cmd%input_file)//c_null_char, O_RDONLY, 0)
      if (fd >= 0) then
        ret = c_dup2(fd, STDIN_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open input file: ', trim(cmd%input_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle output redirection
    if (allocated(cmd%output_file)) then
      if (cmd%append_output) then
        flags = ior(ior(O_WRONLY, O_CREAT), O_APPEND)
      else
        flags = ior(ior(O_WRONLY, O_CREAT), O_TRUNC)
      end if
      
      fd = c_open(trim(cmd%output_file)//c_null_char, flags, int(o'644', c_int))
      if (fd >= 0) then
        ret = c_dup2(fd, STDOUT_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open output file: ', trim(cmd%output_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle error redirection
    if (allocated(cmd%error_file)) then
      if (cmd%append_error) then
        flags = ior(ior(O_WRONLY, O_CREAT), O_APPEND)
      else
        flags = ior(ior(O_WRONLY, O_CREAT), O_TRUNC)
      end if
      
      fd = c_open(trim(cmd%error_file)//c_null_char, flags, int(o'644', c_int))
      if (fd >= 0) then
        ret = c_dup2(fd, STDERR_FD)
        ret = c_close(fd)
      else
        write(error_unit, '(3a)') 'Cannot open error file: ', trim(cmd%error_file)
        call c_exit(1)
      end if
    end if
    
    ! Handle 2>&1
    if (cmd%redirect_stderr_to_stdout) then
      ret = c_dup2(STDOUT_FD, STDERR_FD)
    end if
  end subroutine
  
  subroutine exec_child(tokens, num_tokens)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    
    type(c_ptr) :: argv(num_tokens + 1)
    character(kind=c_char), target :: c_tokens(num_tokens, MAX_TOKEN_LEN+1)
    integer :: i, j
    integer :: ret
    
    ! Convert tokens to C strings
    do i = 1, num_tokens
      do j = 1, len_trim(tokens(i))
        c_tokens(i, j) = tokens(i)(j:j)
      end do
      c_tokens(i, len_trim(tokens(i)) + 1) = c_null_char
      argv(i) = c_loc(c_tokens(i, 1))
    end do
    argv(num_tokens + 1) = c_null_ptr
    
    ! Execute the command
    ret = c_execvp(argv(1), c_loc(argv))
  end subroutine
  
end module executor

! ==============================================================================
! Main Program
! ==============================================================================
program fortran_shell
  use shell_types
  use system_interface
  use signal_handler
  use parser
  use executor
  use job_control
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none
  
  type(shell_state_t) :: shell
  type(pipeline_t) :: pipeline
  character(len=1024) :: input_line
  integer :: iostat, i
  
  ! Initialize shell state
  call initialize_shell(shell)
  
  ! Setup signal handlers if interactive
  if (shell%is_interactive) then
    call setup_signal_handlers()
  end if
  
  ! Main REPL loop
  do while (shell%running)
    ! Update job status
    if (shell%is_interactive) then
      call update_job_status(shell)
      call notify_job_status(shell)
    end if
    
    ! Print prompt
    write(output_unit, '(a,a,a,a,a)', advance='no') &
      trim(shell%username), '@', trim(shell%hostname), ' :: '
    flush(output_unit)
    
    ! Read input
    read(input_unit, '(a)', iostat=iostat) input_line
    
    ! Check for EOF (Ctrl-D)
    if (iostat /= 0) then
      write(output_unit, '(a)') ''
      exit
    end if
    
    ! Skip empty lines
    if (len_trim(input_line) == 0) cycle
    
    ! Parse pipeline
    call parse_pipeline(trim(input_line), pipeline)
    
    ! Execute pipeline
    if (pipeline%num_commands > 0) then
      call execute_pipeline(pipeline, shell, trim(input_line))
    end if
    
    ! Clean up pipeline
    if (allocated(pipeline%commands)) then
      do i = 1, pipeline%num_commands
        if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
        if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
        if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
        if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
        if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
        if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
      end do
      deallocate(pipeline%commands)
    end if
  end do
  
  write(output_unit, '(a)') 'Goodbye!'
  
contains
  
  subroutine initialize_shell(shell)
    type(shell_state_t), intent(out) :: shell
    character(len=:), allocatable :: temp
    character(kind=c_char) :: c_hostname(256)
    integer :: ret, i
    
    ! Get username
    temp = get_environment_var('USER')
    if (len(temp) > 0) then
      shell%username = temp
    else
      shell%username = 'user'
    end if
    
    ! Get hostname
    ret = c_gethostname(c_loc(c_hostname), 256_c_size_t)
    if (ret == 0) then
      shell%hostname = ''
      do i = 1, 256
        if (c_hostname(i) == c_null_char) exit
        shell%hostname(i:i) = c_hostname(i)
      end do
    else
      shell%hostname = 'localhost'
    end if
    
    ! Get current directory
    shell%cwd = get_current_directory()
    
    ! Check if shell is interactive
    shell%is_interactive = (c_isatty(STDIN_FD) /= 0)
    
    ! Setup job control if interactive
    if (shell%is_interactive) then
      shell%shell_pgid = c_getpid()
      ret = c_setpgid(shell%shell_pgid, shell%shell_pgid)
      shell%shell_terminal = STDIN_FD
      ret = c_tcsetpgrp(shell%shell_terminal, shell%shell_pgid)
    end if
    
    ! Initialize other fields
    shell%last_exit_status = 0
    shell%last_pid = 0
    shell%running = .true.
    shell%num_jobs = 0
    shell%next_job_id = 1
    
    ! Initialize jobs array
    do i = 1, MAX_JOBS
      shell%jobs(i)%job_id = 0
    end do
  end subroutine
  
end program fortran_shell
