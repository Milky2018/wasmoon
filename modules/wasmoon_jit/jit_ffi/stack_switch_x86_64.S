// Copyright 2026
// x86_64 assembly context switch for native fibers.

#if defined(__x86_64__) || defined(_M_X64)

#if defined(__APPLE__)
    // macOS uses underscore prefix for C symbols
    #define SYMBOL(name) _##name
    .text
    .p2align 4
#else
    #define SYMBOL(name) name
    .text
    .p2align 4
#endif

// void wasmoon_native_fiber_swap(context *from, const context *to)
// Context layout: rsp, rbx, rbp, r12, r13, r14, r15.
    .globl SYMBOL(wasmoon_native_fiber_swap)
SYMBOL(wasmoon_native_fiber_swap):
    movq    %rsp, 0(%rdi)
    movq    %rbx, 8(%rdi)
    movq    %rbp, 16(%rdi)
    movq    %r12, 24(%rdi)
    movq    %r13, 32(%rdi)
    movq    %r14, 40(%rdi)
    movq    %r15, 48(%rdi)

    movq    0(%rsi), %rsp
    movq    8(%rsi), %rbx
    movq    16(%rsi), %rbp
    movq    24(%rsi), %r12
    movq    32(%rsi), %r13
    movq    40(%rsi), %r14
    movq    48(%rsi), %r15
    ret

#if !defined(__APPLE__)
    .section .note.GNU-stack,"",@progbits
#endif

#endif // __x86_64__ || _M_X64
