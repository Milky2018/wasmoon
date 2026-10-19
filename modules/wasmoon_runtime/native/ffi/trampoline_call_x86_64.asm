; MASM implementation of trampoline_call_x86_64.S
option casemap:none
.code
ALIGN 16
PUBLIC wasmoon_call_entry_trampoline
wasmoon_call_entry_trampoline:
    push rdi
    push rsi
    sub rsp, 160
    movdqu XMMWORD PTR [rsp], xmm6
    movdqu XMMWORD PTR [rsp+16], xmm7
    movdqu XMMWORD PTR [rsp+32], xmm8
    movdqu XMMWORD PTR [rsp+48], xmm9
    movdqu XMMWORD PTR [rsp+64], xmm10
    movdqu XMMWORD PTR [rsp+80], xmm11
    movdqu XMMWORD PTR [rsp+96], xmm12
    movdqu XMMWORD PTR [rsp+112], xmm13
    movdqu XMMWORD PTR [rsp+128], xmm14
    movdqu XMMWORD PTR [rsp+144], xmm15
    mov rdi, rcx
    mov rsi, rdx
    mov rdx, r8
    mov rcx, r9
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    call rax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    movdqu xmm6, XMMWORD PTR [rsp]
    movdqu xmm7, XMMWORD PTR [rsp+16]
    movdqu xmm8, XMMWORD PTR [rsp+32]
    movdqu xmm9, XMMWORD PTR [rsp+48]
    movdqu xmm10, XMMWORD PTR [rsp+64]
    movdqu xmm11, XMMWORD PTR [rsp+80]
    movdqu xmm12, XMMWORD PTR [rsp+96]
    movdqu xmm13, XMMWORD PTR [rsp+112]
    movdqu xmm14, XMMWORD PTR [rsp+128]
    movdqu xmm15, XMMWORD PTR [rsp+144]
    add rsp, 160
    pop rsi
    pop rdi
    ret
END
