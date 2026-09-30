// Typed helper views over the layout supplied by MoonBit. Generated code embeds
// these offsets directly; only native helpers consult the retained descriptor.
#ifndef WASMOON_CONTEXT_FIELDS_H
#define WASMOON_CONTEXT_FIELDS_H

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
#endif
