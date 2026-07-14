#!/bin/sh
# ANSI-C $'...' embedded NUL: bash drops everything from the NUL to the
# closing quote but keeps adjacent segments of the same word. Before
# PARSE-6 the standalone path embedded a raw NUL byte in the token and the
# mid-word path silently dropped just the NUL — three-way disagreement.
# The two paths also disagreed on high bytes (\xff worked standalone,
# vanished mid-word); both now accept the full 0-255 range.
TEST_PREFIX="[ansic-nul]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. NUL ends the \$'...' segment (both lexer paths)"

compare_both "octal NUL standalone"      "printf '%s|' \$'a\\0b'"
compare_both "octal NUL mid-word"        "printf '%s|' pre\$'a\\0b'"
compare_both "hex NUL standalone"        "printf '%s|' \$'a\\x00b'"
compare_both "hex NUL mid-word"          "printf '%s|' pre\$'a\\x00b'"
compare_both "unicode NUL"               "printf '%s|' \$'a\\u0000b'"
compare_both "bare NUL yields empty"     "printf '%s|' \$'\\0'"

section "2. Adjacent segments of the word survive"

compare_both "post segment kept"         "printf '%s|' \$'a\\0b'post"
compare_both "pre and post kept"         "printf '%s|' pre\$'a\\0b'post"
compare_both "escaped quote inside cut"  "printf '%s|' \$'a\\0b\\'c'"

section "3. Non-NUL escapes agree between paths"

compare_both "octal 1"                   "printf '%s|' \$'a\\1b'"
compare_both "octal 101 is A"            "printf '%s|' \$'\\101'"
compare_both "hex ff standalone"         "printf '%s|' \$'\\xff'"
compare_both "hex ff mid-word"           "printf '%s|' pre\$'\\xff'"
compare_both "octal 377 mid-word"        "printf '%s|' pre\$'\\377'"
compare_both "newline escape"            "printf '%s|' \$'a\\nb'"
compare_both "unknown escape kept"       "printf '%s|' \$'a\\qb'"

print_summary
