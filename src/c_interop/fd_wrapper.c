#include <fcntl.h>
#include <unistd.h>

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
