#!/bin/sh
# =====================================
# POSIX Compliance Gap Coverage Test Suite
# =====================================
# This test file specifically targets gaps in the existing 4 POSIX test files
# by comparing against IEEE Std 1003.1-2017 (POSIX.1-2017)
#
# Focus areas:
# - Here-document variations (<<- tab stripping)
# - Additional redirection operators (<>)
# - Complex IFS field splitting scenarios
# - Nested and complex parameter expansions
# - Command name resolution order
# - Complex quoting and escaping
# - Pipeline exit status rules
# - Complex arithmetic edge cases
# - Locale and environment variables
# - Builtin command edge cases
# - Pathname expansion edge cases
# - Function scope and recursion edge cases
# - Signal handling edge cases

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[posix-gaps]"
CURRENT_SECTION=""
TEST_NUM=0

PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS_LIST=""

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
    TEST_NUM=$((TEST_NUM + 1))
    printf "${GREEN}✓ PASS${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s\n" "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    TEST_NUM=$((TEST_NUM + 1))
    TEST_ID="${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}"
    printf "${RED}✗ FAIL${NC} ${TEST_ID}: %s\n" "$1"
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}  ${TEST_ID}: $1\n"
    if [ -n "$2" ]; then
        printf "  posix:  %s\n" "$2"
    fi
    if [ -n "$3" ]; then
        printf "  fortsh: %s\n" "$3"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    TEST_NUM=$((TEST_NUM + 1))
    printf "${YELLOW}⊘ SKIP${NC} ${TEST_PREFIX} ${CURRENT_SECTION}.${TEST_NUM}: %s - %s\n" "$1" "$2"
    SKIPPED=$((SKIPPED + 1))
}

section() {
    # Extract section number from header like "91. HERE DOCUMENT VARIATIONS"
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n"
    printf "${BLUE}==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================${NC}\n"
}

# Normalize shell error messages by stripping shell name and "line N: " prefix
normalize_output() {
    sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'
}

# Helper function to run command in both shells and compare
compare_posix_output() {
    test_name="$1"
    command="$2"
    posix_file="/tmp/posix_gaps_$$_posix"
    fortsh_file="/tmp/posix_gaps_$$_fortsh"

    # Run in POSIX shell (sh)
    bash -c "$command" 2>&1 | normalize_output > "$posix_file" || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" 2>&1 | normalize_output > "$fortsh_file" || true

    # Compare outputs
    if diff -q "$posix_file" "$fortsh_file" > /dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name" "$(cat "$posix_file")" "$(cat "$fortsh_file")"
    fi

    rm -f "$posix_file" "$fortsh_file"
}

# Normalize shell error messages by stripping shell name and "line N: " prefix
# POSIX doesn't mandate error message format, so we normalize for comparison
normalize_error() {
    echo "$1" | sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'
}

# Compare error output, normalizing line number differences
compare_posix_error() {
    test_name="$1"
    command="$2"
    posix_file="/tmp/posix_gaps_$$_posix"
    fortsh_file="/tmp/posix_gaps_$$_fortsh"

    # Run in POSIX shell (sh)
    bash -c "$command" > "$posix_file" 2>&1 || true

    # Run in fortsh
    "$FORTSH_BIN" -c "$command" > "$fortsh_file" 2>&1 || true

    # Normalize error messages before comparison
    posix_norm=$(normalize_error "$(cat "$posix_file")")
    fortsh_norm=$(normalize_error "$(cat "$fortsh_file")")

    if [ "$posix_norm" = "$fortsh_norm" ]; then
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

    bash -c "$command" > /dev/null 2>&1
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
    rm -f /tmp/posix_gaps_$$_* 2>/dev/null
    rm -rf /tmp/posix_gaps_test_* 2>/dev/null
}
trap cleanup EXIT INT TERM

section "91. HERE-DOCUMENT TAB STRIPPING (<<-)"

compare_posix_output "heredoc <<- strips leading tabs" "cat <<-EOF
	line1
		line2
	line3
EOF"

compare_posix_output "heredoc <<- mixed spaces and tabs" "cat <<-EOF
	tab_line
    space_line
EOF"

compare_posix_output "heredoc <<- with variables" "VAR=test; cat <<-EOF
	value=\$VAR
	end
EOF"

compare_posix_output "heredoc <<- quoted delimiter" "cat <<-'EOF'
	\$VAR
	literal
EOF"

