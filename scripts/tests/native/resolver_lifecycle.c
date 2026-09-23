#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
// Deterministic schedules against the production resolver, with allocation
// failures and default SIGPIPE behavior. No DNS service or timing dependency.
#include <assert.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <netdb.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <sys/wait.h>
#include <spawn.h>
#include <stdio.h>
#include "moonbit.h"

static int allocation_index;
static int fail_at;
static int live_allocations;
static int thread_failure;
static void *(*pending_worker)(void *);
static void *pending_argument;
static int pending_count;
static void (*during_lookup)(void);
static void *checked_calloc(size_t count, size_t size) {
    if (++allocation_index == fail_at) return NULL;
    void *value = calloc(count, size);
    if (value) live_allocations++;
    return value;
}
static char *checked_strdup(const char *text) {
    if (++allocation_index == fail_at) return NULL;
    char *value = strdup(text);
    if (value) live_allocations++;
    return value;
}
static void checked_free(void *value) {
    if (value) live_allocations--;
    free(value);
}
static int schedule_worker(pthread_t *thread, const pthread_attr_t *attr,
                           void *(*worker)(void *), void *argument) {
    (void)attr;
    *thread = pthread_self();
    if (thread_failure) return EAGAIN;
    pending_count++;
    pending_worker = worker;
    pending_argument = argument;
    return 0;
}
static int resolve_name(const char *name, const char *service,
                        const struct addrinfo *hints, struct addrinfo **results) {
    (void)name;
    if (during_lookup) during_lookup();
    struct addrinfo numeric = *hints;
    numeric.ai_flags |= AI_NUMERICHOST;
    return getaddrinfo("127.0.0.1", service, &numeric, results);
}
#define calloc checked_calloc
#define strdup checked_strdup
#define free checked_free
#define pthread_create schedule_worker
#define getaddrinfo resolve_name
#include "resolver_native.c"
#undef calloc
#undef strdup
#undef free
#undef pthread_create
#undef getaddrinfo

static void (*object_finalizer)(void *);
void *moonbit_make_external_object(void (*finalizer)(void *), uint32_t size) {
    object_finalizer = finalizer;
    void *object = calloc(1, size);
    assert(object);
    return object;
}
static void complete_worker(void) {
    void *(*worker)(void *) = pending_worker;
    assert(worker && pending_count > 0);
    if (--pending_count == 0) pending_worker = NULL;
    worker(pending_argument);
}
static void destroy_handle(struct wasmoon_wasi_resolver_handle *handle) {
    object_finalizer(handle);
    free(handle);
}
static int next(struct wasmoon_wasi_resolver_handle *handle) {
    uint8_t family, address[16];
    uint32_t scope;
    return wasmoon_wasi_resolver_next(handle, &family, address, &scope);
}

static struct wasmoon_wasi_resolver_handle *batch[34];

static void cancel_during_lookup(void) {
    during_lookup = NULL;
    assert(resolver_requests == RESOLVER_REQUESTS);
    wasmoon_wasi_resolver_drop(batch[0]);
    assert(resolver_requests == RESOLVER_REQUESTS);
    int fd;
    struct wasmoon_wasi_resolver_handle *overflow =
        wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd == -1 && errno == EAGAIN);
    destroy_handle(overflow);
    // Cancelling a queued request really releases its admission slot.
    wasmoon_wasi_resolver_drop(batch[1]);
    assert(resolver_requests == RESOLVER_REQUESTS - 1);
    batch[33] = wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd >= 0);
}

static void test_limits(void) {
    int fd;
    for (int i = 0; i < 32; i++) {
        batch[i] = wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
        assert(fd >= 0);
    }
    assert(pending_count == 4 && resolver_workers == 4);
    struct wasmoon_wasi_resolver_handle *overflow =
        wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd == -1 && errno == EAGAIN);
    destroy_handle(overflow);
    wasmoon_wasi_resolver_drop(batch[31]);
    batch[32] = wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd >= 0 && pending_count == 4);
    during_lookup = cancel_during_lookup;
    while (pending_count) complete_worker();
    assert(resolver_workers == 0 && resolver_requests == 0);
    for (int i = 0; i < 34; i++) {
        assert(next(batch[i]) == ((i == 0 || i == 1 || i == 31) ? 5 : 0));
        destroy_handle(batch[i]);
    }
    assert(live_allocations == 0);
    // A fresh burst after idle must restart workers successfully.
    struct wasmoon_wasi_resolver_handle *again =
        wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd >= 0);
    complete_worker();
    assert(next(again) == 0);
    destroy_handle(again);
    assert(live_allocations == 0);
}

