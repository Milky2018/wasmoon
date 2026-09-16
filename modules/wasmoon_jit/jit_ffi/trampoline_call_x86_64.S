// Copyright 2026
// x86_64 Assembly: ABI-safe entry trampoline caller
//
// JIT-compiled wasm entry trampolines use reserved role registers (r15/r14/r13/r12)
// as pinned VMContext/cache registers and do not preserve them by SysV rules.
// This wrapper preserves the relevant callee-saved GPRs when crossing the
// C -> JIT boundary.

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

// int wasmoon_call_entry_trampoline(
//     void *trampoline_ptr, // rdi
//     void *vmctx,          // rsi
//     void *values_vec,     // rdx
//     void *func_ptr        // rcx
// ) -> int (eax)
//
// Calls trampoline_ptr(vmctx, values_vec, func_ptr) while preserving
// SysV callee-saved role registers used by JIT code.

    .globl SYMBOL(wasmoon_call_entry_trampoline)
SYMBOL(wasmoon_call_entry_trampoline):
#ifdef _WIN32
    // The host uses Win64; the private guest entry ABI remains SysV.
    pushq %rdi
    pushq %rsi
    subq $160, %rsp
    movdqu %xmm6, 0(%rsp)
    movdqu %xmm7, 16(%rsp)
    movdqu %xmm8, 32(%rsp)
    movdqu %xmm9, 48(%rsp)
    movdqu %xmm10, 64(%rsp)
    movdqu %xmm11, 80(%rsp)
    movdqu %xmm12, 96(%rsp)
    movdqu %xmm13, 112(%rsp)
    movdqu %xmm14, 128(%rsp)
    movdqu %xmm15, 144(%rsp)
    movq %rcx, %rdi
    movq %rdx, %rsi
    movq %r8, %rdx
    movq %r9, %rcx
#endif
    // Preserve callee-saved registers that JIT role mapping may clobber.
    // Keep SysV ABI guarantees for the C caller.
    // We preserve rbp/rbx/r12-r15 and maintain 16-byte alignment before call.
    pushq   %rbp
    pushq   %rbx
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15
    subq    $8, %rsp

    // Shuffle args for the entry trampoline signature:
    //   int trampoline(vmctx, values_vec, func_ptr)
    movq    %rdi, %rax        // rax = trampoline_ptr
    movq    %rsi, %rdi        // arg0 = vmctx
    movq    %rdx, %rsi        // arg1 = values_vec
    movq    %rcx, %rdx        // arg2 = func_ptr
    call    *%rax

    // Restore preserved registers.
    addq    $8, %rsp
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbx
    popq    %rbp
#ifdef _WIN32
    movdqu 0(%rsp), %xmm6
    movdqu 16(%rsp), %xmm7
    movdqu 32(%rsp), %xmm8
    movdqu 48(%rsp), %xmm9
    movdqu 64(%rsp), %xmm10
    movdqu 80(%rsp), %xmm11
    movdqu 96(%rsp), %xmm12
    movdqu 112(%rsp), %xmm13
    movdqu 128(%rsp), %xmm14
    movdqu 144(%rsp), %xmm15
    addq $160, %rsp
    popq %rsi
    popq %rdi
#endif
    ret

#if !defined(__APPLE__) && !defined(_WIN32)
    .section .note.GNU-stack,"",@progbits
#endif

#endif // __x86_64__ || _M_X64
