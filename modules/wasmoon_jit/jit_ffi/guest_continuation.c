#include "jit_internal.h"

// Typed continuations run only compiled guest code and C frames on fibers.
// Handles are one-shot generations; the arena owns stacks until completion or
// Store retirement, independently of the dynamic resumer.
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
} continuation_effect_t;

struct native_continuation_body {
    native_continuation_body_t *next;
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
    int started;
};

typedef struct native_continuation_arena {
    size_t references;
    size_t count;
    size_t capacity;
    native_continuation_body_t **handles;
    native_continuation_body_t *bodies;
    int sealed;
} native_continuation_arena_t;

static _Thread_local native_continuation_body_t *current_guest;
extern int64_t wasmoon_native_fiber_yield(int64_t value);
extern int64_t wasmoon_jit_context_ptr(void *context);

static void continuation_trap(int code) __attribute__((noreturn));
static void continuation_trap(int code) {
    g_trap_code = code;
    siglongjmp(g_trap_jmp_buf, 1);
}

struct native_continuation_arena *continuation_arena_new(void) {
    native_continuation_arena_t *arena = calloc(1, sizeof(*arena));
    if (arena) arena->references = 1;
    return arena;
}

static void release_body(native_continuation_body_t *body) {
    if (body->fiber) native_fiber_destroy_c(body->fiber);
    body->fiber = NULL;
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

static void release_owned_body(void *body) { release_body(body); }

static void clear_continuations(native_continuation_arena_t *arena) {
    if (!arena) return;
    // Cancellation scopes may reference other bodies in the same arena.
    // Release all resources before freeing any identity record.
    for (native_continuation_body_t *body = arena->bodies; body; body = body->next)
        release_body(body);
    while (arena->bodies) {
        native_continuation_body_t *next = arena->bodies->next;
        free(arena->bodies);
        arena->bodies = next;
    }
    free(arena->handles);
    arena->handles = NULL;
    arena->count = arena->capacity = 0;
    arena->sealed = 1;
}

void continuation_arena_release(native_continuation_arena_t *arena) {
    if (arena && --arena->references == 0) {
        clear_continuations(arena);
        free(arena);
    }
}

void continuation_types_free(jit_context_t *ctx) {
    native_continuation_type_t *type = ctx->continuation_types;
    while (type) {
        native_continuation_type_t *next = type->next;
        free(type->roots);
        free(type);
        type = next;
    }
    ctx->continuation_types = NULL;
}

static int64_t publish_continuation(native_continuation_arena_t *arena,
    native_continuation_body_t *body) {
    if (!arena || arena->sealed) continuation_trap(8);
    if (arena->count == arena->capacity) {
        size_t capacity = arena->capacity ? arena->capacity * 2 : 16;
        if (capacity > INT32_MAX) continuation_trap(9);
        void *handles = realloc(arena->handles, capacity * sizeof(*arena->handles));
        if (!handles) continuation_trap(9);
        arena->handles = handles;
        arena->capacity = capacity;
    }
    arena->handles[arena->count] = body;
    // Native generations occupy the negative half of the opaque reference
    // namespace; interpreter handles cannot accidentally select a native body.
    return -1 - ((int64_t)arena->count++ << 1);
}

static native_continuation_body_t *take_continuation(jit_context_t *ctx, int64_t reference) {
    native_continuation_arena_t *arena = ctx->continuation_arena;
    if (!reference) continuation_trap(14);
    if (!arena || reference > 0 || !(reference & 1)) continuation_trap(CONT_CONSUMED);
    uint64_t index = (uint64_t)(-(reference + 1)) >> 1;
    if (index >= arena->count) continuation_trap(CONT_CONSUMED);
    native_continuation_body_t *body = arena->handles[index];
    if (!body) continuation_trap(CONT_CONSUMED);
    arena->handles[index] = NULL;
    return body;
}

static int32_t global_tag(jit_context_t *ctx, int32_t tag) {
    return tag >= 0 && tag < ctx->callable_tag_count ? ctx->callable_tags[tag] : tag;
}

static void bind_values(native_continuation_body_t *body, const int64_t *values, int32_t count) {
    if (count < 0 || body->bound > body->type->params - count) continuation_trap(8);
    if (count) memcpy(body->values + body->bound, values, (size_t)count * sizeof(int64_t));
    if (body->roots) {
        for (int i = 0; i < count; ++i) {
            int slot = body->bound + i;
            body->roots[slot] = body->type->roots[slot] ? values[i] : 0;
        }
    }
    body->bound += count;
}

static int64_t continuation_entry(void *closure) {
    native_continuation_body_t *body = closure;
    int slots = body->type->params + body->type->results;
    return wasmoon_jit_call_trampoline_caught(body->type->trampoline,
        (int64_t)body->context, body->function, body->values, slots, &body->thrown_exception);
}

static int64_t continuation_new(jit_context_t *ctx, int32_t index, int64_t function) {
    if (!function) continuation_trap(14);
    native_continuation_type_t *type = ctx->continuation_types;
    while (type && type->index != index) type = type->next;
    if (!type || !ctx->continuation_arena || ctx->continuation_arena->sealed) continuation_trap(8);
    native_continuation_body_t *body = calloc(1, sizeof(*body));
    if (!body) continuation_trap(9);
    body->context = ctx;
    body->type = type;
    body->function = function & ~(INT64_C(1) << 61);
    int slots = type->params + type->results;
    body->values = calloc(slots ? slots : 1, sizeof(int64_t));
    if (!body->values) { free(body); continuation_trap(9); }
    if (type->params && ctx->gc_heap) {
        if (!gc_heap_register_parked_roots(ctx->gc_heap, type->params,
                &body->root_registration, &body->roots)) {
            free(body->values); free(body); continuation_trap(9);
        }
        memset(body->roots, 0, (size_t)type->params * sizeof(int64_t));
    }
    body->next = ctx->continuation_arena->bodies;
    ctx->continuation_arena->bodies = body;
    return publish_continuation(ctx->continuation_arena, body);
}

static int64_t continuation_bind(jit_context_t *ctx, int32_t input_type, int64_t reference,
    const int64_t *values, int32_t count) {
    native_continuation_body_t *body = take_continuation(ctx, reference);
    if (body->started) {
        native_continuation_type_t *type = ctx->continuation_types;
        while (type && type->index != input_type) type = type->next;
        if (!type || count < 0 || count > type->params) continuation_trap(8);
        void *registration = NULL;
        int64_t *roots = NULL;
        int total = body->input_count + count;
        if (total && ctx->gc_heap) {
            if (!gc_heap_register_parked_roots(ctx->gc_heap, total, &registration, &roots))
                continuation_trap(9);
            for (int i = 0; i < body->input_count; ++i)
                roots[i] = body->input_roots ? body->input_roots[i] : 0;
            for (int i = 0; i < count; ++i)
                roots[body->input_count + i] = type->roots[i] ? values[i] : 0;
        }
        gc_heap_unregister_parked_roots(body->input_root_registration);
        body->input_root_registration = registration;
        body->input_roots = roots;
        // A suspended continuation's parameters are its suspension results.
        int64_t *input = malloc((size_t)(body->input_count + count) * sizeof(int64_t));
        if ((body->input_count + count) && !input) continuation_trap(9);
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count += count;
    } else bind_values(body, values, count);
    return publish_continuation(ctx->continuation_arena, body);
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

static void continuation_suspend(jit_context_t *ctx, int32_t tag,
    const int64_t *values, int32_t count, int64_t *outputs, int32_t output_count) {
    if (!current_guest) continuation_trap(CONT_UNHANDLED);
    current_guest->effect = (continuation_effect_t){0, global_tag(ctx, tag), values, count, NULL};
    if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
    deliver_input(current_guest, outputs, output_count);
}

static void continuation_switch(jit_context_t *ctx, int32_t tag, int64_t reference,
    const int64_t *values, int32_t count, int64_t *outputs, int32_t output_count) {
    native_continuation_body_t *target = take_continuation(ctx, reference);
    if (!current_guest) continuation_trap(CONT_UNHANDLED);
    current_guest->effect = (continuation_effect_t){1, global_tag(ctx, tag), values, count, target};
    if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
    deliver_input(current_guest, outputs, output_count);
}

static void prepare_resume(native_continuation_body_t *body,
    const int64_t *values, int32_t count, int64_t exception) {
    if (!body->started) {
        bind_values(body, values, count);
        if (body->bound != body->type->params && !exception) continuation_trap(8);
        body->fiber = native_fiber_alloc_c(continuation_entry, body, native_fiber_stack_size_c());
        if (!body->fiber) continuation_trap(9);
        body->started = 1;
    } else {
        int total = body->input_count + count;
        int64_t *input = total ? malloc((size_t)total * sizeof(int64_t)) : NULL;
        if (total && !input) continuation_trap(9);
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count = total;
    }
    body->input_exception = exception;
}

static int32_t continuation_resume(jit_context_t *ctx, int64_t reference,
    const int64_t *values, int32_t count, const int64_t *handlers, int32_t handler_count,
    int64_t *outputs, int32_t exception_tag) {
    native_continuation_body_t *body = take_continuation(ctx, reference);
    int64_t exception = 0;
    if (exception_tag == -1) {
        if (count != 1) continuation_trap(8);
        exception = values[0];
        if (!exception) continuation_trap(14);
    } else if (exception_tag >= 0) {
        exception = exception_capture_payload(ctx, exception_tag, values, count);
    }
    if (!body->started && exception) {
        release_body(body);
        exception_throw_ref_impl(ctx, exception);
    }
    void *ownership = native_fiber_own_resource(body, release_owned_body);
    prepare_resume(body, values, exception ? 0 : count, exception);
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
            native_fiber_disown_resource(ownership);
            release_body(body);
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
            int64_t saved = publish_continuation(ctx->continuation_arena, body);
            if (!effect.switching) {
                int64_t *region = outputs + handlers[matched * 3 + 2];
                if (effect.count) memcpy(region, effect.values, (size_t)effect.count * sizeof(int64_t));
                region[effect.count] = saved;
                native_fiber_disown_resource(ownership);
                return matched;
            }
            int64_t *input = malloc((size_t)(effect.count + 1) * sizeof(int64_t));
            if (!input) continuation_trap(9);
            if (effect.count) memcpy(input, effect.values, (size_t)effect.count * sizeof(int64_t));
            input[effect.count] = saved;
            body = effect.target;
            native_fiber_replace_resource(ownership, body);
            prepare_resume(body, input, effect.count + 1, 0);
            free(input);
            continue;
        }
        if (!current_guest) continuation_trap(CONT_UNHANDLED);
        current_guest->effect = effect;
        if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
        prepare_resume(body, current_guest->input, current_guest->input_count, current_guest->input_exception);
        free(current_guest->input);
        current_guest->input = NULL;
        current_guest->input_count = 0;
        current_guest->input_exception = 0;
        gc_heap_unregister_parked_roots(current_guest->input_root_registration);
        current_guest->input_root_registration = NULL;
        current_guest->input_roots = NULL;
    }
}

