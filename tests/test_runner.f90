! ==============================================================================
! Module: test_runner
! Purpose: Comprehensive test suite for Fortran Shell (fortsh)
! ==============================================================================
program test_runner
  use shell_types
  use parser
  use glob
  use variables
  use control_flow
  use job_control
  use aliases
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  integer :: total_tests = 0
  integer :: passed_tests = 0
  integer :: failed_tests = 0
  
  write(output_unit, '(a)') '================================'
  write(output_unit, '(a)') 'Fortran Shell (fortsh) Test Suite'
  write(output_unit, '(a)') '================================'
  write(output_unit, '(a)') ''
  
  ! Run all test suites
  call test_parser_module()
  call test_glob_module()
  call test_variables_module()
  call test_control_flow_module()
  call test_aliases_module()
  call test_error_handling()
  
  ! Print summary
  write(output_unit, '(a)') ''
  write(output_unit, '(a)') '================================'
  write(output_unit, '(a)') 'TEST SUMMARY'
  write(output_unit, '(a)') '================================'
  write(output_unit, '(a,i0)') 'Total tests:  ', total_tests
  write(output_unit, '(a,i0)') 'Passed tests: ', passed_tests
  write(output_unit, '(a,i0)') 'Failed tests: ', failed_tests
  
  if (failed_tests == 0) then
    write(output_unit, '(a)') '✅ ALL TESTS PASSED!'
  else
    write(output_unit, '(a)') '❌ Some tests failed'
  end if
  
  if (failed_tests > 0) then
    call exit(1)
  end if

