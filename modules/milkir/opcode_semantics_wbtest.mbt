///|
test "opcode semantics classify optimizer-visible behavior" {
  let signature = Signature([], [])
  let cases : Array[(String, Opcode)] = [
    ("pure scalar", Scalar(ScalarOp::IntBinary(IntBinaryOp::Add))),
    ("trapping scalar", Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv))),
    ("load", Memory(MemoryOp::Load(I32))),
    ("store", Memory(MemoryOp::Store(I32))),
    ("vector load", Vector(VectorOp::LoadZero(VectorLane::I32))),
    ("vector store", Vector(VectorOp::StoreLane(VectorLane::I32, 0))),
    (
      "call",
      Call(CallOp::Direct(ExternalSymbol::ExternalSymbol("callee"), signature)),
    ),
    ("extension", Ext(ExtOp::ExtOp("test", "op", []), signature)),
  ]
  debug_inspect(
    cases.map(fn(entry) {
      let (name, opcode) = entry
      let semantics = opcode.semantics()
      (
        name,
        semantics.memory.reads_memory(),
        semantics.memory.may_write_memory(),
        semantics.may_trap,
        semantics.other_observable_effect,
        semantics.must_preserve_if_unused(),
      )
    }),
    content=(
      #|[
      #|  ("pure scalar", false, false, false, false, false),
      #|  ("trapping scalar", false, false, true, false, true),
      #|  ("load", true, false, true, false, true),
      #|  ("store", false, true, true, false, true),
      #|  ("vector load", true, false, true, false, true),
      #|  ("vector store", false, true, true, false, true),
      #|  ("call", true, true, true, true, true),
      #|  ("extension", true, true, true, true, true),
      #|]
    ),
  )
}

///|
test "dead code preserves unused trapping and observable instructions" {
  let builder = FunctionBuilder::FunctionBuilder("preserve_semantic_effects")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  let float = builder.add_param(F64)
  builder.add_result(I32)
  builder.sdiv(lhs, rhs) |> ignore
  builder.fcvt_to_sint(I32, float) |> ignore
  builder.call_symbol(ExternalSymbol::ExternalSymbol("callee"), Some(I32), [])
  |> ignore
  builder.emit_ext_inst(I32, ExtOp::ExtOp("test", "observable", []), [])
  |> ignore
  let result = builder.iconst_i32(0)
  builder.return_([result])
  let func = builder.get_function()
  let before = instruction_count(func)
  let optimized = eliminate_dead_code(func)
  inspect(optimized.changed, content="false")
  inspect(instruction_count(func) == before, content="true")
}

///|
test "GVN and egraph derive policy from opcode semantics" {
  let func = Function::new_empty("semantic_policy")
  let opcodes : Array[Opcode] = [
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)),
    Scalar(ScalarOp::FloatBinary(FloatBinaryOp::Add)),
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv)),
    Memory(MemoryOp::Load(I32)),
    Call(CallOp::Pointer(0, 1)),
    Ext(ExtOp::ExtOp("test", "op", []), Signature([], [I32])),
  ]
  let instructions = opcodes.map(fn(opcode) {
    func.new_inst(opcode, [], [func.new_value(I32)])
  })
  debug_inspect(
    instructions.map(is_gvn_candidate),
    content="[true, true, false, false, false, false]",
  )
  debug_inspect(
    instructions.map(inst_is_egraph_pure),
    content="[true, false, false, false, false, false]",
  )
}
