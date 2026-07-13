///|
test "build and verify minimal MilkIR function" {
  let func = Function::new_empty("add")
  let lhs = func.add_param(I32)
  let rhs = func.add_param(I32)
  func.add_result(I32)
  let sum = func.new_value(I32)
  let entry = func.new_block([])
  let add = func.new_inst(
    Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)),
    [lhs, rhs],
    [sum],
  )
  add.add_metadata(Comment("lowered from frontend add"))
  entry.append_inst(add)
  entry.set_terminator(Return([sum]))
  inspect(func.blocks.length(), content="1")
  inspect(entry.instructions.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "signature construction materializes canonical function parameters" {
  let func = Function::with_signature(
    "canonical_signature",
    Signature([Type::I32, Type::I64], [Type::I64]),
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
    func.new_value(Type::F32),
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
    func.new_inst(
      Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)),
      [bogus, bogus],
      [result],
    ),
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
  entry.append_inst(func.new_inst(Scalar(ScalarOp::Copy), [forged], [copied]))
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
test "optimizer preserves external calls with unused results" {
  let func = Function::new_empty("external_effect")
  let symbol = func.declare_external_symbol("effect")
  let ignored = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(CallOp::Direct(symbol, Signature([], [I32]))), [], [
      ignored,
    ]),
  )
  entry.set_terminator(Return([]))
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="1")
}

///|
test "optimizer folds integer constants" {
  let builder = FunctionBuilder::FunctionBuilder("const_add")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(20)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O1)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function const_add() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 30
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer leaves trap-prone division unfused" {
  let builder = FunctionBuilder::FunctionBuilder("no_fold_div")
  builder.add_result(I32)
  let entry = builder.current_block()
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(0)
  let result = builder.get_function().new_value(I32)
  entry.append_inst(
    builder
    .get_function()
    .new_inst(Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv)), [lhs, rhs], [
      result,
    ]),
  )
  builder.return_([result])
  let func = builder.get_function()
  let opt = optimize_with_level(func, O2)
  inspect(opt.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function no_fold_div() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 10
      #|    v1:i32 = iconst 0
      #|    v2:i32 = sdiv v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O0 does not rewrite constants" {
  let builder = FunctionBuilder::FunctionBuilder("o0")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O0)
  inspect(result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function o0() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O2 removes dead pure instructions after folding" {
  let builder = FunctionBuilder::FunctionBuilder("o2_dce")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function o2_dce() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 3
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "dead code pass keeps unused loads without alias metadata" {
  let builder = FunctionBuilder::FunctionBuilder("keep_load")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  let _loaded = builder.load_ptr(I32, ptr, offset)
  let result = builder.iconst_i32(7)
  builder.return_([result])
  let func = builder.get_function()
  let opt = eliminate_dead_code(func)
  inspect(opt.changed, content="false")
  inspect(instruction_count(func), content="3")
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
  inspect(
    func.blocks[0].instructions[1].opcode is Memory(MemoryOp::Load(I32)),
    content="true",
  )
  inspect(
    func.blocks[0].instructions[2].opcode is Memory(MemoryOp::Store(I32)),
    content="true",
  )
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
  inspect(
    func.blocks[0].instructions[0].opcode
    is Vector(VectorOp::Splat(VectorLane::I32)),
    content="true",
  )
  inspect(func.verify(), content="()")
}

///|
test "scalar operations use typed semantic families" {
  let builder = FunctionBuilder::FunctionBuilder("scalar_family")
  let lhs = builder.add_param(I64)
  let rhs = builder.add_param(I64)
  builder.add_result(I32)
  let sum = builder.iadd(lhs, rhs)
  let compared = builder.icmp(IntCC::Ult, sum, rhs)
  builder.return_([compared])
  let instructions = builder.get_function().blocks[0].instructions
  inspect(
    instructions[0].opcode is Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)),
    content="true",
  )
  inspect(
    instructions[1].opcode is Scalar(ScalarOp::IntCompare(IntCC::Ult)),
    content="true",
  )
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
    Memory(MemoryOp::Vector(VectorMemoryOp::LoadLane(I16, 3))),
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
  let loaded = builder.v128_load_with_addr(
    LoadExtend(VectorIntLane::I8, VectorSignedness::Signed),
    address,
  )
  builder.return_([loaded])
  let func = builder.get_function()
  inspect(
    func.blocks[0].instructions[0].opcode
    is Memory(
      MemoryOp::Vector(
        VectorMemoryOp::LoadExtend(VectorIntLane::I8, VectorSignedness::Signed)
      )
    ),
    content="true",
  )
  let printed = func.print()
  inspect(printed.contains("v128.load8x8_s"), content="true")
  inspect(printed.contains("mem="), content="false")
  inspect(printed.contains("offset="), content="false")
  inspect(func.verify(), content="()")
}

