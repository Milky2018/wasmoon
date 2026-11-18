#ifndef WASMOON_FFI_CALLBACKS_H
#define WASMOON_FFI_CALLBACKS_H

// FuncRef erases the C backend's generated nominal closure struct tag at
// separately compiled stub boundaries. Keep the exception at the indirect
// call seam; address and all other undefined-behavior checks remain enabled.
#if defined(__clang__) && defined(__has_attribute)
#if __has_attribute(no_sanitize)
#define WASMOON_NO_FUNCTION_SANITIZE __attribute__((no_sanitize("function")))
#endif
#endif
#if !defined(WASMOON_NO_FUNCTION_SANITIZE)
#define WASMOON_NO_FUNCTION_SANITIZE
#endif

#endif
