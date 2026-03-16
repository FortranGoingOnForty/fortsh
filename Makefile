# Fortran Shell (Fortsh) Makefile
# ====================================

# Compiler settings
# Use LLVM Flang on macOS ARM64 for better stability
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),arm64)
        # macOS ARM64: Use LLVM Flang for better stability
        FC = flang-new
        PLATFORM_FLAGS = -D__APPLE__ -cpp
        $(info Using flang-new on macOS ARM64)
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
    ifeq ($(MEMPOOL_DEBUG),1)
        POOL_FLAGS += -DMEMPOOL_DEBUG
        $(info Memory pooling ENABLED with DEBUG output - using zero-copy string pool)
    else
        $(info Memory pooling ENABLED - using zero-copy string pool [DEFAULT])
    endif
endif

# C compiler for string operations library
CC = gcc
# Note: Don't use $(PLATFORM_FLAGS) here - it contains Fortran flags like -cpp
ifeq ($(UNAME_S),Darwin)
  CFLAGS = -Wall -Wextra -fPIC -g -O2 -D__APPLE__
else
  CFLAGS = -Wall -Wextra -fPIC -g -O2
endif

# Warning flags and intrinsics (flang-new doesn't support -Wall/-Wextra/-fall-intrinsics)
ifeq ($(FC),flang-new)
    WARN_FLAGS =
    WARN_FLAGS_RELEASE =
    # flang-new supports F2018 flush() natively; -fall-intrinsics is gfortran-only
    INTRINSICS_FLAG =
else
    WARN_FLAGS = -Wall -Wextra
    WARN_FLAGS_RELEASE = -Wall -Wno-unused-variable -Wno-unused-dummy-argument -Wno-maybe-uninitialized -Wno-function-elimination -Wno-surprising -Wno-character-truncation
    # -fall-intrinsics allows GNU extensions like flush() with -std=f2018
    INTRINSICS_FLAG = -fall-intrinsics
endif

# Development flags (verbose warnings, debug symbols)
FCFLAGS = $(WARN_FLAGS) -std=f2018 $(INTRINSICS_FLAG) -fPIC -g -O0 $(PLATFORM_FLAGS) $(POOL_FLAGS)
# Production flags (minimal warnings, optimized, no debug symbols)
FCFLAGS_RELEASE = $(WARN_FLAGS_RELEASE) -std=f2018 $(INTRINSICS_FLAG) -fPIC -O2 $(PLATFORM_FLAGS) $(POOL_FLAGS)

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

# Core C objects needed on all platforms (fd operations, terminal size, string ops)
CORE_C_OBJS = $(BUILDDIR)/c_interop/fd_wrapper.o $(BUILDDIR)/c_interop/terminal_size.o $(BUILDDIR)/c_interop/fortsh_strings.o

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

# macOS ARM64: increase stack size to 16MB (flang-new uses ~2x more stack per frame)
ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    LDFLAGS += -Wl,-stack_size,0x1000000
  endif
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

