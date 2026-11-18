// Copyright 2025
#include "jit_context.h"
#include "callable_lookup.h"
#include "../memory/memory_ops.h"
#include "../memory/table.h"
#include "../../ownership/native_alloc.h"
#include <stdlib.h>
#include <string.h>

// ============ Context Management FFI Exports ============

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory(int64_t ctx_ptr, wasmoon_memory_t *mem0_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        wasmoon_memory_t *new_mem0 = memory_descriptor_live(mem0_ptr);

        // If the pointer is unchanged, keep existing ownership state.
        if (ctx_memory0(ctx) == new_mem0) {
            ctx_refresh_memory0_fast_fields(ctx);
            return;
        }

        // Release the previous binding. Every non-null binding owns one RC reference.
        if (ctx_runtime(ctx)->owns_memory0 && ctx_memory0(ctx)) {
            wasmoon_jit_free_memory_desc(ctx_memory0(ctx));
        }

        if (new_mem0) moonbit_incref(new_mem0);
        ctx_set_memory0(ctx, new_mem0);
        ctx_runtime(ctx)->owns_memory0 = new_mem0 != NULL;
        ctx_refresh_memory0_fast_fields(ctx);
    }
}

// ============ GC-managed JITContext ============

static void finalize_jit_context(void *self) {
    int64_t *ptr = (int64_t *)self;
    if (*ptr != 0) {
        free_context_internal((jit_context_t *)*ptr);
        *ptr = 0;
    }
}

