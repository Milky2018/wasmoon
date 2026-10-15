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
} continuation_effect_t;

struct native_continuation_body {
    native_continuation_body_t *next;
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
    int started;
    int marked;
    int resource_references;
};

typedef struct { int64_t reference; native_continuation_body_t *body; } native_continuation_handle_t;

typedef struct native_continuation_arena {
    size_t references;
    size_t count;
    size_t capacity;
    int64_t next_reference;
    native_continuation_handle_t *handles;
    native_continuation_body_t *bodies;
    int sealed;
    GcHeap *heap; // Borrowed while bodies own root registrations
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

struct native_continuation_arena *continuation_arena_new(void) {
    native_continuation_arena_t *arena = wasmoon_native_calloc(1, sizeof(*arena));
    if (arena) arena->references = 1;
    return arena;
}

static void release_body(native_continuation_body_t *body) {
    if (body->fiber) native_fiber_destroy_c(body->fiber);
    body->fiber = NULL;
    GcHeap *heap = gc_heap_registration_heap(body->root_registration);
    if (!heap) heap = gc_heap_registration_heap(body->input_root_registration);
    if (heap && body->arena) {
        int other_roots = 0;
        for (native_continuation_body_t *other = body->arena->bodies; other; other = other->next) {
            if (other != body && (gc_heap_registration_heap(other->root_registration) == heap ||
                gc_heap_registration_heap(other->input_root_registration) == heap)) { other_roots = 1; break; }
        }
        // Detach the borrowed arena before dropping its final heap owner.
        if (!other_roots) { heap->continuation_arena = NULL; body->arena->heap = NULL; }
    }
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

static void release_owned_body(void *opaque) {
    native_continuation_body_t *body = opaque;
    release_body(body);
    --body->resource_references;
}

static void clear_continuations(native_continuation_arena_t *arena) {
    if (!arena) return;
    if (arena->heap && arena->heap->continuation_arena == arena)
        arena->heap->continuation_arena = NULL;
    arena->heap = NULL;
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
    native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
    while (type) {
        native_continuation_type_t *next = type->next;
        free(type->roots);
        free(type);
        type = next;
    }
    ctx_runtime(ctx)->continuation_types = NULL;
}

static native_continuation_body_t *find_continuation(native_continuation_arena_t *arena, int64_t reference) {
    if (!arena || reference >= 0 || !(reference & 1)) return NULL;
    size_t low = 0, high = arena->count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (arena->handles[middle].reference > reference) low = middle + 1;
        else high = middle;
    }
    return low < arena->count && arena->handles[low].reference == reference ? arena->handles[low].body : NULL;
}

static void bind_body_roots(native_continuation_arena_t *arena, native_continuation_body_t *body, int64_t reference) {
    void *registrations[] = { body->root_registration, body->input_root_registration,
        native_fiber_gc_roots_c(body->fiber) };
    for (size_t i = 0; i < sizeof(registrations) / sizeof(registrations[0]); ++i) {
        if (registrations[i]) {
            if (!gc_heap_bind_continuation_roots(registrations[i], arena,
                    gc_heap_registration_heap(registrations[i])->root_visitor ? reference : 0))
                continuation_trap(8);
            arena->heap = gc_heap_registration_heap(registrations[i]);
        }
    }
}

void continuation_arena_mark(native_continuation_arena_t *arena, int64_t reference) {
    native_continuation_body_t *body = find_continuation(arena, reference);
    if (body) body->marked = 1;
}

int32_t continuation_arena_marked_count(native_continuation_arena_t *arena) {
    int32_t count = 0;
    if (arena) for (size_t i = 0; i < arena->count; ++i)
        if (arena->handles[i].body && arena->handles[i].body->marked) ++count;
    return count;
}

void continuation_arena_copy_marked(native_continuation_arena_t *arena, int64_t *roots) {
    if (arena) for (size_t i = 0; i < arena->count; ++i)
        if (arena->handles[i].body && arena->handles[i].body->marked) *roots++ = arena->handles[i].reference;
}

void continuation_arena_reset_marks(native_continuation_arena_t *arena) {
    if (arena) for (size_t i = 0; i < arena->count; ++i)
        if (arena->handles[i].body) arena->handles[i].body->marked = 0;
}

static void reclaim_retired_continuations(native_continuation_arena_t *arena) {
    if (!arena) return;
    size_t retained = 0;
    for (size_t i = 0; i < arena->count; ++i) {
        if (arena->handles[i].body) arena->handles[retained++] = arena->handles[i];
    }
    arena->count = retained;
    if (!retained) { free(arena->handles); arena->handles = NULL; arena->capacity = 0; }
    native_continuation_body_t **link = &arena->bodies;
    int has_roots = 0;
    while (*link) {
        native_continuation_body_t *body = *link;
        if (!body->values && !body->fiber && !body->resource_references) {
            *link = body->next;
            free(body);
        } else {
            has_roots |= body->root_registration != NULL || body->input_root_registration != NULL;
            link = &body->next;
        }
    }
    if (!has_roots && arena->heap) { arena->heap->continuation_arena = NULL; arena->heap = NULL; }
}

MOONBIT_FFI_EXPORT void wasmoon_continuation_arena_reclaim_retired(void *owner) {
    reclaim_retired_continuations(*(native_continuation_arena_t **)owner);
}

void continuation_arena_sweep(native_continuation_arena_t *arena) {
    if (!arena || !arena->heap || !arena->heap->root_visitor) return;
    size_t retained = 0;
    for (size_t i = 0; i < arena->count; ++i) {
        native_continuation_handle_t handle = arena->handles[i];
        native_continuation_body_t *body = handle.body;
        if (!body) continue;
        if (body->marked) { body->marked = 0; arena->handles[retained++] = handle; }
        else release_body(body);
    }
    arena->count = retained;
    if (!retained) { free(arena->handles); arena->handles = NULL; arena->capacity = 0; }

}

MOONBIT_FFI_EXPORT int64_t *wasmoon_continuation_arena_gc_roots(void *owner, int64_t reference) {
    native_continuation_arena_t *arena = *(native_continuation_arena_t **)owner;
    native_continuation_body_t *body = find_continuation(arena, reference);
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

static int64_t publish_continuation(native_continuation_arena_t *arena,
    native_continuation_body_t *body) {
    if (!arena || arena->sealed) continuation_trap(8);
    if (arena->count == arena->capacity) {
        size_t capacity = arena->capacity ? arena->capacity * 2 : 16;
        if (capacity > INT32_MAX) continuation_trap(9);
        void *handles = wasmoon_native_realloc(arena->handles, capacity * sizeof(*arena->handles));
        if (!handles) continuation_trap(9);
        arena->handles = handles;
        arena->capacity = capacity;
    }
    if (arena->next_reference == INT32_MAX) continuation_trap(9);
    // References decrease monotonically, independently of the compact live table.
    int64_t reference = -1 - (arena->next_reference++ << 1);
    arena->handles[arena->count++] = (native_continuation_handle_t){ reference, body };
    bind_body_roots(arena, body, reference);
    return reference;
}

static native_continuation_body_t *take_continuation(jit_context_t *ctx, int64_t reference) {
    native_continuation_arena_t *arena = ctx_runtime(ctx)->continuation_arena;
    if (!reference) continuation_trap(14);
    if (!arena || reference > 0 || !(reference & 1)) continuation_trap(CONT_CONSUMED);
    native_continuation_body_t *body = find_continuation(arena, reference);
    if (!body) continuation_trap(CONT_CONSUMED);
    for (size_t i = 0; i < arena->count; ++i) {
        if (arena->handles[i].reference == reference) { arena->handles[i].body = NULL; break; }
    }
    bind_body_roots(arena, body, 0);
    return body;
}

static int32_t global_tag(jit_context_t *ctx, int32_t tag) {
    return tag >= 0 && tag < ctx_runtime(ctx)->callable_tag_count ? ctx_runtime(ctx)->callable_tags[tag] : tag;
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

static int64_t WASMOON_GUEST_ABI continuation_new(jit_context_t *ctx, int32_t index, int64_t function) {
    if (!function) continuation_trap(14);
    native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
    while (type && type->index != index) type = type->next;
    if (!type || !ctx_runtime(ctx)->continuation_arena || ctx_runtime(ctx)->continuation_arena->sealed) continuation_trap(8);
    native_continuation_body_t *body = wasmoon_native_calloc(1, sizeof(*body));
    if (!body) continuation_trap(9);
    body->arena = ctx_runtime(ctx)->continuation_arena;
    body->context = ctx;
    body->type = type;
    body->function = function & ~(INT64_C(1) << 61);
    int slots = type->params + type->results;
    body->values = wasmoon_native_calloc(slots ? slots : 1, sizeof(int64_t));
    if (!body->values) { free(body); continuation_trap(9); }
    if (ctx_gc_heap(ctx)) {
        if (!gc_heap_register_parked_roots(ctx_gc_heap(ctx), type->params ? type->params : 1,
                &body->root_registration, &body->roots)) {
            free(body->values); free(body); continuation_trap(9);
        }
        memset(body->roots, 0, (size_t)(type->params ? type->params : 1) * sizeof(int64_t));
    }
    body->next = ctx_runtime(ctx)->continuation_arena->bodies;
    ctx_runtime(ctx)->continuation_arena->bodies = body;
    return publish_continuation(ctx_runtime(ctx)->continuation_arena, body);
}

static int64_t WASMOON_GUEST_ABI continuation_bind(jit_context_t *ctx, int32_t input_type, int64_t reference,
    const int64_t *values, int32_t count) {
    native_continuation_body_t *body = take_continuation(ctx, reference);
    if (body->started) {
        native_continuation_type_t *type = ctx_runtime(ctx)->continuation_types;
        while (type && type->index != input_type) type = type->next;
        if (!type || count < 0 || count > type->params) continuation_trap(8);
        void *registration = NULL;
        int64_t *roots = NULL;
        int total = body->input_count + count;
        if (total && ctx_gc_heap(ctx)) {
            if (!gc_heap_register_parked_roots(ctx_gc_heap(ctx), total, &registration, &roots))
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
        int64_t *input = wasmoon_native_malloc((size_t)(body->input_count + count) * sizeof(int64_t));
        if ((body->input_count + count) && !input) continuation_trap(9);
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count += count;
    } else bind_values(body, values, count);
    return publish_continuation(ctx_runtime(ctx)->continuation_arena, body);
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
    current_guest->effect = (continuation_effect_t){0, global_tag(ctx, tag), values, count, NULL};
    if (wasmoon_native_fiber_yield(CONT_EVENT) == INT64_MIN) continuation_trap(9);
    deliver_input(current_guest, outputs, output_count);
}

static void WASMOON_GUEST_ABI continuation_switch(jit_context_t *ctx, int32_t tag, int64_t reference,
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
        int64_t *input = total ? wasmoon_native_malloc((size_t)total * sizeof(int64_t)) : NULL;
        if (total && !input) continuation_trap(9);
        if (body->input_count) memcpy(input, body->input, (size_t)body->input_count * sizeof(int64_t));
        if (count) memcpy(input + body->input_count, values, (size_t)count * sizeof(int64_t));
        free(body->input);
        body->input = input;
        body->input_count = total;
    }
    body->input_exception = exception;
}

static int32_t WASMOON_GUEST_ABI continuation_resume(jit_context_t *ctx, int64_t reference,
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
    if (ownership) ++body->resource_references;
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
            if (ownership) --body->resource_references;
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
            int64_t saved = publish_continuation(ctx_runtime(ctx)->continuation_arena, body);
            if (!effect.switching) {
                int64_t *region = outputs + handlers[matched * 3 + 2];
                if (effect.count) memcpy(region, effect.values, (size_t)effect.count * sizeof(int64_t));
                region[effect.count] = saved;
                if (ownership) --body->resource_references;
                native_fiber_disown_resource(ownership);
                return matched;
            }
            int64_t *input = wasmoon_native_malloc((size_t)(effect.count + 1) * sizeof(int64_t));
            if (!input) continuation_trap(9);
            if (effect.count) memcpy(input, effect.values, (size_t)effect.count * sizeof(int64_t));
            input[effect.count] = saved;
            if (ownership) --body->resource_references;
            body = effect.target;
            if (ownership) ++body->resource_references;
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
    if (ctx && arena != ctx_runtime(ctx)->continuation_arena) {
        if (arena) ++arena->references;
        continuation_arena_release(ctx_runtime(ctx)->continuation_arena);
        ctx_runtime(ctx)->continuation_arena = arena;
    }
}
MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_define_type(void *context, int32_t index,
    int64_t trampoline, int32_t params, int32_t results, const int32_t *roots) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(context);
    if (!ctx || params < 0 || results < 0) return 0;
    if (!ctx_runtime(ctx)->continuation_arena) {
        ctx_runtime(ctx)->continuation_arena = continuation_arena_new();
        if (!ctx_runtime(ctx)->continuation_arena) return 0;
    }
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

MOONBIT_FFI_EXPORT int32_t wasmoon_continuation_arena_is_available(void *owner) {
    return owner && *(native_continuation_arena_t **)owner != NULL;
}
