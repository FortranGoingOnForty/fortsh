! ==============================================================================
! Module: completion
! Purpose: Programmable completion system for fortsh (bash-compatible)
! ==============================================================================
module completion
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  use iso_c_binding, only: c_ptr, c_null_char, c_associated
#ifdef USE_MEMORY_POOL
  use string_pool
#endif
  implicit none

  ! Forward declarations for optional dependencies
  ! variables module will be used in specific subroutines

  ! Maximum number of completion specifications
  ! REDUCED to avoid static storage (was 100 specs * 256KB = 25.6MB!)
  integer, parameter :: MAX_COMPLETION_SPECS = 20   ! 20 specs max (was 100)
  integer, parameter :: MAX_WORD_LIST = 50          ! 50 words per spec (was 1000!)
  integer, parameter :: MAX_COMPLETIONS = 50        ! 50 completions (was 1000!)

  ! Completion specification type
  type :: completion_spec_t
    character(len=256) :: command              ! Command this spec applies to
    character(len=256) :: word_list(MAX_WORD_LIST)  ! Static word list (-W)
    integer :: word_list_count
    character(len=256) :: function_name        ! Completion function (-F)
    character(len=256) :: filter_pattern       ! Filter pattern (-X)
    character(len=256) :: prefix               ! Prefix to add (-P)
    character(len=256) :: suffix               ! Suffix to add (-S)
    logical :: use_default                     ! Use default completion (-o default)
    logical :: use_dirnames                    ! Complete directory names (-o dirnames)
    logical :: use_filenames                   ! Complete filenames (-o filenames)
    logical :: nospace                         ! Don't add space after (-o nospace)
    logical :: plusdirs                        ! Add directory completion (+o plusdirs)
    logical :: nosort                          ! Don't sort results (-o nosort)
    ! Built-in completers
    logical :: builtin_alias                   ! Complete aliases (-A alias)
    logical :: builtin_command                 ! Complete commands (-A command)
    logical :: builtin_directory               ! Complete directories (-A directory)
    logical :: builtin_file                    ! Complete files (-A file)
    logical :: builtin_function                ! Complete functions (-A function)
    logical :: builtin_hostname                ! Complete hostnames (-A hostname)
    logical :: builtin_variable                ! Complete variables (-A variable)
    logical :: builtin_user                    ! Complete usernames (-A user)
    logical :: builtin_group                   ! Complete groups (-A group)
    logical :: builtin_service                 ! Complete services (-A service)
    logical :: builtin_export                  ! Complete exported vars (-A export)
    logical :: builtin_keyword                 ! Complete shell keywords (-A keyword)
    logical :: builtin_builtin                 ! Complete builtins (-A builtin)
    logical :: is_active                       ! Whether this spec is active
  end type completion_spec_t

  ! Global completion specs storage
  type(completion_spec_t), save :: completion_specs(MAX_COMPLETION_SPECS)
  integer, save :: num_completion_specs = 0

  ! Current completion context (set during completion)
  type :: completion_context_t
    character(len=1024) :: comp_line           ! Full command line
    integer :: comp_point                      ! Cursor position
    character(len=256) :: comp_words(50)       ! Words in command line
    integer :: comp_cword                      ! Index of word being completed
    integer :: comp_word_count                 ! Total words
    character(len=256) :: comp_word_prefix     ! Word being completed
  end type completion_context_t

  type(completion_context_t), save :: current_comp_context

  ! ===========================================================================
  ! CALLBACK INTERFACE FOR FUNCTION EXECUTION
  ! This allows the executor module to register itself without circular deps
  ! ===========================================================================

  ! Abstract interface for completion function execution callback
  abstract interface
    subroutine completion_func_executor_t(shell, func_name, command, word, prev_word)
      import :: shell_state_t
      type(shell_state_t), intent(inout) :: shell
      character(len=*), intent(in) :: func_name
      character(len=*), intent(in) :: command
      character(len=*), intent(in) :: word
      character(len=*), intent(in) :: prev_word
    end subroutine completion_func_executor_t
  end interface

  ! Procedure pointer for function execution (set by executor at startup)
  procedure(completion_func_executor_t), pointer, save :: completion_func_executor => null()

  ! Public interface for callback registration
  public :: register_completion_executor, completion_func_executor_t