section "92. REDIRECTION OPERATOR <> (READ/WRITE)"

compare_posix_exit_code "redirect <> creates file" "echo test <> /tmp/posix_gaps_rw_$$; test -f /tmp/posix_gaps_rw_$$; rm -f /tmp/posix_gaps_rw_$$"
compare_posix_exit_code "redirect <> opens existing" "echo data > /tmp/posix_gaps_rw2_$$; cat <> /tmp/posix_gaps_rw2_$$ 2>/dev/null; rm -f /tmp/posix_gaps_rw2_$$"

section "93. COMPLEX IFS FIELD SPLITTING"

# Mixed IFS characters (whitespace + non-whitespace)
compare_posix_output "IFS mixed ws and non-ws" "IFS=': \t'; VAR='a:b c:d'; set -- \$VAR; echo \$# \$1 \$2 \$3 \$4"
compare_posix_output "IFS multiple delimiters" "IFS=',:'; VAR='a,b:c,d'; set -- \$VAR; echo \$#"
compare_posix_output "IFS trailing delimiters" "IFS=:; VAR='a:b:c:'; set -- \$VAR; echo \$#"
compare_posix_output "IFS leading and trailing" "IFS=:; VAR=':a:b:'; set -- \$VAR; echo \$# \$1 \$2"
compare_posix_output "IFS consecutive delimiters" "IFS=:; VAR='a::b'; set -- \$VAR; echo \$# \$1 \$2 \$3"
compare_posix_output "IFS whitespace collapsing" "IFS=' '; VAR='a  b   c'; set -- \$VAR; echo \$#"
compare_posix_output "IFS null splits nothing" "IFS=''; VAR='a b c'; set -- \$VAR; echo \$#"

section "94. NESTED PARAMETER EXPANSION"

compare_posix_output "nested default expansion" "unset A; B=inner; echo \${A:-\${B}}"
compare_posix_output "nested length expansion" "VAR=hello; echo \${#VAR}"
compare_posix_output "nested pattern removal" "VAR=/usr/local/bin; echo \${VAR#\${VAR%/*}}"
compare_posix_output "multiple parameter expansions" "A=foo; B=bar; echo \${A}\${B}"
compare_posix_output "nested with quotes" "A='a b'; echo \"\${A}\""

section "95. COMMAND NAME RESOLUTION ORDER"

# Test: function > builtin > external command
compare_posix_output "function overrides echo" "echo() { printf 'function\n'; }; echo test | grep -c function"
compare_posix_output "command -v finds function" "func() { :; }; command -v func | grep -c func"
compare_posix_output "command bypasses function" "echo() { printf 'func\n'; }; command echo test"
compare_posix_output "unset function reveals builtin" "echo() { printf 'f\n'; }; unset -f echo; echo test | grep -c test"

section "96. COMPLEX QUOTING AND ESCAPING"

compare_posix_output "backslash in double quotes" 'echo "test\\nword"'
compare_posix_output "dollar in double quotes" 'echo "cost: \$5"'
compare_posix_output "backtick in double quotes" 'echo "date: \`date +%Y\`" | grep -c date'
compare_posix_output "mixed quoting" "echo 'single'\"double\"'single'"
compare_posix_output "empty quotes concatenation" "echo ''test''"
compare_posix_output "quote removal" 'VAR="\"test\""; echo $VAR'
compare_posix_output "backslash newline in string" "echo 'line1\
line2' | wc -l"

section "97. PIPELINE EXIT STATUS"

compare_posix_exit_code "pipeline last command status" "true | true | false"
compare_posix_exit_code "pipeline first fails" "false | true | true"
compare_posix_exit_code "pipeline middle fails" "true | false | true"
compare_posix_output "PIPESTATUS concept" "false | true | true; echo \$?"

section "98. COMPLEX ARITHMETIC EDGE CASES"

compare_posix_output "arithmetic negative numbers" "echo \$((-5 * -3))"
compare_posix_output "arithmetic large numbers" "echo \$((999999 + 1))"
compare_posix_output "arithmetic modulo negative" "echo \$((-17 % 5))"
compare_posix_output "arithmetic nested parens" "echo \$(((2 + 3) * (4 + 5)))"
compare_posix_output "arithmetic comparison chain" "echo \$((5 > 3 && 10 > 8))"
compare_posix_output "arithmetic unary minus" "X=5; echo \$((-X))"
compare_posix_output "arithmetic unary plus" "X=5; echo \$((+X))"
compare_posix_output "arithmetic octal numbers" "echo \$((010))"
compare_posix_output "arithmetic hex numbers" "echo \$((0x10))"
compare_posix_exit_code "arithmetic division by zero" "echo \$((5 / 0)) 2>/dev/null"

