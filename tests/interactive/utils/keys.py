"""
Key sequence definitions for terminal input simulation.

These escape sequences follow standard xterm/VT100 conventions.
"""

# Arrow keys (CSI sequences)
ARROW_UP = "\x1b[A"
ARROW_DOWN = "\x1b[B"
ARROW_RIGHT = "\x1b[C"
ARROW_LEFT = "\x1b[D"

# Shift-modified arrow / nav keys (xterm modifier 2 = Shift)
# Used for native text selection (shift phase, Sprint 1+).
SHIFT_ARROW_UP = "\x1b[1;2A"
SHIFT_ARROW_DOWN = "\x1b[1;2B"
SHIFT_ARROW_RIGHT = "\x1b[1;2C"
SHIFT_ARROW_LEFT = "\x1b[1;2D"
SHIFT_HOME = "\x1b[1;2H"
SHIFT_END = "\x1b[1;2F"

# Ctrl+Shift arrow (xterm modifier 6) — word-wise selection extension
CTRL_SHIFT_ARROW_RIGHT = "\x1b[1;6C"
CTRL_SHIFT_ARROW_LEFT = "\x1b[1;6D"

# Alt+Shift letter (ESC + uppercase) — emacs-native word-wise selection
ALT_SHIFT_B = "\x1bB"
ALT_SHIFT_F = "\x1bF"

# Alt+Shift arrow (xterm modifier 4) — fortsh binds these to dir history
ALT_SHIFT_UP = "\x1b[1;4A"
ALT_SHIFT_DOWN = "\x1b[1;4B"
ALT_SHIFT_LEFT = "\x1b[1;4D"
ALT_SHIFT_RIGHT = "\x1b[1;4C"

# Control keys (ASCII control characters)
CTRL_A = "\x01"  # Beginning of line
CTRL_B = "\x02"  # Back one character
CTRL_C = "\x03"  # Interrupt (SIGINT)
CTRL_D = "\x04"  # Delete char / EOF
CTRL_E = "\x05"  # End of line
CTRL_F = "\x06"  # Forward one character
CTRL_G = "\x07"  # Cancel
CTRL_H = "\x08"  # Backspace (alternative)
CTRL_I = "\x09"  # Tab
CTRL_J = "\x0a"  # Newline
CTRL_K = "\x0b"  # Kill to end of line
CTRL_L = "\x0c"  # Clear screen
CTRL_M = "\x0d"  # Carriage return (Enter)
CTRL_N = "\x0e"  # Next history
CTRL_O = "\x0f"  # Operate and get next
CTRL_P = "\x10"  # Previous history
CTRL_Q = "\x11"  # Resume output
CTRL_R = "\x12"  # Reverse search
CTRL_S = "\x13"  # Forward search / Suspend output
CTRL_T = "\x14"  # Transpose characters
CTRL_U = "\x15"  # Kill to beginning of line
CTRL_V = "\x16"  # Quoted insert
CTRL_W = "\x17"  # Kill word backward
CTRL_X = "\x18"  # Prefix
CTRL_Y = "\x19"  # Yank
CTRL_Z = "\x1a"  # Suspend (SIGTSTP)

# Alt/Meta keys (ESC + key)
ALT_B = "\x1bb"  # Back one word
ALT_C = "\x1bc"  # Capitalize word
ALT_D = "\x1bd"  # Delete word forward
ALT_F = "\x1bf"  # Forward one word
ALT_L = "\x1bl"  # Lowercase word
ALT_T = "\x1bt"  # Transpose words
ALT_U = "\x1bu"  # Uppercase word
ALT_W = "\x1bw"  # Copy selection (shift phase) / Accept word from suggestion
ALT_Y = "\x1by"  # Yank pop
ALT_DOT = "\x1b."  # Insert last argument
ALT_BACKSPACE = "\x1b\x7f"  # Delete word backward

# Special keys
TAB = "\t"
ENTER = "\r"
NEWLINE = "\n"
BACKSPACE = "\x7f"
ESCAPE = "\x1b"

# Extended keys (xterm sequences)
DELETE = "\x1b[3~"
HOME = "\x1b[H"
END = "\x1b[F"
PAGE_UP = "\x1b[5~"
PAGE_DOWN = "\x1b[6~"
INSERT = "\x1b[2~"

# Alternative Home/End sequences (some terminals use these)
HOME_ALT = "\x1b[1~"
END_ALT = "\x1b[4~"

