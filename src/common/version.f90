! ==============================================================================
! Version Module for Fortran Shell
! ==============================================================================
! Update FORTSH_VERSION on each release
module version
  implicit none
  private
  public :: FORTSH_VERSION, print_version, print_help

  character(len=*), parameter :: FORTSH_VERSION = "1.5.0"

contains

  subroutine print_version()
    use iso_fortran_env, only: output_unit
    write(output_unit, '(a)') 'fortsh ' // FORTSH_VERSION
  end subroutine print_version

  subroutine print_help()
    use iso_fortran_env, only: output_unit
    write(output_unit, '(a)') 'fortsh - Fortran Shell ' // FORTSH_VERSION
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Usage: fortsh [OPTIONS] [SCRIPT [ARGS...]]'
    write(output_unit, '(a)') '       fortsh [OPTIONS] -c COMMAND [ARGS...]'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Options:'
    write(output_unit, '(a)') '  -c COMMAND    Execute COMMAND and exit'
    write(output_unit, '(a)') '  -l, --login   Start as a login shell'
    write(output_unit, '(a)') '  -n            Check syntax only, do not execute'
    write(output_unit, '(a)') '  -v, --version Print version information and exit'
    write(output_unit, '(a)') '  -h, --help    Print this help message and exit'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'If SCRIPT is provided, fortsh executes it. Otherwise, fortsh runs'
    write(output_unit, '(a)') 'interactively, reading commands from standard input.'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'fortsh is a POSIX-compliant shell written in Fortran 2018 with'
    write(output_unit, '(a)') 'bash compatibility features including:'
    write(output_unit, '(a)') '  - Syntax highlighting and autosuggestions'
    write(output_unit, '(a)') '  - Tab completion for commands, files, and variables'
    write(output_unit, '(a)') '  - History search with Ctrl-R'
    write(output_unit, '(a)') '  - Vi and Emacs editing modes'
    write(output_unit, '(a)') '  - Job control (fg, bg, jobs)'
    write(output_unit, '(a)') '  - Shell functions and aliases'
    write(output_unit, '(a)') '  - Pipes, process substitution, and coprocesses'
    write(output_unit, '(a)') '  - Brace, parameter, and arithmetic expansion'
    write(output_unit, '(a)') '  - fzf integration (Ctrl+F files, Ctrl+R history, Alt+j dirs)'
    write(output_unit, '(a)') ''
    write(output_unit, '(a)') 'Report bugs at: https://github.com/FortranGoingOnForty/fortsh/issues'
  end subroutine print_help

end module version
