// Copyright 2025
// Trap handling for JIT runtime
// Handles signals from BRK instructions and stack overflow

#include "jit_internal.h"

// ============ Global Trap State ============

sigjmp_buf g_trap_jmp_buf;
volatile sig_atomic_t g_trap_code = 0;
volatile sig_atomic_t g_trap_active = 0;

// Alternate signal stack for handling stack overflow
#define SIGSTACK_SIZE (64 * 1024)  // 64KB alternate stack
static char g_sigstack[SIGSTACK_SIZE];
static int g_sigstack_installed = 0;

// Stack bounds for overflow detection
static void *g_stack_base = NULL;
static size_t g_stack_size = 0;

// ============ Stack Bounds Detection ============

static void init_stack_bounds(void) {
    if (g_stack_base != NULL) return;  // Already initialized

#if defined(__APPLE__)
    // macOS: use pthread_get_stackaddr_np and pthread_get_stacksize_np
    pthread_t self = pthread_self();
    g_stack_base = pthread_get_stackaddr_np(self);
    g_stack_size = pthread_get_stacksize_np(self);
#elif defined(__linux__)
    // Linux: use pthread_attr_getstack
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_getattr_np(pthread_self(), &attr);
    void *stack_addr;
    size_t stack_size;
    pthread_attr_getstack(&attr, &stack_addr, &stack_size);
    // On Linux, stack_addr is the low address
    g_stack_base = (char*)stack_addr + stack_size;
    g_stack_size = stack_size;
    pthread_attr_destroy(&attr);
#else
    // Fallback: estimate from current stack pointer
    volatile int dummy;
    g_stack_base = (void*)&dummy;
    g_stack_size = 8 * 1024 * 1024;  // Assume 8MB stack
#endif
}

// Check if address is near stack boundary (likely stack overflow)
static int is_stack_overflow(void *fault_addr) {
    if (g_stack_base == NULL || g_stack_size == 0) {
        return 0;  // Can't determine
    }

    // Stack grows down: check if fault address is below stack base
    // and within a reasonable range (stack region + guard pages)
    uintptr_t base = (uintptr_t)g_stack_base;
    uintptr_t addr = (uintptr_t)fault_addr;
    uintptr_t stack_low = base - g_stack_size;

    // Consider addresses within stack region or slightly below (guard page)
    // Guard page is typically 4KB-64KB below stack limit
    size_t guard_zone = 64 * 1024;  // 64KB guard zone
    if (stack_low > guard_zone) {
        stack_low -= guard_zone;
    } else {
        stack_low = 0;
    }

    return (addr >= stack_low && addr < base);
}

// ============ Alternate Signal Stack ============

static void install_alt_stack(void) {
    if (g_sigstack_installed) return;

#ifndef _WIN32
    stack_t ss;
    ss.ss_sp = g_sigstack;
    ss.ss_size = SIGSTACK_SIZE;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) == 0) {
        g_sigstack_installed = 1;
    }
#endif
}

// ============ Signal Handlers ============

#ifndef _WIN32

