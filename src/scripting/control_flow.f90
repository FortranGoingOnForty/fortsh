! ==============================================================================
! Module: control_flow  
! Purpose: Shell scripting control flow structures (if/then/else, loops)
! ==============================================================================
module control_flow
  use shell_types
  use system_interface
  use advanced_test, only: evaluate_test_expression
  use variables, only: set_shell_variable, get_shell_variable
  use glob, only: pattern_matches_no_dotfile_check
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Interface for the evaluate_condition procedure
  abstract interface
    subroutine evaluate_condition_interface(condition_cmd, shell, result)
      import :: shell_state_t
      character(len=*), intent(in) :: condition_cmd
      type(shell_state_t), intent(inout) :: shell
      logical, intent(out) :: result
    end subroutine
  end interface

  ! Procedure pointer for evaluate_condition (set by executor to avoid circular dependency)
  procedure(evaluate_condition_interface), pointer, public :: evaluate_condition => null()

  ! Make simple_variable_expand accessible to executor
  public :: simple_variable_expand

  ! Control flow keywords
  integer, parameter :: FLOW_IF = 1
  integer, parameter :: FLOW_THEN = 2
  integer, parameter :: FLOW_ELSE = 3
  integer, parameter :: FLOW_ELIF = 15
  integer, parameter :: FLOW_FI = 4
  integer, parameter :: FLOW_WHILE = 5
  integer, parameter :: FLOW_UNTIL = 16
  integer, parameter :: FLOW_FOR = 6
  integer, parameter :: FLOW_DO = 7
  integer, parameter :: FLOW_DONE = 8
  integer, parameter :: FLOW_FUNCTION = 9
  integer, parameter :: FLOW_RETURN = 10
  integer, parameter :: FLOW_LOCAL = 11
  integer, parameter :: BLOCK_CASE = 12
  integer, parameter :: FLOW_ESAC = 13
  integer, parameter :: FLOW_IN = 14


  type :: case_pattern_t
    character(len=256) :: pattern
    character(len=2048) :: commands
    logical :: matched
  end type case_pattern_t

  type :: case_block_t
    character(len=256) :: case_variable
    type(case_pattern_t) :: patterns(50)
    integer :: num_patterns
    integer :: current_pattern
    logical :: found_match
  end type case_block_t

