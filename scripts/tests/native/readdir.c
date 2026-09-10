#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "moonbit.h"

// Use exact allocations so ASan can detect any write past the serialized size.
moonbit_bytes_t moonbit_make_bytes(int32_t size, int value) {
    assert(size >= 0);
    unsigned char *bytes = malloc((size_t)size);
    assert(bytes);
    memset(bytes, value, (size_t)size);
    return bytes;
}
extern moonbit_bytes_t wasmoon_wasi_readdir_fd(int fd);

int main(int argc, char **argv) {
    assert(argc == 2);
    int dir = open(argv[1], O_RDONLY | O_DIRECTORY);
    assert(dir >= 0);
    unsigned char *empty = wasmoon_wasi_readdir_fd(dir);
    assert(empty && empty[0] == 0);
    free(empty);
    int file = openat(dir, "file", O_CREAT | O_WRONLY, 0600);
    assert(file >= 0);
    close(file);
    for (int i = 0; i < 100; i++) {
        unsigned char *entries = wasmoon_wasi_readdir_fd(dir);
        assert(entries && entries[0] == 1 && entries[1] == 0);
        assert(entries[4] == 4 && entries[5] == 4);
        assert(memcmp(entries + 9, "file", 4) == 0);
        free(entries);
    }
    assert(unlinkat(dir, "file", 0) == 0);
    close(dir);
}
