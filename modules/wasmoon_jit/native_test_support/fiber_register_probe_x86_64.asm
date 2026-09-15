; MASM implementation of fiber_register_probe_x86_64.S
option casemap:none
.code
EXTERN wasmoon_native_fiber_yield:PROC
ALIGN 16
PUBLIC wasmoon_test_native_fiber_register_probe
wasmoon_test_native_fiber_register_probe:
    push r12
    mov r12, 01938h
    sub rsp, 32
    mov rcx, 1
    call wasmoon_native_fiber_yield
    add rsp, 32
    cmp r12, 01938h
    sete al
    movzx rax, al
    pop r12
    ret
END
