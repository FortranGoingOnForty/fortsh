! ==============================================================================
! Module: evaluator_real
! Purpose: Real evaluator that executes actual commands
! ==============================================================================
module evaluator_real
  use ast_types_enhanced
  use shell_types
  use builtins
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding
  implicit none

  ! C interface for system call
  interface
    function c_system(command) bind(C, name="system")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: command
      integer(c_int) :: c_system
    end function c_system
  end interface

  ! Execution context
  type :: execution_context_real_t
    type(shell_state_t), pointer :: shell => null()

    ! Local variables
    type(shell_var_t), allocatable :: local_vars(:)
    integer :: local_var_count = 0

    ! Control flow flags
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
    procedure :: set_shell_var => context_set_shell_var
  end type execution_context_real_t

  ! Real evaluator type
  type :: evaluator_real_t
    type(execution_context_real_t) :: context
  contains
    procedure :: init => evaluator_init
    procedure :: eval => evaluator_eval
    procedure :: eval_node => evaluator_eval_node
    procedure :: eval_command => evaluator_eval_command
    procedure :: eval_for_loop => evaluator_eval_for_loop
    procedure :: eval_while_loop => evaluator_eval_while_loop
    procedure :: eval_if_statement => evaluator_eval_if_statement
    procedure :: eval_break => evaluator_eval_break
    procedure :: eval_continue => evaluator_eval_continue
    procedure :: eval_word => evaluator_eval_word
    procedure :: eval_variable => evaluator_eval_variable
    procedure :: execute_system => evaluator_execute_system
    procedure :: execute_builtin_simple => evaluator_execute_builtin_simple
    procedure :: destroy => evaluator_destroy
  end type evaluator_real_t

