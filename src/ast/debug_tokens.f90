program debug_tokens
  use ast_types_enhanced
  use lexer_simple
  implicit none

  type(lexer_simple_t) :: lex
  character(:), allocatable :: input
  integer :: i

  input = 'for ((i=0; i<3; i++)); do echo $i; done'
  call lex%init(input)
  call lex%tokenize()

  print *, "Total tokens:", lex%token_count
  print *, ""
  
  do i = 1, lex%token_count
    write(*, '(a,i15,a,i15,a,a)') "Token ", i, ": type=", lex%tokens(i)%type, &
                                " value='", trim(lex%tokens(i)%value), "'"
  end do

  call lex%destroy()
end program debug_tokens