static void *wrap_jit_context(int64_t ctx_ptr) {
    if (ctx_ptr == 0) {
        return NULL;
    }

    int64_t *payload = (int64_t *)moonbit_make_external_object(finalize_jit_context, sizeof(int64_t));
    if (!payload) {
        free_context_internal((jit_context_t *)ctx_ptr);
        return NULL;
    }

    *payload = ctx_ptr;
    return payload;
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_context_managed(int func_count) {
    return wrap_jit_context((int64_t)alloc_context_internal(func_count));
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_null_function_address(void) {
    return NULL;
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_context_with_functions_managed(void **functions) {
    return wrap_jit_context((int64_t)(uintptr_t)alloc_context_with_functions(functions));
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_shaped_context(void **functions, uint8_t *layout) {
    return wrap_jit_context((int64_t)(uintptr_t)alloc_context_with_layout(functions, layout));
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_context_ptr(void *jit_context) {
    if (!jit_context) return 0;
    return *(int64_t *)jit_context;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_context_is_valid(void *jit_context) {
    return wasmoon_jit_context_ptr(jit_context) != 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_func_managed(
    void *jit_context, int idx, int64_t func_ptr
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && idx >= 0 && idx < ctx_func_count(ctx)) {
        ctx_func_table(ctx)[idx] = (void *)func_ptr;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory_managed(
    void *jit_context, wasmoon_memory_t *mem0_ptr
) {
    wasmoon_jit_ctx_set_memory(wasmoon_jit_context_ptr(jit_context), mem0_ptr);
}

// Consume a MoonBit Int64 array of borrowed cell addresses.
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_bind_globals_managed(
    void *jit_context, int64_t *globals
) {
    jit_context_t *ctx = (jit_context_t *)wasmoon_jit_context_ptr(jit_context);
    ctx_set_globals_internal(ctx, globals);
    return ctx ? (int64_t)ctx_globals(ctx) : 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_func_table_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return ctx ? (int64_t)ctx_func_table(ctx) : 0;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_get_func_count_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return ctx ? ctx_func_count(ctx) : 0;
}

MOONBIT_FFI_EXPORT wasmoon_table_t *wasmoon_jit_ctx_get_table_ptr_managed(
    void *jit_context, int table_idx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_idx < 0 || table_idx >= ctx_table_count(ctx) || !ctx_runtime(ctx)->table_bindings)
        return wasmoon_native_table_empty();
    wasmoon_table_t *owner = ctx_runtime(ctx)->table_bindings[table_idx].owner;
    moonbit_incref(owner);
    return owner;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_get_table_size_managed(
    void *jit_context, int table_idx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_idx < 0 || table_idx >= ctx_table_count(ctx)) {
        return 0;
    }
    if (table_idx == 0) {
        return (int)ctx_table0_elements(ctx);
    }
    if (!ctx_table_sizes(ctx)) {
        return 0;
    }
    return (int)ctx_table_sizes(ctx)[table_idx];
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_alloc_indirect_table_managed(
    void *jit_context, int count
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || count <= 0) return 0;
    wasmoon_table_t *owner = wasmoon_jit_alloc_shared_indirect_table(count);
    if (!owner->entries) { moonbit_decref(owner); return 0; }
    wasmoon_jit_ctx_set_table_pointers(ctx_ptr, &owner, NULL, NULL, 1);
    int bound = ctx_runtime(ctx)->table_bindings && ctx_runtime(ctx)->table_bindings[0].owner == owner;
    moonbit_decref(owner);
    return bound;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_indirect_managed(
    void *jit_context, int table_idx, int func_idx, int type_idx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx_table0_base(ctx) &&
        table_idx >= 0 && (size_t)table_idx < ctx_table0_elements(ctx) &&
        func_idx >= 0 && func_idx < ctx_func_count(ctx)) {
        jit_runtime_state_t *state = ctx_runtime(ctx);
        int64_t value = -(int64_t)(func_idx + 1);
        if (state->table_bindings && state->table_bindings[0].owner &&
            state->table_bindings[0].owner->store_references) {
            // A borrowed Store table never accepts executable-pointer identity.
            // Reject incomplete setup without changing its entry or revision.
            if (func_idx >= state->callable_function_count ||
                !state->callable_functions || state->callable_functions[func_idx] < 0)
                return;
            value = callable_store_reference(ctx, value);
        } else {
            int64_t pointer = (int64_t)(intptr_t)ctx_func_table(ctx)[func_idx];
            if (pointer) value = pointer | FUNCREF_TAG;
        }
        ctx_table0_base(ctx)[table_idx * 2] = (void *)(intptr_t)value;
        ctx_table0_base(ctx)[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
        table_mark_mutated(ctx, 0);
    }
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_set_memory_pointers_managed(
    void *jit_context, wasmoon_memory_t **memory_ptrs, int memory_count
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || memory_count < 0 || (memory_count > 0 && !memory_ptrs)) return -1;
    if (memory_count == 0) {
        wasmoon_jit_ctx_set_memory(ctx_ptr, NULL);
        for (int i = 0; i < ctx_memory_count(ctx); ++i) {
            if (ctx_memories(ctx)[i]) moonbit_decref(ctx_memories(ctx)[i]);
        }
        if (!ctx_runtime(ctx)->layout) free(ctx_memories(ctx));
        ctx_set_memories(ctx, NULL);
        ctx_set_memory_count(ctx, 0);
        return 1;
    }
    const uint8_t *layout = ctx_runtime(ctx)->layout;
    if (layout && memory_count > context_layout_field(layout, 28)) return -1;
    wasmoon_memory_t **memories = layout
        ? (wasmoon_memory_t **)((char *)ctx + context_layout_field(layout, 24))
        : wasmoon_native_calloc((size_t)memory_count, sizeof(*memories));
    if (!memories) return 0;
    for (int i = 0; i < memory_count; ++i) {
        wasmoon_memory_t *memory = memory_descriptor_live(memory_ptrs[i]);
        if (memory) moonbit_incref(memory);
    }
    wasmoon_jit_ctx_set_memory(ctx_ptr, memory_ptrs[0]);
    for (int i = 0; i < ctx_memory_count(ctx); ++i) {
        if (ctx_memories(ctx)[i]) moonbit_decref(ctx_memories(ctx)[i]);
    }
    for (int i = 0; i < memory_count; ++i) memories[i] = memory_descriptor_live(memory_ptrs[i]);
    if (!layout) free(ctx_memories(ctx));
    ctx_set_memories(ctx, memories);
    ctx_set_memory_count(ctx, memory_count);
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_set_table_pointers_managed(
    void *jit_context,
    wasmoon_table_t **table_ptrs,
    int32_t *table_sizes,
    int64_t *table_max_sizes,
    int table_count
) {
    return wasmoon_jit_ctx_set_table_pointers(
        wasmoon_jit_context_ptr(jit_context),
        table_ptrs,
        table_sizes,
        table_max_sizes,
        table_count
    );
}

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_jit_ctx_alloc_guarded_memory_managed(
    void *jit_context, int64_t initial_pages, int64_t max_pages
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    if (!ctx_ptr) return wasmoon_memory_descriptor_empty();
    wasmoon_memory_t *memory = wasmoon_jit_alloc_guarded_memory_desc(initial_pages, max_pages, 0);
    if (memory->valid) wasmoon_jit_ctx_set_memory(ctx_ptr, memory);
    return memory;
}

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_jit_ctx_get_memory_descriptor_managed(
    void *jit_context, int32_t memidx
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(jit_context);
    wasmoon_memory_t *memory = NULL;
    if (ctx && memidx >= 0) {
        if (memidx == 0) memory = ctx_memory0(ctx);
        else if (memidx < ctx_memory_count(ctx)) memory = ctx_memories(ctx)[memidx];
    }
    if (!memory) return wasmoon_memory_descriptor_empty();
    moonbit_incref(memory);
    return memory;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_memory_ptr_managed(
    void *jit_context, int memidx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    if (!ctx_ptr || memidx < 0) return 0;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;

    if (memidx == 0) {
        return ctx_memory0_base(ctx) ? (int64_t)ctx_memory0_base(ctx) : 0;
    }

    if (ctx_memories(ctx) && ctx_memory_count(ctx) > 0 && memidx < ctx_memory_count(ctx)) {
        wasmoon_memory_t *mem = ctx_memories(ctx)[memidx];
        return (mem && mem->base) ? (int64_t)mem->base : 0;
    }

    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_memory_size_managed(
    void *jit_context, int memidx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    if (!ctx_ptr || memidx < 0) return 0;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;

    if (memidx == 0) {
        return (int64_t)ctx_memory0_size(ctx);
    }

    if (ctx_memories(ctx) && ctx_memory_count(ctx) > 0 && memidx < ctx_memory_count(ctx)) {
        wasmoon_memory_t *mem = ctx_memories(ctx)[memidx];
        return mem ? (int64_t)atomic_load_explicit(&mem->current_length, memory_order_relaxed) : 0;
    }

    return 0;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_has_callable_metadata(void *managed_context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(managed_context);
    return ctx && ctx_runtime(ctx)->callable_local_types != NULL;
}
