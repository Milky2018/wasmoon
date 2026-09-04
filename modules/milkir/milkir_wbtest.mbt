///|
test "build and verify minimal MilkIR function" {
  let func = Function::new_empty("add")
  let lhs = func.add_param(I32)
  let rhs = func.add_param(I32)
  func.add_result(I32)
  let sum = func.new_value(I32)
  let entry = func.new_block([])
  let add = func.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [sum])
  add.add_metadata(Comment("lowered from frontend add"))
  entry.append_inst(add)
  entry.set_terminator(Return([sum]))
  inspect(func.blocks.length(), content="1")
  inspect(entry.instruction_count(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "signature construction materializes canonical function parameters" {
  let func = Function::with_signature(
    "canonical_signature",
    Signature([I32, I64], [I64]),
  )
  inspect(
    func.params.length(),
    content=(
      #|2
    ),
  )
  debug_inspect(
    func.param(0),
    content=(
      #|Some({ id: 0, ty: I32 })
    ),
  )
  debug_inspect(
    func.param(1),
    content=(
      #|Some({ id: 1, ty: I64 })
    ),
  )
  debug_inspect(
    func.param(2),
    content=(
      #|None
    ),
  )
  debug_inspect(
    func.new_value(F32),
    content=(
      #|{ id: 2, ty: F32 }
    ),
  )
  debug_inspect(
    func.signature(),
    content=(
      #|{ params: [I32, I64], results: [I64] }
    ),
  )
  let entry = func.new_block0()
  entry.set_terminator(Return([func.param(1).unwrap()]))
  inspect(
    func.print().contains("function canonical_signature(v0:i32, v1:i64) -> i64"),
    content=(
      #|true
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "builder prints generic SSA function" {
  let builder = FunctionBuilder::FunctionBuilder("add")
  let p0 = builder.add_param(I32)
  let p1 = builder.add_param(I32)
  builder.add_result(I32)
  let sum = builder.iadd(p0, p1)
  builder.return_([sum])
  inspect(
    builder.print(),
    content=(
      #|function add(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(builder.get_function().verify(), content="()")
}

///|
test "builder prints pointer operations" {
  let builder = FunctionBuilder::FunctionBuilder("load_store")
  let addr = builder.add_param(Ptr)
  builder.add_result(I32)
  let offset0 = builder.iconst_i64(0L)
  let loaded = builder.load_ptr(I32, addr, offset0)
  let one = builder.iconst_i32(1)
  let added = builder.iadd(loaded, one)
  let offset4 = builder.iconst_i64(4L)
  builder.store_ptr(I32, addr, added, offset4)
  builder.return_([added])
  inspect(
    builder.print(),
    content=(
      #|function load_store(v0:ptr) -> i32 {
      #|block0:
      #|    v1:i64 = iconst 0
      #|    v2:i32 = load.i32 v0, v1
      #|    v3:i32 = iconst 1
      #|    v4:i32 = iadd v2, v3
      #|    v5:i64 = iconst 4
      #|    store.i32 v0, v4, v5
      #|    return v4
      #|}
      #|
    ),
  )
}

///|
test "builder prints narrow pointer operations" {
  let builder = FunctionBuilder::FunctionBuilder("narrow_mem")
  let addr = builder.add_param(Ptr)
  builder.add_result(I32)
  let load_offset = builder.iconst_i64(2L)
  let loaded = builder.load_ptr_narrow(I32, 8, true, addr, load_offset)
  let store_offset = builder.iconst_i64(6L)
  builder.store_ptr_narrow(16, addr, loaded, store_offset)
  builder.return_([loaded])
  inspect(
    builder.print(),
    content=(
      #|function narrow_mem(v0:ptr) -> i32 {
      #|block0:
      #|    v1:i64 = iconst 2
      #|    v2:i32 = load8_s.i32 v0, v1
      #|    v3:i64 = iconst 6
      #|    store16 v0, v2, v3
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(builder.get_function().verify(), content="()")
}

///|
test "builder and CFG support branches and block params" {
  let builder = FunctionBuilder::FunctionBuilder("loop_sum")
  let n = builder.add_param(I32)
  builder.add_result(I32)
  let loop_header = builder.create_block()
  let loop_body = builder.create_block()
  let exit_block = builder.create_block()
  let init_sum = builder.iconst_i32(0)
  let init_counter = builder.iconst_i32(0)
  builder.jump(loop_header, [init_sum, init_counter])
  let sum_param = builder.add_block_param(loop_header, I32)
  let counter_param = builder.add_block_param(loop_header, I32)
  builder.switch_to_block(loop_header)
  let cmp = builder.icmp_slt(counter_param, n)
  builder.brnz(cmp, loop_body, exit_block)
  builder.switch_to_block(loop_body)
  let new_sum = builder.iadd(sum_param, counter_param)
  let one = builder.iconst_i32(1)
  let new_counter = builder.iadd(counter_param, one)
  builder.jump(loop_header, [new_sum, new_counter])
  builder.switch_to_block(exit_block)
  builder.return_([sum_param])
  let cfg = CFG::build(builder.get_function())
  let entry_successors = cfg.get_successors(0)
  let header_successors = cfg.get_successors(1)
  inspect(entry_successors.length(), content="1")
  inspect(entry_successors[0], content="1")
  inspect(header_successors.length(), content="2")
  inspect(header_successors[0], content="2")
  inspect(header_successors[1], content="3")
  inspect(cfg.dominates(1, 2), content="true")
}

///|
test "verify catches missing terminator" {
  let func = Function::new_empty("bad")
  func.new_block([]) |> ignore
  try func.verify() catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected missing terminator")
  }
}

///|
test "verify catches undefined operands" {
  let func = Function::new_empty("bad_use")
  let entry = func.new_block([])
  let bogus = Value::new(func.owner, 99, I32)
  let result = func.new_value(I32)
  entry.append_inst(
    func.new_inst(Scalar(IntBinary(Add)), [bogus, bogus], [result]),
  )
  entry.set_terminator(Return([result]))
  try func.verify() catch {
    err => inspect(err, content="UndefinedValue(value_id=99)")
  } noraise {
    _ => fail("expected undefined value")
  }
}

///|
test "verify rejects a value whose type disagrees with its definition" {
  let func = Function::new_empty("bad_value_type")
  let original = func.add_param(I32)
  func.add_result(I64)
  let forged = Value::new(func.owner, original.id, I64)
  let copied = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Scalar(Copy), [forged], [copied]))
  entry.set_terminator(Return([copied]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|TypeMismatch(message="value 0 has type i64, but its definition has type i32")
        ),
      )
  } noraise {
    _ => fail("expected value type mismatch")
  }
}

///|
test "verify rejects a jump to a missing block" {
  let func = Function::new_empty("bad_jump_target")
  let entry = func.new_block([])
  entry.set_terminator(Jump(99, []))
  try func.verify() catch {
    err => inspect(err, content="InvalidBlockTarget(block_id=99)")
  } noraise {
    _ => fail("expected invalid block target")
  }
}

///|
test "verify checks return values against the function signature" {
  let func = Function::new_empty("bad_return")
  func.add_result(I64)
  let entry = func.new_block([])
  entry.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content="ArityMismatch(message=\"return expects 1 values, got 0\")",
      )
  } noraise {
    _ => fail("expected return arity mismatch")
  }
}

///|
test "verify checks jump arguments against block parameters" {
  let func = Function::new_empty("bad_jump_argument")
  let argument = func.add_param(I32)
  let entry = func.new_block([])
  let target_param = func.new_value(I64)
  let target = func.new_block([target_param])
  entry.set_terminator(Jump(target.id, [argument]))
  target.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|TypeMismatch(message="jump to block 1 argument 0 has type i32, expected i64")
        ),
      )
  } noraise {
    _ => fail("expected jump argument type mismatch")
  }
}

