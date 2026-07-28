"""Small foreground-TTY probe used by interactive shell tests."""

import os
import sys
import termios


attrs = termios.tcgetattr(sys.stdin.fileno())
print(
    "TTY_STATE "
    f"foreground={int(os.getpgrp() == os.tcgetpgrp(sys.stdin.fileno()))} "
    f"canonical={int(bool(attrs[3] & termios.ICANON))} "
    f"echo={int(bool(attrs[3] & termios.ECHO))}",
    flush=True,
)
print("CONFIRM [Y/n]:", end="", flush=True)
answer = sys.stdin.readline().rstrip("\r\n")
print(f"ANSWER={answer}", flush=True)
