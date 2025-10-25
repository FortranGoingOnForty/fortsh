! ==============================================================================
! Module: ast_types_enhanced
! Purpose: Enhanced AST types with proper polymorphic support using pointers
! ==============================================================================
module ast_types_enhanced
  use iso_fortran_env, only: int32, int64
  implicit none

  ! Token types (same as before)
  integer, parameter :: TOKEN_EOF = 0
  integer, parameter :: TOKEN_WORD = 1
  integer, parameter :: TOKEN_NUMBER = 2
  integer, parameter :: TOKEN_STRING = 3
  integer, parameter :: TOKEN_VARIABLE = 4
  integer, parameter :: TOKEN_SEMICOLON = 5
  integer, parameter :: TOKEN_NEWLINE = 6
  integer, parameter :: TOKEN_PIPE = 7
  integer, parameter :: TOKEN_AND = 8
  integer, parameter :: TOKEN_OR = 9
  integer, parameter :: TOKEN_BACKGROUND = 10
  integer, parameter :: TOKEN_REDIRECT_IN = 11
  integer, parameter :: TOKEN_REDIRECT_OUT = 12
  integer, parameter :: TOKEN_REDIRECT_APPEND = 13
  integer, parameter :: TOKEN_REDIRECT_HERE = 14
  integer, parameter :: TOKEN_LPAREN = 15
  integer, parameter :: TOKEN_RPAREN = 16
  integer, parameter :: TOKEN_LBRACE = 17
  integer, parameter :: TOKEN_RBRACE = 18
  integer, parameter :: TOKEN_LBRACKET = 19
  integer, parameter :: TOKEN_RBRACKET = 20
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
  integer, parameter :: TOKEN_COMMAND_SUBST_START = 38
  integer, parameter :: TOKEN_ARITH_START = 39
  integer, parameter :: TOKEN_ARITH_END = 40
  integer, parameter :: TOKEN_REDIRECT_HERE_STRING = 41
  integer, parameter :: TOKEN_LBRACKET_DOUBLE = 42
  integer, parameter :: TOKEN_RBRACKET_DOUBLE = 43
  integer, parameter :: TOKEN_PROC_SUBST_IN = 44   ! <(...)
  integer, parameter :: TOKEN_PROC_SUBST_OUT = 45  ! >(...)
  integer, parameter :: TOKEN_REDIRECT_DUP_OUT = 46  ! >&
  integer, parameter :: TOKEN_REDIRECT_DUP_IN = 47   ! <&

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
  integer, parameter :: NODE_GROUP = 123
  integer, parameter :: NODE_BREAK = 114
  integer, parameter :: NODE_CONTINUE = 115
  integer, parameter :: NODE_RETURN = 116
  integer, parameter :: NODE_WORD = 117
  integer, parameter :: NODE_VARIABLE = 118
  integer, parameter :: NODE_ASSIGNMENT = 119
  integer, parameter :: NODE_REDIRECTION = 120
  integer, parameter :: NODE_COMMAND_SUBST = 121
  integer, parameter :: NODE_ARITHMETIC = 122
  integer, parameter :: NODE_COND_EXPR = 124
  integer, parameter :: NODE_PROC_SUBST = 125  ! Process substitution

  ! Variable expansion modifier types
  integer, parameter :: MOD_NONE = 0              ! No modifier
  integer, parameter :: MOD_USE_DEFAULT = 1       ! ${var:-default}
  integer, parameter :: MOD_ASSIGN_DEFAULT = 2    ! ${var:=default}
  integer, parameter :: MOD_ERROR_IF_UNSET = 3    ! ${var:?error}
  integer, parameter :: MOD_USE_ALTERNATE = 4     ! ${var:+alternate}
  integer, parameter :: MOD_STRING_LENGTH = 5     ! ${#var}
  integer, parameter :: MOD_SUBSTRING = 6         ! ${var:offset:length}
  integer, parameter :: MOD_REMOVE_PREFIX_MIN = 7 ! ${var#pattern}
  integer, parameter :: MOD_REMOVE_PREFIX_MAX = 8 ! ${var##pattern}
  integer, parameter :: MOD_REMOVE_SUFFIX_MIN = 9 ! ${var%pattern}
  integer, parameter :: MOD_REMOVE_SUFFIX_MAX = 10! ${var%%pattern}
  integer, parameter :: MOD_REPLACE_FIRST = 11    ! ${var/pattern/replacement}
  integer, parameter :: MOD_REPLACE_ALL = 12      ! ${var//pattern/replacement}
  integer, parameter :: MOD_REPLACE_PREFIX = 13   ! ${var/#pattern/replacement}
  integer, parameter :: MOD_REPLACE_SUFFIX = 14   ! ${var/%pattern/replacement}
  integer, parameter :: MOD_UPPERCASE_FIRST = 15  ! ${var^}
  integer, parameter :: MOD_UPPERCASE_ALL = 16    ! ${var^^}
  integer, parameter :: MOD_LOWERCASE_FIRST = 17  ! ${var,}
  integer, parameter :: MOD_LOWERCASE_ALL = 18    ! ${var,,}

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
    procedure :: clone => ast_node_clone
  end type ast_node_t

  ! Node pointer wrapper for arrays
  type :: ast_node_ptr_t
    class(ast_node_t), pointer :: ptr => null()
  end type ast_node_ptr_t

  ! Script node - uses pointer array
  type, extends(ast_node_t) :: script_node_t
    type(ast_node_ptr_t), allocatable :: statements(:)
    integer :: num_statements = 0
  contains
    procedure :: clone => script_node_clone
  end type script_node_t

  ! Command node - uses pointer arrays
  type, extends(ast_node_t) :: command_node_t
    type(ast_node_ptr_t), allocatable :: words(:)
    type(ast_node_ptr_t), allocatable :: redirections(:)
    type(ast_node_ptr_t), allocatable :: assignments(:)
    integer :: num_words = 0
    integer :: num_redirections = 0
    integer :: num_assignments = 0
    logical :: background = .false.
  contains
    procedure :: clone => command_node_clone
  end type command_node_t

  ! Pipeline node - chains multiple commands
  type, extends(ast_node_t) :: pipeline_node_t
    type(ast_node_ptr_t), allocatable :: commands(:)
    integer :: num_commands = 0
    logical :: background = .false.
  contains
    procedure :: clone => pipeline_node_clone
  end type pipeline_node_t

  ! And-list node - executes second command only if first succeeds (&&)
  type, extends(ast_node_t) :: and_list_node_t
    type(ast_node_ptr_t) :: left
    type(ast_node_ptr_t) :: right
  contains
    procedure :: clone => and_list_node_clone
  end type and_list_node_t

  ! Or-list node - executes second command only if first fails (||)
  type, extends(ast_node_t) :: or_list_node_t
    type(ast_node_ptr_t) :: left
    type(ast_node_ptr_t) :: right
  contains
    procedure :: clone => or_list_node_clone
  end type or_list_node_t

  ! Word node
  type, extends(ast_node_t) :: word_node_t
    character(:), allocatable :: text
    logical :: needs_expansion = .false.
  contains
    procedure :: clone => word_node_clone
  end type word_node_t

  ! Variable reference node
  type, extends(ast_node_t) :: variable_node_t
    character(:), allocatable :: name
    character(:), allocatable :: modifier
    integer :: modifier_type = 0
    character(:), allocatable :: index_expr  ! For array indexing: [0], [@], [*], or [$i]
    logical :: is_array_ref = .false.
    logical :: get_indices = .false.  ! For ${!array[@]} - get array indices
  contains
    procedure :: clone => variable_node_clone
  end type variable_node_t

  ! Redirection node
  type, extends(ast_node_t) :: redirection_node_t
    integer :: redirect_type = 0  ! 1=input(<), 2=output(>), 3=append(>>), 4=heredoc(<<), 5=herestring(<<<), 6=dup_out(>&), 7=dup_in(<&)
    integer :: fd = -1  ! File descriptor (-1 means default: 0 for <, 1 for >, >>)
    class(ast_node_t), allocatable :: target  ! Target file (word_node_t)
    integer :: target_fd = -1  ! Target FD for duplication (literal number like >&4)
    character(:), allocatable :: target_fd_expr  ! Target FD expression for duplication (variable like >&${COPROC[1]})
    character(:), allocatable :: heredoc_delimiter  ! Delimiter for here documents
    character(:), allocatable :: heredoc_content  ! Content for here documents
    logical :: heredoc_strip_tabs = .false.  ! True for <<- (strip leading tabs)
  contains
    procedure :: clone => redirection_node_clone
  end type redirection_node_t

  ! Command substitution node - for $(...) or `...`
  type, extends(ast_node_t) :: command_subst_node_t
    type(ast_node_ptr_t) :: command  ! The command to execute
    logical :: is_backtick = .false.  ! True for `...`, false for $(...)
  contains
    procedure :: clone => command_subst_node_clone
  end type command_subst_node_t

  ! Arithmetic expansion node - for $((...))
  type, extends(ast_node_t) :: arithmetic_node_t
    character(:), allocatable :: expression  ! The arithmetic expression
  contains
    procedure :: clone => arithmetic_node_clone
  end type arithmetic_node_t

  ! For loop node
  type, extends(ast_node_t) :: for_node_t
    character(:), allocatable :: variable
    type(ast_node_ptr_t), allocatable :: word_list(:)
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_words = 0
    integer :: num_body = 0
  contains
    procedure :: clone => for_node_clone
  end type for_node_t

  ! Arithmetic for loop node - for ((init; cond; incr))
  type, extends(ast_node_t) :: for_arith_node_t
    character(:), allocatable :: init_expr     ! Initialization expression
    character(:), allocatable :: cond_expr     ! Condition expression
    character(:), allocatable :: incr_expr     ! Increment expression
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_body = 0
  contains
    procedure :: clone => for_arith_node_clone
  end type for_arith_node_t

  ! While loop node
  type, extends(ast_node_t) :: while_node_t
    type(ast_node_ptr_t) :: condition
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_body = 0
  contains
    procedure :: clone => while_node_clone
  end type while_node_t

  ! If statement node
  type, extends(ast_node_t) :: if_node_t
    type(ast_node_ptr_t) :: condition
    type(ast_node_ptr_t), allocatable :: then_branch(:)
    type(ast_node_ptr_t), allocatable :: else_branch(:)
    integer :: num_then = 0
    integer :: num_else = 0
  contains
    procedure :: clone => if_node_clone
  end type if_node_t

  ! Case item - represents one case pattern and its commands
  type :: case_item_t
    character(:), allocatable, dimension(:) :: patterns
    integer :: num_patterns = 0
    type(ast_node_ptr_t), allocatable :: commands(:)
    integer :: num_commands = 0
  end type case_item_t

  ! Case statement node
  type, extends(ast_node_t) :: case_node_t
    type(ast_node_ptr_t) :: expr  ! Expression to match
    type(case_item_t), allocatable :: items(:)
    integer :: num_items = 0
  contains
    procedure :: clone => case_node_clone
  end type case_node_t

  ! Break statement node
  type, extends(ast_node_t) :: break_node_t
    integer :: levels = 1
  contains
    procedure :: clone => break_node_clone
  end type break_node_t

  ! Continue statement node
  type, extends(ast_node_t) :: continue_node_t
    integer :: levels = 1
  contains
    procedure :: clone => continue_node_clone
  end type continue_node_t

  ! Function definition node
  type, extends(ast_node_t) :: function_node_t
    character(:), allocatable :: name
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_body = 0
  contains
    procedure :: clone => function_node_clone
  end type function_node_t

  ! Subshell node - executes commands in a separate subshell ()
  type, extends(ast_node_t) :: subshell_node_t
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_body = 0
  contains
    procedure :: clone => subshell_node_clone
  end type subshell_node_t

  ! Group node - executes commands in current shell { }
  type, extends(ast_node_t) :: group_node_t
    type(ast_node_ptr_t), allocatable :: body(:)
    integer :: num_body = 0
  contains
    procedure :: clone => group_node_clone
  end type group_node_t

  ! Conditional expression node - for [[ ]] expressions
  type, extends(ast_node_t) :: cond_expr_node_t
    character(:), allocatable :: expression  ! The conditional expression
  contains
    procedure :: clone => cond_expr_node_clone
  end type cond_expr_node_t

  ! Process substitution node - for <(...) and >(...)
  type, extends(ast_node_t) :: proc_subst_node_t
    type(ast_node_ptr_t) :: command  ! The command to execute
    logical :: is_input = .true.  ! True for <(...), false for >(...)
  contains
    procedure :: clone => proc_subst_node_clone
  end type proc_subst_node_t

  ! Linked list for building collections (same as before)
  type :: node_list_element_t
    class(ast_node_t), allocatable :: node
    type(node_list_element_t), pointer :: next => null()
  end type node_list_element_t

  ! Enhanced node list that converts to pointer array
  type :: node_list_t
    type(node_list_element_t), pointer :: head => null()
    type(node_list_element_t), pointer :: tail => null()
    integer :: count = 0
  contains
    procedure :: append => node_list_append
    procedure :: to_ptr_array => node_list_to_ptr_array
    procedure :: clear => node_list_clear
  end type node_list_t

contains

  ! Clone methods for each node type
  function ast_node_clone(self) result(clone)
    class(ast_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone

    allocate(ast_node_t :: clone)
    ast_node_t :: clone = 0
    clone%node_type = self%node_type
    clone%line_number = self%line_number
    clone%column = self%column
  end function ast_node_clone

  function script_node_clone(self) result(clone)
    class(script_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(script_node_t), pointer :: typed_clone
    integer :: i

    allocate(script_node_t :: typed_clone)
    script_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_statements = self%num_statements

    if (allocated(self%statements)) then
      allocate(typed_clone%statements(size(self%statements)))
      do i = 1, size(self%statements)
        if (associated(self%statements(i)%ptr)) then
          typed_clone%statements(i)%ptr => self%statements(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function script_node_clone

  function command_node_clone(self) result(clone)
    class(command_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(command_node_t), pointer :: typed_clone
    integer :: i

    allocate(command_node_t :: typed_clone)
    command_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%background = self%background
    typed_clone%num_words = self%num_words
    typed_clone%num_redirections = self%num_redirections
    typed_clone%num_assignments = self%num_assignments

    if (allocated(self%words)) then
      allocate(typed_clone%words(size(self%words)))
      do i = 1, size(self%words)
        if (associated(self%words(i)%ptr)) then
          typed_clone%words(i)%ptr => self%words(i)%ptr%clone()
        end if
      end do
    end if

    if (allocated(self%redirections)) then
      allocate(typed_clone%redirections(size(self%redirections)))
      do i = 1, size(self%redirections)
        if (associated(self%redirections(i)%ptr)) then
          typed_clone%redirections(i)%ptr => self%redirections(i)%ptr%clone()
        end if
      end do
    end if

    if (allocated(self%assignments)) then
      allocate(typed_clone%assignments(size(self%assignments)))
      do i = 1, size(self%assignments)
        if (associated(self%assignments(i)%ptr)) then
          typed_clone%assignments(i)%ptr => self%assignments(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function command_node_clone

  function pipeline_node_clone(self) result(clone)
    class(pipeline_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(pipeline_node_t), pointer :: typed_clone
    integer :: i

    allocate(pipeline_node_t :: typed_clone)
    pipeline_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%background = self%background
    typed_clone%num_commands = self%num_commands

    if (allocated(self%commands)) then
      allocate(typed_clone%commands(size(self%commands)))
      do i = 1, size(self%commands)
        if (associated(self%commands(i)%ptr)) then
          typed_clone%commands(i)%ptr => self%commands(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function pipeline_node_clone

  function and_list_node_clone(self) result(clone)
    class(and_list_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(and_list_node_t), pointer :: typed_clone

    allocate(and_list_node_t :: typed_clone)
    and_list_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column

    if (associated(self%left%ptr)) then
      typed_clone%left%ptr => self%left%ptr%clone()
    end if

    if (associated(self%right%ptr)) then
      typed_clone%right%ptr => self%right%ptr%clone()
    end if

    clone => typed_clone
  end function and_list_node_clone

  function or_list_node_clone(self) result(clone)
    class(or_list_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(or_list_node_t), pointer :: typed_clone

    allocate(or_list_node_t :: typed_clone)
    or_list_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column

    if (associated(self%left%ptr)) then
      typed_clone%left%ptr => self%left%ptr%clone()
    end if

    if (associated(self%right%ptr)) then
      typed_clone%right%ptr => self%right%ptr%clone()
    end if

    clone => typed_clone
  end function or_list_node_clone

  function word_node_clone(self) result(clone)
    class(word_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(word_node_t), pointer :: typed_clone

    allocate(word_node_t :: typed_clone)
    word_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%text = self%text
    typed_clone%needs_expansion = self%needs_expansion

    clone => typed_clone
  end function word_node_clone

  function variable_node_clone(self) result(clone)
    class(variable_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(variable_node_t), pointer :: typed_clone

    allocate(variable_node_t :: typed_clone)
    variable_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%name = self%name
    if (allocated(self%modifier)) typed_clone%modifier = self%modifier
    typed_clone%modifier_type = self%modifier_type
    if (allocated(self%index_expr)) typed_clone%index_expr = self%index_expr
    typed_clone%is_array_ref = self%is_array_ref
    typed_clone%get_indices = self%get_indices

    clone => typed_clone
  end function variable_node_clone

  function redirection_node_clone(self) result(clone)
    class(redirection_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(redirection_node_t), pointer :: typed_clone

    allocate(redirection_node_t :: typed_clone)
    redirection_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%redirect_type = self%redirect_type
    typed_clone%fd = self%fd
    typed_clone%target_fd = self%target_fd
    if (allocated(self%target)) then
      allocate(typed_clone%target, source=self%target)
    end if
    if (allocated(self%target_fd_expr)) then
      typed_clone%target_fd_expr = self%target_fd_expr
    end if
    if (allocated(self%heredoc_delimiter)) then
      typed_clone%heredoc_delimiter = self%heredoc_delimiter
    end if
    if (allocated(self%heredoc_content)) then
      typed_clone%heredoc_content = self%heredoc_content
    end if
    typed_clone%heredoc_strip_tabs = self%heredoc_strip_tabs
    clone => typed_clone
  end function redirection_node_clone

  function command_subst_node_clone(self) result(clone)
    class(command_subst_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(command_subst_node_t), pointer :: typed_clone

    allocate(command_subst_node_t :: typed_clone)
    command_subst_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%is_backtick = self%is_backtick
    if (associated(self%command%ptr)) then
      typed_clone%command%ptr => self%command%ptr%clone()
    end if
    clone => typed_clone
  end function command_subst_node_clone

  function arithmetic_node_clone(self) result(clone)
    class(arithmetic_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(arithmetic_node_t), pointer :: typed_clone

    allocate(arithmetic_node_t :: typed_clone)
    arithmetic_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    if (allocated(self%expression)) then
      typed_clone%expression = self%expression
    end if
    clone => typed_clone
  end function arithmetic_node_clone

  function for_node_clone(self) result(clone)
    class(for_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(for_node_t), pointer :: typed_clone
    integer :: i

    allocate(for_node_t :: typed_clone)
    for_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%variable = self%variable
    typed_clone%num_words = self%num_words
    typed_clone%num_body = self%num_body

    if (allocated(self%word_list)) then
      allocate(typed_clone%word_list(size(self%word_list)))
      do i = 1, size(self%word_list)
        if (associated(self%word_list(i)%ptr)) then
          typed_clone%word_list(i)%ptr => self%word_list(i)%ptr%clone()
        end if
      end do
    end if

    if (allocated(self%body)) then
      allocate(typed_clone%body(size(self%body)))
      do i = 1, size(self%body)
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function for_node_clone

  function for_arith_node_clone(self) result(clone)
    class(for_arith_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(for_arith_node_t), pointer :: typed_clone
    integer :: i

    allocate(for_arith_node_t :: typed_clone)
    for_arith_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_body = self%num_body

    if (allocated(self%init_expr)) typed_clone%init_expr = self%init_expr
    if (allocated(self%cond_expr)) typed_clone%cond_expr = self%cond_expr
    if (allocated(self%incr_expr)) typed_clone%incr_expr = self%incr_expr

    if (allocated(self%body)) then
      allocate(typed_clone%body(self%num_body))
      do i = 1, self%num_body
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function for_arith_node_clone

  function while_node_clone(self) result(clone)
    class(while_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(while_node_t), pointer :: typed_clone
    integer :: i

    allocate(while_node_t :: typed_clone)
    while_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_body = self%num_body

    if (associated(self%condition%ptr)) then
      typed_clone%condition%ptr => self%condition%ptr%clone()
    end if

    if (allocated(self%body)) then
      allocate(typed_clone%body(size(self%body)))
      do i = 1, size(self%body)
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function while_node_clone

  function if_node_clone(self) result(clone)
    class(if_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(if_node_t), pointer :: typed_clone
    integer :: i

    allocate(if_node_t :: typed_clone)
    if_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_then = self%num_then
    typed_clone%num_else = self%num_else

    if (associated(self%condition%ptr)) then
      typed_clone%condition%ptr => self%condition%ptr%clone()
    end if

    if (allocated(self%then_branch)) then
      allocate(typed_clone%then_branch(size(self%then_branch)))
      do i = 1, size(self%then_branch)
        if (associated(self%then_branch(i)%ptr)) then
          typed_clone%then_branch(i)%ptr => self%then_branch(i)%ptr%clone()
        end if
      end do
    end if

    if (allocated(self%else_branch)) then
      allocate(typed_clone%else_branch(size(self%else_branch)))
      do i = 1, size(self%else_branch)
        if (associated(self%else_branch(i)%ptr)) then
          typed_clone%else_branch(i)%ptr => self%else_branch(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function if_node_clone

  function case_node_clone(self) result(clone)
    class(case_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(case_node_t), pointer :: typed_clone
    integer :: i, j

    allocate(case_node_t :: typed_clone)
    case_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_items = self%num_items

    if (associated(self%expr%ptr)) then
      typed_clone%expr%ptr => self%expr%ptr%clone()
    end if

    if (allocated(self%items)) then
      allocate(typed_clone%items(self%num_items))
      do i = 1, self%num_items
        typed_clone%items(i)%num_patterns = self%items(i)%num_patterns
        typed_clone%items(i)%num_commands = self%items(i)%num_commands

        ! Copy patterns
        if (allocated(self%items(i)%patterns)) then
          allocate(character(len=256) :: typed_clone%items(i)%patterns(self%items(i)%num_patterns))
          do j = 1, self%items(i)%num_patterns
            typed_clone%items(i)%patterns(j) = self%items(i)%patterns(j)
          end do
        end if

        ! Copy commands
        if (allocated(self%items(i)%commands)) then
          allocate(typed_clone%items(i)%commands(self%items(i)%num_commands))
          do j = 1, self%items(i)%num_commands
            if (associated(self%items(i)%commands(j)%ptr)) then
              typed_clone%items(i)%commands(j)%ptr => self%items(i)%commands(j)%ptr%clone()
            end if
          end do
        end if
      end do
    end if

    clone => typed_clone
  end function case_node_clone

  function break_node_clone(self) result(clone)
    class(break_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(break_node_t), pointer :: typed_clone

    allocate(break_node_t :: typed_clone)
    break_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%levels = self%levels

    clone => typed_clone
  end function break_node_clone

  function continue_node_clone(self) result(clone)
    class(continue_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(continue_node_t), pointer :: typed_clone

    allocate(continue_node_t :: typed_clone)
    continue_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%levels = self%levels

    clone => typed_clone
  end function continue_node_clone

  function function_node_clone(self) result(clone)
    class(function_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(function_node_t), pointer :: typed_clone
    integer :: i

    allocate(function_node_t :: typed_clone)
    function_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_body = self%num_body

    if (allocated(self%name)) then
      typed_clone%name = self%name
    end if

    if (allocated(self%body)) then
      allocate(typed_clone%body(self%num_body))
      do i = 1, self%num_body
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function function_node_clone

  function subshell_node_clone(self) result(clone)
    class(subshell_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(subshell_node_t), pointer :: typed_clone
    integer :: i

    allocate(subshell_node_t :: typed_clone)
    subshell_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_body = self%num_body

    if (allocated(self%body)) then
      allocate(typed_clone%body(self%num_body))
      do i = 1, self%num_body
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function subshell_node_clone

  function group_node_clone(self) result(clone)
    class(group_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(group_node_t), pointer :: typed_clone
    integer :: i

    allocate(group_node_t :: typed_clone)
    group_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%num_body = self%num_body

    if (allocated(self%body)) then
      allocate(typed_clone%body(self%num_body))
      do i = 1, self%num_body
        if (associated(self%body(i)%ptr)) then
          typed_clone%body(i)%ptr => self%body(i)%ptr%clone()
        end if
      end do
    end if

    clone => typed_clone
  end function group_node_clone

  function cond_expr_node_clone(self) result(clone)
    class(cond_expr_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(cond_expr_node_t), pointer :: typed_clone

    allocate(cond_expr_node_t :: typed_clone)
    cond_expr_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    if (allocated(self%expression)) then
      typed_clone%expression = self%expression
    end if
    clone => typed_clone
  end function cond_expr_node_clone

  function proc_subst_node_clone(self) result(clone)
    class(proc_subst_node_t), intent(in) :: self
    class(ast_node_t), pointer :: clone
    type(proc_subst_node_t), pointer :: typed_clone

    allocate(proc_subst_node_t :: typed_clone)
    proc_subst_node_t :: typed_clone = 0
    typed_clone%node_type = self%node_type
    typed_clone%line_number = self%line_number
    typed_clone%column = self%column
    typed_clone%is_input = self%is_input
    if (associated(self%command%ptr)) then
      typed_clone%command%ptr => self%command%ptr%clone()
    end if
    clone => typed_clone
  end function proc_subst_node_clone

  ! Linked list methods
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

  ! Convert list to pointer array - preserves polymorphic types!
  subroutine node_list_to_ptr_array(self, ptr_array)
    class(node_list_t), intent(in) :: self
    type(ast_node_ptr_t), allocatable, intent(out) :: ptr_array(:)
    type(node_list_element_t), pointer :: current
    integer :: i

    if (self%count > 0) then
      allocate(ptr_array(self%count))

      current => self%head
      do i = 1, self%count
        if (.not. associated(current)) exit

        ! Clone the node to create a persistent copy
        ptr_array(i)%ptr => current%node%clone()

        current => current%next
      end do
    end if
  end subroutine node_list_to_ptr_array

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

  ! Helper functions
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

end module ast_types_enhanced