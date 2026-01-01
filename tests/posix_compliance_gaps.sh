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
compare_posix_output "\$0 is set" "echo \${0:-none} | grep -c '.'"

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

section "120. ADDITIONAL EXIT CODE TESTS"

compare_posix_exit_code "true exits 0" "true"
compare_posix_exit_code "false exits 1" "false"
compare_posix_exit_code "exit 0" "(exit 0)"
compare_posix_output "exit code chain" "true; echo \$?"

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
compare_posix_output "dollar hyphen" 'echo $- | grep -c "."'
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

section "162. PRINTF VARIATIONS"

compare_posix_output "printf basic" 'printf "hello\n"'
compare_posix_output "printf no newline" 'printf "test"; echo done'
compare_posix_output "printf format s" 'printf "%s\n" hello'
compare_posix_output "printf format d" 'printf "%d\n" 42'
compare_posix_output "printf multi arg" 'printf "%s %s\n" a b'
compare_posix_output "printf width" 'printf "%5s\n" ab'
compare_posix_output "printf escape" 'printf "a\tb\n"'
compare_posix_output "printf percent" 'printf "%%\n"'

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

section "176. ADDITIONAL BUILTINS"

compare_posix_output "test bracket" '[ 1 -eq 1 ]; echo $?'
compare_posix_output "test not" '[ ! 1 -eq 2 ]; echo $?'
compare_posix_output "test and" '[ 1 -eq 1 ] && [ 2 -eq 2 ]; echo $?'

section "177. MORE CONTROL FLOW"

compare_posix_output "if compound" 'if [ 1 -eq 1 ] && [ 2 -eq 2 ]; then echo yes; fi'
compare_posix_output "while compound" 'n=2; while [ $n -gt 0 ] && true; do n=$((n-1)); done; echo $n'

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
compare_posix_output "subshell output" '(echo sub; echo shell) | wc -l'

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

compare_posix_output "and simple" 'true && echo yes'
compare_posix_output "and fail" 'false && echo no; echo done'
compare_posix_output "and chain" 'true && true && echo yes'
compare_posix_output "and or mix" 'true && true || echo no'
compare_posix_output "or and mix" 'false || true && echo yes'
compare_posix_output "triple and" 'true && true && true && echo yes'

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

section "211. IFS WORD SPLITTING"

compare_posix_output "ifs split colon" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "ifs split space" 'IFS=" "; x="a b c"; set -- $x; echo $#'
compare_posix_output "ifs split multi" 'IFS=":;"; x="a:b;c"; set -- $x; echo $#'
compare_posix_output "ifs default split" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "ifs empty no split" 'IFS=""; x="a b"; set -- $x; echo $#'
compare_posix_output "ifs unset default" 'unset IFS; x="a  b"; set -- $x; echo $#'
compare_posix_output "ifs in for" 'IFS=:; for i in a:b:c; do echo $i; done'
compare_posix_output "ifs restore" 'OLD="$IFS"; IFS=:; IFS="$OLD"; echo ok'

section "212. WORD SPLITTING"

compare_posix_output "split unquoted" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "split quoted" 'x="a b c"; set -- "$x"; echo $#'
compare_posix_output "split ifs" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "split empty" 'x=""; set -- $x; echo $#'
compare_posix_output "split whitespace" 'x="  a  b  "; set -- $x; echo $#'
compare_posix_output "split preserve" 'x="a  b"; echo "$x"'
compare_posix_output "split multiple" 'x="a b" y="c d"; set -- $x $y; echo $#'

section "213. PATHNAME EXPANSION"

compare_posix_output "glob star" 'set -f; echo *; set +f'
compare_posix_output "glob question" 'set -f; echo ?; set +f'
compare_posix_output "glob bracket" 'set -f; echo [abc]; set +f'
compare_posix_output "glob quoted" 'echo "*"'
compare_posix_output "glob escaped" 'echo \*'
compare_posix_output "glob noglob" 'set -f; echo *.txt; set +f'
compare_posix_output "glob in var" 'x="*"; echo "$x"'

section "214. TILDE EXPANSION"

compare_posix_output "tilde alone" 'echo ~ | grep -c "/"'
compare_posix_output "tilde slash" 'echo ~/ | grep -c "/"'
compare_posix_output "tilde quoted" 'echo "~"'
compare_posix_output "tilde in var" 'x=~; echo $x | grep -c "/"'
compare_posix_output "tilde assign" 'HOME=/tmp; echo ~ | grep -c "/"'

section "215. COMMAND SUBSTITUTION NESTING"

compare_posix_output "cmd sub simple" 'echo $(echo hello)'
compare_posix_output "cmd sub nested" 'echo $(echo $(echo deep))'
compare_posix_output "cmd sub triple" 'echo $(echo $(echo $(echo triple)))'
compare_posix_output "cmd sub arith" 'echo $(echo $((1+1)))'
compare_posix_output "cmd sub var" 'X=val; echo $(echo $X)'
compare_posix_output "cmd sub quote" 'echo "$(echo "quoted")"'
compare_posix_output "backtick simple" 'echo `echo hello`'
compare_posix_output "backtick nested" 'echo `echo \`echo deep\``'

section "216. PIPELINE ALTERNATIVES"

compare_posix_output "pipe chain filter" 'echo test | grep test | cat'
compare_posix_output "subshell pipe" '(echo test) | cat'
compare_posix_output "brace pipe" '{ echo test; } | cat'
compare_posix_output "pipe to head" 'printf "a\nb\nc\n" | head -2 | wc -l'

section "217. EXIT STATUS"

compare_posix_output "exit 0" 'exit 0'
compare_posix_output "exit 1" '(exit 1); echo $?'
compare_posix_output "exit 255" '(exit 255); echo $?'
compare_posix_output "true status" 'true; echo $?'
compare_posix_output "false status" 'false; echo $?'
compare_posix_output "cmd not found" 'nonexistent_cmd_xyz 2>/dev/null; echo $?'
compare_posix_output "pipe status" 'false | true; echo $?'
compare_posix_output "and status" 'true && true; echo $?'
compare_posix_output "or status" 'false || true; echo $?'
compare_posix_output "not status" '! false; echo $?'

section "218. SIGNAL HANDLING"

compare_posix_output "trap list" 'trap 2>/dev/null; echo $?'
compare_posix_output "trap set" 'trap "echo caught" INT; trap | grep -c INT || echo 0'
compare_posix_output "trap reset" 'trap "echo x" INT; trap - INT; trap | grep -c INT || echo 0'
compare_posix_output "trap ignore" 'trap "" INT; trap | grep -c INT || echo 0'
compare_posix_output "kill signal" 'kill -l | head -1 | grep -c "[A-Z]" || echo 1'

section "219. ADDITIONAL TESTS"

compare_posix_output "pipeline exit" 'true | false; echo $?'
compare_posix_output "pipeline true" 'true | true; echo $?'
compare_posix_output "negation pipe" '! false | true; echo $?'
compare_posix_output "subshell exit" '(exit 42); echo $?'
compare_posix_output "brace exit" '{ true; }; echo $?'

section "220. ENVIRONMENT VARIABLES"

compare_posix_output "env home" 'echo ${HOME:-unset} | grep -c "/"'
compare_posix_output "env path" 'echo ${PATH:-unset} | grep -c ":"'
compare_posix_output "env pwd" 'echo ${PWD:-unset} | grep -c "/"'
compare_posix_output "env shell" 'echo ${SHELL:-unset} | grep -c "/" || echo 1'
compare_posix_output "export var" 'export X=val; sh -c "echo \$X"'
compare_posix_output "prefix assign" 'X=val sh -c "echo \$X"'
compare_posix_output "unset env" 'export X=val; unset X; echo ${X:-unset}'

section "221. SPECIAL VARIABLES"

compare_posix_output "dollar zero" 'echo ${0:-shell} | grep -c "."'
compare_posix_output "dollar hash" 'set -- a b c; echo $#'
compare_posix_output "dollar question" 'true; echo $?'
compare_posix_output "dollar dollar" 'echo $$ | grep -c "[0-9]"'
compare_posix_output "dollar underscore" 'echo test; echo ${_:-none}'
compare_posix_output "dollar at" 'set -- a b c; echo "$@"'
compare_posix_output "dollar star" 'set -- a b c; echo "$*"'
compare_posix_output "dollar minus" 'echo $- | grep -c "."'

section "222. POSITIONAL PARAMETERS"

compare_posix_output "pos one" 'set -- a b c; echo $1'
compare_posix_output "pos two" 'set -- a b c; echo $2'
compare_posix_output "pos three" 'set -- a b c; echo $3'
compare_posix_output "pos shift" 'set -- a b c; shift; echo $1'
compare_posix_output "pos shift n" 'set -- a b c d e; shift 3; echo $1'
compare_posix_output "pos set" 'set -- x y z; echo $1 $2 $3'
compare_posix_output "pos clear" 'set -- a b c; set --; echo ${1:-empty}'
compare_posix_output "pos count" 'set -- a b c d e; echo $#'
compare_posix_output "pos all at" 'set -- a b c; for x in "$@"; do echo $x; done | wc -l'
compare_posix_output "pos all star" 'set -- a b c; echo "$*" | wc -w'

section "223. FUNCTION DEFINITION STYLES"

compare_posix_output "func keyword" 'f() { echo hello; }; f'
compare_posix_output "func oneline" 'f() { echo one; }; f'
compare_posix_output "func multiline" 'f() {
echo multi
}; f'
compare_posix_output "func with args" 'f() { echo $1 $2; }; f a b'
compare_posix_output "func return" 'f() { return 5; }; f; echo $?'
compare_posix_output "func local var" 'X=outer; f() { X=inner; }; f; echo $X'
compare_posix_output "func recursive" 'f() { [ $1 -eq 0 ] && echo done || f $(($1-1)); }; f 3'

section "224. FUNCTION SCOPE"

compare_posix_output "func global var" 'X=global; f() { echo $X; }; f'
compare_posix_output "func modify var" 'X=old; f() { X=new; }; f; echo $X'
compare_posix_output "func args" 'f() { echo $#; }; f a b c'
compare_posix_output "func positional" 'f() { echo $1; }; set -- x; f a; echo $1'
compare_posix_output "func in subshell" 'f() { echo func; }; (f)'
compare_posix_output "func in pipeline" 'f() { echo test; }; f | cat'
compare_posix_output "func redefine" 'f() { echo one; }; f; f() { echo two; }; f'

section "225. ALIAS BASICS"

compare_posix_output "alias define" 'alias x=echo 2>/dev/null; echo ok'
compare_posix_output "alias list" 'alias 2>/dev/null; echo $?'
compare_posix_output "unalias" 'alias x=echo 2>/dev/null; unalias x 2>/dev/null; echo $?'
compare_posix_output "unalias all" 'unalias -a 2>/dev/null; echo $?'

section "226. CONTROL STRUCTURES COMPREHENSIVE"

compare_posix_output "if basic" 'if true; then echo yes; fi'
compare_posix_output "if else" 'if false; then echo no; else echo yes; fi'
compare_posix_output "if elif" 'if false; then echo 1; elif true; then echo 2; fi'
compare_posix_output "if nested" 'if true; then if true; then echo deep; fi; fi'
compare_posix_output "for basic" 'for i in 1 2 3; do echo $i; done | wc -l'
compare_posix_output "for empty" 'for i in; do echo $i; done; echo done'
compare_posix_output "while basic" 'n=3; while [ $n -gt 0 ]; do echo $n; n=$((n-1)); done | wc -l'
compare_posix_output "until basic" 'n=0; until [ $n -eq 3 ]; do n=$((n+1)); done; echo $n'
compare_posix_output "case basic" 'case x in x) echo yes;; esac'
compare_posix_output "case default" 'case x in y) echo no;; *) echo default;; esac'

section "227. BREAK AND CONTINUE"

compare_posix_output "break simple" 'for i in 1 2 3; do [ $i -eq 2 ] && break; echo $i; done'
compare_posix_output "continue simple" 'for i in 1 2 3; do [ $i -eq 2 ] && continue; echo $i; done'
compare_posix_output "break nested" 'for i in 1 2; do for j in a b; do break; done; echo $i; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do break 2; done; done; echo done'
compare_posix_output "continue nested" 'for i in 1 2; do for j in a b; do continue 2; done; echo no; done; echo done'

section "228. RETURN AND EXIT"

compare_posix_output "return 0" 'f() { return 0; }; f; echo $?'
compare_posix_output "return 1" 'f() { return 1; }; f; echo $?'
compare_posix_output "return 255" 'f() { return 255; }; f; echo $?'
compare_posix_output "exit subshell" '(exit 5); echo $?'
compare_posix_output "exit brace" '{ exit 0; }; echo unreached'
compare_posix_output "return implicit" 'f() { true; }; f; echo $?'

section "229. COMPOUND COMMANDS"

compare_posix_output "paren list" '(echo a; echo b) | wc -l'
compare_posix_output "brace list" '{ echo a; echo b; } | wc -l'
compare_posix_output "if in paren" '(if true; then echo yes; fi)'
compare_posix_output "for in brace" '{ for i in 1 2; do echo $i; done; } | wc -l'
compare_posix_output "while in paren" '(n=2; while [ $n -gt 0 ]; do echo $n; n=$((n-1)); done) | wc -l'
compare_posix_output "case in brace" '{ case x in x) echo yes;; esac; }'
compare_posix_output "func in paren" '(f() { echo func; }; f)'

section "230. COMPLEX COMMAND COMBINATIONS"

compare_posix_output "for pipe filter" 'for i in 1 2 3 4 5; do echo $i; done | head -3 | wc -l'
compare_posix_output "case in for" 'for x in a b c; do case $x in a) echo first;; esac; done'
compare_posix_output "if in while" 'n=2; while [ $n -gt 0 ]; do if [ $n -eq 1 ]; then echo one; fi; n=$((n-1)); done'
compare_posix_output "nested for" 'for i in 1 2; do for j in a b; do echo $i$j; done; done | wc -l'
compare_posix_output "subshell in for" 'for i in 1 2; do (echo $i); done | wc -l'
compare_posix_output "func in for" 'f() { echo $1; }; for i in a b c; do f $i; done | wc -l'
compare_posix_output "pipe to sort" 'printf "c\na\nb\n" | sort | head -1'
compare_posix_output "nested subshell" '((echo deep))'

section "231. EXPR COMMAND"

compare_posix_output "expr add" 'expr 5 + 3'
compare_posix_output "expr sub" 'expr 10 - 3'
compare_posix_output "expr mul" 'expr 4 \* 5'
compare_posix_output "expr div" 'expr 20 / 4'
compare_posix_output "expr mod" 'expr 17 % 5'
compare_posix_output "expr compare lt" 'expr 3 \< 5'
compare_posix_output "expr compare gt" 'expr 5 \> 3'
compare_posix_output "expr compare eq" 'expr 5 = 5'
compare_posix_output "expr string" 'expr length hello'
compare_posix_output "expr substr" 'expr substr hello 2 3'

section "232. BASENAME AND DIRNAME"

compare_posix_output "basename simple" 'basename /path/to/file'
compare_posix_output "basename suffix" 'basename /path/to/file.txt .txt'
compare_posix_output "basename no path" 'basename file.txt'
compare_posix_output "dirname simple" 'dirname /path/to/file'
compare_posix_output "dirname root" 'dirname /file'
compare_posix_output "dirname relative" 'dirname file'
compare_posix_output "dirname dot" 'dirname ./file'
compare_posix_output "dirname trailing" 'dirname /path/to/'

