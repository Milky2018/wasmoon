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
#ifdef _WIN32
    subq    $32, %rsp
    movq    $1, %rcx
#else
    movq    $1, %rdi
#endif
    call    SYMBOL(wasmoon_native_fiber_yield)
#ifdef _WIN32
    addq    $32, %rsp
#endif
    cmpq    $0x1938, %r12
    sete    %al
    movzbq  %al, %rax
    popq    %r12
    ret

#if !defined(__APPLE__) && !defined(_WIN32)
    .section .note.GNU-stack,"",@progbits
#endif

#endif