static void finalize_continuation_arena(void *owner) {
    continuation_arena_release(*(native_continuation_arena_t **)owner);
}
MOONBIT_FFI_EXPORT void *wasmoon_continuation_arena_new(void) {
    native_continuation_arena_t **owner = moonbit_make_external_object(finalize_continuation_arena, sizeof(*owner));
    *owner = continuation_arena_new();
    return owner;
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_arena_clear(void *owner) {
    clear_continuations(*(native_continuation_arena_t **)owner);
}
MOONBIT_FFI_EXPORT void wasmoon_continuation_arena_bind(void *context, void *owner) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    native_continuation_arena_t *arena = *(native_continuation_arena_t **)owner;
    if (ctx && arena != ctx->continuation_arena) {
        if (arena) ++arena->references;
        continuation_arena_release(ctx->continuation_arena);
        ctx->continuation_arena = arena;
    }
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_define_type(void *context, int32_t index,
    int64_t trampoline, int32_t params, int32_t results, const int32_t *roots) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (!ctx || params < 0 || results < 0) return 0;
    native_continuation_type_t *type = calloc(1, sizeof(*type));
    if (!type) return 0;
    type->index = index;
    type->params = params;
    type->results = results;
    type->trampoline = trampoline;
    if (params) {
        type->roots = malloc((size_t)params * sizeof(int32_t));
        if (!type->roots) { free(type); return 0; }
        memcpy(type->roots, roots, (size_t)params * sizeof(int32_t));
    }
    type->next = ctx->continuation_types;
    ctx->continuation_types = type;
    return 1;
}
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_new_ptr(void) { return (int64_t)continuation_new; }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_bind_ptr(void) { return (int64_t)continuation_bind; }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_suspend_ptr(void) { return (int64_t)continuation_suspend; }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_resume_ptr(void) { return (int64_t)continuation_resume; }
MOONBIT_FFI_EXPORT int64_t wasmoon_cont_switch_ptr(void) { return (int64_t)continuation_switch; }
