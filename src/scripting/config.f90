! ==============================================================================
! Module: config
! Purpose: Shell configuration file handling (.fshrc)
! ==============================================================================
module shell_config
  use shell_types
  use system_interface
  use variables
  use iso_fortran_env, only: input_unit, output_unit, error_unit
  implicit none

  ! Forward declaration to avoid circular dependency
  abstract interface
    subroutine parse_and_execute_interface(input_line, shell)
      import :: shell_state_t
      character(len=*), intent(in) :: input_line
      type(shell_state_t), intent(inout) :: shell
    end subroutine
  end interface
  
  procedure(parse_and_execute_interface), pointer :: parse_and_execute_proc => null()

contains

  subroutine load_config_file(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir, config_file
    character(len=1024) :: line
    integer :: unit, iostat
    logical :: file_exists
    
    ! Get home directory
    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) then
      return  ! No HOME directory, skip config
    end if
    
    ! Construct config file path
    config_file = trim(home_dir) // '/.fshrc'
    
    ! Check if config file exists
    inquire(file=config_file, exist=file_exists)
    if (.not. file_exists) then
      return  ! No config file, continue normally
    end if
    
    ! Try to open and read the config file
    open(newunit=unit, file=config_file, status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: warning: could not read .fshrc'
      return
    end if
    
    write(output_unit, '(a)') 'Loading .fshrc...'
    
    ! Read and execute each line (simplified approach for now)
    do
      read(unit, '(a)', iostat=iostat) line
      if (iostat /= 0) exit  ! End of file or error
      
      ! Skip empty lines and comments
      line = adjustl(line)
      if (len_trim(line) == 0 .or. line(1:1) == '#') cycle
      
      ! For now, just execute simple variable assignments
      if (index(line, '=') > 0 .and. index(line, ' ') == 0) then
        call process_config_assignment(line, shell)
      end if
    end do
    
    close(unit)
    write(output_unit, '(a)') '.fshrc loaded successfully'
  end subroutine

  subroutine process_config_assignment(line, shell)
    character(len=*), intent(in) :: line
    type(shell_state_t), intent(inout) :: shell
    integer :: eq_pos
    character(len=256) :: var_name, var_value
    
    eq_pos = index(line, '=')
    if (eq_pos > 1) then
      var_name = line(:eq_pos-1)
      var_value = line(eq_pos+1:)
      
      ! Set as shell variable
      call set_shell_variable(shell, trim(var_name), trim(var_value))
    end if
  end subroutine

  ! Create a default .fshrc file if it doesn't exist
  subroutine create_default_config()
    character(len=:), allocatable :: home_dir, config_file
    character(len=1024) :: line
    integer :: unit, iostat
    logical :: file_exists
    
    ! Get home directory
    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) then
      write(output_unit, '(a)') 'fortsh: warning: HOME not set, cannot create .fshrc'
      return
    end if
    
    ! Construct config file path
    config_file = trim(home_dir) // '/.fshrc'
    
    ! Check if config file already exists
    inquire(file=config_file, exist=file_exists)
    if (file_exists) then
      write(output_unit, '(a)') 'fortsh: .fshrc already exists'
      return
    end if
    
    ! Create default config file
    open(newunit=unit, file=config_file, status='new', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: error: could not create .fshrc'
      return
    end if
    
    ! Write default configuration
    write(unit, '(a)') '# Fortran Shell (fsh) Configuration File'
    write(unit, '(a)') '# This file is sourced when fsh starts in interactive mode'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Set some useful variables'
    write(unit, '(a)') 'EDITOR=nano'
    write(unit, '(a)') 'PAGER=less'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Welcome message'
    write(unit, '(a)') 'echo "Welcome to Fortran Shell!"'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Show current directory'
    write(unit, '(a)') 'echo "Current directory: $(pwd)"'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Aliases would go here (when implemented)'
    write(unit, '(a)') '# alias ll="ls -la"'
    
    close(unit)
    write(output_unit, '(a)') 'fortsh: created default .fshrc in ' // config_file
  end subroutine

  ! Show the current config file content
  subroutine show_config()
    character(len=:), allocatable :: home_dir, config_file
    character(len=1024) :: line
    integer :: unit, iostat
    logical :: file_exists
    
    ! Get home directory
    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) then
      write(output_unit, '(a)') 'fortsh: warning: HOME not set'
      return
    end if
    
    ! Construct config file path
    config_file = trim(home_dir) // '/.fshrc'
    
    ! Check if config file exists
    inquire(file=config_file, exist=file_exists)
    if (.not. file_exists) then
      write(output_unit, '(a)') 'fortsh: no .fshrc file found'
      return
    end if
    
    ! Open and display the config file
    open(newunit=unit, file=config_file, status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: error: could not read .fshrc'
      return
    end if
    
    write(output_unit, '(a)') 'Contents of .fshrc:'
    write(output_unit, '(a)') '=================='
    
    do
      read(unit, '(a)', iostat=iostat) line
      if (iostat /= 0) exit
      write(output_unit, '(a)') trim(line)
    end do
    
    close(unit)
  end subroutine

end module shell_config