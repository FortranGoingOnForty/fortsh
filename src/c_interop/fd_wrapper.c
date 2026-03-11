#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

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

// Access environ array by index
// Returns NULL when idx is beyond the end
extern char **environ;
char *get_environ_ptr(int idx) {
    return environ[idx];
}
