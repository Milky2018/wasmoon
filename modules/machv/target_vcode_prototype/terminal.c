#include <moonbit.h>
#include <stdio.h>

MOONBIT_FFI_EXPORT int32_t target_vcode_prototype_read_key(void) {
  for (;;) {
    int key = getchar();
    if (key == EOF) {
      return -1;
    }
    if (key != '\n' && key != '\r' && key != ' ' && key != '\t') {
      return (int32_t)key;
    }
  }
}
