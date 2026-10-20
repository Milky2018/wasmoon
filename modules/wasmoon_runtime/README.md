# Wasmoon shared runtime

Core interpreter execution and state for MoonBit's `native` and linear-memory
`wasm` targets. Import `Milky2018/wasmoon_runtime/runtime` and
`Milky2018/wasmoon_runtime/executor` for portable embedding.

Native JIT assembly depends on this module. The interpreter does not depend on
the `wasmoon_jit` compiler module. Shared instruction semantics use target-selected
storage and ownership implementations. Existing native public imports remain
compatibility facades.

See the repository's [portable interpreter guide](../../docs/portable-interpreter.md)
for the executable example, required `moonrun` host imports, explicit wasm root
and reservation cleanup, capabilities, capacity limits and validation commands.
This module has not yet been published to the registry.
