! ==============================================================================
! Module: ast_types
! Purpose: Abstract Syntax Tree type definitions for fortsh
! ==============================================================================
module ast_types
  use iso_fortran_env, only: int32, int64
  implicit none

  ! Token types for lexical analysis
  integer, parameter :: TOKEN_EOF = 0
  integer, parameter :: TOKEN_WORD = 1
  integer, parameter :: TOKEN_NUMBER = 2
  integer, parameter :: TOKEN_STRING = 3
  integer, parameter :: TOKEN_VARIABLE = 4
  integer, parameter :: TOKEN_SEMICOLON = 5
  integer, parameter :: TOKEN_NEWLINE = 6
  integer, parameter :: TOKEN_PIPE = 7
  integer, parameter :: TOKEN_AND = 8         ! &&
  integer, parameter :: TOKEN_OR = 9          ! ||
  integer, parameter :: TOKEN_BACKGROUND = 10 ! &
  integer, parameter :: TOKEN_REDIRECT_IN = 11   ! <
  integer, parameter :: TOKEN_REDIRECT_OUT = 12  ! >
  integer, parameter :: TOKEN_REDIRECT_APPEND = 13 ! >>
  integer, parameter :: TOKEN_REDIRECT_HERE = 14   ! <<
  integer, parameter :: TOKEN_LPAREN = 15     ! (
  integer, parameter :: TOKEN_RPAREN = 16     ! )
  integer, parameter :: TOKEN_LBRACE = 17     ! {
  integer, parameter :: TOKEN_RBRACE = 18     ! }
  integer, parameter :: TOKEN_LBRACKET = 19   ! [
  integer, parameter :: TOKEN_RBRACKET = 20   ! ]
  integer, parameter :: TOKEN_IF = 21
  integer, parameter :: TOKEN_THEN = 22
  integer, parameter :: TOKEN_ELSE = 23
  integer, parameter :: TOKEN_ELIF = 24
  integer, parameter :: TOKEN_FI = 25
  integer, parameter :: TOKEN_FOR = 26
  integer, parameter :: TOKEN_IN = 27
  integer, parameter :: TOKEN_DO = 28
  integer, parameter :: TOKEN_DONE = 29
  integer, parameter :: TOKEN_WHILE = 30
  integer, parameter :: TOKEN_UNTIL = 31
  integer, parameter :: TOKEN_CASE = 32
  integer, parameter :: TOKEN_ESAC = 33
  integer, parameter :: TOKEN_FUNCTION = 34
  integer, parameter :: TOKEN_BREAK = 35
  integer, parameter :: TOKEN_CONTINUE = 36
  integer, parameter :: TOKEN_RETURN = 37

  ! AST Node types
  integer, parameter :: NODE_SCRIPT = 100
  integer, parameter :: NODE_COMMAND = 101
  integer, parameter :: NODE_PIPELINE = 102
  integer, parameter :: NODE_AND_LIST = 103
  integer, parameter :: NODE_OR_LIST = 104
  integer, parameter :: NODE_COMMAND_LIST = 105
  integer, parameter :: NODE_IF = 106
  integer, parameter :: NODE_FOR = 107
  integer, parameter :: NODE_FOR_ARITH = 108
  integer, parameter :: NODE_WHILE = 109
  integer, parameter :: NODE_UNTIL = 110
  integer, parameter :: NODE_CASE = 111
  integer, parameter :: NODE_FUNCTION = 112
  integer, parameter :: NODE_SUBSHELL = 113
  integer, parameter :: NODE_BREAK = 114
  integer, parameter :: NODE_CONTINUE = 115
  integer, parameter :: NODE_RETURN = 116
  integer, parameter :: NODE_WORD = 117
  integer, parameter :: NODE_VARIABLE = 118
  integer, parameter :: NODE_ASSIGNMENT = 119
  integer, parameter :: NODE_REDIRECTION = 120
  integer, parameter :: NODE_COMMAND_SUBST = 121
  integer, parameter :: NODE_ARITHMETIC = 122

  ! Token structure
  type :: token_t
    integer :: type = TOKEN_EOF
    character(:), allocatable :: value
    integer :: line_number = 1
    integer :: column = 1
  end type token_t

  ! Base AST node type
  type :: ast_node_t
    integer :: node_type = 0
    integer :: line_number = 0
    integer :: column = 0
  contains
    procedure :: destroy => ast_node_destroy
  end type ast_node_t

  ! Script node - top level container
  type, extends(ast_node_t) :: script_node_t
    class(ast_node_t), allocatable :: statements(:)
  end type script_node_t

  ! Simple command node
  type, extends(ast_node_t) :: command_node_t
    class(ast_node_t), allocatable :: words(:)        ! Command and arguments
    class(ast_node_t), allocatable :: redirections(:) ! I/O redirections
    class(ast_node_t), allocatable :: assignments(:)  ! Variable assignments
    logical :: background = .false.
  end type command_node_t

  ! Pipeline node (cmd | cmd | cmd)
  type, extends(ast_node_t) :: pipeline_node_t
    class(ast_node_t), allocatable :: commands(:)
    logical :: negate = .false.  ! For ! pipeline
  end type pipeline_node_t

  ! AND list (cmd && cmd && cmd)
  type, extends(ast_node_t) :: and_list_node_t
    class(ast_node_t), allocatable :: commands(:)
  end type and_list_node_t

  ! OR list (cmd || cmd || cmd)
  type, extends(ast_node_t) :: or_list_node_t
    class(ast_node_t), allocatable :: commands(:)
  end type or_list_node_t

  ! Command list (cmd; cmd; cmd)
  type, extends(ast_node_t) :: command_list_node_t
    class(ast_node_t), allocatable :: commands(:)
  end type command_list_node_t

  ! Word node (for command arguments, etc)
  type, extends(ast_node_t) :: word_node_t
    character(:), allocatable :: text
    logical :: needs_expansion = .false.
  end type word_node_t

  ! Variable reference node
  type, extends(ast_node_t) :: variable_node_t
    character(:), allocatable :: name
    character(:), allocatable :: modifier  ! For ${var:-default} etc
    integer :: modifier_type = 0
  end type variable_node_t

  ! Assignment node (var=value)
  type, extends(ast_node_t) :: assignment_node_t
    character(:), allocatable :: name
    class(ast_node_t), allocatable :: value
    logical :: is_export = .false.
    logical :: is_readonly = .false.
    logical :: is_local = .false.
  end type assignment_node_t

  ! Redirection node
  type, extends(ast_node_t) :: redirection_node_t
    integer :: redirect_type = 0
    integer :: fd_number = -1  ! -1 means default (0 for input, 1 for output)
    class(ast_node_t), allocatable :: target
  end type redirection_node_t

  ! If statement node
  type, extends(ast_node_t) :: if_node_t
    class(ast_node_t), allocatable :: condition
    class(ast_node_t), allocatable :: then_branch(:)
    class(ast_node_t), allocatable :: elif_branches(:)  ! Array of elif nodes
    class(ast_node_t), allocatable :: else_branch(:)
  end type if_node_t

  ! For loop node
  type, extends(ast_node_t) :: for_node_t
    character(:), allocatable :: variable
    class(ast_node_t), allocatable :: word_list(:)
    class(ast_node_t), allocatable :: body(:)
  end type for_node_t

  ! Arithmetic for loop node
  type, extends(ast_node_t) :: for_arith_node_t
    class(ast_node_t), allocatable :: init
    class(ast_node_t), allocatable :: condition
    class(ast_node_t), allocatable :: increment
    class(ast_node_t), allocatable :: body(:)
  end type for_arith_node_t

  ! While loop node
  type, extends(ast_node_t) :: while_node_t
    class(ast_node_t), allocatable :: condition
    class(ast_node_t), allocatable :: body(:)
  end type while_node_t

  ! Until loop node
  type, extends(ast_node_t) :: until_node_t
    class(ast_node_t), allocatable :: condition
    class(ast_node_t), allocatable :: body(:)
  end type until_node_t

  ! Case statement node
  type, extends(ast_node_t) :: case_node_t
    class(ast_node_t), allocatable :: expr
    type(case_item_t), allocatable :: cases(:)
  end type case_node_t

  ! Case item (pattern and commands)
  type :: case_item_t
    class(ast_node_t), allocatable :: patterns(:)
    class(ast_node_t), allocatable :: commands(:)
  end type case_item_t

  ! Function definition node
  type, extends(ast_node_t) :: function_node_t
    character(:), allocatable :: name
    class(ast_node_t), allocatable :: body(:)
  end type function_node_t

  ! Subshell node
  type, extends(ast_node_t) :: subshell_node_t
    class(ast_node_t), allocatable :: commands(:)
  end type subshell_node_t

  ! Break statement node
  type, extends(ast_node_t) :: break_node_t
    integer :: levels = 1
  end type break_node_t

  ! Continue statement node
  type, extends(ast_node_t) :: continue_node_t
    integer :: levels = 1
  end type continue_node_t

  ! Return statement node
  type, extends(ast_node_t) :: return_node_t
    integer :: return_code = 0
  end type return_node_t

  ! Command substitution node
  type, extends(ast_node_t) :: command_subst_node_t
    class(ast_node_t), allocatable :: commands(:)
  end type command_subst_node_t

  ! Arithmetic expression node
  type, extends(ast_node_t) :: arithmetic_node_t
    character(:), allocatable :: expression
  end type arithmetic_node_t

  ! ===========================================================================
  ! Linked list support for building polymorphic arrays
  ! ===========================================================================

  ! Node list element for building collections during parsing
  type :: node_list_element_t
    class(ast_node_t), allocatable :: node
    type(node_list_element_t), pointer :: next => null()
  end type node_list_element_t

  ! Wrapper type for holding node pointers
  type :: node_ptr_t
    class(ast_node_t), pointer :: ptr => null()
  end type node_ptr_t

  ! Node list for collecting AST nodes
  type :: node_list_t
    type(node_list_element_t), pointer :: head => null()
    type(node_list_element_t), pointer :: tail => null()
    integer :: count = 0
  contains
    procedure :: append => node_list_append
    procedure :: to_array => node_list_to_array
    procedure :: clear => node_list_clear
  end type node_list_t

