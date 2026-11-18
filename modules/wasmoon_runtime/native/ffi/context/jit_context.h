// Embedding-owned state. Generated polling reads only the queried control
// offsets; other generated accesses use the VMContext layout descriptor.
#ifndef WASMOON_JIT_CONTEXT_H
#define WASMOON_JIT_CONTEXT_H

#include "jit_ffi.h"
#include <assert.h>
#include "../../callable/registry.h"

// RC-owned reference arrays. Each context owns its mutable outer arrays;
// empty payloads represent dropped segments. Element payloads contain pairs.
typedef struct {
    uint8_t **data_segments;
    int64_t **elem_segments;
    uint8_t *data_dropped;
    uint8_t *elem_dropped;
} jit_segments_state_t;

// Native control-flow state belongs to one invocation, not one instance.
// The legacy standalone helper API allocates this lazily outside an invocation.
typedef struct {
    void *exception_handler;  // Current exception handler (exception_handler_t*)
    int hostcall_exception_pending; // Deliver only after the MoonBit callback returns.
    int64_t exception_ref;
    int32_t exception_tag;    // Tag of in-flight exception
    int64_t *exception_values; // Exception payload values
    int32_t exception_value_count; // Number of exception values
    int64_t *spilled_locals;      // Saved local values
    int32_t spilled_locals_count; // Number of saved locals
    void *poll_controls; // Borrowed activation controls for generated safepoints.
    int gc_collect_requested;
    int gc_in_collect;
    int64_t *gc_root_scratch;
    int32_t gc_root_scratch_len;
    int32_t gc_root_scratch_cap;
    wasmoon_gc_frame_t *gc_frame_chain_head;
    wasmoon_gc_function_frame_t *gc_function_frame_head;
    wasmoon_gc_root_scope_t *gc_root_scope_head;
    // Popped storage belongs to this invocation, including while parked.
    wasmoon_gc_root_scope_t *gc_root_scope_free;
} jit_execution_state_t;

void jit_execution_state_clear(jit_execution_state_t *state);
void jit_execution_clear_root_scopes(jit_execution_state_t *state);
void exception_reset_execution_state(jit_execution_state_t *state);

// Contexts store defaults; active invocations retain their own control snapshot.
typedef struct {
    void *cancellation_callback;
    void *cancellation_callback_data;
    int32_t scheduling_budget;
    int32_t scheduling_quantum;
} jit_invocation_controls_t;

typedef struct {
    uint64_t header;
    uint64_t prefix_shape;
} gc_offset_struct_binding_t;

_Static_assert(sizeof(gc_offset_struct_binding_t) == 16, "offset struct binding size");

typedef struct jit_runtime_state {
    // Prepend experimental fields to preserve ABI-relative offsets.
    gc_offset_struct_binding_t *gc_offset_struct_bindings;

    // Published only for the current activation when it has no callback.
    // Keep this at the start so existing ABI-relative offsets stay fixed.
    int32_t *poll_budget;

    // Retained immutable MoonBit layout; NULL selects the legacy ABI.
    uint8_t *layout;
    jit_execution_state_t *execution;

    // RC-owned MoonBit GC metadata arrays; native helpers borrow their payloads.
    int32_t *gc_type_cache;
    int32_t *gc_canonical_indices;
    int32_t *gc_func_type_indices;
    // RC-owned MoonBit Int64 snapshot of native function addresses.
    int64_t *gc_func_table;

    // Store-bound continuation and exception arenas
    struct native_continuation_arena *continuation_arena;
    struct native_continuation_type *continuation_types;
    struct native_exception_arena *exception_arena;
    struct native_exception_arena *(*exception_arena_factory)(void);

    // Hostcall callback (MoonBit closure) for JIT -> host function bridging.
    // This is invoked by `wasmoon_jit_hostcall` during JIT execution.
    void *hostcall_callback;          // Function pointer for hostcall callback
    void *hostcall_callback_data;     // Closure data for hostcall callback

    jit_invocation_controls_t control_defaults;

    // Optional bulk-memory/table segment storage.
    jit_segments_state_t *segments;

    const wasmoon_gc_safepoint_table_t *gc_safepoint_table;
    // Stable native descriptors retaining MoonBit blob/offset arrays.
    wasmoon_gc_safepoint_table_t *gc_func_safepoint_tables;
    // Callable identity metadata persists across execution activations.
    int32_t *callable_local_types;
    jit_callable_registry_t *callable_registry;
    int32_t *callable_tags;
    int32_t *callable_functions;

    wasmoon_table_binding_t *table_bindings;
    // Pack scalar metadata after pointer fields.
    int gc_num_types;
    int gc_num_canonical;
    int gc_num_funcs;
    int gc_func_table_size;
    int owns_memory0;         // Whether this context owns memory0 (should free it)
    int wasi_exited;          // WASI: proc_exit called
    int wasi_exit_code;       // WASI: exit code
    int32_t gc_func_safepoint_table_count;
    int callable_local_type_count;
    int callable_tag_count;
    int callable_function_count;
    // Use the tail padding so generated offsets and the context stay compact.
    int gc_offset_struct_bindings_enabled;
} jit_runtime_state_t;

