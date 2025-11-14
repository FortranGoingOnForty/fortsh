#include <sys/ioctl.h>
#include <unistd.h>
#include <stdio.h>

// C wrapper for getting terminal size
// Returns 0 on success, -1 on failure
int get_term_size_c(int *rows, int *cols) {
    struct winsize ws;
    int ret;

    // Try stdin first (most reliable for interactive programs)
    ret = ioctl(STDIN_FILENO, TIOCGWINSZ, &ws);

    if (ret == 0 && ws.ws_row > 0 && ws.ws_col > 0) {
        *rows = ws.ws_row;
        *cols = ws.ws_col;
        return 0;
    }

    // Fallback
    *rows = 24;
    *cols = 80;
    return -1;
}
