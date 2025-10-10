! ==============================================================================
! Module: evaluator_simple_real
! Purpose: Simplified real evaluator with basic built-ins and system execution
! ==============================================================================
module evaluator_simple_real
  use ast_types_enhanced
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit, input_unit
  use iso_c_binding
  implicit none

  ! Glob type for pattern matching
  type, bind(C) :: glob_t
    integer(c_size_t) :: gl_pathc
    type(c_ptr) :: gl_pathv
    integer(c_size_t) :: gl_offs
  end type glob_t

  ! C interface for system call
  interface
    function c_system(command) bind(C, name="system")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: command
      integer(c_int) :: c_system
    end function c_system

    function c_chdir(path) bind(C, name="chdir")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: path
      integer(c_int) :: c_chdir
    end function c_chdir

    function c_getcwd(buf, size) bind(C, name="getcwd")
      use iso_c_binding
      character(kind=c_char), dimension(*) :: buf
      integer(c_size_t), value :: size
      type(c_ptr) :: c_getcwd
    end function c_getcwd

    function c_glob(pattern, flags, errfunc, pglob) bind(C, name="glob")
      use iso_c_binding
      import :: glob_t
      character(kind=c_char), dimension(*), intent(in) :: pattern
      integer(c_int), value :: flags
      type(c_funptr), value :: errfunc
      type(glob_t), intent(inout) :: pglob
      integer(c_int) :: c_glob
    end function c_glob

    subroutine c_globfree(pglob) bind(C, name="globfree")
      use iso_c_binding
      import :: glob_t
      type(glob_t), intent(inout) :: pglob
    end subroutine c_globfree

    function c_open(pathname, flags, mode) bind(C, name="open")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      integer(c_int), value :: flags
      integer(c_int), value :: mode
      integer(c_int) :: c_open
    end function c_open

    function c_close(fd) bind(C, name="close")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_close
    end function c_close

    function c_dup(fd) bind(C, name="dup")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_dup
    end function c_dup

    function c_dup2(oldfd, newfd) bind(C, name="dup2")
      use iso_c_binding
      integer(c_int), value :: oldfd
      integer(c_int), value :: newfd
      integer(c_int) :: c_dup2
    end function c_dup2
  end interface

  ! Glob flags (Linux values)
  integer(c_int), parameter :: GLOB_ERR = 1
  integer(c_int), parameter :: GLOB_MARK = 2
  integer(c_int), parameter :: GLOB_NOSORT = 4
  integer(c_int), parameter :: GLOB_NOCHECK = 16

  ! File open flags (Linux values)
  integer(c_int), parameter :: O_RDONLY = 0
  integer(c_int), parameter :: O_WRONLY = 1
  integer(c_int), parameter :: O_RDWR = 2
  integer(c_int), parameter :: O_CREAT = 64
  integer(c_int), parameter :: O_TRUNC = 512
  integer(c_int), parameter :: O_APPEND = 1024

  ! Execution context
  type :: execution_context_t
    type(shell_state_t), pointer :: shell => null()
    type(shell_var_t), allocatable :: local_vars(:)
    integer :: local_var_count = 0
    logical :: break_requested = .false.
    integer :: break_levels = 0
    logical :: continue_requested = .false.
    integer :: continue_levels = 0
    logical :: return_requested = .false.
    integer :: return_value = 0
  contains
    procedure :: init => context_init
    procedure :: destroy => context_destroy
    procedure :: set_var => context_set_var
    procedure :: get_var => context_get_var
  end type execution_context_t

  ! Simple real evaluator
  type :: evaluator_simple_real_t
    type(execution_context_t) :: context
  contains
    procedure :: init => evaluator_init
    procedure :: eval => evaluator_eval
    procedure :: eval_node => evaluator_eval_node
    procedure :: eval_command => evaluator_eval_command
    procedure :: eval_pipeline => evaluator_eval_pipeline
    procedure :: eval_for_loop => evaluator_eval_for_loop
    procedure :: eval_while_loop => evaluator_eval_while_loop
    procedure :: eval_if_statement => evaluator_eval_if_statement
    procedure :: eval_break => evaluator_eval_break
    procedure :: eval_continue => evaluator_eval_continue
    procedure :: eval_word => evaluator_eval_word
    procedure :: eval_variable => evaluator_eval_variable
    procedure :: eval_command_subst => evaluator_eval_command_subst
    procedure :: has_glob_pattern => evaluator_has_glob_pattern
    procedure :: expand_glob => evaluator_expand_glob
    procedure :: destroy => evaluator_destroy
  end type evaluator_simple_real_t

