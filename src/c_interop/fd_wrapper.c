#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pwd.h>

// Look up a user's home directory via getpwnam (for ~user expansion).
// Returns the pw_dir string, or NULL if the user does not exist.
const char *fortsh_user_home(const char *name) {
    struct passwd *pw = getpwnam(name);
    return pw ? pw->pw_dir : (const char *)0;
}

// Enumerate passwd usernames that start with `prefix` (for ~user completion).
// Writes them NUL-separated into `out` (followed by a final empty string, i.e.
// double-NUL), capped by `outlen` bytes and `max_users` entries. Returns the
// count written. NUL-separation avoids marshaling a 2D char array to Fortran.
int fortsh_match_users(const char *prefix, char *out, int outlen, int max_users) {
    int n = 0, pos = 0;
    size_t plen = prefix ? strlen(prefix) : 0;
    struct passwd *pw;
    if (!out || outlen <= 0) return 0;
    out[0] = '\0';
    setpwent();
    while (n < max_users && (pw = getpwent()) != (struct passwd *)0) {
        const char *nm = pw->pw_name;
        size_t L;
        if (!nm) continue;
        if (plen && strncmp(nm, prefix, plen) != 0) continue;
        L = strlen(nm);
        if (pos + (int)L + 2 > outlen) break;  // name + its NUL + final NUL
        memcpy(out + pos, nm, L);
        pos += (int)L;
        out[pos++] = '\0';
        n++;
    }
    endpwent();
    if (pos < outlen) out[pos] = '\0';  // double-NUL terminate the list
    return n;
}

// Securely create a temp file in $TMPDIR (or /tmp): builds "<dir>/<prefix>XXXXXX"
// and mkstemp()s it (O_CREAT|O_EXCL, mode 0600, never follows a symlink, no
// predictable name / race). Writes the chosen path to `out` and returns 0 on
// success, -1 on failure. The unpredictable name makes a later open-by-name safe.
int fortsh_make_temp(const char *prefix, char *out, int outlen) {
    char tmpl[1024];
    const char *dir = getenv("TMPDIR");
    if (!dir || !*dir) dir = "/tmp";
    if (snprintf(tmpl, sizeof(tmpl), "%s/%sXXXXXX", dir, prefix) >= (int)sizeof(tmpl))
        return -1;
    int fd = mkstemp(tmpl);
    if (fd < 0) return -1;
    close(fd);
    if (outlen <= 0) return -1;
    strncpy(out, tmpl, (size_t)(outlen - 1));
    out[outlen - 1] = '\0';
    return 0;
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

// Wrapper for fcntl() with integer arg — Fortran's bind(C) can't call
// variadic C functions correctly on all ABIs (macOS ARM64 in particular).
int fortsh_fcntl(int fd, int cmd, int arg) {
    return fcntl(fd, cmd, arg);
}

// Install SIGWINCH with SA_RESTART cleared so read() returns EINTR
// on terminal resize, allowing the readline loop to handle it immediately.
#include <signal.h>
static void (*g_winch_handler)(void) = NULL;
static void winch_trampoline(int sig) { (void)sig; if (g_winch_handler) g_winch_handler(); }
void fortsh_install_winch_norestart(void (*handler)(void)) {
    g_winch_handler = handler;
    struct sigaction sa;
    sa.sa_handler = winch_trampoline;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;  // no SA_RESTART
    sigaction(SIGWINCH, &sa, NULL);
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
