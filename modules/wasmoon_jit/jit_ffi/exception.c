// Copyright 2025
// Exception handling for JIT runtime
// Implements WebAssembly exception handling using setjmp/longjmp

// Ensure POSIX setjmp APIs are declared on glibc.
// This is required for `sigsetjmp` to be visible in some feature-macro configurations.
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <setjmp.h>

#include "jit_internal.h"

extern int64_t wasmoon_jit_context_ptr(void *jit_context);

static jit_context_t *exception_activation_context(jit_context_t *ctx) {
    jit_context_t *active = get_current_jit_context();
    return ctx && ctx->callable_local_types && active ? active : ctx;
}

// Stable exception objects belong to the Store, independently of handler frames.
typedef struct native_exception {
    int32_t tag;
    int32_t count;
    int64_t *values;
    void *root_registration;
} native_exception_t;

typedef struct native_exception_layout {
    int32_t *roots;
    int32_t count;
    int32_t tag;
    struct native_exception_layout *next;
} native_exception_layout_t;

typedef struct native_exception_arena {
    size_t references;
    size_t count;
    size_t capacity;
    native_exception_t *entries;
    int sealed;
    native_exception_layout_t *layouts;
} native_exception_arena_t;

struct native_exception_arena *exception_arena_new(void) {
    native_exception_arena_t *arena = calloc(1, sizeof(*arena));
    if (arena) arena->references = 1;
    return arena;
}

static void exception_arena_clear(native_exception_arena_t *arena) {
    if (!arena) return;
    for (size_t i = 0; i < arena->count; ++i) {
        native_exception_t *entry = &arena->entries[i];
        if (entry->root_registration)
            gc_heap_unregister_parked_roots(entry->root_registration);
        free(entry->values);
    }
    while (arena->layouts) {
        native_exception_layout_t *next = arena->layouts->next;
        free(arena->layouts->roots);
        free(arena->layouts);
        arena->layouts = next;
    }
    free(arena->entries);
    arena->entries = NULL;
    arena->count = arena->capacity = 0;
    arena->sealed = 1;
}

void exception_arena_release(native_exception_arena_t *arena) {
    if (arena && --arena->references == 0) {
        exception_arena_clear(arena);
        free(arena);
    }
}

static int64_t exception_arena_insert(native_exception_arena_t *arena,
    GcHeap *heap, int32_t tag, const int64_t *values, int32_t count) {
    if (!arena || arena->sealed || count < 0 || (count && !values)) return 0;
    if (arena->count == arena->capacity) {
        size_t capacity = arena->capacity ? arena->capacity * 2 : 16;
        if (capacity > INT32_MAX) return 0;
        void *entries = realloc(arena->entries, capacity * sizeof(native_exception_t));
        if (!entries) return 0;
        arena->entries = entries;
        arena->capacity = capacity;
    }
    native_exception_t entry = { .tag = tag, .count = count };
    if (count) {
        entry.values = malloc((size_t)count * sizeof(int64_t));
        if (!entry.values) return 0;
        memcpy(entry.values, values, (size_t)count * sizeof(int64_t));
        if (heap) {
            native_exception_layout_t *layout = arena->layouts;
            while (layout && layout->tag != tag) layout = layout->next;
            if (layout && layout->count != count) {
                free(entry.values);
                return 0;
            }
            int64_t *roots = NULL;
            if (!gc_heap_register_parked_roots(heap, count,
                    &entry.root_registration, &roots)) {
                free(entry.values);
                return 0;
            }
            for (int32_t i = 0; i < count; ++i)
                roots[i] = !layout || layout->roots[i] ? values[i] : 0;
        }
    }
    arena->entries[arena->count] = entry;
    // Odd references cannot be mistaken for movable GC heap objects.
    return ((int64_t)arena->count++ << 1) | 1;
}

static native_exception_t *exception_arena_lookup(native_exception_arena_t *arena,
    int64_t reference) {
    if (!arena || reference <= 0 || !(reference & 1) ||
        (uint64_t)(reference >> 1) >= arena->count) return NULL;
    return &arena->entries[reference >> 1];
}

static void finalize_exception_arena(void *owner) {
    exception_arena_release(*(native_exception_arena_t **)owner);
}

MOONBIT_FFI_EXPORT void *wasmoon_exception_arena_new(void) {
    native_exception_arena_t **owner = moonbit_make_external_object(
        finalize_exception_arena, sizeof(*owner));
    *owner = exception_arena_new();
    return owner;
}

MOONBIT_FFI_EXPORT void wasmoon_exception_arena_clear(void *owner) {
    exception_arena_clear(*(native_exception_arena_t **)owner);
}

