! ==============================================================================
! Module: printf_builtin
! Purpose: Printf built-in command with full POSIX format string support
! ==============================================================================
module printf_builtin
  use shell_types
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Format specifier components
  type :: format_info_t
    logical :: left_align = .false.     ! '-' flag
    logical :: zero_pad = .false.       ! '0' flag
    logical :: show_sign = .false.      ! '+' flag
    logical :: space_sign = .false.     ! ' ' flag
    logical :: alternate = .false.      ! '#' flag
    integer :: width = 0                ! field width
    integer :: precision = -1           ! precision (-1 = default)
    logical :: width_from_arg = .false. ! '*' for width
    logical :: prec_from_arg = .false.  ! '*' for precision
    character :: conversion = 's'       ! conversion specifier
  end type

contains

  subroutine builtin_printf(cmd, shell)
    use iso_fortran_env, only: error_unit
    type(command_t), intent(in) :: cmd
    type(shell_state_t), intent(inout) :: shell

    character(len=4096) :: format_string, output_buffer
    integer :: arg_index, prev_arg_index, output_len, format_string_len
    integer, allocatable :: arg_lengths(:)
    integer :: i

    if (cmd%num_tokens < 2) then
      write(error_unit, '(a)') 'printf: usage: printf FORMAT [ARGUMENTS...]'
      shell%last_exit_status = 1
      return
    end if

    format_string = cmd%tokens(2)
    ! Determine format string length:
    ! - token_lengths can be wrong for strings with shell-processed escapes
    ! - len_trim strips intentional trailing spaces
    ! Solution: Use len_trim as base. For quoted tokens ending with space,
    ! try to preserve trailing spaces if token_lengths is close to len_trim
    ! (difference of 1-2 suggests trailing spaces, not escape processing)
    format_string_len = len_trim(format_string)
    if (allocated(cmd%token_quoted) .and. size(cmd%token_quoted) >= 2) then
      if (cmd%token_quoted(2)) then
        ! Quoted token - check for trailing spaces to preserve
        if (allocated(cmd%token_lengths) .and. size(cmd%token_lengths) >= 2) then
          ! Only extend for small differences (1-2 chars) that suggest trailing spaces
          ! Larger differences likely indicate escape processing mismatch
          if (cmd%token_lengths(2) > format_string_len .and. &
              cmd%token_lengths(2) <= format_string_len + 2 .and. &
              cmd%token_lengths(2) <= len(format_string)) then
            ! Verify the extra chars are spaces
            if (format_string(format_string_len+1:cmd%token_lengths(2)) == &
                repeat(' ', cmd%token_lengths(2) - format_string_len)) then
              format_string_len = cmd%token_lengths(2)
            end if
          end if
        end if
      end if
    end if

    ! Build array of argument lengths for preserving trailing spaces
    allocate(arg_lengths(cmd%num_tokens))
    do i = 1, cmd%num_tokens
      if (allocated(cmd%token_lengths) .and. i <= size(cmd%token_lengths)) then
        arg_lengths(i) = cmd%token_lengths(i)
      else
        arg_lengths(i) = len_trim(cmd%tokens(i))
      end if
    end do

    arg_index = 3

    ! POSIX behavior: always output format string at least once,
    ! then repeat for any remaining arguments
    do
      prev_arg_index = arg_index
      call process_printf_format(format_string, format_string_len, cmd%tokens, &
                                  cmd%num_tokens, arg_lengths, arg_index, &
                                  output_buffer, output_len)
      ! Output exactly output_len characters to preserve trailing spaces
      if (output_len > 0) then
        write(output_unit, '(a)', advance='no') output_buffer(1:output_len)
      end if

      ! If no arguments were consumed, we're done (format has no specifiers or no more args)
      if (arg_index == prev_arg_index .or. arg_index > cmd%num_tokens) exit
    end do

    deallocate(arg_lengths)
    shell%last_exit_status = 0
  end subroutine

  subroutine process_printf_format(format_str, format_str_len, args, num_args, arg_lengths, start_arg, output, output_len)
    character(len=*), intent(in) :: format_str
    integer, intent(in) :: format_str_len
    character(len=*), intent(in) :: args(:)
    integer, intent(in) :: num_args
    integer, intent(in) :: arg_lengths(:)
    integer, intent(inout) :: start_arg
    character(len=*), intent(out) :: output
    integer, intent(out) :: output_len

    integer :: pos, output_pos, arg_index, format_len, fmt_len
    integer :: current_arg_len
    character :: current_char, next_char
    type(format_info_t) :: fmt_info
    character(len=1024) :: arg_value, formatted_value

    pos = 1
    output_pos = 1
    arg_index = start_arg
    output = ''
    ! Use actual format string length to preserve trailing spaces
    format_len = format_str_len

    do while (pos <= format_len)
      current_char = format_str(pos:pos)

      if (current_char == '%' .and. pos < format_len) then
        next_char = format_str(pos+1:pos+1)

        if (next_char == '%') then
          ! Escaped percent
          if (output_pos <= len(output)) then
            output(output_pos:output_pos) = '%'
            output_pos = output_pos + 1
          end if
          pos = pos + 2
        else
          ! Parse format specifier
          call parse_format_specifier(format_str, pos, fmt_info)

          ! Handle dynamic width from argument
          if (fmt_info%width_from_arg) then
            if (arg_index <= num_args) then
              read(args(arg_index), *, err=10, end=10) fmt_info%width
