///|
test "cheap rematerialization accepts only one-lane integer constants" {
  let func = Function::new_empty("rematerialization_cost")
  let make = fn(opcode : Opcode, ty : Type) {
    func.new_inst(opcode, [], [func.new_value(ty)])
  }
  debug_inspect(
    [
      is_cheap_rematerializable_constant(make(Scalar(IntConst(0L)), I64)),
      is_cheap_rematerializable_constant(make(Scalar(IntConst(65535L)), I64)),
      is_cheap_rematerializable_constant(make(Scalar(IntConst(65536L)), I64)),
      is_cheap_rematerializable_constant(
        make(Scalar(IntConst(65535L << 32)), I64),
      ),
      is_cheap_rematerializable_constant(
        make(Scalar(IntConst(4294967295L)), I64),
      ),
      is_cheap_rematerializable_constant(
        make(Scalar(IntConst(305419896L)), I64),
      ),
      is_cheap_rematerializable_constant(make(Scalar(FloatConst64(0UL)), F64)),
    ],
    content="[true, true, true, true, false, false, false]",
  )
}

///|
test "single-use materialization sinks without cloning multi-use values" {
  let builder = FunctionBuilder::FunctionBuilder("sink_materialization")
  let condition = builder.add_param(I32)
  builder.add_result(I32)
  let use_block = builder.create_block()
  let other_block = builder.create_block()
  let single = builder.iconst_i32(65535)
  let shared = builder.iconst_i32(7)
  builder.brnz(condition, use_block, other_block)
  builder.switch_to_block(use_block)
  let with_single = builder.iadd(condition, single)
  let with_shared = builder.imul(with_single, shared)
  builder.return_([with_shared])
  builder.switch_to_block(other_block)
  builder.return_([shared])
  let func = builder.get_function()

  inspect(optimize_with_level(func, O2).changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function sink_materialization(v0:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iconst 7
      #|    brnz v0, block1, block2
      #|block1:
      #|    v5:i32 = iconst 65535
      #|    v3:i32 = iadd v0, v5
      #|    v4:i32 = imul v3, v2
      #|    return v4
      #|block2:
      #|    return v2
      #|}
      #|
    ),
  )
  func.verify()
}

///|
test "O2 keeps repeated cheap address recipes local" {
  let builder = FunctionBuilder::FunctionBuilder("local_address_recipes")
  builder.add_result(I64)
  builder.add_result(I64)
  let first = builder.uextend(I64, builder.iconst_i32(4))
  let second = builder.uextend(I64, builder.iconst_i32(4))
  builder.return_([first, second])
  let func = builder.get_function()

  optimize_with_level(func, O2) |> ignore
  inspect(
    func.print(),
    content=(
      #|function local_address_recipes() -> i64, i64 {
      #|block0:
      #|    v1:i64 = iconst 4
      #|    v3:i64 = iconst 4
      #|    return v1, v3
      #|}
      #|
    ),
  )
  func.verify()
}
