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
    ! Variables & Environment
    case ('export')
      call help_export(u)
    case ('unset')
      call help_unset(u)
    case ('readonly')
      call help_readonly(u)
    case ('declare', 'typeset')
      call help_declare(u)
    case ('local')
      call help_local(u)
    case ('printenv')
      call help_printenv(u)
    case ('set')
      call help_set(u)
    case ('shopt')
      call help_shopt(u)
    ! I/O & Formatting
    case ('echo')
      call help_echo(u)
    case ('printf')
      call help_printf(u)
    case ('read')
      call help_read(u)
    ! Job Control
    case ('jobs')
      call help_jobs(u)
    case ('fg')
      call help_fg(u)
    case ('bg')
      call help_bg(u)
    case ('kill')
      call help_kill(u)
    case ('wait')
      call help_wait(u)
    case ('coproc')
      call help_coproc(u)
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

  ! --------------------------------------------------------------------------
  ! Variables & Environment
  ! --------------------------------------------------------------------------

  subroutine help_export(u)
    integer, intent(in) :: u
    write(u, '(a)') 'export: export [-fn] [name[=value] ...]'
    write(u, '(a)') '    Set export attribute for shell variables.'
    write(u, '(a)') ''
    write(u, '(a)') '    Marks each NAME for automatic export to the environment of'
    write(u, '(a)') '    subsequently executed commands. If VALUE is supplied, assign'
    write(u, '(a)') '    VALUE before exporting.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -f    Refer to shell functions'
    write(u, '(a)') '      -n    Remove the export property from each NAME'
    write(u, '(a)') '      -p    Display all exported variables and functions'
    write(u, '(a)') ''
    write(u, '(a)') '    With no arguments, displays all exported variables.'
    write(u, '(a)') '    Handles PS1 and PS2 by storing in dedicated shell fields.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option is given or NAME is invalid.'
  end subroutine help_export

  subroutine help_unset(u)
    integer, intent(in) :: u
    write(u, '(a)') 'unset: unset [-fv] [name ...]'
    write(u, '(a)') '    Unset values and attributes of shell variables and functions.'
    write(u, '(a)') ''
    write(u, '(a)') '    For each NAME, remove the corresponding variable or function.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -f    Treat each NAME as a shell function'
    write(u, '(a)') '      -v    Treat each NAME as a shell variable (default)'
    write(u, '(a)') ''
    write(u, '(a)') '    Read-only variables cannot be unset.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless a NAME is read-only.'
  end subroutine help_unset

  subroutine help_readonly(u)
    integer, intent(in) :: u
    write(u, '(a)') 'readonly: readonly [-p] [name[=value] ...]'
    write(u, '(a)') '    Mark shell variables as unchangeable.'
    write(u, '(a)') ''
    write(u, '(a)') '    Mark each NAME as read-only; the values of these NAMEs may'
    write(u, '(a)') '    not be changed by subsequent assignment. If VALUE is supplied,'
    write(u, '(a)') '    assign VALUE before marking as read-only.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -p    Display all read-only variables'
    write(u, '(a)') ''
    write(u, '(a)') '    With no arguments, displays all read-only variables.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option or invalid name is given.'
  end subroutine help_readonly

  subroutine help_declare(u)
    integer, intent(in) :: u
    write(u, '(a)') 'declare: declare [-aAilnrux] [name[=value] ...]'
    write(u, '(a)') '    Set variable values and attributes.'
    write(u, '(a)') ''
    write(u, '(a)') '    Declare variables and give them attributes. If no NAMEs are given,'
    write(u, '(a)') '    display the values of variables instead.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -a    Make NAMEs indexed arrays'
    write(u, '(a)') '      -A    Make NAMEs associative arrays'
    write(u, '(a)') '      -i    Make NAMEs have the integer attribute'
    write(u, '(a)') '      -l    Convert NAMEs to lower case on assignment'
    write(u, '(a)') '      -n    Make NAMEs a reference to the variable named by value'
    write(u, '(a)') '      -r    Make NAMEs read-only'
    write(u, '(a)') '      -u    Convert NAMEs to upper case on assignment'
    write(u, '(a)') '      -x    Mark NAMEs for export'
    write(u, '(a)') '      -p    Display attributes and values of each NAME'
    write(u, '(a)') ''
    write(u, '(a)') '    Using + instead of - turns off the given attribute.'
    write(u, '(a)') '    When used in a function, declare makes NAMEs local, as with local.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option or assignment error occurs.'
  end subroutine help_declare

  subroutine help_local(u)
    integer, intent(in) :: u
    write(u, '(a)') 'local: local [name[=value] ...]'
    write(u, '(a)') '    Define local variables.'
    write(u, '(a)') ''
    write(u, '(a)') '    Create a local variable called NAME with value VALUE. local'
    write(u, '(a)') '    can only be used within a function; it makes the variable NAME'
    write(u, '(a)') '    have a visible scope restricted to that function and its children.'
    write(u, '(a)') ''
    write(u, '(a)') '    Variables are pushed onto a local stack and restored when the'
    write(u, '(a)') '    function returns.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless local is used outside a function or an invalid'
    write(u, '(a)') '    name is given.'
  end subroutine help_local

  subroutine help_printenv(u)
    integer, intent(in) :: u
    write(u, '(a)') 'printenv: printenv [name ...]'
    write(u, '(a)') '    Print environment variables.'
    write(u, '(a)') ''
    write(u, '(a)') '    With no arguments, prints all environment variables in NAME=VALUE'
    write(u, '(a)') '    format. With arguments, prints the value of each specified variable.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 if all specified variables exist, 1 if any are missing.'
  end subroutine help_printenv

  subroutine help_set(u)
    integer, intent(in) :: u
    write(u, '(a)') 'set: set [-abefhkmnptuvxBCHP] [-o option-name] [--] [arg ...]'
    write(u, '(a)') '    Set or unset values of shell options and positional parameters.'
    write(u, '(a)') ''
    write(u, '(a)') '    Change the value of shell attributes and positional parameters,'
    write(u, '(a)') '    or display the names and values of shell variables.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -a    Mark variables for export (allexport)'
    write(u, '(a)') '      -e    Exit on first error (errexit)'
    write(u, '(a)') '      -f    Disable filename generation (noglob)'
    write(u, '(a)') '      -m    Enable job control (monitor)'
    write(u, '(a)') '      -n    Read commands but do not execute (noexec)'
    write(u, '(a)') '      -u    Treat unset variables as error (nounset)'
    write(u, '(a)') '      -v    Print shell input lines as read (verbose)'
    write(u, '(a)') '      -x    Print commands and arguments (xtrace)'
    write(u, '(a)') '      -C    Disallow output redirection to existing files (noclobber)'
    write(u, '(a)') ''
    write(u, '(a)') '    Using + rather than - causes flags to be turned off.'
    write(u, '(a)') '    Flags can be combined: set -eu is valid.'
    write(u, '(a)') ''
    write(u, '(a)') '    Use -o to set options by name:'
    write(u, '(a)') '      set -o vi           Enable vi editing mode'
    write(u, '(a)') '      set -o emacs         Enable emacs editing mode'
    write(u, '(a)') '      set -o pipefail      Pipe returns rightmost non-zero status'
    write(u, '(a)') '      set -o               List all options'
    write(u, '(a)') ''
    write(u, '(a)') '    With no options, displays all shell variables.'
    write(u, '(a)') '    Using -- signals end of options; remaining args become $1, $2, ...'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless an invalid option is given.'
  end subroutine help_set

  subroutine help_shopt(u)
    integer, intent(in) :: u
    write(u, '(a)') 'shopt: shopt [-su] [optname ...]'
    write(u, '(a)') '    Set and unset shell options.'
    write(u, '(a)') ''
    write(u, '(a)') '    Toggle values of settings controlling optional shell behavior.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -s    Enable (set) each OPTNAME'
    write(u, '(a)') '      -u    Disable (unset) each OPTNAME'
    write(u, '(a)') '      -p    Print all options with current status'
    write(u, '(a)') ''
    write(u, '(a)') '    Available options:'
    write(u, '(a)') '      dotglob        Include dot-files in pathname expansion'
    write(u, '(a)') '      expand_aliases  Expand aliases'
    write(u, '(a)') '      extglob        Enable extended pattern matching operators'
    write(u, '(a)') '      failglob       Error if a glob pattern has no matches'
    write(u, '(a)') '      globstar       ** matches all files and zero or more directories'
    write(u, '(a)') '      nocaseglob     Case-insensitive pathname expansion'
    write(u, '(a)') '      nocasematch    Case-insensitive pattern matching in [[ ]] and case'
    write(u, '(a)') '      nullglob       Expand unmatched globs to empty string'
    write(u, '(a)') ''
    write(u, '(a)') '    With no options, displays all options with their current status.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0, or 1 if an invalid option name is given.'
  end subroutine help_shopt

  ! --------------------------------------------------------------------------
  ! I/O & Formatting
  ! --------------------------------------------------------------------------

  subroutine help_echo(u)
    integer, intent(in) :: u
    write(u, '(a)') 'echo: echo [-neE] [arg ...]'
    write(u, '(a)') '    Write arguments to standard output.'
    write(u, '(a)') ''
    write(u, '(a)') '    Display the ARGs, separated by spaces, followed by a newline.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -n    Do not append a trailing newline'
    write(u, '(a)') '      -e    Enable interpretation of backslash escapes'
    write(u, '(a)') '      -E    Disable interpretation of backslash escapes (default)'
    write(u, '(a)') ''
    write(u, '(a)') '    Escape sequences (with -e):'
    write(u, '(a)') '      \\    backslash           \a    alert (bell)'
    write(u, '(a)') '      \b    backspace           \c    stop output (no trailing newline)'
    write(u, '(a)') '      \f    form feed           \n    newline'
    write(u, '(a)') '      \r    carriage return     \t    horizontal tab'
    write(u, '(a)') '      \v    vertical tab        \0nnn octal value'
    write(u, '(a)') '      \xHH  hexadecimal value'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless a write error occurs.'
  end subroutine help_echo

  subroutine help_printf(u)
    integer, intent(in) :: u
    write(u, '(a)') 'printf: printf FORMAT [ARGUMENTS...]'
    write(u, '(a)') '    Formats and prints ARGUMENTS under control of the FORMAT.'
    write(u, '(a)') ''
    write(u, '(a)') '    FORMAT is a string containing three types of objects: plain'
    write(u, '(a)') '    characters (copied to stdout), escape sequences (converted and'
    write(u, '(a)') '    copied), and format specifications, each causing printing of'
    write(u, '(a)') '    the next successive ARGUMENT.'
    write(u, '(a)') ''
    write(u, '(a)') '    Format specifiers:'
    write(u, '(a)') '      %s    string              %c    single character'
    write(u, '(a)') '      %d    decimal integer      %i    integer (same as %d)'
    write(u, '(a)') '      %o    octal               %x    hexadecimal (lowercase)'
    write(u, '(a)') '      %X    hexadecimal (upper)  %u    unsigned decimal'
    write(u, '(a)') '      %f    floating point       %e    scientific notation'
    write(u, '(a)') '      %g    auto float/sci       %b    string with backslash escapes'
    write(u, '(a)') '      %q    shell-quoted string  %%    literal percent sign'
    write(u, '(a)') ''
    write(u, '(a)') '    Modifier flags: -, 0, +, space, #'
    write(u, '(a)') '    Width and precision: %10s, %.5f, %*d (from argument)'
    write(u, '(a)') ''
    write(u, '(a)') '    Integer arguments accept 0x (hex), 0 (octal), and ''A (character).'
    write(u, '(a)') '    FORMAT is reused as necessary to consume all ARGUMENTS.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 on format/numeric error, 2 on usage error.'
  end subroutine help_printf

  subroutine help_read(u)
    integer, intent(in) :: u
    write(u, '(a)') 'read: read [-rs] [-a array] [-d delim] [-n nchars] [-p prompt] ' // &
                     '[-t timeout] [name ...]'
    write(u, '(a)') '    Read a line from standard input.'
    write(u, '(a)') ''
    write(u, '(a)') '    Reads a single line from standard input. The line is split into'
    write(u, '(a)') '    fields using IFS, and each field is assigned to the corresponding'
    write(u, '(a)') '    NAME. Leftover fields go to the last NAME.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -a array   Assign words to sequential indices of ARRAY'
    write(u, '(a)') '      -d delim   Use DELIM to terminate the line instead of newline'
    write(u, '(a)') '      -n nchars  Return after reading NCHARS characters'
    write(u, '(a)') '      -p prompt  Output PROMPT without trailing newline before reading'
    write(u, '(a)') '      -r         Do not allow backslash escapes or line continuation'
    write(u, '(a)') '      -s         Silent mode (do not echo input)'
    write(u, '(a)') '      -t timeout Time out and return failure after TIMEOUT seconds'
    write(u, '(a)') ''
    write(u, '(a)') '    If no NAMEs are supplied, the line is stored in the REPLY variable.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless EOF is encountered with no input or an error occurs.'
  end subroutine help_read

  ! --------------------------------------------------------------------------
  ! Job Control
  ! --------------------------------------------------------------------------

  subroutine help_jobs(u)
    integer, intent(in) :: u
    write(u, '(a)') 'jobs: jobs [-l]'
    write(u, '(a)') '    Display status of jobs.'
    write(u, '(a)') ''
    write(u, '(a)') '    Lists the active jobs. The -l option provides more information.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -l    List process IDs in addition to the normal information'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0.'
  end subroutine help_jobs

  subroutine help_fg(u)
    integer, intent(in) :: u
    write(u, '(a)') 'fg: fg [job_spec]'
    write(u, '(a)') '    Move job to the foreground.'
    write(u, '(a)') ''
    write(u, '(a)') '    Place the job identified by JOB_SPEC in the foreground, making it'
    write(u, '(a)') '    the current job. If JOB_SPEC is not present, the most recent'
    write(u, '(a)') '    background job is used.'
    write(u, '(a)') ''
    write(u, '(a)') '    JOB_SPEC can be:'
    write(u, '(a)') '      %N    Job number N'
    write(u, '(a)') '      %str  Job whose command begins with str'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns the status of the command placed in foreground, or 1 if'
    write(u, '(a)') '    an error occurs.'
  end subroutine help_fg

  subroutine help_bg(u)
    integer, intent(in) :: u
    write(u, '(a)') 'bg: bg [job_spec]'
    write(u, '(a)') '    Move job to the background.'
    write(u, '(a)') ''
    write(u, '(a)') '    Place the job identified by JOB_SPEC in the background, as if it'
    write(u, '(a)') '    had been started with &. If JOB_SPEC is not present, the most'
    write(u, '(a)') '    recently suspended job is used.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 unless job control is not enabled or an error occurs.'
  end subroutine help_bg

  subroutine help_kill(u)
    integer, intent(in) :: u
    write(u, '(a)') 'kill: kill [-s sigspec | -signum] pid | jobspec ...'
    write(u, '(a)') '    Send a signal to a job.'
    write(u, '(a)') ''
    write(u, '(a)') '    Send the processes identified by PID or JOBSPEC the signal named'
    write(u, '(a)') '    by SIGSPEC or SIGNUM. If neither SIGSPEC nor SIGNUM is present,'
    write(u, '(a)') '    SIGTERM is assumed.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -s sig  SIG is a signal name (e.g., TERM, KILL, HUP)'
    write(u, '(a)') '      -l      List signal names'
    write(u, '(a)') '      -NUM    Send signal number NUM'
    write(u, '(a)') ''
    write(u, '(a)') '    Supported signals: HUP (1), INT (2), QUIT (3), KILL (9),'
    write(u, '(a)') '    TERM (15), STOP (17/19), CONT (18/19), USR1 (10), USR2 (12).'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 if at least one signal was sent, 1 on error.'
  end subroutine help_kill

  subroutine help_wait(u)
    integer, intent(in) :: u
    write(u, '(a)') 'wait: wait [-n] [id ...]'
    write(u, '(a)') '    Wait for job completion and return exit status.'
    write(u, '(a)') ''
    write(u, '(a)') '    Wait for each process identified by an ID, which may be a process'
    write(u, '(a)') '    ID or a job specification, and report its termination status.'
    write(u, '(a)') ''
    write(u, '(a)') '    Options:'
    write(u, '(a)') '      -n    Wait for any single job to complete and return its status'
    write(u, '(a)') ''
    write(u, '(a)') '    If ID is not given, waits for all currently active child processes.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns the status of the last ID, or 0 if no ID is given, or'
    write(u, '(a)') '    127 if ID is not a known process.'
  end subroutine help_wait

  subroutine help_coproc(u)
    integer, intent(in) :: u
    write(u, '(a)') 'coproc: coproc [NAME] command [args]'
    write(u, '(a)') '    Create a coprocess named NAME.'
    write(u, '(a)') ''
    write(u, '(a)') '    Execute COMMAND asynchronously with its standard output and input'
    write(u, '(a)') '    connected to the shell via a two-way pipe.'
    write(u, '(a)') ''
    write(u, '(a)') '    The NAME defaults to COPROC. NAME[0] holds the read fd and'
    write(u, '(a)') '    NAME[1] holds the write fd. NAME_PID holds the PID.'
    write(u, '(a)') ''
    write(u, '(a)') '    Exit Status:'
    write(u, '(a)') '    Returns 0 on success, 1 if creation fails.'
  end subroutine help_coproc

end module builtin_help_texts
