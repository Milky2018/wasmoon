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
    return ctx && ctx_runtime(ctx)->callable_local_types && active ? active : ctx;
}

// Logical identities, layouts and reachability belong to the MoonBit state.
// This adapter retains that state, without the state retaining the adapter.
typedef struct exception_insert_request {
    struct native_exception_arena *arena;
    GcHeap *heap;
    int32_t tag;
    int32_t count;
    const int64_t *values;
} exception_insert_request_t;

typedef struct exception_callbacks {
    int64_t (*insert)(void *, exception_insert_request_t *, int32_t, int32_t);
    int64_t (*lookup)(void *, int64_t);
    int64_t (*layout)(void *, int32_t);
    void (*mark)(void *, int64_t);
    int32_t (*marked_count)(void *);
    void (*copy_marked)(void *, int64_t *);
    void (*reset_marks)(void *);
    void (*sweep)(void *, int64_t);
} exception_callbacks_t;

struct exception_storage;

typedef struct native_exception_arena {
    void *state;
    struct exception_storage *storage; // Borrowed from the retained state
    exception_callbacks_t *callbacks;
} native_exception_arena_t;

// Physical payload storage and root leases, released on close or last RC owner.
typedef struct native_exception {
    int64_t *values;
    void *root_registration;
    int64_t byte_charge;
    int64_t object_charge;
    int32_t tag;
    int32_t count;
} native_exception_t;

// One RC owner for physical buffers. This contains no identities, marks,
// admission policy or lookup algorithm; MoonBit supplies validated slot indices.
typedef struct exception_storage {
    native_exception_t *entries;
    int32_t count;
    int32_t capacity;
    wasmoon_quota_t *bytes;
    wasmoon_quota_t *objects;
} exception_storage_t;

static void exception_payload_close(exception_storage_t *storage, native_exception_t *entry) {
    if (entry->count < 0) return;
    if (entry->root_registration) gc_heap_unregister_parked_roots(entry->root_registration);
    free(entry->values);
    wasmoon_quota_release(storage->bytes, entry->byte_charge);
    wasmoon_quota_release(storage->objects, entry->object_charge);
    memset(entry, 0, sizeof(*entry));
    entry->count = -1;
}

MOONBIT_FFI_EXPORT void wasmoon_exception_storage_clear(exception_storage_t *storage) {
    for (int32_t i = 0; i < storage->count; ++i) exception_payload_close(storage, &storage->entries[i]);
    free(storage->entries);
    if (storage->bytes) moonbit_decref(storage->bytes);
    if (storage->objects) moonbit_decref(storage->objects);
    memset(storage, 0, sizeof(*storage));
}

static void finalize_exception_storage(void *storage) {
    wasmoon_exception_storage_clear(storage);
}

