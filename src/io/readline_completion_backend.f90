! ==============================================================================
! Module: readline_completion_backend
! Purpose: Tab-completion candidate generation, filtering, and fuzzy scoring
!          (QUAL-13 split). A leaf over readline_state — no redraw/cursor calls;
!          the only terminal output is show_completions' plain listing. The
!          interactive tab-key glue and the menu/pager renderer stay in readline.
!          Re-exported by readline so `use readline` consumers are unchanged.
! ==============================================================================
module readline_completion_backend
  use readline_constants
  use readline_state
  use shell_types
  use system_interface
  use completion, only: get_completion_spec, generate_completions, &
                        completion_spec_t, MAX_COMPLETIONS
  use glob, only: pattern_matches
  use string_utils, only: to_lowercase => char_lower
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding
  implicit none

contains

  ! Basic tab completion - simplified implementation
  subroutine tab_complete(partial_input, completions, num_completions)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)  ! Max 50 completions
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: last_word
    integer :: last_space_pos, i
    
    num_completions = 0
    
    ! Find the last word to complete
    last_space_pos = 0
    do i = len_trim(partial_input), 1, -1
      if (partial_input(i:i) == ' ') then
        last_space_pos = i
        exit
      end if
    end do
    
    if (last_space_pos == 0) then
      last_word = trim(partial_input)
    else
      last_word = trim(partial_input(last_space_pos+1:))
    end if
    
    ! If it's the first word, complete commands
    if (last_space_pos == 0) then
      call complete_commands(last_word, completions, num_completions)
    else
      ! Otherwise, complete files/directories
      call complete_files(last_word, completions, num_completions)
    end if
  end subroutine

  ! Enhanced tab completion with programmable completion system integration
  subroutine enhanced_tab_complete(partial_input, completions, num_completions, shell, input_len)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    type(shell_state_t), intent(inout), optional :: shell
    integer, intent(in), optional :: input_len

    character(len=MAX_LINE_LEN) :: last_word, prefix_part, command_name
    character(len=256) :: temp_completions(MAX_COMPLETIONS)  ! Must match completion module's expectation
    integer :: last_space_pos, i, first_space_pos, temp_count, actual_len
    logical :: is_command, used_programmable_completion
    type(completion_spec_t) :: spec

    ! Use provided length if given, otherwise use len_trim
    if (present(input_len)) then
      actual_len = input_len
    else
      actual_len = len_trim(partial_input)
    end if

    num_completions = 0
    used_programmable_completion = .false.

    ! Find the last word to complete (respect quotes)
    last_space_pos = 0
    block
      logical :: in_sq, in_dq
      in_sq = .false.
      in_dq = .false.
      do i = 1, actual_len
        if (partial_input(i:i) == "'" .and. .not. in_dq) then
          in_sq = .not. in_sq
        else if (partial_input(i:i) == '"' .and. .not. in_sq) then
          in_dq = .not. in_dq
        else if (partial_input(i:i) == ' ' .and. .not. in_sq .and. .not. in_dq) then
          last_space_pos = i
        end if
      end do
    end block

    if (last_space_pos == 0) then
      last_word = trim(partial_input)
      prefix_part = ''
      is_command = .true.
      command_name = ''
    else
      last_word = trim(partial_input(last_space_pos+1:))
      prefix_part = partial_input(:last_space_pos)
      is_command = .false.

      ! Extract command name (first word)
      first_space_pos = index(partial_input, ' ')
      if (first_space_pos > 0) then
        command_name = partial_input(:first_space_pos-1)
      else
        command_name = trim(partial_input)
      end if
    end if

    ! Try programmable completion first (if shell state available and not completing command)
    if (.not. is_command .and. present(shell)) then
      spec = get_completion_spec(trim(command_name))
      if (spec%is_active) then
        ! Use our programmable completion system!
        call generate_completions(trim(command_name), trim(last_word), temp_completions, temp_count, shell)
        if (temp_count > 0) then
          ! Copy completions (convert from 256 to MAX_LINE_LEN)
          do i = 1, min(temp_count, MAX_LOCAL_COMPLETIONS)
            completions(i) = trim(temp_completions(i))
          end do
          num_completions = min(temp_count, MAX_LOCAL_COMPLETIONS)
          completion_total_matches = completion_total_matches + temp_count
          if (pager_collect) then
            do i = 1, temp_count
              if (pager_item_count >= PAGER_STORE_MAX) exit
              pager_item_count = pager_item_count + 1
              pager_items(pager_item_count) = temp_completions(i)(1:min(len(temp_completions(i)), MAX_MENU_ITEM_LEN))
            end do
          end if
          used_programmable_completion = .true.
        end if
      end if
    end if

    ! Fall back to default completion if programmable completion didn't produce results
    if (.not. used_programmable_completion) then
      if (is_command) then
        ! Check if this looks like a directory path for cd-less navigation
        if (looks_like_directory_path(last_word)) then
          ! Complete as files/directories for path-like input
          if (has_glob_chars(last_word)) then
            call expand_glob_for_completion(last_word, completions, num_completions)
          else
            call complete_files_enhanced(last_word, completions, num_completions)
          end if
          ! Command position: a command must be runnable, so keep only
          ! executables (to run) and directories (to descend) — fish's two-pass
          ! EXECUTABLES_ONLY + DIRECTORIES_ONLY. This replaces the old behavior
          ! that filtered to dirs-only on a trailing-slash path (dropping
          ! executables on `./`+Tab) and applied NO filter when a pattern was
          ! present (offering plain data files like `./readme.txt`). (AR-02
          ! cand-2/3)
          call filter_executables_and_dirs_only(completions, num_completions)
        else
          ! Complete commands (builtins + PATH executables)
          call complete_commands_enhanced(last_word, completions, num_completions)
        end if

        ! Add prefix back to completions
        do i = 1, num_completions
          completions(i) = trim(completions(i))
        end do
      else
        ! Option/flag completion (AR-02b CR-3): a '-'-leading argument
        ! completes from the command's bundled option table. Falls through to
        ! file completion when the command has no table or none of its options
        ! match (e.g. `cmd -xyz`), so `-`-words without a spec still behave.
        if (len_trim(last_word) >= 1 .and. last_word(1:1) == '-') then
          call complete_command_options(command_name, last_word, completions, num_completions)
        end if

        if (num_completions == 0) then
          ! Check if completing a variable name ($VAR)
          if (len_trim(last_word) >= 1 .and. last_word(1:1) == '$') then
            ! Variable completion (AR-06b: >=1 so a lone `$` lists all vars, like
            ! fish; complete_variable_names with an empty prefix matches all).
            ! Passing shell adds unexported locals (absent => environ only).
            call complete_variable_names(last_word, completions, num_completions, shell)
          else if (len_trim(last_word) >= 1 .and. last_word(1:1) == '~' .and. &
                   index(trim(last_word), '/') == 0) then
            ! ~user completion (AR-06b): no slash yet, so complete the username
            ! (e.g. ~ro -> ~root/). ~/path and ~user/path go through file completion.
            call complete_user_names(last_word, completions, num_completions)
          else if (has_glob_chars(last_word)) then
            ! Expand glob pattern instead of regular file completion
            call expand_glob_for_completion(last_word, completions, num_completions)
          else
            ! Complete files and directories normally
            call complete_files_enhanced(last_word, completions, num_completions)
          end if

          ! Filter completions based on command type
          ! cd, pushd, popd should only show directories
          if (trim(command_name) == 'cd' .or. trim(command_name) == 'pushd' .or. &
              trim(command_name) == 'popd') then
            call filter_directories_only(completions, num_completions)
          end if
        end if

        ! Don't add prefix to completions - they are for display only
        ! The prefix will be added when constructing the completed line
      end if
    end if
  end subroutine

  ! Filter completions to only keep directories (entries ending with /)
  subroutine filter_directories_only(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: temp_completions(MAX_LOCAL_COMPLETIONS)  ! Local temp storage
    integer :: i, new_count, original_count

    original_count = num_completions
    new_count = 0
    do i = 1, num_completions
      ! Keep only entries that end with / (directories)
      if (len_trim(completions(i)) > 0) then
        if (completions(i)(len_trim(completions(i)):len_trim(completions(i))) == '/') then
          new_count = new_count + 1
          temp_completions(new_count) = completions(i)
        end if
      end if
    end do

    ! Copy filtered results back
    do i = 1, new_count
      completions(i) = temp_completions(i)
    end do
    num_completions = new_count

    ! Filter the pager store the same way so directory-only menus
    ! (cd/pushd/popd) never page through files
    if (pager_item_count > 0) then
      new_count = 0
      do i = 1, pager_item_count
        if (len_trim(pager_items(i)) > 0) then
          if (pager_items(i)(len_trim(pager_items(i)):len_trim(pager_items(i))) == '/') then
            new_count = new_count + 1
            pager_items(new_count) = pager_items(i)
          end if
        end if
      end do
      pager_item_count = new_count
    end if

    ! The directory-only count of matches beyond the stored cap is
    ! unknowable, so the "more items" indicator must not claim one
    completion_total_matches = 0
  end subroutine

  ! True if a completion string is something runnable as a command: a directory
  ! (trailing '/', to descend into) or an executable file (access X_OK).
  ! Handles a leading ~ for the access test.
  function is_exec_or_dir_completion(path) result(keep)
    character(len=*), intent(in) :: path
    logical :: keep
    character(len=MAX_LINE_LEN) :: resolved
    character(len=:), allocatable :: home
    integer :: plen

    keep = .false.
    plen = len_trim(path)
    if (plen == 0) return
    if (path(plen:plen) == '/') then
      keep = .true.            ! directory — keep to allow descending
      return
    end if
    resolved = path(1:plen)
    if (path(1:1) == '~' .and. plen >= 2) then
      if (path(2:2) == '/') then
        home = get_environment_var('HOME')
        if (allocated(home)) then
          if (len(home) > 0) resolved = trim(home) // path(2:plen)
        end if
      end if
    end if
    keep = file_is_executable(trim(resolved))
  end function is_exec_or_dir_completion

  ! Filter completions to executables-or-directories (command position). A
  ! command must be runnable, so plain data files are dropped. Mirrors
  ! filter_directories_only: filters both the completion array AND the pager
  ! store so the menu shows the same set. (AR-02 cand-2/3)
  subroutine filter_executables_and_dirs_only(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    character(len=MAX_LINE_LEN) :: temp_completions(MAX_LOCAL_COMPLETIONS)
    integer :: i, new_count

    new_count = 0
    do i = 1, num_completions
      if (is_exec_or_dir_completion(completions(i))) then
        new_count = new_count + 1
        temp_completions(new_count) = completions(i)
      end if
    end do
    do i = 1, new_count
      completions(i) = temp_completions(i)
    end do
    num_completions = new_count

    if (pager_item_count > 0) then
      new_count = 0
      do i = 1, pager_item_count
        if (is_exec_or_dir_completion(pager_items(i))) then
          new_count = new_count + 1
          pager_items(new_count) = pager_items(i)
        end if
      end do
      pager_item_count = new_count
    end if

    ! filtered count beyond the stored cap is unknowable; suppress the
    ! "more items" indicator rather than claim a wrong total
    completion_total_matches = 0
  end subroutine

  ! Check if a string contains glob characters
  function has_glob_chars(str) result(has_globs)
    character(len=*), intent(in) :: str
    logical :: has_globs

    has_globs = (index(str, '*') > 0 .or. &
                 index(str, '?') > 0 .or. &
                 index(str, '[') > 0)
  end function has_glob_chars

  ! Check if a string looks like a directory path (for cd-less navigation)
  function looks_like_directory_path(str) result(looks_like_path)
    character(len=*), intent(in) :: str
    logical :: looks_like_path
    character(len=:), allocatable :: trimmed

    trimmed = trim(str)
    if (len(trimmed) == 0) then
      looks_like_path = .false.
      return
    end if

    ! Check for path indicators:
    ! - Starts with / (absolute path)
    ! - Starts with ~ (home directory)
    ! - Starts with . (current/parent directory)
    ! - Contains / anywhere (path separator)
    looks_like_path = (trimmed(1:1) == '/' .or. &
                       trimmed(1:1) == '~' .or. &
                       trimmed(1:1) == '.' .or. &
                       index(trimmed, '/') > 0)
  end function looks_like_directory_path

  ! Expand glob pattern for tab completion using real filesystem
  subroutine expand_glob_for_completion(pattern, completions, num_completions)
    character(len=*), intent(in) :: pattern
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    integer, parameter :: MAX_DIR_ENTRIES = 16384  ! AR-06: 4x coverage (was 4096)
    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    character(len=256), allocatable :: entries(:)
    logical, allocatable :: is_dir_flags(:)
    integer :: num_entries, i, last_slash_pos
    character(len=MAX_LINE_LEN) :: full_path
    logical :: is_dir

    num_completions = 0

    ! Extract directory path and filename pattern (same logic as complete_files_enhanced)
    last_slash_pos = 0
    do i = len_trim(pattern), 1, -1
      if (pattern(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do

    if (last_slash_pos > 0) then
      dir_path = pattern(:last_slash_pos-1)
      file_pattern = pattern(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(pattern)
    end if

    ! Enumerate the directory natively (opendir/readdir) — same as scan_directory
    allocate(entries(MAX_DIR_ENTRIES), is_dir_flags(MAX_DIR_ENTRIES))
    call list_directory(trim(dir_path), entries, is_dir_flags, num_entries)

    ! Match entries against glob pattern. Keep scanning past the storage cap
    ! so the true match count reaches the menu's "more items" indicator.
    do i = 1, num_entries
      ! Skip . and ..
      if (trim(entries(i)) == '.' .or. trim(entries(i)) == '..') cycle

      ! Use pattern_matches from glob module to match against pattern
      if (pattern_matches(file_pattern, trim(entries(i)))) then
        completion_total_matches = completion_total_matches + 1
        if (num_completions >= MAX_LOCAL_COMPLETIONS .and. &
            (.not. pager_collect .or. pager_item_count >= PAGER_STORE_MAX)) cycle  ! count only

        ! Build full path
        if (trim(dir_path) == '.') then
          full_path = trim(entries(i))
        else
          full_path = trim(dir_path) // '/' // trim(entries(i))
        end if

        ! Directory-ness comes straight from readdir (no per-entry test -d)
        is_dir = is_dir_flags(i)
        if (is_dir) full_path = trim(full_path) // '/'
        if (num_completions < MAX_LOCAL_COMPLETIONS) then
          num_completions = num_completions + 1
          completions(num_completions) = trim(full_path)
        end if
        if (pager_collect .and. pager_item_count < PAGER_STORE_MAX) then
          pager_item_count = pager_item_count + 1
          pager_items(pager_item_count) = full_path(1:MAX_MENU_ITEM_LEN)
        end if
      end if
    end do

    ! Clean up allocatable arrays
    if (allocated(entries)) deallocate(entries)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine expand_glob_for_completion

  subroutine complete_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    
    character(len=50), parameter :: builtin_commands(19) = [ &
      'cd       ', 'echo     ', 'exit     ', 'export   ', &
      'pwd      ', 'jobs     ', 'fg       ', 'bg       ', &
      'history  ', 'source   ', 'test     ', 'if       ', &
      'kill     ', 'wait     ', 'trap     ', 'config   ', &
      'alias    ', 'unalias  ', 'help     ' &
    ]
    integer :: i, prefix_len
    
    num_completions = 0
    prefix_len = len_trim(prefix)
    
    ! Complete builtin commands
    do i = 1, size(builtin_commands)
      if (prefix_len == 0 .or. &
          index(trim(builtin_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        if (num_completions <= MAX_LOCAL_COMPLETIONS) then
          completions(num_completions) = trim(builtin_commands(i))
        end if
      end if
    end do
    
    ! TODO: Add external command completion from PATH
  end subroutine

  subroutine complete_files(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    
    character(len=MAX_LINE_LEN) :: dir_path, file_pattern
    integer :: last_slash_pos, i
    
    num_completions = 0
    
    ! Extract directory path and filename pattern
    last_slash_pos = 0
    do i = len_trim(prefix), 1, -1
      if (prefix(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do
    
    if (last_slash_pos > 0) then
      dir_path = prefix(:last_slash_pos-1)
      file_pattern = prefix(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(prefix)
    end if
    
    ! Don't add ./ and ../ automatically - they're not based on user input
    ! Let scan_directory find all matches naturally
    
    ! Add some common file extensions for demonstration
    if (len_trim(file_pattern) == 0) then
      if (num_completions < 47) then
        completions(num_completions + 1) = 'Makefile'
        completions(num_completions + 2) = 'README'
        completions(num_completions + 3) = 'LICENSE'
        num_completions = num_completions + 3
      end if
    end if
  end subroutine

  ! Enhanced command completion with PATH executable scanning
  subroutine complete_variable_names(prefix_with_dollar, completions, num_completions, shell)
    character(len=*), intent(in) :: prefix_with_dollar
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    type(shell_state_t), intent(in), optional :: shell

    character(len=256) :: var_prefix
    integer :: i, j, score, eqpos
    character(len=:), allocatable :: entry
    character(len=MAX_LINE_LEN) :: cand
    logical :: dup

    num_completions = 0
    ! Strip the $ from the prefix
    var_prefix = prefix_with_dollar(2:)

    ! Iterate the environment natively (no `env | cut | tr` subprocess); each
    ! entry is "NAME=value", so match on the NAME before '='.
    i = 0
    do
      entry = get_environ_entry(i)
      if (len(entry) == 0) exit  ! end of environ
      i = i + 1
      if (num_completions >= MAX_LOCAL_COMPLETIONS) cycle
      eqpos = index(entry, '=')
      if (eqpos <= 1) cycle
      score = fuzzy_match_score(trim(var_prefix), entry(1:eqpos-1))
      if (score >= 0) then
        num_completions = num_completions + 1
        completions(num_completions) = '$' // entry(1:eqpos-1)
      end if
      if (i > 100000) exit  ! safety bound
    end do

    ! Also offer unexported shell variables (AR-06b): the environ holds only
    ! exported names, but fish completes all in-scope variables. Dedupe against
    ! the exported names already added.
    if (present(shell)) then
      do i = 1, shell%num_variables
        if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
        if (len_trim(shell%variables(i)%name) == 0) cycle
        if (fuzzy_match_score(trim(var_prefix), trim(shell%variables(i)%name)) < 0) cycle
        cand = '$' // trim(shell%variables(i)%name)
        dup = .false.
        do j = 1, num_completions
          if (trim(completions(j)) == trim(cand)) then
            dup = .true.
            exit
          end if
        end do
        if (.not. dup) then
          num_completions = num_completions + 1
          completions(num_completions) = cand
        end if
      end do
    end if
  end subroutine

  ! ~user completion (AR-06b): the prefix is "~name" with no slash. Enumerate the
  ! passwd database for usernames starting with `name` and offer "~user/" for
  ! each (the trailing / both signals a directory and lets the next Tab descend).
  subroutine complete_user_names(prefix_with_tilde, completions, num_completions)
    character(len=*), intent(in) :: prefix_with_tilde
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=256) :: user_prefix
    character(len=256) :: matches(MAX_LOCAL_COMPLETIONS)
    integer :: i, count

    num_completions = 0
    ! Strip the leading '~'.
    user_prefix = prefix_with_tilde(2:)

    call get_user_matches(trim(user_prefix), matches, count)
    do i = 1, count
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      if (len_trim(matches(i)) == 0) cycle
      num_completions = num_completions + 1
      completions(num_completions) = '~' // trim(matches(i)) // '/'
    end do
  end subroutine

  ! Complete a command's options when the current argument starts with '-'
  ! (AR-02b CR-3). Driven by bundled static option tables for common commands;
  ! an unknown command yields nothing and the caller falls back to files.
  subroutine complete_command_options(command, prefix, completions, num_completions)
    character(len=*), intent(in) :: command, prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=32) :: opts(64)
    integer :: nopts, i, plen

    num_completions = 0
    call command_option_table(trim(command), opts, nopts)
    if (nopts == 0) return

    plen = len_trim(prefix)
    do i = 1, nopts
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      if (plen == 0) then
        num_completions = num_completions + 1
        completions(num_completions) = trim(opts(i))
      else if (len_trim(opts(i)) >= plen) then
        if (opts(i)(1:plen) == prefix(1:plen)) then
          num_completions = num_completions + 1
          completions(num_completions) = trim(opts(i))
        end if
      end if
    end do
  end subroutine

  ! Static option tables (long options + common short flags) for a handful of
  ! common commands. The MVP data set (AR-02b); user-defined option specs are a
  ! later AR. find/ps/git use single-dash primaries/options by convention.
  subroutine command_option_table(command, opts, nopts)
    character(len=*), intent(in) :: command
    character(len=32), intent(out) :: opts(:)
    integer, intent(out) :: nopts

    nopts = 0
    select case (command)
    case ('ls')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-a', '--all', '-A', '--almost-all', '-l', '-h', '--human-readable', &
        '-R', '--recursive', '-r', '--reverse', '-S', '-t', '--sort', &
        '-d', '--directory', '-i', '--inode', '--color', &
        '--group-directories-first', '--help', '--version'])
    case ('grep')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-E', '--extended-regexp', '-F', '--fixed-strings', '-i', '--ignore-case', &
        '-v', '--invert-match', '-w', '--word-regexp', '-c', '--count', &
        '-l', '--files-with-matches', '-n', '--line-number', '-r', '--recursive', &
        '-o', '--only-matching', '--color', '-A', '--after-context', &
        '-B', '--before-context', '-C', '--context', '--help', '--version'])
    case ('cp')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-a', '--archive', '-b', '--backup', '-f', '--force', '-i', '--interactive', &
        '-l', '--link', '-n', '--no-clobber', '-r', '-R', '--recursive', &
        '-s', '--symbolic-link', '-u', '--update', '-v', '--verbose', &
        '-p', '--preserve', '--help', '--version'])
    case ('mv')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-b', '--backup', '-f', '--force', '-i', '--interactive', &
        '-n', '--no-clobber', '-u', '--update', '-v', '--verbose', &
        '--help', '--version'])
    case ('rm')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-f', '--force', '-i', '--interactive', '-r', '-R', '--recursive', &
        '-d', '--dir', '-v', '--verbose', '--help', '--version'])
    case ('mkdir')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-m', '--mode', '-p', '--parents', '-v', '--verbose', '--help', '--version'])
    case ('cat')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-A', '--show-all', '-b', '--number-nonblank', '-E', '--show-ends', &
        '-n', '--number', '-s', '--squeeze-blank', '-T', '--show-tabs', &
        '-v', '--show-nonprinting', '--help', '--version'])
    case ('sort')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-b', '--ignore-leading-blanks', '-f', '--ignore-case', &
        '-n', '--numeric-sort', '-h', '--human-numeric-sort', '-r', '--reverse', &
        '-u', '--unique', '-k', '--key', '-t', '--field-separator', &
        '-o', '--output', '-c', '--check', '--help', '--version'])
    case ('head', 'tail')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-c', '--bytes', '-n', '--lines', '-q', '--quiet', '-v', '--verbose', &
        '-f', '--follow', '--help', '--version'])
    case ('wc')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-c', '--bytes', '-m', '--chars', '-l', '--lines', '-w', '--words', &
        '-L', '--max-line-length', '--help', '--version'])
    case ('find')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-name', '-iname', '-type', '-size', '-mtime', '-newer', '-maxdepth', &
        '-mindepth', '-path', '-regex', '-prune', '-print', '-print0', &
        '-delete', '-exec', '-empty', '-perm', '-user', '-group'])
    case ('ps')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-e', '-f', '-l', '-u', '-x', '-a', '-A', '-w', '-o', '--help', '--version'])
    case ('tar')
      call set_opts(opts, nopts, [character(len=32) :: &
        '-c', '--create', '-x', '--extract', '-t', '--list', '-f', '--file', &
        '-v', '--verbose', '-z', '--gzip', '-j', '--bzip2', '-J', '--xz', &
        '-C', '--directory', '--help', '--version'])
    case ('git')
      call set_opts(opts, nopts, [character(len=32) :: &
        '--version', '--help', '--bare', '--git-dir', '--work-tree', &
        '--paginate', '--no-pager', '--exec-path', '--html-path', &
        '--man-path', '--info-path', '-C', '-c'])
    end select
  end subroutine

  ! Copy an array-constructor option list into the output buffer.
  subroutine set_opts(opts, nopts, vals)
    character(len=32), intent(out) :: opts(:)
    integer, intent(out) :: nopts
    character(len=*), intent(in) :: vals(:)
    integer :: i
    nopts = min(size(vals), size(opts))
    do i = 1, nopts
      opts(i) = vals(i)
    end do
  end subroutine

  subroutine complete_commands_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=50), parameter :: builtin_commands(20) = [ &
      'cd       ', 'echo     ', 'exit     ', 'export   ', &
      'pwd      ', 'jobs     ', 'fg       ', 'bg       ', &
      'history  ', 'source   ', 'test     ', 'if       ', &
      'kill     ', 'wait     ', 'trap     ', 'config   ', &
      'alias    ', 'unalias  ', 'help     ', 'rawtest  ' &
    ]
    ! Use allocatable array to avoid static storage
    type(scored_completion_t), allocatable :: scored(:)
    integer :: i, num_scored, score

    ! Allocate scored array (room for builtins + a $PATH scan, capped at the
    ! pager store size; output is still trimmed to 50 below)
    allocate(scored(PAGER_STORE_MAX))
    num_completions = 0
    num_scored = 0

    ! Score builtin commands using fuzzy matching
    do i = 1, size(builtin_commands)
      score = fuzzy_match_score(prefix, trim(builtin_commands(i)))
      if (score >= 0) then  ! Negative score = no match
        num_scored = num_scored + 1
        if (num_scored <= size(scored)) then
          scored(num_scored)%text = trim(builtin_commands(i))
          scored(num_scored)%score = score
        end if
      end if
    end do

    ! Add common system commands (kept as a fallback; deduped by the PATH scan)
    call add_system_commands_fuzzy(prefix, scored, num_scored)

    ! Scan $PATH for executables matching the prefix (cand-1). This is what
    ! makes `pyt`+Tab complete python3/pytest instead of only ~35 hardcoded
    ! names. Deduped against builtins and common commands.
    call add_path_commands_fuzzy(prefix, scored, num_scored)

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy top matches to the output array, which is sized MAX_LOCAL_COMPLETIONS.
    ! (Was a literal 50 — a latent overflow that never fired until the $PATH
    ! scan let num_scored exceed 40, smashing the stack. The pager store below
    ! holds the full set for the scrollable menu.)
    num_completions = min(num_scored, MAX_LOCAL_COMPLETIONS)
    do i = 1, num_completions
      completions(i) = scored(i)%text
    end do
    completion_total_matches = completion_total_matches + num_scored

    ! Fill the pager store for menu scrolling
    if (pager_collect) then
      do i = 1, num_scored
        if (pager_item_count >= PAGER_STORE_MAX) exit
        pager_item_count = pager_item_count + 1
        pager_items(pager_item_count) = scored(i)%text(1:MAX_MENU_ITEM_LEN)
      end do
    end if

    ! Clean up allocatable array
    if (allocated(scored)) deallocate(scored)
  end subroutine

  subroutine add_system_commands(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    character(len=50), parameter :: common_commands(15) = [ &
      'ls       ', 'cat      ', 'grep     ', 'find     ', &
      'sort     ', 'head     ', 'tail     ', 'wc       ', &
      'cp       ', 'mv       ', 'rm       ', 'mkdir    ', &
      'rmdir    ', 'chmod    ', 'which    ' &
    ]
    integer :: i, prefix_len

    prefix_len = len_trim(prefix)

    do i = 1, size(common_commands)
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      if (prefix_len == 0 .or. &
          index(trim(common_commands(i)), prefix(1:prefix_len)) == 1) then
        num_completions = num_completions + 1
        completions(num_completions) = trim(common_commands(i))
      end if
    end do
  end subroutine

  ! Scan $PATH for executables whose basename starts with `prefix` and add them
  ! to the scored set (deduped by basename against what's already there). Prefix
  ! match (not fuzzy) keeps it cheap and matches fish's command completion; the
  ! cheap prefix test runs BEFORE the access(X_OK) syscall so we only stat
  ! candidates. Bounded by size(scored). (AR-02 cand-1)
  subroutine add_path_commands_fuzzy(prefix, scored, num_scored)
    character(len=*), intent(in) :: prefix
    type(scored_completion_t), intent(inout) :: scored(:)
    integer, intent(inout) :: num_scored

    integer, parameter :: DIR_ENTRIES = 4096
    character(len=:), allocatable :: path_env
    character(len=1024) :: dir
    character(len=256), allocatable :: names(:)
    logical, allocatable :: is_dir_flags(:)
    character(len=MAX_LINE_LEN) :: full_path
    integer :: num_entries, i, j, ds, sep, plen, path_len, score, cap, nlen
    logical :: dup

    path_env = get_environment_var('PATH')
    if (.not. allocated(path_env)) return
    path_len = len_trim(path_env)
    if (path_len == 0) return

    plen = len_trim(prefix)
    cap = size(scored)
    allocate(names(DIR_ENTRIES), is_dir_flags(DIR_ENTRIES))

    ! Walk PATH, splitting on ':'
    ds = 1
    do while (ds <= path_len)
      if (num_scored >= cap) exit
      sep = index(path_env(ds:path_len), ':')
      if (sep == 0) then
        dir = path_env(ds:path_len)
        ds = path_len + 1
      else
        dir = path_env(ds:ds+sep-2)
        ds = ds + sep
      end if
      if (len_trim(dir) == 0) cycle   ! empty PATH element

      call list_directory(trim(dir), names, is_dir_flags, num_entries)
      do i = 1, num_entries
        if (num_scored >= cap) exit
        if (is_dir_flags(i)) cycle    ! a command must be a file, not a dir
        nlen = len_trim(names(i))
        if (nlen == 0) cycle
        ! cheap prefix filter before the access() syscall
        if (plen > 0) then
          if (nlen < plen) cycle
          if (names(i)(1:plen) /= prefix(1:plen)) cycle
        end if
        full_path = trim(dir) // '/' // names(i)(1:nlen)
        if (.not. file_is_executable(trim(full_path))) cycle
        ! dedupe by basename (earlier PATH entry / builtin / common-cmd wins)
        dup = .false.
        do j = 1, num_scored
          if (trim(scored(j)%text) == names(i)(1:nlen)) then
            dup = .true.
            exit
          end if
        end do
        if (dup) cycle
        score = fuzzy_match_score(prefix, names(i)(1:nlen))
        if (score < 0) cycle
        num_scored = num_scored + 1
        scored(num_scored)%text = names(i)(1:nlen)
        scored(num_scored)%score = score
      end do
    end do

    if (allocated(names)) deallocate(names)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine add_path_commands_fuzzy

  ! Fuzzy version of add_system_commands
  subroutine add_system_commands_fuzzy(prefix, scored, num_scored)
    character(len=*), intent(in) :: prefix
    type(scored_completion_t), intent(inout) :: scored(:)
    integer, intent(inout) :: num_scored

    character(len=50), parameter :: common_commands(15) = [ &
      'ls       ', 'cat      ', 'grep     ', 'find     ', &
      'sort     ', 'head     ', 'tail     ', 'wc       ', &
      'cp       ', 'mv       ', 'rm       ', 'mkdir    ', &
      'rmdir    ', 'chmod    ', 'which    ' &
    ]
    integer :: i, score

    do i = 1, size(common_commands)
      if (num_scored >= size(scored)) exit
      score = fuzzy_match_score(prefix, trim(common_commands(i)))
      if (score >= 0) then  ! Negative score = no match
        num_scored = num_scored + 1
        scored(num_scored)%text = trim(common_commands(i))
        scored(num_scored)%score = score
      end if
    end do
  end subroutine

  ! Enhanced file completion with real filesystem access
  subroutine complete_files_enhanced(prefix, completions, num_completions)
    character(len=*), intent(in) :: prefix
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions

    character(len=MAX_LINE_LEN) :: dir_path, file_pattern, clean_prefix
    character(len=:), allocatable :: debug_mode
    integer :: last_slash_pos, i, cp_len
    logical :: debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

    num_completions = 0

    ! Strip leading/trailing quotes from prefix for filesystem access
    clean_prefix = trim(prefix)
    cp_len = len_trim(clean_prefix)
    if (cp_len >= 2) then
      if ((clean_prefix(1:1) == "'" .and. clean_prefix(cp_len:cp_len) == "'") .or. &
          (clean_prefix(1:1) == '"' .and. clean_prefix(cp_len:cp_len) == '"')) then
        clean_prefix = clean_prefix(2:cp_len-1)
      else if (clean_prefix(1:1) == "'" .or. clean_prefix(1:1) == '"') then
        ! Unclosed quote (user still typing) — strip leading quote only
        clean_prefix = clean_prefix(2:cp_len)
      end if
    end if

    ! Extract directory path and filename pattern
    last_slash_pos = 0
    last_slash_pos = 0
    do i = len_trim(clean_prefix), 1, -1
      if (clean_prefix(i:i) == '/') then
        last_slash_pos = i
        exit
      end if
    end do

    if (last_slash_pos > 0) then
      dir_path = clean_prefix(:last_slash_pos-1)
      file_pattern = clean_prefix(last_slash_pos+1:)
      if (len_trim(dir_path) == 0) dir_path = '/'
    else
      dir_path = '.'
      file_pattern = trim(clean_prefix)
    end if

    ! Preserve explicit "./" prefix: when user typed "./something", dir_path
    ! is "." but completions should include "./" to match what was typed.
    ! Pass "./" as dir_path so scan_directory builds paths with "./" prefix.
    if (len_trim(clean_prefix) >= 2 .and. clean_prefix(1:2) == './') then
      if (trim(dir_path) == '.') dir_path = './'
    end if

    ! scan_directory handles all matches including dotfiles when pattern is empty
    call scan_directory(dir_path, file_pattern, completions, num_completions)
  end subroutine

  ! Scan directory for matching files and directories (with fuzzy matching)
  subroutine scan_directory(dir_path, pattern, completions, num_completions)
    character(len=*), intent(in) :: dir_path, pattern
    character(len=MAX_LINE_LEN), intent(inout) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(inout) :: num_completions

    integer, parameter :: MAX_DIR_ENTRIES = 16384  ! AR-06: 4x coverage (was 4096)
    character(len=1024) :: expanded_dir
    character(len=256), allocatable :: entries(:)       ! one filename per slot
    logical, allocatable :: is_dir_flags(:)             ! parallel to entries
    character(len=MAX_LINE_LEN) :: full_path
    character(len=:), allocatable :: home_dir, debug_mode
    ! Use allocatable array to avoid static storage
    type(scored_completion_t), allocatable :: scored(:)
    integer :: num_entries, i, pattern_len, num_scored, score, j, total_matches
    logical :: is_dir, debug_enabled

    ! Check if debug mode is enabled
    debug_mode = get_environment_var('FORTSH_DEBUG_COMPLETION')
    debug_enabled = (allocated(debug_mode) .and. trim(debug_mode) == '1')

    ! Allocate scored array
    allocate(scored(MAX_SCORED_ITEMS))

    pattern_len = len_trim(pattern)

    ! Expand tilde if present (shell doesn't expand ~ inside quotes)
    expanded_dir = dir_path
    if (len_trim(dir_path) > 0 .and. dir_path(1:1) == '~') then
      home_dir = get_environment_var('HOME')
      if (allocated(home_dir) .and. len(home_dir) > 0) then
        if (len_trim(dir_path) == 1) then
          ! Just ~
          expanded_dir = home_dir
        else if (dir_path(2:2) == '/') then
          ! ~/something
          expanded_dir = trim(home_dir) // dir_path(2:)
        else
          ! ~user (not supported for now, just use as-is)
          expanded_dir = dir_path
        end if
      end if
    end if

    ! Enumerate the directory natively via opendir/readdir — no `ls` subprocess.
    ! This removes shell injection, dependence on the host `ls`/locale, and (the
    ! bug that started this) any chance of a subprocess printing onto the
    ! terminal mid-redraw. readdir reports directory-ness directly (symlinks to
    ! directories are followed). Pattern matching stays below in fuzzy_match_score.
    allocate(entries(MAX_DIR_ENTRIES), is_dir_flags(MAX_DIR_ENTRIES))
    call list_directory(trim(expanded_dir), entries, is_dir_flags, num_entries)

    ! Score entries using fuzzy matching. Keep scanning past the storage cap
    ! so total_matches reflects the real match count — the menu reports
    ! "... N more items available" from it.
    num_scored = 0
    total_matches = 0
    do i = 1, num_entries
      ! Hide dotfiles (incl. '.' and '..') unless the pattern itself starts with
      ! '.' (fish convention; AR-06). Previously only '.'/'..' were skipped, so a
      ! bare `ls `+Tab leaked .hidden/.bashrc into the candidate set.
      if (len_trim(entries(i)) > 0) then
        if (entries(i)(1:1) == '.') then
          if (pattern_len == 0 .or. pattern(1:1) /= '.') cycle
        end if
      end if

      ! Directory-ness comes straight from readdir; the name is already clean
      ! (no ls -F markers to strip).
      is_dir = is_dir_flags(i)
      full_path = trim(entries(i))

      ! Calculate fuzzy match score
      score = fuzzy_match_score(pattern, trim(full_path))
      if (score >= 0) then  ! Negative score = no match
        total_matches = total_matches + 1
        if (num_scored >= MAX_SCORED_ITEMS) cycle  ! count, but storage is full

        ! Build full path for display (use original dir_path to preserve ~ in display)
        if (trim(dir_path) == '.') then
          full_path = trim(full_path)
        else if (trim(dir_path) == './') then
          ! Explicit ./ prefix — preserve it without adding extra slash
          full_path = './' // trim(full_path)
        else if (trim(dir_path) == '/') then
          ! Root directory - don't add extra slash
          full_path = '/' // trim(full_path)
        else
          full_path = trim(dir_path) // '/' // trim(full_path)
        end if

        num_scored = num_scored + 1
        if (is_dir) then
          scored(num_scored)%text = trim(full_path) // '/'
        else
          scored(num_scored)%text = trim(full_path)
        end if
        scored(num_scored)%score = score

        ! Bonus for directories (make them appear first in same score bracket)
        if (is_dir) then
          scored(num_scored)%score = scored(num_scored)%score + 5
        end if
      end if
    end do

    completion_total_matches = completion_total_matches + total_matches

    ! Sort by score
    if (num_scored > 0) then
      call sort_completions_by_score(scored, num_scored)
    end if

    ! Copy to output (add to existing completions, limit to MAX_LOCAL_COMPLETIONS)
    do j = 1, num_scored
      if (num_completions >= MAX_LOCAL_COMPLETIONS) exit
      num_completions = num_completions + 1
      completions(num_completions) = scored(j)%text
    end do

    ! Fill the pager store with the full sorted set for menu scrolling
    if (pager_collect) then
      do j = 1, num_scored
        if (pager_item_count >= PAGER_STORE_MAX) exit
        pager_item_count = pager_item_count + 1
        pager_items(pager_item_count) = scored(j)%text(1:MAX_MENU_ITEM_LEN)
      end do
    end if

    ! Debug output
    if (debug_enabled) then
    end if

    ! Clean up allocatable arrays
    if (allocated(scored)) deallocate(scored)
    if (allocated(entries)) deallocate(entries)
    if (allocated(is_dir_flags)) deallocate(is_dir_flags)
  end subroutine


  ! Parse ls output into individual entries
  subroutine parse_ls_output(output, entries, num_entries, use_tab_delim)
    character(len=*), intent(in) :: output
    character(len=MAX_LINE_LEN), allocatable, intent(out) :: entries(:)
    integer, intent(out) :: num_entries
    logical, intent(in), optional :: use_tab_delim

    integer :: pos, start, output_len, count_pass
    logical :: tab_mode
    character :: delim

    tab_mode = .false.
    if (present(use_tab_delim)) tab_mode = use_tab_delim
    delim = merge(char(9), ' ', tab_mode)

    output_len = len_trim(output)

    ! First pass: count entries
    num_entries = 0
    pos = 1
    do while (pos <= output_len)
      ! Skip delimiter characters
      do while (pos <= output_len .and. (output(pos:pos) == delim .or. &
                (.not. tab_mode .and. output(pos:pos) == char(9))))
        pos = pos + 1
      end do

      if (pos > output_len) exit

      start = pos

      ! Find end of entry
      do while (pos <= output_len .and. output(pos:pos) /= delim)
        pos = pos + 1
      end do

      if (pos > start) then
        num_entries = num_entries + 1
      end if

      pos = pos + 1
    end do

    ! Allocate array based on actual count
    if (num_entries > 0) then
      allocate(entries(num_entries))

      ! Second pass: fill entries
      count_pass = 0
      pos = 1
      do while (pos <= output_len .and. count_pass < num_entries)
        ! Skip delimiter characters
        do while (pos <= output_len .and. (output(pos:pos) == delim .or. &
                  (.not. tab_mode .and. output(pos:pos) == char(9))))
          pos = pos + 1
        end do

        if (pos > output_len) exit

        start = pos

        ! Find end of entry
        do while (pos <= output_len .and. output(pos:pos) /= delim)
          pos = pos + 1
        end do

        if (pos > start) then
          count_pass = count_pass + 1
          entries(count_pass) = output(start:pos-1)
        end if

        pos = pos + 1
      end do
    else
      ! No entries - allocate empty array
      allocate(entries(0))
    end if
  end subroutine

  subroutine show_completions(completions, num_completions)
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(in) :: num_completions
    integer :: i, j, max_len, col_width, num_cols, items_in_row
    integer :: term_width, status
    character(len=10) :: cols_env

    if (num_completions > 1) then
      write(output_unit, '(a)') ''

      ! Find maximum length of completions
      max_len = 0
      do i = 1, num_completions
        max_len = max(max_len, len_trim(completions(i)))
      end do

      ! Column width = max length + 2 spaces padding
      col_width = max_len + 2

      ! Get terminal width (default to 80 if not available)
      call get_environment_variable("COLUMNS", cols_env, status=status)
      if (status == 0 .and. len_trim(cols_env) > 0) then
        read(cols_env, *, iostat=status) term_width
        if (status /= 0) term_width = 80
      else
        term_width = 80
      end if

      ! Calculate number of columns that fit
      num_cols = max(1, term_width / col_width)

      ! Print items in rows, aligned to columns
      do i = 1, num_completions
        ! Print item padded to column width (sanitize control/escape bytes in
        ! filenames so they can't inject terminal escape sequences)
        write(output_unit, '(a)', advance='no') sanitize_for_display(trim(completions(i)))

        ! Calculate position in current row
        items_in_row = mod(i - 1, num_cols) + 1

        ! Add padding unless it's the last item in the row or the last item overall
        if (items_in_row < num_cols .and. i < num_completions) then
          ! Pad to column width
          do j = len_trim(completions(i)) + 1, col_width
            write(output_unit, '(a)', advance='no') ' '
          end do
        else
          ! End of row - print newline
          write(output_unit, '(a)') ''
        end if
      end do

      ! Ensure we end with a blank line if last row wasn't complete
      if (mod(num_completions, num_cols) /= 0) then
        write(output_unit, '(a)') ''
      end if
    end if
  end subroutine

  ! Find common prefix among completions
  function get_common_prefix(completions, num_completions) result(prefix)
    character(len=MAX_LINE_LEN), intent(in) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(in) :: num_completions
    character(len=MAX_LINE_LEN) :: prefix
    
    integer :: i, j, min_len, common_len
    logical :: matches
    
    prefix = ''
    if (num_completions == 0) return
    
    if (num_completions == 1) then
      prefix = trim(completions(1))
      return
    end if
    
    ! Find minimum length
    min_len = len_trim(completions(1))
    do i = 2, num_completions
      min_len = min(min_len, len_trim(completions(i)))
    end do
    
    ! Find common prefix length
    common_len = 0
    do j = 1, min_len
      matches = .true.
      do i = 2, num_completions
        if (completions(1)(j:j) /= completions(i)(j:j)) then
          matches = .false.
          exit
        end if
      end do
      
      if (matches) then
        common_len = j
      else
        exit
      end if
    end do
    
    if (common_len > 0) then
      prefix = completions(1)(:common_len)
    end if
  end function

  ! Backslash-escape shell metacharacters in a filename for unquoted insertion.
  ! Matches bash's completion escaping: spaces, quotes, parens, etc.
  function escape_for_completion(input) result(output)
    character(len=*), intent(in) :: input
    character(len=:), allocatable :: output
    integer :: i, ilen, opos
    character(len=1) :: ch
    character(len=MAX_LINE_LEN) :: buf

    ilen = len_trim(input)
    opos = 1
    do i = 1, ilen
      ch = input(i:i)
      select case(ch)
      case(' ', "'", '"', '\', '(', ')', '&', '|', ';', '<', '>', &
           '*', '?', '[', ']', '{', '}', '$', '!', '#', '~', '`')
        if (opos + 1 <= MAX_LINE_LEN) then
          buf(opos:opos) = '\'
          opos = opos + 1
          buf(opos:opos) = ch
          opos = opos + 1
        end if
      case default
        if (opos <= MAX_LINE_LEN) then
          buf(opos:opos) = ch
          opos = opos + 1
        end if
      end select
    end do
    if (opos > 1) then
      output = buf(1:opos-1)
    else
      output = ''
    end if
  end function escape_for_completion

  ! Enhanced tab completion that handles partial completion
  subroutine smart_tab_complete(partial_input, completions, num_completions, completed_line, completed, input_len, shell)
    character(len=*), intent(in) :: partial_input
    character(len=MAX_LINE_LEN), intent(out) :: completions(MAX_LOCAL_COMPLETIONS)
    integer, intent(out) :: num_completions
    character(len=*), intent(out) :: completed_line
    logical, intent(out) :: completed
    integer, intent(in), optional :: input_len
    type(shell_state_t), intent(inout), optional :: shell

    character(len=MAX_LINE_LEN) :: common_prefix, prefix_part, last_word
    character(len=4096) :: expanded_matches
    integer :: last_space_pos, i, pos, j, actual_len
    logical :: is_glob_pattern

    ! Fresh completion run — backends below accumulate the true match count
    ! and (while pager_collect is set) fill the pager item store
    completion_total_matches = 0
    pager_item_count = 0
    pager_collect = .true.

    ! Use provided length if given, otherwise use len_trim
    if (present(input_len)) then
      actual_len = input_len
    else
      actual_len = len_trim(partial_input)
    end if

    completed = .false.
    completed_line = partial_input

    ! Find the prefix (command and any earlier arguments)
    ! Respect quotes: spaces inside quotes don't count as word boundaries
    last_space_pos = 0
    block
      logical :: in_single_quote, in_double_quote
      in_single_quote = .false.
      in_double_quote = .false.
      do i = 1, actual_len
        if (partial_input(i:i) == "'" .and. .not. in_double_quote) then
          in_single_quote = .not. in_single_quote
        else if (partial_input(i:i) == '"' .and. .not. in_single_quote) then
          in_double_quote = .not. in_double_quote
        else if (partial_input(i:i) == ' ' .and. .not. in_single_quote .and. .not. in_double_quote) then
          last_space_pos = i
        end if
      end do
    end block

    if (last_space_pos > 0) then
      prefix_part = partial_input(:last_space_pos)
      last_word = partial_input(last_space_pos+1:)
    else
      prefix_part = ''
      last_word = trim(partial_input)
    end if

    ! Check if we're completing a glob pattern
    is_glob_pattern = has_glob_chars(last_word)

    ! Pass the actual length to preserve trailing spaces
    call enhanced_tab_complete(partial_input, completions, num_completions, shell=shell, input_len=actual_len)

    ! Backends are done — stop pager collection so later backend calls
    ! (e.g. from the autosuggestion path) can't clobber the store
    pager_collect = .false.

    if (num_completions == 0) then
      ! No completions found
      return
    else if (num_completions == 1) then
      ! Single completion - reconstruct with proper quoting
      block
        character(len=1) :: quote_char
        integer :: lw_len

        lw_len = len_trim(last_word)
        quote_char = ' '

        ! Check if last_word starts with a quote
        if (lw_len > 0 .and. (last_word(1:1) == "'" .or. last_word(1:1) == '"')) then
          quote_char = last_word(1:1)
        end if

        ! Completions already include the full path from scan_directory.
        ! Just wrap in quotes if the original word was quoted.
        if (quote_char /= ' ') then
          if (last_space_pos > 0) then
            completed_line = prefix_part(:last_space_pos) // quote_char // &
              trim(completions(1)) // quote_char
          else
            completed_line = quote_char // trim(completions(1)) // quote_char
          end if
        else
          block
            character(len=:), allocatable :: comp_result
            ! Don't escape variable completions ($VAR) or command substitutions
            if (len_trim(completions(1)) > 0 .and. &
                (completions(1)(1:1) == '$' .or. completions(1)(1:1) == '~')) then
              comp_result = trim(completions(1))
            else
              comp_result = escape_for_completion(trim(completions(1)))
            end if
            if (last_space_pos > 0) then
              completed_line = prefix_part(:last_space_pos) // comp_result
            else
              completed_line = comp_result
            end if
          end block
        end if
      end block
      completed = .true.
    else
      ! Multiple completions
      if (is_glob_pattern) then
        ! For glob patterns: expand all matches into command line (like bash)
        ! Build space-separated list of all matches
        expanded_matches = ''
        pos = 1

        do j = 1, num_completions
          if (j > 1) then
            expanded_matches(pos:pos) = ' '
            pos = pos + 1
          end if

          block
            character(len=:), allocatable :: esc_match
            if (len_trim(completions(j)) > 0 .and. &
                (completions(j)(1:1) == '$' .or. completions(j)(1:1) == '~')) then
              esc_match = trim(completions(j))
            else
              esc_match = escape_for_completion(trim(completions(j)))
            end if
            expanded_matches(pos:pos+len(esc_match)-1) = esc_match
            pos = pos + len(esc_match)
          end block
        end do

        ! Replace glob pattern with expanded matches
        if (last_space_pos > 0) then
          completed_line = prefix_part(:last_space_pos) // expanded_matches(:pos-1)
        else
          completed_line = expanded_matches(:pos-1)
        end if
        completed = .true.
      else
        ! For regular completion: try common prefix
        common_prefix = get_common_prefix(completions, num_completions)

        if (len_trim(common_prefix) > len_trim(last_word)) then
          ! We have a common prefix that extends what user typed - use it
          if (last_space_pos > 0) then
            completed_line = prefix_part(:last_space_pos) // trim(common_prefix)
          else
            completed_line = trim(common_prefix)
          end if
          completed = .true.
        else
          ! No useful common prefix - we'll show the completions list instead
          ! Keep completed = .false. but don't treat as "no completions"
          ! The caller will see num_completions > 0 and should show them
          completed = .false.
        end if
      end if
    end if
  end subroutine

  ! ===========================================================================
  ! Fuzzy Matching Functions
  ! ===========================================================================

  ! Calculate fuzzy match score (higher = better match)
  ! Returns -1 if no match (pattern chars not found in order)
  ! Returns 0+ for matches with bonus points for:
  !   - Consecutive character matches
  !   - Matches at word boundaries
  !   - Matches at start of string
  function fuzzy_match_score(pattern, candidate) result(score)
    character(len=*), intent(in) :: pattern, candidate
    integer :: score

    integer :: pattern_len, candidate_len
    integer :: pattern_idx, candidate_idx
    integer :: match_positions(MAX_LINE_LEN)
    integer :: num_matches, i
    integer :: consecutive_bonus, boundary_bonus
    logical :: case_match, is_prefix_match
    character :: pattern_char, candidate_char

    ! Initialize match_positions to avoid uninitialized warning
    match_positions = 0

    pattern_len = len_trim(pattern)
    candidate_len = len_trim(candidate)

    ! Empty pattern matches everything with base score
    if (pattern_len == 0) then
      score = 100
      return
    end if

    ! Pattern longer than candidate = no match
    if (pattern_len > candidate_len) then
      score = -1
      return
    end if

    ! Require a prefix match unless fuzzy-complete is enabled (AR-06).
    ! With fuzzy off (default): behaves like bash/zsh — only prefix matches.
    ! With fuzzy on (set -o fuzzy-complete): uniform fuzzy subsequence matching
    ! at any length (dropped the arbitrary len<=3 gate, which fish has no
    ! analogue for) — EXCEPT an option-looking token (leading '-') stays prefix,
    ! so `-x`+Tab doesn't fuzzily match unrelated flags.
    if (.not. global_fuzzy_complete .or. pattern(1:1) == '-') then
      is_prefix_match = .true.
      do i = 1, pattern_len
        if (to_lowercase(pattern(i:i)) /= to_lowercase(candidate(i:i))) then
          is_prefix_match = .false.
          exit
        end if
      end do
      if (.not. is_prefix_match) then
        score = -1
        return
      end if
    end if

    ! Find all pattern characters in order
    pattern_idx = 1
    num_matches = 0

    do candidate_idx = 1, candidate_len
      if (pattern_idx > pattern_len) exit

      pattern_char = pattern(pattern_idx:pattern_idx)
      candidate_char = candidate(candidate_idx:candidate_idx)

      ! Case-insensitive comparison
      if (to_lowercase(pattern_char) == to_lowercase(candidate_char)) then
        num_matches = num_matches + 1
        match_positions(num_matches) = candidate_idx
        pattern_idx = pattern_idx + 1
      end if
    end do

    ! Not all pattern characters found = no match
    if (pattern_idx <= pattern_len) then
      score = -1
      return
    end if

    ! Base score: 100 points for matching
    score = 100

    ! Bonus for matching at start
    if (match_positions(1) == 1) then
      score = score + 50
    end if

    ! Bonus for consecutive matches
    consecutive_bonus = 0
    do i = 2, num_matches
      if (match_positions(i) == match_positions(i-1) + 1) then
        consecutive_bonus = consecutive_bonus + 10
      end if
    end do
    score = score + consecutive_bonus

    ! Bonus for matches at word boundaries (after space, -, _, /)
    boundary_bonus = 0
    do i = 1, num_matches
      if (match_positions(i) > 1) then
        candidate_char = candidate(match_positions(i)-1:match_positions(i)-1)
        if (candidate_char == ' ' .or. candidate_char == '-' .or. &
            candidate_char == '_' .or. candidate_char == '/') then
          boundary_bonus = boundary_bonus + 15
        end if
      end if
    end do
    score = score + boundary_bonus

    ! Bonus for case-sensitive match
    case_match = .true.
    do i = 1, num_matches
      pattern_char = pattern(i:i)
      candidate_char = candidate(match_positions(i):match_positions(i))
      if (pattern_char /= candidate_char) then
        case_match = .false.
        exit
      end if
    end do
    if (case_match) then
      score = score + 20
    end if

    ! Penalty for longer candidates (prefer shorter matches)
    score = score - (candidate_len - pattern_len)

    ! Penalty for gaps between matches
    do i = 2, num_matches
      score = score - (match_positions(i) - match_positions(i-1) - 1)
    end do
  end function

  ! Sort completions by fuzzy match score (bubble sort - good enough for small arrays)
  subroutine sort_completions_by_score(scored_completions, count)
    type(scored_completion_t), intent(inout) :: scored_completions(:)
    integer, intent(in) :: count

    type(scored_completion_t) :: temp
    integer :: i, j
    logical :: swapped

    ! Bubble sort (descending order - highest scores first)
    do i = 1, count - 1
      swapped = .false.
      do j = 1, count - i
        if (scored_completions(j)%score < scored_completions(j+1)%score) then
          temp = scored_completions(j)
          scored_completions(j) = scored_completions(j+1)
          scored_completions(j+1) = temp
          swapped = .true.
        end if
      end do
      if (.not. swapped) exit
    end do
  end subroutine

end module readline_completion_backend
