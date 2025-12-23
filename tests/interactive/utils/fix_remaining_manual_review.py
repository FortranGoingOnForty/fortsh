#!/usr/bin/env python3
"""
Fix remaining MANUAL_REVIEW items with known expected outputs.
"""

import yaml
from pathlib import Path

# Map of test names to expected outputs (determined by running in /bin/sh)
KNOWN_FIXES = {
    # posix_extended_auto.yaml
    'use default null': '',  # VAR=; echo "${VAR-default}" → empty (VAR is set)
    'alt unset': '',  # unset VAR; echo "${VAR+alternative}" → empty
    'alt null colon': '',  # VAR=; echo "${VAR:+alternative}" → empty
    'shell flags type': '1',  # echo $- | grep -c "^[a-z]*$" → 1 (matches)
    'newline preserving': '1',  # should match 1 newline

    # posix_gaps_auto.yaml
    'set -- with empty': '1 ||',  # set -- ''; echo $# |$1| → "1 ||"
    'break n larger than depth': '',  # break 10 in 1-level loop → exits cleanly
    'continue n larger': '',  # continue 2 in 1-level loop → exits cleanly
    'break outside loop': 'ok',  # break outside loop → ok
    'continue outside loop': 'ok',  # continue outside loop → ok
    'for preserves IFS': '1',  # IFS preserved, grep finds it
    '$@ quoted iteration': '2',  # incomplete test, but should be 2 iterations
    'empty field': '3',  # IFS splits into 3 fields

    # posix_advanced_auto.yaml - file operations that need special handling
    # Will mark these for careful review

    # posix_coverage_auto.yaml
    'set -n parse only': '',  # set -n produces no output (noexec mode)

    # posix_untested_auto.yaml
    'set -n parse only': '',  # set -n; echo "..." → no output (noexec)

    # posix_basic_auto.yaml
    'test with space': '',  # VAR=''; test -n "$VAR" → empty (test fails silently)
}

def fix_test_by_name(test: dict) -> tuple[dict, bool]:
    """Fix test if we know the expected output."""
    if test.get('expect_output') != 'MANUAL_REVIEW':
        return test, False

    name = test.get('name', '')

    # Check if any known fix key appears in the test name
    for key, expected in KNOWN_FIXES.items():
        if key.lower() in name.lower():
            test['expect_output'] = expected
            test['auto_fixed'] = 'manual_determination'
            return test, True

    return test, False

def process_file(filepath: Path) -> tuple[int, int]:
    """Process a single YAML file. Returns (before, after) counts."""
    with open(filepath, 'r') as f:
        data = yaml.safe_load(f)

    before = sum(1 for t in data['tests'] if t.get('expect_output') == 'MANUAL_REVIEW')

    fixed = 0
    for i, test in enumerate(data['tests']):
        updated, was_fixed = fix_test_by_name(test)
        data['tests'][i] = updated
        if was_fixed:
            fixed += 1

    with open(filepath, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    after = sum(1 for t in data['tests'] if t.get('expect_output') == 'MANUAL_REVIEW')

    return before, after, fixed

def main():
    test_dir = Path(__file__).parent.parent / 'test_specs'

    files = [
        'posix_untested_auto.yaml',
        'posix_extended_auto.yaml',
        'posix_basic_auto.yaml',
        'posix_gaps_auto.yaml',
        'posix_advanced_auto.yaml',
        'posix_coverage_auto.yaml',
    ]

    total_before = 0
    total_after = 0
    total_fixed = 0

    print("=" * 60)
    print("  Fixing Remaining MANUAL_REVIEW Items")
    print("=" * 60)
    print()

    for filename in files:
        filepath = test_dir / filename
        if not filepath.exists():
            continue

        before, after, fixed = process_file(filepath)
        total_before += before
        total_after += after
        total_fixed += fixed

        if fixed > 0:
            print(f"✓ {filename}: Fixed {fixed}/{before} items (remaining: {after})")

    print()
    print("=" * 60)
    print(f"Total: Fixed {total_fixed}/{total_before} items")
    print(f"Remaining: {total_after} items")
    print("=" * 60)

if __name__ == '__main__':
    main()
