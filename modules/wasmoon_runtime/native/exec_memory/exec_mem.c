// Copyright 2025
// Executable memory management for JIT runtime
// Handles mmap/VirtualAlloc for code allocation and cache flushing

#include "../ownership/quota.h"
#include "../ownership/native_alloc.h"
#include <string.h>
#include <stdlib.h>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <sys/mman.h>
#include <pthread.h>
#include <unistd.h>
#endif
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#endif
#include <errno.h>

// ============ Code Block Tracking ============

typedef struct {
    void *code;
    size_t size;
} jit_code_block_t;

// Start small and grow on demand. This avoids hard limits for large modules.
#define INITIAL_CODE_BLOCK_CAPACITY 256
static jit_code_block_t *code_blocks = NULL;
static int num_code_blocks = 0;
static int code_blocks_capacity = 0;
#ifndef _WIN32
static void *next_exec_hint = NULL;
#endif

#ifdef _WIN32
static SRWLOCK code_blocks_lock = SRWLOCK_INIT;
static void lock_code_blocks(void) { AcquireSRWLockExclusive(&code_blocks_lock); }
static void unlock_code_blocks(void) { ReleaseSRWLockExclusive(&code_blocks_lock); }
#else
static pthread_mutex_t code_blocks_lock = PTHREAD_MUTEX_INITIALIZER;
static void lock_code_blocks(void) { pthread_mutex_lock(&code_blocks_lock); }
static void unlock_code_blocks(void) { pthread_mutex_unlock(&code_blocks_lock); }
#endif

static int ensure_code_block_capacity(void) {
    if (num_code_blocks < code_blocks_capacity) {
        return 1;
    }

    if (code_blocks_capacity > INT32_MAX / 2) return 0;
    int new_capacity = (code_blocks_capacity == 0)
        ? INITIAL_CODE_BLOCK_CAPACITY
        : code_blocks_capacity * 2;
    if (new_capacity <= code_blocks_capacity) {
        return 0;
    }
    if ((size_t)new_capacity > SIZE_MAX / sizeof(jit_code_block_t)) {
        return 0;
    }

    jit_code_block_t *new_blocks =
        (jit_code_block_t *)wasmoon_native_realloc(code_blocks, (size_t)new_capacity * sizeof(jit_code_block_t));
    if (!new_blocks) {
        return 0;
    }

    code_blocks = new_blocks;
    code_blocks_capacity = new_capacity;
    return 1;
}

// ============ Platform Helpers ============

static size_t get_page_size(void) {
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwPageSize;
#else
    return (size_t)sysconf(_SC_PAGESIZE);
#endif
}

static size_t round_up_to_page(size_t size) {
    size_t page_size = get_page_size();
    if (!page_size || size > SIZE_MAX - (page_size - 1)) return 0;
    return (size + page_size - 1) & ~(page_size - 1);
}

// ============ Executable Memory Allocation ============

static int64_t alloc_exec_internal(int size) {
    if (size <= 0 || !wasmoon_native_allocation_allowed()) {
        return 0;
    }
    lock_code_blocks();
    if (!ensure_code_block_capacity()) {
        unlock_code_blocks();
        return 0;
    }

    size_t alloc_size = round_up_to_page((size_t)size);
    if (!alloc_size) { unlock_code_blocks(); return 0; }

#ifdef _WIN32
    void *ptr = VirtualAlloc(NULL, alloc_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
#else
#ifdef __APPLE__
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_JIT
    flags |= MAP_JIT;
#endif
    // Allocate as RWX; use pthread_jit_write_protect_np to toggle W^X on Apple.
    void *ptr = mmap(next_exec_hint, alloc_size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);
    if (ptr == MAP_FAILED && next_exec_hint != NULL) {
        ptr = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE | PROT_EXEC, flags, -1, 0);
    }
#else
    // Allocate with WRITE permission first, will change to EXEC after copying.
    void *ptr = mmap(next_exec_hint, alloc_size, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ptr == MAP_FAILED && next_exec_hint != NULL) {
        ptr = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    }
#endif
    if (ptr == MAP_FAILED) {
        unlock_code_blocks();
        return 0;
    }
#endif

    if (!ptr) {
        unlock_code_blocks();
        return 0;
    }

    code_blocks[num_code_blocks].code = ptr;
    code_blocks[num_code_blocks].size = alloc_size;
    num_code_blocks++;
#ifndef _WIN32
    next_exec_hint = (void *)((uint8_t *)ptr + alloc_size);
#endif
    unlock_code_blocks();
    return (int64_t)ptr;
}

