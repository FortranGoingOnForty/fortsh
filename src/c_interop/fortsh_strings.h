/**
 * fortsh_strings.h - C string operations for Fortran interop
 *
 * Purpose: Bypass flang-new ARM64 heap corruption bugs on strings >128 bytes
 * by implementing critical string operations in C.
 *
 * The flang-new compiler on macOS ARM64 has a bug where substring operations
 * and assignments on strings >128 bytes cause heap corruption. By implementing
 * these operations in C, we bypass the Fortran runtime entirely.
 */

#ifndef FORTSH_STRINGS_H
#define FORTSH_STRINGS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Command buffer handle - opaque to Fortran
 * Internally manages a dynamically allocated string buffer
 */
typedef struct fortsh_buffer fortsh_buffer_t;

/* ============================================================================
 * Buffer Management
 * ============================================================================ */

/**
 * Create a new string buffer with specified capacity
 * @param capacity Maximum size of buffer (e.g., 1024 for command line)
 * @return Handle to buffer, or NULL on failure
 */
fortsh_buffer_t* fortsh_buffer_create(size_t capacity);

/**
 * Destroy a buffer and free its memory
 * @param buf Buffer handle
 */
void fortsh_buffer_destroy(fortsh_buffer_t* buf);

/**
 * Clear buffer contents (set to empty string)
 * @param buf Buffer handle
 */
void fortsh_buffer_clear(fortsh_buffer_t* buf);

/**
 * Get current length of string in buffer (like len_trim)
 * @param buf Buffer handle
 * @return Length of string (not including trailing spaces)
 */
size_t fortsh_buffer_length(const fortsh_buffer_t* buf);

/**
 * Get capacity of buffer
 * @param buf Buffer handle
 * @return Maximum capacity
 */
size_t fortsh_buffer_capacity(const fortsh_buffer_t* buf);

/* ============================================================================
 * String Operations (safe for >128 bytes)
 * ============================================================================ */

/**
 * Copy C string into buffer (like buffer = "string")
 * @param buf Buffer handle
 * @param str C string to copy (null-terminated)
 * @return 0 on success, -1 on failure (overflow)
 */
int fortsh_buffer_set(fortsh_buffer_t* buf, const char* str);

/**
 * Copy from another buffer (like buffer1 = buffer2)
 * @param dest Destination buffer
 * @param src Source buffer
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_copy(fortsh_buffer_t* dest, const fortsh_buffer_t* src);

/**
 * Extract substring into destination buffer (like dest = src(start:end))
 * @param dest Destination buffer
 * @param src Source buffer
 * @param start Start index (0-based)
 * @param end End index (0-based, inclusive)
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_substring(fortsh_buffer_t* dest, const fortsh_buffer_t* src,
                            size_t start, size_t end);

/**
 * Get character at position (like ch = buffer(i:i))
 * @param buf Buffer handle
 * @param pos Position (0-based)
 * @return Character, or '\0' if out of bounds
 */
char fortsh_buffer_get_char(const fortsh_buffer_t* buf, size_t pos);

/**
 * Set character at position (like buffer(i:i) = 'x')
 * @param buf Buffer handle
 * @param pos Position (0-based)
 * @param ch Character to set
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_set_char(fortsh_buffer_t* buf, size_t pos, char ch);

/* ============================================================================
 * Buffer Manipulation
 * ============================================================================ */

/**
 * Insert string at position
 * @param buf Buffer handle
 * @param pos Position to insert at (0-based)
 * @param str String to insert
 * @return 0 on success, -1 on failure (overflow)
 */
int fortsh_buffer_insert(fortsh_buffer_t* buf, size_t pos, const char* str);

/**
 * Delete characters from buffer
 * @param buf Buffer handle
 * @param start Start position (0-based)
 * @param count Number of characters to delete
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_delete(fortsh_buffer_t* buf, size_t start, size_t count);

/**
 * Append null-terminated string to buffer
 * @param buf Buffer handle
 * @param str String to append
 * @return 0 on success, -1 on failure (overflow)
 */
int fortsh_buffer_append(fortsh_buffer_t* buf, const char* str);

