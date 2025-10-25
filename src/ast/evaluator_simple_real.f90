! ==============================================================================
! Module: evaluator_simple_real
! Purpose: Simplified real evaluator with basic built-ins and system execution
! ==============================================================================
module evaluator_simple_real

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000
  use ast_types_enhanced
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit, input_unit
  use iso_c_binding
  implicit none

  ! Glob type for pattern matching
  type, bind(C) :: glob_t
    integer(c_size_t) :: gl_pathc
    type(c_ptr) :: gl_pathv
    integer(c_size_t) :: gl_offs
  end type glob_t

  ! Password database entry for getpwnam
  type, bind(C) :: passwd_t
    type(c_ptr) :: pw_name
    type(c_ptr) :: pw_passwd
    integer(c_int) :: pw_uid
    integer(c_int) :: pw_gid
    type(c_ptr) :: pw_gecos
    type(c_ptr) :: pw_dir      ! Home directory - what we need
    type(c_ptr) :: pw_shell
  end type passwd_t

  ! POSIX regex types for =~ operator
  type, bind(C) :: regex_t
    ! Opaque regex_t structure - we only need to pass it to C functions
    ! Actual size may vary by system, but allocate enough space
    integer(c_int) :: re_dummy(32)  ! Placeholder - C functions handle it
  end type regex_t

  type, bind(C) :: regmatch_t
    integer(c_int) :: rm_so  ! Start offset
    integer(c_int) :: rm_eo  ! End offset
  end type regmatch_t

  ! Regex compilation flags
  integer(c_int), parameter :: REG_EXTENDED = 1    ! Use extended regular expressions
  integer(c_int), parameter :: REG_ICASE = 2       ! Ignore case
  integer(c_int), parameter :: REG_NOSUB = 4       ! No substring addressing
  integer(c_int), parameter :: REG_NEWLINE = 8     ! Newline is special

  ! Regex execution flags
  integer(c_int), parameter :: REG_NOTBOL = 1      ! Start of string is not beginning of line
  integer(c_int), parameter :: REG_NOTEOL = 2      ! End of string is not end of line

  ! C interface for system call
  interface
    function c_system(command) bind(C, name="system")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: command
      integer(c_int) :: c_system
    end function c_system

    function c_chdir(path) bind(C, name="chdir")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: path
      integer(c_int) :: c_chdir
    end function c_chdir

    function c_getcwd(buf, size) bind(C, name="getcwd")
      use iso_c_binding
      character(kind=c_char), dimension(*) :: buf
      integer(c_size_t), value :: size
      type(c_ptr) :: c_getcwd
    end function c_getcwd

    function c_glob(pattern, flags, errfunc, pglob) bind(C, name="glob")
      use iso_c_binding
      import :: glob_t
      character(kind=c_char), dimension(*), intent(in) :: pattern
      integer(c_int), value :: flags
      type(c_funptr), value :: errfunc
      type(glob_t), intent(inout) :: pglob
      integer(c_int) :: c_glob
    end function c_glob

    subroutine c_globfree(pglob) bind(C, name="globfree")
      use iso_c_binding
      import :: glob_t
      type(glob_t), intent(inout) :: pglob
    end subroutine c_globfree

    function c_open(pathname, flags, mode) bind(C, name="open")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      integer(c_int), value :: flags
      integer(c_int), value :: mode
      integer(c_int) :: c_open
    end function c_open

    function c_close(fd) bind(C, name="close")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_close
    end function c_close

    function c_dup(fd) bind(C, name="dup")
      use iso_c_binding
      integer(c_int), value :: fd
      integer(c_int) :: c_dup
    end function c_dup

    function c_dup2(oldfd, newfd) bind(C, name="dup2")
      use iso_c_binding
      integer(c_int), value :: oldfd
      integer(c_int), value :: newfd
      integer(c_int) :: c_dup2
    end function c_dup2

    function c_write(fd, buf, count) bind(C, name="write")
      use iso_c_binding
      integer(c_int), value :: fd
      character(kind=c_char), dimension(*), intent(in) :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: c_write
    end function c_write

    function c_access(pathname, mode) bind(C, name="access")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      integer(c_int), value :: mode
      integer(c_int) :: c_access
    end function c_access

    function c_stat(pathname, statbuf) bind(C, name="stat")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      type(c_ptr), value :: statbuf
      integer(c_int) :: c_stat
    end function c_stat

    function c_getpwnam(name) bind(C, name="getpwnam")
      use iso_c_binding
      import :: passwd_t
      character(kind=c_char), dimension(*), intent(in) :: name
      type(c_ptr) :: c_getpwnam  ! Returns pointer to passwd struct
    end function c_getpwnam

    ! POSIX regex support for =~ operator
    function c_regcomp(preg, pattern, cflags) bind(C, name="regcomp")
      use iso_c_binding
      import :: regex_t
      type(regex_t), intent(inout) :: preg
      character(kind=c_char), dimension(*), intent(in) :: pattern
      integer(c_int), value :: cflags
      integer(c_int) :: c_regcomp  ! Returns 0 on success
    end function c_regcomp

    function c_regexec(preg, string, nmatch, pmatch, eflags) bind(C, name="regexec")
      use iso_c_binding
      import :: regex_t, regmatch_t
      type(regex_t), intent(in) :: preg
      character(kind=c_char), dimension(*), intent(in) :: string
      integer(c_size_t), value :: nmatch
      type(regmatch_t), dimension(*) :: pmatch
      integer(c_int), value :: eflags
      integer(c_int) :: c_regexec  ! Returns 0 on match
    end function c_regexec

    subroutine c_regfree(preg) bind(C, name="regfree")
      use iso_c_binding
      import :: regex_t
      type(regex_t), intent(inout) :: preg
    end subroutine c_regfree

    ! Process substitution support
    function c_mkfifo(pathname, mode) bind(C, name="mkfifo")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      integer(c_int), value :: mode
      integer(c_int) :: c_mkfifo
    end function c_mkfifo

    function c_pipe(pipefd) bind(C, name="pipe")
      use iso_c_binding
      integer(c_int), dimension(2), intent(out) :: pipefd
      integer(c_int) :: c_pipe
    end function c_pipe

    function c_fork() bind(C, name="fork")
      use iso_c_binding
      integer(c_int) :: c_fork
    end function c_fork

    function c_unlink(pathname) bind(C, name="unlink")
      use iso_c_binding
      character(kind=c_char), dimension(*), intent(in) :: pathname
      integer(c_int) :: c_unlink
    end function c_unlink

    function c_waitpid(pid, status, options) bind(C, name="waitpid")
      use iso_c_binding
      integer(c_int), value :: pid
      type(c_ptr), value :: status
      integer(c_int), value :: options
      integer(c_int) :: c_waitpid
    end function c_waitpid

    function c_read(fd, buf, count) bind(C, name="read")
      use iso_c_binding
      integer(c_int), value :: fd
      character(kind=c_char), dimension(*) :: buf
      integer(c_size_t), value :: count
      integer(c_size_t) :: c_read
    end function c_read

    subroutine c_exit(status) bind(C, name="_exit")
      use iso_c_binding
      integer(c_int), value :: status
    end subroutine c_exit
  end interface

  ! Glob flags (Linux values)
  integer(c_int), parameter :: GLOB_ERR = 1
  integer(c_int), parameter :: GLOB_MARK = 2
  integer(c_int), parameter :: GLOB_NOSORT = 4
  integer(c_int), parameter :: GLOB_NOCHECK = 16

  ! File open flags (Linux values)
  integer(c_int), parameter :: O_RDONLY = 0
  integer(c_int), parameter :: O_WRONLY = 1
  integer(c_int), parameter :: O_RDWR = 2
  integer(c_int), parameter :: O_CREAT = 64
  integer(c_int), parameter :: O_TRUNC = 512
  integer(c_int), parameter :: O_APPEND = 1024

  ! File access mode constants (Linux values)
  integer(c_int), parameter :: F_OK = 0  ! File exists
  integer(c_int), parameter :: R_OK = 4  ! File is readable
  integer(c_int), parameter :: W_OK = 2  ! File is writable
  integer(c_int), parameter :: X_OK = 1  ! File is executable

  ! Execution context
  type :: execution_context_t
    type(shell_state_t), pointer :: shell => null()
    type(shell_var_t), allocatable :: local_vars(:)
    integer :: local_var_count = 0
    logical :: break_requested = .false.
    integer :: break_levels = 0
    logical :: continue_requested = .false.
    integer :: continue_levels = 0
    logical :: return_requested = .false.
    integer :: return_value = 0
  contains
    procedure :: init => context_init
    procedure :: destroy => context_destroy
    procedure :: set_var => context_set_var
    procedure :: get_var => context_get_var
    procedure :: set_local_var => context_set_local_var
    procedure :: declare_array => context_declare_array
    procedure :: set_array_element => context_set_array_element
    procedure :: get_array_element => context_get_array_element
    procedure :: get_array_all => context_get_array_all
    procedure :: get_array_count => context_get_array_count
    procedure :: get_array_indices => context_get_array_indices
    procedure :: slice_array => context_slice_array
  end type execution_context_t

  ! Simple real evaluator
  type :: evaluator_simple_real_t
    type(execution_context_t) :: context
  contains
    procedure :: init => evaluator_init
    procedure :: eval => evaluator_eval
    procedure :: eval_node => evaluator_eval_node
    procedure :: eval_command => evaluator_eval_command
    procedure :: eval_pipeline => evaluator_eval_pipeline
    procedure :: eval_and_list => evaluator_eval_and_list
    procedure :: eval_or_list => evaluator_eval_or_list
    procedure :: eval_for_loop => evaluator_eval_for_loop
    procedure :: eval_for_arith_loop => evaluator_eval_for_arith_loop
    procedure :: eval_while_loop => evaluator_eval_while_loop
    procedure :: eval_if_statement => evaluator_eval_if_statement
    procedure :: eval_case_statement => evaluator_eval_case_statement
    procedure :: eval_function_definition => evaluator_eval_function_definition
    procedure :: eval_function_call => evaluator_eval_function_call
    procedure :: eval_subshell => evaluator_eval_subshell
    procedure :: eval_group => evaluator_eval_group
    procedure :: eval_break => evaluator_eval_break
    procedure :: eval_continue => evaluator_eval_continue
    procedure :: eval_word => evaluator_eval_word
    procedure :: eval_variable => evaluator_eval_variable
    procedure :: eval_command_subst => evaluator_eval_command_subst
    procedure :: eval_arithmetic => evaluator_eval_arithmetic
    procedure :: eval_cond_expr => evaluator_eval_cond_expr
    procedure :: eval_proc_subst => evaluator_eval_proc_subst
    procedure :: has_glob_pattern => evaluator_has_glob_pattern
    procedure :: expand_glob => evaluator_expand_glob
    procedure :: destroy => evaluator_destroy
  end type evaluator_simple_real_t

