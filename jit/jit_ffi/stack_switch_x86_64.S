// Copyright 2026
// x86_64 Assembly: Stack switching wrapper for WASM execution
//
// Mirrors `stack_switch_aarch64.S` but for SysV AMD64.

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

// ============ Stack Switch Trampoline ============
//
// int stack_switch_call(
//     void *wasm_stack_top,  // rdi
//     void *trampoline_ptr,  // rsi
//     void *vmctx,           // rdx
//     void *values_vec,      // rcx
//     void *func_ptr         // r8
// ) -> int (result in eax)
//
// The trampoline signature is: int (*)(vmctx, values_vec, func_ptr)
// so we shuffle: rdx->rdi, rcx->rsi, r8->rdx, then call trampoline_ptr.

    .globl SYMBOL(stack_switch_call)
SYMBOL(stack_switch_call):
    // Prologue: save callee-saved registers
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15

    // Save args
    movq    %rdi, %r12        // wasm_stack_top
    movq    %rsi, %r13        // trampoline_ptr
    movq    %rdx, %r14        // vmctx
    movq    %rcx, %r15        // values_vec
    movq    %r8,  %r9         // func_ptr (caller-saved temp)
    movq    %rsp, %rax        // host stack pointer (after pushes)

    // Switch to WASM stack
    movq    %r12, %rsp
    // Reserve a small slot on the WASM stack to save the host SP.
    // Do not rely on the callee preserving any particular register.
    subq    $16, %rsp
    movq    %rax, 8(%rsp)

    // Prepare args for trampoline call: (vmctx, values_vec, func_ptr)
    movq    %r14, %rdi
    movq    %r15, %rsi
    movq    %r9,  %rdx

    call    *%r13

    // Restore host stack
    movq    8(%rsp), %rsp

    // Epilogue: restore callee-saved regs
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    popq    %rbp
    ret

// ============ Get Current Stack Pointer ============
//
// void* get_current_sp(void) -> current stack pointer in rax

    .globl SYMBOL(get_current_sp)
SYMBOL(get_current_sp):
    movq    %rsp, %rax
    ret

#if !defined(__APPLE__)
    .section .note.GNU-stack,"",@progbits
#endif

#endif // __x86_64__ || _M_X64
