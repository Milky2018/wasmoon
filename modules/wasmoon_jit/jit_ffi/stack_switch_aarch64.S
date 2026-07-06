// Copyright 2025
// AArch64 Assembly: Stack switching wrapper for WASM execution
// This provides a safe way to switch to the WASM stack before calling JIT code

#if defined(__aarch64__) || defined(_M_ARM64)

#if defined(__APPLE__)
    // macOS uses underscore prefix for C symbols
    #define SYMBOL(name) _##name
    // macOS assembler directives
    .section __TEXT,__text,regular,pure_instructions
    .p2align 2
#else
    // Linux/other platforms
    #define SYMBOL(name) name
    .text
    .align 2
#endif

// ============ Stack Switch Trampoline ============
//
// int stack_switch_call(
//     void *wasm_stack_top,  // x0 - Top of WASM stack (SP will be set to this)
//     void *trampoline_ptr,  // x1 - Pointer to the trampoline function
//     void *vmctx,           // x2 - VMContext pointer
//     void *values_vec,      // x3 - Pointer to values array
//     void *func_ptr         // x4 - WASM function pointer
// ) -> int (result in w0)
//
// The trampoline signature is: int (*)(vmctx, values_vec, func_ptr)
// So we need to shuffle: x2->x0, x3->x1, x4->x2, then call x1

    .globl SYMBOL(stack_switch_call)
SYMBOL(stack_switch_call):
    // Prologue: Save callee-saved registers and frame setup
    stp     x29, x30, [sp, #-96]!   // Save frame pointer and link register
    mov     x29, sp                  // Set up frame pointer
    stp     x19, x20, [sp, #16]     // Save callee-saved registers
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    // Save arguments to callee-saved registers
    mov     x19, x0                  // x19 = wasm_stack_top
    mov     x20, x1                  // x20 = trampoline_ptr
    mov     x21, x2                  // x21 = vmctx
    mov     x22, x3                  // x22 = values_vec
    mov     x23, x4                  // x23 = func_ptr
    mov     x24, sp                  // x24 = host stack pointer (save for later)

    // Switch to WASM stack
    // The WASM stack top should be 16-byte aligned already
    mov     sp, x19                  // SP = wasm_stack_top

    // Prepare arguments for trampoline call
    // Trampoline expects: (vmctx, values_vec, func_ptr)
    mov     x0, x21                  // arg0 = vmctx
    mov     x1, x22                  // arg1 = values_vec
    mov     x2, x23                  // arg2 = func_ptr

    // Call the trampoline
    blr     x20                      // Call trampoline_ptr, result in x0/w0

    // Save result
    mov     w25, w0                  // w25 = result (preserve across stack switch)

    // Switch back to host stack
    mov     sp, x24                  // Restore host stack pointer

    // Return result
    mov     w0, w25

    // Epilogue: Restore callee-saved registers
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96      // Restore frame pointer and link register
    ret

// ============ Get Current Stack Pointer ============
//
// void* get_current_sp(void) -> current stack pointer

    .globl SYMBOL(get_current_sp)
SYMBOL(get_current_sp):
    mov     x0, sp
    ret

#endif // __aarch64__ || _M_ARM64
