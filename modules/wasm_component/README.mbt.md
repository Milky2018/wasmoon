# wasm_component

Portable syntax, binary decoding, canonical ABI modeling, validation, and text
tooling for the WebAssembly Component Model.

The module is independent of Wasmoon runtime objects, JIT execution, WASI, and
native host bindings. Product runtimes consume its validated component model
through their own adapters.

`Milky2018/wasmoon/component` is the Wasmoon runtime facade, and
`Milky2018/wasmoon/wit_binding` adapts a resolved portable WIT world to a live
Wasmoon component instance.

## Packages

- `Milky2018/wasm_component`: component types, binary decoding, and canonical
  ABI helpers.
- `Milky2018/wasm_component/validator`: component validation and immutable
  validation evidence.
- `Milky2018/wasm_component/text`: Component Model text parsing and encoding.
- `Milky2018/wasm_component/wit`: WIT parsing, resolution, formatting, and
  Component Model encoding and decoding.
