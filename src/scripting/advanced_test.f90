! ==============================================================================
! Module: advanced_test
! Purpose: Advanced test operations [[ ]] with string/file/numeric tests
! ==============================================================================
module advanced_test
  use shell_types
  use system_interface
  use variables
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding
  implicit none

  ! Test result constants
  integer, parameter :: TEST_TRUE = 0
  integer, parameter :: TEST_FALSE = 1
  integer, parameter :: TEST_ERROR = 2

  ! POSIX regex types for =~ operator
  type, bind(C) :: regex_t
#if defined(__APPLE__) || defined(__FreeBSD__)
    integer(c_int8_t) :: re_dummy(32)   ! macOS/FreeBSD: regex_t is 32 bytes
#else
    integer(c_int8_t) :: re_dummy(256)  ! Linux: regex_t is ~128-256 bytes
#endif
  end type regex_t

  type, bind(C) :: regmatch_t
#if defined(__APPLE__) || defined(__FreeBSD__)
    integer(c_long) :: rm_so  ! regoff_t is long (8 bytes) on macOS/FreeBSD
    integer(c_long) :: rm_eo
#else
    integer(c_int) :: rm_so   ! regoff_t is int (4 bytes) on Linux
    integer(c_int) :: rm_eo
#endif
  end type regmatch_t

  ! Regex compilation flags
  integer(c_int), parameter :: REG_EXTENDED = 1
  integer(c_int), parameter :: REG_ICASE = 2
  integer(c_int), parameter :: REG_NOSUB = 4
  integer(c_int), parameter :: REG_NEWLINE = 8

  ! C interface for POSIX regex
  interface
    function c_regcomp(preg, pattern, cflags) bind(C, name="regcomp")
      use iso_c_binding
      import :: regex_t
      type(regex_t), intent(inout) :: preg
      character(kind=c_char), dimension(*), intent(in) :: pattern
      integer(c_int), value :: cflags
      integer(c_int) :: c_regcomp
    end function c_regcomp

    function c_regexec(preg, string, nmatch, pmatch, eflags) bind(C, name="regexec")
      use iso_c_binding
      import :: regex_t, regmatch_t
      type(regex_t), intent(in) :: preg
      character(kind=c_char), dimension(*), intent(in) :: string
      integer(c_size_t), value :: nmatch
      type(regmatch_t), dimension(*) :: pmatch
      integer(c_int), value :: eflags
      integer(c_int) :: c_regexec
    end function c_regexec

    subroutine c_regfree(preg) bind(C, name="regfree")
      use iso_c_binding
      import :: regex_t
      type(regex_t), intent(inout) :: preg
    end subroutine c_regfree
  end interface

