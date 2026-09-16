#ifndef WASMOON_WINDOWS_INPUT_H
#define WASMOON_WINDOWS_INPUT_H
#include "windows_io.h"
#ifdef _WIN32
typedef struct {
    SOCKET reader, writer;
    SRWLOCK lock;
    int signalled;
} wasmoon_notification;
int wasmoon_notification_init(wasmoon_notification *notification);
void wasmoon_notification_signal(wasmoon_notification *notification);
void wasmoon_notification_clear(wasmoon_notification *notification);
void wasmoon_notification_close(wasmoon_notification *notification);
typedef struct wasmoon_input wasmoon_input;
wasmoon_input *wasmoon_input_create(HANDLE handle);
void wasmoon_input_destroy(wasmoon_input *input);
int wasmoon_input_read(wasmoon_input *input, void *buffer, int count, int nonblocking);
int wasmoon_input_ready(wasmoon_input *input);
int64_t wasmoon_input_available(wasmoon_input *input);
SOCKET wasmoon_input_notification(wasmoon_input *input);
#endif
#endif
