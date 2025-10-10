program test_heredoc
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: pars
  type(script_node_t) :: ast
  character(:), allocatable :: input
  integer :: i

  print *, "=== Test 1: Lexing here string ==="
  input = 'cat <<< "Hello World"'
  call lex%init(input)
  call lex%tokenize()
  
  print *, "Tokens:"
  do i = 1, lex%token_count
    print *, "  ", i, "Type:", lex%tokens(i)%type, "Value: [", trim(lex%tokens(i)%value), "]"
  end do
  print *, ""

  print *, "=== Test 2: Parsing here string ==="
  call pars%init(lex%tokens, lex%token_count)
  ast = pars%parse()
  
  if (ast%num_statements > 0) then
    print *, "Parsed successfully, statements:", ast%num_statements
    if (associated(ast%statements(1)%ptr)) then
      select type(cmd => ast%statements(1)%ptr)
      type is (command_node_t)
        print *, "  Command with", cmd%num_words, "words and", cmd%num_redirections, "redirections"
        if (cmd%num_redirections > 0) then
          select type(r => cmd%redirections(1)%ptr)
          type is (redirection_node_t)
            print *, "  Redirect type:", r%redirect_type
            if (allocated(r%heredoc_content)) then
              print *, "  Content: [", trim(r%heredoc_content), "]"
            end if
          end select
        end if
      end select
    end if
  end if

  call lex%destroy()
  call pars%destroy()

end program test_heredoc