// ============ Code Copy with Permission Change ============

static int copy_code_internal(int64_t dest, const uint8_t *src, int size) {
    void *ptr = (void *)dest;
    if (!ptr || !src || size <= 0) {
        return -1;
    }
    lock_code_blocks();

    // Find the code block containing this complete write range.
    size_t alloc_size = 0;
#ifndef __APPLE__
    void *block_base = NULL;
#endif
    for (int i = 0; i < num_code_blocks; i++) {
        uint8_t *base = (uint8_t *)code_blocks[i].code;
        uintptr_t base_address = (uintptr_t)base;
        uintptr_t end_address = base_address + code_blocks[i].size;
        uintptr_t address = (uintptr_t)ptr;
        if (address >= base_address && address <= end_address &&
            end_address - address >= (size_t)size) {
            alloc_size = code_blocks[i].size;
#ifndef __APPLE__
            block_base = base;
#endif
            break;
        }
    }
    if (alloc_size == 0) {
        unlock_code_blocks();
        return -1;
    }

#ifdef _WIN32
    DWORD old_protection = 0;
    if (!VirtualProtect(block_base, alloc_size, PAGE_READWRITE, &old_protection)) {
        unlock_code_blocks();
        return -1;
    }
#elif defined(__APPLE__)
    // Toggle write protection for JIT pages on Apple platforms.
    pthread_jit_write_protect_np(0);
#else
    // Ensure writable before patching (needed for runtime fixups).
    if (mprotect(block_base, alloc_size, PROT_READ | PROT_WRITE) != 0) {
        unlock_code_blocks();
        return -1;
    }
#endif

    // Copy code.
    memcpy(ptr, src, (size_t)size);

#ifdef _WIN32
    DWORD ignored = 0;
    if (!VirtualProtect(block_base, alloc_size, PAGE_EXECUTE_READ, &ignored)) {
        unlock_code_blocks();
        return -1;
    }
#elif defined(__APPLE__)
    // Re-enable write protection for JIT pages.
    pthread_jit_write_protect_np(1);
#else
    // Change permissions from WRITE to EXEC.
    if (mprotect(block_base, alloc_size, PROT_READ | PROT_EXEC) != 0) {
        unlock_code_blocks();
        return -1;
    }
#endif

    // Flush instruction cache
#ifdef _WIN32
    if (!FlushInstructionCache(GetCurrentProcess(), ptr, (SIZE_T)size)) {
        unlock_code_blocks();
        return -1;
    }
#elif defined(__APPLE__)
    sys_icache_invalidate(ptr, (size_t)size);
#elif defined(__aarch64__)
    __builtin___clear_cache(ptr, (char*)ptr + size);
#endif

    unlock_code_blocks();
    return 0;
}

// ============ Free Executable Memory ============

static int free_exec_internal(int64_t ptr_i64) {
    void *ptr = (void *)ptr_i64;
    if (!ptr) {
        return -1;
    }
    lock_code_blocks();

    // Find the code block
    for (int i = 0; i < num_code_blocks; i++) {
        if (code_blocks[i].code == ptr) {
#ifdef _WIN32
            VirtualFree(ptr, 0, MEM_RELEASE);
#else
            munmap(ptr, code_blocks[i].size);
#endif
            // Remove from array in O(1) by swapping with the tail.
            num_code_blocks--;
            if (i != num_code_blocks) {
                code_blocks[i] = code_blocks[num_code_blocks];
            }
            if (num_code_blocks == 0) {
                free(code_blocks);
                code_blocks = NULL;
                code_blocks_capacity = 0;
            }
            unlock_code_blocks();
            return 0;
        }
    }

    unlock_code_blocks();
    return -1;  // Not found
}