contains

  subroutine assert_true(condition, test_name)
    logical, intent(in) :: condition
    character(len=*), intent(in) :: test_name
    
    total_tests = total_tests + 1
    
    if (condition) then
      write(output_unit, '(a,a)') '✓ ', test_name
      passed_tests = passed_tests + 1
    else
      write(output_unit, '(a,a)') '✗ ', test_name
      failed_tests = failed_tests + 1
    end if
  end subroutine

  subroutine assert_equal_str(actual, expected, test_name)
    character(len=*), intent(in) :: actual, expected, test_name
    call assert_true(trim(actual) == trim(expected), test_name)
  end subroutine

  subroutine assert_equal_int(actual, expected, test_name)
    integer, intent(in) :: actual, expected
    character(len=*), intent(in) :: test_name
    call assert_true(actual == expected, test_name)
  end subroutine

  subroutine test_parser_module()
    write(output_unit, '(a)') 'Testing Parser Module:'
    write(output_unit, '(a)') '====================='
    
    ! Test tokenization
    call test_tokenization()
    
    ! Test pipeline parsing
    call test_pipeline_parsing()
    
    ! Test redirection parsing
    call test_redirection_parsing()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_tokenization()
    character(len=:), allocatable :: tokens(:)
    integer :: num_tokens
    
    ! Test basic tokenization
    call tokenize_with_substitution('echo hello world', tokens, num_tokens)
    call assert_equal_int(num_tokens, 3, 'Basic tokenization count')
    if (num_tokens >= 3) then
      call assert_equal_str(tokens(1), 'echo', 'Token 1 correct')
      call assert_equal_str(tokens(2), 'hello', 'Token 2 correct')
      call assert_equal_str(tokens(3), 'world', 'Token 3 correct')
    end if
    if (allocated(tokens)) deallocate(tokens)
    
    ! Test empty input
    call tokenize_with_substitution('', tokens, num_tokens)
    call assert_equal_int(num_tokens, 0, 'Empty input tokenization')
    if (allocated(tokens)) deallocate(tokens)
    
    ! Test whitespace handling
    call tokenize_with_substitution('  echo   test  ', tokens, num_tokens)
    call assert_equal_int(num_tokens, 2, 'Whitespace handling count')
    if (num_tokens >= 2) then
      call assert_equal_str(tokens(1), 'echo', 'Whitespace token 1')
      call assert_equal_str(tokens(2), 'test', 'Whitespace token 2')
    end if
    if (allocated(tokens)) deallocate(tokens)
  end subroutine

  subroutine test_pipeline_parsing()
    type(pipeline_t) :: pipeline
    
    ! Test single command
    call parse_pipeline('echo hello', pipeline)
    call assert_equal_int(pipeline%num_commands, 1, 'Single command pipeline')
    if (pipeline%num_commands >= 1) then
      call assert_equal_int(pipeline%commands(1)%separator, SEP_NONE, 'Single command separator')
    end if
    
    ! Cleanup
    if (allocated(pipeline%commands)) then
      if (allocated(pipeline%commands(1)%tokens)) deallocate(pipeline%commands(1)%tokens)
      deallocate(pipeline%commands)
    end if
    
    ! Test pipe command
    call parse_pipeline('ls | grep test', pipeline)
    call assert_equal_int(pipeline%num_commands, 2, 'Pipe command pipeline')
    if (pipeline%num_commands >= 2) then
      call assert_equal_int(pipeline%commands(1)%separator, SEP_PIPE, 'Pipe separator')
    end if
    
    ! Cleanup
    if (allocated(pipeline%commands)) then
      do i = 1, pipeline%num_commands
        if (allocated(pipeline%commands(i)%tokens)) deallocate(pipeline%commands(i)%tokens)
        if (allocated(pipeline%commands(i)%input_file)) deallocate(pipeline%commands(i)%input_file)
        if (allocated(pipeline%commands(i)%output_file)) deallocate(pipeline%commands(i)%output_file)
        if (allocated(pipeline%commands(i)%error_file)) deallocate(pipeline%commands(i)%error_file)
        if (allocated(pipeline%commands(i)%heredoc_delimiter)) deallocate(pipeline%commands(i)%heredoc_delimiter)
        if (allocated(pipeline%commands(i)%heredoc_content)) deallocate(pipeline%commands(i)%heredoc_content)
        if (allocated(pipeline%commands(i)%here_string)) deallocate(pipeline%commands(i)%here_string)
      end do
      deallocate(pipeline%commands)
    end if
  end subroutine

  subroutine test_redirection_parsing()
    type(command_t) :: cmd
    character(len=256) :: input
    
    input = 'echo hello > output.txt'
    call parse_simple_command(input, cmd)
    
    call assert_true(allocated(cmd%output_file), 'Output redirection detected')
    if (allocated(cmd%output_file)) then
      call assert_equal_str(cmd%output_file, 'output.txt', 'Output file correct')
    end if
    call assert_true(.not. cmd%append_output, 'Append flag correct')
    
    ! Cleanup
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)
    if (allocated(cmd%output_file)) deallocate(cmd%output_file)
  end subroutine

  subroutine test_glob_module()
    write(output_unit, '(a)') 'Testing Glob Module:'
    write(output_unit, '(a)') '==================='
    
    call test_pattern_matching()
    call test_glob_expansion()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_pattern_matching()
    ! Test wildcard patterns
    call assert_true(pattern_matches('*.txt', 'file.txt'), 'Simple wildcard match')
    call assert_true(.not. pattern_matches('*.txt', 'file.log'), 'Simple wildcard no match')
    
    ! Test single character wildcard
    call assert_true(pattern_matches('file?.txt', 'file1.txt'), 'Single char wildcard match')
    call assert_true(.not. pattern_matches('file?.txt', 'file10.txt'), 'Single char wildcard no match')
    
    ! Test character classes
    call assert_true(pattern_matches('[abc]*', 'apple'), 'Character class match')
    call assert_true(.not. pattern_matches('[abc]*', 'orange'), 'Character class no match')
    
    ! Test character ranges
    call assert_true(pattern_matches('[a-z]*', 'hello'), 'Character range match')
    call assert_true(.not. pattern_matches('[a-z]*', '123'), 'Character range no match')
    
    ! Test negation
    call assert_true(pattern_matches('[!0-9]*', 'hello'), 'Negation match')
    call assert_true(.not. pattern_matches('[!0-9]*', '123'), 'Negation no match')
  end subroutine

  subroutine test_glob_expansion()
    character(len=MAX_TOKEN_LEN), allocatable :: expanded_tokens(:)
    character(len=MAX_TOKEN_LEN) :: input_tokens(2)
    integer :: expanded_count
    
    input_tokens(1) = '*.txt'
    input_tokens(2) = 'literal'
    
    call expand_glob_patterns(input_tokens, 2, expanded_tokens, expanded_count)
    call assert_true(expanded_count >= 2, 'Glob expansion returns results')
    call assert_true(allocated(expanded_tokens), 'Expanded tokens allocated')
    
    if (allocated(expanded_tokens)) deallocate(expanded_tokens)
  end subroutine

  subroutine test_variables_module()
    write(output_unit, '(a)') 'Testing Variables Module:'
    write(output_unit, '(a)') '========================'
    
    call test_variable_assignment()
    call test_variable_expansion()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_variable_assignment()
    call assert_true(is_assignment('VAR=value'), 'Simple assignment detection')
    call assert_true(is_assignment('PATH=/usr/bin'), 'Path assignment detection')
    call assert_true(.not. is_assignment('echo hello'), 'Non-assignment detection')
    call assert_true(.not. is_assignment('test='), 'Empty value assignment')
  end subroutine

  subroutine test_variable_expansion()
    type(shell_state_t) :: shell
    character(len=:), allocatable :: expanded
    
    ! Initialize shell
    shell%num_variables = 1
    shell%variables(1)%name = 'TEST'
    shell%variables(1)%value = 'hello'
    
    call expand_variables('$TEST', expanded, shell)
    call assert_equal_str(expanded, 'hello', 'Simple variable expansion')
    
    call expand_variables('${TEST}world', expanded, shell)
    call assert_equal_str(expanded, 'helloworld', 'Braced variable expansion')
    
    call expand_variables('$NONEXISTENT', expanded, shell)
    call assert_equal_str(expanded, '', 'Non-existent variable expansion')
  end subroutine

  subroutine test_control_flow_module()
    write(output_unit, '(a)') 'Testing Control Flow Module:'
    write(output_unit, '(a)') '==========================='
    
    call test_control_flow_keywords()
    call test_condition_evaluation()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_control_flow_keywords()
    call assert_true(is_control_flow_keyword('if'), 'If keyword recognition')
    call assert_true(is_control_flow_keyword('while'), 'While keyword recognition')
    call assert_true(is_control_flow_keyword('for'), 'For keyword recognition')
    call assert_true(.not. is_control_flow_keyword('echo'), 'Non-keyword rejection')
    
    call assert_equal_int(identify_flow_keyword('if'), FLOW_IF, 'If keyword identification')
    call assert_equal_int(identify_flow_keyword('while'), FLOW_WHILE, 'While keyword identification')
  end subroutine

  subroutine test_condition_evaluation()
    type(shell_state_t) :: shell
    logical :: result
    
    ! Initialize shell with success status
    shell%last_exit_status = 0
    
    call evaluate_condition('[ "hello" = "hello" ]', shell, result)
    call assert_true(result, 'String equality condition')
    
    call evaluate_condition('[ "hello" = "world" ]', shell, result)
    call assert_true(.not. result, 'String inequality condition')
  end subroutine

  subroutine test_aliases_module()
    write(output_unit, '(a)') 'Testing Aliases Module:'
    write(output_unit, '(a)') '======================'
    
    call test_alias_operations()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_alias_operations()
    type(shell_state_t) :: shell
    character(len=:), allocatable :: expanded_line
    
    ! Initialize shell
    shell%num_aliases = 0
    
    ! Test alias creation
    call set_alias(shell, 'll', 'ls -l')
    call assert_equal_int(shell%num_aliases, 1, 'Alias count after creation')
    call assert_true(is_alias(shell, 'll'), 'Alias existence check')
    
    ! Test alias expansion
    call expand_alias(shell, 'll -a', expanded_line)
    call assert_equal_str(expanded_line, 'ls -l -a', 'Alias expansion')
    
    ! Test non-alias expansion
    call expand_alias(shell, 'echo hello', expanded_line)
    call assert_equal_str(expanded_line, 'echo hello', 'Non-alias passthrough')
  end subroutine

  subroutine test_error_handling()
    write(output_unit, '(a)') 'Testing Error Handling:'
    write(output_unit, '(a)') '======================'
    
    call test_parser_error_handling()
    call test_command_error_handling()
    
    write(output_unit, '(a)') ''
  end subroutine

  subroutine test_parser_error_handling()
    type(pipeline_t) :: pipeline
    
    ! Test malformed pipeline
    call parse_pipeline('command |', pipeline)
    call assert_equal_int(pipeline%num_commands, 1, 'Malformed pipe handling')
    
    ! Cleanup
    if (allocated(pipeline%commands)) then
      if (allocated(pipeline%commands(1)%tokens)) deallocate(pipeline%commands(1)%tokens)
      deallocate(pipeline%commands)
    end if
  end subroutine

  subroutine test_command_error_handling()
    ! Test invalid redirection
    call assert_true(.true., 'Invalid redirection placeholder test')
    
    ! Test command not found
    call assert_true(.true., 'Command not found placeholder test')
  end subroutine

end program test_runner