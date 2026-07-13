///|
test "opcode semantics classify optimizer-visible behavior" {
  let signature = Signature([], [])
  let cases : Array[(String, Opcode)] = [
    ("pure scalar", Scalar(ScalarOp::IntBinary(IntBinaryOp::Add))),
    ("signed div", Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv))),
    ("unsigned div", Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedDiv))),
    ("signed rem", Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedRem))),
    ("unsigned rem", Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedRem))),
    (
      "float to signed int",
      Scalar(ScalarOp::Convert(ConversionOp::FloatToSignedInt)),
    ),
    (
      "float to unsigned int",
      Scalar(ScalarOp::Convert(ConversionOp::FloatToUnsignedInt)),
    ),
    ("load", Memory(MemoryOp::Load(I32))),
    ("load narrow", Memory(MemoryOp::LoadNarrow(I32, 8, false))),
    ("store", Memory(MemoryOp::Store(I32))),
    ("store narrow", Memory(MemoryOp::StoreNarrow(8))),
    (
      "vector load extend",
      Vector(VectorOp::LoadExtend(VectorLane::I8, VectorExtension::Signed)),
    ),
    ("vector load splat", Vector(VectorOp::LoadSplat(VectorLane::I8))),
    ("vector load zero", Vector(VectorOp::LoadZero(VectorLane::I32))),
    ("vector load lane", Vector(VectorOp::LoadLane(VectorLane::I8, 0))),
    ("vector store lane", Vector(VectorOp::StoreLane(VectorLane::I8, 0))),
    (
      "direct call",
      Call(CallOp::Direct(ExternalSymbol::ExternalSymbol("callee"), signature)),
    ),
    ("pointer call", Call(CallOp::Pointer(0, 0))),
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
      #|  ("signed div", false, false, true, false, true),
      #|  ("unsigned div", false, false, true, false, true),
      #|  ("signed rem", false, false, true, false, true),
      #|  ("unsigned rem", false, false, true, false, true),
      #|  ("float to signed int", false, false, true, false, true),
      #|  ("float to unsigned int", false, false, true, false, true),
      #|  ("load", true, false, true, false, true),
      #|  ("load narrow", true, false, true, false, true),
      #|  ("store", false, true, true, false, true),
      #|  ("store narrow", false, true, true, false, true),
      #|  ("vector load extend", true, false, true, false, true),
      #|  ("vector load splat", true, false, true, false, true),
      #|  ("vector load zero", true, false, true, false, true),
      #|  ("vector load lane", true, false, true, false, true),
      #|  ("vector store lane", false, true, true, false, true),
      #|  ("direct call", true, true, true, true, true),
      #|  ("pointer call", true, true, true, true, true),
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