///|
test "strength reduction derives shift amounts and remainder masks" {
  let builder = FunctionBuilder::FunctionBuilder("strength_reduce_pow2")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  let quotient = builder.udiv(value, eight)
  let remainder = builder.urem(value, eight)
  builder.return_([product, quotient, remainder])
  let func = builder.get_function()
  let result = reduce_strength(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function strength_reduce_pow2(v0:i32) -> i32, i32, i32 {
      #|block0:
      #|    v1:i32 = iconst 8
      #|    v5:i32 = iconst 3
      #|    v2:i32 = ishl v0, v5
      #|    v6:i32 = iconst 3
      #|    v3:i32 = ushr v0, v6
      #|    v7:i32 = iconst 7
      #|    v4:i32 = band v0, v7
      #|    return v2, v3, v4
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "O3 derives power-of-two constants with a bounded large-function egraph" {
  let builder = FunctionBuilder::FunctionBuilder("o3_large_strength_reduce")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  for _ in 0..<296 {
    builder.iconst_i32(0) |> ignore
  }
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  let quotient = builder.udiv(value, eight)
  let remainder = builder.urem(value, eight)
  builder.return_([product, quotient, remainder])
  let func = builder.get_function()
  optimize_with_level(func, O3) |> ignore
  let instructions = func.blocks[0].instructions
  inspect(instructions.length(), content="5")
  inspect(instructions[0].opcode, content="Scalar(IntConst(3))")
  inspect(instructions[1].opcode, content="Scalar(IntBinary(ShiftLeft))")
  inspect(
    instructions[2].opcode,
    content="Scalar(IntBinary(UnsignedShiftRight))",
  )
  inspect(instructions[3].opcode, content="Scalar(IntConst(7))")
  inspect(instructions[4].opcode, content="Scalar(IntBinary(And))")
  inspect(func.verify(), content="()")
}

///|
test "O3 does not duplicate loop side effects without a safe unroll proof" {
  let builder = FunctionBuilder::FunctionBuilder("o3_loop_side_effect")
  let condition = builder.add_param(I32)
  let header = builder.create_block()
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [])
  builder.switch_to_block(header)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  let func = builder.get_function()
  let symbol = func.declare_external_symbol("effect")
  builder
  .current_block()
  .append_inst(
    func.new_inst(Call(CallOp::Direct(symbol, Signature([], []))), [], []),
  )
  builder.jump(header, [])
  builder.switch_to_block(exit)
  builder.return_([])
  optimize_with_level(func, O3) |> ignore
  let mut external_calls = 0
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Call(_) {
        external_calls = external_calls + 1
      }
    }
  }
  inspect(external_calls, content="1")
  inspect(func.verify(), content="()")
}

///|
test "optimizer CSE replaces duplicate pure expression with copy" {
  let builder = FunctionBuilder::FunctionBuilder("cse_local")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  let _sum0 = builder.iadd(lhs, rhs)
  let sum1 = builder.iadd(lhs, rhs)
  builder.return_([sum1])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function cse_local(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iadd v0, v1
      #|    return v3
      #|}
      #|
    ),
  )
}

///|
test "instruction identity includes result types and arity" {
  let func = Function::new_empty("instruction_identity")
  let i32_result = func.new_value(I32)
  let i64_result = func.new_value(I64)
  let second_i64_result = func.new_value(I64)
  let i32_const = func.new_inst(Scalar(ScalarOp::IntConst(1L)), [], [i32_result])
  let i64_const = func.new_inst(Scalar(ScalarOp::IntConst(1L)), [], [i64_result])
  let i64_pair = func.new_inst(Scalar(ScalarOp::IntConst(1L)), [], [
    i64_result, second_i64_result,
  ])
  let expressions : @hashmap.HashMap[Inst, Unit] = HashMap([])
  expressions.set(i32_const, ())
  expressions.set(i64_const, ())
  expressions.set(i64_pair, ())
  inspect(expressions.length(), content="3")
  inspect(is_gvn_candidate(i64_pair), content="false")
}

