// Copyright 2025
// AArch64 assembly context switch for native fibers.

#if defined(__aarch64__) || defined(_M_ARM64)

#if defined(__APPLE__)
    // macOS uses underscore prefix for C symbols
    #define SYMBOL(name) _##name
    // macOS assembler directives
    .section __TEXT,__text,regular,pure_instructions
    .p2align 2
#else
    // Linux/other platforms
    #define SYMBOL(name) name
    .text
    .align 2
#endif

// void wasmoon_native_fiber_swap(context *from, const context *to)
// Context layout: sp, x19-x30, d8-d15.
    .globl SYMBOL(wasmoon_native_fiber_swap)
SYMBOL(wasmoon_native_fiber_swap):
    mov     x9, sp
    str     x9, [x0, #0]
    stp     x19, x20, [x0, #8]
    stp     x21, x22, [x0, #24]
    stp     x23, x24, [x0, #40]
    stp     x25, x26, [x0, #56]
    stp     x27, x28, [x0, #72]
    stp     x29, x30, [x0, #88]
    stp     d8, d9, [x0, #104]
    stp     d10, d11, [x0, #120]
    stp     d12, d13, [x0, #136]
    stp     d14, d15, [x0, #152]

    ldr     x9, [x1, #0]
    ldp     x19, x20, [x1, #8]
    ldp     x21, x22, [x1, #24]
    ldp     x23, x24, [x1, #40]
    ldp     x25, x26, [x1, #56]
    ldp     x27, x28, [x1, #72]
    ldp     x29, x30, [x1, #88]
    ldp     d8, d9, [x1, #104]
    ldp     d10, d11, [x1, #120]
    ldp     d12, d13, [x1, #136]
    ldp     d14, d15, [x1, #152]
    mov     sp, x9
    ret

#endif // __aarch64__ || _M_ARM64