section "99. PATHNAME EXPANSION EDGE CASES"

mkdir -p /tmp/posix_gaps_test_glob
touch "/tmp/posix_gaps_test_glob/file1.txt"
touch "/tmp/posix_gaps_test_glob/file2.txt"
touch "/tmp/posix_gaps_test_glob/file[3].txt"
touch "/tmp/posix_gaps_test_glob/-file.txt"
mkdir -p "/tmp/posix_gaps_test_glob/.hidden"

compare_posix_output "glob bracket literal" "ls /tmp/posix_gaps_test_glob/file[[]3].txt 2>/dev/null | wc -l"
compare_posix_output "glob dash in bracket" "ls /tmp/posix_gaps_test_glob/[-a-z]file.txt 2>/dev/null | wc -l"
compare_posix_output "glob no match returns literal" "echo /tmp/posix_gaps_test_glob/*.xyz | grep -c '\\*'"
compare_posix_output "glob hidden dirs" "ls -d /tmp/posix_gaps_test_glob/.* 2>/dev/null | grep -c hidden"
compare_posix_output "glob character class digit" "touch /tmp/posix_gaps_test_glob/f1.txt; ls /tmp/posix_gaps_test_glob/f[[:digit:]].txt 2>/dev/null | wc -l"

rm -rf /tmp/posix_gaps_test_glob

section "100. FUNCTION SCOPE AND RECURSION EDGE CASES"

compare_posix_output "function local scope via subshell" "f() { (X=inner; echo \$X); }; X=outer; f; echo \$X"
compare_posix_output "function positional params" "f() { echo \$1 \$2; }; set -- a b; f x y"
compare_posix_output "function preserves positional" "f() { echo \$1; }; set -- a b; f x; echo \$1"
compare_posix_output "nested function calls" "a() { b; }; b() { c; }; c() { echo deep; }; a"
compare_posix_output "function return in subshell" "f() { (return 5); echo \$?; }; f"
compare_posix_output "recursive factorial" "fact() { if [ \$1 -le 1 ]; then echo 1; else local r=\$(fact \$((\$1-1)) 2>/dev/null || fact \$((\$1-1))); echo \$((\$1 * r)); fi; }; fact 4"

section "101. EXIT STATUS IN COMPOUND COMMANDS"

compare_posix_exit_code "subshell exit status" "(exit 42); echo \$?"
compare_posix_exit_code "brace group exit status" "{ exit 42; }; echo \$?"
compare_posix_exit_code "if statement exit status" "if true; then true; fi; echo \$?"
compare_posix_exit_code "for loop exit status" "for i in 1; do false; done; echo \$?"
compare_posix_exit_code "while loop exit status" "while false; do :; done; echo \$?"
compare_posix_exit_code "case exit status" "case x in x) false;; esac; echo \$?"

section "102. SET BUILTIN EDGE CASES"

compare_posix_output "set -- clears positionals" "set -- a b; set --; echo \$#"
compare_posix_error "set -- with empty" "set -- ''; echo \$# |\$1|"
compare_posix_output "set -- with spaces" "set -- 'a b' 'c d'; echo \$1"
compare_posix_output "set without args shows vars" "X=1; set | grep -c '^X='"
compare_posix_output "set -o lists options" "set -o 2>&1 | wc -l"

section "103. SHIFT EDGE CASES"

compare_posix_output "shift with count" "set -- a b c d e; shift 3; echo \$1"
compare_posix_exit_code "shift too many" "set -- a b; shift 5 2>/dev/null"
compare_posix_output "shift zero" "set -- a b c; shift 0; echo \$#"
compare_posix_output "shift all" "set -- a b c; shift 3; echo \$#"
compare_posix_exit_code "shift with no args" "set --; shift 2>/dev/null"

section "104. EVAL EDGE CASES"

compare_posix_output "eval with semicolons" "eval 'echo a; echo b' | wc -l"
compare_posix_output "eval with pipes" "eval 'echo test | cat'"
compare_posix_output "eval with redirects" "eval 'echo test > /tmp/posix_gaps_eval_$$'; cat /tmp/posix_gaps_eval_$$; rm -f /tmp/posix_gaps_eval_$$"
compare_posix_output "eval double expansion" "VAR='echo \$HOME'; eval \$VAR | grep -c /"
compare_posix_output "eval empty string" "eval ''; echo ok"
compare_posix_output "nested eval" "eval eval echo nested"