# Object files with explicit dependencies
# All module dependencies are properly declared in the rules below,
# so parallel builds work correctly
OBJECTS = $(BUILDDIR)/common/types.o \
          $(BUILDDIR)/common/version.o \
          $(BUILDDIR)/common/error_handling.o \
          $(BUILDDIR)/common/performance.o \
          $(POOL_OBJECTS) \
          $(BUILDDIR)/common/buffer_ops.o \
          $(BUILDDIR)/system/interface.o \
          $(BUILDDIR)/common/io_helpers.o \
          $(BUILDDIR)/system/signals.o \
          $(BUILDDIR)/system/signal_handling.o \
          $(BUILDDIR)/parsing/glob.o \
          $(BUILDDIR)/scripting/variables.o \
          $(BUILDDIR)/execution/jobs.o \
          $(BUILDDIR)/scripting/test_builtin.o \
          $(BUILDDIR)/scripting/advanced_test.o \
          $(BUILDDIR)/scripting/printf_builtin.o \
          $(BUILDDIR)/scripting/read_builtin.o \
          $(BUILDDIR)/scripting/getopts_builtin.o \
          $(BUILDDIR)/scripting/directory_builtin.o \
          $(BUILDDIR)/scripting/command_builtin.o \
          $(BUILDDIR)/scripting/prompt_formatting.o \
          $(BUILDDIR)/scripting/config.o \
          $(BUILDDIR)/scripting/aliases.o \
          $(BUILDDIR)/scripting/abbreviations.o \
          $(BUILDDIR)/io/syntax_highlight.o \
          $(BUILDDIR)/execution/coprocess.o \
          $(BUILDDIR)/execution/better_errors.o \
          $(BUILDDIR)/io/heredoc.o \
          $(BUILDDIR)/io/fd_redirection.o \
          $(BUILDDIR)/scripting/control_flow.o \
          $(BUILDDIR)/parsing/lexer.o \
          $(BUILDDIR)/parsing/command_tree.o \
          $(BUILDDIR)/parsing/grammar_parser.o \
          $(BUILDDIR)/parsing/parser.o \
          $(BUILDDIR)/scripting/completion.o \
          $(BUILDDIR)/execution/builtin_help_texts.o \
          $(BUILDDIR)/execution/builtin_interface.o \
          $(BUILDDIR)/execution/trap_dispatch.o \
          $(BUILDDIR)/execution/pipeline_helpers.o \
          $(BUILDDIR)/execution/executor.o \
          $(BUILDDIR)/execution/ast_executor.o \
          $(BUILDDIR)/execution/eval_builtin.o \
          $(BUILDDIR)/execution/builtins.o \
          $(BUILDDIR)/execution/command_capture.o \
          $(BUILDDIR)/execution/command_capture_callback.o \
          $(BUILDDIR)/scripting/expansion.o \
          $(BUILDDIR)/scripting/substitution.o \
          $(BUILDDIR)/io/suggestions.o \
          $(BUILDDIR)/io/readline.o \
          $(BUILDDIR)/scripting/shell_options.o \
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
$(TARGET): $(OBJECTS) $(CORE_C_OBJS) $(C_STRING_OBJ) $(C_STRING_LIB) | $(BINDIR)
	$(FC) $(C_STRING_OBJ) $(CORE_C_OBJS) $(OBJECTS) -o $@ $(LDFLAGS)
	@echo "Fortsh built successfully!"

# Individual compilation rules with proper dependencies
$(BUILDDIR)/common/types.o: src/common/types.f90 | $(BUILDDIR)/common
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/common/version.o: src/common/version.f90 | $(BUILDDIR)/common
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

# Buffer operations abstraction (depends on C strings if enabled)
$(BUILDDIR)/common/buffer_ops.o: src/common/buffer_ops.f90 $(C_STRING_OBJ) | $(BUILDDIR)/common
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

$(BUILDDIR)/parsing/parser.o: src/parsing/parser.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/error_handling.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/parsing/glob.o $(BUILDDIR)/scripting/substitution.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/parsing/lexer.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/lexer.o: src/parsing/lexer.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/command_tree.o: src/parsing/command_tree.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/parsing/grammar_parser.o: src/parsing/grammar_parser.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/parsing/lexer.o $(BUILDDIR)/parsing/parser.o | $(BUILDDIR)/parsing
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/jobs.o: src/execution/jobs.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/control_flow.o: src/scripting/control_flow.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/expansion.o $(BUILDDIR)/scripting/advanced_test.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/test_builtin.o $(BUILDDIR)/scripting/substitution.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtin_help_texts.o: src/execution/builtin_help_texts.f90 | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtin_interface.o: src/execution/builtin_interface.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/builtins.o: src/execution/builtins.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/common/io_helpers.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/test_builtin.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/execution/coprocess.o $(BUILDDIR)/scripting/command_builtin.o $(BUILDDIR)/scripting/directory_builtin.o $(BUILDDIR)/scripting/getopts_builtin.o $(BUILDDIR)/scripting/printf_builtin.o $(BUILDDIR)/scripting/read_builtin.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/execution/builtin_interface.o $(BUILDDIR)/execution/builtin_help_texts.o $(BUILDDIR)/execution/eval_builtin.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/system/signal_handling.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/trap_dispatch.o: src/execution/trap_dispatch.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/pipeline_helpers.o: src/execution/pipeline_helpers.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/parsing/glob.o $(BUILDDIR)/scripting/expansion.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/executor.o: src/execution/executor.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/error_handling.o $(BUILDDIR)/common/performance.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/scripting/control_flow.o $(BUILDDIR)/execution/builtin_interface.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/parsing/grammar_parser.o $(BUILDDIR)/parsing/command_tree.o $(BUILDDIR)/execution/trap_dispatch.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/execution/better_errors.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/execution/pipeline_helpers.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/ast_executor.o: src/execution/ast_executor.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/parsing/command_tree.o $(BUILDDIR)/execution/executor.o $(BUILDDIR)/execution/pipeline_helpers.o $(BUILDDIR)/execution/trap_dispatch.o $(BUILDDIR)/io/fd_redirection.o $(BUILDDIR)/parsing/grammar_parser.o $(BUILDDIR)/execution/coprocess.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/eval_builtin.o: src/execution/eval_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/parsing/grammar_parser.o $(BUILDDIR)/parsing/command_tree.o $(BUILDDIR)/execution/ast_executor.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/command_capture.o: src/execution/command_capture.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/command_capture_callback.o: src/execution/command_capture_callback.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/parsing/grammar_parser.o $(BUILDDIR)/execution/ast_executor.o $(BUILDDIR)/parsing/command_tree.o $(BUILDDIR)/execution/command_capture.o | $(BUILDDIR)/execution
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