section "233. CUT COMMAND"

compare_posix_output "cut field" 'echo "a:b:c" | cut -d: -f2'
compare_posix_output "cut fields" 'echo "a:b:c" | cut -d: -f1,3'
compare_posix_output "cut chars" 'echo "hello" | cut -c1-3'
compare_posix_output "cut char single" 'echo "hello" | cut -c2'
compare_posix_output "cut range" 'echo "a:b:c:d" | cut -d: -f2-3'

section "234. TR COMMAND"

compare_posix_output "tr simple" 'echo abc | tr a-z A-Z'
compare_posix_output "tr delete" 'echo "a1b2c3" | tr -d 0-9'
compare_posix_output "tr squeeze" 'echo "aabbcc" | tr -s a-z'
compare_posix_output "tr single" 'echo abc | tr a x'
compare_posix_output "tr complement" 'echo "a1b2" | tr -cd a-z'

section "235. SORT COMMAND"

compare_posix_output "sort lines" 'printf "c\na\nb\n" | sort'
compare_posix_output "sort reverse" 'printf "a\nb\nc\n" | sort -r'
compare_posix_output "sort numeric" 'printf "10\n2\n1\n" | sort -n'
compare_posix_output "sort unique" 'printf "a\na\nb\n" | sort -u'
compare_posix_output "sort first" 'printf "c\na\nb\n" | sort | head -1'

section "236. UNIQ COMMAND"

compare_posix_output "uniq simple" 'printf "a\na\nb\n" | uniq'
compare_posix_output "uniq count" 'printf "a\na\nb\n" | uniq -c | wc -l'
compare_posix_output "uniq duplicate" 'printf "a\na\nb\n" | uniq -d'
compare_posix_output "uniq unique" 'printf "a\na\nb\n" | uniq -u'

section "237. WC COMMAND"

compare_posix_output "wc lines" 'printf "a\nb\nc\n" | wc -l'
compare_posix_output "wc words" 'echo "one two three" | wc -w'
compare_posix_output "wc chars" 'echo "hello" | wc -c'
compare_posix_output "wc empty" 'echo "" | wc -l'

section "238. HEAD AND TAIL"

compare_posix_output "head default" 'seq 1 20 | head | wc -l'
compare_posix_output "head n" 'seq 1 10 | head -3'
compare_posix_output "tail default" 'seq 1 20 | tail | wc -l'
compare_posix_output "tail n" 'seq 1 10 | tail -3'
compare_posix_output "head tail combo" 'seq 1 10 | head -5 | tail -1'

section "239. GREP PATTERNS"

compare_posix_output "grep simple" 'echo hello | grep hello'
compare_posix_output "grep no match" 'echo hello | grep xyz; echo $?'
compare_posix_output "grep count" 'printf "a\nb\na\n" | grep -c a'
compare_posix_output "grep ignore case" 'echo HELLO | grep -i hello'
compare_posix_output "grep invert" 'printf "a\nb\n" | grep -v a'
compare_posix_output "grep line" 'printf "abc\ndef\n" | grep -n abc'

section "240. SED BASICS"

compare_posix_output "sed substitute" 'echo hello | sed "s/hello/world/"'
compare_posix_output "sed global" 'echo "aaa" | sed "s/a/b/g"'
compare_posix_output "sed delete" 'printf "a\nb\nc\n" | sed "1d" | wc -l'
compare_posix_output "sed print" 'printf "a\nb\n" | sed -n "1p"'
compare_posix_output "sed range" 'printf "a\nb\nc\n" | sed "1,2d"'

section "241. AWK BASICS"

compare_posix_output "awk print" 'echo "a b c" | awk "{print \$2}"'
compare_posix_output "awk field" 'echo "a:b:c" | awk -F: "{print \$2}"'
compare_posix_output "awk NF" 'echo "a b c" | awk "{print NF}"'
compare_posix_output "awk NR" 'printf "a\nb\n" | awk "{print NR}"'
compare_posix_output "awk math" 'echo "5 3" | awk "{print \$1 + \$2}"'

section "242. TEE COMMAND"

compare_posix_output "tee output" 'echo test | tee /dev/null'
compare_posix_output "tee passthrough" 'echo hello | tee /dev/null | cat'

section "243. XARGS BASICS"

compare_posix_output "xargs echo" 'echo "a b c" | xargs echo'
compare_posix_output "xargs n1" 'printf "a\nb\nc\n" | xargs -n1 echo | wc -l'

section "244. FIND BASICS"

compare_posix_output "find type d" 'find /tmp -maxdepth 1 -type d 2>/dev/null | head -1 | grep -c "/"'
compare_posix_output "find name" 'find /etc -maxdepth 1 -name "passwd" 2>/dev/null | grep -c passwd || echo 0'

section "245. TEST COMMAND FORMS"

compare_posix_output "test bracket" '[ 1 -eq 1 ]; echo $?'
compare_posix_output "test keyword" 'test 1 -eq 1; echo $?'
compare_posix_output "test string" '[ "a" = "a" ]; echo $?'
compare_posix_output "test empty" '[ -z "" ]; echo $?'
compare_posix_output "test nonempty" '[ -n "x" ]; echo $?'
compare_posix_output "test not" '[ ! 1 -eq 2 ]; echo $?'
compare_posix_output "test and ext" '[ 1 -eq 1 -a 2 -eq 2 ]; echo $?'
compare_posix_output "test or ext" '[ 1 -eq 2 -o 2 -eq 2 ]; echo $?'

section "246. ARITHMETIC BITWISE"

compare_posix_output "arith and" 'echo $((5 & 3))'
compare_posix_output "arith or" 'echo $((5 | 3))'
compare_posix_output "arith xor" 'echo $((5 ^ 3))'
compare_posix_output "arith not" 'echo $((~0))'
compare_posix_output "arith lshift" 'echo $((1 << 4))'
compare_posix_output "arith rshift" 'echo $((16 >> 2))'

section "247. COMPLEX CASE PATTERNS"

compare_posix_output "case or pattern" 'case abc in a*|b*) echo match;; esac'
compare_posix_output "case bracket" 'case a in [abc]) echo match;; esac'
compare_posix_output "case negbracket" 'case d in [!abc]) echo match;; esac'
compare_posix_output "case question" 'case ab in ??) echo two;; esac'
compare_posix_output "case star" 'case anything in *) echo match;; esac'
compare_posix_output "case empty" 'case "" in "") echo empty;; esac'
compare_posix_output "case number" 'case 42 in [0-9]*) echo num;; esac'

section "248. COMPLEX FOR LOOPS"

compare_posix_output "for glob safe" 'set -f; for i in *; do echo "$i"; done; set +f'
compare_posix_output "for break early" 'for i in 1 2 3 4 5; do echo $i; [ $i -eq 3 ] && break; done | wc -l'
compare_posix_output "for continue skip" 'for i in 1 2 3; do [ $i -eq 2 ] && continue; echo $i; done | wc -l'
compare_posix_output "for nested count" 'for i in 1 2; do for j in a b c; do echo x; done; done | wc -l'
compare_posix_output "for empty list" 'for i in; do echo never; done; echo done'
compare_posix_output "for single" 'for i in only; do echo $i; done'

section "249. COMPLEX WHILE LOOPS"

compare_posix_output "while decrement" 'n=5; while [ $n -gt 0 ]; do n=$((n-1)); done; echo $n'
compare_posix_output "while false" 'while false; do echo never; done; echo done'
compare_posix_output "while break" 'n=0; while true; do n=$((n+1)); [ $n -ge 3 ] && break; done; echo $n'
compare_posix_output "while nested" 'i=2; while [ $i -gt 0 ]; do j=2; while [ $j -gt 0 ]; do echo x; j=$((j-1)); done; i=$((i-1)); done | wc -l'
compare_posix_output "until true" 'until true; do echo never; done; echo done'
compare_posix_output "until count" 'n=0; until [ $n -ge 3 ]; do n=$((n+1)); done; echo $n'

section "250. COMPLEX FUNCTIONS"

compare_posix_output "func args count" 'f() { echo $#; }; f a b c d e'
compare_posix_output "func all args" 'f() { echo "$@"; }; f a b c'
compare_posix_output "func star args" 'f() { echo "$*"; }; f a b c'
compare_posix_output "func return val" 'f() { return 42; }; f; echo $?'
compare_posix_output "func modify global" 'x=old; f() { x=new; }; f; echo $x'
compare_posix_output "func recursive" 'f() { [ $1 -le 1 ] && echo 1 || echo $(($(f $(($1-1))) + $(f $(($1-2))))); }; f 5'
compare_posix_output "func in subshell" 'f() { echo inner; }; (f)'
compare_posix_output "func pipe" 'f() { echo test; }; f | cat'
compare_posix_output "func empty" 'f() { :; }; f; echo $?'
compare_posix_output "func chain" 'f() { echo $1; }; g() { f hello; }; g'

section "251. SHELL ARITHMETIC EDGE CASES"

compare_posix_output "arith octal" 'echo $((010))'
compare_posix_output "arith hex" 'echo $((0x10))'
compare_posix_output "arith unary plus" 'echo $((+5))'
compare_posix_output "arith unary minus" 'echo $((-5))'
compare_posix_output "arith double neg" 'echo $((--5))'
compare_posix_output "arith complex" 'echo $(((1+2)*(3+4)))'
compare_posix_output "arith assign" 'x=5; echo $((x=x+1)); echo $x'
compare_posix_output "arith incr" 'x=5; echo $((x+=1))'
compare_posix_output "arith decr" 'x=5; echo $((x-=1))'

section "252. VARIABLE EDGE CASES"

compare_posix_output "var underscore" '_x=val; echo $_x'
compare_posix_output "var number suffix" 'x1=val; echo $x1'
compare_posix_output "var long name" 'very_long_variable_name_here=val; echo $very_long_variable_name_here'
compare_posix_output "var empty val" 'x=; echo "[$x]"'
compare_posix_output "var space val" 'x="a b"; echo "$x"'
compare_posix_output "var newline val" 'x="a
b"; echo "$x" | wc -l'
compare_posix_output "var special chars" 'x="!@#"; echo "$x"'
compare_posix_output "var equals in val" 'x="a=b"; echo "$x"'

section "253. QUOTING EDGE CASES"

compare_posix_output "quote empty" 'echo ""'
compare_posix_output "quote space" 'echo " "'
compare_posix_output "quote tab" 'echo "	"'
compare_posix_output "quote newline" 'echo "
"'
compare_posix_output "quote dollar" 'echo "\$"'
compare_posix_output "quote backslash" 'echo "\\"'
compare_posix_output "quote backtick" 'echo "\`"'
compare_posix_output "quote double" 'echo "\""'
compare_posix_output "single in double" 'echo "'"'"'"'
compare_posix_output "double in single" "echo '\"'"

section "254. PARAMETER EXPANSION COMPREHENSIVE"

compare_posix_output "param default unset" 'echo ${undef:-default}'
compare_posix_output "param default empty" 'x=; echo ${x:-default}'
compare_posix_output "param default set" 'x=val; echo ${x:-default}'
compare_posix_output "param alt unset" 'echo ${undef:+alt}'
compare_posix_output "param alt empty" 'x=; echo ${x:+alt}'
compare_posix_output "param alt set" 'x=val; echo ${x:+alt}'
compare_posix_output "param assign unset" 'unset y; echo ${y:=assigned}; echo $y'
compare_posix_output "param length" 'x=hello; echo ${#x}'
compare_posix_output "param suffix" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "param prefix" 'x=prefix_name; echo ${x#prefix_}'

section "255. REDIRECTION COMPREHENSIVE"

compare_posix_output "redir stdout" 'echo test > /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir append" 'echo a > /tmp/r$$; echo b >> /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir stdin" 'echo test > /tmp/r$$; cat < /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir stderr" 'echo err >&2 2>/dev/null; echo ok'
compare_posix_output "redir fd dup" 'echo test 2>&1 | cat'
compare_posix_output "redir devnull" 'echo test > /dev/null; echo $?'
compare_posix_output "redir clobber" 'echo a > /tmp/r$$; echo b > /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'

section "256. HEREDOC COMPREHENSIVE"

compare_posix_output "heredoc basic" 'cat <<EOF
line
EOF'
compare_posix_output "heredoc multi" 'cat <<EOF
one
two
EOF'
compare_posix_output "heredoc var" 'x=val; cat <<EOF
$x
EOF'
compare_posix_output "heredoc quoted" "cat <<'EOF'
\$x
EOF"
compare_posix_output "heredoc tab strip" 'cat <<-EOF
	indented
EOF'

section "257. PIPELINE COMPREHENSIVE"

compare_posix_output "pipe two" 'echo test | cat'
compare_posix_output "pipe three" 'echo test | cat | cat'
compare_posix_output "pipe four" 'echo test | cat | cat | cat'
compare_posix_output "pipe filter" 'echo hello | grep h'
compare_posix_output "pipe transform" 'echo abc | tr a-z A-Z'
compare_posix_output "pipe count" 'printf "a\nb\nc\n" | wc -l'
compare_posix_output "pipe subshell" '(echo test) | cat'
compare_posix_output "pipe brace" '{ echo test; } | cat'

section "258. LOGICAL OPERATORS COMPREHENSIVE"

compare_posix_output "and tt" 'true && true; echo $?'
compare_posix_output "and tf" 'true && false; echo $?'
compare_posix_output "and ft" 'false && true; echo $?'
compare_posix_output "and ff" 'false && false; echo $?'
compare_posix_output "or tt" 'true || true; echo $?'
compare_posix_output "or tf" 'true || false; echo $?'
compare_posix_output "or ft" 'false || true; echo $?'
compare_posix_output "or ff" 'false || false; echo $?'
compare_posix_output "not t" '! true; echo $?'
compare_posix_output "not f" '! false; echo $?'
compare_posix_output "mixed 1" 'true && false || echo fallback'
compare_posix_output "mixed 2" 'false || true && echo success'

section "259. SUBSHELL COMPREHENSIVE"

compare_posix_output "sub echo" '(echo sub)'
compare_posix_output "sub var" '(x=inner; echo $x)'
compare_posix_output "sub no leak" 'x=outer; (x=inner); echo $x'
compare_posix_output "sub exit" '(exit 5); echo $?'
compare_posix_output "sub cd" '(cd /tmp; pwd)'
compare_posix_output "sub pipe" '(echo a; echo b) | wc -l'
compare_posix_output "sub nested" '((echo deep))'
compare_posix_output "sub multi" '(echo a); (echo b)'

section "260. BRACE GROUP COMPREHENSIVE"

compare_posix_output "brace echo" '{ echo brace; }'
compare_posix_output "brace multi" '{ echo a; echo b; }'
compare_posix_output "brace var" '{ x=val; }; echo $x'
compare_posix_output "brace pipe" '{ echo test; } | cat'
compare_posix_output "brace redir" '{ echo test; } > /tmp/b$$; cat /tmp/b$$; rm /tmp/b$$'
compare_posix_output "brace nested" '{ { echo deep; }; }'
compare_posix_output "brace and sub" '{ (echo sub); }'

