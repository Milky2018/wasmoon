#include "moonbit.h"
MOONBIT_FFI_EXPORT int wasmoon_host_is_windows(void) {
#ifdef _WIN32
    return 1;
#else
    return 0;
#endif
}

#ifdef _WIN32
#include "windows_io.h"
#include <errno.h>
#include <io.h>
#include <fcntl.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")

int wasmoon_windows_error(DWORD error) {
  switch (error) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: errno = ENOENT; break;
    case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: errno = EACCES; break;
    case ERROR_INVALID_HANDLE: errno = EBADF; break;
    case ERROR_ALREADY_EXISTS: case ERROR_FILE_EXISTS: errno = EEXIST; break;
    case ERROR_DIRECTORY: errno = ENOTDIR; break;
    case ERROR_DIR_NOT_EMPTY: errno = ENOTEMPTY; break;
    case ERROR_DISK_FULL: case ERROR_HANDLE_DISK_FULL: errno = ENOSPC; break;
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: errno = ENOMEM; break;
    case ERROR_FILENAME_EXCED_RANGE: errno = ENAMETOOLONG; break;
    case ERROR_INVALID_NAME: case ERROR_INVALID_PARAMETER: errno = EINVAL; break;
    case ERROR_NOT_SAME_DEVICE: errno = EXDEV; break;
    case ERROR_TOO_MANY_OPEN_FILES: errno = EMFILE; break;
    case ERROR_NOT_SUPPORTED: case ERROR_INVALID_FUNCTION: errno = ENOTSUP; break;
    case ERROR_CANT_RESOLVE_FILENAME: case ERROR_STOPPED_ON_SYMLINK: errno = ELOOP; break;
    case ERROR_BROKEN_PIPE: case ERROR_NO_DATA: errno = EPIPE; break;
    case ERROR_OPERATION_ABORTED: errno = EINTR; break;
    default: errno = EIO; break;
  }
  return -1;
}
// CRT descriptors are int-sized; SOCKET is pointer-sized. Never truncate one
// into the other. Reserved ids hold sockets until explicit close, with reuse
// following ordinary descriptor semantics. Callers must not close a borrowed
// descriptor concurrently with an operation on it.
#define SOCKET_FD_BASE 0x40000000
static SRWLOCK sockets_lock = SRWLOCK_INIT;
static SOCKET *sockets;
static size_t sockets_count;
static INIT_ONCE winsock_once = INIT_ONCE_STATIC_INIT;
static int winsock_error;
static BOOL CALLBACK initialize_winsock(PINIT_ONCE once, PVOID arg, PVOID *context) {
    (void)once; (void)arg; (void)context;
    WSADATA data;
    winsock_error = WSAStartup(MAKEWORD(2, 2), &data);
    return TRUE;
}
int wasmoon_windows_winsock_init(void) {
    InitOnceExecuteOnce(&winsock_once, initialize_winsock, NULL, NULL);
    if (winsock_error) { errno = EIO; return -1; }
    return 0;
}
int wasmoon_windows_socket_adopt(SOCKET socket, int flags) {
    if (socket == INVALID_SOCKET) return -1;
    AcquireSRWLockExclusive(&sockets_lock);
    size_t slot = 0;
    while (slot < sockets_count && sockets[slot] != INVALID_SOCKET) slot++;
    if (slot == sockets_count) {
        if (sockets_count >= 0x3fffffff) {
            ReleaseSRWLockExclusive(&sockets_lock);
            closesocket(socket); errno = EMFILE; return -1;
        }
        size_t count = sockets_count ? sockets_count * 2 : 16;
        if (count > 0x3fffffff) count = 0x3fffffff;
        SOCKET *next = realloc(sockets, count * sizeof(*next));
        if (!next) {
            ReleaseSRWLockExclusive(&sockets_lock);
            closesocket(socket); errno = ENOMEM; return -1;
        }
        for (size_t i = sockets_count; i < count; i++) next[i] = INVALID_SOCKET;
        sockets = next;
        sockets_count = count;
    }
    sockets[slot] = socket;
    ReleaseSRWLockExclusive(&sockets_lock);
    int fd = SOCKET_FD_BASE + (int)slot;
    if (wasmoon_windows_track_file(fd, flags) < 0) {
        wasmoon_windows_close(fd); errno = ENOMEM; return -1;
    }
    return fd;
}
SOCKET wasmoon_windows_socket_get(int fd) {
    SOCKET socket = INVALID_SOCKET;
    if (fd >= SOCKET_FD_BASE) {
        size_t slot = (size_t)(fd - SOCKET_FD_BASE);
        AcquireSRWLockShared(&sockets_lock);
        if (slot < sockets_count) socket = sockets[slot];
        ReleaseSRWLockShared(&sockets_lock);
    }
    if (socket == INVALID_SOCKET) errno = ENOTSOCK;
    return socket;
}
int wasmoon_windows_is_socket(int fd) {
    return fd >= SOCKET_FD_BASE;
}
static void ignore_invalid_descriptor(const wchar_t *expression, const wchar_t *function,
                                      const wchar_t *file, unsigned line, uintptr_t reserved) {
    (void)expression; (void)function; (void)file; (void)line; (void)reserved;
}
HANDLE wasmoon_windows_fd_handle(int fd) {
    if (wasmoon_windows_is_socket(fd)) return (HANDLE)wasmoon_windows_socket_get(fd);
    if (fd < 0) { errno = EBADF; return INVALID_HANDLE_VALUE; }
    // UCRT otherwise terminates the process for an invalid inherited fd.
    _invalid_parameter_handler old = _set_thread_local_invalid_parameter_handler(ignore_invalid_descriptor);
    intptr_t handle = _get_osfhandle(fd);
    _set_thread_local_invalid_parameter_handler(old);
    return (HANDLE)handle;
}
typedef struct { int flags; unsigned references; } file_description;
typedef struct descriptor_flags {
    int fd;
    file_description *description;
    struct descriptor_flags *next;
} descriptor_flags;
static SRWLOCK flags_lock = SRWLOCK_INIT;
static descriptor_flags *descriptors;
static descriptor_flags *find_flags(int fd) {
    for (descriptor_flags *entry = descriptors; entry; entry = entry->next)
        if (entry->fd == fd) return entry;
    return NULL;
}
static void forget_flags(int fd) {
    AcquireSRWLockExclusive(&flags_lock);
    descriptor_flags **link = &descriptors;
    while (*link && (*link)->fd != fd) link = &(*link)->next;
    if (*link) {
        descriptor_flags *entry = *link;
        *link = entry->next;
        if (--entry->description->references == 0) free(entry->description);
        free(entry);
    }
    ReleaseSRWLockExclusive(&flags_lock);
}
int wasmoon_windows_track_file(int fd, int flags) {
    descriptor_flags *entry = malloc(sizeof(*entry));
    file_description *description = malloc(sizeof(*description));
    if (!entry || !description) { free(entry); free(description); errno = ENOMEM; return -1; }
    description->flags = flags;
    description->references = 1;
    entry->fd = fd; entry->description = description;
    AcquireSRWLockExclusive(&flags_lock);
    entry->next = descriptors; descriptors = entry;
    ReleaseSRWLockExclusive(&flags_lock);
    return 0;
}
static int file_access(HANDLE handle, ACCESS_MASK *access);
int wasmoon_windows_getfl(int fd) {
    HANDLE handle = wasmoon_windows_fd_handle(fd);
    if (handle == INVALID_HANDLE_VALUE) return -1;
    AcquireSRWLockShared(&flags_lock);
    descriptor_flags *entry = find_flags(fd);
    int flags = entry ? entry->description->flags : -1;
    ReleaseSRWLockShared(&flags_lock);
    if (flags >= 0) return flags;
    DWORD console_mode;
    if (GetConsoleMode(handle, &console_mode)) {
        CONSOLE_SCREEN_BUFFER_INFO screen;
        return GetConsoleScreenBufferInfo(handle, &screen) ? _O_WRONLY : _O_RDONLY;
    }
    ACCESS_MASK access;
    if (file_access(handle, &access) < 0) return -1;
    return access & FILE_WRITE_DATA ? (access & FILE_READ_DATA ? _O_RDWR : _O_WRONLY) : _O_RDONLY;
}
int wasmoon_windows_setfl(int fd, int flags) {
    int current = wasmoon_windows_getfl(fd);
    if (current < 0) return -1;
    int changeable = _O_APPEND | WASMOON_O_NONBLOCK;
    flags = (current & ~changeable) | (flags & changeable);
    AcquireSRWLockExclusive(&flags_lock);
    descriptor_flags *entry = find_flags(fd);
    if (!entry) {
        ReleaseSRWLockExclusive(&flags_lock);
        if (wasmoon_windows_track_file(fd, current) < 0) return -1;
        AcquireSRWLockExclusive(&flags_lock);
        entry = find_flags(fd);
    }
    if (wasmoon_windows_is_socket(fd)) {
        SOCKET socket = wasmoon_windows_socket_get(fd);
        u_long nonblocking = (flags & WASMOON_O_NONBLOCK) != 0;
        if (ioctlsocket(socket, FIONBIO, &nonblocking)) {
            int error = WSAGetLastError(); ReleaseSRWLockExclusive(&flags_lock);
            return wasmoon_windows_socket_error(error);
        }
    } else {
        HANDLE handle = wasmoon_windows_fd_handle(fd);
        if (GetFileType(handle) == FILE_TYPE_PIPE) {
            DWORD mode = (flags & WASMOON_O_NONBLOCK) ? PIPE_NOWAIT : PIPE_WAIT;
            if (!SetNamedPipeHandleState(handle, &mode, NULL, NULL)) {
                DWORD error = GetLastError(); ReleaseSRWLockExclusive(&flags_lock);
                return wasmoon_windows_error(error);
            }
        }
    }
    entry->description->flags = flags;
    ReleaseSRWLockExclusive(&flags_lock);
    return 0;
}
int wasmoon_windows_read(int fd, void *buffer, int count) {
    if (count < 0) { errno = EINVAL; return -1; }
    if (wasmoon_windows_is_socket(fd)) {
        SOCKET socket = wasmoon_windows_socket_get(fd);
        if (socket == INVALID_SOCKET) return -1;
        int result = recv(socket, buffer, count, 0);
        return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : result;
    }
    HANDLE handle = wasmoon_windows_fd_handle(fd);
    if (handle == INVALID_HANDLE_VALUE) return -1;
    DWORD read;
    if (ReadFile(handle, buffer, (DWORD)count, &read, NULL)) return (int)read;
    DWORD error = GetLastError();
    if (error == ERROR_BROKEN_PIPE) return 0;
    if (error == ERROR_NO_DATA) { errno = EAGAIN; return -1; }
    return wasmoon_windows_error(error);
}
int wasmoon_windows_write(int fd, const void *buffer, int count) {
    if (count < 0) { errno = EINVAL; return -1; }
    if (wasmoon_windows_is_socket(fd)) {
        SOCKET socket = wasmoon_windows_socket_get(fd);
        if (socket == INVALID_SOCKET) return -1;
        int result = send(socket, buffer, count, 0);
        return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : result;
    }
    HANDLE handle = wasmoon_windows_fd_handle(fd);
    if (handle == INVALID_HANDLE_VALUE) return -1;
    int flags = wasmoon_windows_getfl(fd);
    if (flags < 0) return -1;
    OVERLAPPED append = {0};
    append.Offset = MAXDWORD; append.OffsetHigh = MAXDWORD;
    OVERLAPPED *position = (flags & _O_APPEND) && GetFileType(handle) == FILE_TYPE_DISK ? &append : NULL;
    DWORD written;
    if (WriteFile(handle, buffer, (DWORD)count, &written, position)) {
        if (count && !written && (flags & WASMOON_O_NONBLOCK)) { errno = EAGAIN; return -1; }
        return (int)written;
    }
    return wasmoon_windows_error(GetLastError());
}
static int positioned_io(int fd, void *buffer, int count, int64_t offset, int write) {
    if (count < 0 || offset < 0) { errno = EINVAL; return -1; }
    HANDLE original = wasmoon_windows_fd_handle(fd);
    if (original == INVALID_HANDLE_VALUE) return -1;
    if (wasmoon_windows_is_socket(fd) || GetFileType(original) != FILE_TYPE_DISK) {
        errno = ESPIPE; return -1;
    }
    ACCESS_MASK access;
    if (file_access(original, &access) < 0) return -1;
    if (!(access & (write ? FILE_WRITE_DATA : FILE_READ_DATA))) { errno = EBADF; return -1; }
    // A separate overlapped handle addresses the same object even after a
    // rename and never changes the shared cursor of the original descriptor.
    HANDLE handle = ReOpenFile(original, write ? GENERIC_WRITE : GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, FILE_FLAG_OVERLAPPED);
    if (handle == INVALID_HANDLE_VALUE) return wasmoon_windows_error(GetLastError());
    OVERLAPPED operation = {0};
    operation.Offset = (DWORD)offset;
    operation.OffsetHigh = (DWORD)((uint64_t)offset >> 32);
    operation.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!operation.hEvent) {
        DWORD error = GetLastError(); CloseHandle(handle); return wasmoon_windows_error(error);
    }
    DWORD transferred = 0;
    BOOL result = write ? WriteFile(handle, buffer, (DWORD)count, &transferred, &operation)
                        : ReadFile(handle, buffer, (DWORD)count, &transferred, &operation);
    DWORD error = result ? ERROR_SUCCESS : GetLastError();
    if (!result && error == ERROR_IO_PENDING) {
        result = GetOverlappedResult(handle, &operation, &transferred, TRUE);
        error = result ? ERROR_SUCCESS : GetLastError();
    }
    CloseHandle(operation.hEvent); CloseHandle(handle);
    if (result) return (int)transferred;
    if (!write && error == ERROR_HANDLE_EOF) return 0;
    return wasmoon_windows_error(error);
}
int wasmoon_windows_pread(int fd, void *buffer, int count, int64_t offset) {
    return positioned_io(fd, buffer, count, offset, 0);
}
int wasmoon_windows_pwrite(int fd, const void *buffer, int count, int64_t offset) {
    return positioned_io(fd, (void *)buffer, count, offset, 1);
}
int wasmoon_windows_dup(int fd) {
    int flags = wasmoon_windows_getfl(fd);
    if (flags < 0) return -1;
    int duplicate;
    if (!wasmoon_windows_is_socket(fd)) {
        duplicate = _dup(fd);
        if (duplicate < 0) return -1;
        if (wasmoon_windows_track_file(duplicate, flags) < 0) {
            _close(duplicate); errno = ENOMEM; return -1;
        }
    } else {
        SOCKET socket = wasmoon_windows_socket_get(fd);
        if (socket == INVALID_SOCKET) return -1;
        WSAPROTOCOL_INFOW protocol;
        if (WSADuplicateSocketW(socket, GetCurrentProcessId(), &protocol))
            return wasmoon_windows_socket_error(WSAGetLastError());
        SOCKET socket_copy = WSASocketW(FROM_PROTOCOL_INFO, FROM_PROTOCOL_INFO,
            FROM_PROTOCOL_INFO, &protocol, 0, WSA_FLAG_NO_HANDLE_INHERIT);
        if (socket_copy == INVALID_SOCKET) return wasmoon_windows_socket_error(WSAGetLastError());
        duplicate = wasmoon_windows_socket_adopt(socket_copy, flags);
        if (duplicate < 0) return -1;
    }
    AcquireSRWLockExclusive(&flags_lock);
    descriptor_flags *original = find_flags(fd), *copy = find_flags(duplicate);
    if (original) {
        free(copy->description);
        copy->description = original->description;
        copy->description->references++;
    }
    ReleaseSRWLockExclusive(&flags_lock);
    return duplicate;
}
int wasmoon_windows_dup2(int old_fd, int new_fd) {
    if (new_fd < 0 || wasmoon_windows_is_socket(new_fd) || wasmoon_windows_is_socket(old_fd)) {
        errno = EBADF; return -1;
    }
    if (wasmoon_windows_fd_handle(old_fd) == INVALID_HANDLE_VALUE) return -1;
    if (old_fd == new_fd) return new_fd;
    // Allocate ownership metadata before replacing the destination. The
    // temporary duplicate also retains the shared open-file description.
    int temporary = wasmoon_windows_dup(old_fd);
    if (temporary < 0 || temporary == new_fd) return temporary;
    if (_dup2(temporary, new_fd) < 0) {
        int error = errno; wasmoon_windows_close(temporary); errno = error; return -1;
    }
    forget_flags(new_fd);
    AcquireSRWLockExclusive(&flags_lock);
    find_flags(temporary)->fd = new_fd;
    ReleaseSRWLockExclusive(&flags_lock);
    _close(temporary);
    return new_fd;
}
int wasmoon_windows_close(int fd) {
    if (!wasmoon_windows_is_socket(fd)) {
        if (wasmoon_windows_fd_handle(fd) == INVALID_HANDLE_VALUE) return -1;
        forget_flags(fd);
        return _close(fd);
    }
    size_t slot = (size_t)(fd - SOCKET_FD_BASE);
    AcquireSRWLockExclusive(&sockets_lock);
    SOCKET socket = slot < sockets_count ? sockets[slot] : INVALID_SOCKET;
    if (socket != INVALID_SOCKET) sockets[slot] = INVALID_SOCKET;
    ReleaseSRWLockExclusive(&sockets_lock);
    if (socket == INVALID_SOCKET) { errno = EBADF; return -1; }
    forget_flags(fd);
    int result = closesocket(socket);
    return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : 0;
}
int wasmoon_windows_socket_error(int error) {
    switch (error) {
        case WSAEWOULDBLOCK: errno = EAGAIN; break;
        case WSAEINTR: errno = EINTR; break;
        case WSAEBADF: case WSAENOTSOCK: errno = EBADF; break;
        case WSAEACCES: errno = EACCES; break;
        case WSAEINVAL: errno = EINVAL; break;
        case WSAEADDRINUSE: errno = EADDRINUSE; break;
        case WSAEADDRNOTAVAIL: errno = EADDRNOTAVAIL; break;
        case WSAECONNRESET: errno = ECONNRESET; break;
        case WSAECONNREFUSED: errno = ECONNREFUSED; break;
        case WSAECONNABORTED: errno = ECONNABORTED; break;
        case WSAENOTCONN: errno = ENOTCONN; break;
        case WSAETIMEDOUT: errno = ETIMEDOUT; break;
        case WSAEINPROGRESS: errno = EINPROGRESS; break;
        case WSAENOBUFS: errno = ENOMEM; break;
        case WSAEAFNOSUPPORT: errno = EAFNOSUPPORT; break;
        case WSAEMSGSIZE: errno = EMSGSIZE; break;
        case WSAESHUTDOWN: errno = EPIPE; break;
        default: errno = EIO; break;
    }
    return -1;
}

