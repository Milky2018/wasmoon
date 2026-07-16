///|
test "core lowering preserves target-neutral SSA and CFG" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("choose_sum")
  let condition = builder.add_param(I32)
  let left = builder.add_param(I64)
  let right = builder.add_param(I64)
  builder.add_result(I64)
  let add_block = builder.create_block()
  let passthrough_block = builder.create_block()
  let join_block = builder.create_block()
  let joined = builder.add_block_param(join_block, I64)
  builder.brnz(condition, add_block, passthrough_block)
  builder.switch_to_block(add_block)
  let sum = builder.iadd(left, right)
  builder.jump(join_block, [sum])
  builder.switch_to_block(passthrough_block)
  builder.jump(join_block, [left])
  builder.switch_to_block(join_block)
  builder.return_([joined])
  let lowered = lower_core_function(builder.finalize())
  inspect(
    lowered,
    content=(
      #|machv choose_sum [internal](v0:i32, v1:i64, v2:i64) -> (i64) {
      #|block0:
      #|  branch v0, block1, block2
      #|block1:
      #|  v4:i64 = int.binary.Add v1, v2
      #|  jump block3(v4)
      #|block2:
      #|  jump block3(v1)
      #|block3(v3:i64):
      #|  return v3
      #|}
    ),
  )
}

///|
test "core lowering preserves high-half multiplication semantics" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("mul_high")
  let left = builder.add_param(I64)
  let right = builder.add_param(I64)
  builder.add_result(I64)
  let result = builder.smulh(left, right)
  builder.return_([result])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv mul_high [internal](v0:i64, v1:i64) -> (i64) {
      #|block0:
      #|  v2:i64 = int.high_multiply.Signed v0, v1
      #|  return v2
      #|}
    ),
  )
}

///|
test "core lowering rejects dialect operations structurally" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("dialect_op")
  builder.emit_void_ext_inst(ExtOp("demo", "effect", []), [])
  builder.return_([])
  try lower_core_function(builder.finalize()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidMilkIR(message="UnverifiableInstruction(message=\"unresolved dialect operation demo.effect is not core MilkIR\")")
        ),
      )
  }
}

///|
test "core lowering makes pointer arithmetic and memory effects explicit" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("raw_memory")
  let base = builder.add_param(Ptr)
  let offset = builder.add_param(I64)
  let stored = builder.add_param(I32)
  builder.add_result(I64)
  let loaded = builder.load_ptr(I64, base, offset)
  builder.store_ptr_narrow(8, base, stored, offset)
  builder.return_([loaded])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv raw_memory [internal](v0:ptr64, v1:i64, v2:i32) -> (i64) {
      #|block0:
      #|  v3:ptr64 = pointer.offset v0, v1
      #|  v4:i64 = load {
      #|  width: W64,
      #|  extension: None,
      #|  result_type: I64,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v3 [memory=read]
      #|  v5:ptr64 = pointer.offset v0, v1
      #|  store {
      #|  width: W8,
      #|  value_type: I32,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v5, v2 [memory=write]
      #|  return v4
      #|}
    ),
  )
}

///|
test "core lowering preserves logical direct-call contracts" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("direct_call")
  let argument = builder.add_param(I32)
  builder.add_result(I64)
  let symbol = builder.get_function().declare_external_symbol("host.convert")
  let results = builder.call_symbol_multi(symbol, [I64], [argument])
  builder.return_(results)
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv direct_call [internal](v0:i32) -> (i64) {
      #|block0:
      #|  v1:i64 = call external @host.convert (i32) -> (i64) [platform] v0 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v1
      #|}
    ),
  )
}

///|
test "core lowering makes indirect callees explicit ptr64 values" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("indirect_call")
  let callee = builder.add_param(I64)
  let argument = builder.add_param(I32)
  builder.add_result(I32)
  let results = builder.call_pointer(callee, [argument], [I32])
  builder.return_(results)
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv indirect_call [internal](v0:i64, v1:i32) -> (i32) {
      #|block0:
      #|  v2:ptr64 = convert.Bitcast(I64, Ptr64) v0
      #|  v3:i32 = call indirect (i32) -> (i32) [internal] v2, v1 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint]
      #|  return v3
      #|}
    ),
  )
}

///|
test "core lowering keeps the enclosing call protocol explicit" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("platform_entry")
  builder.return_([])
  inspect(
    lower_core_function_with_protocol(builder.finalize(), Platform),
    content=(
      #|machv platform_entry [platform]() -> () {
      #|block0:
      #|  return
      #|}
    ),
  )
}

///|
test "core lowering follows CFG order instead of physical block order" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("physical_order")
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let use_block = builder.create_block()
  let defining_block = builder.create_block()
  builder.jump(defining_block, [])
  builder.switch_to_block(defining_block)
  let one = builder.iconst_i32(1)
  let defined = builder.iadd(input, one)
  builder.jump(use_block, [])
  builder.switch_to_block(use_block)
  builder.return_([defined])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv physical_order [internal](v0:i32) -> (i32) {
      #|block0:
      #|  jump block2
      #|block1:
      #|  return v2
      #|block2:
      #|  v1:i32 = i32.const 1
      #|  v2:i32 = int.binary.Add v0, v1
      #|  jump block1
      #|}
    ),
  )
}

///|
test "core lowering reports only live managed references at calls" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("call_roots")
  let live = builder.add_param(Ref)
  builder.add_param(Ref) |> ignore
  builder.add_result(Ref)
  let symbol = builder.get_function().declare_external_symbol("host.observe")
  builder.call_symbol_multi(symbol, [], [live]) |> ignore
  builder.return_([live])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv call_roots [internal](v0:gcref64, v1:gcref64) -> (gcref64) {
      #|block0:
      #|  call external @host.observe (gcref64) -> () [platform] v0 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] roots=[v0]
      #|  return v0
      #|}
    ),
  )
}