contains

  ! Initialize context
  subroutine context_init(self, shell)
    class(execution_context_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    self%shell => shell
    self%local_var_count = 0
    self%break_requested = .false.
    self%break_levels = 0
    self%continue_requested = .false.
    self%continue_levels = 0
    self%return_requested = .false.
    self%return_value = 0

    if (.not. allocated(self%local_vars)) then
      allocate(self%local_vars(50))
    end if
  end subroutine context_init

  ! Destroy context
  subroutine context_destroy(self)
    class(execution_context_t), intent(inout) :: self

    if (allocated(self%local_vars)) deallocate(self%local_vars)
    self%shell => null()
  end subroutine context_destroy

  ! Set variable
  subroutine context_set_var(self, name, value)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    ! Set in local context
    do i = 1, self%local_var_count
      if (trim(self%local_vars(i)%name) == trim(name)) then
        self%local_vars(i)%value = value
        return
      end if
    end do

    ! Add new variable
    if (self%local_var_count < size(self%local_vars)) then
      self%local_var_count = self%local_var_count + 1
      self%local_vars(self%local_var_count)%name = name
      self%local_vars(self%local_var_count)%value = value
    end if

    ! Also update shell variables if available
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (trim(self%shell%variables(i)%name) == trim(name)) then
          self%shell%variables(i)%value = value
          return
        end if
      end do
      ! Add to shell if not found
      if (self%shell%num_variables < size(self%shell%variables)) then
        self%shell%num_variables = self%shell%num_variables + 1
        self%shell%variables(self%shell%num_variables)%name = name
        self%shell%variables(self%shell%num_variables)%value = value
      end if
    end if
  end subroutine context_set_var

  ! Get variable
  function context_get_var(self, name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: name
    character(:), allocatable :: value
    integer :: i

    ! Check local variables
    do i = 1, self%local_var_count
      if (trim(self%local_vars(i)%name) == trim(name)) then
        value = trim(self%local_vars(i)%value)
        return
      end if
    end do

    ! Check shell variables
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (trim(self%shell%variables(i)%name) == trim(name)) then
          value = trim(self%shell%variables(i)%value)
          return
        end if
      end do
    end if

    ! Check environment
    call get_environment_variable(name, value)
    if (.not. allocated(value)) value = ''
  end function context_get_var

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main eval
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(script_node_t), intent(in) :: ast
    integer :: exit_code
    integer :: i

    exit_code = 0

    if (.not. allocated(ast%statements)) return

    do i = 1, ast%num_statements
      if (associated(ast%statements(i)%ptr)) then
        exit_code = self%eval_node(ast%statements(i)%ptr)
        if (self%context%return_requested) then
          exit_code = self%context%return_value
          exit
        end if
      end if
    end do
  end function evaluator_eval

  ! Eval node
  recursive function evaluator_eval_node(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    integer :: exit_code
    type(command_node_t), pointer :: cmd_ptr
    type(pipeline_node_t), pointer :: pipe_ptr
    type(for_node_t), pointer :: for_ptr
    type(while_node_t), pointer :: while_ptr
    type(if_node_t), pointer :: if_ptr
    type(break_node_t), pointer :: break_ptr
    type(continue_node_t), pointer :: continue_ptr

    exit_code = 0
    if (.not. associated(node)) return

    select type(node)
    type is (command_node_t)
      ! Create pointer to preserve allocated arrays
      cmd_ptr => node
      exit_code = self%eval_command(cmd_ptr)

    type is (pipeline_node_t)
      pipe_ptr => node
      exit_code = self%eval_pipeline(pipe_ptr)

    type is (for_node_t)
      for_ptr => node
      exit_code = self%eval_for_loop(for_ptr)

    type is (while_node_t)
      while_ptr => node
      exit_code = self%eval_while_loop(while_ptr)

    type is (if_node_t)
      if_ptr => node
      exit_code = self%eval_if_statement(if_ptr)

    type is (break_node_t)
      break_ptr => node
      exit_code = self%eval_break(break_ptr)

    type is (continue_node_t)
      continue_ptr => node
      exit_code = self%eval_continue(continue_ptr)

    class default
      exit_code = 127
    end select
  end function evaluator_eval_node

  ! Evaluate command - THE KEY FUNCTION!
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(command_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(1024) :: cmd_str
    character(256) :: word_value
    character(:), allocatable :: first_word, expanded_word
    integer :: i, j
    character(kind=c_char, len=256) :: c_cmd
    character(256) :: cwd_buffer
    integer(c_int) :: status
    type(c_ptr) :: ptr

    ! Redirection handling variables
    integer(c_int) :: saved_stdin, saved_stdout, saved_stderr
    integer(c_int) :: new_fd, flags, ret
    logical :: has_redirections
    character(256) :: redir_file
    type(redirection_node_t), pointer :: redir

    exit_code = 0

    if (.not. allocated(node%words) .or. node%num_words == 0) return

    ! Check if we have redirections
    has_redirections = allocated(node%redirections) .and. node%num_redirections > 0

    ! Save current file descriptors if needed
    if (has_redirections) then
      saved_stdin = c_dup(0_c_int)
      saved_stdout = c_dup(1_c_int)
      saved_stderr = c_dup(2_c_int)

      ! Apply redirections
      do j = 1, node%num_redirections
        if (associated(node%redirections(j)%ptr)) then
          select type(r => node%redirections(j)%ptr)
          type is (redirection_node_t)
            ! Get the target filename
            if (allocated(r%target)) then
              select type(t => r%target)
              type is (word_node_t)
                redir_file = trim(t%text) // c_null_char

                ! Open file based on redirection type
                select case(r%redirect_type)
                case(1)  ! Input redirection (<)
                  new_fd = c_open(redir_file, O_RDONLY, 0_c_int)
                  if (new_fd >= 0) then
                    ret = c_dup2(new_fd, 0_c_int)
                    ret = c_close(new_fd)
                  end if

                case(2)  ! Output redirection (>)
                  flags = ior(O_WRONLY, ior(O_CREAT, O_TRUNC))
                  new_fd = c_open(redir_file, flags, int(o'644', c_int))
                  if (new_fd >= 0) then
                    ret = c_dup2(new_fd, 1_c_int)
                    ret = c_close(new_fd)
                  end if

                case(3)  ! Append redirection (>>)
                  flags = ior(O_WRONLY, ior(O_CREAT, O_APPEND))
                  new_fd = c_open(redir_file, flags, int(o'644', c_int))
                  if (new_fd >= 0) then
                    ret = c_dup2(new_fd, 1_c_int)
                    ret = c_close(new_fd)
                  end if
                end select
              end select
            end if
          end select
        end if
      end do
    end if

    ! Get first word to check for built-ins
    if (associated(node%words(1)%ptr)) then
      first_word = self%eval_word(node%words(1)%ptr)
    else
      if (has_redirections) then
        ! Restore file descriptors
        ret = c_dup2(saved_stdin, 0_c_int)
        ret = c_dup2(saved_stdout, 1_c_int)
        ret = c_dup2(saved_stderr, 2_c_int)
        ret = c_close(saved_stdin)
        ret = c_close(saved_stdout)
        ret = c_close(saved_stderr)
      end if
      return
    end if

    ! Handle simple built-ins
    select case(trim(first_word))
    case('echo')
      ! Build echo arguments with proper spacing
      cmd_str = ''
      do i = 2, node%num_words
        if (associated(node%words(i)%ptr)) then
          expanded_word = self%eval_word(node%words(i)%ptr)
          if (i == 2) then
            cmd_str = trim(expanded_word)
          else
            cmd_str = cmd_str(1:len_trim(cmd_str)) // ' ' // trim(expanded_word)
          end if
        end if
      end do
      write(output_unit, '(a)') trim(cmd_str)
      exit_code = 0

    case('pwd')
      ! Get current directory
      cwd_buffer = ''  ! Initialize buffer
      c_cmd = c_null_char
      ptr = c_getcwd(c_cmd, 256_c_size_t)
      if (c_associated(ptr)) then
        ! Convert C string to Fortran
        do i = 1, 256
          if (c_cmd(i:i) == c_null_char) then
            cwd_buffer = cwd_buffer(1:i-1)  ! Trim to actual length
            exit
          end if
          cwd_buffer(i:i) = c_cmd(i:i)
        end do
        write(output_unit, '(a)') trim(cwd_buffer)
        exit_code = 0
      else
        exit_code = 1
      end if

    case('cd')
      ! Change directory
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        c_cmd = trim(expanded_word) // c_null_char
        status = c_chdir(c_cmd)
        exit_code = abs(status)
        ! Update shell cwd if successful
        if (exit_code == 0 .and. associated(self%context%shell)) then
          ptr = c_getcwd(c_cmd, 256_c_size_t)
          if (c_associated(ptr)) then
            do i = 1, 256
              if (c_cmd(i:i) == c_null_char) exit
              self%context%shell%cwd(i:i) = c_cmd(i:i)
            end do
          end if
        end if
      else
        ! cd with no args goes home
        call get_environment_variable('HOME', word_value)
        c_cmd = trim(word_value) // c_null_char
        status = c_chdir(c_cmd)
        exit_code = abs(status)
      end if

    case('exit')
      ! Exit shell - TODO: integrate with main shell running state
      ! if (associated(self%context%shell)) then
      !   self%context%shell%running = .false.
      ! end if
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        read(expanded_word, *, iostat=status) exit_code
        if (status /= 0) exit_code = 0
      else
        exit_code = 0
      end if

    case('export')
      ! Export variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Look for = in the word
        i = index(expanded_word, '=')
        if (i > 1) then
          ! VAR=value format
          call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
          call setenv(expanded_word(1:i-1), expanded_word(i+1:), 1)
        end if
      end if
      exit_code = 0

    case('set')
      ! Set or show shell variables
      if (node%num_words == 1) then
        ! Show all variables
        if (associated(self%context%shell)) then
          do i = 1, self%context%shell%num_variables
            write(output_unit, '(3a)') trim(self%context%shell%variables(i)%name), &
                                       '=', trim(self%context%shell%variables(i)%value)
          end do
        end if
      else if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Look for = in the word
        i = index(expanded_word, '=')
        if (i > 1) then
          ! VAR=value format - set variable
          call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
        end if
      end if
      exit_code = 0

    case('declare')
      ! Declare variable (similar to set for now)
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Look for = in the word
        i = index(expanded_word, '=')
        if (i > 1) then
          ! VAR=value format
          call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
        else
          ! Just declare with empty value
          call self%context%set_var(trim(expanded_word), '')
        end if
      end if
      exit_code = 0

    case('true')
      exit_code = 0

    case('false')
      exit_code = 1

    case('test', '[')
      ! Basic test command
      if (node%num_words >= 3) then
        if (associated(node%words(2)%ptr)) then
          expanded_word = self%eval_word(node%words(2)%ptr)
          select case(trim(expanded_word))
          case('-f')
            ! Test file exists
            if (node%num_words >= 3 .and. associated(node%words(3)%ptr)) then
              expanded_word = self%eval_word(node%words(3)%ptr)
              block
                logical :: file_exists
                inquire(file=trim(expanded_word), exist=file_exists)
                if (file_exists) then
                  exit_code = 0
                else
                  exit_code = 1
                end if
              end block
            end if
          case('-d')
            ! Test directory (simplified)
            exit_code = 1
          case('-z')
            ! Test empty string
            if (node%num_words >= 3 .and. associated(node%words(3)%ptr)) then
              expanded_word = self%eval_word(node%words(3)%ptr)
              if (len_trim(expanded_word) == 0) then
                exit_code = 0
              else
                exit_code = 1
              end if
            end if
          case default
            exit_code = 1
          end select
        end if
      else
        exit_code = 1
      end if

    case('unset')
      ! Unset variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Remove from context variables
        if (associated(self%context%shell)) then
          do i = 1, self%context%shell%num_variables
            if (trim(self%context%shell%variables(i)%name) == trim(expanded_word)) then
              ! Shift remaining variables up
              do j = i, self%context%shell%num_variables - 1
                self%context%shell%variables(j) = self%context%shell%variables(j+1)
              end do
              self%context%shell%num_variables = self%context%shell%num_variables - 1
              exit
            end if
          end do
        end if
      end if
      exit_code = 0

    case('read')
      ! Read input into variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Read a line from stdin
        read(input_unit, '(a)', iostat=status) word_value
        if (status == 0) then
          call self%context%set_var(trim(expanded_word), trim(word_value))
          exit_code = 0
        else
          exit_code = 1
        end if
      else
        exit_code = 1
      end if

    case('source', '.')
      ! Source/execute commands from file
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        block
          logical :: file_exists
          character(4096) :: line
          integer :: unit_num, io_stat

          inquire(file=trim(expanded_word), exist=file_exists)
          if (file_exists) then
            open(newunit=unit_num, file=trim(expanded_word), status='old', &
                 action='read', iostat=io_stat)
            if (io_stat == 0) then
              do
                read(unit_num, '(a)', iostat=io_stat) line
                if (io_stat /= 0) exit
                ! Execute each line as a command
                ! Note: This is simplified - should use full parsing
                c_cmd = trim(line) // c_null_char
                status = c_system(c_cmd)
              end do
              close(unit_num)
              exit_code = 0
            else
              exit_code = 1
            end if
          else
            write(error_unit, *) 'source: cannot read: ', trim(expanded_word)
            exit_code = 1
          end if
        end block
      else
        exit_code = 1
      end if

    case('alias')
      ! Alias command (simplified - just show message for now)
      if (node%num_words >= 2) then
        ! Would need to implement alias storage in shell context
        write(output_unit, *) 'alias: not fully implemented yet'
      else
        ! Show all aliases (none for now)
        write(output_unit, *) 'No aliases defined'
      end if
      exit_code = 0

    case('type')
      ! Show type of command
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        select case(trim(expanded_word))
        case('echo', 'pwd', 'cd', 'exit', 'export', 'set', 'declare', 'true', 'false', &
             'test', '[', 'unset', 'read', 'source', '.', 'alias', 'type')
          write(output_unit, '(2a)') trim(expanded_word), ' is a shell builtin'
        case default
          ! Check if it's an external command
          c_cmd = 'which ' // trim(expanded_word) // ' 2>/dev/null' // c_null_char
          status = c_system(c_cmd)
          if (status == 0) then
            write(output_unit, '(3a)') trim(expanded_word), ' is ', trim(expanded_word)
          else
            write(output_unit, '(3a)') 'bash: type: ', trim(expanded_word), ': not found'
            exit_code = 1
          end if
        end select
      else
        exit_code = 1
      end if

    case default
      ! External command - build full command line
      cmd_str = trim(first_word)
      do i = 2, node%num_words
        if (associated(node%words(i)%ptr)) then
          expanded_word = self%eval_word(node%words(i)%ptr)
          cmd_str = trim(cmd_str) // ' ' // trim(expanded_word)
        end if
      end do

      ! Execute via system()
      c_cmd = trim(cmd_str) // c_null_char
      status = c_system(c_cmd)

      ! Extract exit code
      if (status < 0) then
        exit_code = 127
      else
        exit_code = status / 256
      end if
    end select

    ! Restore file descriptors if they were redirected
    if (has_redirections) then
      ret = c_dup2(saved_stdin, 0_c_int)
      ret = c_dup2(saved_stdout, 1_c_int)
      ret = c_dup2(saved_stderr, 2_c_int)
      ret = c_close(saved_stdin)
      ret = c_close(saved_stdout)
      ret = c_close(saved_stderr)
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if

  contains
    subroutine setenv(name, value, overwrite)
      character(*), intent(in) :: name, value
      integer, intent(in) :: overwrite
      ! Simple setenv - would need proper implementation
      call execute_command_line('export ' // trim(name) // '=' // trim(value), exitstat=status)
    end subroutine setenv

  end function evaluator_eval_command

  ! Eval pipeline - chain commands with pipes
  function evaluator_eval_pipeline(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(pipeline_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(4096) :: pipeline_cmd
    character(1024) :: cmd_str
    integer :: i, j
    character(:), allocatable :: word_value
    integer(c_int) :: status

    exit_code = 0
    pipeline_cmd = ''

    ! Build the pipeline command string
    do i = 1, node%num_commands
      if (associated(node%commands(i)%ptr)) then
        ! Build this command's string
        cmd_str = ''

        select type(cmd => node%commands(i)%ptr)
        type is (command_node_t)
          if (allocated(cmd%words)) then
            do j = 1, cmd%num_words
              if (associated(cmd%words(j)%ptr)) then
                word_value = self%eval_word(cmd%words(j)%ptr)
                if (j > 1) then
                  cmd_str = trim(cmd_str) // ' ' // trim(word_value)
                else
                  cmd_str = trim(word_value)
                end if
              end if
            end do
          end if
        end select

        ! Add to pipeline
        if (i > 1) then
          pipeline_cmd = trim(pipeline_cmd) // ' | ' // trim(cmd_str)
        else
          pipeline_cmd = trim(cmd_str)
        end if
      end if
    end do

    ! Execute the pipeline
    if (len_trim(pipeline_cmd) > 0) then
      status = c_system(trim(pipeline_cmd) // c_null_char)

      if (status < 0) then
        exit_code = 127
      else
        exit_code = status / 256
      end if
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_pipeline

  ! Eval for loop
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(for_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: i, j, k
    character(:), allocatable :: item_value
    character(256), allocatable :: glob_matches(:)
    integer :: match_count
    logical :: glob_success

    exit_code = 0

    if (allocated(node%word_list)) then
      do i = 1, node%num_words
        if (associated(node%word_list(i)%ptr)) then
          item_value = self%eval_word(node%word_list(i)%ptr)

          ! Check if word contains glob patterns
          if (self%has_glob_pattern(item_value)) then
            ! Expand glob pattern
            glob_success = self%expand_glob(item_value, glob_matches, match_count)
            if (glob_success .and. match_count > 0) then
              ! Process each glob match
              do k = 1, match_count
                call self%context%set_var(trim(node%variable), trim(glob_matches(k)))

                if (allocated(node%body)) then
                  do j = 1, node%num_body
                    if (associated(node%body(j)%ptr)) then
                      exit_code = self%eval_node(node%body(j)%ptr)

                      if (self%context%break_requested) then
                        if (self%context%break_levels <= 1) then
                          self%context%break_requested = .false.
                          self%context%break_levels = 0
                          return
                        else
                          self%context%break_levels = self%context%break_levels - 1
                          return
                        end if
                      end if

                      if (self%context%continue_requested) then
                        if (self%context%continue_levels <= 1) then
                          self%context%continue_requested = .false.
                          self%context%continue_levels = 0
                          exit
                        else
                          self%context%continue_levels = self%context%continue_levels - 1
                          return
                        end if
                      end if
                    end if
                  end do
                end if
              end do

              if (allocated(glob_matches)) deallocate(glob_matches)
            else
              ! No glob expansion - use original value
              call self%context%set_var(trim(node%variable), item_value)

              if (allocated(node%body)) then
                do j = 1, node%num_body
                  if (associated(node%body(j)%ptr)) then
                    exit_code = self%eval_node(node%body(j)%ptr)

                    if (self%context%break_requested) then
                      if (self%context%break_levels <= 1) then
                        self%context%break_requested = .false.
                        self%context%break_levels = 0
                        return
                      else
                        self%context%break_levels = self%context%break_levels - 1
                        return
                      end if
                    end if

                    if (self%context%continue_requested) then
                      if (self%context%continue_levels <= 1) then
                        self%context%continue_requested = .false.
                        self%context%continue_levels = 0
                        exit
                      else
                        self%context%continue_levels = self%context%continue_levels - 1
                        return
                      end if
                    end if
                  end if
                end do
              end if
            end if
          else
            ! No glob pattern - use original value
            call self%context%set_var(trim(node%variable), item_value)

            if (allocated(node%body)) then
              do j = 1, node%num_body
                if (associated(node%body(j)%ptr)) then
                  exit_code = self%eval_node(node%body(j)%ptr)

                if (self%context%break_requested) then
                  if (self%context%break_levels <= 1) then
                    self%context%break_requested = .false.
                    self%context%break_levels = 0
                    return
                  else
                    self%context%break_levels = self%context%break_levels - 1
                    return
                  end if
                end if

                if (self%context%continue_requested) then
                  if (self%context%continue_levels <= 1) then
                    self%context%continue_requested = .false.
                    self%context%continue_levels = 0
                    exit
                  else
                    self%context%continue_levels = self%context%continue_levels - 1
                    return
                  end if
                end if
              end if
            end do
            end if
          end if
        end if
      end do
    end if
  end function evaluator_eval_for_loop

  ! Eval while loop
  function evaluator_eval_while_loop(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(while_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    do while (.true.)
      if (associated(node%condition%ptr)) then
        exit_code = self%eval_node(node%condition%ptr)
        if (exit_code /= 0) exit
      end if

      if (allocated(node%body)) then
        do j = 1, node%num_body
          if (associated(node%body(j)%ptr)) then
            exit_code = self%eval_node(node%body(j)%ptr)

            if (self%context%break_requested) then
              if (self%context%break_levels <= 1) then
                self%context%break_requested = .false.
                self%context%break_levels = 0
                return
              else
                self%context%break_levels = self%context%break_levels - 1
                return
              end if
            end if

            if (self%context%continue_requested) then
              if (self%context%continue_levels <= 1) then
                self%context%continue_requested = .false.
                self%context%continue_levels = 0
                exit
              else
                self%context%continue_levels = self%context%continue_levels - 1
                return
              end if
            end if
          end if
        end do
      end if
    end do
  end function evaluator_eval_while_loop

  ! Eval if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(if_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    if (associated(node%condition%ptr)) then
      exit_code = self%eval_node(node%condition%ptr)
    end if

    if (exit_code == 0) then
      if (allocated(node%then_branch)) then
        do j = 1, node%num_then
          if (associated(node%then_branch(j)%ptr)) then
            exit_code = self%eval_node(node%then_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    else
      if (allocated(node%else_branch)) then
        do j = 1, node%num_else
          if (associated(node%else_branch(j)%ptr)) then
            exit_code = self%eval_node(node%else_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    end if
  end function evaluator_eval_if_statement

  ! Eval break
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(break_node_t), pointer, intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    self%context%break_levels = node%levels
    exit_code = 0
  end function evaluator_eval_break

  ! Eval continue
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(continue_node_t), pointer, intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    self%context%continue_levels = node%levels
    exit_code = 0
  end function evaluator_eval_continue

  ! Eval word
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    type(variable_node_t), pointer :: var_ptr
    type(command_subst_node_t), pointer :: subst_ptr
    character(4096) :: output_buffer
    integer :: exit_code

    select type(node)
    type is (word_node_t)
      result = node%text

    type is (variable_node_t)
      var_ptr => node
      result = self%eval_variable(var_ptr)

    type is (command_subst_node_t)
      subst_ptr => node
      result = self%eval_command_subst(subst_ptr)

    class default
      result = ''
    end select
  end function evaluator_eval_word

  ! Eval variable
  function evaluator_eval_variable(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(variable_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(16) :: tmp

    ! Handle special variables
    select case(trim(node%name))
    case('?')
      if (associated(self%context%shell)) then
        write(tmp, '(i0)') self%context%shell%last_exit_status
        result = trim(tmp)
      else
        result = '0'
      end if

    case('#')
      result = '0'

    case('$')
      call get_environment_variable('PPID', result)
      if (.not. allocated(result)) result = '0'

    case default
      result = self%context%get_var(trim(node%name))
    end select
  end function evaluator_eval_variable

  ! Eval command substitution - execute command and capture output
  function evaluator_eval_command_subst(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(command_subst_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(4096) :: cmd_str
    character(256) :: temp_file
    integer :: unit_num, ios, i
    character(4096) :: line
    character(:), allocatable :: output
    integer(c_int) :: status

    ! Build command string from the command node
    cmd_str = ''
    if (associated(node%command%ptr)) then
      select type(cmd => node%command%ptr)
      type is (command_node_t)
        if (allocated(cmd%words) .and. cmd%num_words > 0) then
          ! Build command from words
          do i = 1, cmd%num_words
            if (associated(cmd%words(i)%ptr)) then
              select type(w => cmd%words(i)%ptr)
              type is (word_node_t)
                if (i > 1) then
                  cmd_str = trim(cmd_str) // ' ' // trim(w%text)
                else
                  cmd_str = trim(w%text)
                end if
              end select
            end if
          end do
        end if
      end select
    end if

    ! Execute command and capture output using a temp file
    ! Generate temp filename
    write(temp_file, '(a,i0)') '/tmp/fortsh_subst_', getpid()

    ! Execute command with output redirection
    cmd_str = trim(cmd_str) // ' > ' // trim(temp_file) // ' 2>&1'
    status = c_system(trim(cmd_str) // c_null_char)

    ! Read the output from temp file
    open(newunit=unit_num, file=trim(temp_file), status='old', &
         action='read', iostat=ios)
    if (ios == 0) then
      output = ''
      do
        read(unit_num, '(a)', iostat=ios) line
        if (ios /= 0) exit
        if (allocated(output)) then
          output = output // ' ' // trim(line)
        else
          output = trim(line)
        end if
      end do
      close(unit_num)

      ! Remove trailing newlines/spaces
      if (allocated(output)) then
        result = trim(adjustl(output))
      else
        result = ''
      end if
    else
      result = ''
    end if

    ! Delete temp file
    call execute_command_line('rm -f ' // trim(temp_file))

  contains
    function getpid() result(pid)
      integer :: pid
      ! Simple pseudo-random number based on time
      real :: rnum
      call random_seed()
      call random_number(rnum)
      pid = int(rnum * 99999) + 10000
    end function getpid

  end function evaluator_eval_command_subst

  ! Check if string contains glob patterns
  function evaluator_has_glob_pattern(self, str) result(has_pattern)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: str
    logical :: has_pattern
    integer :: i

    has_pattern = .false.
    do i = 1, len_trim(str)
      if (str(i:i) == '*' .or. str(i:i) == '?' .or. str(i:i) == '[') then
        has_pattern = .true.
        return
      end if
    end do
  end function evaluator_has_glob_pattern

  ! Expand glob pattern to list of files
  function evaluator_expand_glob(self, pattern, matches, match_count) result(success)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: pattern
    character(256), allocatable, intent(out) :: matches(:)
    integer, intent(out) :: match_count
    logical :: success
    type(glob_t) :: pglob
    integer(c_int) :: status
    type(c_ptr), dimension(:), pointer :: pathv_array
    type(c_ptr) :: path_ptr
    character(kind=c_char), pointer :: path_chars(:)
    character(256) :: temp_str
    integer :: i, j

    success = .false.
    match_count = 0

    ! Call glob with pattern
    status = c_glob(trim(pattern) // c_null_char, 0, c_null_funptr, pglob)

    if (status == 0 .and. pglob%gl_pathc > 0) then
      match_count = int(pglob%gl_pathc)
      allocate(matches(match_count))

      ! Access the path array
      call c_f_pointer(pglob%gl_pathv, pathv_array, [int(pglob%gl_pathc)])

      do i = 1, match_count
        path_ptr = pathv_array(i)
        if (c_associated(path_ptr)) then
          ! Convert C string to Fortran string
          call c_f_pointer(path_ptr, path_chars, [256])
          temp_str = ''
          do j = 1, 256
            if (path_chars(j) == c_null_char) exit
            temp_str(j:j) = path_chars(j)
          end do
          matches(i) = temp_str
        end if
      end do
      success = .true.

      ! Free glob resources
      call c_globfree(pglob)
    else
      ! No matches or glob failed - return original pattern
      match_count = 1
      allocate(matches(1))
      matches(1) = pattern
      success = .true.
      if (status == 0) call c_globfree(pglob)
    end if
  end function evaluator_expand_glob

  ! Destroy evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_simple_real_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

end module evaluator_simple_real