// Copyright 2025
#include "memory_ops.h"
#include "../../ownership/native_alloc.h"
#include <string.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#include <malloc.h>
#else
#include <sys/mman.h>
#endif

// ============ Multi-Memory Operations (with memidx) ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_grow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(memory_grow_indexed_internal);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_ptr(void) {
    return WASMOON_GUEST_ADDRESS(memory_size_indexed_internal);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_fill_ptr(void) {
    return WASMOON_GUEST_ADDRESS(memory_fill_indexed_internal);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_copy_ptr(void) {
    return WASMOON_GUEST_ADDRESS(memory_copy_indexed_internal);
}

// ============ Linear Memory Allocation FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_memory(int64_t size) {
    if (size <= 0) return 0;
    void *mem = wasmoon_native_calloc(1, (size_t)size);
    return (int64_t)mem;
}

static _Atomic int64_t g_memory_descriptor_live_count = 0;

static void finalize_memory_descriptor(void *object) {
    wasmoon_memory_t *mem = object;
    if (!mem->valid) return;
    if (mem->is_guarded) {
        if (mem->alloc_base) {
#ifdef _WIN32
            VirtualFree(mem->alloc_base, 0, MEM_RELEASE);
#else
            munmap(mem->alloc_base, mem->alloc_size);
#endif
        }
    } else {
        if (mem->base) {
            free(mem->base);
        }
    }

    if (mem->reservation) moonbit_decref(mem->reservation);
    atomic_fetch_sub_explicit(&g_memory_descriptor_live_count, 1, memory_order_relaxed);
}

