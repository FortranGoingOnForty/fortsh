#!/bin/bash
# Verification script for macOS keyboard binding fix

echo "=========================================="
echo "fortsh macOS Keyboard Binding Verification"
echo "=========================================="
echo ""
echo "This script will help you verify that the fix works."
echo ""
echo "Testing Phase 1: Structure Size Verification"
echo "---------------------------------------------"

cat > /tmp/test_termios_size.c << 'EOF'
#include <termios.h>
#include <stdio.h>
#include <unistd.h>

int main() {
    struct termios t;
    int ret = tcgetattr(STDIN_FILENO, &t);

    printf("tcgetattr returned: %d (0 = success)\n", ret);
    printf("sizeof(struct termios) = %zu bytes\n", sizeof(struct termios));
    printf("sizeof(tcflag_t) = %zu bytes\n", sizeof(tcflag_t));
    printf("Expected: 72 bytes for termios, 8 bytes for tcflag_t\n");

    if (sizeof(struct termios) == 72 && sizeof(tcflag_t) == 8) {
        printf("✓ Structure sizes match!\n");
        return 0;
    } else {
        printf("✗ Structure size mismatch!\n");
        return 1;
    }
}
EOF

gcc /tmp/test_termios_size.c -o /tmp/test_termios_size
if /tmp/test_termios_size; then
    echo "✓ C structure verification passed"
else
    echo "✗ C structure verification failed"
    exit 1
fi

echo ""
echo "Testing Phase 2: Interactive Keyboard Test"
echo "-------------------------------------------"
echo "Please run fortsh and test these keyboard shortcuts:"
echo ""
echo "  1. Ctrl-L          → Should clear the screen"
echo "  2. Ctrl-C          → Should cancel line (no ^C visible)"
echo "  3. Tab (twice)     → Should show command completions"
echo "  4. Ctrl-R          → Should enter reverse-i-search"
echo "  5. Up/Down arrows  → Should navigate command history"
echo "  6. Ctrl-A          → Should move to beginning of line"
echo "  7. Ctrl-E          → Should move to end of line"
echo "  8. Ctrl-K          → Should kill to end of line"
echo "  9. Ctrl-W          → Should kill previous word"
echo " 10. Ctrl-Y          → Should yank (paste) killed text"
echo ""
echo "Press Enter to launch fortsh for testing..."
read

./bin/fortsh

echo ""
echo "Did all keyboard bindings work correctly? (y/n)"
read answer

if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    echo "✓ Verification complete - fix successful!"
    exit 0
else
    echo "✗ Some keyboard bindings still don't work"
    echo "  Please report which ones failed."
    exit 1
fi
