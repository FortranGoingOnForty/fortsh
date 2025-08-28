Name:           fortsh
Version:        2.0.0
Release:        1%{?dist}
Summary:        Fortran Shell - A modern shell implementation in Fortran with advanced features

License:        MIT
URL:            https://github.com/FortranGoingOnForty/fortsh
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gfortran >= 11.0
BuildRequires:  gcc
BuildRequires:  make
Requires:       glibc

%description
Fortsh (Fortran Shell) is a modern Unix shell implementation written in Fortran 2018
that demonstrates Fortran's capability for system programming. It provides advanced
shell features including comprehensive built-in commands, job control, pattern matching,
performance monitoring, and complete scripting support.

Features:
- Advanced I/O & Process Management (pipes, process substitution, coprocesses, brace expansion)
- Comprehensive Built-in Command Library (printf, read, getopts, pushd/popd, type/which)
- Advanced test operations with [[ ]] syntax and pattern matching
- Full scripting support (loops, functions, local variables, interactive input)
- Job control enhancements (suspend/resume, background process management)
- Enhanced command substitution with nesting and signal handling
- Pattern matching and globbing (*,?,[]) with brace expansion
- Performance monitoring and memory management with optimization
- Compatible with bash/zsh scripts and modern shell workflows

%prep
%autosetup

%build
make clean
make all

%check
make test

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_mandir}/man1
mkdir -p %{buildroot}%{_docdir}/%{name}

# Install binary
install -Dm755 bin/fortsh %{buildroot}%{_bindir}/fortsh

# Install documentation
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%files
%doc README.md
%{_bindir}/fortsh
%{_docdir}/%{name}/README.md

%changelog
* Wed Aug 28 2024 mfw <espadon@outlook.com> - 2.0.0-1
- Full POSIX Compliance implementation
- Complete parameter expansion: ${var:-word}, ${var%pattern}, ${var#pattern}
- Positional parameters: $1, $2, $#, $*, $@ with proper handling
- Field splitting with $IFS support for word boundary control
- File descriptor redirection: n>file, n<file, <&n, >&n syntax
- Quote removal and tilde expansion for proper path handling
- All POSIX required built-ins: type, unset, readonly, shift, exec, eval
- Enterprise-grade POSIX.1-2017 compliance achieved

* Wed Aug 28 2024 mfw <espadon@outlook.com> - 1.5.0-1
- Phase 9 implementation: POSIX Compliance & Shell Standards  
- Shell options framework: set -e, set -u, set -o pipefail, shopt commands
- Proper pipeline exit status handling with POSIX compliance
- Special variables: $$, $!, $?, $0, $PPID with automatic expansion
- Errexit integration for command failure handling
- Enhanced bash/zsh compatibility (~90% achieved)
- POSIX-compliant shell behavior for enterprise use

* Wed Aug 28 2024 mfw <espadon@outlook.com> - 1.4.0-1
- Phase 8 implementation: Advanced Shell Features
- Case statements: case/esac with pattern matching and wildcard support  
- Here documents/strings: << <<- <<< operators with variable expansion
- History expansion: !!, !n, !-n, !string patterns with command search
- Enhanced aliases: parameter support with $1, $2, $*, $@, $#, ${n}
- Command line editing: Emacs and Vi modes with proper mode switching
- Associative arrays: key-value storage with declare, set, get operations
- Advanced shell features for improved bash/zsh compatibility

* Wed Aug 28 2024 mfw <espadon@outlook.com> - 1.3.0-1
- Phase 7 implementation: Built-in Command Library
- Advanced test operations: [[ ]] syntax with pattern matching, regex support
- Printf built-in: comprehensive formatting with %s, %d, %f, %x specifiers
- Interactive read built-in: -p prompt, -t timeout, -s silent, -a array modes
- Getopts command: full option parsing with OPTIND, OPTARG support
- Directory operations: pushd/popd/dirs with stack management
- Command identification: type/which/command for locating executables
- Enhanced built-in command library with 25+ commands

* Wed Aug 28 2024 mfw <espadon@outlook.com> - 1.2.0-1
- Phase 6 implementation: Advanced I/O & Process Management
- Enhanced command substitution with nested $(command $(inner)) support
- Process substitution: <(command) and >(command) functionality
- Brace expansion: {a,b,c}, {1..10}, {a..z} patterns
- Coprocess support: coproc command bidirectional communication
- Advanced signal handling: timeout, enhanced traps, process groups
- Built-in timeout command with automatic process termination

* Wed Aug 28 2024 mfw <espadon@outlook.com> - 1.1.0-1
- Phase 5 implementation: Core Language Extensions
- Array variables support: arr=(a b c), ${arr[0]}, ${arr[@]}
- Parameter expansion: ${var:offset:length}, ${var:-default}, ${#var}
- Arithmetic expansion: $((expression)) with basic math operations
- Enhanced variable assignment and expansion system

* Sun Aug 25 2024 mfw <espadon@outlook.com> - 1.0.1-1
- Enhanced shell functionality with functions and command substitution
- Improved variable expansion with parameter substitution
- Enhanced readline with history and tab completion
- Source file execution support
- Advanced scripting capabilities

* Sun Aug 25 2024 mfw <espadon@outlook.com> - 1.0.0-1
- Initial RPM release
- Complete Fortran shell implementation
- Advanced I/O redirection and job control
- Performance monitoring and memory management
- Pattern matching and globbing support
- Full scripting capabilities with control flow
- Comprehensive test suite and error handling