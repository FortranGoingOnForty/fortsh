! ==============================================================================
! Module: evaluator_enhanced
! Purpose: Enhanced evaluator that works with pointer-based AST
! ==============================================================================
module evaluator_enhanced

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000
  use ast_types_enhanced
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Execution context
  type :: execution_context_t
    type(shell_state_t), pointer :: shell => null()

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
  contains
    procedure :: init => context_init
    procedure :: destroy => context_destroy
    procedure :: set_var => context_set_var
    procedure :: get_var => context_get_var
  end type execution_context_t

  ! Enhanced evaluator type
  type :: evaluator_enhanced_t
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
    procedure :: eval_variable => evaluator_eval_variable
    procedure :: destroy => evaluator_destroy
  end type evaluator_enhanced_t

contains

  ! Initialize execution context
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

  ! Clean up execution context
  subroutine context_destroy(self)
    class(execution_context_t), intent(inout) :: self

    if (allocated(self%local_vars)) deallocate(self%local_vars)
    self%shell => null()
  end subroutine context_destroy

  ! Set variable in context
  subroutine context_set_var(self, name, value)
    class(execution_context_t), intent(inout) :: self
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

  ! Get variable from context
  function context_get_var(self, name) result(value)
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

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main evaluation entry point
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(script_node_t), intent(in) :: ast
    integer :: exit_code
    integer :: i

    exit_code = 0

    if (.not. allocated(ast%statements)) return

    do i = 1, ast%num_statements
      if (associated(ast%statements(i)%ptr)) then
        exit_code = self%eval_node(ast%statements(i)%ptr)

        ! Check for return from script
        if (self%context%return_requested) then
          exit_code = self%context%return_value
          exit
        end if
      end if
    end do
  end function evaluator_eval

  ! Evaluate any node type - with full polymorphic dispatch!
  recursive function evaluator_eval_node(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    integer :: exit_code

    exit_code = 0

    if (.not. associated(node)) return

    ! Now we can use SELECT TYPE with full type information!
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
      write(error_unit, '(a,i15)') 'Unknown node type: ', node%node_type
      exit_code = 1
    end select
  end function evaluator_eval_node

  ! Evaluate simple command - now with full access to fields!
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(command_node_t), intent(in) :: node
    integer :: exit_code
    character(1024) :: cmd_str
    integer :: i
    character(:), allocatable :: word_value

    exit_code = 0

    ! Build command string from words
    cmd_str = ''
    if (allocated(node%words)) then
      do i = 1, node%num_words
        if (associated(node%words(i)%ptr)) then
          word_value = self%eval_word(node%words(i)%ptr)
          if (i == 1) then
            cmd_str = word_value
          else
            cmd_str = trim(cmd_str) // ' ' // word_value
          end if
        end if
      end do
    end if

    ! Output the command we would execute
    write(output_unit, '(a,a)') 'Executing: ', trim(cmd_str)

    ! In real implementation, would call system() or fork/exec
    ! For now, just handle some built-in commands
    if (index(cmd_str, 'echo ') == 1) then
      write(output_unit, '(a)') trim(cmd_str(6:))
      exit_code = 0
    else if (trim(cmd_str) == 'true') then
      exit_code = 0
    else if (trim(cmd_str) == 'false') then
      exit_code = 1
    end if

    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_command

  ! Evaluate for loop - now with full access to word_list and body!
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(for_node_t), intent(in) :: node
    integer :: exit_code
    integer :: i, j
    character(:), allocatable :: item_value

    exit_code = 0

    write(output_unit, '(a,a)') 'For loop over variable: ', node%variable

    ! Iterate over word list
    if (allocated(node%word_list)) then
      do i = 1, node%num_words
        if (associated(node%word_list(i)%ptr)) then
          ! Get value of current item
          item_value = self%eval_word(node%word_list(i)%ptr)

          ! Set loop variable
          call self%context%set_var(node%variable, item_value)

          write(output_unit, '(a,a,a,a)') 'Setting ', trim(node%variable), ' = ', item_value

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
                    write(output_unit, '(a)') 'Breaking from for loop'
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
                    write(output_unit, '(a)') 'Continuing to next iteration'
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
    class(evaluator_enhanced_t), intent(inout) :: self
    type(while_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    write(output_unit, '(a)') 'While loop'

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
                write(output_unit, '(a)') 'Breaking from while loop'
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
                write(output_unit, '(a)') 'Continuing to next iteration'
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

  ! Evaluate if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(if_node_t), intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    write(output_unit, '(a)') 'If statement'

    ! Evaluate condition
    if (associated(node%condition%ptr)) then
      exit_code = self%eval_node(node%condition%ptr)
    end if

    if (exit_code == 0) then
      write(output_unit, '(a)') 'Condition true, executing then branch'
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
      write(output_unit, '(a)') 'Condition false'
      ! Execute else branch if exists
      if (allocated(node%else_branch)) then
        write(output_unit, '(a)') 'Executing else branch'
        do j = 1, node%num_else
          if (associated(node%else_branch(j)%ptr)) then
            exit_code = self%eval_node(node%else_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    end if
  end function evaluator_eval_if_statement

  ! Evaluate break - now with access to levels!
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(break_node_t), intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    self%context%break_levels = node%levels
    write(output_unit, '(a,i15)') 'Break statement with levels: ', node%levels
    exit_code = 0
  end function evaluator_eval_break

  ! Evaluate continue - now with access to levels!
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(continue_node_t), intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    self%context%continue_levels = node%levels
    write(output_unit, '(a,i15)') 'Continue statement with levels: ', node%levels
    exit_code = 0
  end function evaluator_eval_continue

  ! Evaluate word node
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_enhanced_t), intent(inout) :: self
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

  ! Evaluate variable node - now with full access!
  function evaluator_eval_variable(self, node) result(result)
    class(evaluator_enhanced_t), intent(inout) :: self
    type(variable_node_t), intent(in) :: node
    character(:), allocatable :: result

    result = self%context%get_var(node%name)

    ! Could handle modifiers here (${var:-default} etc)
    if (allocated(node%modifier)) then
      ! Handle parameter expansion modifiers
      select case(node%modifier_type)
      case default
        ! Just return the value for now
      end select
    end if
  end function evaluator_eval_variable

  ! Clean up evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_enhanced_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

end module evaluator_enhanced