contains

  ! Destructor for base node
  subroutine ast_node_destroy(self)
    class(ast_node_t), intent(inout) :: self
    ! Base implementation - derived types will override
    self%line_number = 0
    self%column = 0
  end subroutine ast_node_destroy

  ! Helper to create a token
  function make_token(token_type, value, line, col) result(token)
    integer, intent(in) :: token_type
    character(*), intent(in) :: value
    integer, intent(in) :: line, col
    type(token_t) :: token

    token%type = token_type
    token%value = value
    token%line_number = line
    token%column = col
  end function make_token

  ! Helper to check if token is a keyword
  logical function is_keyword(word)
    character(*), intent(in) :: word

    select case(word)
    case('if', 'then', 'else', 'elif', 'fi', &
         'for', 'in', 'do', 'done', &
         'while', 'until', 'case', 'esac', &
         'function', 'break', 'continue', 'return')
      is_keyword = .true.
    case default
      is_keyword = .false.
    end select
  end function is_keyword

  ! Get token type for a keyword
  function keyword_token_type(word) result(token_type)
    character(*), intent(in) :: word
    integer :: token_type

    select case(word)
    case('if');       token_type = TOKEN_IF
    case('then');     token_type = TOKEN_THEN
    case('else');     token_type = TOKEN_ELSE
    case('elif');     token_type = TOKEN_ELIF
    case('fi');       token_type = TOKEN_FI
    case('for');      token_type = TOKEN_FOR
    case('in');       token_type = TOKEN_IN
    case('do');       token_type = TOKEN_DO
    case('done');     token_type = TOKEN_DONE
    case('while');    token_type = TOKEN_WHILE
    case('until');    token_type = TOKEN_UNTIL
    case('case');     token_type = TOKEN_CASE
    case('esac');     token_type = TOKEN_ESAC
    case('function'); token_type = TOKEN_FUNCTION
    case('break');    token_type = TOKEN_BREAK
    case('continue'); token_type = TOKEN_CONTINUE
    case('return');   token_type = TOKEN_RETURN
    case default;     token_type = TOKEN_WORD
    end select
  end function keyword_token_type

  ! ===========================================================================
  ! Linked list methods for node collection
  ! ===========================================================================

  ! Append a node to the list
  subroutine node_list_append(self, node)
    class(node_list_t), intent(inout) :: self
    class(ast_node_t), intent(in) :: node
    type(node_list_element_t), pointer :: new_element

    allocate(new_element)
    allocate(new_element%node, source=node)
    new_element%next => null()

    if (.not. associated(self%head)) then
      self%head => new_element
      self%tail => new_element
    else
      self%tail%next => new_element
      self%tail => new_element
    end if

    self%count = self%count + 1
  end subroutine node_list_append

  ! Convert list to array - basic working version
  subroutine node_list_to_array(self, array)
    class(node_list_t), intent(in) :: self
    class(ast_node_t), allocatable, intent(out) :: array(:)
    type(node_list_element_t), pointer :: current
    integer :: i

    if (self%count > 0) then
      ! Simple allocation - all elements as base type for now
      allocate(array(self%count))

      ! Copy basic node data
      current => self%head
      do i = 1, self%count
        if (.not. associated(current)) exit

        ! Copy base fields
        array(i)%node_type = current%node%node_type
        array(i)%line_number = current%node%line_number
        array(i)%column = current%node%column

        ! Store type-specific data in derived fields when possible
        select type(node => current%node)
        type is (word_node_t)
          ! For words, we'd need the derived type allocated
          ! For now, just preserve the node type
        type is (for_node_t)
          ! For loops, we'd need derived type
          ! For now, just preserve the node type
        end select

        current => current%next
      end do
    end if
  end subroutine node_list_to_array



  ! Clear the list
  subroutine node_list_clear(self)
    class(node_list_t), intent(inout) :: self
    type(node_list_element_t), pointer :: current, next

    current => self%head
    do while (associated(current))
      next => current%next
      if (allocated(current%node)) deallocate(current%node)
      deallocate(current)
      current => next
    end do

    self%head => null()
    self%tail => null()
    self%count = 0
  end subroutine node_list_clear

end module ast_types