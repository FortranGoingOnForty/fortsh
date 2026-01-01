#!/bin/sh
# =====================================
# POSIX Character Class Gap Tests
# =====================================
# Tests for POSIX character classes in bracket expressions
# Split from posix_compliance_gaps.sh for better organization

# Colors (POSIX-compliant way)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test identification
TEST_PREFIX="[gaps-charclass]"
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
    if [ -n "$2" ]; then printf "  posix:  %s\n" "$2"; fi
    if [ -n "$3" ]; then printf "  fortsh: %s\n" "$3"; fi
    FAILED=$((FAILED + 1))
}

section() {
    CURRENT_SECTION=$(echo "$1" | grep -oE '^[0-9]+' || echo "0")
    TEST_NUM=0
    printf "\n${BLUE}==========================================\n%s\n==========================================${NC}\n" "$1"
}

normalize_output() { sed -e 's/^bash: /sh: /' -e 's/line [0-9]*: //'; }

compare_posix_output() {
    test_name="$1"; command="$2"
    posix_out=$(bash -c "$command" 2>&1 | normalize_output)
    fortsh_out=$("$FORTSH_BIN" -c "$command" 2>&1 | normalize_output)
    if [ "$posix_out" = "$fortsh_out" ]; then pass "$test_name"
    else fail "$test_name" "$posix_out" "$fortsh_out"; fi
}

# ============================================================================
# CHARACTER CLASS TESTS
# ============================================================================

section "1. CHARACTER CLASS ALNUM"
compare_posix_output "alnum a" 'case a in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum Z" 'case Z in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum 5" 'case 5 in [[:alnum:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alnum excl" 'case "!" in [[:alnum:]]) echo yes;; *) echo no;; esac'

section "2. CHARACTER CLASS ALPHA"
compare_posix_output "alpha a" 'case a in [[:alpha:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alpha Z" 'case Z in [[:alpha:]]) echo yes;; *) echo no;; esac'
compare_posix_output "alpha 5" 'case 5 in [[:alpha:]]) echo yes;; *) echo no;; esac'

section "3. CHARACTER CLASS DIGIT"
compare_posix_output "digit 0" 'case 0 in [[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "digit 9" 'case 9 in [[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "digit a" 'case a in [[:digit:]]) echo yes;; *) echo no;; esac'

section "4. CHARACTER CLASS LOWER"
compare_posix_output "lower a" 'case a in [[:lower:]]) echo yes;; *) echo no;; esac'
compare_posix_output "lower z" 'case z in [[:lower:]]) echo yes;; *) echo no;; esac'
compare_posix_output "lower A" 'case A in [[:lower:]]) echo yes;; *) echo no;; esac'

section "5. CHARACTER CLASS UPPER"
compare_posix_output "upper A" 'case A in [[:upper:]]) echo yes;; *) echo no;; esac'
compare_posix_output "upper Z" 'case Z in [[:upper:]]) echo yes;; *) echo no;; esac'
compare_posix_output "upper a" 'case a in [[:upper:]]) echo yes;; *) echo no;; esac'

section "6. CHARACTER CLASS SPACE"
compare_posix_output "space sp" 'case " " in [[:space:]]) echo yes;; *) echo no;; esac'
compare_posix_output "space tab" 'case "	" in [[:space:]]) echo yes;; *) echo no;; esac'
compare_posix_output "space a" 'case a in [[:space:]]) echo yes;; *) echo no;; esac'

section "7. CHARACTER CLASS BLANK"
compare_posix_output "blank sp" 'case " " in [[:blank:]]) echo yes;; *) echo no;; esac'
compare_posix_output "blank tab" 'case "	" in [[:blank:]]) echo yes;; *) echo no;; esac'
compare_posix_output "blank a" 'case a in [[:blank:]]) echo yes;; *) echo no;; esac'

section "8. CHARACTER CLASS PUNCT"
compare_posix_output "punct dot" 'case "." in [[:punct:]]) echo yes;; *) echo no;; esac'
compare_posix_output "punct excl" 'case "!" in [[:punct:]]) echo yes;; *) echo no;; esac'
compare_posix_output "punct a" 'case a in [[:punct:]]) echo yes;; *) echo no;; esac'

section "9. CHARACTER CLASS XDIGIT"
compare_posix_output "xdigit 0" 'case 0 in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit a" 'case a in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit F" 'case F in [[:xdigit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "xdigit g" 'case g in [[:xdigit:]]) echo yes;; *) echo no;; esac'

section "10. CHARACTER CLASS PRINT GRAPH"
compare_posix_output "print a" 'case a in [[:print:]]) echo yes;; *) echo no;; esac'
compare_posix_output "print sp" 'case " " in [[:print:]]) echo yes;; *) echo no;; esac'
compare_posix_output "graph a" 'case a in [[:graph:]]) echo yes;; *) echo no;; esac'
compare_posix_output "graph sp" 'case " " in [[:graph:]]) echo yes;; *) echo no;; esac'

section "11. CHARACTER CLASS CNTRL"
compare_posix_output "cntrl a" 'case a in [[:cntrl:]]) echo yes;; *) echo no;; esac'

section "12. COMBINED CHARACTER CLASSES"
compare_posix_output "combo alpha digit a" 'case a in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "combo alpha digit 5" 'case 5 in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "combo alpha digit excl" 'case "!" in [[:alpha:][:digit:]]) echo yes;; *) echo no;; esac'

section "13. NEGATED CHARACTER CLASSES"
compare_posix_output "not digit a" 'case a in [^[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "not digit 5" 'case 5 in [^[:digit:]]) echo yes;; *) echo no;; esac'
compare_posix_output "not alpha bang" 'case a in [![:alpha:]]) echo yes;; *) echo no;; esac'

section "14. RANGE EXPRESSIONS"
compare_posix_output "range a-z m" 'case m in [a-z]) echo yes;; *) echo no;; esac'
compare_posix_output "range A-Z M" 'case M in [A-Z]) echo yes;; *) echo no;; esac'
compare_posix_output "range 0-9 5" 'case 5 in [0-9]) echo yes;; *) echo no;; esac'
compare_posix_output "range combo" 'case M in [a-zA-Z]) echo yes;; *) echo no;; esac'

section "15. BRACKET EDGE CASES"
compare_posix_output "literal hyphen start" 'case "-" in [-abc]) echo yes;; *) echo no;; esac'
compare_posix_output "literal hyphen end" 'case "-" in [abc-]) echo yes;; *) echo no;; esac'
compare_posix_output "literal caret" 'case "^" in [a^b]) echo yes;; *) echo no;; esac'
compare_posix_output "literal rbracket" 'case "]" in []abc]) echo yes;; *) echo no;; esac'

# Summary
printf "\n==========================================\n"
printf "CHARACTER CLASS GAP TEST RESULTS\n"
printf "==========================================\n"
printf "${GREEN}Passed:${NC}  %d\n" "$PASSED"
printf "${RED}Failed:${NC}  %d\n" "$FAILED"
printf "Total:   %d\n" "$((PASSED + FAILED))"
if [ "$FAILED" -gt 0 ]; then
    printf "\n${RED}Failed tests:${NC}\n%b" "$FAILED_TESTS_LIST"
    exit 1
fi
exit 0
