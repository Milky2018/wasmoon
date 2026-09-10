///|
test "NaN canonicalization preserves SSA results and excludes sign operations" {
  let builder = @milkir.FunctionBuilder("canonical_nan")
  let input = builder.add_param(F64)
  builder.add_result(F64)
  let negated = builder.fneg(input)
  let result = builder.fadd(negated, input)
  builder.return_([result])
  let func = builder.get_function()
  canonicalize_nans(func)
  func.verify()
  inspect(instruction_count(func), content="5")
  inspect(
    func.defining_inst(negated).unwrap().opcode == Scalar(FloatUnary(Neg)),
    content="true",
  )
  inspect(
    func.defining_inst(result).unwrap().opcode == Scalar(Select),
    content="true",
  )
  optimize_with_level(func, O2) |> ignore
  func.verify()
}
