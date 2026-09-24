/**
 * DWARF Debug Info Generation for JIT Code
 */

#ifndef WASMOON_DWARF_H
#define WASMOON_DWARF_H

#include <stdint.h>
#include "moonbit.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Create a new DWARF builder.
 * @return MoonBit managed object; C callers must retain/release it with MoonBit RC.
 */
MOONBIT_FFI_EXPORT void *wasmoon_dwarf_create(void);

/**
 * Add a function to the DWARF debug info.
 * @param dwarf   Builder handle
 * @param name    Function name (null-terminated)
 * @param addr    Function start address
 * @param size    Function size in bytes
 * @param func_idx  WebAssembly function index
 */
MOONBIT_FFI_EXPORT void wasmoon_dwarf_add_function(
    void *dwarf,
    const char *name,
    int64_t addr,
    int size,
    int func_idx
);

/**
 * Register the DWARF debug info with the debugger.
 * This generates a Mach-O/ELF object file in memory and
 * registers it with LLDB/GDB via the JIT interface.
 * @param dwarf    Builder handle
 * @param verbose  If non-zero, print debug info to stderr
 */
MOONBIT_FFI_EXPORT void wasmoon_dwarf_register(void *dwarf, int verbose);

/**
 * Unregister DWARF debug info from the debugger.
 * @param dwarf  Builder handle
 */
MOONBIT_FFI_EXPORT void wasmoon_dwarf_unregister(void *dwarf);

/**
 * Close the DWARF builder and release its resources (idempotent).
 * Does not free the managed object or consume a reference.
 * This also unregisters the debug info if registered.
 * @param dwarf  Builder handle
 */
MOONBIT_FFI_EXPORT void wasmoon_dwarf_destroy(void *dwarf);

#ifdef __cplusplus
}
#endif

#endif // WASMOON_DWARF_H
