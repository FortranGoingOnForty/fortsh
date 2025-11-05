# Fortran Shell (Fortsh) Makefile
# ====================================

# Compiler settings
# Use LLVM Flang on macOS ARM64 for better stability
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),arm64)
        # macOS ARM64: Use LLVM Flang with no optimization to avoid crashes
        FC = flang-new
        PLATFORM_FLAGS = -D__APPLE__ -cpp
        $(info Using LLVM Flang (flang-new) for macOS ARM64)
    else
        # macOS Intel: Use gfortran with fixes
        FC = gfortran
        PLATFORM_FLAGS = -D__APPLE__ -cpp -frecursive
        $(info Using gfortran on macOS Intel)
    endif
else
    # Linux: Use gfortran
    FC = gfortran
    PLATFORM_FLAGS = -cpp
    $(info Using gfortran on Linux)
endif

# Memory pooling (enabled by default, set NO_MEMPOOL=1 to disable)
ifeq ($(NO_MEMPOOL),1)
    POOL_FLAGS =
    $(info Memory pooling DISABLED - using standard allocation)
else
    POOL_FLAGS = -DUSE_MEMORY_POOL
    $(info Memory pooling ENABLED - using zero-copy string pool [DEFAULT])
endif

# C compiler for string operations library
CC = gcc
CFLAGS = -Wall -Wextra -fPIC -g -O2 $(PLATFORM_FLAGS)

# Development flags (verbose warnings, debug symbols)
FCFLAGS = -Wall -Wextra -std=f2018 -fPIC -g -O0 $(PLATFORM_FLAGS) $(POOL_FLAGS)
# Production flags (minimal warnings, optimized, no debug symbols)
FCFLAGS_RELEASE = -Wall -Wno-unused-variable -Wno-unused-dummy-argument -Wno-maybe-uninitialized -Wno-function-elimination -Wno-surprising -Wno-character-truncation -std=f2018 -fPIC -O2 $(PLATFORM_FLAGS) $(POOL_FLAGS)

# C string library (for flang-new workaround)
# Automatically enable on macOS ARM64 unless explicitly disabled
ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    ifeq ($(NO_C_STRINGS),1)
      USE_C_STRINGS = 0
    else
      USE_C_STRINGS = 1
    endif
  endif
endif

ifeq ($(USE_C_STRINGS),1)
  C_STRING_LIB = $(BUILDDIR)/c_interop/libfortsh_strings.a
  C_STRING_OBJ = $(BUILDDIR)/c_interop/fortsh_c_strings.o
  C_STRING_FLAGS = -DUSE_C_STRINGS
  LDFLAGS = $(C_STRING_LIB)
  FCFLAGS += $(C_STRING_FLAGS)
  FCFLAGS_RELEASE += $(C_STRING_FLAGS)
  $(info C string library ENABLED - workaround for flang-new >128 byte bug)
else
  C_STRING_LIB =
  C_STRING_OBJ =
  C_STRING_FLAGS =
  LDFLAGS =
  $(info C string library DISABLED - using native Fortran strings)
endif 

# Directory structure
SRCDIR = src
BUILDDIR = build
BINDIR = bin

# Conditionally add string pool and memory dashboard (included by default)
ifeq ($(NO_MEMPOOL),1)
    POOL_OBJECTS =
else
    POOL_OBJECTS = $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o
endif

