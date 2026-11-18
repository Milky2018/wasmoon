#ifndef WASMOON_TRAP_H
#define WASMOON_TRAP_H

#include <signal.h>
#include <setjmp.h>
#include "../abi/windows_context.h"
#include "../context/jit_context.h"
#include "../gc/gc_heap.h"

// Returns zero only when no native trap activation is active.
int64_t jit_trap_result(int32_t code);

#define MAX_TRAP_FRAMES 32

typedef struct jit_trap_activation {
    sigjmp_buf jmp_buf;
#ifdef __APPLE__
    sigset_t signal_mask;
    uintptr_t signal_landing_sp;
#endif
    volatile sig_atomic_t active;
    volatile sig_atomic_t code;
    volatile sig_atomic_t signal;
    volatile uintptr_t pc;
    volatile uintptr_t lr;
    volatile uintptr_t fp;
    volatile uintptr_t frame_lr;
    volatile uintptr_t fault_addr;
    volatile sig_atomic_t brk_imm;
    volatile sig_atomic_t func_idx;
    volatile uintptr_t x0;
    volatile uintptr_t x1;
    volatile uintptr_t x2;
    volatile uintptr_t x3;
    volatile uintptr_t x6;
    volatile uintptr_t x7;
    volatile uintptr_t x8;
    volatile uintptr_t x9;
    volatile uintptr_t x10;
    volatile uintptr_t x11;
    volatile uintptr_t x15;
    volatile uintptr_t stack_base;
    volatile uintptr_t stack_top;
    volatile uintptr_t guard_base;
    volatile size_t guard_size;
    volatile uintptr_t frames_pc[MAX_TRAP_FRAMES];
    volatile uintptr_t frames_fp[MAX_TRAP_FRAMES];
    volatile int frame_count;
    jit_context_t *context;
    jit_invocation_controls_t owned_controls;
    jit_invocation_controls_t *controls;
    int inherit_controls;
    struct jit_trap_activation *previous;
    jit_execution_state_t execution;
    jit_execution_state_t *previous_execution;
    int32_t debug_current_func_idx;
    int32_t previous_debug_func_idx;
    int context_detached;
    GcParkedRoots parked_roots;
} jit_trap_activation_t;

typedef struct {
    jit_trap_activation_t fallback;
    jit_trap_activation_t *current;
} jit_activation_slot_t;
// One TLS lookup serves both the active and fallback activation.
extern _Thread_local jit_activation_slot_t wasmoon_jit_activation_slot;
jit_trap_activation_t *jit_current_trap_activation(void);
static inline jit_trap_activation_t *jit_current_trap_activation_fast(void) {
    jit_activation_slot_t *slot = &wasmoon_jit_activation_slot;
    return slot->current ? slot->current : &slot->fallback;
}
jit_trap_activation_t *jit_observed_trap_activation(void);
void jit_trap_activation_init(
    jit_trap_activation_t *activation,
    jit_context_t *context
);
int jit_trap_activation_push(jit_trap_activation_t *activation);
void jit_trap_activation_finalize(jit_trap_activation_t *activation);
void jit_trap_activation_publish(jit_trap_activation_t *activation);
void jit_trap_activation_pop(jit_trap_activation_t *activation);
jit_trap_activation_t *jit_trap_activation_detach(void);
void jit_trap_activation_attach(jit_trap_activation_t *activation);
void jit_trap_activation_abandon(jit_trap_activation_t *activation);
void jit_mark_active_gc_roots(GcHeap *heap);

int jit_parked_gc_roots_register(
    jit_trap_activation_t *activation,
    void **registration
);
void jit_parked_gc_roots_unregister(void *registration);

#define g_trap_jmp_buf (jit_current_trap_activation_fast()->jmp_buf)
#define g_trap_active (jit_current_trap_activation_fast()->active)
#define g_trap_code (jit_current_trap_activation_fast()->code)
#define g_trap_signal (jit_current_trap_activation_fast()->signal)
#define g_trap_pc (jit_current_trap_activation_fast()->pc)
#define g_trap_lr (jit_current_trap_activation_fast()->lr)
#define g_trap_fp (jit_current_trap_activation_fast()->fp)
#define g_trap_frame_lr (jit_current_trap_activation_fast()->frame_lr)
#define g_trap_fault_addr (jit_current_trap_activation_fast()->fault_addr)
#define g_trap_brk_imm (jit_current_trap_activation_fast()->brk_imm)
#define g_trap_func_idx (jit_current_trap_activation_fast()->func_idx)
#define g_trap_x0 (jit_current_trap_activation_fast()->x0)
#define g_trap_x1 (jit_current_trap_activation_fast()->x1)
#define g_trap_x2 (jit_current_trap_activation_fast()->x2)
#define g_trap_x3 (jit_current_trap_activation_fast()->x3)
#define g_trap_x6 (jit_current_trap_activation_fast()->x6)
#define g_trap_x7 (jit_current_trap_activation_fast()->x7)
#define g_trap_x8 (jit_current_trap_activation_fast()->x8)
#define g_trap_x9 (jit_current_trap_activation_fast()->x9)
#define g_trap_x10 (jit_current_trap_activation_fast()->x10)
#define g_trap_x11 (jit_current_trap_activation_fast()->x11)
#define g_trap_x15 (jit_current_trap_activation_fast()->x15)
#define g_trap_wasm_stack_base (jit_current_trap_activation_fast()->stack_base)
#define g_trap_wasm_stack_top (jit_current_trap_activation_fast()->stack_top)
#define g_trap_frames_pc (jit_current_trap_activation_fast()->frames_pc)
#define g_trap_frames_fp (jit_current_trap_activation_fast()->frames_fp)
#define g_trap_frame_count (jit_current_trap_activation_fast()->frame_count)

int install_trap_handler(void);

// Get the context owned by the current trap activation.
jit_context_t *get_current_jit_context(void);
static inline jit_context_t *get_current_jit_context_fast(void) {
    jit_trap_activation_t *activation = jit_current_trap_activation_fast();
    return activation->active ? activation->context : NULL;
}

#endif