MOONBIT_FFI_EXPORT void wasmoon_exception_arena_bind(void *context, void *owner) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    native_exception_arena_t *arena = *(native_exception_arena_t **)owner;
    if (ctx && arena != ctx->exception_arena) {
        if (arena) ++arena->references;
        exception_arena_release(ctx->exception_arena);
        ctx->exception_arena = arena;
    }
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_arena_define_tag(void *owner,
    int32_t tag, const int32_t *roots, int32_t count) {
    native_exception_arena_t *arena = *(native_exception_arena_t **)owner;
    if (!arena || arena->sealed || count < 0) return 0;
    for (native_exception_layout_t *entry = arena->layouts; entry; entry = entry->next)
        if (entry->tag == tag) return 1;
    native_exception_layout_t *layout = calloc(1, sizeof(*layout));
    if (!layout) return 0;
    if (count) {
        layout->roots = malloc((size_t)count * sizeof(int32_t));
        if (!layout->roots) { free(layout); return 0; }
        memcpy(layout->roots, roots, (size_t)count * sizeof(int32_t));
    }
    layout->count = count;
    layout->tag = tag;
    layout->next = arena->layouts;
    arena->layouts = layout;
    return 1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_exception_arena_insert(void *owner,
    int64_t heap, int32_t tag, const int64_t *values, int32_t count) {
    return exception_arena_insert(*(native_exception_arena_t **)owner,
        (GcHeap *)heap, tag, values, count);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_arena_tag(void *owner, int64_t ref) {
    native_exception_t *entry = exception_arena_lookup(*(native_exception_arena_t **)owner, ref);
    return entry ? entry->tag : -1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_arena_count(void *owner, int64_t ref) {
    native_exception_t *entry = exception_arena_lookup(*(native_exception_arena_t **)owner, ref);
    return entry ? entry->count : -1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_exception_arena_value(void *owner, int64_t ref, int32_t index) {
    native_exception_t *entry = exception_arena_lookup(*(native_exception_arena_t **)owner, ref);
    return entry && index >= 0 && index < entry->count ? entry->values[index] : 0;
}

static int64_t exception_get_ref_impl(jit_context_t *ctx) {
    ctx = exception_activation_context(ctx);
    if (!ctx->exception_ref) {
        ctx->exception_ref = exception_arena_insert(ctx->exception_arena,
            ctx->gc_heap, ctx->exception_tag, ctx->exception_values,
            ctx->exception_value_count);
        if (!ctx->exception_ref) {
            g_trap_code = 9;
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }
    return ctx->exception_ref;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_ref_ptr(void) {
    return (int64_t)exception_get_ref_impl;
}

// ============ Exception Handler Management ============

sigjmp_buf* exception_try_begin_impl(jit_context_t *ctx, int32_t handler_id) {
    ctx = exception_activation_context(ctx);
    // Allocate new handler node
    exception_handler_t *handler = (exception_handler_t *)malloc(sizeof(exception_handler_t));
    if (!handler) {
        // Out of memory - trap
        g_trap_code = 99;
        siglongjmp(g_trap_jmp_buf, 1);
    }

    // Link to previous handler
    handler->prev = (exception_handler_t *)ctx->exception_handler;
    handler->handler_id = handler_id;
    handler->gc_root_scope_marker = ctx->gc_root_scope_head;
    ctx->exception_handler = handler;

    // Return pointer to jmp_buf for caller to call setjmp
    return &handler->jmp_buf;
}

void exception_try_end_impl(jit_context_t *ctx, int32_t handler_id) {
    ctx = exception_activation_context(ctx);
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;

    // A mismatch means generated control flow violated lexical handler order.
    // Continuing would leave a stale jmp_buf linked into the runtime chain.
    if (!handler || handler->handler_id != handler_id) {
        g_trap_code = 8;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    ctx->exception_handler = handler->prev;
    free(handler);

    // Clear any pending exception values
    if (ctx->exception_values) {
        free(ctx->exception_values);
        ctx->exception_values = NULL;
    }
    ctx->exception_ref = 0;
    ctx->exception_value_count = 0;

    // Clear any spilled locals
    if (ctx->spilled_locals) {
        free(ctx->spilled_locals);
        ctx->spilled_locals = NULL;
    }
    ctx->spilled_locals_count = 0;
}

void exception_reset_context_state(jit_context_t *ctx) {
    if (!ctx) {
        return;
    }

    // Unwind and free any stale handler chain. This can happen when control
    // exits a function via trap longjmp before try_end executes.
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;
    while (handler) {
        exception_handler_t *prev = handler->prev;
        free(handler);
        handler = prev;
    }
    ctx->exception_handler = NULL;
    ctx_gc_clear_root_scopes_internal(ctx);

    if (ctx->exception_values) {
        free(ctx->exception_values);
        ctx->exception_values = NULL;
    }
    ctx->exception_ref = 0;
    ctx->exception_value_count = 0;
    ctx->exception_tag = 0;

    if (ctx->spilled_locals) {
        free(ctx->spilled_locals);
        ctx->spilled_locals = NULL;
    }
    ctx->spilled_locals_count = 0;
}

// ============ Exception Throwing ============

static void exception_raise_current(jit_context_t *ctx) __attribute__((noreturn));
static void exception_raise_current(jit_context_t *ctx) {
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;
    if (handler) {
        ctx_gc_restore_root_scopes_internal(ctx, handler->gc_root_scope_marker);
        siglongjmp(handler->jmp_buf, handler->handler_id);
    }
    g_trap_code = 12;
    ctx_gc_clear_root_scopes_internal(ctx);
    siglongjmp(g_trap_jmp_buf, 1);
}

static void exception_set_payload(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int64_t reference) {
    int64_t *copy = NULL;
    if (count > 0) {
        copy = malloc((size_t)count * sizeof(int64_t));
        if (!copy) {
            g_trap_code = 9;
            siglongjmp(g_trap_jmp_buf, 1);
        }
        memcpy(copy, values, (size_t)count * sizeof(int64_t));
    }
    free(ctx->exception_values);
    ctx->exception_values = copy;
    ctx->exception_value_count = count;
    ctx->exception_tag = tag;
    ctx->exception_ref = reference;
}

void exception_throw_impl(jit_context_t *ctx, int32_t tag_addr,
                          int64_t *values, int32_t count) {
    if (ctx && tag_addr >= 0 && tag_addr < ctx->callable_tag_count)
        tag_addr = ctx->callable_tags[tag_addr];
    ctx = exception_activation_context(ctx);
    exception_set_payload(ctx, tag_addr, values, count, 0);
    exception_raise_current(ctx);
}

void exception_throw_ref_impl(jit_context_t *ctx, int64_t exnref) {
    ctx = exception_activation_context(ctx);
    native_exception_t *entry = exception_arena_lookup(ctx->exception_arena, exnref);
    if (!entry) {
        g_trap_code = exnref == 0 ? 14 : 8;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    // The snapshot already stores a Store tag, never a module-local index.
    exception_set_payload(ctx, entry->tag, entry->values, entry->count, exnref);
    exception_raise_current(ctx);
}

void exception_delegate_impl(jit_context_t *ctx, int32_t depth) {
    ctx = exception_activation_context(ctx);
    // Delegate skips 'depth' handlers and throws to the one at that level
    exception_handler_t *target = (exception_handler_t *)ctx->exception_handler;

    // Walk up the handler chain by depth
    for (int i = 0; i < depth && target; i++) {
        // Pop this handler (we're delegating past it)
        exception_handler_t *to_free = target;
        target = target->prev;
        ctx->exception_handler = target;
        free(to_free);
    }

    if (target) {
        // longjmp to target handler
        ctx_gc_restore_root_scopes_internal(
            ctx,
            target->gc_root_scope_marker
        );
        siglongjmp(target->jmp_buf, target->handler_id);
    }

    // No handler at that depth - uncaught exception
    g_trap_code = 12;
    ctx_gc_clear_root_scopes_internal(ctx);
    siglongjmp(g_trap_jmp_buf, 1);
}

// ============ Locals Spilling for Exception Handling ============

void exception_spill_locals_impl(jit_context_t *ctx, int64_t *locals, int32_t count) {
    ctx = exception_activation_context(ctx);
    // Free any previous spilled locals
    if (ctx->spilled_locals) {
        free(ctx->spilled_locals);
        ctx->spilled_locals = NULL;
    }

    ctx->spilled_locals_count = count;

    if (count > 0 && locals) {
        // Copy locals to heap
        ctx->spilled_locals = (int64_t *)malloc(count * sizeof(int64_t));
        if (ctx->spilled_locals) {
            memcpy(ctx->spilled_locals, locals, count * sizeof(int64_t));
        }
    } else {
        ctx->spilled_locals = NULL;
    }
}

int64_t exception_get_spilled_local_impl(jit_context_t *ctx, int32_t idx) {
    ctx = exception_activation_context(ctx);
    if (idx >= 0 && idx < ctx->spilled_locals_count && ctx->spilled_locals) {
        return ctx->spilled_locals[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

// ============ Exception Value Access ============

int32_t exception_get_tag_impl(jit_context_t *ctx) {
    int32_t tag = exception_activation_context(ctx)->exception_tag;
    if (ctx->callable_local_types) {
        for (int i = 0; i < ctx->callable_tag_count; ++i) {
            if (ctx->callable_tags[i] == tag) return i;
        }
        return -1;
    }
    return tag;
}

int64_t exception_get_value_impl(jit_context_t *ctx, int32_t idx) {
    ctx = exception_activation_context(ctx);
    if (idx >= 0 && idx < ctx->exception_value_count && ctx->exception_values) {
        return ctx->exception_values[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

int32_t exception_get_value_count_impl(jit_context_t *ctx) {
    ctx = exception_activation_context(ctx);
    return ctx->exception_value_count;
}

// ============ FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_try_begin(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return (int64_t)exception_try_begin_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_try_end(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_try_end_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw(int64_t ctx_ptr, int32_t tag_addr,
                                                     int64_t values_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *values = (int64_t *)values_ptr;
    exception_throw_impl(ctx, tag_addr, values, count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_tag(int64_t ctx_ptr, int32_t tag_addr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_throw_impl(ctx, tag_addr, NULL, 0);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_values(
    int64_t ctx_ptr,
    int32_t tag_addr,
    int64_t *values,
    int32_t count
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_throw_impl(ctx, tag_addr, values, count);
}

extern int64_t wasmoon_jit_context_ptr(void *jit_context);

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_tag_managed(
    void *jit_context, int32_t tag_addr
) {
    wasmoon_jit_exception_throw_tag(
        wasmoon_jit_context_ptr(jit_context), tag_addr
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_values_managed(
    void *jit_context,
    int32_t tag_addr,
    int64_t *values,
    int32_t count
) {
    wasmoon_jit_exception_throw_values(
        wasmoon_jit_context_ptr(jit_context), tag_addr, values, count
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_ref(int64_t ctx_ptr, int64_t exnref) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_throw_ref_impl(ctx, exnref);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_delegate(int64_t ctx_ptr, int32_t depth) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_delegate_impl(ctx, depth);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_get_tag(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_tag_impl(ctx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_get_value(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_get_value_count(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_count_impl(ctx);
}

// Get function pointers for JIT codegen
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_begin_ptr(void) {
    return (int64_t)wasmoon_jit_exception_try_begin;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_end_ptr(void) {
    return (int64_t)wasmoon_jit_exception_try_end;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ptr(void) {
    return (int64_t)wasmoon_jit_exception_throw;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_tag_ptr(void) {
    return (int64_t)wasmoon_jit_exception_throw_tag;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ref_ptr(void) {
    return (int64_t)wasmoon_jit_exception_throw_ref;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_delegate_ptr(void) {
    return (int64_t)wasmoon_jit_exception_delegate;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_tag_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_tag;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_value;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_count_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_value_count;
}

// Spill/restore locals for exception handling
MOONBIT_FFI_EXPORT void wasmoon_jit_exception_spill_locals(int64_t ctx_ptr,
                                                            int64_t locals_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *locals = (int64_t *)locals_ptr;
    exception_spill_locals_impl(ctx, locals, count);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_get_spilled_local(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_spilled_local_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_spill_locals_ptr(void) {
    return (int64_t)wasmoon_jit_exception_spill_locals;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_spilled_local_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_spilled_local;
}

// Get sigsetjmp function pointer for JIT to call directly.
//
// IMPORTANT: do NOT wrap sigsetjmp in another C function.
// The JIT calls setjmp inside the *current* wasm frame and later longjmps back
// into that exact frame. If setjmp is performed in a wrapper that returns, the
// saved environment becomes invalid (undefined behavior) and longjmp may crash.
//
// On glibc, `sigsetjmp` may be a macro, so taking its address can be brittle.
// We return the address of the underlying implementation when available.
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sigsetjmp_ptr(void) {
#if defined(__GLIBC__)
    // glibc exposes the underlying implementation as __sigsetjmp.
    extern int __sigsetjmp(sigjmp_buf env, int savemask);
    return (int64_t)__sigsetjmp;
#else
    return (int64_t)sigsetjmp;
#endif
}

int64_t exception_capture_current(jit_context_t *ctx) {
    return exception_get_ref_impl(ctx);
}
int64_t exception_capture_payload(jit_context_t *ctx, int32_t tag, const int64_t *values, int32_t count) {
    if (tag >= 0 && tag < ctx->callable_tag_count) tag = ctx->callable_tags[tag];
    jit_context_t *active = exception_activation_context(ctx);
    int64_t reference = exception_arena_insert(active->exception_arena, active->gc_heap, tag, values, count);
    if (!reference) { g_trap_code = 9; siglongjmp(g_trap_jmp_buf, 1); }
    return reference;
}
