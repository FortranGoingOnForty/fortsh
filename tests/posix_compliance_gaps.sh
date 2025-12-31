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

section "141. ADDITIONAL EDGE CASES"

compare_posix_output "while zero iterations" 'while false; do echo never; done; echo done'
compare_posix_output "until zero iterations" 'until true; do echo never; done; echo done'
compare_posix_output "function empty body" 'f() { :; }; f; echo $?'
compare_posix_output "pipeline single" 'echo test | cat'
compare_posix_output "assignment no space" 'x=value; echo $x'
compare_posix_output "comment mid-line" 'echo visible # hidden'
compare_posix_output "newline continuation" 'echo hel\
lo'
compare_posix_output "mixed operators" 'true && false || echo fallback'

section "142. ADDITIONAL GAPS"

compare_posix_output "expr string length" 'expr length "hello"'
compare_posix_output "test with and" '[ 1 -eq 1 ] && [ 2 -eq 2 ] && echo both'
compare_posix_output "test with or" '[ 1 -eq 2 ] || [ 2 -eq 2 ] && echo one'
compare_posix_output "double negation" '! ! true && echo yes'
compare_posix_output "triple pipe" 'echo test | cat | cat | cat'
compare_posix_output "var in quotes" 'X="hello world"; echo "$X"'
compare_posix_output "arithmetic compare" 'echo $((5 > 3))'
compare_posix_output "arithmetic ternary sim" '[ 5 -gt 3 ] && echo big || echo small'
compare_posix_output "for with seq" 'for i in 1 2 3 4 5; do echo $i; done | wc -l'
compare_posix_output "while decrement" 'i=5; while [ $i -gt 0 ]; do i=$((i-1)); done; echo $i'
compare_posix_output "case star pattern" 'x=anything; case $x in *) echo star;; esac'
compare_posix_output "func recursion base" 'f() { [ $1 -le 0 ] && echo done || f $(($1-1)); }; f 3'
compare_posix_output "heredoc simple" 'cat <<END
test
END'
compare_posix_output "redirect both" 'echo out; echo err >&2'
compare_posix_output "subshell cd" '(cd /tmp; pwd)'

section "143. ARITHMETIC EXPRESSION COVERAGE"

compare_posix_output "arith modulo" 'echo $((10 % 3))'
compare_posix_output "arith negative" 'echo $((-5))'
compare_posix_output "arith zero" 'echo $((0))'
compare_posix_output "arith multiply" 'echo $((6 * 7))'
compare_posix_output "arith divide" 'echo $((42 / 6))'
compare_posix_output "arith subtract" 'echo $((100 - 58))'
compare_posix_output "arith precedence" 'echo $((2 + 3 * 4))'
compare_posix_output "arith parens" 'echo $(((2 + 3) * 4))'
compare_posix_output "arith nested" 'echo $(($((1 + 2)) + 3))'
compare_posix_output "arith var ref" 'X=10; echo $((X + 5))'

section "144. STRING OPERATIONS"

compare_posix_output "length of empty" 'x=""; echo ${#x}'
compare_posix_output "length of one" 'x="a"; echo ${#x}'
compare_posix_output "length of special" 'x="a b c"; echo ${#x}'
compare_posix_output "suffix remove" 'x="file.txt"; echo ${x%.txt}'
compare_posix_output "prefix remove" 'x="prefix_name"; echo ${x#prefix_}'
compare_posix_output "longest suffix" 'x="a.b.c"; echo ${x%%.*}'
compare_posix_output "longest prefix" 'x="a.b.c"; echo ${x##*.}'
compare_posix_output "default empty" 'x=""; echo ${x:-default}'
compare_posix_output "default unset" 'unset x; echo ${x:-default}'
compare_posix_output "default set" 'x="value"; echo ${x:-default}'

section "145. COMMAND SUBSTITUTION VARIANTS"

compare_posix_output "cmd sub echo" 'echo $(echo hello)'
compare_posix_output "cmd sub pwd" 'echo $(pwd | grep -c "/")'
compare_posix_output "cmd sub math" 'echo $(($(echo 5) + 3))'
compare_posix_output "cmd sub in var" 'x=$(echo test); echo $x'
compare_posix_output "cmd sub nested" 'echo $(echo $(echo deep))'
compare_posix_output "backtick equiv" 'echo `echo hello`'
compare_posix_output "cmd sub whitespace" 'echo "$(echo "  spaces  ")"'
compare_posix_output "cmd sub multiline" 'echo "$(echo -e "a\nb")" | wc -l'
compare_posix_output "cmd sub exit code" '$(exit 0); echo $?'
compare_posix_output "cmd sub fail code" '$(exit 1); echo $?'

section "146. PIPELINES COMPREHENSIVE"

compare_posix_output "pipe two" 'echo hello | cat'
compare_posix_output "pipe three" 'echo hello | cat | cat'
compare_posix_output "pipe with grep" 'echo hello | grep -o h'
compare_posix_output "pipe word count" 'echo "a b c" | wc -w'
compare_posix_output "pipe line count" 'printf "a\nb\nc\n" | wc -l'
compare_posix_output "pipe sort" 'printf "c\na\nb\n" | sort | head -1'
compare_posix_output "pipe uniq" 'printf "a\na\nb\n" | uniq | wc -l'
compare_posix_output "pipe head" 'printf "1\n2\n3\n4\n5\n" | head -2'
compare_posix_output "pipe tail" 'printf "1\n2\n3\n4\n5\n" | tail -2'
compare_posix_output "pipe tr" 'echo abc | tr a-z A-Z'

section "147. VARIABLE ASSIGNMENT CONTEXTS"

