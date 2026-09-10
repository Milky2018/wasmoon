#ifndef WASMOON_NATIVE_FILETYPE_H
#define WASMOON_NATIVE_FILETYPE_H
#include <stdint.h>
#include <sys/stat.h>

// Native file-type tokens shared with the MoonBit side. Values 0-7 match
// WASI Preview 1 filetype; 8 extends the internal protocol for FIFO, which is
// represented explicitly by the Component Model.
static uint8_t wasmoon_wasi_filetype_from_mode(mode_t mode) {
  if (S_ISDIR(mode)) return 3;
  if (S_ISREG(mode)) return 4;
  if (S_ISLNK(mode)) return 7;
  if (S_ISCHR(mode)) return 2;
  if (S_ISBLK(mode)) return 1;
#ifdef S_ISSOCK
  if (S_ISSOCK(mode)) return 6;
#endif
#ifdef S_ISFIFO
  if (S_ISFIFO(mode)) return 8;
#endif
  return 0;
}

#endif
