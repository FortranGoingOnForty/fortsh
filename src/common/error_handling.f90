! ==============================================================================
! Module: error_handling
! Purpose: Comprehensive error handling and logging for fortsh
! ==============================================================================
module error_handling
  use iso_fortran_env, only: output_unit, error_unit
  implicit none

  ! Error severity levels
  integer, parameter :: ERR_DEBUG = 0
  integer, parameter :: ERR_INFO = 1
  integer, parameter :: ERR_WARN = 2
  integer, parameter :: ERR_ERROR = 3
  integer, parameter :: ERR_FATAL = 4

  ! Error categories
  integer, parameter :: ERR_CAT_PARSER = 100
  integer, parameter :: ERR_CAT_EXECUTOR = 200
  integer, parameter :: ERR_CAT_SYSTEM = 300
  integer, parameter :: ERR_CAT_IO = 400
  integer, parameter :: ERR_CAT_MEMORY = 500

  ! Global error handling state
  logical :: debug_mode = .false.
  logical :: verbose_errors = .true.
  integer :: max_error_count = 50
  integer :: error_count = 0

  type :: error_info_t
    integer :: severity
    integer :: category
    integer :: code
    character(len=256) :: message
    character(len=64) :: location
    character(len=32) :: timestamp
  end type error_info_t

  type(error_info_t) :: error_history(50)

