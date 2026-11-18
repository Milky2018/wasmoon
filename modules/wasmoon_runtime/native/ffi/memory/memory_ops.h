#ifndef WASMOON_MEMORY_OPS_H
#define WASMOON_MEMORY_OPS_H

#include "../context/jit_ffi.h"

// Free a `wasmoon_memory_t` descriptor
MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory_desc(wasmoon_memory_t * mem_ptr);

#define WASM_PAGE_SIZE 65536

// Guard page memory allocation (for bounds check elimination)
uint8_t *alloc_shared_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size);
uint8_t *alloc_guarded_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size);
int is_memory_guard_page_access(jit_context_t *ctx, void *addr);

// Multi-memory variants (with memidx parameter)
int64_t WASMOON_GUEST_ABI memory_grow_indexed_internal(jit_context_t *ctx, int32_t memidx, int64_t delta, int32_t max_pages);
int64_t WASMOON_GUEST_ABI memory_size_indexed_internal(jit_context_t *ctx, int32_t memidx);
void WASMOON_GUEST_ABI memory_fill_indexed_internal(jit_context_t *ctx, int32_t memidx, int64_t dst, int32_t val, int64_t size);
void WASMOON_GUEST_ABI memory_copy_indexed_internal(jit_context_t *ctx, int32_t dst_memidx, int32_t src_memidx,
                                   int64_t dst, int64_t src, int64_t size);

// Descriptor-only variants (no ctx)
int64_t memory_grow_desc_internal(wasmoon_memory_t *mem, int64_t delta, int32_t max_pages);
int64_t memory_len_desc_internal(wasmoon_memory_t *mem);

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_memory_descriptor_empty(void);
MOONBIT_FFI_EXPORT void wasmoon_jit_retain_memory_desc(wasmoon_memory_t *memory);
MOONBIT_FFI_EXPORT int64_t wasmoon_memory_atomic_load(wasmoon_memory_t *memory, int64_t offset, int32_t width);

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_jit_alloc_guarded_memory_desc(int64_t initial_pages, int64_t max_pages, int32_t is_shared);

#endif