// Signal handler for SIGTRAP (triggered by BRK instruction)
// Uses SA_SIGINFO to get ucontext and extract BRK immediate
static void trap_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)sig;
    (void)info;

    if (g_trap_active) {
        int trap_code = 99;  // Default to unknown

#if defined(__APPLE__) && defined(__aarch64__)
        // On macOS ARM64, extract PC from ucontext and read BRK immediate
        ucontext_t *uc = (ucontext_t *)ucontext;
        uint64_t pc = uc->uc_mcontext->__ss.__pc;
        // PC points to the instruction after BRK, so read at PC-4
        uint32_t instr = *(uint32_t *)(pc - 4);
        // BRK encoding: 0xD4200000 | (imm16 << 5)
        // Extract imm16: (instr >> 5) & 0xFFFF
        int brk_imm = (instr >> 5) & 0xFFFF;

        // Map BRK immediate to trap code
        switch (brk_imm) {
            case 0: trap_code = 3; break;   // unreachable
            case 1: trap_code = 1; break;   // out of bounds (memory/table access)
            case 2: trap_code = 4; break;   // indirect call type mismatch
            case 3: trap_code = 5; break;   // invalid conversion to integer
            case 4: trap_code = 6; break;   // integer divide by zero
            case 5: trap_code = 7; break;   // integer overflow
            default: trap_code = 99; break; // unknown
        }
#elif defined(__linux__) && defined(__aarch64__)
        // On Linux ARM64
        ucontext_t *uc = (ucontext_t *)ucontext;
        uint64_t pc = uc->uc_mcontext.pc;
        uint32_t instr = *(uint32_t *)(pc - 4);
        int brk_imm = (instr >> 5) & 0xFFFF;

        switch (brk_imm) {
            case 0: trap_code = 3; break;   // unreachable
            case 1: trap_code = 1; break;   // out of bounds (memory/table access)
            case 2: trap_code = 4; break;   // indirect call type mismatch
            case 3: trap_code = 5; break;   // invalid conversion to integer
            case 4: trap_code = 6; break;   // integer divide by zero
            case 5: trap_code = 7; break;   // integer overflow
            default: trap_code = 99; break; // unknown
        }
#else
        (void)ucontext;
        trap_code = 99;  // Unknown on unsupported platforms
#endif

        g_trap_code = trap_code;
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

// Signal handler for SIGSEGV (triggered by stack overflow or invalid memory access)
static void segv_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)sig;
    (void)ucontext;

    if (g_trap_active) {
        void *fault_addr = info->si_addr;

        // First, check for WASM stack guard page access
        // This has priority over native stack overflow detection
        jit_context_t *ctx = get_current_jit_context();
        if (ctx && is_wasm_guard_page_access(ctx, fault_addr)) {
            // WASM stack overflow - hit the guard page
            g_trap_code = 2;  // call stack exhausted
            siglongjmp(g_trap_jmp_buf, 1);
        }

        if (is_stack_overflow(fault_addr)) {
            // Native stack overflow detected (fallback for non-stack-switching mode)
            g_trap_code = 2;  // call stack exhausted
            siglongjmp(g_trap_jmp_buf, 1);
        } else {
            // Could be WASM memory access violation or other error
            // Use unknown trap code since we can't determine the exact cause
            g_trap_code = 99;
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }

    // Not in JIT context, re-raise signal for default handling
    signal(SIGSEGV, SIG_DFL);
    raise(SIGSEGV);
}

#endif // !_WIN32

// ============ Handler Installation ============

void install_trap_handler(void) {
    static int installed = 0;
    if (installed) return;

#ifndef _WIN32
    init_stack_bounds();
    install_alt_stack();  // Must install alternate stack first

    // Install SIGTRAP handler (for BRK instructions)
    // Use SA_SIGINFO to get ucontext for extracting BRK immediate
    struct sigaction sa_trap;
    sa_trap.sa_sigaction = trap_signal_handler;
    sigemptyset(&sa_trap.sa_mask);
    sa_trap.sa_flags = SA_SIGINFO;
    sigaction(SIGTRAP, &sa_trap, NULL);

    // Install SIGSEGV handler (for stack overflow)
    // Use SA_SIGINFO to get fault address, SA_ONSTACK to use alternate stack
    struct sigaction sa_segv;
    sa_segv.sa_sigaction = segv_signal_handler;
    sigemptyset(&sa_segv.sa_mask);
    sa_segv.sa_flags = SA_SIGINFO | SA_ONSTACK;  // Run on alternate stack!
    sigaction(SIGSEGV, &sa_segv, NULL);

    // Also handle SIGBUS (on some platforms, stack overflow triggers SIGBUS)
    sigaction(SIGBUS, &sa_segv, NULL);
#endif

    installed = 1;
}