section "261. SPECIAL CHARACTERS"

compare_posix_output "char star" 'echo "*"'
compare_posix_output "char question" 'echo "?"'
compare_posix_output "char bracket" 'echo "[]"'
compare_posix_output "char brace" 'echo "{}"'
compare_posix_output "char paren" 'echo "()"'
compare_posix_output "char pipe" 'echo "|"'
compare_posix_output "char amp" 'echo "&"'
compare_posix_output "char semi" 'echo ";"'
compare_posix_output "char dollar" 'echo "\$"'
compare_posix_output "char hash" 'echo "#"'

section "262. COMMAND LINE PARSING"

compare_posix_output "parse simple" 'echo hello'
compare_posix_output "parse multi arg" 'echo a b c'
compare_posix_output "parse quoted arg" 'echo "a b c"'
compare_posix_output "parse mixed" 'echo a "b c" d'
compare_posix_output "parse empty arg" 'echo "" x'
compare_posix_output "parse escape" 'echo a\ b'
compare_posix_output "parse continued" 'echo hel\
lo'

section "263. EXECUTION CONTEXT"

compare_posix_output "exec subshell" '(echo sub)'
compare_posix_output "exec pipeline" 'echo test | cat'
compare_posix_output "exec background" 'true & echo fg'
compare_posix_output "exec compound" '{ echo a; echo b; }'
compare_posix_output "exec function" 'f() { echo func; }; f'
compare_posix_output "exec builtin" 'echo hello'
compare_posix_output "exec external" '/bin/echo hello'

section "264. STRING COMPARISON"

compare_posix_output "str eq" '[ "a" = "a" ]; echo $?'
compare_posix_output "str ne" '[ "a" != "b" ]; echo $?'
compare_posix_output "str lt" '[ "a" \< "b" ]; echo $?'
compare_posix_output "str gt" '[ "b" \> "a" ]; echo $?'
compare_posix_output "str empty" '[ -z "" ]; echo $?'
compare_posix_output "str nonempty" '[ -n "x" ]; echo $?'
compare_posix_output "str space" '[ "a b" = "a b" ]; echo $?'

section "265. NUMERIC COMPARISON"

compare_posix_output "num eq" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "num ne" '[ 5 -ne 6 ]; echo $?'
compare_posix_output "num lt" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "num gt" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "num le" '[ 5 -le 5 ]; echo $?'
compare_posix_output "num ge" '[ 5 -ge 5 ]; echo $?'
compare_posix_output "num zero" '[ 0 -eq 0 ]; echo $?'
compare_posix_output "num neg" '[ -1 -lt 0 ]; echo $?'

section "266. FILE TESTS COMPREHENSIVE"

compare_posix_output "file e" '[ -e /tmp ]; echo $?'
compare_posix_output "file f" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "file d" '[ -d /tmp ]; echo $?'
compare_posix_output "file r" '[ -r /etc/passwd ]; echo $?'
compare_posix_output "file w" '[ -w /tmp ]; echo $?'
compare_posix_output "file x" '[ -x /bin/sh ]; echo $?'
compare_posix_output "file s" '[ -s /etc/passwd ]; echo $?'
compare_posix_output "file L" '[ -L /dev/stdin ] 2>/dev/null; echo $?'

section "267. PRINTF FORMAT SPECIFIERS"

compare_posix_output "printf s" 'printf "%s\n" hello'
compare_posix_output "printf d" 'printf "%d\n" 42'
compare_posix_output "printf i" 'printf "%i\n" 42'
compare_posix_output "printf o" 'printf "%o\n" 8'
compare_posix_output "printf x" 'printf "%x\n" 255'
compare_posix_output "printf X" 'printf "%X\n" 255'
compare_posix_output "printf c" 'printf "%c\n" A'
compare_posix_output "printf percent" 'printf "%%\n"'

section "268. PRINTF WIDTH AND PRECISION"

compare_posix_output "printf width" 'printf "%5d\n" 42'
compare_posix_output "printf zero" 'printf "%05d\n" 42'
compare_posix_output "printf left" 'printf "%-5d|\n" 42'
compare_posix_output "printf prec" 'printf "%.3s\n" hello'
compare_posix_output "printf both" 'printf "%8.3s\n" hello'

section "269. ECHO OPTIONS"

compare_posix_output "echo simple" 'echo hello'
compare_posix_output "echo multi" 'echo a b c'
compare_posix_output "echo n" 'echo -n test; echo done'
compare_posix_output "echo e tab" 'echo -e "a\tb"'
compare_posix_output "echo e nl" 'echo -e "a\nb" | wc -l'

section "270. ENVIRONMENT MANIPULATION"

compare_posix_output "env set" 'X=val; echo $X'
compare_posix_output "env export" 'export X=val; echo $X'
compare_posix_output "env unset" 'X=val; unset X; echo ${X:-unset}'
compare_posix_output "env prefix" 'X=val sh -c "echo \$X"'
compare_posix_output "env readonly" 'readonly X=const; echo $X'
compare_posix_output "env home" 'echo ${HOME:-none} | grep -c "/"'
compare_posix_output "env path" 'echo ${PATH:-none} | grep -c ":"'
compare_posix_output "env pwd" 'echo ${PWD:-none} | grep -c "/"'

section "271. GETOPTS COMPREHENSIVE"

compare_posix_output "getopts single" 'set -- -a; getopts a opt; echo $opt'
compare_posix_output "getopts value" 'set -- -a val; getopts a: opt; echo $opt $OPTARG'
compare_posix_output "getopts multi" 'set -- -ab; getopts ab opt; echo $opt'
compare_posix_output "getopts optind" 'set -- -a -b; OPTIND=1; getopts ab opt; echo $OPTIND'
compare_posix_output "getopts unknown" 'set -- -x; getopts a opt 2>/dev/null; echo $?'
compare_posix_output "getopts missing" 'set -- -a; getopts a: opt 2>/dev/null; echo $?'

section "272. TRAP COMPREHENSIVE"

compare_posix_output "trap list" 'trap 2>/dev/null; echo done'
compare_posix_output "trap set" 'trap "echo trapped" INT; trap | grep -c INT || echo 0'
compare_posix_output "trap reset" 'trap "echo x" INT; trap - INT; echo done'
compare_posix_output "trap ignore" 'trap "" INT; echo done'
compare_posix_output "trap exit" 'sh -c "trap \"echo bye\" EXIT; exit 0" 2>/dev/null || echo done'

section "273. EVAL COMPREHENSIVE"

compare_posix_output "eval simple" 'eval echo hello'
compare_posix_output "eval var" 'x=world; eval echo $x'
compare_posix_output "eval quoted" 'eval "echo test"'
compare_posix_output "eval multi" 'eval "echo a; echo b" | wc -l'
compare_posix_output "eval indirect" 'x=y; y=val; eval echo \$$x'
compare_posix_output "eval assign" 'eval "x=test"; echo $x'
compare_posix_output "eval complex" 'x="echo hello"; eval $x'

section "274. EXEC COMPREHENSIVE"

compare_posix_output "exec fd open" 'exec 3>&1; echo test >&3; exec 3>&-'
compare_posix_output "exec fd close" 'exec 3>&1; exec 3>&-; echo ok'
compare_posix_output "exec redir" 'exec 3>/tmp/e$$; echo test >&3; exec 3>&-; cat /tmp/e$$; rm /tmp/e$$'

section "275. DOT SOURCE COMPREHENSIVE"

compare_posix_output "dot var" 'echo "X=sourced" > /tmp/s$$; . /tmp/s$$; echo $X; rm /tmp/s$$'
compare_posix_output "dot func" 'echo "f() { echo func; }" > /tmp/s$$; . /tmp/s$$; f; rm /tmp/s$$'
compare_posix_output "dot persist" 'echo "Y=persist" > /tmp/s$$; . /tmp/s$$; echo $Y; rm /tmp/s$$'

section "276. COMMAND BUILTIN"

compare_posix_output "command echo" 'command echo hello'
compare_posix_output "command v" 'command -v echo | grep -c echo'
compare_posix_output "command V" 'command -V echo 2>/dev/null | grep -c echo || echo 1'
compare_posix_output "command p" 'command -p echo hello'
compare_posix_output "command bypass" 'echo() { printf "func\n"; }; command echo builtin; unset -f echo'

section "277. TYPE BUILTIN"

compare_posix_output "type builtin" 'type echo 2>/dev/null | head -1 | grep -c echo || echo 1'
compare_posix_output "type external" 'type cat 2>/dev/null | head -1 | grep -c cat || echo 1'
compare_posix_output "type notfound" 'type nonexistent_xyz 2>&1 | grep -ci "not found" || echo 0'

section "278. HASH BUILTIN"

compare_posix_output "hash show" 'hash 2>/dev/null; echo $?'
compare_posix_output "hash clear" 'hash -r 2>/dev/null; echo $?'

section "279. ULIMIT BUILTIN"

compare_posix_output "ulimit show" 'ulimit 2>/dev/null | grep -c "[0-9]" || echo 1'
compare_posix_output "ulimit n" 'ulimit -n 2>/dev/null | grep -c "[0-9]" || echo 1'
compare_posix_output "ulimit a" 'ulimit -a 2>/dev/null | wc -l'

section "280. UMASK BUILTIN"

compare_posix_output "umask show" 'umask | grep -c "[0-7]"'
compare_posix_output "umask symbolic" 'umask -S | grep -c "u="'
compare_posix_output "umask set" 'old=$(umask); umask 022; umask $old; echo done'

section "281. TIMES BUILTIN"

compare_posix_output "times output" 'times 2>&1 | head -1 | grep -c "[0-9]" || echo 0'

section "282. KILL BUILTIN"

compare_posix_output "kill list" 'kill -l | head -1 | grep -c "[A-Z]" || echo 1'
compare_posix_output "kill l num" 'kill -l 1 2>/dev/null | grep -ci "hup\|term" || echo 0'

section "283. CD COMPREHENSIVE"

compare_posix_output "cd tmp" 'cd /tmp && pwd'
compare_posix_output "cd home" 'cd ~ && pwd | grep -c "/"'
compare_posix_output "cd dash" 'cd /tmp; cd /; cd - 2>/dev/null | grep -c "/" || pwd'
compare_posix_output "cd dotdot" 'cd /tmp; cd ..; pwd | grep -v "^/tmp$" | grep -c "/"'
compare_posix_output "cd absolute" 'cd /usr && pwd'
compare_posix_output "cd relative" 'cd /; cd tmp && pwd'
compare_posix_output "cd oldpwd" 'cd /tmp; cd /; echo $OLDPWD | grep -c tmp'

section "284. PWD COMPREHENSIVE"

compare_posix_output "pwd basic" 'pwd | grep -c "/"'
compare_posix_output "pwd L" 'pwd -L 2>/dev/null | grep -c "/" || pwd | grep -c "/"'
compare_posix_output "pwd P" 'pwd -P 2>/dev/null | grep -c "/" || pwd | grep -c "/"'
compare_posix_output "pwd var" 'echo $PWD | grep -c "/"'

section "285. COLON BUILTIN"

compare_posix_output "colon simple" ':; echo $?'
compare_posix_output "colon args" ': arg1 arg2; echo $?'
compare_posix_output "colon in if" 'if :; then echo yes; fi'
compare_posix_output "colon in while" 'n=0; while :; do n=$((n+1)); [ $n -ge 2 ] && break; done; echo $n'
compare_posix_output "colon expansion" ': ${x:=default}; echo $x'

section "286. TRUE FALSE BUILTINS"

compare_posix_output "true exit" 'true; echo $?'
compare_posix_output "false exit" 'false; echo $?'
compare_posix_output "true in if" 'if true; then echo yes; fi'
compare_posix_output "false in if" 'if false; then echo no; else echo yes; fi'
compare_posix_output "true and" 'true && echo yes'
compare_posix_output "false or" 'false || echo yes'

section "287. RETURN BUILTIN"

compare_posix_output "return 0" 'f() { return 0; }; f; echo $?'
compare_posix_output "return 1" 'f() { return 1; }; f; echo $?'
compare_posix_output "return 42" 'f() { return 42; }; f; echo $?'
compare_posix_output "return 255" 'f() { return 255; }; f; echo $?'
compare_posix_output "return implicit" 'f() { true; }; f; echo $?'
compare_posix_output "return last" 'f() { false; }; f; echo $?'

section "288. EXIT BUILTIN"

compare_posix_output "exit 0" '(exit 0); echo $?'
compare_posix_output "exit 1" '(exit 1); echo $?'
compare_posix_output "exit 42" '(exit 42); echo $?'
compare_posix_output "exit 255" '(exit 255); echo $?'
compare_posix_output "exit implicit" '(true); echo $?'

section "289. BREAK BUILTIN"

compare_posix_output "break for" 'for i in 1 2 3; do [ $i -eq 2 ] && break; echo $i; done'
compare_posix_output "break while" 'n=0; while true; do n=$((n+1)); [ $n -ge 2 ] && break; done; echo $n'
compare_posix_output "break nested" 'for i in 1 2; do for j in a b; do break; done; echo $i; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do break 2; done; done; echo done'

section "290. CONTINUE BUILTIN"

compare_posix_output "continue for" 'for i in 1 2 3; do [ $i -eq 2 ] && continue; echo $i; done'
compare_posix_output "continue while" 'n=0; while [ $n -lt 3 ]; do n=$((n+1)); [ $n -eq 2 ] && continue; echo $n; done'
compare_posix_output "continue nested" 'for i in 1 2; do for j in a b; do continue; done; echo $i; done'
compare_posix_output "continue 2" 'for i in 1 2; do for j in a b; do continue 2; done; echo never; done; echo done'

section "291. SHIFT BUILTIN"

compare_posix_output "shift once" 'set -- a b c; shift; echo $1'
compare_posix_output "shift twice" 'set -- a b c; shift; shift; echo $1'
compare_posix_output "shift n" 'set -- a b c d e; shift 3; echo $1'
compare_posix_output "shift all" 'set -- a b; shift 2; echo ${1:-empty}'
compare_posix_output "shift count" 'set -- a b c; shift; echo $#'

section "292. SET BUILTIN COMPREHENSIVE"

compare_posix_output "set args" 'set -- a b c; echo $1 $2 $3'
compare_posix_output "set clear" 'set -- a b; set --; echo ${1:-none}'
compare_posix_output "set e" 'set -e; true; echo ok'
compare_posix_output "set f" 'set -f; echo *; set +f'
compare_posix_output "set x" 'set +x; echo ok'
compare_posix_output "set minus" 'echo $- | grep -c "."'
compare_posix_output "set show" 'X=val; set | grep -c "^X=" || echo 0'

section "293. UNSET BUILTIN"

compare_posix_output "unset var" 'X=val; unset X; echo ${X:-gone}'
compare_posix_output "unset func" 'f() { echo func; }; unset -f f 2>/dev/null; type f 2>&1 | grep -c "not found" || echo 0'
compare_posix_output "unset v" 'X=val; unset -v X; echo ${X:-gone}'
compare_posix_output "unset multi" 'X=1 Y=2; unset X Y; echo ${X:-a} ${Y:-b}'

section "294. EXPORT BUILTIN"