contains

  ! Initialize the completion system
  subroutine init_completion_system()
    integer :: i

    num_completion_specs = 0
    do i = 1, MAX_COMPLETION_SPECS
      completion_specs(i)%is_active = .false.
      completion_specs(i)%command = ''
      completion_specs(i)%word_list_count = 0
      completion_specs(i)%function_name = ''
      completion_specs(i)%filter_pattern = ''
      completion_specs(i)%prefix = ''
      completion_specs(i)%suffix = ''
      completion_specs(i)%use_default = .false.
      completion_specs(i)%use_dirnames = .false.
      completion_specs(i)%use_filenames = .false.
      completion_specs(i)%nospace = .false.
      completion_specs(i)%plusdirs = .false.
      completion_specs(i)%nosort = .false.
      completion_specs(i)%builtin_alias = .false.
      completion_specs(i)%builtin_command = .false.
      completion_specs(i)%builtin_directory = .false.
      completion_specs(i)%builtin_file = .false.
      completion_specs(i)%builtin_function = .false.
      completion_specs(i)%builtin_hostname = .false.
      completion_specs(i)%builtin_variable = .false.
      completion_specs(i)%builtin_user = .false.
      completion_specs(i)%builtin_group = .false.
      completion_specs(i)%builtin_service = .false.
      completion_specs(i)%builtin_export = .false.
      completion_specs(i)%builtin_keyword = .false.
      completion_specs(i)%builtin_builtin = .false.
    end do
  end subroutine init_completion_system

  ! Register the completion function executor callback
  ! Called by executor module at shell startup to avoid circular dependency
  subroutine register_completion_executor(executor_proc)
    procedure(completion_func_executor_t) :: executor_proc

    completion_func_executor => executor_proc
  end subroutine register_completion_executor

  ! Register a new completion spec
  function register_completion_spec(spec) result(success)
    type(completion_spec_t), intent(in) :: spec
    logical :: success
    integer :: i, existing_idx

    success = .false.
    existing_idx = -1

    ! Check if a spec already exists for this command
    do i = 1, num_completion_specs
      if (completion_specs(i)%is_active .and. &
          trim(completion_specs(i)%command) == trim(spec%command)) then
        existing_idx = i
        exit
      end if
    end do

    if (existing_idx > 0) then
      ! Replace existing spec
      completion_specs(existing_idx) = spec
      completion_specs(existing_idx)%is_active = .true.
      success = .true.
    else if (num_completion_specs < MAX_COMPLETION_SPECS) then
      ! Add new spec
      num_completion_specs = num_completion_specs + 1
      completion_specs(num_completion_specs) = spec
      completion_specs(num_completion_specs)%is_active = .true.
      success = .true.
    end if
  end function register_completion_spec

  ! Get completion spec for a command
  function get_completion_spec(command) result(spec)
    character(len=*), intent(in) :: command
    type(completion_spec_t) :: spec
    integer :: i

    ! Initialize result
    spec%is_active = .false.
    spec%command = ''
    spec%word_list_count = 0

    ! Search for matching spec
    do i = 1, num_completion_specs
      if (completion_specs(i)%is_active .and. &
          trim(completion_specs(i)%command) == trim(command)) then
        spec = completion_specs(i)
        return
      end if
    end do
  end function get_completion_spec

  ! Remove completion spec for a command
  function remove_completion_spec(command) result(success)
    character(len=*), intent(in) :: command
    logical :: success
    integer :: i

    success = .false.
    do i = 1, num_completion_specs
      if (completion_specs(i)%is_active .and. &
          trim(completion_specs(i)%command) == trim(command)) then
        completion_specs(i)%is_active = .false.
        success = .true.
        return
      end if
    end do
  end function remove_completion_spec

  ! Clear all completion specs
  subroutine clear_completion_specs()
    integer :: i
    do i = 1, num_completion_specs
      completion_specs(i)%is_active = .false.
    end do
    num_completion_specs = 0
  end subroutine clear_completion_specs

  ! List all registered completion specs
  subroutine list_completion_specs()
    integer :: i
    logical :: found_any

    found_any = .false.
    do i = 1, num_completion_specs
      if (completion_specs(i)%is_active) then
        found_any = .true.
        write(output_unit, '(a)', advance='no') 'complete'

        ! Print word list if present
        if (completion_specs(i)%word_list_count > 0) then
          write(output_unit, '(a)', advance='no') ' -W "...'
        end if

        ! Print function if present
        if (len_trim(completion_specs(i)%function_name) > 0) then
          write(output_unit, '(a)', advance='no') ' -F ' // trim(completion_specs(i)%function_name)
        end if

        ! Print built-in completers
        if (completion_specs(i)%builtin_command) then
          write(output_unit, '(a)', advance='no') ' -A command'
        end if
        if (completion_specs(i)%builtin_file) then
          write(output_unit, '(a)', advance='no') ' -A file'
        end if
        if (completion_specs(i)%builtin_directory) then
          write(output_unit, '(a)', advance='no') ' -A directory'
        end if
        if (completion_specs(i)%builtin_variable) then
          write(output_unit, '(a)', advance='no') ' -A variable'
        end if
        if (completion_specs(i)%builtin_function) then
          write(output_unit, '(a)', advance='no') ' -A function'
        end if
        if (completion_specs(i)%builtin_alias) then
          write(output_unit, '(a)', advance='no') ' -A alias'
        end if
        if (completion_specs(i)%builtin_builtin) then
          write(output_unit, '(a)', advance='no') ' -A builtin'
        end if
        if (completion_specs(i)%builtin_keyword) then
          write(output_unit, '(a)', advance='no') ' -A keyword'
        end if
        if (completion_specs(i)%builtin_hostname) then
          write(output_unit, '(a)', advance='no') ' -A hostname'
        end if
        if (completion_specs(i)%builtin_user) then
          write(output_unit, '(a)', advance='no') ' -A user'
        end if

        ! Print options
        if (completion_specs(i)%use_default) then
          write(output_unit, '(a)', advance='no') ' -o default'
        end if
        if (completion_specs(i)%use_dirnames) then
          write(output_unit, '(a)', advance='no') ' -o dirnames'
        end if
        if (completion_specs(i)%use_filenames) then
          write(output_unit, '(a)', advance='no') ' -o filenames'
        end if
        if (completion_specs(i)%nospace) then
          write(output_unit, '(a)', advance='no') ' -o nospace'
        end if
        if (completion_specs(i)%nosort) then
          write(output_unit, '(a)', advance='no') ' -o nosort'
        end if

        ! Print command name
        write(output_unit, '(a)') ' ' // trim(completion_specs(i)%command)
      end if
    end do

    if (.not. found_any) then
      ! No output for empty list (matches bash behavior)
    end if
  end subroutine list_completion_specs

  ! Parse word list from -W argument
  subroutine parse_word_list(word_list_str, spec)
    character(len=*), intent(in) :: word_list_str
    type(completion_spec_t), intent(inout) :: spec
    integer :: i, start, pos, str_len
    logical :: in_quotes
    character(len=1) :: quote_char

    spec%word_list_count = 0
    i = 1
    str_len = len_trim(word_list_str)

    do while (i <= str_len .and. spec%word_list_count < MAX_WORD_LIST)
      ! Skip leading spaces
      do while (i <= str_len .and. word_list_str(i:i) == ' ')
        i = i + 1
      end do
      if (i > str_len) exit

      ! Start of word
      start = i
      in_quotes = .false.
      quote_char = ' '

      ! Find end of word
      do while (i <= str_len)
        if (.not. in_quotes) then
          if (word_list_str(i:i) == '"' .or. word_list_str(i:i) == "'") then
            in_quotes = .true.
            quote_char = word_list_str(i:i)
          else if (word_list_str(i:i) == ' ') then
            exit
          end if
        else
          ! Handle escaped quotes (backslash before quote char)
          if (word_list_str(i:i) == '\' .and. i < str_len) then
            ! Skip backslash and the next character (escaped)
            i = i + 1
          else if (word_list_str(i:i) == quote_char) then
            in_quotes = .false.
          end if
        end if
        i = i + 1
      end do

      ! Extract word (remove quotes if present)
      spec%word_list_count = spec%word_list_count + 1
      spec%word_list(spec%word_list_count) = word_list_str(start:i-1)

      ! Strip surrounding quotes
      pos = spec%word_list_count
      if (len_trim(spec%word_list(pos)) >= 2) then
        if ((spec%word_list(pos)(1:1) == '"' .and. &
             spec%word_list(pos)(len_trim(spec%word_list(pos)):len_trim(spec%word_list(pos))) == '"') .or. &
            (spec%word_list(pos)(1:1) == "'" .and. &
             spec%word_list(pos)(len_trim(spec%word_list(pos)):len_trim(spec%word_list(pos))) == "'")) then
          spec%word_list(pos) = spec%word_list(pos)(2:len_trim(spec%word_list(pos))-1)
        end if
      end if
    end do
  end subroutine parse_word_list

  ! ===========================================================================
  ! COMPLETION GENERATION FUNCTIONS
  ! ===========================================================================

  ! Generate completions from a word list
  subroutine generate_word_list_completions(spec, prefix, completions, count)
    type(completion_spec_t), intent(in) :: spec
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    integer :: i, prefix_len, word_len, compare_len
    logical :: matches
    character(len=256) :: word, prefix_trimmed

    count = 0
    prefix_trimmed = trim(prefix)
    prefix_len = len_trim(prefix_trimmed)

    do i = 1, spec%word_list_count
      word = trim(spec%word_list(i))
      word_len = len_trim(word)

      ! Check if word matches prefix
      if (prefix_len == 0) then
        matches = .true.
      else if (word_len >= prefix_len) then
        compare_len = min(prefix_len, word_len)
        matches = (word(1:compare_len) == prefix_trimmed(1:compare_len))
      else
        matches = .false.
      end if

      if (matches .and. count < MAX_COMPLETIONS) then
        count = count + 1

        ! Apply prefix transformation
        if (len_trim(spec%prefix) > 0) then
          completions(count) = trim(spec%prefix) // word
        else
          completions(count) = word
        end if

        ! Apply suffix transformation
        if (len_trim(spec%suffix) > 0) then
          completions(count) = trim(completions(count)) // trim(spec%suffix)
        end if
      end if
    end do

    ! Sort completions unless nosort is set
    if (.not. spec%nosort .and. count > 1) then
      call sort_completions(completions, count)
    end if
  end subroutine generate_word_list_completions

  ! Sort completions alphabetically (simple bubble sort)
  subroutine sort_completions(completions, count)
    character(len=256), intent(inout) :: completions(:)
    integer, intent(in) :: count
    integer :: i, j
    character(len=256) :: temp
    logical :: swapped

    do i = 1, count - 1
      swapped = .false.
      do j = 1, count - i
        if (lgt(trim(completions(j)), trim(completions(j+1)))) then
          temp = completions(j)
          completions(j) = completions(j+1)
          completions(j+1) = temp
          swapped = .true.
        end if
      end do
      if (.not. swapped) exit
    end do
  end subroutine sort_completions

  ! Check if a word matches a filter pattern
  function matches_filter(word, filter_pattern) result(matches)
    character(len=*), intent(in) :: word, filter_pattern
    logical :: matches

    ! For now, simple implementation - can be enhanced with glob patterns
    if (len_trim(filter_pattern) == 0) then
      matches = .true.
    else
      ! Simple prefix match
      matches = (index(trim(word), trim(filter_pattern)) > 0)
    end if
  end function matches_filter

  ! Apply filter to completions
  subroutine filter_completions(completions, count, filter_pattern)
    character(len=256), intent(inout) :: completions(:)
    integer, intent(inout) :: count
    character(len=*), intent(in) :: filter_pattern
    integer :: i, write_pos

    if (len_trim(filter_pattern) == 0) return

    write_pos = 1
    do i = 1, count
      if (.not. matches_filter(completions(i), filter_pattern)) then
        ! Keep completions that DON'T match (bash -X semantics removes matches)
        if (write_pos /= i) then
          completions(write_pos) = completions(i)
        end if
        write_pos = write_pos + 1
      end if
    end do

    count = write_pos - 1
  end subroutine filter_completions

  ! Set up completion context for function-based completion
  subroutine setup_completion_context(shell, comp_line, comp_point, comp_words, comp_cword)
    use variables, only: set_shell_variable
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: comp_line
    integer, intent(in) :: comp_point, comp_cword
    character(len=256), intent(in) :: comp_words(:)
    character(len=32) :: point_str, cword_str
    integer :: i

    ! Set COMP_LINE - the current command line
    call set_shell_variable(shell, 'COMP_LINE', trim(comp_line), len_trim(comp_line))

    ! Set COMP_POINT - cursor position in the line
    write(point_str, '(i15)') comp_point
    call set_shell_variable(shell, 'COMP_POINT', trim(point_str), len_trim(point_str))

    ! Set COMP_CWORD - index of the word containing cursor
    write(cword_str, '(i15)') comp_cword
    call set_shell_variable(shell, 'COMP_CWORD', trim(cword_str), len_trim(cword_str))

    ! Set COMP_WORDS array (bash uses indexed array)
    ! For now, we'll set COMP_WORDS as individual variables COMP_WORDS_0, COMP_WORDS_1, etc.
    do i = 0, comp_cword
      if (i <= size(comp_words)) then
        write(point_str, '(a,i15)') 'COMP_WORDS_', i
        call set_shell_variable(shell, trim(point_str), trim(comp_words(i+1)), len_trim(comp_words(i+1)))
      end if
    end do

    ! Initialize empty COMPREPLY array
    call set_shell_variable(shell, 'COMPREPLY', '', 0)
  end subroutine setup_completion_context

  ! Get completions from COMPREPLY array
  subroutine get_compreply_results(shell, completions, count)
    use variables, only: get_shell_variable, get_array_size, get_array_element
    type(shell_state_t), intent(inout) :: shell
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    integer :: array_size, i
    character(len=1024) :: element

    count = 0

    ! Get COMPREPLY array size
    array_size = get_array_size(shell, 'COMPREPLY')

    if (array_size > 0) then
      ! Read array elements
      do i = 0, min(array_size - 1, MAX_COMPLETIONS - 1)
        element = get_array_element(shell, 'COMPREPLY', i)
        if (len_trim(element) > 0) then
          count = count + 1
          completions(count) = trim(element)
        end if
      end do
    else
      ! Fallback: try reading COMPREPLY as a space-separated string
      element = get_shell_variable(shell, 'COMPREPLY')
      if (len_trim(element) > 0) then
        ! Parse space-separated values
        call parse_space_separated(element, completions, count)
      end if
    end if
  end subroutine get_compreply_results

  ! Parse space-separated values into array
  subroutine parse_space_separated(input, values, count)
    character(len=*), intent(in) :: input
    character(len=256), intent(out) :: values(MAX_COMPLETIONS)
    integer, intent(out) :: count
    integer :: i, start

    count = 0
    i = 1

    do while (i <= len_trim(input) .and. count < MAX_COMPLETIONS)
      ! Skip spaces
      do while (i <= len_trim(input) .and. input(i:i) == ' ')
        i = i + 1
      end do
      if (i > len_trim(input)) exit

      ! Start of value
      start = i
      do while (i <= len_trim(input) .and. input(i:i) /= ' ')
        i = i + 1
      end do

      ! Extract value
      count = count + 1
      values(count) = input(start:i-1)
    end do
  end subroutine parse_space_separated

  ! Generate completions by calling a shell function
  subroutine generate_function_completions(shell, spec, command, word_prefix, completions, count)
    use parser, only: parse_pipeline
    type(shell_state_t), intent(inout) :: shell
    type(completion_spec_t), intent(in) :: spec
    character(len=*), intent(in) :: command, word_prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    character(len=1024) :: function_call
    character(len=256) :: comp_words(50)
    integer :: comp_cword

    count = 0

    ! Build minimal context for now
    ! In a real implementation, we'd parse the full command line
    comp_words(1) = trim(command)
    comp_words(2) = trim(word_prefix)
    comp_cword = 1  ! Completing the second word

    ! Set up completion context variables
    call setup_completion_context(shell, trim(command) // ' ' // trim(word_prefix), &
                                   len_trim(command) + 1 + len_trim(word_prefix), &
                                   comp_words, comp_cword)

    ! Build function call: function_name "command" "word" "prev_word"
    ! For simplicity, we'll call with just command and word
    function_call = trim(spec%function_name) // ' "' // trim(command) // '" "' // trim(word_prefix) // '" ""'

    ! Execute the completion function via callback
    ! The callback is registered by the executor module at shell startup
    if (associated(completion_func_executor)) then
      ! Clear COMPREPLY before calling the function
      call clear_compreply(shell)

      ! Call the completion function via the registered executor
      ! The function is expected to populate COMPREPLY array
      call completion_func_executor(shell, trim(spec%function_name), &
                                     trim(command), trim(word_prefix), '')
    end if

    ! Get results from COMPREPLY (populated by the completion function)
    call get_compreply_results(shell, completions, count)
  end subroutine generate_function_completions

  ! Clear the COMPREPLY array
  subroutine clear_compreply(shell)
    use variables, only: set_array_variable
    type(shell_state_t), intent(inout) :: shell
    character(len=1) :: empty_arr(1)

    ! Clear the COMPREPLY array by setting it to empty
    empty_arr(1) = ''
    call set_array_variable(shell, 'COMPREPLY', empty_arr, 0)
  end subroutine clear_compreply

  ! ===========================================================================
  ! BUILT-IN COMPLETERS
  ! ===========================================================================

  ! Complete file names
  ! For now, use a simplified implementation. Full filesystem access
  ! will be added in a future enhancement.
  subroutine complete_files(prefix, completions, count)
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count

    ! Simplified implementation - return empty for now
    ! Phase 5 will integrate with readline's existing file completion
    count = 0
    completions = ''  ! Initialize to silence warning
    if (.false.) print *, prefix  ! Silence unused warning
  end subroutine complete_files

  ! Complete directory names only
  ! For now, use a simplified implementation
  subroutine complete_directories(prefix, completions, count)
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count

    ! Simplified implementation - return empty for now
    ! Phase 5 will integrate with readline's existing directory completion
    count = 0
    completions = ''  ! Initialize to silence warning
    if (.false.) print *, prefix  ! Silence unused warning
  end subroutine complete_directories

  ! Complete command names from PATH
  ! Simplified implementation for Phase 4
  subroutine complete_commands(shell, prefix, completions, count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count

    ! Simplified implementation - return empty for now
    ! Phase 5 will add full command completion
    completions = ''  ! Initialize to silence warning
    if (.false.) print *, prefix, shell%cwd  ! Silence unused warnings
    count = 0
  end subroutine complete_commands

  ! Complete variable names
  subroutine complete_variables(shell, prefix, completions, count)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    integer :: i
    character(len=256) :: var_name

    count = 0

    ! Iterate through shell variables
    do i = 1, shell%num_variables
      if (count >= MAX_COMPLETIONS) exit

      var_name = trim(shell%variables(i)%name)

      ! Check if variable matches prefix
      if (len_trim(prefix) == 0 .or. &
          index(var_name, trim(prefix)) == 1) then
        count = count + 1
        completions(count) = var_name
      end if
    end do
  end subroutine complete_variables

  ! Complete shell keywords
  subroutine complete_keywords(prefix, completions, count)
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    character(len=20), parameter :: keywords(20) = [ &
      'if      ', 'then    ', 'else    ', 'elif    ', 'fi      ', &
      'for     ', 'while   ', 'until   ', 'do      ', 'done    ', &
      'case    ', 'esac    ', 'in      ', 'function', 'select  ', &
      'time    ', 'coproc  ', '[[      ', '!       ', '{       ' ]
    integer :: i

    count = 0

    do i = 1, size(keywords)
      if (count >= MAX_COMPLETIONS) exit

      if (len_trim(prefix) == 0 .or. &
          index(trim(keywords(i)), trim(prefix)) == 1) then
        count = count + 1
        completions(count) = trim(keywords(i))
      end if
    end do
  end subroutine complete_keywords

  ! Complete builtin commands
  subroutine complete_builtins(prefix, completions, count)
    character(len=*), intent(in) :: prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    character(len=20), parameter :: builtins(50) = [ &
      'alias     ', 'bg        ', 'bind      ', 'break     ', 'builtin   ', &
      'cd        ', 'command   ', 'compgen   ', 'complete  ', 'continue  ', &
      'declare   ', 'dirs      ', 'disown    ', 'echo      ', 'enable    ', &
      'eval      ', 'exec      ', 'exit      ', 'export    ', 'fc        ', &
      'fg        ', 'getopts   ', 'hash      ', 'help      ', 'history   ', &
      'jobs      ', 'kill      ', 'let       ', 'local     ', 'logout    ', &
      'popd      ', 'printf    ', 'pushd     ', 'pwd       ', 'read      ', &
      'readonly  ', 'return    ', 'set       ', 'shift     ', 'shopt     ', &
      'source    ', 'suspend   ', 'test      ', 'times     ', 'trap      ', &
      'type      ', 'ulimit    ', 'umask     ', 'unalias   ', 'unset     ' ]
    integer :: i

    count = 0

    do i = 1, size(builtins)
      if (count >= MAX_COMPLETIONS) exit

      if (len_trim(prefix) == 0 .or. &
          index(trim(builtins(i)), trim(prefix)) == 1) then
        count = count + 1
        completions(count) = trim(builtins(i))
      end if
    end do
  end subroutine complete_builtins

  ! Main entry point for generating completions for a command
  subroutine generate_completions(command, word_prefix, completions, count, shell)
    character(len=*), intent(in) :: command
    character(len=*), intent(in) :: word_prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    type(shell_state_t), intent(inout), optional :: shell
    type(completion_spec_t) :: spec
    character(len=256) :: temp_completions(MAX_COMPLETIONS)
    integer :: temp_count, initial_count

    count = 0

    ! Get completion spec for this command
    spec = get_completion_spec(command)
    if (.not. spec%is_active) return

    ! Priority 1: Function-based completion
    if (len_trim(spec%function_name) > 0 .and. present(shell)) then
      call generate_function_completions(shell, spec, command, word_prefix, completions, count)
      if (count > 0) return
    end if

    ! Priority 2: Generate completions from word list
    if (spec%word_list_count > 0) then
      call generate_word_list_completions(spec, word_prefix, completions, count)
    end if

    ! Priority 3: Built-in completers
    initial_count = count

    if (spec%builtin_file .and. count < MAX_COMPLETIONS) then
      call complete_files(word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    if (spec%builtin_directory .and. count < MAX_COMPLETIONS) then
      call complete_directories(word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    if (spec%builtin_command .and. present(shell) .and. count < MAX_COMPLETIONS) then
      call complete_commands(shell, word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    if (spec%builtin_variable .and. present(shell) .and. count < MAX_COMPLETIONS) then
      call complete_variables(shell, word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    if (spec%builtin_keyword .and. count < MAX_COMPLETIONS) then
      call complete_keywords(word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    if (spec%builtin_builtin .and. count < MAX_COMPLETIONS) then
      call complete_builtins(word_prefix, temp_completions, temp_count)
      call merge_completions(completions, count, temp_completions, temp_count)
    end if

    ! Apply filter if present
    if (len_trim(spec%filter_pattern) > 0) then
      call filter_completions(completions, count, spec%filter_pattern)
    end if

    ! Sort if we added any completions and nosort is not set
    if (count > initial_count .and. .not. spec%nosort) then
      call sort_completions(completions, count)
    end if
  end subroutine generate_completions

  ! Merge temp completions into main list, avoiding duplicates
  subroutine merge_completions(completions, count, temp_completions, temp_count)
    character(len=256), intent(inout) :: completions(MAX_COMPLETIONS)
    integer, intent(inout) :: count
    character(len=256), intent(in) :: temp_completions(MAX_COMPLETIONS)
    integer, intent(in) :: temp_count
    integer :: i, j
    logical :: is_duplicate

    do i = 1, temp_count
      if (count >= MAX_COMPLETIONS) exit

      ! Check for duplicates
      is_duplicate = .false.
      do j = 1, count
        if (trim(completions(j)) == trim(temp_completions(i))) then
          is_duplicate = .true.
          exit
        end if
      end do

      if (.not. is_duplicate) then
        count = count + 1
        completions(count) = temp_completions(i)
      end if
    end do
  end subroutine merge_completions

end module completion
