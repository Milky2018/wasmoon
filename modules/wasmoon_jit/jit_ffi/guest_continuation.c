#include "jit_internal.h"

// Typed continuations run only compiled guest code and C frames on fibers.
// Handles are one-shot generations. Reachable handles own paused stacks;
// active resumers own stacks through their cancellation scopes.
#define CONT_EVENT 6001
#define CONT_CONSUMED WASMOON_TRAP_CONTINUATION_CONSUMED
#define CONT_UNHANDLED WASMOON_TRAP_UNHANDLED_SUSPENSION

typedef struct native_continuation_type {
    int32_t index;
    int32_t params;
    int32_t results;
    int64_t trampoline;
    int32_t *roots;
    struct native_continuation_type *next;
} native_continuation_type_t;

typedef struct native_continuation_body native_continuation_body_t;

typedef struct {
    int32_t switching;
    int32_t tag;
    const int64_t *values;
    int32_t count;
    native_continuation_body_t *target;
    void *target_scope;
} continuation_effect_t;

struct native_continuation_body {
    struct native_continuation_arena *arena;
    jit_context_t *context;
    native_continuation_type_t *type;
    void *fiber;
    int64_t function;
    int64_t *values;
    int32_t bound;
    int64_t *input;
    int32_t input_count;
    int64_t input_exception;
    void *input_root_registration;
    int64_t *input_roots;
    int64_t thrown_exception;
    void *root_registration;
    int64_t *roots;
    continuation_effect_t effect;
    wasmoon_quota_t *pending_quota;
};

// Storage owns physical bodies. Only MoonBit assigns identities or decides which
// bodies to retire. Scope pins retain a body directly, independently of storage.
typedef struct {
    native_continuation_body_t **bodies;
    int32_t count;
    int32_t capacity;
} continuation_storage_t;

typedef struct {
    jit_context_t *context;
    native_continuation_type_t *type;
    int64_t function;
} continuation_create_request_t;

typedef struct {
    int64_t (*create)(void *, continuation_create_request_t *);
    int64_t (*publish)(void *, int64_t);
    int64_t (*take)(void *, int64_t);
    void (*mark)(void *, int64_t);
    int32_t (*marked_count)(void *);
    void (*copy_marked)(void *, int64_t *);
    void (*reset_marks)(void *);
    void (*sweep)(void *, int64_t);
} continuation_callbacks_t;

typedef struct native_continuation_arena {
    void *state;
    continuation_callbacks_t *callbacks;
} native_continuation_arena_t;

static _Thread_local native_continuation_body_t *current_guest;
extern int64_t wasmoon_native_fiber_yield(int64_t value);
extern int64_t wasmoon_jit_context_ptr(void *context);

#if defined(_MSC_VER) && !defined(__clang__)
__declspec(noreturn) static void continuation_trap(int code);
#else
static void continuation_trap(int code) __attribute__((noreturn));
#endif
static void continuation_trap(int code) {
    g_trap_code = code;
    siglongjmp(g_trap_jmp_buf, 1);
}

static void release_body(native_continuation_body_t *body) {
    void *fiber = body->fiber;
    body->fiber = NULL;
    if (fiber) native_fiber_destroy_c(fiber);
    gc_heap_unregister_parked_roots(body->root_registration);
    body->root_registration = NULL;
    body->roots = NULL;
    free(body->values);
    body->values = NULL;
    free(body->input);
    body->input = NULL;
    gc_heap_unregister_parked_roots(body->input_root_registration);
    body->input_root_registration = NULL;
    body->input_roots = NULL;
}

static void finalize_body(void *opaque) {
    native_continuation_body_t *body = opaque;
    release_body(body);
    if (body->pending_quota) {
        wasmoon_quota_release(body->pending_quota, 1);
        moonbit_decref(body->pending_quota);
    }
}

static void release_owned_body(void *opaque) {
    release_body(opaque);
    moonbit_decref(opaque);
}

static void *pin_body(native_continuation_body_t *body) {
    moonbit_incref(body);
    void *scope = native_fiber_own_resource(body, release_owned_body);
    if (!scope) moonbit_decref(body);
    return scope;
}

static void close_resumer(native_continuation_body_t *body, void *scope) {
    native_fiber_disown_resource(scope);
    release_body(body);
    if (scope) moonbit_decref(body);
}