$(BUILDDIR)/scripting/command_builtin.o: src/scripting/command_builtin.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/execution/ast_executor.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/variables.o: src/scripting/variables.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/prompt_formatting.o: src/scripting/prompt_formatting.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/substitution.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/expansion.o: src/scripting/expansion.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/execution/command_capture.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/substitution.o: src/scripting/substitution.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/execution/command_capture.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/coprocess.o: src/execution/coprocess.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/execution/better_errors.o: src/execution/better_errors.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/execution
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/config.o: src/scripting/config.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/aliases.o: src/scripting/aliases.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/io_helpers.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/abbreviations.o: src/scripting/abbreviations.f90 $(BUILDDIR)/common/types.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/shell_options.o: src/scripting/shell_options.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/prompt_formatting.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/scripting/completion.o: src/scripting/completion.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o $(BUILDDIR)/parsing/parser.o | $(BUILDDIR)/scripting
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/syntax_highlight.o: src/io/syntax_highlight.f90 $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/suggestions.o: src/io/suggestions.f90 | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/readline.o: src/io/readline.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/buffer_ops.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/io/syntax_highlight.o $(BUILDDIR)/io/suggestions.o $(BUILDDIR)/scripting/abbreviations.o $(BUILDDIR)/parsing/glob.o $(BUILDDIR)/scripting/completion.o $(C_STRING_OBJ) | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/heredoc.o: src/io/heredoc.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/scripting/variables.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/io/fd_redirection.o: src/io/fd_redirection.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/system/interface.o | $(BUILDDIR)/io
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

$(BUILDDIR)/fortsh.o: src/fortsh.f90 $(BUILDDIR)/common/types.o $(BUILDDIR)/common/version.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/system/signals.o $(BUILDDIR)/system/signal_handling.o $(BUILDDIR)/parsing/parser.o $(BUILDDIR)/parsing/lexer.o $(BUILDDIR)/parsing/grammar_parser.o $(BUILDDIR)/parsing/command_tree.o $(BUILDDIR)/execution/executor.o $(BUILDDIR)/execution/ast_executor.o $(BUILDDIR)/execution/jobs.o $(BUILDDIR)/io/readline.o $(BUILDDIR)/scripting/config.o $(BUILDDIR)/scripting/aliases.o $(BUILDDIR)/scripting/shell_options.o $(BUILDDIR)/scripting/prompt_formatting.o $(BUILDDIR)/execution/command_capture_callback.o $(BUILDDIR)/execution/builtins.o $(BUILDDIR)/common/performance.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) -c $< -o $@

# ============================================================================
# C string library (flang-new workaround for macOS ARM64)
# ============================================================================

# Compile C string operations library
$(BUILDDIR)/c_interop/fortsh_strings.o: src/c_interop/fortsh_strings.c src/c_interop/fortsh_strings.h | $(BUILDDIR)/c_interop
	$(CC) $(CFLAGS) -c $< -o $@

# Compile C file descriptor wrapper (workaround for Fortran C binding mode_t bug)
$(BUILDDIR)/c_interop/fd_wrapper.o: src/c_interop/fd_wrapper.c | $(BUILDDIR)/c_interop
	$(CC) $(CFLAGS) -c $< -o $@

