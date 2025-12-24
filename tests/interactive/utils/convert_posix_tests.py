#!/usr/bin/env python3
"""
Convert non-interactive POSIX compliance tests to interactive YAML format.

This tool parses posix_compliance*.sh files and generates YAML test specifications
that can be run with the interactive test framework.
"""

import re
import sys
import yaml
from pathlib import Path
from typing import List, Dict, Any, Optional


class POSIXTestConverter:
    """Convert POSIX shell tests to interactive YAML format."""

    def __init__(self):
        self.current_section = None
        self.tests = []

    def parse_section(self, line: str) -> Optional[str]:
        """Parse a section declaration."""
        match = re.match(r'section\s+"([^"]+)"', line)
        if match:
            return match.group(1)
        return None

    def parse_compare_posix_output(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse: compare_posix_output "test name" "command"

        Returns a test dictionary ready for YAML output.
        """
        # Handle both single and double quoted commands
        match = re.match(r'compare_posix_output\s+"([^"]+)"\s+"([^"]+)"', line)
        if not match:
            match = re.match(r"compare_posix_output\s+'([^']+)'\s+'([^']+)'", line)
        if not match:
            # Try mixed quotes
            match = re.match(r'compare_posix_output\s+"([^"]+)"\s+\'([^\']+)\'', line)

        if match:
            name, command = match.groups()

            # Estimate expected output based on command
            expected_output = self._estimate_output(command)

            return {
                'name': f"{self.current_section}: {name}" if self.current_section else name,
                'steps': [{'send_line': command}],
                'expect_output': expected_output,
                'match_type': 'contains'
            }

        return None

    def parse_compare_posix_exit_code(self, line: str) -> Optional[Dict[str, Any]]:
        """
        Parse: compare_posix_exit_code "test name" "command"

        Exit code tests are harder in interactive mode - we need to check $?
        """
        match = re.match(r'compare_posix_exit_code\s+"([^"]+)"\s+"([^"]+)"', line)
        if match:
            name, command = match.groups()

            # Add step to check exit code
            return {
                'name': f"{self.current_section}: {name} (exit code)" if self.current_section else f"{name} (exit code)",
                'steps': [
                    {'send_line': command},
                    {'send_line': 'echo "EXIT=$?"'}
                ],
                'expect_output': 'EXIT=',  # Will need manual adjustment
                'match_type': 'contains',
                'note': 'MANUAL REVIEW NEEDED: Check expected exit code'
            }

        return None

    def _estimate_output(self, command: str) -> str:
        """
        Estimate the expected output of a command.

        This is a best-effort heuristic and may need manual review.
        """
        # Simple echo commands
        if command.startswith('echo '):
            # Extract what's being echoed
            echo_match = re.match(r'echo\s+(.+)', command)
            if echo_match:
                content = echo_match.group(1)
                # Remove quotes if present
                content = content.strip('\'"')
                # Handle variable expansion markers
                if '$' in content:
                    return 'MANUAL_REVIEW'  # Variables need manual check
                return content

        # printf commands
        if command.startswith('printf '):
            return 'MANUAL_REVIEW'  # printf is complex

        # Variable assignments followed by echo
        if ';' in command:
            parts = command.split(';')
            last_part = parts[-1].strip()
            if last_part.startswith('echo '):
                return self._estimate_output(last_part)

        # Commands that typically produce numeric output
        if 'wc -l' in command or 'grep -c' in command:
            return 'DIGIT'  # Will match any digit

        # Default: mark for manual review
        return 'MANUAL_REVIEW'

    def parse_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Parse a POSIX compliance test file and extract tests."""
        self.tests = []

        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()

                # Check for section
                section = self.parse_section(line)
                if section:
                    self.current_section = section
                    continue

                # Check for compare_posix_output
                test = self.parse_compare_posix_output(line)
                if test:
                    self.tests.append(test)
                    continue

                # Check for compare_posix_exit_code
                test = self.parse_compare_posix_exit_code(line)
                if test:
                    self.tests.append(test)
                    continue

        return self.tests

    def generate_yaml(self, tests: List[Dict[str, Any]], category: str) -> str:
        """Generate YAML output for tests."""
        output = {
            'metadata': {
                'category': category,
                'description': f'Tests converted from POSIX compliance suite',
                'auto_generated': True,
                'needs_review': 'Tests with MANUAL_REVIEW need expected output verification'
            },
            'tests': tests
        }

        return yaml.dump(output, default_flow_style=False, sort_keys=False)


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <posix_compliance_file.sh> [output.yaml]")
        print("\nExample:")
        print(f"  {sys.argv[0]} ../../fortsh/tests/posix_compliance_gaps.sh gaps_interactive.yaml")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if not input_file.exists():
        print(f"Error: File not found: {input_file}")
        sys.exit(1)

    output_file = Path(sys.argv[2]) if len(sys.argv) > 2 else None

    # Determine category from filename
    category = input_file.stem.replace('posix_compliance_', '').replace('_', ' ').title()

    # Convert tests
    converter = POSIXTestConverter()
    tests = converter.parse_file(input_file)

    print(f"Parsed {len(tests)} tests from {input_file}")

    # Count tests needing review
    needs_review = sum(1 for t in tests if
                      'MANUAL_REVIEW' in str(t.get('expect_output', '')) or
                      'note' in t)

    if needs_review > 0:
        print(f"⚠️  {needs_review} tests need manual review of expected output")

    # Generate YAML
    yaml_content = converter.generate_yaml(tests, category)

    if output_file:
        output_file.write_text(yaml_content)
        print(f"✓ Wrote YAML to {output_file}")
    else:
        print("\n" + "="*60)
        print("Generated YAML:")
        print("="*60)
        print(yaml_content)

    # Print statistics
    print(f"\nStatistics:")
    print(f"  Total tests: {len(tests)}")
    print(f"  Needs review: {needs_review}")
    print(f"  Ready to use: {len(tests) - needs_review}")


if __name__ == '__main__':
    main()
