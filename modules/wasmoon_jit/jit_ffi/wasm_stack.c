// Copyright 2025
// WASM stack allocation and management
// Provides an independent stack for WASM execution with guard page protection

#include "jit_internal.h"

// Default WASM stack size: 1MB (configurable via parameter)
#define DEFAULT_WASM_STACK_SIZE (1024 * 1024)

// ============ Internal Stack Allocation ============

#ifdef _WIN32
// Windows implementation using VirtualAlloc/VirtualProtect/VirtualFree

static int alloc_wasm_stack_internal(jit_context_t *ctx, size_t requested_size) {
    if (!ctx) return -1;

    // If stack already allocated, free it first
    if (ctx->wasm_stack_base) {
        VirtualFree(ctx->wasm_stack_base, 0, MEM_RELEASE);
        ctx->wasm_stack_base = NULL;
        ctx->wasm_stack_top = NULL;
        ctx->wasm_stack_guard = NULL;
        ctx->wasm_stack_size = 0;
        ctx->guard_page_size = 0;
    }

    // Get system page size
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    size_t page_size = si.dwPageSize;
    size_t guard_size = page_size;  // One guard page

    // Calculate total size (align to page boundary)
    size_t stack_size = requested_size > 0 ? requested_size : DEFAULT_WASM_STACK_SIZE;
    size_t total_size = stack_size + guard_size;
    total_size = (total_size + page_size - 1) & ~(page_size - 1);

    // Allocate memory with VirtualAlloc
    void *mem = VirtualAlloc(NULL, total_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (mem == NULL) {
        return -1;
    }

    // Set up guard page at the bottom (low address)
    // Stack grows downward, so overflow hits the guard page
    DWORD old_protect;
    if (!VirtualProtect(mem, guard_size, PAGE_NOACCESS, &old_protect)) {
        VirtualFree(mem, 0, MEM_RELEASE);
        return -1;
    }

    // Initialize context fields
    ctx->wasm_stack_base = mem;
    ctx->wasm_stack_guard = mem;
    ctx->guard_page_size = guard_size;
    ctx->wasm_stack_size = total_size;

    // Stack pointer starts at the top (high address)
    // Align to 16 bytes for ABI compliance
    uintptr_t top = (uintptr_t)mem + total_size;
    top &= ~(uintptr_t)0xF;  // 16-byte alignment
    ctx->wasm_stack_top = (void *)top;

    return 0;
}

static void free_wasm_stack_internal(jit_context_t *ctx) {
    if (!ctx || !ctx->wasm_stack_base) return;

    VirtualFree(ctx->wasm_stack_base, 0, MEM_RELEASE);
    ctx->wasm_stack_base = NULL;
    ctx->wasm_stack_top = NULL;
    ctx->wasm_stack_guard = NULL;
    ctx->wasm_stack_size = 0;
    ctx->guard_page_size = 0;
}

#else
// POSIX implementation using mmap/mprotect/munmap

static int alloc_wasm_stack_internal(jit_context_t *ctx, size_t requested_size) {
    if (!ctx) return -1;

    // If stack already allocated, free it first
    if (ctx->wasm_stack_base) {
        munmap(ctx->wasm_stack_base, ctx->wasm_stack_size);
        ctx->wasm_stack_base = NULL;
        ctx->wasm_stack_top = NULL;
        ctx->wasm_stack_guard = NULL;
        ctx->wasm_stack_size = 0;
        ctx->guard_page_size = 0;
    }

    // Get system page size
    size_t page_size = (size_t)getpagesize();
    size_t guard_size = page_size;  // One guard page

    // Calculate total size (align to page boundary)
    size_t stack_size = requested_size > 0 ? requested_size : DEFAULT_WASM_STACK_SIZE;
    size_t total_size = stack_size + guard_size;
    total_size = (total_size + page_size - 1) & ~(page_size - 1);

    // Allocate memory with mmap
    // MAP_STACK hint is available on some platforms
#ifdef MAP_STACK
    int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK;
#else
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#endif

    void *mem = mmap(NULL, total_size, PROT_READ | PROT_WRITE, flags, -1, 0);
    if (mem == MAP_FAILED) {
        return -1;
    }

    // Set up guard page at the bottom (low address)
    // Stack grows downward, so overflow hits the guard page
    if (mprotect(mem, guard_size, PROT_NONE) != 0) {
        munmap(mem, total_size);
        return -1;
    }

    // Initialize context fields
    ctx->wasm_stack_base = mem;
    ctx->wasm_stack_guard = mem;
    ctx->guard_page_size = guard_size;
    ctx->wasm_stack_size = total_size;

    // Stack pointer starts at the top (high address)
    // Align to 16 bytes for AArch64 ABI compliance
    uintptr_t top = (uintptr_t)mem + total_size;
    top &= ~(uintptr_t)0xF;  // 16-byte alignment
    ctx->wasm_stack_top = (void *)top;

    return 0;
}

static void free_wasm_stack_internal(jit_context_t *ctx) {
    if (!ctx || !ctx->wasm_stack_base) return;

    munmap(ctx->wasm_stack_base, ctx->wasm_stack_size);
    ctx->wasm_stack_base = NULL;
    ctx->wasm_stack_top = NULL;
    ctx->wasm_stack_guard = NULL;
    ctx->wasm_stack_size = 0;
    ctx->guard_page_size = 0;
}

#endif // _WIN32

// ============ Guard Page Detection ============

// Check if an address is in the WASM stack guard page
int is_wasm_guard_page_access(jit_context_t *ctx, void *addr) {
    if (!ctx || !ctx->wasm_stack_guard) return 0;

    uintptr_t guard_start = (uintptr_t)ctx->wasm_stack_guard;
    uintptr_t guard_end = guard_start + ctx->guard_page_size;
    uintptr_t fault_addr = (uintptr_t)addr;

    return (fault_addr >= guard_start && fault_addr < guard_end);
}

// ============ FFI Exports ============

MOONBIT_FFI_EXPORT int wasmoon_jit_alloc_wasm_stack(int64_t ctx_ptr, int64_t stack_size) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return alloc_wasm_stack_internal(ctx, (size_t)stack_size);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_wasm_stack(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    free_wasm_stack_internal(ctx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_wasm_stack_top(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->wasm_stack_top) return 0;
    return (int64_t)ctx->wasm_stack_top;
}

// Check if address is in WASM stack guard page (used by trap handler)
MOONBIT_FFI_EXPORT int wasmoon_jit_is_guard_page_access(int64_t ctx_ptr, int64_t addr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return is_wasm_guard_page_access(ctx, (void *)addr);
}