10            arg_index = arg_index + 1
            end if
          end if

          ! Handle dynamic precision from argument
          if (fmt_info%prec_from_arg) then
            if (arg_index <= num_args) then
              read(args(arg_index), *, err=20, end=20) fmt_info%precision
20            arg_index = arg_index + 1
            end if
          end if

          ! Get argument value and its length
          if (arg_index <= num_args) then
            arg_value = args(arg_index)
            if (arg_index <= size(arg_lengths)) then
              current_arg_len = arg_lengths(arg_index)
            else
              current_arg_len = len_trim(arg_value)
            end if
            arg_index = arg_index + 1
          else
            arg_value = ''
            current_arg_len = 0
          end if

          call format_argument(fmt_info, arg_value, current_arg_len, formatted_value, fmt_len)

          ! Append formatted value to output (use exact length to preserve padding)
          call append_to_output_len(output, output_pos, formatted_value, fmt_len)
        end if
      else if (current_char == char(92) .and. pos < format_len) then
        ! Handle escape sequences (backslash)
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
    ! Return actual output length (output_pos - 1 is the last written position)
    output_len = output_pos - 1
  end subroutine

  subroutine parse_format_specifier(format_str, pos, fmt_info)
    character(len=*), intent(in) :: format_str
    integer, intent(inout) :: pos
    type(format_info_t), intent(out) :: fmt_info

    integer :: format_len, width_start
    character :: c
    logical :: parsing_flags, parsing_width, parsing_precision

    ! Initialize
    fmt_info%left_align = .false.
    fmt_info%zero_pad = .false.
    fmt_info%show_sign = .false.
    fmt_info%space_sign = .false.
    fmt_info%alternate = .false.
    fmt_info%width = 0
    fmt_info%precision = -1
    fmt_info%width_from_arg = .false.
    fmt_info%prec_from_arg = .false.
    fmt_info%conversion = 's'

    format_len = len_trim(format_str)
    pos = pos + 1  ! Skip %

    parsing_flags = .true.
    parsing_width = .false.
    parsing_precision = .false.

    do while (pos <= format_len)
      c = format_str(pos:pos)

      ! Parse flags
      if (parsing_flags) then
        select case (c)
        case ('-')
          fmt_info%left_align = .true.
          pos = pos + 1
          cycle
        case ('+')
          fmt_info%show_sign = .true.
          pos = pos + 1
          cycle
        case (' ')
          fmt_info%space_sign = .true.
          pos = pos + 1
          cycle
        case ('#')
          fmt_info%alternate = .true.
          pos = pos + 1
          cycle
        case ('0')
          ! Only a flag if at start of width
          if (.not. parsing_width) then
            fmt_info%zero_pad = .true.
            pos = pos + 1
            cycle
          end if
        case default
          parsing_flags = .false.
        end select
      end if

      ! Parse width
      if (c == '*') then
        fmt_info%width_from_arg = .true.
        pos = pos + 1
        c = format_str(pos:pos)
      else if (c >= '0' .and. c <= '9') then
        width_start = pos
        do while (pos <= format_len)
          c = format_str(pos:pos)
          if (c < '0' .or. c > '9') exit
          pos = pos + 1
        end do
        read(format_str(width_start:pos-1), '(I10)') fmt_info%width
        c = format_str(pos:pos)
      end if

      ! Parse precision
      if (c == '.') then
        pos = pos + 1
        if (pos > format_len) exit
        c = format_str(pos:pos)

        if (c == '*') then
          fmt_info%prec_from_arg = .true.
          pos = pos + 1
        else if (c >= '0' .and. c <= '9') then
          width_start = pos
          do while (pos <= format_len)
            c = format_str(pos:pos)
            if (c < '0' .or. c > '9') exit
            pos = pos + 1
          end do
          read(format_str(width_start:pos-1), '(I10)') fmt_info%precision
        else
          fmt_info%precision = 0
        end if
        if (pos > format_len) exit
        c = format_str(pos:pos)
      end if

      ! Check for conversion specifier
      if (index('diouxXeEfFgGaAcspb', c) > 0) then
        fmt_info%conversion = c
        pos = pos + 1
        return
      end if

      ! Unknown character, skip
      pos = pos + 1
    end do
  end subroutine

  subroutine format_argument(fmt_info, arg_value, arg_len, formatted_value, formatted_len)
    type(format_info_t), intent(in) :: fmt_info
    character(len=*), intent(in) :: arg_value
    integer, intent(in) :: arg_len  ! Actual length of arg_value (to preserve trailing spaces)
    character(len=*), intent(out) :: formatted_value
    integer, intent(out) :: formatted_len

    character(len=1024) :: raw_value, temp_value
    integer :: int_val, status, val_len, pad_len, prec, actual_len
    real(8) :: real_val
    character :: pad_char

    formatted_value = ''
    raw_value = ''
    formatted_len = 0

    ! Use provided arg_len to preserve trailing spaces
    actual_len = arg_len
    if (actual_len <= 0 .or. actual_len > len(arg_value)) then
      actual_len = len_trim(arg_value)
    end if

    select case (fmt_info%conversion)
    case ('s')
      ! String - use actual_len to preserve trailing spaces
      if (actual_len > 0 .and. actual_len <= len(raw_value)) then
        raw_value = arg_value(1:actual_len)
      else
        raw_value = arg_value
      end if
      ! Apply precision (truncation for strings)
      if (fmt_info%precision >= 0 .and. fmt_info%precision < actual_len) then
        raw_value = raw_value(1:fmt_info%precision)
        actual_len = fmt_info%precision
      end if

    case ('b')
      ! %b: interpret backslash escapes in argument
      call interpret_escapes(arg_value, raw_value)

    case ('c')
      ! Character
      if (actual_len > 0) then
        raw_value = arg_value(1:1)
      else
        raw_value = ''
      end if

    case ('d', 'i')
      ! Integer
      call parse_integer(arg_value, int_val, status)
      if (status == 0) then
        call format_integer(int_val, fmt_info, raw_value)
      else
        raw_value = '0'
      end if

    case ('o')
      ! Octal
      call parse_integer(arg_value, int_val, status)
      if (status == 0) then
        write(temp_value, '(O0)') int_val
        raw_value = trim(temp_value)
        if (fmt_info%alternate .and. int_val /= 0) then
          raw_value = '0' // trim(raw_value)
        end if
      else
        raw_value = '0'
      end if

    case ('x')
      ! Hex lowercase
      call parse_integer(arg_value, int_val, status)
      if (status == 0) then
        write(temp_value, '(Z0)') int_val
        raw_value = to_lowercase(trim(temp_value))
        if (fmt_info%alternate .and. int_val /= 0) then
          raw_value = '0x' // trim(raw_value)
        end if
      else
        raw_value = '0'
      end if

    case ('X')
      ! Hex uppercase
      call parse_integer(arg_value, int_val, status)
      if (status == 0) then
        write(temp_value, '(Z0)') int_val
        raw_value = to_uppercase(trim(temp_value))
        if (fmt_info%alternate .and. int_val /= 0) then
          raw_value = '0X' // trim(raw_value)
        end if
      else
        raw_value = '0'
      end if

    case ('u')
      ! Unsigned integer (treat as regular integer in Fortran)
      call parse_integer(arg_value, int_val, status)
      if (status == 0) then
        if (int_val < 0) int_val = int_val + 2147483647 + 1  ! Approximate unsigned
        write(raw_value, '(I0)') int_val
      else
        raw_value = '0'
      end if

    case ('f', 'F')
      ! Fixed-point notation
      read(arg_value, *, iostat=status) real_val
      prec = 6
      if (fmt_info%precision >= 0) prec = fmt_info%precision
      if (status == 0) then
        call format_float_fixed(real_val, prec, raw_value)
      else
        raw_value = '0.' // repeat('0', prec)
      end if

    case ('e')
      ! Scientific notation lowercase
      read(arg_value, *, iostat=status) real_val
      prec = 6
      if (fmt_info%precision >= 0) prec = fmt_info%precision
      if (status == 0) then
        call format_float_exp(real_val, prec, raw_value)
        raw_value = to_lowercase(raw_value)
      else
        raw_value = '0.' // repeat('0', prec) // 'e+00'
      end if

    case ('E')
      ! Scientific notation uppercase
      read(arg_value, *, iostat=status) real_val
      prec = 6
      if (fmt_info%precision >= 0) prec = fmt_info%precision
      if (status == 0) then
        call format_float_exp(real_val, prec, raw_value)
        raw_value = to_uppercase(raw_value)
      else
        raw_value = '0.' // repeat('0', prec) // 'E+00'
      end if

    case ('g', 'G')
      ! General format
      read(arg_value, *, iostat=status) real_val
      prec = 6
      if (fmt_info%precision >= 0) prec = fmt_info%precision
      if (status == 0) then
        if (abs(real_val) >= 0.0001d0 .and. abs(real_val) < 1000000.0d0) then
          call format_float_fixed(real_val, prec, raw_value)
        else
          call format_float_exp(real_val, prec, raw_value)
        end if
        if (fmt_info%conversion == 'g') then
          raw_value = to_lowercase(raw_value)
        else
          raw_value = to_uppercase(raw_value)
        end if
      else
        raw_value = '0'
      end if

    case default
      ! Unknown format, treat as string
      raw_value = arg_value
    end select

    ! Apply width padding
    ! For string types, use actual_len to preserve trailing spaces
    if (fmt_info%conversion == 's') then
      val_len = actual_len
    else
      val_len = len_trim(raw_value)
    end if

    if (fmt_info%width > val_len) then
      pad_len = fmt_info%width - val_len
      if (fmt_info%zero_pad .and. .not. fmt_info%left_align .and. &
          index('diouxXeEfFgG', fmt_info%conversion) > 0) then
        pad_char = '0'
      else
        pad_char = ' '
      end if

      if (fmt_info%left_align) then
        ! For strings, use actual length; for others, use trim
        if (fmt_info%conversion == 's' .and. val_len > 0) then
          formatted_value = raw_value(1:val_len) // repeat(' ', pad_len)
        else
          formatted_value = trim(raw_value) // repeat(' ', pad_len)
        end if
        formatted_len = fmt_info%width
      else
        ! For zero padding with sign, put sign before zeros
        if (pad_char == '0' .and. len_trim(raw_value) > 0) then
          if (raw_value(1:1) == '-' .or. raw_value(1:1) == '+') then
            formatted_value = raw_value(1:1) // repeat('0', pad_len) // trim(raw_value(2:))
          else
            formatted_value = repeat('0', pad_len) // trim(raw_value)
          end if
        else
          if (fmt_info%conversion == 's' .and. val_len > 0) then
            formatted_value = repeat(pad_char, pad_len) // raw_value(1:val_len)
          else
            formatted_value = repeat(pad_char, pad_len) // trim(raw_value)
          end if
        end if
        formatted_len = fmt_info%width
      end if
    else
      ! No padding needed - use exact length
      if (fmt_info%conversion == 's' .and. val_len > 0) then
        formatted_value = raw_value(1:val_len)
      else
        formatted_value = trim(raw_value)
      end if
      formatted_len = val_len
    end if
  end subroutine

  subroutine parse_integer(arg_value, int_val, status)
    character(len=*), intent(in) :: arg_value
    integer, intent(out) :: int_val
    integer, intent(out) :: status

    character(len=256) :: clean_arg
    integer :: i

    clean_arg = adjustl(arg_value)
    int_val = 0
    status = 0

    if (len_trim(clean_arg) == 0) then
      int_val = 0
      return
    end if

    ! Handle character constants like 'A
    if (clean_arg(1:1) == "'" .and. len_trim(clean_arg) >= 2) then
      int_val = ichar(clean_arg(2:2))
      return
    end if

    ! Handle hex (0x...) and octal (0...) prefixes
    if (len_trim(clean_arg) >= 2) then
      if (clean_arg(1:2) == '0x' .or. clean_arg(1:2) == '0X') then
        read(clean_arg(3:), '(Z20)', iostat=status) int_val
        return
      else if (clean_arg(1:1) == '0' .and. len_trim(clean_arg) > 1) then
        ! Could be octal, try it
        read(clean_arg(2:), '(O20)', iostat=status) int_val
        if (status == 0) return
      end if
    end if

    ! Standard decimal
    read(clean_arg, *, iostat=status) int_val
  end subroutine

  subroutine format_integer(int_val, fmt_info, result)
    integer, intent(in) :: int_val
    type(format_info_t), intent(in) :: fmt_info
    character(len=*), intent(out) :: result

    character(len=32) :: temp

    if (int_val >= 0) then
      write(temp, '(I0)') int_val
      if (fmt_info%show_sign) then
        result = '+' // trim(temp)
      else if (fmt_info%space_sign) then
        result = ' ' // trim(temp)
      else
        result = trim(temp)
      end if
    else
      write(temp, '(I0)') int_val
      result = trim(temp)
    end if
  end subroutine

  subroutine format_float_fixed(val, precision, result)
    real(8), intent(in) :: val
    integer, intent(in) :: precision
    character(len=*), intent(out) :: result

    character(len=64) :: fmt_str, temp

    write(fmt_str, '(a,i0,a)') '(F0.', precision, ')'
    write(temp, fmt_str) val
    result = adjustl(temp)
  end subroutine

  subroutine format_float_exp(val, precision, result)
    real(8), intent(in) :: val
    integer, intent(in) :: precision
    character(len=*), intent(out) :: result

    character(len=64) :: fmt_str, temp
    integer :: e_pos, exp_val
    character(len=16) :: mantissa, exp_str

    write(fmt_str, '(a,i0,a,i0,a)') '(ES', precision+8, '.', precision, ')'
    write(temp, fmt_str) val
    result = adjustl(temp)
  end subroutine

  subroutine interpret_escapes(input, output)
    character(len=*), intent(in) :: input
    character(len=*), intent(out) :: output

    integer :: pos, out_pos, input_len, octal_val, i
    character :: c
    character(len=3) :: octal_str

    pos = 1
    out_pos = 1
    input_len = len_trim(input)
    output = ''

    do while (pos <= input_len .and. out_pos <= len(output))
      c = input(pos:pos)

      if (c == char(92) .and. pos < input_len) then  ! backslash
        pos = pos + 1
        c = input(pos:pos)

        select case (c)
        case ('n')
          output(out_pos:out_pos) = char(10)
        case ('t')
          output(out_pos:out_pos) = char(9)
        case ('r')
          output(out_pos:out_pos) = char(13)
        case ('b')
          output(out_pos:out_pos) = char(8)
        case ('a')
          output(out_pos:out_pos) = char(7)
        case ('f')
          output(out_pos:out_pos) = char(12)
        case ('v')
          output(out_pos:out_pos) = char(11)
        case (char(92))  ! backslash
          output(out_pos:out_pos) = char(92)
        case ('0', '1', '2', '3', '4', '5', '6', '7')
          ! Octal escape
          octal_str = c
          do i = 2, 3
            if (pos + i - 1 <= input_len) then
              c = input(pos + i - 1:pos + i - 1)
              if (c >= '0' .and. c <= '7') then
                octal_str(i:i) = c
              else
                exit
              end if
            else
              exit
            end if
          end do
          read(octal_str, '(O3)', err=30) octal_val
          output(out_pos:out_pos) = char(mod(octal_val, 256))
          pos = pos + len_trim(octal_str) - 1
          go to 40
