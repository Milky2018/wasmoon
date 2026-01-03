// Native FFI for cli/tools
#include <stdlib.h>

// Exit wrapper with correct void return type
// (moonbitlang/x/sys declares exit as returning int32, which causes compiler warnings)
void wasmoon_exit(int code) {
  exit(code);
}