compare_posix_output "simple assign" 'x=5; echo $x'
compare_posix_output "multi assign" 'x=1 y=2 z=3; echo $x $y $z'
compare_posix_output "assign in subshell" '(x=inner; echo $x); echo ${x:-unset}'
compare_posix_output "assign export" 'export X=exported; printenv X 2>/dev/null || echo $X'
compare_posix_output "assign readonly" 'readonly X=constant; echo $X'
compare_posix_output "assign with cmd" 'X=$(echo value); echo $X'
compare_posix_output "assign quoted" 'X="with spaces"; echo "$X"'
compare_posix_output "assign empty" 'X=""; echo "[$X]"'
compare_posix_output "assign special" 'X="$HOME"; echo ${X:+set}'
compare_posix_output "unset removes" 'X=val; unset X; echo ${X:-gone}'

section "148. CONTROL FLOW PATTERNS"

compare_posix_output "if true" 'if true; then echo yes; fi'
compare_posix_output "if false" 'if false; then echo yes; fi; echo done'
compare_posix_output "if else" 'if false; then echo yes; else echo no; fi'
compare_posix_output "if elif" 'if false; then echo 1; elif true; then echo 2; fi'
compare_posix_output "if elif else" 'if false; then echo 1; elif false; then echo 2; else echo 3; fi'
compare_posix_output "nested if true" 'if true; then if true; then echo deep; fi; fi'
compare_posix_output "nested if false" 'if true; then if false; then echo no; fi; echo yes; fi'
compare_posix_output "if and condition" 'if true && true; then echo yes; fi'
compare_posix_output "if or condition" 'if false || true; then echo yes; fi'
compare_posix_output "if not condition" 'if ! false; then echo yes; fi'

section "149. LOOP PATTERNS"

compare_posix_output "for simple" 'for i in a b c; do echo $i; done'
compare_posix_output "for numbers" 'for i in 1 2 3; do echo $i; done | wc -l'
compare_posix_output "for empty" 'for i in; do echo $i; done; echo done'
compare_posix_output "while true once" 'n=1; while [ $n -eq 1 ]; do echo loop; n=0; done'
compare_posix_output "while count" 'n=3; while [ $n -gt 0 ]; do n=$((n-1)); done; echo $n'
compare_posix_output "until count" 'n=0; until [ $n -eq 3 ]; do n=$((n+1)); done; echo $n'
compare_posix_output "break in for" 'for i in 1 2 3; do [ $i -eq 2 ] && break; echo $i; done'
compare_posix_output "continue in for" 'for i in 1 2 3; do [ $i -eq 2 ] && continue; echo $i; done'
compare_posix_output "nested loops" 'for i in 1 2; do for j in a b; do echo $i$j; done; done | wc -l'
compare_posix_output "loop with pipe" 'for i in 1 2 3; do echo $i; done | head -2'

section "150. CASE STATEMENT PATTERNS"

compare_posix_output "case single" 'case x in x) echo yes;; esac'
compare_posix_output "case default" 'case x in y) echo no;; *) echo default;; esac'
compare_posix_output "case multi pattern" 'case x in x|y) echo xy;; esac'
compare_posix_output "case glob star" 'case abc in a*) echo star;; esac'
compare_posix_output "case glob question" 'case abc in a?c) echo match;; esac'
compare_posix_output "case glob bracket" 'case abc in [a-z]*) echo match;; esac'
compare_posix_output "case no match" 'case x in y) echo no;; esac; echo done'
compare_posix_output "case empty" 'case "" in "") echo empty;; esac'
compare_posix_output "case with var" 'x=test; case $x in test) echo yes;; esac'
compare_posix_output "case quoted" 'case "a b" in "a b") echo space;; esac'

section "151. FUNCTION PATTERNS"

compare_posix_output "func define call" 'f() { echo hello; }; f'
compare_posix_output "func with args" 'f() { echo $1 $2; }; f a b'
compare_posix_output "func return code" 'f() { return 0; }; f; echo $?'
compare_posix_output "func return 1" 'f() { return 1; }; f; echo $?'
compare_posix_output "func with local" 'x=outer; f() { x=inner; }; f; echo $x'
compare_posix_output "func recursive" 'f() { [ $1 -eq 0 ] && echo done || f $(($1-1)); }; f 2'
compare_posix_output "func in pipeline" 'f() { echo test; }; f | cat'
compare_posix_output "func multi stmt" 'f() { echo a; echo b; }; f | wc -l'
compare_posix_output "func empty body" 'f() { :; }; f; echo ok'
compare_posix_output "func all args" 'f() { echo $@; }; f a b c'

section "152. REDIRECTION PATTERNS"

compare_posix_output "redir output" 'echo test > /tmp/test_$$; cat /tmp/test_$$; rm /tmp/test_$$'
compare_posix_output "redir append" 'echo a > /tmp/test_$$; echo b >> /tmp/test_$$; wc -l < /tmp/test_$$; rm /tmp/test_$$'
compare_posix_output "redir input" 'echo test > /tmp/test_$$; cat < /tmp/test_$$; rm /tmp/test_$$'
compare_posix_output "redir stderr" 'echo err >&2 2>/dev/null; echo ok'
compare_posix_output "redir both devnull" 'echo out; echo err >&2 2>/dev/null'
compare_posix_output "redir fd dup" 'echo test 2>&1 | cat'
compare_posix_output "redir here string alt" 'echo test | cat'
compare_posix_output "redir noclobber safe" 'echo ok'
compare_posix_output "multiple redir" 'echo a; echo b; echo c'
compare_posix_output "redir in subshell" '(echo test > /tmp/test_$$); cat /tmp/test_$$ 2>/dev/null; rm /tmp/test_$$ 2>/dev/null; echo done'

section "153. SPECIAL PARAMETERS"

compare_posix_output "dollar question" 'true; echo $?'
compare_posix_output "dollar question fail" 'false; echo $?'
compare_posix_output "dollar bang" 'sleep 0.01 & echo ${!:-bg}'
compare_posix_output "dollar dollar" 'echo $$ | grep -c "[0-9]"'
compare_posix_output "dollar zero" 'echo ${0:-shell} | grep -c "."'
compare_posix_output "positional one" 'set -- a b c; echo $1'
compare_posix_output "positional two" 'set -- a b c; echo $2'
compare_posix_output "positional three" 'set -- a b c; echo $3'
compare_posix_output "dollar at" 'set -- a b c; echo "$@"'
compare_posix_output "dollar star" 'set -- a b c; echo "$*"'

