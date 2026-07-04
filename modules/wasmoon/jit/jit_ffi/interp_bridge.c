// Copyright 2025
// Interpreter bridge for hybrid JIT/interpreter execution
// Allows JIT-compiled code to call back into the interpreter for specific functions

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "jit_ffi.h"

// ============ Global State ============

// Callback function type for interpreter invocation
// Parameters:
//   func_idx: The wasm function index to call
//   args: Array of argument values (as int64)
//   num_args: Number of arguments
//   results: Array to store results (as int64)
//   num_results: Number of expected results
// Returns: 0 on success, non-zero on error
typedef int32_t (*interp_callback_fn)(
    int32_t func_idx,
    int64_t *args,
    int32_t num_args,
    int64_t *results,
    int32_t num_results
);

// Global interpreter callback (set by MoonBit before JIT execution)
static interp_callback_fn g_interp_callback = NULL;

// Per-function metadata for interpreter fallback
typedef struct {
    int32_t func_idx;      // Wasm function index
    int32_t num_params;    // Number of parameters
    int32_t num_results;   // Number of results
} interp_func_info_t;

// Array of function info for interpreter-executed functions
static interp_func_info_t *g_interp_funcs = NULL;
static int32_t g_interp_funcs_count = 0;
static int32_t g_interp_funcs_capacity = 0;

// ============ Setup/Teardown ============

MOONBIT_FFI_EXPORT void wasmoon_jit_set_interp_callback(int64_t callback_ptr) {
    g_interp_callback = (interp_callback_fn)(uintptr_t)callback_ptr;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_interp_callback(void) {
    g_interp_callback = NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_init_interp_funcs(int32_t capacity) {
    if (g_interp_funcs) {
        free(g_interp_funcs);
    }
    g_interp_funcs = (interp_func_info_t *)calloc(capacity, sizeof(interp_func_info_t));
    g_interp_funcs_count = 0;
    g_interp_funcs_capacity = capacity;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_add_interp_func(
    int32_t func_idx,
    int32_t num_params,
    int32_t num_results
) {
    if (!g_interp_funcs || g_interp_funcs_count >= g_interp_funcs_capacity) {
        return;
    }
    g_interp_funcs[g_interp_funcs_count].func_idx = func_idx;
    g_interp_funcs[g_interp_funcs_count].num_params = num_params;
    g_interp_funcs[g_interp_funcs_count].num_results = num_results;
    g_interp_funcs_count++;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_interp_funcs(void) {
    if (g_interp_funcs) {
        free(g_interp_funcs);
        g_interp_funcs = NULL;
    }
    g_interp_funcs_count = 0;
    g_interp_funcs_capacity = 0;
}

// ============ Interpreter Trampoline ============
// Generic trampoline that can handle any function signature
// JIT ABI v3: X0 = callee_vmctx, X1 = caller_vmctx, X2-X7 = args

// Helper to find function info by index
static interp_func_info_t* find_interp_func(int32_t func_idx) {
    for (int32_t i = 0; i < g_interp_funcs_count; i++) {
        if (g_interp_funcs[i].func_idx == func_idx) {
            return &g_interp_funcs[i];
        }
    }
    return NULL;
}

// Trampoline for functions with 0 params, 0 results
static int64_t interp_trampoline_0_0(
    jit_context_t *ctx, jit_context_t *caller_ctx
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    g_interp_callback(func_idx, NULL, 0, NULL, 0);
    return 0;
}

// Trampoline for functions with 0 params, 1 result
static int64_t interp_trampoline_0_1(
    jit_context_t *ctx, jit_context_t *caller_ctx
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t result = 0;
    g_interp_callback(func_idx, NULL, 0, &result, 1);
    return result;
}

// Trampoline for functions with 1 param, 0 results
static int64_t interp_trampoline_1_0(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[1] = {arg0};
    g_interp_callback(func_idx, args, 1, NULL, 0);
    return 0;
}

// Trampoline for functions with 1 param, 1 result
static int64_t interp_trampoline_1_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[1] = {arg0};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 1, &result, 1);
    return result;
}

// Trampoline for functions with 2 params, 0 results
static int64_t interp_trampoline_2_0(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[2] = {arg0, arg1};
    g_interp_callback(func_idx, args, 2, NULL, 0);
    return 0;
}

// Trampoline for functions with 2 params, 1 result
static int64_t interp_trampoline_2_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[2] = {arg0, arg1};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 2, &result, 1);
    return result;
}

// Trampoline for functions with 3 params, 1 result
static int64_t interp_trampoline_3_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1, int64_t arg2
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[3] = {arg0, arg1, arg2};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 3, &result, 1);
    return result;
}

// Trampoline for functions with 4 params, 1 result
static int64_t interp_trampoline_4_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1, int64_t arg2, int64_t arg3
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[4] = {arg0, arg1, arg2, arg3};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 4, &result, 1);
    return result;
}

// Trampoline for functions with 5 params, 1 result
static int64_t interp_trampoline_5_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1, int64_t arg2, int64_t arg3, int64_t arg4
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[5] = {arg0, arg1, arg2, arg3, arg4};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 5, &result, 1);
    return result;
}

// Trampoline for functions with 6 params, 1 result (max register args)
static int64_t interp_trampoline_6_1(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t arg0, int64_t arg1, int64_t arg2,
    int64_t arg3, int64_t arg4, int64_t arg5
) {
    (void)caller_ctx;
    if (!g_interp_callback) return 0;
    int32_t func_idx = ctx->debug_current_func_idx;
    int64_t args[6] = {arg0, arg1, arg2, arg3, arg4, arg5};
    int64_t result = 0;
    g_interp_callback(func_idx, args, 6, &result, 1);
    return result;
}

// ============ FFI Exports ============

// Get trampoline pointer for a given signature
// Returns 0 if no matching trampoline exists
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_interp_trampoline(
    int32_t num_params,
    int32_t num_results
) {
    // Match signature to trampoline
    if (num_params == 0 && num_results == 0) {
        return (int64_t)(uintptr_t)interp_trampoline_0_0;
    }
    if (num_params == 0 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_0_1;
    }
    if (num_params == 1 && num_results == 0) {
        return (int64_t)(uintptr_t)interp_trampoline_1_0;
    }
    if (num_params == 1 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_1_1;
    }
    if (num_params == 2 && num_results == 0) {
        return (int64_t)(uintptr_t)interp_trampoline_2_0;
    }
    if (num_params == 2 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_2_1;
    }
    if (num_params == 3 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_3_1;
    }
    if (num_params == 4 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_4_1;
    }
    if (num_params == 5 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_5_1;
    }
    if (num_params == 6 && num_results == 1) {
        return (int64_t)(uintptr_t)interp_trampoline_6_1;
    }
    // Unsupported signature - fall back to JIT or error
    return 0;
}

// Check if interpreter callback is set
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_has_interp_callback(void) {
    return g_interp_callback != NULL ? 1 : 0;
}
