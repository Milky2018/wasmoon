#ifndef WASMOON_WASI_PATH_PORTABILITY_H
#define WASMOON_WASI_PATH_PORTABILITY_H

#ifndef _WIN32
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Preserve Preview 1 path semantics across POSIX kernels in both engines.
static inline int wasmoon_wasi_symlinkat_portable(
    const char *target, int dirfd, const char *linkpath) {
    int result = symlinkat(target, dirfd, linkpath);
    if (result < 0 && errno == EEXIST) {
        size_t length = strlen(linkpath);
        if (length > 0 && linkpath[length - 1] == '/') {
            // Linux reports EEXIST for a regular file followed by a slash.
            // An existing directory must retain EEXIST.
            struct stat st;
            int saved_errno = errno;
            if (fstatat(dirfd, linkpath, &st, 0) < 0 && errno == ENOTDIR) {
                saved_errno = ENOTDIR;
            }
            errno = saved_errno;
        }
    }
    return result;
}

static inline ssize_t wasmoon_wasi_readlinkat_portable(
    int dirfd, const char *path, char *buf, size_t size) {
    if (size == 0) {
        // Validate the link even when there are no guest bytes to write.
        char scratch;
        return readlinkat(dirfd, path, &scratch, 1) < 0 ? -1 : 0;
    }
    return readlinkat(dirfd, path, buf, size);
}
#endif
#endif
