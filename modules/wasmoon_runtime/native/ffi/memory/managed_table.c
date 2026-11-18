// Copyright 2025
#include "../context/jit_context.h"
#include "table.h"
#include "../../ownership/native_alloc.h"
#include <stdlib.h>
#include <string.h>

// ============ Shared Indirect Table Support ============

static _Atomic int64_t g_shared_indirect_table_live_count = 0;

static void finalize_shared_table(void *object) {
    wasmoon_table_t *table = object;
    if (table->bindings) abort();
    if (table->entries) {
        free(table->entries);
        atomic_fetch_sub_explicit(&g_shared_indirect_table_live_count, 1, memory_order_relaxed);
    }
    if (table->reservation) moonbit_decref(table->reservation);
}

MOONBIT_FFI_EXPORT wasmoon_table_t *wasmoon_native_table_empty(void) {
    wasmoon_table_t *table = moonbit_make_external_object(finalize_shared_table, sizeof(*table));
    memset(table, 0, sizeof(*table));
    return table;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_native_table_is_empty(wasmoon_table_t *table) { return !table->entries; }
MOONBIT_FFI_EXPORT int32_t wasmoon_native_table_size(wasmoon_table_t *table) { return (int32_t)table->size; }

MOONBIT_FFI_EXPORT wasmoon_table_t *wasmoon_jit_alloc_shared_indirect_table(int count) {
    wasmoon_table_t *table = wasmoon_native_table_empty();
    if (count < 0) return table;
    table->entries = wasmoon_native_calloc((size_t)(count ? count : 1) * 2, sizeof(void *));
    if (!table->entries) return table;
    table->size = (size_t)count;
    for (size_t i = 0; i < table->size; i++) table->entries[i * 2 + 1] = (void *)(intptr_t)-1;
    atomic_fetch_add_explicit(&g_shared_indirect_table_live_count, 1, memory_order_relaxed);
    return table;
}

// Runtime close is terminal for every context borrowing this logical table.
// JITTableOwner::close remains only a view-release capability.
MOONBIT_FFI_EXPORT void wasmoon_native_table_invalidate(wasmoon_table_t *table) {
    if (!table || !table->entries) return;
    void **entries = table->entries;
    table_publish_layout(table, NULL, 0);
    table->revision++;
    free(entries);
    atomic_fetch_sub_explicit(&g_shared_indirect_table_live_count, 1, memory_order_relaxed);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_debug_shared_indirect_table_live_count(void) {
    return atomic_load_explicit(&g_shared_indirect_table_live_count, memory_order_relaxed);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_native_table_fill(wasmoon_table_t *table, int32_t offset, int32_t length, int64_t value, int32_t metadata) {
    if (!table || !table->entries || offset < 0 || length < 0 ||
        (size_t)offset > table->size || (size_t)length > table->size - (size_t)offset) return 0;
    for (int32_t i = 0; i < length; ++i) {
        table->entries[((size_t)offset + i) * 2] = (void *)(intptr_t)value;
        table->entries[((size_t)offset + i) * 2 + 1] = (void *)(intptr_t)metadata;
    }
    if (length) table->revision++;
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_native_table_copy(wasmoon_table_t *table, int32_t offset, wasmoon_table_t *source, int32_t source_offset, int32_t length) {
    if (!table || !source || !table->entries || !source->entries || offset < 0 || source_offset < 0 || length < 0 ||
        (size_t)offset > table->size || (size_t)length > table->size - (size_t)offset ||
        (size_t)source_offset > source->size || (size_t)length > source->size - (size_t)source_offset) return 0;
    if (length) {
        memmove(table->entries + (size_t)offset * 2, source->entries + (size_t)source_offset * 2, (size_t)length * 2 * sizeof(void *));
        table->revision++;
    }
    return 1;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_shared_table_set(wasmoon_table_t *table, int index, int64_t value, int type) {
    if (index < 0 || (size_t)index >= table->size) return;
    table->entries[(size_t)index * 2] = (void *)(intptr_t)value;
    table->entries[(size_t)index * 2 + 1] = (void *)(intptr_t)type;
    table->revision++;
}

// ============ Table Operations ============

MOONBIT_FFI_EXPORT int64_t WASMOON_GUEST_ABI wasmoon_jit_table_grow(
    jit_context_t *ctx,
    int32_t table_idx,
    int64_t delta,
    int64_t init_value
) {
    return table_grow_ctx_internal(ctx, table_idx, delta, init_value);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_grow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_table_grow);
}

// ============ Multi-Memory Array Setup ============

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_set_table_pointers(
    int64_t ctx_ptr, wasmoon_table_t **owners, int32_t *table_sizes,
    int64_t *table_max_sizes, int table_count
) {
    (void)table_sizes;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_count < 0 || (table_count > 0 && !owners)) return -1;
    if (table_count == 0) {
        ctx_clear_table_bindings(ctx);
        if (!ctx_runtime(ctx)->layout) { free(ctx_tables(ctx)); free(ctx_table_sizes(ctx)); free(ctx_table_max_sizes(ctx)); }
        ctx_set_tables(ctx, NULL); ctx_set_table_sizes(ctx, NULL); ctx_set_table_max_sizes(ctx, NULL);
        ctx_set_table_count(ctx, 0); ctx_set_table0_base(ctx, NULL); ctx_set_table0_elements(ctx, 0);
        return 1;
    }
    for (int i = 0; i < table_count; ++i) if (!owners[i]) return -1;
    const uint8_t *layout = ctx_runtime(ctx)->layout;
    if (layout && table_count > context_layout_field(layout, 29)) return -1;
    void ***tables = layout ? (void ***)((char *)ctx + context_layout_field(layout, 25)) : wasmoon_native_calloc((size_t)table_count, sizeof(*tables));
    size_t *sizes = layout ? (size_t *)((char *)ctx + context_layout_field(layout, 26)) : wasmoon_native_calloc((size_t)table_count, sizeof(*sizes));
    size_t *maxima = layout ? (size_t *)((char *)ctx + context_layout_field(layout, 27)) : wasmoon_native_calloc((size_t)table_count, sizeof(*maxima));
    wasmoon_table_binding_t *bindings = wasmoon_native_calloc((size_t)table_count, sizeof(*bindings));
    if (!tables || !sizes || !maxima || !bindings) {
        if (!layout) { free(tables); free(sizes); free(maxima); }
        free(bindings);
        return 0;
    }
    // Retain replacements before releasing any old bindings, including aliases.
    for (int i = 0; i < table_count; ++i) moonbit_incref(owners[i]);
    ctx_clear_table_bindings(ctx);
    if (!ctx_runtime(ctx)->layout) { free(ctx_tables(ctx)); free(ctx_table_sizes(ctx)); free(ctx_table_max_sizes(ctx)); }
    ctx_set_tables(ctx, tables); ctx_set_table_sizes(ctx, sizes); ctx_set_table_max_sizes(ctx, maxima);
    ctx_runtime(ctx)->table_bindings = bindings; ctx_set_table_count(ctx, table_count);
    for (int i = 0; i < table_count; ++i) {
        wasmoon_table_t *owner = owners[i];
        tables[i] = owner->entries;
        sizes[i] = owner->size;
        maxima[i] = table_max_sizes ? (size_t)(uint64_t)table_max_sizes[i] : SIZE_MAX;
        bindings[i].owner = owner; bindings[i].context = ctx; bindings[i].index = i;
        bindings[i].next = owner->bindings;
        if (owner->bindings) owner->bindings->previous = &bindings[i];
        owner->bindings = &bindings[i];
    }
    ctx_set_table0_base(ctx, tables[0]); ctx_set_table0_elements(ctx, sizes[0]);
    return 1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_table_entry_word(wasmoon_table_t *table, int32_t index, int32_t word) {
    return (int64_t)(intptr_t)table->entries[(size_t)index * 2 + (size_t)word];
}

MOONBIT_FFI_EXPORT int32_t wasmoon_table_bind_reservation(wasmoon_table_t *table, wasmoon_reservation_t *reservation) {
    if (!table || !table->entries || table->reservation || !wasmoon_reservation_valid(reservation)) return 0;
    moonbit_incref(reservation);
    table->reservation = reservation;
    return 1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_table_revision(wasmoon_table_t *table) {
    return table ? (int64_t)table->revision : 0;
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_table_grow);
#endif
