#ifdef _WIN32
#include "windows_input.h"
#include <errno.h>
#include <process.h>
#include <stdlib.h>
#include <string.h>

// Socket notifications let input completions and reactor wakeups share WSAPoll
// with ordinary sockets without changing their blocking mode or event mask.
int wasmoon_notification_init(wasmoon_notification *n) {
    n->reader = n->writer = INVALID_SOCKET;
    InitializeSRWLock(&n->lock);
    n->signalled = 0;
    if (wasmoon_windows_winsock_init()) return -1;
    SOCKET listener = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
    if (listener == INVALID_SOCKET) return wasmoon_windows_socket_error(WSAGetLastError());
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int length = sizeof(address);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
        getsockname(listener, (struct sockaddr *)&address, &length) || listen(listener, 1)) goto failed;
    n->writer = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
    if (n->writer == INVALID_SOCKET || connect(n->writer, (struct sockaddr *)&address, sizeof(address))) goto failed;
    n->reader = accept(listener, NULL, NULL);
    if (n->reader == INVALID_SOCKET) goto failed;
    if (!SetHandleInformation((HANDLE)n->reader, HANDLE_FLAG_INHERIT, 0)) {
        DWORD error = GetLastError();
        closesocket(listener);
        wasmoon_notification_close(n);
        return wasmoon_windows_error(error);
    }
    u_long nonblocking = 1;
    int no_delay = 1;
    if (ioctlsocket(n->writer, FIONBIO, &nonblocking) ||
        setsockopt(n->writer, IPPROTO_TCP, TCP_NODELAY, (char *)&no_delay, sizeof(no_delay))) goto failed;
    closesocket(listener);
    return 0;
failed: {
    int error = WSAGetLastError();
    closesocket(listener);
    wasmoon_notification_close(n);
    return wasmoon_windows_socket_error(error);
}
}
void wasmoon_notification_signal(wasmoon_notification *n) {
    AcquireSRWLockExclusive(&n->lock);
    if (!n->signalled) {
        n->signalled = 1;
        // At most one byte is outstanding. A failed transport also wakes poll.
        if (send(n->writer, "x", 1, 0) != 1) shutdown(n->writer, SD_SEND);
    }
    ReleaseSRWLockExclusive(&n->lock);
}
void wasmoon_notification_clear(wasmoon_notification *n) {
    AcquireSRWLockExclusive(&n->lock);
    if (n->signalled) {
        char byte;
        recv(n->reader, &byte, 1, 0);
        n->signalled = 0;
    }
    ReleaseSRWLockExclusive(&n->lock);
}
void wasmoon_notification_close(wasmoon_notification *n) {
    if (n->reader != INVALID_SOCKET) closesocket(n->reader);
    if (n->writer != INVALID_SOCKET) closesocket(n->writer);
    n->reader = n->writer = INVALID_SOCKET;
}

