# Fortran Shell (Fortsh) Makefile
# ====================================

# Compiler settings
FC = gfortran
FCFLAGS = -Wall -Wextra -std=f2018 -fPIC -g -O2
LDFLAGS = 

# Directory structure
SRCDIR = src
BUILDDIR = build
BINDIR = bin

# Object files in dependency order
OBJECTS = $(BUILDDIR)/common/types.o \
          $(BUILDDIR)/system/interface.o \
          $(BUILDDIR)/system/signals.o \
          $(BUILDDIR)/parsing/parser.o \
          $(BUILDDIR)/execution/jobs.o \
          $(BUILDDIR)/execution/builtins.o \
          $(BUILDDIR)/execution/executor.o \
          $(BUILDDIR)/scripting/control_flow.o \
          $(BUILDDIR)/scripting/test_builtin.o \
          $(BUILDDIR)/scripting/variables.o \
          $(BUILDDIR)/fortsh.o

# Target executable
TARGET = $(BINDIR)/fortsh

# Default target
all: $(TARGET)

# Create directories
$(BUILDDIR) $(BINDIR):
	mkdir -p $@

$(BUILDDIR)/common $(BUILDDIR)/system $(BUILDDIR)/parsing $(BUILDDIR)/execution $(BUILDDIR)/scripting: | $(BUILDDIR)
	mkdir -p $@

# Build target
$(TARGET): $(OBJECTS) | $(BINDIR)
	$(FC) $(OBJECTS) -o $@ $(LDFLAGS)
	@echo "Fortsh built successfully!"

# Individual compilation rules with proper dependencies
$(BUILDDIR)/common/types.o: src/common/types.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/system/interface.o: src/system/interface.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/system
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/system/signals.o: src/system/signals.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/system
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/parser.o: src/parsing/parser.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/jobs.o: src/execution/jobs.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtins.o: src/execution/builtins.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/test_builtin.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/executor.o: src/execution/executor.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/execution/builtins.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/control_flow.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/control_flow.o: src/scripting/control_flow.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/test_builtin.o: src/scripting/test_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/variables.o: src/scripting/variables.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/parsing/parser.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/fortsh.o: src/fortsh.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signals.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/execution/executor.o $(BUILDDIR)/execution/jobs.o | $(BUILDDIR)
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

# Help target
help:
	@echo "Fortran Shell (Fortsh) Build System"
	@echo "==================================="
	@echo ""
	@echo "Available targets:"
	@echo "  all       - Build fortsh (default)"
	@echo "  clean     - Remove build artifacts"
	@echo "  distclean - Remove all generated files"
	@echo "  install   - Install fortsh to /usr/local/bin"
	@echo "  test      - Run basic functionality test"
	@echo "  debug     - Build with debug flags"
	@echo "  help      - Show this help"

.PHONY: all clean distclean install test debug help