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

///|
test "direct Wasm tail calls replace the source placeholder terminator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("tail_caller")
  let argument = builder.add_param(Ref)
  builder.add_result(I64)
  builder.emit_void_ext_inst(@wasm_milkir.encode(ReturnCall(4)), [argument])
  builder.trap("unreachable after return_call")
  let environment = Environment::new(fn(index) {
    @machv.CodeSymbol::new("wasm.function.\{index}")
  })
  inspect(
    lower_function(builder.finalize(), environment),
    content=(
      #|machv tail_caller [internal](v0:ptr64, v1:gcref64) -> (i64) {
      #|block0:
      #|  tail_call internal @wasm.function.4 (ptr64, gcref64) -> (i64) [internal] (v0, v1) [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v1]
      #|}
    ),
  )
}

///|
test "call_ref exposes tagged-reference removal before an indirect call" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("reference_caller")
  let callee = builder.add_param(CallableRef)
  let argument = builder.add_param(I32)
  builder.add_result(I32)
  let results = builder.emit_multi_ext_inst(
    [I32],
    @wasm_milkir.encode(CallRef(2)),
    [callee, argument],
  )
  builder.return_(results)
  let environment = Environment::new(fn(index) {
    @machv.CodeSymbol::new("wasm.function.\{index}")
  })
  inspect(
    lower_function(builder.finalize(), environment),
    content=(
      #|machv reference_caller [internal](v0:ptr64, v1:gcref64, v2:i32) -> (i32) {
      #|block0:
      #|  v3:ptr64 = gcref.address v1
      #|  v4:i64 = convert.Bitcast(Ptr64, I64) v3
      #|  v5:i64 = i64.const 16140901064495857663
      #|  v6:i64 = int.binary.And v4, v5
      #|  v7:ptr64 = convert.Bitcast(I64, Ptr64) v6
      #|  v8:i32 = call indirect (ptr64, i32) -> (i32) [internal] v7, v0, v2 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v1]
      #|  return v8
      #|}
    ),
  )
}