# Object files in dependency order
OBJECTS = $(BUILDDIR)/common/types.o \
          $(BUILDDIR)/common/error_handling.o \
          $(BUILDDIR)/common/performance.o \
          $(POOL_OBJECTS) \
          $(BUILDDIR)/system/interface.o \
          $(BUILDDIR)/common/io_helpers.o \
          $(BUILDDIR)/system/signals.o \
          $(BUILDDIR)/system/signal_handling.o \
          $(BUILDDIR)/parsing/glob.o \
          $(BUILDDIR)/parsing/parser.o \
          $(BUILDDIR)/execution/jobs.o \
          $(BUILDDIR)/scripting/control_flow.o \
          $(BUILDDIR)/scripting/test_builtin.o \
          $(BUILDDIR)/scripting/advanced_test.o \
          $(BUILDDIR)/scripting/printf_builtin.o \
          $(BUILDDIR)/scripting/read_builtin.o \
          $(BUILDDIR)/scripting/getopts_builtin.o \
          $(BUILDDIR)/scripting/directory_builtin.o \
          $(BUILDDIR)/scripting/command_builtin.o \
          $(BUILDDIR)/scripting/variables.o \
          $(BUILDDIR)/scripting/prompt_formatting.o \
          $(BUILDDIR)/scripting/expansion.o \
          $(BUILDDIR)/scripting/substitution.o \
          $(BUILDDIR)/scripting/config.o \
          $(BUILDDIR)/scripting/aliases.o \
          $(BUILDDIR)/scripting/abbreviations.o \
          $(BUILDDIR)/io/syntax_highlight.o \
          $(BUILDDIR)/io/readline.o \
          $(BUILDDIR)/scripting/shell_options.o \
          $(BUILDDIR)/scripting/completion.o \
          $(BUILDDIR)/execution/coprocess.o \
          $(BUILDDIR)/execution/better_errors.o \
          $(BUILDDIR)/io/heredoc.o \
          $(BUILDDIR)/io/fd_redirection.o \
          $(BUILDDIR)/execution/builtins.o \
          $(BUILDDIR)/execution/executor.o \
          $(BUILDDIR)/fortsh.o

# Target executable
TARGET = $(BINDIR)/fortsh

# Default target
all: $(TARGET)

# Create directories
$(BUILDDIR) $(BINDIR):
	mkdir -p $@

$(BUILDDIR)/common $(BUILDDIR)/system $(BUILDDIR)/parsing $(BUILDDIR)/execution $(BUILDDIR)/scripting $(BUILDDIR)/io $(BUILDDIR)/c_interop: | $(BUILDDIR)
	mkdir -p $@

# Build target
$(TARGET): $(OBJECTS) $(C_STRING_LIB) | $(BINDIR)
	$(FC) $(OBJECTS) -o $@ $(LDFLAGS)
	@echo "Fortsh built successfully!"

# Individual compilation rules with proper dependencies
$(BUILDDIR)/common/types.o: src/common/types.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/error_handling.o: src/common/error_handling.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/performance.o: src/common/performance.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# String pool (included by default unless NO_MEMPOOL=1)
$(BUILDDIR)/common/string_pool.o: src/common/string_pool.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# Memory dashboard (included by default unless NO_MEMPOOL=1)
$(BUILDDIR)/common/memory_dashboard.o: src/common/memory_dashboard.f90 $(BUILDDIR)/common/string_pool.o | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/system/interface.o: src/system/interface.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/system
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/io_helpers.o: src/common/io_helpers.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/system/signals.o: src/system/signals.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/system
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/system/signal_handling.o: src/system/signal_handling.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/system
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/glob.o: src/parsing/glob.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/parser.o: src/parsing/parser.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/error_handling.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/substitution.o $(BUILDDIR)/parsing/glob.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/jobs.o: src/execution/jobs.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/control_flow.o: src/scripting/control_flow.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/advanced_test.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/test_builtin.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtins.o: src/execution/builtins.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/common/io_helpers.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/test_builtin.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/scripting/completion.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/coprocess.o $(BUILDDIR)/scripting/command_builtin.o $(BUILDDIR)/scripting/directory_builtin.o $(BUILDDIR)/scripting/getopts_builtin.o $(BUILDDIR)/scripting/printf_builtin.o $(BUILDDIR)/scripting/read_builtin.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/substitution.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/executor.o: src/execution/executor.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/error_handling.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/control_flow.o $(BUILDDIR)/execution/builtins.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/test_builtin.o: src/scripting/test_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/advanced_test.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/advanced_test.o: src/scripting/advanced_test.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/printf_builtin.o: src/scripting/printf_builtin.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/read_builtin.o: src/scripting/read_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/getopts_builtin.o: src/scripting/getopts_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/directory_builtin.o: src/scripting/directory_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/command_builtin.o: src/scripting/command_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/variables.o: src/scripting/variables.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/prompt_formatting.o: src/scripting/prompt_formatting.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/expansion.o: src/scripting/expansion.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/substitution.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/substitution.o: src/scripting/substitution.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/coprocess.o: src/execution/coprocess.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/better_errors.o: src/execution/better_errors.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/config.o: src/scripting/config.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/aliases.o: src/scripting/aliases.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/abbreviations.o: src/scripting/abbreviations.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/shell_options.o: src/scripting/shell_options.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/prompt_formatting.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/completion.o: src/scripting/completion.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/parsing/parser.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/syntax_highlight.o: src/io/syntax_highlight.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/readline.o: src/io/readline.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/completion.o $(BUILDDIR)/io/syntax_highlight.o $(BUILDDIR)/scripting/abbreviations.o $(BUILDDIR)/parsing/glob.o $(C_STRING_OBJ) | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/heredoc.o: src/io/heredoc.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/fd_redirection.o: src/io/fd_redirection.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/fortsh.o: src/fortsh.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signals.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/executor.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/scripting/prompt_formatting.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# ============================================================================
# C string library (flang-new workaround for macOS ARM64)
# ============================================================================

