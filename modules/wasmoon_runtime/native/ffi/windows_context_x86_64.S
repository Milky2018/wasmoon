// Win64 non-unwinding guest trap recovery. Layout matches windows_context.h.
#if defined(_WIN32) && (defined(__x86_64__) || defined(_M_X64))
.text
.p2align 4
.globl wasmoon_windows_guest_setjmp
wasmoon_windows_guest_setjmp:
    movq %rdi, %rcx
    jmp wasmoon_windows_setjmp
.globl wasmoon_windows_setjmp
wasmoon_windows_setjmp:
    movq %rbx, 0(%rcx)
    movq %rbp, 8(%rcx)
    movq %rdi, 16(%rcx)
    movq %rsi, 24(%rcx)
    movq %r12, 32(%rcx)
    movq %r13, 40(%rcx)
    movq %r14, 48(%rcx)
    movq %r15, 56(%rcx)
    leaq 8(%rsp), %rax
    movq %rax, 64(%rcx)
    movq (%rsp), %rax
    movq %rax, 72(%rcx)
    stmxcsr 80(%rcx)
    fnstcw 84(%rcx)
    movdqu %xmm6, 96(%rcx)
    movdqu %xmm7, 112(%rcx)
    movdqu %xmm8, 128(%rcx)
    movdqu %xmm9, 144(%rcx)
    movdqu %xmm10, 160(%rcx)
    movdqu %xmm11, 176(%rcx)
    movdqu %xmm12, 192(%rcx)
    movdqu %xmm13, 208(%rcx)
    movdqu %xmm14, 224(%rcx)
    movdqu %xmm15, 240(%rcx)
    xorl %eax, %eax
    ret
.globl wasmoon_windows_longjmp
wasmoon_windows_longjmp:
    movl %edx, %eax
    testl %eax, %eax
    jne 1f
    movl $1, %eax
1:
    movq 0(%rcx), %rbx
    movq 8(%rcx), %rbp
    movq 16(%rcx), %rdi
    movq 24(%rcx), %rsi
    movq 32(%rcx), %r12
    movq 40(%rcx), %r13
    movq 48(%rcx), %r14
    movq 56(%rcx), %r15
    ldmxcsr 80(%rcx)
    fldcw 84(%rcx)
    movdqu 96(%rcx), %xmm6
    movdqu 112(%rcx), %xmm7
    movdqu 128(%rcx), %xmm8
    movdqu 144(%rcx), %xmm9
    movdqu 160(%rcx), %xmm10
    movdqu 176(%rcx), %xmm11
    movdqu 192(%rcx), %xmm12
    movdqu 208(%rcx), %xmm13
    movdqu 224(%rcx), %xmm14
    movdqu 240(%rcx), %xmm15
    movq 64(%rcx), %rsp
    jmp *72(%rcx)
#endif