static wasmoon_memory_t *memory_descriptor_new(int valid) {
    wasmoon_memory_t *mem = moonbit_make_external_object(finalize_memory_descriptor, sizeof(*mem));
    memset(mem, 0, sizeof(*mem));
    mem->valid = valid;
    if (valid) atomic_fetch_add_explicit(&g_memory_descriptor_live_count, 1, memory_order_relaxed);
    return mem;
}

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_memory_descriptor_empty(void) { return memory_descriptor_new(0); }
MOONBIT_FFI_EXPORT int32_t wasmoon_memory_descriptor_is_empty(wasmoon_memory_t *mem) { return !mem->valid; }
MOONBIT_FFI_EXPORT int32_t wasmoon_memory_descriptor_equal(wasmoon_memory_t *a, wasmoon_memory_t *b) {
    return a == b || (!a->valid && !b->valid);
}
MOONBIT_FFI_EXPORT int64_t wasmoon_memory_descriptor_live_count(void) {
    return atomic_load_explicit(&g_memory_descriptor_live_count, memory_order_relaxed);
}

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_jit_alloc_memory_desc(
    int64_t size_bytes,
    int64_t max_pages,
    int32_t is_memory64,
    int32_t page_size_log2,
    int32_t is_shared
) {
    if (size_bytes < 0) return memory_descriptor_new(0);
    wasmoon_memory_t *mem = memory_descriptor_new(1);
    atomic_init(&mem->growth_lock, 0);

    mem->max_pages = (max_pages < 0) ? SIZE_MAX : (size_t)max_pages;
    mem->is_memory64 = (is_memory64 != 0);
    mem->page_size_log2 = page_size_log2;
    mem->is_shared = (is_shared != 0);
    if (mem->is_shared) {
        if (max_pages < 0 || page_size_log2 < 0 || page_size_log2 > 30 ||
            (uint64_t)max_pages > SIZE_MAX >> page_size_log2 ||
            !alloc_shared_memory_external(mem, (size_t)size_bytes,
                (size_t)max_pages << page_size_log2)) {
            moonbit_decref(mem);
            return memory_descriptor_new(0);
        }
    } else {
        if (size_bytes > 0) {
            mem->base = (uint8_t *)wasmoon_native_calloc(1, (size_t)size_bytes);
            if (!mem->base) {
                moonbit_decref(mem);
                return memory_descriptor_new(0);
            }
        }
        atomic_store_explicit(&mem->current_length, (size_t)size_bytes, memory_order_relaxed);
    }
    return mem;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_retain_memory_desc(wasmoon_memory_t *mem) {
    if (mem) moonbit_incref(mem);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory_desc(wasmoon_memory_t *mem) {
    if (mem) moonbit_decref(mem);
}

// Allocate guarded memory into a standalone descriptor (store-owned).
// Returns a managed descriptor, empty on failure.

MOONBIT_FFI_EXPORT wasmoon_memory_t *wasmoon_jit_alloc_guarded_memory_desc(int64_t initial_pages, int64_t max_pages, int32_t is_shared) {
    // Guarded memory is used for memory32 bounds-check elimination.
    // Only supported for 64KiB pages.
    if (initial_pages < 0 || initial_pages > 65536) {
        return memory_descriptor_new(0);
    }
    if (max_pages > 65536) {
        max_pages = 65536;
    }

    size_t initial_size = (size_t)initial_pages * WASM_PAGE_SIZE;
    size_t max_size = (max_pages < 0) ? 0 : (size_t)max_pages * WASM_PAGE_SIZE;

    wasmoon_memory_t *memory = memory_descriptor_new(1);

    atomic_init(&memory->growth_lock, 0);
    memory->max_pages = (max_pages < 0) ? SIZE_MAX : (size_t)max_pages;
    memory->is_memory64 = 0;
    memory->page_size_log2 = 16;
    memory->is_shared = (is_shared != 0);

    uint8_t *base = alloc_guarded_memory_external(memory, initial_size, max_size);
    if (!base && initial_size > 0) {
        moonbit_decref(memory);
        return memory_descriptor_new(0);
    }

    return memory;
}

// The caller and context each retain the new managed descriptor.
MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory(int64_t mem_ptr) {
    if (mem_ptr) {
        free((void *)mem_ptr);
    }
}

// ============ Memory Descriptor Helpers (runtime + JIT sharing) ============

MOONBIT_FFI_EXPORT int64_t wasmoon_mem_desc_get_len(wasmoon_memory_t *mem_desc_ptr) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    return memory_len_desc_internal(mem);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_mem_desc_grow(wasmoon_memory_t *mem_desc_ptr, int64_t delta, int32_t max_pages) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    return memory_grow_desc_internal(mem, delta, max_pages);
}

// Validate without adding signed offsets or forming an out-of-range pointer.
// Empty live allocations accept (0, 0); empty managed handles never do.
static int memory_descriptor_range(wasmoon_memory_t *memory, int64_t offset, int64_t size) {
    if (!memory || offset < 0 || size < 0) return 0;
    size_t length = atomic_load_explicit(&memory->current_length, memory_order_acquire);
    return (uint64_t)size <= length && (uint64_t)offset <= length - (uint64_t)size;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_read(wasmoon_memory_t *mem_desc_ptr, int64_t offset, moonbit_bytes_t out, int size) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    if (!memory_descriptor_range(mem, offset, size)) return -1;
    if (size == 0) return 0;
    if (!out) return -1;
    memcpy(out, mem->base + offset, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_write(wasmoon_memory_t *mem_desc_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    if (!memory_descriptor_range(mem, offset, size)) return -1;
    if (size == 0) return 0;
    if (!data) return -1;
    memcpy(mem->base + offset, data, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_memmove(wasmoon_memory_t *mem_desc_ptr, int64_t dst, int64_t src, int size) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    if (!memory_descriptor_range(mem, dst, size) || !memory_descriptor_range(mem, src, size)) return -1;
    if (size == 0) return 0;
    memmove(mem->base + dst, mem->base + src, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_copy64(wasmoon_memory_t *dst_desc, int64_t dst, wasmoon_memory_t *src_desc, int64_t src, int64_t size) {
    wasmoon_memory_t *destination = memory_descriptor_live(dst_desc);
    wasmoon_memory_t *source = memory_descriptor_live(src_desc);
    if (!memory_descriptor_range(destination, dst, size) || !memory_descriptor_range(source, src, size)) return -1;
    if (size == 0) return 0;
    memmove(destination->base + dst, source->base + src, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_memset64(wasmoon_memory_t *mem_desc_ptr, int64_t dst, int32_t val, int64_t size) {
    wasmoon_memory_t *mem = memory_descriptor_live(mem_desc_ptr);
    if (!memory_descriptor_range(mem, dst, size)) return -1;
    if (size == 0) return 0;
    memset(mem->base + dst, val & 0xFF, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_memset(wasmoon_memory_t *mem_desc_ptr, int64_t dst, int32_t val, int size) {
    return wasmoon_mem_desc_memset64(mem_desc_ptr, dst, val, size);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_memory_bind_reservation(wasmoon_memory_t *memory, wasmoon_reservation_t *reservation) {
    if (!memory_descriptor_live(memory)) return 0;
    if (memory->reservation) return memory->reservation->quota == reservation->quota;
    if (!wasmoon_reservation_valid(reservation) || reservation->amount != (int64_t)atomic_load(&memory->current_length)) return 0;
    moonbit_incref(reservation);
    memory->reservation = reservation;
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_memory_matches_quota(wasmoon_memory_t *memory, wasmoon_quota_t *quota) {
    if (!memory_descriptor_live(memory)) return 0;
    return memory->reservation ? (wasmoon_reservation_matches(memory->reservation, quota) ? 1 : -1) : 0;
}
