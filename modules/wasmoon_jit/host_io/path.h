#ifndef WASMOON_HOST_PATH_H
#define WASMOON_HOST_PATH_H
#ifndef _WIN32
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
int wasmoon_wasi_symlinkat_portable(const char *target, int dirfd, const char *linkpath);
ssize_t wasmoon_wasi_readlinkat_portable(int dirfd, const char *path, char *buf, size_t size);
#endif
#endif
