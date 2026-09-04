///|
test "opcode semantics classify optimizer-visible behavior" {
  let signature = @milkir.Signature([], [])
  let cases : Array[(String, @milkir.Opcode)] = [
    ("pure scalar", Scalar(IntBinary(Add))),
    ("signed div", Scalar(IntBinary(SignedDiv))),
    ("unsigned div", Scalar(IntBinary(UnsignedDiv))),
    ("signed rem", Scalar(IntBinary(SignedRem))),
    ("unsigned rem", Scalar(IntBinary(UnsignedRem))),
    ("float to signed int", Scalar(Convert(FloatToSignedInt))),
    ("float to unsigned int", Scalar(Convert(FloatToUnsignedInt))),
    ("load", Memory(Load(I32))),
    ("load narrow", Memory(LoadNarrow(I32, 8, false))),
    ("store", Memory(Store(I32))),
    ("store narrow", Memory(StoreNarrow(8))),
    ("vector load extend", Memory(Vector(LoadExtend(I8, Signed)))),
    ("vector load splat", Memory(Vector(LoadSplat(I8)))),
    ("vector load zero", Memory(Vector(LoadZero(I32)))),
    ("vector load lane", Memory(Vector(LoadLane(I8, 0)))),
    ("vector store lane", Memory(Vector(StoreLane(I8, 0)))),
    ("direct call", Call(Direct(ExternalSymbol("callee"), signature))),
    ("pointer call", Call(Pointer(0, 0))),
    ("extension", Ext(ExtOp("test", "op", []), signature)),
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
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "preserve_semantic_effects",
  )
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  let float = builder.add_param(F64)
  builder.add_result(I32)
  builder.sdiv(lhs, rhs) |> ignore
  builder.fcvt_to_sint(I32, float) |> ignore
  builder.call_symbol(ExternalSymbol("callee"), Some(I32), []) |> ignore
  builder.emit_ext_inst(I32, ExtOp("test", "observable", []), []) |> ignore
  let result = builder.iconst_i32(0)
  builder.return_([result])
  let func = builder.get_function()
  let before = instruction_count(func)
  let optimized = eliminate_dead_code(func)
  inspect(optimized.changed, content="false")
  inspect(instruction_count(func) == before, content="true")
}

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
        inst.opcode.semantics().can_stage_as_pure_candidate()
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