30        output(out_pos:out_pos) = c
40        continue
        case default
          output(out_pos:out_pos) = c
        end select
        out_pos = out_pos + 1
        pos = pos + 1
      else
        output(out_pos:out_pos) = c
        out_pos = out_pos + 1
        pos = pos + 1
      end if
    end do
  end subroutine

  subroutine process_escape_sequence(format_str, pos, output, output_pos)
    character(len=*), intent(in) :: format_str
    integer, intent(inout) :: pos
    character(len=*), intent(inout) :: output
    integer, intent(inout) :: output_pos

    character :: escape_char
    integer :: format_len, octal_val, i
    character(len=3) :: octal_str

    format_len = len_trim(format_str)

    if (pos >= format_len) then
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
    case (char(92))  ! backslash
      output(output_pos:output_pos) = char(92)
    case ('"')
      output(output_pos:output_pos) = '"'
    case ("'")
      output(output_pos:output_pos) = "'"
    case ('0', '1', '2', '3', '4', '5', '6', '7')
      ! Octal escape sequence \NNN
      octal_str = escape_char
      do i = 2, 3
        if (pos + i - 1 <= format_len) then
          escape_char = format_str(pos + i - 1:pos + i - 1)
          if (escape_char >= '0' .and. escape_char <= '7') then
            octal_str(i:i) = escape_char
          else
            exit
          end if
        else
          exit
        end if
      end do
      read(octal_str, '(O3)', err=50) octal_val
      output(output_pos:output_pos) = char(mod(octal_val, 256))
      pos = pos + len_trim(octal_str) - 1
      go to 60
