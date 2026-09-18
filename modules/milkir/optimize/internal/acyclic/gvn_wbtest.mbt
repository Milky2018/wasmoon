///|
test "GVN excludes instructions with multiple results" {
  let func = @milkir.Function::new_empty("multi_result")
  let inst = func.new_inst(Scalar(IntConst(1L)), [], [
    func.new_value(I64),
    func.new_value(I64),
  ])
  inspect(is_gvn_candidate(inst), content="false")
}
