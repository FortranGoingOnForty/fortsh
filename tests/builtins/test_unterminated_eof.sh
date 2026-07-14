#!/bin/sh
# Unterminated quote / $( / ${ / $'...' at end of input must be a syntax
# error (exit 2) in non-interactive mode. Before PARSE-3 the lexer flushed
# the open construct as a completed word with no error flag, so fortsh ran
# the mangled command and exited 0 (bash exits 2 with "unexpected EOF").
TEST_PREFIX="[unterminated-eof]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

# The diagnostic prefix differs by design (fortsh: "sh: -c: line 1:", see
# grammar_parser.f90 prefix policy / PARSE-7), so cases assert the exit
# code plus the message body rather than diffing bash's full line.
expect_eof_error() {
    _name=$1; _cmd=$2; _closer=$3
    _out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" -c "$_cmd" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 2 ] && printf '%s' "$_out" | \
         grep -q "unexpected EOF while looking for matching \`$_closer'"; then
        pass "$_name"
    else
        fail "$_name" "rc=2 + EOF diagnostic naming $_closer" "rc=$_rc out=$_out"
    fi
}

section "1. -c mode: exit 2 with the matching-closer diagnostic"

expect_eof_error "unterminated double quote"  'echo "unterminated'   '"'
expect_eof_error "unterminated single quote"  "echo 'unterminated"   "'"
expect_eof_error "unterminated \$("           'echo $(echo hi'       ')'
expect_eof_error "unterminated \${"           'echo ${unclosed'      '}'
expect_eof_error "unterminated \$'...'"       "echo \$'abc"          "'"
expect_eof_error "unterminated <("            'cat <(echo hi'        ')'
expect_eof_error "mid-word \$'... "           "echo pre\$'abc"       "'"

section "2. Exit code matches bash across the repros"

compare_exit "double quote rc" 'echo "unterminated'
compare_exit "single quote rc" "echo 'unterminated"
compare_exit "\$( rc"          'echo $(echo hi'
compare_exit "\${ rc"          'echo ${unclosed'

section "3. Piped-stdin and script-file modes reject too"

_out=$(printf 'echo "unterminated\n' | run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" 2>&1)
_rc=$?
if [ "$_rc" -eq 2 ] && printf '%s' "$_out" | grep -q 'unexpected EOF'; then
    pass "stdin pipe exits 2 with diagnostic"
else
    fail "stdin pipe exits 2 with diagnostic" "rc=2 + EOF diagnostic" "rc=$_rc out=$_out"
fi

scr="$TEST_TMPDIR/unterm.sh"
printf 'echo before\necho "unterminated\n' > "$scr"
_out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr" 2>&1)
_rc=$?
if [ "$_rc" -eq 2 ] && printf '%s' "$_out" | grep -q '^before$' && \
   printf '%s' "$_out" | grep -q 'unexpected EOF'; then
    pass "script file runs prior lines then exits 2"
else
    fail "script file runs prior lines then exits 2" \
         "before + diagnostic + rc=2" "rc=$_rc out=$_out"
fi

section "4. Terminated constructs and lookalikes still parse"

compare_both "closed double quote"        'echo "ok"'
compare_both "closed substitution"        'echo $(echo ok)'
compare_both "closed parameter expansion" 'echo ${HOME:+ok}'
compare_both "closed \$'...'"             "echo \$'ok'"
compare_both "quote inside comment"       'echo ok # don"t care'
compare_both "multiline quote in -c"      'echo "line one
line two"'
compare_both "heredoc body with quote"    'cat <<EOF
it"s fine
EOF'

scr2="$TEST_TMPDIR/cont.sh"
printf 'echo "line one\nline two"\necho done\n' > "$scr2"
_out=$(run_with_timeout "$TEST_TIMEOUT" "$FORTSH_BIN" "$scr2" 2>&1)
_rc=$?
_exp=$(run_with_timeout "$TEST_TIMEOUT" "$BASH_REF" "$scr2" 2>&1)
if [ "$_rc" -eq 0 ] && [ "$_out" = "$_exp" ]; then
    pass "script-file quote continuation still joins lines"
else
    fail "script-file quote continuation still joins lines" "$_exp (rc 0)" "rc=$_rc out=$_out"
fi

print_summary