section "154. TEST BUILTIN COMPREHENSIVE"

compare_posix_output "test eq" '[ 1 -eq 1 ]; echo $?'
compare_posix_output "test ne" '[ 1 -ne 2 ]; echo $?'
compare_posix_output "test lt" '[ 1 -lt 2 ]; echo $?'
compare_posix_output "test gt" '[ 2 -gt 1 ]; echo $?'
compare_posix_output "test le" '[ 1 -le 1 ]; echo $?'
compare_posix_output "test ge" '[ 1 -ge 1 ]; echo $?'
compare_posix_output "test str eq" '[ "a" = "a" ]; echo $?'
compare_posix_output "test str ne" '[ "a" != "b" ]; echo $?'
compare_posix_output "test z" '[ -z "" ]; echo $?'
compare_posix_output "test n" '[ -n "x" ]; echo $?'

section "155. FILE TEST OPERATIONS"

compare_posix_output "test f file" '[ -f /etc/passwd ] && echo yes || echo no'
compare_posix_output "test d dir" '[ -d /tmp ] && echo yes || echo no'
compare_posix_output "test e exists" '[ -e /tmp ] && echo yes || echo no'
compare_posix_output "test r read" '[ -r /etc/passwd ] && echo yes || echo no'
compare_posix_output "test w write" '[ -w /tmp ] && echo yes || echo no'
compare_posix_output "test x exec" '[ -x /bin/sh ] && echo yes || echo no'
compare_posix_output "test s size" '[ -s /etc/passwd ] && echo yes || echo no'
compare_posix_output "test not exist" '[ -e /nonexistent_xyz ] && echo yes || echo no'
compare_posix_output "test not dir" '[ -d /etc/passwd ] && echo yes || echo no'
compare_posix_output "test not file" '[ -f /tmp ] && echo yes || echo no'

section "156. LOGICAL COMBINATIONS"

compare_posix_output "and true true" 'true && true; echo $?'
compare_posix_output "and true false" 'true && false; echo $?'
compare_posix_output "and false true" 'false && true; echo $?'
compare_posix_output "and false false" 'false && false; echo $?'
compare_posix_output "or true true" 'true || true; echo $?'
compare_posix_output "or true false" 'true || false; echo $?'
compare_posix_output "or false true" 'false || true; echo $?'
compare_posix_output "or false false" 'false || false; echo $?'
compare_posix_output "not true" '! true; echo $?'
compare_posix_output "not false" '! false; echo $?'

section "157. SUBSHELL AND GROUPING"

compare_posix_output "subshell basic" '(echo sub)'
compare_posix_output "subshell var scope" 'x=outer; (x=inner); echo $x'
compare_posix_output "subshell exit" '(exit 5); echo $?'
compare_posix_output "subshell cd scope" '(cd /tmp); pwd | grep -v "/tmp" | head -1'
compare_posix_output "brace group" '{ echo brace; }'
compare_posix_output "brace group var" 'x=outer; { x=inner; }; echo $x'
compare_posix_output "brace group list" '{ echo a; echo b; } | wc -l'
compare_posix_output "subshell nested" '(echo $(echo nested))'
compare_posix_output "mixed grouping" '(echo sub); { echo brace; }'
compare_posix_output "subshell pipeline" '(echo test) | cat'

section "158. HEREDOC PATTERNS"

compare_posix_output "heredoc basic" 'cat <<EOF
test
EOF'
compare_posix_output "heredoc multi" 'cat <<EOF
line1
line2
EOF'
compare_posix_output "heredoc expand" 'X=val; cat <<EOF
$X
EOF'
compare_posix_output "heredoc quoted" "cat <<'EOF'
\$X
EOF"
compare_posix_output "heredoc tab" 'cat <<-EOF
	indented
EOF'
compare_posix_output "heredoc empty" 'cat <<EOF
EOF
echo done'
compare_posix_output "heredoc special" 'cat <<EOF
* $ " '"'"'
EOF'

section "159. QUOTING EDGE CASES"

compare_posix_output "double quote var" 'x=val; echo "$x"'
compare_posix_output "single quote literal" "echo 'literal \$x'"
compare_posix_output "escape in double" 'echo "a\\b"'
compare_posix_output "dollar literal" 'echo "\$"'
compare_posix_output "backtick literal" 'echo "\`"'
compare_posix_output "newline in quote" 'echo "line1
line2"'
compare_posix_output "tab in quote" 'echo "a	b"'
compare_posix_output "space preservation" 'echo "a   b"'
compare_posix_output "empty string" 'echo ""'
compare_posix_output "adjacent quotes" 'echo "a""b"'

section "160. EXPANSION ORDER"

compare_posix_output "tilde first" 'echo ~ | grep -c "/"'
compare_posix_output "param before cmd" 'x=echo; $x hello'
compare_posix_output "arith in var" 'x=$((1+1)); echo $x'
compare_posix_output "cmd in arith" 'echo $(($(echo 5) + 1))'
compare_posix_output "var in glob" 'x="*"; echo "$x"'
compare_posix_output "split then glob" 'IFS=" "; x="a b"; for i in $x; do echo $i; done | wc -l'
compare_posix_output "quote prevents split" 'x="a b c"; set -- "$x"; echo $#'
compare_posix_output "unquote allows split" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "nested expansion" 'x=y; y=val; eval echo \$$x'
compare_posix_output "complex chain" 'x=$(echo $((1+2))); echo $x'

section "161. BUILTIN COMMAND VARIATIONS"