static int exec_block_count_internal(void) {
    lock_code_blocks();
    int count = num_code_blocks;
    unlock_code_blocks();
    return count;
}

// ============ Executable Memory FFI Exports ============

typedef struct {
    int64_t ptr;
    int32_t size;
    int32_t finalized;
    int32_t code_bytes; // Logical code size, excluding inter-function alignment.
    wasmoon_reservation_t *reservation;
} managed_exec_code_t;

static void finalize_exec_code(void *self) {
    managed_exec_code_t *code = (managed_exec_code_t *)self;
    if (code->ptr != 0) {
        free_exec_internal(code->ptr);
        code->ptr = 0;
    }
    if (code->reservation) { moonbit_decref(code->reservation); code->reservation = NULL; }
}

static void *make_managed_exec_code(int64_t ptr, int size, int finalized) {
    managed_exec_code_t *payload = (managed_exec_code_t *)moonbit_make_external_object(
        finalize_exec_code,
        sizeof(managed_exec_code_t)
    );
    if (!payload) {
        free_exec_internal(ptr);
        return NULL;
    }
    payload->ptr = ptr;
    payload->size = size;
    payload->code_bytes = size;
    payload->finalized = finalized;
    payload->reservation = NULL;
    return payload;
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_exec_managed(moonbit_bytes_t code, int size) {
    if (size <= 0 || !code) {
        return NULL;
    }

    int64_t ptr = alloc_exec_internal(size);
    if (ptr == 0) {
        return NULL;
    }

    int result = copy_code_internal(ptr, code, size);
    if (result != 0) {
        free_exec_internal(ptr);
        return NULL;
    }

    return make_managed_exec_code(ptr, size, 1);
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_stage_exec_managed(int size, int code_bytes) {
    if (code_bytes == -1) code_bytes = size;
    if (size <= 0 || code_bytes < 0 || code_bytes > size) return NULL;
    int64_t ptr = alloc_exec_internal(size);
    if (ptr == 0) return NULL;
    managed_exec_code_t *code = make_managed_exec_code(ptr, size, 0);
    if (code) code->code_bytes = code_bytes;
    return code;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_finalize_exec_managed(
    void *exec_code,
    moonbit_bytes_t code,
    int size
) {
    if (!exec_code || !code) return -1;
    managed_exec_code_t *payload = (managed_exec_code_t *)exec_code;
    if (payload->ptr == 0 || payload->finalized || size != payload->size) return -1;
    if (copy_code_internal(payload->ptr, code, size) != 0) return -1;
    payload->finalized = 1;
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_release_exec_managed(void *exec_code) {
    if (!exec_code) return -1;
    managed_exec_code_t *payload = (managed_exec_code_t *)exec_code;
    if (payload->ptr == 0) return 0;
    if (free_exec_internal(payload->ptr) != 0) return -1;
    payload->ptr = 0;
    payload->size = 0;
    payload->finalized = 0;
    if (payload->reservation) { moonbit_decref(payload->reservation); payload->reservation = NULL; }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exec_code_ptr(void *exec_code) {
    if (!exec_code) return 0;
    return ((managed_exec_code_t *)exec_code)->ptr;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_exec_mapping_count(void) {
    return exec_block_count_internal();
}

MOONBIT_FFI_EXPORT int32_t wasmoon_exec_bind_reservation(void *object, wasmoon_reservation_t *reservation) {
    managed_exec_code_t *code = object;
    if (!code || !code->ptr || code->reservation || !wasmoon_reservation_valid(reservation) || reservation->amount != code->code_bytes) return 0;
    moonbit_incref(reservation);
    code->reservation = reservation;
    return 1;
}

// ============ Memory Read/Write Helpers ============

MOONBIT_FFI_EXPORT void wasmoon_jit_write_i64(int64_t addr, int64_t value) {
    if (addr == 0) return;
    if (copy_code_internal(addr, (const uint8_t *)&value, (int)sizeof(value)) != 0) {
        memcpy((void *)addr, &value, sizeof(value));
    }
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_read_i64(int64_t addr) {
    if (addr != 0) {
        return *((int64_t *)addr);
    }
    return 0;
}
