! =====================================
! Command Tree Module - Abstract Syntax Tree for Shell Commands
! =====================================
! Defines command tree structures for grammar-aware parser
! Part of the parser rewrite project
!
! Status: PHASE 2 - Full AST implementation
! Author: Parser Rewrite Team
! Created: 2025-11-05

module command_tree
  use iso_fortran_env
  use shell_types
  implicit none
  private

  ! Public types
  public :: command_node_t
  public :: command_node_ptr_t
  public :: simple_command_data_t
  public :: pipeline_data_t
  public :: list_data_t
  public :: if_data_t
  public :: while_data_t
  public :: for_data_t
  public :: case_data_t
  public :: case_item_t
  public :: function_def_data_t

  ! Public functions
  public :: create_simple_command
  public :: create_pipeline
  public :: create_list
  public :: create_if_statement
  public :: create_while_loop
  public :: create_for_loop
  public :: create_case_statement
  public :: create_subshell
  public :: create_brace_group
  public :: create_function_def
  public :: destroy_command_node
  public :: print_command_tree

  ! Public constants
  public :: LIST_SEP_SEQUENTIAL, LIST_SEP_AND, LIST_SEP_OR, LIST_SEP_BACKGROUND

  ! Node type constants (these are already in shell_types, but we alias them here)
  integer, parameter :: NODE_SIMPLE = CMD_SIMPLE
  integer, parameter :: NODE_PIPELINE = CMD_PIPELINE
  integer, parameter :: NODE_LIST = CMD_LIST
  integer, parameter :: NODE_IF = CMD_IF_STATEMENT
  integer, parameter :: NODE_WHILE = CMD_WHILE_LOOP
  integer, parameter :: NODE_UNTIL = CMD_UNTIL_LOOP
  integer, parameter :: NODE_FOR = CMD_FOR_LOOP
  integer, parameter :: NODE_CASE = CMD_CASE_STATEMENT
  integer, parameter :: NODE_SUBSHELL = CMD_SUBSHELL
  integer, parameter :: NODE_BRACE_GROUP = CMD_BRACE_GROUP
  integer, parameter :: NODE_FUNCTION_DEF = CMD_FUNCTION_DEF

  ! List separator types
  integer, parameter :: LIST_SEP_SEQUENTIAL = 1    ! ;
  integer, parameter :: LIST_SEP_AND = 2           ! &&
  integer, parameter :: LIST_SEP_OR = 3            ! ||
  integer, parameter :: LIST_SEP_BACKGROUND = 4    ! &

  ! Pointer wrapper for arrays of command nodes
  type :: command_node_ptr_t
    type(command_node_t), pointer :: ptr => null()
  end type command_node_ptr_t

  ! =====================================
  ! Simple Command Data
  ! =====================================
  type :: simple_command_data_t
    character(len=MAX_TOKEN_LEN), allocatable :: words(:)     ! Command words
    logical, allocatable :: word_was_quoted(:)                ! Track quoted tokens for old executor
    logical, allocatable :: word_was_escaped(:)               ! Track escaped tokens (prevent glob expansion)
    integer, allocatable :: word_quote_type(:)                ! Track quote type (QUOTE_* constant)
    integer :: num_words = 0
    type(redirection_t), allocatable :: redirects(:)          ! Redirections
    integer :: num_redirects = 0
    character(len=MAX_TOKEN_LEN), allocatable :: assignments(:) ! VAR=value
    integer :: num_assignments = 0
    ! Heredoc support (delimiter only, content handled at execution)
    character(len=MAX_TOKEN_LEN) :: heredoc_delimiter = ''    ! Delimiter word (EOF)
    logical :: heredoc_quoted = .false.                       ! Was delimiter quoted? (suppress expansion)
  end type simple_command_data_t

  ! =====================================
  ! Pipeline Data
  ! =====================================
  type :: pipeline_data_t
    type(command_node_t), pointer :: commands(:) => null()    ! Pipeline commands
    integer :: num_commands = 0
    logical :: negate = .false.                               ! ! pipeline
  end type pipeline_data_t

  ! =====================================
  ! List Data (command sequences)
  ! =====================================
  type :: list_data_t
    type(command_node_t), pointer :: left => null()           ! Left command
    type(command_node_t), pointer :: right => null()          ! Right command
    integer :: separator = LIST_SEP_SEQUENTIAL                ! && || ; &
  end type list_data_t

  ! =====================================
  ! If Statement Data
  ! =====================================
  type :: if_data_t
    type(command_node_t), pointer :: condition => null()      ! if condition
    type(command_node_t), pointer :: then_part => null()      ! then commands
    type(command_node_t), pointer :: elif_parts(:) => null()  ! elif branches (pairs of condition+then)
    integer :: num_elifs = 0
    type(command_node_t), pointer :: else_part => null()      ! else commands
  end type if_data_t

  ! =====================================
  ! While/Until Loop Data
  ! =====================================
  type :: while_data_t
    type(command_node_t), pointer :: condition => null()      ! Loop condition
    type(command_node_t), pointer :: body => null()           ! Loop body
    logical :: is_until = .false.                             ! True for until loops
  end type while_data_t

  ! =====================================
  ! For Loop Data
  ! =====================================
  type :: for_data_t
    character(len=MAX_TOKEN_LEN) :: variable                  ! Loop variable
    character(len=MAX_TOKEN_LEN), allocatable :: words(:)     ! for x in word1 word2 ...
    integer :: num_words = 0
    type(command_node_t), pointer :: body => null()           ! Loop body
  end type for_data_t

  ! =====================================
  ! Case Statement Item
  ! =====================================
  type :: case_item_t
    character(len=MAX_TOKEN_LEN), allocatable :: patterns(:)  ! Case patterns
    integer :: num_patterns = 0
    type(command_node_t), pointer :: commands => null()       ! Commands for this case
  end type case_item_t

  ! =====================================
  ! Case Statement Data
  ! =====================================
  type :: case_data_t
    character(len=MAX_TOKEN_LEN) :: word                      ! case $word in
    type(case_item_t), allocatable :: items(:)                ! Case items
    integer :: num_items = 0
  end type case_data_t

  ! =====================================
  ! Function Definition Data
  ! =====================================
  type :: function_def_data_t
    character(len=MAX_TOKEN_LEN) :: name                      ! Function name
    type(command_node_t), pointer :: body => null()           ! Function body
  end type function_def_data_t

  ! =====================================
  ! Main Command Node (Union-like structure)
  ! =====================================
  type :: command_node_t
    integer :: node_type = 0                                  ! NODE_* constant
    integer :: line = 0                                       ! Line number for errors
    integer :: column = 0                                     ! Column for errors

    ! Type-specific data (only one will be used based on node_type)
    type(simple_command_data_t), pointer :: simple_cmd => null()
    type(pipeline_data_t), pointer :: pipeline => null()
    type(list_data_t), pointer :: list => null()
    type(if_data_t), pointer :: if_stmt => null()
    type(while_data_t), pointer :: while_loop => null()
    type(for_data_t), pointer :: for_loop => null()
    type(case_data_t), pointer :: case_stmt => null()
    type(function_def_data_t), pointer :: function_def => null()
    type(command_node_t), pointer :: subshell => null()       ! For subshells/groups

    ! Redirections (can apply to any command type, not just simple commands)
    type(redirection_t), allocatable :: redirects(:)
    integer :: num_redirects = 0
  end type command_node_t