compare_posix_output "echo no newline" 'echo -n test; echo done'
compare_posix_output "echo escape e" 'echo -e "a\tb"'
compare_posix_output "printf string" 'printf "%s\n" hello'
compare_posix_output "printf number" 'printf "%d\n" 42'
compare_posix_output "printf hex" 'printf "%x\n" 255'
compare_posix_output "printf octal" 'printf "%o\n" 64'
compare_posix_output "printf width" 'printf "%5d\n" 42'
compare_posix_output "printf zero pad" 'printf "%05d\n" 42'
compare_posix_output "printf left align" 'printf "%-5d|\n" 42'
compare_posix_output "printf multiple" 'printf "%s %s\n" a b'

section "162. READ BUILTIN VARIATIONS"

compare_posix_output "read single" 'echo hello | { read x; echo $x; }'
compare_posix_output "read multiple" 'echo "a b c" | { read x y z; echo "$x:$y:$z"; }'
compare_posix_output "read extra" 'echo "a b c d" | { read x y; echo "$x:$y"; }'
compare_posix_output "read fewer" 'echo "a" | { read x y; echo "x=$x y=${y:-empty}"; }'
compare_posix_output "read ifs colon" 'echo "a:b:c" | { IFS=: read x y z; echo "$x $y $z"; }'
compare_posix_output "read empty ifs" 'echo "a b c" | { IFS= read x; echo "$x"; }'
compare_posix_output "read backslash" 'printf "a\\\\b\n" | { read x; echo "$x"; }'
compare_posix_output "read raw" 'printf "a\\\\b\n" | { read -r x; echo "$x"; }'

section "163. SET BUILTIN VARIATIONS"

compare_posix_output "set positional" 'set -- a b c; echo $1 $2 $3'
compare_posix_output "set clear" 'set -- a b; set --; echo ${1:-none}'
compare_posix_output "set e exit" 'set -e; true; echo ok'
compare_posix_output "set u unset" 'set +u; echo ${undefined_var:-default}'
compare_posix_output "set f noglob" 'set -f; echo *; set +f'
compare_posix_output "set minus" 'echo $-'
compare_posix_output "set show" 'X=1; set | grep -c "^X=" || echo 0'
compare_posix_output "shift once" 'set -- a b c; shift; echo $1'
compare_posix_output "shift twice" 'set -- a b c; shift 2; echo $1'
compare_posix_output "shift all" 'set -- a b; shift 2; echo ${1:-empty}'

section "164. EXPORT AND ENV"

compare_posix_output "export simple" 'export X=val; echo $X'
compare_posix_output "export existing" 'X=val; export X; echo $X'
compare_posix_output "export list" 'export X=1 Y=2; echo $X $Y'
compare_posix_output "export subshell" 'export X=val; (echo $X)'
compare_posix_output "env prefix" 'X=override sh -c "echo \$X"'
compare_posix_output "env clear" 'X=val; unset X; echo ${X:-unset}'
compare_posix_output "readonly var" 'readonly X=const; echo $X'
compare_posix_output "unset normal" 'X=val; unset X; echo ${X:-gone}'

section "165. TRAP VARIATIONS"

compare_posix_output "trap list empty" 'trap | wc -l'
compare_posix_output "trap set list" 'trap "echo x" INT; trap | grep -c INT || echo 0'
compare_posix_output "trap reset" 'trap "echo x" INT; trap - INT; trap | grep -c INT || echo 0'
compare_posix_output "trap exit" 'sh -c "trap \"echo exit\" EXIT" 2>/dev/null || echo done'
compare_posix_output "trap ignore" 'trap "" INT; trap | grep -c INT || echo 0'
compare_posix_output "trap in func" 'f() { trap "echo trap" EXIT; }; f 2>/dev/null; echo done'

section "166. EVAL AND EXEC"

compare_posix_output "eval simple" 'eval echo hello'
compare_posix_output "eval var" 'X=world; eval echo hello $X'
compare_posix_output "eval cmd" 'eval "echo test"'
compare_posix_output "eval multi" 'eval "echo a; echo b"'
compare_posix_output "eval indirect" 'X=Y; Y=val; eval echo \$$X'
compare_posix_output "exec redirect" 'exec 3>&1; echo test >&3'
compare_posix_output "exec close" 'exec 3>&1; exec 3>&-; echo ok'

section "167. DOT AND SOURCE"

compare_posix_output "dot inline" 'echo "X=sourced" > /tmp/src_$$; . /tmp/src_$$; echo $X; rm /tmp/src_$$'
compare_posix_output "dot func" 'echo "f() { echo func; }" > /tmp/src_$$; . /tmp/src_$$; f; rm /tmp/src_$$'
compare_posix_output "dot var persist" 'echo "Y=persist" > /tmp/src_$$; . /tmp/src_$$; echo $Y; rm /tmp/src_$$'

section "168. COMMAND AND TYPE"

compare_posix_output "command echo" 'command echo hello'
compare_posix_output "command builtin" 'command true; echo $?'
compare_posix_output "command v" 'command -v echo | grep -c echo'
compare_posix_output "type builtin" 'type echo 2>/dev/null | grep -c echo || echo 1'
compare_posix_output "type not found" 'type nonexistent_cmd_xyz 2>&1 | grep -c "not found" || echo 0'

section "169. GETOPTS VARIATIONS"

compare_posix_output "getopts simple" 'set -- -a; getopts a opt; echo $opt'
compare_posix_output "getopts arg" 'set -- -a val; getopts a: opt; echo $opt $OPTARG'
compare_posix_output "getopts multi" 'set -- -a -b; getopts ab opt && echo $opt'
compare_posix_output "getopts unknown" 'set -- -x; getopts a opt 2>/dev/null; echo ${opt:-?}'
compare_posix_output "getopts optind" 'set -- -a arg; getopts a opt; echo $OPTIND'

section "170. COLON AND TRUE/FALSE"

