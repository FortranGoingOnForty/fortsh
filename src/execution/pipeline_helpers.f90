! ==============================================================================
! Module: pipeline_helpers
! ==============================================================================
! Shared helpers for command expansion used by both executor and ast_executor.
! Extracted from executor.f90 and parser.f90 to break the ast_executor → executor
! dependency for pipeline execution.
!
! Functions:
!   - expand_tokens: Variable expansion, IFS field splitting, quote handling
!   - expand_command_globs: Glob pattern expansion for command tokens
!   - process_command_escapes: Post-glob backslash escape processing
!   - has_escaped_spaces: Check for backslash-escaped spaces
!   - interpret_ifs_escapes: Convert IFS escape sequences (\t, \n, \\)
module pipeline_helpers
  use shell_types
  use iso_fortran_env, only: error_unit
  implicit none
  private

  public :: expand_tokens
  public :: expand_command_globs
  public :: process_command_escapes
  public :: has_escaped_spaces
  public :: interpret_ifs_escapes

contains

  function has_escaped_spaces(str) result(has_escaped)
    character(len=*), intent(in) :: str
    logical :: has_escaped
    integer :: i, len_str
    character(len=1) :: backslash

    has_escaped = .false.
    len_str = len_trim(str)
    backslash = char(92)  ! ASCII code for backslash

    do i = 1, len_str - 1
      if (str(i:i) == backslash .and. str(i+1:i+1) == ' ') then
        has_escaped = .true.
        return
      end if
    end do
  end function

  ! Interpret escape sequences in IFS string (\t -> tab, \n -> newline)
  subroutine interpret_ifs_escapes(input, output, output_len)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output
    integer, intent(out) :: output_len
    integer :: i, j, input_len
    character(len=1) :: backslash

    backslash = char(92)  ! ASCII code for backslash
    input_len = len(input)  ! Use len(), not len_trim() - input might be all spaces (IFS=" ")
    j = 1
    i = 1
    output = ''

    do while (i <= input_len)
      if (input(i:i) == backslash .and. i < input_len) then
        ! Check for escape sequences
        if (input(i+1:i+1) == 't') then
          ! \t -> tab
          output(j:j) = char(9)
          j = j + 1
          i = i + 2
        else if (input(i+1:i+1) == 'n') then
          ! \n -> newline
          output(j:j) = char(10)
          j = j + 1
          i = i + 2
        else if (input(i+1:i+1) == backslash) then
          ! \\ -> backslash
          output(j:j) = backslash
          j = j + 1
          i = i + 2
        else
          ! Unknown escape, keep backslash and next char
          output(j:j) = input(i:i)
          j = j + 1
          i = i + 1
        end if
      else
        ! Regular character
        output(j:j) = input(i:i)
        j = j + 1
        i = i + 1
      end if
    end do
    output_len = j - 1  ! Return actual length of output
  end subroutine

  subroutine expand_tokens(cmd, shell)
    use expansion, only: field_split
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(inout) :: shell
    integer :: i, j, total_tokens, temp_cap
    character(len=:), allocatable :: expanded
    character(len=MAX_TOKEN_LEN), allocatable :: temp_tokens(:)
    integer, allocatable :: temp_token_lengths(:)  ! Track actual lengths of expanded tokens
    logical, allocatable :: temp_token_quoted(:)  ! Track if original token was quoted
    logical :: is_format_string
    ! Heap-allocated to avoid static storage in recursive context
    character(len=MAX_TOKEN_LEN), allocatable :: split_words(:)
    integer :: split_cap
    character(len=256) :: ifs_to_use
    integer :: word_count, k, ifs_check_i, ifs_len_to_use
    logical :: should_split, has_quotes, has_equals, has_escaped, has_ifs_char, ifs_explicitly_set
    logical :: is_double_bracket_cmd
    logical :: was_originally_quoted

    split_cap = 256
    allocate(split_words(split_cap))

    ! Allocate temporary storage for expanded tokens
    temp_cap = max(cmd%num_tokens * 10, 256)
    allocate(temp_tokens(temp_cap))
    allocate(temp_token_lengths(temp_cap))
    allocate(temp_token_quoted(temp_cap))
    temp_token_lengths = 0
    temp_token_quoted = .false.
    total_tokens = 0

    ! Check if this is a [[ ]] command - word splitting is NOT performed in [[ ]]
    ! per POSIX and bash behavior
    is_double_bracket_cmd = .false.
    if (cmd%num_tokens > 0) then
      if (trim(cmd%tokens(1)) == '[[') then
        is_double_bracket_cmd = .true.
      end if
    end if

    ! Determine IFS characters to use
    ! Interpret escape sequences in IFS (\t -> tab, \n -> newline)
    ! POSIX: When IFS is set to empty, field splitting is disabled
    ! Check if IFS was explicitly set by user (in global variables or local scope)
    ifs_explicitly_set = .false.
    ! Check global variables array
    do ifs_check_i = 1, shell%num_variables
      if (trim(shell%variables(ifs_check_i)%name) == 'IFS') then
        ifs_explicitly_set = .true.
        exit
      end if
    end do
    ! Also check local variable scope (for local IFS=...)
    if (.not. ifs_explicitly_set .and. shell%function_depth > 0) then
      block
        integer :: lv_depth, lv_i
        do lv_depth = shell%function_depth, 1, -1
          if (lv_depth <= size(shell%local_var_counts)) then
            do lv_i = 1, shell%local_var_counts(lv_depth)
              if (trim(shell%local_vars(lv_depth, lv_i)%name) == 'IFS') then
                ifs_explicitly_set = .true.
                exit
              end if
            end do
          end if
          if (ifs_explicitly_set) exit
        end do
      end block
    end if

    if (ifs_explicitly_set) then
      ! IFS is explicitly set - use its value (even if empty)
      ! Use ifs_len to preserve trailing whitespace (e.g., IFS=" ")
      if (shell%ifs_len > 0) then
        call interpret_ifs_escapes(shell%ifs(1:shell%ifs_len), ifs_to_use, ifs_len_to_use)
      else
        ifs_to_use = ''  ! Empty IFS disables field splitting
        ifs_len_to_use = 0
      end if
    else
      ! IFS not set - use default
      ifs_to_use = ' '//char(9)//char(10)  ! space, tab, newline (default IFS)
      ifs_len_to_use = 3
    end if

    do i = 1, cmd%num_tokens
      ! Track if this token was originally quoted (for preserving trailing whitespace)
      was_originally_quoted = .false.
      if (allocated(cmd%token_quoted) .and. i <= size(cmd%token_quoted)) then
        was_originally_quoted = cmd%token_quoted(i)
      else if (allocated(cmd%token_quote_type) .and. i <= size(cmd%token_quote_type)) then
        was_originally_quoted = (cmd%token_quote_type(i) == QUOTE_SINGLE .or. &
                                 cmd%token_quote_type(i) == QUOTE_DOUBLE)
      end if

      ! POSIX: Special handling for "$@" - expands to separate quoted arguments
      ! When a double-quoted token is exactly $@ or just contains $@ as the whole expansion,
      ! we need to add each positional parameter as a separate token
      if (allocated(cmd%token_quote_type) .and. &
          i <= size(cmd%token_quote_type) .and. &
          cmd%token_quote_type(i) == QUOTE_DOUBLE .and. &
          trim(cmd%tokens(i)) == '$@') then
        ! "$@" - add each positional parameter as a separate quoted token
        do j = 1, shell%num_positional
          total_tokens = total_tokens + 1
          if (total_tokens > temp_cap) call grow_temp_arrays()
          temp_tokens(total_tokens) = trim(shell%positional_params(j))
          temp_token_lengths(total_tokens) = len_trim(shell%positional_params(j))
          temp_token_quoted(total_tokens) = .true.  ! Positional params from "$@" are quoted
        end do
        cycle  ! Skip normal token processing
      end if

      ! Check if this token was single-quoted (no expansion)
      if (allocated(cmd%token_quote_type) .and. &
          i <= size(cmd%token_quote_type) .and. &
          cmd%token_quote_type(i) == QUOTE_SINGLE) then
        ! Single quotes - no expansion, use literal value but strip sentinels/quotes
        ! Lexer uses char(2) for start sentinel and char(3) for end sentinel
        ! Old parser path uses actual quote characters
        block
          character(len=:), allocatable :: stripped
          integer :: strip_j, strip_k, strip_len, start_pos, end_pos
          ! Use token_lengths to preserve trailing spaces if available
          if (allocated(cmd%token_lengths) .and. i <= size(cmd%token_lengths) .and. &
              cmd%token_lengths(i) > 0) then
            strip_len = cmd%token_lengths(i)
          else
            strip_len = len_trim(cmd%tokens(i))
          end if

          ! Determine start and end positions, skipping outer quotes if present
          start_pos = 1
          end_pos = strip_len
          if (strip_len >= 2) then
            ! Check for actual quote characters at start and end (old parser path)
            if (cmd%tokens(i)(1:1) == "'" .and. cmd%tokens(i)(strip_len:strip_len) == "'") then
              start_pos = 2
              end_pos = strip_len - 1
            end if
          end if

          allocate(character(len=end_pos - start_pos + 1) :: stripped)
          strip_k = 1
          do strip_j = start_pos, end_pos
            ! Skip single-quote sentinels (for new lexer path)
            if (cmd%tokens(i)(strip_j:strip_j) /= char(2) .and. &
                cmd%tokens(i)(strip_j:strip_j) /= char(3)) then
              stripped(strip_k:strip_k) = cmd%tokens(i)(strip_j:strip_j)
              strip_k = strip_k + 1
            end if
          end do
          if (strip_k > 1) then
            expanded = stripped(1:strip_k-1)
          else
            expanded = ''
          end if
        end block
      else
        ! No quotes or double quotes - perform expansion
        block
          use parser, only: expand_variables
          use expansion, only: expand_braces_to_words
          logical :: is_double_quoted_token
          is_double_quoted_token = .false.
          if (allocated(cmd%token_quote_type) .and. &
              i <= size(cmd%token_quote_type)) then
            is_double_quoted_token = (cmd%token_quote_type(i) == QUOTE_DOUBLE)
          end if

          if (is_double_quoted_token) then
            ! Double-quoted: no brace expansion, preserve trailing whitespace
            if (allocated(cmd%token_lengths) .and. i <= size(cmd%token_lengths)) then
              if (cmd%token_lengths(i) > 0) then
                call expand_variables(cmd%tokens(i)(1:cmd%token_lengths(i)), expanded, shell, was_quoted_in=.true.)
              else
                expanded = ''
              end if
            else
              call expand_variables(cmd%tokens(i), expanded, shell, was_quoted_in=.true.)
            end if
          else if (index(cmd%tokens(i), '{') > 0 .and. index(cmd%tokens(i), '}') > 0 .and. &
                   index(cmd%tokens(i), '${') == 0) then
            ! Unquoted token with braces (not ${...}): expand braces into
            ! separate words first, then variable-expand each word individually.
            ! This bypasses MAX_TOKEN_LEN limits and matches bash/zsh behavior.
            block
              character(len=MAX_TOKEN_LEN), allocatable :: brace_words(:)
              character(len=:), allocatable :: var_expanded
              integer :: bw_count, bw_i

              call expand_braces_to_words(trim(cmd%tokens(i)), brace_words, bw_count)

              if (bw_count > 1) then
                ! Multiple words from brace expansion — add each as a separate token
                do bw_i = 1, bw_count
                  ! Expand variables in each brace word individually
                  if (index(brace_words(bw_i), '$') > 0 .or. &
                      index(brace_words(bw_i), '`') > 0) then
                    call expand_variables(trim(brace_words(bw_i)), var_expanded, shell, was_quoted_in=.false.)
                    total_tokens = total_tokens + 1
                    if (total_tokens > temp_cap) call grow_temp_arrays()
                    if (allocated(var_expanded)) then
                      temp_tokens(total_tokens) = var_expanded
                      temp_token_lengths(total_tokens) = len(var_expanded)
                    else
                      temp_tokens(total_tokens) = brace_words(bw_i)
                      temp_token_lengths(total_tokens) = len_trim(brace_words(bw_i))
                    end if
                  else
                    total_tokens = total_tokens + 1
                    if (total_tokens > temp_cap) call grow_temp_arrays()
                    temp_tokens(total_tokens) = brace_words(bw_i)
                    temp_token_lengths(total_tokens) = len_trim(brace_words(bw_i))
                  end if
                  temp_token_quoted(total_tokens) = .false.
                end do
                deallocate(brace_words)
                cycle  ! All words already added as separate tokens
              else
                ! Single word — fall through to normal variable expansion
                expanded = trim(brace_words(1))
                deallocate(brace_words)
                if (index(expanded, '$') > 0 .or. index(expanded, '`') > 0) then
                  call expand_variables(expanded, var_expanded, shell, was_quoted_in=.false.)
                  if (allocated(var_expanded)) expanded = var_expanded
                end if
              end if
            end block
          else
            ! No braces — standard variable expansion
            call expand_variables(cmd%tokens(i), expanded, shell, was_quoted_in=.false.)
          end if
        end block
      end if

      ! Determine if we should split this token on IFS characters
      ! Only split if:
      ! 1. Contains IFS characters
      ! 2. NOT quoted (doesn't contain quote characters)
      ! 3. NOT an assignment (doesn't contain =, like alias ll='...' or var=value)
      ! 4. NOT escaped (doesn't contain escaped IFS chars)
      should_split = .false.

      ! Check if expanded string contains any IFS character
      has_ifs_char = .false.
      if (ifs_len_to_use > 0) then
        do k = 1, len(expanded)
          ! Only check against actual IFS chars (first ifs_len_to_use chars of ifs_to_use)
          if (index(ifs_to_use(1:ifs_len_to_use), expanded(k:k)) > 0) then
            has_ifs_char = .true.
            exit
          end if
        end do
      end if
      ! If ifs_len_to_use == 0 (empty IFS), has_ifs_char stays false, disabling field splitting

      if (has_ifs_char) then
        ! Check if ORIGINAL token was quoted (using metadata, not looking for quotes in string)
        if (allocated(cmd%token_quoted) .and. i <= size(cmd%token_quoted)) then
          has_quotes = cmd%token_quoted(i)
        else
          ! Fallback: Check if ORIGINAL token had quotes (not expanded, since expand_variables strips them)
          has_quotes = (index(cmd%tokens(i), '"') > 0 .or. index(cmd%tokens(i), "'") > 0)
        end if
        ! Check if it's an assignment (contains =)
        has_equals = (index(expanded, '=') > 0)
        ! Check if spaces are escaped with backslash in ORIGINAL token
        has_escaped = has_escaped_spaces(cmd%tokens(i))
        ! PARSER FIX: Check if token starts with % (printf format string)
        is_format_string = (len_trim(expanded) > 0 .and. expanded(1:1) == '%')

        ! Only split if no quotes, no equals sign, no escaped spaces, not a format string,
        ! and NOT inside a [[ ]] expression (word splitting is disabled in [[ ]])
        should_split = (.not. has_quotes .and. .not. has_equals .and. .not. has_escaped &
                        .and. .not. is_format_string .and. .not. is_double_bracket_cmd)
      end if

      if (should_split) then
        ! Split the expanded string using IFS characters
        word_count = 0
        ! Grow split_words if expanded string could produce more words than capacity
        ! Worst case: every other char is an IFS separator → len/2 + 1 words
        if (allocated(expanded) .and. len(expanded) / 2 + 1 > split_cap) then
          deallocate(split_words)
          split_cap = len(expanded) / 2 + 1
          allocate(split_words(split_cap))
        end if
        ! Pass ifs_to_use with exact length - use substring to avoid trailing blanks
        if (ifs_len_to_use > 0) then
          call field_split(expanded, ifs_to_use(1:ifs_len_to_use), split_words, word_count)
        else
          ! Empty IFS - no splitting should happen (but we shouldn't reach here)
          split_words(1) = expanded
          word_count = 1
        end if

        ! Add all split words as separate tokens
        do j = 1, word_count
          total_tokens = total_tokens + 1
          if (total_tokens > temp_cap) call grow_temp_arrays()
          temp_tokens(total_tokens) = split_words(j)
          temp_token_lengths(total_tokens) = len_trim(split_words(j))
          ! Split tokens from unquoted expansion are not quoted
          temp_token_quoted(total_tokens) = .false.
        end do
      else
        ! No IFS chars or shouldn't split, just add as single token
        ! POSIX: Skip empty tokens from unquoted variable expansion
        ! Only keep empty strings if the original token was quoted
        if (len_trim(expanded) == 0) then
          ! Check if original token was quoted
          if (allocated(cmd%token_quoted) .and. i <= size(cmd%token_quoted)) then
            if (.not. cmd%token_quoted(i)) then
              cycle  ! Skip empty unquoted token
            end if
          else
            ! No metadata - check token for quotes (fallback)
            if (index(cmd%tokens(i), '"') == 0 .and. index(cmd%tokens(i), "'") == 0) then
              cycle  ! Skip empty unquoted token
            end if
          end if
        end if
        total_tokens = total_tokens + 1
        if (total_tokens > temp_cap) call grow_temp_arrays()
        temp_tokens(total_tokens) = expanded
        ! Track actual length of expanded token (use len for allocatable to get real length)
        if (allocated(expanded)) then
          temp_token_lengths(total_tokens) = len(expanded)
        else
          temp_token_lengths(total_tokens) = 0
        end if
        ! Preserve quoted status for trailing whitespace preservation
        temp_token_quoted(total_tokens) = was_originally_quoted
      end if
    end do

    ! Replace command tokens with expanded ones
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)
    allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(total_tokens))
    do i = 1, total_tokens
      cmd%tokens(i) = temp_tokens(i)
    end do
    cmd%num_tokens = total_tokens

    ! Update token_lengths with actual expanded lengths
    if (allocated(cmd%token_lengths)) deallocate(cmd%token_lengths)
    allocate(cmd%token_lengths(total_tokens))
    cmd%token_lengths(1:total_tokens) = temp_token_lengths(1:total_tokens)

    ! Update token_quoted to preserve original quoted status
    if (allocated(cmd%token_quoted)) deallocate(cmd%token_quoted)
    allocate(cmd%token_quoted(total_tokens))
    cmd%token_quoted(1:total_tokens) = temp_token_quoted(1:total_tokens)

    deallocate(temp_tokens)
    deallocate(temp_token_lengths)
    deallocate(temp_token_quoted)

  contains

    subroutine grow_temp_arrays()
      character(len=MAX_TOKEN_LEN), allocatable :: new_tokens(:)
      integer, allocatable :: new_lengths(:)
      logical, allocatable :: new_quoted(:)
      integer :: new_cap

      new_cap = temp_cap * 2
      allocate(new_tokens(new_cap))
      allocate(new_lengths(new_cap))
      allocate(new_quoted(new_cap))
      new_lengths = 0
      new_quoted = .false.
      new_tokens(1:temp_cap) = temp_tokens(1:temp_cap)
      new_lengths(1:temp_cap) = temp_token_lengths(1:temp_cap)
      new_quoted(1:temp_cap) = temp_token_quoted(1:temp_cap)
      call move_alloc(new_tokens, temp_tokens)
      call move_alloc(new_lengths, temp_token_lengths)
      call move_alloc(new_quoted, temp_token_quoted)
      temp_cap = new_cap
    end subroutine grow_temp_arrays

  end subroutine

  subroutine expand_command_globs(cmd, shell)
    use glob, only: expand_glob_patterns
    type(command_t), intent(inout) :: cmd
    type(shell_state_t), intent(in) :: shell

    character(len=MAX_TOKEN_LEN), allocatable :: expanded_tokens(:)
    character(len=MAX_TOKEN_LEN), allocatable :: original_tokens(:)
    integer :: expanded_count, i
    logical :: has_expandable

    if (.not. allocated(cmd%tokens) .or. cmd%num_tokens == 0) return

    ! Skip glob expansion if noglob option is enabled (set -f)
    if (shell%option_noglob) return

    ! Save original tokens
    allocate(original_tokens(cmd%num_tokens))
    do i = 1, cmd%num_tokens
      original_tokens(i) = cmd%tokens(i)
    end do

    ! Don't glob expand tokens that were quoted, escaped, or have backslashes
    ! Check metadata if available, otherwise fall back to checking for backslash
    has_expandable = .false.
    do i = 1, cmd%num_tokens
      ! Skip if token was quoted (prevents glob expansion per POSIX)
      if (allocated(cmd%token_quoted)) then
        if (i <= size(cmd%token_quoted) .and. cmd%token_quoted(i)) then
          cycle  ! Skip this token - it was quoted
        end if
      end if

      ! Skip if token was escaped (metadata available) or has backslash (fallback)
      if (allocated(cmd%token_escaped)) then
        ! Use metadata if available
        if (i <= size(cmd%token_escaped) .and. cmd%token_escaped(i)) then
          cycle  ! Skip this token - it was escaped
        end if
      else if (index(cmd%tokens(i), '\') > 0) then
        ! Fallback: check for backslash in token
        cycle  ! Skip this token - it has a backslash
      end if

      ! Check if token has glob characters
      if (index(cmd%tokens(i), '*') > 0 .or. &
          index(cmd%tokens(i), '?') > 0 .or. &
          index(cmd%tokens(i), '[') > 0) then
        has_expandable = .true.
        exit
      end if
    end do

    if (.not. has_expandable) then
      ! No tokens need glob expansion
      if (allocated(original_tokens)) deallocate(original_tokens)
      return
    end if

    ! Expand glob patterns (pass token_quoted to prevent glob expansion on quoted tokens)
    if (allocated(cmd%token_quoted)) then
      call expand_glob_patterns(original_tokens, cmd%num_tokens, expanded_tokens, expanded_count, cmd%token_quoted)
    else
      call expand_glob_patterns(original_tokens, cmd%num_tokens, expanded_tokens, expanded_count)
    end if

    ! Replace command tokens with expanded ones
    if (allocated(cmd%tokens)) deallocate(cmd%tokens)

    if (expanded_count > 0) then
      allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(expanded_count))
      do i = 1, expanded_count
        cmd%tokens(i) = expanded_tokens(i)
      end do
      cmd%num_tokens = expanded_count

      ! Update token_lengths to match new tokens (use trimmed length)
      if (allocated(cmd%token_lengths)) deallocate(cmd%token_lengths)
      allocate(cmd%token_lengths(expanded_count))
      do i = 1, expanded_count
        cmd%token_lengths(i) = len_trim(expanded_tokens(i))
      end do

      ! Reset token_quoted and token_escaped for expanded tokens
      ! (glob-expanded filenames are not quoted)
      if (allocated(cmd%token_quoted)) deallocate(cmd%token_quoted)
      allocate(cmd%token_quoted(expanded_count))
      cmd%token_quoted = .false.

      if (allocated(cmd%token_escaped)) deallocate(cmd%token_escaped)
      allocate(cmd%token_escaped(expanded_count))
      cmd%token_escaped = .false.
    else
      ! No expansion occurred - restore original
      allocate(character(len=MAX_TOKEN_LEN) :: cmd%tokens(cmd%num_tokens))
      do i = 1, cmd%num_tokens
        cmd%tokens(i) = original_tokens(i)
      end do
    end if

    ! Cleanup
    if (allocated(expanded_tokens)) deallocate(expanded_tokens)
    if (allocated(original_tokens)) deallocate(original_tokens)
  end subroutine

  subroutine process_command_escapes(cmd)
    type(command_t), intent(inout) :: cmd
    integer :: i, j, k, token_len
    character(len=MAX_TOKEN_LEN) :: result
    logical :: in_quotes
    character(len=1) :: quote_char, backslash

    backslash = char(92)  ! ASCII for backslash

    do i = 1, cmd%num_tokens
      token_len = len_trim(cmd%tokens(i))
      result = ''
      k = 0  ! Count of characters written to result
      j = 1
      in_quotes = .false.
      quote_char = ' '

      do while (j <= token_len)
        ! Track quote state
        if (.not. in_quotes .and. (cmd%tokens(i)(j:j) == '"' .or. cmd%tokens(i)(j:j) == "'")) then
          in_quotes = .true.
          quote_char = cmd%tokens(i)(j:j)
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        else if (in_quotes .and. cmd%tokens(i)(j:j) == quote_char) then
          in_quotes = .false.
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        else if (.not. in_quotes .and. cmd%tokens(i)(j:j) == backslash .and. j < token_len) then
          ! Check what character follows the backslash
          ! Only process structural escapes (space, glob characters)
          if (cmd%tokens(i)(j+1:j+1) == ' ' .or. &
              cmd%tokens(i)(j+1:j+1) == '*' .or. &
              cmd%tokens(i)(j+1:j+1) == '?' .or. &
              cmd%tokens(i)(j+1:j+1) == '[') then
            ! Structural escape - skip backslash, keep next char
            j = j + 1
            k = k + 1
            result(k:k) = cmd%tokens(i)(j:j)
            j = j + 1
          else
            ! Non-structural escape (like \n, \t) - keep both backslash and next char
            k = k + 1
            result(k:k) = backslash
            j = j + 1
            if (j <= token_len) then
              k = k + 1
              result(k:k) = cmd%tokens(i)(j:j)
              j = j + 1
            end if
          end if
        else
          ! Regular character
          k = k + 1
          result(k:k) = cmd%tokens(i)(j:j)
          j = j + 1
        end if
      end do

      ! Only copy the actual content (k characters)
      if (k > 0) then
        cmd%tokens(i) = result(1:k)
      else
        cmd%tokens(i) = ''
      end if
    end do
  end subroutine

end module pipeline_helpers
