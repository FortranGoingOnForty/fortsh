! ==============================================================================
! Module: parser
! Purpose: Recursive descent parser for fortsh - builds AST from tokens
! ==============================================================================
module parser
  use ast_types
  use lexer
  use iso_fortran_env, only: error_unit
  implicit none

  ! Parser state
  type :: parser_t
    type(token_t), allocatable :: tokens(:)
    integer :: token_count = 0
    integer :: current = 1
  contains
    procedure :: init => parser_init
    procedure :: parse => parser_parse
    procedure :: current_token => parser_current_token
    procedure :: peek_token => parser_peek_token
    procedure :: advance => parser_advance
    procedure :: expect => parser_expect
    procedure :: parse_script => parser_parse_script
    procedure :: parse_command_list => parser_parse_command_list
    procedure :: parse_pipeline => parser_parse_pipeline
    procedure :: parse_command => parser_parse_command
    procedure :: parse_for_loop => parser_parse_for_loop
    procedure :: parse_if_statement => parser_parse_if_statement
    procedure :: parse_while_loop => parser_parse_while_loop
    procedure :: parse_word => parser_parse_word
    procedure :: destroy => parser_destroy
  end type parser_t

contains


  ! Initialize parser with tokens
  subroutine parser_init(self, tokens, count)
    class(parser_t), intent(inout) :: self
    type(token_t), intent(in) :: tokens(:)
    integer, intent(in) :: count

    if (allocated(self%tokens)) deallocate(self%tokens)
    allocate(self%tokens(count))
    self%tokens = tokens(1:count)
    self%token_count = count
    self%current = 1
  end subroutine parser_init

  ! Main parse entry point
  function parser_parse(self) result(ast)
    class(parser_t), intent(inout) :: self
    type(script_node_t) :: ast

    ast = self%parse_script()
  end function parser_parse

  ! Parse script (top level)
  function parser_parse_script(self) result(node)
    class(parser_t), intent(inout) :: self
    type(script_node_t) :: node
    type(token_t) :: tok

    node%node_type = NODE_SCRIPT

    ! For now, just parse statements without pre-counting
    ! This is simpler and avoids polymorphic assignment issues
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_EOF) exit

      ! Skip newlines at top level
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      ! Parse statement - for now just skip it
      ! TODO: Implement proper statement collection
      block
        class(ast_node_t), allocatable :: stmt
        stmt = self%parse_command_list()
      end block
    end do
  end function parser_parse_script

  ! Parse command list (commands separated by ; or newline)
  function parser_parse_command_list(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(command_list_node_t), allocatable :: list_node
    class(ast_node_t), allocatable :: cmd
    type(token_t) :: tok

    cmd = self%parse_pipeline()

    ! Check for semicolon or newline
    if (self%current <= self%token_count) then
      tok = self%current_token()
      if (tok%type == TOKEN_SEMICOLON .or. &
          tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if
    end if

    node = cmd
  end function parser_parse_command_list

  ! Parse pipeline (commands separated by |)
  function parser_parse_pipeline(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(pipeline_node_t), allocatable :: pipe_node
    class(ast_node_t), allocatable :: commands(:)
    integer :: cmd_count

    ! For now, just parse single command
    node = self%parse_command()
  end function parser_parse_pipeline

  ! Parse single command
  function parser_parse_command(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(command_node_t), allocatable :: cmd_node
    type(token_t) :: token, next_tok
    integer :: level_value

    token = self%current_token()

    ! Check for control structures
    select case(token%type)
    case(TOKEN_FOR)
      node = self%parse_for_loop()
      return
    case(TOKEN_IF)
      node = self%parse_if_statement()
      return
    case(TOKEN_WHILE)
      node = self%parse_while_loop()
      return
    case(TOKEN_BREAK)
      allocate(break_node_t :: node)
      select type(node)
      type is (break_node_t)
        node%node_type = NODE_BREAK
        node%levels = 1
        call self%advance()
        ! Check for numeric argument
        next_tok = self%current_token()
        if (next_tok%type == TOKEN_WORD) then
          read(next_tok%value, *) level_value
          node%levels = level_value
          call self%advance()
        end if
      end select
      return
    case(TOKEN_CONTINUE)
      allocate(continue_node_t :: node)
      select type(node)
      type is (continue_node_t)
        node%node_type = NODE_CONTINUE
        node%levels = 1
        call self%advance()
        ! Check for numeric argument
        next_tok = self%current_token()
        if (next_tok%type == TOKEN_WORD) then
          read(next_tok%value, *) level_value
          node%levels = level_value
          call self%advance()
        end if
      end select
      return
    end select

    ! Parse simple command
    allocate(cmd_node)
    cmd_node%node_type = NODE_COMMAND

    ! Parse words (command and arguments)
    call parse_command_words(self, cmd_node)

    call move_alloc(cmd_node, node)
  end function parser_parse_command

  ! Parse for loop
  function parser_parse_for_loop(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(for_node_t), allocatable :: for_node
    type(token_t) :: tok

    allocate(for_node)
    for_node%node_type = NODE_FOR

    ! Expect 'for'
    call self%expect(TOKEN_FOR)

    ! Get variable name
    tok = self%current_token()
    if (tok%type == TOKEN_WORD) then
      for_node%variable = tok%value
      call self%advance()
    end if

    ! Expect 'in'
    call self%expect(TOKEN_IN)

    ! Parse word list
    call parse_word_list(self, for_node%word_list)

    ! Skip separator (newline or semicolon)
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE .or. &
        tok%type == TOKEN_SEMICOLON) then
      call self%advance()
    end if

    ! Expect 'do'
    call self%expect(TOKEN_DO)

    ! Skip newline after do
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE) then
      call self%advance()
    end if

    ! Parse loop body
    call parse_loop_body(self, for_node%body)

    ! Expect 'done'
    call self%expect(TOKEN_DONE)

    call move_alloc(for_node, node)
  end function parser_parse_for_loop

  ! Parse if statement
  function parser_parse_if_statement(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(if_node_t), allocatable :: if_node
    type(token_t) :: tok

    allocate(if_node)
    if_node%node_type = NODE_IF

    ! Expect 'if'
    call self%expect(TOKEN_IF)

    ! Parse condition (command)
    if_node%condition = self%parse_command()

    ! Skip separator
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE .or. &
        tok%type == TOKEN_SEMICOLON) then
      call self%advance()
    end if

    ! Expect 'then'
    call self%expect(TOKEN_THEN)

    ! Skip newline after then
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE) then
      call self%advance()
    end if

    ! Parse then branch
    call parse_command_sequence(self, if_node%then_branch, &
                               [TOKEN_ELSE, TOKEN_ELIF, TOKEN_FI])

    ! Check for else/elif
    tok = self%current_token()
    if (tok%type == TOKEN_ELSE) then
      call self%advance()
      tok = self%current_token()
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if
      call parse_command_sequence(self, if_node%else_branch, [TOKEN_FI])
    end if

    ! Expect 'fi'
    call self%expect(TOKEN_FI)

    call move_alloc(if_node, node)
  end function parser_parse_if_statement

  ! Parse while loop
  function parser_parse_while_loop(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(while_node_t), allocatable :: while_node
    type(token_t) :: tok

    allocate(while_node)
    while_node%node_type = NODE_WHILE

    ! Expect 'while'
    call self%expect(TOKEN_WHILE)

    ! Parse condition
    while_node%condition = self%parse_command()

    ! Skip separator
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE .or. &
        tok%type == TOKEN_SEMICOLON) then
      call self%advance()
    end if

    ! Expect 'do'
    call self%expect(TOKEN_DO)

    ! Skip newline after do
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE) then
      call self%advance()
    end if

    ! Parse loop body
    call parse_loop_body(self, while_node%body)

    ! Expect 'done'
    call self%expect(TOKEN_DONE)

    call move_alloc(while_node, node)
  end function parser_parse_while_loop

  ! Parse word
  function parser_parse_word(self) result(node)
    class(parser_t), intent(inout) :: self
    class(ast_node_t), allocatable :: node
    type(word_node_t), allocatable :: word_node
    type(token_t) :: tok

    allocate(word_node)
    word_node%node_type = NODE_WORD
    tok = self%current_token()
    word_node%text = tok%value
    call self%advance()

    call move_alloc(word_node, node)
  end function parser_parse_word

  ! Get current token
  function parser_current_token(self) result(token)
    class(parser_t), intent(in) :: self
    type(token_t) :: token

    if (self%current <= self%token_count) then
      token = self%tokens(self%current)
    else
      token%type = TOKEN_EOF
    end if
  end function parser_current_token

  ! Peek at next token
  function parser_peek_token(self, offset) result(token)
    class(parser_t), intent(in) :: self
    integer, intent(in), optional :: offset
    type(token_t) :: token
    integer :: pos

    pos = self%current + 1
    if (present(offset)) pos = self%current + offset

    if (pos <= self%token_count) then
      token = self%tokens(pos)
    else
      token%type = TOKEN_EOF
    end if
  end function parser_peek_token

  ! Advance to next token
  subroutine parser_advance(self)
    class(parser_t), intent(inout) :: self

    if (self%current <= self%token_count) then
      self%current = self%current + 1
    end if
  end subroutine parser_advance

  ! Expect specific token type
  subroutine parser_expect(self, token_type)
    class(parser_t), intent(inout) :: self
    integer, intent(in) :: token_type
    type(token_t) :: tok

    tok = self%current_token()
    if (tok%type /= token_type) then
      write(error_unit, '(a,i0,a,i0)') &
        'Parse error: expected token type ', token_type, &
        ' but got ', tok%type
      stop 1
    end if

    call self%advance()
  end subroutine parser_expect

  ! Clean up parser
  subroutine parser_destroy(self)
    class(parser_t), intent(inout) :: self

    if (allocated(self%tokens)) deallocate(self%tokens)
    self%token_count = 0
    self%current = 1
  end subroutine parser_destroy

  ! Helper: Parse command words
  subroutine parse_command_words(parser, cmd_node)
    type(parser_t), intent(inout) :: parser
    type(command_node_t), intent(inout) :: cmd_node
    type(token_t) :: tok

    ! For now, just skip words without collecting them
    ! TODO: Implement proper word collection
    do while (parser%current <= parser%token_count)
      tok = parser%current_token()
      select case(tok%type)
      case(TOKEN_WORD, TOKEN_STRING, TOKEN_VARIABLE)
        call parser%advance()
      case default
        exit
      end select
    end do
  end subroutine parse_command_words

  ! Helper: Parse word list for 'for' loops
  subroutine parse_word_list(parser, word_list)
    type(parser_t), intent(inout) :: parser
    class(ast_node_t), allocatable, intent(out) :: word_list(:)
    type(token_t) :: tok

    ! For now, just skip words without collecting them
    ! TODO: Implement proper word list collection
    do while (parser%current <= parser%token_count)
      tok = parser%current_token()
      select case(tok%type)
      case(TOKEN_WORD, TOKEN_STRING, TOKEN_VARIABLE)
        call parser%advance()
      case(TOKEN_NEWLINE, TOKEN_SEMICOLON, TOKEN_DO)
        exit
      case default
        exit
      end select
    end do
  end subroutine parse_word_list

  ! Helper: Parse loop body
  subroutine parse_loop_body(parser, body)
    type(parser_t), intent(inout) :: parser
    class(ast_node_t), allocatable, intent(out) :: body(:)

    call parse_command_sequence(parser, body, [TOKEN_DONE])
  end subroutine parse_loop_body

  ! Helper: Parse sequence of commands until terminator
  subroutine parse_command_sequence(parser, commands, terminators)
    type(parser_t), intent(inout) :: parser
    class(ast_node_t), allocatable, intent(out) :: commands(:)
    integer, intent(in) :: terminators(:)
    integer :: i
    type(token_t) :: tok
    logical :: is_terminator

    ! For now, just skip commands until terminator
    ! TODO: Implement proper command sequence collection
    do while (parser%current <= parser%token_count)
      tok = parser%current_token()

      ! Check for terminator
      is_terminator = .false.
      do i = 1, size(terminators)
        if (tok%type == terminators(i)) then
          is_terminator = .true.
          exit
        end if
      end do
      if (is_terminator) exit

      ! Skip newlines
      if (tok%type == TOKEN_NEWLINE) then
        call parser%advance()
        cycle
      end if

      ! Skip this command
      block
        class(ast_node_t), allocatable :: cmd
        cmd = parser%parse_command_list()
      end block
    end do
  end subroutine parse_command_sequence


end module parser