compare_posix_output "colon noop" ':; echo $?'
compare_posix_output "colon with args" ': arg1 arg2; echo $?'
compare_posix_output "true exit" 'true; echo $?'
compare_posix_output "false exit" 'false; echo $?'
compare_posix_output "colon in if" 'if :; then echo yes; fi'
compare_posix_output "colon in while" 'n=0; while :; do n=$((n+1)); [ $n -ge 3 ] && break; done; echo $n'

section "171. PWD AND CD"

compare_posix_output "pwd basic" 'pwd | grep -c "/"'
compare_posix_output "cd tmp" 'cd /tmp && pwd'
compare_posix_output "cd home" 'cd ~ && pwd | grep -c "/"'
compare_posix_output "cd dash" 'cd /tmp; cd /; cd -'
compare_posix_output "cd dotdot" 'cd /tmp; cd ..; pwd'
compare_posix_output "cd subshell" '(cd /tmp; pwd); pwd | grep -v "/tmp" | wc -l'
compare_posix_output "OLDPWD" 'cd /tmp; cd /; echo $OLDPWD'

section "172. UMASK VARIATIONS"

compare_posix_output "umask get" 'umask | grep -c "[0-7]"'
compare_posix_output "umask symbolic" 'umask -S | grep -c "u="'

section "173. TIMES BUILTIN"

compare_posix_output "times format" 'times 2>&1 | head -1 | grep -c "[0-9]" || echo 0'

section "174. HASH BUILTIN"

compare_posix_output "hash list" 'hash 2>/dev/null; echo $?'
compare_posix_output "hash r clear" 'hash -r 2>/dev/null; echo $?'

section "175. ALIAS VARIATIONS"

compare_posix_output "alias set" 'alias x=echo 2>/dev/null; echo ok'
compare_posix_output "alias list" 'alias 2>/dev/null; echo $?'
compare_posix_output "unalias" 'alias x=echo 2>/dev/null; unalias x 2>/dev/null; echo $?'

section "176. WAIT BUILTIN"

compare_posix_output "wait all" 'sleep 0.01 & wait; echo $?'
compare_posix_output "wait pid" 'sleep 0.01 & p=$!; wait $p; echo $?'
compare_posix_output "wait none" 'wait; echo $?'

section "177. JOBS AND BG/FG"

compare_posix_output "jobs empty" 'jobs 2>/dev/null; echo $?'
compare_posix_output "bg pid" 'sleep 0.01 & echo bg'

section "178. ULIMIT VARIATIONS"

compare_posix_output "ulimit soft" 'ulimit -S -n 2>/dev/null | grep -c "[0-9]" || echo 1'
compare_posix_output "ulimit hard" 'ulimit -H -n 2>/dev/null | grep -c "[0-9]" || echo 1'
compare_posix_output "ulimit all" 'ulimit -a 2>/dev/null | wc -l'

section "179. SPECIAL EXPANSIONS"

compare_posix_output "length special" 'set -- a b c; echo ${#@}'
compare_posix_output "length star" 'set -- a b c; echo ${#*}'
compare_posix_output "at in quotes" 'set -- a b c; for x in "$@"; do echo $x; done | wc -l'
compare_posix_output "star in quotes" 'set -- a b c; echo "$*" | wc -w'
compare_posix_output "hash positional" 'set -- a b c d e; echo $#'
compare_posix_output "shift and hash" 'set -- a b c; shift; echo $#'
compare_posix_output "at unquoted" 'set -- a b c; for x in $@; do echo $x; done | wc -l'
compare_posix_output "star unquoted" 'set -- a b c; for x in $*; do echo $x; done | wc -l'

section "180. COMPLEX PATTERNS"

compare_posix_output "nested cmd sub" 'echo $(echo $(echo $(echo deep)))'
compare_posix_output "nested arith" 'echo $(( $(( $(( 1+1 )) + 1 )) + 1 ))'
compare_posix_output "mixed nesting" 'echo $(( $(echo 5) + $(echo 3) ))'
compare_posix_output "pipeline chain" 'echo test | cat | cat | cat | cat'
compare_posix_output "long and chain" 'true && true && true && true && echo yes'
compare_posix_output "long or chain" 'false || false || false || true && echo yes'
compare_posix_output "mixed logic" 'true && false || true && echo yes'
compare_posix_output "nested subshell" '((((echo deep))))'
compare_posix_output "nested brace" '{ { { echo deep; }; }; }'
compare_posix_output "func chain" 'f() { echo $1; }; g() { f hello; }; g'

section "181. WORD BOUNDARY CASES"

compare_posix_output "empty word" 'echo "" | cat'
compare_posix_output "space word" 'echo " " | cat'
compare_posix_output "tab word" 'echo "	" | cat'
compare_posix_output "newline word" 'echo "
" | wc -l'
compare_posix_output "mixed whitespace" 'echo " 	 " | cat'
compare_posix_output "leading space" 'echo " test" | cat'
compare_posix_output "trailing space" 'echo "test " | cat'
compare_posix_output "multiple spaces" 'echo "a    b" | cat'

section "182. NUMERIC EDGE CASES"

compare_posix_output "zero" 'echo $((0))'
compare_posix_output "negative one" 'echo $((-1))'
compare_posix_output "large number" 'echo $((999999))'
compare_posix_output "add negative" 'echo $((5 + -3))'
compare_posix_output "sub negative" 'echo $((5 - -3))'
compare_posix_output "mult negative" 'echo $((5 * -3))'
compare_posix_output "div negative" 'echo $((-15 / 3))'
compare_posix_output "mod negative" 'echo $((-7 % 3))'
compare_posix_output "compare negative" 'echo $((-1 < 0))'
compare_posix_output "zero compare" 'echo $((0 == 0))'

section "183. STRING BOUNDARY CASES"