// FilePipeLocalInformation is defined by the NT I/O contract, but omitted
// from the user-mode SDK. Querying it observes quotas without consuming data.
#include <winternl.h>
typedef struct {
    ULONG type, configuration, maximum_instances, current_instances;
    ULONG inbound_quota, read_available, outbound_quota, write_available;
    ULONG state, end;
} pipe_local_information;
typedef NTSTATUS (NTAPI *query_file_fn)(HANDLE, PIO_STATUS_BLOCK, PVOID, ULONG, FILE_INFORMATION_CLASS);
typedef NTSTATUS (NTAPI *query_object_fn)(HANDLE, ULONG, PVOID, ULONG, PULONG);
static query_file_fn query_file;
static query_object_fn query_object;
static INIT_ONCE query_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK initialize_queries(PINIT_ONCE once, PVOID argument, PVOID *context) {
    (void)once; (void)argument; (void)context;
    HMODULE module = GetModuleHandleW(L"ntdll.dll");
    query_file = (query_file_fn)GetProcAddress(module, "NtQueryInformationFile");
    query_object = (query_object_fn)GetProcAddress(module, "NtQueryObject");
    return TRUE;
}
static int pipe_information(HANDLE handle, pipe_local_information *information) {
    InitOnceExecuteOnce(&query_once, initialize_queries, NULL, NULL);
    if (!query_file) return -1;
    IO_STATUS_BLOCK status;
    NTSTATUS result = query_file(handle, &status, information, sizeof(*information),
                                (FILE_INFORMATION_CLASS)24);
    return result >= 0 ? 0 : -1;
}
static int file_access(HANDLE handle, ACCESS_MASK *access) {
    InitOnceExecuteOnce(&query_once, initialize_queries, NULL, NULL);
    if (!query_file) { errno = ENOTSUP; return -1; }
    IO_STATUS_BLOCK status;
    if (query_file(handle, &status, access, sizeof(*access),
                   (FILE_INFORMATION_CLASS)8 /* FileAccessInformation */) < 0) {
        errno = EBADF; return -1;
    }
    return 0;
}
static int is_null_device(HANDLE handle) {
    InitOnceExecuteOnce(&query_once, initialize_queries, NULL, NULL);
    if (!query_object) return 0;
    union { UNICODE_STRING name; unsigned char bytes[1024]; } object;
    ULONG length;
    if (query_object(handle, 1, &object, sizeof(object), &length) < 0) return 0;
    static const wchar_t name[] = L"\\Device\\Null";
    return object.name.Length == sizeof(name) - sizeof(wchar_t) &&
           memcmp(object.name.Buffer, name, object.name.Length) == 0;
}
static int console_readiness(HANDLE handle, DWORD mode) {
    DWORD count;
    if (!GetNumberOfConsoleInputEvents(handle, &count)) return 8;
    if (!count) return 0;
    if ((size_t)count > SIZE_MAX / sizeof(INPUT_RECORD)) return 8;
    INPUT_RECORD *records = malloc((size_t)count * sizeof(*records));
    if (!records) return 8;
    DWORD read;
    int result = 0;
    if (!PeekConsoleInputW(handle, records, count, &read)) result = 8;
    else for (DWORD i = 0; i < read; i++) {
        if (records[i].EventType != KEY_EVENT || !records[i].Event.KeyEvent.bKeyDown) continue;
        wchar_t character = records[i].Event.KeyEvent.uChar.UnicodeChar;
        if (character && (!(mode & ENABLE_LINE_INPUT) || character == L'\r' || character == 26)) {
            result = 1;
            break;
        }
    }
    free(records);
    return result;
}
static int handle_readiness(HANDLE handle, int events) {
    SetLastError(NO_ERROR);
    DWORD kind = GetFileType(handle);
    if (kind == FILE_TYPE_UNKNOWN && GetLastError() != NO_ERROR) return 32;
    if (kind == FILE_TYPE_DISK) return events & 5;
    if (kind == FILE_TYPE_PIPE) {
        pipe_local_information information;
        if (pipe_information(handle, &information)) return 8;
        int result = 0;
        if (information.state == 1 || information.state == 4) result |= 16;
        if ((events & 1) && information.read_available) result |= 1;
        if ((events & 4) && information.state == 3 && information.write_available) result |= 4;
        return result;
    }
    if (kind == FILE_TYPE_CHAR) {
        DWORD mode;
        if (GetConsoleMode(handle, &mode)) {
            CONSOLE_SCREEN_BUFFER_INFO screen;
            if (GetConsoleScreenBufferInfo(handle, &screen)) return events & 4;
            return events & 1 ? console_readiness(handle, mode) : 0;
        }
        if (is_null_device(handle)) return events & 5;
    }
    // Unknown character devices must not acquire invented readiness.
    return 8;
}
int64_t wasmoon_windows_bytes_available(int fd) {
    if (wasmoon_windows_is_socket(fd)) {
        SOCKET socket = wasmoon_windows_socket_get(fd);
        if (socket == INVALID_SOCKET) return -1;
        u_long available = 0;
        if (ioctlsocket(socket, FIONREAD, &available))
            return wasmoon_windows_socket_error(WSAGetLastError());
        return available;
    }
    HANDLE handle = wasmoon_windows_fd_handle(fd);
    pipe_local_information information;
    if (handle != INVALID_HANDLE_VALUE && GetFileType(handle) == FILE_TYPE_PIPE &&
        !pipe_information(handle, &information)) return information.read_available;
    errno = ENOTSUP;
    return -1;
}
int wasmoon_windows_poll(const int *fds, const int *events, int *revents,
                         int count, int timeout_ms) {
    if (count <= 0 || timeout_ms < -1) { errno = EINVAL; return -1; }
    WSAPOLLFD *sockets = calloc((size_t)count, sizeof(*sockets));
    int *indices = malloc((size_t)count * sizeof(*indices));
    if (!sockets || !indices) { free(sockets); free(indices); errno = ENOMEM; return -1; }
    ULONGLONG start = GetTickCount64();
    int result;
    for (;;) {
        int socket_count = 0, observe_handles = 0;
        result = 0;
        for (int i = 0; i < count; i++) {
            revents[i] = 0;
            if (fds[i] < 0) continue;
            if (wasmoon_windows_is_socket(fds[i])) {
                SOCKET socket = wasmoon_windows_socket_get(fds[i]);
                if (socket == INVALID_SOCKET) revents[i] = 32;
                else {
                    WSAPOLLFD *item = &sockets[socket_count];
                    item->fd = socket;
                    item->events = ((events[i] & 1) ? POLLRDNORM : 0) |
                                   ((events[i] & 4) ? POLLWRNORM : 0);
                    item->revents = 0;
                    indices[socket_count++] = i;
                }
            } else {
                HANDLE handle = wasmoon_windows_fd_handle(fds[i]);
                revents[i] = handle == INVALID_HANDLE_VALUE ? 32 : handle_readiness(handle, events[i]);
                observe_handles = 1;
            }
            if (revents[i]) result++;
        }
        ULONGLONG elapsed = GetTickCount64() - start;
        int remaining = timeout_ms < 0 ? -1 : elapsed >= (ULONGLONG)timeout_ms
            ? 0 : timeout_ms - (int)elapsed;
        // Synchronous pipes and console handles have no non-consuming uniform
        // readiness wait. Recheck them after bounded sleeps, while WSAPoll owns
        // socket waits. This never spins or reads ahead from a guest descriptor.
        int wait = result ? 0 : remaining;
        if (observe_handles && (wait < 0 || wait > 10)) wait = 10;
        if (socket_count) {
            int ready = WSAPoll(sockets, (ULONG)socket_count, wait);
            if (ready == SOCKET_ERROR) {
                result = wasmoon_windows_socket_error(WSAGetLastError());
                break;
            }
            for (int j = 0; j < socket_count; j++) {
                int flags = sockets[j].revents;
                int i = indices[j];
                revents[i] = ((flags & (POLLRDNORM | POLLRDBAND)) ? 1 : 0) |
                    ((flags & POLLWRNORM) ? 4 : 0) | ((flags & POLLERR) ? 8 : 0) |
                    ((flags & POLLHUP) ? 16 : 0) | ((flags & POLLNVAL) ? 32 : 0);
                if (revents[i]) result++;
            }
        } else if (!result && wait != 0) {
            if (SleepEx(wait < 0 ? INFINITE : (DWORD)wait, TRUE) == WAIT_IO_COMPLETION) {
                errno = EINTR; result = -1; break;
            }
        }
        if (result || remaining == 0) break;
        // Rescan handles before returning a timeout: readiness may have arrived
        // in the last bounded wait interval.
    }
    int saved_errno = errno;
    free(sockets); free(indices);
    errno = saved_errno;
    return result;
}
#endif