contains

  ! Initialize context
  subroutine context_init(self, shell)
    class(execution_context_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    self%shell => shell
    self%local_var_count = 0
    self%break_requested = .false.
    self%break_levels = 0
    self%continue_requested = .false.
    self%continue_levels = 0
    self%return_requested = .false.
    self%return_value = 0

    if (.not. allocated(self%local_vars)) then
      allocate(self%local_vars(50))
    end if
  end subroutine context_init

  ! Destroy context
  subroutine context_destroy(self)
    class(execution_context_t), intent(inout) :: self

    if (allocated(self%local_vars)) deallocate(self%local_vars)
    self%shell => null()
  end subroutine context_destroy

  ! Set variable
  subroutine context_set_var(self, name, value)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    ! Set in local context
    do i = 1, self%local_var_count
      if (trim(self%local_vars(i)%name) == trim(name)) then
        self%local_vars(i)%value = value
        return
      end if
    end do

    ! Add new variable
    if (self%local_var_count < size(self%local_vars)) then
      self%local_var_count = self%local_var_count + 1
      self%local_vars(self%local_var_count)%name = name
      self%local_vars(self%local_var_count)%value = value
    end if

    ! Also update shell variables if available
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (trim(self%shell%variables(i)%name) == trim(name)) then
          self%shell%variables(i)%value = value
          return
        end if
      end do
      ! Add to shell if not found
      if (self%shell%num_variables < size(self%shell%variables)) then
        self%shell%num_variables = self%shell%num_variables + 1
        self%shell%variables(self%shell%num_variables)%name = name
        self%shell%variables(self%shell%num_variables)%value = value
      end if
    end if
  end subroutine context_set_var

  ! Set local variable (only in local scope, not shell scope)
  subroutine context_set_local_var(self, name, value)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: name, value
    integer :: i

    ! Set in local context only (not in shell variables)
    do i = 1, self%local_var_count
      if (trim(self%local_vars(i)%name) == trim(name)) then
        self%local_vars(i)%value = value
        return
      end if
    end do

    ! Add new local variable
    if (self%local_var_count < size(self%local_vars)) then
      self%local_var_count = self%local_var_count + 1
      self%local_vars(self%local_var_count)%name = name
      self%local_vars(self%local_var_count)%value = value
    end if
  end subroutine context_set_local_var

  ! Declare an array variable
  subroutine context_declare_array(self, name)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: name
    integer :: i

    ! Check if variable already exists in shell variables
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (trim(self%shell%variables(i)%name) == trim(name)) then
          ! Mark existing variable as array
          self%shell%variables(i)%is_array = .true.
          self%shell%variables(i)%value = ''  ! Clear scalar value
          self%shell%variables(i)%num_elements = 0
          if (.not. allocated(self%shell%variables(i)%elements)) then
            allocate(self%shell%variables(i)%elements(0))
          end if
          return
        end if
      end do

      ! Add new array variable to shell
      if (self%shell%num_variables < size(self%shell%variables)) then
        self%shell%num_variables = self%shell%num_variables + 1
        self%shell%variables(self%shell%num_variables)%name = name
        self%shell%variables(self%shell%num_variables)%value = ''
        self%shell%variables(self%shell%num_variables)%is_array = .true.
        self%shell%variables(self%shell%num_variables)%num_elements = 0
        allocate(self%shell%variables(self%shell%num_variables)%elements(0))
      end if
    end if
  end subroutine context_declare_array

  ! Set an array element
  subroutine context_set_array_element(self, array_name, index, value)
    class(execution_context_t), intent(inout) :: self
    character(*), intent(in) :: array_name, value
    integer, intent(in) :: index
    integer :: i, j
    type(array_element_t), allocatable :: temp_elements(:)

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        ! Ensure it's an array
        if (.not. self%shell%variables(i)%is_array) then
          self%shell%variables(i)%is_array = .true.
          self%shell%variables(i)%num_elements = 0
          if (.not. allocated(self%shell%variables(i)%elements)) then
            allocate(self%shell%variables(i)%elements(0))
          end if
        end if

        ! Check if index already exists
        do j = 1, self%shell%variables(i)%num_elements
          if (self%shell%variables(i)%elements(j)%index == index) then
            ! Update existing element
            self%shell%variables(i)%elements(j)%value = value
            return
          end if
        end do

        ! Add new element - need to resize array
        allocate(temp_elements(self%shell%variables(i)%num_elements + 1))
        if (self%shell%variables(i)%num_elements > 0) then
          temp_elements(1:self%shell%variables(i)%num_elements) = &
            self%shell%variables(i)%elements
        end if
        temp_elements(self%shell%variables(i)%num_elements + 1)%index = index
        temp_elements(self%shell%variables(i)%num_elements + 1)%value = value
        call move_alloc(temp_elements, self%shell%variables(i)%elements)
        self%shell%variables(i)%num_elements = self%shell%variables(i)%num_elements + 1
        return
      end if
    end do

    ! Array doesn't exist - create it
    if (self%shell%num_variables < size(self%shell%variables)) then
      self%shell%num_variables = self%shell%num_variables + 1
      self%shell%variables(self%shell%num_variables)%name = array_name
      self%shell%variables(self%shell%num_variables)%is_array = .true.
      self%shell%variables(self%shell%num_variables)%num_elements = 1
      allocate(self%shell%variables(self%shell%num_variables)%elements(1))
      self%shell%variables(self%shell%num_variables)%elements(1)%index = index
      self%shell%variables(self%shell%num_variables)%elements(1)%value = value
    end if
  end subroutine context_set_array_element

  ! Get an array element
  function context_get_array_element(self, array_name, index) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: array_name
    integer, intent(in) :: index
    character(:), allocatable :: value
    integer :: i, j

    value = ''

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        if (.not. self%shell%variables(i)%is_array) return

        ! Find the element with matching index
        do j = 1, self%shell%variables(i)%num_elements
          if (self%shell%variables(i)%elements(j)%index == index) then
            value = self%shell%variables(i)%elements(j)%value
            return
          end if
        end do
        return
      end if
    end do
  end function context_get_array_element

  ! Get all array elements as a space-separated string
  function context_get_array_all(self, array_name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: array_name
    character(:), allocatable :: value
    integer :: i, j

    value = ''

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        if (.not. self%shell%variables(i)%is_array) return

        ! Concatenate all elements
        do j = 1, self%shell%variables(i)%num_elements
          if (j > 1) value = trim(value) // ' '
          value = trim(value) // trim(self%shell%variables(i)%elements(j)%value)
        end do
        return
      end if
    end do
  end function context_get_array_all

  ! Get array element count
  function context_get_array_count(self, array_name) result(count)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: array_name
    integer :: count
    integer :: i

    count = 0

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        if (self%shell%variables(i)%is_array) then
          count = self%shell%variables(i)%num_elements
        end if
        return
      end if
    end do
  end function context_get_array_count

  ! Get array indices as a space-separated string (for ${!array[@]})
  function context_get_array_indices(self, array_name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: array_name
    character(:), allocatable :: value
    character(16) :: index_str
    integer :: i, j

    value = ''

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        if (.not. self%shell%variables(i)%is_array) return

        ! Concatenate all indices as strings
        do j = 1, self%shell%variables(i)%num_elements
          if (j > 1) value = trim(value) // ' '
          write(index_str, '(i15)') self%shell%variables(i)%elements(j)%index
          value = trim(value) // trim(index_str)
        end do
        return
      end if
    end do
  end function context_get_array_indices

  ! Slice array elements (for ${array[@]:offset:length})
  function context_slice_array(self, array_name, offset, length) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: array_name
    integer, intent(in) :: offset, length
    character(:), allocatable :: value
    integer :: i, j, count, start_idx, end_idx
    logical :: first

    value = ''

    if (.not. associated(self%shell)) return

    ! Find the array variable
    do i = 1, self%shell%num_variables
      if (trim(self%shell%variables(i)%name) == trim(array_name)) then
        if (.not. self%shell%variables(i)%is_array) return

        ! Calculate start and end indices (0-based offset)
        start_idx = offset + 1  ! Convert to 1-based
        if (start_idx < 1) start_idx = 1
        if (start_idx > self%shell%variables(i)%num_elements) return

        if (length < 0) then
          ! Negative length means "all remaining"
          end_idx = self%shell%variables(i)%num_elements
        else
          end_idx = start_idx + length - 1
          if (end_idx > self%shell%variables(i)%num_elements) then
            end_idx = self%shell%variables(i)%num_elements
          end if
        end if

        ! Collect the sliced elements
        first = .true.
        do j = start_idx, end_idx
          if (.not. first) value = trim(value) // ' '
          value = trim(value) // trim(self%shell%variables(i)%elements(j)%value)
          first = .false.
        end do
        return
      end if
    end do
  end function context_slice_array

  ! Get variable
  function context_get_var(self, name) result(value)
    class(execution_context_t), intent(in) :: self
    character(*), intent(in) :: name
    character(:), allocatable :: value
    integer :: i

    ! Check local variables
    do i = 1, self%local_var_count
      if (trim(self%local_vars(i)%name) == trim(name)) then
        value = trim(self%local_vars(i)%value)
        return
      end if
    end do

    ! Check shell variables
    if (associated(self%shell)) then
      do i = 1, self%shell%num_variables
        if (trim(self%shell%variables(i)%name) == trim(name)) then
          value = trim(self%shell%variables(i)%value)
          return
        end if
      end do
    end if

    ! Check environment
    call get_environment_variable(name, value)
    if (.not. allocated(value)) value = ''
  end function context_get_var

  ! Initialize evaluator
  subroutine evaluator_init(self, shell)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(shell_state_t), target, intent(in) :: shell

    call self%context%init(shell)
  end subroutine evaluator_init

  ! Main eval
  function evaluator_eval(self, ast) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(script_node_t), intent(in) :: ast
    integer :: exit_code
    integer :: i

    exit_code = 0

    if (.not. allocated(ast%statements)) return

    do i = 1, ast%num_statements
      if (associated(ast%statements(i)%ptr)) then
        exit_code = self%eval_node(ast%statements(i)%ptr)
        if (self%context%return_requested) then
          exit_code = self%context%return_value
          exit
        end if
      end if
    end do
  end function evaluator_eval

  ! Eval node
  recursive function evaluator_eval_node(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    integer :: exit_code
    type(command_node_t), pointer :: cmd_ptr
    type(pipeline_node_t), pointer :: pipe_ptr
    type(and_list_node_t), pointer :: and_ptr
    type(or_list_node_t), pointer :: or_ptr
    type(for_node_t), pointer :: for_ptr
    type(for_arith_node_t), pointer :: for_arith_ptr
    type(while_node_t), pointer :: while_ptr
    type(if_node_t), pointer :: if_ptr
    type(case_node_t), pointer :: case_ptr
    type(function_node_t), pointer :: func_ptr
    type(break_node_t), pointer :: break_ptr
    type(continue_node_t), pointer :: continue_ptr
    type(subshell_node_t), pointer :: subshell_ptr
    type(group_node_t), pointer :: group_ptr

    exit_code = 0
    if (.not. associated(node)) return

    select type(node)
    type is (command_node_t)
      ! Create pointer to preserve allocated arrays
      cmd_ptr => node
      exit_code = self%eval_command(cmd_ptr)

    type is (pipeline_node_t)
      pipe_ptr => node
      exit_code = self%eval_pipeline(pipe_ptr)

    type is (and_list_node_t)
      and_ptr => node
      exit_code = self%eval_and_list(and_ptr)

    type is (or_list_node_t)
      or_ptr => node
      exit_code = self%eval_or_list(or_ptr)

    type is (for_node_t)
      for_ptr => node
      exit_code = self%eval_for_loop(for_ptr)

    type is (for_arith_node_t)
      for_arith_ptr => node
      exit_code = self%eval_for_arith_loop(for_arith_ptr)

    type is (while_node_t)
      while_ptr => node
      exit_code = self%eval_while_loop(while_ptr)

    type is (if_node_t)
      if_ptr => node
      exit_code = self%eval_if_statement(if_ptr)

    type is (case_node_t)
      case_ptr => node
      exit_code = self%eval_case_statement(case_ptr)

    type is (function_node_t)
      func_ptr => node
      exit_code = self%eval_function_definition(func_ptr)

    type is (break_node_t)
      break_ptr => node
      exit_code = self%eval_break(break_ptr)

    type is (continue_node_t)
      continue_ptr => node
      exit_code = self%eval_continue(continue_ptr)

    type is (subshell_node_t)
      subshell_ptr => node
      exit_code = self%eval_subshell(subshell_ptr)

    type is (group_node_t)
      group_ptr => node
      exit_code = self%eval_group(group_ptr)

    type is (cond_expr_node_t)
      exit_code = self%eval_cond_expr(node)

    class default
      exit_code = 127
    end select
  end function evaluator_eval_node

  ! Evaluate command - THE KEY FUNCTION!
  function evaluator_eval_command(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(command_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(1024) :: cmd_str
    character(256) :: word_value
    character(:), allocatable :: first_word, expanded_word
    integer :: i, j
    integer :: bracket_end, array_index
    character(:), allocatable :: array_name, index_str
    character(kind=c_char, len=256) :: c_cmd
    character(256) :: cwd_buffer
    integer(c_int) :: status
    type(c_ptr) :: ptr

    ! Redirection handling variables
    integer(c_int) :: saved_stdin, saved_stdout, saved_stderr
    integer(c_int) :: new_fd, flags, ret
    integer(c_size_t) :: bytes_written
    logical :: has_redirections
    character(256) :: redir_file
    character(16) :: pid_str
    character(16) :: tmp
    type(redirection_node_t), pointer :: redir
    real :: rnum

    ! Function call handling variables
    logical :: call_as_function
    character(256), allocatable :: func_args(:)

    exit_code = 0

    if (.not. allocated(node%words) .or. node%num_words == 0) return

    ! Check if this is a background job
    if (node%background) then
      ! Build command string for background execution
      cmd_str = ''
      do i = 1, node%num_words
        if (associated(node%words(i)%ptr)) then
          expanded_word = self%eval_word(node%words(i)%ptr)
          if (i == 1) then
            cmd_str = trim(expanded_word)
          else
            cmd_str = trim(cmd_str) // ' ' // trim(expanded_word)
          end if
        end if
      end do

      ! Execute as background job by appending & to the command
      c_cmd = trim(cmd_str) // ' &' // c_null_char
      status = c_system(c_cmd)

      ! Background jobs return immediately with exit code 0
      exit_code = 0
      if (associated(self%context%shell)) then
        self%context%shell%last_exit_status = 0
      end if
      return
    end if

    ! Check if we have redirections
    has_redirections = allocated(node%redirections) .and. node%num_redirections > 0

    ! Save current file descriptors if needed
    if (has_redirections) then
      saved_stdin = c_dup(0_c_int)
      saved_stdout = c_dup(1_c_int)
      saved_stderr = c_dup(2_c_int)

      ! Apply redirections
      do j = 1, node%num_redirections
        if (associated(node%redirections(j)%ptr)) then
          select type(r => node%redirections(j)%ptr)
          type is (redirection_node_t)
            select case(r%redirect_type)
            case(4, 5)  ! Here document (<<) or here string (<<<)
              ! Create temporary file for here document/string content
              call random_number(rnum)
              write(pid_str, '(i15)') int(rnum * 99999) + 10000
              redir_file = '/tmp/fortsh_heredoc_' // trim(pid_str) // c_null_char
              flags = ior(O_WRONLY, ior(O_CREAT, O_TRUNC))
              new_fd = c_open(redir_file, flags, int(o'644', c_int))
              if (new_fd >= 0) then
                ! Write content to temp file
                if (allocated(r%heredoc_content)) then
                  ! For here strings, add a newline at the end
                  if (r%redirect_type == 5) then
                    bytes_written = c_write(new_fd, trim(r%heredoc_content) // char(10) // c_null_char, &
                                           int(len_trim(r%heredoc_content) + 1, c_size_t))
                  else
                    bytes_written = c_write(new_fd, trim(r%heredoc_content) // c_null_char, &
                                           int(len_trim(r%heredoc_content), c_size_t))
                  end if
                end if
                ret = c_close(new_fd)

                ! Reopen for reading and redirect to stdin
                new_fd = c_open(redir_file, O_RDONLY, 0_c_int)
                if (new_fd >= 0) then
                  ret = c_dup2(new_fd, 0_c_int)
                  ret = c_close(new_fd)
                end if
              end if

            case(6, 7)  ! FD duplication (>& or <&)
              ! Determine target FD
              if (r%target_fd >= 0) then
                ! Literal FD number (e.g., >&4)
                new_fd = int(r%target_fd, c_int)
              else if (allocated(r%target_fd_expr)) then
                ! Variable expression (e.g., >&${COPROC[1]})
                ! Need to expand the expression
                tmp = self%expand_string(r%target_fd_expr)
                read(tmp, *, iostat=status) new_fd
                if (status /= 0) then
                  ! Invalid FD number from expansion
                  cycle
                end if
              else
                ! No target FD specified
                cycle
              end if

              ! Apply FD duplication using c_dup2
              ! r%fd is the source (default stdin/stdout), new_fd is the target
              if (r%redirect_type == 6) then
                ! >&n - duplicate target FD to stdout (or specified FD)
                ret = c_dup2(int(new_fd, c_int), int(r%fd, c_int))
              else if (r%redirect_type == 7) then
                ! <&n - duplicate target FD to stdin (or specified FD)
                ret = c_dup2(int(new_fd, c_int), int(r%fd, c_int))
              end if

            case default
              ! Get the target filename for regular redirections
              if (allocated(r%target)) then
                select type(t => r%target)
                type is (word_node_t)
                  redir_file = trim(t%text) // c_null_char

                  ! Open file based on redirection type
                  select case(r%redirect_type)
                  case(1)  ! Input redirection (<)
                    new_fd = c_open(redir_file, O_RDONLY, 0_c_int)
                    if (new_fd >= 0) then
                      ret = c_dup2(new_fd, 0_c_int)
                      ret = c_close(new_fd)
                    end if

                  case(2)  ! Output redirection (>)
                    flags = ior(O_WRONLY, ior(O_CREAT, O_TRUNC))
                    new_fd = c_open(redir_file, flags, int(o'644', c_int))
                    if (new_fd >= 0) then
                      ret = c_dup2(new_fd, 1_c_int)
                      ret = c_close(new_fd)
                    end if

                  case(3)  ! Append redirection (>>)
                    flags = ior(O_WRONLY, ior(O_CREAT, O_APPEND))
                    new_fd = c_open(redir_file, flags, int(o'644', c_int))
                    if (new_fd >= 0) then
                      ret = c_dup2(new_fd, 1_c_int)
                      ret = c_close(new_fd)
                    end if
                  end select
                end select
              end if
            end select
          end select
        end if
      end do
    end if

    ! Get first word to check for built-ins
    if (associated(node%words(1)%ptr)) then
      first_word = self%eval_word(node%words(1)%ptr)
    else
      if (has_redirections) then
        ! Restore file descriptors
        ret = c_dup2(saved_stdin, 0_c_int)
        ret = c_dup2(saved_stdout, 1_c_int)
        ret = c_dup2(saved_stderr, 2_c_int)
        ret = c_close(saved_stdin)
        ret = c_close(saved_stdout)
        ret = c_close(saved_stderr)
      end if
      return
    end if

    ! Check for variable assignment (VAR=value or array[index]=value)
    i = index(first_word, '=')
    if (i > 1) then
      ! It's an assignment
      ! Check if it's an array assignment: array[index]=value
      j = index(first_word(1:i-1), '[')
      if (j > 0) then
        ! Array assignment
        bracket_end = index(first_word(1:i-1), ']')
        if (bracket_end > j) then
          ! Extract array name and index
          array_name = first_word(1:j-1)
          index_str = first_word(j+1:bracket_end-1)

          ! Convert index to integer
          read(index_str, *, iostat=status) array_index
          if (status == 0) then
            ! Set the array element
            call self%context%set_array_element(trim(array_name), array_index, first_word(i+1:))
            exit_code = 0
          else
            exit_code = 1
          end if
        else
          exit_code = 1
        end if
      else
        ! Regular variable assignment
        call self%context%set_var(first_word(1:i-1), first_word(i+1:))
        exit_code = 0
      end if

      ! Restore file descriptors if needed
      if (has_redirections) then
        ret = c_dup2(saved_stdin, 0_c_int)
        ret = c_dup2(saved_stdout, 1_c_int)
        ret = c_dup2(saved_stderr, 2_c_int)
        ret = c_close(saved_stdin)
        ret = c_close(saved_stdout)
        ret = c_close(saved_stderr)
      end if

      ! Update shell exit status
      if (associated(self%context%shell)) then
        self%context%shell%last_exit_status = exit_code
      end if
      return
    end if

    ! Handle simple built-ins
    select case(trim(first_word))
    case('echo')
      ! Build echo arguments with proper spacing
      cmd_str = ''
      do i = 2, node%num_words
        if (associated(node%words(i)%ptr)) then
          expanded_word = self%eval_word(node%words(i)%ptr)
          if (i == 2) then
            cmd_str = trim(expanded_word)
          else
            cmd_str = cmd_str(1:len_trim(cmd_str)) // ' ' // trim(expanded_word)
          end if
        end if
      end do
      write(output_unit, '(a)') trim(cmd_str)
      exit_code = 0

    case('pwd')
      ! Get current directory
      cwd_buffer = ''  ! Initialize buffer
      c_cmd = c_null_char
      ptr = c_getcwd(c_cmd, 256_c_size_t)
      if (c_associated(ptr)) then
        ! Convert C string to Fortran
        do i = 1, 256
          if (c_cmd(i:i) == c_null_char) then
            cwd_buffer = cwd_buffer(1:i-1)  ! Trim to actual length
            exit
          end if
          cwd_buffer(i:i) = c_cmd(i:i)
        end do
        write(output_unit, '(a)') trim(cwd_buffer)
        exit_code = 0
      else
        exit_code = 1
      end if

    case('cd')
      ! Change directory
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        c_cmd = trim(expanded_word) // c_null_char
        status = c_chdir(c_cmd)
        exit_code = abs(status)
        ! Update shell cwd if successful
        if (exit_code == 0 .and. associated(self%context%shell)) then
          ptr = c_getcwd(c_cmd, 256_c_size_t)
          if (c_associated(ptr)) then
            do i = 1, 256
              if (c_cmd(i:i) == c_null_char) exit
              self%context%shell%cwd(i:i) = c_cmd(i:i)
            end do
          end if
        end if
      else
        ! cd with no args goes home
        call get_environment_variable('HOME', word_value)
        c_cmd = trim(word_value) // c_null_char
        status = c_chdir(c_cmd)
        exit_code = abs(status)
      end if

    case('exit')
      ! Exit shell - TODO: integrate with main shell running state
      ! if (associated(self%context%shell)) then
      !   self%context%shell%running = .false.
      ! end if
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        read(expanded_word, *, iostat=status) exit_code
        if (status /= 0) exit_code = 0
      else
        exit_code = 0
      end if

    case('return')
      ! Return from function with optional exit code
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        read(expanded_word, *, iostat=status) exit_code
        if (status /= 0) exit_code = 0
      else
        exit_code = 0
      end if
      self%context%return_requested = .true.
      self%context%return_value = exit_code

    case('export')
      ! Export variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Look for = in the word
        i = index(expanded_word, '=')
        if (i > 1) then
          ! VAR=value format
          call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
          call setenv(expanded_word(1:i-1), expanded_word(i+1:), 1)
        end if
      end if
      exit_code = 0

    case('set')
      ! Set or show shell variables
      if (node%num_words == 1) then
        ! Show all variables
        if (associated(self%context%shell)) then
          do i = 1, self%context%shell%num_variables
            write(output_unit, '(3a)') trim(self%context%shell%variables(i)%name), &
                                       '=', trim(self%context%shell%variables(i)%value)
          end do
        end if
      else if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Look for = in the word
        i = index(expanded_word, '=')
        if (i > 1) then
          ! VAR=value format - set variable
          call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
        end if
      end if
      exit_code = 0

    case('declare')
      ! Declare variable with optional flags (-a for arrays)
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)

        ! Check for -a flag (array declaration)
        if (trim(expanded_word) == '-a') then
          ! Array declaration: declare -a arrayname
          if (node%num_words >= 3 .and. associated(node%words(3)%ptr)) then
            expanded_word = self%eval_word(node%words(3)%ptr)
            ! Look for = in the word
            i = index(expanded_word, '=')
            if (i > 1) then
              ! Array with immediate assignment: declare -a arr=value
              ! For now, just declare the array (assignment comes later)
              call self%context%declare_array(expanded_word(1:i-1))
            else
              ! Just declare array with no assignment
              call self%context%declare_array(trim(expanded_word))
            end if
          end if
        else
          ! Regular variable declaration
          ! Look for = in the word
          i = index(expanded_word, '=')
          if (i > 1) then
            ! VAR=value format
            call self%context%set_var(expanded_word(1:i-1), expanded_word(i+1:))
          else
            ! Just declare with empty value
            call self%context%set_var(trim(expanded_word), '')
          end if
        end if
      end if
      exit_code = 0

    case('true')
      exit_code = 0

    case('false')
      exit_code = 1

    case('test', '[')
      ! Comprehensive POSIX test command
      exit_code = call_test_builtin(self, node)

    case('unset')
      ! Unset variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Remove from context variables
        if (associated(self%context%shell)) then
          do i = 1, self%context%shell%num_variables
            if (trim(self%context%shell%variables(i)%name) == trim(expanded_word)) then
              ! Shift remaining variables up
              do j = i, self%context%shell%num_variables - 1
                self%context%shell%variables(j) = self%context%shell%variables(j+1)
              end do
              self%context%shell%num_variables = self%context%shell%num_variables - 1
              exit
            end if
          end do
        end if
      end if
      exit_code = 0

    case('read')
      ! Read input into variable
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Read a line from stdin
        read(input_unit, '(a)', iostat=status) word_value
        if (status == 0) then
          call self%context%set_var(trim(expanded_word), trim(word_value))
          exit_code = 0
        else
          exit_code = 1
        end if
      else
        exit_code = 1
      end if

    case('source', '.')
      ! Source/execute commands from file
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        block
          logical :: file_exists
          character(4096) :: line
          integer :: unit_num, io_stat

          inquire(file=trim(expanded_word), exist=file_exists)
          if (file_exists) then
            open(newunit=unit_num, file=trim(expanded_word), status='old', &
                 action='read', iostat=io_stat)
            if (io_stat == 0) then
              do
                read(unit_num, '(a)', iostat=io_stat) line
                if (io_stat /= 0) exit
                ! Execute each line as a command
                ! Note: This is simplified - should use full parsing
                c_cmd = trim(line) // c_null_char
                status = c_system(c_cmd)
              end do
              close(unit_num)
              exit_code = 0
            else
              exit_code = 1
            end if
          else
            write(error_unit, *) 'source: cannot read: ', trim(expanded_word)
            exit_code = 1
          end if
        end block
      else
        exit_code = 1
      end if

    case('alias')
      ! Alias command (simplified - just show message for now)
      if (node%num_words >= 2) then
        ! Would need to implement alias storage in shell context
        write(output_unit, *) 'alias: not fully implemented yet'
      else
        ! Show all aliases (none for now)
        write(output_unit, *) 'No aliases defined'
      end if
      exit_code = 0

    case('type')
      ! Show type of command
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        expanded_word = self%eval_word(node%words(2)%ptr)

        ! Check if it's a builtin
        select case(trim(expanded_word))
        case('echo', 'pwd', 'cd', 'exit', 'return', 'export', 'set', 'declare', 'true', 'false', &
             'test', '[', 'unset', 'read', 'source', '.', 'alias', 'type', &
             'printf', 'let', 'eval', 'shift', 'local', 'getopts', 'trap', 'wait', 'kill', 'ulimit')
          write(output_unit, '(2a)') trim(expanded_word), ' is a shell builtin'
        case default
          ! Not a builtin, check if it's a shell function
          call_as_function = .false.
          if (associated(self%context%shell)) then
            do i = 1, self%context%shell%num_functions
              if (trim(self%context%shell%functions(i)%name) == trim(expanded_word)) then
                call_as_function = .true.
                exit
              end if
            end do
          end if

          if (call_as_function) then
            write(output_unit, '(2a)') trim(expanded_word), ' is a function'
          else
            ! Check if it's an external command
            c_cmd = 'which ' // trim(expanded_word) // ' 2>/dev/null' // c_null_char
            status = c_system(c_cmd)
            if (status == 0) then
              write(output_unit, '(3a)') trim(expanded_word), ' is ', trim(expanded_word)
            else
              write(output_unit, '(3a)') 'bash: type: ', trim(expanded_word), ': not found'
              exit_code = 1
            end if
          end if
        end select
      else
        exit_code = 1
      end if

    case('printf')
      ! printf - formatted output (simplified implementation)
      if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
        ! Get format string
        expanded_word = self%eval_word(node%words(2)%ptr)
        cmd_str = trim(expanded_word)

        ! Append remaining arguments
        do i = 3, node%num_words
          if (associated(node%words(i)%ptr)) then
            word_value = self%eval_word(node%words(i)%ptr)
            cmd_str = trim(cmd_str) // ' ' // trim(word_value)
          end if
        end do

        ! Use system printf for now (simple implementation)
        c_cmd = 'printf ' // trim(cmd_str) // c_null_char
        status = c_system(c_cmd)
        exit_code = 0
      else
        exit_code = 1
      end if

    case('let')
      ! let - arithmetic evaluation and assignment
      ! Example: let x=5+3 or let "x = 5 + 3"
      if (node%num_words >= 2) then
        exit_code = 0
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            expanded_word = self%eval_word(node%words(i)%ptr)

            ! Look for = to find assignment
            j = index(expanded_word, '=')
            if (j > 1) then
              ! Extract variable name and expression
              word_value = trim(expanded_word(1:j-1))
              cmd_str = trim(expanded_word(j+1:))

              ! Evaluate the arithmetic expression
              call evaluate_arithmetic_expr(trim(cmd_str), status, rnum)
              if (status == 0) then
                ! Set the variable to the result
                write(cwd_buffer, '(i15)') int(rnum)
                call self%context%set_var(trim(word_value), trim(cwd_buffer))
              else
                exit_code = 1
              end if
            else
              ! Just evaluate expression (exit code 0 if non-zero, 1 if zero)
              call evaluate_arithmetic_expr(trim(expanded_word), status, rnum)
              if (status == 0) then
                if (int(rnum) == 0) then
                  exit_code = 1
                else
                  exit_code = 0
                end if
              else
                exit_code = 1
              end if
            end if
          end if
        end do
      else
        exit_code = 1
      end if

    case('eval')
      ! eval - evaluate string as shell command
      if (node%num_words >= 2) then
        ! Concatenate all arguments into a command string
        cmd_str = ''
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            expanded_word = self%eval_word(node%words(i)%ptr)
            if (i == 2) then
              cmd_str = trim(expanded_word)
            else
              cmd_str = trim(cmd_str) // ' ' // trim(expanded_word)
            end if
          end if
        end do

        ! Execute the constructed command string
        c_cmd = trim(cmd_str) // c_null_char
        status = c_system(c_cmd)
        if (status < 0) then
          exit_code = 127
        else
          exit_code = status / 256
        end if
      else
        exit_code = 0
      end if

    case('shift')
      ! shift - shift positional parameters left
      if (associated(self%context%shell)) then
        ! Get shift count (default 1)
        j = 1
        if (node%num_words >= 2 .and. associated(node%words(2)%ptr)) then
          expanded_word = self%eval_word(node%words(2)%ptr)
          read(expanded_word, *, iostat=status) j
          if (status /= 0) j = 1
        end if

        ! Shift parameters (would need proper positional parameter support)
        ! For now, just return success
        exit_code = 0
        ! TODO: Implement actual positional parameter shifting when $1, $2, etc. are supported
      else
        exit_code = 1
      end if

    case('local')
      ! local - declare local variables in functions
      if (node%num_words >= 2) then
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            expanded_word = self%eval_word(node%words(i)%ptr)

            ! Look for = in the word
            j = index(expanded_word, '=')
            if (j > 1) then
              ! VAR=value format - set local variable
              call self%context%set_local_var(expanded_word(1:j-1), expanded_word(j+1:))
            else
              ! Just declare with empty value
              call self%context%set_local_var(trim(expanded_word), '')
            end if
          end if
        end do
        exit_code = 0
      else
        exit_code = 0
      end if

    case('getopts')
      ! getopts - parse command options
      ! Usage: getopts optstring name [args]
      ! Example: getopts "a:b:c" opt
      if (node%num_words >= 3 .and. associated(self%context%shell)) then
        ! Get optstring (e.g., "a:b:c" where : means option requires argument)
        expanded_word = self%eval_word(node%words(2)%ptr)
        ! Get variable name to store current option
        word_value = self%eval_word(node%words(3)%ptr)

        ! Get OPTIND (current position, defaults to 1)
        cmd_str = self%context%get_var('OPTIND')
        if (len_trim(cmd_str) == 0) then
          j = 1  ! Start at first positional parameter
        else
          read(cmd_str, *, iostat=status) j
          if (status /= 0) j = 1
        end if

        ! Check if we're done (no more positional parameters)
        if (j > self%context%shell%num_positional) then
          exit_code = 1  ! Done processing
        else
          ! Get current positional parameter
          cmd_str = trim(self%context%shell%positional_params(j))

          ! Check if it starts with - and has at least one option character
          if (len_trim(cmd_str) >= 2 .and. cmd_str(1:1) == '-' .and. cmd_str(2:2) /= '-') then
            ! Extract option character (first char after -)
            tmp(1:1) = cmd_str(2:2)

            ! Check if this option is in optstring
            i = index(expanded_word, tmp(1:1))
            if (i > 0) then
              ! Valid option - set the variable to the option character
              call self%context%set_var(trim(word_value), tmp(1:1))

              ! Check if option requires an argument (followed by : in optstring)
              if (i < len_trim(expanded_word) .and. expanded_word(i+1:i+1) == ':') then
                ! Option requires an argument
                if (len_trim(cmd_str) > 2) then
                  ! Argument is rest of current parameter (e.g., -ovalue)
                  call self%context%set_var('OPTARG', trim(cmd_str(3:)))
                  j = j + 1
                else if (j < self%context%shell%num_positional) then
                  ! Argument is next parameter (e.g., -o value)
                  j = j + 1
                  call self%context%set_var('OPTARG', &
                    trim(self%context%shell%positional_params(j)))
                  j = j + 1
                else
                  ! Missing required argument
                  call self%context%set_var(trim(word_value), '?')
                  call self%context%set_var('OPTARG', tmp(1:1))
                  j = j + 1
                  exit_code = 0
                end if
              else
                ! Option doesn't require argument
                j = j + 1
              end if
              exit_code = 0
            else
              ! Invalid option
              call self%context%set_var(trim(word_value), '?')
              call self%context%set_var('OPTARG', tmp(1:1))
              j = j + 1
              exit_code = 0
            end if
          else
            ! Not an option (doesn't start with -) - done
            exit_code = 1
          end if

          ! Update OPTIND
          write(tmp, '(i15)') j
          call self%context%set_var('OPTIND', trim(tmp))
        end if
      else
        exit_code = 1
      end if

    case('trap')
      ! trap - catch signals and execute commands
      ! Usage: trap [-p] [[arg] signal_spec ...]
      ! Example: trap 'echo caught' SIGINT
      !          trap - SIGINT  (remove trap)
      !          trap -p        (list traps)

      ! NOTE: This is a minimal implementation that doesn't actually set signal handlers
      ! Full signal handling would require C bindings for sigaction/signal

      if (node%num_words == 1) then
        ! No arguments - list all traps (currently none implemented)
        exit_code = 0
      else if (node%num_words == 2) then
        expanded_word = self%eval_word(node%words(2)%ptr)
        if (trim(expanded_word) == '-p') then
          ! List traps in reusable format (currently none)
          exit_code = 0
        else
          ! Invalid usage
          exit_code = 1
        end if
      else if (node%num_words >= 3) then
        ! Get command and signal
        cmd_str = self%eval_word(node%words(2)%ptr)
        word_value = self%eval_word(node%words(3)%ptr)

        ! In a full implementation, we would:
        ! 1. Parse signal name/number (SIGINT, INT, 2, etc.)
        ! 2. Store cmd_str as the handler for that signal
        ! 3. Use sigaction/signal C bindings to register handler
        ! 4. On signal, execute the stored command

        ! For now, just accept the syntax and return success
        exit_code = 0
      else
        exit_code = 1
      end if

    case('wait')
      ! wait - wait for background processes to complete
      ! Usage: wait [pid ...]
      ! Example: wait
      !          wait %1
      !          wait $pid

      ! NOTE: This is a minimal implementation
      ! Full job control would require:
      ! 1. Tracking background PIDs in shell context
      ! 2. C bindings for waitpid()
      ! 3. Job table with job IDs and states

      if (node%num_words == 1) then
        ! No arguments - wait for all background jobs
        ! In full implementation: loop through all background PIDs and wait
        exit_code = 0
      else
        ! Wait for specific PIDs
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            word_value = self%eval_word(node%words(i)%ptr)
            ! In full implementation:
            ! 1. Parse PID or job ID (%1, %2, etc.)
            ! 2. Call waitpid() for that process
            ! 3. Set exit_code to the exit status of the waited process
          end if
        end do
        exit_code = 0
      end if

    case('kill')
      ! kill - send signal to processes
      ! Usage: kill [-s sigspec | -n signum | -sigspec] pid ...
      ! Example: kill 1234
      !          kill -9 1234
      !          kill -TERM 1234
      !          kill -s SIGKILL 1234

      ! NOTE: This is a minimal implementation
      ! Full implementation would require:
      ! 1. C bindings for kill() system call
      ! 2. Signal name/number parsing
      ! 3. Process validation

      if (node%num_words < 2) then
        ! Need at least one PID
        exit_code = 1
      else
        ! Parse arguments
        j = 2  ! Start at first argument
        i = 15  ! Default signal is SIGTERM (15)

        ! Check if first arg is a signal specification
        if (j <= node%num_words) then
          word_value = self%eval_word(node%words(j)%ptr)
          if (len_trim(word_value) > 0 .and. word_value(1:1) == '-') then
            ! Signal specification
            if (trim(word_value) == '-s' .or. trim(word_value) == '-n') then
              ! Next arg is the signal
              j = j + 1
              if (j <= node%num_words) then
                cmd_str = self%eval_word(node%words(j)%ptr)
                ! Parse signal name or number
                ! In full implementation: convert signal name to number
              end if
              j = j + 1
            else
              ! Signal in format -SIGNAME or -NUM
              ! In full implementation: parse signal from word_value
              j = j + 1
            end if
          end if
        end if

        ! Process remaining arguments as PIDs
        do while (j <= node%num_words)
          if (associated(node%words(j)%ptr)) then
            word_value = self%eval_word(node%words(j)%ptr)
            ! In full implementation:
            ! 1. Parse PID from word_value
            ! 2. Call kill(pid, signal)
            ! 3. Check return value
          end if
          j = j + 1
        end do

        exit_code = 0
      end if

    case('ulimit')
      ! ulimit - set or display resource limits
      ! Usage: ulimit [-SHacdefilmnpqrstuvx] [limit]
      ! Example: ulimit -n        (show max open files)
      !          ulimit -n 2048   (set max open files)
      !          ulimit -a        (show all limits)

      ! NOTE: This is a minimal implementation
      ! Full implementation would require:
      ! 1. C bindings for getrlimit() and setrlimit()
      ! 2. Parsing of resource limit options
      ! 3. Proper formatting of limit values

      if (node%num_words == 1) then
        ! No arguments - show default limit (max file size, unlimited)
        exit_code = 0
      else if (node%num_words == 2) then
        word_value = self%eval_word(node%words(2)%ptr)
        if (trim(word_value) == '-a') then
          ! Show all limits
          ! In full implementation: call getrlimit() for each resource type
          exit_code = 0
        else if (len_trim(word_value) > 0 .and. word_value(1:1) == '-') then
          ! Show specific limit (e.g., -n for open files)
          exit_code = 0
        else
          ! Set default limit to specified value
          exit_code = 0
        end if
      else if (node%num_words == 3) then
        ! Set specific limit: ulimit -n 2048
        word_value = self%eval_word(node%words(2)%ptr)
        cmd_str = self%eval_word(node%words(3)%ptr)
        ! In full implementation:
        ! 1. Parse resource type from word_value (-n, -u, etc.)
        ! 2. Parse limit value from cmd_str
        ! 3. Call setrlimit() with appropriate resource and limit
        exit_code = 0
      else
        exit_code = 1
      end if

    case default
      ! Check if it's a shell function first
      call_as_function = .false.
      if (associated(self%context%shell)) then
        do i = 1, self%context%shell%num_functions
          if (trim(self%context%shell%functions(i)%name) == trim(first_word)) then
            call_as_function = .true.
            exit
          end if
        end do
      end if

      if (call_as_function) then
        ! Call shell function
        ! Build argument array
        allocate(func_args(node%num_words - 1))
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            func_args(i-1) = self%eval_word(node%words(i)%ptr)
          else
            func_args(i-1) = ''
          end if
        end do
        exit_code = self%eval_function_call(trim(first_word), func_args)
        deallocate(func_args)
      else
        ! External command - build full command line
        cmd_str = trim(first_word)
        do i = 2, node%num_words
          if (associated(node%words(i)%ptr)) then
            expanded_word = self%eval_word(node%words(i)%ptr)
            cmd_str = trim(cmd_str) // ' ' // trim(expanded_word)
          end if
        end do

        ! Execute via system()
        c_cmd = trim(cmd_str) // c_null_char
        status = c_system(c_cmd)

        ! Extract exit code
        if (status < 0) then
          exit_code = 127
        else
          exit_code = status / 256
        end if
      end if
    end select

    ! Restore file descriptors if they were redirected
    if (has_redirections) then
      ret = c_dup2(saved_stdin, 0_c_int)
      ret = c_dup2(saved_stdout, 1_c_int)
      ret = c_dup2(saved_stderr, 2_c_int)
      ret = c_close(saved_stdin)
      ret = c_close(saved_stdout)
      ret = c_close(saved_stderr)
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if

  contains
    subroutine setenv(name, value, overwrite)
      character(*), intent(in) :: name, value
      integer, intent(in) :: overwrite
      ! Simple setenv - would need proper implementation
      call execute_command_line('export ' // trim(name) // '=' // trim(value), exitstat=status)
    end subroutine setenv

    subroutine evaluate_arithmetic_expr(expr, error_status, result_value)
      character(*), intent(in) :: expr
      integer, intent(out) :: error_status
      real, intent(out) :: result_value
      integer :: i, j, k
      character(256) :: clean_expr, token
      real :: lhs, rhs
      character :: op

      ! Simplified arithmetic evaluator
      ! Handles basic operations: +, -, *, /, %
      ! TODO: Full expression evaluation with parentheses, etc.

      error_status = 0
      result_value = 0.0

      ! Remove spaces
      clean_expr = ''
      do i = 1, len_trim(expr)
        if (expr(i:i) /= ' ') then
          clean_expr = trim(clean_expr) // expr(i:i)
        end if
      end do

      ! Look for operators (simple left-to-right evaluation)
      ! Find first operator
      do i = 1, len_trim(clean_expr)
        if (index('+-*/%', clean_expr(i:i)) > 0 .and. i > 1) then
          ! Found operator
          op = clean_expr(i:i)

          ! Parse left side
          read(clean_expr(1:i-1), *, iostat=j) lhs
          if (j /= 0) then
            error_status = 1
            return
          end if

          ! Parse right side
          read(clean_expr(i+1:), *, iostat=j) rhs
          if (j /= 0) then
            error_status = 1
            return
          end if

          ! Perform operation
          select case(op)
          case('+')
            result_value = lhs + rhs
          case('-')
            result_value = lhs - rhs
          case('*')
            result_value = lhs * rhs
          case('/')
            if (abs(rhs) < 1e-10) then
              error_status = 1
              return
            end if
            result_value = lhs / rhs
          case('%')
            result_value = real(mod(int(lhs), int(rhs)))
          end select

          return
        end if
      end do

      ! No operator found - just a number
      read(clean_expr, *, iostat=j) result_value
      if (j /= 0) error_status = 1

    end subroutine evaluate_arithmetic_expr

  end function evaluator_eval_command

  ! Eval pipeline - chain commands with pipes
  function evaluator_eval_pipeline(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(pipeline_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(4096) :: pipeline_cmd
    character(1024) :: cmd_str
    integer :: i, j
    character(:), allocatable :: word_value
    integer(c_int) :: status

    exit_code = 0
    pipeline_cmd = ''

    ! Build the pipeline command string
    do i = 1, node%num_commands
      if (associated(node%commands(i)%ptr)) then
        ! Build this command's string
        cmd_str = ''

        select type(cmd => node%commands(i)%ptr)
        type is (command_node_t)
          if (allocated(cmd%words)) then
            do j = 1, cmd%num_words
              if (associated(cmd%words(j)%ptr)) then
                word_value = self%eval_word(cmd%words(j)%ptr)
                if (j > 1) then
                  cmd_str = trim(cmd_str) // ' ' // trim(word_value)
                else
                  cmd_str = trim(word_value)
                end if
              end if
            end do
          end if
        end select

        ! Add to pipeline
        if (i > 1) then
          pipeline_cmd = trim(pipeline_cmd) // ' | ' // trim(cmd_str)
        else
          pipeline_cmd = trim(cmd_str)
        end if
      end if
    end do

    ! Check if this is a background pipeline
    if (node%background) then
      ! Execute as background job by appending &
      if (len_trim(pipeline_cmd) > 0) then
        status = c_system(trim(pipeline_cmd) // ' &' // c_null_char)
      end if
      ! Background jobs return immediately with exit code 0
      exit_code = 0
      if (associated(self%context%shell)) then
        self%context%shell%last_exit_status = 0
      end if
      return
    end if

    ! Execute the pipeline
    if (len_trim(pipeline_cmd) > 0) then
      status = c_system(trim(pipeline_cmd) // c_null_char)

      if (status < 0) then
        exit_code = 127
      else
        exit_code = status / 256
      end if
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_pipeline

  ! Eval logical AND (&&) - execute right only if left succeeds
  function evaluator_eval_and_list(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(and_list_node_t), pointer, intent(in) :: node
    integer :: exit_code

    exit_code = 0

    ! Execute left side
    if (associated(node%left%ptr)) then
      exit_code = self%eval_node(node%left%ptr)
    end if

    ! Only execute right side if left succeeded (exit_code == 0)
    if (exit_code == 0 .and. associated(node%right%ptr)) then
      exit_code = self%eval_node(node%right%ptr)
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_and_list

  ! Eval logical OR (||) - execute right only if left fails
  function evaluator_eval_or_list(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(or_list_node_t), pointer, intent(in) :: node
    integer :: exit_code

    exit_code = 0

    ! Execute left side
    if (associated(node%left%ptr)) then
      exit_code = self%eval_node(node%left%ptr)
    end if

    ! Only execute right side if left failed (exit_code /= 0)
    if (exit_code /= 0 .and. associated(node%right%ptr)) then
      exit_code = self%eval_node(node%right%ptr)
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_or_list

  ! Eval for loop
  function evaluator_eval_for_loop(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(for_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: i, j, k
    character(:), allocatable :: item_value
    character(256), allocatable :: glob_matches(:)
    integer :: match_count
    logical :: glob_success

    exit_code = 0

    if (allocated(node%word_list)) then
      do i = 1, node%num_words
        if (associated(node%word_list(i)%ptr)) then
          item_value = self%eval_word(node%word_list(i)%ptr)

          ! Check if word contains glob patterns
          if (self%has_glob_pattern(item_value)) then
            ! Expand glob pattern
            glob_success = self%expand_glob(item_value, glob_matches, match_count)
            if (glob_success .and. match_count > 0) then
              ! Process each glob match
              do k = 1, match_count
                call self%context%set_var(trim(node%variable), trim(glob_matches(k)))

                if (allocated(node%body)) then
                  do j = 1, node%num_body
                    if (associated(node%body(j)%ptr)) then
                      exit_code = self%eval_node(node%body(j)%ptr)

                      if (self%context%break_requested) then
                        if (self%context%break_levels <= 1) then
                          self%context%break_requested = .false.
                          self%context%break_levels = 0
                          return
                        else
                          self%context%break_levels = self%context%break_levels - 1
                          return
                        end if
                      end if

                      if (self%context%continue_requested) then
                        if (self%context%continue_levels <= 1) then
                          self%context%continue_requested = .false.
                          self%context%continue_levels = 0
                          exit
                        else
                          self%context%continue_levels = self%context%continue_levels - 1
                          return
                        end if
                      end if
                    end if
                  end do
                end if
              end do

              if (allocated(glob_matches)) deallocate(glob_matches)
            else
              ! No glob expansion - use original value
              call self%context%set_var(trim(node%variable), item_value)

              if (allocated(node%body)) then
                do j = 1, node%num_body
                  if (associated(node%body(j)%ptr)) then
                    exit_code = self%eval_node(node%body(j)%ptr)

                    if (self%context%break_requested) then
                      if (self%context%break_levels <= 1) then
                        self%context%break_requested = .false.
                        self%context%break_levels = 0
                        return
                      else
                        self%context%break_levels = self%context%break_levels - 1
                        return
                      end if
                    end if

                    if (self%context%continue_requested) then
                      if (self%context%continue_levels <= 1) then
                        self%context%continue_requested = .false.
                        self%context%continue_levels = 0
                        exit
                      else
                        self%context%continue_levels = self%context%continue_levels - 1
                        return
                      end if
                    end if
                  end if
                end do
              end if
            end if
          else
            ! No glob pattern - use original value
            call self%context%set_var(trim(node%variable), item_value)

            if (allocated(node%body)) then
              do j = 1, node%num_body
                if (associated(node%body(j)%ptr)) then
                  exit_code = self%eval_node(node%body(j)%ptr)

                if (self%context%break_requested) then
                  if (self%context%break_levels <= 1) then
                    self%context%break_requested = .false.
                    self%context%break_levels = 0
                    return
                  else
                    self%context%break_levels = self%context%break_levels - 1
                    return
                  end if
                end if

                if (self%context%continue_requested) then
                  if (self%context%continue_levels <= 1) then
                    self%context%continue_requested = .false.
                    self%context%continue_levels = 0
                    exit
                  else
                    self%context%continue_levels = self%context%continue_levels - 1
                    return
                  end if
                end if
              end if
            end do
            end if
          end if
        end if
      end do
    end if
  end function evaluator_eval_for_loop

  ! Eval arithmetic for loop
  function evaluator_eval_for_arith_loop(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(for_arith_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: j, cond_value
    character(:), allocatable :: cond_result

    exit_code = 0

    ! Evaluate init expression using bash arithmetic
    if (allocated(node%init_expr) .and. len_trim(node%init_expr) > 0) then
      cond_result = eval_arithmetic_expr(node%init_expr)
    end if

    ! Loop while condition is true
    do while (.true.)
      ! Evaluate condition expression
      if (allocated(node%cond_expr) .and. len_trim(node%cond_expr) > 0) then
        cond_result = eval_arithmetic_expr(node%cond_expr)
        read(cond_result, *, iostat=exit_code) cond_value
        if (exit_code /= 0 .or. cond_value == 0) exit
      else
        ! No condition means infinite loop
      end if

      ! Execute loop body
      if (allocated(node%body)) then
        do j = 1, node%num_body
          if (associated(node%body(j)%ptr)) then
            exit_code = self%eval_node(node%body(j)%ptr)

            if (self%context%break_requested) then
              if (self%context%break_levels <= 1) then
                self%context%break_requested = .false.
                self%context%break_levels = 0
                return
              else
                self%context%break_levels = self%context%break_levels - 1
                return
              end if
            end if

            if (self%context%continue_requested) then
              if (self%context%continue_levels <= 1) then
                self%context%continue_requested = .false.
                self%context%continue_levels = 0
                exit
              else
                self%context%continue_levels = self%context%continue_levels - 1
                return
              end if
            end if
          end if
        end do
      end if

      ! Evaluate increment expression
      if (allocated(node%incr_expr) .and. len_trim(node%incr_expr) > 0) then
        cond_result = eval_arithmetic_expr(node%incr_expr)
      end if
    end do

  contains
    ! Helper to evaluate arithmetic expressions (similar to eval_arithmetic but simpler)
    function eval_arithmetic_expr(expr) result(result)
      character(*), intent(in) :: expr
      character(:), allocatable :: result
      character(4096) :: expanded_expr, var_name, var_value
      integer :: i, j, k
      character(256) :: temp_file
      integer :: unit_num, ios
      character(4096) :: line
      integer(c_int) :: status
      character(kind=c_char, len=256) :: c_cmd

      ! Expand variables in the expression
      expanded_expr = ''
      i = 1
      do while (i <= len_trim(expr))
        if (expr(i:i) == '$') then
          j = i + 1
          if (j <= len_trim(expr) .and. expr(j:j) == '{') then
            j = j + 1
            k = j
            do while (k <= len_trim(expr) .and. expr(k:k) /= '}')
              k = k + 1
            end do
            var_name = expr(j:k-1)
            var_value = self%context%get_var(trim(var_name))
            if (len_trim(var_value) == 0) var_value = '0'
            expanded_expr = trim(expanded_expr) // trim(var_value)
            i = k + 1
          else
            k = j
            do while (k <= len_trim(expr))
              if (.not. ((expr(k:k) >= 'a' .and. expr(k:k) <= 'z') .or. &
                         (expr(k:k) >= 'A' .and. expr(k:k) <= 'Z') .or. &
                         (expr(k:k) >= '0' .and. expr(k:k) <= '9') .or. &
                         expr(k:k) == '_')) exit
              k = k + 1
            end do
            var_name = expr(j:k-1)
            if (len_trim(var_name) > 0) then
              var_value = self%context%get_var(trim(var_name))
              if (len_trim(var_value) == 0) var_value = '0'
              expanded_expr = trim(expanded_expr) // trim(var_value)
            else
              expanded_expr = trim(expanded_expr) // '$'
            end if
            i = k
          end if
        else
          expanded_expr = trim(expanded_expr) // expr(i:i)
          i = i + 1
        end if
      end do

      ! Evaluate using bash
      write(temp_file, '(a,i15,a)') '/tmp/fortsh_arith_', getpid(), '.tmp'
      c_cmd = 'echo $((' // trim(expanded_expr) // ')) > ' // trim(temp_file) // ' 2>/dev/null' // c_null_char
      status = c_system(c_cmd)

      open(newunit=unit_num, file=temp_file, status='old', action='read', iostat=ios)
      if (ios == 0) then
        read(unit_num, '(a)', iostat=ios) line
        if (ios == 0) then
          result = trim(line)
        else
          result = '0'
        end if
        close(unit_num)
      else
        result = '0'
      end if

      c_cmd = 'rm -f ' // trim(temp_file) // c_null_char
      status = c_system(c_cmd)
    end function eval_arithmetic_expr

    function getpid() result(pid)
      integer :: pid
      real :: rnum
      call random_seed()
      call random_number(rnum)
      pid = int(rnum * 99999) + 10000
    end function getpid

  end function evaluator_eval_for_arith_loop

  ! Eval while loop
  function evaluator_eval_while_loop(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(while_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    do while (.true.)
      if (associated(node%condition%ptr)) then
        exit_code = self%eval_node(node%condition%ptr)
        if (exit_code /= 0) exit
      end if

      if (allocated(node%body)) then
        do j = 1, node%num_body
          if (associated(node%body(j)%ptr)) then
            exit_code = self%eval_node(node%body(j)%ptr)

            if (self%context%break_requested) then
              if (self%context%break_levels <= 1) then
                self%context%break_requested = .false.
                self%context%break_levels = 0
                return
              else
                self%context%break_levels = self%context%break_levels - 1
                return
              end if
            end if

            if (self%context%continue_requested) then
              if (self%context%continue_levels <= 1) then
                self%context%continue_requested = .false.
                self%context%continue_levels = 0
                exit
              else
                self%context%continue_levels = self%context%continue_levels - 1
                return
              end if
            end if
          end if
        end do
      end if
    end do
  end function evaluator_eval_while_loop

  ! Eval if statement
  function evaluator_eval_if_statement(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(if_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: j

    exit_code = 0

    if (associated(node%condition%ptr)) then
      exit_code = self%eval_node(node%condition%ptr)
    end if

    if (exit_code == 0) then
      if (allocated(node%then_branch)) then
        do j = 1, node%num_then
          if (associated(node%then_branch(j)%ptr)) then
            exit_code = self%eval_node(node%then_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    else
      if (allocated(node%else_branch)) then
        do j = 1, node%num_else
          if (associated(node%else_branch(j)%ptr)) then
            exit_code = self%eval_node(node%else_branch(j)%ptr)
            if (self%context%return_requested) return
          end if
        end do
      end if
    end if
  end function evaluator_eval_if_statement

  ! Eval case statement
  function evaluator_eval_case_statement(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(case_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(:), allocatable :: expr_value
    integer :: i, j, k
    logical :: matched

    exit_code = 0

    ! Evaluate the expression
    if (associated(node%expr%ptr)) then
      expr_value = self%eval_word(node%expr%ptr)
    else
      expr_value = ''
    end if

    ! Try to match against each case item
    matched = .false.
    do i = 1, node%num_items
      if (matched) exit

      ! Check each pattern for this item
      do j = 1, node%items(i)%num_patterns
        if (allocated(node%items(i)%patterns)) then
          ! Simple pattern matching - support *, ?, and literal matches
          if (pattern_matches(trim(expr_value), trim(node%items(i)%patterns(j)))) then
            matched = .true.

            ! Execute commands for this case
            do k = 1, node%items(i)%num_commands
              if (associated(node%items(i)%commands(k)%ptr)) then
                exit_code = self%eval_node(node%items(i)%commands(k)%ptr)

                ! Check for break in case statement
                if (self%context%break_requested) then
                  self%context%break_requested = .false.
                  self%context%break_levels = 0
                  return
                end if

                if (self%context%return_requested) return
              end if
            end do
            exit  ! Exit pattern loop
          end if
        end if
      end do
    end do

  contains
    ! Simple pattern matching function
    logical function pattern_matches(str, pattern)
      character(*), intent(in) :: str, pattern
      integer :: i, j, pi, si

      ! Handle special patterns
      if (pattern == '*') then
        pattern_matches = .true.
        return
      end if

      ! Simple literal match for now (can be extended for glob patterns)
      pattern_matches = (str == pattern)

      ! Basic wildcard support
      if (index(pattern, '*') > 0 .or. index(pattern, '?') > 0) then
        pattern_matches = glob_match(str, pattern)
      end if
    end function pattern_matches

    ! Basic glob pattern matching
    logical function glob_match(str, pattern)
      character(*), intent(in) :: str, pattern
      integer :: si, pi, star_pos

      si = 1
      pi = 1
      star_pos = 0

      do while (si <= len_trim(str) .and. pi <= len_trim(pattern))
        if (pattern(pi:pi) == '*') then
          ! Found *, remember position and advance pattern
          star_pos = pi
          pi = pi + 1
          if (pi > len_trim(pattern)) then
            glob_match = .true.
            return
          end if
        else if (pattern(pi:pi) == '?' .or. pattern(pi:pi) == str(si:si)) then
          ! Character match or ?
          si = si + 1
          pi = pi + 1
        else if (star_pos > 0) then
          ! Mismatch but we have a *, backtrack
          pi = star_pos + 1
          si = si + 1
        else
          ! No match
          glob_match = .false.
          return
        end if
      end do

      ! Check if we consumed all of pattern (except trailing *)
      do while (pi <= len_trim(pattern) .and. pattern(pi:pi) == '*')
        pi = pi + 1
      end do

      glob_match = (pi > len_trim(pattern))
    end function glob_match

  end function evaluator_eval_case_statement

  ! Eval function definition - store function for later calls
  function evaluator_eval_function_definition(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(function_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: i

    exit_code = 0

    ! Store the function definition in the shell
    if (associated(self%context%shell)) then
      ! Find if function already exists
      do i = 1, self%context%shell%num_functions
        if (self%context%shell%functions(i)%name == node%name) then
          ! Replace existing function
          self%context%shell%functions(i)%body%ptr => node
          return
        end if
      end do

      ! Add new function
      if (self%context%shell%num_functions < size(self%context%shell%functions)) then
        self%context%shell%num_functions = self%context%shell%num_functions + 1
        i = self%context%shell%num_functions
        self%context%shell%functions(i)%name = node%name
        self%context%shell%functions(i)%body%ptr => node
      end if
    end if
  end function evaluator_eval_function_definition

  ! Eval function call - execute a stored function
  function evaluator_eval_function_call(self, func_name, args) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: func_name
    character(*), dimension(:), intent(in), optional :: args
    integer :: exit_code
    integer :: i, j
    type(function_node_t), pointer :: func_def
    character(256), dimension(100) :: saved_params
    integer :: saved_num_params
    character(256) :: saved_script_name

    exit_code = 127  ! Command not found

    ! Look for function definition
    if (associated(self%context%shell)) then
      do i = 1, self%context%shell%num_functions
        if (trim(self%context%shell%functions(i)%name) == trim(func_name)) then
          ! Found function - execute it
          select type(fnode => self%context%shell%functions(i)%body%ptr)
          type is (function_node_t)
            func_def => fnode

            ! Save current positional parameters and $0
            saved_params = self%context%shell%positional_params
            saved_num_params = self%context%shell%num_positional
            saved_script_name = self%context%shell%script_name

            ! Set new positional parameters from arguments
            self%context%shell%script_name = func_name
            if (present(args)) then
              self%context%shell%num_positional = min(size(args), 100)
              do j = 1, self%context%shell%num_positional
                self%context%shell%positional_params(j) = args(j)
              end do
            else
              self%context%shell%num_positional = 0
            end if

            ! Execute function body
            exit_code = 0
            do j = 1, func_def%num_body
              if (associated(func_def%body(j)%ptr)) then
                exit_code = self%eval_node(func_def%body(j)%ptr)

                ! Check for return statement
                if (self%context%return_requested) then
                  self%context%return_requested = .false.
                  exit
                end if
              end if
            end do

            ! Restore original positional parameters and $0
            self%context%shell%positional_params = saved_params
            self%context%shell%num_positional = saved_num_params
            self%context%shell%script_name = saved_script_name
          end select
          return
        end if
      end do
    end if
  end function evaluator_eval_function_call

  ! Eval subshell - execute commands in subshell environment
  ! Note: Full POSIX compliance would require fork(), but for now we execute in current context
  function evaluator_eval_subshell(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(subshell_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: i

    exit_code = 0

    ! Execute body statements
    if (allocated(node%body)) then
      do i = 1, node%num_body
        if (associated(node%body(i)%ptr)) then
          exit_code = self%eval_node(node%body(i)%ptr)

          ! Check for return (exits subshell)
          if (self%context%return_requested) then
            exit_code = self%context%return_value
            self%context%return_requested = .false.
            exit
          end if

          ! Check for break/continue (should not escape subshell)
          if (self%context%break_requested .or. self%context%continue_requested) then
            ! In a true subshell, break/continue would be contained
            ! For now, we'll let them propagate
            exit
          end if
        end if
      end do
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_subshell

  ! Eval group - execute commands in current shell environment
  function evaluator_eval_group(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(group_node_t), pointer, intent(in) :: node
    integer :: exit_code
    integer :: i

    exit_code = 0

    ! Execute body statements in current shell context
    if (allocated(node%body)) then
      do i = 1, node%num_body
        if (associated(node%body(i)%ptr)) then
          exit_code = self%eval_node(node%body(i)%ptr)

          ! Check for return
          if (self%context%return_requested) then
            exit_code = self%context%return_value
            exit
          end if

          ! Check for break/continue
          if (self%context%break_requested .or. self%context%continue_requested) then
            exit
          end if
        end if
      end do
    end if

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if
  end function evaluator_eval_group

  ! Eval break
  function evaluator_eval_break(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(break_node_t), pointer, intent(in) :: node
    integer :: exit_code

    self%context%break_requested = .true.
    self%context%break_levels = node%levels
    exit_code = 0
  end function evaluator_eval_break

  ! Eval continue
  function evaluator_eval_continue(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(continue_node_t), pointer, intent(in) :: node
    integer :: exit_code

    self%context%continue_requested = .true.
    self%context%continue_levels = node%levels
    exit_code = 0
  end function evaluator_eval_continue

  ! Eval word
  function evaluator_eval_word(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    type(variable_node_t), pointer :: var_ptr
    type(command_subst_node_t), pointer :: subst_ptr
    type(arithmetic_node_t), pointer :: arith_ptr
    type(proc_subst_node_t), pointer :: proc_ptr
    character(4096) :: output_buffer
    integer :: exit_code

    select type(node)
    type is (word_node_t)
      ! Apply brace expansion first (happens before other expansions)
      result = expand_braces(node%text)
      ! Then apply tilde expansion
      result = expand_tilde(self, result)

    type is (variable_node_t)
      var_ptr => node
      result = self%eval_variable(var_ptr)

    type is (command_subst_node_t)
      subst_ptr => node
      result = self%eval_command_subst(subst_ptr)

    type is (arithmetic_node_t)
      arith_ptr => node
      result = self%eval_arithmetic(arith_ptr)

    type is (proc_subst_node_t)
      proc_ptr => node
      result = self%eval_proc_subst(proc_ptr)

    class default
      result = ''
    end select
  end function evaluator_eval_word

  ! Eval variable
  function evaluator_eval_variable(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(variable_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(:), allocatable :: var_value, temp, index_val
    character(16) :: tmp
    integer :: param_num, i, ios, offset, length, pos
    integer :: arr_index, arr_status, elem_count
    logical :: is_set

    ! First, get the base variable value
    var_value = ''
    is_set = .false.

    ! Handle special variables
    select case(trim(node%name))
    case('?')
      ! Last exit status
      if (associated(self%context%shell)) then
        write(tmp, '(i15)') self%context%shell%last_exit_status
        var_value = trim(tmp)
      else
        var_value = '0'
      end if
      is_set = .true.

    case('#')
      ! Number of positional parameters
      if (associated(self%context%shell)) then
        write(tmp, '(i15)') self%context%shell%num_positional
        var_value = trim(tmp)
      else
        var_value = '0'
      end if
      is_set = .true.

    case('@')
      ! All positional parameters as separate words
      var_value = ''
      if (associated(self%context%shell)) then
        do i = 1, self%context%shell%num_positional
          if (i > 1) var_value = trim(var_value) // ' '
          var_value = trim(var_value) // trim(self%context%shell%positional_params(i))
        end do
      end if
      is_set = .true.

    case('*')
      ! All positional parameters as a single word
      var_value = ''
      if (associated(self%context%shell)) then
        do i = 1, self%context%shell%num_positional
          if (i > 1) var_value = trim(var_value) // ' '
          var_value = trim(var_value) // trim(self%context%shell%positional_params(i))
        end do
      end if
      is_set = .true.

    case('0')
      ! Script/command name
      if (associated(self%context%shell)) then
        var_value = trim(self%context%shell%script_name)
      else
        var_value = 'fortsh'
      end if
      is_set = .true.

    case('$')
      ! Process ID (simplified)
      call get_environment_variable('PPID', var_value)
      if (.not. allocated(var_value)) var_value = '0'
      is_set = .true.

    case('!')
      ! PID of last background command (not implemented)
      var_value = '0'
      is_set = .true.

    case('-')
      ! Current shell options (simplified)
      var_value = ''
      is_set = .true.

    case default
      ! Check if it's a numeric positional parameter
      read(node%name, *, iostat=ios) param_num
      if (ios == 0 .and. param_num > 0) then
        ! It's a positional parameter like $1, $2, etc.
        if (associated(self%context%shell)) then
          if (param_num <= self%context%shell%num_positional) then
            var_value = trim(self%context%shell%positional_params(param_num))
            is_set = .true.
          else
            var_value = ''
            is_set = .false.
          end if
        else
          var_value = ''
          is_set = .false.
        end if
      else
        ! Regular variable or array element
        ! Check for array indices expansion: ${!array[@]}
        if (node%get_indices) then
          ! Get array indices (keys) instead of values
          if (node%is_array_ref .and. allocated(node%index_expr)) then
            if (trim(node%index_expr) == '@' .or. trim(node%index_expr) == '*') then
              ! ${!array[@]} - get all array indices
              var_value = self%context%get_array_indices(trim(node%name))
              is_set = .true.
            else
              ! ${!array[index]} - not a standard bash feature, treat as empty
              var_value = ''
              is_set = .false.
            end if
          else
            ! ${!var} - indirect variable expansion (not implemented yet)
            var_value = ''
            is_set = .false.
          end if
        else if (node%is_array_ref .and. allocated(node%index_expr)) then
          ! Array element access: ${array[index]}, ${array[@]}, or ${array[*]}
          ! Check for special array expansions
          if (trim(node%index_expr) == '@' .or. trim(node%index_expr) == '*') then
            ! ${array[@]} or ${array[*]} - all elements
            var_value = self%context%get_array_all(trim(node%name))
            is_set = (len_trim(var_value) > 0)
          else
            ! Regular numeric index
            read(node%index_expr, *, iostat=arr_status) arr_index
            if (arr_status == 0) then
              var_value = self%context%get_array_element(trim(node%name), arr_index)
              is_set = (len_trim(var_value) > 0)
            else
              var_value = ''
              is_set = .false.
            end if
          end if
        else
          ! Regular scalar variable
          var_value = self%context%get_var(trim(node%name))
          is_set = (len_trim(var_value) > 0)
        end if
      end if
    end select

    ! Apply parameter expansion modifiers
    select case(node%modifier_type)
    case(MOD_NONE)
      result = var_value

    case(MOD_USE_DEFAULT)
      ! ${var:-default} - use default if unset or null
      if (.not. is_set .or. len_trim(var_value) == 0) then
        result = trim(node%modifier)
      else
        result = var_value
      end if

    case(MOD_ASSIGN_DEFAULT)
      ! ${var:=default} - assign and use default if unset or null
      if (.not. is_set .or. len_trim(var_value) == 0) then
        result = trim(node%modifier)
        call self%context%set_var(trim(node%name), result)
      else
        result = var_value
      end if

    case(MOD_ERROR_IF_UNSET)
      ! ${var:?error} - error if unset or null
      if (.not. is_set .or. len_trim(var_value) == 0) then
        if (len_trim(node%modifier) > 0) then
          write(error_unit, '(a)') trim(node%name) // ': ' // trim(node%modifier)
        else
          write(error_unit, '(a)') trim(node%name) // ': parameter null or not set'
        end if
        self%context%shell%last_exit_status = 1
        result = ''
      else
        result = var_value
      end if

    case(MOD_USE_ALTERNATE)
      ! ${var:+alternate} - use alternate if set and non-null
      if (is_set .and. len_trim(var_value) > 0) then
        result = trim(node%modifier)
      else
        result = ''
      end if

    case(MOD_STRING_LENGTH)
      ! ${#var} - string length or ${#array[@]} - array element count
      if (node%is_array_ref .and. allocated(node%index_expr)) then
        if (trim(node%index_expr) == '@' .or. trim(node%index_expr) == '*') then
          ! ${#array[@]} - array element count
          elem_count = self%context%get_array_count(trim(node%name))
          write(tmp, '(i15)') elem_count
          result = trim(tmp)
        else
          ! ${#array[0]} - length of specific element
          write(tmp, '(i15)') len_trim(var_value)
          result = trim(tmp)
        end if
      else
        ! ${#var} - string length
        write(tmp, '(i15)') len_trim(var_value)
        result = trim(tmp)
      end if

    case(MOD_SUBSTRING)
      ! ${var:offset:length} - substring or ${array[@]:offset:length} - array slice
      call parse_substring_params(node%modifier, offset, length)

      ! Check if this is array slicing
      if (node%is_array_ref .and. allocated(node%index_expr)) then
        if (trim(node%index_expr) == '@' .or. trim(node%index_expr) == '*') then
          ! ${array[@]:offset:length} - array slicing
          result = self%context%slice_array(trim(node%name), offset, length)
        else
          ! ${array[i]:offset:length} - substring of array element
          if (offset < 0) offset = len_trim(var_value) + offset + 1
          if (offset < 1) offset = 1
          if (offset > len_trim(var_value)) then
            result = ''
          else
            if (length < 0) then
              result = trim(var_value(offset:))
            else if (offset + length - 1 > len_trim(var_value)) then
              result = trim(var_value(offset:))
            else
              result = trim(var_value(offset:offset+length-1))
            end if
          end if
        end if
      else
        ! ${var:offset:length} - string substring
        if (offset < 0) offset = len_trim(var_value) + offset + 1
        if (offset < 1) offset = 1
        if (offset > len_trim(var_value)) then
          result = ''
        else
          if (length < 0) then
            result = trim(var_value(offset:))
          else if (offset + length - 1 > len_trim(var_value)) then
            result = trim(var_value(offset:))
          else
            result = trim(var_value(offset:offset+length-1))
          end if
        end if
      end if

    case(MOD_REMOVE_PREFIX_MIN)
      ! ${var#pattern} - remove shortest matching prefix
      result = remove_prefix(var_value, node%modifier, .false.)

    case(MOD_REMOVE_PREFIX_MAX)
      ! ${var##pattern} - remove longest matching prefix
      result = remove_prefix(var_value, node%modifier, .true.)

    case(MOD_REMOVE_SUFFIX_MIN)
      ! ${var%pattern} - remove shortest matching suffix
      result = remove_suffix(var_value, node%modifier, .false.)

    case(MOD_REMOVE_SUFFIX_MAX)
      ! ${var%%pattern} - remove longest matching suffix
      result = remove_suffix(var_value, node%modifier, .true.)

    case(MOD_REPLACE_FIRST, MOD_REPLACE_ALL, MOD_REPLACE_PREFIX, MOD_REPLACE_SUFFIX)
      ! ${var/pattern/replacement} and variants
      result = apply_replacement(var_value, node%modifier, node%modifier_type)

    case(MOD_UPPERCASE_FIRST)
      ! ${var^} - uppercase first character
      if (len_trim(var_value) > 0) then
        result = to_upper(var_value(1:1)) // var_value(2:)
      else
        result = var_value
      end if

    case(MOD_UPPERCASE_ALL)
      ! ${var^^} - uppercase all
      result = to_upper(var_value)

    case(MOD_LOWERCASE_FIRST)
      ! ${var,} - lowercase first character
      if (len_trim(var_value) > 0) then
        result = to_lower(var_value(1:1)) // var_value(2:)
      else
        result = var_value
      end if

    case(MOD_LOWERCASE_ALL)
      ! ${var,,} - lowercase all
      result = to_lower(var_value)

    case default
      result = var_value
    end select

  contains
    ! Parse substring parameters "offset:length"
    subroutine parse_substring_params(params, off, len)
      character(*), intent(in) :: params
      integer, intent(out) :: off, len
      integer :: colon_pos, ios

      off = 0
      len = -1  ! -1 means to end of string

      colon_pos = index(params, ':')
      if (colon_pos > 0) then
        read(params(1:colon_pos-1), *, iostat=ios) off
        if (colon_pos < len_trim(params)) then
          read(params(colon_pos+1:), *, iostat=ios) len
        end if
      else
        read(params, *, iostat=ios) off
      end if
    end subroutine parse_substring_params

  end function evaluator_eval_variable

  ! Eval command substitution - execute command and capture output
  function evaluator_eval_command_subst(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(command_subst_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(4096) :: cmd_str
    character(256) :: temp_file
    integer :: unit_num, ios, i
    character(4096) :: line
    character(:), allocatable :: output
    integer(c_int) :: status

    ! Build command string from the command node
    cmd_str = ''
    if (associated(node%command%ptr)) then
      select type(cmd => node%command%ptr)
      type is (command_node_t)
        if (allocated(cmd%words) .and. cmd%num_words > 0) then
          ! Build command from words
          do i = 1, cmd%num_words
            if (associated(cmd%words(i)%ptr)) then
              select type(w => cmd%words(i)%ptr)
              type is (word_node_t)
                if (i > 1) then
                  cmd_str = trim(cmd_str) // ' ' // trim(w%text)
                else
                  cmd_str = trim(w%text)
                end if
              end select
            end if
          end do
        end if
      end select
    end if

    ! Execute command and capture output using a temp file
    ! Generate temp filename
    write(temp_file, '(a,i15)') '/tmp/fortsh_subst_', getpid()

    ! Execute command with output redirection
    cmd_str = trim(cmd_str) // ' > ' // trim(temp_file) // ' 2>&1'
    status = c_system(trim(cmd_str) // c_null_char)

    ! Read the output from temp file
    open(newunit=unit_num, file=trim(temp_file), status='old', &
         action='read', iostat=ios)
    if (ios == 0) then
      output = ''
      do
        read(unit_num, '(a)', iostat=ios) line
        if (ios /= 0) exit
        if (allocated(output)) then
          output = output // ' ' // trim(line)
        else
          output = trim(line)
        end if
      end do
      close(unit_num)

      ! Remove trailing newlines/spaces
      if (allocated(output)) then
        result = trim(adjustl(output))
      else
        result = ''
      end if
    else
      result = ''
    end if

    ! Delete temp file
    call execute_command_line('rm -f ' // trim(temp_file))

  contains
    function getpid() result(pid)
      integer :: pid
      ! Simple pseudo-random number based on time
      real :: rnum
      call random_seed()
      call random_number(rnum)
      pid = int(rnum * 99999) + 10000
    end function getpid

  end function evaluator_eval_command_subst

  ! Eval arithmetic expression - evaluate arithmetic and return result as string
  function evaluator_eval_arithmetic(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(arithmetic_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(4096) :: expr, expanded_expr
    character(256) :: var_name, var_value
    integer :: i, j, k, value, total
    character(256) :: temp_file
    integer :: unit_num, ios
    character(4096) :: line
    character(:), allocatable :: output
    integer(c_int) :: status
    character(kind=c_char, len=256) :: c_cmd

    ! First, expand variables in the expression
    expanded_expr = ''
    i = 1
    do while (i <= len_trim(node%expression))
      if (node%expression(i:i) == '$') then
        ! Found a variable, extract its name
        j = i + 1
        ! Check if it's ${var} format
        if (j <= len_trim(node%expression) .and. node%expression(j:j) == '{') then
          j = j + 1
          k = j
          do while (k <= len_trim(node%expression) .and. node%expression(k:k) /= '}')
            k = k + 1
          end do
          var_name = node%expression(j:k-1)
          var_value = self%context%get_var(trim(var_name))
          ! If variable is empty, use 0
          if (len_trim(var_value) == 0) var_value = '0'
          expanded_expr = trim(expanded_expr) // trim(var_value)
          i = k + 1
        else
          ! Simple $var format
          k = j
          do while (k <= len_trim(node%expression))
            if (.not. (node%expression(k:k) >= 'a' .and. node%expression(k:k) <= 'z' .or. &
                       node%expression(k:k) >= 'A' .and. node%expression(k:k) <= 'Z' .or. &
                       node%expression(k:k) >= '0' .and. node%expression(k:k) <= '9' .or. &
                       node%expression(k:k) == '_')) exit
            k = k + 1
          end do
          var_name = node%expression(j:k-1)
          if (len_trim(var_name) > 0) then
            var_value = self%context%get_var(trim(var_name))
            if (len_trim(var_value) == 0) var_value = '0'
            expanded_expr = trim(expanded_expr) // trim(var_value)
          else
            expanded_expr = trim(expanded_expr) // '$'
          end if
          i = k
        end if
      else
        expanded_expr = trim(expanded_expr) // node%expression(i:i)
        i = i + 1
      end if
    end do

    ! Now evaluate the arithmetic expression
    ! Try using expr, bash arithmetic, or awk
    write(temp_file, '(a,i15,a)') '/tmp/fortsh_arith_', getpid(), '.tmp'

    ! Try using bash arithmetic expansion first
    c_cmd = 'echo $((' // trim(expanded_expr) // ')) > ' // trim(temp_file) // ' 2>/dev/null' // c_null_char
    status = c_system(c_cmd)

    ! Read the result
    output = ''
    open(newunit=unit_num, file=temp_file, status='old', &
         action='read', iostat=ios)
    if (ios == 0) then
      read(unit_num, '(a)', iostat=ios) line
      if (ios == 0) then
        output = trim(line)
      end if
      close(unit_num)
    end if

    ! Clean up temp file
    c_cmd = 'rm -f ' // trim(temp_file) // c_null_char
    status = c_system(c_cmd)

    ! If bc failed or returned empty, try simple evaluation
    if (len_trim(output) == 0) then
      ! Very simple fallback - just try to parse as integer
      read(expanded_expr, *, iostat=ios) value
      if (ios == 0) then
        write(line, '(i15)') value
        output = trim(line)
      else
        output = '0'
      end if
    end if

    result = trim(output)

  contains
    function getpid() result(pid)
      integer :: pid
      real :: rnum
      call random_seed()
      call random_number(rnum)
      pid = int(rnum * 99999) + 10000
    end function getpid

  end function evaluator_eval_arithmetic

  ! Eval conditional expression [[ ]] - returns 0 for true, 1 for false
  function evaluator_eval_cond_expr(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    class(ast_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(:), allocatable :: expr
    type(cond_expr_node_t), pointer :: cond_node

    exit_code = 1  ! Default to false

    ! Cast to conditional expression node
    select type(node)
    type is (cond_expr_node_t)
      cond_node => node
      if (allocated(cond_node%expression)) then
        expr = trim(cond_node%expression)
        exit_code = eval_cond_expression(self, expr)
      end if
    end select

    ! Update shell exit status
    if (associated(self%context%shell)) then
      self%context%shell%last_exit_status = exit_code
    end if

  contains
    ! Recursive function to evaluate conditional expressions
    recursive function eval_cond_expression(evaluator, expression) result(result_code)
      type(evaluator_simple_real_t), intent(inout) :: evaluator
      character(*), intent(in) :: expression
      integer :: result_code
      character(:), allocatable :: left, right, op, val
      integer :: i, j, paren_depth, val1, val2, ios
      logical :: file_exists, match
      character(kind=c_char, len=256) :: c_path
      integer(c_int) :: access_result
      integer :: file_size
      character(:), allocatable :: expanded_left, expanded_right
      ! Regex matching support for =~ operator
      type(regex_t) :: regex
      character(kind=c_char, len=:), allocatable :: c_pattern, c_string
      integer(c_int) :: comp_result, exec_result
      type(regmatch_t) :: pmatch(10)  ! Capture up to 9 groups + full match
      integer :: nmatch, match_idx, match_start, match_end
      character(:), allocatable :: matched_str

      result_code = 1  ! Default to false
      if (len_trim(expression) == 0) return

      ! Handle logical operators && and ||
      ! Find && or || at the top level (not in parentheses)
      paren_depth = 0
      do i = 1, len_trim(expression) - 1
        if (expression(i:i) == '(') then
          paren_depth = paren_depth + 1
        else if (expression(i:i) == ')') then
          paren_depth = paren_depth - 1
        else if (paren_depth == 0) then
          if (expression(i:i+1) == '&&') then
            left = trim(expression(1:i-1))
            right = trim(expression(i+2:))
            ! Evaluate left && right
            result_code = eval_cond_expression(evaluator, left)
            if (result_code == 0) then
              result_code = eval_cond_expression(evaluator, right)
            end if
            return
          else if (expression(i:i+1) == '||') then
            left = trim(expression(1:i-1))
            right = trim(expression(i+2:))
            ! Evaluate left || right
            result_code = eval_cond_expression(evaluator, left)
            if (result_code /= 0) then
              result_code = eval_cond_expression(evaluator, right)
            end if
            return
          end if
        end if
      end do

      ! Handle parentheses
      if (expression(1:1) == '(' .and. expression(len_trim(expression):len_trim(expression)) == ')') then
        result_code = eval_cond_expression(evaluator, expression(2:len_trim(expression)-1))
        return
      end if

      ! Handle negation !
      if (expression(1:1) == '!') then
        result_code = eval_cond_expression(evaluator, trim(expression(2:)))
        result_code = merge(0, 1, result_code /= 0)
        return
      end if

      ! Parse the expression into tokens (simplified)
      ! Expected forms:
      ! -f file, -d file, -e file, -r file, -w file, -x file, -s file
      ! -z string, -n string
      ! string == string, string != string
      ! num -eq num, num -ne num, num -lt num, num -le num, num -gt num, num -ge num

      call tokenize_expr(expression, left, op, right)

      ! Unary operators
      if (len_trim(right) == 0) then
        select case(trim(left))
        case('-z')
          ! True if string is empty
          val = expand_word(evaluator, trim(op))
          result_code = merge(0, 1, len_trim(val) == 0)
        case('-n')
          ! True if string is not empty
          val = expand_word(evaluator, trim(op))
          result_code = merge(0, 1, len_trim(val) > 0)
        case('-f')
          ! True if file exists and is regular file
          val = expand_word(evaluator, trim(op))
          inquire(file=trim(val), exist=file_exists)
          result_code = merge(0, 1, file_exists)
        case('-d')
          ! True if file exists and is directory
          val = expand_word(evaluator, trim(op))
          c_path = trim(val) // c_null_char
          access_result = c_access(c_path, F_OK)
          ! Simple check - if exists, assume directory if file check fails
          if (access_result == 0) then
            inquire(file=trim(val), exist=file_exists)
            ! If exists but not a regular file, assume directory
            result_code = 0
          else
            result_code = 1
          end if
        case('-e')
          ! True if file exists
          val = expand_word(evaluator, trim(op))
          c_path = trim(val) // c_null_char
          access_result = c_access(c_path, F_OK)
          result_code = merge(0, 1, access_result == 0)
        case('-r')
          ! True if file is readable
          val = expand_word(evaluator, trim(op))
          c_path = trim(val) // c_null_char
          access_result = c_access(c_path, R_OK)
          result_code = merge(0, 1, access_result == 0)
        case('-w')
          ! True if file is writable
          val = expand_word(evaluator, trim(op))
          c_path = trim(val) // c_null_char
          access_result = c_access(c_path, W_OK)
          result_code = merge(0, 1, access_result == 0)
        case('-x')
          ! True if file is executable
          val = expand_word(evaluator, trim(op))
          c_path = trim(val) // c_null_char
          access_result = c_access(c_path, X_OK)
          result_code = merge(0, 1, access_result == 0)
        case('-s')
          ! True if file has size > 0
          val = expand_word(evaluator, trim(op))
          inquire(file=trim(val), exist=file_exists, size=file_size)
          result_code = merge(0, 1, file_exists .and. file_size > 0)
        case default
          ! Check if just a string (non-empty test)
          val = expand_word(evaluator, trim(left))
          result_code = merge(0, 1, len_trim(val) > 0)
        end select
        return
      end if

      ! Binary operators
      expanded_left = expand_word(evaluator, trim(left))
      expanded_right = expand_word(evaluator, trim(right))

      select case(trim(op))
      ! String comparisons
      case('==', '=')
        ! Check for pattern matching
        if (index(expanded_right, '*') > 0 .or. index(expanded_right, '?') > 0) then
          ! Pattern matching
          match = pattern_match(expanded_left, expanded_right)
          result_code = merge(0, 1, match)
        else
          ! Literal string comparison
          result_code = merge(0, 1, trim(expanded_left) == trim(expanded_right))
        end if

      case('!=')
        ! Check for pattern matching with negation
        if (index(expanded_right, '*') > 0 .or. index(expanded_right, '?') > 0) then
          ! Pattern matching
          match = pattern_match(expanded_left, expanded_right)
          result_code = merge(0, 1, .not. match)
        else
          ! Literal string comparison
          result_code = merge(0, 1, trim(expanded_left) /= trim(expanded_right))
        end if

      case('=~')
        ! Regex matching - [[ $str =~ pattern ]]
        ! expanded_left is the string to match
        ! expanded_right is the regex pattern

        ! Prepare C strings (null-terminated)
        c_pattern = trim(expanded_right) // c_null_char
        c_string = trim(expanded_left) // c_null_char

        ! Compile the regex pattern (use extended regex)
        comp_result = c_regcomp(regex, c_pattern, REG_EXTENDED)

        if (comp_result == 0) then
          ! Pattern compiled successfully - now execute it with capture groups
          exec_result = c_regexec(regex, c_string, 10_c_size_t, pmatch, 0_c_int)

          if (exec_result == 0) then
            ! Match found - populate BASH_REMATCH array
            ! First, declare the array
            call evaluator%context%declare_array('BASH_REMATCH')

            ! Populate captured groups
            nmatch = 0
            do match_idx = 0, 9
              ! Check if this match is valid (rm_so != -1)
              if (pmatch(match_idx + 1)%rm_so /= -1) then
                match_start = pmatch(match_idx + 1)%rm_so + 1  ! Convert to 1-based
                match_end = pmatch(match_idx + 1)%rm_eo

                ! Extract matched substring
                matched_str = ''
                if (match_end > match_start - 1) then
                  matched_str = expanded_left(match_start:match_end)
                end if

                ! Store in BASH_REMATCH[match_idx]
                call evaluator%context%set_array_element('BASH_REMATCH', match_idx, matched_str)
                nmatch = match_idx + 1
              else
                ! No more matches
                exit
              end if
            end do
          end if

          ! Clean up regex
          call c_regfree(regex)

          ! exec_result == 0 means match found
          result_code = merge(0, 1, exec_result == 0)
        else
          ! Pattern compilation failed - treat as no match
          call c_regfree(regex)
          result_code = 2  ! Error code
        end if

      ! Integer comparisons
      case('-eq')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 == val2)

      case('-ne')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 /= val2)

      case('-lt')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 < val2)

      case('-le')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 <= val2)

      case('-gt')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 > val2)

      case('-ge')
        read(expanded_left, *, iostat=ios) val1
        if (ios /= 0) then
          result_code = 2
          return
        end if
        read(expanded_right, *, iostat=ios) val2
        if (ios /= 0) then
          result_code = 2
          return
        end if
        result_code = merge(0, 1, val1 >= val2)

      case default
        result_code = 2  ! Syntax error
      end select
    end function eval_cond_expression

    ! Tokenize expression into left, operator, right
    subroutine tokenize_expr(expr, left, op, right)
      character(*), intent(in) :: expr
      character(:), allocatable, intent(out) :: left, op, right
      integer :: i, j, start
      logical :: in_word

      left = ''
      op = ''
      right = ''

      ! Skip leading spaces
      i = 1
      do while (i <= len_trim(expr) .and. expr(i:i) == ' ')
        i = i + 1
      end do

      ! Get first token (left or unary operator)
      start = i
      do while (i <= len_trim(expr) .and. expr(i:i) /= ' ')
        i = i + 1
      end do
      left = expr(start:i-1)

      ! Skip spaces
      do while (i <= len_trim(expr) .and. expr(i:i) == ' ')
        i = i + 1
      end do

      if (i > len_trim(expr)) return  ! Only one token (unary)

      ! Get operator/second token
      start = i
      do while (i <= len_trim(expr) .and. expr(i:i) /= ' ')
        i = i + 1
      end do
      op = expr(start:i-1)

      ! Skip spaces
      do while (i <= len_trim(expr) .and. expr(i:i) == ' ')
        i = i + 1
      end do

      if (i > len_trim(expr)) return  ! Only two tokens

      ! Get right operand (rest of expression)
      right = trim(expr(i:))
    end subroutine tokenize_expr

    ! Expand variables in a word
    function expand_word(evaluator, word) result(expanded)
      type(evaluator_simple_real_t), intent(inout) :: evaluator
      character(*), intent(in) :: word
      character(:), allocatable :: expanded
      character(256) :: var_name
      integer :: i, j, k

      if (len_trim(word) == 0) then
        expanded = ''
        return
      end if

      ! Check for variable expansion
      if (word(1:1) == '$') then
        i = 2
        ! Handle ${var} or $var
        if (i <= len_trim(word) .and. word(i:i) == '{') then
          i = i + 1
          j = i
          do while (j <= len_trim(word) .and. word(j:j) /= '}')
            j = j + 1
          end do
          var_name = word(i:j-1)
          expanded = evaluator%context%get_var(trim(var_name))
        else
          ! Simple $var format
          j = i
          do while (j <= len_trim(word))
            if (.not. ((word(j:j) >= 'a' .and. word(j:j) <= 'z') .or. &
                       (word(j:j) >= 'A' .and. word(j:j) <= 'Z') .or. &
                       (word(j:j) >= '0' .and. word(j:j) <= '9') .or. &
                       word(j:j) == '_')) exit
            j = j + 1
          end do
          var_name = word(i:j-1)
          if (len_trim(var_name) > 0) then
            expanded = evaluator%context%get_var(trim(var_name))
          else
            expanded = word
          end if
        end if
      else
        expanded = word
      end if
    end function expand_word

    ! Pattern matching for [[ ]] expressions
    logical function pattern_match(str, pattern)
      character(*), intent(in) :: str, pattern
      integer :: si, pi, star_idx, s_idx

      si = 1
      pi = 1
      star_idx = 0
      s_idx = 0

      do while (si <= len_trim(str))
        if (pi <= len_trim(pattern)) then
          if (pattern(pi:pi) == '*') then
            star_idx = pi
            s_idx = si
            pi = pi + 1
          else if (pattern(pi:pi) == '?' .or. pattern(pi:pi) == str(si:si)) then
            si = si + 1
            pi = pi + 1
          else if (star_idx > 0) then
            pi = star_idx + 1
            s_idx = s_idx + 1
            si = s_idx
          else
            pattern_match = .false.
            return
          end if
        else if (star_idx > 0) then
          pi = star_idx + 1
          s_idx = s_idx + 1
          si = s_idx
        else
          pattern_match = .false.
          return
        end if
      end do

      ! Skip trailing *
      do while (pi <= len_trim(pattern) .and. pattern(pi:pi) == '*')
        pi = pi + 1
      end do

      pattern_match = (pi > len_trim(pattern))
    end function pattern_match

  end function evaluator_eval_cond_expr

  ! Eval process substitution - create named pipe and execute command
  function evaluator_eval_proc_subst(self, node) result(result)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(proc_subst_node_t), pointer, intent(in) :: node
    character(:), allocatable :: result
    character(256) :: pipe_path
    character(4096) :: cmd_str
    integer(c_int) :: pid, ret, new_fd, flags
    integer :: i
    real :: rnum

    ! Generate unique pipe path
    call random_number(rnum)
    write(pipe_path, '(a,i15)') '/tmp/fortsh_proc_', int(rnum * 999999) + 100000

    ! Create named pipe (FIFO)
    ret = c_mkfifo(trim(pipe_path) // c_null_char, int(o'666', c_int))
    if (ret /= 0) then
      ! Failed to create pipe - return empty string
      result = ''
      return
    end if

    ! Fork child process to execute the command
    pid = c_fork()

    if (pid < 0) then
      ! Fork failed - clean up and return empty string
      ret = c_unlink(trim(pipe_path) // c_null_char)
      result = ''
      return

    else if (pid == 0) then
      ! ===== CHILD PROCESS =====

      ! Build command string from the command node
      cmd_str = ''
      if (associated(node%command%ptr)) then
        select type(cmd => node%command%ptr)
        type is (command_node_t)
          if (allocated(cmd%words) .and. cmd%num_words > 0) then
            ! Build command from words
            do i = 1, cmd%num_words
              if (associated(cmd%words(i)%ptr)) then
                select type(w => cmd%words(i)%ptr)
                type is (word_node_t)
                  if (i > 1) then
                    cmd_str = trim(cmd_str) // ' ' // trim(w%text)
                  else
                    cmd_str = trim(w%text)
                  end if
                end select
              end if
            end do
          end if
        end select
      end if

      ! Open the pipe and redirect I/O
      if (node%is_input) then
        ! <(command) - redirect command's stdout to the pipe
        ! Parent will read from the pipe
        flags = O_WRONLY
        new_fd = c_open(trim(pipe_path) // c_null_char, flags, 0_c_int)
        if (new_fd >= 0) then
          ! Redirect stdout to pipe
          ret = c_dup2(new_fd, 1_c_int)
          ret = c_close(new_fd)
        end if
      else
        ! >(command) - redirect pipe to command's stdin
        ! Parent will write to the pipe
        flags = O_RDONLY
        new_fd = c_open(trim(pipe_path) // c_null_char, flags, 0_c_int)
        if (new_fd >= 0) then
          ! Redirect stdin from pipe
          ret = c_dup2(new_fd, 0_c_int)
          ret = c_close(new_fd)
        end if
      end if

      ! Execute the command
      if (len_trim(cmd_str) > 0) then
        ret = c_system(trim(cmd_str) // c_null_char)
      end if

      ! Child exits (use _exit for forked processes)
      call c_exit(0_c_int)

    else
      ! ===== PARENT PROCESS =====
      ! Return the pipe path - the parent command will use it as a filename
      result = trim(pipe_path)

      ! Note: We don't wait for the child here. The child will run concurrently.
      ! The parent command will open the pipe, which will block until the child
      ! opens the other end. After the parent command finishes reading/writing,
      ! both ends will close and the child will exit.
      !
      ! TODO: Track the PID and pipe_path for cleanup after the parent command completes
    end if

  end function evaluator_eval_proc_subst

  ! Check if string contains glob patterns
  function evaluator_has_glob_pattern(self, str) result(has_pattern)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: str
    logical :: has_pattern
    integer :: i

    has_pattern = .false.
    do i = 1, len_trim(str)
      if (str(i:i) == '*' .or. str(i:i) == '?' .or. str(i:i) == '[') then
        has_pattern = .true.
        return
      end if
    end do
  end function evaluator_has_glob_pattern

  ! Expand glob pattern to list of files
  function evaluator_expand_glob(self, pattern, matches, match_count) result(success)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: pattern
    character(256), allocatable, intent(out) :: matches(:)
    integer, intent(out) :: match_count
    logical :: success
    type(glob_t) :: pglob
    integer(c_int) :: status
    type(c_ptr), dimension(:), pointer :: pathv_array
    type(c_ptr) :: path_ptr
    character(kind=c_char), pointer :: path_chars(:)
    character(256) :: temp_str
    integer :: i, j

    success = .false.
    match_count = 0

    ! Call glob with pattern
    status = c_glob(trim(pattern) // c_null_char, 0, c_null_funptr, pglob)

    if (status == 0 .and. pglob%gl_pathc > 0) then
      match_count = int(pglob%gl_pathc)
      allocate(matches(match_count))

      ! Access the path array
      call c_f_pointer(pglob%gl_pathv, pathv_array, [int(pglob%gl_pathc)])

      do i = 1, match_count
        path_ptr = pathv_array(i)
        if (c_associated(path_ptr)) then
          ! Convert C string to Fortran string
          call c_f_pointer(path_ptr, path_chars, [256])
          temp_str = ''
          do j = 1, 256
            if (path_chars(j) == c_null_char) exit
            temp_str(j:j) = path_chars(j)
          end do
          matches(i) = temp_str
        end if
      end do
      success = .true.

      ! Free glob resources
      call c_globfree(pglob)
    else
      ! No matches or glob failed - return original pattern
      match_count = 1
      allocate(matches(1))
      matches(1) = pattern
      success = .true.
      if (status == 0) call c_globfree(pglob)
    end if
  end function evaluator_expand_glob

  ! Destroy evaluator
  subroutine evaluator_destroy(self)
    class(evaluator_simple_real_t), intent(inout) :: self

    call self%context%destroy()
  end subroutine evaluator_destroy

  ! Helper function for test builtin
  function call_test_builtin(self, node) result(exit_code)
    class(evaluator_simple_real_t), intent(inout) :: self
    type(command_node_t), pointer, intent(in) :: node
    integer :: exit_code
    character(:), allocatable :: arg1, arg2, arg3
    character(kind=c_char, len=256) :: c_path
    integer(c_int) :: access_result, chdir_result
    integer :: val1, val2, ios, file_size
    logical :: file_exists
    character(kind=c_char, len=256) :: old_cwd
    type(c_ptr) :: getcwd_result

    exit_code = 0

    ! Handle empty test (test with no args returns false)
    if (node%num_words == 1) then
      exit_code = 1
      return
    end if

    ! Single argument: test if non-empty string
    if (node%num_words == 2) then
      if (associated(node%words(2)%ptr)) then
        arg1 = self%eval_word(node%words(2)%ptr)
        if (len_trim(arg1) > 0) then
          exit_code = 0
        else
          exit_code = 1
        end if
      else
        exit_code = 1
      end if
      return
    end if

    ! Two arguments: unary operator
    if (node%num_words == 3) then
      if (associated(node%words(2)%ptr)) arg1 = self%eval_word(node%words(2)%ptr)
      if (associated(node%words(3)%ptr)) arg2 = self%eval_word(node%words(3)%ptr)

      select case(trim(arg1))
      ! String tests
      case('-z')
        ! True if string is empty
        exit_code = merge(0, 1, len_trim(arg2) == 0)

      case('-n')
        ! True if string is not empty
        exit_code = merge(0, 1, len_trim(arg2) > 0)

      ! File tests
      case('-e')
        ! True if file exists
        c_path = trim(arg2) // c_null_char
        access_result = c_access(c_path, F_OK)
        exit_code = merge(0, 1, access_result == 0)

      case('-f')
        ! True if file exists and is regular file
        inquire(file=trim(arg2), exist=file_exists)
        exit_code = merge(0, 1, file_exists)

      case('-d')
        ! True if file exists and is directory
        ! Try to access as directory by checking if we can chdir to it
        old_cwd = ''
        getcwd_result = c_getcwd(old_cwd, 256_c_size_t)
        c_path = trim(arg2) // c_null_char
        chdir_result = c_chdir(c_path)
        if (chdir_result == 0) then
          exit_code = 0
          ! Restore directory
          chdir_result = c_chdir(old_cwd)
        else
          exit_code = 1
        end if

      case('-r')
        ! True if file exists and is readable
        c_path = trim(arg2) // c_null_char
        access_result = c_access(c_path, R_OK)
        exit_code = merge(0, 1, access_result == 0)

      case('-w')
        ! True if file exists and is writable
        c_path = trim(arg2) // c_null_char
        access_result = c_access(c_path, W_OK)
        exit_code = merge(0, 1, access_result == 0)

      case('-x')
        ! True if file exists and is executable
        c_path = trim(arg2) // c_null_char
        access_result = c_access(c_path, X_OK)
        exit_code = merge(0, 1, access_result == 0)

      case('-s')
        ! True if file exists and has size > 0
        inquire(file=trim(arg2), exist=file_exists, size=file_size)
        exit_code = merge(0, 1, file_exists .and. file_size > 0)

      case('!')
        ! Negation - run test on arg2 and invert result
        exit_code = merge(1, 0, len_trim(arg2) > 0)

      case default
        exit_code = 2  ! Syntax error
      end select
      return
    end if

    ! Three arguments: binary operator
    if (node%num_words == 4) then
      if (associated(node%words(2)%ptr)) arg1 = self%eval_word(node%words(2)%ptr)
      if (associated(node%words(3)%ptr)) arg2 = self%eval_word(node%words(3)%ptr)
      if (associated(node%words(4)%ptr)) arg3 = self%eval_word(node%words(4)%ptr)

      select case(trim(arg2))
      ! String comparisons
      case('=', '==')
        exit_code = merge(0, 1, trim(arg1) == trim(arg3))

      case('!=')
        exit_code = merge(0, 1, trim(arg1) /= trim(arg3))

      ! Integer comparisons
      case('-eq')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 == val2)

      case('-ne')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 /= val2)

      case('-lt')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 < val2)

      case('-le')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 <= val2)

      case('-gt')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 > val2)

      case('-ge')
        read(arg1, *, iostat=ios) val1
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        read(arg3, *, iostat=ios) val2
        if (ios /= 0) then
          exit_code = 2
          return
        end if
        exit_code = merge(0, 1, val1 >= val2)

      case default
        exit_code = 2  ! Syntax error
      end select
      return
    end if

    ! Four or more arguments: complex expressions (not fully supported yet)
    exit_code = 2
  end function call_test_builtin

  ! Helper functions for parameter expansion

  ! Convert string to uppercase
  function to_upper(str) result(upper)
    character(*), intent(in) :: str
    character(:), allocatable :: upper
    integer :: i, diff
    character(len(str)) :: temp

    diff = ichar('A') - ichar('a')
    temp = str
    do i = 1, len(str)
      if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
        temp(i:i) = char(ichar(str(i:i)) + diff)
      end if
    end do
    upper = temp
  end function to_upper

  ! Convert string to lowercase
  function to_lower(str) result(lower)
    character(*), intent(in) :: str
    character(:), allocatable :: lower
    integer :: i, diff
    character(len(str)) :: temp

    diff = ichar('a') - ichar('A')
    temp = str
    do i = 1, len(str)
      if (str(i:i) >= 'A' .and. str(i:i) <= 'Z') then
        temp(i:i) = char(ichar(str(i:i)) + diff)
      end if
    end do
    lower = temp
  end function to_lower

  ! Remove prefix pattern from string
  function remove_prefix(str, pattern, greedy) result(res)
    character(*), intent(in) :: str, pattern
    logical, intent(in) :: greedy
    character(:), allocatable :: res
    integer :: i, match_len

    res = str

    if (greedy) then
      ! Remove longest matching prefix
      do i = len_trim(str), 1, -1
        if (pattern_matches(str(1:i), pattern)) then
          if (i < len_trim(str)) then
            res = trim(str(i+1:))
          else
            res = ''
          end if
          return
        end if
      end do
    else
      ! Remove shortest matching prefix
      do i = 1, len_trim(str)
        if (pattern_matches(str(1:i), pattern)) then
          if (i < len_trim(str)) then
            res = trim(str(i+1:))
          else
            res = ''
          end if
          return
        end if
      end do
    end if
  end function remove_prefix

  ! Remove suffix pattern from string
  function remove_suffix(str, pattern, greedy) result(res)
    character(*), intent(in) :: str, pattern
    logical, intent(in) :: greedy
    character(:), allocatable :: res
    integer :: i, str_len, match_len

    res = str
    str_len = len_trim(str)

    if (greedy) then
      ! Remove longest matching suffix
      do i = 1, str_len
        if (pattern_matches(str(i:str_len), pattern)) then
          if (i > 1) then
            res = trim(str(1:i-1))
          else
            res = ''
          end if
          return
        end if
      end do
    else
      ! Remove shortest matching suffix
      do i = str_len, 1, -1
        if (pattern_matches(str(i:str_len), pattern)) then
          if (i > 1) then
            res = trim(str(1:i-1))
          else
            res = ''
          end if
          return
        end if
      end do
    end if
  end function remove_suffix

  ! Apply pattern replacement
  function apply_replacement(str, modifier, mod_type) result(res)
    character(*), intent(in) :: str, modifier
    integer, intent(in) :: mod_type
    character(:), allocatable :: res
    character(:), allocatable :: pattern, replacement
    integer :: slash_pos, i, str_len
    logical :: found

    ! Parse modifier as "pattern/replacement"
    slash_pos = index(modifier, '/')
    if (slash_pos > 0) then
      pattern = modifier(1:slash_pos-1)
      replacement = modifier(slash_pos+1:)
    else
      pattern = modifier
      replacement = ''
    end if

    res = str
    str_len = len_trim(str)

    select case(mod_type)
    case(MOD_REPLACE_FIRST)
      ! Replace first match
      do i = 1, str_len
        if (i + len(pattern) - 1 <= str_len) then
          if (pattern_matches(str(i:i+len(pattern)-1), pattern)) then
            res = str(1:i-1) // replacement // str(i+len(pattern):)
            return
          end if
        end if
      end do

    case(MOD_REPLACE_ALL)
      ! Replace all matches
      res = ''
      i = 1
      do while (i <= str_len)
        found = .false.
        if (i + len(pattern) - 1 <= str_len) then
          if (pattern_matches(str(i:i+len(pattern)-1), pattern)) then
            res = trim(res) // replacement
            i = i + len(pattern)
            found = .true.
          end if
        end if
        if (.not. found) then
          res = trim(res) // str(i:i)
          i = i + 1
        end if
      end do

    case(MOD_REPLACE_PREFIX)
      ! Replace at beginning
      if (str_len >= len(pattern)) then
        if (pattern_matches(str(1:len(pattern)), pattern)) then
          res = replacement // str(len(pattern)+1:)
        end if
      end if

    case(MOD_REPLACE_SUFFIX)
      ! Replace at end
      if (str_len >= len(pattern)) then
        if (pattern_matches(str(str_len-len(pattern)+1:str_len), pattern)) then
          res = str(1:str_len-len(pattern)) // replacement
        end if
      end if
    end select
  end function apply_replacement

  ! Simple pattern matching for glob-style patterns (* and ?)
  logical function pattern_matches(str, pattern)
    character(*), intent(in) :: str, pattern
    integer :: i, star_pos, str_len, before_len, after_len
    character(:), allocatable :: before_star, after_star

    pattern_matches = .false.
    str_len = len_trim(str)

    ! If pattern has no wildcards, do simple comparison
    if (index(pattern, '*') == 0 .and. index(pattern, '?') == 0) then
      pattern_matches = (trim(str) == trim(pattern))
      return
    end if

    ! Handle * wildcard
    star_pos = index(pattern, '*')
    if (star_pos > 0) then
      before_star = pattern(1:star_pos-1)
      after_star = pattern(star_pos+1:)
      before_len = len_trim(before_star)
      after_len = len_trim(after_star)

      ! Check if string is long enough
      if (str_len < before_len + after_len) return

      ! Check prefix
      if (before_len > 0) then
        if (str(1:before_len) /= trim(before_star)) return
      end if

      ! Check suffix
      if (after_len > 0) then
        if (str(str_len-after_len+1:str_len) /= trim(after_star)) return
      end if

      pattern_matches = .true.
      return
    end if

    ! Handle ? wildcard (single character)
    if (len(pattern) /= len(str)) return

    do i = 1, len(pattern)
      if (pattern(i:i) /= '?' .and. pattern(i:i) /= str(i:i)) then
        return
      end if
    end do

    pattern_matches = .true.
  end function pattern_matches

  ! Expand braces in words
  ! Examples:
  !   {a,b,c} → a b c
  !   {1..5} → 1 2 3 4 5
  !   {a..e} → a b c d e
  !   {1..10..2} → 1 3 5 7 9
  !   prefix{a,b}suffix → prefixa prefixasuffix prefixbsuffix (ENHANCED: now supports prefix/suffix!)
  !   {A,B{1,2},C} → A B{1,2} C (ENHANCED: respects nested braces!)
  function expand_braces(word) result(expanded)
    character(*), intent(in) :: word
    character(:), allocatable :: expanded
    integer :: brace_start, brace_end, comma_pos, dot_pos, depth, pos
    character(:), allocatable :: prefix, brace_content, suffix, item
    character(1024) :: result_buf
    integer :: i, start_val, end_val, step_val, current_val
    integer :: start_char, end_char, current_char
    integer :: comma_count, last_pos, item_start, second_dot
    logical :: is_numeric, is_alpha, has_step
    character(16) :: num_str
    character(:), allocatable :: start_str, end_str, step_str

    expanded = word
    result_buf = ''

    ! Find opening brace
    brace_start = index(word, '{')
    if (brace_start == 0) return

    ! Find MATCHING closing brace by counting depth (supports nested braces)
    depth = 0
    brace_end = 0
    do pos = brace_start, len_trim(word)
      if (word(pos:pos) == '{') then
        depth = depth + 1
      else if (word(pos:pos) == '}') then
        depth = depth - 1
        if (depth == 0) then
          brace_end = pos
          exit
        end if
      end if
    end do

    if (brace_end == 0) return

    ! Extract prefix, brace content, and suffix
    if (brace_start > 1) then
      prefix = word(1:brace_start-1)
    else
      prefix = ''
    end if

    brace_content = word(brace_start+1:brace_end-1)

    if (brace_end < len_trim(word)) then
      suffix = word(brace_end+1:)
    else
      suffix = ''
    end if
    if (len_trim(brace_content) == 0) return

    ! Check if it's a range expansion (contains ..)
    dot_pos = index(brace_content, '..')
    if (dot_pos > 0) then
      ! Range expansion: {start..end} or {start..end..step}

      ! Extract start
      start_str = brace_content(1:dot_pos-1)

      ! Check for step (second ..)
      second_dot = index(brace_content(dot_pos+2:), '..')
      has_step = (second_dot > 0)

      if (has_step) then
        ! {start..end..step}
        second_dot = dot_pos + 1 + second_dot
        end_str = brace_content(dot_pos+2:second_dot-1)
        step_str = brace_content(second_dot+2:)
        read(step_str, *, iostat=i) step_val
        if (i /= 0) then
          step_val = 1
        end if
      else
        ! {start..end}
        end_str = brace_content(dot_pos+2:)
        step_val = 1
      end if

      ! Check if numeric or alphabetic
      is_numeric = .false.
      is_alpha = .false.

      read(start_str, *, iostat=i) start_val
      if (i == 0) then
        ! Numeric range
        read(end_str, *, iostat=i) end_val
        if (i == 0) then
          is_numeric = .true.
        end if
      end if

      if (.not. is_numeric .and. len_trim(start_str) == 1 .and. len_trim(end_str) == 1) then
        ! Alphabetic range
        start_char = ichar(start_str(1:1))
        end_char = ichar(end_str(1:1))
        is_alpha = .true.
      end if

      if (is_numeric) then
        ! Numeric range expansion
        if (start_val <= end_val) then
          current_val = start_val
          do while (current_val <= end_val)
            write(num_str, '(i15)') current_val
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(num_str) // trim(suffix)
            else
              result_buf = trim(prefix) // trim(num_str) // trim(suffix)
            end if
            current_val = current_val + step_val
          end do
        else
          ! Descending range
          current_val = start_val
          do while (current_val >= end_val)
            write(num_str, '(i15)') current_val
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(num_str) // trim(suffix)
            else
              result_buf = trim(prefix) // trim(num_str) // trim(suffix)
            end if
            current_val = current_val - step_val
          end do
        end if
        expanded = trim(result_buf)
        return
      else if (is_alpha) then
        ! Alphabetic range expansion
        if (start_char <= end_char) then
          current_char = start_char
          do while (current_char <= end_char)
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // char(current_char) // trim(suffix)
            else
              result_buf = trim(prefix) // char(current_char) // trim(suffix)
            end if
            current_char = current_char + step_val
          end do
        else
          ! Descending range
          current_char = start_char
          do while (current_char >= end_char)
            if (len_trim(result_buf) > 0) then
              result_buf = trim(result_buf) // ' ' // trim(prefix) // char(current_char) // trim(suffix)
            else
              result_buf = trim(prefix) // char(current_char) // trim(suffix)
            end if
            current_char = current_char - step_val
          end do
        end if
        expanded = trim(result_buf)
        return
      end if
    else
      ! List expansion: {a,b,c} - respect nested braces when finding commas
      last_pos = 1
      depth = 0
      do i = 1, len_trim(brace_content)
        if (brace_content(i:i) == '{') then
          depth = depth + 1
        else if (brace_content(i:i) == '}') then
          depth = depth - 1
        else if (brace_content(i:i) == ',' .and. depth == 0) then
          ! Found a comma at depth 0 - extract item
          item = brace_content(last_pos:i-1)
          if (len_trim(result_buf) > 0) then
            result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(item) // trim(suffix)
          else
            result_buf = trim(prefix) // trim(item) // trim(suffix)
          end if
          last_pos = i + 1
        end if
      end do
      ! Don't forget last item
      item = brace_content(last_pos:)
      if (len_trim(result_buf) > 0) then
        result_buf = trim(result_buf) // ' ' // trim(prefix) // trim(item) // trim(suffix)
      else
        result_buf = trim(prefix) // trim(item) // trim(suffix)
      end if
      expanded = trim(result_buf)
      return
    end if

  end function expand_braces

  ! Expand tilde in paths
  function expand_tilde(self, word) result(expanded)
    class(evaluator_simple_real_t), intent(inout) :: self
    character(*), intent(in) :: word
    character(:), allocatable :: expanded
    character(256) :: home_buf, username_buf
    character(:), allocatable :: home, username, pwd, oldpwd
    character(256) :: c_str
    type(c_ptr) :: passwd_ptr, dir_ptr
    type(passwd_t), pointer :: passwd
    integer :: slash_pos, i, status
    character(1) :: next_char

    expanded = word

    ! Must start with ~
    if (len_trim(word) == 0 .or. word(1:1) /= '~') return

    ! Handle single ~ or ~/path
    if (len_trim(word) == 1) then
      ! Just ~
      call get_environment_variable('HOME', home_buf, status=status)
      if (status == 0 .and. len_trim(home_buf) > 0) then
        expanded = trim(home_buf)
      else
        expanded = word
      end if
      return
    end if

    next_char = word(2:2)

    ! Check for ~/ (home directory followed by path)
    if (next_char == '/') then
      call get_environment_variable('HOME', home_buf, status=status)
      if (status == 0 .and. len_trim(home_buf) > 0) then
        expanded = trim(home_buf) // word(2:)
      else
        expanded = word
      end if
      return
    end if

    ! Check for ~+ (current directory)
    if (next_char == '+') then
      if (len_trim(word) == 2 .or. (len_trim(word) > 2 .and. word(3:3) == '/')) then
        pwd = self%context%get_var('PWD')
        if (len_trim(pwd) > 0) then
          if (len_trim(word) == 2) then
            expanded = pwd
          else
            expanded = trim(pwd) // word(3:)
          end if
        else
          expanded = word
        end if
        return
      end if
    end if

    ! Check for ~- (previous directory)
    if (next_char == '-') then
      if (len_trim(word) == 2 .or. (len_trim(word) > 2 .and. word(3:3) == '/')) then
        oldpwd = self%context%get_var('OLDPWD')
        if (len_trim(oldpwd) > 0) then
          if (len_trim(word) == 2) then
            expanded = oldpwd
          else
            expanded = trim(oldpwd) // word(3:)
          end if
        else
          expanded = word
        end if
        return
      end if
    end if

    ! Handle ~username
    ! Find the slash (if any) to separate username from path
    slash_pos = index(word, '/')
    if (slash_pos > 0) then
      username_buf = word(2:slash_pos-1)
    else
      username_buf = word(2:)
    end if

    ! Look up user's home directory using getpwnam
    c_str = trim(username_buf) // c_null_char
    passwd_ptr = c_getpwnam(c_str)

    if (c_associated(passwd_ptr)) then
      call c_f_pointer(passwd_ptr, passwd)
      dir_ptr = passwd%pw_dir

      if (c_associated(dir_ptr)) then
        ! Convert C string pointer to Fortran string
        home = c_ptr_to_f_string(dir_ptr)

        ! Combine with remaining path
        if (slash_pos > 0) then
          expanded = trim(home) // word(slash_pos:)
        else
          expanded = home
        end if
        return
      end if
    end if

    ! If lookup failed, return original word
    expanded = word

  contains
    ! Convert C string pointer to Fortran string
    function c_ptr_to_f_string(c_str_ptr) result(f_str)
      type(c_ptr), intent(in) :: c_str_ptr
      character(:), allocatable :: f_str
      character(kind=c_char), dimension(:), pointer :: c_str_array
      integer :: j, str_len

      call c_f_pointer(c_str_ptr, c_str_array, [256])

      ! Find length (look for null terminator)
      str_len = 0
      do j = 1, 256
        if (c_str_array(j) == c_null_char) exit
        str_len = j
      end do

      ! Allocate and copy
      allocate(character(str_len) :: f_str)
      do j = 1, str_len
        f_str(j:j) = c_str_array(j)
      end do
    end function c_ptr_to_f_string
  end function expand_tilde

end module evaluator_simple_real