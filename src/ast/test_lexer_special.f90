program test_lexer
  use lexer_simple
  use ast_types_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  integer :: i

  ! Test $# tokenization
  call lex%init("echo $# and $1")
  call lex%tokenize()
  
  print *, "Tokens:"
  do i = 1, lex%token_count
    print *, i, "Type:", lex%tokens(i)%type, "Value: [", trim(lex%tokens(i)%value), "]"
  end do

end program test_lexer
