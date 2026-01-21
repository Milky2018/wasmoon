// Copyright 2025
// Trap handling for JIT runtime
// Handles signals from BRK instructions and stack overflow

#include "jit_internal.h"

// ============ Trap State (Thread-Local) ============
// These values are read/written by JIT execution and signal handlers.
// They must be thread-local because tests (and users) may run JIT concurrently.

__thread sigjmp_buf g_trap_jmp_buf;
__thread volatile sig_atomic_t g_trap_code = 0;
__thread volatile sig_atomic_t g_trap_active = 0;
__thread volatile sig_atomic_t g_trap_signal = 0;
__thread volatile uintptr_t g_trap_pc = 0;
__thread volatile uintptr_t g_trap_lr = 0;
__thread volatile uintptr_t g_trap_fp = 0;
__thread volatile uintptr_t g_trap_frame_lr = 0;
__thread volatile uintptr_t g_trap_fault_addr = 0;
__thread volatile sig_atomic_t g_trap_brk_imm = -1;
__thread volatile sig_atomic_t g_trap_func_idx = -1;

// WASM stack bounds for frame walking validation
__thread volatile uintptr_t g_trap_wasm_stack_base = 0;
__thread volatile uintptr_t g_trap_wasm_stack_top = 0;

// Pre-captured frame chain (captured in signal handler while stack is still valid)
#define MAX_TRAP_FRAMES 32
__thread volatile uintptr_t g_trap_frames_pc[MAX_TRAP_FRAMES];
__thread volatile uintptr_t g_trap_frames_fp[MAX_TRAP_FRAMES];
__thread volatile int g_trap_frame_count = 0;

// Alternate signal stack for handling stack overflow (per-thread; sigaltstack is per-thread)
#define SIGSTACK_SIZE (64 * 1024)  // 64KB alternate stack
static __thread char g_sigstack[SIGSTACK_SIZE];
static __thread int g_sigstack_installed = 0;

// Stack bounds for overflow detection (per-thread)
static __thread void *g_stack_base = NULL;
static __thread size_t g_stack_size = 0;

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

// BRK encoding: 0xD4200000 | (imm16 << 5)
// Match fixed bits [31:21] and [4:0].
#define BRK_MASK 0xFFE0001FU
#define BRK_BASE 0xD4200000U

static int decode_brk_imm(uintptr_t pc, uintptr_t *out_brk_pc, int *out_imm) {
    if (!out_brk_pc || !out_imm) return 0;
    // On some platforms, the ucontext PC points to the BRK instruction; on others it points
    // to the next instruction. Probe both `pc` and `pc-4` and validate the encoding.
    uint32_t instr = *(uint32_t *)pc;
    if ((instr & BRK_MASK) == BRK_BASE) {
        *out_brk_pc = pc;
        *out_imm = (int)((instr >> 5) & 0xFFFF);
        return 1;
    }
    if (pc >= 4) {
        uint32_t instr_prev = *(uint32_t *)(pc - 4);
        if ((instr_prev & BRK_MASK) == BRK_BASE) {
            *out_brk_pc = pc - 4;
            *out_imm = (int)((instr_prev >> 5) & 0xFFFF);
            return 1;
        }
    }
    return 0;
}

// External functions to get JIT code range (from dwarf.c)
extern uint64_t wasmoon_dwarf_get_low_pc(void);
extern uint64_t wasmoon_dwarf_get_high_pc(void);

// Walk the frame pointer chain and capture frames
// Must be called from signal handler while WASM stack is still valid
static void capture_frame_chain(uintptr_t initial_pc, uintptr_t initial_fp,
                                 uintptr_t stack_base, uintptr_t stack_top) {
    g_trap_frame_count = 0;

    // Get JIT code range for boundary detection
    uint64_t jit_low_pc = wasmoon_dwarf_get_low_pc();
    uint64_t jit_high_pc = wasmoon_dwarf_get_high_pc();

    // Capture first frame (trap location)
    if (g_trap_frame_count < MAX_TRAP_FRAMES) {
        g_trap_frames_pc[g_trap_frame_count] = initial_pc;
        g_trap_frames_fp[g_trap_frame_count] = initial_fp;
        g_trap_frame_count++;
    }

    // Walk the frame pointer chain
    uintptr_t fp = initial_fp;
    uintptr_t guard_size = 16 * 1024;  // Skip guard page region
    uintptr_t valid_low = stack_base + guard_size;

    while (fp != 0 && g_trap_frame_count < MAX_TRAP_FRAMES) {
        // Validate FP is within WASM stack bounds
        if (fp < valid_low || fp >= stack_top || (fp & 0xF) != 0) {
            break;
        }

        // Read frame record: [fp] = prev_fp, [fp+8] = return_address
        uintptr_t *frame_ptr = (uintptr_t *)fp;
        uintptr_t prev_fp = frame_ptr[0];
        uintptr_t return_addr = frame_ptr[1];

        if (return_addr == 0) {
            break;  // End of chain
        }

        // Stop if return address is outside JIT code range
        // This means we've reached the runtime boundary (trampoline)
        if (jit_low_pc != 0 && jit_high_pc != 0) {
            if (return_addr < jit_low_pc || return_addr >= jit_high_pc) {
                break;  // Left JIT code region
            }
        }

        // Add this frame
        g_trap_frames_pc[g_trap_frame_count] = return_addr;
        g_trap_frames_fp[g_trap_frame_count] = prev_fp;
        g_trap_frame_count++;

        // Move to previous frame (FP should grow upward as we unwind)
        if (prev_fp != 0 && prev_fp <= fp) {
            break;  // Invalid chain
        }
        fp = prev_fp;
    }
}

