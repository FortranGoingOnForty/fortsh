! ==============================================================================
! Module: better_errors
! Purpose: Enhanced error messages with helpful suggestions
! ==============================================================================
module better_errors
  use iso_fortran_env, only: error_unit
  use system_interface, only: get_environment_var
  implicit none
  private

  ! Public interface
  public :: show_command_not_found_error
  public :: suggest_similar_commands
  public :: levenshtein_distance

  ! ANSI color codes for errors
  integer, parameter :: COLOR_RED = 31
  integer, parameter :: COLOR_YELLOW = 33
  integer, parameter :: COLOR_CYAN = 36
  integer, parameter :: COLOR_GREEN = 32
  integer, parameter :: COLOR_RESET = 0

  ! Maximum suggestions to show
  integer, parameter :: MAX_SUGGESTIONS = 3
  integer, parameter :: MAX_EDIT_DISTANCE = 3

contains

  ! Show enhanced "command not found" error with suggestions
  subroutine show_command_not_found_error(command)
    character(len=*), intent(in) :: command
    character(len=:), allocatable :: suggestions(:)
    integer :: num_suggestions, i

    ! Print main error message in red
    write(error_unit, '(a,a,a,a)') &
      color_code(COLOR_RED), &
      "fortsh: Unknown command '", trim(command), "'"
    write(error_unit, '(a)') color_code(COLOR_RESET)

    ! Try to find similar commands
    call suggest_similar_commands(command, suggestions, num_suggestions)

    if (num_suggestions > 0) then
      ! Print suggestions
      write(error_unit, '(a)', advance='no') color_code(COLOR_CYAN)
      write(error_unit, '(a)', advance='no') "Did you mean"

      if (num_suggestions == 1) then
        write(error_unit, '(a)', advance='no') " '"
        write(error_unit, '(a)', advance='no') trim(suggestions(1))
        write(error_unit, '(a)') "'?"
      else
        write(error_unit, '(a)') ":"
        do i = 1, num_suggestions
          write(error_unit, '(a)', advance='no') "  "
          write(error_unit, '(a)', advance='no') color_code(COLOR_GREEN)
          write(error_unit, '(a)', advance='no') trim(suggestions(i))
          write(error_unit, '(a)') color_code(COLOR_CYAN)
        end do
      end if
      write(error_unit, '(a)') color_code(COLOR_RESET)
    end if

    ! Cleanup
    if (allocated(suggestions)) deallocate(suggestions)
  end subroutine

  ! Find similar commands in PATH and builtins
  subroutine suggest_similar_commands(command, suggestions, num_suggestions)
    character(len=*), intent(in) :: command
    character(len=:), allocatable, intent(out) :: suggestions(:)
    integer, intent(out) :: num_suggestions

    character(len=:), allocatable :: candidates(:)
    integer, allocatable :: distances(:)
    integer :: num_candidates, i, j, min_dist
    character(len=256) :: temp_suggestions(MAX_SUGGESTIONS)

    ! Get candidate commands
    call get_command_candidates(candidates, num_candidates)

    if (num_candidates == 0) then
      num_suggestions = 0
      return
    end if

    ! Allocate distances array
    allocate(distances(num_candidates))

    ! Calculate edit distance for each candidate
    do i = 1, num_candidates
      distances(i) = levenshtein_distance(command, candidates(i))
    end do

    ! Find commands within acceptable edit distance
    min_dist = minval(distances)
    num_suggestions = 0

    ! Only suggest if distance is reasonable
    if (min_dist > MAX_EDIT_DISTANCE) then
      deallocate(candidates, distances)
      return
    end if

    ! Collect suggestions (up to MAX_SUGGESTIONS)
    do i = 1, num_candidates
      if (num_suggestions >= MAX_SUGGESTIONS) exit

      ! Include commands with distance <= min_dist + 1
      if (distances(i) <= min(min_dist + 1, MAX_EDIT_DISTANCE)) then
        num_suggestions = num_suggestions + 1
        temp_suggestions(num_suggestions) = trim(candidates(i))
      end if
    end do

    ! Copy to output
    if (num_suggestions > 0) then
      allocate(character(len=256) :: suggestions(num_suggestions))
      do i = 1, num_suggestions
        suggestions(i) = temp_suggestions(i)
      end do
    end if

    ! Cleanup
    deallocate(candidates, distances)
  end subroutine

  ! Get list of candidate commands (builtins + PATH)
  subroutine get_command_candidates(candidates, num_candidates)
    character(len=:), allocatable, intent(out) :: candidates(:)
    integer, intent(out) :: num_candidates

    character(len=256), allocatable :: temp_candidates(:)
    character(len=:), allocatable :: path_env
    character(len=1024) :: dir, cmd_path
    integer :: max_candidates, path_start, path_end, colon_pos
    integer :: unit, iostat
    logical :: dir_exists

    max_candidates = 1000
    allocate(temp_candidates(max_candidates))
    num_candidates = 0

    ! Add common builtins
    call add_builtins(temp_candidates, num_candidates, max_candidates)

    ! Get PATH
    path_env = get_environment_var('PATH')
    if (.not. allocated(path_env) .or. len_trim(path_env) == 0) then
      ! Just return builtins
      allocate(character(len=256) :: candidates(num_candidates))
      candidates(1:num_candidates) = temp_candidates(1:num_candidates)
      deallocate(temp_candidates)
      return
    end if

    ! Search PATH directories for executables
    path_start = 1
    do while (path_start <= len_trim(path_env) .and. num_candidates < max_candidates)
      ! Find next colon
      colon_pos = index(path_env(path_start:), ':')
      if (colon_pos > 0) then
        path_end = path_start + colon_pos - 2
      else
        path_end = len_trim(path_env)
      end if

      ! Extract directory
      dir = path_env(path_start:path_end)

      ! Check if directory exists (simple check)
      inquire(file=trim(dir), exist=dir_exists)
      if (dir_exists) then
        ! Try to list files in directory using ls
        ! This is a simplified version - in production, use directory listing
        ! For now, just add a few common commands
        if (num_candidates < max_candidates) then
          ! Just add some known commands for demonstration
          ! In full implementation, would scan directory
        end if
      end if

      ! Move to next directory
      if (colon_pos > 0) then
        path_start = path_start + colon_pos
      else
        exit
      end if
    end do

    ! Copy to output
    allocate(character(len=256) :: candidates(num_candidates))
    candidates(1:num_candidates) = temp_candidates(1:num_candidates)
    deallocate(temp_candidates)
  end subroutine

  ! Add builtin commands to candidate list
  subroutine add_builtins(candidates, num, max_count)
    character(len=*), intent(inout) :: candidates(:)
    integer, intent(inout) :: num
    integer, intent(in) :: max_count

    character(len=20) :: builtins(50)
    integer :: i, n_builtins

    ! Common builtins that users might typo
    builtins = [ &
      'cd      ', 'ls      ', 'echo    ', 'pwd     ', 'exit    ', &
      'export  ', 'set     ', 'unset   ', 'alias   ', 'unalias ', &
      'source  ', 'history ', 'jobs    ', 'fg      ', 'bg      ', &
      'kill    ', 'wait    ', 'read    ', 'printf  ', 'test    ', &
      'type    ', 'command ', 'builtin ', 'declare ', 'local   ', &
      'return  ', 'shift   ', 'break   ', 'continue', 'eval    ', &
      'exec    ', 'trap    ', 'ulimit  ', 'umask   ', 'getopts ', &
      'hash    ', 'help    ', 'fc      ', 'complete', 'compgen ', &
      'git     ', 'grep    ', 'find    ', 'sed     ', 'awk     ', &
      'cat     ', 'less    ', 'more    ', 'vim     ', 'nano    ' &
    ]
    n_builtins = 50

    do i = 1, n_builtins
      if (num >= max_count) exit
      num = num + 1
      candidates(num) = trim(builtins(i))
    end do
  end subroutine

  ! Calculate Levenshtein distance (edit distance) between two strings
  function levenshtein_distance(s1, s2) result(distance)
    character(len=*), intent(in) :: s1, s2
    integer :: distance

    integer :: len1, len2, i, j, cost
    integer, allocatable :: matrix(:,:)

    len1 = len_trim(s1)
    len2 = len_trim(s2)

    ! Handle empty strings
    if (len1 == 0) then
      distance = len2
      return
    end if
    if (len2 == 0) then
      distance = len1
      return
    end if

    ! Allocate matrix (0:len1, 0:len2)
    allocate(matrix(0:len1, 0:len2))

    ! Initialize first row and column
    do i = 0, len1
      matrix(i, 0) = i
    end do
    do j = 0, len2
      matrix(0, j) = j
    end do

    ! Fill matrix using dynamic programming
    do j = 1, len2
      do i = 1, len1
        if (s1(i:i) == s2(j:j)) then
          cost = 0
        else
          cost = 1
        end if

        matrix(i, j) = min( &
          matrix(i-1, j) + 1,      & ! Deletion
          matrix(i, j-1) + 1,      & ! Insertion
          matrix(i-1, j-1) + cost  & ! Substitution
        )
      end do
    end do

    distance = matrix(len1, len2)
    deallocate(matrix)
  end function

  ! Generate ANSI color code
  function color_code(color) result(code)
    integer, intent(in) :: color
    character(len=16) :: code

    if (color == COLOR_RESET) then
      code = char(27) // '[0m'
    else
      write(code, '(a,i0,a)') char(27) // '[', color, 'm'
    end if
  end function

end module better_errors
