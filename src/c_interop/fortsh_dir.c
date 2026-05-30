// Native directory enumeration for fortsh.
//
// Replaces shelling out to `ls` (and `ls | grep`) for completion and glob.
// A name-based API keeps the platform-specific `struct dirent` layout entirely
// on the C side — Fortran never needs to know it, exactly like fd_wrapper.c
// hides `struct stat`. Works on Linux, macOS, and FreeBSD.

#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string.h>

// Open a directory. Returns an opaque DIR* (as void*), or NULL on failure.
void *fortsh_opendir(const char *path) {
    return (void *)opendir(path);
}

// Read the next entry from an open directory.
//   name_buf / buf_len : caller buffer; the entry name is copied NUL-terminated
//                        (truncated if it would not fit).
//   is_dir             : set to 1 if the entry is a directory (symlinks to
//                        directories are followed), else 0.
// Returns 1 when an entry was produced, 0 at end of directory / on error.
int fortsh_readdir(void *dirp, char *name_buf, int buf_len, int *is_dir) {
    DIR *d = (DIR *)dirp;
    struct dirent *e;

    if (d == NULL || name_buf == NULL || buf_len <= 0) return 0;

    e = readdir(d);
    if (e == NULL) return 0;

    strncpy(name_buf, e->d_name, (size_t)(buf_len - 1));
    name_buf[buf_len - 1] = '\0';

    // Determine directory-ness. d_type is fast but not universally populated
    // (some filesystems report DT_UNKNOWN), and symlinks report DT_LNK — for
    // completion we want to follow links, so stat those via fstatat (relative
    // to the open dir fd, so no path reconstruction is needed).
    *is_dir = 0;
#ifdef DT_DIR
    if (e->d_type == DT_DIR) {
        *is_dir = 1;
    } else if (e->d_type == DT_LNK || e->d_type == DT_UNKNOWN) {
#endif
        struct stat st;
        if (fstatat(dirfd(d), e->d_name, &st, 0) == 0 && S_ISDIR(st.st_mode)) {
            *is_dir = 1;
        }
#ifdef DT_DIR
    }
#endif

    return 1;
}

void fortsh_closedir(void *dirp) {
    if (dirp != NULL) closedir((DIR *)dirp);
}
