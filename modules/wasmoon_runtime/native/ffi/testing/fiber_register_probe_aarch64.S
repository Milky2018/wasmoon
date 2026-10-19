#if defined(__aarch64__) || defined(_M_ARM64)

#if defined(__APPLE__)
    #define SYMBOL(name) _##name
    .section __TEXT,__text,regular,pure_instructions
    .p2align 2
#else
    #define SYMBOL(name) name
    .text
    .align 2
#endif

// Verify that a fiber suspension preserves one integer and one floating-point
// callee-saved register.
    .globl SYMBOL(wasmoon_test_native_fiber_register_probe)
SYMBOL(wasmoon_test_native_fiber_register_probe):
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     d8, [sp, #24]
    mov     x19, #0x1938
    mov     x9, #0x406e
    fmov    d8, x9
    mov     x0, #1
    bl      SYMBOL(wasmoon_native_fiber_yield)
    mov     x10, #0x1938
    cmp     x19, x10
    b.ne    1f
    fmov    x9, d8
    mov     x10, #0x406e
    cmp     x9, x10
    b.ne    1f
    mov     x0, #1
    b       2f
1:
    mov     x0, #0
2:
    ldr     d8, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

#endif
