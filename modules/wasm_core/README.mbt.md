# wasm_core

Reusable WebAssembly specification model for MoonBit tools.

This module contains the shared data model used by parsers, validators,
frontends, runtimes, and tests. It is intentionally independent from Wasmoon
execution and JIT implementation details.

## Packages

- `Milky2018/wasm_core`: small construction helpers and facade APIs.
- `Milky2018/wasm_core/types`: WebAssembly value types, instructions,
  modules, function types, subtyping helpers, and related spec data.

## Boundary

`wasm_core` should stay reusable. It must not import `Milky2018/wasmoon`,
`Milky2018/wasmoon_jit`, native runtime glue, or product-specific host APIs.