compare_posix_output "export simple" 'export X=val; echo $X'
compare_posix_output "export existing" 'X=val; export X; echo $X'
compare_posix_output "export multi" 'export X=1 Y=2; echo $X $Y'
compare_posix_output "export child" 'export X=val; sh -c "echo \$X"'
compare_posix_output "export list" 'export 2>/dev/null | head -1 | grep -c "=" || echo 0'

section "295. READONLY BUILTIN"

compare_posix_output "readonly simple" 'readonly X=val; echo $X'
compare_posix_output "readonly existing" 'X=val; readonly X; echo $X'
compare_posix_output "readonly list" 'readonly 2>/dev/null | wc -l'

section "296. LOCAL SCOPE SIMULATION"

compare_posix_output "scope global" 'X=global; f() { echo $X; }; f'
compare_posix_output "scope modify" 'X=old; f() { X=new; }; f; echo $X'
compare_posix_output "scope subshell" 'X=outer; (X=inner; echo $X); echo $X'
compare_posix_output "scope func arg" 'f() { echo $1; }; f arg'
compare_posix_output "scope nested" 'f() { g() { echo inner; }; g; }; f'

section "297. GLOB PATTERNS COMPREHENSIVE"

compare_posix_output "glob star" 'set -f; echo *; set +f'
compare_posix_output "glob question" 'set -f; echo ?; set +f'
compare_posix_output "glob bracket" 'set -f; echo [abc]; set +f'
compare_posix_output "glob range" 'set -f; echo [a-z]; set +f'
compare_posix_output "glob neg" 'set -f; echo [!abc]; set +f'
compare_posix_output "glob quoted" 'echo "*"'
compare_posix_output "glob escaped" 'echo \*'
compare_posix_output "glob in var" 'x="*"; echo "$x"'

section "298. TILDE EXPANSION COMPREHENSIVE"

compare_posix_output "tilde home" 'echo ~ | grep -c "/"'
compare_posix_output "tilde slash" 'echo ~/ | grep -c "/"'
compare_posix_output "tilde quoted" 'echo "~"'
compare_posix_output "tilde var" 'x=~; echo $x | grep -c "/"'
compare_posix_output "tilde plus" 'cd /tmp; echo ~+ | grep -c "/"'
compare_posix_output "tilde minus" 'cd /tmp; cd /; echo ~- | grep -c tmp'

section "299. BRACE EXPANSION TESTS"

compare_posix_output "brace literal" 'echo {a,b,c}'
compare_posix_output "brace seq" 'echo {1..3} 2>/dev/null || echo "1 2 3"'
compare_posix_output "brace prefix" 'echo pre{a,b} 2>/dev/null || echo "prea preb"'
compare_posix_output "brace suffix" 'echo {a,b}suf 2>/dev/null || echo "asuf bsuf"'

section "300. WORD SPLITTING COMPREHENSIVE"

compare_posix_output "split default" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "split quoted" 'x="a b c"; set -- "$x"; echo $#'
compare_posix_output "split ifs" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "split empty ifs" 'IFS=""; x="a b"; set -- $x; echo $#'
compare_posix_output "split unset ifs" 'unset IFS; x="a  b"; set -- $x; echo $#'
compare_posix_output "split whitespace" 'x="  a  b  "; set -- $x; echo $#'
compare_posix_output "split preserve" 'x="a  b"; echo "$x" | grep -c "  "'
compare_posix_output "split tab" 'x="a	b"; set -- $x; echo $#'

section "301. FIELD SPLITTING EDGE CASES"

compare_posix_output "field leading" 'IFS=:; x=":a:b"; set -- $x; echo $# $1'
compare_posix_output "field trailing" 'IFS=:; x="a:b:"; set -- $x; echo $#'
compare_posix_output "field empty" 'IFS=:; x="a::b"; set -- $x; echo $#'
compare_posix_output "field multi ifs" 'IFS=":;"; x="a:b;c"; set -- $x; echo $#'

section "302. COMMAND SUBSTITUTION COMPREHENSIVE"

compare_posix_output "cmdsub simple" 'echo $(echo hello)'
compare_posix_output "cmdsub nested" 'echo $(echo $(echo deep))'
compare_posix_output "cmdsub backtick" 'echo `echo hello`'
compare_posix_output "cmdsub var" 'x=$(echo val); echo $x'
compare_posix_output "cmdsub arith" 'echo $(echo $((1+1)))'
compare_posix_output "cmdsub pipe" 'echo $(echo test | cat)'
compare_posix_output "cmdsub multiline" 'x=$(printf "a\nb"); echo "$x" | wc -l'
compare_posix_output "cmdsub exit" '$(exit 5); echo $?'
compare_posix_output "cmdsub empty" 'x=$(true); echo "[$x]"'

section "303. ARITHMETIC EXPANSION COMPREHENSIVE"

compare_posix_output "arith simple" 'echo $((1+1))'
compare_posix_output "arith all ops" 'echo $((2+3-1*2/1%3))'
compare_posix_output "arith paren" 'echo $(((1+2)*3))'
compare_posix_output "arith var" 'x=5; echo $((x+1))'
compare_posix_output "arith compare" 'echo $((5 > 3))'
compare_posix_output "arith logical" 'echo $((1 && 1))'
compare_posix_output "arith ternary" 'echo $((1 ? 10 : 20))'
compare_posix_output "arith nested" 'echo $(($((1+1)) + 1))'
compare_posix_output "arith negative" 'echo $((-5))'
compare_posix_output "arith zero" 'echo $((0))'

section "304. PATTERN MATCHING COMPREHENSIVE"

compare_posix_output "pat suffix" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "pat suffix long" 'x=a.b.c; echo ${x%%.*}'
compare_posix_output "pat prefix" 'x=prefix_name; echo ${x#prefix_}'
compare_posix_output "pat prefix long" 'x=a.b.c; echo ${x##*.}'
compare_posix_output "pat star" 'x=hello; echo ${x%l*}'
compare_posix_output "pat question" 'x=hello; echo ${x%?}'
compare_posix_output "pat no match" 'x=hello; echo ${x%.txt}'
compare_posix_output "pat empty" 'x=; echo ${x%.txt}'

section "305. SPECIAL PARAMETER COMPREHENSIVE"

compare_posix_output "param zero" 'echo ${0:-shell} | grep -c "."'
compare_posix_output "param hash" 'set -- a b c; echo $#'
compare_posix_output "param question" 'true; echo $?'
compare_posix_output "param dollar" 'echo $$ | grep -c "[0-9]"'
compare_posix_output "param at" 'set -- a b c; echo "$@"'
compare_posix_output "param star" 'set -- a b c; echo "$*"'
compare_posix_output "param minus" 'echo $- | grep -c "."'
compare_posix_output "param at loop" 'set -- a b c; for x in "$@"; do echo $x; done | wc -l'
compare_posix_output "param star loop" 'set -- a b c; for x in "$*"; do echo $x; done | wc -l'

section "306. CONTROL FLOW EDGE CASES"

compare_posix_output "if true simple" 'if true; then echo yes; fi'
compare_posix_output "if false simple" 'if false; then echo no; fi; echo done'
compare_posix_output "if else" 'if false; then echo no; else echo yes; fi'
compare_posix_output "if elif" 'if false; then echo 1; elif true; then echo 2; fi'
compare_posix_output "if nested" 'if true; then if true; then echo deep; fi; fi'
compare_posix_output "if compound" 'if true && true; then echo yes; fi'
compare_posix_output "if pipeline" 'if echo test | grep -q test; then echo yes; fi'
compare_posix_output "if negation" 'if ! false; then echo yes; fi'

section "307. FOR LOOP EDGE CASES"

compare_posix_output "for basic" 'for i in a b c; do echo $i; done | wc -l'
compare_posix_output "for single" 'for i in only; do echo $i; done'
compare_posix_output "for empty" 'for i in; do echo $i; done; echo done'
compare_posix_output "for numbers" 'for i in 1 2 3 4 5; do echo $i; done | wc -l'
compare_posix_output "for var" 'list="a b c"; for i in $list; do echo $i; done | wc -l'
compare_posix_output "for quoted" 'for i in "a b" "c d"; do echo "$i"; done | wc -l'
compare_posix_output "for break" 'for i in 1 2 3; do [ $i -eq 2 ] && break; echo $i; done'
compare_posix_output "for continue" 'for i in 1 2 3; do [ $i -eq 2 ] && continue; echo $i; done'

section "308. WHILE LOOP EDGE CASES"

compare_posix_output "while count" 'n=3; while [ $n -gt 0 ]; do echo $n; n=$((n-1)); done | wc -l'
compare_posix_output "while false" 'while false; do echo never; done; echo done'
compare_posix_output "while true break" 'n=0; while true; do n=$((n+1)); [ $n -ge 3 ] && break; done; echo $n'
compare_posix_output "while compound" 'n=2; while [ $n -gt 0 ] && true; do n=$((n-1)); done; echo $n'
compare_posix_output "while pipeline" 'echo ok | while true; do echo yes; break; done'

section "309. UNTIL LOOP EDGE CASES"

compare_posix_output "until count" 'n=0; until [ $n -ge 3 ]; do n=$((n+1)); done; echo $n'
compare_posix_output "until true" 'until true; do echo never; done; echo done'
compare_posix_output "until false" 'n=0; until false; do n=$((n+1)); [ $n -ge 2 ] && break; done; echo $n'

section "310. CASE EDGE CASES"

compare_posix_output "case simple" 'case x in x) echo yes;; esac'
compare_posix_output "case default" 'case x in y) echo no;; *) echo default;; esac'
compare_posix_output "case multi" 'case a in a|b|c) echo match;; esac'
compare_posix_output "case glob" 'case hello in h*) echo match;; esac'
compare_posix_output "case question" 'case ab in ??) echo two;; esac'
compare_posix_output "case bracket" 'case a in [abc]) echo match;; esac'
compare_posix_output "case empty" 'case "" in "") echo empty;; esac'
compare_posix_output "case var" 'x=test; case $x in test) echo yes;; esac'
compare_posix_output "case quoted" 'case "a b" in "a b") echo space;; esac'
compare_posix_output "case no match" 'case x in y) echo no;; esac; echo done'

section "311. FUNCTION EDGE CASES"

compare_posix_output "func simple" 'f() { echo hello; }; f'
compare_posix_output "func args" 'f() { echo $1 $2; }; f a b'
compare_posix_output "func return" 'f() { return 42; }; f; echo $?'
compare_posix_output "func local" 'x=outer; f() { x=inner; }; f; echo $x'
compare_posix_output "func recursive" 'f() { [ $1 -le 0 ] && echo done || f $(($1-1)); }; f 3'
compare_posix_output "func in func" 'f() { g() { echo inner; }; g; }; f'
compare_posix_output "func pipe" 'f() { echo test; }; f | cat'
compare_posix_output "func subshell" 'f() { echo func; }; (f)'
compare_posix_output "func all args" 'f() { echo $@; }; f a b c'
compare_posix_output "func count" 'f() { echo $#; }; f a b c d e'

section "312. REDIRECTION EDGE CASES"

compare_posix_output "redir out" 'echo test > /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir append" 'echo a > /tmp/r$$; echo b >> /tmp/r$$; wc -l < /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir in" 'echo test > /tmp/r$$; cat < /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir err" 'echo err >&2 2>/dev/null; echo ok'
compare_posix_output "redir fd" 'echo test 2>&1 | cat'
compare_posix_output "redir null" 'echo test > /dev/null; echo $?'
compare_posix_output "redir here" 'cat <<EOF
test
EOF'
compare_posix_output "redir here var" 'x=val; cat <<EOF
$x
EOF'

section "313. PIPELINE EDGE CASES"

compare_posix_output "pipe simple" 'echo test | cat'
compare_posix_output "pipe chain" 'echo test | cat | cat | cat'
compare_posix_output "pipe grep" 'echo hello | grep h'
compare_posix_output "pipe wc" 'printf "a\nb\nc\n" | wc -l'
compare_posix_output "pipe head" 'seq 1 10 | head -3'
compare_posix_output "pipe tail" 'seq 1 10 | tail -3'
compare_posix_output "pipe sort" 'printf "c\na\nb\n" | sort'
compare_posix_output "pipe subshell" '(echo test) | cat'
compare_posix_output "pipe brace" '{ echo test; } | cat'
compare_posix_output "pipe status" 'true | false; echo $?'

section "314. SUBSHELL EDGE CASES"

compare_posix_output "sub simple" '(echo sub)'
compare_posix_output "sub var" '(x=inner; echo $x)'
compare_posix_output "sub no leak" 'x=outer; (x=inner); echo $x'
compare_posix_output "sub exit" '(exit 42); echo $?'
compare_posix_output "sub cd" '(cd /tmp; pwd)'
compare_posix_output "sub nested" '((echo deep))'
compare_posix_output "sub pipe" '(echo a; echo b) | wc -l'
compare_posix_output "sub multi" '(echo a); (echo b)'
compare_posix_output "sub compound" '(echo a; echo b; echo c) | wc -l'

section "315. BRACE GROUP EDGE CASES"

compare_posix_output "brace simple" '{ echo test; }'
compare_posix_output "brace multi" '{ echo a; echo b; }'
compare_posix_output "brace var" '{ x=val; }; echo $x'
compare_posix_output "brace pipe" '{ echo test; } | cat'
compare_posix_output "brace nested" '{ { echo deep; }; }'
compare_posix_output "brace and sub" '{ (echo sub); }'
compare_posix_output "brace redir" '{ echo test; } > /tmp/b$$; cat /tmp/b$$; rm /tmp/b$$'

section "316. LOGICAL OPERATOR EDGE CASES"

compare_posix_output "and both true" 'true && true; echo $?'
compare_posix_output "and first false" 'false && echo never; echo $?'
compare_posix_output "and second false" 'true && false; echo $?'
compare_posix_output "or both false" 'false || false; echo $?'
compare_posix_output "or first true" 'true || echo never; echo $?'
compare_posix_output "or second true" 'false || true; echo $?'
compare_posix_output "not true" '! true; echo $?'
compare_posix_output "not false" '! false; echo $?'
compare_posix_output "chain and" 'true && true && true; echo $?'
compare_posix_output "chain or" 'false || false || true; echo $?'
compare_posix_output "mixed" 'true && false || echo fallback'

section "317. QUOTING COMPREHENSIVE"

compare_posix_output "quote single" "echo 'hello'"
compare_posix_output "quote double" 'echo "hello"'
compare_posix_output "quote escape" 'echo hello\ world'
compare_posix_output "quote mixed" "echo 'a'\"b\"c"
compare_posix_output "quote empty single" "echo ''"
compare_posix_output "quote empty double" 'echo ""'
compare_posix_output "quote dollar" 'echo "\$x"'
compare_posix_output "quote backtick" 'echo "\`"'
compare_posix_output "quote backslash" 'echo "\\"'
compare_posix_output "quote newline" 'echo "a
b" | wc -l'

section "318. VARIABLE COMPREHENSIVE"

compare_posix_output "var simple" 'x=val; echo $x'
compare_posix_output "var empty" 'x=; echo "[$x]"'
compare_posix_output "var quoted" 'x="a b"; echo "$x"'
compare_posix_output "var concat" 'x=hel; y=lo; echo $x$y'
compare_posix_output "var braces" 'x=val; echo ${x}'
compare_posix_output "var default" 'echo ${undef:-default}'
compare_posix_output "var alt" 'x=val; echo ${x:+alt}'
compare_posix_output "var length" 'x=hello; echo ${#x}'
compare_posix_output "var suffix" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "var prefix" 'x=pre_name; echo ${x#pre_}'

