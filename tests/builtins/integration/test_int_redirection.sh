#!/bin/sh
TEST_PREFIX="[int-redirection]"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FORTSH_BIN="${FORTSH_BIN:-$SCRIPT_DIR/../../../bin/fortsh}"
export FORTSH_BIN
. "$SCRIPT_DIR/../test_harness.sh"

# Integration tests: builtins with I/O redirections

section "1. output redirections"
compare_output "echo to file" "echo hello > $TEST_TMPDIR/out1; cat $TEST_TMPDIR/out1"
compare_output "echo append" "echo first > $TEST_TMPDIR/out2; echo second >> $TEST_TMPDIR/out2; cat $TEST_TMPDIR/out2"
compare_output "printf to file" "printf '%s\n' a b > $TEST_TMPDIR/out3; cat $TEST_TMPDIR/out3"
compare_output "echo to stderr" 'echo err >&2 2>/dev/null; echo $?'
compare_output "echo to dev null" 'echo test > /dev/null; echo $?'
compare_output "multiple echo to same file" "echo a > $TEST_TMPDIR/out4; echo b >> $TEST_TMPDIR/out4; echo c >> $TEST_TMPDIR/out4; cat $TEST_TMPDIR/out4"
compare_output "overwrite existing file" "echo first > $TEST_TMPDIR/out5; echo second > $TEST_TMPDIR/out5; cat $TEST_TMPDIR/out5"

section "2. input redirections"
compare_output "read from file" "echo data > $TEST_TMPDIR/in1; read VAR < $TEST_TMPDIR/in1; echo \$VAR"
compare_output "cat from redirect" "echo hello > $TEST_TMPDIR/in2; cat < $TEST_TMPDIR/in2"
compare_output "sort from redirect" "printf 'c\na\nb\n' > $TEST_TMPDIR/in3; sort < $TEST_TMPDIR/in3"
compare_output "while read from redirect" "printf 'a\nb\nc\n' > $TEST_TMPDIR/in4; while read line; do echo \"got:\$line\"; done < $TEST_TMPDIR/in4"
compare_output "read multiple vars from file" "echo 'one two three' > $TEST_TMPDIR/in5; read A B C < $TEST_TMPDIR/in5; echo \$A \$B \$C"

section "3. file descriptor manipulation"
compare_output "exec open write close" "exec 3>$TEST_TMPDIR/fd1; echo hello >&3; exec 3>&-; cat $TEST_TMPDIR/fd1"
compare_output "exec open read close" "echo data > $TEST_TMPDIR/fd2; exec 3<$TEST_TMPDIR/fd2; read VAR <&3; exec 3<&-; echo \$VAR"
compare_output "multiple fd open" "exec 4>$TEST_TMPDIR/fd3; exec 5>$TEST_TMPDIR/fd4; echo a >&4; echo b >&5; exec 4>&- 5>&-; cat $TEST_TMPDIR/fd3 $TEST_TMPDIR/fd4"
compare_output "dup stdout to fd" "exec 3>&1; echo hello >&3; exec 3>&-"
compare_output "stderr to file" "echo err >&2 2>$TEST_TMPDIR/fd5; cat $TEST_TMPDIR/fd5"
compare_output "stderr and stdout to same file" "echo out; echo err >&2 > $TEST_TMPDIR/fd6 2>&1; cat $TEST_TMPDIR/fd6"

section "4. here-documents"
compare_output "read from heredoc" 'read VAR <<EOF
hello
EOF
echo $VAR'
compare_output "cat with heredoc" 'cat <<EOF
line1
line2
EOF'
compare_output "while read from heredoc" 'while read line; do echo "got:$line"; done <<EOF
alpha
beta
gamma
EOF'
compare_output "heredoc with variable expansion" 'X=world; cat <<EOF
hello $X
EOF'
compare_output "quoted heredoc no expansion" 'X=world; cat <<'"'"'EOF'"'"'
hello $X
EOF'
compare_output "heredoc with command sub" 'cat <<EOF
today is $(echo wednesday)
EOF'
compare_output "heredoc with arithmetic" 'cat <<EOF
result is $((3 + 4))
EOF'
compare_output "empty heredoc" 'cat <<EOF
EOF'

section "5. here-strings"
compare_output "read from here-string" 'read VAR <<< "hello"; echo $VAR'
compare_output "read multiple from here-string" 'read A B <<< "one two"; echo $A $B'
compare_output "cat from here-string" 'cat <<< "hello world"'
compare_output "here-string with expansion" 'X=world; cat <<< "hello $X"'
compare_output "here-string with cmd sub" 'cat <<< "$(echo computed)"'
compare_output "here-string whitespace" 'read VAR <<< "  spaces  "; echo "[$VAR]"'

section "6. redirections with builtin output"
compare_output "type to file" "type echo > $TEST_TMPDIR/rtype 2>&1; head -1 $TEST_TMPDIR/rtype"
compare_output "set to dev null" 'X=test; set > /dev/null; echo $?'
compare_output "alias to file" "alias myalias='echo hi' 2>/dev/null; alias > $TEST_TMPDIR/ralias 2>/dev/null; echo done"
compare_output "redirect error messages" 'cd /nonexistent_xyz 2>/dev/null; echo $?'
compare_output "test with file redirect" "echo content > $TEST_TMPDIR/rtst; test -s $TEST_TMPDIR/rtst && echo nonempty"
compare_output "declare -p redirect" "X=42; declare -p X > $TEST_TMPDIR/rdecl 2>/dev/null; cat $TEST_TMPDIR/rdecl 2>/dev/null"

section "7. noclobber"
compare_output "noclobber prevents overwrite" "echo first > $TEST_TMPDIR/noclob; set -C; echo second > $TEST_TMPDIR/noclob 2>/dev/null; echo \$?; set +C; cat $TEST_TMPDIR/noclob"
compare_output "noclobber allows append" "echo first > $TEST_TMPDIR/noclob2; set -C; echo second >> $TEST_TMPDIR/noclob2; set +C; cat $TEST_TMPDIR/noclob2"
compare_output "noclobber force override" "echo first > $TEST_TMPDIR/noclob3; set -C; echo second >| $TEST_TMPDIR/noclob3; set +C; cat $TEST_TMPDIR/noclob3"

section "8. process substitution"
compare_output "input process sub" 'cat <(echo hello)'
compare_output "diff two process subs" 'diff <(echo a) <(echo a) && echo same'
compare_output "while read from process sub" 'while read line; do echo "got:$line"; done < <(printf "a\nb\n")'
compare_output "process sub with sort" 'sort <(printf "c\na\nb\n")'

print_summary
