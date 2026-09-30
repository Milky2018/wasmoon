#include "../jit_ffi/jit_internal.h"

#ifdef __APPLE__
typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t condition;
    int phase;
    int blocked;
} signal_mask_probe_t;

static void *signal_mask_worker(void *data) {
    signal_mask_probe_t *probe = data;
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR2);
    pthread_sigmask(SIG_BLOCK, &mask, NULL);
    pthread_mutex_lock(&probe->lock);
    probe->phase = 1;
    pthread_cond_signal(&probe->condition);
    while (probe->phase != 2) pthread_cond_wait(&probe->condition, &probe->lock);
    pthread_sigmask(SIG_SETMASK, NULL, &mask);
    probe->blocked = sigismember(&mask, SIGUSR2);
    pthread_mutex_unlock(&probe->lock);
    return NULL;
}

static int WASMOON_GUEST_ABI signal_mask_trampoline(
    jit_context_t *ctx, int64_t *values, void *mode
) {
    (void)values;
    if ((uintptr_t)mode == 3) {
        int inner = wasmoon_jit_call_trampoline_caught(
            (int64_t)(uintptr_t)signal_mask_trampoline, (int64_t)(uintptr_t)ctx,
            2, NULL, 0, NULL);
        if (inner != 99) return -1;
        // Recovering the inner signal must leave the outer jump target active.
        g_trap_code = 6;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    if ((uintptr_t)mode == 1) {
        g_trap_code = 6;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    // The runtime's SIGSEGV handler runs on its alternate signal stack.
    raise(SIGSEGV);
    return -1;
}
#endif

MOONBIT_FFI_EXPORT int wasmoon_test_trap_signal_masks(void) {
#ifdef __APPLE__
    signal_mask_probe_t probe = {
        PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, 0, 0
    };
    sigset_t original, mask;
    pthread_sigmask(SIG_SETMASK, NULL, &original);
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR2);
    pthread_sigmask(SIG_UNBLOCK, &mask, NULL);
    pthread_sigmask(SIG_SETMASK, NULL, &mask);
    pthread_t worker;
    if (pthread_create(&worker, NULL, signal_mask_worker, &probe) != 0) abort();
    pthread_mutex_lock(&probe.lock);
    while (probe.phase != 1) pthread_cond_wait(&probe.condition, &probe.lock);
    jit_context_t *ctx = alloc_context_internal(0);
    if (!ctx) abort();
    install_trap_handler();
    stack_t before, after;
    sigaltstack(NULL, &before);
    int passed = 1;
    for (int i = 0; i < 48; ++i) {
        int mode = i % 3 + 1;
        int result = wasmoon_jit_call_trampoline_caught(
            (int64_t)(uintptr_t)signal_mask_trampoline, (int64_t)(uintptr_t)ctx,
            mode, NULL, 0, NULL);
        passed &= result == (mode == 2 ? 99 : 6);
        sigset_t current;
        pthread_sigmask(SIG_SETMASK, NULL, &current);
        passed &= current == mask;
        sigaltstack(NULL, &after);
        passed &= before.ss_sp == after.ss_sp && before.ss_size == after.ss_size &&
            before.ss_flags == after.ss_flags;
    }
    free_context_internal(ctx);
    probe.phase = 2;
    pthread_cond_signal(&probe.condition);
    pthread_mutex_unlock(&probe.lock);
    pthread_join(worker, NULL);
    passed &= probe.blocked;
    pthread_cond_destroy(&probe.condition);
    pthread_mutex_destroy(&probe.lock);
    pthread_sigmask(SIG_SETMASK, &original, NULL);
    return passed;
#else
    return 1;
#endif
}
