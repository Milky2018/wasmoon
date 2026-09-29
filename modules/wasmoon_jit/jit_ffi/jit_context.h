// Private per-instance state. Generated code only sees jit_context_t.
#ifndef WASMOON_JIT_CONTEXT_H
#define WASMOON_JIT_CONTEXT_H

#include "jit_ffi.h"
#include "../native/callable/registry.h"

typedef struct {
    uint8_t **data_segments;
    size_t *data_segment_sizes;   // number of bytes per segment
    uint8_t *data_dropped;        // 0/1 per segment
    int data_segment_count;
    // Each element is a (value, type index) pair.
    int64_t **elem_segments;
    size_t *elem_segment_sizes;   // number of elements (not Int64 slots)
    uint8_t *elem_dropped;        // 0/1 per segment
    int elem_segment_count;
} jit_segments_state_t;

// Native control-flow state belongs to one invocation, not one instance.
// The legacy standalone helper API allocates this lazily outside an invocation.
typedef struct {
    void *exception_handler;  // Current exception handler (exception_handler_t*)
    int64_t exception_ref;
    int32_t exception_tag;    // Tag of in-flight exception
    int64_t *exception_values; // Exception payload values
    int32_t exception_value_count; // Number of exception values
    int64_t *spilled_locals;      // Saved local values
    int32_t spilled_locals_count; // Number of saved locals
    int gc_collect_requested;
    int gc_in_collect;
    int64_t *gc_root_scratch;
    int32_t gc_root_scratch_len;
    int32_t gc_root_scratch_cap;
    wasmoon_gc_frame_t *gc_frame_chain_head;
    wasmoon_gc_root_scope_t *gc_root_scope_head;
} jit_execution_state_t;

void jit_execution_state_clear(jit_execution_state_t *state);
void jit_execution_clear_root_scopes(jit_execution_state_t *state);
void exception_reset_execution_state(jit_execution_state_t *state);

typedef struct jit_runtime_state {
    jit_execution_state_t *execution;

    // RC-owned MoonBit GC metadata arrays; native helpers borrow their payloads.
    int32_t *gc_type_cache;
    int gc_num_types;
    int32_t *gc_canonical_indices;
    int gc_num_canonical;
    int32_t *gc_func_type_indices;
    int gc_num_funcs;
    // Legacy native function-address snapshot remains malloc-owned.
    void **gc_func_table;
    int gc_func_table_size;

    // Additional fields (not accessed by JIT code directly)
    int owns_memory0;         // Whether this context owns memory0 (should free it)
    int wasi_exited;          // WASI: proc_exit called
    int wasi_exit_code;       // WASI: exit code

    // Store-bound continuation and exception arenas
    struct native_continuation_arena *continuation_arena;
    struct native_continuation_type *continuation_types;
    struct native_exception_arena *exception_arena;

    // Hostcall callback (MoonBit closure) for JIT -> host function bridging.
    // This is invoked by `wasmoon_jit_hostcall` during JIT execution.
    void *hostcall_callback;          // Function pointer for hostcall callback
    void *hostcall_callback_data;     // Closure data for hostcall callback

    // Invocation-local cooperative cancellation callback. Generated code only
    // passes the context to a C helper; these fields stay outside the fixed ABI.
    void *cancellation_callback;
    void *cancellation_callback_data;
    int32_t scheduling_budget;

    // Optional bulk-memory/table segment storage.
    jit_segments_state_t *segments;

    const wasmoon_gc_safepoint_table_t *gc_safepoint_table;
    // Per-function safepoint tables owned by this context.
    wasmoon_gc_safepoint_table_t *gc_func_safepoint_tables;
    int32_t gc_func_safepoint_table_count;
    // Callable identity metadata persists across execution activations.
    int32_t *callable_local_types;
    int callable_local_type_count;
    jit_callable_registry_t *callable_registry;
    int32_t *callable_tags;
    int callable_tag_count;

    wasmoon_table_binding_t *table_bindings;
} jit_runtime_state_t;

// A single allocation and finalizer own both the ABI and its private state.
typedef struct {
    jit_context_t abi;
    jit_runtime_state_t runtime;
} jit_context_owner_t;

// jit_context_t is the initial member of every native context allocation.
// Recovering the owner keeps helper accesses direct, without a back-pointer load.
static inline jit_runtime_state_t *ctx_runtime(const jit_context_t *ctx) {
    return &((jit_context_owner_t *)(void *)ctx)->runtime;
}

// Read/write helper access. Real invocations install their stack-owned state;
// only standalone context helpers need a separately allocated fallback.
jit_execution_state_t *ctx_execution_fallback(const jit_context_t *ctx);
static inline jit_execution_state_t *ctx_execution(const jit_context_t *ctx) {
    jit_execution_state_t *state = ctx_runtime(ctx)->execution;
    return state ? state : ctx_execution_fallback(ctx);
}

static inline const jit_segments_state_t *ctx_segments_state(const jit_context_t *ctx) {
    static const jit_segments_state_t empty = {0};
    return ctx && ctx_runtime(ctx)->segments ? ctx_runtime(ctx)->segments : &empty;
}

_Static_assert(offsetof(jit_context_owner_t, abi) == 0, "context owner prefix");

#endif