// Signal handler for SIGTRAP (triggered by BRK instruction)
// Uses SA_SIGINFO to get ucontext and extract BRK immediate
static void trap_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)info;

    if (g_trap_active) {
        int trap_code = 99;  // Default to unknown
        uintptr_t trap_pc = 0;
        int brk_imm = -1;

        jit_context_t *ctx = get_current_jit_context();

        g_trap_signal = sig;
        g_trap_fault_addr = 0;
        g_trap_pc = 0;
        g_trap_lr = 0;
        g_trap_fp = 0;
        g_trap_frame_lr = 0;
        g_trap_brk_imm = -1;
        g_trap_func_idx = -1;
        if (ctx) {
            g_trap_func_idx = (sig_atomic_t)ctx->debug_current_func_idx;
            // Save WASM stack bounds for frame walking validation
            g_trap_wasm_stack_base = (uintptr_t)ctx->wasm_stack_base;
            g_trap_wasm_stack_top = (uintptr_t)ctx->wasm_stack_top;
        }

#if defined(__APPLE__) && defined(__aarch64__)
        // On macOS ARM64, extract PC from ucontext and read BRK immediate
        ucontext_t *uc = (ucontext_t *)ucontext;
        uint64_t pc = uc->uc_mcontext->__ss.__pc;
        g_trap_lr = (uintptr_t)uc->uc_mcontext->__ss.__lr;
        // Capture frame pointer for stack walking
        uintptr_t fp = (uintptr_t)uc->uc_mcontext->__ss.__fp;
        g_trap_fp = fp;
        // If the function uses the standard prologue, the caller return address
        // is saved in the frame record at [fp + 8]. Only read it when `fp` looks safe.
        g_trap_frame_lr = 0;
        if (fp) {
            uintptr_t low = 0;
            uintptr_t high = 0;
            if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
                low = g_trap_wasm_stack_base;
                high = g_trap_wasm_stack_top;
            } else if (g_stack_base != NULL && g_stack_size != 0) {
                uintptr_t base = (uintptr_t)g_stack_base;
                low = base - (uintptr_t)g_stack_size;
                high = base;
            }
            if (high > low && fp >= low && fp + sizeof(uintptr_t) < high && (fp & 0xF) == 0) {
                g_trap_frame_lr = *(uintptr_t *)(fp + sizeof(uintptr_t));
            }
        }
        if (!decode_brk_imm((uintptr_t)pc, &trap_pc, &brk_imm)) {
            trap_pc = (uintptr_t)pc;
        }

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
        g_trap_lr = (uintptr_t)uc->uc_mcontext.regs[30];
        // Capture frame pointer for stack walking
         uintptr_t fp = (uintptr_t)uc->uc_mcontext.regs[29];
         g_trap_fp = fp;
         g_trap_frame_lr = 0;
         if (fp) {
             uintptr_t low = 0;
             uintptr_t high = 0;
             if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
                 low = g_trap_wasm_stack_base;
                 high = g_trap_wasm_stack_top;
             } else if (g_stack_base != NULL && g_stack_size != 0) {
                 uintptr_t base = (uintptr_t)g_stack_base;
                 low = base - (uintptr_t)g_stack_size;
                 high = base;
             }
             if (high > low && fp >= low && fp + sizeof(uintptr_t) < high && (fp & 0xF) == 0) {
                 g_trap_frame_lr = *(uintptr_t *)(fp + sizeof(uintptr_t));
             }
         }
        if (!decode_brk_imm((uintptr_t)pc, &trap_pc, &brk_imm)) {
            trap_pc = (uintptr_t)pc;
        }

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
        g_trap_pc = trap_pc;
        g_trap_brk_imm = brk_imm;

        // Capture frame chain while WASM stack is still accessible.
        // If we don't have WASM stack bounds, still record the top frame.
        if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
            capture_frame_chain(trap_pc, g_trap_fp,
                               g_trap_wasm_stack_base, g_trap_wasm_stack_top);
        } else {
            g_trap_frame_count = 0;
            if (g_trap_frame_count < MAX_TRAP_FRAMES) {
                g_trap_frames_pc[g_trap_frame_count] = trap_pc;
                g_trap_frames_fp[g_trap_frame_count] = g_trap_fp;
                g_trap_frame_count++;
            }
        }

        siglongjmp(g_trap_jmp_buf, 1);
    }
}

