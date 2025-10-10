! ==============================================================================
! Module: parser_enhanced
! Purpose: Enhanced parser using pointer arrays for proper polymorphism
! ==============================================================================
module parser_enhanced
  use ast_types_enhanced
  use iso_fortran_env, only: error_unit
  implicit none

  type :: parser_enhanced_t
    type(token_t), allocatable :: tokens(:)
    integer :: token_count = 0
    integer :: current = 1
  contains
    procedure :: init => parser_init
    procedure :: parse => parser_parse
    procedure :: current_token => parser_current_token
    procedure :: advance => parser_advance
    procedure :: expect => parser_expect
    procedure :: parse_script => parser_parse_script
    procedure :: parse_command_list => parser_parse_command_list
    procedure :: parse_pipeline => parser_parse_pipeline
    procedure :: parse_command => parser_parse_command
    procedure :: parse_for_loop => parser_parse_for_loop
    procedure :: parse_if_statement => parser_parse_if_statement
    procedure :: parse_while_loop => parser_parse_while_loop
    procedure :: parse_case_statement => parser_parse_case_statement
    procedure :: parse_function_definition => parser_parse_function_definition
    procedure :: parse_word => parser_parse_word
    procedure :: parse_variable => parser_parse_variable
    procedure :: parse_redirection => parser_parse_redirection
    procedure :: parse_command_subst => parser_parse_command_subst
    procedure :: parse_arithmetic => parser_parse_arithmetic
    procedure :: destroy => parser_destroy
  end type parser_enhanced_t

