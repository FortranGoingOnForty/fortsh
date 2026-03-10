#!/bin/sh
TEST_PREFIX="[read]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. read basic"
compare_output "read from herestring" 'read VAR <<< "hello"; echo $VAR'
compare_output "read multiple vars" 'read A B C <<< "one two three"; echo "$A|$B|$C"'
compare_output "read excess into last var" 'read A B <<< "one two three four"; echo "$A|$B"'
compare_output "read single var gets all" 'read LINE <<< "hello world test"; echo "$LINE"'
compare_output "read with empty input" 'read VAR <<< ""; echo ">${VAR}<"'

section "2. read flags"
compare_output "read -r preserves backslash" 'read -r VAR <<< "hello\\world"; echo "$VAR"'
compare_output "read without -r interprets backslash" 'read VAR <<< "hello\\\\world"; echo "$VAR"'
compare_output "read -a into array" 'read -a ARR <<< "a b c"; echo ${ARR[0]} ${ARR[1]} ${ARR[2]}'
compare_output "read -a array length" 'read -a ARR <<< "x y z"; echo ${#ARR[@]}'

section "3. read with IFS"
compare_output "read with colon IFS" 'IFS=: read A B C <<< "x:y:z"; echo "$A|$B|$C"'
compare_output "read with comma IFS" 'IFS=, read A B C <<< "a,b,c"; echo "$A|$B|$C"'
compare_output "read with custom IFS excess" 'IFS=: read A B <<< "x:y:z"; echo "$A|$B"'
compare_output "read with space IFS default" 'read A B <<< "  hello   world  "; echo ">$A<>$B<"'

section "4. read from heredoc"
compare_output "read from heredoc" 'read VAR << EOF
hello
EOF
echo $VAR'
compare_output "read loop from heredoc" 'while read line; do echo "got:$line"; done << EOF
alpha
beta
EOF'

section "5. read edge cases"
compare_exit "read with no input returns 1" 'echo -n "" | read VAR'
compare_output "read preserves whitespace with IFS empty" 'IFS= read line <<< "  spaces  "; echo ">$line<"'
compare_output "read -r with trailing backslash" 'read -r VAR <<< "end\\"; echo "$VAR"'

print_summary