// Signal handler for SIGSEGV (triggered by stack overflow or invalid memory access)
static void segv_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    if (g_trap_active) {
        void *fault_addr = info->si_addr;
        jit_context_t *ctx = get_current_jit_context();
        uintptr_t pc = 0;

        g_trap_signal = sig;
        g_trap_fault_addr = (uintptr_t)fault_addr;
        g_trap_brk_imm = -1;
        g_trap_func_idx = -1;
        if (ctx) {
            g_trap_func_idx = (sig_atomic_t)ctx->debug_current_func_idx;
            // Save WASM stack bounds for frame walking validation
            g_trap_wasm_stack_base = (uintptr_t)ctx->wasm_stack_base;
            g_trap_wasm_stack_top = (uintptr_t)ctx->wasm_stack_top;
        }

#if defined(__APPLE__) && defined(__aarch64__)
        if (ucontext) {
            ucontext_t *uc = (ucontext_t *)ucontext;
            pc = (uintptr_t)uc->uc_mcontext->__ss.__pc;
            g_trap_lr = (uintptr_t)uc->uc_mcontext->__ss.__lr;
             uintptr_t fp = (uintptr_t)uc->uc_mcontext->__ss.__fp;
             g_trap_fp = fp;
             g_trap_frame_lr = 0;
             if (fp) {
                 uintptr_t low = 0;
                 uintptr_t high = 0;
                 if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
                     low = g_trap_wasm_stack_base;
                     high = g_trap_wasm_stack_top;
                 } else if (g_stack_base != NULL && g_stack_size != 0) {
                     uintptr_t base = (uintptr_t)g_stack_base;
                     low = base - (uintptr_t)g_stack_size;
                     high = base;
                 }
                 if (high > low && fp >= low && fp + sizeof(uintptr_t) < high && (fp & 0xF) == 0) {
                     g_trap_frame_lr = *(uintptr_t *)(fp + sizeof(uintptr_t));
                 }
             }
        }
#elif defined(__linux__) && defined(__aarch64__)
        if (ucontext) {
            ucontext_t *uc = (ucontext_t *)ucontext;
            pc = (uintptr_t)uc->uc_mcontext.pc;
            g_trap_lr = (uintptr_t)uc->uc_mcontext.regs[30];
            uintptr_t fp = (uintptr_t)uc->uc_mcontext.regs[29];
            g_trap_fp = fp;
            g_trap_frame_lr = 0;
            if (fp) {
                uintptr_t low = 0;
                uintptr_t high = 0;
                if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
                    low = g_trap_wasm_stack_base;
                    high = g_trap_wasm_stack_top;
                } else if (g_stack_base != NULL && g_stack_size != 0) {
                    uintptr_t base = (uintptr_t)g_stack_base;
                    low = base - (uintptr_t)g_stack_size;
                    high = base;
                }
                if (high > low && fp >= low && fp + sizeof(uintptr_t) < high && (fp & 0xF) == 0) {
                    g_trap_frame_lr = *(uintptr_t *)(fp + sizeof(uintptr_t));
                }
            }
        }
#endif
        g_trap_pc = pc;

        // Capture frame chain while WASM stack is still accessible.
        // If we don't have WASM stack bounds, still record the top frame.
        if (g_trap_wasm_stack_base != 0 && g_trap_wasm_stack_top != 0) {
            capture_frame_chain(pc, g_trap_fp,
                               g_trap_wasm_stack_base, g_trap_wasm_stack_top);
        } else {
            g_trap_frame_count = 0;
            if (g_trap_frame_count < MAX_TRAP_FRAMES) {
                g_trap_frames_pc[g_trap_frame_count] = pc;
                g_trap_frames_fp[g_trap_frame_count] = g_trap_fp;
                g_trap_frame_count++;
            }
        }

        // Check for memory guard page access (bounds check elimination)
        // This converts out-of-bounds memory access to a proper trap
        if (ctx && is_memory_guard_page_access(ctx, fault_addr)) {
            g_trap_code = 1;  // out of bounds memory access
            siglongjmp(g_trap_jmp_buf, 1);
        }

        // Check for WASM stack guard page access
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
#ifndef _WIN32
    // Signal handlers are process-wide; install them once.
    // (Multiple installations are harmless, but keep this race-free.)
    static atomic_int installed_handlers = 0;
    int expected = 0;
    if (atomic_compare_exchange_strong(&installed_handlers, &expected, 1)) {
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
    }

    // These are per-thread: stacks differ per thread and sigaltstack is per-thread.
    init_stack_bounds();
    install_alt_stack();
#endif
}