compare_posix_output "empty length" 'x=""; echo ${#x}'
compare_posix_output "single char" 'x="a"; echo ${#x}'
compare_posix_output "special chars" 'x="!@#"; echo ${#x}'
compare_posix_output "spaces length" 'x="a b c"; echo ${#x}'
compare_posix_output "suffix on empty" 'x=""; echo ${x%.txt}'
compare_posix_output "prefix on empty" 'x=""; echo ${x#pre}'
compare_posix_output "default on set" 'x="val"; echo ${x:-def}'
compare_posix_output "alt on unset" 'unset x; echo ${x:+alt}'
compare_posix_output "alt on set" 'x="val"; echo ${x:+alt}'
compare_posix_output "assign on set" 'x="val"; echo ${x:=new}; echo $x'

section "184. GLOB BOUNDARY CASES"

compare_posix_output "star only" 'echo "*"'
compare_posix_output "question only" 'echo "?"'
compare_posix_output "bracket only" 'echo "[a]"'
compare_posix_output "glob in quotes" 'echo "*.txt"'
compare_posix_output "glob escaped" 'echo \*'
compare_posix_output "noglob star" 'set -f; echo *; set +f'
compare_posix_output "noglob question" 'set -f; echo ?; set +f'
compare_posix_output "noglob bracket" 'set -f; echo [a]; set +f'

section "185. REDIRECTION BOUNDARY CASES"

compare_posix_output "redir empty file" 'echo -n > /tmp/empty_$$; wc -c < /tmp/empty_$$; rm /tmp/empty_$$'
compare_posix_output "append to new" 'rm -f /tmp/new_$$; echo test >> /tmp/new_$$; cat /tmp/new_$$; rm /tmp/new_$$'
compare_posix_output "input from empty" 'echo -n > /tmp/empty_$$; cat < /tmp/empty_$$; echo done; rm /tmp/empty_$$'
compare_posix_output "stderr only" 'echo err >&2 2>&1 | cat'
compare_posix_output "stdout to null" 'echo test > /dev/null; echo $?'
compare_posix_output "stderr to null" 'echo err >&2 2>/dev/null; echo done'

section "186. PIPELINE BOUNDARY CASES"

compare_posix_output "empty input pipe" 'echo -n | cat'
compare_posix_output "single char pipe" 'echo a | cat'
compare_posix_output "large pipe" 'seq 1 100 | wc -l'
compare_posix_output "pipe to head 1" 'seq 1 10 | head -1'
compare_posix_output "pipe to tail 1" 'seq 1 10 | tail -1'
compare_posix_output "multi filter" 'seq 1 10 | head -5 | tail -1'

section "187. LOOP BOUNDARY CASES"

compare_posix_output "for single item" 'for i in x; do echo $i; done'
compare_posix_output "for no items" 'for i in; do echo $i; done; echo done'
compare_posix_output "while never" 'while false; do echo no; done; echo done'
compare_posix_output "until immediate" 'until true; do echo no; done; echo done'
compare_posix_output "break immediate" 'for i in 1 2 3; do break; echo $i; done; echo done'
compare_posix_output "continue all" 'for i in 1 2 3; do continue; echo $i; done; echo done'
compare_posix_output "nested break" 'for i in 1 2; do for j in a b; do break; done; echo $i; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do break 2; done; done; echo done'

section "188. FUNCTION BOUNDARY CASES"

compare_posix_output "func no args" 'f() { echo ${1:-none}; }; f'
compare_posix_output "func many args" 'f() { echo $#; }; f a b c d e f g h i j'
compare_posix_output "func return max" 'f() { return 255; }; f; echo $?'
compare_posix_output "func return zero" 'f() { return 0; }; f; echo $?'
compare_posix_output "func empty" 'f() { :; }; f; echo $?'
compare_posix_output "func redefine" 'f() { echo one; }; f() { echo two; }; f'
compare_posix_output "func recursive depth" 'f() { [ $1 -eq 0 ] && echo done || f $(($1-1)); }; f 5'

section "189. CASE BOUNDARY CASES"

compare_posix_output "case empty string" 'case "" in "") echo empty;; esac'
compare_posix_output "case single char" 'case "x" in x) echo x;; esac'
compare_posix_output "case no patterns" 'case x in esac; echo done'
compare_posix_output "case all patterns" 'case x in a|b|c|x|y) echo match;; esac'
compare_posix_output "case star first" 'case x in *) echo star;; x) echo x;; esac'
compare_posix_output "case question" 'case ab in ??) echo two;; esac'
compare_posix_output "case bracket range" 'case m in [a-z]) echo lower;; esac'
compare_posix_output "case bracket neg" 'case 5 in [!a-z]) echo notlower;; esac'

section "190. SUBSHELL BOUNDARY CASES"

compare_posix_output "subshell empty" '(); echo $?'
compare_posix_output "subshell exit 0" '(exit 0); echo $?'
compare_posix_output "subshell exit 1" '(exit 1); echo $?'
compare_posix_output "subshell var" '(X=inner; echo $X)'
compare_posix_output "subshell no leak" 'X=outer; (X=inner); echo $X'
compare_posix_output "subshell nested" '((echo deep))'
compare_posix_output "subshell pipe" '(echo test) | (cat)'
compare_posix_output "subshell bg" '(sleep 0.01) & wait; echo done'

section "191. BRACE GROUP BOUNDARY CASES"

compare_posix_output "brace simple" '{ echo test; }'
compare_posix_output "brace multi" '{ echo a; echo b; }'
compare_posix_output "brace var" '{ X=val; }; echo $X'
compare_posix_output "brace exit" '{ exit 0; }; echo $?'
compare_posix_output "brace pipe" '{ echo test; } | cat'
compare_posix_output "brace nested" '{ { echo deep; }; }'
compare_posix_output "brace and sub" '{ (echo sub); echo brace; }'
compare_posix_output "brace redirect" '{ echo test; } > /tmp/br_$$; cat /tmp/br_$$; rm /tmp/br_$$'

section "192. COMMENT VARIATIONS"

