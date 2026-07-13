#!/bin/sh
# Bash case terminators ;& (fall through) and ;;& (retest remaining patterns).
# Before PARSE-1 these tokenized as `;`/`;;` plus a stray `&`, and the case
# parser spun forever on the leftover token. compare_output runs under
# run_with_timeout, so a regression to that hang shows up as a failed test
# (mismatched/empty output) rather than an infinite run.
TEST_PREFIX="[case-fallthrough]"
. "$(cd "$(dirname "$0")" && pwd)/test_harness.sh"

section "1. ;& fallthrough"

compare_both "single ;& falls into next body" \
    'case a in a) echo one;& b) echo two;; esac'
compare_both "chained ;& runs every following body" \
    'case a in a) echo one;& b) echo two;& c) echo three;; esac'
compare_both ";& stops at the next ;;" \
    'case a in a) echo one;& b) echo two;; c) echo three;; esac'
compare_both ";& body runs unconditionally (pattern would not match)" \
    'case a in a) echo A;& zzz) echo Z;; esac'

section "2. ;;& retest"

compare_both ";;& re-tests remaining patterns" \
    'case a in a) echo one;;& a) echo two;; esac'
compare_both ";;& then a non-matching pattern is skipped" \
    'case a in a) echo A;;& b) echo B;; esac'
compare_both ";;& glob then exact both fire" \
    'case foo in f*) echo star;;& foo) echo exact;; *) echo any;; esac'

section "3. Plain ;; is unaffected"

compare_both "exact match with ;;" \
    'case x in a) echo A;; x) echo X;; esac'
compare_both "default with ;;" \
    'case z in a) echo a;; *) echo default;; esac'

section "4. Exit status propagates through terminators"

compare_both "; & carries last body exit status" \
    'case a in a) echo A;& b) false;; esac; echo rc=$?'
compare_both ";;& match sets exit status" \
    'case q in a) true;; q) false;; esac; echo rc=$?'

print_summary