///|
test "memory operations use the semantic opcode family" {
  let builder = FunctionBuilder::FunctionBuilder("memory_family")
  let address = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  let loaded = builder.load_ptr(I32, address, offset)
  builder.store_ptr(I32, address, value, offset)
  builder.return_([loaded])
  let func = builder.get_function()
  let instructions = test_block_instructions(func, func.blocks[0])
  inspect(instructions[1].opcode is Memory(Load(I32)), content="true")
  inspect(instructions[2].opcode is Memory(Store(I32)), content="true")
  inspect(func.verify(), content="()")
}

///|
test "vector operations use the semantic opcode family" {
  let builder = FunctionBuilder::FunctionBuilder("vector_family")
  let scalar = builder.add_param(I32)
  builder.add_result(V128)
  let vector = builder.v128_splat32(scalar)
  builder.return_([vector])
  let func = builder.get_function()
  let instructions = test_block_instructions(func, func.blocks[0])
  inspect(instructions[0].opcode is Vector(Splat(I32)), content="true")
  inspect(func.verify(), content="()")
}

///|
test "scalar operations use typed semantic families" {
  let builder = FunctionBuilder::FunctionBuilder("scalar_family")
  let lhs = builder.add_param(I64)
  let rhs = builder.add_param(I64)
  builder.add_result(I32)
  let sum = builder.iadd(lhs, rhs)
  let compared = builder.icmp(Ult, sum, rhs)
  builder.return_([compared])
  let func = builder.get_function()
  let instructions = test_block_instructions(func, func.blocks[0])
  inspect(instructions[0].opcode is Scalar(IntBinary(Add)), content="true")
  inspect(instructions[1].opcode is Scalar(IntCompare(Ult)), content="true")
}

