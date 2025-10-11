# Makefile for Enhanced AST modules
FC = gfortran
FCFLAGS = -Wall -Wextra -std=f2018 -g -O2 -J.

# Source files for enhanced architecture
SRCS = shell_types_stub.f90 ast_types_enhanced.f90 lexer_simple.f90 parser_enhanced.f90 evaluator_simple_real.f90
OBJS = shell_types_stub.o ast_types_enhanced.o lexer_simple.o parser_enhanced.o evaluator_simple_real.o

# Test programs
TEST_AST_SRC = ../../tests/test_ast_simple.f90
TEST_AST_EXE = test_ast_simple

TEST_PARSER_SRC = ../../tests/test_parser_lists.f90
TEST_PARSER_EXE = test_parser_lists

TEST_EVAL_SRC = ../../tests/test_evaluator.f90
TEST_EVAL_EXE = test_evaluator

# Build all modules
all: $(OBJS)

# Module dependencies
shell_types_stub.o: shell_types_stub.f90
	$(FC) $(FCFLAGS) -c $<

ast_types_enhanced.o: ast_types_enhanced.f90
	$(FC) $(FCFLAGS) -c $<

lexer_simple.o: lexer_simple.f90 ast_types_enhanced.o
	$(FC) $(FCFLAGS) -c $<

parser_enhanced.o: parser_enhanced.f90 ast_types_enhanced.o
	$(FC) $(FCFLAGS) -c $<

evaluator_simple_real.o: evaluator_simple_real.f90 shell_types_stub.o ast_types_enhanced.o lexer_simple.o parser_enhanced.o
	$(FC) $(FCFLAGS) -c $<

# Build test programs
test_ast: shell_types_stub.o ast_types_enhanced.o
	$(FC) $(FCFLAGS) -o $(TEST_AST_EXE) $(TEST_AST_SRC) shell_types_stub.o ast_types_enhanced.o

test_parser: shell_types_stub.o ast_types_enhanced.o lexer_simple.o parser_enhanced.o
	$(FC) $(FCFLAGS) -o $(TEST_PARSER_EXE) $(TEST_PARSER_SRC) shell_types_stub.o ast_types_enhanced.o lexer_simple.o parser_enhanced.o

test_evaluator: $(OBJS)
	$(FC) $(FCFLAGS) -o $(TEST_EVAL_EXE) $(TEST_EVAL_SRC) $(OBJS)

# Run tests
run-test-ast: test_ast
	./$(TEST_AST_EXE)

run-test-parser: test_parser
	./$(TEST_PARSER_EXE)

run-test-evaluator: test_evaluator
	./$(TEST_EVAL_EXE)

# Run all tests
test: test_ast test_parser test_evaluator
	@echo "Running AST tests..."
	./$(TEST_AST_EXE)
	@echo "Running parser tests..."
	./$(TEST_PARSER_EXE)
	@echo "Running evaluator tests..."
	./$(TEST_EVAL_EXE)

# Clean
clean:
	rm -f *.o *.mod $(TEST_AST_EXE) $(TEST_PARSER_EXE) $(TEST_EVAL_EXE)

.PHONY: all test test_ast test_parser test_evaluator run-test-ast run-test-parser run-test-evaluator clean