section "319. ARITHMETIC COMPREHENSIVE"

compare_posix_output "arith add" 'echo $((5+3))'
compare_posix_output "arith sub" 'echo $((5-3))'
compare_posix_output "arith mul" 'echo $((5*3))'
compare_posix_output "arith div" 'echo $((15/3))'
compare_posix_output "arith mod" 'echo $((17%5))'
compare_posix_output "arith paren" 'echo $(((1+2)*3))'
compare_posix_output "arith var" 'x=5; echo $((x+1))'
compare_posix_output "arith neg" 'echo $((-5))'
compare_posix_output "arith cmp" 'echo $((5>3))'
compare_posix_output "arith log" 'echo $((1&&1))'

section "320. TEST COMPREHENSIVE"

compare_posix_output "test eq" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "test ne" '[ 5 -ne 6 ]; echo $?'
compare_posix_output "test lt" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "test gt" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "test le" '[ 5 -le 5 ]; echo $?'
compare_posix_output "test ge" '[ 5 -ge 5 ]; echo $?'
compare_posix_output "test str eq" '[ "a" = "a" ]; echo $?'
compare_posix_output "test str ne" '[ "a" != "b" ]; echo $?'
compare_posix_output "test z" '[ -z "" ]; echo $?'
compare_posix_output "test n" '[ -n "x" ]; echo $?'
compare_posix_output "test f" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "test d" '[ -d /tmp ]; echo $?'
compare_posix_output "test not" '[ ! 1 -eq 2 ]; echo $?'

# ============================================================================
# SECTION 321-340: PARAMETER EXPANSION WITHOUT COLON (POSIX 2.6.2)
# These test unset-only behavior vs null-or-unset behavior
# ============================================================================

section "321. USE DEFAULT WITHOUT COLON"

# ${parameter-word} - substitute word only if parameter is UNSET (not for null)
compare_posix_output "default unset only" 'unset x; echo ${x-default}'
compare_posix_output "default set empty" 'x=""; echo "[${x-default}]"'
compare_posix_output "default set value" 'x=val; echo ${x-default}'
compare_posix_output "colon default unset" 'unset x; echo ${x:-default}'
compare_posix_output "colon default empty" 'x=""; echo "[${x:-default}]"'
compare_posix_output "colon default value" 'x=val; echo ${x:-default}'

section "322. ASSIGN DEFAULT WITHOUT COLON"

# ${parameter=word} - assign only if UNSET
compare_posix_output "assign unset only" 'unset x; echo ${x=assigned}; echo $x'
compare_posix_output "assign set empty" 'x=""; echo "[${x=assigned}]"; echo "[$x]"'
compare_posix_output "colon assign unset" 'unset x; echo ${x:=assigned}; echo $x'
compare_posix_output "colon assign empty" 'x=""; echo "[${x:=assigned}]"; echo "[$x]"'

section "323. ERROR IF UNSET WITHOUT COLON"

# ${parameter?word} - error only if UNSET
compare_posix_output "error unset only" '(unset x; echo ${x?errmsg}) 2>/dev/null; echo $?'
compare_posix_output "error set empty" 'x=""; echo "[${x?errmsg}]"'
compare_posix_output "colon error unset" '(unset x; echo ${x:?errmsg}) 2>/dev/null; echo $?'
compare_posix_output "colon error empty" '(x=""; echo ${x:?errmsg}) 2>/dev/null; echo $?'

section "324. ALT VALUE WITHOUT COLON"

# ${parameter+word} - substitute word if parameter is SET (even if null)
compare_posix_output "alt unset" 'unset x; echo "[${x+alt}]"'
compare_posix_output "alt empty" 'x=""; echo "[${x+alt}]"'
compare_posix_output "alt value" 'x=val; echo "[${x+alt}]"'
compare_posix_output "colon alt unset" 'unset x; echo "[${x:+alt}]"'
compare_posix_output "colon alt empty" 'x=""; echo "[${x:+alt}]"'
compare_posix_output "colon alt value" 'x=val; echo "[${x:+alt}]"'

# ============================================================================
# SECTION 325-335: SPECIAL PARAMETERS (POSIX 2.5.2)
# ============================================================================

section "325. DOLLAR AT VS DOLLAR STAR"

compare_posix_output "at basic" 'set -- a b c; echo "$@"'
compare_posix_output "star basic" 'set -- a b c; echo "$*"'
compare_posix_output "at count" 'set -- a b c; for x in "$@"; do echo $x; done | wc -l'
compare_posix_output "star count" 'set -- a b c; for x in "$*"; do echo $x; done | wc -l'
compare_posix_output "at with spaces" 'set -- "a b" "c d"; for x in "$@"; do echo "[$x]"; done'
compare_posix_output "star with spaces" 'set -- "a b" "c d"; for x in "$*"; do echo "[$x]"; done'

section "326. IFS AFFECTS DOLLAR STAR"

compare_posix_output "star ifs colon" 'IFS=:; set -- a b c; echo "$*"'
compare_posix_output "star ifs comma" 'IFS=,; set -- x y z; echo "$*"'
compare_posix_output "star ifs empty" 'IFS=""; set -- a b c; echo "$*"'
compare_posix_output "at ifs colon" 'IFS=:; set -- a b c; echo "$@"'

section "327. DOLLAR HASH"

compare_posix_output "hash zero" 'set --; echo $#'
compare_posix_output "hash one" 'set -- a; echo $#'
compare_posix_output "hash five" 'set -- a b c d e; echo $#'
compare_posix_output "hash after shift" 'set -- a b c; shift; echo $#'

section "328. DOLLAR QUESTION"

compare_posix_output "question success" 'true; echo $?'
compare_posix_output "question fail" 'false; echo $?'
compare_posix_output "question exit" '(exit 42); echo $?'
compare_posix_output "question pipe" 'true | false; echo $?'

section "329. DOLLAR HYPHEN"

compare_posix_output "hyphen basic" 'echo $- | grep -c .'
compare_posix_output "hyphen after set" 'set -f; case "$-" in *f*) echo yes;; esac; set +f'
compare_posix_output "hyphen in subsh" '(echo $-) | grep -c .'

section "330. DOLLAR DOLLAR"

compare_posix_output "pid numeric" 'echo $$ | grep -cE "^[0-9]+$"'
compare_posix_output "pid same subsh" 'x=$$; (echo $(( $$ == x ? 1 : 0 )))'
compare_posix_output "pid consistent" 'x=$$; echo $(( $$ == x ))'

section "331. DOLLAR ZERO"

compare_posix_output "zero set" 'echo $0 | grep -c .'
compare_posix_output "zero in func" 'f() { echo $0 | grep -c .; }; f'

section "332. LINENO VARIABLE"

compare_posix_output "lineno set" 'echo $LINENO | grep -cE "^[0-9]+$"'
compare_posix_output "lineno in script" 'echo "echo \$LINENO" > /tmp/ln$$; sh /tmp/ln$$; rm /tmp/ln$$'

section "333. PPID VARIABLE"

compare_posix_output "ppid set" 'echo $PPID | grep -cE "^[0-9]+$"'
compare_posix_output "ppid same subsh" '(echo $PPID) | grep -cE "^[0-9]+$"'
compare_posix_output "ppid not self" 'test $PPID -ne $$; echo $?'

section "334. PWD AND OLDPWD"

compare_posix_output "pwd set" 'echo $PWD | grep -c /'
compare_posix_output "pwd equals pwd" 'test "$PWD" = "$(pwd)"; echo $?'
compare_posix_output "oldpwd after cd" 'cd /tmp; cd /; echo $OLDPWD | grep -c tmp'

section "335. PS VARIABLES"

compare_posix_output "ps1 set" 'echo ${PS1:-unset} | grep -c .'
compare_posix_output "ps2 set" 'echo ${PS2:-unset} | grep -c .'
compare_posix_output "ps4 default" 'echo ${PS4:-unset} | grep -c .'

# ============================================================================
# SECTION 336-345: ADDITIONAL FILE TEST OPERATORS (POSIX test utility)
# ============================================================================

section "336. TEST TERMINAL FD"

compare_posix_output "test t stdin" '[ -t 0 ] </dev/null; echo $?'
compare_posix_output "test t stdout" '[ -t 1 ] >/dev/null; echo $?'
compare_posix_output "test t invalid" '[ -t 999 ]; echo $?'

section "337. TEST SETUID SETGID"

compare_posix_output "test u nofile" '[ -u /etc/passwd ]; echo $?'
compare_posix_output "test g nofile" '[ -g /etc/passwd ]; echo $?'

section "338. TEST SPECIAL FILES"

compare_posix_output "test b regular" '[ -b /etc/passwd ]; echo $?'
compare_posix_output "test c regular" '[ -c /etc/passwd ]; echo $?'
compare_posix_output "test c tty" '[ -c /dev/tty ] 2>/dev/null; echo $?'
compare_posix_output "test p regular" '[ -p /etc/passwd ]; echo $?'
compare_posix_output "test S regular" '[ -S /etc/passwd ]; echo $?'

section "339. TEST FILE PERMS"

compare_posix_output "test r readable" '[ -r /etc/passwd ]; echo $?'
compare_posix_output "test w writable" 'touch /tmp/tw$$; [ -w /tmp/tw$$ ]; echo $?; rm /tmp/tw$$'
compare_posix_output "test x dir" '[ -x /tmp ]; echo $?'
compare_posix_output "test r nonexist" '[ -r /nonexistent$$ ]; echo $?'

section "340. TEST STRING PRIMARIES"

compare_posix_output "test str alone" '[ "nonempty" ]; echo $?'
compare_posix_output "test str empty" '[ "" ]; echo $?'
compare_posix_output "test str n" '[ -n "abc" ]; echo $?'
compare_posix_output "test str n empty" '[ -n "" ]; echo $?'
compare_posix_output "test str z" '[ -z "" ]; echo $?'
compare_posix_output "test str z non" '[ -z "abc" ]; echo $?'

section "341. TEST STRING COMPARE"

compare_posix_output "test str eq" '[ "abc" = "abc" ]; echo $?'
compare_posix_output "test str ne" '[ "abc" = "def" ]; echo $?'
compare_posix_output "test str neq" '[ "abc" != "def" ]; echo $?'
compare_posix_output "test str neq same" '[ "abc" != "abc" ]; echo $?'

section "342. TEST NUMERIC COMPARE"

compare_posix_output "test num eq" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "test num ne" '[ 5 -ne 3 ]; echo $?'
compare_posix_output "test num lt" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "test num le" '[ 5 -le 5 ]; echo $?'
compare_posix_output "test num gt" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "test num ge" '[ 5 -ge 5 ]; echo $?'
compare_posix_output "test num neg" '[ -5 -lt 0 ]; echo $?'

section "343. TEST COMPOUND"

compare_posix_output "test not" '[ ! -d /tmp ]; echo $?'
compare_posix_output "test not false" '[ ! -d /nonexistent ]; echo $?'
compare_posix_output "test and" '[ -d /tmp -a -f /etc/passwd ]; echo $?'
compare_posix_output "test or" '[ -d /nonexistent -o -f /etc/passwd ]; echo $?'
compare_posix_output "test parens" '[ \( -d /tmp \) ]; echo $?'

section "344. TEST EDGE CASES"

compare_posix_output "test no args" '[ ]; echo $?'
compare_posix_output "test one arg" '[ x ]; echo $?'
compare_posix_output "test empty arg" '[ "" ]; echo $?'
compare_posix_output "test dash arg" '[ "-n" = "-n" ]; echo $?'

section "345. TEST BUILTIN BRACKET"

compare_posix_output "bracket basic" '[ 1 -eq 1 ]; echo $?'
compare_posix_output "bracket string" '[ "a" = "a" ]; echo $?'
compare_posix_output "bracket file" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "bracket missing bracket" '[ 1 -eq 1 2>/dev/null; echo $?'

# ============================================================================
# SECTION 346-355: REDIRECTION (POSIX 2.7)
# ============================================================================

section "346. INPUT REDIRECTION"

compare_posix_output "redir input" 'echo test > /tmp/ri$$; cat < /tmp/ri$$; rm /tmp/ri$$'
compare_posix_output "redir input fd" 'echo test > /tmp/ri$$; cat 0< /tmp/ri$$; rm /tmp/ri$$'

section "347. OUTPUT REDIRECTION"

compare_posix_output "redir output" 'echo test > /tmp/ro$$; cat /tmp/ro$$; rm /tmp/ro$$'
compare_posix_output "redir output fd" 'echo test 1> /tmp/ro$$; cat /tmp/ro$$; rm /tmp/ro$$'
compare_posix_output "redir clobber" 'echo a > /tmp/ro$$; echo b > /tmp/ro$$; cat /tmp/ro$$; rm /tmp/ro$$'

section "348. APPEND REDIRECTION"

compare_posix_output "redir append" 'echo a > /tmp/ra$$; echo b >> /tmp/ra$$; cat /tmp/ra$$; rm /tmp/ra$$'
compare_posix_output "redir append new" 'rm -f /tmp/ra$$; echo x >> /tmp/ra$$; cat /tmp/ra$$; rm /tmp/ra$$'

section "349. STDERR REDIRECTION"

compare_posix_output "redir stderr" 'ls /nonexistent$$ 2>/dev/null; echo done'
compare_posix_output "redir stderr to file" 'ls /nonexistent$$ 2>/tmp/re$$; cat /tmp/re$$ | grep -c .; rm /tmp/re$$'
compare_posix_output "redir both" '{ echo out; ls /nonexistent$$; } >/tmp/re$$ 2>&1; grep -c . /tmp/re$$; rm /tmp/re$$'

section "350. FD DUPLICATION"

compare_posix_output "dup stdout to stderr" 'echo test >&2 2>/tmp/rd$$; cat /tmp/rd$$; rm /tmp/rd$$'
compare_posix_output "dup stderr to stdout" '{ ls /nonexistent$$; } 2>&1 | grep -c .'
compare_posix_output "dup close" 'exec 3>/tmp/rd$$; echo test >&3; exec 3>&-; cat /tmp/rd$$; rm /tmp/rd$$'

section "351. READ WRITE REDIRECTION"

compare_posix_output "redir rw" 'echo test > /tmp/rw$$; exec 3<>/tmp/rw$$; cat <&3; exec 3>&-; rm /tmp/rw$$'

section "352. HEREDOC BASIC"

compare_posix_output "heredoc simple" 'cat <<EOF
hello
EOF'
compare_posix_output "heredoc multi" 'cat <<EOF
line1
line2
line3
EOF'

section "353. HEREDOC EXPANSION"

compare_posix_output "heredoc var" 'x=value; cat <<EOF
$x
EOF'
compare_posix_output "heredoc cmd" 'cat <<EOF
$(echo hello)
EOF'
compare_posix_output "heredoc arith" 'cat <<EOF
$((1+2))
EOF'

section "354. HEREDOC QUOTED DELIM"

compare_posix_output "heredoc no expand" "cat <<'EOF'
\$x
EOF"
compare_posix_output "heredoc quote double" 'cat <<"EOF"
$x
EOF'

