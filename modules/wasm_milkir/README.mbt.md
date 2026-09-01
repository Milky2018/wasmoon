# wasm_milkir

WebAssembly dialect adapter for MilkIR extension operations.

`wasm_milkir` provides the Wasm-specific opcode set, extension descriptors, and
builder helpers used with MilkIR. Frontends encode Wasm operations through
typed `WasmOpcode` constructors, then a lowering adapter checks and decodes
those extensions before machine lowering.

Typed Wasm builders only emit IR data; they do not attach validator closures to the MilkIR function. Generic MilkIR finalization checks the extension envelope and its explicit signature, while `verify_function` applies context-free schema contracts. Operations whose contracts depend on module or linker metadata must use an explicit `WasmValidationContext` and `verify_function_with_context`. Wasm lowering requires the same context and validates it immediately before instruction selection.

Typed constructors, serialized opcode names, and immediate layouts are defined once in `wasm_opcodes.schema`. During development, `dev_build` runs the deterministic `tools/generate_wasm_opcodes.py` generator to refresh the committed `dialect_generated.mbt` source. Published packages include that generated MoonBit source, so downstream builds neither load the schema at runtime nor execute development build rules.

## Packages

- `Milky2018/wasm_milkir`: Wasm opcode encoding/decoding and builder helpers
  for `Milky2018/milkir`.
- `Milky2018/wasm_milkir/native`: contextual Wasm dialect validation and
  streaming lowering into a native target sink.

## How it fits

MilkIR represents common SSA operations directly. This package represents
WebAssembly operations that need additional immediates or lowering semantics as
typed MilkIR extensions. The extension descriptor lets a lowering pipeline
validate the encoded operation before decoding it.

Common arithmetic, calls, references, and SIMD operations use MilkIR's semantic
opcode families directly. In particular, the Wasm frontend consumes SIMD
`memidx`, alignment, and offset fields while constructing the effective address;
the resulting MilkIR `VectorOp` carries only vector load/store semantics.

Linear-memory base pointers use MilkIR `GlobalValue` declarations rather than a
Wasm extension opcode. `memory_base_context_field` identifies the memory index,
the declaration records `Heap(memidx)` provenance, and the frontend chooses
`Stable` only when the embedding guarantees that the base cannot move during
the function invocation. Contextual validation checks that the memory exists;
`wasm_milkir/native` resolves the opaque field through its embedding environment.

## Example: map Wasm reference types to MilkIR

```moonbit check
///|
test "map Wasm reference spelling to generic MilkIR references" {
  inspect(wasm_funcref_type().to_string(), content="callable_ref")
  inspect(wasm_externref_type().to_string(), content="opaque_ref")
}
```

## Example: encode a Wasm memory operation

```moonbit check
///|
test "build a Wasm memory.size extension instruction" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("memory_size")
  let symbols = RuntimeSymbols::with_runtime_prefix("example.runtime")
  let vmctx = builder.add_param(I64)
  builder.add_result(I32)
  let size = memory_size(builder, symbols, vmctx, 0)
  builder.return_([size])
  let func = builder.get_function()
  inspect(func.blocks.length(), content="1")
  verify_function(func)
  match func.blocks[0].instructions[1].opcode {
    Call(Direct(symbol, _)) =>
      inspect(symbol.name, content="example.runtime.memory_size")
    _ => inspect(false, content="true")
  }
}
```

## Example: validate and decode a Wasm extension

```moonbit check
///|
test "validate and decode a typed Wasm extension operation" {
  let opcode = WasmOpcode::RefTest(3, true)
  let ext = encode(opcode)
  let desc = descriptor(opcode)
  inspect(ext.matches_descriptor(desc), content="true")
  inspect(decode(ext) == Some(opcode), content="true")
  let malformed = @milkir.ExtOp(
    "wasm",
    "ref_test",
    FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
  )
  debug_inspect(
    decode_error(malformed),
    content=(
      #|Some("malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
    ),
  )
}
```
