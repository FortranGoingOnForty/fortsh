# Fortran Shell (Fortsh) Makefile
# ====================================

# Compiler settings
FC = gfortran

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    PLATFORM_FLAGS = -D__APPLE__ -cpp
else
    PLATFORM_FLAGS = -cpp
endif

# Development flags (verbose warnings, debug symbols)
FCFLAGS = -Wall -Wextra -std=f2018 -fPIC -g -O2 $(PLATFORM_FLAGS)
# Production flags (minimal warnings, optimized, no debug symbols)
FCFLAGS_RELEASE = -Wall -Wno-unused-variable -Wno-unused-dummy-argument -Wno-maybe-uninitialized -Wno-function-elimination -Wno-surprising -Wno-character-truncation -std=f2018 -fPIC -O2 $(PLATFORM_FLAGS)
LDFLAGS = 

# Directory structure
SRCDIR = src
BUILDDIR = build
BINDIR = bin

# Object files in dependency order
OBJECTS = $(BUILDDIR)/common/types.o \
          $(BUILDDIR)/common/error_handling.o \
          $(BUILDDIR)/common/performance.o \
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
          $(BUILDDIR)/io/readline.o \
          $(BUILDDIR)/scripting/shell_options.o \
          $(BUILDDIR)/execution/coprocess.o \
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

$(BUILDDIR)/common $(BUILDDIR)/system $(BUILDDIR)/parsing $(BUILDDIR)/execution $(BUILDDIR)/scripting $(BUILDDIR)/io: | $(BUILDDIR)
	mkdir -p $@

# Build target
$(TARGET): $(OBJECTS) | $(BINDIR)
	$(FC) $(OBJECTS) -o $@ $(LDFLAGS)
	@echo "Fortsh built successfully!"

# Individual compilation rules with proper dependencies
$(BUILDDIR)/common/types.o: src/common/types.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/error_handling.o: src/common/error_handling.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/performance.o: src/common/performance.f90 | $(BUILDDIR)/common
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

$(BUILDDIR)/execution/executor.o: src/execution/executor.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/error_handling.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/control_flow.o $(BUILDDIR)/execution/builtins.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtins.o: src/execution/builtins.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/common/io_helpers.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/test_builtin.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/coprocess.o $(BUILDDIR)/scripting/command_builtin.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/substitution.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/control_flow.o: src/scripting/control_flow.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/advanced_test.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/test_builtin.o | $(BUILDDIR)/scripting
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

$(BUILDDIR)/scripting/expansion.o: src/scripting/expansion.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/substitution.o: src/scripting/substitution.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/coprocess.o: src/execution/coprocess.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/config.o: src/scripting/config.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/aliases.o: src/scripting/aliases.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/shell_options.o: src/scripting/shell_options.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/io/readline.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/readline.o: src/io/readline.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/heredoc.o: src/io/heredoc.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/fd_redirection.o: src/io/fd_redirection.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/fortsh.o: src/fortsh.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signals.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/executor.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/scripting/prompt_formatting.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

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

# Help target
help:
	@echo "Fortran Shell (Fortsh) Build System"
	@echo "==================================="
	@echo ""
	@echo "Available targets:"
	@echo "  all       - Build fortsh (default, development mode)"
	@echo "  release   - Build optimized production binary (stripped, minimal warnings)"
	@echo "  debug     - Build with extra debug flags and checks"
	@echo "  clean     - Remove build artifacts"
	@echo "  distclean - Remove all generated files"
	@echo "  install   - Install fortsh to /usr/local/bin"
	@echo "  test      - Run basic functionality test"
	@echo "  help      - Show this help"
	@echo "  dist      - Create distribution package"
	@echo "  rpm       - Build RPM package"
	@echo "  check     - Run comprehensive checks"
	@echo "  smoke-test- Run basic functionality tests"

# Package information
PACKAGE = fortsh
VERSION = 4.0.0

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

.PHONY: all clean distclean install test debug release help dist rpm dev-install uninstall check smoke-test