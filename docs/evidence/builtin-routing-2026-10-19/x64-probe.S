.text
.globl _probe
_probe:
    pushq %rbp
    movq %rsp, %rbp
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movq %rdi, %r15
    movq %rsi, %r13
    movq %rdx, %r12
    xorq %rdi, %rdi
    callq *%r15
    movq %rax, 0(%r13)
    movq %rdx, 8(%r13)
    movq %rcx, 16(%r13)
    movq %r8, 24(%r13)
    movq %r9, 32(%r13)
    movq %rsi, 40(%r13)
    movq %rdi, 48(%r13)
    movq %r10, 56(%r13)
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbp
    retq