contains

  subroutine parser_init(self, tokens, count)
    class(parser_enhanced_t), intent(inout) :: self
    type(token_t), intent(in) :: tokens(:)
    integer, intent(in) :: count

    if (allocated(self%tokens)) deallocate(self%tokens)
    allocate(self%tokens(count))
    self%tokens = tokens(1:count)
    self%token_count = count
    self%current = 1
  end subroutine parser_init

  function parser_parse(self) result(ast)
    class(parser_enhanced_t), intent(inout) :: self
    type(script_node_t) :: ast

    ast = self%parse_script()
  end function parser_parse

  function parser_parse_script(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    type(script_node_t) :: node
    type(node_list_t) :: stmt_list
    class(ast_node_t), pointer :: stmt
    type(token_t) :: tok

    node%node_type = NODE_SCRIPT
    node%num_statements = 0

    ! Collect statements using linked list
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_EOF) exit

      ! Skip newlines at top level
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      ! Parse statement
      stmt => self%parse_command_list()
      if (associated(stmt)) then
        call stmt_list%append(stmt)
        deallocate(stmt)  ! List makes a copy
      end if
    end do

    ! Convert to pointer array
    if (stmt_list%count > 0) then
      call stmt_list%to_ptr_array(node%statements)
      node%num_statements = stmt_list%count
    end if

    call stmt_list%clear()
  end function parser_parse_script

  function parser_parse_command_list(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(and_list_node_t), pointer :: and_node
    type(or_list_node_t), pointer :: or_node
    class(ast_node_t), pointer :: right
    type(token_t) :: tok

    ! Parse first pipeline
    node => self%parse_pipeline()

    ! Check for logical operators (&& or ||)
    do while (self%current <= self%token_count)
      tok = self%current_token()

      if (tok%type == TOKEN_AND) then
        ! && operator - execute right only if left succeeds
        call self%advance()  ! skip &&
        right => self%parse_pipeline()

        allocate(and_node)
        and_node%node_type = NODE_AND_LIST
        and_node%left%ptr => node
        and_node%right%ptr => right
        node => and_node

      else if (tok%type == TOKEN_OR) then
        ! || operator - execute right only if left fails
        call self%advance()  ! skip ||
        right => self%parse_pipeline()

        allocate(or_node)
        or_node%node_type = NODE_OR_LIST
        or_node%left%ptr => node
        or_node%right%ptr => right
        node => or_node

      else
        ! No more logical operators
        exit
      end if
    end do

    ! Check for semicolon or newline
    if (self%current <= self%token_count) then
      tok = self%current_token()
      if (tok%type == TOKEN_SEMICOLON .or. &
          tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if
    end if
  end function parser_parse_command_list

  function parser_parse_pipeline(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(pipeline_node_t), pointer :: pipe_node
    type(node_list_t) :: cmd_list
    class(ast_node_t), pointer :: cmd
    type(token_t) :: tok

    ! Parse first command
    cmd => self%parse_command()

    ! Check if there's a pipe
    if (self%current <= self%token_count) then
      tok = self%current_token()
      if (tok%type == TOKEN_PIPE) then
        ! We have a pipeline
        allocate(pipeline_node_t :: pipe_node)
        pipe_node%node_type = NODE_PIPELINE

        ! Add first command
        call cmd_list%append(cmd)
        deallocate(cmd)

        ! Parse remaining commands in pipeline
        do while (self%current <= self%token_count)
          tok = self%current_token()
          if (tok%type /= TOKEN_PIPE) exit

          call self%advance()  ! skip pipe

          ! Parse next command
          cmd => self%parse_command()
          call cmd_list%append(cmd)
          deallocate(cmd)
        end do

        ! Convert to pointer array
        if (cmd_list%count > 0) then
          call cmd_list%to_ptr_array(pipe_node%commands)
          pipe_node%num_commands = cmd_list%count
        end if

        call cmd_list%clear()
        node => pipe_node
      else
        ! Single command, not a pipeline
        node => cmd
      end if
    else
      ! Single command at end of input
      node => cmd
    end if
  end function parser_parse_pipeline

  function parser_parse_command(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(command_node_t), pointer :: cmd_node
    type(token_t) :: token
    type(node_list_t) :: word_list, redir_list
    class(ast_node_t), pointer :: word, redir
    integer :: level_value

    token = self%current_token()

    ! Check for control structures
    select case(token%type)
    case(TOKEN_FOR)
      node => self%parse_for_loop()
      return

    case(TOKEN_IF)
      node => self%parse_if_statement()
      return

    case(TOKEN_WHILE)
      node => self%parse_while_loop()
      return

    case(TOKEN_CASE)
      node => self%parse_case_statement()
      return

    case(TOKEN_FUNCTION)
      node => self%parse_function_definition()
      return

    case(TOKEN_BREAK)
      allocate(break_node_t :: node)
      select type(node)
      type is (break_node_t)
        node%node_type = NODE_BREAK
        node%levels = 1
        call self%advance()
        ! Check for numeric argument
        token = self%current_token()
        if (token%type == TOKEN_WORD) then
          read(token%value, *, iostat=level_value) level_value
          if (level_value == 0) then
            node%levels = level_value
            call self%advance()
          end if
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
        token = self%current_token()
        if (token%type == TOKEN_WORD) then
          read(token%value, *, iostat=level_value) level_value
          if (level_value == 0) then
            node%levels = level_value
            call self%advance()
          end if
        end if
      end select
      return
    end select

    ! Parse simple command
    allocate(cmd_node)
    cmd_node%node_type = NODE_COMMAND
    cmd_node%num_words = 0
    cmd_node%num_redirections = 0

    ! Parse command words and redirections
    do while (self%current <= self%token_count)
      token = self%current_token()
      select case(token%type)
      case(TOKEN_WORD, TOKEN_STRING)
        word => self%parse_word()
        call word_list%append(word)
        deallocate(word)

      case(TOKEN_VARIABLE)
        word => self%parse_variable()
        call word_list%append(word)
        deallocate(word)

      case(TOKEN_COMMAND_SUBST_START)
        word => self%parse_command_subst()
        call word_list%append(word)
        deallocate(word)

      case(TOKEN_ARITH_START)
        word => self%parse_arithmetic()
        call word_list%append(word)
        deallocate(word)

      case(TOKEN_REDIRECT_IN, TOKEN_REDIRECT_OUT, TOKEN_REDIRECT_APPEND, &
           TOKEN_REDIRECT_HERE, TOKEN_REDIRECT_HERE_STRING)
        redir => self%parse_redirection(token%type)
        call redir_list%append(redir)
        deallocate(redir)
        ! Don't exit - continue parsing

      case default
        exit
      end select
    end do

    ! Convert words to pointer array
    if (word_list%count > 0) then
      call word_list%to_ptr_array(cmd_node%words)
      cmd_node%num_words = word_list%count
    end if

    ! Convert redirections to pointer array
    if (redir_list%count > 0) then
      call redir_list%to_ptr_array(cmd_node%redirections)
      cmd_node%num_redirections = redir_list%count
    end if

    call word_list%clear()
    call redir_list%clear()
    node => cmd_node
  end function parser_parse_command

  function parser_parse_for_loop(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(for_node_t), pointer :: for_node
    type(token_t) :: tok
    type(node_list_t) :: word_list, body_list
    class(ast_node_t), pointer :: word, stmt

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
    do while (self%current <= self%token_count)
      tok = self%current_token()
      select case(tok%type)
      case(TOKEN_WORD, TOKEN_STRING)
        word => self%parse_word()
        call word_list%append(word)
        deallocate(word)
      case(TOKEN_VARIABLE)
        word => self%parse_variable()
        call word_list%append(word)
        deallocate(word)
      case(TOKEN_COMMAND_SUBST_START)
        word => self%parse_command_subst()
        call word_list%append(word)
        deallocate(word)
      case(TOKEN_ARITH_START)
        word => self%parse_arithmetic()
        call word_list%append(word)
        deallocate(word)
      case(TOKEN_NEWLINE, TOKEN_SEMICOLON, TOKEN_DO)
        exit
      case default
        exit
      end select
    end do

    if (word_list%count > 0) then
      call word_list%to_ptr_array(for_node%word_list)
      for_node%num_words = word_list%count
    end if
    call word_list%clear()

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
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_DONE) exit
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      stmt => self%parse_command_list()
      if (associated(stmt)) then
        call body_list%append(stmt)
        deallocate(stmt)
      end if
    end do

    if (body_list%count > 0) then
      call body_list%to_ptr_array(for_node%body)
      for_node%num_body = body_list%count
    end if
    call body_list%clear()

    ! Expect 'done'
    call self%expect(TOKEN_DONE)

    node => for_node
  end function parser_parse_for_loop

  function parser_parse_if_statement(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(if_node_t), pointer :: if_node
    type(token_t) :: tok
    type(node_list_t) :: then_list, else_list
    class(ast_node_t), pointer :: stmt

    allocate(if_node)
    if_node%node_type = NODE_IF

    ! Expect 'if'
    call self%expect(TOKEN_IF)

    ! Parse condition (can be a pipeline)
    if_node%condition%ptr => self%parse_command_list()

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
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_ELSE .or. &
          tok%type == TOKEN_ELIF .or. &
          tok%type == TOKEN_FI) exit
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      stmt => self%parse_command_list()
      if (associated(stmt)) then
        call then_list%append(stmt)
        deallocate(stmt)
      end if
    end do

    if (then_list%count > 0) then
      call then_list%to_ptr_array(if_node%then_branch)
      if_node%num_then = then_list%count
    end if
    call then_list%clear()

    ! Check for else
    tok = self%current_token()
    if (tok%type == TOKEN_ELSE) then
      call self%advance()
      tok = self%current_token()
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if

      ! Parse else branch
      do while (self%current <= self%token_count)
        tok = self%current_token()
        if (tok%type == TOKEN_FI) exit
        if (tok%type == TOKEN_NEWLINE) then
          call self%advance()
          cycle
        end if

        stmt => self%parse_command_list()
        if (associated(stmt)) then
          call else_list%append(stmt)
          deallocate(stmt)
        end if
      end do

      if (else_list%count > 0) then
        call else_list%to_ptr_array(if_node%else_branch)
        if_node%num_else = else_list%count
      end if
      call else_list%clear()
    end if

    ! Expect 'fi'
    call self%expect(TOKEN_FI)

    node => if_node
  end function parser_parse_if_statement

  function parser_parse_while_loop(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(while_node_t), pointer :: while_node
    type(token_t) :: tok
    type(node_list_t) :: body_list
    class(ast_node_t), pointer :: stmt

    allocate(while_node)
    while_node%node_type = NODE_WHILE

    ! Expect 'while'
    call self%expect(TOKEN_WHILE)

    ! Parse condition (can be a pipeline)
    while_node%condition%ptr => self%parse_command_list()

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
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_DONE) exit
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      stmt => self%parse_command_list()
      if (associated(stmt)) then
        call body_list%append(stmt)
        deallocate(stmt)
      end if
    end do

    if (body_list%count > 0) then
      call body_list%to_ptr_array(while_node%body)
      while_node%num_body = body_list%count
    end if
    call body_list%clear()

    ! Expect 'done'
    call self%expect(TOKEN_DONE)

    node => while_node
  end function parser_parse_while_loop

  function parser_parse_case_statement(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(case_node_t), pointer :: case_node
    type(token_t) :: tok
    type(node_list_t) :: cmd_list
    class(ast_node_t), pointer :: stmt
    character(:), allocatable :: pattern
    integer :: item_count, pattern_count, i

    allocate(case_node)
    case_node%node_type = NODE_CASE

    ! Expect 'case'
    call self%expect(TOKEN_CASE)

    ! Parse the expression to match
    tok = self%current_token()
    if (tok%type == TOKEN_WORD .or. tok%type == TOKEN_VARIABLE) then
      case_node%expr%ptr => self%parse_word()
    else
      ! Error: expected word after case
      node => case_node
      return
    end if

    ! Expect 'in'
    call self%expect(TOKEN_IN)

    ! Skip newline after 'in' if present
    tok = self%current_token()
    if (tok%type == TOKEN_NEWLINE) then
      call self%advance()
    end if

    ! Parse case items
    item_count = 0
    allocate(case_node%items(10))  ! Start with space for 10 items

    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_ESAC) exit

      ! Skip newlines between items
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      ! Parse pattern(s)
      item_count = item_count + 1
      if (item_count > size(case_node%items)) then
        ! Need to resize array - simplified for now
        exit
      end if

      ! Initialize this item
      pattern_count = 0
      allocate(character(len=256) :: case_node%items(item_count)%patterns(5))  ! Space for 5 patterns

      ! Collect patterns (separated by |)
      do while (self%current <= self%token_count)
        tok = self%current_token()
        if (tok%type /= TOKEN_WORD .and. tok%type /= TOKEN_STRING) exit

        pattern_count = pattern_count + 1
        if (pattern_count <= 5) then
          case_node%items(item_count)%patterns(pattern_count) = tok%value
        end if
        call self%advance()

        ! Check for | (alternate pattern)
        tok = self%current_token()
        if (tok%type == TOKEN_PIPE) then
          call self%advance()
        else if (tok%type == TOKEN_RPAREN) then
          call self%advance()
          exit
        else
          ! Expect ) after pattern
          exit
        end if
      end do
      case_node%items(item_count)%num_patterns = pattern_count

      ! Skip newline after )
      tok = self%current_token()
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if

      ! Parse commands for this pattern
      cmd_list%count = 0
      do while (self%current <= self%token_count)
        tok = self%current_token()

        ! Check for end of this case item (;;)
        if (tok%type == TOKEN_SEMICOLON) then
          call self%advance()
          tok = self%current_token()
          if (tok%type == TOKEN_SEMICOLON) then
            call self%advance()
            exit
          end if
          ! Single semicolon - continue within same item
        end if

        ! Check for esac or next pattern
        if (tok%type == TOKEN_ESAC) exit
        if (tok%type == TOKEN_WORD .or. tok%type == TOKEN_STRING) then
          ! Peek ahead to see if it's a pattern (has ))
          if (self%current + 1 <= self%token_count) then
            if (self%tokens(self%current + 1)%type == TOKEN_RPAREN) then
              exit  ! Start of next pattern
            end if
          end if
        end if

        if (tok%type == TOKEN_NEWLINE) then
          call self%advance()
          cycle
        end if

        stmt => self%parse_command_list()
        if (associated(stmt)) then
          call cmd_list%append(stmt)
          deallocate(stmt)
        end if
      end do

      ! Store commands for this item
      if (cmd_list%count > 0) then
        call cmd_list%to_ptr_array(case_node%items(item_count)%commands)
        case_node%items(item_count)%num_commands = cmd_list%count
      end if
      call cmd_list%clear()
    end do

    case_node%num_items = item_count

    ! Expect 'esac'
    call self%expect(TOKEN_ESAC)

    node => case_node
  end function parser_parse_case_statement

  function parser_parse_function_definition(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(function_node_t), pointer :: func_node
    type(token_t) :: tok
    type(node_list_t) :: body_list
    class(ast_node_t), pointer :: stmt

    allocate(func_node)
    func_node%node_type = NODE_FUNCTION

    ! Two forms:
    ! 1) function name { ... }
    ! 2) name() { ... }

    tok = self%current_token()
    if (tok%type == TOKEN_FUNCTION) then
      ! Form 1: function name { ... }
      call self%advance()  ! Skip 'function'

      ! Get function name
      tok = self%current_token()
      if (tok%type == TOKEN_WORD) then
        func_node%name = tok%value
        call self%advance()
      else
        ! Error: expected function name
        node => func_node
        return
      end if

      ! Expect { or allow () then {
      tok = self%current_token()
      if (tok%type == TOKEN_LPAREN) then
        call self%advance()
        tok = self%current_token()
        if (tok%type == TOKEN_RPAREN) then
          call self%advance()
        end if
      end if

      ! Expect {
      tok = self%current_token()
      if (tok%type == TOKEN_LBRACE) then
        call self%advance()
      else if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        tok = self%current_token()
        if (tok%type == TOKEN_LBRACE) then
          call self%advance()
        end if
      end if
    else if (tok%type == TOKEN_WORD) then
      ! Form 2: name() { ... } - check ahead for ()
      func_node%name = tok%value
      call self%advance()

      ! Expect ()
      tok = self%current_token()
      if (tok%type == TOKEN_LPAREN) then
        call self%advance()
        tok = self%current_token()
        if (tok%type == TOKEN_RPAREN) then
          call self%advance()
        else
          ! Not a function definition
          deallocate(func_node)
          node => null()
          return
        end if
      else
        ! Not a function definition
        deallocate(func_node)
        node => null()
        return
      end if

      ! Skip optional newline
      tok = self%current_token()
      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
      end if

      ! Expect {
      tok = self%current_token()
      if (tok%type == TOKEN_LBRACE) then
        call self%advance()
      else
        ! Not a function definition
        deallocate(func_node)
        node => null()
        return
      end if
    else
      ! Not a function definition
      deallocate(func_node)
      node => null()
      return
    end if

    ! Parse function body until }
    body_list%count = 0
    do while (self%current <= self%token_count)
      tok = self%current_token()

      if (tok%type == TOKEN_RBRACE) then
        call self%advance()
        exit
      end if

      if (tok%type == TOKEN_NEWLINE) then
        call self%advance()
        cycle
      end if

      if (tok%type == TOKEN_EOF) exit

      stmt => self%parse_command_list()
      if (associated(stmt)) then
        call body_list%append(stmt)
        deallocate(stmt)
      end if
    end do

    ! Store body
    if (body_list%count > 0) then
      call body_list%to_ptr_array(func_node%body)
      func_node%num_body = body_list%count
    end if
    call body_list%clear()

    node => func_node
  end function parser_parse_function_definition

  function parser_parse_word(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(word_node_t), pointer :: word_node
    type(token_t) :: tok

    allocate(word_node)
    word_node%node_type = NODE_WORD
    tok = self%current_token()
    word_node%text = tok%value
    word_node%needs_expansion = .false.
    call self%advance()

    node => word_node
  end function parser_parse_word

  function parser_parse_variable(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(variable_node_t), pointer :: var_node
    type(token_t) :: tok

    allocate(var_node)
    var_node%node_type = NODE_VARIABLE
    tok = self%current_token()
    var_node%name = tok%value
    call self%advance()

    node => var_node
  end function parser_parse_variable

  function parser_parse_redirection(self, redir_type) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    integer, intent(in) :: redir_type
    class(ast_node_t), pointer :: node
    type(redirection_node_t), pointer :: redir_node
    type(token_t) :: tok

    allocate(redir_node)
    redir_node%node_type = NODE_REDIRECTION

    ! Set redirection type
    select case(redir_type)
    case(TOKEN_REDIRECT_IN)
      redir_node%redirect_type = 1  ! input
      redir_node%fd = 0  ! stdin
    case(TOKEN_REDIRECT_OUT)
      redir_node%redirect_type = 2  ! output
      redir_node%fd = 1  ! stdout
    case(TOKEN_REDIRECT_APPEND)
      redir_node%redirect_type = 3  ! append
      redir_node%fd = 1  ! stdout
    case(TOKEN_REDIRECT_HERE)
      redir_node%redirect_type = 4  ! heredoc
      redir_node%fd = 0  ! stdin
    case(TOKEN_REDIRECT_HERE_STRING)
      redir_node%redirect_type = 5  ! here string
      redir_node%fd = 0  ! stdin
    end select

    ! Skip the redirection operator
    call self%advance()

    ! Handle here documents and here strings
    if (redir_type == TOKEN_REDIRECT_HERE) then
      ! Parse heredoc delimiter
      tok = self%current_token()
      if (tok%type == TOKEN_WORD .or. tok%type == TOKEN_STRING) then
        redir_node%heredoc_delimiter = tok%value
        call self%advance()
        ! Note: heredoc content will be collected later by the parser
        ! For now, we just store the delimiter
      end if
    else if (redir_type == TOKEN_REDIRECT_HERE_STRING) then
      ! Parse here string content (just the next word/string)
      tok = self%current_token()
      if (tok%type == TOKEN_WORD .or. tok%type == TOKEN_STRING .or. tok%type == TOKEN_VARIABLE) then
        ! Store the content directly
        redir_node%heredoc_content = tok%value
        call self%advance()
      end if
    else
      ! Parse the target file for regular redirections
      tok = self%current_token()
      if (tok%type == TOKEN_WORD .or. tok%type == TOKEN_STRING) then
        allocate(word_node_t :: redir_node%target)
        select type(target => redir_node%target)
        type is (word_node_t)
          target%node_type = NODE_WORD
          target%text = tok%value
        end select
        call self%advance()
      end if
    end if

    node => redir_node
  end function parser_parse_redirection

  function parser_parse_command_subst(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(command_subst_node_t), pointer :: subst_node
    type(token_t) :: tok
    integer :: paren_depth, i
    integer :: start_pos, end_pos
    character(:), allocatable :: subcommand

    allocate(subst_node)
    subst_node%node_type = NODE_COMMAND_SUBST
    subst_node%is_backtick = .false.

    ! Skip the $( token
    call self%advance()

    ! Find the matching )
    ! For simplicity, collect everything until matching )
    paren_depth = 1
    start_pos = self%current

    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_LPAREN) then
        paren_depth = paren_depth + 1
      else if (tok%type == TOKEN_RPAREN) then
        paren_depth = paren_depth - 1
        if (paren_depth == 0) then
          end_pos = self%current - 1
          call self%advance()  ! Skip the closing )
          exit
        end if
      else if (tok%type == TOKEN_EOF) then
        ! Error: unclosed command substitution
        exit
      end if
      call self%advance()
    end do

    ! Parse the command inside
    ! For now, create a simple command node with the content
    ! In a full implementation, we'd save/restore parser state and parse recursively
    allocate(command_node_t :: subst_node%command%ptr)
    select type(cmd => subst_node%command%ptr)
    type is (command_node_t)
      cmd%node_type = NODE_COMMAND
      ! For now, just store the first token as a word
      if (start_pos <= end_pos) then
        allocate(cmd%words(1))
        allocate(word_node_t :: cmd%words(1)%ptr)
        select type(w => cmd%words(1)%ptr)
        type is (word_node_t)
          w%node_type = NODE_WORD
          ! Concatenate all tokens for now (simple implementation)
          w%text = self%tokens(start_pos)%value
          do i = start_pos + 1, end_pos
            w%text = trim(w%text) // ' ' // trim(self%tokens(i)%value)
          end do
        end select
        cmd%num_words = 1
      end if
    end select

    node => subst_node
  end function parser_parse_command_subst

  function parser_parse_arithmetic(self) result(node)
    class(parser_enhanced_t), intent(inout) :: self
    class(ast_node_t), pointer :: node
    type(arithmetic_node_t), pointer :: arith_node
    type(token_t) :: tok
    integer :: start_pos
    character(:), allocatable :: expr

    allocate(arith_node)
    arith_node%node_type = NODE_ARITHMETIC

    ! Skip the $(( token
    call self%advance()

    ! Collect everything until ))
    expr = ''
    do while (self%current <= self%token_count)
      tok = self%current_token()
      if (tok%type == TOKEN_ARITH_END) then
        call self%advance()  ! Skip the ))
        exit
      end if
      ! Build the expression from tokens
      if (len(expr) > 0) expr = expr // ' '
      expr = expr // tok%value
      call self%advance()
    end do

    arith_node%expression = expr
    node => arith_node
  end function parser_parse_arithmetic

  function parser_current_token(self) result(token)
    class(parser_enhanced_t), intent(in) :: self
    type(token_t) :: token

    if (self%current <= self%token_count) then
      token = self%tokens(self%current)
    else
      token%type = TOKEN_EOF
    end if
  end function parser_current_token

  subroutine parser_advance(self)
    class(parser_enhanced_t), intent(inout) :: self

    if (self%current <= self%token_count) then
      self%current = self%current + 1
    end if
  end subroutine parser_advance

  subroutine parser_expect(self, token_type)
    class(parser_enhanced_t), intent(inout) :: self
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

  subroutine parser_destroy(self)
    class(parser_enhanced_t), intent(inout) :: self

    if (allocated(self%tokens)) deallocate(self%tokens)
    self%token_count = 0
    self%current = 1
  end subroutine parser_destroy

end module parser_enhanced