///|
test "instruction identity compares float constants by bit pattern" {
  let func = Function::new_empty("float_instruction_identity")
  let positive_zero = func.new_inst(Scalar(ScalarOp::FloatConst64(0UL)), [], [
    func.new_value(F64),
  ])
  let negative_zero = func.new_inst(
    Scalar(ScalarOp::FloatConst64(0x8000000000000000UL)),
    [],
    [func.new_value(F64)],
  )
  let nan_bits = 0x7FF8000000000001UL
  let other_nan_bits = 0x7FF8000000000002UL
  let nan0 = func.new_inst(Scalar(ScalarOp::FloatConst64(nan_bits)), [], [
    func.new_value(F64),
  ])
  let nan0_again = func.new_inst(Scalar(ScalarOp::FloatConst64(nan_bits)), [], [
    func.new_value(F64),
  ])
  let nan1 = func.new_inst(Scalar(ScalarOp::FloatConst64(other_nan_bits)), [], [
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

///|
test "GVN reuses float constants with identical NaN bits" {
  let builder = FunctionBuilder::FunctionBuilder("gvn_nan_bits")
  builder.add_result(F64)
  let nan = 0x7FF8000000000001UL.reinterpret_as_double()
  let _first = builder.fconst_f64(nan)
  let second = builder.fconst_f64(nan)
  builder.return_([second])
  let func = builder.get_function()
  let stats = cse_gvn_global(func)
  inspect(stats.result.changed, content="true")
  inspect(
    func.blocks[0].instructions[1].opcode is Scalar(ScalarOp::Copy),
    content="true",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN does not conflate integer constants with different widths" {
  let builder = FunctionBuilder::FunctionBuilder("gvn_integer_widths")
  builder.add_result(I64)
  let _narrow = builder.iconst_i32(1)
  let wide = builder.iconst_i64(1L)
  builder.return_([wide])
  let func = builder.get_function()
  let stats = cse_gvn_global(func)
  inspect(stats.result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function gvn_integer_widths() -> i64 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i64 = iconst 1
      #|    return v1
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer CSE reuses expressions from dominating blocks" {
  let builder = FunctionBuilder::FunctionBuilder("cse_global")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  let cond = builder.add_param(I32)
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let sum0 = builder.iadd(lhs, rhs)
  builder.brnz(cond, then_block, else_block)
  builder.switch_to_block(then_block)
  let sum1 = builder.iadd(lhs, rhs)
  builder.return_([sum1])
  builder.switch_to_block(else_block)
  builder.return_([sum0])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function cse_global(v0:i32, v1:i32, v2:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iadd v0, v1
      #|    brnz v2, block1, block2
      #|block1:
      #|    return v3
      #|block2:
      #|    return v3
      #|}
      #|
    ),
  )
}

///|
test "optimizer propagates local copies" {
  let builder = FunctionBuilder::FunctionBuilder("copy_prop")
  let param = builder.add_param(I32)
  builder.add_result(I32)
  let copy = builder.copy(param)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(copy, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function copy_prop(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = copy v0
      #|    v2:i32 = iconst 1
      #|    v3:i32 = iadd v0, v2
      #|    return v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer canonicalizes aliases through dominating blocks" {
  let builder = FunctionBuilder::FunctionBuilder("alias_canon_copy_chain")
  let param = builder.add_param(I32)
  builder.add_result(I32)
  let body = builder.create_block()
  let copy0 = builder.copy(param)
  builder.jump(body, [])
  builder.switch_to_block(body)
  let copy1 = builder.copy(copy0)
  let copy2 = builder.copy(copy1)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(copy2, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function alias_canon_copy_chain(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = copy v0
      #|    jump block1
      #|block1:
      #|    v2:i32 = copy v0
      #|    v3:i32 = copy v0
      #|    v4:i32 = iconst 1
      #|    v5:i32 = iadd v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer canonicalizes branch args without crossing sibling dominance" {
  let builder = FunctionBuilder::FunctionBuilder("alias_canon_branch_args")
  let value = builder.add_param(I32)
  let cond = builder.add_param(I32)
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let join = builder.create_block()
  let join_param = builder.add_block_param(join, I32)
  builder.brnz(cond, then_block, else_block)
  builder.switch_to_block(then_block)
  let copy = builder.copy(value)
  builder.jump(join, [copy])
  builder.switch_to_block(else_block)
  builder.jump(join, [value])
  builder.switch_to_block(join)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(join_param, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function alias_canon_branch_args(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    brnz v1, block1, block2
      #|block1:
      #|    v3:i32 = copy v0
      #|    jump block3(v0)
      #|block2:
      #|    jump block3(v0)
      #|block3(v2:i32):
      #|    v4:i32 = iconst 1
      #|    v5:i32 = iadd v2, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes unused block params and jump args" {
  let builder = FunctionBuilder::FunctionBuilder("dead_block_params")
  builder.add_result(I32)
  let target = builder.create_block()
  let used_arg = builder.iconst_i32(1)
  let dead_arg = builder.iconst_i32(2)
  builder.jump(target, [used_arg, dead_arg])
  let used_param = builder.add_block_param(target, I32)
  builder.add_block_param(target, I32) |> ignore
  builder.switch_to_block(target)
  builder.return_([used_param])
  let func = builder.get_function()
  let result = eliminate_dead_block_params(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function dead_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    jump block1(v0)
      #|block1(v2:i32):
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer keeps block params forwarded through jump args" {
  let builder = FunctionBuilder::FunctionBuilder("forwarded_block_params")
  builder.add_result(I32)
  let middle = builder.create_block()
  let exit = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(middle, [arg])
  let middle_param = builder.add_block_param(middle, I32)
  builder.switch_to_block(middle)
  builder.jump(exit, [middle_param])
  let exit_param = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  builder.return_([exit_param])
  let func = builder.get_function()
  let result = eliminate_dead_block_params(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes constant block params and rewrites uses" {
  let builder = FunctionBuilder::FunctionBuilder("const_block_params")
  builder.add_result(I32)
  let target = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(target, [arg])
  let param = builder.add_block_param(target, I32)
  builder.switch_to_block(target)
  builder.return_([param])
  let func = builder.get_function()
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function const_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 7
      #|    jump block1
      #|block1:
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes constant branch block params" {
  let builder = FunctionBuilder::FunctionBuilder("branch_const_block_params")
  builder.add_result(I32)
  let join = builder.create_block()
  let cond = builder.iconst_i32(1)
  let arg = builder.iconst_i32(7)
  let block = builder.current_block()
  block.set_terminator(Branch(cond, join.id, [arg], join.id, [arg]))
  let param = builder.add_block_param(join, I32)
  builder.switch_to_block(join)
  builder.return_([param])
  let func = builder.get_function()
  // TODO(milkir): extend constant block-param elimination to inspect Branch
  // arguments directly, or run branch simplification before this standalone pass.
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function branch_const_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 7
      #|    branch v0, block1(v1), block1(v1)
      #|block1(v2:i32):
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer keeps varying branch block params" {
  let builder = FunctionBuilder::FunctionBuilder("branch_varying_block_params")
  builder.add_result(I32)
  let join = builder.create_block()
  let cond = builder.iconst_i32(1)
  let lhs = builder.iconst_i32(7)
  let rhs = builder.iconst_i32(9)
  let block = builder.current_block()
  block.set_terminator(Branch(cond, join.id, [lhs], join.id, [rhs]))
  let param = builder.add_block_param(join, I32)
  builder.switch_to_block(join)
  builder.return_([param])
  let func = builder.get_function()
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes unreachable blocks" {
  let builder = FunctionBuilder::FunctionBuilder("unreachable")
  builder.add_result(I32)
  let exit = builder.create_block()
  let dead = builder.create_block()
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  let result_value = builder.iconst_i32(1)
  builder.return_([result_value])
  builder.switch_to_block(dead)
  let dead_value = builder.iconst_i32(99)
  builder.return_([dead_value])
  let func = builder.get_function()
  let result = eliminate_unreachable_code(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function unreachable() -> i32 {
      #|block0:
      #|    jump block1
      #|block1:
      #|    v0:i32 = iconst 1
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer simplifies constant brz" {
  let builder = FunctionBuilder::FunctionBuilder("branch_simp_brz")
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let zero = builder.iconst_i32(0)
  builder.brz(zero, then_block, else_block)
  builder.switch_to_block(then_block)
  let then_value = builder.iconst_i32(42)
  builder.return_([then_value])
  builder.switch_to_block(else_block)
  let else_value = builder.iconst_i32(100)
  builder.return_([else_value])
  let func = builder.get_function()
  let result = simplify_branches(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_simp_brz() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 0
      #|    jump block1
      #|block1:
      #|    v1:i32 = iconst 42
      #|    return v1
      #|block2:
      #|    v2:i32 = iconst 100
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer simplifies constant br_table" {
  let builder = FunctionBuilder::FunctionBuilder("branch_simp_table")
  let target0 = builder.create_block()
  let target1 = builder.create_block()
  let default_target = builder.create_block()
  let index = builder.iconst_i32(1)
  builder.br_table(index, [target0, target1], default_target)
  builder.switch_to_block(target0)
  builder.trap("target0")
  builder.switch_to_block(target1)
  builder.trap("target1")
  builder.switch_to_block(default_target)
  builder.trap("default")
  let func = builder.get_function()
  let result = simplify_branches(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_simp_table() {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    jump block2
      #|block1:
      #|    trap "target0"
      #|block2:
      #|    trap "target1"
      #|block3:
      #|    trap "default"
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer threads trivial jump blocks" {
  let builder = FunctionBuilder::FunctionBuilder("thread_jump")
  let middle = builder.create_block()
  let exit = builder.create_block()
  builder.jump(middle, [])
  builder.switch_to_block(middle)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.trap("exit")
  let func = builder.get_function()
  let result = thread_jumps(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function thread_jump() {
      #|block0:
      #|    jump block2
      #|block1:
      #|    jump block2
      #|block2:
      #|    trap "exit"
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer threads jump args through block params" {
  let builder = FunctionBuilder::FunctionBuilder("thread_jump_args")
  builder.add_result(I32)
  let middle = builder.create_block()
  let exit = builder.create_block()
  let a = builder.iconst_i32(1)
  let b = builder.iconst_i32(2)
  builder.jump(middle, [a, b])
  let p0 = builder.add_block_param(middle, I32)
  let p1 = builder.add_block_param(middle, I32)
  builder.switch_to_block(middle)
  builder.jump(exit, [p1, p0])
  let q0 = builder.add_block_param(exit, I32)
  let q1 = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  let sum = builder.iadd(q0, q1)
  builder.return_([sum])
  let func = builder.get_function()
  let result = thread_jumps(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function thread_jump_args() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    jump block2(v1, v0)
      #|block1(v2:i32, v3:i32):
      #|    jump block2(v3, v2)
      #|block2(v4:i32, v5:i32):
      #|    v6:i32 = iadd v4, v5
      #|    return v6
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer merges straight line blocks" {
  let builder = FunctionBuilder::FunctionBuilder("merge_blocks")
  builder.add_result(I32)
  let exit = builder.create_block()
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  let value = builder.iconst_i32(7)
  builder.return_([value])
  let func = builder.get_function()
  let result = merge_blocks(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function merge_blocks() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 7
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer does not merge block with params" {
  let builder = FunctionBuilder::FunctionBuilder("merge_skip_params")
  builder.add_result(I32)
  let exit = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(exit, [arg])
  let param = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  builder.return_([param])
  let func = builder.get_function()
  let result = merge_blocks(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "CSE keeps duplicate loads without alias metadata" {
  let builder = FunctionBuilder::FunctionBuilder("no_load_cse")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  let _loaded0 = builder.load_ptr(I32, ptr, offset)
  let loaded1 = builder.load_ptr(I32, ptr, offset)
  builder.return_([loaded1])
  let func = builder.get_function()
  let stats = cse_gvn_global(func)
  inspect(stats.result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function no_load_cse(v0:ptr) -> i32 {
      #|block0:
      #|    v1:i64 = iconst 0
      #|    v2:i32 = load.i32 v0, v1
      #|    v3:i32 = load.i32 v0, v1
      #|    return v3
      #|}
      #|
    ),
  )
}