contains

  function is_control_flow_keyword(word) result(is_flow)
    character(len=*), intent(in) :: word
    logical :: is_flow

    is_flow = (trim(word) == 'if' .or. &
               trim(word) == 'then' .or. &
               trim(word) == 'else' .or. &
               trim(word) == 'elif' .or. &
               trim(word) == 'fi' .or. &
               trim(word) == 'while' .or. &
               trim(word) == 'until' .or. &
               trim(word) == 'for' .or. &
               trim(word) == 'do' .or. &
               trim(word) == 'done' .or. &
               trim(word) == 'function' .or. &
               trim(word) == 'return' .or. &
               trim(word) == 'local' .or. &
               trim(word) == 'case' .or. &
               trim(word) == 'esac' .or. &
               trim(word) == 'in')
  end function

  function identify_flow_keyword(word) result(flow_type)
    character(len=*), intent(in) :: word
    integer :: flow_type

    select case(trim(word))
    case('if')
      flow_type = FLOW_IF
    case('then')
      flow_type = FLOW_THEN
    case('else')
      flow_type = FLOW_ELSE
    case('elif')
      flow_type = FLOW_ELIF
    case('fi')
      flow_type = FLOW_FI
    case('while')
      flow_type = FLOW_WHILE
    case('until')
      flow_type = FLOW_UNTIL
    case('for')
      flow_type = FLOW_FOR
    case('do')
      flow_type = FLOW_DO
    case('done')
      flow_type = FLOW_DONE
    case('function')
      flow_type = FLOW_FUNCTION
    case('return')
      flow_type = FLOW_RETURN
    case('local')
      flow_type = FLOW_LOCAL
    case('case')
      flow_type = BLOCK_CASE
    case('esac')
      flow_type = FLOW_ESAC
    case('in')
      flow_type = FLOW_IN
    case default
      flow_type = 0
    end select
  end function

  subroutine handle_if_statement(condition_cmd, shell, result)
    character(len=*), intent(in) :: condition_cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: result
    
    ! For now, implement simple test conditions
    ! Later this would parse and execute test expressions
    if (index(condition_cmd, '-f') > 0) then
      ! File exists test
      result = .false.  ! Simplified for now
    else if (index(condition_cmd, '-d') > 0) then
      ! Directory exists test  
      result = .false.  ! Simplified for now
    else
      ! Default: treat as command and check exit status
      ! This would execute the condition command and check its exit status
      result = (shell%last_exit_status == 0)
    end if
  end subroutine

  subroutine process_control_flow(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    should_execute = .true.  ! Default: execute normally

    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return

    ! Check for arithmetic for loop without space: for((  ...
    if (len_trim(cmd%tokens(1)) >= 5) then
      if (cmd%tokens(1)(1:5) == 'for((') then
        call process_for_arith_statement(cmd, shell)
        should_execute = .false.  ! Don't execute the for command itself
        return
      end if
    end if

    ! Check for arithmetic for loop with space: for (( ...
    if (cmd%num_tokens >= 2 .and. trim(cmd%tokens(1)) == 'for') then
      if (len_trim(cmd%tokens(2)) >= 2 .and. cmd%tokens(2)(1:2) == '((') then
        call process_for_arith_statement(cmd, shell)
        should_execute = .false.  ! Don't execute the for command itself
        return
      end if
    end if

    select case(trim(cmd%tokens(1)))
    case('if')
      call process_if_statement(cmd, shell, should_execute)
    case('then')
      call process_then_statement(cmd, shell, should_execute)
    case('else')
      call process_else_statement(shell, should_execute)
    case('elif')
      call process_elif_statement(cmd, shell, should_execute)
    case('fi')
      call process_fi_statement(shell, should_execute)
    case('while')
      call process_while_statement(cmd, shell, should_execute)
    case('until')
      call process_until_statement(cmd, shell, should_execute)
    case('do')
      call process_do_statement(cmd, shell, should_execute)
    case('done')
      call process_done_statement(shell, should_execute)
    case('for')
      call process_for_statement(cmd, shell, should_execute)
    case('function')
      call process_function_statement(cmd, shell, should_execute)
    case('case')
      call handle_case_statement(cmd, shell)
      should_execute = .false.  ! Don't execute 'case' as a command
    case('esac')
      call handle_esac_statement(shell)
      should_execute = .false.  ! Don't execute 'esac' as a command
    case default
      ! Check if line contains a case pattern (ends with ')' and we're in a case block)
      if (shell%control_depth > 0 .and. shell%control_stack(shell%control_depth)%block_type == BLOCK_CASE) then
        ! Check if this looks like a case pattern or ;;
        if (trim(cmd%tokens(1)) == ';;') then
          ! End of pattern commands - stop executing this case branch
          shell%control_stack(shell%control_depth)%case_in_match = .false.
          shell%control_stack(shell%control_depth)%condition_met = .false.
          should_execute = .false.  ! Don't execute ';;'
        else if (index(cmd%tokens(1), ')') > 0 .and. cmd%num_tokens > 1) then
          ! This is a pattern line (pattern is in first token)
          ! with commands following it (e.g., "2) echo two")
          call handle_case_pattern(cmd, shell)
          ! Execute remaining tokens as command if pattern matched
          should_execute = shell%control_stack(shell%control_depth)%case_in_match
          shell%case_pattern_skip_first_token = should_execute  ! Skip pattern token if executing
        else if (index(cmd%tokens(1), ')') > 0) then
          ! Pattern line with no following commands
          call handle_case_pattern(cmd, shell)
          should_execute = .false.
        else
          ! Regular command inside case - only execute if we're in a matched pattern
          should_execute = shell%control_stack(shell%control_depth)%case_in_match
        end if
      else
        ! Check if we should execute this command based on control flow state
        should_execute = should_execute_command(shell)
      end if
    end select
  end subroutine
  
  subroutine process_if_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    logical :: condition_result
    integer :: i
    character(len=1024) :: condition_cmd
    
    should_execute = .false.  ! Don't execute the if command itself
    
    ! Parse if condition: if [ condition ] or if command
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'if: missing condition'
      shell%last_exit_status = 1
      return
    end if
    
    ! Build condition command from tokens (skip "if")
    condition_cmd = ''
    do i = 2, cmd%num_tokens
      if (len_trim(condition_cmd) > 0) then
        condition_cmd = trim(condition_cmd) // ' ' // trim(cmd%tokens(i))
      else
        condition_cmd = trim(cmd%tokens(i))
      end if
    end do
    
    ! Evaluate condition
    call evaluate_condition(condition_cmd, shell, condition_result)

    ! Push if block onto control stack
    call push_control_block(shell, BLOCK_IF, condition_result)

    ! POSIX: Reset exit status after evaluating control flow condition
    ! The 'if' keyword itself doesn't fail - it just sets up control state
    shell%last_exit_status = 0
  end subroutine
  
  subroutine process_while_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    logical :: condition_result
    integer :: i
    character(len=1024) :: condition_cmd
    
    should_execute = .false.  ! Don't execute the while command itself
    
    ! Parse while condition: while [ condition ] or while command
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'while: missing condition'
      shell%last_exit_status = 1
      return
    end if
    
    ! Build condition command from tokens (skip "while")
    condition_cmd = ''
    do i = 2, cmd%num_tokens
      if (len_trim(condition_cmd) > 0) then
        condition_cmd = trim(condition_cmd) // ' ' // trim(cmd%tokens(i))
      else
        condition_cmd = trim(cmd%tokens(i))
      end if
    end do
    
    ! Evaluate condition
    call evaluate_condition(condition_cmd, shell, condition_result)

    ! Push while block onto control stack
    call push_control_block(shell, BLOCK_WHILE, condition_result)

    ! IMPORTANT: Store the condition command for re-evaluation at each iteration
    shell%control_stack(shell%control_depth)%condition_cmd = condition_cmd

    ! POSIX: Reset exit status after evaluating control flow condition
    ! The 'while' keyword itself doesn't fail - it just sets up control state
    ! Re-evaluation at 'done' will execute the condition command fresh
    shell%last_exit_status = 0
  end subroutine

  subroutine process_until_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    logical :: condition_result
    integer :: i
    character(len=1024) :: condition_cmd

    should_execute = .false.  ! Don't execute the until command itself

    ! Parse until condition: until [ condition ] or until command
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'until: missing condition'
      shell%last_exit_status = 1
      return
    end if

    ! Build condition command from tokens (skip "until")
    condition_cmd = ''
    do i = 2, cmd%num_tokens
      if (len_trim(condition_cmd) > 0) then
        condition_cmd = trim(condition_cmd) // ' ' // trim(cmd%tokens(i))
      else
        condition_cmd = trim(cmd%tokens(i))
      end if
    end do

    ! Evaluate condition
    call evaluate_condition(condition_cmd, shell, condition_result)

    ! Push until block onto control stack with INVERTED condition
    ! until loops run while condition is FALSE
    call push_control_block(shell, BLOCK_UNTIL, .not. condition_result)

    ! IMPORTANT: Store the condition command for re-evaluation at each iteration
    shell%control_stack(shell%control_depth)%condition_cmd = condition_cmd

    ! POSIX: Reset exit status after evaluating control flow condition
    ! The 'until' keyword itself doesn't fail - it just sets up control state
    ! Re-evaluation at 'done' will execute the condition command fresh
    shell%last_exit_status = 0
  end subroutine

  subroutine process_for_statement(cmd, shell, should_execute)
    use substitution, only: expand_braces
    use glob, only: glob_match, has_unescaped_glob_chars
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    character(len=256) :: var_name, list_part
    character(len=256) :: expanded_items(100)
    character(len=256) :: glob_matches(100)
    character(len=256) :: final_items(100)
    integer :: expanded_count, final_count, glob_count, start_pos, end_pos
    integer :: in_pos, i, j, k, word_start, word_end

    should_execute = .false.  ! Don't execute the for command itself

    ! Check if this is arithmetic for loop: for ((init; cond; incr))
    if (cmd%num_tokens >= 2) then
      if (index(cmd%tokens(2), '((') == 1) then
        call process_for_arith_statement(cmd, shell)
        return
      end if
    end if

    ! Parse: for var in [word1 word2 word3]
    ! Note: Empty list is allowed (e.g., "for x in; do")
    if (cmd%num_tokens < 3 .or. trim(cmd%tokens(3)) /= 'in') then
      write(error_unit, '(a)') 'for: syntax error, expected "for var in [list]"'
      shell%last_exit_status = 1
      return
    end if

    var_name = trim(cmd%tokens(2))

    ! If there are no items after "in", that's valid - just an empty loop
    if (cmd%num_tokens < 4) then
      final_count = 0
    else
      ! Process each token as a separate item (they're already tokenized correctly)
      ! Expand braces and globs as needed
      final_count = 0
      do i = 4, cmd%num_tokens
        ! Check if this token needs brace expansion
        if (index(cmd%tokens(i), '{') > 0 .and. index(cmd%tokens(i), '}') > 0) then
          ! Expand braces for this token (e.g., {1..5} -> 1 2 3 4 5)
          call expand_braces(trim(cmd%tokens(i)), expanded_items, expanded_count)
          ! Add all expanded items to final list
          do j = 1, expanded_count
            if (final_count < 100) then
              final_count = final_count + 1
              final_items(final_count) = trim(expanded_items(j))
            end if
          end do
        ! Check if this token needs glob expansion
        else if (has_unescaped_glob_chars(trim(cmd%tokens(i)))) then
          ! Expand glob pattern (e.g., *.txt -> file1.txt file2.txt)
          call glob_match(trim(cmd%tokens(i)), glob_matches, glob_count)
          if (glob_count > 0) then
            ! Add all matched files to final list
            do j = 1, glob_count
              if (final_count < 100) then
                final_count = final_count + 1
                final_items(final_count) = trim(glob_matches(j))
              end if
            end do
          else
            ! No matches - use pattern literally (POSIX behavior)
            if (final_count < 100) then
              final_count = final_count + 1
              final_items(final_count) = trim(cmd%tokens(i))
            end if
          end if
        else
          ! No expansion needed - use token as-is (preserves quoted strings)
          if (final_count < 100) then
            final_count = final_count + 1
            final_items(final_count) = trim(cmd%tokens(i))
          end if
        end if
      end do
    end if

    ! Push for block onto control stack with final split items
    if (shell%control_depth < MAX_CONTROL_DEPTH) then
      shell%control_depth = shell%control_depth + 1
      shell%control_stack(shell%control_depth)%block_type = BLOCK_FOR
      shell%control_stack(shell%control_depth)%loop_variable = var_name

      ! Build list_part from final_items for storage (mainly for debugging)
      list_part = ''
      if (final_count > 0) then
        do i = 1, final_count
          if (len_trim(list_part) > 0) then
            list_part = trim(list_part) // ' ' // trim(final_items(i))
          else
            list_part = trim(final_items(i))
          end if
        end do
      end if
      shell%control_stack(shell%control_depth)%for_list = list_part

      ! Use final split items
      shell%control_stack(shell%control_depth)%for_count = final_count
      if (final_count > 0) then
        allocate(shell%control_stack(shell%control_depth)%for_values(final_count))
        do i = 1, final_count
          shell%control_stack(shell%control_depth)%for_values(i) = trim(final_items(i))
        end do
      end if

      ! Set up for first iteration - start at index 0 so first 'done' will set it to 1
      shell%control_stack(shell%control_depth)%for_index = 0
      if (shell%control_stack(shell%control_depth)%for_count > 0 .and. &
          allocated(shell%control_stack(shell%control_depth)%for_values)) then
        shell%control_stack(shell%control_depth)%should_execute = .true.
        ! Don't set loop variable yet - let first 'done' do it
      else
        shell%control_stack(shell%control_depth)%should_execute = .false.
      end if
    else
      write(error_unit, '(a)') 'Error: Control flow nesting too deep'
    end if
  end subroutine

  ! Process arithmetic for loop: for ((init; condition; increment))
  subroutine process_for_arith_statement(cmd, shell)
    use expansion, only: arithmetic_expansion_shell
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=512) :: full_expr, init_expr, cond_expr, incr_expr
    integer :: i, start_pos, end_pos, semi1, semi2, paren_depth
    character(len=:), allocatable :: result_value

    ! Reconstruct the full (( ... )) expression from tokens
    ! Check if token(1) contains the entire for((expression))
    if (cmd%num_tokens >= 1 .and. len_trim(cmd%tokens(1)) >= 5) then
      if (cmd%tokens(1)(1:5) == 'for((') then
        ! Entire for(( expression is in token(1), strip the "for" prefix
        full_expr = cmd%tokens(1)(4:)  ! Start from position 4 to skip "for"
      else
        ! Tokens are separated: token(1)='for', token(2)='((...)'
        full_expr = ''
        do i = 2, cmd%num_tokens
          if (len_trim(full_expr) > 0) then
            full_expr = trim(full_expr) // ' ' // trim(cmd%tokens(i))
          else
            full_expr = trim(cmd%tokens(i))
          end if
        end do
      end if
    else
      ! Tokens are separated or insufficient tokens
      full_expr = ''
      do i = 2, cmd%num_tokens
        if (len_trim(full_expr) > 0) then
          full_expr = trim(full_expr) // ' ' // trim(cmd%tokens(i))
        else
          full_expr = trim(cmd%tokens(i))
        end if
      end do
    end if


    ! Find the (( and )) boundaries
    start_pos = index(full_expr, '((')
    if (start_pos == 0) then
      write(error_unit, '(a)') 'for: syntax error in arithmetic for loop'
      shell%last_exit_status = 1
      return
    end if

    ! Find matching ))
    paren_depth = 0
    end_pos = 0
    i = start_pos
    do while (i < len_trim(full_expr))
      if (i+1 <= len_trim(full_expr) .and. full_expr(i:i+1) == '((') then
        paren_depth = paren_depth + 1
        i = i + 2
      else if (i+1 <= len_trim(full_expr) .and. full_expr(i:i+1) == '))') then
        paren_depth = paren_depth - 1
        if (paren_depth == 0) then
          end_pos = i
          exit
        end if
        i = i + 2
      else
        i = i + 1
      end if
    end do

    if (end_pos == 0) then
      write(error_unit, '(a)') 'for: syntax error, unclosed (('
      shell%last_exit_status = 1
      return
    end if

    ! Extract content between (( and ))
    full_expr = full_expr(start_pos+2:end_pos-1)

    ! Split by semicolons to get init, condition, increment
    semi1 = index(full_expr, ';')
    if (semi1 > 0) then
      init_expr = full_expr(:semi1-1)
      semi2 = index(full_expr(semi1+1:), ';')
      if (semi2 > 0) then
        semi2 = semi1 + semi2
        cond_expr = full_expr(semi1+1:semi2-1)
        incr_expr = full_expr(semi2+1:)
      else
        ! Only one semicolon: init; condition (no increment)
        cond_expr = full_expr(semi1+1:)
        incr_expr = ''
      end if
    else
      ! No semicolons: treat entire expression as condition
      init_expr = ''
      cond_expr = full_expr
      incr_expr = ''
    end if

    ! Push arithmetic for block onto control stack
    if (shell%control_depth < MAX_CONTROL_DEPTH) then
      shell%control_depth = shell%control_depth + 1
      shell%control_stack(shell%control_depth)%block_type = BLOCK_FOR_ARITH
      shell%control_stack(shell%control_depth)%arith_init = trim(init_expr)
      shell%control_stack(shell%control_depth)%arith_condition = trim(cond_expr)
      shell%control_stack(shell%control_depth)%arith_increment = trim(incr_expr)
      shell%control_stack(shell%control_depth)%arith_first_iteration = .true.
      shell%control_stack(shell%control_depth)%should_execute = .true.

      ! Execute initialization
      if (len_trim(init_expr) > 0) then
        result_value = arithmetic_expansion_shell('$((' // trim(init_expr) // '))', shell)
      end if
    else
      write(error_unit, '(a)') 'Error: Control flow nesting too deep'
    end if
  end subroutine

  subroutine process_then_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    should_execute = .false.  ! Don't execute the "then" keyword itself

    if (shell%control_depth == 0) then
      write(error_unit, '(a)') 'then: no matching if'
      shell%last_exit_status = 1
      return
    end if

    ! "then" marks the start of the if block
    ! For single-line if statements, the remaining tokens after "then" will be
    ! handled as separate commands by the main execution loop
  end subroutine

  subroutine process_else_statement(shell, should_execute)
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    should_execute = .false.  ! Don't execute the "else" keyword itself

    if (shell%control_depth == 0 .or. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_IF) then
      write(error_unit, '(a)') 'else: no matching if'
      shell%last_exit_status = 1
      return
    end if

    ! Switch to else branch - flip the execution logic
    shell%control_stack(shell%control_depth)%in_else_branch = .true.
    shell%control_stack(shell%control_depth)%should_execute = &
      .not. shell%control_stack(shell%control_depth)%condition_met
  end subroutine

  subroutine process_elif_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    logical :: condition_result
    integer :: i
    character(len=1024) :: condition_cmd

    should_execute = .false.  ! Don't execute the "elif" keyword itself

    if (shell%control_depth == 0 .or. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_IF) then
      write(error_unit, '(a)') 'elif: no matching if'
      shell%last_exit_status = 1
      return
    end if

    ! Parse elif condition: elif [ condition ] or elif command
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'elif: missing condition'
      shell%last_exit_status = 1
      return
    end if

    ! Build condition command from tokens (skip "elif")
    condition_cmd = ''
    do i = 2, cmd%num_tokens
      if (len_trim(condition_cmd) > 0) then
        condition_cmd = trim(condition_cmd) // ' ' // trim(cmd%tokens(i))
      else
        condition_cmd = trim(cmd%tokens(i))
      end if
    end do

    ! Only evaluate elif if previous conditions were false
    if (.not. shell%control_stack(shell%control_depth)%condition_met) then
      ! Evaluate condition
      call evaluate_condition(condition_cmd, shell, condition_result)

      ! Update control stack based on condition result
      shell%control_stack(shell%control_depth)%condition_met = condition_result
      shell%control_stack(shell%control_depth)%should_execute = condition_result
    else
      ! Previous condition was met, skip this elif
      shell%control_stack(shell%control_depth)%should_execute = .false.
    end if

    ! POSIX: Reset exit status after evaluating control flow condition
    ! The 'elif' keyword itself doesn't fail - it just sets up control state
    shell%last_exit_status = 0
  end subroutine

  subroutine process_fi_statement(shell, should_execute)
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    
    should_execute = .false.  ! Don't execute the "fi" keyword itself
    
    if (shell%control_depth == 0 .or. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_IF) then
      write(error_unit, '(a)') 'fi: no matching if'
      shell%last_exit_status = 1
      return
    end if
    
    ! Pop the if block from the stack
    call pop_control_block(shell)
  end subroutine

  subroutine process_do_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    character(len=1024) :: remainder_cmd
    integer :: i

    should_execute = .false.  ! Don't execute the "do" keyword itself

    if (shell%control_depth == 0) then
      write(error_unit, '(a)') 'do: no matching while/for'
      shell%last_exit_status = 1
      return
    end if

    ! "do" marks the start of the loop body - start capturing commands
    if (.not. allocated(shell%control_stack(shell%control_depth)%loop_body)) then
      allocate(shell%control_stack(shell%control_depth)%loop_body(100))
    end if

    shell%control_stack(shell%control_depth)%loop_body_count = 0
    shell%control_stack(shell%control_depth)%capturing_loop_body = .true.
    shell%control_stack(shell%control_depth)%capture_nesting_depth = 0

    ! Handle single-line loops: for x in a; do echo $x; done
    ! If there are tokens after "do", capture them as the first loop body command
    if (cmd%num_tokens > 1) then
      ! Build command from remaining tokens (skip "do")
      remainder_cmd = ''
      do i = 2, cmd%num_tokens
        if (len_trim(remainder_cmd) > 0) then
          remainder_cmd = trim(remainder_cmd) // ' ' // trim(cmd%tokens(i))
        else
          remainder_cmd = trim(cmd%tokens(i))
        end if
      end do

      ! Capture the command in the loop body
      if (len_trim(remainder_cmd) > 0) then
        call capture_loop_command(shell, trim(remainder_cmd))
      end if
    end if
  end subroutine

  subroutine process_done_statement(shell, should_execute)
    use expansion, only: arithmetic_expansion_shell
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute

    character(len=:), allocatable :: cond_result
    integer :: cond_value
    logical :: condition_result

    should_execute = .false.  ! Don't execute the "done" keyword itself

    if (shell%control_depth == 0) then
      ! Silently return if called when no loop is active (can happen during cleanup)
      shell%last_exit_status = 0
      return
    end if

    if (shell%control_stack(shell%control_depth)%block_type /= BLOCK_WHILE .and. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_UNTIL .and. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_FOR .and. &
        shell%control_stack(shell%control_depth)%block_type /= BLOCK_FOR_ARITH) then
      write(error_unit, '(a)') 'done: no matching while/for/until'
      shell%last_exit_status = 1
      return
    end if
    
    ! Stop capturing loop body
    shell%control_stack(shell%control_depth)%capturing_loop_body = .false.

    ! Check if break or continue was requested (for multi-level propagation)
    if (shell%control_stack(shell%control_depth)%break_requested) then
      ! Break requested - exit the loop
      shell%control_stack(shell%control_depth)%break_requested = .false.
      shell%control_stack(shell%control_depth)%break_level = 0
      ! Pop the control stack
      shell%control_depth = shell%control_depth - 1
      shell%last_exit_status = 0
      return
    end if

    if (shell%control_stack(shell%control_depth)%continue_requested) then
      ! Continue requested - skip to next iteration
      shell%control_stack(shell%control_depth)%continue_requested = .false.
      shell%control_stack(shell%control_depth)%continue_level = 0
      ! Don't return - fall through to iteration logic
    end if

    ! Handle for loop iteration
    if (shell%control_stack(shell%control_depth)%block_type == BLOCK_FOR) then
      ! Increment to next iteration value
      shell%control_stack(shell%control_depth)%for_index = &
        shell%control_stack(shell%control_depth)%for_index + 1

      ! Check if we have more iterations to do
      if (shell%control_stack(shell%control_depth)%for_index <= &
          shell%control_stack(shell%control_depth)%for_count .and. &
          allocated(shell%control_stack(shell%control_depth)%for_values)) then
        ! Set variable to current iteration value
        call set_shell_variable(shell, &
          trim(shell%control_stack(shell%control_depth)%loop_variable), &
          trim(shell%control_stack(shell%control_depth)%for_values(&
            shell%control_stack(shell%control_depth)%for_index)))

        ! Mark that we need to replay - executor will handle it
        ! Don't pop the stack, just return - executor will see loop needs replay
        return
      end if


    else if (shell%control_stack(shell%control_depth)%block_type == BLOCK_FOR_ARITH) then
      ! Arithmetic for loop: execute increment, then check condition
      ! Execute increment expression
      if (len_trim(shell%control_stack(shell%control_depth)%arith_increment) > 0) then
        cond_result = arithmetic_expansion_shell( &
          '$((' // trim(shell%control_stack(shell%control_depth)%arith_increment) // '))', shell)
      end if

      ! Evaluate condition
      if (len_trim(shell%control_stack(shell%control_depth)%arith_condition) > 0) then
        cond_result = arithmetic_expansion_shell( &
          '$((' // trim(shell%control_stack(shell%control_depth)%arith_condition) // '))', shell)

        ! Check if condition is true (non-zero)
        if (allocated(cond_result)) then
          read(cond_result, *, iostat=cond_value) cond_value
          if (cond_value == 0) cond_value = 0
        else
          cond_value = 0
        end if

        if (cond_value /= 0) then
          ! Condition is true - continue loop, executor will replay
          return
        end if
      else
        ! No condition means infinite loop - but we'll exit for now
        ! In a real implementation would loop back
      end if

    else if (shell%control_stack(shell%control_depth)%block_type == BLOCK_WHILE) then
      ! For while loops, re-evaluate condition and replay if true
      ! The condition is stored in condition_cmd

      if (len_trim(shell%control_stack(shell%control_depth)%condition_cmd) > 0) then
        ! Re-evaluate the while condition with current variable values
        call evaluate_condition(shell%control_stack(shell%control_depth)%condition_cmd, &
                               shell, condition_result)

        if (condition_result) then
          ! Condition is still true - executor will replay the loop body
          return
        end if

        ! POSIX: Reset exit status after loop condition check
        ! The 'done' keyword itself doesn't fail - it just ends the loop
        shell%last_exit_status = 0
      end if

    else if (shell%control_stack(shell%control_depth)%block_type == BLOCK_UNTIL) then
      ! For until loops, re-evaluate condition and replay if FALSE (inverted logic)
      ! The condition is stored in condition_cmd

      if (len_trim(shell%control_stack(shell%control_depth)%condition_cmd) > 0) then
        ! Re-evaluate the until condition with current variable values
        if (associated(evaluate_condition)) then
          call evaluate_condition(shell%control_stack(shell%control_depth)%condition_cmd, &
                                 shell, condition_result)
        else
          write(error_unit, '(a)') 'ERROR: evaluate_condition is not initialized!'
          condition_result = .false.
        end if

        ! until loops continue while condition is FALSE (opposite of while)
        if (.not. condition_result) then
          ! Condition is still false - executor will replay the loop body
          ! POSIX: Reset exit status before returning
          ! The 'done' keyword itself doesn't fail - it's checking loop continuation
          shell%last_exit_status = 0
          return
        end if

        ! POSIX: Reset exit status after loop condition check
        ! The 'done' keyword itself doesn't fail - it just ends the loop
        shell%last_exit_status = 0
      end if
    end if

    ! Pop the loop block from the stack
    call pop_control_block(shell)
  end subroutine

  subroutine push_control_block(shell, block_type, condition_met)
    type(shell_state_t), intent(inout) :: shell
    integer, intent(in) :: block_type
    logical, intent(in) :: condition_met
    
    if (shell%control_depth < MAX_CONTROL_DEPTH) then
      shell%control_depth = shell%control_depth + 1
      shell%control_stack(shell%control_depth)%block_type = block_type
      shell%control_stack(shell%control_depth)%condition_met = condition_met
      shell%control_stack(shell%control_depth)%in_else_branch = .false.
      shell%control_stack(shell%control_depth)%should_execute = condition_met
    else
      write(error_unit, '(a)') 'Error: Control flow nesting too deep'
    end if
  end subroutine

  subroutine pop_control_block(shell)
    type(shell_state_t), intent(inout) :: shell

    if (shell%control_depth > 0) then
      ! Deallocate for_values if allocated
      if (allocated(shell%control_stack(shell%control_depth)%for_values)) then
        deallocate(shell%control_stack(shell%control_depth)%for_values)
      end if
      ! Clear loop body to prevent replay in subsequent loops
      shell%control_stack(shell%control_depth)%loop_body_count = 0
      shell%control_stack(shell%control_depth)%capturing_loop_body = .false.
      shell%control_depth = shell%control_depth - 1
    end if
  end subroutine

  function should_execute_command(shell) result(should_exec)
    type(shell_state_t), intent(in) :: shell
    logical :: should_exec
    integer :: i
    
    should_exec = .true.
    
    ! Check all control blocks in the stack
    do i = 1, shell%control_depth
      if (.not. shell%control_stack(i)%should_execute) then
        should_exec = .false.
        exit
      end if
    end do
  end function


  ! Helper to tokenize and expand variables
  subroutine tokenize_and_expand(input, tokens, num_tokens, shell)
    character(len=*), intent(in) :: input
    character(len=256), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens
    type(shell_state_t), intent(inout) :: shell

    integer :: pos, start_pos
    character(len=256) :: expanded_token
    character(len=:), allocatable :: expanded_result

    num_tokens = 0
    start_pos = 1

    do while (start_pos <= len_trim(input) .and. num_tokens < size(tokens))
      ! Skip leading spaces
      do while (start_pos <= len_trim(input) .and. input(start_pos:start_pos) == ' ')
        start_pos = start_pos + 1
      end do

      if (start_pos > len_trim(input)) exit

      ! Find end of token
      pos = start_pos
      do while (pos <= len_trim(input) .and. input(pos:pos) /= ' ')
        pos = pos + 1
      end do

      ! Extract token and expand variables
      num_tokens = num_tokens + 1
      expanded_token = input(start_pos:pos-1)

      ! Expand variables in the token
      if (index(expanded_token, '$') > 0) then
        call simple_variable_expand(expanded_token, expanded_result, shell)
        if (allocated(expanded_result)) then
          tokens(num_tokens) = expanded_result
        else
          tokens(num_tokens) = expanded_token
        end if
      else
        tokens(num_tokens) = expanded_token
      end if

      start_pos = pos + 1
    end do
  end subroutine

  subroutine execute_test_condition(test_cmd, shell, result)
    use test_builtin, only: execute_test_command
    character(len=*), intent(in) :: test_cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: result

    type(command_t) :: cmd
    character(len=256) :: tokens(50), expanded_token
    integer :: num_tokens, i, pos, start_pos, test_exit_status
    character(len=1024) :: trimmed_cmd
    character(len=:), allocatable :: expanded_result

    ! Check if this is a [[ ]] expression
    trimmed_cmd = trim(test_cmd)

    if (index(trimmed_cmd, '[[') > 0) then
      ! This is an advanced test expression [[ ... ]]
      ! Tokenize the expression

      num_tokens = 0
      start_pos = 1

      ! Simple tokenization by spaces
      do while (start_pos <= len_trim(trimmed_cmd) .and. num_tokens < 50)
        ! Skip leading spaces
        do while (start_pos <= len_trim(trimmed_cmd) .and. trimmed_cmd(start_pos:start_pos) == ' ')
          start_pos = start_pos + 1
        end do

        if (start_pos > len_trim(trimmed_cmd)) exit

        ! Find end of token
        pos = start_pos
        do while (pos <= len_trim(trimmed_cmd) .and. trimmed_cmd(pos:pos) /= ' ')
          pos = pos + 1
        end do

        ! Extract token
        num_tokens = num_tokens + 1
        tokens(num_tokens) = trimmed_cmd(start_pos:pos-1)
        start_pos = pos + 1
      end do

      ! Call advanced test evaluator
      test_exit_status = evaluate_test_expression(shell, tokens, num_tokens)
      result = (test_exit_status == 0)

    else
      ! For [ ] test commands, tokenize and call the test builtin
      num_tokens = 0
      start_pos = 1

      do while (start_pos <= len_trim(trimmed_cmd) .and. num_tokens < 50)
        ! Skip leading spaces
        do while (start_pos <= len_trim(trimmed_cmd) .and. trimmed_cmd(start_pos:start_pos) == ' ')
          start_pos = start_pos + 1
        end do

        if (start_pos > len_trim(trimmed_cmd)) exit

        ! Find end of token
        pos = start_pos
        do while (pos <= len_trim(trimmed_cmd) .and. trimmed_cmd(pos:pos) /= ' ')
          pos = pos + 1
        end do

        ! Extract token and expand variables
        num_tokens = num_tokens + 1
        expanded_token = trimmed_cmd(start_pos:pos-1)

        ! Expand variables in the token (e.g., $count becomes the value of count)
        if (index(expanded_token, '$') > 0) then
          ! Use get_shell_variable for simple $var expansion
          ! parameter_expansion is only for ${var} format
          call simple_variable_expand(expanded_token, expanded_result, shell)
          if (allocated(expanded_result)) then
            tokens(num_tokens) = expanded_result
          else
            tokens(num_tokens) = expanded_token
          end if
        else
          tokens(num_tokens) = expanded_token
        end if

        start_pos = pos + 1
      end do

      ! If we have tokens and the first is '[' or 'test', execute the test builtin
      if (num_tokens > 0 .and. (trim(tokens(1)) == '[' .or. trim(tokens(1)) == 'test')) then
        ! Build command structure
        cmd%num_tokens = num_tokens
        allocate(character(len=256) :: cmd%tokens(num_tokens))
        do i = 1, num_tokens
          cmd%tokens(i) = trim(tokens(i))
        end do

        ! Execute the test command
        call execute_test_command(cmd, shell)

        ! Clean up
        deallocate(cmd%tokens)

        ! Check exit status
        result = (shell%last_exit_status == 0)
      else
        ! Fallback: check last exit status
        result = (shell%last_exit_status == 0)
      end if
    end if

  end subroutine

  function count_substring(string, substring) result(count)
    character(len=*), intent(in) :: string, substring
    integer :: count, pos, start
    
    count = 0
    start = 1
    do
      pos = index(string(start:), substring)
      if (pos == 0) exit
      count = count + 1
      start = start + pos + len(substring) - 1
    end do
  end function

  subroutine parse_for_values(block, list_str)
    type(control_block_t), intent(inout) :: block
    character(len=*), intent(in) :: list_str
    
    character(len=256) :: temp_values(20)  ! Max 20 values
    integer :: count, start_pos, end_pos, i
    
    count = 0
    start_pos = 1
    
    ! Parse space-separated values
    do
      ! Skip leading spaces
      do while (start_pos <= len_trim(list_str) .and. list_str(start_pos:start_pos) == ' ')
        start_pos = start_pos + 1
      end do
      
      if (start_pos > len_trim(list_str)) exit
      
      ! Find end of current word
      end_pos = start_pos
      do while (end_pos <= len_trim(list_str) .and. list_str(end_pos:end_pos) /= ' ')
        end_pos = end_pos + 1
      end do
      
      count = count + 1
      if (count <= 20) then
        temp_values(count) = list_str(start_pos:end_pos-1)
      end if
      
      start_pos = end_pos + 1
    end do
    
    block%for_count = count
    if (count > 0) then
      allocate(block%for_values(count))
      do i = 1, count
        block%for_values(i) = trim(temp_values(i))
      end do
    end if
  end subroutine

  subroutine process_function_statement(cmd, shell, should_execute)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell
    logical, intent(out) :: should_execute
    
    should_execute = .false.  ! Don't execute function definition itself
    
    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'function: missing function name'
      shell%last_exit_status = 1
      return
    end if
    
    write(output_unit, '(a)') 'function definitions not fully implemented yet'
    write(output_unit, '(a,a)') 'Would define function: ', trim(cmd%tokens(2))
  end subroutine

  ! Note: return and local are now implemented as builtins in builtins.f90
  ! Note: set_shell_variable is now imported from the variables module

  subroutine handle_case_statement(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=256) :: case_variable, expanded_value

    if (cmd%num_tokens < 3) then
      write(error_unit, '(a)') 'case: syntax error, expected "case variable in"'
      shell%last_exit_status = 1
      return
    end if

    if (trim(cmd%tokens(3)) /= 'in' .and. cmd%num_tokens >= 3) then
      write(error_unit, '(a)') 'case: syntax error, expected "in" keyword'
      shell%last_exit_status = 1
      return
    end if

    case_variable = trim(cmd%tokens(2))

    ! Expand the variable to get its value
    call expand_case_variable(shell, case_variable, expanded_value)

    ! Initialize case block
    if (shell%control_depth < MAX_CONTROL_DEPTH) then
      shell%control_depth = shell%control_depth + 1
      shell%control_stack(shell%control_depth)%block_type = BLOCK_CASE
      shell%control_stack(shell%control_depth)%condition_met = .false.
      shell%control_stack(shell%control_depth)%condition_cmd = expanded_value
      shell%control_stack(shell%control_depth)%loop_start_line = 0
      shell%control_stack(shell%control_depth)%case_found_match = .false.
      shell%control_stack(shell%control_depth)%case_in_match = .false.
    else
      write(error_unit, '(a)') 'case: control structure too deeply nested'
      shell%last_exit_status = 1
    end if
  end subroutine

  subroutine handle_case_pattern(cmd, shell)
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=1024) :: case_value  ! Increased to match condition_cmd length
    character(len=256) :: pattern
    logical :: pattern_matches
    integer :: i

    if (shell%control_depth == 0) then
      write(error_unit, '(a)') 'case pattern outside case statement'
      shell%last_exit_status = 1
      return
    end if

    if (shell%control_stack(shell%control_depth)%block_type /= BLOCK_CASE) then
      write(error_unit, '(a)') 'case pattern in wrong context'
      shell%last_exit_status = 1
      return
    end if

    ! If we've already found a match, skip all subsequent patterns
    if (shell%control_stack(shell%control_depth)%case_found_match) then
      shell%control_stack(shell%control_depth)%condition_met = .false.
      shell%control_stack(shell%control_depth)%case_in_match = .false.
      return
    end if

    ! Get the case value we're matching against
    case_value = shell%control_stack(shell%control_depth)%condition_cmd

    ! Check if any pattern matches - patterns end with )
    pattern_matches = .false.
    do i = 1, cmd%num_tokens
      if (index(cmd%tokens(i), ')') > 0) then
        ! Remove the ) from pattern
        pattern = cmd%tokens(i)
        if (len_trim(pattern) > 0 .and. pattern(len_trim(pattern):len_trim(pattern)) == ')') then
          pattern = pattern(1:len_trim(pattern)-1)
        end if

        ! Check for multi-pattern (e.g., a|b|c)
        ! Split on | and check each sub-pattern
        call check_multi_pattern(case_value, pattern, pattern_matches)

        if (pattern_matches) then
          exit
        end if
      end if
    end do

    ! Set condition based on pattern match
    shell%control_stack(shell%control_depth)%condition_met = pattern_matches
    shell%control_stack(shell%control_depth)%case_in_match = pattern_matches
    if (pattern_matches) then
      shell%control_stack(shell%control_depth)%case_found_match = .true.
    end if
  end subroutine

  subroutine handle_esac_statement(shell)
    type(shell_state_t), intent(inout) :: shell
    
    if (shell%control_depth == 0) then
      write(error_unit, '(a)') 'esac without matching case'
      shell%last_exit_status = 1
      return
    end if
    
    if (shell%control_stack(shell%control_depth)%block_type /= BLOCK_CASE) then
      write(error_unit, '(a)') 'esac without matching case'
      shell%last_exit_status = 1
      return
    end if
    
    ! Pop case block from stack
    shell%control_depth = shell%control_depth - 1
    shell%last_exit_status = 0
  end subroutine

  subroutine expand_case_variable(shell, variable_name, expanded_value)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: variable_name
    character(len=*), intent(out) :: expanded_value

    integer :: i

    expanded_value = ''

    ! Simple variable expansion
    if (variable_name(1:1) == '$') then
      ! Variable reference
      do i = 1, shell%num_variables
        if (trim(shell%variables(i)%name) == trim(variable_name(2:))) then
          expanded_value = trim(shell%variables(i)%value)
          return
        end if
      end do
      ! Variable not found - leave empty
      expanded_value = ''
    else
      ! Not a variable reference - use the literal value
      expanded_value = trim(variable_name)
    end if
  end subroutine

  function case_pattern_match(value, pattern) result(matches)
    character(len=*), intent(in) :: value, pattern
    logical :: matches

    ! Use the pattern_matches_no_dotfile_check function from glob module
    ! This handles *, ?, [abc], [!abc], [[:class:]], etc. correctly
    ! without the dotfile exclusion (which shouldn't apply to case statements)
    matches = pattern_matches_no_dotfile_check(trim(pattern), trim(value))
  end function

  ! Check multi-pattern (e.g., a|b|c) - split on | and check each
  subroutine check_multi_pattern(value, pattern_str, matches)
    character(len=*), intent(in) :: value, pattern_str
    logical, intent(out) :: matches

    character(len=256) :: sub_patterns(20)
    integer :: num_patterns, i, start_pos, pipe_pos
    character(len=256) :: remaining

    matches = .false.

    ! Check if pattern contains | (multi-pattern)
    if (index(pattern_str, '|') == 0) then
      ! Single pattern, just match directly
      matches = case_pattern_match(value, pattern_str)
      return
    end if

    ! Split on | to get individual patterns
    num_patterns = 0
    remaining = trim(pattern_str)

    do while (len_trim(remaining) > 0 .and. num_patterns < 20)
      pipe_pos = index(remaining, '|')
      if (pipe_pos > 0) then
        ! Found a |, extract pattern before it
        num_patterns = num_patterns + 1
        sub_patterns(num_patterns) = remaining(1:pipe_pos-1)
        remaining = remaining(pipe_pos+1:)
      else
        ! No more |, this is the last pattern
        num_patterns = num_patterns + 1
        sub_patterns(num_patterns) = remaining
        exit
      end if
    end do

    ! Check each sub-pattern
    do i = 1, num_patterns
      if (case_pattern_match(value, trim(sub_patterns(i)))) then
        matches = .true.
        return
      end if
    end do
  end subroutine

  ! Capture a command into the loop body buffer
  subroutine capture_loop_command(shell, command_line)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: command_line

    if (shell%control_depth == 0) return
    if (.not. shell%control_stack(shell%control_depth)%capturing_loop_body) return

    ! Add command to buffer
    shell%control_stack(shell%control_depth)%loop_body_count = &
      shell%control_stack(shell%control_depth)%loop_body_count + 1

    if (shell%control_stack(shell%control_depth)%loop_body_count <= 100) then
      shell%control_stack(shell%control_depth)%loop_body(&
        shell%control_stack(shell%control_depth)%loop_body_count) = command_line
    end if
  end subroutine

  ! Check if loop body replay is needed
  function should_replay_loop(shell) result(should_replay)
    type(shell_state_t), intent(in) :: shell
    logical :: should_replay

    should_replay = .false.
    if (shell%control_depth == 0) return
    if (shell%control_stack(shell%control_depth)%loop_body_count == 0) return

    should_replay = .true.
  end function

  ! Simple variable expansion for $var (not ${var})
  subroutine simple_variable_expand(input, output, shell)
    character(len=*), intent(in) :: input
    character(len=:), allocatable, intent(out) :: output
    type(shell_state_t), intent(inout) :: shell
    character(len=1024) :: result
    character(len=256) :: var_name
    character(len=1024) :: var_value
    integer :: i, j, var_start

    result = ''
    i = 1
    j = 1

    do while (i <= len_trim(input))
      if (input(i:i) == '$' .and. i < len_trim(input)) then
        i = i + 1
        var_start = i

        ! Extract variable name (alphanumeric + underscore)
        do while (i <= len_trim(input))
          if (.not. ((input(i:i) >= 'a' .and. input(i:i) <= 'z') .or. &
                     (input(i:i) >= 'A' .and. input(i:i) <= 'Z') .or. &
                     (input(i:i) >= '0' .and. input(i:i) <= '9') .or. &
                     input(i:i) == '_')) exit
          i = i + 1
        end do

        if (i > var_start) then
          var_name = input(var_start:i-1)
          var_value = get_shell_variable(shell, trim(var_name))
          if (len_trim(var_value) > 0) then
            result(j:j+len_trim(var_value)-1) = trim(var_value)
            j = j + len_trim(var_value)
          end if
        else
          ! Just a $ with no variable name
          result(j:j) = '$'
          j = j + 1
        end if
      else
        result(j:j) = input(i:i)
        i = i + 1
        j = j + 1
      end if
    end do

    output = trim(result)
  end subroutine

end module control_flow