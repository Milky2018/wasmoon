#ifndef WASMOON_TABLE_H
#define WASMOON_TABLE_H

#include "../context/jit_ffi.h"

// Table operations
int64_t table_grow_ctx_internal(jit_context_t *ctx, int32_t table_idx, int64_t delta, int64_t init_value);

// Managed shared tables
MOONBIT_FFI_EXPORT wasmoon_table_t *wasmoon_jit_alloc_shared_indirect_table(int count);
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_ctx_set_table_pointers(int64_t ctx_ptr, wasmoon_table_t **owners,
    int32_t *sizes, int64_t *max_sizes, int count);
void ctx_clear_table_bindings(jit_context_t *ctx);
void table_publish_layout(wasmoon_table_t *table, void **entries, size_t size);
MOONBIT_FFI_EXPORT wasmoon_table_t *wasmoon_native_table_empty(void);

#endif
