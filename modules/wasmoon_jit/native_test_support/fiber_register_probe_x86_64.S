#if defined(__x86_64__) || defined(_M_X64)

#if defined(__APPLE__)
    #define SYMBOL(name) _##name
    .text
    .p2align 4
#else
    #define SYMBOL(name) name
    .text
    .p2align 4
#endif

// Verify that a fiber suspension preserves a callee-saved register.
    .globl SYMBOL(wasmoon_test_native_fiber_register_probe)
SYMBOL(wasmoon_test_native_fiber_register_probe):
    pushq   %r12
    movq    $0x1938, %r12
    movq    $1, %rdi
    call    SYMBOL(wasmoon_native_fiber_yield)
    cmpq    $0x1938, %r12
    sete    %al
    movzbq  %al, %rax
    popq    %r12
    ret

#if !defined(__APPLE__)
    .section .note.GNU-stack,"",@progbits
#endif

#endif
