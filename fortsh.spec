Name:           fortsh
Version:        1.0.0
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
shell features including job control, pattern matching, performance monitoring,
and comprehensive scripting support.

Features:
- Advanced I/O redirection (pipes, here-strings, process substitution)
- Full scripting support (loops, functions, local variables)  
- Job control enhancements (suspend/resume, background process management)
- Pattern matching and globbing (*,?,[])
- Performance monitoring and memory management
- Tab completion, command history, aliases, and variables
- Compatible with bash/zsh scripts and workflows
- Built-in performance profiling and memory optimization

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
* Sun Aug 25 2024 mfw <espadon@outlook.com> - 1.0.0-1
- Initial RPM release
- Complete Fortran shell implementation
- Advanced I/O redirection and job control
- Performance monitoring and memory management
- Pattern matching and globbing support
- Full scripting capabilities with control flow
- Comprehensive test suite and error handling