50    output(output_pos:output_pos) = format_str(pos:pos)
60    continue
    case default
      ! Unknown escape - per POSIX, output both backslash and character
      output(output_pos:output_pos) = char(92)  ! backslash
      output_pos = output_pos + 1
      output(output_pos:output_pos) = escape_char
    end select

    output_pos = output_pos + 1
    pos = pos + 1
  end subroutine

  subroutine append_to_output(output, output_pos, value)
    character(len=*), intent(inout) :: output
    integer, intent(inout) :: output_pos
    character(len=*), intent(in) :: value

    integer :: val_len

    val_len = len_trim(value)
    if (val_len == 0) return

    if (output_pos + val_len - 1 <= len(output)) then
      output(output_pos:output_pos + val_len - 1) = value(1:val_len)
      output_pos = output_pos + val_len
    end if
  end subroutine

  subroutine append_to_output_len(output, output_pos, value, value_len)
    character(len=*), intent(inout) :: output
    integer, intent(inout) :: output_pos
    character(len=*), intent(in) :: value
    integer, intent(in) :: value_len

    if (value_len <= 0) return

    if (output_pos + value_len - 1 <= len(output)) then
      output(output_pos:output_pos + value_len - 1) = value(1:value_len)
      output_pos = output_pos + value_len
    end if
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