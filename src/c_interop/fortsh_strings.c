/**
 * fortsh_strings.c - Implementation of C string operations for Fortran interop
 *
 * This library provides string buffer operations that work around flang-new
 * ARM64 bugs related to substring operations on strings >128 bytes.
 */

#include "fortsh_strings.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Internal buffer structure */
struct fortsh_buffer {
    char* data;           /* Actual string data (null-terminated) */
    size_t length;        /* Current length of string */
    size_t capacity;      /* Maximum capacity (excluding null terminator) */
};

/* ============================================================================
 * Buffer Management
 * ============================================================================ */

fortsh_buffer_t* fortsh_buffer_create(size_t capacity) {
    if (capacity == 0 || capacity > 1024*1024) {  /* Sanity check: max 1MB */
        return NULL;
    }

    fortsh_buffer_t* buf = (fortsh_buffer_t*)malloc(sizeof(fortsh_buffer_t));
    if (!buf) {
        return NULL;
    }

    /* Allocate capacity + 1 for null terminator */
    buf->data = (char*)calloc(capacity + 1, sizeof(char));
    if (!buf->data) {
        free(buf);
        return NULL;
    }

    buf->length = 0;
    buf->capacity = capacity;
    buf->data[0] = '\0';

    return buf;
}

void fortsh_buffer_destroy(fortsh_buffer_t* buf) {
    if (buf) {
        if (buf->data) {
            free(buf->data);
        }
        free(buf);
    }
}

void fortsh_buffer_clear(fortsh_buffer_t* buf) {
    if (buf && buf->data) {
        buf->data[0] = '\0';
        buf->length = 0;
    }
}

size_t fortsh_buffer_length(const fortsh_buffer_t* buf) {
    return buf ? buf->length : 0;
}

size_t fortsh_buffer_capacity(const fortsh_buffer_t* buf) {
    return buf ? buf->capacity : 0;
}

/* ============================================================================
 * String Operations
 * ============================================================================ */

int fortsh_buffer_set(fortsh_buffer_t* buf, const char* str) {
    if (!buf || !buf->data || !str) {
        return -1;
    }

    size_t len = strlen(str);
    if (len > buf->capacity) {
        return -1;  /* Overflow */
    }

    strcpy(buf->data, str);
    buf->length = len;
    return 0;
}

int fortsh_buffer_copy(fortsh_buffer_t* dest, const fortsh_buffer_t* src) {
    if (!dest || !src || !dest->data || !src->data) {
        return -1;
    }

    if (src->length > dest->capacity) {
        return -1;  /* Overflow */
    }

    memcpy(dest->data, src->data, src->length);
    dest->data[src->length] = '\0';
    dest->length = src->length;
    return 0;
}

int fortsh_buffer_substring(fortsh_buffer_t* dest, const fortsh_buffer_t* src,
                            size_t start, size_t end) {
    if (!dest || !src || !dest->data || !src->data) {
        return -1;
    }

    /* Validate indices */
    if (start > end || end >= src->length) {
        return -1;
    }

    size_t sub_len = end - start + 1;
    if (sub_len > dest->capacity) {
        return -1;  /* Overflow */
    }

    memcpy(dest->data, src->data + start, sub_len);
    dest->data[sub_len] = '\0';
    dest->length = sub_len;
    return 0;
}

char fortsh_buffer_get_char(const fortsh_buffer_t* buf, size_t pos) {
    if (!buf || !buf->data || pos >= buf->length) {
        return '\0';
    }
    return buf->data[pos];
}

int fortsh_buffer_set_char(fortsh_buffer_t* buf, size_t pos, char ch) {
    if (!buf || !buf->data || pos >= buf->capacity) {
        return -1;
    }

    buf->data[pos] = ch;

    /* Update length if we extended the string */
    if (pos >= buf->length) {
        buf->length = pos + 1;
        buf->data[buf->length] = '\0';
    }

    return 0;
}

/* ============================================================================
 * Buffer Manipulation
 * ============================================================================ */

