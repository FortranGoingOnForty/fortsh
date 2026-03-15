! ==============================================================================
! Module: glob
! Purpose: Pattern matching and file globbing functionality
! ==============================================================================
module glob
  use shell_types
  use system_interface
  use performance
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding
  implicit none

  integer, parameter :: MAX_GLOB_MATCHES = 1000
  integer, parameter :: MAX_FILENAME_LEN = 256
  integer, parameter :: MAX_GLOB_RECURSION = 4096
  integer :: glob_recursion_depth = 0

contains

  ! Check if string contains unescaped glob characters
  function has_unescaped_glob_chars(str) result(has_unescaped)
    character(len=*), intent(in) :: str
    logical :: has_unescaped
    integer :: i, len_str
    logical :: escaped
    character(len=1) :: backslash

    has_unescaped = .false.
    len_str = len_trim(str)
    escaped = .false.
    backslash = char(92)  ! ASCII code for backslash

    do i = 1, len_str
      if (escaped) then
        ! Previous char was backslash, so this char is escaped
        escaped = .false.
      else if (str(i:i) == backslash) then
        ! This is an escape character
        escaped = .true.
      else if (str(i:i) == '*' .or. str(i:i) == '?' .or. str(i:i) == '[') then
        ! Found unescaped glob character
        has_unescaped = .true.
        return
      end if
    end do
  end function

  ! Main glob expansion function
  subroutine expand_glob_patterns(tokens, num_tokens, expanded_tokens, expanded_count, token_quoted)
    character(len=*), intent(in) :: tokens(:)
    integer, intent(in) :: num_tokens
    character(len=MAX_TOKEN_LEN), allocatable, intent(out) :: expanded_tokens(:)
    integer, intent(out) :: expanded_count
    logical, intent(in), optional :: token_quoted(:)

    ! Use allocatable arrays to avoid static storage
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    character(len=MAX_TOKEN_LEN), allocatable :: matches(:)
    integer :: i, j, match_count, total_count, current_size
    logical :: has_glob_chars, is_quoted
    integer(int64) :: glob_start_time

    ! Start performance timing
    call start_timer('glob_expansion', glob_start_time)

    ! Allocate initial arrays
    allocate(temp_tokens(100))  ! Start with reasonable size
    allocate(matches(MAX_GLOB_MATCHES))
    current_size = 100
    total_count = 0

    do i = 1, num_tokens
      ! Check if this token was quoted (skip glob expansion if so)
      is_quoted = .false.
      if (present(token_quoted)) then
        if (i <= size(token_quoted)) then
          is_quoted = token_quoted(i)
        end if
      end if

      ! Check if token contains unescaped glob characters (skip if quoted)
      if (is_quoted) then
        has_glob_chars = .false.  ! Quoted tokens don't get glob expanded
      else
        has_glob_chars = has_unescaped_glob_chars(tokens(i))
      end if

      if (has_glob_chars) then
        ! Expand the glob pattern
        call glob_match(tokens(i), matches, match_count)

        if (match_count > 0) then
          ! Add matches to result
          do j = 1, match_count
            ! Grow array if needed
            if (total_count >= current_size) then
              call grow_token_array(temp_tokens, current_size)
            end if
            total_count = total_count + 1
            temp_tokens(total_count) = trim(matches(j))
          end do
        else
          ! No matches found - keep original token
          if (total_count >= current_size) then
            call grow_token_array(temp_tokens, current_size)
          end if
          total_count = total_count + 1
          temp_tokens(total_count) = tokens(i)
        end if
      else
        ! No glob characters - keep original token
        if (total_count >= current_size) then
          call grow_token_array(temp_tokens, current_size)
        end if
        total_count = total_count + 1
        temp_tokens(total_count) = tokens(i)
      end if
    end do
    
    ! Allocate result array
    expanded_count = total_count
    if (expanded_count > 0) then
      allocate(expanded_tokens(expanded_count))
      do i = 1, expanded_count
        expanded_tokens(i) = temp_tokens(i)
      end do
    else
      allocate(expanded_tokens(1))
      expanded_tokens(1) = ''
      expanded_count = 0
    end if
    
    ! Track memory allocation
    if (allocated(expanded_tokens)) then
      call track_allocation(size(expanded_tokens) * MAX_TOKEN_LEN, 'expanded_tokens')
    end if

    ! Clean up allocatable arrays
    if (allocated(temp_tokens)) deallocate(temp_tokens)
    if (allocated(matches)) deallocate(matches)

    ! End performance timing
    call end_timer('glob_expansion', glob_start_time, total_glob_time)
  end subroutine

  ! Helper subroutine to grow token array
  subroutine grow_token_array(array, current_size)
    character(len=MAX_TOKEN_LEN), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    character(len=MAX_TOKEN_LEN), allocatable :: new_array(:)
    integer :: new_size

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    new_array(1:current_size) = array(1:current_size)

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  ! Match a glob pattern against files in current directory
  subroutine glob_match(pattern, matches, match_count)
    character(len=*), intent(in) :: pattern
    character(len=MAX_TOKEN_LEN), intent(out) :: matches(:)
    integer, intent(out) :: match_count

    character(len=MAX_FILENAME_LEN) :: directory_path, filename
    character(len=MAX_FILENAME_LEN) :: full_pattern
    integer :: dir_pos, i
    logical :: is_dir_pattern

    match_count = 0
    full_pattern = trim(pattern)
    
    ! Check if pattern contains directory separator
    dir_pos = 0
    do i = len_trim(pattern), 1, -1
      if (pattern(i:i) == '/') then
        dir_pos = i
        exit
      end if
    end do
    
    if (dir_pos > 0) then
      ! Pattern has directory component
      directory_path = pattern(1:dir_pos-1)
      if (len_trim(directory_path) == 0) directory_path = '/'
      filename = pattern(dir_pos+1:)
      is_dir_pattern = .true.
    else
      ! Pattern is just a filename in current directory
      directory_path = '.'
      filename = pattern
      is_dir_pattern = .false.
    end if
    
    ! List files in directory and match pattern
    call match_files_in_directory(directory_path, filename, is_dir_pattern, matches, match_count)
  end subroutine

  ! Match files in a specific directory against a pattern
  subroutine match_files_in_directory(dir_path, file_pattern, include_dir_path, matches, match_count)
    character(len=*), intent(in) :: dir_path, file_pattern
    logical, intent(in) :: include_dir_path
    character(len=MAX_TOKEN_LEN), intent(out) :: matches(:)
    integer, intent(out) :: match_count

    ! Simple implementation - in a full shell this would use opendir/readdir
    ! Use allocatable to avoid stack overflow on macOS
    character(len=MAX_FILENAME_LEN), allocatable :: test_files(:)
    integer :: num_test_files, i

    match_count = 0
    allocate(test_files(10000))  ! Increased to handle directories with many files

    ! For now, simulate some common files for testing
    ! In a real implementation, this would read the actual directory
    call get_simulated_directory_contents(dir_path, test_files, num_test_files)
    
    do i = 1, num_test_files
      if (pattern_matches(file_pattern, test_files(i))) then
        if (match_count < size(matches)) then
          match_count = match_count + 1
          if (include_dir_path) then
            if (trim(dir_path) == '.') then
              matches(match_count) = trim(test_files(i))
            else
              matches(match_count) = trim(dir_path) // '/' // trim(test_files(i))
            end if
          else
            matches(match_count) = trim(test_files(i))
          end if
        end if
      end if
    end do

    if (allocated(test_files)) deallocate(test_files)
  end subroutine

  ! Get actual directory contents (simplified implementation)
  subroutine get_simulated_directory_contents(dir_path, files, count)
    character(len=*), intent(in) :: dir_path
    character(len=MAX_FILENAME_LEN), intent(out) :: files(:)
    integer, intent(out) :: count
    
    ! For now, keep simulation but add note
    ! In a production shell, this would use opendir/readdir system calls
    ! or execute 'ls' and parse output
    
    ! Try to read actual directory via ls command
    call read_directory_with_ls(dir_path, files, count)

    ! No fallback simulation - if ls returns nothing, return nothing
  end subroutine

  ! Read directory contents using ls command
  subroutine read_directory_with_ls(dir_path, files, count)
    character(len=*), intent(in) :: dir_path
    character(len=MAX_FILENAME_LEN), intent(out) :: files(:)
    integer, intent(out) :: count

    ! Increased buffer size to handle directories with many files (like /tmp)
    integer, parameter :: BUFFER_SIZE = 524288  ! 512KB buffer for large directories

    character(len=512) :: command
    integer(c_pid_t) :: pid
    integer(c_int), target :: status, pipefd(2)
    integer :: ret, i, line_start, total_bytes
    character(len=BUFFER_SIZE), allocatable :: buffer
    integer(c_size_t) :: bytes_read
    character(kind=c_char), target :: c_buffer(8192)  ! Read in 8KB chunks

    count = 0
    allocate(character(len=BUFFER_SIZE) :: buffer)

    ! Construct ls command (-A excludes . and .., -1 means one per line)
    if (trim(dir_path) == '.' .or. trim(dir_path) == '') then
      command = 'ls -A1 2>/dev/null'
    else
      command = 'ls -A1 ' // trim(dir_path) // ' 2>/dev/null'
    end if

    ! Create pipe for reading output
    ret = c_pipe(c_loc(pipefd))
    if (ret /= 0) return

    ! Fork to execute ls
    pid = c_fork()

    if (pid == 0) then
      ! Child: redirect stdout to pipe and execute ls
      ret = c_close(pipefd(1))  ! Close read end
      ret = c_dup2(pipefd(2), STDOUT_FD)
      ret = c_close(pipefd(2))  ! Close original write end

      ! Execute ls via shell
      call execute_ls_command(trim(command))
      call c_exit(127)
    else if (pid > 0) then
      ! Parent: read from pipe
      ret = c_close(pipefd(2))  ! Close write end

      ! Read output from pipe in chunks until EOF
      buffer = ''
      total_bytes = 0
      do
        bytes_read = c_read(pipefd(1), c_loc(c_buffer), int(8192, c_size_t))
        if (bytes_read <= 0) exit  ! EOF or error

        ! Append to buffer
        do i = 1, min(int(bytes_read), 8192)
          if (c_buffer(i) == c_null_char) exit
          if (total_bytes < BUFFER_SIZE) then
            total_bytes = total_bytes + 1
            buffer(total_bytes:total_bytes) = c_buffer(i)
          end if
        end do

        ! Stop if buffer is full
        if (total_bytes >= BUFFER_SIZE) exit
      end do

      ! Parse lines from buffer
      line_start = 1
      do i = 1, total_bytes
        if (buffer(i:i) == char(10)) then  ! Newline
          if (i > line_start .and. count < size(files)) then
            count = count + 1
            files(count) = buffer(line_start:i-1)
          end if
          line_start = i + 1
        end if
      end do

      ! Handle last line if no trailing newline
      if (line_start <= total_bytes .and. count < size(files)) then
        count = count + 1
        files(count) = buffer(line_start:total_bytes)
      end if

      ret = c_close(pipefd(1))
      ret = c_waitpid(pid, c_loc(status), 0)
    end if
  end subroutine

  ! Execute ls command via shell
  subroutine execute_ls_command(command)
    character(len=*), intent(in) :: command
    character(kind=c_char), target :: shell_path(10)
    character(kind=c_char), target :: c_flag(3)
    character(kind=c_char), target :: c_command(512)
    type(c_ptr), target :: argv(4)
    integer :: i, ret

    ! Prepare /bin/sh
    shell_path(1) = '/'
    shell_path(2) = 'b'
    shell_path(3) = 'i'
    shell_path(4) = 'n'
    shell_path(5) = '/'
    shell_path(6) = 's'
    shell_path(7) = 'h'
    shell_path(8) = c_null_char

    ! Prepare -c flag
    c_flag(1) = '-'
    c_flag(2) = 'c'
    c_flag(3) = c_null_char

    ! Prepare command string
    do i = 1, min(len_trim(command), 500)
      c_command(i) = command(i:i)
    end do
    c_command(min(len_trim(command), 500) + 1) = c_null_char

    ! Setup argv: ["/bin/sh", "-c", command, NULL]
    argv(1) = c_loc(shell_path)    ! /bin/sh
    argv(2) = c_loc(c_flag)        ! -c
    argv(3) = c_loc(c_command)     ! command
    argv(4) = c_null_ptr

    ! Execute
    ret = c_execvp(argv(1), c_loc(argv))
  end subroutine

  ! Check if a filename matches a glob pattern
  function pattern_matches(pattern, filename) result(matches)
    character(len=*), intent(in) :: pattern, filename
    logical :: matches

    ! POSIX: * and ? should not match files starting with . (dotfiles)
    ! unless the pattern explicitly starts with .
    if (len_trim(filename) > 0 .and. filename(1:1) == '.') then
      ! This is a dotfile
      if (len_trim(pattern) > 0 .and. pattern(1:1) == '.') then
        ! Pattern explicitly starts with ., so allow matching
        matches = glob_match_recursive(pattern, filename, 1, 1)
      else
        ! Pattern doesn't start with ., so don't match dotfiles
        matches = .false.
      end if
    else
      ! Not a dotfile, normal matching
      matches = glob_match_recursive(pattern, filename, 1, 1)
    end if
  end function

  ! Pattern matching without dotfile exclusion (for case statements, etc.)
  function pattern_matches_no_dotfile_check(pattern, text) result(matches)
    character(len=*), intent(in) :: pattern, text
    logical :: matches

    ! Direct pattern matching without dotfile exclusion
    matches = glob_match_recursive(pattern, text, 1, 1)
  end function

  ! Recursive pattern matching function
  recursive function glob_match_recursive(pattern, text, p_pos, t_pos) result(matches)
    character(len=*), intent(in) :: pattern, text
    integer, intent(in) :: p_pos, t_pos
    logical :: matches

    integer :: p_len, t_len, i, bracket_end
    character(len=1) :: p_char, t_char
    logical :: bracket_match

    ! Guard against runaway recursion (e.g., pathological patterns like **...**)
    glob_recursion_depth = glob_recursion_depth + 1
    if (glob_recursion_depth > MAX_GLOB_RECURSION) then
      glob_recursion_depth = glob_recursion_depth - 1
      matches = .false.
      return
    end if

    p_len = len_trim(pattern)
    t_len = len_trim(text)

    ! Special case: empty pattern should only match empty text
    if (p_len == 0) then
      matches = (t_len == 0)
      glob_recursion_depth = glob_recursion_depth - 1
      return
    end if

    ! Handle whitespace-only text (e.g., " " should match [[:space:]])
    ! len_trim returns 0 for whitespace, but we need to match it
    ! Only do this if pattern is NOT empty (otherwise we'd match padding)
    if (t_len == 0 .and. len(text) > 0) then
      ! Check if first char is whitespace - if so, use length 1
      if (text(1:1) == ' ' .or. ichar(text(1:1)) == 9) then
        t_len = 1
      end if
    end if

    ! End conditions
    if (p_pos > p_len) then
      matches = (t_pos > t_len)
      glob_recursion_depth = glob_recursion_depth - 1
      return
    end if
    
    p_char = pattern(p_pos:p_pos)
    
    select case(p_char)
    case('*')
      ! Match zero or more characters
      ! Try matching rest of pattern at current position
      if (glob_match_recursive(pattern, text, p_pos + 1, t_pos)) then
        matches = .true.
        glob_recursion_depth = glob_recursion_depth - 1
        return
      end if

      ! Try consuming one character from text and continue
      do i = t_pos, t_len
        if (glob_match_recursive(pattern, text, p_pos + 1, i + 1)) then
          matches = .true.
          glob_recursion_depth = glob_recursion_depth - 1
          return
        end if
      end do
      
      matches = .false.
      
    case('?')
      ! Match exactly one character
      if (t_pos <= t_len) then
        matches = glob_match_recursive(pattern, text, p_pos + 1, t_pos + 1)
      else
        matches = .false.
      end if
      
    case('[')
      ! Character class matching
      if (t_pos > t_len) then
        matches = .false.
        glob_recursion_depth = glob_recursion_depth - 1
        return
      end if
      
      ! Find end of bracket expression (handling nested [:...:])
      ! POSIX: ] is literal if it's first char after [ or [! or [^
      bracket_end = p_pos + 1
      ! Skip negation marker if present
      if (bracket_end <= p_len .and. &
          (pattern(bracket_end:bracket_end) == '!' .or. pattern(bracket_end:bracket_end) == '^')) then
        bracket_end = bracket_end + 1
      end if
      ! Skip ] if it's first (literal ])
      if (bracket_end <= p_len .and. pattern(bracket_end:bracket_end) == ']') then
        bracket_end = bracket_end + 1
      end if
      do while (bracket_end <= p_len)
        ! Check for character class [:...:] and skip over it
        if (bracket_end + 1 <= p_len .and. pattern(bracket_end:bracket_end+1) == '[:') then
          ! Skip to the end of the character class
          bracket_end = bracket_end + 2
          do while (bracket_end + 1 <= p_len)
            if (pattern(bracket_end:bracket_end+1) == ':]') then
              bracket_end = bracket_end + 2
              exit
            end if
            bracket_end = bracket_end + 1
          end do
        else if (pattern(bracket_end:bracket_end) == ']') then
          ! Found the closing bracket
          exit
        else
          bracket_end = bracket_end + 1
        end if
      end do
      
      if (bracket_end > p_len) then
        ! Invalid bracket expression - treat as literal
        matches = (t_pos <= t_len .and. text(t_pos:t_pos) == '[') .and. &
                 glob_match_recursive(pattern, text, p_pos + 1, t_pos + 1)
      else
        t_char = text(t_pos:t_pos)
        bracket_match = match_bracket_expression(pattern(p_pos+1:bracket_end-1), t_char)
        
        if (bracket_match) then
          matches = glob_match_recursive(pattern, text, bracket_end + 1, t_pos + 1)
        else
          matches = .false.
        end if
      end if
      
    case default
      ! Literal character match
      if (t_pos <= t_len .and. text(t_pos:t_pos) == p_char) then
        matches = glob_match_recursive(pattern, text, p_pos + 1, t_pos + 1)
      else
        matches = .false.
      end if
    end select
    glob_recursion_depth = glob_recursion_depth - 1
  end function

  ! Match bracket expression [abc], [a-z], [!abc], [[:class:]]
  function match_bracket_expression(bracket_content, test_char) result(matches)
    character(len=*), intent(in) :: bracket_content
    character(len=1), intent(in) :: test_char
    logical :: matches

    logical :: negated, found
    integer :: i, content_len, class_end
    character(len=1) :: current_char, next_char, range_start
    character(len=20) :: char_class

    content_len = len_trim(bracket_content)
    if (content_len == 0) then
      matches = .false.
      return
    end if

    ! Check for negation (POSIX uses ! but ^ is also common)
    negated = (bracket_content(1:1) == '!' .or. bracket_content(1:1) == '^')
    i = 1
    if (negated) i = 2

    found = .false.

    do while (i <= content_len .and. .not. found)
      current_char = bracket_content(i:i)

      ! Check for POSIX character class [:class:]
      if (i + 3 <= content_len .and. bracket_content(i:i+1) == '[:') then
        ! Find the closing :]
        class_end = index(bracket_content(i+2:), ':]')
        if (class_end > 0) then
          ! Extract the class name
          char_class = bracket_content(i+2:i+class_end)

          ! Check if character matches the class
          found = match_char_class(trim(char_class), test_char)

          ! Move past the character class
          i = i + class_end + 3  ! Move past [:class:]
        else
          ! Malformed character class, treat as literal characters
          if (test_char == current_char) then
            found = .true.
          end if
          i = i + 1
        end if
      ! Check for range (a-z)
      else if (i + 2 <= content_len .and. bracket_content(i+1:i+1) == '-') then
        range_start = current_char
        next_char = bracket_content(i+2:i+2)

        ! Check if character is in range
        if (ichar(test_char) >= ichar(range_start) .and. ichar(test_char) <= ichar(next_char)) then
          found = .true.
        end if
        i = i + 3
      else
        ! Single character match
        if (test_char == current_char) then
          found = .true.
        end if
        i = i + 1
      end if
    end do

    if (negated) then
      matches = .not. found
    else
      matches = found
    end if
  end function

  ! Match POSIX character class
  function match_char_class(class_name, test_char) result(matches)
    character(len=*), intent(in) :: class_name
    character(len=1), intent(in) :: test_char
    logical :: matches
    integer :: char_code

    char_code = ichar(test_char)
    matches = .false.

    select case (trim(class_name))
      case ('alnum')
        ! Alphanumeric: [A-Za-z0-9]
        matches = (char_code >= ichar('A') .and. char_code <= ichar('Z')) .or. &
                  (char_code >= ichar('a') .and. char_code <= ichar('z')) .or. &
                  (char_code >= ichar('0') .and. char_code <= ichar('9'))

      case ('alpha')
        ! Alphabetic: [A-Za-z]
        matches = (char_code >= ichar('A') .and. char_code <= ichar('Z')) .or. &
                  (char_code >= ichar('a') .and. char_code <= ichar('z'))

      case ('blank')
        ! Space and tab
        matches = (test_char == ' ' .or. test_char == char(9))

      case ('cntrl')
        ! Control characters (0-31, 127)
        matches = (char_code >= 0 .and. char_code <= 31) .or. char_code == 127

      case ('digit')
        ! Digits: [0-9]
        matches = (char_code >= ichar('0') .and. char_code <= ichar('9'))

      case ('graph')
        ! Visible characters (33-126)
        matches = (char_code >= 33 .and. char_code <= 126)

      case ('lower')
        ! Lowercase letters: [a-z]
        matches = (char_code >= ichar('a') .and. char_code <= ichar('z'))

      case ('print')
        ! Printable characters (32-126)
        matches = (char_code >= 32 .and. char_code <= 126)

      case ('punct')
        ! Punctuation (visible non-alphanumeric)
        matches = ((char_code >= 33 .and. char_code <= 47) .or. &
                   (char_code >= 58 .and. char_code <= 64) .or. &
                   (char_code >= 91 .and. char_code <= 96) .or. &
                   (char_code >= 123 .and. char_code <= 126))

      case ('space')
        ! Whitespace: space, tab, newline, etc.
        matches = (test_char == ' ' .or. test_char == char(9) .or. test_char == char(10) .or. &
                   test_char == char(11) .or. test_char == char(12) .or. test_char == char(13))

      case ('upper')
        ! Uppercase letters: [A-Z]
        matches = (char_code >= ichar('A') .and. char_code <= ichar('Z'))

      case ('xdigit')
        ! Hexadecimal digits: [0-9A-Fa-f]
        matches = (char_code >= ichar('0') .and. char_code <= ichar('9')) .or. &
                  (char_code >= ichar('A') .and. char_code <= ichar('F')) .or. &
                  (char_code >= ichar('a') .and. char_code <= ichar('f'))

      case default
        ! Unknown character class
        matches = .false.
    end select
  end function

  ! Sort matches alphabetically (simple bubble sort)
  subroutine sort_matches(matches, count)
    character(len=*), intent(inout) :: matches(:)
    integer, intent(in) :: count

    integer :: i, j
    character(len=len(matches)) :: temp

    do i = 1, count - 1
      do j = i + 1, count
        if (matches(i) > matches(j)) then
          temp = matches(i)
          matches(i) = matches(j)
          matches(j) = temp
        end if
      end do
    end do
  end subroutine

end module glob