#!/usr/bin/env bash
# ==============================================================================
# Interactive Terminal Tests for fortsh
# Tests features that require real terminal interaction
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

FORTSH="${FORTSH:-./bin/fortsh}"

if [[ ! -x "$FORTSH" ]]; then
    echo -e "${RED}Error: fortsh binary not found at $FORTSH${RESET}"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    Interactive Terminal Tests for fortsh                    ║"
echo "║    (Manual verification required)                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}\n"

prompt_user() {
    local message="$1"
    echo -e "${YELLOW}${message}${RESET}"
    read -p "Press Enter to continue..."
}

test_section() {
    local title="$1"
    echo -e "\n${BOLD}${CYAN}═══ $title ═══${RESET}\n"
}

# ==============================================================================
# Test 1: Bracketed Paste Mode
# ==============================================================================

test_bracketed_paste() {
    test_section "Test 1: Bracketed Paste Mode"

    cat <<EOF
${BOLD}This test verifies that multi-line paste doesn't execute immediately.${RESET}

Instructions:
1. fortsh will start in interactive mode
2. Copy this multi-line code:

${GREEN}for i in 1 2 3; do
  echo "Number: \$i"
done${RESET}

3. Paste it into the fortsh prompt
4. Observe that it does NOT execute immediately
5. The entire block should appear on the command line
6. Press Enter to execute it
7. Type 'exit' to finish the test

EOF

    prompt_user "Ready to test bracketed paste?"

    echo -e "${BOLD}Starting fortsh...${RESET}\n"
    FORTSH_RC_FILE=/dev/null "$FORTSH"

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did the paste work correctly (text appeared without executing)? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Bracketed paste test PASSED${RESET}"
    else
        echo -e "${RED}✗ Bracketed paste test FAILED${RESET}"
    fi
}

# ==============================================================================
# Test 2: Window Resize (SIGWINCH)
# ==============================================================================

test_window_resize() {
    test_section "Test 2: Window Resize (SIGWINCH)"

    cat <<EOF
${BOLD}This test verifies that window resize is handled correctly.${RESET}

Instructions:
1. fortsh will start in interactive mode
2. Type: ${GREEN}echo \$COLUMNS \$LINES${RESET}
3. Note the values
4. Resize your terminal window (drag corner)
5. Type: ${GREEN}echo \$COLUMNS \$LINES${RESET} again
6. Verify that the values changed to match new size
7. Type a long command and verify cursor positioning works
8. Type 'exit' to finish

EOF

    prompt_user "Ready to test window resize?"

    echo -e "${BOLD}Starting fortsh...${RESET}\n"
    FORTSH_RC_FILE=/dev/null "$FORTSH"

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did COLUMNS/LINES update after resize? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Window resize test PASSED${RESET}"
    else
        echo -e "${RED}✗ Window resize test FAILED${RESET}"
    fi
}

# ==============================================================================
# Test 3: Colored Prompts & Cursor Positioning
# ==============================================================================

test_colored_prompts() {
    test_section "Test 3: Colored Prompts & Cursor Positioning"

    cat <<EOF
${BOLD}This test verifies that colored prompts don't break cursor positioning.${RESET}

Instructions:
1. fortsh will start with a colored prompt
2. Type a long command that wraps multiple lines
3. Verify that cursor stays in correct position
4. Use arrow keys to navigate - cursor should track correctly
5. Backspace should delete correctly without visual glitches
6. Type 'exit' to finish

EOF

    prompt_user "Ready to test colored prompts?"

    echo -e "${BOLD}Starting fortsh with colored prompt...${RESET}\n"
    # Set a colored prompt using PS1
    FORTSH_RC_FILE=/dev/null "$FORTSH" -c 'PS1="\[\e[1;32m\]fortsh\[\e[0m\]> "; exec ../bin/fortsh'

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did cursor positioning work correctly with colored prompt? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Colored prompt test PASSED${RESET}"
    else
        echo -e "${RED}✗ Colored prompt test FAILED${RESET}"
    fi
}

# ==============================================================================
# Test 4: Job Control & Job Specs
# ==============================================================================