int fortsh_buffer_insert(fortsh_buffer_t* buf, size_t pos, const char* str) {
    if (!buf || !buf->data || !str) {
        return -1;
    }

    size_t str_len = strlen(str);
    size_t new_len = buf->length + str_len;

    /* Check for overflow */
    if (new_len > buf->capacity || pos > buf->length) {
        return -1;
    }

    /* Shift existing content right to make room */
    if (pos < buf->length) {
        memmove(buf->data + pos + str_len, buf->data + pos, buf->length - pos);
    }

    /* Insert new string */
    memcpy(buf->data + pos, str, str_len);
    buf->length = new_len;
    buf->data[buf->length] = '\0';

    return 0;
}

int fortsh_buffer_delete(fortsh_buffer_t* buf, size_t start, size_t count) {
    if (!buf || !buf->data) {
        return -1;
    }

    /* Validate bounds */
    if (start >= buf->length || count == 0) {
        return 0;  /* Nothing to delete */
    }

    /* Adjust count if it would go past end */
    if (start + count > buf->length) {
        count = buf->length - start;
    }

    /* Shift content left */
    memmove(buf->data + start, buf->data + start + count,
            buf->length - start - count);

    buf->length -= count;
    buf->data[buf->length] = '\0';

    return 0;
}

int fortsh_buffer_append(fortsh_buffer_t* buf, const char* str) {
    if (!buf || !buf->data || !str) {
        return -1;
    }

    size_t str_len = strlen(str);
    size_t new_len = buf->length + str_len;

    if (new_len > buf->capacity) {
        return -1;  /* Overflow */
    }

    strcpy(buf->data + buf->length, str);
    buf->length = new_len;

    return 0;
}

int fortsh_buffer_grow(fortsh_buffer_t* buf, size_t new_capacity) {
    if (!buf || !buf->data) return -1;
    if (new_capacity <= buf->capacity) return 0;  /* already big enough */
    if (new_capacity > 16*1024*1024) return -1;   /* 16MB sanity cap */

    char* new_data = (char*)realloc(buf->data, new_capacity + 1);
    if (!new_data) return -1;

    buf->data = new_data;
    buf->capacity = new_capacity;
    return 0;
}

int fortsh_buffer_append_chars(fortsh_buffer_t* buf, const char* str, size_t len) {
    if (!buf || !buf->data || !str || len == 0) return (buf && len == 0) ? 0 : -1;

    size_t new_len = buf->length + len;
    if (new_len > buf->capacity) {
        /* Double or add 256, whichever is larger */
        size_t grow_to = buf->capacity * 2;
        if (grow_to < new_len + 256) grow_to = new_len + 256;
        if (fortsh_buffer_grow(buf, grow_to) != 0) return -1;
    }

    memcpy(buf->data + buf->length, str, len);
    buf->length = new_len;
    buf->data[new_len] = '\0';
    return 0;
}

int fortsh_buffer_append_char(fortsh_buffer_t* buf, char ch) {
    return fortsh_buffer_append_chars(buf, &ch, 1);
}

void fortsh_buffer_trim(fortsh_buffer_t* buf) {
    if (!buf || !buf->data || buf->length == 0) {
        return;
    }

    /* Trim trailing whitespace */
    while (buf->length > 0 && isspace((unsigned char)buf->data[buf->length - 1])) {
        buf->length--;
    }
    buf->data[buf->length] = '\0';
}

/* ============================================================================
 * Fortran Interop Helpers
 * ============================================================================ */

size_t fortsh_buffer_to_fortran(const fortsh_buffer_t* buf, char* fortran_str,
                                 size_t fortran_len) {
    if (!buf || !buf->data || !fortran_str || fortran_len == 0) {
        return 0;
    }

    size_t copy_len = (buf->length < fortran_len) ? buf->length : fortran_len;

    /* Copy data */
    memcpy(fortran_str, buf->data, copy_len);

    /* Pad with spaces (Fortran convention) */
    if (copy_len < fortran_len) {
        memset(fortran_str + copy_len, ' ', fortran_len - copy_len);
    }

    return copy_len;
}

