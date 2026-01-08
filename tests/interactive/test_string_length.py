#!/usr/bin/env python3
import sys
sys.path.insert(0, '/home/mfwolffe/GithubOrgs/FortranGoingOnForty/fortsh-fixes/tests/interactive')

from utils.fortsh_pty import FortshPTY
import time

pty = FortshPTY('/home/mfwolffe/GithubOrgs/FortranGoingOnForty/fortsh-fixes/bin/fortsh')
pty.start()

# Wait for initial prompt
time.sleep(0.5)
pty.expect_prompt(timeout=2)

# Send the command
print("Sending command...")
pty.send_line("VAR=hello; echo ${#VAR}")

# Wait as the test does
print("Waiting 1.0s...")
time.sleep(1.0)

# Read output
print("Reading output...")
output = pty.read_output(timeout=2)
print(f"Raw output: {repr(output)}")
print(f"Output contains '5': {'5' in output}")
print(f"Output contains '>': {'>' in output}")

# Try to see the actual buffer
print("\nTrying to read more...")
try:
    more = pty.process.read_nonblocking(size=1024, timeout=1)
    print(f"Additional output: {repr(more)}")
except:
    print("No additional output")

pty.stop()