/**
 * Append N bytes from a Fortran string (not null-terminated). Auto-grows.
 * @param buf Buffer handle
 * @param str Fortran character data
 * @param len Number of bytes to append
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_append_chars(fortsh_buffer_t* buf, const char* str, size_t len);

/**
 * Append a single character. Auto-grows.
 * @param buf Buffer handle
 * @param ch Character to append
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_append_char(fortsh_buffer_t* buf, char ch);

/**
 * Grow buffer capacity via realloc, preserving contents.
 * @param buf Buffer handle
 * @param new_capacity New capacity (must be >= current length)
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_grow(fortsh_buffer_t* buf, size_t new_capacity);

/**
 * Trim trailing whitespace (like trim(buffer))
 * Modifies buffer in place
 * @param buf Buffer handle
 */
void fortsh_buffer_trim(fortsh_buffer_t* buf);

/* ============================================================================
 * Fortran Interop Helpers
 * ============================================================================ */

/**
 * Copy buffer contents to Fortran character array
 * @param buf Buffer handle
 * @param fortran_str Fortran character array (NOT null-terminated)
 * @param fortran_len Length of Fortran array
 * @return Number of characters copied
 */
size_t fortsh_buffer_to_fortran(const fortsh_buffer_t* buf, char* fortran_str,
                                 size_t fortran_len);

/**
 * Set buffer from Fortran character array
 * @param buf Buffer handle
 * @param fortran_str Fortran character array (NOT null-terminated)
 * @param fortran_len Length of Fortran string to use
 * @return 0 on success, -1 on failure
 */
int fortsh_buffer_from_fortran(fortsh_buffer_t* buf, const char* fortran_str,
                                size_t fortran_len);

/**
 * Get pointer to internal C string (null-terminated)
 * WARNING: Pointer is only valid until next buffer operation!
 * @param buf Buffer handle
 * @return Pointer to C string
 */
const char* fortsh_buffer_c_str(const fortsh_buffer_t* buf);

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

/**
 * Find substring in buffer (like index(buffer, pattern))
 * @param buf Buffer handle
 * @param pattern Pattern to search for
 * @return Position of first match (0-based), or -1 if not found
 */
int fortsh_buffer_find(const fortsh_buffer_t* buf, const char* pattern);

/**
 * Compare buffer contents with C string
 * @param buf Buffer handle
 * @param str String to compare
 * @return 0 if equal, <0 if buf < str, >0 if buf > str
 */
int fortsh_buffer_compare(const fortsh_buffer_t* buf, const char* str);

/* ============================================================================
 * String Operations (non-buffer, direct C string functions)
 * ============================================================================ */

/**
 * Pattern replace on raw C strings — bypasses Fortran runtime entirely.
 * Replaces occurrences of pattern in input, writing result to output.
 * @param input       Input string (null-terminated)
 * @param input_len   Length of input string
 * @param pattern     Pattern to find (null-terminated)
 * @param pat_len     Length of pattern
 * @param replacement Replacement string (null-terminated)
 * @param repl_len    Length of replacement
 * @param replace_all 1 = replace all occurrences, 0 = first only
 * @param output      Output buffer (caller-allocated, must be large enough)
 * @param output_cap  Capacity of output buffer
 * @return            Length of result string, or -1 on error
 */
int fortsh_pattern_replace(const char* input, int input_len,
                           const char* pattern, int pat_len,
                           const char* replacement, int repl_len,
                           int replace_all,
                           char* output, int output_cap);

/**
 * Pattern replace with C-managed allocation.
 * All memory is malloc'd in C — no Fortran allocatable involved.
 * @param result_out  Pointer to receive C-allocated result string
 * @return            Length of result, or -1 on error. Caller must free with fortsh_free_string().
 */
int fortsh_pattern_replace_alloc(const char* input, int input_len,
                                 const char* pattern, int pat_len,
                                 const char* replacement, int repl_len,
                                 int replace_all,
                                 char** result_out);

/**
 * Free a string allocated by fortsh_pattern_replace_alloc.
 */
void fortsh_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* FORTSH_STRINGS_H */