int fortsh_buffer_from_fortran(fortsh_buffer_t* buf, const char* fortran_str,
                                size_t fortran_len) {
    if (!buf || !buf->data || !fortran_str) {
        return -1;
    }

    /* Find actual length by trimming trailing spaces */
    size_t actual_len = fortran_len;
    while (actual_len > 0 && (fortran_str[actual_len - 1] == ' ' ||
                              fortran_str[actual_len - 1] == '\0')) {
        actual_len--;
    }

    if (actual_len > buf->capacity) {
        return -1;  /* Overflow */
    }

    memcpy(buf->data, fortran_str, actual_len);
    buf->data[actual_len] = '\0';
    buf->length = actual_len;

    return 0;
}

const char* fortsh_buffer_c_str(const fortsh_buffer_t* buf) {
    return (buf && buf->data) ? buf->data : "";
}

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

int fortsh_buffer_find(const fortsh_buffer_t* buf, const char* pattern) {
    if (!buf || !buf->data || !pattern) {
        return -1;
    }

    const char* pos = strstr(buf->data, pattern);
    if (!pos) {
        return -1;  /* Not found */
    }

    return (int)(pos - buf->data);  /* Return 0-based index */
}

int fortsh_buffer_compare(const fortsh_buffer_t* buf, const char* str) {
    if (!buf || !buf->data || !str) {
        return -1;
    }

    return strcmp(buf->data, str);
}

/* ============================================================================
 * String Operations (non-buffer, direct C string functions)
 * ============================================================================ */

int fortsh_pattern_replace(const char* input, int input_len,
                           const char* pattern, int pat_len,
                           const char* replacement, int repl_len,
                           int replace_all,
                           char* output, int output_cap) {
    if (!input || !pattern || !replacement || !output || pat_len <= 0 || output_cap <= 0) {
        if (output && output_cap > 0) output[0] = '\0';
        return 0;
    }

    int out_pos = 0;
    int i = 0;

    while (i < input_len && out_pos < output_cap - 1) {
        /* Check if pattern matches at position i */
        if (i + pat_len <= input_len && memcmp(input + i, pattern, pat_len) == 0) {
            /* Copy replacement */
            int copy_len = repl_len;
            if (out_pos + copy_len > output_cap - 1) {
                copy_len = output_cap - 1 - out_pos;
            }
            if (copy_len > 0) {
                memcpy(output + out_pos, replacement, copy_len);
                out_pos += copy_len;
            }
            i += pat_len;

            if (!replace_all) {
                /* Copy rest of input */
                int rest = input_len - i;
                if (out_pos + rest > output_cap - 1) {
                    rest = output_cap - 1 - out_pos;
                }
                if (rest > 0) {
                    memcpy(output + out_pos, input + i, rest);
                    out_pos += rest;
                }
                break;
            }
        } else {
            output[out_pos++] = input[i++];
        }
    }

    output[out_pos] = '\0';
    return out_pos;
}

/*
 * Full pattern replace with C-managed memory.
 * Fortran passes raw strings (not null-terminated), C handles all allocation.
 * Returns result via caller-provided pointer to a C-allocated buffer.
 * Caller must call fortsh_free_string() on the result.
 */
int fortsh_pattern_replace_alloc(const char* input, int input_len,
                                 const char* pattern, int pat_len,
                                 const char* replacement, int repl_len,
                                 int replace_all,
                                 char** result_out) {
    *result_out = NULL;

    if (!input || !pattern || !replacement || pat_len <= 0) {
        /* No pattern: return copy of input */
        *result_out = (char*)malloc(input_len + 1);
        if (!*result_out) return 0;
        memcpy(*result_out, input, input_len);
        (*result_out)[input_len] = '\0';
        return input_len;
    }

    /* Estimate output size */
    int out_cap;
    if (repl_len > pat_len) {
        out_cap = input_len + (input_len / pat_len + 1) * (repl_len - pat_len) + 2;
    } else {
        out_cap = input_len + 2;
    }

    char* output = (char*)malloc(out_cap);
    if (!output) return -1;

    int result_len = fortsh_pattern_replace(input, input_len, pattern, pat_len,
                                            replacement, repl_len, replace_all,
                                            output, out_cap);
    *result_out = output;
    return result_len;
}

void fortsh_free_string(char* ptr) {
    if (ptr) free(ptr);
}
