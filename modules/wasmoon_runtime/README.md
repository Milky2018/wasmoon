# Wasmoon shared runtime

Core interpreter execution and state for MoonBit's `native` and linear-memory
`wasm` targets. Import `Milky2018/wasmoon_runtime/runtime` and
`Milky2018/wasmoon_runtime/executor` for portable embedding.

Native JIT assembly depends on this module. The interpreter does not depend on
the `wasmoon_jit` compiler module. Shared instruction semantics use target-selected
storage and ownership implementations. Existing native public imports remain
compatibility facades.

See the repository's [portable interpreter guide](https://github.com/Milky2018/wasmoon/blob/main/docs/portable-interpreter.md)
for the executable example, required `moonrun` host imports, explicit wasm root
and reservation cleanup, capabilities, capacity limits and validation commands.
Use matching versions for the runtime, JIT and compiler modules. See the
[0.18.0 migration notes](https://github.com/Milky2018/wasmoon/blob/main/docs/releases/0.18.0.md)
for the current release candidate and compatibility changes.
