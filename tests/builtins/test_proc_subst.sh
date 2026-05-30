#!/bin/sh
TEST_PREFIX="[proc-subst]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. basic process substitution"
compare_output "cat input proc sub" 'cat <(echo hello)'
compare_output "cat multi-word" 'cat <(echo hello world)'
compare_output "empty proc sub" 'cat <(true); echo done'
compare_output "proc sub exit code" 'diff <(echo same) <(echo same); echo $?'

section "2. execution-time expansion (bash-compatible)"
compare_output "same-line function visible" 'f() { echo NATIVE; }; cat <(f)'
compare_output "same-line variable visible" 'MYVAL=42; cat <(echo $MYVAL)'
compare_output "prior assignment visible" 'x=hello; cat <(echo $x)'

section "3. content inside proc sub"
compare_output "pipeline inside" 'cat <(echo hello | tr h H)'
compare_output "semicolons inside" 'cat <(echo a; echo b; echo c)'
compare_output "arithmetic inside" 'cat <(echo $((2+3)))'
compare_output "variable expansion inside" 'x=world; cat <(echo hello $x)'

section "4. multiple process substitutions"
compare_exit "diff identical" 'diff <(echo same) <(echo same)'
compare_output "diff shows difference" 'diff <(echo a) <(echo b) | head -1'
compare_output "paste two streams" 'paste <(echo a) <(echo b)'

section "5. quoting prevents expansion"
compare_output "single-quoted literal" "echo '<(literal)'"
compare_output "double-quoted literal" 'echo "<(literal)"'

section "6. nested process substitution"
compare_output "nested input" 'cat <(cat <(echo nested))'

section "7. proc sub with other features"
compare_output "in variable assignment" 'x=$(cat <(echo captured)); echo $x'
compare_output "with grep" 'grep hello <(printf "hello\nworld\n")'
