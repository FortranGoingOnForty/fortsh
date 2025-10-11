program test_cond_expr_parser
  use ast_types_enhanced
  use lexer_simple
  use parser_enhanced
  implicit none

  type(lexer_simple_t) :: lex
  type(parser_enhanced_t) :: parser
  character(:), allocatable :: input
  class(ast_node_t), pointer :: result
  integer :: exit_code

  exit_code = 0

  ! Test 1: Simple file test
  print *, "=== Test 1: [[ -f file.txt ]] ==="
  input = '[[ -f file.txt ]]'
  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:", lex%token_count
  call parser%init(lex%tokens, lex%token_count)
  result => parser%parse_command()

  if (associated(result)) then
    select type(result)
    type is (cond_expr_node_t)
      print *, "✓ Parsed as cond_expr_node_t"
      print *, "  Expression: '", trim(result%expression), "'"
      if (trim(result%expression) == "-f file.txt") then
        print *, "✓ Expression content correct"
      else
        print *, "✗ Expression content incorrect"
        exit_code = 1
      end if
    class default
      print *, "✗ Wrong node type"
      exit_code = 1
    end select
    deallocate(result)
  else
    print *, "✗ Parser returned null"
    exit_code = 1
  end if

  call parser%destroy()
  call lex%destroy()
  print *, ""

  ! Test 2: String comparison
  print *, "=== Test 2: [[ $var == 'value' ]] ==="
  input = '[[ $var == ''value'' ]]'
  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:", lex%token_count
  call parser%init(lex%tokens, lex%token_count)
  result => parser%parse_command()

  if (associated(result)) then
    select type(result)
    type is (cond_expr_node_t)
      print *, "✓ Parsed as cond_expr_node_t"
      print *, "  Expression: '", trim(result%expression), "'"
    class default
      print *, "✗ Wrong node type"
      exit_code = 1
    end select
    deallocate(result)
  else
    print *, "✗ Parser returned null"
    exit_code = 1
  end if

  call parser%destroy()
  call lex%destroy()
  print *, ""

  ! Test 3: Complex condition with logical operators
  print *, "=== Test 3: [[ -f file && -r file ]] ==="
  input = '[[ -f file && -r file ]]'
  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:", lex%token_count
  call parser%init(lex%tokens, lex%token_count)
  result => parser%parse_command()

  if (associated(result)) then
    select type(result)
    type is (cond_expr_node_t)
      print *, "✓ Parsed as cond_expr_node_t"
      print *, "  Expression: '", trim(result%expression), "'"
    class default
      print *, "✗ Wrong node type"
      exit_code = 1
    end select
    deallocate(result)
  else
    print *, "✗ Parser returned null"
    exit_code = 1
  end if

  call parser%destroy()
  call lex%destroy()
  print *, ""

  ! Test 4: Pattern matching
  print *, "=== Test 4: [[ $file == *.txt ]] ==="
  input = '[[ $file == *.txt ]]'
  call lex%init(input)
  call lex%tokenize()

  print *, "Tokens:", lex%token_count
  call parser%init(lex%tokens, lex%token_count)
  result => parser%parse_command()

  if (associated(result)) then
    select type(result)
    type is (cond_expr_node_t)
      print *, "✓ Parsed as cond_expr_node_t"
      print *, "  Expression: '", trim(result%expression), "'"
    class default
      print *, "✗ Wrong node type"
      exit_code = 1
    end select
    deallocate(result)
  else
    print *, "✗ Parser returned null"
    exit_code = 1
  end if

  call parser%destroy()
  call lex%destroy()

  if (exit_code == 0) then
    print *, ""
    print *, "=== All parser tests passed! ==="
  else
    print *, ""
    print *, "=== Some tests failed ==="
  end if

  stop exit_code
end program test_cond_expr_parser
