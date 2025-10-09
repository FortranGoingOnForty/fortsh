# Makefile for AST modules
FC = gfortran
FCFLAGS = -Wall -Wextra -std=f2018 -g -O2 -I../../build -J.

# Source files
SRCS = ast_types.f90 lexer.f90 parser.f90 evaluator.f90
OBJS = ast_types.o lexer.o parser.o evaluator.o

# Test program
TEST_SRC = ../../tests/test_ast.f90
TEST_EXE = test_ast

# Build all modules
all: $(OBJS) test

# Module dependencies
ast_types.o: ast_types.f90
	$(FC) $(FCFLAGS) -c $<

lexer.o: lexer.f90 ast_types.o
	$(FC) $(FCFLAGS) -c $<

parser.o: parser.f90 ast_types.o lexer.o
	$(FC) $(FCFLAGS) -c $<

evaluator.o: evaluator.f90 ast_types.o ../../build/shell_types.o ../../build/system_interface.o
	$(FC) $(FCFLAGS) -c $<

# Build test program
test: $(OBJS)
	$(FC) $(FCFLAGS) -o $(TEST_EXE) $(TEST_SRC) $(OBJS) ../../build/shell_types.o ../../build/system_interface.o

# Run tests
run-test: test
	./$(TEST_EXE)

# Clean
clean:
	rm -f *.o *.mod $(TEST_EXE)

.PHONY: all test run-test clean