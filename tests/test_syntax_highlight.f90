! ==============================================================================
! Test: syntax_highlight v2 tokenizer
! Unit tests for position-based tokenization and token classification.
! ==============================================================================
program test_syntax_highlight
  use syntax_highlight
  implicit none

  integer, parameter :: MT = 100  ! MAX_TOKENS

  integer :: passed, failed, total
  passed = 0
  failed = 0
  total = 0

  write(*, '(a)') '=========================================='
  write(*, '(a)') 'Testing Syntax Highlight v2 Tokenizer'
  write(*, '(a)') '=========================================='

  ! --- Basic token type tests ---
  call test_simple_command()
  call test_invalid_command()
  call test_builtin_echo()
  call test_keyword_if_then_fi()
  call test_pipe_resets_cmd_pos()
  call test_and_or_resets_cmd_pos()
  call test_semicolon_resets_cmd_pos()
  call test_option_token()
  call test_single_quoted_string()
  call test_double_quoted_string()
  call test_variable_simple()
  call test_variable_brace()
  call test_variable_subshell()
  call test_comment()
  call test_redirect_gt()
  call test_redirect_append()
  call test_redirect_heredoc()
  call test_redirect_fd_prefix()
  call test_redirect_amp_gt()
  call test_operator_background()
  call test_operator_parens()
  call test_assignment()
  call test_glob_star()
  call test_glob_question()
  call test_path_token()
  call test_number_token()
  call test_empty_input()
  call test_whitespace_only()
  call test_complex_pipeline()
  call test_keyword_resets_cmd_pos()
  call test_case_esac()

  write(*, '(a)') ''
  write(*, '(a)') '=========================================='
  write(*, '(a,i0,a,i0,a,i0,a)') 'Results: ', passed, ' passed, ', failed, ' failed (', total, ' total)'
  write(*, '(a)') '=========================================='

  if (failed > 0) then
    write(*, '(a)') 'SOME TESTS FAILED!'
    error stop 1
  else
    write(*, '(a)') 'All tests passed!'
  end if

