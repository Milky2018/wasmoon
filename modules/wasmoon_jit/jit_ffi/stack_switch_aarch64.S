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

// void wasmoon_native_fiber_swap(context *from, const context *to)
// Context layout: sp, x19-x30, d8-d15.
    .globl SYMBOL(wasmoon_native_fiber_swap)
SYMBOL(wasmoon_native_fiber_swap):
    mov     x9, sp
    str     x9, [x0, #0]
    stp     x19, x20, [x0, #8]
    stp     x21, x22, [x0, #24]
    stp     x23, x24, [x0, #40]
    stp     x25, x26, [x0, #56]
    stp     x27, x28, [x0, #72]
    stp     x29, x30, [x0, #88]
    stp     d8, d9, [x0, #104]
    stp     d10, d11, [x0, #120]
    stp     d12, d13, [x0, #136]
    stp     d14, d15, [x0, #152]

    ldr     x9, [x1, #0]
    ldp     x19, x20, [x1, #8]
    ldp     x21, x22, [x1, #24]
    ldp     x23, x24, [x1, #40]
    ldp     x25, x26, [x1, #56]
    ldp     x27, x28, [x1, #72]
    ldp     x29, x30, [x1, #88]
    ldp     d8, d9, [x1, #104]
    ldp     d10, d11, [x1, #120]
    ldp     d12, d13, [x1, #136]
    ldp     d14, d15, [x1, #152]
    mov     sp, x9
    ret

#endif // __aarch64__ || _M_ARM64
