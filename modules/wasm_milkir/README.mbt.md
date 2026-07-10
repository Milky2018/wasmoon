# wasm_milkir

WebAssembly dialect adapter for MilkIR extension operations.

`wasm_milkir` provides the Wasm-specific opcode set, extension descriptors, and
builder helpers used with MilkIR. Frontends encode Wasm operations through
typed `WasmOpcode` constructors, then a lowering adapter checks and decodes
those extensions before machine lowering.

## Packages

- `Milky2018/wasm_milkir`: Wasm opcode encoding/decoding and builder helpers
  for `Milky2018/milkir`.

## How it fits

MilkIR represents common SSA operations directly. This package represents
WebAssembly operations that need additional immediates or lowering semantics as
typed MilkIR extensions. The extension descriptor lets a lowering pipeline
validate the encoded operation before decoding it.

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
  inspect(func.verify(), content="()")
  match func.blocks[0].instructions[1].opcode {
    Call(symbol) => inspect(symbol.name, content="example.runtime.memory_size")
    _ => inspect(false, content="true")
  }
}
```

## Example: validate and decode a Wasm extension

```moonbit check
///|
test "validate and decode a typed Wasm extension operation" {
  let opcode = WasmOpcode::MemoryGrow(0, Some(1024))
  let ext = encode(opcode)
  let desc = descriptor(opcode)
  inspect(ext.matches_descriptor(desc), content="true")
  inspect(decode_or_abort(ext) == opcode, content="true")
  let malformed = @milkir.ExtOp(
    "wasm",
    "memory_grow",
    FixedArray::makei(0, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(malformed),
    content=(
      #|Some("malformed Wasm MilkIR extension 'memory_grow': expected 1..2 immediates, got 0")
    ),
  )
}
```