test_job_specs() {
    test_section "Test 4: Job Control & Job Specs"

    cat <<EOF
${BOLD}This test verifies job control and job spec parsing.${RESET}

Instructions:
1. fortsh will start in interactive mode
2. Run: ${GREEN}sleep 100 &${RESET}
3. Run: ${GREEN}sleep 200 &${RESET}
4. Run: ${GREEN}jobs${RESET} - verify both jobs listed
5. Run: ${GREEN}fg %1${RESET} - bring job 1 to foreground
6. Press Ctrl-Z to suspend it
7. Run: ${GREEN}fg %%${RESET} - bring current job to foreground
8. Press Ctrl-Z again
9. Run: ${GREEN}fg %-${RESET} - bring previous job to foreground
10. Press Ctrl-C to kill it
11. Run: ${GREEN}kill %1${RESET} - kill remaining job
12. Type 'exit' to finish

EOF

    prompt_user "Ready to test job specs?"

    echo -e "${BOLD}Starting fortsh...${RESET}\n"
    FORTSH_RC_FILE=/dev/null "$FORTSH"

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did job specs (%1, %%, %-, etc.) work correctly? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Job specs test PASSED${RESET}"
    else
        echo -e "${RED}✗ Job specs test FAILED${RESET}"
    fi
}

# ==============================================================================
# Test 5: Terminal Title Updates
# ==============================================================================

test_terminal_title() {
    test_section "Test 5: Terminal Title Updates"

    cat <<EOF
${BOLD}This test verifies that terminal title updates correctly.${RESET}

Instructions:
1. Look at your terminal window/tab title BEFORE starting fortsh
2. Note the current title
3. fortsh will start in interactive mode
4. Check if terminal title changed to show: user@host:/path
5. Run: ${GREEN}cd /tmp${RESET}
6. Check if title updated to show new path
7. Type 'exit' to finish

EOF

    prompt_user "Ready to test terminal title?"

    echo -e "${BOLD}Starting fortsh...${RESET}\n"
    echo -e "${YELLOW}Check your terminal window title NOW${RESET}"
    sleep 2

    FORTSH_RC_FILE=/dev/null "$FORTSH"

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did terminal title update to show user@host:path? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Terminal title test PASSED${RESET}"
    else
        echo -e "${RED}✗ Terminal title test FAILED${RESET}"
    fi
}

# ==============================================================================
# Test 6: UTF-8 Wide Characters
# ==============================================================================

test_utf8_wide_chars() {
    test_section "Test 6: UTF-8 Wide Characters"

    cat <<EOF
${BOLD}This test verifies UTF-8 wide character handling.${RESET}

Instructions:
1. fortsh will start in interactive mode
2. Type: ${GREEN}echo "🚀 Rocket"${RESET}
3. Verify emoji displays correctly
4. Type: ${GREEN}echo "中文字"${RESET}
5. Verify Chinese characters display correctly
6. Set prompt with emoji: ${GREEN}PS1="🚀 > "${RESET}
7. Type a long command - verify cursor positioning is correct
8. Arrow keys should work correctly with emoji prompt
9. Type 'exit' to finish

EOF

    prompt_user "Ready to test UTF-8 wide characters?"

    echo -e "${BOLD}Starting fortsh...${RESET}\n"
    FORTSH_RC_FILE=/dev/null "$FORTSH"

    echo -e "\n${GREEN}Test complete!${RESET}"
    read -p "Did UTF-8 wide characters display and position correctly? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ UTF-8 wide chars test PASSED${RESET}"
    else
        echo -e "${RED}✗ UTF-8 wide chars test FAILED${RESET}"
    fi
}

# ==============================================================================
# Main Menu
# ==============================================================================

main_menu() {
    while true; do
        echo -e "\n${BOLD}${CYAN}Select a test to run:${RESET}\n"
        echo "  1) Bracketed Paste Mode"
        echo "  2) Window Resize (SIGWINCH)"
        echo "  3) Colored Prompts & Cursor Positioning"
        echo "  4) Job Control & Job Specs"
        echo "  5) Terminal Title Updates"
        echo "  6) UTF-8 Wide Characters"
        echo "  7) Run ALL tests"
        echo "  0) Exit"
        echo ""
        read -p "Enter choice [0-7]: " choice

        case "$choice" in
            1) test_bracketed_paste ;;
            2) test_window_resize ;;
            3) test_colored_prompts ;;
            4) test_job_specs ;;
            5) test_terminal_title ;;
            6) test_utf8_wide_chars ;;
            7)
                test_bracketed_paste
                test_window_resize
                test_colored_prompts
                test_job_specs
                test_terminal_title
                test_utf8_wide_chars
                ;;
            0)
                echo -e "\n${GREEN}Goodbye!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${RESET}"
                ;;
        esac
    done
}

# ==============================================================================
# Run
# ==============================================================================

if [[ "${1:-}" == "--all" ]]; then
    test_bracketed_paste
    test_window_resize
    test_colored_prompts
    test_job_specs
    test_terminal_title
    test_utf8_wide_chars
else
    main_menu
fi