section "105. READONLY AND UNSET INTERACTIONS"

compare_posix_exit_code "readonly then unset fails" "readonly X=1; unset X 2>/dev/null"
compare_posix_exit_code "export readonly" "readonly X=1; export X; sh -c 'echo \$X' | grep -c 1"
compare_posix_output "readonly in subshell" "(readonly Y=2; echo \$Y); readonly | grep -c Y || echo 0"

section "106. RETURN BUILTIN EDGE CASES"

compare_posix_output "return without function" "return 2>/dev/null || echo ok"
compare_posix_output "return value preserved" "f() { return 42; }; f; echo \$?"
compare_posix_output "return in sourced script" "echo 'return 7' > /tmp/posix_gaps_source_$$; . /tmp/posix_gaps_source_$$ 2>/dev/null || echo \$?; rm -f /tmp/posix_gaps_source_$$"

section "107. DOT (.) BUILTIN EDGE CASES"

compare_posix_output "source with PATH search" "echo 'echo sourced' > /tmp/posix_gaps_dot_$$; PATH=/tmp:\$PATH; . posix_gaps_dot_$$ 2>/dev/null || echo 'not found'; rm -f /tmp/posix_gaps_dot_$$"
compare_posix_exit_code "source nonexistent" ". /tmp/posix_gaps_nonexistent_$$ 2>/dev/null"
compare_posix_output "source preserves variables" "echo 'A=from_source' > /tmp/posix_gaps_dot2_$$; . /tmp/posix_gaps_dot2_$$; echo \$A; rm -f /tmp/posix_gaps_dot2_$$"

section "108. BREAK AND CONTINUE EDGE CASES"

compare_posix_output "break with level 0" "for i in 1 2; do break 0 2>/dev/null || break; echo \$i; done || echo ok"
compare_posix_output "break level too high" "for i in 1 2; do break 10 2>/dev/null || break; echo \$i; done || echo done"
compare_posix_output "continue with level" "for i in 1 2; do for j in a b; do continue 2 2>/dev/null || continue; echo \$i\$j; done; done || echo ok"
compare_posix_output "break outside loop" "break 2>/dev/null || echo ok"
compare_posix_output "continue outside loop" "continue 2>/dev/null || echo ok"

section "109. CASE STATEMENT EDGE CASES"

compare_posix_output "case empty pattern" "x=''; case \$x in '') echo empty;; esac"
compare_posix_output "case no match" "x=z; case \$x in a) echo a;; b) echo b;; esac; echo ok"
compare_posix_output "case with quotes" "x='a b'; case \$x in 'a b') echo match;; esac"
compare_posix_output "case glob vs literal" "x='*'; case \$x in '*') echo literal;; esac"
compare_posix_output "case bracket range" "x=b; case \$x in [a-c]) echo range;; esac"
compare_posix_output "case multiple patterns order" "x=a; case \$x in a|b) echo first;; a) echo second;; esac"
compare_posix_output "case with variable pattern" "P='a*'; x=abc; case \$x in \$P) echo var_pattern;; esac"

section "110. FOR LOOP EDGE CASES"

compare_posix_output "for empty word list" "for i in; do echo \$i; done; echo empty"
compare_posix_output "for single item" "for i in one; do echo \$i; done"
compare_posix_output "for with glob expansion" "touch /tmp/posix_gaps_for{1,2,3}_$$.txt 2>/dev/null; for f in /tmp/posix_gaps_for*_$$.txt; do test -f \$f && echo yes; done | head -1; rm -f /tmp/posix_gaps_for*_$$.txt"
compare_posix_output "for preserves IFS" "IFS=:; for i in a b c; do echo \$i; done; echo \$IFS | od -A n -t x1 | grep -c 3a"

section "111. WHILE AND UNTIL EDGE CASES"

compare_posix_output "while true with break" "i=0; while true; do i=\$((i+1)); test \$i -eq 3 && break; done; echo \$i"
compare_posix_output "until false with break" "i=0; until false; do i=\$((i+1)); test \$i -eq 3 && break; done; echo \$i"
compare_posix_output "while with exit status" "i=5; while [ \$i -gt 0 ]; do i=\$((i-1)); done; echo \$?"
compare_posix_output "until with complex condition" "i=0; until [ \$i -gt 3 ] && [ \$i -lt 10 ]; do i=\$((i+1)); done; echo \$i"

