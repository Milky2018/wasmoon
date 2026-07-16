///|
test "direct Wasm calls carry the explicit execution environment" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("caller")
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let results = builder.emit_multi_ext_inst(
    [I64],
    @wasm_milkir.encode(WasmCall(7)),
    [argument],
  )
  builder.return_(results)
  let environment = Environment::new(fn(index) {
    @machv.CodeSymbol::new("wasm.function.\{index}")
  })
  inspect(
    lower_function(builder.finalize(), environment),
    content=(
      #|machv caller [internal](v0:ptr64, v1:i32) -> (i64) {
      #|block0:
      #|  v2:i64 = call internal @wasm.function.7 (ptr64, i32) -> (i64) [internal] v0, v1 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v2
      #|}
    ),
  )
}
