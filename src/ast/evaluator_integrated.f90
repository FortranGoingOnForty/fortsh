! ==============================================================================
! Module: evaluator_integrated
! Purpose: AST evaluator integrated with real shell execution
! ==============================================================================
module evaluator_integrated

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000
  use ast_types
  use shell_types  ! Use the actual shell_types module
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Execution context - maintains state during evaluation
  type :: execution_context_t
    type(shell_state_t), pointer :: shell => null()
    type(execution_context_t), pointer :: parent => null()

    ! Local variables for this context
    type(shell_var_t), allocatable :: local_vars(:)
    integer :: local_var_count = 0

    ! Control flow flags
    logical :: break_requested = .false.
    integer :: break_levels = 0
    logical :: continue_requested = .false.
    integer :: continue_levels = 0
    logical :: return_requested = .false.
    integer :: return_value = 0

    ! Function call depth
    integer :: call_depth = 0
  contains
    procedure :: init => context_init
    procedure :: destroy => context_destroy
    procedure :: set_local_var => context_set_local_var
    procedure :: get_var => context_get_var
    procedure :: push_scope => context_push_scope
    procedure :: pop_scope => context_pop_scope
  end type execution_context_t

  ! Main evaluator type
  type :: evaluator_integrated_t
    type(execution_context_t) :: context
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
    procedure :: destroy => evaluator_destroy
  end type evaluator_integrated_t

contains

  ! Initialize execution context
  subroutine context_init(self, shell)
    class(execution_context_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    self%shell => shell
    self%parent => null()
    self%local_var_count = 0
    self%break_requested = .false.
    self%break_levels = 0
    self%continue_requested = .false.
    self%continue_levels = 0
    self%return_requested = .false.
    self%return_value = 0
    self%call_depth = 0

    if (.not. allocated(self%local_vars)) then
      allocate(self%local_vars(50))
    end if
  end subroutine context_init

  ! Clean up execution context
  subroutine context_destroy(self)
    class(execution_context_t), intent(inout) :: self

    if (allocated(self%local_vars)) deallocate(self%local_vars)
    self%shell => null()
    self%parent => null()
  end subroutine context_destroy

  ! Set local variable in context
  subroutine context_set_local_var(self, name, value)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    ! Check if variable already exists
    do i = 1, self%local_var_count
      if (self%local_vars(i)%name == name) then
        self%local_vars(i)%value = value
        return
      end if
    end do

    ! Add new variable
    self%local_var_count = self%local_var_count + 1
    self%local_vars(self%local_var_count)%name = name
    self%local_vars(self%local_var_count)%value = value
  end subroutine context_set_local_var

  ! Get variable from context (checks local then global)
  recursive function context_get_var(self, name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: name
    character(:), allocatable :: value
    integer :: i

    ! Check local variables first
    do i = 1, self%local_var_count
      if (self%local_vars(i)%name == name) then
        value = trim(self%local_vars(i)%value)
        return
      end if
    end do

    ! Check parent context if exists
    if (associated(self%parent)) then
      value = self%parent%get_var(name)
      return
    end if

    ! Check shell variables
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (self%shell%variables(i)%name == name) then
          value = trim(self%shell%variables(i)%value)
          return
        end if
      end do
    end if

    ! Not found - return empty
    value = ''
  end function context_get_var

  ! Simplified scope management
  subroutine context_push_scope(self)
    class(execution_context_t), intent(inout) :: self
    self%call_depth = self%call_depth + 1
  end subroutine context_push_scope

  subroutine context_pop_scope(self)
    class(execution_context_t), intent(inout) :: self
    if (self%call_depth > 0) then
      self%call_depth = self%call_depth - 1
    end if
  end subroutine context_pop_scope

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_integrated_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main evaluation entry point
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    type(script_node_t), intent(in) :: ast
    integer :: exit_code
    integer :: i

    exit_code = 0

    if (.not. allocated(ast%statements)) return

    do i = 1, size(ast%statements)
      exit_code = self%eval_node(ast%statements(i))

      ! Check for return from script
      if (self%context%return_requested) then
        exit_code = self%context%return_value
        exit
      end if
    end do
  end function evaluator_eval

  ! Evaluate any node type
  function evaluator_eval_node(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    exit_code = 0

    ! Due to polymorphic array limitations, dispatch based on node_type
    select case(node%node_type)
    case(NODE_COMMAND)
      exit_code = self%eval_command(node)

    case(NODE_FOR)
      exit_code = self%eval_for_loop(node)

    case(NODE_WHILE)
      exit_code = self%eval_while_loop(node)

    case(NODE_IF)
      exit_code = self%eval_if_statement(node)

    case(NODE_BREAK)
      exit_code = self%eval_break(node)

    case(NODE_CONTINUE)
      exit_code = self%eval_continue(node)

    case default
      write(error_unit, '(a,i15)') 'Unknown node type: ', node%node_type
      exit_code = 1
    end select
  end function evaluator_eval_node

  ! Evaluate simple command
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code
    type(command_t) :: cmd
    type(pipeline_t) :: pipeline
    integer :: i
    character(1024) :: cmd_str, word_value

    ! Build command structure for existing executor
    cmd%num_tokens = 0
    cmd%separator = SEP_NONE

    ! Since we can't access derived fields due to polymorphic limitations,
    ! we'll need to reconstruct the command from node_type info
    ! For now, return a placeholder

    ! In a full implementation, we would:
    ! 1. Extract words from the command node
    ! 2. Build a command_t structure
    ! 3. Call the existing execute_single from executor module

    exit_code = 0

    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if

  end function evaluator_eval_command

  ! Evaluate for loop
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code
    integer :: i, j

    exit_code = 0

    ! Due to polymorphic limitations, can't access for_node_t fields
    ! Would need proper deep copy to make this work

    ! In full implementation:
    ! 1. Extract loop variable name
    ! 2. Extract word list
    ! 3. For each word:
    !    - Set loop variable
    !    - Execute body commands
    !    - Check for break/continue

    ! Update control flow in shell
    if (associated(self%context%shell)) then
      if (self%context%break_requested) then
        ! Handle break in shell control stack
        if (self%context%shell%control_depth > 0) then
          self%context%shell%control_stack(self%context%shell%control_depth)%break_requested = .true.
          self%context%shell%control_stack(self%context%shell%control_depth)%break_level = self%context%break_levels
        end if
      end if
    end if

  end function evaluator_eval_for_loop

  ! Evaluate while loop
  function evaluator_eval_while_loop(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    exit_code = 0

    ! Similar limitations as for_loop
    ! Would evaluate condition and body in a loop

  end function evaluator_eval_while_loop

  ! Evaluate if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    exit_code = 0

    ! Would evaluate condition and execute appropriate branch

  end function evaluator_eval_if_statement

  ! Evaluate break
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    ! Would extract break levels from break_node_t if accessible
    self%context%break_levels = 1
    exit_code = 0
  end function evaluator_eval_break

  ! Evaluate continue
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    ! Would extract continue levels from continue_node_t if accessible
    self%context%continue_levels = 1
    exit_code = 0
  end function evaluator_eval_continue

  ! Evaluate word (with expansions)
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_integrated_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    character(:), allocatable :: result

    ! Due to polymorphic limitations, can't distinguish word vs variable nodes
    ! Would need proper type info preservation
    result = ''

  end function evaluator_eval_word

  ! Clean up evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_integrated_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

end module evaluator_integrated