struct wasmoon_input {
    HANDLE handle, worker;
    SRWLOCK lock;
    CONDITION_VARIABLE changed;
    wasmoon_notification notification;
    int requested, closing, eof;
    DWORD error;
    size_t offset, length;
    unsigned char buffer[4096];
};
static unsigned __stdcall read_input(void *argument) {
    wasmoon_input *input = argument;
    AcquireSRWLockExclusive(&input->lock);
    for (;;) {
        while (!input->closing && (!input->requested || input->length || input->eof || input->error))
            SleepConditionVariableSRW(&input->changed, &input->lock, INFINITE, 0);
        if (input->closing) break;
        input->requested = 0;
        ReleaseSRWLockExclusive(&input->lock);
        DWORD count = 0;
        BOOL ok = ReadFile(input->handle, input->buffer, sizeof(input->buffer), &count, NULL);
        DWORD error = ok ? ERROR_SUCCESS : GetLastError();
        AcquireSRWLockExclusive(&input->lock);
        input->offset = 0;
        input->length = count;
        input->eof = (ok && !count) || error == ERROR_BROKEN_PIPE || error == ERROR_HANDLE_EOF;
        input->error = input->eof ? ERROR_SUCCESS : error;
        wasmoon_notification_signal(&input->notification);
        WakeAllConditionVariable(&input->changed);
    }
    ReleaseSRWLockExclusive(&input->lock);
    return 0;
}
wasmoon_input *wasmoon_input_create(HANDLE handle) {
    wasmoon_input *input = calloc(1, sizeof(*input));
    if (!input) { errno = ENOMEM; return NULL; }
    InitializeSRWLock(&input->lock);
    InitializeConditionVariable(&input->changed);
    if (!DuplicateHandle(GetCurrentProcess(), handle, GetCurrentProcess(), &input->handle,
                         0, FALSE, DUPLICATE_SAME_ACCESS)) {
        DWORD error = GetLastError(); free(input); wasmoon_windows_error(error); return NULL;
    }
    if (wasmoon_notification_init(&input->notification)) {
        CloseHandle(input->handle); free(input); return NULL;
    }
    input->worker = (HANDLE)_beginthreadex(NULL, 0, read_input, input, 0, NULL);
    if (!input->worker) {
        wasmoon_notification_close(&input->notification);
        CloseHandle(input->handle); free(input); errno = ENOMEM; return NULL;
    }
    return input;
}
void wasmoon_input_destroy(wasmoon_input *input) {
    if (!input) return;
    AcquireSRWLockExclusive(&input->lock);
    input->closing = 1;
    WakeAllConditionVariable(&input->changed);
    ReleaseSRWLockExclusive(&input->lock);
    // Cancellation can race the worker between releasing its lock and entering
    // ReadFile. Retry only during teardown until the worker has acknowledged it.
    while (WaitForSingleObject(input->worker, 0) == WAIT_TIMEOUT) {
        CancelSynchronousIo(input->worker);
        WaitForSingleObject(input->worker, 1);
    }
    CloseHandle(input->worker);
    CloseHandle(input->handle);
    wasmoon_notification_close(&input->notification);
    free(input);
}
static void request_input(wasmoon_input *input) {
    if (!input->length && !input->eof && !input->error) {
        input->requested = 1;
        WakeAllConditionVariable(&input->changed);
    }
}
int wasmoon_input_ready(wasmoon_input *input) {
    AcquireSRWLockExclusive(&input->lock);
    request_input(input);
    int result = input->length ? 1 : input->eof ? 1 | 16 : input->error ? 8 : 0;
    ReleaseSRWLockExclusive(&input->lock);
    return result;
}
int64_t wasmoon_input_available(wasmoon_input *input) {
    AcquireSRWLockShared(&input->lock);
    int64_t result = (int64_t)input->length;
    ReleaseSRWLockShared(&input->lock);
    return result;
}
SOCKET wasmoon_input_notification(wasmoon_input *input) { return input->notification.reader; }
int wasmoon_input_read(wasmoon_input *input, void *buffer, int count, int nonblocking) {
    if (!count) return 0;
    AcquireSRWLockExclusive(&input->lock);
    request_input(input);
    while (!input->length && !input->eof && !input->error) {
        if (nonblocking) {
            ReleaseSRWLockExclusive(&input->lock); errno = EAGAIN; return -1;
        }
        SleepConditionVariableSRW(&input->changed, &input->lock, INFINITE, 0);
    }
    int result;
    if (input->length) {
        size_t take = (size_t)count < input->length ? (size_t)count : input->length;
        memcpy(buffer, input->buffer + input->offset, take);
        input->offset += take;
        input->length -= take;
        result = (int)take;
        if (!input->length && !input->eof && !input->error)
            wasmoon_notification_clear(&input->notification);
    } else result = input->eof ? 0 : wasmoon_windows_error(input->error);
    ReleaseSRWLockExclusive(&input->lock);
    return result;
}
#endif
