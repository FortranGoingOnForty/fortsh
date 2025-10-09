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

  ! Main entry point - loads configs based on shell type
  subroutine load_config_file(shell)
    type(shell_state_t), intent(inout) :: shell

    ! Check if this is first run and prompt for config creation
    if (shell%is_interactive) then
      call check_first_run_and_prompt(shell)
    end if

    if (shell%is_login_shell) then
      ! Login shell: load profile files
      call load_login_configs(shell)
    else if (shell%is_interactive) then
      ! Interactive non-login shell: load rc files
      call load_interactive_configs(shell)
    else
      ! Non-interactive shell: check ENV variable
      call load_noninteractive_configs(shell)
    end if
  end subroutine

  ! Check if this is first run (no config files) and prompt user
  subroutine check_first_run_and_prompt(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir
    logical :: fortshrc_exists, fortsh_profile_exists
    character(len=10) :: response

    ! Get home directory
    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) return

    ! Check if config files exist
    inquire(file=trim(home_dir)//'/.fortshrc', exist=fortshrc_exists)
    inquire(file=trim(home_dir)//'/.fortsh_profile', exist=fortsh_profile_exists)

    ! If at least one exists, assume not first run
    if (fortshrc_exists .or. fortsh_profile_exists) return

    ! First run detected - prompt user
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') '==================================================================='
    write(output_unit, '(a)') 'Welcome to Fortran Shell (fortsh)!'
    write(output_unit, '(a)') 'It looks like this is your first time running fortsh.'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Would you like to create default configuration files?'
    write(output_unit, '(a)') '  - ~/.fortshrc       (interactive shell config)'
    write(output_unit, '(a)') '  - ~/.fortsh_profile (login shell config)'
    write(output_unit, '(a)') '  - ~/.fortsh_logout  (logout script)'
    write(output_unit, '(a)') '==================================================================='
    write(output_unit, '(a)', advance='no') 'Create default configs? [Y/n]: '

    ! Read user response
    read(*, '(a)') response

    ! Check response (default to yes)
    if (len_trim(response) == 0 .or. &
        response(1:1) == 'Y' .or. response(1:1) == 'y') then
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'Creating default configuration files...'
      call create_default_config()
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'Configuration files created successfully!'
      write(output_unit, '(a)') 'You can customize them by editing the files in your home directory.'
      write(output_unit, '(a)') 'Type "config show" to view the current configuration.'
      write(output_unit, '(a)') ''
    else
      write(output_unit, '(a)') ''
      write(output_unit, '(a)') 'Skipping config creation.'
      write(output_unit, '(a)') 'You can create them later by running: config create'
      write(output_unit, '(a)') ''
    end if
  end subroutine

  ! Load configuration for login shells
  subroutine load_login_configs(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir
    logical :: file_exists

    ! 1. System-wide profile
    call source_if_exists('/etc/fortsh/profile', shell, .false.)

    ! 2. User profile (try in order)
    home_dir = get_environment_var('HOME')
    if (len(home_dir) > 0) then
      ! Try ~/.fortsh_profile first
      inquire(file=trim(home_dir)//'/.fortsh_profile', exist=file_exists)
      if (file_exists) then
        call source_if_exists(trim(home_dir)//'/.fortsh_profile', shell, .true.)
        return
      end if

      ! Fall back to ~/.profile (POSIX compatibility)
      call source_if_exists(trim(home_dir)//'/.profile', shell, .true.)
    end if
  end subroutine

  ! Load configuration for interactive non-login shells
  subroutine load_interactive_configs(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: home_dir

    ! 1. System-wide rc file
    call source_if_exists('/etc/fortsh/fortshrc', shell, .false.)

    ! 2. User rc file
    home_dir = get_environment_var('HOME')
    if (len(home_dir) > 0) then
      ! Try ~/.fortshrc (new style)
      call source_if_exists(trim(home_dir)//'/.fortshrc', shell, .true.)

      ! Also try legacy ~/.fshrc for backward compatibility
      call source_if_exists(trim(home_dir)//'/.fshrc', shell, .false.)
    end if
  end subroutine

  ! Load configuration for non-interactive shells
  subroutine load_noninteractive_configs(shell)
    type(shell_state_t), intent(inout) :: shell
    character(len=:), allocatable :: env_file

    ! Check ENV variable
    env_file = get_environment_var('ENV')
    if (len(env_file) > 0) then
      call source_if_exists(env_file, shell, .false.)
    end if
  end subroutine

  ! Helper: source a file if it exists
  subroutine source_if_exists(filepath, shell, verbose)
    character(len=*), intent(in) :: filepath
    type(shell_state_t), intent(inout) :: shell
    logical, intent(in) :: verbose
    logical :: file_exists

    inquire(file=filepath, exist=file_exists)
    if (.not. file_exists) return

    if (verbose) then
      write(output_unit, '(a)') 'Loading ' // trim(filepath) // '...'
    end if

    ! Set up to source the file
    shell%source_file = filepath
    shell%should_source = .true.
  end subroutine

  ! Legacy load function for backward compatibility
  subroutine load_legacy_config(shell)
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

  ! Create default configuration files
  subroutine create_default_config()
    character(len=:), allocatable :: home_dir

    ! Get home directory
    home_dir = get_environment_var('HOME')
    if (len(home_dir) == 0) then
      write(output_unit, '(a)') 'fortsh: warning: HOME not set, cannot create config files'
      return
    end if

    ! Create all default config files
    call create_fortshrc(home_dir)
    call create_fortsh_profile(home_dir)
    call create_fortsh_logout(home_dir)
  end subroutine

  ! Create default ~/.fortshrc
  subroutine create_fortshrc(home_dir)
    character(len=*), intent(in) :: home_dir
    character(len=:), allocatable :: config_file
    integer :: unit, iostat
    logical :: file_exists

    config_file = trim(home_dir) // '/.fortshrc'

    inquire(file=config_file, exist=file_exists)
    if (file_exists) then
      write(output_unit, '(a)') 'fortsh: ~/.fortshrc already exists'
      return
    end if

    open(newunit=unit, file=config_file, status='new', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: error: could not create ~/.fortshrc'
      return
    end if

    ! Write comprehensive default configuration
    write(unit, '(a)') '# ~/.fortshrc - Fortsh interactive shell configuration'
    write(unit, '(a)') '# This file is sourced by interactive non-login shells'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Prompt Configuration ====='
    write(unit, '(a)') '# Default fortsh style with :: separator'
    write(unit, '(a)') 'PS1=''\u@\h :: \w\$ '''
    write(unit, '(a)') ''
    write(unit, '(a)') '# Colorful prompt (uncomment to use)'
    write(unit, '(a)') '# PS1=''\[\e[1;32m\]\u@\h\[\e[0m\] :: \[\e[1;34m\]\w\[\e[0m\]\$ '''
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Environment Variables ====='
    write(unit, '(a)') 'export EDITOR=vim'
    write(unit, '(a)') 'export PAGER=less'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Aliases ====='
    write(unit, '(a)') 'alias ll=''ls -lah'''
    write(unit, '(a)') 'alias la=''ls -A'''
    write(unit, '(a)') 'alias ..=''cd ..'''
    write(unit, '(a)') 'alias ...=''cd ../..'''
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Shell Options ====='
    write(unit, '(a)') '# set -o emacs    # Emacs editing mode'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Welcome Message ====='
    write(unit, '(a)') 'echo "Welcome to Fortran Shell!"'

    close(unit)
    write(output_unit, '(a)') 'Created: ~/.fortshrc'
  end subroutine

  ! Create default ~/.fortsh_profile
  subroutine create_fortsh_profile(home_dir)
    character(len=*), intent(in) :: home_dir
    character(len=:), allocatable :: config_file
    integer :: unit, iostat
    logical :: file_exists

    config_file = trim(home_dir) // '/.fortsh_profile'

    inquire(file=config_file, exist=file_exists)
    if (file_exists) then
      write(output_unit, '(a)') 'fortsh: ~/.fortsh_profile already exists'
      return
    end if

    open(newunit=unit, file=config_file, status='new', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: error: could not create ~/.fortsh_profile'
      return
    end if

    write(unit, '(a)') '# ~/.fortsh_profile - Fortsh login shell configuration'
    write(unit, '(a)') '# This file is sourced by login shells'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== PATH Configuration ====='
    write(unit, '(a)') 'export PATH="$HOME/bin:$HOME/.local/bin:$PATH"'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Source interactive config if shell is interactive ====='
    write(unit, '(a)') '# This ensures ~/.fortshrc is loaded in login shells too'
    write(unit, '(a)') 'if [ -f ~/.fortshrc ]; then'
    write(unit, '(a)') '    source ~/.fortshrc'
    write(unit, '(a)') 'fi'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Login-specific setup ====='
    write(unit, '(a)') '# Set umask'
    write(unit, '(a)') '# umask 022'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Display login information'
    write(unit, '(a)') 'echo "Logged in as $USER on $HOSTNAME"'
    write(unit, '(a)') 'echo "Today is $(date)"'

    close(unit)
    write(output_unit, '(a)') 'Created: ~/.fortsh_profile'
  end subroutine

  ! Create default ~/.fortsh_logout
  subroutine create_fortsh_logout(home_dir)
    character(len=*), intent(in) :: home_dir
    character(len=:), allocatable :: config_file
    integer :: unit, iostat
    logical :: file_exists

    config_file = trim(home_dir) // '/.fortsh_logout'

    inquire(file=config_file, exist=file_exists)
    if (file_exists) then
      write(output_unit, '(a)') 'fortsh: ~/.fortsh_logout already exists'
      return
    end if

    open(newunit=unit, file=config_file, status='new', action='write', iostat=iostat)
    if (iostat /= 0) then
      write(error_unit, '(a)') 'fortsh: error: could not create ~/.fortsh_logout'
      return
    end if

    write(unit, '(a)') '# ~/.fortsh_logout - Fortsh logout script'
    write(unit, '(a)') '# This file is executed when a login shell exits'
    write(unit, '(a)') ''
    write(unit, '(a)') '# ===== Cleanup tasks ====='
    write(unit, '(a)') '# Clear the screen'
    write(unit, '(a)') '# clear'
    write(unit, '(a)') ''
    write(unit, '(a)') '# Display logout message'
    write(unit, '(a)') 'echo "Logging out from fortsh..."'
    write(unit, '(a)') 'echo "Session ended at $(date)"'

    close(unit)
    write(output_unit, '(a)') 'Created: ~/.fortsh_logout'
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