static void clear_storage(continuation_storage_t *storage) {
    // A stack's cancellation scopes can pin another body in this table.
    // Close every physical resource before dropping any table-owned body.
    for (int32_t i = 0; i < storage->count; ++i)
        if (storage->bodies[i]) release_body(storage->bodies[i]);
    for (int32_t i = 0; i < storage->count; ++i)
        if (storage->bodies[i]) moonbit_decref(storage->bodies[i]);
    free(storage->bodies);
    storage->bodies = NULL;
    storage->count = storage->capacity = 0;
}

static void finalize_storage(void *opaque) { clear_storage(opaque); }

MOONBIT_FFI_EXPORT continuation_storage_t *wasmoon_continuation_storage_new(void) {
    continuation_storage_t *storage = moonbit_make_external_object(finalize_storage, sizeof(*storage));
    memset(storage, 0, sizeof(*storage));
    return storage;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_storage_clear(continuation_storage_t *storage) { clear_storage(storage); }
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_storage_count(continuation_storage_t *storage) { return storage->count; }
MOONBIT_FFI_EXPORT int64_t wasmoon_continuation_storage_body(continuation_storage_t *storage, int32_t index) {
    return index >= 0 && index < storage->count ? (int64_t)(uintptr_t)storage->bodies[index] : 0;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_storage_move(continuation_storage_t *storage, int32_t from, int32_t to) {
    if (from == to || from < 0 || to < 0 || from >= storage->count || to >= storage->count) return;
    if (storage->bodies[to]) moonbit_decref(storage->bodies[to]);
    storage->bodies[to] = storage->bodies[from];
    storage->bodies[from] = NULL;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_storage_truncate(continuation_storage_t *storage, int32_t count) {
    if (count < 0 || count > storage->count) return;
    for (int32_t i = count; i < storage->count; ++i)
        if (storage->bodies[i]) moonbit_decref(storage->bodies[i]);
    storage->count = count;
    if (!count) { free(storage->bodies); storage->bodies = NULL; storage->capacity = 0; }
    else if (count <= storage->capacity / 4) {
        void *bodies = realloc(storage->bodies, (size_t)count * sizeof(*storage->bodies));
        if (bodies) { storage->bodies = bodies; storage->capacity = count; }
    }
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_body_available(int64_t address) {
    native_continuation_body_t *body = (void *)(uintptr_t)address;
    return body && body->values != NULL;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_body_close(int64_t address) { release_body((void *)(uintptr_t)address); }
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_body_on_heap(int64_t address, int64_t heap) {
    native_continuation_body_t *body = (void *)(uintptr_t)address;
    return gc_heap_registration_heap(body->root_registration) == (GcHeap *)(uintptr_t)heap ||
        gc_heap_registration_heap(body->input_root_registration) == (GcHeap *)(uintptr_t)heap ||
        gc_heap_registration_heap(native_fiber_gc_roots_c(body->fiber)) == (GcHeap *)(uintptr_t)heap;
}

void continuation_arena_release(native_continuation_arena_t *arena) { if (arena) moonbit_decref(arena); }

void continuation_types_free(jit_context_t *ctx) {
    native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
    while (type) {
        native_continuation_type_t *next = type->next;
        free(type->roots);
        free(type);
        type = next;
    }
    ctx_runtime(ctx)->continuation_types = NULL;
}

static int32_t bind_body_roots(native_continuation_arena_t *arena, native_continuation_body_t *body, int64_t reference) {
    void *registrations[] = { body->root_registration, body->input_root_registration,
        native_fiber_gc_roots_c(body->fiber) };
    for (size_t i = 0; i < sizeof(registrations) / sizeof(registrations[0]); ++i) {
        if (registrations[i]) {
            if (!gc_heap_bind_continuation_roots(registrations[i], arena,
                    gc_heap_registration_heap(registrations[i])->precise_roots ? reference : 0))
                return 0;
        }
    }
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_body_bind_roots(int64_t address, int64_t reference) {
    native_continuation_body_t *body = (void *)(uintptr_t)address;
    return bind_body_roots(body->arena, body, reference);
}
WASMOON_NO_FUNCTION_SANITIZE void continuation_arena_mark(native_continuation_arena_t *arena, int64_t reference) {
    if (arena) arena->callbacks->mark(arena->state, reference);
}
WASMOON_NO_FUNCTION_SANITIZE int32_t continuation_arena_marked_count(native_continuation_arena_t *arena) {
    return arena ? arena->callbacks->marked_count(arena->state) : 0;
}
WASMOON_NO_FUNCTION_SANITIZE void continuation_arena_copy_marked(native_continuation_arena_t *arena, int64_t *roots) {
    if (arena) arena->callbacks->copy_marked(arena->state, roots);
}
WASMOON_NO_FUNCTION_SANITIZE void continuation_arena_reset_marks(native_continuation_arena_t *arena) {
    if (arena) arena->callbacks->reset_marks(arena->state);
}
WASMOON_NO_FUNCTION_SANITIZE void continuation_arena_sweep(native_continuation_arena_t *arena, GcHeap *heap) {
    if (arena) arena->callbacks->sweep(arena->state, (int64_t)(uintptr_t)heap);
}

MOONBIT_FFI_EXPORT int64_t *wasmoon_continuation_body_gc_roots(int64_t address) {
    native_continuation_body_t *body = (void *)(uintptr_t)address;
    if (!body) return moonbit_make_int64_array(0, 0);
    void *registrations[] = { body->root_registration, body->input_root_registration,
        native_fiber_gc_roots_c(body->fiber) };
    int32_t count = body->input_exception ? 1 : 0;
    for (size_t i = 0; i < sizeof(registrations) / sizeof(registrations[0]); ++i)
        count += gc_heap_registered_root_count(registrations[i]);
    int64_t *roots = moonbit_make_int64_array(count, 0);
    int32_t at = 0;
    if (body->input_exception) roots[at++] = body->input_exception;
    for (size_t i = 0; i < sizeof(registrations) / sizeof(registrations[0]); ++i) {
        gc_heap_copy_registered_roots(registrations[i], roots + at);
        at += gc_heap_registered_root_count(registrations[i]);
    }
    return roots;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_root_write(int64_t *roots, int32_t index, int64_t value) { roots[index] = value; }

static WASMOON_NO_FUNCTION_SANITIZE int64_t publish_continuation(native_continuation_arena_t *arena,
    native_continuation_body_t *body) {
    if (!arena) continuation_trap(8);
    int64_t result = arena->callbacks->publish(arena->state, (int64_t)(uintptr_t)body);
    if (result >= 0) continuation_trap(result ? (int)result : 9);
    return result;
}
static WASMOON_NO_FUNCTION_SANITIZE native_continuation_body_t *take_continuation(jit_context_t *ctx, int64_t reference) {
    native_continuation_arena_t *arena = ctx_runtime(ctx)->continuation_arena;
    if (!reference) continuation_trap(14);
    if (!arena) continuation_trap(CONT_CONSUMED);
    int64_t result = arena->callbacks->take(arena->state, reference);
    if (result <= 0) continuation_trap(result ? (int)-result : CONT_CONSUMED);
    native_continuation_body_t *body = (void *)(uintptr_t)result;
    if (!bind_body_roots(arena, body, 0)) { release_body(body); continuation_trap(8); }
    return body;
}

static int32_t global_tag(jit_context_t *ctx, int32_t tag) {
    return tag >= 0 && tag < ctx_runtime(ctx)->callable_tag_count ? ctx_runtime(ctx)->callable_tags[tag] : tag;
}

static int bind_values(native_continuation_body_t *body, const int64_t *values, int32_t count) {
    if (count < 0 || count > body->type->params || body->bound > body->type->params - count) return 8;
    if (count) memcpy(body->values + body->bound, values, (size_t)count * sizeof(int64_t));
    if (body->roots) {
        for (int i = 0; i < count; ++i) {
            int slot = body->bound + i;
            body->roots[slot] = body->type->roots[slot] ? values[i] : 0;
        }
    }
    body->bound += count;
    return 0;
}

static int64_t continuation_entry(void *closure) {
    native_continuation_body_t *body = closure;
    int slots = body->type->params + body->type->results;
    return wasmoon_jit_call_trampoline_caught(body->type->trampoline,
        (int64_t)body->context, body->function, body->values, slots, &body->thrown_exception);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_continuation_storage_create(continuation_storage_t *storage,
    continuation_create_request_t *request, wasmoon_quota_t *quota) {
    if (storage->count == storage->capacity) {
        size_t capacity = storage->capacity ? (size_t)storage->capacity * 2 : 16;
        if (capacity > INT32_MAX || capacity > SIZE_MAX / sizeof(*storage->bodies)) return 0;
        void *bodies = wasmoon_native_realloc(storage->bodies, capacity * sizeof(*storage->bodies));
        if (!bodies) return 0;
        storage->bodies = bodies;
        storage->capacity = (int32_t)capacity;
    }
    native_continuation_body_t *body = moonbit_make_external_object(finalize_body, sizeof(*body));
    memset(body, 0, sizeof(*body));
    body->arena = ctx_runtime(request->context)->continuation_arena;
    body->context = request->context;
    body->type = request->type;
    body->function = request->function & ~(INT64_C(1) << 61);
    int slots = body->type->params + body->type->results;
    body->values = wasmoon_native_calloc(slots ? slots : 1, sizeof(int64_t));
    if (!body->values) { moonbit_decref(body); return 0; }
    GcHeap *heap = ctx_gc_heap(request->context);
    if (heap) {
        int32_t roots = body->type->params ? body->type->params : 1;
        if (!gc_heap_register_parked_roots(heap, roots, &body->root_registration, &body->roots)) {
            moonbit_decref(body); return 0;
        }
        memset(body->roots, 0, (size_t)roots * sizeof(int64_t));
    }
    if (quota) moonbit_incref(quota);
    body->pending_quota = quota;
    storage->bodies[storage->count++] = body;
    return (int64_t)(uintptr_t)body;
}

static WASMOON_NO_FUNCTION_SANITIZE int64_t WASMOON_GUEST_ABI continuation_new(jit_context_t *ctx, int32_t index, int64_t function) {
    if (!function) continuation_trap(14);
    native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
    while (type && type->index != index) type = type->next;
    native_continuation_arena_t *arena = ctx_runtime(ctx)->continuation_arena;
    if (!type || !arena) continuation_trap(8);
    continuation_create_request_t request = {ctx, type, function};
    int64_t result = arena->callbacks->create(arena->state, &request);
    if (result >= 0) continuation_trap(result ? (int)result : 9);
    return result;
}

static int64_t WASMOON_GUEST_ABI continuation_bind(jit_context_t *ctx, int32_t input_type, int64_t reference,
    const int64_t *values, int32_t count) {
    native_continuation_body_t *body = take_continuation(ctx, reference);
    int code = 8;
    if (body->fiber) {
        native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
        while (type && type->index != input_type) type = type->next;
        if (!type || count < 0 || count > type->params || body->input_count > INT32_MAX - count) goto failed;
        void *registration = NULL;
        int64_t *roots = NULL;
        int total = body->input_count + count;
        if (total && ctx_gc_heap(ctx)) {
            if (!gc_heap_register_parked_roots(ctx_gc_heap(ctx), total, &registration, &roots)) {
                code = 9; goto failed;
            }
            for (int i = 0; i < body->input_count; ++i)
                roots[i] = body->input_roots ? body->input_roots[i] : 0;
            for (int i = 0; i < count; ++i)
                roots[body->input_count + i] = type->roots[i] ? values[i] : 0;
        }
        gc_heap_unregister_parked_roots(body->input_root_registration);
        body->input_root_registration = registration;
        body->input_roots = roots;
        // A suspended continuation's parameters are its suspension results.
        int64_t *input = wasmoon_native_malloc((size_t)(body->input_count + count) * sizeof(int64_t));
        if ((body->input_count + count) && !input) { code = 9; goto failed; }
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count += count;
    } else {
        code = bind_values(body, values, count);
        if (code) goto failed;
    }
    return publish_continuation(ctx_runtime(ctx)->continuation_arena, body);
failed:
    release_body(body);
    continuation_trap(code);
}

static void deliver_input(native_continuation_body_t *body, int64_t *outputs, int32_t count) {
    int64_t exception = body->input_exception;
    if (!exception && count != body->input_count) continuation_trap(8);
    if (!exception && count) memcpy(outputs, body->input, (size_t)count * sizeof(int64_t));
    free(body->input);
    body->input = NULL;
    body->input_count = 0;
    body->input_exception = 0;
    gc_heap_unregister_parked_roots(body->input_root_registration);
    body->input_root_registration = NULL;
    body->input_roots = NULL;
    if (exception) exception_throw_ref_impl(body->context, exception);
}

static void WASMOON_GUEST_ABI continuation_suspend(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int64_t *outputs, int32_t output_count) {
    if (!current_guest) continuation_trap(CONT_UNHANDLED);
    current_guest->effect = (continuation_effect_t){0, global_tag(ctx, tag), values, count, NULL, NULL};
    if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
    deliver_input(current_guest, outputs, output_count);
}

static void WASMOON_GUEST_ABI continuation_switch(jit_context_t *ctx, int32_t tag, int64_t reference,
    const int64_t *values, int32_t count, int64_t *outputs, int32_t output_count) {
    native_continuation_body_t *target = take_continuation(ctx, reference);
    if (!current_guest) { release_body(target); continuation_trap(CONT_UNHANDLED); }
    void *scope = pin_body(target);
    current_guest->effect = (continuation_effect_t){1, global_tag(ctx, tag), values, count, target, scope};
    if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
    deliver_input(current_guest, outputs, output_count);
}

static int prepare_resume(native_continuation_body_t *body,
    const int64_t *values, int32_t count, int64_t exception) {
    if (!body->fiber) {
        int code = bind_values(body, values, count);
        if (code) return code;
        if (body->bound != body->type->params && !exception) return 8;
        body->fiber = native_fiber_alloc_c(continuation_entry, body, native_fiber_stack_size_c());
        if (!body->fiber) return 9;
    } else {
        if (count < 0 || body->input_count > INT32_MAX - count) return 8;
        int total = body->input_count + count;
        int64_t *input = total ? wasmoon_native_malloc((size_t)total * sizeof(int64_t)) : NULL;
        if (total && !input) return 9;
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count = total;
    }
    body->input_exception = exception;
    return 0;
}

static int32_t WASMOON_GUEST_ABI continuation_resume(jit_context_t *ctx, int64_t reference,
    const int64_t *values, int32_t count, const int64_t *handlers, int32_t handler_count,
    int64_t *outputs, int32_t exception_tag) {
    native_continuation_body_t *body = take_continuation(ctx, reference);
    void *ownership = pin_body(body);
    int prepare_error = 0;
    int64_t exception = 0;
    if (exception_tag == -1) {
        if (count != 1) prepare_error = 8;
        else { exception = values[0]; if (!exception) prepare_error = 14; }
    } else if (exception_tag >= 0) {
        exception = exception_try_capture_payload(ctx, exception_tag, values, count);
        if (exception <= 0) prepare_error = exception ? (int)-exception : 9;
    }
    if (prepare_error) { close_resumer(body, ownership); continuation_trap(prepare_error); }
    if (!body->fiber && exception) {
        close_resumer(body, ownership);
        exception_throw_ref_impl(ctx, exception);
    }
    prepare_error = prepare_resume(body, values, exception ? 0 : count, exception);
    if (prepare_error) { close_resumer(body, ownership); continuation_trap(prepare_error); }
    int64_t resume_value = 0;
    for (;;) {
        native_continuation_body_t *previous = current_guest;
        current_guest = body;
        int status = native_fiber_continue_c(body->fiber, resume_value);
        current_guest = previous;
        resume_value = 0;
        if (status == WASMOON_FIBER_ADVANCE_RETURNED) {
            int code = (int)native_fiber_result_c(body->fiber);
            int64_t thrown = body->thrown_exception;
            if (!code && body->type->results)
                memcpy(outputs, body->values + body->type->params, (size_t)body->type->results * sizeof(int64_t));
            close_resumer(body, ownership);
            if (code == 12 && thrown) exception_throw_ref_impl(ctx, thrown);
            if (code) continuation_trap(code);
            return -1;
        }
        if (status != WASMOON_FIBER_ADVANCE_SUSPENDED) continuation_trap(8);
        int64_t event = native_fiber_event_c(body->fiber);
        if (event != CONT_EVENT) {
            resume_value = wasmoon_native_fiber_yield(event);
            if (resume_value == INT64_MIN) continuation_trap(8);
            continue;
        }
        continuation_effect_t effect = body->effect;
        int matched = -1;
        for (int i = 0; i < handler_count; ++i) {
            if (global_tag(ctx, (int32_t)handlers[i * 3]) == effect.tag &&
                handlers[i * 3 + 1] == effect.switching) { matched = i; break; }
        }
        if (matched >= 0) {
            int64_t saved = publish_continuation(ctx_runtime(ctx)->continuation_arena, body);
            if (!effect.switching) {
                int64_t *region = outputs + handlers[matched * 3 + 2];
                if (effect.count) memcpy(region, effect.values, (size_t)effect.count * sizeof(int64_t));
                region[effect.count] = saved;
                native_fiber_disown_resource(ownership);
                if (ownership) moonbit_decref(body);
                return matched;
            }
            int64_t *input = wasmoon_native_malloc((size_t)(effect.count + 1) * sizeof(int64_t));
            if (!input) continuation_trap(9);
            if (effect.count) memcpy(input, effect.values, (size_t)effect.count * sizeof(int64_t));
            input[effect.count] = saved;
            if (ownership) moonbit_decref(body);
            body = effect.target;
            if (ownership) moonbit_incref(body);
            native_fiber_replace_resource(ownership, body);
            if (effect.target_scope) {
                native_fiber_disown_resource(effect.target_scope);
                moonbit_decref(body);
            }
            prepare_error = prepare_resume(body, input, effect.count + 1, 0);
            free(input);
            if (prepare_error) { close_resumer(body, ownership); continuation_trap(prepare_error); }
            continue;
        }
        if (!current_guest) continuation_trap(CONT_UNHANDLED);
        current_guest->effect = effect;
        if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
        prepare_error = prepare_resume(body, current_guest->input, current_guest->input_count, current_guest->input_exception);
        free(current_guest->input);
        current_guest->input = NULL;
        current_guest->input_count = 0;
        current_guest->input_exception = 0;
        gc_heap_unregister_parked_roots(current_guest->input_root_registration);
        current_guest->input_root_registration = NULL;
        current_guest->input_roots = NULL;
        if (prepare_error) { close_resumer(body, ownership); continuation_trap(prepare_error); }
    }
}

static void finalize_continuation_arena(void *opaque) {
    native_continuation_arena_t *arena = opaque;
    if (arena->state) moonbit_decref(arena->state);
    free(arena->callbacks);
}
MOONBIT_FFI_EXPORT native_continuation_arena_t *wasmoon_continuation_arena_new(
    void *state, int64_t (*create)(void *, continuation_create_request_t *),
    int64_t (*publish)(void *, int64_t), int64_t (*take)(void *, int64_t),
    void (*mark)(void *, int64_t), int32_t (*marked_count)(void *),
    void (*copy_marked)(void *, int64_t *), void (*reset_marks)(void *),
    void (*sweep)(void *, int64_t)) {
    native_continuation_arena_t *arena = moonbit_make_external_object(finalize_continuation_arena, sizeof(*arena));
    memset(arena, 0, sizeof(*arena));
    arena->callbacks = wasmoon_native_malloc(sizeof(*arena->callbacks));
    if (arena->callbacks) {
        *arena->callbacks = (continuation_callbacks_t){create,publish,take,mark,marked_count,copy_marked,reset_marks,sweep};
        moonbit_incref(state);
        arena->state = state;
    }
    return arena;
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_arena_is_available(native_continuation_arena_t *arena) {
    return arena && arena->callbacks;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_arena_bind(void *context, native_continuation_arena_t *arena) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (ctx && arena != ctx_runtime(ctx)->continuation_arena) {
        if (arena) moonbit_incref(arena);
        continuation_arena_release(ctx_runtime(ctx)->continuation_arena);
        ctx_runtime(ctx)->continuation_arena = arena;
    }
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_arena_is_bound(void *context) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    return ctx && ctx_runtime(ctx)->continuation_arena != NULL;
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_define_type(void *context, int32_t index,
    int64_t trampoline, int32_t params, int32_t results, const int32_t *roots) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (!ctx || params < 0 || results < 0 || !ctx_runtime(ctx)->continuation_arena) return 0;
    native_continuation_type_t *type = wasmoon_native_calloc(1, sizeof(*type));
    if (!type) return 0;
    type->index = index;
    type->params = params;
    type->results = results;
    type->trampoline = trampoline;
    if (params) {
        type->roots = wasmoon_native_malloc((size_t)params * sizeof(int32_t));
        if (!type->roots) { free(type); return 0; }
        memcpy(type->roots, roots, (size_t)params * sizeof(int32_t));
    }
    type->next = ctx_runtime(ctx)->continuation_types;
    ctx_runtime(ctx)->continuation_types = type;
    return 1;
}
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_new_ptr(void) { return WASMOON_GUEST_ADDRESS(continuation_new); }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_bind_ptr(void) { return WASMOON_GUEST_ADDRESS(continuation_bind); }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_suspend_ptr(void) { return WASMOON_GUEST_ADDRESS(continuation_suspend); }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_resume_ptr(void) { return WASMOON_GUEST_ADDRESS(continuation_resume); }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_switch_ptr(void) { return WASMOON_GUEST_ADDRESS(continuation_switch); }

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(continuation_bind);
WASMOON_DEFINE_GUEST_TARGET(continuation_new);
WASMOON_DEFINE_GUEST_TARGET(continuation_resume);
WASMOON_DEFINE_GUEST_TARGET(continuation_suspend);
WASMOON_DEFINE_GUEST_TARGET(continuation_switch);
#endif
