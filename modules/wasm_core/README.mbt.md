# wasm_core

Reusable WebAssembly specification model for MoonBit tools.

This module contains the shared data model used by parsers, validators,
frontends, runtimes, and tests.

## Packages

- `Milky2018/wasm_core`: small construction helpers and facade APIs.
- `Milky2018/wasm_core/types`: WebAssembly value types, instructions,
  modules, function types, subtyping helpers, and related spec data.

## Example: build a small core module model

The root package is a small facade for constructing common WebAssembly module
shapes. Use `Milky2018/wasm_core/types` when you need the full specification
data model.

```moonbit check
///|
test "build a module with one exported function" {
  let mod_ = simple_module([I32], [I64], [I64Const(7L)], "answer")
  inspect(mod_.funcs.length(), content="1")
  inspect(mod_.exports.length(), content="1")
  debug_inspect(mod_.get_func_type(0).params, content="[I32]")
  debug_inspect(mod_.get_func_type(0).results, content="[I64]")
}
```

## Example: model GC proposal types

The `types` package contains the richer specification model. Root-level helper
functions are intentionally thin; use `SubType`, `FuncType`, `StructType`, and
`ArrayType` directly for validation or frontend tests.

```moonbit check
///|
test "construct function subtypes for a module type section" {
  let unary = func_subtype([I32], [I32])
  let binary = func_subtype([I32, I32], [I32])
  let mod_ = empty_module()
  mod_.types.push(unary)
  mod_.types.push(binary)
  inspect(mod_.is_func_type(0), content="true")
  inspect(mod_.is_func_type(1), content="true")
  debug_inspect(mod_.get_func_type(1).params, content="[I32, I32]")
}
```
