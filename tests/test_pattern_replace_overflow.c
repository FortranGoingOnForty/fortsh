/*
 * MEM-6 regression: fortsh_pattern_replace_alloc must not overflow its output
 * size estimate. With a large input, a single-character pattern, and a multi-KB
 * replacement, the old 32-bit `int out_cap` computation overflowed (UBSAN flags
 * the signed overflow) and mallocd a negative/undersized buffer. The estimate
 * now runs in size_t and refuses a size it cannot represent (returns -1).
 *
 * Build+run: make test-pattern-overflow
 * Under UBSAN: make test-pattern-overflow CFLAGS="-g -O0 -fsanitize=undefined"
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fortsh_strings.h"

int main(void) {
    int failures = 0;

    /* Overflow dimensions: ~0.5 MB input, single-char pattern, 5000-byte
     * replacement. Estimate ~ 500001 * 4999 ~= 2.5e9, past INT_MAX. */
    int input_len = 500000;
    char *input = (char *)malloc((size_t)input_len);
    if (!input) { fprintf(stderr, "setup: input alloc failed\n"); return 2; }
    memset(input, 'a', (size_t)input_len);

    char repl[5001];
    memset(repl, 'b', 5000);
    repl[5000] = '\0';

    char *out = (char *)0xdead;   /* must be reset to NULL on refusal */
    int rc = fortsh_pattern_replace_alloc(input, input_len, "a", 1,
                                          repl, 5000, 1, &out);
    if (rc != -1) {
        fprintf(stderr, "FAIL: overflow-sized replace returned %d, expected -1\n", rc);
        failures++;
        if (out && out != (char *)0xdead) fortsh_free_string(out);
    } else if (out != NULL) {
        fprintf(stderr, "FAIL: result_out not NULL after refusal\n");
        failures++;
    } else {
        printf("PASS: overflow-sized replace refused cleanly (rc=-1)\n");
    }
    free(input);

    /* A normal, representable replace must still expand fully, not truncate. */
    out = NULL;
    rc = fortsh_pattern_replace_alloc("aXaXa", 5, "X", 1, "YY", 2, 1, &out);
    if (rc != 7 || !out || strncmp(out, "aYYaYYa", 7) != 0) {
        fprintf(stderr, "FAIL: normal replace wrong: rc=%d out=%s\n",
                rc, out ? out : "(null)");
        failures++;
    } else {
        printf("PASS: normal replace intact (aXaXa -> aYYaYYa)\n");
    }
    if (out) fortsh_free_string(out);

    if (failures == 0) {
        printf("=== ALL PASS ===\n");
        return 0;
    }
    printf("=== %d FAILURE(S) ===\n", failures);
    return 1;
}
