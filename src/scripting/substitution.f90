! ==============================================================================
! Module: substitution
! Purpose: Enhanced command and process substitution
! ==============================================================================
module substitution
  use shell_types
  use system_interface
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Process substitution file descriptors
  type :: proc_subst_t
    integer :: fd = -1
    character(len=256) :: filename = ''
    integer(c_pid_t) :: pid = 0
    logical :: is_input = .true.  ! true for <(), false for >()
    logical :: active = .false.
  end type proc_subst_t

contains

  ! Enhanced command substitution with nested support
  function enhanced_command_substitution(shell, input) result(output)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: input
    character(len=4096) :: output
    
    character(len=4096) :: processed_input
    integer :: i, paren_count, start_pos
    character(len=2048) :: inner_cmd, inner_result
    
    output = ''
    processed_input = input
    
    ! Process nested command substitutions from inside out
    call process_nested_substitutions(shell, processed_input)
    
    ! Execute the final command
    call execute_command_and_capture(processed_input, output)
    
    ! Remove trailing newlines
    do while (len_trim(output) > 0 .and. output(len_trim(output):len_trim(output)) == char(10))
      output = output(:len_trim(output)-1)
    end do
  end function

  subroutine process_nested_substitutions(shell, cmd_str)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(inout) :: cmd_str
    
    character(len=len(cmd_str)) :: result
    integer :: i, start_pos, paren_count, subst_start, subst_end
    character(len=2048) :: inner_cmd, inner_result
    logical :: found_nested
    
    found_nested = .true.
    
    ! Keep processing until no more nested substitutions
    do while (found_nested)
      found_nested = .false.
      result = ''
      i = 1
      
      do while (i <= len_trim(cmd_str))
        if (i < len_trim(cmd_str) - 1 .and. cmd_str(i:i+1) == '$(') then
          ! Found start of command substitution
          subst_start = i
          paren_count = 1
          i = i + 2
          
          ! Find the matching closing parenthesis
          do while (i <= len_trim(cmd_str) .and. paren_count > 0)
            if (cmd_str(i:i) == '(') then
              paren_count = paren_count + 1
            else if (cmd_str(i:i) == ')') then
              paren_count = paren_count - 1
            end if
            i = i + 1
          end do
          
          if (paren_count == 0) then
            subst_end = i - 1
            inner_cmd = cmd_str(subst_start+2:subst_end-1)
            
            ! Check if this inner command has nested substitutions
            if (index(inner_cmd, '$(') == 0) then
              ! No more nesting - execute this command
              call execute_command_and_capture(inner_cmd, inner_result)
              result = trim(result) // trim(inner_result)
              found_nested = .true.
            else
              ! Keep the substitution for next iteration
              result = trim(result) // cmd_str(subst_start:subst_end)
            end if
          else
            result = trim(result) // cmd_str(subst_start:subst_start)
            i = subst_start + 1
          end if
        else
          result = trim(result) // cmd_str(i:i)
          i = i + 1
        end if
      end do
      
      cmd_str = result
    end do
  end subroutine

  subroutine execute_command_and_capture(command, output)
    character(len=*), intent(in) :: command
    character(len=*), intent(out) :: output
    
    integer :: unit, iostat, pos
    character(len=256) :: temp_file, line
    character(len=1024) :: full_cmd
    
    output = ''
    
    ! Create temporary file for output capture
    temp_file = '/tmp/fortsh_subst_' // generate_temp_suffix()
    
    ! Execute command with output redirection - simplified
    output = 'mock_output'  ! Placeholder
    
    ! Read captured output
    open(newunit=unit, file=trim(temp_file), status='old', iostat=iostat)
    if (iostat == 0) then
      pos = 1
      do
        read(unit, '(A)', iostat=iostat) line
        if (iostat /= 0) exit
        
        if (pos + len_trim(line) <= len(output)) then
          output(pos:pos+len_trim(line)-1) = trim(line)
          pos = pos + len_trim(line)
          if (pos <= len(output)) then
            output(pos:pos) = char(10)  ! newline
            pos = pos + 1
          end if
        else
          exit
        end if
      end do
      close(unit)
      
      ! Remove temporary file - placeholder
    end if
  end subroutine

  ! Process substitution: <(command) and >(command)
  function create_process_substitution(command, is_input) result(proc_subst)
    character(len=*), intent(in) :: command
    logical, intent(in) :: is_input
    type(proc_subst_t) :: proc_subst
    
    character(len=256) :: fifo_name
    integer :: status
    character(len=1024) :: full_cmd
    
    proc_subst%is_input = is_input
    proc_subst%active = .false.
    
    ! Generate FIFO name
    fifo_name = '/tmp/fortsh_fifo_' // generate_temp_suffix()
    proc_subst%filename = fifo_name
    
    ! Create named pipe (FIFO) - placeholder
    
    if (is_input) then
      ! <(command) - command writes to FIFO, shell reads from it
      full_cmd = '(' // trim(command) // ') > ' // trim(fifo_name) // ' &'
    else
      ! >(command) - shell writes to FIFO, command reads from it  
      full_cmd = '(' // trim(command) // ') < ' // trim(fifo_name) // ' &'
    end if
    
    ! Start background process - placeholder
    proc_subst%active = .true.
  end function

  subroutine cleanup_process_substitution(proc_subst)
    type(proc_subst_t), intent(inout) :: proc_subst
    
    if (proc_subst%active) then
      ! Remove FIFO - placeholder
      proc_subst%active = .false.
      proc_subst%filename = ''
      proc_subst%fd = -1
    end if
  end subroutine

  function generate_temp_suffix() result(suffix)
    character(len=16) :: suffix
    integer :: values(8)
    
    call date_and_time(values=values)
    write(suffix, '(I4.4,I2.2,I2.2,I2.2,I2.2,I2.2)') values(1), values(2), values(3), values(5), values(6), values(7)
  end function

  ! Brace expansion implementation
  subroutine expand_braces(input, expanded_list, count)
    character(len=*), intent(in) :: input
    character(len=256), intent(out) :: expanded_list(100)
    integer, intent(out) :: count

    integer :: brace_start, brace_end, comma_pos, depth, pos
    character(len=256) :: prefix, suffix, middle_part
    character(len=256) :: options(50)
    integer :: option_count, i

    count = 0

    ! Find first brace expansion
    brace_start = index(input, '{')
    if (brace_start == 0) then
      count = 1
      expanded_list(1) = input
      return
    end if

    ! Find MATCHING closing brace by counting depth
    depth = 0
    brace_end = 0
    do pos = brace_start, len_trim(input)
      if (input(pos:pos) == '{') then
        depth = depth + 1
      else if (input(pos:pos) == '}') then
        depth = depth - 1
        if (depth == 0) then
          brace_end = pos
          exit
        end if
      end if
    end do

    if (brace_end == 0) then
      count = 1
      expanded_list(1) = input
      return
    end if
    
    prefix = input(:brace_start-1)
    suffix = input(brace_end+1:)
    middle_part = input(brace_start+1:brace_end-1)
    
    ! Parse comma-separated options or ranges
    if (index(middle_part, '..') > 0) then
      call expand_range(middle_part, options, option_count)
    else
      call parse_comma_list(middle_part, options, option_count)
    end if
    
    ! Generate expanded strings
    do i = 1, option_count
      if (count < 100) then
        count = count + 1
        expanded_list(count) = trim(prefix) // trim(options(i)) // trim(suffix)
      end if
    end do
    
    ! Recursively expand any remaining braces
    if (count > 0) then
      call recursive_brace_expansion(expanded_list, count)
    end if
  end subroutine

  subroutine expand_range(range_expr, options, count)
    character(len=*), intent(in) :: range_expr
    character(len=256), intent(out) :: options(50)
    integer, intent(out) :: count
    
    integer :: dot_pos, start_val, end_val, i
    character(len=32) :: start_str, end_str
    
    count = 0
    dot_pos = index(range_expr, '..')
    
    if (dot_pos == 0) return
    
    start_str = range_expr(:dot_pos-1)
    end_str = range_expr(dot_pos+2:)
    
    ! Try numeric range first
    read(start_str, *, iostat=i) start_val
    if (i == 0) then
      read(end_str, *, iostat=i) end_val
      if (i == 0) then
        do i = start_val, end_val
          if (count < 50) then
            count = count + 1
            write(options(count), '(I0)') i
          end if
        end do
        return
      end if
    end if
    
    ! Character range (a-z)
    if (len_trim(start_str) == 1 .and. len_trim(end_str) == 1) then
      do i = ichar(start_str(1:1)), ichar(end_str(1:1))
        if (count < 50) then
          count = count + 1
          options(count) = char(i)
        end if
      end do
    end if
  end subroutine

  subroutine parse_comma_list(list_str, options, count)
    character(len=*), intent(in) :: list_str
    character(len=256), intent(out) :: options(50)
    integer, intent(out) :: count

    integer :: pos, start_pos, comma_pos, depth

    count = 0
    pos = 1
    start_pos = 1
    depth = 0

    do while (pos <= len_trim(list_str))
      ! Track brace depth to avoid splitting on commas inside nested braces
      if (list_str(pos:pos) == '{') then
        depth = depth + 1
      else if (list_str(pos:pos) == '}') then
        depth = depth - 1
      else if (list_str(pos:pos) == ',' .and. depth == 0) then
        ! Only split on commas at depth 0 (not inside braces)
        if (count < 50 .and. pos > start_pos) then
          count = count + 1
          options(count) = list_str(start_pos:pos-1)
        end if
        start_pos = pos + 1
      end if
      pos = pos + 1
    end do

    ! Handle last option
    if (count < 50 .and. start_pos <= len_trim(list_str)) then
      count = count + 1
      options(count) = list_str(start_pos:)
    end if
  end subroutine

  subroutine recursive_brace_expansion(list, count)
    character(len=256), intent(inout) :: list(100)
    integer, intent(inout) :: count
    
    character(len=256) :: temp_list(100), expanded_temp(100)
    integer :: i, j, temp_count, expanded_count, total_count
    
    total_count = 0
    
    do i = 1, count
      if (index(list(i), '{') > 0) then
        call expand_braces(list(i), expanded_temp, expanded_count)
        do j = 1, expanded_count
          if (total_count < 100) then
            total_count = total_count + 1
            temp_list(total_count) = expanded_temp(j)
          end if
        end do
      else
        if (total_count < 100) then
          total_count = total_count + 1
          temp_list(total_count) = list(i)
        end if
      end if
    end do
    
    count = total_count
    list(1:count) = temp_list(1:count)
  end subroutine

end module substitution