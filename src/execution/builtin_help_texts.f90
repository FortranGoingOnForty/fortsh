! ==============================================================================
! Module: builtin_help_texts
! Per-builtin help text for `help <builtin>` command
! ==============================================================================
module builtin_help_texts
  use iso_fortran_env, only: output_unit
  implicit none
  private
  public :: print_builtin_help

contains

  function print_builtin_help(name) result(found)
    character(len=*), intent(in) :: name
    logical :: found
    integer :: u

    u = output_unit
    found = .true.

    select case (trim(name))
    ! Navigation & Directories
    case ('cd')
      call help_cd(u)
    case ('pwd')
      call help_pwd(u)
    case ('pushd')
      call help_pushd(u)
    case ('popd')
      call help_popd(u)
    case ('dirs')
      call help_dirs(u)
    case ('prevd')
      call help_prevd(u)
    case ('nextd')
      call help_nextd(u)
    case ('dirh')
      call help_dirh(u)
    case default
      found = .false.
    end select
  end function print_builtin_help

  ! --------------------------------------------------------------------------
  ! Navigation & Directories
  ! --------------------------------------------------------------------------

  subroutine help_cd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'cd: cd [-L|-P] [dir]'
    write(u, '(a)') '    Change the shell working directory.'
    write(u, '(a)') ''
    write(u, '(a)') '    Change the current directory to DIR. The default DIR is the value'
    write(u, '(a)') '    of the HOME shell variable. A DIR of - is equivalent to $OLDPWD.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -L    follow symbolic links (default)'
    write(u, '(a)') '      -P    use physical directory structure without following symlinks'
    write(u, '(a)') ''
    write(u, '(a)') '    The variable CDPATH defines the search path for the directory'
    write(u, '(a)') '    containing DIR. CDPATH entries are separated by colons.'
    write(u, '(a)') '    A null directory name is the same as the current directory.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 if the directory is changed, 1 otherwise.'
  end subroutine help_cd

  subroutine help_pwd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'pwd: pwd [-LP]'
    write(u, '(a)') '    Print the name of the current working directory.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -L    print the value of $PWD if it names the current working'
    write(u, '(a)') '            directory (default)'
    write(u, '(a)') '      -P    print the physical directory, without any symbolic links'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option is given or the current directory'
    write(u, '(a)') '    cannot be read.'
  end subroutine help_pwd

  subroutine help_pushd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'pushd: pushd [-n] [dir]'
    write(u, '(a)') '    Add a directory to the directory stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Save the current directory on the top of the directory stack'
    write(u, '(a)') '    and then cd to DIR. With no arguments, exchanges the top two'
    write(u, '(a)') '    directories on the stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -n    Suppresses the normal change of directory; only manipulates'
    write(u, '(a)') '            the stack'
    write(u, '(a)') ''
    write(u, '(a)') '    Tilde (~) in DIR is expanded to $HOME.'
    write(u, '(a)') '    Maximum stack depth is 32 directories.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 if cd fails or stack is full.'
  end subroutine help_pushd

  subroutine help_popd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'popd: popd [-n] [+N | -N]'
    write(u, '(a)') '    Remove a directory from the directory stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Remove the top entry from the directory stack and cd to the new'
    write(u, '(a)') '    top directory. With no arguments, removes the top directory and'
    write(u, '(a)') '    changes to the new top entry.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -n    Suppresses the normal change of directory; only manipulates'
    write(u, '(a)') '            the stack'
    write(u, '(a)') ''
    write(u, '(a)') '    Arguments:'
    write(u, '(a)') '      +N    Removes the Nth entry counting from the top of the stack'
    write(u, '(a)') '      -N    Removes the Nth entry counting from the bottom'
    write(u, '(a)') ''
    write(u, '(a)') '    When a numeric argument is given, the entry is removed without'
    write(u, '(a)') '    changing the current directory.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 if the stack is empty or index is invalid.'
  end subroutine help_popd

  subroutine help_dirs(u)
    integer, intent(in) :: u
    write(u, '(a)') 'dirs: dirs [-clpv]'
    write(u, '(a)') '    Display the directory stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Display the list of currently remembered directories. Directories'
    write(u, '(a)') '    are added with the pushd command and removed with the popd command.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -c    Clear the directory stack'
    write(u, '(a)') '      -l    Long listing (full paths, no tilde abbreviation)'
    write(u, '(a)') '      -p    Print one entry per line'
    write(u, '(a)') '      -v    Verbose: print numbered stack entries, one per line'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option is given.'
  end subroutine help_dirs

  subroutine help_prevd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'prevd: prevd'
    write(u, '(a)') '    Navigate to the previous directory in the directory stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 if the stack is empty.'
  end subroutine help_prevd

  subroutine help_nextd(u)
    integer, intent(in) :: u
    write(u, '(a)') 'nextd: nextd'
    write(u, '(a)') '    Navigate to the next directory in the directory stack.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 if the stack is empty.'
  end subroutine help_nextd

  subroutine help_dirh(u)
    integer, intent(in) :: u
    write(u, '(a)') 'dirh: dirh'
    write(u, '(a)') '    Display the directory history.'
    write(u, '(a)') ''
    write(u, '(a)') '    Shows a numbered list of recently visited directories.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0.'
  end subroutine help_dirh

end module builtin_help_texts