contains

  ! Main [[ ]] test evaluation
  function evaluate_test_expression(shell, tokens, num_tokens) result(test_result)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    integer :: test_result

    character(len=256) :: left_operand, operator, right_operand
    logical :: result_bool

    test_result = TEST_FALSE

    if (num_tokens < 3) then
      test_result = TEST_ERROR
      return
    end if

    ! Skip [[ and ]] tokens
    if (num_tokens == 3) then
      ! Single condition: [[ condition ]]
      result_bool = evaluate_unary_test(shell, tokens(2))
    else if (num_tokens == 5) then
      ! Binary condition: [[ left op right ]]
      left_operand = tokens(2)
      operator = tokens(3)
      right_operand = tokens(4)
      result_bool = evaluate_binary_test(shell, left_operand, operator, right_operand)
    else
      ! Complex expression with logical operators
      result_bool = evaluate_complex_test(shell, tokens, num_tokens)
    end if
    
    if (result_bool) then
      test_result = TEST_TRUE
    else
      test_result = TEST_FALSE
    end if
  end function

  ! Evaluate unary test conditions
  function evaluate_unary_test(shell, operand) result(result_bool)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: operand
    logical :: result_bool
    
    character(len=256) :: expanded_operand
    
    result_bool = .false.
    
    ! Expand variables in operand
    call expand_test_operand(shell, operand, expanded_operand)
    
    ! Non-empty string test
    result_bool = (len_trim(expanded_operand) > 0)
  end function

  ! Evaluate binary test conditions
  function evaluate_binary_test(shell, left, operator, right) result(result_bool)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: left, operator, right
    logical :: result_bool

    character(len=256) :: expanded_left, expanded_right

    result_bool = .false.

    ! Expand variables in operands
    call expand_test_operand(shell, left, expanded_left)
    call expand_test_operand(shell, right, expanded_right)

    select case (trim(operator))
    ! String comparisons (use wildcard match for [[ ]] glob support)
    case ('=', '==')
      result_bool = wildcard_match(trim(expanded_left), trim(expanded_right))
    case ('!=')
      result_bool = (trim(expanded_left) /= trim(expanded_right))
    case ('<')
      result_bool = (trim(expanded_left) < trim(expanded_right))
    case ('>')
      result_bool = (trim(expanded_left) > trim(expanded_right))
    case ('=~')
      result_bool = match_regex(shell, expanded_left, expanded_right)
    case ('!~')
      result_bool = .not. match_regex(shell, expanded_left, expanded_right)
    
    ! Numeric comparisons
    case ('-eq')
      result_bool = numeric_equal(expanded_left, expanded_right)
    case ('-ne')
      result_bool = .not. numeric_equal(expanded_left, expanded_right)
    case ('-lt')
      result_bool = numeric_less_than(expanded_left, expanded_right)
    case ('-le')
      result_bool = numeric_less_equal(expanded_left, expanded_right)
    case ('-gt')
      result_bool = numeric_greater_than(expanded_left, expanded_right)
    case ('-ge')
      result_bool = numeric_greater_equal(expanded_left, expanded_right)
    
    ! File tests
    case ('-ef')
      result_bool = files_same_device_inode(expanded_left, expanded_right)
    case ('-nt')
      result_bool = file_newer_than(expanded_left, expanded_right)
    case ('-ot')
      result_bool = file_older_than(expanded_left, expanded_right)
    
    case default
      result_bool = .false.
    end select
  end function

  ! Evaluate complex expressions with && || ! operators
  function evaluate_complex_test(shell, tokens, num_tokens) result(result_bool)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    logical :: result_bool
    
    integer :: i
    logical :: current_result, next_result
    character(len=16) :: logical_op
    
    result_bool = .false.
    current_result = .false.
    logical_op = ''
    
    ! Simple left-to-right evaluation
    i = 2  ! Skip initial [[
    
    do while (i < num_tokens)
      if (tokens(i) == '&&' .or. tokens(i) == '||' .or. tokens(i) == '!') then
        logical_op = tokens(i)
        i = i + 1
      else if (tokens(i) == ']]') then
        exit
      else
        ! Evaluate next test
        if (i + 2 < num_tokens .and. is_test_operator(tokens(i+1))) then
          ! Binary test
          next_result = evaluate_binary_test(shell, tokens(i), tokens(i+1), tokens(i+2))
          i = i + 3
          ! After a binary test, next token must be logical operator or ]]
          ! Extra tokens are a syntax error (e.g., [[ x =~ foo bar ]] is invalid)
          if (i < num_tokens) then
            if (tokens(i) /= '&&' .and. tokens(i) /= '||' .and. tokens(i) /= ']]') then
              ! Syntax error: unexpected token after binary test
              result_bool = .false.
              return
            end if
          end if
        else if (is_unary_test_operator(tokens(i)) .and. &
                 i + 1 < num_tokens) then
          ! Unary operator with argument: -z str, -n str, -e file, etc.
          block
            character(len=256) :: expanded_arg
            call expand_test_operand(shell, tokens(i+1), expanded_arg)
            select case (trim(tokens(i)))
            case ('-z')
              next_result = (len_trim(expanded_arg) == 0)
            case ('-n')
              next_result = (len_trim(expanded_arg) > 0)
            case ('-e', '-f', '-d', '-r', '-w', '-x', '-s', '-L', &
                  '-h', '-p', '-b', '-c', '-g', '-u', '-k', '-G', &
                  '-O', '-S')
              next_result = file_test(expanded_arg, tokens(i))
            case default
              next_result = .false.
            end select
          end block
          i = i + 2
        else
          ! Simple unary test (non-empty string check)
          next_result = evaluate_unary_test(shell, tokens(i))
          i = i + 1
        end if

        ! Apply logical operator
        select case (trim(logical_op))
        case ('&&')
          current_result = current_result .and. next_result
        case ('||')
          current_result = current_result .or. next_result
        case ('!')
          current_result = .not. next_result
        case ('')
          current_result = next_result
        end select

        logical_op = ''
      end if
    end do
    
    result_bool = current_result
  end function

  ! File test operations
  function file_test(filename, test_type) result(test_result)
    character(len=*), intent(in) :: filename, test_type
    logical :: test_result

    logical :: exists, is_file, is_dir, is_executable, is_readable, is_writable

    test_result = .false.
    
    ! Check file existence and properties
    inquire(file=trim(filename), exist=exists)
    
    if (.not. exists) then
      test_result = .false.
      return
    end if
    
    ! Use stat-like functionality through system calls
    call get_file_info(filename, exists, is_file, is_dir, is_executable, is_readable, is_writable)
    
    select case (trim(test_type))
    case ('-e')  ! exists
      test_result = exists
    case ('-f')  ! regular file
      test_result = is_file
    case ('-d')  ! directory
      test_result = is_dir
    case ('-r')  ! readable
      test_result = is_readable
    case ('-w')  ! writable
      test_result = is_writable
    case ('-x')  ! executable
      test_result = is_executable
    case ('-s')  ! non-empty
      test_result = (file_size(filename) > 0)
    case ('-L', '-h')  ! symbolic link
      test_result = is_symbolic_link(filename)
    case ('-b')  ! block device
      test_result = is_block_device(filename)
    case ('-c')  ! character device
      test_result = is_char_device(filename)
    case ('-p')  ! named pipe
      test_result = is_named_pipe(filename)
    case ('-S')  ! socket
      test_result = is_socket(filename)
    case default
      test_result = .false.
    end select
  end function

  ! String pattern matching with POSIX regex
  function match_regex(shell, string, pattern) result(matches)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: string, pattern
    logical :: matches

    type(regex_t) :: regex
    type(regmatch_t) :: pmatch(10)  ! Capture up to 9 groups + full match
    character(kind=c_char, len=:), allocatable :: c_pattern, c_string
    integer(c_int) :: comp_result, exec_result
    integer :: match_idx, match_start, match_end
    character(len=256) :: matched_str

    matches = .false.

    ! Prepare C strings (null-terminated)
    c_pattern = trim(pattern) // c_null_char
    c_string = trim(string) // c_null_char

    ! Compile the regex pattern (use extended regex, add case-insensitive flag if nocasematch is enabled)
    if (shell%shopt_nocasematch) then
      comp_result = c_regcomp(regex, c_pattern, ior(REG_EXTENDED, REG_ICASE))
    else
      comp_result = c_regcomp(regex, c_pattern, REG_EXTENDED)
    end if

    if (comp_result == 0) then
      ! Pattern compiled successfully - now execute it with capture groups
      exec_result = c_regexec(regex, c_string, 10_c_size_t, pmatch, 0_c_int)

      if (exec_result == 0) then
        ! Match found - populate BASH_REMATCH array
        matches = .true.

        ! Populate captured groups
        do match_idx = 0, 9
          ! Check if this match is valid (rm_so != -1)
          if (pmatch(match_idx + 1)%rm_so /= -1) then
            match_start = int(pmatch(match_idx + 1)%rm_so) + 1  ! Convert to 1-based
            match_end = int(pmatch(match_idx + 1)%rm_eo)

            ! Extract matched substring
            matched_str = ''
            if (match_end > match_start - 1) then
              matched_str = string(match_start:match_end)
            end if

            ! Store in BASH_REMATCH[match_idx] (use 1-based index for Fortran)
            call set_array_element(shell, 'BASH_REMATCH', match_idx + 1, trim(matched_str))
          else
            ! No more matches
            exit
          end if
        end do
      end if

      ! Clean up regex
      call c_regfree(regex)
    end if
  end function

  recursive function wildcard_match(string, pattern) result(matches)
    character(len=*), intent(in) :: string, pattern
    logical :: matches
    
    integer :: s_pos, p_pos, s_len, p_len
    
    matches = .false.
    s_len = len_trim(string)
    p_len = len_trim(pattern)
    s_pos = 1
    p_pos = 1
    
    do while (s_pos <= s_len .and. p_pos <= p_len)
      if (pattern(p_pos:p_pos) == '*') then
        ! Skip consecutive *
        do while (p_pos <= p_len .and. pattern(p_pos:p_pos) == '*')
          p_pos = p_pos + 1
        end do
        
        if (p_pos > p_len) then
          matches = .true.
          return
        end if
        
        ! Try to match remaining pattern
        do while (s_pos <= s_len)
          if (wildcard_match(string(s_pos:), pattern(p_pos:))) then
            matches = .true.
            return
          end if
          s_pos = s_pos + 1
        end do
        
        return
      else if (pattern(p_pos:p_pos) == '?' .or. pattern(p_pos:p_pos) == string(s_pos:s_pos)) then
        p_pos = p_pos + 1
        s_pos = s_pos + 1
      else
        return
      end if
    end do
    
    ! Handle trailing *
    do while (p_pos <= p_len .and. pattern(p_pos:p_pos) == '*')
      p_pos = p_pos + 1
    end do
    
    matches = (s_pos > s_len .and. p_pos > p_len)
  end function

  ! Numeric comparison functions
  function numeric_equal(left, right) result(equal)
    character(len=*), intent(in) :: left, right
    logical :: equal
    integer :: left_val, right_val, status1, status2
    
    read(left, *, iostat=status1) left_val
    read(right, *, iostat=status2) right_val
    
    if (status1 == 0 .and. status2 == 0) then
      equal = (left_val == right_val)
    else
      equal = .false.
    end if
  end function

  function numeric_less_than(left, right) result(less)
    character(len=*), intent(in) :: left, right
    logical :: less
    integer :: left_val, right_val, status1, status2
    
    read(left, *, iostat=status1) left_val
    read(right, *, iostat=status2) right_val
    
    if (status1 == 0 .and. status2 == 0) then
      less = (left_val < right_val)
    else
      less = .false.
    end if
  end function

  function numeric_less_equal(left, right) result(less_eq)
    character(len=*), intent(in) :: left, right
    logical :: less_eq
    integer :: left_val, right_val, status1, status2
    
    read(left, *, iostat=status1) left_val
    read(right, *, iostat=status2) right_val
    
    if (status1 == 0 .and. status2 == 0) then
      less_eq = (left_val <= right_val)
    else
      less_eq = .false.
    end if
  end function

  function numeric_greater_than(left, right) result(greater)
    character(len=*), intent(in) :: left, right
    logical :: greater
    integer :: left_val, right_val, status1, status2
    
    read(left, *, iostat=status1) left_val
    read(right, *, iostat=status2) right_val
    
    if (status1 == 0 .and. status2 == 0) then
      greater = (left_val > right_val)
    else
      greater = .false.
    end if
  end function

  function numeric_greater_equal(left, right) result(greater_eq)
    character(len=*), intent(in) :: left, right
    logical :: greater_eq
    integer :: left_val, right_val, status1, status2
    
    read(left, *, iostat=status1) left_val
    read(right, *, iostat=status2) right_val
    
    if (status1 == 0 .and. status2 == 0) then
      greater_eq = (left_val >= right_val)
    else
      greater_eq = .false.
    end if
  end function

  ! File comparison functions (simplified implementations)
  function files_same_device_inode(file1, file2) result(same)
    character(len=*), intent(in) :: file1, file2
    logical :: same
    ! -ef: same device + inode (native stat, not a path string compare)
    same = file_same_as(file1, file2)
  end function

  function file_newer_than(file1, file2) result(newer)
    character(len=*), intent(in) :: file1, file2
    logical :: newer
    ! -nt: file1 mtime > file2 mtime (native stat)
    newer = file_is_newer(file1, file2)
  end function

  function file_older_than(file1, file2) result(older)
    character(len=*), intent(in) :: file1, file2
    logical :: older
    ! -ot: file1 mtime < file2 mtime (native stat)
    older = file_is_older(file1, file2)
  end function

  function file_size(filename) result(size)
    character(len=*), intent(in) :: filename
    integer :: size
    
    integer :: unit, iostat
    character :: dummy
    
    size = 0
    
    open(newunit=unit, file=trim(filename), status='old', iostat=iostat)
    if (iostat == 0) then
      do
        read(unit, '(A1)', iostat=iostat) dummy
        if (iostat /= 0) exit
        size = size + 1
      end do
      close(unit)
    end if
  end function

  ! File type checks — delegate to the native stat-based helpers in
  ! system_interface (these used to be hardcoded always-false placeholders).
  function is_symbolic_link(filename) result(is_link)
    character(len=*), intent(in) :: filename
    logical :: is_link
    is_link = file_is_symlink(filename)
  end function

  function is_block_device(filename) result(is_block)
    character(len=*), intent(in) :: filename
    logical :: is_block
    is_block = file_is_block_device(filename)
  end function

  function is_char_device(filename) result(is_char)
    character(len=*), intent(in) :: filename
    logical :: is_char
    is_char = file_is_char_device(filename)
  end function

  function is_named_pipe(filename) result(is_pipe)
    character(len=*), intent(in) :: filename
    logical :: is_pipe
    is_pipe = file_is_fifo(filename)
  end function

  function is_socket(filename) result(is_sock)
    character(len=*), intent(in) :: filename
    logical :: is_sock
    is_sock = file_is_socket(filename)
  end function

  subroutine get_file_info(filename, exists, is_file, is_dir, is_executable, is_readable, is_writable)
    character(len=*), intent(in) :: filename
    logical, intent(out) :: exists, is_file, is_dir, is_executable, is_readable, is_writable

    ! Native stat/access — previously this forked five `test` subprocesses
    ! per file check.
    inquire(file=trim(filename), exist=exists)
    if (exists) then
      is_file       = file_is_regular(filename)
      is_dir        = file_is_directory(filename)
      is_readable   = file_is_readable(filename)
      is_writable   = file_is_writable(filename)
      is_executable = file_is_executable(filename)
    else
      is_file = .false.
      is_dir = .false.
      is_executable = .false.
      is_readable = .false.
      is_writable = .false.
    end if
  end subroutine

  ! Helper functions
  function is_test_operator(op) result(is_op)
    character(len=*), intent(in) :: op
    logical :: is_op

    is_op = (op == '=' .or. op == '==' .or. op == '!=' .or. &
             op == '<' .or. op == '>' .or. op == '=~' .or. op == '!~' .or. &
             op == '-eq' .or. op == '-ne' .or. op == '-lt' .or. op == '-le' .or. &
             op == '-gt' .or. op == '-ge' .or. op == '-ef' .or. op == '-nt' .or. &
             op == '-ot')
  end function

  function is_unary_test_operator(op) result(is_op)
    character(len=*), intent(in) :: op
    logical :: is_op

    is_op = (op == '-z' .or. op == '-n' .or. &
             op == '-e' .or. op == '-f' .or. op == '-d' .or. &
             op == '-r' .or. op == '-w' .or. op == '-x' .or. &
             op == '-s' .or. op == '-L' .or. op == '-h' .or. &
             op == '-p' .or. op == '-b' .or. op == '-c' .or. &
             op == '-g' .or. op == '-u' .or. op == '-k' .or. &
             op == '-G' .or. op == '-O' .or. op == '-S')
  end function

  subroutine expand_test_operand(shell, operand, expanded)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: operand
    character(len=*), intent(out) :: expanded

    character(len=:), allocatable :: temp
    integer :: temp_len

    ! Simple variable expansion for test operands
    if (operand(1:1) == '$') then
      temp = get_shell_variable(shell, operand(2:))
    else
      temp = operand
    end if

    ! Strip surrounding quotes if present
    temp_len = len_trim(temp)
    if (temp_len >= 2) then
      if ((temp(1:1) == '"' .and. temp(temp_len:temp_len) == '"') .or. &
          (temp(1:1) == "'" .and. temp(temp_len:temp_len) == "'")) then
        expanded = temp(2:temp_len-1)
        return
      end if
    end if

    expanded = temp
  end subroutine

end module advanced_test