contains

  ! Initialize execution context
  subroutine context_init(self, shell)
    class(execution_context_real_t), intent(inout) :: self
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
    class(execution_context_real_t), intent(inout) :: self

    if (allocated(self%local_vars)) deallocate(self%local_vars)
    self%shell => null()
  end subroutine context_destroy

  ! Set local variable
  subroutine context_set_var(self, name, value)
    class(execution_context_real_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    ! Check if variable already exists locally
    do i = 1, self%local_var_count
      if (self%local_vars(i)%name == name) then
        self%local_vars(i)%value = value
        return
      end if
    end do

    ! Add new local variable
    if (self%local_var_count < size(self%local_vars)) then
      self%local_var_count = self%local_var_count + 1
      self%local_vars(self%local_var_count)%name = name
      self%local_vars(self%local_var_count)%value = value
    end if
  end subroutine context_set_var

  ! Get variable value
  function context_get_var(self, name) result(value)
    class(execution_context_real_t), intent(in) :: self
    character(*), intent(in) :: name
    character(:), allocatable :: value
    integer :: i

    ! Check local variables first
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

    ! Check environment variables
    call get_environment_variable(name, value)
    if (.not. allocated(value)) value = ''
  end function context_get_var

  ! Set shell variable
  subroutine context_set_shell_var(self, name, value)
    class(execution_context_real_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    if (.not. associated(self%shell)) return

    ! Find existing or add new
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(name)) then
        self%shell%variables(i)%value = value
        return
      end if
    end do

    ! Add new variable
    if (self%shell%num_variables < size(self%shell%variables)) then
      self%shell%num_variables = self%shell%num_variables + 1
      self%shell%variables(self%shell%num_variables)%name = name
      self%shell%variables(self%shell%num_variables)%value = value
    end if
  end subroutine context_set_shell_var

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_real_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main evaluation entry point
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(script_node_t), intent(in) :: ast
    integer :: exit_code
    integer :: i

    exit_code = 0

    if (.not. allocated(ast%statements)) return

    do i = 1, ast%num_statements
      if (associated(ast%statements(i)%ptr)) then
        exit_code = self%eval_node(ast%statements(i)%ptr)

        ! Check for return
        if (self%context%return_requested) then
          exit_code = self%context%return_value
          exit
        end if
      end if
    end do
  end function evaluator_eval

  ! Evaluate any node
  recursive function evaluator_eval_node(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    integer :: exit_code

    exit_code = 0

    if (.not. associated(node)) return

    select type(node)
    type is (command_node_t)
      exit_code = self%eval_command(node)

    type is (for_node_t)
      exit_code = self%eval_for_loop(node)

    type is (while_node_t)
      exit_code = self%eval_while_loop(node)

    type is (if_node_t)
      exit_code = self%eval_if_statement(node)

    type is (break_node_t)
      exit_code = self%eval_break(node)

    type is (continue_node_t)
      exit_code = self%eval_continue(node)

    class default
      write(error_unit, '(a,i0)') 'Unknown node type: ', node%node_type
      exit_code = 127
    end select
  end function evaluator_eval_node

  ! Evaluate command - THE REAL DEAL!
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(command_node_t), intent(in) :: node
    integer :: exit_code
    character(1024) :: cmd_str
    character(256), allocatable :: words(:)
    character(:), allocatable :: word_value, first_word
    integer :: i, num_words
    type(command_t) :: shell_cmd

    exit_code = 0

    ! Build command words array
    if (.not. allocated(node%words) .or. node%num_words == 0) then
      return  ! Empty command
    end if

    allocate(words(node%num_words))
    num_words = 0

    do i = 1, node%num_words
      if (associated(node%words(i)%ptr)) then
        word_value = self%eval_word(node%words(i)%ptr)
        num_words = num_words + 1
        words(num_words) = word_value
      end if
    end do

    if (num_words == 0) return

    first_word = trim(words(1))

    ! Check for built-in commands
    if (is_builtin(first_word)) then
      ! Build command_t structure for built-ins
      allocate(shell_cmd%tokens(num_words))
      shell_cmd%num_tokens = num_words
      do i = 1, num_words
        shell_cmd%tokens(i) = trim(words(i))
      end do
      shell_cmd%background = node%background

      ! Execute built-in
      call execute_builtin(shell_cmd, self%context%shell)
      exit_code = self%context%shell%last_exit_status

      deallocate(shell_cmd%tokens)
    else
      ! Build command string for external commands
      cmd_str = trim(words(1))
      do i = 2, num_words
        cmd_str = trim(cmd_str) // ' ' // trim(words(i))
      end do

      ! Execute external command
      exit_code = self%execute_system(trim(cmd_str))
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if

    deallocate(words)
  end function evaluator_eval_command

  ! Execute system command
  function evaluator_execute_system(self, cmd_str) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    character(*), intent(in) :: cmd_str
    integer :: exit_code
    character(kind=c_char, len=:), allocatable :: c_cmd
    integer(c_int) :: status

    ! Add null terminator for C
    c_cmd = trim(cmd_str) // c_null_char

    ! Call system()
    status = c_system(c_cmd)

    ! Extract exit code (system returns status * 256)
    if (status < 0) then
      exit_code = 127  ! Command not found
    else
      exit_code = status / 256
    end if
  end function evaluator_execute_system

  ! Execute simple built-ins (temporary)
  function evaluator_execute_builtin_simple(self, cmd_name, args) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    character(*), intent(in) :: cmd_name
    character(*), intent(in) :: args
    integer :: exit_code

    exit_code = 0

    select case(trim(cmd_name))
    case('echo')
      write(output_unit, '(a)') trim(args)

    case('pwd')
      if (associated(self%context%shell)) then
        write(output_unit, '(a)') trim(self%context%shell%cwd)
      end if

    case('exit')
      if (associated(self%context%shell)) then
        self%context%shell%running = .false.
        if (len_trim(args) > 0) then
          read(args, *) exit_code
        end if
      end if

    case default
      exit_code = 127
    end select
  end function evaluator_execute_builtin_simple

  ! Evaluate for loop
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(for_node_t), intent(in) :: node
    integer :: exit_code
    integer :: i, j
    character(:), allocatable :: item_value

    exit_code = 0

    ! Iterate over word list
    if (allocated(node%word_list)) then
      do i = 1, node%num_words
        if (associated(node%word_list(i)%ptr)) then
          ! Get value of current item
          item_value = self%eval_word(node%word_list(i)%ptr)

          ! Set loop variable
          call self%context%set_var(trim(node%variable), item_value)
          call self%context%set_shell_var(trim(node%variable), item_value)

          ! Execute loop body
          if (allocated(node%body)) then
            do j = 1, node%num_body
              if (associated(node%body(j)%ptr)) then
                exit_code = self%eval_node(node%body(j)%ptr)

                ! Check for break
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

                ! Check for continue
                if (self%context%continue_requested) then
                  if (self%context%continue_levels <= 1) then
                    self%context%continue_requested = .false.
                    self%context%continue_levels = 0
                    exit  ! Continue to next iteration
                  else
                    self%context%continue_levels = self%context%continue_levels - 1
                    return
                  end if
                end if
              end if
            end do
          end if
        end if
      end do
    end if
  end function evaluator_eval_for_loop

  ! Evaluate while loop
  function evaluator_eval_while_loop(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(while_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    do while (.true.)
      ! Evaluate condition
      if (associated(node%condition%ptr)) then
        exit_code = self%eval_node(node%condition%ptr)
        if (exit_code /= 0) exit
      end if

      ! Execute loop body
      if (allocated(node%body)) then
        do j = 1, node%num_body
          if (associated(node%body(j)%ptr)) then
            exit_code = self%eval_node(node%body(j)%ptr)

            ! Check for break
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

            ! Check for continue
            if (self%context%continue_requested) then
              if (self%context%continue_levels <= 1) then
                self%context%continue_requested = .false.
                self%context%continue_levels = 0
                exit  ! Continue to next iteration
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

  ! Evaluate if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(if_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    ! Evaluate condition
    if (associated(node%condition%ptr)) then
      exit_code = self%eval_node(node%condition%ptr)
    end if

    if (exit_code == 0) then
      ! Execute then branch
      if (allocated(node%then_branch)) then
        do j = 1, node%num_then
          if (associated(node%then_branch(j)%ptr)) then
            exit_code = self%eval_node(node%then_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    else
      ! Execute else branch if exists
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

  ! Evaluate break
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(break_node_t), intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    self%context%break_levels = node%levels
    exit_code = 0
  end function evaluator_eval_break

  ! Evaluate continue
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_real_t), intent(inout) :: self
    type(continue_node_t), intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    self%context%continue_levels = node%levels
    exit_code = 0
  end function evaluator_eval_continue

  ! Evaluate word
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result

    select type(node)
    type is (word_node_t)
      result = node%text

    type is (variable_node_t)
      result = self%eval_variable(node)

    class default
      result = ''
    end select
  end function evaluator_eval_word

  ! Evaluate variable
  function evaluator_eval_variable(self, node) result(result)
    class(evaluator_real_t), intent(inout) :: self
    type(variable_node_t), intent(in) :: node
    character(:), allocatable :: result

    result = self%context%get_var(trim(node%name))

    ! Handle special variables
    if (trim(node%name) == '?') then
      if (associated(self%context%shell)) then
        write(result, '(i0)') self%context%shell%last_exit_status
      else
        result = '0'
      end if
    else if (trim(node%name) == '#') then
      result = '0'  ! Argument count
    else if (trim(node%name) == '$') then
      if (associated(self%context%shell)) then
        write(result, '(i0)') self%context%shell%shell_pgid
      else
        result = '0'
      end if
    end if

    ! Handle parameter expansion modifiers
    if (allocated(node%modifier)) then
      ! TODO: Implement ${var:-default} etc
    end if
  end function evaluator_eval_variable

  ! Clean up evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_real_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

end module evaluator_real