# Compile C string operations library
$(BUILDDIR)/c_interop/fortsh_strings.o: src/c_interop/fortsh_strings.c src/c_interop/fortsh_strings.h | $(BUILDDIR)/c_interop
	$(CC) $(CFLAGS) -c $< -o $@

# Create static library from C objects
$(BUILDDIR)/c_interop/libfortsh_strings.a: $(BUILDDIR)/c_interop/fortsh_strings.o
	ar rcs $@ $<

# Compile Fortran wrapper module (depends on C library for testing)
$(BUILDDIR)/c_interop/fortsh_c_strings.o: src/c_interop/fortsh_c_strings.f90 | $(BUILDDIR)/c_interop
	$(FC) $(FCFLAGS) $(C_STRING_FLAGS) -J$(BUILDDIR) -c $< -o $@

# Standalone test program for C string library
$(BUILDDIR)/test_c_strings: tests/test_c_strings.f90 $(BUILDDIR)/c_interop/fortsh_c_strings.o $(BUILDDIR)/c_interop/libfortsh_strings.a | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/c_interop/fortsh_c_strings.o $(BUILDDIR)/c_interop/libfortsh_strings.a -o $@

# ============================================================================

# Clean targets
clean:
	rm -rf $(BUILDDIR) $(BINDIR)
	@echo "Clean completed!"

distclean: clean
	rm -f *.mod

# Install target (optional)
install: $(TARGET)
	cp $(TARGET) /usr/local/bin/
	@echo "Fortsh installed to /usr/local/bin/"

# Development targets
test: $(TARGET)
	@echo "Running basic functionality test..."
	@echo "echo 'Hello from Fortsh!'" | $(TARGET)

debug: FCFLAGS += -g -fbacktrace -fcheck=bounds
debug: $(TARGET)

release: FCFLAGS = $(FCFLAGS_RELEASE)
release: clean $(TARGET)
	@echo "Building release version..."
	strip $(TARGET)
	@echo "Release build complete! Binary size: $$(du -h $(TARGET) | cut -f1)"

# Test suite targets
test-integration: $(TARGET)
	@echo "Running integration tests..."
	chmod +x tests/integration_test.sh
	./tests/integration_test.sh

test-parity: $(TARGET)
	@echo "Running bash parity tests..."
	chmod +x tests/bash_parity_test.sh
	FORTSH_BIN=$(TARGET) ./tests/bash_parity_test.sh