static void test_inheritance(const char *program) {
    int fd;
    struct wasmoon_wasi_resolver_handle *handle =
        wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd >= 0);
    int writer = handle->state->write_fd;
    assert(fcntl(fd, F_GETFD) & FD_CLOEXEC);
    assert(writer < 0 || (fcntl(writer, F_GETFD) & FD_CLOEXEC));
    int control = open("/dev/null", O_RDONLY);
    assert(control >= 0);
    char reader_arg[32], writer_arg[32], control_arg[32];
    snprintf(reader_arg, sizeof(reader_arg), "%d", fd);
    snprintf(writer_arg, sizeof(writer_arg), "%d", writer);
    snprintf(control_arg, sizeof(control_arg), "%d", control);
    char *args[] = {(char *)program, "child", reader_arg, writer_arg, control_arg, NULL};
    extern char **environ;
    pid_t child;
    // No close-all action: the notification itself must prevent inheritance.
    assert(posix_spawn(&child, program, NULL, NULL, args, environ) == 0);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(control);
    destroy_handle(handle);
    complete_worker();
    assert(live_allocations == 0);
}

int main(int argc, char **argv) {
    if (argc == 5) {
        assert(fcntl(atoi(argv[2]), F_GETFD) == -1 && errno == EBADF);
        if (atoi(argv[3]) >= 0)
            assert(fcntl(atoi(argv[3]), F_GETFD) == -1 && errno == EBADF);
        assert(fcntl(atoi(argv[4]), F_GETFD) >= 0);
        return 0;
    }

    signal(SIGPIPE, SIG_DFL);
    // Initial allocation, name copy, and result allocation fail independently.
    for (fail_at = 1; fail_at <= 4; fail_at++) {
        allocation_index = 0;
        int fd = -1;
        struct wasmoon_wasi_resolver_handle *handle =
            wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
        if (pending_worker) {
            assert(next(handle) == 1);
            complete_worker();
            assert(next(handle) == (fail_at == 3 ? 5 : 0));
        } else {
            assert(fd == -1);
            assert(next(handle) == 5);
        }
        wasmoon_wasi_resolver_drop(handle);
        wasmoon_wasi_resolver_drop(handle);
        assert(next(handle) == 5);
        destroy_handle(handle);
        assert(live_allocations == 0);
    }
    fail_at = 0;
    thread_failure = 1;
    int fd;
    struct wasmoon_wasi_resolver_handle *failed =
        wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
    assert(fd == -1 && next(failed) == 5);
    destroy_handle(failed);
    assert(live_allocations == 0);
    thread_failure = 0;
    for (int complete_first = 0; complete_first < 2; complete_first++) {
        for (int explicit_close = 0; explicit_close < 2; explicit_close++) {
            struct wasmoon_wasi_resolver_handle *handle =
                wasmoon_wasi_resolver_start((moonbit_bytes_t)"localhost", &fd);
            assert(fd >= 0);
            if (complete_first) {
                complete_worker();
                struct pollfd notification = {fd, POLLIN, 0};
                assert(poll(&notification, 1, 0) == 1);
                assert(notification.revents & POLLIN);
                assert(next(handle) == 0);
                assert(next(handle) == 2);
            }
            if (explicit_close) {
                wasmoon_wasi_resolver_drop(handle);
                wasmoon_wasi_resolver_drop(handle);
                assert(next(handle) == 5);
            }
            destroy_handle(handle);
            assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
            if (!complete_first) complete_worker();
            assert(live_allocations == 0);
        }
    }
    test_limits();
    test_inheritance(argv[0]);
    return 0;
}