// Private state precedes the address passed to generated code. Its size is
// independent of the module; the trailing ABI storage follows the layout.
// The queried polling prefix is pinned by the artifact codegen revision.
typedef struct {
    jit_runtime_state_t runtime;
    jit_context_t abi;
} jit_context_owner_t;

static inline jit_runtime_state_t *ctx_runtime(const jit_context_t *ctx) {
    return (jit_runtime_state_t *)((char *)(void *)ctx - offsetof(jit_context_owner_t, abi));
}

void ctx_clear_gc_offset_struct_bindings(jit_context_t *ctx);

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

_Static_assert(offsetof(jit_context_owner_t, abi) == sizeof(jit_runtime_state_t), "context ABI alignment");

// Typed helper views over the layout supplied by MoonBit. Generated code embeds
// these offsets directly; only native helpers consult the retained descriptor.

// The descriptor stores byte offsets for the 18 scalar ABI fields, followed
// by seven little-endian 32-bit array layout/capacity words at byte 20.
static inline int32_t context_layout_field(const uint8_t *layout, int index) {
    if (index < 18) return layout[index] == 255 ? -1 : layout[index];
    const uint8_t *word = layout + (index - 18) * 4;
    return (int32_t)((uint32_t)word[0] | ((uint32_t)word[1] << 8) |
                     ((uint32_t)word[2] << 16) | ((uint32_t)word[3] << 24));
}

#define CONTEXT_FIELD_ADDRESS(name, type, index) \
    static inline type *ctx_##name##_address(const jit_context_t *ctx) { \
        const uint8_t *layout = ctx_runtime(ctx)->layout; \
        int32_t offset = layout ? context_layout_field(layout, index) : (int32_t)offsetof(jit_context_t, name); \
        return offset < 0 ? NULL : (type *)((char *)(void *)ctx + offset); \
    }

#define CONTEXT_FIELD(name, type, index) \
    CONTEXT_FIELD_ADDRESS(name, type, index) \
    static inline type ctx_##name(const jit_context_t *ctx) { \
        type *address = ctx_##name##_address(ctx); \
        return address ? *address : (type)0; \
    } \
    static inline void ctx_set_##name(jit_context_t *ctx, type value) { \
        type *address = ctx_##name##_address(ctx); \
        if (address) *address = value; \
        else assert(value == (type)0); \
    }

CONTEXT_FIELD(memory0, wasmoon_memory_t *, 0)
CONTEXT_FIELD(memory0_base, uint8_t *, 1)
CONTEXT_FIELD(func_table, void **, 3)
CONTEXT_FIELD(table0_base, void **, 4)
CONTEXT_FIELD(table0_elements, size_t, 5)
CONTEXT_FIELD(globals, void *, 6)
CONTEXT_FIELD(tables, void ***, 7)
CONTEXT_FIELD(table_count, int, 8)
CONTEXT_FIELD(func_count, int, 9)
CONTEXT_FIELD(table_sizes, size_t *, 10)
CONTEXT_FIELD(table_max_sizes, size_t *, 11)
CONTEXT_FIELD(memories, wasmoon_memory_t **, 12)
CONTEXT_FIELD(memory_count, int, 13)
CONTEXT_FIELD(debug_current_func_idx, int32_t, 14)
CONTEXT_FIELD(gc_heap_ptr, uint8_t *, 15)
CONTEXT_FIELD(gc_heap_limit, uint8_t *, 16)
CONTEXT_FIELD(gc_heap, void *, 17)

CONTEXT_FIELD_ADDRESS(memory0_size, _Atomic size_t, 2)
static inline size_t ctx_memory0_size(const jit_context_t *ctx) {
    _Atomic size_t *address = ctx_memory0_size_address(ctx);
    return address ? atomic_load_explicit(address, memory_order_relaxed) : 0;
}
static inline void ctx_set_memory0_size(jit_context_t *ctx, size_t value) {
    _Atomic size_t *address = ctx_memory0_size_address(ctx);
    if (address) atomic_store_explicit(address, value, memory_order_relaxed);
    else assert(value == 0);
}

#undef CONTEXT_FIELD
#undef CONTEXT_FIELD_ADDRESS

static inline void table_mark_mutated(jit_context_t *ctx, int index) {
    if (ctx && index >= 0 && index < ctx_table_count(ctx) &&
        ctx_runtime(ctx)->table_bindings && ctx_runtime(ctx)->table_bindings[index].owner) {
        ctx_runtime(ctx)->table_bindings[index].owner->revision++;
    }
}

// Context allocation/free (internal implementations)
void ctx_set_globals_internal(jit_context_t *ctx, int64_t *globals);
void ctx_clear_segments_internal(jit_context_t *ctx);
jit_context_t *alloc_context_internal(int func_count);
// Consumes the supplied MoonBit external-pointer array, including on failure.
jit_context_t *alloc_context_with_functions(void **functions);
jit_context_t *alloc_context_with_layout(void **functions, uint8_t *layout);
void free_context_internal(jit_context_t *ctx);
void ctx_refresh_memory0_fast_fields(jit_context_t *ctx);
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_context_ptr(void *context);

#endif