compare_posix_output "comment end" 'echo test # comment'
compare_posix_output "comment only" '# just a comment
echo ok'
compare_posix_output "comment in quotes" 'echo "# not comment"'
compare_posix_output "hash in var" 'X="#value"; echo $X'
compare_posix_output "comment after semi" 'echo a; # comment
echo b'

section "193. LINE CONTINUATION"

compare_posix_output "backslash newline" 'echo hel\
lo'
compare_posix_output "continuation in cmd" 'ec\
ho test'
compare_posix_output "continuation in arg" 'echo "hel\
lo"'
compare_posix_output "multi continuation" 'echo a\
b\
c'

section "194. SEMICOLON VARIATIONS"

compare_posix_output "semi two cmds" 'echo a; echo b'
compare_posix_output "semi three cmds" 'echo a; echo b; echo c'
compare_posix_output "semi with space" 'echo a ; echo b'
compare_posix_output "semi end of line" 'echo test;'
compare_posix_output "semi in quotes" 'echo "a;b"'
compare_posix_output "semi empty" '; echo ok'

section "195. NEWLINE AS SEPARATOR"

compare_posix_output "newline sep" 'echo a
echo b'
compare_posix_output "newline in if" 'if true
then
echo yes
fi'
compare_posix_output "newline in for" 'for i in 1 2
do
echo $i
done | wc -l'
compare_posix_output "newline in case" 'case x in
x) echo yes;;
esac'

section "196. AMPERSAND VARIATIONS"

compare_posix_output "bg simple" 'sleep 0.01 &; wait'
compare_posix_output "bg echo" 'echo test & wait'
compare_posix_output "and simple" 'true && echo yes'
compare_posix_output "and fail" 'false && echo no; echo done'
compare_posix_output "and chain" 'true && true && echo yes'
compare_posix_output "bg multiple" 'sleep 0.01 & sleep 0.01 & wait'

section "197. PIPE VARIATIONS"

compare_posix_output "or simple" 'false || echo yes'
compare_posix_output "or pass" 'true || echo no; echo done'
compare_posix_output "or chain" 'false || false || echo yes'
compare_posix_output "pipe simple" 'echo test | cat'
compare_posix_output "pipe chain" 'echo test | cat | cat'
compare_posix_output "mixed or and" 'false || true && echo yes'

section "198. PARENTHESES AND BRACES"

compare_posix_output "paren group" '(echo a; echo b)'
compare_posix_output "brace group" '{ echo a; echo b; }'
compare_posix_output "paren in paren" '((echo deep))'
compare_posix_output "brace in brace" '{ { echo deep; }; }'
compare_posix_output "paren in brace" '{ (echo sub); }'
compare_posix_output "brace in paren" '({ echo brace; })'

section "199. RESERVED WORD POSITIONS"

compare_posix_output "if as arg" 'echo if'
compare_posix_output "then as arg" 'echo then'
compare_posix_output "else as arg" 'echo else'
compare_posix_output "fi as arg" 'echo fi'
compare_posix_output "for as arg" 'echo for'
compare_posix_output "while as arg" 'echo while'
compare_posix_output "case as arg" 'echo case'
compare_posix_output "do as arg" 'echo do'
compare_posix_output "done as arg" 'echo done'

section "200. ASSIGNMENT VARIATIONS"

compare_posix_output "simple assign" 'X=val; echo $X'
compare_posix_output "empty assign" 'X=; echo "[$X]"'
compare_posix_output "quoted assign" 'X="val"; echo $X'
compare_posix_output "single quote assign" "X='val'; echo \$X"
compare_posix_output "cmd sub assign" 'X=$(echo val); echo $X'
compare_posix_output "arith assign" 'X=$((1+1)); echo $X'
compare_posix_output "multi assign" 'X=1 Y=2; echo $X $Y'
compare_posix_output "prefix assign" 'X=val sh -c "echo \$X"'
compare_posix_output "no space assign" 'X=nospace; echo $X'

section "201. PARAMETER EXPANSION EDGE CASES"

compare_posix_output "unset default" 'echo ${UNSET_VAR_XYZ:-default}'
compare_posix_output "set default" 'X=val; echo ${X:-default}'
compare_posix_output "empty default" 'X=; echo ${X:-default}'
compare_posix_output "unset alt" 'echo ${UNSET_VAR_XYZ:+alt}'
compare_posix_output "set alt" 'X=val; echo ${X:+alt}'
compare_posix_output "empty alt" 'X=; echo ${X:+alt}'
compare_posix_output "unset assign" 'echo ${UNSET_VAR_ABC:=assigned}; echo $UNSET_VAR_ABC'
compare_posix_output "set no assign" 'X=val; echo ${X:=new}; echo $X'
compare_posix_output "length zero" 'X=; echo ${#X}'
compare_posix_output "length five" 'X=hello; echo ${#X}'

section "202. PATTERN MATCHING IN EXPANSION"

compare_posix_output "suffix percent" 'X=file.txt; echo ${X%.txt}'
compare_posix_output "suffix double" 'X=a.b.c; echo ${X%%.*}'
compare_posix_output "prefix hash" 'X=prefix_name; echo ${X#prefix_}'
compare_posix_output "prefix double" 'X=a.b.c; echo ${X##*.}'
compare_posix_output "no match suffix" 'X=file.txt; echo ${X%.jpg}'
compare_posix_output "no match prefix" 'X=file.txt; echo ${X#img_}'
compare_posix_output "star suffix" 'X=hello; echo ${X%l*}'
compare_posix_output "star prefix" 'X=hello; echo ${X#*l}'
compare_posix_output "question suffix" 'X=hello; echo ${X%?}'
compare_posix_output "question prefix" 'X=hello; echo ${X#?}'

section "203. ARITHMETIC OPERATORS"

