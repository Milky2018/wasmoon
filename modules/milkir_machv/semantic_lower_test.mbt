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
  builder.get_function().blocks[0].instructions[0].add_metadata(
    SourceLoc("call.wat"),
  )
  builder.return_([live])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv call_roots [internal](v0:gcref64, v1:gcref64) -> (gcref64) {
      #|block0:
      #|  call external @host.observe (gcref64) -> () [platform] v0 [memory=read-write, trap, unwind, gc-safepoint, cancel-safepoint] source=call.wat:0:0 roots=[v0]
      #|  return v0
      #|}
    ),
  )
}

///|
test "core lowering preserves normalized vector operation families" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("vector_families")
  let left = builder.add_param(V128)
  let right = builder.add_param(V128)
  let third = builder.add_param(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  let pairwise = builder.emit_inst(
    V128,
    Vector(IntUnary(ExtAddPairwise(Signed), I16)),
    [left],
  )
  let extended = builder.emit_inst(
    V128,
    Vector(IntBinary(ExtMul(High, Unsigned), I32)),
    [left, right],
  )
  let converted = builder.emit_inst(
    V128,
    Vector(Convert(ConvertLowI32ToF64(Signed))),
    [extended],
  )
  let fused = builder.emit_inst(V128, Vector(Relaxed(Fma(F64, NegatedAdd))), [
    converted, right, third,
  ])
  let dotted = builder.emit_inst(V128, Vector(Relaxed(Dot8To32AddSigned)), [
    left, right, third,
  ])
  builder.return_([pairwise, extended, converted, fused, dotted])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv vector_families [internal](v0:v128, v1:v128, v2:v128) -> (v128, v128, v128, v128, v128) {
      #|block0:
      #|  v3:v128 = vector.IntUnary(I16x8, ExtendAddPairwise(Signed)) v0
      #|  v4:v128 = vector.IntBinary(I32x4, ExtendMultiply(High, Unsigned)) v0, v1
      #|  v5:v128 = vector.Convert(IntToFloat(I32x4, F64x2, Signed)) v4
      #|  v6:v128 = vector.Relaxed(FusedMultiplyAdd(F64x2, FusedNegatedMultiplyAdd)) v5, v1, v2
      #|  v7:v128 = vector.Relaxed(Dot8To32AddSigned) v0, v1, v2
      #|  return v3, v4, v5, v6, v7
      #|}
    ),
  )
}

///|
test "core lowering preserves target-neutral vector memory effects" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("vector_memory")
  let address = builder.add_param(Ptr)
  let vector = builder.add_param(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  builder.add_result(V128)
  let extended = builder.v128_load_with_addr(LoadExtend(I16, Unsigned), address)
  let zeroed = builder.v128_load_with_addr(LoadZero(I32), address)
  let lane = builder.v128_load_lane_with_addr(LoadLane(I64, 1), address, vector)
  builder.v128_store_lane_with_addr(StoreLane(I16, 3), address, lane)
  builder.return_([extended, zeroed, lane])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv vector_memory [internal](v0:ptr64, v1:v128) -> (v128, v128, v128) {
      #|block0:
      #|  v2:v128 = vector.load {
      #|  kind: Extend(I32x4, Unsigned),
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v0 [memory=read]
      #|  v3:v128 = vector.load { kind: Zero(W32), offset: 0, endianness: Little, trap: None } v0 [memory=read]
      #|  v4:v128 = vector.load { kind: Lane(I64x2, 1), offset: 0, endianness: Little, trap: None } v0, v1 [memory=read]
      #|  vector.store_lane {
      #|  lane: I16x8,
      #|  lane_index: 3,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v0, v4 [memory=write]
      #|  return v2, v3, v4
      #|}
    ),
  )
}

///|
test "core lowering converts textual traps into structured reasons" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("table_trap")
  builder.trap("table out of bounds")
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv table_trap [internal]() -> () {
      #|block0:
      #|  trap TableOutOfBounds
      #|}
    ),
  )
}

///|
test "core lowering rejects unknown textual trap reasons" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_trap")
  builder.trap("embedding-specific failure")
  try lower_core_function(builder.finalize()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_id=-1,
          #|  instruction_id=-1,
          #|  message="unknown MilkIR trap reason 'embedding-specific failure'",
          #|)
        ),
      )
  }
}

///|
test "core lowering preserves source metadata across semantic expansion" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("source_memory")
  let base = builder.add_param(I64)
  let offset = builder.add_param(I64)
  builder.add_result(I32)
  let loaded = builder.load_ptr(I32, base, offset)
  builder.get_function().blocks[0].instructions[0].add_metadata(
    SourceLoc("module.wat"),
  )
  builder.return_([loaded])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv source_memory [internal](v0:i64, v1:i64) -> (i32) {
      #|block0:
      #|  v2:ptr64 = convert.Bitcast(I64, Ptr64) v0 source=module.wat:0:0
      #|  v3:ptr64 = pointer.offset v2, v1 source=module.wat:0:0
      #|  v4:i32 = load {
      #|  width: W32,
      #|  extension: None,
      #|  result_type: I32,
      #|  offset: 0,
      #|  endianness: Little,
      #|  trap: None,
      #|} v3 [memory=read] source=module.wat:0:0
      #|  return v4
      #|}
    ),
  )
}

///|
test "dialect lowering uses the narrow semantic adapter" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("dialect_adapter")
  builder.add_param(I32) |> ignore
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let result = builder.emit_ext_inst(
    I32,
    ExtOp("demo", "add_environment", []),
    [input],
  )
  builder.return_([result])
  fn validate(view : @milkir.ExtensionInstView) -> String? {
    if view.op.dialect != "demo" || view.op.opcode != "add_environment" {
      return Some("unknown demo operation")
    }
    if view.operand_types.length() != 1 ||
      view.operand_types[0] != I32 ||
      view.result_types.length() != 1 ||
      view.result_types[0] != I32 {
      return Some("demo.add_environment expects (i32) -> i32")
    }
    None
  }
  fn lower(
    context : @adapter.InstructionContext,
    operation : @milkir.ExtOp,
  ) -> String? {
    if operation.opcode != "add_environment" {
      return Some("unknown demo operation")
    }
    let operands = context.operands()
    let environment = context.environment()
    context.finish_operation(IntBinary(Add), [operands[0], environment[0]])
    None
  }
  inspect(
    lower_dialect_function(
      builder.finalize(),
      "demo",
      validate,
      [(0, I32)],
      lower,
    ),
    content=(
      #|machv dialect_adapter [internal](v0:i32, v1:i32) -> (i32) {
      #|block0:
      #|  v2:i32 = int.binary.Add v1, v0
      #|  return v2
      #|}
    ),
  )
}

///|
test "dialect lowering rejects an adapter that omits completion" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("incomplete_adapter")
  let result = builder.emit_ext_inst(I32, ExtOp("demo", "incomplete", []), [])
  builder.add_result(I32)
  builder.return_([result])
  fn validate(_view : @milkir.ExtensionInstView) -> String? {
    None
  }
  fn lower(
    _context : @adapter.InstructionContext,
    _operation : @milkir.ExtOp,
  ) -> String? {
    None
  }
  try
    lower_dialect_function(builder.finalize(), "demo", validate, [], lower)
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_id=0,
          #|  instruction_id=0,
          #|  message="dialect instruction did not complete its result contract",
          #|)
        ),
      )
  }
}
