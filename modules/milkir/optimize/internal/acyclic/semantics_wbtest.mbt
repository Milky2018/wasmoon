///|
test "GVN derives policy from opcode semantics" {
  let func = @milkir.Function::new_empty("semantic_policy")
  let cases : Array[(@milkir.Opcode, Array[@milkir.Value])] = [
    (Scalar(IntBinary(Add)), [func.new_value(I32)]),
    (Scalar(FloatBinary(Add)), [func.new_value(F32)]),
    (Vector(Bitwise(Xor)), [func.new_value(V128)]),
    (Scalar(IntBinary(SignedDiv)), [func.new_value(I32)]),
    (Memory(Load(I32)), [func.new_value(I32)]),
    (Call(Pointer(0, 1)), [func.new_value(I32)]),
    (Ext(ExtOp("test", "op", []), Signature([], [I32])), [func.new_value(I32)]),
    (Scalar(IntBinary(Add)), [func.new_value(I32), func.new_value(I32)]),
  ]
  let instructions = cases.map(fn(case) {
    let (opcode, results) = case
    func.new_inst(opcode, [], results)
  })
  debug_inspect(
    instructions.map(fn(inst) {
      let pure_single_result = inst.results.length() == 1 &&
        opcode_semantics(inst.opcode).can_stage_as_pure_candidate()
      (pure_single_result, is_gvn_candidate(inst))
    }),
    content=(
      #|[
      #|  (true, true),
      #|  (true, true),
      #|  (true, true),
      #|  (false, false),
      #|  (false, false),
      #|  (false, false),
      #|  (false, false),
      #|  (false, false),
      #|]
    ),
  )
}
