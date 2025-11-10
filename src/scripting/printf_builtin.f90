! ==============================================================================
! Module: printf_builtin
! Purpose: Printf built-in command with format string support
! ==============================================================================
module printf_builtin
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

contains

  subroutine builtin_printf(cmd, shell)
    use iso_fortran_env, only: error_unit
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=2048) :: format_string, output_buffer
    integer :: arg_index, prev_arg_index, di

    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'printf: usage: printf FORMAT [ARGUMENTS...]'
      shell%last_exit_status = 1
      return
    end if

    format_string = cmd%tokens(2)
    arg_index = 3

    ! POSIX behavior: always output format string at least once,
    ! then repeat for any remaining arguments
    do
      prev_arg_index = arg_index
      call process_printf_format(format_string, cmd%tokens, cmd%num_tokens, arg_index, output_buffer)
      write(output_unit, '(a)', advance='no') trim(output_buffer)

      ! If no arguments were consumed, we're done (format has no specifiers or no more args)
      if (arg_index == prev_arg_index .or. arg_index > cmd%num_tokens) exit
    end do

    shell%last_exit_status = 0
  end subroutine

  subroutine process_printf_format(format_str, args, num_args, start_arg, output)
    character(len=*), intent(in) :: format_str
    character(len=*), intent(in) :: args(:)
    integer, intent(in) :: num_args
    integer, intent(inout) :: start_arg
    character(len=*), intent(out) :: output

    integer :: pos, output_pos, arg_index
    character :: current_char, next_char
    character(len=16) :: format_spec
    character(len=256) :: arg_value, formatted_value
    
    pos = 1
    output_pos = 1
    arg_index = start_arg
    output = ''
    
    do while (pos <= len_trim(format_str))
      current_char = format_str(pos:pos)
      
      if (current_char == '%' .and. pos < len_trim(format_str)) then
        next_char = format_str(pos+1:pos+1)
        
        if (next_char == '%') then
          ! Escaped percent
          output(output_pos:output_pos) = '%'
          output_pos = output_pos + 1
          pos = pos + 2
        else
          ! Format specifier
          call parse_format_specifier(format_str, pos, format_spec)
          
          if (arg_index <= num_args) then
            arg_value = args(arg_index)
            arg_index = arg_index + 1
          else
            arg_value = ''
          end if
          
          call format_argument(format_spec, arg_value, formatted_value)
          
          ! Append formatted value to output
          if (output_pos + len_trim(formatted_value) <= len(output)) then
            output(output_pos:output_pos+len_trim(formatted_value)-1) = trim(formatted_value)
            output_pos = output_pos + len_trim(formatted_value)
          end if
        end if
      else if (current_char == '\' .and. pos < len_trim(format_str)) then
        ! Handle escape sequences
        call process_escape_sequence(format_str, pos, output, output_pos)
      else
        ! Regular character
        if (output_pos <= len(output)) then
          output(output_pos:output_pos) = current_char
          output_pos = output_pos + 1
        end if
        pos = pos + 1
      end if
    end do

    ! Update start_arg to reflect how many arguments were consumed
    start_arg = arg_index
  end subroutine

  subroutine parse_format_specifier(format_str, pos, format_spec)
    character(len=*), intent(in) :: format_str
    integer, intent(inout) :: pos
    character(len=*), intent(out) :: format_spec
    
    integer :: start_pos, spec_pos
    character :: spec_char
    
    start_pos = pos
    pos = pos + 1  ! Skip %
    spec_pos = 1
    format_spec = ''
    
    ! Parse format specification
    do while (pos <= len_trim(format_str))
      spec_char = format_str(pos:pos)
      
      ! Check if this is the conversion specifier
      if (index('diouxXeEfFgGaAcsp', spec_char) > 0) then
        format_spec = format_str(start_pos:pos)
        pos = pos + 1
        return
      end if
      
      pos = pos + 1
    end do
    
    ! Malformed format specifier
    format_spec = '%s'
  end subroutine

  subroutine format_argument(format_spec, arg_value, formatted_value)
    character(len=*), intent(in) :: format_spec, arg_value
    character(len=*), intent(out) :: formatted_value
    
    character :: conversion_char
    integer :: int_val, status
    real :: real_val
    
    formatted_value = ''
    
    if (len_trim(format_spec) == 0) then
      formatted_value = arg_value
      return
    end if
    
    conversion_char = format_spec(len_trim(format_spec):len_trim(format_spec))
    
    select case (conversion_char)
    case ('s')
      ! String
      formatted_value = arg_value
    case ('c')
      ! Character
      if (len_trim(arg_value) > 0) then
        formatted_value = arg_value(1:1)
      else
        formatted_value = ' '
      end if
    case ('d', 'i')
      ! Integer
      read(arg_value, *, iostat=status) int_val
      if (status == 0) then
        write(formatted_value, '(I0)') int_val
      else
        formatted_value = '0'
      end if
    case ('o')
      ! Octal
      read(arg_value, *, iostat=status) int_val
      if (status == 0) then
        write(formatted_value, '(O0)') int_val
      else
        formatted_value = '0'
      end if
    case ('x')
      ! Hex lowercase
      read(arg_value, *, iostat=status) int_val
      if (status == 0) then
        write(formatted_value, '(Z0)') int_val
        formatted_value = to_lowercase(formatted_value)
      else
        formatted_value = '0'
      end if
    case ('X')
      ! Hex uppercase
      read(arg_value, *, iostat=status) int_val
      if (status == 0) then
        write(formatted_value, '(Z0)') int_val
        formatted_value = to_uppercase(formatted_value)
      else
        formatted_value = '0'
      end if
    case ('f', 'F')
      ! Fixed-point notation
      read(arg_value, *, iostat=status) real_val
      if (status == 0) then
        write(formatted_value, '(F0.6)') real_val
      else
        formatted_value = '0.000000'
      end if
    case ('e')
      ! Scientific notation lowercase
      read(arg_value, *, iostat=status) real_val
      if (status == 0) then
        write(formatted_value, '(E12.6)') real_val
        formatted_value = to_lowercase(formatted_value)
      else
        formatted_value = '0.000000e+00'
      end if
    case ('E')
      ! Scientific notation uppercase
      read(arg_value, *, iostat=status) real_val
      if (status == 0) then
        write(formatted_value, '(E12.6)') real_val
        formatted_value = to_uppercase(formatted_value)
      else
        formatted_value = '0.000000E+00'
      end if
    case ('g', 'G')
      ! General format
      read(arg_value, *, iostat=status) real_val
      if (status == 0) then
        if (abs(real_val) >= 0.0001 .and. abs(real_val) < 1000000.0) then
          write(formatted_value, '(F0.6)') real_val
        else
          write(formatted_value, '(E12.6)') real_val
        end if
        if (conversion_char == 'g') then
          formatted_value = to_lowercase(formatted_value)
        else
          formatted_value = to_uppercase(formatted_value)
        end if
      else
        formatted_value = '0'
      end if
    case default
      ! Unknown format, treat as string
      formatted_value = arg_value
    end select
  end subroutine

  subroutine process_escape_sequence(format_str, pos, output, output_pos)
    character(len=*), intent(in) :: format_str
    integer, intent(inout) :: pos
    character(len=*), intent(inout) :: output
    integer, intent(inout) :: output_pos
    
    character :: escape_char
    
    if (pos >= len_trim(format_str)) then
      pos = pos + 1
      return
    end if
    
    pos = pos + 1  ! Skip backslash
    escape_char = format_str(pos:pos)
    
    select case (escape_char)
    case ('n')
      output(output_pos:output_pos) = char(10)  ! newline
    case ('t')
      output(output_pos:output_pos) = char(9)   ! tab
    case ('r')
      output(output_pos:output_pos) = char(13)  ! carriage return
    case ('b')
      output(output_pos:output_pos) = char(8)   ! backspace
    case ('a')
      output(output_pos:output_pos) = char(7)   ! bell
    case ('f')
      output(output_pos:output_pos) = char(12)  ! form feed
    case ('v')
      output(output_pos:output_pos) = char(11)  ! vertical tab
    case ('\')
      output(output_pos:output_pos) = '\'
    case ('"')
      output(output_pos:output_pos) = '"'
    case ("'")
      output(output_pos:output_pos) = "'"
    case ('0')
      output(output_pos:output_pos) = char(0)   ! null character
    case default
      ! Unknown escape, keep as-is
      output(output_pos:output_pos) = escape_char
    end select
    
    output_pos = output_pos + 1
    pos = pos + 1
  end subroutine

  function to_lowercase(str) result(lower_str)
    character(len=*), intent(in) :: str
    character(len=len(str)) :: lower_str
    integer :: i
    
    lower_str = str
    do i = 1, len_trim(str)
      if (str(i:i) >= 'A' .and. str(i:i) <= 'Z') then
        lower_str(i:i) = char(ichar(str(i:i)) + 32)
      end if
    end do
  end function

  function to_uppercase(str) result(upper_str)
    character(len=*), intent(in) :: str
    character(len=len(str)) :: upper_str
    integer :: i
    
    upper_str = str
    do i = 1, len_trim(str)
      if (str(i:i) >= 'a' .and. str(i:i) <= 'z') then
        upper_str(i:i) = char(ichar(str(i:i)) - 32)
      end if
    end do
  end function

end module printf_builtin