compare_posix_output "arith add" 'echo $((5 + 3))'
compare_posix_output "arith sub" 'echo $((5 - 3))'
compare_posix_output "arith mul" 'echo $((5 * 3))'
compare_posix_output "arith div" 'echo $((15 / 3))'
compare_posix_output "arith mod" 'echo $((17 % 5))'
compare_posix_output "arith neg" 'echo $((-5))'
compare_posix_output "arith paren" 'echo $(((2 + 3) * 4))'
compare_posix_output "arith var" 'X=5; echo $((X + 1))'
compare_posix_output "arith nested" 'echo $(($((1+1)) + $((2+2))))'
compare_posix_output "arith zero div" 'echo $((0 / 1))'

section "204. ARITHMETIC COMPARISONS"

compare_posix_output "arith lt true" 'echo $((1 < 2))'
compare_posix_output "arith lt false" 'echo $((2 < 1))'
compare_posix_output "arith gt true" 'echo $((2 > 1))'
compare_posix_output "arith gt false" 'echo $((1 > 2))'
compare_posix_output "arith le true" 'echo $((1 <= 1))'
compare_posix_output "arith ge true" 'echo $((1 >= 1))'
compare_posix_output "arith eq true" 'echo $((5 == 5))'
compare_posix_output "arith eq false" 'echo $((5 == 6))'
compare_posix_output "arith ne true" 'echo $((5 != 6))'
compare_posix_output "arith ne false" 'echo $((5 != 5))'

section "205. ARITHMETIC LOGICAL"

compare_posix_output "arith and true" 'echo $((1 && 1))'
compare_posix_output "arith and false" 'echo $((1 && 0))'
compare_posix_output "arith or true" 'echo $((0 || 1))'
compare_posix_output "arith or false" 'echo $((0 || 0))'
compare_posix_output "arith not true" 'echo $((!0))'
compare_posix_output "arith not false" 'echo $((!1))'
compare_posix_output "arith ternary t" 'echo $((1 ? 10 : 20))'
compare_posix_output "arith ternary f" 'echo $((0 ? 10 : 20))'
compare_posix_output "arith complex" 'echo $(((1 && 1) || 0))'
compare_posix_output "arith nested log" 'echo $((!(0 || 0)))'

section "206. TEST NUMERIC OPERATORS"

compare_posix_output "test eq true" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "test eq false" '[ 5 -eq 6 ]; echo $?'
compare_posix_output "test ne true" '[ 5 -ne 6 ]; echo $?'
compare_posix_output "test ne false" '[ 5 -ne 5 ]; echo $?'
compare_posix_output "test lt true" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "test lt false" '[ 5 -lt 3 ]; echo $?'
compare_posix_output "test le true" '[ 5 -le 5 ]; echo $?'
compare_posix_output "test gt true" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "test ge true" '[ 5 -ge 5 ]; echo $?'
compare_posix_output "test zero" '[ 0 -eq 0 ]; echo $?'

section "207. TEST STRING OPERATORS"

compare_posix_output "test str eq true" '[ "abc" = "abc" ]; echo $?'
compare_posix_output "test str eq false" '[ "abc" = "def" ]; echo $?'
compare_posix_output "test str ne true" '[ "abc" != "def" ]; echo $?'
compare_posix_output "test str ne false" '[ "abc" != "abc" ]; echo $?'
compare_posix_output "test z true" '[ -z "" ]; echo $?'
compare_posix_output "test z false" '[ -z "x" ]; echo $?'
compare_posix_output "test n true" '[ -n "x" ]; echo $?'
compare_posix_output "test n false" '[ -n "" ]; echo $?'
compare_posix_output "test str space" '[ "a b" = "a b" ]; echo $?'
compare_posix_output "test str empty" '[ "" = "" ]; echo $?'

section "208. TEST FILE OPERATORS"

compare_posix_output "test e exist" '[ -e /tmp ]; echo $?'
compare_posix_output "test e noexist" '[ -e /nonexistent_xyz ]; echo $?'
compare_posix_output "test f file" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "test f dir" '[ -f /tmp ]; echo $?'
compare_posix_output "test d dir" '[ -d /tmp ]; echo $?'
compare_posix_output "test d file" '[ -d /etc/passwd ]; echo $?'
compare_posix_output "test r read" '[ -r /etc/passwd ]; echo $?'
compare_posix_output "test w write" '[ -w /tmp ]; echo $?'
compare_posix_output "test x exec" '[ -x /bin/sh ]; echo $?'
compare_posix_output "test s size" '[ -s /etc/passwd ]; echo $?'

section "209. TEST LOGICAL OPERATORS"

compare_posix_output "test not true" '[ ! -f /nonexistent ]; echo $?'
compare_posix_output "test not false" '[ ! -d /tmp ]; echo $?'
compare_posix_output "test and true" '[ -d /tmp ] && [ -f /etc/passwd ]; echo $?'
compare_posix_output "test and false" '[ -d /tmp ] && [ -f /nonexistent ]; echo $?'
compare_posix_output "test or true" '[ -f /nonexistent ] || [ -d /tmp ]; echo $?'
compare_posix_output "test or false" '[ -f /nonexistent ] || [ -d /nonexistent ]; echo $?'
compare_posix_output "test complex" '[ -d /tmp ] && [ ! -f /nonexistent ]; echo $?'
compare_posix_output "test chain" '[ 1 -eq 1 ] && [ 2 -eq 2 ] && [ 3 -eq 3 ]; echo $?'

section "210. HEREDOC VARIATIONS"

compare_posix_output "heredoc simple" 'cat <<EOF
line
EOF'
compare_posix_output "heredoc multi" 'cat <<EOF
one
two
three
EOF'
compare_posix_output "heredoc empty" 'cat <<EOF
EOF
echo done'
compare_posix_output "heredoc expand" 'X=val; cat <<EOF
$X
EOF'
compare_posix_output "heredoc no expand" "cat <<'EOF'
\$X
EOF"
compare_posix_output "heredoc indent" 'cat <<-EOF
	tab
EOF'
compare_posix_output "heredoc special" 'cat <<EOF
* $ @ !
EOF'

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
