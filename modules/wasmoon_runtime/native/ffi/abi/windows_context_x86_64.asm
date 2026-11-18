; MASM implementation of windows_context_x86_64.S
option casemap:none
.code
ALIGN 16
PUBLIC wasmoon_windows_guest_setjmp
wasmoon_windows_guest_setjmp:
    mov rcx, rdi
    jmp wasmoon_windows_setjmp
PUBLIC wasmoon_windows_setjmp
wasmoon_windows_setjmp:
    mov QWORD PTR [rcx], rbx
    mov QWORD PTR [rcx+8], rbp
    mov QWORD PTR [rcx+16], rdi
    mov QWORD PTR [rcx+24], rsi
    mov QWORD PTR [rcx+32], r12
    mov QWORD PTR [rcx+40], r13
    mov QWORD PTR [rcx+48], r14
    mov QWORD PTR [rcx+56], r15
    lea rax, QWORD PTR [rsp+8]
    mov QWORD PTR [rcx+64], rax
    mov rax, QWORD PTR [rsp]
    mov QWORD PTR [rcx+72], rax
    stmxcsr DWORD PTR [rcx+80]
    fnstcw WORD PTR [rcx+84]
    movdqu XMMWORD PTR [rcx+96], xmm6
    movdqu XMMWORD PTR [rcx+112], xmm7
    movdqu XMMWORD PTR [rcx+128], xmm8
    movdqu XMMWORD PTR [rcx+144], xmm9
    movdqu XMMWORD PTR [rcx+160], xmm10
    movdqu XMMWORD PTR [rcx+176], xmm11
    movdqu XMMWORD PTR [rcx+192], xmm12
    movdqu XMMWORD PTR [rcx+208], xmm13
    movdqu XMMWORD PTR [rcx+224], xmm14
    movdqu XMMWORD PTR [rcx+240], xmm15
    xor eax, eax
    ret
PUBLIC wasmoon_windows_longjmp
wasmoon_windows_longjmp:
    mov eax, edx
    test eax, eax
    jne label1
    mov eax, 1
label1:
    mov rbx, QWORD PTR [rcx]
    mov rbp, QWORD PTR [rcx+8]
    mov rdi, QWORD PTR [rcx+16]
    mov rsi, QWORD PTR [rcx+24]
    mov r12, QWORD PTR [rcx+32]
    mov r13, QWORD PTR [rcx+40]
    mov r14, QWORD PTR [rcx+48]
    mov r15, QWORD PTR [rcx+56]
    ldmxcsr DWORD PTR [rcx+80]
    fldcw WORD PTR [rcx+84]
    movdqu xmm6, XMMWORD PTR [rcx+96]
    movdqu xmm7, XMMWORD PTR [rcx+112]
    movdqu xmm8, XMMWORD PTR [rcx+128]
    movdqu xmm9, XMMWORD PTR [rcx+144]
    movdqu xmm10, XMMWORD PTR [rcx+160]
    movdqu xmm11, XMMWORD PTR [rcx+176]
    movdqu xmm12, XMMWORD PTR [rcx+192]
    movdqu xmm13, XMMWORD PTR [rcx+208]
    movdqu xmm14, XMMWORD PTR [rcx+224]
    movdqu xmm15, XMMWORD PTR [rcx+240]
    mov rsp, QWORD PTR [rcx+64]
    jmp QWORD PTR [rcx+72]
END
