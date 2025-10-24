#!/bin/sh
# =====================================
# POSIX Compliance Test Suite for fortsh
# =====================================
# Tests compliance with POSIX shell specification
# Uses /bin/sh for comparison (typically dash or bash in POSIX mode)

# Note: Using only POSIX-compliant constructs in this script
# No bash-isms allowed!

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

# Get script directory (POSIX way)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../bin/fortsh}"

# Check if fortsh exists
if [ ! -x "$FORTSH_BIN" ]; then
    printf "${RED}ERROR${NC}: fortsh binary not found at $FORTSH_BIN\n"
    printf "Please run 'make' first or set FORTSH_BIN environment variable\n"
    exit 1
fi

# Test result trackers
pass() {
    printf "${GREEN}✓ PASS${NC}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf "${RED}✗ FAIL${NC}: %s\n" "$1"
    if [ -n "$2" ]; then
        printf "  posix:  %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  fortsh: %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    printf "${YELLOW}⊘ SKIP${NC}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Helper function to run command in both shells and compare
compare_posix_output() {
    test_name="$1"
    command="$2"
    posix_file="/tmp/posix_comp_$$_posix"
    fortsh_file="/tmp/posix_comp_$$_fortsh"

    # Run in POSIX shell (sh)
    sh -c "$command" > "$posix_file" 2>&1 || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" > "$fortsh_file" 2>&1 || true

    # Compare outputs
    if diff -q "$posix_file" "$fortsh_file" > /dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "$(cat "$posix_file")" "$(cat "$fortsh_file")"
    fi

    rm -f "$posix_file" "$fortsh_file"
}

# Helper function to compare exit codes
compare_posix_exit_code() {
    test_name="$1"
    command="$2"

    sh -c "$command" > /dev/null 2>&1
    posix_exit=$?

    "$FORTSH_BIN" -c "$command" > /dev/null 2>&1
    fortsh_exit=$?

    if [ "$posix_exit" -eq "$fortsh_exit" ]; then
        pass "$test_name"
    else
        fail "$test_name" "exit=$posix_exit" "exit=$fortsh_exit"
    fi
}

# Cleanup
cleanup() {
    rm -f /tmp/posix_comp_$$_* 2>/dev/null
    rm -f /tmp/posix_test_* 2>/dev/null
}
trap cleanup EXIT INT TERM

section "1. POSIX BASIC COMMANDS"

compare_posix_output "echo simple" "echo hello"
compare_posix_output "echo with args" "echo one two three"
compare_posix_output "printf basic" "printf 'test\n'"
compare_posix_output "printf with args" "printf '%s %d\n' hello 42"

section "2. POSIX VARIABLE EXPANSION"

compare_posix_output "simple variable" "VAR=test; echo \$VAR"
compare_posix_output "variable in quotes" 'VAR=test; echo "$VAR"'
compare_posix_output "multiple vars" "A=hello; B=world; echo \$A \$B"
compare_posix_output "undefined variable" "echo \$UNDEFINED_VAR_XYZ_987"

section "3. POSIX PARAMETER EXPANSION"

# Basic parameter expansion
compare_posix_output "default value" 'echo "${UNSET:-default}"'
compare_posix_output "assign default" 'UNSET=; echo "${UNSET:=assigned}"; echo $UNSET'
compare_posix_output "error if unset" 'echo "${VAR:+alternative}"'
compare_posix_output "string length" 'VAR=hello; echo "${#VAR}"'

# Prefix removal (# and ##)
compare_posix_output "remove shortest prefix" 'VAR=foo.bar.baz; echo "${VAR#*.}"'
compare_posix_output "remove longest prefix" 'VAR=foo.bar.baz; echo "${VAR##*.}"'
compare_posix_output "prefix no match" 'VAR=hello; echo "${VAR#x*}"'
compare_posix_output "prefix remove slash" 'VAR=/usr/local/bin; echo "${VAR#/*/}"'

# Suffix removal (% and %%)
compare_posix_output "remove shortest suffix" 'VAR=foo.bar.baz; echo "${VAR%.*}"'
compare_posix_output "remove longest suffix" 'VAR=foo.bar.baz; echo "${VAR%%.*}"'
compare_posix_output "suffix no match" 'VAR=hello; echo "${VAR%x*}"'
compare_posix_output "suffix remove extension" 'VAR=file.tar.gz; echo "${VAR%.gz}"'

section "4. POSIX COMMAND SUBSTITUTION"

compare_posix_output "backtick substitution" 'echo `echo test`'
compare_posix_output "dollar paren substitution" "echo \$(echo test)"
compare_posix_output "nested substitution" "echo \$(echo \$(echo nested))"

section "5. POSIX ARITHMETIC"

# POSIX arithmetic uses expr or $(( ))
compare_posix_output "expr addition" "expr 5 + 3"
compare_posix_output "expr multiplication" "expr 4 \* 3"
compare_posix_output "expr division" "expr 15 / 3"

section "6. POSIX REDIRECTION"

compare_posix_output "output redirect" "echo test > /tmp/posix_test_out; cat /tmp/posix_test_out"
compare_posix_output "append redirect" "echo line1 > /tmp/posix_test_app; echo line2 >> /tmp/posix_test_app; wc -l < /tmp/posix_test_app"
compare_posix_output "input redirect" "echo input > /tmp/posix_test_in; cat < /tmp/posix_test_in"
compare_posix_output "stderr redirect" "ls /nonexistent 2>&1 | grep -c 'cannot access\|No such\|not found'"

section "7. POSIX PIPELINES"

compare_posix_output "simple pipe" "echo hello | cat"
compare_posix_output "two-stage pipe" "echo test | cat | tr t T"
compare_posix_output "pipe with filter" "printf 'a\nb\nc\n' | grep b"

section "8. POSIX TEST COMMAND"

compare_posix_exit_code "test -f file" "touch /tmp/posix_test_file && test -f /tmp/posix_test_file"
compare_posix_exit_code "test -d directory" "test -d /tmp"
compare_posix_exit_code "test -n nonempty" "test -n 'hello'"
compare_posix_exit_code "test -z empty" "test -z ''"
compare_posix_exit_code "test string =" "test 'hello' = 'hello'"
compare_posix_exit_code "test string !=" "test 'hello' != 'world'"
compare_posix_exit_code "test number -eq" "test 5 -eq 5"
compare_posix_exit_code "test number -ne" "test 5 -ne 3"
compare_posix_exit_code "test number -gt" "test 5 -gt 3"
compare_posix_exit_code "test number -ge" "test 5 -ge 5"
compare_posix_exit_code "test number -lt" "test 3 -lt 5"
compare_posix_exit_code "test number -le" "test 3 -le 3"

section "9. POSIX CONDITIONALS"

compare_posix_output "if true" "if true; then echo yes; fi"
compare_posix_output "if false else" "if false; then echo no; else echo yes; fi"
compare_posix_output "if-elif-else" "X=2; if [ \$X -eq 1 ]; then echo one; elif [ \$X -eq 2 ]; then echo two; else echo other; fi"

section "10. POSIX LOOPS"

compare_posix_output "for loop" "for i in a b c; do echo \$i; done"
compare_posix_output "while loop" "i=3; while [ \$i -gt 0 ]; do echo \$i; i=\$((i - 1)); done"
compare_posix_output "until loop" "i=1; until [ \$i -gt 3 ]; do echo \$i; i=\$((i + 1)); done"

section "11. POSIX CASE STATEMENT"

compare_posix_output "case exact match" "x=2; case \$x in 1) echo one;; 2) echo two;; esac"
compare_posix_output "case pattern match" "x=hello; case \$x in h*) echo h_prefix;; esac"
compare_posix_output "case default" "x=z; case \$x in a) echo a;; b) echo b;; *) echo default;; esac"
compare_posix_output "case multiple patterns" "x=b; case \$x in a|b|c) echo abc;; *) echo other;; esac"

section "12. POSIX FUNCTIONS"

compare_posix_output "simple function" "func() { echo hello; }; func"
compare_posix_output "function with args" "func() { echo \$1 \$2; }; func foo bar"
compare_posix_output "function return" "func() { return 42; }; func; echo \$?"
compare_posix_output "function \$# args" "func() { echo \$#; }; func a b c"

section "13. POSIX SPECIAL VARIABLES"

compare_posix_output "\$? exit status" "true; echo \$?"
compare_posix_output "\$? after false" "false; echo \$?"
compare_posix_output "\$# argument count" "set -- a b c; echo \$#"
compare_posix_output "\$@ all arguments" "set -- a b c; echo \$@"
compare_posix_output "\$* all arguments" "set -- a b c; echo \$*"
compare_posix_output "\$0 script name" "echo \$0 | grep -c sh"

section "14. POSIX LOGICAL OPERATORS"

compare_posix_exit_code "true && true" "true && true"
compare_posix_exit_code "true && false" "true && false"
compare_posix_exit_code "false || true" "false || true"
compare_posix_exit_code "false || false" "false || false"
compare_posix_output "command && echo" "true && echo success"
compare_posix_output "command || echo" "false || echo fallback"
compare_posix_output "! negation" "! false && echo negated"

section "15. POSIX QUOTING"

compare_posix_output "single quote literal" "echo '\$VAR'"
compare_posix_output "double quote expand" 'VAR=test; echo "$VAR"'
compare_posix_output "escape in double" 'echo "test\$var"'
compare_posix_output "backslash escape" 'echo test\ word'

section "16. POSIX SUBSHELLS"

compare_posix_output "subshell grouping" "(echo a; echo b) | wc -l"
compare_posix_output "subshell var isolation" "(VAR=inner; echo \$VAR); echo \$VAR"

section "17. POSIX COMPOUND COMMANDS"

compare_posix_output "command grouping {}" "{ echo a; echo b; } | wc -l"
compare_posix_output "command list ;" "echo a; echo b"

section "18. POSIX HERE DOCUMENTS"

compare_posix_output "simple heredoc" "cat <<EOF
line1
line2
EOF"

compare_posix_output "heredoc with vars" "VAR=test; cat <<EOF
value=\$VAR
EOF"

compare_posix_output "quoted heredoc" "cat <<'EOF'
\$VAR
EOF"

section "19. POSIX WORD EXPANSION ORDER"

# POSIX specifies: tilde, parameter, command subst, arithmetic, field splitting, pathname, quote removal
compare_posix_output "expansion order" "VAR='a b'; echo \$VAR"
compare_posix_output "quoted expansion" 'VAR="a b"; echo "$VAR"'

section "20. POSIX PATHNAME EXPANSION (GLOBBING)"

# Setup test files
mkdir -p /tmp/posix_test_glob
touch /tmp/posix_test_glob/a.txt /tmp/posix_test_glob/b.txt /tmp/posix_test_glob/c.dat

compare_posix_output "glob * pattern" "ls /tmp/posix_test_glob/*.txt 2>/dev/null | wc -l"
compare_posix_output "glob ? pattern" "ls /tmp/posix_test_glob/?.txt 2>/dev/null | wc -l"
compare_posix_output "glob [abc] pattern" "ls /tmp/posix_test_glob/[ab].txt 2>/dev/null | wc -l"

section "21. POSIX FIELD SPLITTING (IFS)"

compare_posix_output "default IFS" "VAR='a b c'; set -- \$VAR; echo \$#"
compare_posix_output "custom IFS" "IFS=:; VAR='a:b:c'; set -- \$VAR; echo \$1"

section "22. POSIX EXIT STATUS"

compare_posix_exit_code "true exit status" "true"
compare_posix_exit_code "false exit status" "false"
compare_posix_exit_code "command not found" "nonexistent_command_xyz 2>/dev/null"
compare_posix_exit_code "return from function" "func() { return 3; }; func"

section "23. POSIX SET BUILTIN"

compare_posix_output "set positional" "set -- a b c; echo \$1 \$2 \$3"
compare_posix_output "set shift" "set -- a b c; shift; echo \$1"
compare_posix_output "set shift n" "set -- a b c d; shift 2; echo \$1"

section "24. POSIX EXPORT"

compare_posix_output "export variable" "export VAR=test; sh -c 'echo \$VAR'"

section "25. POSIX READONLY"

compare_posix_exit_code "readonly assignment" "readonly VAR=test; VAR=new 2>/dev/null"

# Summary
section "SUMMARY"
printf "\n"
printf "==========================================\n"
printf "POSIX COMPLIANCE TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "${YELLOW}Skipped:${NC} %d\n" "$SKIPPED"
printf "Total:   %d\n" "$((PASSED + FAILED + SKIPPED))"
printf "==========================================\n"

if [ $((PASSED + FAILED)) -gt 0 ]; then
    PASS_RATE=$((PASSED * 100 / (PASSED + FAILED)))
    printf "Pass rate: %d%%\n" "$PASS_RATE"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL POSIX COMPLIANCE TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
