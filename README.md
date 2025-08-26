# Fortsh - Fortran Shell

A modern Unix shell implementation written in Fortran 2018 that demonstrates Fortran's capability for system programming.

## Features

### 🔧 Advanced I/O Redirection
- Pipes and pipeline processing
- Here-strings (`<<<`) and here-documents (`<<`)
- Process substitution and combined redirections
- File redirection with append and truncate modes

### 📜 Full Scripting Support
- For-in loops, while loops, and control flow
- Functions with local variables
- Variable expansion and environment management
- Conditional execution (if/then/else/fi)

### ⚙️ Job Control
- Background job execution (`&`)
- Suspend/resume functionality
- Process group management
- Built-in commands: `jobs`, `fg`, `bg`, `kill`, `wait`

### 🔍 Pattern Matching & Globbing
- Wildcard patterns: `*`, `?`, `[abc]`, `[a-z]`
- Recursive pattern matching algorithm
- Sorted glob expansion results
- Directory-aware pattern matching

### 📊 Performance Monitoring
- Real-time execution timing
- Memory allocation tracking
- Built-in performance commands (`perf`, `memory`)
- Memory pool optimization
- Runtime statistics and profiling

### 🛡️ Error Handling
- Comprehensive test suite
- Robust error categorization
- Memory leak prevention
- Signal handling and cleanup

## Quick Start

### Installation

#### From Repository (Recommended)
```bash
# Add repository
sudo wget -O /etc/yum.repos.d/fortsh.repo https://repos.musicsian.com/fortsh.repo

# Install fortsh  
sudo dnf install fortsh
```

#### Build from Source
```bash
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
make all
make dev-install
```

### Usage Examples

```bash
# Start the shell
fortsh

# Enable performance monitoring
export FORTSH_PERF=1
fortsh

# Basic scripting
for file in *.txt; do
    echo "Processing: $file"
done

# Job control
command &    # Background execution
jobs         # List active jobs
fg %1        # Bring job to foreground

# Pattern matching
echo *.{txt,log}    # Multiple extensions
echo test-[0-9]*    # Character ranges
```

### Performance Features

```bash
# Runtime performance monitoring
perf on              # Enable monitoring
perf                 # Show statistics
memory               # Memory usage info

# Example output:
# ====================================
# FORTSH PERFORMANCE STATISTICS  
# ====================================
# Uptime:           .002 seconds
# Total commands:   9
# Avg parse time:   .009 ms
# Avg exec time:    .115 ms
# Current memory:   4608 bytes
# Peak memory:      14592 bytes
```

## Architecture

Fortsh is built with a modular architecture:

- **Common**: Core types, error handling, performance monitoring
- **System**: OS interface layer, signal handling  
- **Parsing**: Command parsing, glob expansion
- **Execution**: Command execution, job control, built-ins
- **Scripting**: Variables, control flow, configuration
- **I/O**: Readline interface and input handling

## Requirements

- **Operating System**: Linux (RHEL 9, CentOS Stream 9, Rocky Linux 9, AlmaLinux 9, Fedora)
- **Architecture**: x86_64
- **Build Dependencies**: gfortran >= 11.0, make, gcc
- **Runtime Dependencies**: glibc

## Development

### Building
```bash
make all        # Build the shell
make test       # Run integration tests
make check      # Run comprehensive checks
make smoke-test # Basic functionality tests
```

### Packaging
```bash
make dist       # Create distribution tarball
make rpm        # Build RPM packages
```

### Installation
```bash
make install       # System-wide installation (/usr/local/bin)
make dev-install   # User installation (~/.local/bin)
make uninstall     # Remove installation
```

## Performance

Fortsh includes comprehensive performance monitoring:

- **Parsing**: ~0.009ms average per command
- **Execution**: ~0.115ms average per command  
- **Memory**: Automatic optimization with pools
- **Profiling**: Built-in timing and allocation tracking

## Testing

Comprehensive test suite with:
- Integration tests for all major features
- Memory leak detection
- Performance regression testing
- Error condition handling

```bash
./tests/integration_test.sh    # Full test suite
make smoke-test                # Quick verification
```

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## Support

- **Issues**: https://github.com/FortranGoingOnForty/fortsh/issues
- **Documentation**: https://repos.musicsian.com/fortsh.html
- **Repository**: https://repos.musicsian.com/

---

*Fortsh demonstrates that Fortran is not just for scientific computing - it's capable of modern system programming and can compete with traditional system languages for shell implementation.*