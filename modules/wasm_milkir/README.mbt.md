# wasm_milkir

WebAssembly dialect adapter for MilkIR extension operations.

`wasm_milkir` owns the Wasm-specific opcode set and builder helpers that are
not part of generic MilkIR. Frontends can encode Wasm-only operations as
`milkir.ExtOp` values, then a lowering adapter can decode them before machine
lowering.

## Packages

- `Milky2018/wasm_milkir`: Wasm opcode encoding/decoding and builder helpers
  for `Milky2018/milkir`.

## Boundary

`milkir` owns generic SSA IR. `wasm_milkir` owns the WebAssembly dialect carried
through MilkIR extension operations. Product-specific runtime addresses,
VMContext layouts, and native glue still belong outside this module.

## Example: encode a Wasm memory operation

```moonbit check
///|
test "build a Wasm memory.size extension instruction" {
  let builder = @milkir.IRBuilder::new("memory_size")
  let vmctx = builder.add_param(I64)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let size = memory_size(builder, vmctx, 0)
  builder.return_([size])
  let func = builder.get_function()
  inspect(func.blocks.length(), content="1")
  inspect(func.verify(), content="()")
  match func.blocks[0].instructions[1].opcode {
    Call(symbol) => inspect(symbol.name, content="wasmoon.runtime.memory_size")
    _ => inspect(false, content="true")
  }
}
```