///|
test "vector family identity includes every semantic axis" {
  let add8 : Opcode = Vector(IntBinary(Add, I8))
  let add8_again : Opcode = Vector(IntBinary(Add, I8))
  let add16 : Opcode = Vector(IntBinary(Add, I16))
  let unsigned_high_mul : Opcode = Vector(
    IntBinary(ExtMul(High, Unsigned), I32),
  )
  inspect(add8 == add8_again, content="true")
  inspect(add8 == add16, content="false")
  inspect(add8.hash() == add8_again.hash(), content="true")
  let identities : @hashmap.HashMap[Opcode, String] = HashMap([])
  identities.set(add8, "i8")
  identities.set(add16, "i16")
  inspect(identities.get(add8_again).unwrap_or("missing"), content="i8")
  inspect(identities.get(add16).unwrap_or("missing"), content="i16")
  debug_inspect(
    [add8, add16, unsigned_high_mul],
    content=(
      #|[
      #|  Vector(IntBinary(Add, I8)),
      #|  Vector(IntBinary(Add, I16)),
      #|  Vector(IntBinary(ExtMul(High, Unsigned), I32)),
      #|]
    ),
  )
}

///|
test "normalized vector families preserve textual spelling" {
  let func = Function::new_empty("vector_spelling")
  let vector = func.add_param(V128)
  let cases : Array[Opcode] = [
    Vector(IntUnary(Extend(High, Unsigned), I32)),
    Vector(IntBinary(AddSaturating(Signed), I16)),
    Vector(IntShift(Right(Unsigned), I64)),
    Vector(IntCompare(Lt(Unsigned), I32)),
    Vector(Narrow(I8, Signed)),
    Vector(FloatBinary(PseudoMax, F64)),
    Vector(Convert(ConvertI32ToF32(Unsigned))),
    Vector(Relaxed(Fma(F32, Add))),
    Memory(Vector(LoadLane(I16, 3))),
  ]
  debug_inspect(
    cases.map(fn(opcode) { format_opcode(opcode, [vector]) }),
    content=(
      #|[
      #|  "i32x4.extend_high_i16x8_u v0",
      #|  "i16x8.add_sat_s v0",
      #|  "i64x2.shr_u v0",
      #|  "i32x4.lt_u v0",
      #|  "i8x16.narrow_i16x8_s v0",
      #|  "f64x2.pmax v0",
      #|  "f32x4.convert_i32x4_u v0",
      #|  "v128.relaxed_madd_f32 v0",
      #|  "v128.load16_lane lane=3 v0",
      #|]
    ),
  )
}

///|
test "vector memory operations discard Wasm memory arguments" {
  let builder = FunctionBuilder::FunctionBuilder("vector_memory_family")
  let address = builder.add_param(Ptr)
  builder.add_result(V128)
  let loaded = builder.v128_load_with_addr(LoadExtend(I8, Signed), address)
  builder.return_([loaded])
  let func = builder.get_function()
  let instructions = test_block_instructions(func, func.blocks[0])
  inspect(
    instructions[0].opcode is Memory(Vector(LoadExtend(I8, Signed))),
    content="true",
  )
  let printed = func.print()
  inspect(printed.contains("v128.load8x8_s"), content="true")
  inspect(printed.contains("mem="), content="false")
  inspect(printed.contains("offset="), content="false")
  inspect(func.verify(), content="()")
}

///|
test "instruction identity includes result types and arity" {
  let func = Function::new_empty("instruction_identity")
  let i32_result = func.new_value(I32)
  let i64_result = func.new_value(I64)
  let second_i64_result = func.new_value(I64)
  let i32_const = func.new_inst(Scalar(IntConst(1L)), [], [i32_result])
  let i64_const = func.new_inst(Scalar(IntConst(1L)), [], [i64_result])
  let i64_pair = func.new_inst(Scalar(IntConst(1L)), [], [
    i64_result, second_i64_result,
  ])
  let expressions : @hashmap.HashMap[Inst, Unit] = HashMap([])
  expressions.set(i32_const, ())
  expressions.set(i64_const, ())
  expressions.set(i64_pair, ())
  inspect(expressions.length(), content="3")
}

///|
test "instruction identity compares float constants by bit pattern" {
  let func = Function::new_empty("float_instruction_identity")
  let positive_zero = func.new_inst(Scalar(FloatConst64(0UL)), [], [
    func.new_value(F64),
  ])
  let negative_zero = func.new_inst(
    Scalar(FloatConst64(0x8000000000000000UL)),
    [],
    [func.new_value(F64)],
  )
  let nan_bits = 0x7FF8000000000001UL
  let other_nan_bits = 0x7FF8000000000002UL
  let nan0 = func.new_inst(Scalar(FloatConst64(nan_bits)), [], [
    func.new_value(F64),
  ])
  let nan0_again = func.new_inst(Scalar(FloatConst64(nan_bits)), [], [
    func.new_value(F64),
  ])
  let nan1 = func.new_inst(Scalar(FloatConst64(other_nan_bits)), [], [
    func.new_value(F64),
  ])
  inspect(positive_zero == negative_zero, content="false")
  inspect(nan0 == nan0_again, content="true")
  inspect(nan0 == nan1, content="false")
  inspect(nan0.hash() == nan0_again.hash(), content="true")
  let expressions : @hashmap.HashMap[Inst, Int] = HashMap([])
  expressions.set(nan0, 7)
  inspect(expressions.get(nan0_again).unwrap_or(-1), content="7")
}