MOONBIT_FFI_EXPORT exception_storage_t *wasmoon_exception_storage_new(void) {
    exception_storage_t *storage = moonbit_make_external_object(finalize_exception_storage, sizeof(*storage));
    memset(storage, 0, sizeof(*storage));
    return storage;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_storage_bind_quotas(exception_storage_t *storage,
    wasmoon_quota_t *bytes, wasmoon_quota_t *objects) {
    if (storage->count || storage->bytes || storage->objects) return 0;
    moonbit_incref(bytes);
    moonbit_incref(objects);
    storage->bytes = bytes;
    storage->objects = objects;
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_storage_capacity(exception_storage_t *storage) {
    return storage->capacity;
}

MOONBIT_FFI_EXPORT void wasmoon_exception_storage_shrink(exception_storage_t *storage) {
    if (storage->count == 0) {
        free(storage->entries);
        storage->entries = NULL;
        storage->capacity = 0;
    } else if (storage->count < storage->capacity) {
        // Best-effort reduction, not resource acquisition or guest admission.
        void *entries = realloc(storage->entries, (size_t)storage->count * sizeof(*storage->entries));
        if (entries) { storage->entries = entries; storage->capacity = storage->count; }
    }
}

static native_exception_t *exception_storage_at(exception_storage_t *storage, int32_t index) {
    return index >= 0 && index < storage->count ? &storage->entries[index] : NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_exception_storage_close_at(exception_storage_t *storage, int32_t index) {
    native_exception_t *entry = exception_storage_at(storage, index);
    if (entry) exception_payload_close(storage, entry);
}

MOONBIT_FFI_EXPORT void wasmoon_exception_storage_move(exception_storage_t *storage, int32_t from, int32_t to) {
    native_exception_t *source = exception_storage_at(storage, from);
    native_exception_t *target = exception_storage_at(storage, to);
    if (!source || !target || from == to) return;
    exception_payload_close(storage, target);
    *target = *source;
    memset(source, 0, sizeof(*source));
    source->count = -1;
}

MOONBIT_FFI_EXPORT void wasmoon_exception_storage_truncate(exception_storage_t *storage, int32_t count) {
    if (count < 0 || count > storage->count) return;
    for (int32_t i = count; i < storage->count; ++i) exception_payload_close(storage, &storage->entries[i]);
    storage->count = count;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_storage_append(
    exception_insert_request_t *request, int64_t reference, const int32_t *mask,
    int32_t traced, int64_t byte_charge, int64_t object_charge
) {
    exception_storage_t *storage = request->arena->storage;
    int32_t count = request->count;
    if (count < 0 || (size_t)count > SIZE_MAX / sizeof(int64_t)) return 0;
    if (storage->count == storage->capacity) {
        size_t capacity = storage->capacity ? (size_t)storage->capacity * 2 : 16;
        if (capacity > INT32_MAX || capacity > SIZE_MAX / sizeof(native_exception_t)) return 0;
        void *entries = wasmoon_native_realloc(storage->entries, capacity * sizeof(native_exception_t));
        if (!entries) return 0;
        storage->entries = entries;
        storage->capacity = (int32_t)capacity;
    }
    native_exception_t entry = {0};
    if (count) {
        entry.values = wasmoon_native_malloc((size_t)count * sizeof(int64_t));
        if (!entry.values) return 0;
        memcpy(entry.values, request->values, (size_t)count * sizeof(int64_t));
    }
    entry.tag = request->tag;
    entry.count = count;
    if (request->heap && (count || traced)) {
        int64_t *roots = NULL;
        int32_t slots = count ? count : 1;
        // Keep the out-parameter separate so the pending record can stay scalar.
        void *registration = NULL;
        if (!gc_heap_register_parked_roots(request->heap, slots, &registration, &roots)) goto failed;
        entry.root_registration = registration;
        int32_t mask_count = Moonbit_array_length(mask);
        for (int32_t i = 0; i < slots; ++i)
            roots[i] = i < count && (!mask_count || mask[i]) ? entry.values[i] : 0;
        if (traced && !gc_heap_bind_exception_roots(entry.root_registration, request->arena, reference)) goto failed;
    }
    entry.byte_charge = byte_charge;
    entry.object_charge = object_charge;
    storage->entries[storage->count++] = entry;
    return 1;
failed:
    exception_payload_close(storage, &entry);
    return 0;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_storage_tag(exception_storage_t *storage, int32_t index) {
    native_exception_t *entry = exception_storage_at(storage, index);
    return entry && entry->count >= 0 ? entry->tag : -1;
}
MOONBIT_FFI_EXPORT int64_t *wasmoon_exception_storage_values(exception_storage_t *storage, int32_t index) {
    native_exception_t *entry = exception_storage_at(storage, index);
    int32_t count = entry && entry->count >= 0 ? entry->count : 0;
    int64_t *values = moonbit_make_int64_array(count, 0);
    if (count) memcpy(values, entry->values, (size_t)count * sizeof(int64_t));
    return values;
}
MOONBIT_FFI_EXPORT int32_t wasmoon_exception_storage_on_heap(exception_storage_t *storage, int32_t index, int64_t heap) {
    native_exception_t *entry = exception_storage_at(storage, index);
    return entry && gc_heap_registration_heap(entry->root_registration) == (GcHeap *)(uintptr_t)heap;
}
MOONBIT_FFI_EXPORT int64_t wasmoon_exception_layout_address(const int32_t *mask) { return (int64_t)(uintptr_t)mask; }
MOONBIT_FFI_EXPORT void wasmoon_exception_root_write(int64_t *roots, int32_t index, int64_t value) { roots[index] = value; }

static void finalize_exception_arena(void *object) {
    native_exception_arena_t *arena = object;
    // The storage finalizer unregisters its leases at the last state release.
    // Neither state nor physical storage owns an edge back to this adapter.
    if (arena->state) moonbit_decref(arena->state);
    free(arena->callbacks);
}

MOONBIT_FFI_EXPORT native_exception_arena_t *wasmoon_exception_arena_new(
    void *state, exception_storage_t *storage,
    int64_t (*insert)(void *, exception_insert_request_t *, int32_t, int32_t),
    int64_t (*lookup)(void *, int64_t),
    int64_t (*layout)(void *, int32_t),
    void (*mark)(void *, int64_t), int32_t (*marked_count)(void *),
    void (*copy_marked)(void *, int64_t *), void (*reset_marks)(void *),
    void (*sweep)(void *, int64_t)
) {
    native_exception_arena_t *arena = moonbit_make_external_object(finalize_exception_arena, sizeof(*arena));
    memset(arena, 0, sizeof(*arena));
    arena->callbacks = wasmoon_native_malloc(sizeof(*arena->callbacks));
    if (arena->callbacks) {
        *arena->callbacks = (exception_callbacks_t){insert, lookup, layout, mark, marked_count, copy_marked, reset_marks, sweep};
        moonbit_incref(state);
        arena->state = state;
        arena->storage = storage;
    }
    return arena;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exception_arena_is_available(native_exception_arena_t *arena) {
    return arena && arena->callbacks;
}

void exception_arena_release(native_exception_arena_t *arena) {
    if (arena) moonbit_decref(arena);
}

// Callbacks borrow the retained state and cannot suspend or transfer control.
// In particular, native throws only occur after these frames have returned.
static WASMOON_NO_FUNCTION_SANITIZE int64_t exception_arena_insert(native_exception_arena_t *arena,
    GcHeap *heap, int32_t tag, const int64_t *values, int32_t count) {
    if (!arena || count < 0 || (count && !values)) return -9;
    exception_insert_request_t request = {arena, gc_heap_live(heap), tag, count, values};
    return arena->callbacks->insert(arena->state, &request, tag, count);
}

static WASMOON_NO_FUNCTION_SANITIZE native_exception_t *exception_arena_lookup(native_exception_arena_t *arena, int64_t reference) {
    if (!arena) return NULL;
    // The callback returns slot + 1 after full identity/liveness validation.
    int64_t slot = arena->callbacks->lookup(arena->state, reference);
    native_exception_t *entry = slot > 0 && slot <= INT32_MAX
        ? exception_storage_at(arena->storage, (int32_t)slot - 1) : NULL;
    return entry && entry->count >= 0 ? entry : NULL;
}

static WASMOON_NO_FUNCTION_SANITIZE const int32_t *exception_layout(native_exception_arena_t *arena, int32_t tag) {
    return arena ? (const int32_t *)(uintptr_t)arena->callbacks->layout(arena->state, tag) : NULL;
}

WASMOON_NO_FUNCTION_SANITIZE void exception_arena_mark(native_exception_arena_t *arena, int64_t reference) {
    if (arena) arena->callbacks->mark(arena->state, reference);
}
WASMOON_NO_FUNCTION_SANITIZE int32_t exception_arena_marked_count(native_exception_arena_t *arena) {
    return arena ? arena->callbacks->marked_count(arena->state) : 0;
}
WASMOON_NO_FUNCTION_SANITIZE void exception_arena_copy_marked(native_exception_arena_t *arena, int64_t *roots) {
    if (arena) arena->callbacks->copy_marked(arena->state, roots);
}
WASMOON_NO_FUNCTION_SANITIZE void exception_arena_reset_marks(native_exception_arena_t *arena) {
    if (arena) arena->callbacks->reset_marks(arena->state);
}
WASMOON_NO_FUNCTION_SANITIZE void exception_arena_sweep(native_exception_arena_t *arena, GcHeap *heap) {
    if (arena) arena->callbacks->sweep(arena->state, (int64_t)(uintptr_t)heap);
}

MOONBIT_FFI_EXPORT void wasmoon_exception_arena_bind(void *context, native_exception_arena_t *arena) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (ctx && arena != ctx_runtime(ctx)->exception_arena) {
        moonbit_incref(arena);
        exception_arena_release(ctx_runtime(ctx)->exception_arena);
        ctx_runtime(ctx)->exception_arena = arena;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_exception_arena_set_factory(void *context, native_exception_arena_t *(*factory)(void)) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (ctx) ctx_runtime(ctx)->exception_arena_factory = factory;
}

static WASMOON_NO_FUNCTION_SANITIZE native_exception_arena_t *exception_ensure_arena(jit_context_t *ctx) {
    jit_runtime_state_t *runtime = ctx_runtime(ctx);
    if (!runtime->exception_arena && runtime->exception_arena_factory) {
        native_exception_arena_t *arena = runtime->exception_arena_factory();
        if (wasmoon_exception_arena_is_available(arena)) runtime->exception_arena = arena;
        else exception_arena_release(arena);
    }
    return runtime->exception_arena;
}

// Managed insertions use the same synchronous request as compiled guest code.
MOONBIT_FFI_EXPORT int64_t wasmoon_exception_arena_insert(native_exception_arena_t *arena,
    GcHeap *heap, int32_t tag, const int64_t *values, int32_t count) {
    int64_t result = exception_arena_insert(arena, heap, tag, values, count);
    return result > 0 ? result : 0;
}

static int64_t WASMOON_GUEST_ABI exception_get_ref_impl(jit_context_t *ctx) {
    ctx = exception_activation_context(ctx);
    jit_execution_state_t *state = ctx_execution(ctx);
    if (!state->exception_ref) {
        int64_t reference = exception_arena_insert(exception_ensure_arena(ctx),
            ctx_gc_heap(ctx), state->exception_tag, state->exception_values,
            state->exception_value_count);
        if (reference <= 0) {
            g_trap_code = (int32_t)-reference;
            siglongjmp(g_trap_jmp_buf, 1);
        }
        state->exception_ref = reference;
    }
    return state->exception_ref;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_ref_ptr(void) {
    return WASMOON_GUEST_ADDRESS(exception_get_ref_impl);
}

// Snapshot only the current exception's typed reference words. The immutable
// exception token, when present, is sufficient to trace its complete payload.
int32_t exception_copy_activation_roots(jit_context_t *ctx, const jit_execution_state_t *state, int64_t *roots) {
    if (state->exception_ref) {
        if (roots) roots[0] = state->exception_ref;
        return 1;
    }
    const int32_t *layout = exception_layout(ctx_runtime(ctx)->exception_arena, state->exception_tag);
    int32_t count = 0;
    for (int32_t i = 0; i < state->exception_value_count; ++i) {
        if (state->exception_values && (!layout || (i < Moonbit_array_length(layout) && layout[i]))) {
            if (roots) roots[count] = state->exception_values[i];
            ++count;
        }
    }
    return count;
}

// Mark seeds without allocating: this path can run inside a MoonBit collector
// callback, where a native longjmp would bypass managed cleanup.
void exception_mark_activation_roots(GcHeap *heap, jit_context_t *ctx,
    const jit_execution_state_t *state) {
    if (state->exception_ref) {
        gc_heap_mark_roots(heap, &state->exception_ref, 1);
        return;
    }
    const int32_t *layout = exception_layout(ctx_runtime(ctx)->exception_arena, state->exception_tag);
    for (int32_t i = 0; i < state->exception_value_count; ++i) {
        if (state->exception_values && (!layout || (i < Moonbit_array_length(layout) && layout[i]))) {
            gc_heap_mark_roots(heap, &state->exception_values[i], 1);
        }
    }
}

// ============ Exception Handler Management ============

sigjmp_buf* exception_try_begin_impl(jit_context_t *ctx, int32_t handler_id) {
    ctx = exception_activation_context(ctx);
    jit_execution_state_t *state = ctx_execution(ctx);
    // Allocate new handler node
    exception_handler_t *handler = (exception_handler_t *)wasmoon_native_malloc(sizeof(exception_handler_t));
    if (!handler) {
        // Allocation failure is distinct from an unknown/internal trap.
        g_trap_code = 9;
        siglongjmp(g_trap_jmp_buf, 1);
    }

    // Link to previous handler
    handler->prev = (exception_handler_t *)state->exception_handler;
    handler->handler_id = handler_id;
    handler->gc_root_scope_marker = state->gc_root_scope_head;
    state->exception_handler = handler;

    // Return pointer to jmp_buf for caller to call setjmp
    return &handler->jmp_buf;
}

void exception_try_end_impl(jit_context_t *ctx, int32_t handler_id) {
    ctx = exception_activation_context(ctx);
    jit_execution_state_t *state = ctx_execution(ctx);
    exception_handler_t *handler = (exception_handler_t *)state->exception_handler;

    // A mismatch means generated control flow violated lexical handler order.
    // Continuing would leave a stale jmp_buf linked into the runtime chain.
    if (!handler || handler->handler_id != handler_id) {
        g_trap_code = 8;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    state->exception_handler = handler->prev;
    free(handler);

    // Clear any pending exception values
    if (state->exception_values) {
        free(state->exception_values);
        state->exception_values = NULL;
    }
    state->exception_ref = 0;
    state->exception_value_count = 0;

    // Clear any spilled locals
    if (state->spilled_locals) {
        free(state->spilled_locals);
        state->spilled_locals = NULL;
    }
    state->spilled_locals_count = 0;
}

void exception_reset_execution_state(jit_execution_state_t *state) {
    if (!state) {
        return;
    }

    // Unwind and free any stale handler chain. This can happen when control
    // exits a function via trap longjmp before try_end executes.
    exception_handler_t *handler = (exception_handler_t *)state->exception_handler;
    while (handler) {
        exception_handler_t *prev = handler->prev;
        free(handler);
        handler = prev;
    }
    state->exception_handler = NULL;
    jit_execution_clear_root_scopes(state);

    if (state->exception_values) {
        free(state->exception_values);
        state->exception_values = NULL;
    }
    state->exception_ref = 0;
    state->exception_value_count = 0;
    state->exception_tag = 0;
    state->hostcall_exception_pending = 0;

    if (state->spilled_locals) {
        free(state->spilled_locals);
        state->spilled_locals = NULL;
    }
    state->spilled_locals_count = 0;
}


// ============ Exception Throwing ============

#if defined(_MSC_VER) && !defined(__clang__)
__declspec(noreturn) static void exception_raise_current(jit_context_t *ctx);
#else
static void exception_raise_current(jit_context_t *ctx) __attribute__((noreturn));
#endif
static void exception_raise_current(jit_context_t *ctx) {
    exception_handler_t *handler = (exception_handler_t *)ctx_execution(ctx)->exception_handler;
    if (handler) {
        ctx_gc_restore_root_scopes_internal(ctx, handler->gc_root_scope_marker);
        siglongjmp(handler->jmp_buf, handler->handler_id);
    }
    g_trap_code = 12;
    ctx_gc_clear_root_scopes_internal(ctx);
    siglongjmp(g_trap_jmp_buf, 1);
}

static int exception_set_payload_checked(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int64_t reference) {
    jit_execution_state_t *state = ctx_execution(ctx);
    if (!state || count < 0 || (count > 0 && !values) ||
        (size_t)count > SIZE_MAX / sizeof(int64_t)) return 0;
    int64_t *copy = NULL;
    if (count > 0) {
        copy = wasmoon_native_malloc((size_t)count * sizeof(int64_t));
        if (!copy) return 0;
        memcpy(copy, values, (size_t)count * sizeof(int64_t));
    }
    free(state->exception_values);
    state->exception_values = copy;
    state->exception_value_count = count;
    state->exception_tag = tag;
    state->exception_ref = reference;
    return 1;
}

static void exception_set_payload(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int64_t reference) {
    if (!exception_set_payload_checked(ctx, tag, values, count, reference)) {
        g_trap_code = 9;
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

int exception_has_pending_hostcall(jit_context_t *ctx) {
    ctx = exception_activation_context(ctx);
    return ctx && ctx_runtime(ctx)->execution &&
        ctx_runtime(ctx)->execution->hostcall_exception_pending;
}

void exception_raise_pending_hostcall(jit_context_t *ctx) {
    if (exception_has_pending_hostcall(ctx)) {
        ctx = exception_activation_context(ctx);
        ctx_runtime(ctx)->execution->hostcall_exception_pending = 0;
        exception_raise_current(ctx);
    }
}

void exception_throw_impl(jit_context_t *ctx, int32_t tag_addr,
                          int64_t *values, int32_t count) {
    if (ctx && tag_addr >= 0 && tag_addr < ctx_runtime(ctx)->callable_tag_count)
        tag_addr = ctx_runtime(ctx)->callable_tags[tag_addr];
    ctx = exception_activation_context(ctx);
    exception_set_payload(ctx, tag_addr, values, count, 0);
    exception_raise_current(ctx);
}

void exception_throw_ref_impl(jit_context_t *ctx, int64_t exnref) {
    ctx = exception_activation_context(ctx);
    native_exception_t *entry = exception_arena_lookup(ctx_runtime(ctx)->exception_arena, exnref);
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
    jit_execution_state_t *state = ctx_execution(ctx);
    // Delegate skips 'depth' handlers and throws to the one at that level
    exception_handler_t *target = (exception_handler_t *)state->exception_handler;

    // Walk up the handler chain by depth
    for (int i = 0; i < depth && target; i++) {
        // Pop this handler (we're delegating past it)
        exception_handler_t *to_free = target;
        target = target->prev;
        state->exception_handler = target;
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
    jit_execution_state_t *state = ctx_execution(ctx);
    int64_t *copy = NULL;
    if (count > 0 && locals) {
        if ((size_t)count > SIZE_MAX / (2 * sizeof(int64_t))) {
            g_trap_code = 9;
            siglongjmp(g_trap_jmp_buf, 1);
        }
        copy = wasmoon_native_malloc((size_t)count * 2 * sizeof(int64_t));
        if (!copy) {
            g_trap_code = 9;
            siglongjmp(g_trap_jmp_buf, 1);
        }
        memcpy(copy, locals, (size_t)count * 2 * sizeof(int64_t));
    }
    free(state->spilled_locals);
    state->spilled_locals = copy;
    state->spilled_locals_count = copy ? count : 0;
}

int64_t exception_get_spilled_local_impl(jit_context_t *ctx, int32_t idx) {
    ctx = exception_activation_context(ctx);
    jit_execution_state_t *state = ctx_execution(ctx);
    if (idx >= 0 && idx < state->spilled_locals_count && state->spilled_locals) {
        return state->spilled_locals[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

// ============ Exception Value Access ============

int32_t exception_get_tag_impl(jit_context_t *ctx) {
    int32_t tag = ctx_execution(exception_activation_context(ctx))->exception_tag;
    if (ctx_runtime(ctx)->callable_local_types) {
        for (int i = 0; i < ctx_runtime(ctx)->callable_tag_count; ++i) {
            if (ctx_runtime(ctx)->callable_tags[i] == tag) return i;
        }
        return -1;
    }
    return tag;
}

int64_t exception_get_value_impl(jit_context_t *ctx, int32_t idx) {
    ctx = exception_activation_context(ctx);
    jit_execution_state_t *state = ctx_execution(ctx);
    if (idx >= 0 && idx < state->exception_value_count && state->exception_values) {
        return state->exception_values[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

int32_t exception_get_value_count_impl(jit_context_t *ctx) {
    ctx = exception_activation_context(ctx);
    return ctx_execution(ctx)->exception_value_count;
}

// ============ FFI Exports ============

MOONBIT_FFI_EXPORT int64_t WASMOON_GUEST_ABI wasmoon_jit_exception_try_begin(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return (int64_t)exception_try_begin_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_try_end(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_try_end_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_throw(int64_t ctx_ptr, int32_t tag_addr,
                                                     int64_t values_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *values = (int64_t *)values_ptr;
    exception_throw_impl(ctx, tag_addr, values, count);
}

MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_throw_tag(int64_t ctx_ptr, int32_t tag_addr) {
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

static int32_t exception_stage_hostcall(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int local_tag) {
    if (!ctx || !jit_hostcall_is_active(ctx) || !g_trap_active || count < 0 ||
        (count > 0 && !values)) return -1;
    if (local_tag) {
        if (tag < 0 || tag >= ctx_runtime(ctx)->callable_tag_count) return -1;
        tag = ctx_runtime(ctx)->callable_tags[tag];
    } else if (tag < 0) {
        return -1;
    }
    ctx = exception_activation_context(ctx);
    if (!ctx_runtime(ctx)->execution) return -1;
    if (!exception_set_payload_checked(ctx, tag, values, count, 0)) return 0;
    ctx_runtime(ctx)->execution->hostcall_exception_pending = 1;
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_throw_tag_managed(
    void *jit_context, int32_t tag_addr
) {
    return exception_stage_hostcall(
        (jit_context_t *)wasmoon_jit_context_ptr(jit_context),
        tag_addr, NULL, 0, 1
    );
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_throw_values_managed(
    void *jit_context, int32_t tag_addr, int64_t *values, int32_t count
) {
    return exception_stage_hostcall(
        (jit_context_t *)wasmoon_jit_context_ptr(jit_context),
        tag_addr, values, count, 1
    );
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_throw_store_values_managed(
    void *jit_context, int32_t tag_addr, int64_t *values, int32_t count
) {
    return exception_stage_hostcall(
        (jit_context_t *)wasmoon_jit_context_ptr(jit_context),
        tag_addr, values, count, 0
    );
}

MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_throw_ref(int64_t ctx_ptr, int64_t exnref) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_throw_ref_impl(ctx, exnref);
}

MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_delegate(int64_t ctx_ptr, int32_t depth) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_delegate_impl(ctx, depth);
}

MOONBIT_FFI_EXPORT int32_t WASMOON_GUEST_ABI wasmoon_jit_exception_get_tag(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_tag_impl(ctx);
}

MOONBIT_FFI_EXPORT int64_t WASMOON_GUEST_ABI wasmoon_jit_exception_get_value(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int32_t WASMOON_GUEST_ABI wasmoon_jit_exception_get_value_count(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_count_impl(ctx);
}

// Get function pointers for JIT codegen
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_begin_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_try_begin);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_end_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_try_end);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_throw);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_tag_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_throw_tag);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ref_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_throw_ref);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_delegate_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_delegate);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_tag_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_get_tag);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_get_value);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_count_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_get_value_count);
}

// Spill/restore locals for exception handling
MOONBIT_FFI_EXPORT void WASMOON_GUEST_ABI wasmoon_jit_exception_spill_locals(int64_t ctx_ptr,
                                                            int64_t locals_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *locals = (int64_t *)locals_ptr;
    exception_spill_locals_impl(ctx, locals, count);
}

MOONBIT_FFI_EXPORT int64_t WASMOON_GUEST_ABI wasmoon_jit_exception_get_spilled_local(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_spilled_local_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_spill_locals_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_spill_locals);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_spilled_local_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_exception_get_spilled_local);
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
#if defined(_WIN32)
    return (int64_t)wasmoon_windows_guest_setjmp;
#elif defined(__GLIBC__)
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
    if (tag >= 0 && tag < ctx_runtime(ctx)->callable_tag_count) tag = ctx_runtime(ctx)->callable_tags[tag];
    jit_context_t *active = exception_activation_context(ctx);
    int64_t reference = exception_arena_insert(exception_ensure_arena(active), ctx_gc_heap(active), tag, values, count);
    if (reference <= 0) {
        g_trap_code = (int32_t)-reference;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return reference;
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(exception_get_ref_impl);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_delegate);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_get_spilled_local);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_get_tag);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_get_value);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_get_value_count);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_spill_locals);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_throw);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_throw_ref);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_throw_tag);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_try_begin);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_exception_try_end);
#endif