test-posix: $(TARGET)
	@echo "Running POSIX compliance tests..."
	chmod +x tests/posix_compliance_test.sh
	FORTSH_BIN=$(TARGET) ./tests/posix_compliance_test.sh

test-features: $(TARGET)
	@echo "Running feature test suite..."
	chmod +x tests/feature_test_suite.sh
	./tests/feature_test_suite.sh

test-all: test-integration test-parity test-posix
	@echo ""
	@echo "=========================================="
	@echo "ALL TEST SUITES COMPLETED"
	@echo "=========================================="
	@echo "✓ Integration tests"
	@echo "✓ Bash parity tests"
	@echo "✓ POSIX compliance tests"
	@echo "=========================================="

# Help target
help:
	@echo "Fortran Shell (Fortsh) Build System"
	@echo "==================================="
	@echo ""
	@echo "Build targets:"
	@echo "  all           - Build fortsh (default, with memory pooling)"
	@echo "  release       - Build optimized production binary"
	@echo "  debug         - Build with extra debug flags and checks"
	@echo "  clean         - Remove build artifacts"
	@echo "  distclean     - Remove all generated files"
	@echo ""
	@echo "Memory pooling options:"
	@echo "  make          - Build with memory pooling (DEFAULT)"
	@echo "  NO_MEMPOOL=1 make - Build without memory pooling"
	@echo ""
	@echo "C string library (flang-new workaround):"
	@echo "  c-strings     - Build C string library test"
	@echo "  test-c-strings - Test C string library (>128 byte strings)"
	@echo "  USE_C_STRINGS=1 make - Enable C strings in fortsh (experimental)"
	@echo ""
	@echo "Test targets:"
	@echo "  test          - Run basic functionality test"
	@echo "  test-all      - Run all test suites (integration, parity, POSIX)"
	@echo "  test-integration - Run integration tests"
	@echo "  test-parity   - Run bash parity tests"
	@echo "  test-posix    - Run POSIX compliance tests"
	@echo "  test-features - Run feature test suite"
	@echo "  smoke-test    - Run quick smoke tests"
	@echo "  check         - Run comprehensive checks"
	@echo ""
	@echo "Installation targets:"
	@echo "  install       - Install fortsh to /usr/local/bin"
	@echo "  dev-install   - Install fortsh to ~/.local/bin"
	@echo "  uninstall     - Remove fortsh from system"
	@echo ""
	@echo "Package targets:"
	@echo "  dist          - Create distribution package"
	@echo "  rpm           - Build RPM package"
	@echo ""
	@echo "Other targets:"
	@echo "  help          - Show this help"

# Package information
PACKAGE = fortsh
VERSION = 0.8.0
# Legacy version (pre-semver reset): 6.0.6

# Distribution and packaging targets
dist: clean
	@echo "Creating distribution package..."
	tar czf $(PACKAGE)-$(VERSION).tar.gz \
		--exclude='.git*' \
		--exclude='*.o' \
		--exclude='*.mod' \
		--exclude='build' \
		--exclude='bin' \
		--transform 's,^,$(PACKAGE)-$(VERSION)/,' \
		src/ tests/ Makefile README.md fortsh.spec

rpm: dist
	@echo "Building RPM package..."
	@command -v rpmbuild >/dev/null 2>&1 || (echo "rpmbuild not available - install rpm-build package" && exit 1)
	mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	cp $(PACKAGE)-$(VERSION).tar.gz ~/rpmbuild/SOURCES/
	cp $(PACKAGE).spec ~/rpmbuild/SPECS/
	rpmbuild -ba ~/rpmbuild/SPECS/$(PACKAGE).spec
	@echo "RPM packages created in ~/rpmbuild/RPMS/"

dev-install: $(TARGET)
	@echo "Installing fortsh for development..."
	mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/
	@echo "fortsh installed to ~/.local/bin/fortsh"
	@echo "Make sure ~/.local/bin is in your PATH"

