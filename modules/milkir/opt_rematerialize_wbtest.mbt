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