contains

  ! =====================================
  ! Constructor Functions
  ! =====================================

  function create_simple_command(words, num_words) result(node)
    character(len=*), intent(in) :: words(:)
    integer, intent(in) :: num_words
    type(command_node_t), pointer :: node
    integer :: i

    allocate(node)
    node%node_type = NODE_SIMPLE
    allocate(node%simple_cmd)
    allocate(node%simple_cmd%words(num_words))
    node%simple_cmd%num_words = num_words
    do i = 1, num_words
      node%simple_cmd%words(i) = words(i)
    end do
  end function create_simple_command

  function create_pipeline(commands, num_commands, negate) result(node)
    type(command_node_t), pointer, intent(in) :: commands(:)
    integer, intent(in) :: num_commands
    logical, intent(in) :: negate
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_PIPELINE
    allocate(node%pipeline)
    ! Take ownership of the commands array
    node%pipeline%commands => commands
    node%pipeline%num_commands = num_commands
    node%pipeline%negate = negate
  end function create_pipeline

  function create_list(left, right, separator) result(node)
    type(command_node_t), pointer, intent(in) :: left, right
    integer, intent(in) :: separator
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_LIST
    allocate(node%list)
    node%list%left => left
    node%list%right => right
    node%list%separator = separator
  end function create_list

  function create_if_statement(condition, then_part, else_part) result(node)
    type(command_node_t), pointer, intent(in) :: condition, then_part
    type(command_node_t), pointer, intent(in), optional :: else_part
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_IF
    allocate(node%if_stmt)
    node%if_stmt%condition => condition
    node%if_stmt%then_part => then_part
    if (present(else_part)) then
      node%if_stmt%else_part => else_part
    end if
  end function create_if_statement

  function create_while_loop(condition, body, is_until) result(node)
    type(command_node_t), pointer, intent(in) :: condition, body
    logical, intent(in) :: is_until
    type(command_node_t), pointer :: node

    allocate(node)
    if (is_until) then
      node%node_type = NODE_UNTIL
    else
      node%node_type = NODE_WHILE
    end if
    allocate(node%while_loop)
    node%while_loop%condition => condition
    node%while_loop%body => body
    node%while_loop%is_until = is_until
  end function create_while_loop

  function create_for_loop(variable, words, num_words, body) result(node)
    character(len=*), intent(in) :: variable
    character(len=*), intent(in) :: words(:)
    integer, intent(in) :: num_words
    type(command_node_t), pointer, intent(in) :: body
    type(command_node_t), pointer :: node
    integer :: i

    allocate(node)
    node%node_type = NODE_FOR
    allocate(node%for_loop)
    node%for_loop%variable = variable
    allocate(node%for_loop%words(num_words))
    node%for_loop%num_words = num_words
    do i = 1, num_words
      node%for_loop%words(i) = words(i)
    end do
    node%for_loop%body => body
  end function create_for_loop

  function create_case_statement(word, items, num_items) result(node)
    character(len=*), intent(in) :: word
    type(case_item_t), intent(in) :: items(:)
    integer, intent(in) :: num_items
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_CASE
    allocate(node%case_stmt)
    node%case_stmt%word = word
    allocate(node%case_stmt%items(num_items))
    node%case_stmt%items = items
    node%case_stmt%num_items = num_items
  end function create_case_statement

  function create_subshell(commands) result(node)
    type(command_node_t), pointer, intent(in) :: commands
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_SUBSHELL
    node%subshell => commands
  end function create_subshell

  function create_brace_group(commands) result(node)
    type(command_node_t), pointer, intent(in) :: commands
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_BRACE_GROUP
    node%subshell => commands  ! Reuse subshell pointer for brace groups
  end function create_brace_group

  function create_function_def(name, body) result(node)
    character(len=*), intent(in) :: name
    type(command_node_t), pointer, intent(in) :: body
    type(command_node_t), pointer :: node

    allocate(node)
    node%node_type = NODE_FUNCTION_DEF
    allocate(node%function_def)
    node%function_def%name = name
    node%function_def%body => body
  end function create_function_def

  ! =====================================
  ! Destructor Function
  ! =====================================

  recursive subroutine destroy_command_node(node)
    type(command_node_t), pointer, intent(inout) :: node
    integer :: i
    type(command_node_t), pointer :: temp_cmd

    if (.not. associated(node)) return

    select case(node%node_type)
    case(NODE_SIMPLE)
      if (associated(node%simple_cmd)) then
        if (allocated(node%simple_cmd%words)) deallocate(node%simple_cmd%words)
        if (allocated(node%simple_cmd%redirects)) deallocate(node%simple_cmd%redirects)
        if (allocated(node%simple_cmd%assignments)) deallocate(node%simple_cmd%assignments)
        deallocate(node%simple_cmd)
      end if

    case(NODE_PIPELINE)
      if (associated(node%pipeline)) then
        if (associated(node%pipeline%commands)) then
          ! Just deallocate the array, not the individual nodes
          ! (nodes are allocated separately and may be shared/reused)
          deallocate(node%pipeline%commands)
        end if
        deallocate(node%pipeline)
      end if

    case(NODE_LIST)
      if (associated(node%list)) then
        call destroy_command_node(node%list%left)
        call destroy_command_node(node%list%right)
        deallocate(node%list)
      end if

    case(NODE_IF)
      if (associated(node%if_stmt)) then
        call destroy_command_node(node%if_stmt%condition)
        call destroy_command_node(node%if_stmt%then_part)
        if (associated(node%if_stmt%else_part)) call destroy_command_node(node%if_stmt%else_part)
        deallocate(node%if_stmt)
      end if

    case(NODE_WHILE, NODE_UNTIL)
      if (associated(node%while_loop)) then
        call destroy_command_node(node%while_loop%condition)
        call destroy_command_node(node%while_loop%body)
        deallocate(node%while_loop)
      end if

    case(NODE_FOR)
      if (associated(node%for_loop)) then
        if (allocated(node%for_loop%words)) deallocate(node%for_loop%words)
        call destroy_command_node(node%for_loop%body)
        deallocate(node%for_loop)
      end if

    case(NODE_CASE)
      if (associated(node%case_stmt)) then
        if (allocated(node%case_stmt%items)) deallocate(node%case_stmt%items)
        deallocate(node%case_stmt)
      end if

    case(NODE_SUBSHELL, NODE_BRACE_GROUP)
      call destroy_command_node(node%subshell)

    case(NODE_FUNCTION_DEF)
      if (associated(node%function_def)) then
        call destroy_command_node(node%function_def%body)
        deallocate(node%function_def)
      end if
    end select

    ! Clean up node-level redirections
    if (allocated(node%redirects)) deallocate(node%redirects)

    deallocate(node)
    nullify(node)
  end subroutine destroy_command_node

  ! =====================================
  ! Debug Print Function
  ! =====================================

  recursive subroutine print_command_tree(node, indent)
    type(command_node_t), pointer, intent(in) :: node
    integer, intent(in), optional :: indent
    integer :: ind, i
    character(len=100) :: indent_str

    if (.not. associated(node)) return

    ind = 0
    if (present(indent)) ind = indent
    indent_str = repeat('  ', ind)

    select case(node%node_type)
    case(NODE_SIMPLE)
      write(*, '(A,A)') trim(indent_str), 'SIMPLE_COMMAND:'
      if (associated(node%simple_cmd)) then
        do i = 1, node%simple_cmd%num_words
          write(*, '(A,A,A)') trim(indent_str), '  ', trim(node%simple_cmd%words(i))
        end do
      end if

    case(NODE_PIPELINE)
      write(*, '(A,A)') trim(indent_str), 'PIPELINE:'
      if (associated(node%pipeline)) then
        if (associated(node%pipeline%commands)) then
          do i = 1, node%pipeline%num_commands
            call print_command_tree(node%pipeline%commands(i), ind + 1)
          end do
        end if
      end if

    case(NODE_LIST)
      write(*, '(A,A)') trim(indent_str), 'LIST:'
      if (associated(node%list)) then
        call print_command_tree(node%list%left, ind + 1)
        call print_command_tree(node%list%right, ind + 1)
      end if

    case(NODE_IF)
      write(*, '(A,A)') trim(indent_str), 'IF:'
      if (associated(node%if_stmt)) then
        write(*, '(A,A)') trim(indent_str), '  condition:'
        call print_command_tree(node%if_stmt%condition, ind + 2)
        write(*, '(A,A)') trim(indent_str), '  then:'
        call print_command_tree(node%if_stmt%then_part, ind + 2)
        if (associated(node%if_stmt%else_part)) then
          write(*, '(A,A)') trim(indent_str), '  else:'
          call print_command_tree(node%if_stmt%else_part, ind + 2)
        end if
      end if

    case(NODE_WHILE)
      write(*, '(A,A)') trim(indent_str), 'WHILE:'
      if (associated(node%while_loop)) then
        call print_command_tree(node%while_loop%condition, ind + 1)
        call print_command_tree(node%while_loop%body, ind + 1)
      end if

    case(NODE_FOR)
      write(*, '(A,A,A)') trim(indent_str), 'FOR: ', trim(node%for_loop%variable)
      if (associated(node%for_loop)) then
        call print_command_tree(node%for_loop%body, ind + 1)
      end if

    case default
      write(*, '(A,A,I0)') trim(indent_str), 'UNKNOWN_NODE_TYPE: ', node%node_type
    end select
  end subroutine print_command_tree

end module command_tree
