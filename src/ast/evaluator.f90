! ==============================================================================
! Module: evaluator
! Purpose: AST evaluator for fortsh - executes the abstract syntax tree
! ==============================================================================
module evaluator
  use ast_types
  use shell_types
  use system_interface
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
  type :: evaluator_t
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
  end type evaluator_t

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

    allocate(self%local_vars(50))
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
  function context_get_var(self, name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: name
    character(:), allocatable :: value
    integer :: i

    ! Check local variables first
    do i = 1, self%local_var_count
      if (self%local_vars(i)%name == name) then
        value = self%local_vars(i)%value
        return
      end if
    end do

    ! Check parent context if exists
    if (associated(self%parent)) then
      value = self%parent%get_var(name)
      return
    end if

    ! Fall back to shell global variables
    ! This would call the existing get_shell_variable function
    value = ''
  end function context_get_var

  ! Push new scope (for functions)
  subroutine context_push_scope(self)
    class(execution_context_t), intent(inout) :: self
    type(execution_context_t), allocatable :: new_context

    allocate(new_context)
    call new_context%init(self%shell)
    new_context%parent => self
    new_context%call_depth = self%call_depth + 1
  end subroutine context_push_scope

  ! Pop scope
  subroutine context_pop_scope(self)
    class(execution_context_t), intent(inout) :: self

    if (associated(self%parent)) then
      ! Move back to parent context
      self = self%parent
    end if
  end subroutine context_pop_scope

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main evaluation entry point
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_t), intent(inout) :: self
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
    class(evaluator_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    integer :: exit_code

    exit_code = 0

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
      exit_code = 1
    end select
  end function evaluator_eval_node

  ! Evaluate simple command
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(command_node_t), intent(in) :: node
    integer :: exit_code
    character(:), allocatable :: cmd_str
    integer :: i

    exit_code = 0

    ! Build command string from words
    cmd_str = ''
    if (allocated(node%words)) then
      do i = 1, size(node%words)
        if (i > 1) cmd_str = cmd_str // ' '
        cmd_str = cmd_str // self%eval_word(node%words(i))
      end do
    end if

    ! For demonstration, just print the command
    write(output_unit, '(a,a)') 'Would execute: ', cmd_str

    ! In real implementation, would call existing execute_command
    ! with proper redirections, background flag, etc.
  end function evaluator_eval_command

  ! Evaluate for loop
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(for_node_t), intent(in) :: node
    integer :: exit_code
    integer :: i, j
    character(:), allocatable :: item_value

    exit_code = 0

    ! Iterate over word list
    if (allocated(node%word_list)) then
      do i = 1, size(node%word_list)
        ! Set loop variable
        item_value = self%eval_word(node%word_list(i))
        call self%context%set_local_var(node%variable, item_value)

        ! Execute loop body
        if (allocated(node%body)) then
          do j = 1, size(node%body)
            exit_code = self%eval_node(node%body(j))

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

            ! Check for return
            if (self%context%return_requested) then
              return
            end if
          end do
        end if
      end do
    end if
  end function evaluator_eval_for_loop

  ! Evaluate while loop
  function evaluator_eval_while_loop(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(while_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    do while (.true.)
      ! Evaluate condition
      exit_code = self%eval_node(node%condition)
      if (exit_code /= 0) exit

      ! Execute loop body
      if (allocated(node%body)) then
        do j = 1, size(node%body)
          exit_code = self%eval_node(node%body(j))

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

          ! Check for return
          if (self%context%return_requested) then
            return
          end if
        end do
      end if
    end do
  end function evaluator_eval_while_loop

  ! Evaluate if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(if_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    ! Evaluate condition
    exit_code = self%eval_node(node%condition)

    if (exit_code == 0) then
      ! Execute then branch
      if (allocated(node%then_branch)) then
        do j = 1, size(node%then_branch)
          exit_code = self%eval_node(node%then_branch(j))
          if (self%context%return_requested) return
        end do
      end if
    else
      ! Execute else branch if exists
      if (allocated(node%else_branch)) then
        do j = 1, size(node%else_branch)
          exit_code = self%eval_node(node%else_branch(j))
          if (self%context%return_requested) return
        end do
      end if
    end if
  end function evaluator_eval_if_statement

  ! Evaluate break
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(break_node_t), intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    self%context%break_levels = node%levels
    exit_code = 0
  end function evaluator_eval_break

  ! Evaluate continue
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_t), intent(inout) :: self
    type(continue_node_t), intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    self%context%continue_levels = node%levels
    exit_code = 0
  end function evaluator_eval_continue

  ! Evaluate word (with expansions)
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    character(:), allocatable :: result

    select type(node)
    type is (word_node_t)
      result = node%text
      ! TODO: Apply expansions if needed

    type is (variable_node_t)
      result = self%context%get_var(node%name)

    class default
      result = ''
    end select
  end function evaluator_eval_word

  ! Clean up evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

end module evaluator