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
  public :: parse_with_grammar, parse_command_line

  type :: parser_state_t
    type(token_t) :: tokens(MAX_TOKENS)
    integer :: num_tokens = 0
    integer :: pos = 1
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
  end function

  subroutine parse_with_grammar(input, pipeline, shell)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline
    type(shell_state_t), intent(inout) :: shell
    pipeline%num_commands = 0
    if (shell%control_depth >= 0) then
    end if
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
    if (.not. associated(node)) return
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
        else if (trim(tok%value) == '&') then
          sep_type = LIST_SEP_BACKGROUND
          call advance(state)
        else
          exit
        end if
      else if (tok%token_type == TOKEN_NEWLINE) then
        sep_type = LIST_SEP_SEQUENTIAL
        call advance(state)
      else
        exit
      end if
      tok = current_token(state)
      if (tok%token_type == TOKEN_KEYWORD) then
        if (trim(tok%value) == 'done' .or. trim(tok%value) == 'fi' .or. &
            trim(tok%value) == 'else' .or. trim(tok%value) == 'elif' .or. &
            trim(tok%value) == 'esac') exit
      end if
      right_node => parse_and_or(state)
      if (.not. associated(right_node)) exit
      node => create_list(node, right_node, sep_type)
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
    integer :: num_commands, i
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
        num_commands = num_commands + 1
        temp_node => parse_command_node(state)
        if (.not. associated(temp_node)) exit
        commands(num_commands) = temp_node
        tok = current_token(state)
      end do
      node => create_pipeline(commands, num_commands, negate)
    else if (negate) then
      allocate(commands(1))
      commands(1) = node
      node => create_pipeline(commands, 1, .true.)
    end if
  end function

  recursive function parse_command_node(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node
    type(token_t) :: tok
    tok = current_token(state)
    if (tok%token_type == TOKEN_KEYWORD) then
      select case(trim(tok%value))
      case('if')
        node => parse_if_stmt(state)
      case('while')
        node => parse_while_stmt(state, .false.)
      case('until')
        node => parse_while_stmt(state, .true.)
      case('for')
        node => parse_for_stmt(state)
      case('case')
        node => parse_case_stmt(state)
      case('{')
        node => parse_brace_group(state)
      case default
        node => parse_simple_cmd(state)
      end select
    else if (tok%token_type == TOKEN_OPERATOR .and. trim(tok%value) == '(') then
      node => parse_subshell(state)
    else
      node => parse_simple_cmd(state)
    end if
  end function

  function parse_simple_cmd(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, func_body
    character(len=MAX_TOKEN_LEN) :: words(MAX_TOKENS), func_name, delimiter, merged_word
    logical :: was_quoted(MAX_TOKENS), was_escaped(MAX_TOKENS)
    integer :: quote_types(MAX_TOKENS)
    character(len=MAX_TOKEN_LEN) :: saved_heredoc_delimiter
    logical :: saved_heredoc_quoted
    logical :: has_heredoc
    type(redirection_t) :: redirects(10)
    integer :: num_words, num_redirects, i, fd_num, io_stat, saved_pos
    type(token_t) :: tok, next_tok, peek_tok, delim_tok
    num_words = 0
    num_redirects = 0
    nullify(node)
    was_quoted = .false.
    was_escaped = .false.
    quote_types = QUOTE_NONE
    has_heredoc = .false.
    saved_heredoc_quoted = .false.
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
      if (tok%token_type == TOKEN_WORD) then
        ! Check if this is an assignment (VAR= followed by value)
        ! Only merge if first token (assignments come before commands)
        if (num_words == 0 .and. index(tok%value, '=') > 0 .and. index(tok%value, '=') == len_trim(tok%value)) then
          ! This ends with = , check if next token is the value
          call advance(state)
          next_tok = current_token(state)
          if (next_tok%token_type == TOKEN_WORD) then
            ! Merge: VAR= + value → VAR=value
            merged_word = trim(tok%value) // trim(next_tok%value)
            if (num_words < MAX_TOKENS) then
              num_words = num_words + 1
              words(num_words) = merged_word
              was_quoted(num_words) = next_tok%quoted
              was_escaped(num_words) = next_tok%escaped
            end if
            call advance(state)
          else
            ! Just VAR= without value, keep as-is
            if (num_words < MAX_TOKENS) then
              num_words = num_words + 1
              words(num_words) = tok%value
              was_quoted(num_words) = tok%quoted
              was_escaped(num_words) = tok%escaped
              quote_types(num_words) = tok%quote_type
            end if
          end if
        else
          ! Regular word
          if (num_words < MAX_TOKENS) then
            num_words = num_words + 1
            words(num_words) = tok%value
            was_quoted(num_words) = tok%quoted
            was_escaped(num_words) = tok%escaped
            quote_types(num_words) = tok%quote_type
          end if
          call advance(state)
        end if
      else if (tok%token_type == TOKEN_REDIRECT) then
        if (num_redirects < 10) then
          num_redirects = num_redirects + 1

          ! Check if previous word was a file descriptor number (e.g., "2" before ">" or ">&")
          if (num_words > 0 .and. (trim(tok%value) == '>' .or. trim(tok%value) == '>&')) then
            read(words(num_words), *, iostat=io_stat) fd_num
            if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
              ! Previous word was a single digit - this is fd redirection
              if (trim(tok%value) == '>&') then
                redirects(num_redirects)%type = REDIR_DUP_OUT
              else
                redirects(num_redirects)%type = REDIR_FD_OUT
              end if
              redirects(num_redirects)%fd = fd_num
              num_words = num_words - 1  ! Remove fd from words
            else
              if (trim(tok%value) == '>&') then
                redirects(num_redirects)%type = REDIR_DUP_OUT
              else
                redirects(num_redirects)%type = REDIR_OUT
              end if
            end if
          else
            select case(trim(tok%value))
            case('<')
              redirects(num_redirects)%type = REDIR_IN
            case('>')
              redirects(num_redirects)%type = REDIR_OUT
            case('>|')
              redirects(num_redirects)%type = REDIR_OUT
              redirects(num_redirects)%force_clobber = .true.
            case('>>')
              redirects(num_redirects)%type = REDIR_APPEND
            case('>&')
              redirects(num_redirects)%type = REDIR_DUP_OUT
            case('<<')
              ! Heredoc - just store the delimiter, executor will handle content
              call advance(state)
              delim_tok = current_token(state)
              if (delim_tok%token_type == TOKEN_WORD) then
                delimiter = trim(delim_tok%value)
                has_heredoc = .true.
                saved_heredoc_delimiter = delimiter
                saved_heredoc_quoted = delim_tok%quoted
                call advance(state)
                ! Don't add as regular redirect
                num_redirects = num_redirects - 1
              end if
            end select
          end if

          if (trim(tok%value) /= '<<') then
            call advance(state)
            tok = current_token(state)
            if (tok%token_type == TOKEN_WORD) then
              ! For >&, check if the "filename" is actually a file descriptor number
              if (redirects(num_redirects)%type == REDIR_DUP_OUT) then
                ! Try to parse as fd number
                read(tok%value, *, iostat=io_stat) fd_num
                if (io_stat == 0 .and. fd_num >= 0 .and. fd_num <= 9) then
                  ! It's a target fd like in 2>&1
                  redirects(num_redirects)%target_fd = fd_num
                else
                  ! It's a filename (rare but possible)
                  allocate(redirects(num_redirects)%filename, source=trim(tok%value))
                end if
              else
                ! Regular filename for other redirects
                allocate(redirects(num_redirects)%filename, source=trim(tok%value))
              end if
              call advance(state)
            end if
          end if
        end if
      else
        exit
      end if
    end do
    if (num_words > 0) then
      node => create_simple_command(words, num_words)
      if (associated(node%simple_cmd)) then
        ! Store quoted and escaped flags
        allocate(node%simple_cmd%word_was_quoted(num_words))
        node%simple_cmd%word_was_quoted(1:num_words) = was_quoted(1:num_words)
        allocate(node%simple_cmd%word_was_escaped(num_words))
        node%simple_cmd%word_was_escaped(1:num_words) = was_escaped(1:num_words)
        allocate(node%simple_cmd%word_quote_type(num_words))
        node%simple_cmd%word_quote_type(1:num_words) = quote_types(1:num_words)

        ! Store heredoc delimiter if present
        if (has_heredoc) then
          node%simple_cmd%heredoc_delimiter = saved_heredoc_delimiter
          node%simple_cmd%heredoc_quoted = saved_heredoc_quoted
        end if

        if (num_redirects > 0) then
          allocate(node%simple_cmd%redirects(num_redirects))
          node%simple_cmd%num_redirects = num_redirects
          node%simple_cmd%redirects(1:num_redirects) = redirects(1:num_redirects)
        end if
      end if
    end if
  end function

  recursive function parse_if_stmt(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, cond, then_part, else_part, elif_node
    type(token_t) :: tok
    nullify(else_part)
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
    nullify(else_part)
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
    node => create_for_loop(variable, words, num_words, body)
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
    if (.not. expect(state, '(')) return
    call skip_newlines(state)
    commands => parse_list(state)
    call skip_newlines(state)
    if (.not. expect(state, ')')) return
    node => create_subshell(commands)
  end function

  recursive function parse_brace_group(state) result(node)
    type(parser_state_t), intent(inout) :: state
    type(command_node_t), pointer :: node, commands
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
      call advance(state)
      tok = current_token(state)
    end do
  end subroutine

end module grammar_parser