contains

  ! Log an error with context information
  subroutine log_error(severity, category, code, message, location)
    integer, intent(in) :: severity, category, code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    
    character(len=32) :: severity_str, category_str
    character(len=64) :: loc_str
    
    ! Increment error count and store in history
    error_count = error_count + 1
    if (error_count <= max_error_count) then
      error_history(error_count)%severity = severity
      error_history(error_count)%category = category
      error_history(error_count)%code = code
      error_history(error_count)%message = message
      if (present(location)) then
        error_history(error_count)%location = location
      else
        error_history(error_count)%location = 'unknown'
      end if
      call get_timestamp(error_history(error_count)%timestamp)
    end if
    
    ! Only display if severity is high enough
    if (severity < ERR_WARN .and. .not. debug_mode) return
    
    ! Format severity and category
    call format_severity(severity, severity_str)
    call format_category(category, category_str)
    
    if (present(location)) then
      loc_str = location
    else
      loc_str = 'unknown'
    end if
    
    ! Print error message
    if (severity >= ERR_ERROR) then
      write(error_unit, '(a,a,a,a,a,i15,a,a,a,a,a)') &
        '[', trim(severity_str), '] ', trim(category_str), ' (', code, ') in ', &
        trim(loc_str), ': ', trim(message)
    else if (verbose_errors .or. debug_mode) then
      write(output_unit, '(a,a,a,a,a,i15,a,a,a,a,a)') &
        '[', trim(severity_str), '] ', trim(category_str), ' (', code, ') in ', &
        trim(loc_str), ': ', trim(message)
    end if
    
    ! Fatal errors should terminate
    if (severity == ERR_FATAL) then
      write(error_unit, '(a)') 'FATAL ERROR: Terminating shell'
      stop 1
    end if
  end subroutine

  ! Convenience functions for common error types
  subroutine parser_error(code, message, location)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_ERROR, ERR_CAT_PARSER, code, message, location)
  end subroutine

  subroutine executor_error(code, message, location)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_ERROR, ERR_CAT_EXECUTOR, code, message, location)
  end subroutine

  subroutine system_error(code, message, location)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_ERROR, ERR_CAT_SYSTEM, code, message, location)
  end subroutine

  subroutine io_error(code, message, location)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_ERROR, ERR_CAT_IO, code, message, location)
  end subroutine

  subroutine memory_error(code, message, location)
    integer, intent(in) :: code
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_FATAL, ERR_CAT_MEMORY, code, message, location)
  end subroutine

  subroutine debug_log(message, location)
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_DEBUG, 0, 0, message, location)
  end subroutine

  subroutine warning_log(message, location)
    character(len=*), intent(in) :: message
    character(len=*), intent(in), optional :: location
    call log_error(ERR_WARN, 0, 0, message, location)
  end subroutine

  ! Validate system resource availability
  function check_system_resources() result(is_ok)
    logical :: is_ok
    integer :: available_memory, available_fds
    
    is_ok = .true.
    
    ! Basic resource checks (simplified)
    available_memory = 1000000  ! Placeholder
    available_fds = 100         ! Placeholder
    
    if (available_memory < 1000) then
      call system_error(301, 'Low memory warning', 'check_system_resources')
      is_ok = .false.
    end if
    
    if (available_fds < 10) then
      call system_error(302, 'Low file descriptor count', 'check_system_resources')
      is_ok = .false.
    end if
  end function

  ! Validate command before execution
  function validate_command(command) result(is_valid)
    character(len=*), intent(in) :: command
    logical :: is_valid
    
    is_valid = .true.
    
    ! Basic command validation
    if (len_trim(command) == 0) then
      call executor_error(201, 'Empty command', 'validate_command')
      is_valid = .false.
      return
    end if
    
    if (len_trim(command) > 4096) then
      call executor_error(202, 'Command too long', 'validate_command')
      is_valid = .false.
      return
    end if
    
    ! Check for potentially dangerous commands
    if (index(command, 'rm -rf /') > 0) then
      call executor_error(203, 'Dangerous command detected', 'validate_command')
      is_valid = .false.
      return
    end if
    
    call debug_log('Command validation passed: ' // trim(command), 'validate_command')
  end function

  ! Validate file operations
  function validate_file_operation(operation, filepath) result(is_valid)
    character(len=*), intent(in) :: operation, filepath
    logical :: is_valid
    
    is_valid = .true.
    
    if (len_trim(filepath) == 0) then
      call io_error(401, 'Empty file path', 'validate_file_operation')
      is_valid = .false.
      return
    end if
    
    if (len_trim(filepath) > 4096) then
      call io_error(402, 'File path too long', 'validate_file_operation')
      is_valid = .false.
      return
    end if
    
    ! Check for directory traversal attempts
    if (index(filepath, '../') > 0) then
      call warning_log('Directory traversal detected: ' // trim(filepath), 'validate_file_operation')
    end if
    
    call debug_log('File operation validated: ' // trim(operation) // ' ' // trim(filepath), &
                  'validate_file_operation')
  end function

  ! Memory allocation wrapper with error handling
  subroutine safe_allocate_string_array(array, size, length, location)
    character(len=:), allocatable, intent(out) :: array(:)
    integer, intent(in) :: size, length
    character(len=*), intent(in), optional :: location
    
    integer :: stat
    character(len=64) :: loc_str
    
    if (present(location)) then
      loc_str = location
    else
      loc_str = 'unknown'
    end if
    
    allocate(character(len=length) :: array(size), stat=stat)
    
    if (stat /= 0) then
      call memory_error(501, 'Failed to allocate string array', loc_str)
    else
      call debug_log('Successfully allocated string array', loc_str)
    end if
  end subroutine

  ! Print error summary
  subroutine print_error_summary()
    integer :: i, warn_count, error_count_local, fatal_count
    
    warn_count = 0
    error_count_local = 0
    fatal_count = 0
    
    do i = 1, min(error_count, max_error_count)
      select case(error_history(i)%severity)
      case(ERR_WARN)
        warn_count = warn_count + 1
      case(ERR_ERROR)
        error_count_local = error_count_local + 1
      case(ERR_FATAL)
        fatal_count = fatal_count + 1
      end select
    end do
    
    if (error_count > 0) then
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'Error Summary:'
      write(output_unit, '(a,i15)') '  Warnings: ', warn_count
      write(output_unit, '(a,i15)') '  Errors:   ', error_count_local
      write(output_unit, '(a,i15)') '  Fatal:    ', fatal_count
      write(output_unit, '(a,i15)') '  Total:    ', min(error_count, max_error_count)
    end if
  end subroutine

  ! Clear error history
  subroutine clear_error_history()
    error_count = 0
    call debug_log('Error history cleared', 'clear_error_history')
  end subroutine

  ! Set debugging mode
  subroutine set_debug_mode(enabled)
    logical, intent(in) :: enabled
    debug_mode = enabled
    if (enabled) then
      call debug_log('Debug mode enabled', 'set_debug_mode')
    end if
  end subroutine

  ! Helper functions
  subroutine format_severity(severity, str)
    integer, intent(in) :: severity
    character(len=*), intent(out) :: str
    
    select case(severity)
    case(ERR_DEBUG)
      str = 'DEBUG'
    case(ERR_INFO)
      str = 'INFO'
    case(ERR_WARN)
      str = 'WARN'
    case(ERR_ERROR)
      str = 'ERROR'
    case(ERR_FATAL)
      str = 'FATAL'
    case default
      str = 'UNKNOWN'
    end select
  end subroutine

  subroutine format_category(category, str)
    integer, intent(in) :: category
    character(len=*), intent(out) :: str
    
    select case(category)
    case(ERR_CAT_PARSER)
      str = 'PARSER'
    case(ERR_CAT_EXECUTOR)
      str = 'EXECUTOR'
    case(ERR_CAT_SYSTEM)
      str = 'SYSTEM'
    case(ERR_CAT_IO)
      str = 'IO'
    case(ERR_CAT_MEMORY)
      str = 'MEMORY'
    case default
      str = 'GENERAL'
    end select
  end subroutine

  subroutine get_timestamp(timestamp)
    character(len=*), intent(out) :: timestamp
    ! Simplified timestamp - in production would use system calls
    timestamp = '2024-01-01T12:00:00'
  end subroutine

end module error_handling