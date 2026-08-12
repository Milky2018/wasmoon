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
test "late rematerialization rebuilds once per using block" {
  let builder = FunctionBuilder::FunctionBuilder("rematerialize_across_blocks")
  let condition = builder.add_param(I32)
  builder.add_result(I64)
  let local_use = builder.create_block()
  let terminator_use = builder.create_block()
  let constant = builder.iconst_i64(65535L)
  builder.brnz(condition, local_use, terminator_use)
  builder.switch_to_block(local_use)
  let sum = builder.iadd(constant, constant)
  builder.return_([sum])
  builder.switch_to_block(terminator_use)
  builder.return_([constant])
  let func = builder.get_function()

  inspect(
    rematerialize_cheap_values_across_blocks(func).changed,
    content="true",
  )
  eliminate_dead_code(func) |> ignore
  inspect(
    func.print(),
    content=(
      #|function rematerialize_across_blocks(v0:i32) -> i64 {
      #|block0:
      #|    brnz v0, block1, block2
      #|block1:
      #|    v3:i64 = iconst 65535
      #|    v2:i64 = iadd v3, v3
      #|    return v2
      #|block2:
      #|    v4:i64 = iconst 65535
      #|    return v4
      #|}
      #|
    ),
  )
  func.verify()
}
