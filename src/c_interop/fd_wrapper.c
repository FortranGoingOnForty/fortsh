#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pwd.h>

// Look up a user's home directory via getpwnam (for ~user expansion).
// Returns the pw_dir string, or NULL if the user does not exist.
const char *fortsh_user_home(const char *name) {
    struct passwd *pw = getpwnam(name);
    return pw ? pw->pw_dir : (const char *)0;
}

// macOS kernel bug workaround: set S_CTTYREF on the controlling terminal.
// On macOS, PTY slave output is discarded when the child process exits unless
// /dev/tty was opened (which sets S_CTTYREF). Without this, pexpect-based tests
// lose output from commands that fork short-lived child processes.
// See: https://github.com/pexpect/pexpect/issues/662
void fortsh_set_cttyref(void) {
#ifdef __APPLE__
    int fd = open("/dev/tty", O_WRONLY);
    if (fd >= 0) close(fd);
#endif
}

// Wrapper for open() that takes mode as a separate parameter
// This works around a bug in Fortran's C binding where mode_t is not passed correctly
int fortsh_open(const char *pathname, int flags, int mode) {
    return open(pathname, flags, (mode_t)mode);
}

int fortsh_close(int fd) {
    return close(fd);
}

int fortsh_dup(int fd) {
    return dup(fd);
}

int fortsh_dup2(int oldfd, int newfd) {
    return dup2(oldfd, newfd);
}

int fortsh_get_errno(void) {
    return errno;
}

const char *fortsh_strerror(int errnum) {
    return strerror(errnum);
}

// Portable file type checks — bypasses Fortran struct stat layout issues
// across architectures (x86_64 vs aarch64 have different struct stat layouts)
int fortsh_stat_mode(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (int)st.st_mode;
}

int fortsh_lstat_mode(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) return -1;
    return (int)st.st_mode;
}

long long fortsh_stat_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (long long)st.st_size;
}

int fortsh_stat_uid(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (int)st.st_uid;
}

long long fortsh_stat_mtime(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
#ifdef __APPLE__
    return (long long)st.st_mtimespec.tv_sec;
#else
    return (long long)st.st_mtim.tv_sec;
#endif
}

long long fortsh_stat_dev(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (long long)st.st_dev;
}

long long fortsh_stat_ino(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (long long)st.st_ino;
}

// Access environ array by index
// Returns NULL when idx is beyond the end
extern char **environ;
char *get_environ_ptr(int idx) {
    return environ[idx];
}
