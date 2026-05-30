! ==============================================================================
! Module: heredoc
! Purpose: Here documents and here strings support
! ==============================================================================
module heredoc
  use shell_types
  use variables
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  integer, parameter :: MAX_HEREDOC_LINES = 1000
  integer, parameter :: MAX_HEREDOC_LENGTH = 4096

  type :: heredoc_t
    character(len=256) :: delimiter
    character(len=MAX_HEREDOC_LENGTH) :: lines(MAX_HEREDOC_LINES)
    integer :: num_lines
    logical :: expand_variables
    logical :: strip_tabs
    character(len=MAX_PATH_LEN) :: temp_file
  end type heredoc_t

contains

  subroutine parse_heredoc_redirection(shell, cmd_line, heredoc_start, cmd_modified)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(inout) :: cmd_line
    integer, intent(out) :: heredoc_start
    logical, intent(out) :: cmd_modified

    integer :: pos, delimiter_start, delimiter_end
    character(len=256) :: delimiter
    logical :: strip_tabs, expand_vars

    ! write(error_unit, '(A,A,A)') 'DEBUG: parse_heredoc_redirection called with cmd_line=|', trim(cmd_line), '|'

    cmd_modified = .false.
    heredoc_start = 0

    ! Look for << or <<< operators
    pos = index(cmd_line, '<<')
    if (pos == 0) return
    
    ! Check if it's a here string (<<<)
    if (pos > 0 .and. pos + 2 <= len_trim(cmd_line) .and. cmd_line(pos+2:pos+2) == '<') then
      call parse_here_string(shell, cmd_line, pos, cmd_modified)
      return
    end if
    
    ! It's a here document (<<)
    heredoc_start = pos
    
    ! Check for <<- (strip leading tabs)
    strip_tabs = .false.
    if (pos + 2 <= len_trim(cmd_line) .and. cmd_line(pos+2:pos+2) == '-') then
      strip_tabs = .true.
      delimiter_start = pos + 3
    else
      delimiter_start = pos + 2
    end if
    
    ! Skip whitespace after <<
    do while (delimiter_start <= len_trim(cmd_line) .and. &
              (cmd_line(delimiter_start:delimiter_start) == ' ' .or. &
               cmd_line(delimiter_start:delimiter_start) == char(9)))
      delimiter_start = delimiter_start + 1
    end do
    
    ! Extract delimiter
    delimiter_end = delimiter_start
    do while (delimiter_end <= len_trim(cmd_line) .and. &
              cmd_line(delimiter_end:delimiter_end) /= ' ' .and. &
              cmd_line(delimiter_end:delimiter_end) /= char(9))
      delimiter_end = delimiter_end + 1
    end do
    
    if (delimiter_start >= delimiter_end) then
      write(error_unit, '(a)') 'heredoc: missing delimiter'
      shell%last_exit_status = 1
      return
    end if
    
    delimiter = cmd_line(delimiter_start:delimiter_end-1)

    ! write(error_unit, '(A,A,A,A,A,L1)') 'DEBUG: parse_heredoc delimiter=|', &
    !   trim(delimiter), '| vs pending=|', trim(shell%pending_heredoc_delimiter), '| has=', shell%has_pending_heredoc

    ! Check if delimiter is quoted (affects variable expansion)
    expand_vars = .true.
    if (delimiter(1:1) == '"' .or. delimiter(1:1) == "'" .or. delimiter(1:1) == '\') then
      expand_vars = .false.
      ! Remove quotes from delimiter
      if (len_trim(delimiter) > 2) then
        delimiter = delimiter(2:len_trim(delimiter)-1)
      end if
    end if
    
    ! Process the here document
    call process_heredoc(shell, delimiter, expand_vars, strip_tabs, cmd_line, pos)
    cmd_modified = .true.
  end subroutine

  subroutine parse_here_string(shell, cmd_line, pos, cmd_modified)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(inout) :: cmd_line
    integer, intent(in) :: pos
    logical, intent(out) :: cmd_modified

    character(len=2048) :: here_string, expanded_string, temp_file
    integer :: string_start
    
    cmd_modified = .false.
    
    ! Find the start of the here string (after <<<)
    string_start = pos + 3
    
    ! Skip whitespace
    do while (string_start <= len_trim(cmd_line) .and. &
              (cmd_line(string_start:string_start) == ' ' .or. &
               cmd_line(string_start:string_start) == char(9)))
      string_start = string_start + 1
    end do
    
    if (string_start > len_trim(cmd_line)) then
      write(error_unit, '(a)') 'here string: missing string'
      shell%last_exit_status = 1
      return
    end if
    
    ! Extract the here string (rest of the line)
    here_string = cmd_line(string_start:)
    
    ! Expand variables in the here string
    call expand_here_string(shell, here_string, expanded_string)
    
    ! Create temporary file with the expanded string
    call create_temp_heredoc_file(expanded_string, temp_file)
    
    ! Replace the <<< part with redirection from temp file
    cmd_line = cmd_line(1:pos-1) // ' < ' // trim(temp_file)
    cmd_modified = .true.
  end subroutine

  subroutine process_heredoc(shell, delimiter, expand_vars, strip_tabs, cmd_line, pos)
    type(shell_state_t), intent(inout) :: shell
    character(len=*), intent(in) :: delimiter
    logical, intent(in) :: expand_vars, strip_tabs
    character(len=*), intent(inout) :: cmd_line
    integer, intent(in) :: pos

    ! Use allocatable array to avoid static storage (was 4MB!)
    character(len=MAX_HEREDOC_LENGTH), allocatable :: doc_lines(:)
    character(len=MAX_HEREDOC_LENGTH) :: line, processed_line
    character(len=MAX_PATH_LEN) :: temp_file
    integer :: num_lines, i, capacity
    logical :: found_delimiter, actual_expand_vars
    
    ! Allocate initial array
    allocate(doc_lines(20))  ! Start with reasonable size
    capacity = 20
    num_lines = 0
    found_delimiter = .false.
    actual_expand_vars = expand_vars  ! Default to input value

    ! Check if we have pending heredoc content from -c flag
    if (shell%has_pending_heredoc .and. &
        trim(shell%pending_heredoc_delimiter) == trim(delimiter)) then
      ! Use the pre-stored heredoc content
      ! Use the stored quoted flag to determine expansion
      actual_expand_vars = .not. shell%pending_heredoc_quoted

      ! DEBUG: Print what we're doing
      ! write(error_unit, '(A,L1,A,A,A,A)') 'DEBUG: Using pending heredoc, expand_vars=', actual_expand_vars, &
      !   ', delimiter=', trim(delimiter), ', pending_delim=', trim(shell%pending_heredoc_delimiter)

      ! Split pending content into lines
      block
        integer :: line_start, line_end, content_len
        content_len = len_trim(shell%pending_heredoc)
        line_start = 1

        do while (line_start <= content_len)
          ! Find end of line
          line_end = line_start
          do while (line_end <= content_len .and. &
                    shell%pending_heredoc(line_end:line_end) /= char(10))
            line_end = line_end + 1
          end do

          num_lines = num_lines + 1
          ! Grow array if needed
          if (num_lines > capacity) then
            block
              character(len=MAX_HEREDOC_LENGTH), allocatable :: temp(:)
              allocate(temp(capacity * 2))
              temp(1:capacity) = doc_lines
              call move_alloc(temp, doc_lines)
              capacity = capacity * 2
            end block
          end if

          ! Store the line
          if (line_end > line_start) then
            doc_lines(num_lines) = shell%pending_heredoc(line_start:line_end-1)
          else
            doc_lines(num_lines) = ''
          end if

          line_start = line_end + 1
        end do
      end block

      ! Clear the pending heredoc
      shell%has_pending_heredoc = .false.
      shell%pending_heredoc = ''
      found_delimiter = .true.

    else
      ! Read from stdin as usual
      write(output_unit, '(a)', advance='no') '> '

      ! Read lines until we find the delimiter
      do while (.true.)  ! Remove MAX_HEREDOC_LINES limit
        read(input_unit, '(a)', iostat=i) line
        if (i /= 0) then
          write(error_unit, '(a)') 'heredoc: unexpected end of input'
          shell%last_exit_status = 1
          if (allocated(doc_lines)) deallocate(doc_lines)
          return
        end if

        ! Check if this line is the delimiter
        if (strip_tabs) then
          ! Remove leading tabs for comparison
          processed_line = line
          do while (len_trim(processed_line) > 0 .and. processed_line(1:1) == char(9))
            processed_line = processed_line(2:)
          end do
        else
          processed_line = line
        end if

        if (trim(processed_line) == trim(delimiter)) then
          found_delimiter = .true.
          exit
        end if

        num_lines = num_lines + 1
        ! Grow array if needed
        if (num_lines > capacity) then
        call grow_heredoc_array(doc_lines, capacity)
      end if
      doc_lines(num_lines) = line

      ! Show continuation prompt
      write(output_unit, '(a)', advance='no') '> '
    end do
    end if  ! end of else (reading from stdin vs using pending heredoc)

    if (.not. found_delimiter) then
      write(error_unit, '(a,a,a)') 'heredoc: delimiter "', trim(delimiter), '" not found'
      shell%last_exit_status = 1
      if (allocated(doc_lines)) deallocate(doc_lines)
      return
    end if
    
    ! Process the collected lines
    call process_heredoc_lines(shell, doc_lines(1:num_lines), num_lines, actual_expand_vars, strip_tabs, temp_file)

    ! Clean up allocatable array
    if (allocated(doc_lines)) deallocate(doc_lines)

    ! Replace the heredoc part in command line with file redirection
    cmd_line = cmd_line(1:pos-1) // ' < ' // trim(temp_file)
  end subroutine

  ! Helper subroutine to grow heredoc array
  subroutine grow_heredoc_array(array, current_size)
    character(len=MAX_HEREDOC_LENGTH), allocatable, intent(inout) :: array(:)
    integer, intent(inout) :: current_size
    character(len=MAX_HEREDOC_LENGTH), allocatable :: new_array(:)
    integer :: new_size

    new_size = current_size * 2
    allocate(new_array(new_size))

    ! Copy existing data
    new_array(1:current_size) = array(1:current_size)

    ! Swap arrays
    call move_alloc(new_array, array)
    current_size = new_size
  end subroutine

  subroutine process_heredoc_lines(shell, lines, num_lines, expand_vars, strip_tabs, temp_file)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: lines(:)
    integer, intent(in) :: num_lines
    logical, intent(in) :: expand_vars, strip_tabs
    character(len=*), intent(out) :: temp_file

    character(len=MAX_HEREDOC_LENGTH) :: processed_line, expanded_line
    integer :: unit, i
    
    ! Create temporary file
    call create_temp_file(temp_file, unit)
    if (unit <= 0) then
      write(error_unit, '(a)') 'heredoc: cannot create temporary file'
      return
    end if
    
    ! Write processed lines to temporary file
    do i = 1, num_lines
      processed_line = lines(i)
      
      ! Strip leading tabs if requested
      if (strip_tabs) then
        do while (len_trim(processed_line) > 0 .and. processed_line(1:1) == char(9))
          processed_line = processed_line(2:)
        end do
      end if
      
      ! Expand variables if requested
      if (expand_vars) then
        call expand_here_string(shell, processed_line, expanded_line)
        processed_line = expanded_line
      end if
      
      write(unit, '(a)') trim(processed_line)
    end do
    
    close(unit)
  end subroutine

  subroutine expand_here_string(shell, input_string, expanded_string)
    type(shell_state_t), intent(in) :: shell
    character(len=*), intent(in) :: input_string
    character(len=*), intent(out) :: expanded_string
    
    character(len=len(input_string)) :: work_string
    integer :: pos, var_start, var_end
    character(len=256) :: var_name
    character(len=:), allocatable :: var_value
    
    work_string = input_string
    expanded_string = ''
    pos = 1
    
    do while (pos <= len_trim(work_string))
      if (work_string(pos:pos) == '$' .and. pos < len_trim(work_string)) then
        ! Found variable reference
        var_start = pos + 1
        var_end = var_start
        
        ! Find end of variable name
        if (work_string(var_start:var_start) == '{') then
          ! ${variable} format
          var_start = var_start + 1
          do while (var_end <= len_trim(work_string) .and. work_string(var_end:var_end) /= '}')
            var_end = var_end + 1
          end do
          if (var_end <= len_trim(work_string) .and. work_string(var_end:var_end) == '}') then
            var_name = work_string(var_start:var_end-1)
            pos = var_end + 1
          else
            ! Malformed variable reference
            expanded_string = trim(expanded_string) // '$'
            pos = pos + 1
            cycle
          end if
        else
          ! $variable format
          do while (var_end <= len_trim(work_string) .and. &
                    ((work_string(var_end:var_end) >= 'A' .and. work_string(var_end:var_end) <= 'Z') .or. &
                     (work_string(var_end:var_end) >= 'a' .and. work_string(var_end:var_end) <= 'z') .or. &
                     (work_string(var_end:var_end) >= '0' .and. work_string(var_end:var_end) <= '9') .or. &
                     work_string(var_end:var_end) == '_'))
            var_end = var_end + 1
          end do
          if (var_end > var_start) then
            var_name = work_string(var_start:var_end-1)
            pos = var_end
          else
            expanded_string = trim(expanded_string) // '$'
            pos = pos + 1
            cycle
          end if
        end if
        
        ! Get variable value
        var_value = get_shell_variable(shell, trim(var_name))
        expanded_string = trim(expanded_string) // trim(var_value)
      else
        expanded_string = trim(expanded_string) // work_string(pos:pos)
        pos = pos + 1
      end if
    end do
  end subroutine

  subroutine create_temp_file(filename, unit)
    use system_interface, only: make_temp_file
    character(len=*), intent(out) :: filename
    integer, intent(out) :: unit
    logical :: ok
    integer :: ios

    ! Securely create a unique temp file (mkstemp: random name, 0600, O_EXCL).
    ! The old fixed /tmp/fortsh_heredoc_1234.tmp was a symlink/TOCTOU hazard,
    ! and `iostat=unit` clobbered the newunit handle.
    ok = make_temp_file('fortsh_heredoc_', filename)
    if (.not. ok) then
      unit = -1
      return
    end if

    ! mkstemp already created the file (owned by us); open by its
    ! unpredictable name to write the heredoc body.
    open(newunit=unit, file=trim(filename), status='old', action='write', iostat=ios)
    if (ios /= 0) unit = -1
  end subroutine

  subroutine create_temp_heredoc_file(content, filename)
    character(len=*), intent(in) :: content
    character(len=*), intent(out) :: filename

    integer :: unit
    
    call create_temp_file(filename, unit)
    if (unit <= 0) return
    
    write(unit, '(a)') trim(content)
    close(unit)
  end subroutine

  subroutine cleanup_heredoc_temp_files()
    ! Clean up temporary files (simplified)
    ! In a real implementation, would maintain a list of temp files to clean up
  end subroutine

end module heredoc