section "112. SUBSHELL VARIABLE ISOLATION"

compare_posix_output "subshell doesnt modify parent" "(X=inner); echo \${X:-unset}"
compare_posix_output "subshell inherits variables" "X=outer; (echo \$X)"
compare_posix_output "nested subshells" "X=1; (X=2; (X=3; echo \$X); echo \$X); echo \$X"
compare_posix_output "subshell with exports" "export X=exp; (X=inner; echo \$X); echo \$X"

section "113. BRACE GROUP SCOPING"

compare_posix_output "brace group modifies parent" "X=1; { X=2; }; echo \$X"
compare_posix_output "brace group with redirects" "{ echo a; echo b; } | wc -l"
compare_posix_output "nested brace groups" "X=1; { { X=2; }; echo \$X; }; echo \$X"

section "114. ALIAS EDGE CASES"

compare_posix_output "alias with args" "alias ll='ls -l'; alias ll | grep -c 'ls -l'"
compare_posix_output "alias recursive prevention" "alias ls='ls -a'; command ls /tmp >/dev/null; echo \$?"
compare_posix_output "unalias nonexistent" "unalias nonexistent_alias_$$ 2>/dev/null || echo ok"
compare_posix_output "alias name same as builtin" "alias echo='printf'; unalias echo; command -v echo | grep -c echo"

section "115. TEST COMMAND COMPLEX EXPRESSIONS"

compare_posix_exit_code "test complex AND/OR" "test 5 -gt 3 -a \( 10 -lt 20 -o 1 -eq 2 \)"
compare_posix_exit_code "test negation precedence" "test ! 5 -gt 10"
compare_posix_exit_code "test string empty" "test -z ''"
compare_posix_exit_code "test string nonempty" "test -n 'x'"
compare_posix_exit_code "test string unary" "test 'nonempty'"

section "116. SPECIAL PARAMETER EDGE CASES"

compare_posix_output "\$@ with IFS" "IFS=:; set -- a b c; echo \"\$*\""
compare_posix_output "\$* vs \$@ unquoted" "set -- a b c; for x in \$*; do echo \$x; done | wc -l"
compare_posix_output "\$@ quoted iteration" "set -- 'a b' 'c d'; for x in \"\$@\"; do echo \$x; done | wc -l"
compare_posix_output "\$# after shift" "set -- a b c; shift; echo \$#"
compare_posix_output "\$- shows options" "echo \$- | grep -c '[a-z]'"
compare_posix_output "\$\$ is numeric" "echo \$\$ | grep -c '^[0-9]*\$'"
compare_posix_output "\$! after background" "sleep 0.1 & echo \$! | grep -c '^[0-9]*\$'"

section "117. TILDE EXPANSION EDGE CASES"

compare_posix_output "tilde in assignment" "VAR=~/test; echo \$VAR | grep -c '^/'"
compare_posix_output "tilde in middle no expand" "echo a~b | grep -c '~'"
compare_posix_output "tilde in quotes no expand" "echo '~' | grep -c '~'"

section "118. COMMAND SUBSTITUTION EDGE CASES"

compare_posix_output "command subst nested" "echo \$(echo \$(echo nested))"
compare_posix_output "command subst with pipes" "echo \$(echo a | cat)"
compare_posix_output "command subst multiline" "result=\$(echo a; echo b); echo \"\$result\" | wc -l"
compare_posix_output "command subst empty" "x=\$(true); echo \"|\$x|\""
compare_posix_output "backtick vs dollar-paren" "a=\`echo test\`; b=\$(echo test); test \"\$a\" = \"\$b\" && echo same"

section "119. REDIRECT EDGE CASES"

compare_posix_output "redirect order matters" "echo test 2>&1 >/dev/null | wc -l"
compare_posix_output "redirect to same fd" "echo test >&1 2>&1"
compare_posix_output "redirect append" "echo a > /tmp/posix_gaps_redir_$$; echo b >> /tmp/posix_gaps_redir_$$; wc -l < /tmp/posix_gaps_redir_$$; rm -f /tmp/posix_gaps_redir_$$"
compare_posix_output "redirect here-string alternative" "cat <<EOF
test
EOF"
compare_posix_output "redirect duplicate stdin" "cat <&0 <<EOF
input
EOF"