section "355. HEREDOC TAB STRIP"

compare_posix_output "heredoc dash" 'cat <<-EOF
	hello
	EOF'

# ============================================================================
# SECTION 356-365: SPECIAL BUILTINS ERROR HANDLING (POSIX 2.14)
# ============================================================================

section "356. BREAK CONTINUE"

compare_posix_output "break basic" 'for i in 1 2 3; do echo $i; break; done'
compare_posix_output "break nested" 'for i in 1 2; do for j in a b; do echo $i$j; break; done; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do echo $i$j; break 2; done; done'
compare_posix_output "continue basic" 'for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; echo $i; done'
compare_posix_output "continue 2" 'for i in 1 2 3; do for j in a b; do if [ $j = a ]; then continue 2; fi; echo $i$j; done; done'

section "357. COLON COMMAND"

compare_posix_output "colon return" ': ; echo $?'
compare_posix_output "colon with args" ': arg1 arg2 arg3; echo $?'
compare_posix_output "colon expansion" 'unset x; : ${x:=default}; echo $x'

section "358. DOT COMMAND"

compare_posix_output "dot source" 'echo "x=sourced" > /tmp/ds$$; . /tmp/ds$$; echo $x; rm /tmp/ds$$'
compare_posix_output "dot with args" 'echo "echo \$1 \$2" > /tmp/ds$$; . /tmp/ds$$ arg1 arg2; rm /tmp/ds$$'
compare_posix_output "dot function" 'echo "f() { echo func; }" > /tmp/ds$$; . /tmp/ds$$; f; rm /tmp/ds$$'

section "359. EVAL COMMAND"

compare_posix_output "eval basic" 'eval echo hello'
compare_posix_output "eval var" 'x=echo; eval $x world'
compare_posix_output "eval multi" 'eval "echo one; echo two"'
compare_posix_output "eval indirect" 'x=y; y=value; eval echo \$$x'
compare_posix_output "eval quote" 'eval "echo \"quoted\""'

section "360. EXEC COMMAND"

compare_posix_output "exec redirect" 'exec 3>/tmp/ex$$; echo test >&3; exec 3>&-; cat /tmp/ex$$; rm /tmp/ex$$'
compare_posix_output "exec input" 'echo test > /tmp/ex$$; exec 4</tmp/ex$$; cat <&4; exec 4<&-; rm /tmp/ex$$'

section "361. EXIT COMMAND"

compare_posix_output "exit basic" '(exit); echo $?'
compare_posix_output "exit code" '(exit 5); echo $?'
compare_posix_output "exit 0" '(exit 0); echo $?'
compare_posix_output "exit 255" '(exit 255); echo $?'

section "362. EXPORT COMMAND"

compare_posix_output "export basic" 'export X=5; sh -c "echo \$X"'
compare_posix_output "export separate" 'Y=6; export Y; sh -c "echo \$Y"'
compare_posix_output "export list" 'export | grep -c ='
compare_posix_output "export unset" 'export Z=7; unset Z; sh -c "echo \${Z:-unset}"'

section "363. READONLY COMMAND"

compare_posix_output "readonly basic" 'readonly X=5; echo $X'
compare_posix_output "readonly list" 'readonly | grep -c .'
compare_posix_output "readonly modify" '(readonly Y=1; Y=2) 2>/dev/null; echo $?'

section "364. RETURN COMMAND"

compare_posix_output "return basic" 'f() { return; }; f; echo $?'
compare_posix_output "return code" 'f() { return 5; }; f; echo $?'
compare_posix_output "return from func" 'f() { echo before; return 3; echo after; }; f; echo $?'

section "365. SET COMMAND"

compare_posix_output "set args" 'set -- a b c; echo $1 $2 $3'
compare_posix_output "set count" 'set -- a b c d e; echo $#'
compare_posix_output "set clear" 'set -- a b; set --; echo $#'
compare_posix_output "set option f" 'set -f; echo $- | grep -c f; set +f'
compare_posix_output "set minus" 'set -x; set +x; echo ok'

# ============================================================================
# SECTION 366-375: MORE SPECIAL BUILTINS
# ============================================================================

section "366. SHIFT COMMAND"

compare_posix_output "shift basic" 'set -- a b c; shift; echo $1'
compare_posix_output "shift count" 'set -- a b c; shift; echo $#'
compare_posix_output "shift 2" 'set -- a b c d; shift 2; echo $1'
compare_posix_output "shift all" 'set -- a b; shift 2; echo $#'

section "367. TIMES COMMAND"

compare_posix_output "times output" 'times 2>/dev/null | wc -l | xargs test 0 -lt && echo ok || echo ok'

section "368. TRAP COMMAND"

compare_posix_output "trap list" 'trap 2>/dev/null; echo $?'
compare_posix_output "trap exit" 'trap "echo trapped" EXIT; exit 0'
compare_posix_output "trap reset" 'trap "" INT; trap - INT; echo ok'

section "369. UNSET COMMAND"

compare_posix_output "unset var" 'x=5; unset x; echo ${x:-unset}'
compare_posix_output "unset func" 'f() { echo func; }; unset -f f; f 2>/dev/null || echo unset'
compare_posix_output "unset v flag" 'x=5; unset -v x; echo ${x:-unset}'

section "370. ALIAS COMMAND"

compare_posix_output "alias set" 'alias ll="ls -l" 2>/dev/null; alias ll 2>/dev/null | grep -c ll || echo 0'
compare_posix_output "alias list" 'alias 2>/dev/null; echo $?'
compare_posix_output "unalias" 'alias xx="echo xx" 2>/dev/null; unalias xx 2>/dev/null; echo $?'

section "371. COMMAND BUILTIN"

compare_posix_output "command v" 'command -v echo | grep -c echo'
compare_posix_output "command V" 'command -V echo 2>/dev/null | grep -c echo'
compare_posix_output "command p" 'command -p echo test'
compare_posix_output "command bypass" 'echo() { printf "func\n"; }; command echo real; unset -f echo'

section "372. GETOPTS COMMAND"

compare_posix_output "getopts basic" 'set -- -a; getopts a opt; echo $opt'
compare_posix_output "getopts optarg" 'set -- -b val; getopts b: opt; echo $opt $OPTARG'
compare_posix_output "getopts optind" 'set -- -a arg; getopts a opt; echo $OPTIND'

section "373. READ COMMAND OPTIONS"

compare_posix_output "read r flag" 'echo "a\\b" > /tmp/rr$$; read -r x < /tmp/rr$$; echo $x; rm /tmp/rr$$'
compare_posix_output "read multiple" 'echo "a b c" > /tmp/rm$$; read x y z < /tmp/rm$$; echo "$x:$y:$z"; rm /tmp/rm$$'
compare_posix_output "read extra" 'echo "a b c d" > /tmp/re$$; read x y < /tmp/re$$; echo "$x:$y"; rm /tmp/re$$'

section "374. PRINTF COMMAND"

compare_posix_output "printf basic" 'printf "hello\n"'
compare_posix_output "printf format s" 'printf "%s\n" world'
compare_posix_output "printf format d" 'printf "%d\n" 42'
compare_posix_output "printf format x" 'printf "%x\n" 255'
compare_posix_output "printf format o" 'printf "%o\n" 8'
compare_posix_output "printf width" 'printf "%5d\n" 42'
compare_posix_output "printf left" 'printf "%-5d|\n" 42'
compare_posix_output "printf zero" 'printf "%05d\n" 42'
compare_posix_output "printf multi" 'printf "%s %s\n" hello world'

section "375. ECHO COMMAND"

compare_posix_output "echo basic" 'echo hello'
compare_posix_output "echo multi" 'echo hello world'
compare_posix_output "echo empty" 'echo ""'
compare_posix_output "echo n flag" 'echo -n hello; echo world'
compare_posix_output "echo escapes" 'echo "a\tb"'

# ============================================================================
# SECTION 376-385: WORD EXPANSION EDGE CASES
# ============================================================================

section "376. TILDE EXPANSION"

compare_posix_output "tilde home" 'echo ~ | grep -c /'
compare_posix_output "tilde slash" 'echo ~/ | grep -c /'
compare_posix_output "tilde plus" 'echo ~+ | grep -c /'
compare_posix_output "tilde minus" 'OLDPWD=/tmp; echo ~-'
compare_posix_output "tilde quoted" 'echo "~"'
compare_posix_output "tilde mid word" 'echo a~b'
compare_posix_output "tilde in assign" 'x=~/test; echo $x | grep -c /'

section "377. PATHNAME EXPANSION"

compare_posix_output "glob star" 'mkdir -p /tmp/pg$$; touch /tmp/pg$$/a /tmp/pg$$/b; echo /tmp/pg$$/* | grep -c pg; rm -rf /tmp/pg$$'
compare_posix_output "glob question" 'mkdir -p /tmp/pg$$; touch /tmp/pg$$/ab; echo /tmp/pg$$/a? | grep -c ab; rm -rf /tmp/pg$$'
compare_posix_output "glob bracket" 'mkdir -p /tmp/pg$$; touch /tmp/pg$$/a1 /tmp/pg$$/a2; ls /tmp/pg$$/a[12] | wc -l; rm -rf /tmp/pg$$'
compare_posix_output "glob negate" 'mkdir -p /tmp/pg$$; touch /tmp/pg$$/a1 /tmp/pg$$/b1; ls /tmp/pg$$/[!a]1 | wc -l; rm -rf /tmp/pg$$'
compare_posix_output "glob range" 'mkdir -p /tmp/pg$$; touch /tmp/pg$$/a1 /tmp/pg$$/b1 /tmp/pg$$/c1; ls /tmp/pg$$/[a-c]1 | wc -l; rm -rf /tmp/pg$$'
compare_posix_output "glob no match" 'echo /nonexistent$$/*'

section "378. FIELD SPLITTING"

compare_posix_output "split default" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "split tab" 'x="a	b	c"; set -- $x; echo $#'
compare_posix_output "split newline" 'x="a
b
c"; set -- $x; echo $#'
compare_posix_output "split ifs colon" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "split ifs multi" 'IFS=":;"; x="a:b;c"; set -- $x; echo $#'
compare_posix_output "split no split" 'x="a b c"; set -- "$x"; echo $#'

section "379. QUOTE REMOVAL"

compare_posix_output "quote remove single" "echo 'hello'"
compare_posix_output "quote remove double" 'echo "hello"'
compare_posix_output "quote remove escape" 'echo hello\ world'
compare_posix_output "quote remove mixed" "echo 'a'b'c'"
compare_posix_output "quote remove empty" "echo ''"
compare_posix_output "quote preserve space" 'echo "a   b"'

section "380. COMMAND SUBSTITUTION"

compare_posix_output "cmd sub basic" 'echo $(echo hello)'
compare_posix_output "cmd sub backtick" 'echo `echo hello`'
compare_posix_output "cmd sub nested" 'echo $(echo $(echo deep))'
compare_posix_output "cmd sub quote" 'echo "$(echo "hello world")"'
compare_posix_output "cmd sub multi" 'echo $(echo a; echo b)'
compare_posix_output "cmd sub exit" 'echo $(exit 5); echo $?'

section "381. ARITHMETIC EXPANSION"

compare_posix_output "arith basic" 'echo $((1+2))'
compare_posix_output "arith var" 'x=5; echo $((x*2))'
compare_posix_output "arith nested" 'echo $(( $((1+2)) + 3 ))'
compare_posix_output "arith in string" 'echo "result: $((3*4))"'
compare_posix_output "arith negative" 'echo $((-5))'

section "382. PARAMETER LENGTH"

compare_posix_output "length basic" 'x=hello; echo ${#x}'
compare_posix_output "length empty" 'x=""; echo ${#x}'
compare_posix_output "length special" 'set -- a b c; echo ${#@}'
compare_posix_output "length star" 'set -- a b c; echo ${#*}'

section "383. PATTERN SUFFIX REMOVAL"

compare_posix_output "suffix short" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "suffix long" 'x=file.tar.gz; echo ${x%%.*}'
compare_posix_output "suffix star" 'x=abcabc; echo ${x%abc}'
compare_posix_output "suffix star long" 'x=abcabc; echo ${x%%a*}'
compare_posix_output "suffix no match" 'x=hello; echo ${x%.xyz}'

section "384. PATTERN PREFIX REMOVAL"

compare_posix_output "prefix short" 'x=prefix_name; echo ${x#prefix_}'
compare_posix_output "prefix long" 'x=/usr/local/bin; echo ${x##*/}'
compare_posix_output "prefix star" 'x=abcabc; echo ${x#abc}'
compare_posix_output "prefix star long" 'x=abcabc; echo ${x##*a}'
compare_posix_output "prefix no match" 'x=hello; echo ${x#xyz}'

section "385. EXPANSION ORDER"

compare_posix_output "order brace tilde" 'echo ~/{a,b} | grep -c /'
compare_posix_output "order param cmd" 'x=$(echo val); echo $x'
compare_posix_output "order arith param" 'x=5; echo $((x+1))'
compare_posix_output "order split glob" 'mkdir -p /tmp/eo$$; touch /tmp/eo$$/f1; x="/tmp/eo$$/f*"; echo $x | grep -c f; rm -rf /tmp/eo$$'

# ============================================================================
# SECTION 386-400: POSIX CHARACTER CLASSES (basedefs/V1_chap09)
# ============================================================================

section "386. CHARACTER CLASS ALNUM"

compare_posix_output "alnum a" 'case a in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum Z" 'case Z in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum 5" 'case 5 in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum excl" 'case "!" in [[:alnum:]]) echo yes;; *) echo no;; esac'

section "387. CHARACTER CLASS ALPHA"

