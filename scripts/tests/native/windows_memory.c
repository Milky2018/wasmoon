#include "windows_fs.h"
#include <assert.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  assert(argc == 2);
  int root = wasmoon_windows_open(argv[1], WASMOON_O_DIRECTORY, 0);
  assert(root >= 0);
  for (int i = 0; i < 128; i++) {
    int file = wasmoon_windows_openat(root, "buffer", _O_RDWR | _O_CREAT | _O_TRUNC, 0600);
    assert(file >= 0);
    int copy = wasmoon_windows_dup(file);
    assert(copy >= 0);
    assert(wasmoon_windows_setfl(copy, _O_RDWR | _O_APPEND) == 0);
    assert(wasmoon_windows_write(file, "x\r\n\x1a", 4) == 4);
    assert(wasmoon_windows_setfl(file, _O_RDWR) == 0);
    assert(!(wasmoon_windows_getfl(copy) & _O_APPEND));
    char buffer[4];
    assert(wasmoon_windows_pread(copy, buffer, sizeof(buffer), 0) == 4);
    assert(!memcmp(buffer, "x\r\n\x1a", 4));
    assert(wasmoon_windows_pwrite(copy, "y", 1, 0) == 1);
    assert(_lseeki64(file, 0, SEEK_CUR) == 4);
    assert(wasmoon_windows_close(file) == 0);
    assert(wasmoon_windows_read(copy, buffer, sizeof(buffer)) == 0);
    assert(wasmoon_windows_close(copy) == 0);
  }
  assert(wasmoon_windows_symlinkat("buffer", root, "link") == 0);
  char byte = 0;
  assert(wasmoon_windows_readlinkat(root, "link", &byte, 1) == 1);
  assert(byte == 'b');
  assert(wasmoon_windows_readlinkat(root, "link", &byte, 0) == 0);
  assert(wasmoon_windows_linkat(root, "buffer", root, "hard-link", 0) == 0);
  int size;
  unsigned char *entries = wasmoon_windows_directory_entries(root, &size);
  assert(entries && size >= 4);
  free(entries);
  assert(wasmoon_windows_unlinkat(root, "link", 0) == 0);
  assert(wasmoon_windows_unlinkat(root, "hard-link", 0) == 0);
  assert(wasmoon_windows_unlinkat(root, "buffer", 0) == 0);
  assert(wasmoon_windows_close(root) == 0);
  return 0;
}