section "120. WAIT BUILTIN EDGE CASES"

compare_posix_exit_code "wait for background job" "sleep 0.1 & pid=\$!; wait \$pid"
compare_posix_exit_code "wait all jobs" "sleep 0.1 & sleep 0.1 & wait"
compare_posix_exit_code "wait nonexistent PID" "wait 9999999 2>/dev/null"
compare_posix_output "wait preserves exit status" "sh -c 'exit 42' & pid=\$!; wait \$pid; echo \$?"

section "121. GETOPTS COMPREHENSIVE"

compare_posix_output "getopts basic" "set -- -a test; getopts 'a:' opt; echo \$opt"
compare_posix_output "getopts OPTARG" "set -- -a value; getopts 'a:' opt; echo \$OPTARG"
compare_posix_output "getopts OPTIND" "set -- -a -b; getopts 'ab' opt; echo \$OPTIND"
compare_posix_output "getopts invalid option" "set -- -z; getopts 'ab' opt 2>/dev/null; echo \$opt | grep -c '?'"

section "122. UMASK EDGE CASES"

compare_posix_output "umask get" "umask | grep -c '^[0-9]*\$'"
compare_posix_output "umask set and get" "old=\$(umask); umask 022; umask; umask \$old | head -1"

section "123. HASH BUILTIN EDGE CASES"

compare_posix_exit_code "hash command" "hash echo 2>/dev/null"
compare_posix_exit_code "hash -r clears" "hash -r"
compare_posix_exit_code "hash nonexistent" "hash nonexistent_cmd_$$ 2>/dev/null"

section "124. TYPE BUILTIN EDGE CASES"

compare_posix_output "type builtin" "type echo | grep -ci 'builtin\\|built-in\\|shell builtin'"
compare_posix_output "type function" "f() { :; }; type f | grep -c function"
compare_posix_output "type external" "type cat | grep -c '/'"
compare_posix_exit_code "type nonexistent" "type nonexistent_$$ 2>/dev/null"

section "125. TIMES BUILTIN"

compare_posix_output "times output format" "times | wc -l"
compare_posix_exit_code "times exit status" "times >/dev/null"

section "126. TRAP SIGNAL EDGE CASES"

compare_posix_output "trap with signal number" "trap 'echo sig' 15; trap | grep -c 15"
compare_posix_output "trap with multiple signals" "trap 'echo multi' INT TERM; trap | grep -c 'echo multi'"
compare_posix_output "trap ignore signal" "trap '' INT; trap | grep INT | grep -c ''"

section "127. EMPTY AND WHITESPACE EDGE CASES"

compare_posix_output "empty command in list" ": ; echo ok"
compare_posix_output "whitespace only" "   ; echo ok"
compare_posix_output "multiple empty commands" ": ; : ; echo ok"
compare_posix_output "empty string as command" "'' 2>/dev/null || echo ok"

section "128. COMPLEX PIPELINES"

compare_posix_output "five stage pipeline" "echo test | cat | cat | cat | cat"
compare_posix_exit_code "pipeline with negation" "! false | false"
compare_posix_output "pipeline with subshell" "(echo a; echo b) | wc -l"
compare_posix_output "pipeline with brace group" "{ echo x; echo y; } | wc -l"

section "129. EXIT BUILTIN EDGE CASES"

compare_posix_exit_code "exit with status" "sh -c 'exit 42'"
compare_posix_exit_code "exit in subshell" "(exit 7); echo \$?"
compare_posix_exit_code "exit in function" "f() { exit 13; }; sh -c '. /dev/stdin <<EOF
f() { exit 13; }
f
EOF'"

section "130. EXPORT EDGE CASES"

compare_posix_output "export without value" "export VAR; sh -c 'echo \${VAR:-unset}'"
compare_posix_output "export with value" "export VAR=value; sh -c 'echo \$VAR'"
compare_posix_output "export multiple" "export A=1 B=2; sh -c 'echo \$A \$B'"
compare_posix_output "export readonly" "readonly X=ro; export X; sh -c 'echo \$X'"

section "131. VARIABLE SCOPE EDGE CASES"

compare_posix_output "var in subshell lost" 'X=1; (X=2); echo $X'
compare_posix_output "var in brace group kept" 'X=1; { X=2; }; echo $X'
compare_posix_output "env var in subshell" 'export X=1; (echo $X)'
compare_posix_output "command prefix assignment" 'X=val sh -c "echo \$X"'