compare_posix_output "alpha a" 'case a in [[:alpha:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alpha Z" 'case Z in [[:alpha:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alpha 5" 'case 5 in [[:alpha:]]) echo yes;; *) echo no;; esac'

section "388. CHARACTER CLASS DIGIT"

compare_posix_output "digit 0" 'case 0 in [[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "digit 9" 'case 9 in [[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "digit a" 'case a in [[:digit:]]) echo yes;; *) echo no;; esac'

section "389. CHARACTER CLASS LOWER"

compare_posix_output "lower a" 'case a in [[:lower:]]) echo yes;; *) echo no;; esac'
compare_posix_output "lower z" 'case z in [[:lower:]]) echo yes;; *) echo no;; esac'
compare_posix_output "lower A" 'case A in [[:lower:]]) echo yes;; *) echo no;; esac'

section "390. CHARACTER CLASS UPPER"

compare_posix_output "upper A" 'case A in [[:upper:]]) echo yes;; *) echo no;; esac'
compare_posix_output "upper Z" 'case Z in [[:upper:]]) echo yes;; *) echo no;; esac'
compare_posix_output "upper a" 'case a in [[:upper:]]) echo yes;; *) echo no;; esac'

section "391. CHARACTER CLASS SPACE"

compare_posix_output "space sp" 'case " " in [[:space:]]) echo yes;; *) echo no;; esac'
compare_posix_output "space tab" 'case "	" in [[:space:]]) echo yes;; *) echo no;; esac'
compare_posix_output "space a" 'case a in [[:space:]]) echo yes;; *) echo no;; esac'

section "392. CHARACTER CLASS BLANK"

compare_posix_output "blank sp" 'case " " in [[:blank:]]) echo yes;; *) echo no;; esac'
compare_posix_output "blank tab" 'case "	" in [[:blank:]]) echo yes;; *) echo no;; esac'
compare_posix_output "blank a" 'case a in [[:blank:]]) echo yes;; *) echo no;; esac'

section "393. CHARACTER CLASS PUNCT"

compare_posix_output "punct dot" 'case "." in [[:punct:]]) echo yes;; *) echo no;; esac'
compare_posix_output "punct excl" 'case "!" in [[:punct:]]) echo yes;; *) echo no;; esac'
compare_posix_output "punct a" 'case a in [[:punct:]]) echo yes;; *) echo no;; esac'

section "394. CHARACTER CLASS XDIGIT"

compare_posix_output "xdigit 0" 'case 0 in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit a" 'case a in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit F" 'case F in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit g" 'case g in [[:xdigit:]]) echo yes;; *) echo no;; esac'

section "395. CHARACTER CLASS PRINT GRAPH"

compare_posix_output "print a" 'case a in [[:print:]]) echo yes;; *) echo no;; esac'
compare_posix_output "print sp" 'case " " in [[:print:]]) echo yes;; *) echo no;; esac'
compare_posix_output "graph a" 'case a in [[:graph:]]) echo yes;; *) echo no;; esac'
compare_posix_output "graph sp" 'case " " in [[:graph:]]) echo yes;; *) echo no;; esac'

section "396. CHARACTER CLASS CNTRL"

compare_posix_output "cntrl a" 'case a in [[:cntrl:]]) echo yes;; *) echo no;; esac'

section "397. COMBINED CHARACTER CLASSES"

compare_posix_output "combo alpha digit a" 'case a in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "combo alpha digit 5" 'case 5 in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "combo alpha digit excl" 'case "!" in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'

section "398. NEGATED CHARACTER CLASSES"

compare_posix_output "not digit a" 'case a in [^[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "not digit 5" 'case 5 in [^[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "not alpha bang" 'case a in [![:alpha:]]) echo yes;; *) echo no;; esac'

section "399. RANGE EXPRESSIONS"

compare_posix_output "range a-z m" 'case m in [a-z]) echo yes;; *) echo no;; esac'
compare_posix_output "range A-Z M" 'case M in [A-Z]) echo yes;; *) echo no;; esac'
compare_posix_output "range 0-9 5" 'case 5 in [0-9]) echo yes;; *) echo no;; esac'
compare_posix_output "range combo" 'case M in [a-zA-Z]) echo yes;; *) echo no;; esac'

section "400. BRACKET EDGE CASES"

compare_posix_output "literal hyphen start" 'case "-" in [-abc]) echo yes;; *) echo no;; esac'
compare_posix_output "literal hyphen end" 'case "-" in [abc-]) echo yes;; *) echo no;; esac'
compare_posix_output "literal caret" 'case "^" in [a^b]) echo yes;; *) echo no;; esac'
compare_posix_output "literal rbracket" 'case "]" in []abc]) echo yes;; *) echo no;; esac'

# ============================================================================
# SECTION 401-410: ADDITIONAL SPECIAL VARIABLE TESTS
# ============================================================================

section "401. IFS EDGE CASES"

compare_posix_output "ifs default split" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "ifs null no split" 'IFS=""; x="abc"; set -- $x; echo $#'
compare_posix_output "ifs custom colon" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "ifs whitespace" 'IFS=" "; x="a  b"; set -- $x; echo $#'

section "402. HOME VARIABLE"

compare_posix_output "home set" 'echo ${HOME:-unset} | grep -c /'
compare_posix_output "home in tilde" 'test ~ = "$HOME"; echo $?'

section "403. PATH VARIABLE"

compare_posix_output "path set" 'echo ${PATH:-unset} | grep -c :'
compare_posix_output "path search" 'PATH=/bin:/usr/bin; command -v ls | grep -c /'

section "404. SHELL OPTION FLAGS"

compare_posix_output "set f noglob" 'set -f; echo *; set +f'
compare_posix_output "set u nounset" '(set -u; echo ${x:-default})'
compare_posix_output "set e errexit" '(set -e; true; echo ok)'
compare_posix_output "set x xtrace" '(set -x; echo test) 2>&1 | grep -c test'

section "405. EXIT STATUS PROPAGATION"

compare_posix_output "exit from pipe" 'true | false; echo $?'
compare_posix_output "exit from and" 'true && true; echo $?'
compare_posix_output "exit from or" 'false || true; echo $?'
compare_posix_output "exit from not" '! false; echo $?'

section "406. SUBSHELL ISOLATION"

compare_posix_output "subshell var" 'x=1; (x=2); echo $x'
compare_posix_output "subshell cd" 'cd /tmp; (cd /); pwd | grep -c tmp'
compare_posix_output "subshell exit" '(exit 5); echo $?'

section "407. BRACE GROUP SEMANTICS"

compare_posix_output "brace var" 'x=1; { x=2; }; echo $x'
compare_posix_output "brace redir" '{ echo a; echo b; } > /tmp/bg$$; wc -l < /tmp/bg$$; rm /tmp/bg$$'

section "408. FUNCTION SEMANTICS"

compare_posix_output "func scope" 'x=1; f() { x=2; }; f; echo $x'
compare_posix_output "func params" 'f() { echo $1 $2 $#; }; f a b c'
compare_posix_output "func return" 'f() { return 42; }; f; echo $?'

section "409. ALIAS EXPANSION"

compare_posix_output "alias define" 'alias x="echo test" 2>/dev/null; echo $?'
compare_posix_output "unalias" 'alias x="echo test" 2>/dev/null; unalias x 2>/dev/null; echo $?'

section "410. COMPOUND ASSIGNMENT"

compare_posix_output "assign simple" 'x=5; echo $x'
compare_posix_output "assign expand" 'x=$(echo val); echo $x'
compare_posix_output "assign arith" 'x=$((2+3)); echo $x'
compare_posix_output "assign concat" 'x=hel; x=${x}lo; echo $x'

# ============================================================================
# SECTION 411-420: COMPLEX PATTERNS
# ============================================================================

section "411. CASE PATTERN MATCHING"

compare_posix_output "case star" 'case abc in a*) echo yes;; esac'
compare_posix_output "case question" 'case ab in a?) echo yes;; esac'
compare_posix_output "case bracket" 'case a in [abc]) echo yes;; esac'
compare_posix_output "case or" 'case b in a|b|c) echo yes;; esac'
compare_posix_output "case default" 'case x in a) echo a;; *) echo default;; esac'

section "412. GLOB PATTERNS IN EXPANSION"

compare_posix_output "glob files" 'mkdir -p /tmp/gt$$; touch /tmp/gt$$/a /tmp/gt$$/b; ls /tmp/gt$$/* | wc -l; rm -rf /tmp/gt$$'
compare_posix_output "glob question" 'mkdir -p /tmp/gt$$; touch /tmp/gt$$/ab; echo /tmp/gt$$/a? | grep -c ab; rm -rf /tmp/gt$$'
compare_posix_output "glob no match" 'echo /nonexistent_$$/*'

section "413. SUFFIX REMOVAL PATTERNS"

compare_posix_output "suffix short" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "suffix long" 'x=file.tar.gz; echo ${x%%.*}'
compare_posix_output "suffix star" 'x=path/to/file; echo ${x%/*}'

section "414. PREFIX REMOVAL PATTERNS"

compare_posix_output "prefix short" 'x=file.txt; echo ${x#*.}'
compare_posix_output "prefix long" 'x=file.tar.gz; echo ${x##*.}'
compare_posix_output "prefix path" 'x=/path/to/file; echo ${x##*/}'

section "415. LENGTH OPERATOR"

compare_posix_output "length string" 'x=hello; echo ${#x}'
compare_posix_output "length empty" 'x=""; echo ${#x}'
compare_posix_output "length positional" 'set -- a b c; echo $#'

section "416. CONDITIONAL DEFAULTS"

compare_posix_output "default unset" 'unset x; echo ${x:-default}'
compare_posix_output "default empty" 'x=""; echo ${x:-default}'
compare_posix_output "default set" 'x=val; echo ${x:-default}'

section "417. CONDITIONAL ASSIGN"

compare_posix_output "assign unset" 'unset x; echo ${x:=assigned}; echo $x'
compare_posix_output "assign empty" 'x=""; echo ${x:=assigned}; echo $x'

section "418. CONDITIONAL ERROR"

compare_posix_output "error unset" '(unset x; echo ${x:?msg}) 2>/dev/null; echo $?'
compare_posix_output "error set" 'x=val; echo ${x:?msg}'

section "419. CONDITIONAL ALT"

compare_posix_output "alt unset" 'unset x; echo "[${x:+alt}]"'
compare_posix_output "alt set" 'x=val; echo "[${x:+alt}]"'

section "420. NESTED PARAMETER"

compare_posix_output "nested default" 'y=inner; echo ${x:-${y:-outer}}'
compare_posix_output "nested length" 'x=hello; echo $((${#x} + 1))'

# ============================================================================
# SECTION 421-430: HEREDOC VARIATIONS
# ============================================================================

section "421. HEREDOC BASIC"

compare_posix_output "heredoc simple" 'cat <<EOF
hello
EOF'
compare_posix_output "heredoc multi" 'cat <<EOF
line1
line2
EOF'
compare_posix_output "heredoc empty" 'cat <<EOF
EOF'

section "422. HEREDOC EXPANSION"

compare_posix_output "heredoc var" 'x=value; cat <<EOF
$x
EOF'
compare_posix_output "heredoc cmd" 'cat <<EOF
$(echo hello)
EOF'
compare_posix_output "heredoc arith" 'cat <<EOF
$((1+2))
EOF'

section "423. HEREDOC QUOTED DELIMITER"

compare_posix_output "heredoc single quote" "cat <<'EOF'
\$x \$(cmd)
EOF"
compare_posix_output "heredoc double quote" 'cat <<"EOF"
$x $(cmd)
EOF'

section "424. HEREDOC TAB STRIP"

compare_posix_output "heredoc dash" 'cat <<-EOF
	tabbed
	EOF'

section "425. MULTIPLE HEREDOCS"

compare_posix_output "double heredoc" 'cat <<EOF1; cat <<EOF2
first
EOF1
second
EOF2'

# ============================================================================
# SECTION 426-435: ADDITIONAL ARITHMETIC
# ============================================================================

section "426. ARITHMETIC OPERATORS"

compare_posix_output "arith add" 'echo $((5+3))'
compare_posix_output "arith sub" 'echo $((5-3))'
compare_posix_output "arith mul" 'echo $((5*3))'
compare_posix_output "arith div" 'echo $((15/3))'
compare_posix_output "arith mod" 'echo $((17%5))'
compare_posix_output "arith neg" 'echo $((-5))'

section "427. ARITHMETIC COMPARISONS"

compare_posix_output "arith lt" 'echo $((3<5))'
compare_posix_output "arith gt" 'echo $((5>3))'
compare_posix_output "arith le" 'echo $((5<=5))'
compare_posix_output "arith ge" 'echo $((5>=5))'
compare_posix_output "arith eq" 'echo $((5==5))'
compare_posix_output "arith ne" 'echo $((5!=3))'

section "428. ARITHMETIC LOGICAL"

compare_posix_output "arith and" 'echo $((1&&1))'
compare_posix_output "arith or" 'echo $((0||1))'
compare_posix_output "arith not" 'echo $((!0))'

section "429. ARITHMETIC BITWISE"

compare_posix_output "arith band" 'echo $((12&10))'
compare_posix_output "arith bor" 'echo $((12|10))'
compare_posix_output "arith bxor" 'echo $((12^10))'
compare_posix_output "arith lshift" 'echo $((1<<4))'
compare_posix_output "arith rshift" 'echo $((16>>2))'

section "430. ARITHMETIC TERNARY"

compare_posix_output "arith ternary t" 'echo $((1?10:20))'
compare_posix_output "arith ternary f" 'echo $((0?10:20))'
compare_posix_output "arith ternary expr" 'echo $((5>3?1:0))'

section "431. ARITHMETIC ASSIGNMENT"

compare_posix_output "arith pluseq" 'x=5; echo $((x+=3))'
compare_posix_output "arith minuseq" 'x=5; echo $((x-=3))'
compare_posix_output "arith muleq" 'x=5; echo $((x*=3))'
compare_posix_output "arith diveq" 'x=15; echo $((x/=3))'

section "432. ARITHMETIC PRECEDENCE"

compare_posix_output "arith prec 1" 'echo $((2+3*4))'
compare_posix_output "arith prec 2" 'echo $(((2+3)*4))'
compare_posix_output "arith prec 3" 'echo $((10/2+3))'

section "433. ARITHMETIC WITH VARS"

compare_posix_output "arith var simple" 'x=5; echo $((x))'
compare_posix_output "arith var expr" 'a=3; b=4; echo $((a*a+b*b))'
compare_posix_output "arith var unset" 'unset z; echo $((z))'

section "434. ARITHMETIC BASE"

compare_posix_output "arith octal" 'echo $((010))'
compare_posix_output "arith hex" 'echo $((0x10))'
compare_posix_output "arith hex lc" 'echo $((0xa))'

section "435. ARITHMETIC INCREMENT"

compare_posix_output "arith preinc" 'x=5; echo $((++x))'
compare_posix_output "arith predec" 'x=5; echo $((--x))'
compare_posix_output "arith postinc" 'x=5; echo $((x++))'
compare_posix_output "arith postdec" 'x=5; echo $((x--))'

# ============================================================================
# SECTION 436-445: QUOTING EDGE CASES
# ============================================================================

section "436. SINGLE QUOTING"

compare_posix_output "squote simple" "echo 'hello'"
compare_posix_output "squote space" "echo 'hello world'"
compare_posix_output "squote dollar" "echo '\$x'"
compare_posix_output "squote backtick" "echo '\`cmd\`'"
compare_posix_output "squote backslash" "echo '\\'"

section "437. DOUBLE QUOTING"

compare_posix_output "dquote simple" 'echo "hello"'
compare_posix_output "dquote space" 'echo "hello world"'
compare_posix_output "dquote expand" 'x=val; echo "$x"'
compare_posix_output "dquote escaped dollar" 'echo "\$x"'
compare_posix_output "dquote escaped quote" 'echo "hello\"world"'

section "438. BACKSLASH ESCAPING"

compare_posix_output "escape space" 'echo hello\ world'
compare_posix_output "escape dollar" 'echo \$x'
compare_posix_output "escape newline" 'echo hello\
world'
compare_posix_output "escape backslash" 'echo \\\\'

section "439. MIXED QUOTING"

compare_posix_output "mixed sd" 'echo "'"'"'"'
compare_posix_output "mixed ds" "echo '\"'"
compare_posix_output "mixed concat" "echo 'a'b'c'"
compare_posix_output "mixed dquote" 'echo "a'"'"'b"'

section "440. EMPTY QUOTES"

compare_posix_output "empty single" "echo ''"
compare_posix_output "empty double" 'echo ""'
compare_posix_output "empty in string" 'echo a""b'
compare_posix_output "empty as arg" 'set -- ""; echo $#'

# ============================================================================
# SECTION 441-450: COMMAND LINE SYNTAX
# ============================================================================

section "441. SIMPLE COMMANDS"

compare_posix_output "simple echo" 'echo hello'
compare_posix_output "simple true" 'true; echo $?'
compare_posix_output "simple false" 'false; echo $?'
compare_posix_output "simple colon" ': ; echo $?'

section "442. PIPELINES"

compare_posix_output "pipe simple" 'echo hello | cat'
compare_posix_output "pipe multi" 'echo hello | cat | cat'
compare_posix_output "pipe exit" 'true | false; echo $?'
compare_posix_output "pipe negation" '! echo x | grep y 2>/dev/null; echo $?'

section "443. LISTS"

compare_posix_output "list semi" 'echo a; echo b'
compare_posix_output "list newline" 'echo a
echo b'
compare_posix_output "list and" 'true && echo yes'
compare_posix_output "list or" 'false || echo yes'

section "444. COMPOUND COMMANDS"

compare_posix_output "subshell" '(echo hello)'
compare_posix_output "brace" '{ echo hello; }'
compare_posix_output "if" 'if true; then echo yes; fi'
compare_posix_output "for" 'for i in a b; do echo $i; done'
compare_posix_output "case" 'case x in x) echo yes;; esac'

section "445. REDIRECTIONS"

compare_posix_output "redir out" 'echo test > /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir in" 'echo test > /tmp/r$$; cat < /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir append" 'echo a > /tmp/r$$; echo b >> /tmp/r$$; cat /tmp/r$$; rm /tmp/r$$'
compare_posix_output "redir stderr" 'ls /nonexistent$$ 2>/dev/null; echo done'

section "446. COMMENTS"

compare_posix_output "comment inline" 'echo yes # comment'
compare_posix_output "comment in dquote" 'echo "not # comment"'
compare_posix_output "comment in squote" "echo 'not # comment'"

section "447. RESERVED WORDS"

compare_posix_output "reserved if" 'if true; then echo 1; fi'
compare_posix_output "reserved for" 'for x in a; do echo $x; done'
compare_posix_output "reserved case" 'case a in a) echo yes;; esac'

section "448. WORD SPLITTING"

compare_posix_output "split default" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "split quoted" 'x="a b c"; set -- "$x"; echo $#'
compare_posix_output "split ifs" 'IFS=:; x="a:b:c"; set -- $x; echo $#'

section "449. GLOB EXPANSION"

compare_posix_output "glob star" 'mkdir -p /tmp/g$$; touch /tmp/g$$/a; echo /tmp/g$$/* | grep -c g; rm -rf /tmp/g$$'
compare_posix_output "glob question" 'mkdir -p /tmp/g$$; touch /tmp/g$$/ab; echo /tmp/g$$/a? | grep -c ab; rm -rf /tmp/g$$'
compare_posix_output "glob bracket" 'mkdir -p /tmp/g$$; touch /tmp/g$$/a1; echo /tmp/g$$/a[12] | grep -c a1; rm -rf /tmp/g$$'
compare_posix_output "glob nomatch" 'echo /nonexistent$$/*'

section "450. TILDE EXPANSION"

compare_posix_output "tilde home" 'echo ~ | grep -c /'
compare_posix_output "tilde plus" 'echo ~+ | grep -c /'
compare_posix_output "tilde in assign" 'x=~/test; echo $x | grep -c /'
compare_posix_output "tilde quoted" 'echo "~"'

# ============================================================================
# SECTION 451-460: BUILTINS EDGE CASES
# ============================================================================

section "451. CD BUILTIN"

compare_posix_output "cd tmp" 'cd /tmp; pwd'
compare_posix_output "cd home" 'cd ~; pwd | grep -c /'
compare_posix_output "cd dash" 'cd /tmp; cd /; cd -'
compare_posix_output "cd dotdot" 'cd /tmp; cd ..; pwd'

section "452. PWD BUILTIN"

compare_posix_output "pwd basic" 'pwd | grep -c /'
compare_posix_output "pwd P" 'pwd -P | grep -c /'
compare_posix_output "pwd L" 'pwd -L | grep -c /'

section "453. ECHO BUILTIN"

compare_posix_output "echo basic" 'echo hello'
compare_posix_output "echo multi" 'echo hello world'
compare_posix_output "echo empty" 'echo ""'
compare_posix_output "echo n" 'echo -n hello; echo world'
compare_posix_output "echo special" 'echo "a\tb"'

section "454. PRINTF BUILTIN"

compare_posix_output "printf s" 'printf "%s\n" hello'
compare_posix_output "printf d" 'printf "%d\n" 42'
compare_posix_output "printf x" 'printf "%x\n" 255'
compare_posix_output "printf o" 'printf "%o\n" 8'
compare_posix_output "printf width" 'printf "%5d\n" 42'
compare_posix_output "printf left" 'printf "%-5d|\n" 42'
compare_posix_output "printf zero" 'printf "%05d\n" 42'

section "455. TEST BUILTIN OPERATORS"

compare_posix_output "test eq" '[ 5 -eq 5 ]; echo $?'
compare_posix_output "test ne" '[ 5 -ne 3 ]; echo $?'
compare_posix_output "test lt" '[ 3 -lt 5 ]; echo $?'
compare_posix_output "test gt" '[ 5 -gt 3 ]; echo $?'
compare_posix_output "test le" '[ 5 -le 5 ]; echo $?'
compare_posix_output "test ge" '[ 5 -ge 5 ]; echo $?'

section "456. TEST BUILTIN STRINGS"

compare_posix_output "test z empty" '[ -z "" ]; echo $?'
compare_posix_output "test z nonempty" '[ -z "x" ]; echo $?'
compare_posix_output "test n empty" '[ -n "" ]; echo $?'
compare_posix_output "test n nonempty" '[ -n "x" ]; echo $?'
compare_posix_output "test str eq" '[ "a" = "a" ]; echo $?'
compare_posix_output "test str ne" '[ "a" != "b" ]; echo $?'

section "457. TEST BUILTIN FILES"

compare_posix_output "test f" '[ -f /etc/passwd ]; echo $?'
compare_posix_output "test d" '[ -d /tmp ]; echo $?'
compare_posix_output "test e" '[ -e /tmp ]; echo $?'
compare_posix_output "test r" '[ -r /etc/passwd ]; echo $?'
compare_posix_output "test x" '[ -x /bin/sh ]; echo $?'
compare_posix_output "test s" 'echo x > /tmp/ts$$; [ -s /tmp/ts$$ ]; echo $?; rm /tmp/ts$$'

section "458. TEST BUILTIN COMPOUND"

compare_posix_output "test and" '[ -d /tmp -a -f /etc/passwd ]; echo $?'
compare_posix_output "test or" '[ -d /nonexistent -o -f /etc/passwd ]; echo $?'
compare_posix_output "test not" '[ ! -d /nonexistent ]; echo $?'
compare_posix_output "test paren" '[ \( -d /tmp \) ]; echo $?'

section "459. TYPE BUILTIN"

compare_posix_output "type echo" 'type echo 2>/dev/null | grep -c echo'
compare_posix_output "type cd" 'type cd 2>/dev/null | grep -c cd'

section "460. COMMAND BUILTIN"

compare_posix_output "command v" 'command -v echo | grep -c echo'
compare_posix_output "command V" 'command -V echo 2>/dev/null | grep -c echo'
compare_posix_output "command p" 'command -p echo test'

# ============================================================================
# SECTION 461-470: CONTROL FLOW COMPREHENSIVE
# ============================================================================

section "461. IF STATEMENT"

compare_posix_output "if basic" 'if true; then echo yes; fi'
compare_posix_output "if else" 'if false; then echo no; else echo yes; fi'
compare_posix_output "if elif" 'if false; then echo 1; elif true; then echo 2; fi'
compare_posix_output "if elif else" 'if false; then echo 1; elif false; then echo 2; else echo 3; fi'
compare_posix_output "if nested" 'if true; then if true; then echo deep; fi; fi'

section "462. FOR LOOP"

compare_posix_output "for basic" 'for i in 1 2 3; do echo $i; done'
compare_posix_output "for words" 'for w in a b c; do echo $w; done'
compare_posix_output "for empty" 'for i in; do echo $i; done; echo done'
compare_posix_output "for break" 'for i in 1 2 3; do echo $i; break; done'
compare_posix_output "for continue" 'for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; echo $i; done'

section "463. WHILE LOOP"

compare_posix_output "while basic" 'i=0; while [ $i -lt 3 ]; do echo $i; i=$((i+1)); done'
compare_posix_output "while false" 'while false; do echo no; done; echo done'
compare_posix_output "while break" 'while true; do echo once; break; done'

section "464. UNTIL LOOP"

compare_posix_output "until basic" 'i=0; until [ $i -ge 3 ]; do echo $i; i=$((i+1)); done'
compare_posix_output "until true" 'until true; do echo no; done; echo done'

section "465. CASE STATEMENT"

compare_posix_output "case basic" 'case x in x) echo yes;; esac'
compare_posix_output "case default" 'case y in x) echo no;; *) echo yes;; esac'
compare_posix_output "case multi" 'case b in a|b|c) echo abc;; esac'
compare_posix_output "case glob" 'case abc in a*) echo yes;; esac'
compare_posix_output "case nested" 'case x in x) case y in y) echo deep;; esac;; esac'

section "466. FUNCTION DEFINITION"

compare_posix_output "func basic" 'f() { echo hello; }; f'
compare_posix_output "func args" 'f() { echo $1 $2; }; f a b'
compare_posix_output "func return" 'f() { return 5; }; f; echo $?'
compare_posix_output "func positional" 'f() { echo $# $@; }; f a b c'

section "467. SUBSHELL AND BRACE"

compare_posix_output "subshell basic" '(echo hello)'
compare_posix_output "subshell var" 'x=1; (x=2); echo $x'
compare_posix_output "subshell exit" '(exit 5); echo $?'
compare_posix_output "brace basic" '{ echo hello; }'
compare_posix_output "brace var" 'x=1; { x=2; }; echo $x'
compare_posix_output "brace redir" '{ echo a; echo b; } > /tmp/b$$; wc -l < /tmp/b$$; rm /tmp/b$$'

section "468. BREAK AND CONTINUE"

compare_posix_output "break simple" 'for i in 1 2 3; do echo $i; break; done'
compare_posix_output "break nested" 'for i in 1 2; do for j in a b; do echo $i$j; break; done; done'
compare_posix_output "break 2" 'for i in 1 2; do for j in a b; do echo $i$j; break 2; done; done'
compare_posix_output "continue simple" 'for i in 1 2 3; do if [ $i = 2 ]; then continue; fi; echo $i; done'
compare_posix_output "continue 2" 'for i in 1 2; do for j in a b; do if [ $j = a ]; then continue 2; fi; echo $i$j; done; done'

section "469. RETURN AND EXIT"

compare_posix_output "return basic" 'f() { return; }; f; echo $?'
compare_posix_output "return code" 'f() { return 5; }; f; echo $?'
compare_posix_output "exit subshell" '(exit 5); echo $?'
compare_posix_output "exit code" '(exit 42); echo $?'

section "470. LOGICAL OPERATORS"

compare_posix_output "and both true" 'true && echo yes'
compare_posix_output "and first false" 'false && echo no; echo done'
compare_posix_output "or first true" 'true || echo no; echo done'
compare_posix_output "or first false" 'false || echo yes'
compare_posix_output "not true" '! true; echo $?'
compare_posix_output "not false" '! false; echo $?'

# ============================================================================
# SECTION 471-480: VARIABLE OPERATIONS
# ============================================================================

section "471. VARIABLE ASSIGNMENT"

compare_posix_output "var simple" 'x=5; echo $x'
compare_posix_output "var empty" 'x=; echo "[$x]"'
compare_posix_output "var quoted" 'x="a b"; echo "$x"'
compare_posix_output "var concat" 'x=hel; y=lo; echo $x$y'
compare_posix_output "var braces" 'x=val; echo ${x}'

section "472. EXPORT AND READONLY"

compare_posix_output "export basic" 'export X=5; sh -c "echo \$X"'
compare_posix_output "export list" 'export | grep -c ='
compare_posix_output "readonly basic" 'readonly Y=5; echo $Y'
compare_posix_output "readonly list" 'readonly | grep -c .'

section "473. UNSET"

compare_posix_output "unset var" 'x=5; unset x; echo ${x:-unset}'
compare_posix_output "unset func" 'f() { echo f; }; unset -f f; f 2>/dev/null || echo unset'
compare_posix_output "unset v flag" 'x=5; unset -v x; echo ${x:-unset}'

section "474. SHIFT"

compare_posix_output "shift basic" 'set -- a b c; shift; echo $1'
compare_posix_output "shift count" 'set -- a b c; shift; echo $#'
compare_posix_output "shift 2" 'set -- a b c d; shift 2; echo $1'

section "475. SET POSITIONAL"

compare_posix_output "set args" 'set -- a b c; echo $1 $2 $3'
compare_posix_output "set count" 'set -- a b c d e; echo $#'
compare_posix_output "set all" 'set -- x y z; echo "$@"'
compare_posix_output "set star" 'set -- x y z; echo "$*"'

section "476. LOCAL SCOPE IN FUNCTIONS"

compare_posix_output "func global" 'x=global; f() { x=func; }; f; echo $x'
compare_posix_output "func params" 'f() { echo $# $1 $2; }; f a b c'
compare_posix_output "func shift" 'f() { shift; echo $1; }; f a b c'

section "477. SPECIAL PARAMETERS"

compare_posix_output "dollar at" 'set -- a b c; echo "$@"'
compare_posix_output "dollar star" 'set -- a b c; echo "$*"'
compare_posix_output "dollar hash" 'set -- a b c; echo $#'
compare_posix_output "dollar question" 'true; echo $?'
compare_posix_output "dollar pid" 'echo $$ | grep -cE "^[0-9]+$"'
compare_posix_output "dollar zero" 'echo $0 | grep -c .'

section "478. PARAMETER EXPANSION"

compare_posix_output "pe default" 'unset x; echo ${x:-default}'
compare_posix_output "pe assign" 'unset x; echo ${x:=assigned}; echo $x'
compare_posix_output "pe error" '(unset x; echo ${x:?msg}) 2>/dev/null; echo $?'
compare_posix_output "pe alt" 'x=val; echo ${x:+alt}'
compare_posix_output "pe length" 'x=hello; echo ${#x}'
compare_posix_output "pe suffix" 'x=file.txt; echo ${x%.txt}'
compare_posix_output "pe prefix" 'x=/path/file; echo ${x##*/}'

section "479. IFS SPLITTING"

compare_posix_output "ifs default" 'x="a b c"; set -- $x; echo $#'
compare_posix_output "ifs colon" 'IFS=:; x="a:b:c"; set -- $x; echo $#'
compare_posix_output "ifs empty" 'IFS=""; x="abc"; set -- $x; echo $#'
compare_posix_output "ifs star" 'IFS=:; set -- a b c; echo "$*"'

section "480. COMMAND SUBSTITUTION"

compare_posix_output "cmdsub basic" 'echo $(echo hello)'
compare_posix_output "cmdsub backtick" 'echo `echo hello`'
compare_posix_output "cmdsub nested" 'echo $(echo $(echo deep))'
compare_posix_output "cmdsub quoted" 'echo "$(echo hello world)"'
compare_posix_output "cmdsub multi" 'echo $(echo a; echo b)'

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
