! ==============================================================================
! Module: completion
! Purpose: Programmable completion system for fortsh (bash-compatible)
! ==============================================================================
module completion
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Maximum number of completion specifications
  integer, parameter :: MAX_COMPLETION_SPECS = 100
  integer, parameter :: MAX_WORD_LIST = 1000
  integer, parameter :: MAX_COMPLETIONS = 1000

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
    integer :: i, start, pos
    logical :: in_quotes
    character(len=1) :: quote_char

    spec%word_list_count = 0
    i = 1

    do while (i <= len_trim(word_list_str) .and. spec%word_list_count < MAX_WORD_LIST)
      ! Skip leading spaces
      do while (i <= len_trim(word_list_str) .and. word_list_str(i:i) == ' ')
        i = i + 1
      end do
      if (i > len_trim(word_list_str)) exit

      ! Start of word
      start = i
      in_quotes = .false.
      quote_char = ' '

      ! Find end of word
      do while (i <= len_trim(word_list_str))
        if (.not. in_quotes) then
          if (word_list_str(i:i) == '"' .or. word_list_str(i:i) == "'") then
            in_quotes = .true.
            quote_char = word_list_str(i:i)
          else if (word_list_str(i:i) == ' ') then
            exit
          end if
        else
          if (word_list_str(i:i) == quote_char) then
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
        ! Keep this completion
        if (write_pos /= i) then
          completions(write_pos) = completions(i)
        end if
        write_pos = write_pos + 1
      end if
    end do

    count = write_pos - 1
  end subroutine filter_completions

  ! Main entry point for generating completions for a command
  subroutine generate_completions(command, word_prefix, completions, count)
    character(len=*), intent(in) :: command
    character(len=*), intent(in) :: word_prefix
    character(len=256), intent(out) :: completions(MAX_COMPLETIONS)
    integer, intent(out) :: count
    type(completion_spec_t) :: spec

    count = 0

    ! Get completion spec for this command
    spec = get_completion_spec(command)
    if (.not. spec%is_active) return

    ! Generate completions from word list
    if (spec%word_list_count > 0) then
      call generate_word_list_completions(spec, word_prefix, completions, count)
    end if

    ! Apply filter if present
    if (len_trim(spec%filter_pattern) > 0) then
      call filter_completions(completions, count, spec%filter_pattern)
    end if
  end subroutine generate_completions

end module completion