section "132. FUNCTION VARIABLE SCOPE"

compare_posix_output "global in function" 'X=global; f() { echo $X; }; f'
compare_posix_output "function modifies global" 'X=1; f() { X=2; }; f; echo $X'
compare_posix_output "local shadows global" 'X=1; f() { local X=2; echo $X; }; f; echo $X'

section "133. ARITHMETIC EDGE CASES"

compare_posix_output "arith with spaces" 'echo $(( 1 + 2 ))'
compare_posix_output "arith nested parens" 'echo $(( (1 + 2) * 3 ))'
compare_posix_output "arith division" 'echo $((10 / 3))'
compare_posix_output "arith modulo" 'echo $((10 % 3))'
compare_posix_output "arith negative" 'echo $((-5 + 3))'

section "134. COMMAND SUBSTITUTION EDGE CASES"

compare_posix_output "nested cmd sub" 'echo $(echo $(echo deep))'
compare_posix_output "cmd sub with quotes" 'echo "$(echo "hello world")"'
compare_posix_output "cmd sub trailing newline" 'x=$(printf "hi\n"); echo "[$x]"'
compare_posix_output "backtick substitution" 'echo `echo hello`'

section "135. REDIRECTION EDGE CASES"

compare_posix_output "redirect in loop" 'for i in 1 2 3; do echo $i; done > /tmp/redir_test_$$; cat /tmp/redir_test_$$; rm /tmp/redir_test_$$'
compare_posix_output "append multiple" 'echo a >> /tmp/app_test_$$; echo b >> /tmp/app_test_$$; cat /tmp/app_test_$$; rm /tmp/app_test_$$'
compare_posix_output "stderr to file" 'ls /nonexistent 2>/tmp/err_test_$$ || cat /tmp/err_test_$$ | wc -l; rm -f /tmp/err_test_$$'

section "136. HERE-DOC EDGE CASES"

compare_posix_output "heredoc basic" 'cat <<EOF
hello
EOF'
compare_posix_output "heredoc with var" 'X=world; cat <<EOF
hello $X
EOF'
compare_posix_output "heredoc quoted delim" "cat <<'EOF'
\$notvar
EOF"

section "137. WORD SPLITTING EDGE CASES"

compare_posix_output "IFS colon split" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "IFS multiple chars" 'IFS=":;"; x="a:b;c"; set -- $x; echo $#'
compare_posix_output "empty IFS no split" 'IFS=""; x="a b c"; set -- $x; echo $#'
compare_posix_output "default IFS" 'unset IFS; x="a   b"; set -- $x; echo $#'

section "138. GLOB EDGE CASES"

compare_posix_output "glob no match" 'echo /nonexistent_dir_xyz_$$/* 2>/dev/null | grep -c nonexistent || echo "0 or pattern"'
compare_posix_output "set -f disables glob" 'set -f; echo *; set +f'
compare_posix_output "quoted glob literal" 'echo "*"'

section "139. SIGNAL EDGE CASES"

compare_posix_output "trap list" 'trap "echo x" INT; trap | grep -c INT || echo 0'
compare_posix_output "trap reset" 'trap "echo x" INT; trap - INT; trap | grep -c INT || echo 0'
compare_posix_output "trap EXIT runs" 'sh -c "trap echo_exit EXIT; exit 0" 2>/dev/null; echo done'

section "140. MISCELLANEOUS EDGE CASES"

compare_posix_output "empty for list" 'for x in; do echo x; done; echo done'
compare_posix_output "case no match" 'case x in y) echo y;; esac; echo done'
compare_posix_output "if false branch" 'if false; then echo yes; else echo no; fi'
compare_posix_output "elif chain" 'if false; then echo 1; elif false; then echo 2; else echo 3; fi'
compare_posix_output "nested if" 'if true; then if true; then echo nested; fi; fi'

# Summary
printf "\n"
printf "==========================================\n"
printf "GAP COVERAGE POSIX COMPLIANCE TEST RESULTS ${TEST_PREFIX}\n"
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

if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n"
    printf "%b" "$FAILED_TESTS_LIST"
    printf "==========================================\n"
fi

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN}ALL GAP COVERAGE TESTS PASSED!${NC} ✓\n"
    exit 0
else
    printf "${RED}SOME TESTS FAILED${NC} ✗\n"
    exit 1
fi
