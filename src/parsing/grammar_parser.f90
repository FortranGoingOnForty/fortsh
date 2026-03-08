! Grammar Parser - Streamlined working version
module grammar_parser
  use iso_fortran_env
  use shell_types
  use lexer
  use command_tree, only: command_node_t, create_simple_command, create_pipeline, &
                          create_list, create_if_statement, create_while_loop, &
                          create_for_loop, create_case_statement, create_subshell, &
                          create_brace_group, create_function_def, destroy_command_node, &
                          print_command_tree, case_item_t, LIST_SEP_SEQUENTIAL, &
                          LIST_SEP_AND, LIST_SEP_OR, LIST_SEP_BACKGROUND
  implicit none
  private
  public :: parse_with_grammar, parse_command_line, last_parse_had_error

  ! Module-level variable to track if last parse had an error
  logical :: last_parse_had_error = .false.

  type :: parser_state_t
    type(token_t) :: tokens(MAX_TOKENS)
    integer :: num_tokens = 0
    integer :: pos = 1
    integer :: current_line = 1  ! Track line number for LINENO
    logical :: has_error = .false.
    character(len=1024) :: error_msg = ''
    character(len=:), allocatable :: raw_input  ! For heredoc extraction
  end type parser_state_t

contains

  function parse_command_line(input) result(root)
    character(len=*), intent(in) :: input
    type(command_node_t), pointer :: root
    type(parser_state_t) :: state
    state%raw_input = input  ! Save for heredoc parsing
    call tokenize(input, state%tokens, state%num_tokens)
    state%pos = 1
    root => parse_complete_command(state)
    if (state%has_error .and. associated(root)) then
      call destroy_command_node(root)
      nullify(root)
    end if
    ! Expose error status to caller
    last_parse_had_error = state%has_error
  end function

  subroutine parse_with_grammar(input, pipeline, shell)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline
    type(shell_state_t), intent(inout) :: shell
    pipeline%num_commands = 0
    ! Silence unused warnings
    if (.false.) print *, input, shell%control_depth
  end subroutine

  function current_token(state) result(tok)
    type(parser_state_t), intent(in) :: state
    type(token_t) :: tok
    if (state%pos <= state%num_tokens) then
      tok = state%tokens(state%pos)
    else
      tok%token_type = TOKEN_EOF
    end if
  end function

  subroutine advance(state)
    type(parser_state_t), intent(inout) :: state
    if (state%pos <= state%num_tokens) state%pos = state%pos + 1
  end subroutine

  function match(state, expected) result(matched)
    type(parser_state_t), intent(inout) :: state
    character(len=*), intent(in) :: expected
    logical :: matched
    type(token_t) :: tok
    tok = current_token(state)
    matched = (trim(tok%value) == trim(expected))
    if (matched) call advance(state)
  end function

  function expect(state, expected) result(success)
    type(parser_state_t), intent(inout) :: state
    character(len=*), intent(in) :: expected
    logical :: success
    success = match(state, expected)
    if (.not. success) then
      state%has_error = .true.
      state%error_msg = 'expected "' // trim(expected) // '"'
    end if
  end function

  recursive function parse_complete_command(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node
    type(token_t) :: tok
    ! Skip leading newlines (e.g., from comment-only lines)
    call skip_newlines(state)
    node => parse_list(state)
    tok = current_token(state)
    do while (tok%token_type == TOKEN_NEWLINE)
      call advance(state)
      tok = current_token(state)
    end do
  end function

  recursive function parse_list(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, right_node
    type(token_t) :: tok
    integer :: sep_type
    node => parse_and_or(state)
    if (.not. associated(node)) then
      ! Check for leading separator (syntax error)
      tok = current_token(state)
      if (tok%token_type == TOKEN_OPERATOR .and. &
          (trim(tok%value) == ';' .or. trim(tok%value) == ';;' .or. trim(tok%value) == '&')) then
        write(error_unit, '(A)') 'sh: -c: line 1: syntax error near unexpected token `' // trim(tok%value) // "'"
        if (allocated(state%raw_input)) then
          write(error_unit, '(A)') "sh: -c: line 1: `" // trim(state%raw_input) // "'"
        end if
        state%has_error = .true.
        state%error_msg = 'syntax error near unexpected token ' // trim(tok%value)
      end if
      return
    end if
    do while (.true.)
      tok = current_token(state)
      if (tok%token_type == TOKEN_KEYWORD) then
        if (trim(tok%value) == 'done' .or. trim(tok%value) == 'fi' .or. &
            trim(tok%value) == 'else' .or. trim(tok%value) == 'elif' .or. &
            trim(tok%value) == 'esac' .or. trim(tok%value) == 'then') exit
      end if
      if (tok%token_type == TOKEN_OPERATOR .and. (trim(tok%value) == ')' .or. trim(tok%value) == '}')) exit
      if (tok%token_type == TOKEN_OPERATOR) then
        if (trim(tok%value) == ';') then
          sep_type = LIST_SEP_SEQUENTIAL
          call advance(state)
          ! Skip any newlines after semicolon (e.g., semicolon at end of line)
          call skip_newlines(state)
        else if (trim(tok%value) == ';;') then
          ! ;; is only valid in case statements, not here
          write(error_unit, '(A)') 'sh: -c: line 1: syntax error near unexpected token `;;'''
          if (allocated(state%raw_input)) then
            write(error_unit, '(A)') "sh: -c: line 1: `" // trim(state%raw_input) // "'"
          end if
          ! Set error and return null
          state%has_error = .true.
          state%error_msg = 'syntax error near unexpected token ;;'
          nullify(node)
          return
        else if (trim(tok%value) == '&') then
          sep_type = LIST_SEP_BACKGROUND
          call advance(state)
          ! Skip any newlines after ampersand (e.g., background at end of line)
          call skip_newlines(state)
        else
          exit
        end if
      else if (tok%token_type == TOKEN_NEWLINE) then
        sep_type = LIST_SEP_SEQUENTIAL
        state%current_line = state%current_line + 1  ! Track this newline for LINENO
        call advance(state)
        ! Skip any additional newlines (e.g., from comment-only lines)
        call skip_newlines(state)
      else
        exit
      end if
      tok = current_token(state)
      if (tok%token_type == TOKEN_KEYWORD) then
        if (trim(tok%value) == 'done' .or. trim(tok%value) == 'fi' .or. &
            trim(tok%value) == 'else' .or. trim(tok%value) == 'elif' .or. &
            trim(tok%value) == 'esac' .or. trim(tok%value) == 'then') exit
      end if
      right_node => parse_and_or(state)
      ! Create LIST node even if right side is null (for background jobs at end of input)
      if (.not. associated(right_node) .and. sep_type /= LIST_SEP_BACKGROUND) exit
      node => create_list(node, right_node, sep_type)
      if (.not. associated(right_node)) exit
    end do
  end function

  recursive function parse_and_or(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, right_node
    type(token_t) :: tok
    integer :: sep_type
    node => parse_pipeline_node(state)
    if (.not. associated(node)) return
    do while (.true.)
      tok = current_token(state)
      if (tok%token_type == TOKEN_OPERATOR) then
        if (trim(tok%value) == '&&') then
          sep_type = LIST_SEP_AND
          call advance(state)
        else if (trim(tok%value) == '||') then
          sep_type = LIST_SEP_OR
          call advance(state)
        else
          exit
        end if
      else
        exit
      end if
      call skip_newlines(state)
      right_node => parse_pipeline_node(state)
      if (.not. associated(right_node)) then
        state%has_error = .true.
        exit
      end if
      node => create_list(node, right_node, sep_type)
    end do
  end function

  recursive function parse_pipeline_node(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, temp_node, commands(:)
    integer :: num_commands
    logical :: negate
    type(token_t) :: tok
    negate = .false.
    num_commands = 0
    tok = current_token(state)
    if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == '!') then
      negate = .true.
      call advance(state)
      call skip_newlines(state)
    end if
    node => parse_command_node(state)
    if (.not. associated(node)) return
    tok = current_token(state)
    if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '|') then
      allocate(commands(10))
      num_commands = 1
      commands(1) = node
      do while (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '|')
        call advance(state)
        call skip_newlines(state)
        if (num_commands >= 10) exit
        temp_node => parse_command_node(state)
        if (.not. associated(temp_node)) then
          ! Incomplete pipeline - set error, print message, and exit
          write(error_unit, '(A)') 'sh: -c: line 1: syntax error: unexpected end of file'
          state%has_error = .true.
          exit
        end if
        num_commands = num_commands + 1
        commands(num_commands) = temp_node
        tok = current_token(state)
      end do
      if (state%has_error) then
        ! Error occurred - return null
        nullify(node)
      else
        node => create_pipeline(commands, num_commands, negate)
      end if
    else if (negate) then
      allocate(commands(1))
      commands(1) = node
      node => create_pipeline(commands, 1, .true.)
    end if
  end function

  recursive function parse_command_node(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node
    type(token_t) :: tok, next_tok
    logical :: is_compound
    tok = current_token(state)
    is_compound = .false.
    if (tok%token_type == TOKEN_KEYWORD) then
      select case(trim(tok%value))
      case('!')
        ! Nested negation - parse as a pipeline with negation
        node => parse_pipeline_node(state)
        is_compound = .true.
      case('if')
        node => parse_if_stmt(state)
        is_compound = .true.
      case('while')
        node => parse_while_stmt(state, .false.)
        is_compound = .true.
      case('until')
        node => parse_while_stmt(state, .true.)
        is_compound = .true.
      case('for')
        node => parse_for_stmt(state)
        is_compound = .true.
      case('case')
        node => parse_case_stmt(state)
        is_compound = .true.
      case('{')
        node => parse_brace_group(state)
        is_compound = .true.
      case default
        node => parse_simple_cmd(state)
      end select
    else if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '(') then
      ! Check if this is (( for arithmetic command vs ( for subshell
      ! Key: (( with no space = arithmetic, ( ( with space = nested subshell
      next_tok = peek_token(state%tokens, state%pos + 1)
      if (next_tok%token_type == TOKEN_OPERATOR .and. trim(next_tok%value) == '(' .and. &
          tok%end_pos + 1 == next_tok%start_pos) then
        ! Adjacent (( - treat as arithmetic
        node => parse_arithmetic_command(state)
      else
        node => parse_subshell(state)
      end if
      is_compound = .true.
    else
      node => parse_simple_cmd(state)
    end if

    ! Parse trailing redirections for compound commands
    ! (simple commands already handle redirections internally)
    if (is_compound .and. associated(node)) then
      call parse_trailing_redirections(state, node)
    end if
  end function

  function parse_simple_cmd(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, func_body
    character(len=MAX_TOKEN_LEN) :: words(MAX_TOKENS), func_name, delimiter, merged_word
    logical :: was_quoted(MAX_TOKENS), was_escaped(MAX_TOKENS)
    integer :: quote_types(MAX_TOKENS), word_lens(MAX_TOKENS)
    character(len=MAX_TOKEN_LEN) :: saved_heredoc_delimiter
    logical :: saved_heredoc_quoted
    logical :: saved_heredoc_strip_tabs
    logical :: has_heredoc
    type(redirection_t) :: redirects(10)
    integer :: num_words, num_redirects, i, fd_num, io_stat, saved_pos
    type(token_t) :: tok, next_tok, peek_tok, delim_tok
    ! Prefix assignments (VAR=value before command)
    character(len=MAX_TOKEN_LEN) :: assignments(10)
    integer :: assignment_lens(10)
    integer :: num_assignments, eq_pos
    logical :: seen_command
    num_words = 0
    num_redirects = 0
    num_assignments = 0
    assignment_lens = 0
    seen_command = .false.
    nullify(node)
    was_quoted = .false.
    was_escaped = .false.
    quote_types = QUOTE_NONE
    word_lens = 0
    has_heredoc = .false.
    saved_heredoc_quoted = .false.
    saved_heredoc_strip_tabs = .false.
    saved_heredoc_delimiter = ''

    ! Check for function definition: name() { ... }
    tok = current_token(state)
    if (tok%token_type == TOKEN_WORD) then
      saved_pos = state%pos
      func_name = tok%value
      call advance(state)
      peek_tok = current_token(state)

      if (peek_tok%token_type == TOKEN_OPERATOR .and. trim(peek_tok%value) == '(') then
        call advance(state)
        peek_tok = current_token(state)
        if (peek_tok%token_type == TOKEN_OPERATOR .and. trim(peek_tok%value) == ')') then
          call advance(state)
          call skip_newlines(state)
          peek_tok = current_token(state)
          if (peek_tok%token_type == TOKEN_KEYWORD .and. trim(peek_tok%value) == '{') then
            ! This is a function definition!
            func_body => parse_brace_group(state)
            node => create_function_def(func_name, func_body)
            return
          end if
        end if
      end if
      ! Not a function, restore position
      state%pos = saved_pos
    end if

    do while (.true.)
      tok = current_token(state)
      ! Accept TOKEN_WORD, or TOKEN_KEYWORD if we already have a command (num_words > 0)
      ! This allows "echo done" to work while preventing "done" from being a command
      if (tok%token_type == TOKEN_WORD .or. &
          (tok%token_type == TOKEN_KEYWORD .and. num_words > 0)) then
        ! Check if this is an assignment (VAR= followed by value)
        ! Use actual token length (end_pos - start_pos + 1) instead of len_trim to preserve whitespace
        ! Require at least one char before '=' to avoid treating standalone '=' as assignment
        ! Also check that it's not a != operator (where = is preceded by !)
        eq_pos = index(tok%value, '=')
        if (eq_pos > 1 .and. &
            eq_pos == (tok%end_pos - tok%start_pos + 1) .and. &
            tok%value(eq_pos-1:eq_pos-1) /= '!') then
          ! This ends with = , check if next token is the value
          call advance(state)
          next_tok = current_token(state)
          if (next_tok%token_type == TOKEN_WORD) then
            ! Merge: VAR= + value → VAR=value
            ! For quoted tokens, preserve whitespace by using actual token length
            if (next_tok%quoted) then
              merged_word = trim(tok%value) // next_tok%value(1:next_tok%end_pos - next_tok%start_pos + 1 - 2)
            else
              merged_word = trim(tok%value) // trim(next_tok%value)
            end if
            ! Check if this is a prefix assignment (before command) or regular word
            if (.not. seen_command .and. num_assignments < 10) then
              ! This is a prefix assignment
              num_assignments = num_assignments + 1
              assignments(num_assignments) = merged_word
              ! Calculate actual length
              if (next_tok%quoted) then
                assignment_lens(num_assignments) = len_trim(tok%value) + (next_tok%end_pos - next_tok%start_pos + 1 - 2)
              else
                assignment_lens(num_assignments) = len_trim(tok%value) + len_trim(next_tok%value)
              end if
            else
              ! This is a regular word (assignment after command name)
              if (num_words < MAX_TOKENS) then
                num_words = num_words + 1
                words(num_words) = merged_word
                was_quoted(num_words) = next_tok%quoted
                was_escaped(num_words) = next_tok%escaped
                quote_types(num_words) = next_tok%quote_type
                if (next_tok%quoted) then
                  word_lens(num_words) = len_trim(tok%value) + (next_tok%end_pos - next_tok%start_pos + 1 - 2)
                else
                  word_lens(num_words) = len_trim(merged_word)
                end if
              end if
            end if
            call advance(state)
          else
            ! Just VAR= without value
            if (.not. seen_command .and. num_assignments < 10) then
              num_assignments = num_assignments + 1
              assignments(num_assignments) = tok%value
              assignment_lens(num_assignments) = tok%end_pos - tok%start_pos + 1
            else
              if (num_words < MAX_TOKENS) then
                num_words = num_words + 1
                words(num_words) = tok%value
                was_quoted(num_words) = tok%quoted
                was_escaped(num_words) = tok%escaped
                quote_types(num_words) = tok%quote_type
                ! For quoted tokens (fully or partially), use value_length (preserves trailing whitespace)
                if (tok%quote_type == QUOTE_DOUBLE .or. tok%quote_type == QUOTE_SINGLE .or. tok%quoted) then
                  word_lens(num_words) = tok%value_length
                else
                  word_lens(num_words) = len_trim(tok%value)
                end if
              end if
            end if
          end if
        else
          ! Check if this is a complete assignment (VAR=value) before the command
          eq_pos = index(tok%value, '=')
          if (.not. seen_command .and. eq_pos > 1 .and. &
              is_valid_assignment_name(tok%value(1:eq_pos-1)) .and. &
              num_assignments < 10) then
            ! This is a prefix assignment
            num_assignments = num_assignments + 1
            assignments(num_assignments) = tok%value
            ! Use actual token value length (preserves whitespace in quoted parts)
            if (tok%quoted) then
              assignment_lens(num_assignments) = tok%value_length
            else
              assignment_lens(num_assignments) = len_trim(tok%value)
            end if
            call advance(state)
          else
            ! Regular word - this is the command or an argument
            seen_command = .true.
            if (num_words < MAX_TOKENS) then
              num_words = num_words + 1
              words(num_words) = tok%value
              was_quoted(num_words) = tok%quoted
              was_escaped(num_words) = tok%escaped
              quote_types(num_words) = tok%quote_type
              ! For quoted tokens (fully or partially), use value_length (preserves trailing whitespace)
              if (tok%quote_type == QUOTE_DOUBLE .or. tok%quote_type == QUOTE_SINGLE .or. tok%quoted) then
                word_lens(num_words) = tok%value_length
              else
                word_lens(num_words) = len_trim(tok%value)
              end if
            end if
            call advance(state)
          end if
        end if
      else if (tok%token_type == TOKEN_REDIRECT) then
        if (num_redirects < 10) then
          num_redirects = num_redirects + 1

          ! Check if previous word was a file descriptor number (e.g., "2" before ">", "3" before "<&")
          ! FD must be a single digit (0-9) to avoid false positives like "/tmp"
          if (num_words > 0 .and. (trim(tok%value) == '>' .or. trim(tok%value) == '>&' .or. &
                                    trim(tok%value) == '<' .or. trim(tok%value) == '<&' .or. &
                                    trim(tok%value) == '>>' .or. trim(tok%value) == '<>')) then
            ! Only treat as FD if it's exactly one digit character
            if (len_trim(words(num_words)) == 1 .and. &
                index('0123456789', trim(words(num_words))) > 0) then
              read(words(num_words), *, iostat=io_stat) fd_num
            else
              ! Not a single digit, treat as regular word
              io_stat = -1  ! Force failure
              fd_num = -1
            end if
            if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
              ! Previous word was a single digit - this is fd redirection
              select case(trim(tok%value))
              case('>&')
                redirects(num_redirects)%type = REDIR_DUP_OUT
              case('<&')
                redirects(num_redirects)%type = REDIR_DUP_IN
              case('>>')
                redirects(num_redirects)%type = REDIR_FD_APPEND
              case('<')
                redirects(num_redirects)%type = REDIR_FD_IN
              case('<>')
                redirects(num_redirects)%type = REDIR_READWRITE
              case default  ! '>'
                redirects(num_redirects)%type = REDIR_FD_OUT
              end select
              redirects(num_redirects)%fd = fd_num
              num_words = num_words - 1  ! Remove fd from words
            else
              select case(trim(tok%value))
              case('>&')
                redirects(num_redirects)%type = REDIR_DUP_OUT
                redirects(num_redirects)%fd = 1  ! default stdout
              case('<&')
                redirects(num_redirects)%type = REDIR_DUP_IN
                redirects(num_redirects)%fd = 0  ! default stdin
              case('>>')
                redirects(num_redirects)%type = REDIR_APPEND
              case('<')
                redirects(num_redirects)%type = REDIR_IN
              case('<>')
                redirects(num_redirects)%type = REDIR_READWRITE
              case default  ! '>'
                redirects(num_redirects)%type = REDIR_OUT
              end select
            end if
          else
            select case(trim(tok%value))
            case('<')
              redirects(num_redirects)%type = REDIR_IN
            case('<>')
              redirects(num_redirects)%type = REDIR_READWRITE
            case('<&')
              redirects(num_redirects)%type = REDIR_DUP_IN
              redirects(num_redirects)%fd = 0  ! default stdin
            case('>')
              redirects(num_redirects)%type = REDIR_OUT
            case('>|')
              redirects(num_redirects)%type = REDIR_OUT
              redirects(num_redirects)%force_clobber = .true.
            case('>>')
              redirects(num_redirects)%type = REDIR_APPEND
            case('>&')
              redirects(num_redirects)%type = REDIR_DUP_OUT
              redirects(num_redirects)%fd = 1  ! default stdout
            case('<<')
              ! Heredoc - just store the delimiter, executor will handle content
              call advance(state)
              delim_tok = current_token(state)
              if (delim_tok%token_type == TOKEN_WORD) then
                delimiter = trim(delim_tok%value)
                has_heredoc = .true.
                saved_heredoc_delimiter = delimiter
                saved_heredoc_quoted = delim_tok%quoted
                saved_heredoc_strip_tabs = .false.
                call advance(state)
                ! Don't add as regular redirect
                num_redirects = num_redirects - 1
              end if
            case('<<-')
              ! Heredoc with tab stripping - store delimiter and set strip_tabs flag
              call advance(state)
              delim_tok = current_token(state)
              if (delim_tok%token_type == TOKEN_WORD) then
                delimiter = trim(delim_tok%value)
                has_heredoc = .true.
                saved_heredoc_delimiter = delimiter
                saved_heredoc_quoted = delim_tok%quoted
                saved_heredoc_strip_tabs = .true.
                call advance(state)
                ! Don't add as regular redirect
                num_redirects = num_redirects - 1
              end if
            case('<<<')
              ! Here-string - get content from next token
              redirects(num_redirects)%type = REDIR_HERE_STRING
              redirects(num_redirects)%fd = 0  ! stdin
            end select
          end if

          if (trim(tok%value) /= '<<' .and. trim(tok%value) /= '<<-') then
            call advance(state)
            tok = current_token(state)
            if (tok%token_type == TOKEN_WORD) then
              ! Check for >&- or <&- (close fd) syntax
              if (trim(tok%value) == '-' .and. &
                  (redirects(num_redirects)%type == REDIR_DUP_OUT .or. &
                   redirects(num_redirects)%type == REDIR_DUP_IN)) then
                ! This is n>&- or n<&- (close fd n)
                redirects(num_redirects)%type = REDIR_CLOSE
                call advance(state)
              else if (redirects(num_redirects)%type == REDIR_DUP_OUT .or. &
                       redirects(num_redirects)%type == REDIR_DUP_IN) then
                ! For >& and <&, check if the "filename" is actually a file descriptor number
                ! Try to parse as fd number
                read(tok%value, *, iostat=io_stat) fd_num
                if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
                  ! It's a target fd like in 2>&1 or 3<&0
                  redirects(num_redirects)%target_fd = fd_num
                else
                  ! It's a filename (rare but possible)
                  allocate(redirects(num_redirects)%filename, source=trim(tok%value))
                end if
                call advance(state)
              else
                ! Regular filename for other redirects
                allocate(redirects(num_redirects)%filename, source=trim(tok%value))
                call advance(state)
              end if
            end if
          end if
        end if
      else
        exit
      end if
    end do
    if (num_words > 0) then
      node => create_simple_command(words, num_words)
      node%line = state%current_line  ! Track line number for LINENO
      if (associated(node%simple_cmd)) then
        ! Store quoted and escaped flags
        allocate(node%simple_cmd%word_was_quoted(num_words))
        node%simple_cmd%word_was_quoted(1:num_words) = was_quoted(1:num_words)
        allocate(node%simple_cmd%word_was_escaped(num_words))
        node%simple_cmd%word_was_escaped(1:num_words) = was_escaped(1:num_words)
        allocate(node%simple_cmd%word_quote_type(num_words))
        node%simple_cmd%word_quote_type(1:num_words) = quote_types(1:num_words)
        allocate(node%simple_cmd%word_lengths(num_words))
        node%simple_cmd%word_lengths(1:num_words) = word_lens(1:num_words)

        ! Store heredoc delimiter if present
        if (has_heredoc) then
          node%simple_cmd%heredoc_delimiter = saved_heredoc_delimiter
          node%simple_cmd%heredoc_quoted = saved_heredoc_quoted
          node%simple_cmd%heredoc_strip_tabs = saved_heredoc_strip_tabs
        end if

        if (num_redirects > 0) then
          allocate(node%simple_cmd%redirects(num_redirects))
          node%simple_cmd%num_redirects = num_redirects
          node%simple_cmd%redirects(1:num_redirects) = redirects(1:num_redirects)
        end if

        ! Store prefix assignments
        if (num_assignments > 0) then
          allocate(node%simple_cmd%assignments(num_assignments))
          allocate(node%simple_cmd%assignment_lengths(num_assignments))
          node%simple_cmd%num_assignments = num_assignments
          do i = 1, num_assignments
            node%simple_cmd%assignments(i) = assignments(i)
            node%simple_cmd%assignment_lengths(i) = assignment_lens(i)
          end do
        end if
      end if
    else if (num_assignments > 0) then
      ! Pure assignment(s) with no command - create a node with just assignments
      node => create_simple_command(assignments, num_assignments)
      node%line = state%current_line  ! Track line number for LINENO
      if (associated(node%simple_cmd)) then
        ! Mark these as assignments, not command words
        node%simple_cmd%num_words = 0
        if (allocated(node%simple_cmd%words)) deallocate(node%simple_cmd%words)
        allocate(node%simple_cmd%assignments(num_assignments))
        allocate(node%simple_cmd%assignment_lengths(num_assignments))
        node%simple_cmd%num_assignments = num_assignments
        do i = 1, num_assignments
          node%simple_cmd%assignments(i) = assignments(i)
          node%simple_cmd%assignment_lengths(i) = assignment_lens(i)
        end do
      end if
    else if (num_redirects > 0) then
      ! POSIX: Null command with just redirects (e.g., "> file" creates empty file)
      ! Create a simple command node with the colon (:) builtin as the command
      words(1) = ':'
      num_words = 1
      node => create_simple_command(words, num_words)
      node%line = state%current_line  ! Track line number for LINENO
      if (associated(node%simple_cmd)) then
        allocate(node%simple_cmd%word_was_quoted(1))
        node%simple_cmd%word_was_quoted(1) = .false.
        allocate(node%simple_cmd%word_was_escaped(1))
        node%simple_cmd%word_was_escaped(1) = .false.
        allocate(node%simple_cmd%word_quote_type(1))
        node%simple_cmd%word_quote_type(1) = 0
        allocate(node%simple_cmd%word_lengths(1))
        node%simple_cmd%word_lengths(1) = 1
        allocate(node%simple_cmd%redirects(num_redirects))
        node%simple_cmd%num_redirects = num_redirects
        node%simple_cmd%redirects(1:num_redirects) = redirects(1:num_redirects)
      end if
    end if
  end function

  recursive function parse_if_stmt(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, cond, then_part, else_part, elif_node
    type(token_t) :: tok
    nullify(node, else_part)
    if (.not. expect(state, 'if')) return
    call skip_newlines(state)
    cond => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, 'then')) return
    call skip_newlines(state)
    then_part => parse_list(state)
    call skip_newlines(state)
    tok = current_token(state)
    if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'elif') then
      call advance(state)
      call skip_newlines(state)
      cond => parse_list(state)
      call skip_newlines(state)
      if (.not. expect(state, 'then')) return
      call skip_newlines(state)
      then_part => parse_list(state)
      call skip_newlines(state)
      tok = current_token(state)
      if (tok%token_type == TOKEN_KEYWORD .and. (trim(tok%value) == 'elif' .or. trim(tok%value) == 'else')) then
        elif_node => parse_if_continuation(state)
        else_part => elif_node
      else
        if (.not. expect(state, 'fi')) return
      end if
      node => create_if_statement(cond, then_part, else_part)
      return
    else if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'else') then
      call advance(state)
      call skip_newlines(state)
      else_part => parse_list(state)
      call skip_newlines(state)
      if (.not. expect(state, 'fi')) return
    else
      if (.not. expect(state, 'fi')) return
    end if
    node => create_if_statement(cond, then_part, else_part)
  end function

  recursive function parse_if_continuation(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, cond, then_part, else_part
    type(token_t) :: tok
    nullify(node, else_part)
    tok = current_token(state)
    if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'elif') then
      call advance(state)
      call skip_newlines(state)
      cond => parse_list(state)
      call skip_newlines(state)
      if (.not. expect(state, 'then')) return
      call skip_newlines(state)
      then_part => parse_list(state)
      call skip_newlines(state)
      tok = current_token(state)
      if (tok%token_type == TOKEN_KEYWORD .and. (trim(tok%value) == 'elif' .or. trim(tok%value) == 'else')) then
        else_part => parse_if_continuation(state)
      end if
      node => create_if_statement(cond, then_part, else_part)
    else if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'else') then
      call advance(state)
      call skip_newlines(state)
      node => parse_list(state)
    end if
  end function

  recursive function parse_while_stmt(state, is_until) result(node)
    type(parser_state_t), intent(inout) :: state
    logical, intent(in) :: is_until
    type(command_node_t), pointer :: node, cond, body
    nullify(node)
    if (is_until) then
      if (.not. expect(state, 'until')) return
    else
      if (.not. expect(state, 'while')) return
    end if
    call skip_newlines(state)
    cond => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, 'do')) return
    call skip_newlines(state)
    body => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, 'done')) return
    node => create_while_loop(cond, body, is_until)
  end function

  recursive function parse_for_stmt(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, body
    character(len=MAX_TOKEN_LEN) :: variable, words(MAX_TOKENS)
    integer :: num_words, quote_types(MAX_TOKENS)
    type(token_t) :: tok
    nullify(node)
    num_words = 0
    quote_types = QUOTE_NONE
    if (.not. expect(state, 'for')) return
    tok = current_token(state)
    if (tok%token_type /= TOKEN_WORD) return
    variable = tok%value
    call advance(state)
    call skip_newlines(state)
    tok = current_token(state)
    if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'in') then
      call advance(state)
      tok = current_token(state)
      do while (tok%token_type == TOKEN_WORD)
        if (num_words < MAX_TOKENS) then
          num_words = num_words + 1
          words(num_words) = tok%value
          quote_types(num_words) = tok%quote_type
        end if
        call advance(state)
        tok = current_token(state)
      end do
    end if
    call skip_newlines(state)
    if (match(state, ';')) call skip_newlines(state)
    if (.not. expect(state, 'do')) return
    call skip_newlines(state)
    body => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, 'done')) return
    node => create_for_loop(variable, words, num_words, body, quote_types)
  end function

  function parse_case_stmt(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, case_cmds
    character(len=MAX_TOKEN_LEN) :: word, patterns(10)
    type(case_item_t) :: items(20)
    integer :: num_items, num_patterns, i
    type(token_t) :: tok
    nullify(node)
    num_items = 0
    if (.not. expect(state, 'case')) return
    tok = current_token(state)
    if (tok%token_type /= TOKEN_WORD) return
    word = tok%value
    call advance(state)
    call skip_newlines(state)
    if (.not. expect(state, 'in')) return
    call skip_newlines(state)

    ! Parse case items: pattern) commands ;;
    tok = current_token(state)
    do while (tok%token_type /= TOKEN_KEYWORD .or. trim(tok%value) /= 'esac')
      if (tok%token_type == TOKEN_EOF) exit
      if (num_items >= 20) exit

      ! Parse patterns (pattern1|pattern2|...)
      num_patterns = 0
      do while (tok%token_type == TOKEN_WORD .or. &
                (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '|'))
        if (tok%token_type == TOKEN_WORD) then
          if (num_patterns < 10) then
            num_patterns = num_patterns + 1
            patterns(num_patterns) = tok%value
          end if
          call advance(state)
          tok = current_token(state)

          ! After pattern word, expect ) or |
          if (tok%token_type == TOKEN_OPERATOR) then
            if (trim(tok%value) == ')') then
              call advance(state)
              exit  ! End of patterns
            else if (trim(tok%value) == '|') then
              call advance(state)
              tok = current_token(state)
              ! Continue to next pattern
            else
              exit
            end if
          else
            exit
          end if
        else
          ! Skip | if we somehow see it
          call advance(state)
          tok = current_token(state)
        end if
      end do

      call skip_newlines(state)

      ! Parse commands for this case item
      case_cmds => parse_case_item_commands(state)

      ! Store case item with patterns and commands
      if (num_patterns > 0) then
        num_items = num_items + 1
        allocate(items(num_items)%patterns(num_patterns))
        items(num_items)%num_patterns = num_patterns
        do i = 1, num_patterns
          items(num_items)%patterns(i) = patterns(i)
        end do
        items(num_items)%commands => case_cmds
      end if

      call skip_newlines(state)
      tok = current_token(state)
    end do

    if (.not. expect(state, 'esac')) return
    node => create_case_statement(word, items, num_items)
  end function

  ! Parse commands in a case item until ;; or esac
  recursive function parse_case_item_commands(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, right_node
    type(token_t) :: tok
    integer :: sep_type

    node => parse_and_or(state)
    if (.not. associated(node)) return

    do while (.true.)
      tok = current_token(state)

      ! Stop at ;; or esac
      if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == ';;') then
        call advance(state)
        exit
      end if
      if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'esac') exit

      ! Handle list separators
      if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == ';') then
        sep_type = LIST_SEP_SEQUENTIAL
        call advance(state)
      else if (tok%token_type == TOKEN_NEWLINE) then
        sep_type = LIST_SEP_SEQUENTIAL
        call advance(state)
      else
        exit
      end if

      ! Check again for terminators
      tok = current_token(state)
      if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == ';;') then
        call advance(state)
        exit
      end if
      if (tok%token_type == TOKEN_KEYWORD .and. trim(tok%value) == 'esac') exit

      right_node => parse_and_or(state)
      if (.not. associated(right_node)) exit
      node => create_list(node, right_node, sep_type)
    end do
  end function

  recursive function parse_subshell(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, commands
    nullify(node)
    if (.not. expect(state, '(')) return
    call skip_newlines(state)
    commands => parse_list(state)
    call skip_newlines(state)
    ! POSIX: Empty subshell () is a syntax error
    if (.not. associated(commands)) then
      write(error_unit, '(A)') "sh: -c: line 1: syntax error near unexpected token `)'"
      if (allocated(state%raw_input)) then
        write(error_unit, '(A)') "sh: -c: `" // trim(state%raw_input) // "'"
      end if
      state%has_error = .true.
      return
    end if
    if (.not. expect(state, ')')) return
    node => create_subshell(commands)
  end function

  ! Parse (( ... )) arithmetic command
  recursive function parse_arithmetic_command(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node
    type(token_t) :: tok
    character(len=MAX_TOKEN_LEN) :: arith_expr, words(1)
    integer :: paren_depth, expr_pos, prev_end_pos
    logical :: found_close

    nullify(node)

    ! Consume first (
    if (.not. expect(state, '(')) return
    ! Consume second (
    if (.not. expect(state, '(')) return

    ! Collect tokens until )) is found
    arith_expr = '(('
    expr_pos = 3
    paren_depth = 2
    found_close = .false.
    prev_end_pos = -1  ! Track previous token's end position

    do while (state%pos <= state%num_tokens)
      tok = current_token(state)

      if (tok%token_type == TOKEN_EOF) exit

      if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == ')') then
        paren_depth = paren_depth - 1
        arith_expr(expr_pos:expr_pos) = ')'
        expr_pos = expr_pos + 1
        prev_end_pos = tok%end_pos
        call advance(state)
        if (paren_depth == 0) then
          found_close = .true.
          exit
        end if
      else if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '(') then
        paren_depth = paren_depth + 1
        arith_expr(expr_pos:expr_pos) = '('
        expr_pos = expr_pos + 1
        prev_end_pos = tok%end_pos
        call advance(state)
      else
        ! Add token value to expression
        ! Only add a space if there was whitespace between this token and the previous one
        ! in the original source (to preserve adjacent operators like && and ||)
        if (prev_end_pos >= 0 .and. tok%start_pos > prev_end_pos + 1) then
          if (expr_pos + 1 <= MAX_TOKEN_LEN) then
            arith_expr(expr_pos:expr_pos) = ' '
            expr_pos = expr_pos + 1
          end if
        end if
        if (expr_pos + len_trim(tok%value) <= MAX_TOKEN_LEN) then
          arith_expr(expr_pos:expr_pos+len_trim(tok%value)-1) = trim(tok%value)
          expr_pos = expr_pos + len_trim(tok%value)
        end if
        prev_end_pos = tok%end_pos
        call advance(state)
      end if
    end do

    if (.not. found_close) then
      ! Syntax error - unmatched ((
      return
    end if

    ! Create a simple command with the arithmetic expression as the first token
    words(1) = arith_expr(1:expr_pos-1)
    node => create_simple_command(words, 1)
    node%line = state%current_line  ! Track line number for LINENO

    ! Allocate metadata arrays to prevent segfaults in AST executor
    ! Mark the arithmetic expression as "quoted" to prevent word splitting
    ! (the expression is a single unit that should not be split on IFS)
    if (associated(node) .and. associated(node%simple_cmd)) then
      allocate(node%simple_cmd%word_was_quoted(1))
      node%simple_cmd%word_was_quoted(1) = .true.  ! Prevent word splitting
      allocate(node%simple_cmd%word_was_escaped(1))
      node%simple_cmd%word_was_escaped(1) = .false.
      allocate(node%simple_cmd%word_quote_type(1))
      node%simple_cmd%word_quote_type(1) = QUOTE_DOUBLE  ! Treat like double-quoted
      allocate(node%simple_cmd%word_lengths(1))
      node%simple_cmd%word_lengths(1) = expr_pos - 1
    end if
  end function

  recursive function parse_brace_group(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, commands
    nullify(node)
    if (.not. expect(state, '{')) return
    call skip_newlines(state)
    commands => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, '}')) return
    node => create_brace_group(commands)
  end function

  subroutine skip_newlines(state)
    type(parser_state_t), intent(inout) :: state
    type(token_t) :: tok
    tok = current_token(state)
    do while (tok%token_type == TOKEN_NEWLINE)
      state%current_line = state%current_line + 1  ! Track LINENO
      call advance(state)
      tok = current_token(state)
    end do
  end subroutine

  ! Parse trailing redirections for compound commands
  subroutine parse_trailing_redirections(state, node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer, intent(inout) :: node
    type(redirection_t) :: redirects(10)
    integer :: num_redirects, fd_num, io_stat
    type(token_t) :: tok, next_tok
    logical :: has_fd_prefix

    if (.not. associated(node)) return

    num_redirects = 0
    tok = current_token(state)

    ! Parse any trailing redirect operators
    ! Handle both "2>/dev/null" (fd-numbered) and ">/dev/null" (default fd)
    do while (num_redirects < 10)
      has_fd_prefix = .false.
      fd_num = -1

      ! Check if current token is a single digit followed by redirect operator
      if (tok%token_type == TOKEN_WORD) then
        if (len_trim(tok%value) == 1 .and. &
            index('0123456789', trim(tok%value)) > 0) then
          ! Peek at next token
          next_tok = peek_token(state%tokens, state%pos + 1)
          if (next_tok%token_type == TOKEN_REDIRECT) then
            ! This is fd-numbered redirection like "2>"
            read(tok%value, *, iostat=io_stat) fd_num
            if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
              has_fd_prefix = .true.
              call advance(state)  ! consume the digit
              tok = current_token(state)  ! now tok is the redirect operator
            end if
          else
            exit  ! Not a redirect, done parsing
          end if
        else
          exit  ! Not a single digit, done parsing
        end if
      end if

      if (tok%token_type /= TOKEN_REDIRECT) exit

      num_redirects = num_redirects + 1

      ! Set redirect type based on operator
      if (has_fd_prefix) then
        ! fd-numbered redirection
        select case(trim(tok%value))
        case('>&')
          redirects(num_redirects)%type = REDIR_DUP_OUT
          redirects(num_redirects)%fd = fd_num
        case('<&')
          redirects(num_redirects)%type = REDIR_DUP_IN
          redirects(num_redirects)%fd = fd_num
        case('>>')
          redirects(num_redirects)%type = REDIR_FD_APPEND
          redirects(num_redirects)%fd = fd_num
        case('<')
          redirects(num_redirects)%type = REDIR_FD_IN
          redirects(num_redirects)%fd = fd_num
        case('<>')
          redirects(num_redirects)%type = REDIR_READWRITE
          redirects(num_redirects)%fd = fd_num
        case('>|')
          redirects(num_redirects)%type = REDIR_FD_OUT
          redirects(num_redirects)%fd = fd_num
          redirects(num_redirects)%force_clobber = .true.
        case default  ! '>'
          redirects(num_redirects)%type = REDIR_FD_OUT
          redirects(num_redirects)%fd = fd_num
        end select
      else
        ! Default fd redirection
        select case(trim(tok%value))
        case('<')
          redirects(num_redirects)%type = REDIR_IN
        case('<>')
          redirects(num_redirects)%type = REDIR_READWRITE
        case('<&')
          redirects(num_redirects)%type = REDIR_DUP_IN
          redirects(num_redirects)%fd = 0  ! default stdin
        case('>')
          redirects(num_redirects)%type = REDIR_OUT
        case('>|')
          redirects(num_redirects)%type = REDIR_OUT
          redirects(num_redirects)%force_clobber = .true.
        case('>>')
          redirects(num_redirects)%type = REDIR_APPEND
        case('>&')
          redirects(num_redirects)%type = REDIR_DUP_OUT
          redirects(num_redirects)%fd = 1  ! default stdout
        case('<<<')
          redirects(num_redirects)%type = REDIR_HERE_STRING
          redirects(num_redirects)%fd = 0  ! stdin
        case default
          num_redirects = num_redirects - 1
          exit
        end select
      end if

      call advance(state)
      tok = current_token(state)

      if (tok%token_type == TOKEN_WORD) then
        ! Check for >&- or <&- (close fd) syntax
        if (trim(tok%value) == '-' .and. &
            (redirects(num_redirects)%type == REDIR_DUP_OUT .or. &
             redirects(num_redirects)%type == REDIR_DUP_IN)) then
          ! This is n>&- or n<&- (close fd n)
          redirects(num_redirects)%type = REDIR_CLOSE
          call advance(state)
          tok = current_token(state)
        else if (redirects(num_redirects)%type == REDIR_DUP_OUT .or. &
                 redirects(num_redirects)%type == REDIR_DUP_IN) then
          ! For >& and <&, check if it's a file descriptor or filename
          read(tok%value, *, iostat=io_stat) fd_num
          if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
            redirects(num_redirects)%target_fd = fd_num
          else
            allocate(redirects(num_redirects)%filename, source=trim(tok%value))
          end if
          call advance(state)
          tok = current_token(state)
        else
          allocate(redirects(num_redirects)%filename, source=trim(tok%value))
          call advance(state)
          tok = current_token(state)
        end if
      end if
    end do

    ! Store redirections in node if any were found
    if (num_redirects > 0) then
      allocate(node%redirects(num_redirects))
      node%num_redirects = num_redirects
      node%redirects(1:num_redirects) = redirects(1:num_redirects)
    end if
  end subroutine

  ! Check if a string is a valid shell variable name for assignments
  function is_valid_assignment_name(name) result(valid)
    character(len=*), intent(in) :: name
    logical :: valid
    integer :: i, name_len
    character :: ch

    valid = .false.
    name_len = len_trim(name)

    if (name_len == 0) return

    ! First character must be letter or underscore
    ch = name(1:1)
    if (.not. ((ch >= 'a' .and. ch <= 'z') .or. &
               (ch >= 'A' .and. ch <= 'Z') .or. &
               ch == '_')) then
      return
    end if

    ! Remaining characters must be letter, digit, or underscore
    do i = 2, name_len
      ch = name(i:i)
      if (.not. ((ch >= 'a' .and. ch <= 'z') .or. &
                 (ch >= 'A' .and. ch <= 'Z') .or. &
                 (ch >= '0' .and. ch <= '9') .or. &
                 ch == '_')) then
        return
      end if
    end do

    valid = .true.
  end function is_valid_assignment_name

end module grammar_parser