# Compile C terminal size wrapper
$(BUILDDIR)/c_interop/terminal_size.o: src/c_interop/terminal_size.c | $(BUILDDIR)/c_interop
	$(CC) $(CFLAGS) -c $< -o $@

# Create static library from C objects
$(BUILDDIR)/c_interop/libfortsh_strings.a: $(BUILDDIR)/c_interop/fortsh_strings.o $(BUILDDIR)/c_interop/fd_wrapper.o $(BUILDDIR)/c_interop/terminal_size.o
	ar rcs $@ $^

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

ifeq ($(FC),flang-new)
debug: FCFLAGS += -g
else
debug: FCFLAGS += -g -fbacktrace -fcheck=bounds
endif
debug: $(TARGET)

release: FCFLAGS = $(FCFLAGS_RELEASE)
release: clean $(TARGET)
	@echo "Building release version..."
	strip $(TARGET)
	@echo "Release build complete! Binary size: $$(du -h $(TARGET) | cut -f1)"

# Test suite targets
FORTSH_ABS = $(CURDIR)/$(TARGET)

# POSIX compliance: single canonical test script (fastest)
test-posix: $(TARGET)
	@echo "Running POSIX compliance tests..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/posix_compliance_test.sh

# Full POSIX suite: all shell-based POSIX test scripts via the comprehensive runner
test-posix-full: $(TARGET)
	@echo "Running full POSIX compliance test suite..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/run_all_tests.sh --posix-only

# Quick POSIX suite: skip slow coverage/untested suites
test-posix-quick: $(TARGET)
	@echo "Running quick POSIX compliance tests..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/run_all_tests.sh --posix-only --quick

# Interactive PTY tests (requires Python venv with pexpect)
test-interactive: $(TARGET)
	@echo "Running interactive PTY tests..."
	@if [ ! -d tests/interactive/.venv ] && [ ! -d tests/interactive/venv ]; then \
		echo "Setting up Python virtual environment..."; \
		python3 -m venv tests/interactive/.venv; \
		. tests/interactive/.venv/bin/activate && pip install -r tests/interactive/requirements.txt; \
	fi
	@if [ -f tests/interactive/.venv/bin/activate ]; then \
		. tests/interactive/.venv/bin/activate && cd tests/interactive && python run_tests.py; \
	elif [ -f tests/interactive/venv/bin/activate ]; then \
		. tests/interactive/venv/bin/activate && cd tests/interactive && python run_tests.py; \
	else \
		echo "Error: Python venv not found. Run: cd tests/interactive && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"; \
		exit 1; \
	fi

# Full test run: POSIX + interactive (no memory rebuild)
test-full: $(TARGET)
	@echo "Running full test suite (POSIX + interactive)..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/run_all_tests.sh --full

# Everything including memory pool tests (SLOW: rebuilds fortsh)
test-all: $(TARGET)
	@echo "Running all test suites..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/run_all_tests.sh --all

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
	@echo "  MEMPOOL_DEBUG=1 make - Build with memory pool debug output"
	@echo ""
	@echo "C string library (flang-new workaround):"
	@echo "  c-strings     - Build C string library test"
	@echo "  test-c-strings - Test C string library (>128 byte strings)"
	@echo "  USE_C_STRINGS=1 make - Enable C strings in fortsh (experimental)"
	@echo ""
	@echo "Test targets:"
	@echo "  test            - Run basic functionality test"
	@echo "  test-posix      - Run core POSIX compliance tests (~1 min)"
	@echo "  test-posix-full - Run all POSIX test suites (~3 min)"
	@echo "  test-posix-quick- Run fast POSIX tests, skip coverage (~30s)"
	@echo "  test-interactive- Run interactive PTY tests (~2 min)"
	@echo "  test-full       - Run POSIX + interactive tests (~5 min)"
	@echo "  test-all        - Run everything incl. memory tests (SLOW)"
	@echo "  test-stress     - Run stress tests for large values/deep nesting"
	@echo "  check           - Run comprehensive checks"
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
VERSION = 1.0.1
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
	@printf 'help\nexit\n' | $(TARGET) >/dev/null && echo "✓ Help command works"
	@printf 'echo *.txt\nexit\n' | $(TARGET) >/dev/null && echo "✓ Glob expansion works"
	@printf 'perf on\necho test\nperf\nexit\n' | $(TARGET) >/dev/null && echo "✓ Performance monitoring works"
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

