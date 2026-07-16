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
