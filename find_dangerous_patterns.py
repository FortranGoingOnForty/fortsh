#!/usr/bin/env python3
"""
Find dangerous .and./.or. patterns in Fortran code.
These are patterns where array/string indexing might happen after a failed bounds check.
"""

import re
import sys
from pathlib import Path

# Patterns that indicate array/string access
ACCESS_PATTERNS = [
    r'\([i\d+\-\+:]+\)',  # Array/string access like (i), (i-1:i-1), (i:i+1)
]

# Compile regex for .and. and .or.
AND_OR_PATTERN = re.compile(r'\.(?:and|or)\.', re.IGNORECASE)

def is_dangerous_line(line):
    """Check if a line contains both .and./.or. AND array/string access."""
    # Must have .and. or .or.
    if not AND_OR_PATTERN.search(line):
        return False

    # Must have array/string indexing with variables
    has_index = False
    for pattern in ACCESS_PATTERNS:
        if re.search(pattern, line):
            # Check if it's accessing with i, i-1, i+1, pos, etc.
            if re.search(r'\([i\w]*[\+\-]\d+[:\w]*\)', line) or \
               re.search(r'\([i\w]+:[i\w]+[\+\-]?\d*\)', line) or \
               re.search(r'\(pos[\+\-]?\d*:', line) or \
               re.search(r'\([i\w]+[\+\-]\d+\)', line):
                has_index = True
                break

    return has_index

def analyze_file(filepath):
    """Analyze a Fortran file for dangerous patterns."""
    dangerous_lines = []

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                stripped = line.strip()
                # Skip comments
                if stripped.startswith('!'):
                    continue

                if is_dangerous_line(line):
                    dangerous_lines.append((line_num, line.rstrip()))
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return []

    return dangerous_lines

def main():
    src_dir = Path('src')
    if not src_dir.exists():
        print("Error: src directory not found", file=sys.stderr)
        sys.exit(1)

    # Find all .f90 files
    f90_files = list(src_dir.rglob('*.f90'))

    print(f"Analyzing {len(f90_files)} Fortran files...")
    print("=" * 80)

    total_issues = 0
    files_with_issues = {}

    for f90_file in sorted(f90_files):
        dangerous = analyze_file(f90_file)
        if dangerous:
            files_with_issues[str(f90_file)] = dangerous
            total_issues += len(dangerous)
            print(f"\n{f90_file}:")
            for line_num, line in dangerous[:10]:  # Show first 10
                print(f"  {line_num:5d}: {line}")
            if len(dangerous) > 10:
                print(f"  ... and {len(dangerous) - 10} more lines")

    print("\n" + "=" * 80)
    print(f"Summary: Found {total_issues} potentially dangerous patterns in {len(files_with_issues)} files")

    # Write detailed report
    report_file = Path('dangerous_patterns_report.txt')
    with open(report_file, 'w') as f:
        f.write(f"Dangerous Fortran Patterns Report\n")
        f.write(f"{'=' * 80}\n\n")

        for filepath, lines in sorted(files_with_issues.items()):
            f.write(f"\n{filepath}: {len(lines)} issues\n")
            f.write('-' * 80 + '\n')
            for line_num, line in lines:
                f.write(f"{line_num:5d}: {line}\n")
            f.write('\n')

    print(f"Detailed report written to: {report_file}")

    return 0 if total_issues == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