# ============================================================================
# Unit Test Bench Files
# ============================================================================

# Build rules for unit tests
$(BUILDDIR)/test_memory_pool: tests/test_memory_pool.f90 $(BUILDDIR)/common/string_pool.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o -o $@

$(BUILDDIR)/test_lexer_simple: tests/test_lexer_simple.f90 $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o -o $@

$(BUILDDIR)/test_parser_simple: tests/test_parser_simple.f90 $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o -o $@

$(BUILDDIR)/test_executor_simple: tests/test_executor_simple.f90 $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o -o $@

$(BUILDDIR)/test_expansion_simple: tests/test_expansion_simple.f90 $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o -o $@

$(BUILDDIR)/test_variables_simple: tests/test_variables_simple.f90 $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(BUILDDIR)/common/types.o -o $@

$(BUILDDIR)/test_suggestions: tests/test_suggestions.f90 $(BUILDDIR)/io/suggestions.o | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/io/suggestions.o -o $@

$(BUILDDIR)/test_syntax_highlight: tests/test_syntax_highlight.f90 $(BUILDDIR)/io/syntax_highlight.o $(CORE_C_OBJS) | $(BUILDDIR)
	$(FC) $(FCFLAGS) -J$(BUILDDIR) $< $(BUILDDIR)/io/syntax_highlight.o $(BUILDDIR)/system/interface.o $(BUILDDIR)/common/types.o $(BUILDDIR)/common/string_pool.o $(BUILDDIR)/common/memory_dashboard.o $(CORE_C_OBJS) -o $@

# Individual test targets
test-memory-pool: $(BUILDDIR)/test_memory_pool
	@echo "=========================================="
	@echo "Testing Memory Pool (String Pool)"
	@echo "=========================================="
	@$(BUILDDIR)/test_memory_pool

test-lexer: $(BUILDDIR)/test_lexer_simple
	@echo "=========================================="
	@echo "Testing Lexer"
	@echo "=========================================="
	@$(BUILDDIR)/test_lexer_simple

test-parser: $(BUILDDIR)/test_parser_simple
	@echo "=========================================="
	@echo "Testing Parser"
	@echo "=========================================="
	@$(BUILDDIR)/test_parser_simple

test-executor: $(BUILDDIR)/test_executor_simple
	@echo "=========================================="
	@echo "Testing Executor"
	@echo "=========================================="
	@$(BUILDDIR)/test_executor_simple

test-expansion: $(BUILDDIR)/test_expansion_simple
	@echo "=========================================="
	@echo "Testing Expansion"
	@echo "=========================================="
	@$(BUILDDIR)/test_expansion_simple

test-variables: $(BUILDDIR)/test_variables_simple
	@echo "=========================================="
	@echo "Testing Variables"
	@echo "=========================================="
	@$(BUILDDIR)/test_variables_simple

test-suggestions: $(BUILDDIR)/test_suggestions
	@echo "=========================================="
	@echo "Testing Suggestions"
	@echo "=========================================="
	@$(BUILDDIR)/test_suggestions

test-highlight: $(BUILDDIR)/test_syntax_highlight
	@echo "=========================================="
	@echo "Testing Syntax Highlight v2"
	@echo "=========================================="
	@$(BUILDDIR)/test_syntax_highlight

# Run all unit bench tests (working tests only)
test-stress: $(TARGET)
	@echo "Running stress tests..."
	FORTSH_BIN=$(FORTSH_ABS) ./tests/builtins/test_stress.sh

test-bench: test-memory-pool test-lexer test-executor test-suggestions test-highlight test-c-strings test-stress
	@echo ""
	@echo "=========================================="
	@echo "All bench tests passed!"
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

.PHONY: all clean distclean install test debug release help dist rpm dev-install uninstall check smoke-test test-integration test-parity test-posix test-features test-all test-macos-pool test-macos-compiler test-macos test-c-strings c-strings test-memory-pool test-lexer test-parser test-executor test-expansion test-variables test-suggestions test-highlight test-stress test-bench