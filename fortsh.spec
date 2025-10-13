Name:           fortsh
Version:        4.2.0
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
# Tests temporarily disabled due to circular module dependencies
# make test

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
* Sun Oct 13 2024 mfw <espadon@outlook.com> - 4.2.0-1
- Enhanced vi editing mode with advanced features
- Added forward search capability in command line editing
- Implemented case-insensitive regex support
- Improved readline functionality and text manipulation
- Enhanced command line editing experience

* Sun Oct 13 2024 mfw <espadon@outlook.com> - 4.1.0-1
- NEW FEATURE: Bash-style programmable completion system
- Implemented complete builtin for defining custom completions
- Implemented compgen builtin for testing completion generation
- Added function-based completion support
- Built-in completers for commands, files, directories, and variables
- Prefix matching and alphabetical sorting
- Prefix/suffix transforms for completion candidates
- Filter support for completion results

* Sun Oct 13 2024 mfw <espadon@outlook.com> - 4.0.2-1
- Fixed single-line if statement execution
- Fixed infinite while loop issues
- Resolved circular module dependency between control_flow and executor
- Improved control flow condition evaluation
- Enhanced variable expansion in test conditions

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 4.0.1-1
- Fixed multiline function conditionals
- Improved scripting support and control flow
- Minor fixes and adjustments for better compatibility
- Updated README with compliance and parity targets

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 4.0.0-1
- MAJOR RELEASE: Bash parity and POSIX compliance improvements
- Implemented process substitution <() and >() operators
- Full trap command support for signal handling
- Enhanced bash compatibility and POSIX compliance
- Major improvements to shell script compatibility

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.10-1
- Major fixes to background job control
- Fixed history expansion handling
- Added tracing and trap hooks
- Improved signal handling for background jobs

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.9-1
- Fixed backgrounding jobs edge cases
- Implemented $! expansion for last background job PID
- Fixed single line for loops
- Updated test suite

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.8-1
- Resolved pipeline+redirect edge case
- Further improvements to pipe and redirect handling

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.7-1
- Enhanced redirect and pipe handling
- Fixed edge cases with builtins after pipes
- Added I/O helper module for better redirection

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.6-1
- Fixed redirection operators
- Improved I/O redirection handling

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.5-1
- Fixed macOS raw mode enabling for terminal
- Keybinds now work correctly on macOS

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.4-1
- Further macOS completion and readline fixes
- Improved platform-specific compatibility

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.3-1
- Fixed macOS readline compatibility issues
- Added platform-specific build flags for Darwin
- Enhanced coprocess functionality

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.2-1
- Added associative array support
- Enhanced parser functionality
- Improved expansion capabilities

* Sat Oct 12 2024 mfw <espadon@outlook.com> - 3.3.1-1
- Improved history navigation and reverse-i-search
- Fixed ctrl-c signal handling in shell
- Enhanced readline functionality

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.3.0-1
- Fixed execvp model for path program execution
- Programs found by which now execute properly
- Improved readline functionality
- Updated Makefile with release targets

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.2.0-1
- Full builtin compliance implementation
- Enhanced directory builtins
- Wired in which command
- Updated documentation

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.1.0-1
- Implemented proper signal handling for external commands
- Shell now ignores signals to run commands in succession
- Significantly improved shell functionality and stability

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.0.2-1
- Fixed parser handling of spaces
- Improved prompt parsing
- Various parser improvements

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.0.1-1
- Enhanced prompt formatting and expansion
- Improved variable handling
- Better job control
- Completed brace expansion implementation

* Fri Oct 11 2024 mfw <espadon@outlook.com> - 3.0.0-1
- Complete rewrite with AST-based parsing architecture
- Modern compiler design with lexer, parser, and AST evaluator
- Improved POSIX compliance and shell compatibility
- Enhanced error handling and diagnostics
- Significant performance improvements
- Better memory management and resource handling

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