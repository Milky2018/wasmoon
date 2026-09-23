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
#include "moonbit.h"

static int allocation_index;
static int fail_at;
static int live_allocations;
static int thread_failure;
static void *(*pending_worker)(void *);
static void *pending_argument;
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
    assert(pending_worker == NULL);
    pending_worker = worker;
    pending_argument = argument;
    return 0;
}
static int detach_worker(pthread_t thread) { (void)thread; return 0; }
static int resolve_name(const char *name, const char *service,
                        const struct addrinfo *hints, struct addrinfo **results) {
    (void)name;
    struct addrinfo numeric = *hints;
    numeric.ai_flags |= AI_NUMERICHOST;
    return getaddrinfo("127.0.0.1", service, &numeric, results);
}
#define calloc checked_calloc
#define strdup checked_strdup
#define free checked_free
#define pthread_create schedule_worker
#define pthread_detach detach_worker
#define getaddrinfo resolve_name
#include "resolver_native.c"
#undef calloc
#undef strdup
#undef free
#undef pthread_create
#undef pthread_detach
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
    pending_worker = NULL;
    assert(worker);
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

int main(void) {
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
                uint8_t notification = 0;
                assert(read(fd, &notification, 1) == 1 && notification == 1);
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
    return 0;
}
