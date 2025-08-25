# Test Suite Makefile for Fortran Shell (fortsh)
# ================================================

# Compiler settings
FC = gfortran
FCFLAGS = -Wall -Wextra -std=f2018 -fPIC -g -O0 -fcheck=all
LDFLAGS = 

# Directories
SRCDIR = ../src
BUILDDIR = build
TESTDIR = .

# Include path for main source modules
INCFLAGS = -I../build

# Test sources
TEST_SOURCES = test_runner.f90

# Required source modules (in dependency order)
SRC_MODULES = $(SRCDIR)/common/types.f90 \
              $(SRCDIR)/common/error_handling.f90 \
              $(SRCDIR)/system/interface.f90 \
              $(SRCDIR)/parsing/glob.f90 \
              $(SRCDIR)/scripting/variables.f90 \
              $(SRCDIR)/parsing/parser.f90 \
              $(SRCDIR)/scripting/control_flow.f90 \
              $(SRCDIR)/execution/jobs.f90 \
              $(SRCDIR)/scripting/aliases.f90

# Object files
SRC_OBJECTS = $(BUILDDIR)/types.o \
              $(BUILDDIR)/error_handling.o \
              $(BUILDDIR)/interface.o \
              $(BUILDDIR)/glob.o \
              $(BUILDDIR)/variables.o \
              $(BUILDDIR)/parser.o \
              $(BUILDDIR)/control_flow.o \
              $(BUILDDIR)/jobs.o \
              $(BUILDDIR)/aliases.o

TEST_OBJECTS = $(BUILDDIR)/test_runner.o

# Target executable
TARGET = $(BUILDDIR)/test_runner

# Default target
all: $(TARGET)

# Create build directory
$(BUILDDIR):
	mkdir -p $(BUILDDIR)

# Test runner executable
$(TARGET): $(SRC_OBJECTS) $(TEST_OBJECTS) | $(BUILDDIR)
	$(FC) $(SRC_OBJECTS) $(TEST_OBJECTS) -o $@ $(LDFLAGS)
	@echo "Test suite built successfully!"

# Test runner object
$(BUILDDIR)/test_runner.o: test_runner.f90 $(SRC_OBJECTS) | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# Source module objects
$(BUILDDIR)/types.o: $(SRCDIR)/common/types.f90 | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/error_handling.o: $(SRCDIR)/common/error_handling.f90 | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/interface.o: $(SRCDIR)/system/interface.f90 $(BUILDDIR)/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/glob.o: $(SRCDIR)/parsing/glob.f90 $(BUILDDIR)/types.o $(BUILDDIR)/interface.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/variables.o: $(SRCDIR)/scripting/variables.f90 $(BUILDDIR)/types.o $(BUILDDIR)/interface.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parser.o: $(SRCDIR)/parsing/parser.f90 $(BUILDDIR)/types.o $(BUILDDIR)/interface.o $(BUILDDIR)/variables.o $(BUILDDIR)/glob.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/control_flow.o: $(SRCDIR)/scripting/control_flow.f90 $(BUILDDIR)/types.o $(BUILDDIR)/interface.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/jobs.o: $(SRCDIR)/execution/jobs.f90 $(BUILDDIR)/types.o $(BUILDDIR)/interface.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/aliases.o: $(SRCDIR)/scripting/aliases.f90 $(BUILDDIR)/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# Run tests
test: $(TARGET)
	@echo "Running test suite..."
	@echo "====================="
	@./$(TARGET)

# Run tests with verbose output
test-verbose: $(TARGET)
	@echo "Running test suite (verbose)..."
	@echo "==============================="
	@./$(TARGET) --verbose

# Clean build artifacts
clean:
	rm -rf $(BUILDDIR)
	@echo "Cleaned test build directory"

# Clean and rebuild
rebuild: clean all

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build test suite"
	@echo "  test     - Run tests"
	@echo "  test-verbose - Run tests with verbose output"
	@echo "  clean    - Remove build artifacts"
	@echo "  rebuild  - Clean and rebuild"
	@echo "  help     - Show this help message"

.PHONY: all test test-verbose clean rebuild help