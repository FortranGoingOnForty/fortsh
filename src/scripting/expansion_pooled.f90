! ==============================================================================
! Module: expansion_pooled
! Purpose: Memory-pooled version of parameter expansion and arithmetic operations
! Phase 6 integration - Expansion module with memory pooling
! ==============================================================================
module expansion_pooled
  use shell_types
  use string_pool
  use memory_dashboard
  use variables
  use substitution, only: execute_command_and_capture
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Recursion depth limits
  integer, parameter :: MAX_RECURSION_DEPTH = 1000

contains

  ! Parameter expansion with pooled memory: ${var:offset:length}
  function parameter_expansion_pooled(shell, expression) result(expanded_ref)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: expression
    type(string_ref) :: expanded_ref

    ! Use pooled strings for all working variables
    type(string_ref) :: var_name_ref, operation_ref, var_value_ref
    type(string_ref) :: pattern_ref, replacement_ref
    type(string_ref) :: array_name_ref, array_key_ref
    type(string_ref), allocatable :: keys_refs(:)

    integer :: colon_pos, dash_pos, plus_pos, percent_pos, hash_pos, slash_pos, equals_pos, question_pos
    integer :: offset, length, i, double_op_pos, at_pos
    integer :: bracket_pos, bracket_end, j, num_keys
    character :: transform_op
    logical :: replace_all, greedy, has_colon, var_is_set, var_is_null
    logical :: is_keys_expansion, is_length_expansion, is_all_expansion
    character(len=256) :: temp_str  ! For temporary operations only

    ! Allocate result string from pool
    expanded_ref = pool_get_string(2048)
    call dashboard_track_allocation(MOD_EXPANSION, 2048, get_bucket_idx(2048))
    call pool_copy_to_ref(expanded_ref, '')

    ! Validate input
    if (len_trim(expression) < 4) return

    ! Get pooled string for var_name
    var_name_ref = pool_get_string(256)
    call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))

    ! Extract variable name (remove ${ and })
    temp_str = expression(3:len_trim(expression)-1)
    call pool_copy_to_ref(var_name_ref, trim(temp_str))

    ! Debug output (using pooled string)
    if (associated(var_name_ref%data)) then
      write(error_unit, '(A,A,A)') 'DEBUG START: var_name=[', trim(var_name_ref%data), ']'
    end if

    ! Check for array bracket syntax
    bracket_pos = index(var_name_ref%data, '[')
    if (bracket_pos > 0) then
      bracket_end = index(var_name_ref%data, ']')
      if (bracket_end > bracket_pos) then
        ! Use pooled strings for array operations
        array_name_ref = pool_get_string(256)
        array_key_ref = pool_get_string(256)
        call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))
        call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))

        ! Extract array name and key
        call pool_copy_to_ref(array_name_ref, var_name_ref%data(:bracket_pos-1))
        call pool_copy_to_ref(array_key_ref, var_name_ref%data(bracket_pos+1:bracket_end-1))

        ! Check for special prefixes
        is_keys_expansion = .false.
        is_length_expansion = .false.

        if (len_trim(array_name_ref%data) > 0 .and. array_name_ref%data(1:1) == '!') then
          is_keys_expansion = .true.
          array_name_ref%data = array_name_ref%data(2:)
        else if (len_trim(array_name_ref%data) > 0 .and. array_name_ref%data(1:1) == '#') then
          is_length_expansion = .true.
          array_name_ref%data = array_name_ref%data(2:)
        end if

        is_all_expansion = (trim(array_key_ref%data) == '@' .or. trim(array_key_ref%data) == '*')

        ! Handle associative arrays with pooled memory
        if (is_associative_array(shell, trim(array_name_ref%data))) then
          if (is_keys_expansion .and. is_all_expansion) then
            ! Allocate pooled array for keys
            allocate(keys_refs(50))
            do j = 1, 50
              keys_refs(j) = pool_get_string(256)
              call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))
            end do

            ! Get keys (would need pooled version of get_assoc_array_keys)
            ! For now, using temporary conversion
            block
              character(len=256) :: temp_keys(50)
              call get_assoc_array_keys(shell, trim(array_name_ref%data), temp_keys, num_keys)

              ! Build result
              call pool_copy_to_ref(expanded_ref, '')
              do j = 1, min(num_keys, 50)
                if (j > 1) then
                  expanded_ref%data = trim(expanded_ref%data) // ' '
                end if
                expanded_ref%data = trim(expanded_ref%data) // trim(temp_keys(j))
              end do
            end block

            ! Clean up keys
            do j = 1, 50
              call pool_release_string(keys_refs(j))
              call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
            end do
            deallocate(keys_refs)

            ! Clean up other refs
            call release_temp_refs(array_name_ref, array_key_ref, var_name_ref)
            return
          else if (is_length_expansion .and. is_all_expansion) then
            ! Similar handling for length expansion
            block
              character(len=256) :: temp_keys(50)
              character(len=20) :: num_str
              call get_assoc_array_keys(shell, trim(array_name_ref%data), temp_keys, num_keys)
              write(num_str, '(I0)') num_keys
              call pool_copy_to_ref(expanded_ref, trim(num_str))
            end block

            call release_temp_refs(array_name_ref, array_key_ref, var_name_ref)
            return
          else
            ! Get value for specific key
            temp_str = get_assoc_array_value(shell, trim(array_name_ref%data), trim(array_key_ref%data))
            call pool_copy_to_ref(expanded_ref, trim(temp_str))

            call release_temp_refs(array_name_ref, array_key_ref, var_name_ref)
            return
          end if
        end if

        ! Clean up array refs if not returned
        call pool_release_string(array_name_ref)
        call pool_release_string(array_key_ref)
        call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
        call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
      end if
    end if

    ! Check for @ transformations
    at_pos = index(var_name_ref%data, '@')
    if (at_pos > 0 .and. at_pos < len_trim(var_name_ref%data)) then
      operation_ref = pool_get_string(256)
      var_value_ref = pool_get_string(1024)
      call dashboard_track_allocation(MOD_EXPANSION, 256, get_bucket_idx(256))
      call dashboard_track_allocation(MOD_EXPANSION, 1024, get_bucket_idx(1024))

      call pool_copy_to_ref(operation_ref, var_name_ref%data(:at_pos-1))
      transform_op = var_name_ref%data(at_pos+1:at_pos+1)

      temp_str = get_shell_variable(shell, trim(operation_ref%data))
      call pool_copy_to_ref(var_value_ref, temp_str)

      select case (transform_op)
      case ('U')
        call pool_copy_to_ref(expanded_ref, to_upper_pooled(var_value_ref))
      case ('L')
        call pool_copy_to_ref(expanded_ref, to_lower_pooled(var_value_ref))
      case ('u')
        if (len_trim(var_value_ref%data) > 0) then
          temp_str = to_upper_pooled(var_value_ref%data(1:1))
          if (len_trim(var_value_ref%data) > 1) then
            temp_str = trim(temp_str) // var_value_ref%data(2:)
          end if
          call pool_copy_to_ref(expanded_ref, temp_str)
        end if
      case ('Q')
        call pool_copy_to_ref(expanded_ref, quote_value_pooled(var_value_ref))
      case ('E')
        call pool_copy_to_ref(expanded_ref, expand_escape_sequences_pooled(var_value_ref))
      end select

      call pool_release_string(operation_ref)
      call pool_release_string(var_value_ref)
      call pool_release_string(var_name_ref)
      call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
      call dashboard_track_deallocation(MOD_EXPANSION, 1024, get_bucket_idx(1024))
      call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))
      return
    end if

    ! Default case: simple variable expansion
    temp_str = get_shell_variable(shell, trim(var_name_ref%data))
    call pool_copy_to_ref(expanded_ref, trim(temp_str))

    ! Clean up
    call pool_release_string(var_name_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, 256, get_bucket_idx(256))

  end function parameter_expansion_pooled

  ! Helper function to convert string to uppercase using pooled memory
  function to_upper_pooled(str_ref) result(result_str)
    type(string_ref), intent(in) :: str_ref
    character(len=:), allocatable :: result_str
    integer :: i

    allocate(character(len=len_trim(str_ref%data)) :: result_str)
    do i = 1, len_trim(str_ref%data)
      if (str_ref%data(i:i) >= 'a' .and. str_ref%data(i:i) <= 'z') then
        result_str(i:i) = char(ichar(str_ref%data(i:i)) - 32)
      else
        result_str(i:i) = str_ref%data(i:i)
      end if
    end do
  end function to_upper_pooled

  ! Helper function to convert string to lowercase using pooled memory
  function to_lower_pooled(str_ref) result(result_str)
    type(string_ref), intent(in) :: str_ref
    character(len=:), allocatable :: result_str
    integer :: i

    allocate(character(len=len_trim(str_ref%data)) :: result_str)
    do i = 1, len_trim(str_ref%data)
      if (str_ref%data(i:i) >= 'A' .and. str_ref%data(i:i) <= 'Z') then
        result_str(i:i) = char(ichar(str_ref%data(i:i)) + 32)
      else
        result_str(i:i) = str_ref%data(i:i)
      end if
    end do
  end function to_lower_pooled

  ! Quote a value for shell use (pooled version)
  function quote_value_pooled(str_ref) result(quoted)
    type(string_ref), intent(in) :: str_ref
    character(len=:), allocatable :: quoted
    integer :: i, j, len_needed

    ! Calculate space needed (worst case: every char needs escaping)
    len_needed = 2 + len_trim(str_ref%data) * 2
    allocate(character(len=len_needed) :: quoted)

    quoted = "'"
    j = 2
    do i = 1, len_trim(str_ref%data)
      if (str_ref%data(i:i) == "'") then
        quoted(j:j+3) = "'\\''"
        j = j + 4
      else
        quoted(j:j) = str_ref%data(i:i)
        j = j + 1
      end if
    end do
    quoted(j:j) = "'"
    quoted = quoted(1:j)
  end function quote_value_pooled

  ! Expand escape sequences (pooled version)
  function expand_escape_sequences_pooled(str_ref) result(expanded)
    type(string_ref), intent(in) :: str_ref
    character(len=:), allocatable :: expanded
    type(string_ref) :: temp_ref
    integer :: i, j

    ! Get pooled temp string
    temp_ref = pool_get_string(len(str_ref%data) * 2)
    call dashboard_track_allocation(MOD_EXPANSION, len(str_ref%data) * 2, get_bucket_idx(len(str_ref%data) * 2))

    j = 1
    i = 1
    do while (i <= len_trim(str_ref%data))
      if (str_ref%data(i:i) == '\' .and. i < len_trim(str_ref%data)) then
        select case(str_ref%data(i+1:i+1))
        case ('n')
          temp_ref%data(j:j) = new_line('a')
          i = i + 2
        case ('t')
          temp_ref%data(j:j) = char(9)
          i = i + 2
        case ('r')
          temp_ref%data(j:j) = char(13)
          i = i + 2
        case ('\')
          temp_ref%data(j:j) = '\'
          i = i + 2
        case default
          temp_ref%data(j:j) = str_ref%data(i:i)
          i = i + 1
        end select
      else
        temp_ref%data(j:j) = str_ref%data(i:i)
        i = i + 1
      end if
      j = j + 1
    end do

    ! Create result
    allocate(character(len=j-1) :: expanded)
    expanded = temp_ref%data(1:j-1)

    ! Clean up
    call pool_release_string(temp_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, len(str_ref%data) * 2, get_bucket_idx(len(str_ref%data) * 2))

  end function expand_escape_sequences_pooled

  ! Arithmetic evaluation using pooled memory
  function evaluate_arithmetic_pooled(shell, expression) result(result_ref)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: expression
    type(string_ref) :: result_ref
    type(string_ref) :: expr_ref
    character(len=32) :: result_str
    integer :: result_value

    ! Get pooled string for expression
    expr_ref = pool_get_string(512)
    call dashboard_track_allocation(MOD_EXPANSION, 512, get_bucket_idx(512))
    call pool_copy_to_ref(expr_ref, expression)

    ! Get result string from pool
    result_ref = pool_get_string(32)
    call dashboard_track_allocation(MOD_EXPANSION, 32, get_bucket_idx(32))

    ! Simple evaluation (would need full implementation)
    result_value = evaluate_arithmetic_expr(trim(expr_ref%data))
    write(result_str, '(I0)') result_value
    call pool_copy_to_ref(result_ref, trim(result_str))

    ! Clean up
    call pool_release_string(expr_ref)
    call dashboard_track_deallocation(MOD_EXPANSION, 512, get_bucket_idx(512))

  end function evaluate_arithmetic_pooled

  ! Pattern substitution using pooled memory
  subroutine pattern_substitution_pooled(input_ref, pattern_ref, replacement_ref, &
                                         greedy, at_start, output_ref)
    type(string_ref), intent(in) :: input_ref, pattern_ref, replacement_ref
    logical, intent(in) :: greedy, at_start
    type(string_ref), intent(out) :: output_ref

    type(string_ref) :: temp_ref
    integer :: pattern_len, input_len, pos, last_pos
    character(len=2048) :: temp_str  ! Temporary for building result

    ! Allocate output from pool
    output_ref = pool_get_string(2048)
    call dashboard_track_allocation(MOD_EXPANSION, 2048, get_bucket_idx(2048))

    input_len = len_trim(input_ref%data)
    pattern_len = len_trim(pattern_ref%data)

    if (pattern_len == 0 .or. input_len == 0) then
      call pool_copy_to_ref(output_ref, input_ref%data)
      return
    end if

    ! Build result in temporary string
    temp_str = ''
    pos = 1

    if (at_start) then
      ! Replace only at start
      if (input_ref%data(1:pattern_len) == pattern_ref%data(1:pattern_len)) then
        temp_str = replacement_ref%data(1:len_trim(replacement_ref%data)) // &
                  input_ref%data(pattern_len+1:input_len)
      else
        temp_str = input_ref%data(1:input_len)
      end if
    else if (greedy) then
      ! Replace all occurrences
      last_pos = 1
      do
        pos = index(input_ref%data(last_pos:), pattern_ref%data(1:pattern_len))
        if (pos == 0) exit

        pos = pos + last_pos - 1
        temp_str = trim(temp_str) // input_ref%data(last_pos:pos-1) // &
                  replacement_ref%data(1:len_trim(replacement_ref%data))
        last_pos = pos + pattern_len
      end do
      temp_str = trim(temp_str) // input_ref%data(last_pos:input_len)
    else
      ! Replace first occurrence
      pos = index(input_ref%data, pattern_ref%data(1:pattern_len))
      if (pos > 0) then
        temp_str = input_ref%data(1:pos-1) // &
                  replacement_ref%data(1:len_trim(replacement_ref%data)) // &
                  input_ref%data(pos+pattern_len:input_len)
      else
        temp_str = input_ref%data(1:input_len)
      end if
    end if

    call pool_copy_to_ref(output_ref, trim(temp_str))

  end subroutine pattern_substitution_pooled

  ! Helper to release temporary refs
  subroutine release_temp_refs(ref1, ref2, ref3)
    type(string_ref), intent(inout), optional :: ref1, ref2, ref3

    if (present(ref1)) then
      if (ref1%pool_index /= 0) then
        call pool_release_string(ref1)
        call dashboard_track_deallocation(MOD_EXPANSION, ref1%str_len, get_bucket_idx(ref1%str_len))
      end if
    end if

    if (present(ref2)) then
      if (ref2%pool_index /= 0) then
        call pool_release_string(ref2)
        call dashboard_track_deallocation(MOD_EXPANSION, ref2%str_len, get_bucket_idx(ref2%str_len))
      end if
    end if

    if (present(ref3)) then
      if (ref3%pool_index /= 0) then
        call pool_release_string(ref3)
        call dashboard_track_deallocation(MOD_EXPANSION, ref3%str_len, get_bucket_idx(ref3%str_len))
      end if
    end if

  end subroutine release_temp_refs

  ! Get bucket index for dashboard tracking
  function get_bucket_idx(size_bytes) result(idx)
    integer, intent(in) :: size_bytes
    integer :: idx

    if (size_bytes <= 64) then
      idx = 1
    else if (size_bytes <= 256) then
      idx = 2
    else if (size_bytes <= 1024) then
      idx = 3
    else if (size_bytes <= 4096) then
      idx = 4
    else if (size_bytes <= 16384) then
      idx = 5
    else
      idx = 0
    end if
  end function get_bucket_idx

  ! Simple arithmetic expression evaluator (placeholder)
  function evaluate_arithmetic_expr(expr) result(value)
    character(len=*), intent(in) :: expr
    integer :: value

    ! Simplified implementation - would need full parser
    read(expr, *, iostat=value) value
    if (value /= 0) value = 0

  end function evaluate_arithmetic_expr

end module expansion_pooled