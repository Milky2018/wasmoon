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

// int64_t wasmoon_native_fiber_register_probe(void *closure)
    .globl SYMBOL(wasmoon_native_fiber_register_probe)
SYMBOL(wasmoon_native_fiber_register_probe):
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

#endif // __x86_64__ || _M_X64