uninstall:
	@echo "Uninstalling fortsh..."
	@rm -f ~/.local/bin/fortsh 2>/dev/null || true
	@rm -f /usr/local/bin/fortsh 2>/dev/null || sudo rm -f /usr/local/bin/fortsh 2>/dev/null || true
	@echo "Uninstall complete!"

check: $(TARGET)
	@echo "Running comprehensive checks..."
	@echo "✓ Build system works"
	./tests/integration_test.sh
	@echo "✓ Integration tests completed"

smoke-test: $(TARGET)
	@echo "Running smoke tests..."
	@echo "echo 'Hello from Fortsh!'" | $(TARGET) && echo "✓ Basic execution works"
	@echo -e "help\nexit" | $(TARGET) >/dev/null && echo "✓ Help command works"
	@echo -e "echo *.txt\nexit" | $(TARGET) >/dev/null && echo "✓ Glob expansion works"
	@echo "perf on\necho 'test'\nperf\nexit" | $(TARGET) >/dev/null && echo "✓ Performance monitoring works"
	@echo "All smoke tests passed!"

# macOS ARM64 specific tests - only run on Darwin arm64
test-macos-pool: $(TARGET)
ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),arm64)
	@echo "=========================================="
	@echo "macOS ARM64 Memory Pool Validation"
	@echo "Testing string pool with flang-new limits"
	@echo "=========================================="
	@if [ -f tests/macos_arm64_pool_checks.sh ]; then \
		chmod +x tests/macos_arm64_pool_checks.sh && \
		./tests/macos_arm64_pool_checks.sh; \
	else \
		echo "⚠️  macOS ARM64 pool checks not found"; \
	fi
	@if [ -f tests/memory_pool_validation.sh ]; then \
		echo "" && \
		echo "Running general pool validation..." && \
		chmod +x tests/memory_pool_validation.sh && \
		./tests/memory_pool_validation.sh; \
	fi
	@echo "✓ macOS ARM64 pool tests complete"
    else
	@echo "⚠️  Skipping macOS ARM64 tests (not on arm64 platform)"
    endif
else
	@echo "⚠️  Skipping macOS tests (not on Darwin)"
endif

# macOS build verification - ensures no flang-new regressions
test-macos-compiler: $(TARGET)
ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),arm64)
	@echo "=========================================="
	@echo "macOS ARM64 Compiler Compatibility Check"
	@echo "Verifying flang-new workarounds"
	@echo "=========================================="
	@echo "Testing 127-byte command limit..."
	@echo 'echo "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456"' | $(TARGET) 2>&1 | grep -q "123456" && echo "✓ Long command handling works"
	@echo "Testing fixed-length string buffers..."
	@echo "echo test" | $(TARGET) >/dev/null && echo "✓ Fixed-length buffers work"
	@echo "✓ macOS compiler compatibility verified"
    else
	@echo "⚠️  Skipping macOS ARM64 compiler tests (not on arm64)"
    endif
else
	@echo "⚠️  Skipping macOS compiler tests (not on Darwin)"
endif

# Combined macOS test suite
test-macos: test-macos-pool test-macos-compiler
	@echo ""
	@echo "=========================================="
	@echo "All macOS ARM64 Tests Complete"
	@echo "=========================================="

# Test C string library (flang-new workaround)
test-c-strings: $(BUILDDIR)/test_c_strings
	@echo "=========================================="
	@echo "Testing C String Library"
	@echo "=========================================="
	@$(BUILDDIR)/test_c_strings
	@echo ""
	@echo "✓ C string library test passed!"
	@echo "This proves we can handle >128 byte strings"
	@echo "without triggering flang-new heap corruption!"
	@echo "=========================================="

# Build just the C string library and test
c-strings: $(BUILDDIR)/test_c_strings
	@echo "C string library built successfully!"
	@echo "Run 'make test-c-strings' to test it"

.PHONY: all clean distclean install test debug release help dist rpm dev-install uninstall check smoke-test test-integration test-parity test-posix test-features test-all test-macos-pool test-macos-compiler test-macos test-c-strings c-strings