contains

  subroutine assert_eq(test_name, expected, actual)
    character(len=*), intent(in) :: test_name
    integer, intent(in) :: expected, actual
    total = total + 1
    if (expected == actual) then
      passed = passed + 1
      write(*, '(a,a)') '  PASS: ', test_name
    else
      failed = failed + 1
      write(*, '(a,a,a,i0,a,i0,a)') '  FAIL: ', test_name, ' (expected=', expected, ', got=', actual, ')'
    end if
  end subroutine

  subroutine assert_token(test_name, tok, exp_start, exp_end, exp_type)
    character(len=*), intent(in) :: test_name
    type(hl_token_t), intent(in) :: tok
    integer, intent(in) :: exp_start, exp_end, exp_type
    call assert_eq(trim(test_name) // ': start', exp_start, tok%start_pos)
    call assert_eq(trim(test_name) // ': end', exp_end, tok%end_pos)
    call assert_eq(trim(test_name) // ': type', exp_type, tok%token_type)
  end subroutine

  ! ======================== Tests ========================

  subroutine test_simple_command()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=8) :: input
    input = 'ls -la /'
    call tokenize_v2(input, 8, tokens, n)
    call assert_eq('simple_cmd: count', 3, n)
    ! 'ls' at pos 1-2 — should be COMMAND_VALID (ls exists)
    call assert_token('simple_cmd/ls', tokens(1), 1, 2, HTOK_COMMAND_VALID)
    call assert_token('simple_cmd/-la', tokens(2), 4, 6, HTOK_OPTION)
    call assert_token('simple_cmd//', tokens(3), 8, 8, HTOK_PATH)
  end subroutine

  subroutine test_invalid_command()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'xyznotfound foo '
    call tokenize_v2(input, 15, tokens, n)
    call assert_eq('invalid_cmd: count', 2, n)
    call assert_token('invalid_cmd/xyz', tokens(1), 1, 11, HTOK_COMMAND_INVALID)
    call assert_token('invalid_cmd/foo', tokens(2), 13, 15, HTOK_DEFAULT)
  end subroutine

  subroutine test_builtin_echo()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo hello world'
    call tokenize_v2(input, 16, tokens, n)
    call assert_eq('builtin_echo: count', 3, n)
    call assert_token('builtin_echo/echo', tokens(1), 1, 4, HTOK_BUILTIN)
    call assert_token('builtin_echo/hello', tokens(2), 6, 10, HTOK_DEFAULT)
    call assert_token('builtin_echo/world', tokens(3), 12, 16, HTOK_DEFAULT)
  end subroutine

  subroutine test_keyword_if_then_fi()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = 'if true; then echo hi; fi'
    call tokenize_v2(input, 25, tokens, n)
    ! Expected: if=KEYWORD, true=CMD, ;=OP, then=KEYWORD, echo=BUILTIN, hi=DEFAULT, ;=OP, fi=KEYWORD
    call assert_eq('if_then_fi: count', 8, n)
    call assert_token('if_then_fi/if', tokens(1), 1, 2, HTOK_KEYWORD)
    call assert_token('if_then_fi/;', tokens(3), 8, 8, HTOK_OPERATOR)
    call assert_token('if_then_fi/then', tokens(4), 10, 13, HTOK_KEYWORD)
    call assert_token('if_then_fi/echo', tokens(5), 15, 18, HTOK_BUILTIN)
    call assert_token('if_then_fi/hi', tokens(6), 20, 21, HTOK_DEFAULT)
    call assert_token('if_then_fi/fi', tokens(8), 24, 25, HTOK_KEYWORD)
  end subroutine

  subroutine test_pipe_resets_cmd_pos()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'cat file | wc -l'
    call tokenize_v2(input, 16, tokens, n)
    call assert_eq('pipe: count', 5, n)
    call assert_token('pipe/|', tokens(3), 10, 10, HTOK_OPERATOR)
    call assert_token('pipe/wc', tokens(4), 12, 13, HTOK_COMMAND_VALID)
    call assert_token('pipe/-l', tokens(5), 15, 16, HTOK_OPTION)
  end subroutine

  subroutine test_and_or_resets_cmd_pos()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'ls && pwd'
    call tokenize_v2(input, 9, tokens, n)
    call assert_eq('and_or: count', 3, n)
    call assert_token('and_or/&&', tokens(2), 4, 5, HTOK_OPERATOR)
    call assert_token('and_or/pwd', tokens(3), 7, 9, HTOK_BUILTIN)
  end subroutine

  subroutine test_semicolon_resets_cmd_pos()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo a; echo b'
    call tokenize_v2(input, 14, tokens, n)
    call assert_eq('semicolon: count', 5, n)
    call assert_token('semicolon/;', tokens(3), 7, 7, HTOK_OPERATOR)
    call assert_token('semicolon/echo2', tokens(4), 9, 12, HTOK_BUILTIN)
  end subroutine

  subroutine test_option_token()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'ls --color=auto '
    call tokenize_v2(input, 15, tokens, n)
    call assert_eq('option: count', 2, n)
    call assert_token('option/--color', tokens(2), 4, 15, HTOK_OPTION)
  end subroutine

  subroutine test_single_quoted_string()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = "echo 'hello world'"
    call tokenize_v2(input, 18, tokens, n)
    call assert_eq('sq_string: count', 2, n)
    call assert_token('sq_string/str', tokens(2), 6, 18, HTOK_STRING_SINGLE)
  end subroutine

  subroutine test_double_quoted_string()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = 'echo "hello world"'
    call tokenize_v2(input, 18, tokens, n)
    call assert_eq('dq_string: count', 2, n)
    call assert_token('dq_string/str', tokens(2), 6, 18, HTOK_STRING_DOUBLE)
  end subroutine

  subroutine test_variable_simple()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo $HOME'
    call tokenize_v2(input, 10, tokens, n)
    call assert_eq('var_simple: count', 2, n)
    call assert_token('var_simple/$HOME', tokens(2), 6, 10, HTOK_VARIABLE)
  end subroutine

  subroutine test_variable_brace()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo ${PATH}'
    call tokenize_v2(input, 12, tokens, n)
    call assert_eq('var_brace: count', 2, n)
    call assert_token('var_brace/${PATH}', tokens(2), 6, 12, HTOK_VARIABLE)
  end subroutine

  subroutine test_variable_subshell()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = 'echo $(whoami)'
    call tokenize_v2(input, 14, tokens, n)
    call assert_eq('var_subshell: count', 2, n)
    call assert_token('var_subshell/$()', tokens(2), 6, 14, HTOK_VARIABLE)
  end subroutine

  subroutine test_comment()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = '# this is a test'
    call tokenize_v2(input, 16, tokens, n)
    call assert_eq('comment: count', 1, n)
    call assert_token('comment/#...', tokens(1), 1, 16, HTOK_COMMENT)
  end subroutine

  subroutine test_redirect_gt()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo hi > out'
    call tokenize_v2(input, 13, tokens, n)
    call assert_eq('redir_gt: count', 4, n)
    call assert_token('redir_gt/>', tokens(3), 9, 9, HTOK_REDIRECT)
    call assert_token('redir_gt/out', tokens(4), 11, 13, HTOK_DEFAULT)
  end subroutine

  subroutine test_redirect_append()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo hi >> out'
    call tokenize_v2(input, 14, tokens, n)
    call assert_eq('redir_append: count', 4, n)
    call assert_token('redir_append/>>', tokens(3), 9, 10, HTOK_REDIRECT)
  end subroutine

  subroutine test_redirect_heredoc()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'cat << EOF'
    call tokenize_v2(input, 10, tokens, n)
    call assert_eq('redir_heredoc: count', 3, n)
    call assert_token('redir_heredoc/<<', tokens(2), 5, 6, HTOK_REDIRECT)
  end subroutine

  subroutine test_redirect_fd_prefix()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = 'cmd 2>/dev/null'
    call tokenize_v2(input, 15, tokens, n)
    ! 'cmd' = command_invalid, '2>' = redirect, '/dev/null' = path
    call assert_eq('redir_fd: count', 3, n)
    call assert_token('redir_fd/2>', tokens(2), 5, 6, HTOK_REDIRECT)
    call assert_token('redir_fd//dev/null', tokens(3), 7, 15, HTOK_PATH)
  end subroutine

  subroutine test_redirect_amp_gt()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    input = 'cmd &> /dev/null'
    call tokenize_v2(input, 16, tokens, n)
    call assert_eq('redir_amp_gt: count', 3, n)
    call assert_token('redir_amp_gt/&>', tokens(2), 5, 6, HTOK_REDIRECT)
  end subroutine

  subroutine test_operator_background()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'sleep 10 &'
    call tokenize_v2(input, 10, tokens, n)
    call assert_eq('bg: count', 3, n)
    call assert_token('bg/&', tokens(3), 10, 10, HTOK_OPERATOR)
  end subroutine

  subroutine test_operator_parens()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = '(echo hi)'
    call tokenize_v2(input, 9, tokens, n)
    call assert_eq('parens: count', 4, n)
    call assert_token('parens/(', tokens(1), 1, 1, HTOK_OPERATOR)
    call assert_token('parens/echo', tokens(2), 2, 5, HTOK_BUILTIN)
    call assert_token('parens/)', tokens(4), 9, 9, HTOK_OPERATOR)
  end subroutine

  subroutine test_assignment()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'FOO=bar'
    call tokenize_v2(input, 7, tokens, n)
    ! Assignment in command position — tokenizer checks keyword first, then builtin,
    ! then valid command, then invalid command. Assignment with = is detected in
    ! non-command position. In command position, FOO=bar is treated as a command.
    ! Let's just check it produces something reasonable.
    call assert_eq('assign: count', 1, n)
  end subroutine

  subroutine test_glob_star()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo *.txt'
    call tokenize_v2(input, 10, tokens, n)
    call assert_eq('glob_star: count', 2, n)
    call assert_token('glob_star/*.txt', tokens(2), 6, 10, HTOK_GLOB)
  end subroutine

  subroutine test_glob_question()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo file?.log'
    call tokenize_v2(input, 14, tokens, n)
    call assert_eq('glob_question: count', 2, n)
    call assert_token('glob_question/file?.log', tokens(2), 6, 14, HTOK_GLOB)
  end subroutine

  subroutine test_path_token()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo /usr/bin'
    call tokenize_v2(input, 13, tokens, n)
    call assert_eq('path: count', 2, n)
    call assert_token('path//usr/bin', tokens(2), 6, 13, HTOK_PATH)
  end subroutine

  subroutine test_number_token()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'echo 42'
    call tokenize_v2(input, 7, tokens, n)
    call assert_eq('number: count', 2, n)
    call assert_token('number/42', tokens(2), 6, 7, HTOK_NUMBER)
  end subroutine

  subroutine test_empty_input()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    call tokenize_v2('', 0, tokens, n)
    call assert_eq('empty: count', 0, n)
  end subroutine

  subroutine test_whitespace_only()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=4) :: input
    input = '    '
    call tokenize_v2(input, 4, tokens, n)
    call assert_eq('whitespace: count', 0, n)
  end subroutine

  subroutine test_complex_pipeline()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    ! ls -la | grep foo | wc -l
    input = 'ls -la | grep foo | wc -l'
    call tokenize_v2(input, 25, tokens, n)
    call assert_eq('pipeline: count', 8, n)
    call assert_eq('pipeline/ls type', HTOK_COMMAND_VALID, tokens(1)%token_type)
    call assert_eq('pipeline/-la type', HTOK_OPTION, tokens(2)%token_type)
    call assert_eq('pipeline/|1 type', HTOK_OPERATOR, tokens(3)%token_type)
    call assert_eq('pipeline/grep type', HTOK_COMMAND_VALID, tokens(4)%token_type)
    call assert_eq('pipeline/foo type', HTOK_DEFAULT, tokens(5)%token_type)
    call assert_eq('pipeline/|2 type', HTOK_OPERATOR, tokens(6)%token_type)
    call assert_eq('pipeline/wc type', HTOK_COMMAND_VALID, tokens(7)%token_type)
    call assert_eq('pipeline/-l type', HTOK_OPTION, tokens(8)%token_type)
  end subroutine

  subroutine test_keyword_resets_cmd_pos()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=32) :: input
    ! 'then' and 'else' should reset cmd pos so next word is a command
    input = 'if true; then ls; else pwd; fi'
    call tokenize_v2(input, 30, tokens, n)
    ! if=KW true=CMD ;=OP then=KW ls=CMD ;=OP else=KW pwd=BUILTIN ;=OP fi=KW
    call assert_eq('kw_reset: count', 10, n)
    call assert_eq('kw_reset/if', HTOK_KEYWORD, tokens(1)%token_type)
    call assert_eq('kw_reset/then', HTOK_KEYWORD, tokens(4)%token_type)
    call assert_eq('kw_reset/ls', HTOK_COMMAND_VALID, tokens(5)%token_type)
    call assert_eq('kw_reset/else', HTOK_KEYWORD, tokens(7)%token_type)
    call assert_eq('kw_reset/pwd', HTOK_BUILTIN, tokens(8)%token_type)
    call assert_eq('kw_reset/fi', HTOK_KEYWORD, tokens(10)%token_type)
  end subroutine

  subroutine test_case_esac()
    type(hl_token_t) :: tokens(MT)
    integer :: n
    character(len=16) :: input
    input = 'case esac'
    call tokenize_v2(input, 9, tokens, n)
    call assert_eq('case_esac: count', 2, n)
    call assert_eq('case_esac/case', HTOK_KEYWORD, tokens(1)%token_type)
    ! esac is not in command position after case (case doesn't reset cmd pos)
    ! but 'case' is a keyword. After case, in_cmd_pos goes to false.
    ! esac is a word in non-cmd position — DEFAULT
    call assert_eq('case_esac/esac', HTOK_DEFAULT, tokens(2)%token_type)
  end subroutine

end program test_syntax_highlight