# Function keys
F1 = "\x1bOP"
F2 = "\x1bOQ"
F3 = "\x1bOR"
F4 = "\x1bOS"
F5 = "\x1b[15~"
F6 = "\x1b[17~"
F7 = "\x1b[18~"
F8 = "\x1b[19~"
F9 = "\x1b[20~"
F10 = "\x1b[21~"
F11 = "\x1b[23~"
F12 = "\x1b[24~"

# Key name to sequence mapping (for YAML test specs)
KEYS = {
    # Arrow keys
    "Up": ARROW_UP,
    "Down": ARROW_DOWN,
    "Right": ARROW_RIGHT,
    "Left": ARROW_LEFT,

    # Shift-modified navigation (for native text selection)
    "S-Up": SHIFT_ARROW_UP,
    "S-Down": SHIFT_ARROW_DOWN,
    "S-Right": SHIFT_ARROW_RIGHT,
    "S-Left": SHIFT_ARROW_LEFT,
    "S-Home": SHIFT_HOME,
    "S-End": SHIFT_END,

    # Ctrl+Shift navigation (word-wise selection)
    "C-S-Right": CTRL_SHIFT_ARROW_RIGHT,
    "C-S-Left": CTRL_SHIFT_ARROW_LEFT,

    # Alt+Shift letter (emacs word-wise selection)
    "M-B": ALT_SHIFT_B,
    "M-F": ALT_SHIFT_F,

    # Alt+Shift arrows (fortsh directory history, NOT selection)
    "M-S-Up": ALT_SHIFT_UP,
    "M-S-Down": ALT_SHIFT_DOWN,
    "M-S-Left": ALT_SHIFT_LEFT,
    "M-S-Right": ALT_SHIFT_RIGHT,

    # Control keys
    "C-a": CTRL_A,
    "C-b": CTRL_B,
    "C-c": CTRL_C,
    "C-d": CTRL_D,
    "C-e": CTRL_E,
    "C-f": CTRL_F,
    "C-g": CTRL_G,
    "C-h": CTRL_H,
    "C-k": CTRL_K,
    "C-l": CTRL_L,
    "C-n": CTRL_N,
    "C-p": CTRL_P,
    "C-r": CTRL_R,
    "C-s": CTRL_S,
    "C-t": CTRL_T,
    "C-u": CTRL_U,
    "C-w": CTRL_W,
    "C-y": CTRL_Y,
    "C-z": CTRL_Z,

    # Alt/Meta keys
    "M-b": ALT_B,
    "M-c": ALT_C,
    "M-d": ALT_D,
    "M-f": ALT_F,
    "M-l": ALT_L,
    "M-t": ALT_T,
    "M-u": ALT_U,
    "M-w": ALT_W,
    "M-y": ALT_Y,
    "M-.": ALT_DOT,
    "M-Backspace": ALT_BACKSPACE,

    # Special keys
    "Tab": TAB,
    "Enter": ENTER,
    "Return": ENTER,
    "Backspace": BACKSPACE,
    "Delete": DELETE,
    "Home": HOME,
    "End": END,
    "PageUp": PAGE_UP,
    "PageDown": PAGE_DOWN,
    "Insert": INSERT,
    "Escape": ESCAPE,
    "Esc": ESCAPE,

    # Function keys
    "F1": F1,
    "F2": F2,
    "F3": F3,
    "F4": F4,
    "F5": F5,
    "F6": F6,
    "F7": F7,
    "F8": F8,
    "F9": F9,
    "F10": F10,
    "F11": F11,
    "F12": F12,
}


def get_key(name: str) -> str:
    """
    Get the escape sequence for a key name.

    Args:
        name: Key name (e.g., "Up", "C-a", "M-f", "Enter")

    Returns:
        The escape sequence for that key

    Raises:
        KeyError: If the key name is not recognized
    """
    if name not in KEYS:
        raise KeyError(f"Unknown key: {name}. Available keys: {sorted(KEYS.keys())}")
    return KEYS[name]


def key_sequence(*keys: str) -> str:
    """
    Build a sequence of multiple keys.

    Args:
        *keys: Key names to combine

    Returns:
        Combined escape sequence string

    Example:
        key_sequence("C-a", "C-k")  # Move to beginning, kill to end
    """
    return "".join(get_key(k) for k in keys)
