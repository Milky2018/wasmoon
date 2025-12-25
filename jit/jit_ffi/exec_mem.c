// Copyright 2025
// Executable memory management for JIT runtime
// Handles mmap/VirtualAlloc for code allocation and cache flushing

#include "jit_internal.h"

// ============ Code Block Tracking ============

typedef struct {
    void *code;
    size_t size;
} jit_code_block_t;

#define MAX_CODE_BLOCKS 1024
static jit_code_block_t code_blocks[MAX_CODE_BLOCKS];
static int num_code_blocks = 0;

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
    return (size + page_size - 1) & ~(page_size - 1);
}

// ============ Executable Memory Allocation ============

int64_t alloc_exec_internal(int size) {
    if (size <= 0 || num_code_blocks >= MAX_CODE_BLOCKS) {
        return 0;
    }

    size_t alloc_size = round_up_to_page((size_t)size);

#ifdef _WIN32
    void *ptr = VirtualAlloc(NULL, alloc_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
#else
    // Allocate with WRITE permission first, will change to EXEC after copying
    void *ptr = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ptr == MAP_FAILED) {
        return 0;
    }
#endif

    if (ptr) {
        code_blocks[num_code_blocks].code = ptr;
        code_blocks[num_code_blocks].size = alloc_size;
        num_code_blocks++;
    }

    return (int64_t)ptr;
}

// ============ Code Copy with Permission Change ============

int copy_code_internal(int64_t dest, const uint8_t *src, int size) {
    void *ptr = (void *)dest;
    if (!ptr || !src || size <= 0) {
        return -1;
    }

    // Copy code
    memcpy(ptr, src, (size_t)size);

    // Find the code block to get the size for mprotect
    size_t alloc_size = 0;
    for (int i = 0; i < num_code_blocks; i++) {
        if (code_blocks[i].code == ptr) {
            alloc_size = code_blocks[i].size;
            break;
        }
    }
    if (alloc_size == 0) {
        return -1;
    }

#ifndef _WIN32
    // Change permissions from WRITE to EXEC
    if (mprotect(ptr, alloc_size, PROT_READ | PROT_EXEC) != 0) {
        return -1;
    }
#endif

    // Flush instruction cache
#ifdef __APPLE__
    sys_icache_invalidate(ptr, (size_t)size);
#elif defined(__aarch64__) && !defined(_WIN32)
    __builtin___clear_cache(ptr, (char*)ptr + size);
#endif

    return 0;
}

// ============ Free Executable Memory ============

int free_exec_internal(int64_t ptr_i64) {
    void *ptr = (void *)ptr_i64;
    if (!ptr) {
        return -1;
    }

    // Find the code block
    for (int i = 0; i < num_code_blocks; i++) {
        if (code_blocks[i].code == ptr) {
#ifdef _WIN32
            VirtualFree(ptr, 0, MEM_RELEASE);
#else
            munmap(ptr, code_blocks[i].size);
#endif
            // Remove from array (shift remaining)
            for (int j = i; j < num_code_blocks - 1; j++) {
                code_blocks[j] = code_blocks[j + 1];
            }
            num_code_blocks--;
            return 0;
        }
    }

    return -1;  // Not found
}
