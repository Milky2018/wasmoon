///|
priv struct CanonicalI32LoopFixture {
  func : Function
  preheader : Block
  header : Block
  body : Block
  latch : Block
  exit : Block
  induction : Value
  step : Value
}

///|
priv struct CarriedEffectLoopFixture {
  func : Function
  preheader : Block
  header : Block
  latch : Block
}

///|
priv struct CountedLoopFixture {
  func : Function
}

///|
priv enum TestBranchPolarity {
  ContinueOnTrue
  ContinueOnFalseWithBrz
}

///|
fn make_canonical_i32_loop(
  initial : Int,
  bound_value : Int,
  step_value : Int,
) -> CanonicalI32LoopFixture {
  let builder = FunctionBuilder::FunctionBuilder("canonical_i32_loop")
  let preheader = builder.current_block()
  let initial_value = builder.iconst_i32(initial)
  let bound = builder.iconst_i32(bound_value)
  let step = builder.iconst_i32(step_value)
  let one = builder.iconst_i32(1)
  let header = builder.create_block()
  let body = builder.create_block()
  let latch = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [initial_value])
  let induction = builder.add_block_param(header, I32)
  builder.switch_to_block(header)
  let condition = builder.icmp_slt(induction, bound)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  let incremented = builder.iadd(induction, one)
  builder.imul(incremented, one) |> ignore
  builder.jump(latch, [])
  builder.switch_to_block(latch)
  let next = builder.iadd(induction, step)
  builder.jump(header, [next])
  builder.switch_to_block(exit)
  builder.return_([])
  {
    func: builder.get_function(),
    preheader,
    header,
    body,
    latch,
    exit,
    induction,
    step,
  }
}

///|
fn make_carried_effect_loop(bound_value : Int) -> CarriedEffectLoopFixture {
  let builder = FunctionBuilder::FunctionBuilder("carried_effect_loop")
  let callee = builder.add_param(Ptr)
  let address = builder.add_param(Ptr)
  let preheader = builder.current_block()
  let initial = builder.iconst_i32(0)
  let bound = builder.iconst_i32(bound_value)
  let step = builder.iconst_i32(1)
  let initial_accumulator = builder.iconst_i32(10)
  let offset = builder.iconst_i64(0L)
  let header = builder.create_block()
  let body = builder.create_block()
  let latch = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [initial, initial_accumulator])
  let induction = builder.add_block_param(header, I32)
  let accumulator = builder.add_block_param(header, I32)
  builder.switch_to_block(header)
  let condition = builder.icmp_slt(induction, bound)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  let func = builder.get_function()
  let first = func.new_value(I32)
  let second = func.new_value(I32)
  let call = func.new_inst(CallIndirect(Signature([], [I32, I32])), [callee], [
    first, second,
  ])
  call.add_metadata(Comment("effect order"))
  body.append_inst(call)
  let pair_sum = func.new_value(I32)
  body.append_inst(func.new_inst(Iadd, [first, second], [pair_sum]))
  let loaded = func.new_value(I32)
  body.append_inst(func.new_inst(LoadPtr(I32), [address, offset], [loaded]))
  let accumulated = func.new_value(I32)
  body.append_inst(func.new_inst(Iadd, [accumulator, pair_sum], [accumulated]))
  let next_accumulator = func.new_value(I32)
  body.append_inst(
    func.new_inst(Iadd, [accumulated, loaded], [next_accumulator]),
  )
  body.append_inst(
    func.new_inst(StorePtr(I32), [address, next_accumulator, offset], []),
  )
  body.append_inst(func.new_inst(Trap("effect trap"), [next_accumulator], []))
  builder.jump(latch, [])
  builder.switch_to_block(latch)
  let next_induction = builder.iadd(induction, step)
  builder.jump(header, [next_induction, next_accumulator])
  builder.switch_to_block(exit)
  builder.return_([])
  { func, preheader, header, latch }
}

///|
fn make_counted_loop(
  ty : Type,
  initial_raw : Int64,
  bound_raw : Int64,
  step_raw : Int64,
  cc : IntCC,
  update_opcode : Opcode,
  reversed_operands : Bool,
  polarity : TestBranchPolarity,
) -> CountedLoopFixture {
  let builder = FunctionBuilder::FunctionBuilder("counted_loop")
  let initial = builder.emit_inst(ty, Iconst(initial_raw), [])
  let bound = builder.emit_inst(ty, Iconst(bound_raw), [])
  let step = builder.emit_inst(ty, Iconst(step_raw), [])
  let header = builder.create_block()
  let body = builder.create_block()
  let latch = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [initial])
  let induction = builder.add_block_param(header, ty)
  builder.switch_to_block(header)
  let condition = if reversed_operands {
    builder.icmp(cc, bound, induction)
  } else {
    builder.icmp(cc, induction, bound)
  }
  match polarity {
    ContinueOnTrue => builder.brnz(condition, body, exit)
    ContinueOnFalseWithBrz =>
      builder.current_block().set_terminator(Brz(condition, body.id, exit.id))
  }
  builder.switch_to_block(body)
  builder.emit_inst(ty, Copy, [induction]) |> ignore
  builder.jump(latch, [])
  builder.switch_to_block(latch)
  let next = builder.emit_inst(ty, update_opcode, [induction, step])
  builder.jump(header, [next])
  builder.switch_to_block(exit)
  builder.return_([])
  { func: builder.get_function() }
}

///|
fn require_counted_loop_plan(func : Function) -> CountedLoopPlan raise {
  let loops = CFG::build(func).find_loops()
  if loops.length() != 1 {
    fail("expected exactly one loop")
  }
  match
    analyze_counted_loop(
      func,
      CFG::build(func),
      loops[0],
      MAX_FACTOR_TWO_TRIP_COUNT,
    ) {
    Apply(plan) => plan
    Skip(reason) => fail("expected an unroll plan, got: \{reason}")
  }
}

///|
fn require_counted_trip_count(func : Function, expected : Int) -> Unit raise {
  let plan = require_counted_loop_plan(func)
  if plan.trip_count != expected {
    fail("unexpected counted-loop trip count")
  }
}

///|
fn require_unroll_skip_without_mutation(func : Function) -> Unit raise {
  let before = func.print()
  let result = unroll_counted_loops(func)
  if result.changed {
    fail("unsupported loop was transformed")
  }
  if func.print() != before {
    fail("unsupported loop was mutated")
  }
  func.verify()
}

///|
fn evaluate_canonical_instructions(
  instructions : Array[Inst],
  values : @hashmap.HashMap[Int, Int64],
) -> Int raise {
  let mut body_executions = 0
  for inst in instructions {
    match inst.opcode {
      Iconst(value) => values.set(inst.results[0].id, value)
      Iadd => {
        let lhs = values.get(inst.operands[0].id).unwrap()
        let rhs = values.get(inst.operands[1].id).unwrap()
        values.set(inst.results[0].id, lhs + rhs)
      }
      Imul => {
        let lhs = values.get(inst.operands[0].id).unwrap()
        let rhs = values.get(inst.operands[1].id).unwrap()
        values.set(inst.results[0].id, lhs * rhs)
        body_executions = body_executions + 1
      }
      _ => fail("unexpected opcode in canonical loop evaluator")
    }
  }
  body_executions
}

///|
fn evaluate_canonical_i32_loop(
  fixture : CanonicalI32LoopFixture,
) -> (Int64, Int) raise {
  let values : @hashmap.HashMap[Int, Int64] = HashMap([])
  let mut body_executions = evaluate_canonical_instructions(
    fixture.preheader.instructions,
    values,
  )
  let bound_value = values
    .get(fixture.header.instructions[0].operands[1].id)
    .unwrap()
  let mut induction = match fixture.preheader.terminator {
    Some(Jump(_, args)) => values.get(args[0].id).unwrap()
    _ => fail("expected preheader jump")
  }
  let mut iterations = 0
  while induction < bound_value {
    values.set(fixture.induction.id, induction)
    body_executions = body_executions +
      evaluate_canonical_instructions(fixture.body.instructions, values)
    body_executions = body_executions +
      evaluate_canonical_instructions(fixture.latch.instructions, values)
    induction = match fixture.latch.terminator {
      Some(Jump(_, args)) => values.get(args[0].id).unwrap()
      _ => fail("expected latch jump")
    }
    iterations = iterations + 1
    if iterations > 1000 {
      fail("canonical loop evaluator did not terminate")
    }
  }
  (induction, body_executions)
}

///|
test "full-unroll analysis counts canonical I32 trips from zero through the bound" {
  for expected in 0..<(MAX_FULL_UNROLL_TRIP_COUNT + 1) {
    let fixture = make_canonical_i32_loop(0, expected, 1)
    let plan = require_counted_loop_plan(fixture.func)
    if plan.trip_count != expected {
      fail("expected \{expected} trips, got \{plan.trip_count}")
    }
  }
}

///|
test "full unrolling clones dependent pure instructions with fresh ids" {
  let fixture = make_canonical_i32_loop(0, 3, 1)
  let original_preheader_insts = fixture.preheader.instructions.length()
  let first_fresh_value = fixture.func.next_value_id
  let first_fresh_inst = fixture.func.next_inst_id
  let result = unroll_counted_loops(fixture.func)
  inspect(result.changed, content="true")
  let cloned = fixture.preheader.instructions[original_preheader_insts:]
  inspect(cloned.length(), content="9")
  let mut current_induction = fixture.preheader.instructions[0].results[0]
  for iteration in 0..<3 {
    let body_add = cloned[iteration * 3]
    let body_mul = cloned[iteration * 3 + 1]
    let latch_add = cloned[iteration * 3 + 2]
    if body_add.id < first_fresh_inst ||
      body_mul.id < first_fresh_inst ||
      latch_add.id < first_fresh_inst {
      fail("cloned instruction reused an existing id")
    }
    if body_add.results[0].id < first_fresh_value ||
      body_mul.results[0].id < first_fresh_value ||
      latch_add.results[0].id < first_fresh_value {
      fail("cloned instruction reused an existing value id")
    }
    if body_add.operands[0] != current_induction {
      fail("body induction dependency was not rewritten")
    }
    if body_mul.operands[0] != body_add.results[0] {
      fail("intra-iteration dependency was not rewritten")
    }
    if latch_add.operands[0] != current_induction {
      fail("latch induction dependency was not rewritten")
    }
    current_induction = latch_add.results[0]
  }
  match fixture.preheader.terminator {
    Some(Jump(target, args)) => {
      inspect(target, content="1")
      inspect(args.length(), content="1")
      if args[0] != current_induction {
        fail("preheader did not forward the final induction value")
      }
    }
    _ => fail("expected preheader jump")
  }
  fixture.func.verify()
}

///|
test "full unrolling preserves carried values, multi-results, and effect order" {
  let fixture = make_carried_effect_loop(2)
  let original_preheader_insts = fixture.preheader.instructions.length()
  let first_fresh_value = fixture.func.next_value_id
  let first_fresh_inst = fixture.func.next_inst_id
  let result = unroll_counted_loops(fixture.func)
  inspect(result.changed, content="true")
  let cloned = fixture.preheader.instructions[original_preheader_insts:]
  inspect(cloned.length(), content="16")
  let mut current_induction = fixture.preheader.instructions[0].results[0]
  let mut current_accumulator = fixture.preheader.instructions[3].results[0]
  for iteration in 0..<2 {
    let base = iteration * 8
    let call = cloned[base]
    let pair_sum = cloned[base + 1]
    let load = cloned[base + 2]
    let accumulated = cloned[base + 3]
    let next_accumulator = cloned[base + 4]
    let store = cloned[base + 5]
    let trap = cloned[base + 6]
    let next_induction = cloned[base + 7]
    if !(call.opcode is CallIndirect(_)) ||
      pair_sum.opcode != Iadd ||
      load.opcode != LoadPtr(I32) ||
      accumulated.opcode != Iadd ||
      next_accumulator.opcode != Iadd ||
      store.opcode != StorePtr(I32) ||
      trap.opcode != Trap("effect trap") ||
      next_induction.opcode != Iadd {
      fail("effectful instruction order changed")
    }
    if call.id < first_fresh_inst || call.results.length() != 2 {
      fail("multi-result call was not freshly cloned")
    }
    for value in call.results {
      if value.id < first_fresh_value {
        fail("multi-result call reused an existing value id")
      }
    }
    if pair_sum.operands[0] != call.results[0] ||
      pair_sum.operands[1] != call.results[1] {
      fail("multi-result dependencies were not remapped")
    }
    if accumulated.operands[0] != current_accumulator ||
      accumulated.operands[1] != pair_sum.results[0] ||
      next_accumulator.operands[0] != accumulated.results[0] ||
      next_accumulator.operands[1] != load.results[0] {
      fail("carried accumulator dependencies were not remapped")
    }
    if store.operands[1] != next_accumulator.results[0] ||
      trap.operands[0] != next_accumulator.results[0] {
      fail("effect operands were not remapped")
    }
    if next_induction.operands[0] != current_induction {
      fail("carried induction dependency was not remapped")
    }
    if call.metadata != [Comment("effect order")] {
      fail("instruction metadata was not preserved")
    }
    current_induction = next_induction.results[0]
    current_accumulator = next_accumulator.results[0]
  }
  match fixture.preheader.terminator {
    Some(Jump(target, args)) =>
      if target != fixture.header.id ||
        args.length() != 2 ||
        args[0] != current_induction ||
        args[1] != current_accumulator {
        fail("final carried state was not forwarded to the header")
      }
    _ => fail("expected preheader jump")
  }
  fixture.func.verify()
}

///|
test "full unrolling rejects an unmappable carried edge without mutation" {
  let fixture = make_carried_effect_loop(2)
  let next_induction = fixture.latch.instructions[0].results[0]
  let header_condition = fixture.header.instructions[0].results[0]
  fixture.latch.set_terminator(
    Jump(fixture.header.id, [next_induction, header_condition]),
  )
  require_unroll_skip_without_mutation(fixture.func)
}

///|
test "factor-two unrolling composes two transitions for an even trip count" {
  let fixture = make_canonical_i32_loop(0, 10, 1)
  let original_preheader_insts = fixture.preheader.instructions.length()
  let original_latch_insts = fixture.latch.instructions.length()
  let first_state = fixture.latch.instructions[0].results[0]
  let result = unroll_counted_loops(fixture.func)
  inspect(result.changed, content="true")
  inspect(
    fixture.preheader.instructions.length(),
    content=original_preheader_insts.to_string(),
  )
  inspect(fixture.latch.instructions.length(), content="4")
  let second_body_add = fixture.latch.instructions[original_latch_insts]
  let second_body_mul = fixture.latch.instructions[original_latch_insts + 1]
  let second_latch_add = fixture.latch.instructions[original_latch_insts + 2]
  if second_body_add.operands[0] != first_state ||
    second_body_mul.operands[0] != second_body_add.results[0] ||
    second_latch_add.operands[0] != first_state {
    fail("factor-two transition did not start from the first transition state")
  }
  match fixture.latch.terminator {
    Some(Jump(target, args)) =>
      if target != fixture.header.id ||
        args.length() != 1 ||
        args[0] != second_latch_add.results[0] {
        fail("factor-two latch did not forward the second transition state")
      }
    _ => fail("expected latch jump")
  }
  fixture.func.verify()
}

///|
test "factor-two unrolling peels one transition for an odd trip count" {
  let fixture = make_canonical_i32_loop(0, 11, 1)
  let original_preheader_insts = fixture.preheader.instructions.length()
  let original_latch_insts = fixture.latch.instructions.length()
  let result = unroll_counted_loops(fixture.func)
  inspect(result.changed, content="true")
  inspect(
    fixture.preheader.instructions.length() - original_preheader_insts,
    content="3",
  )
  inspect(
    fixture.latch.instructions.length() - original_latch_insts,
    content="3",
  )
  let peeled_latch = fixture.preheader.instructions[fixture.preheader.instructions.length() -
    1]
  match fixture.preheader.terminator {
    Some(Jump(target, args)) =>
      if target != fixture.header.id ||
        args.length() != 1 ||
        args[0] != peeled_latch.results[0] {
        fail("odd-trip remainder was not forwarded to the header")
      }
    _ => fail("expected preheader jump")
  }
  fixture.func.verify()
}

///|
test "factor-two policy preserves zero-trip and one-trip loops" {
  let zero = make_canonical_i32_loop(0, 0, 1)
  let zero_before = zero.func.print()
  inspect(unroll_counted_loops(zero.func).changed, content="false")
  if zero.func.print() != zero_before {
    fail("zero-trip loop was mutated")
  }
  let one = make_canonical_i32_loop(0, 1, 1)
  let original_preheader_insts = one.preheader.instructions.length()
  inspect(unroll_counted_loops(one.func).changed, content="true")
  inspect(
    one.preheader.instructions.length() - original_preheader_insts,
    content="3",
  )
  inspect(one.latch.instructions.length(), content="1")
  one.func.verify()
}

///|
test "factor-two unrolling preserves carried effects in both transitions" {
  let fixture = make_carried_effect_loop(10)
  let original_latch_insts = fixture.latch.instructions.length()
  let first_state = match fixture.latch.terminator {
    Some(Jump(_, args)) => args
    _ => fail("expected latch jump")
  }
  let result = unroll_counted_loops(fixture.func)
  inspect(result.changed, content="true")
  inspect(
    fixture.latch.instructions.length() - original_latch_insts,
    content="8",
  )
  let call = fixture.latch.instructions[original_latch_insts]
  let pair_sum = fixture.latch.instructions[original_latch_insts + 1]
  let load = fixture.latch.instructions[original_latch_insts + 2]
  let accumulated = fixture.latch.instructions[original_latch_insts + 3]
  let next_accumulator = fixture.latch.instructions[original_latch_insts + 4]
  let store = fixture.latch.instructions[original_latch_insts + 5]
  let trap = fixture.latch.instructions[original_latch_insts + 6]
  let next_induction = fixture.latch.instructions[original_latch_insts + 7]
  if !(call.opcode is CallIndirect(_)) ||
    pair_sum.opcode != Iadd ||
    load.opcode != LoadPtr(I32) ||
    accumulated.opcode != Iadd ||
    next_accumulator.opcode != Iadd ||
    store.opcode != StorePtr(I32) ||
    trap.opcode != Trap("effect trap") ||
    next_induction.opcode != Iadd {
    fail("factor-two effect order changed")
  }
  if accumulated.operands[0] != first_state[1] ||
    next_induction.operands[0] != first_state[0] ||
    store.operands[1] != next_accumulator.results[0] ||
    trap.operands[0] != next_accumulator.results[0] {
    fail("factor-two carried effects were not remapped")
  }
  match fixture.latch.terminator {
    Some(Jump(_, args)) =>
      if args[0] != next_induction.results[0] ||
        args[1] != next_accumulator.results[0] {
        fail("factor-two latch did not forward the second carried state")
      }
    _ => fail("expected latch jump")
  }
  fixture.func.verify()
}

///|
test "factor-two transformed loops match the original state and body count" {
  for trip_count in [0, 1, 9, 10, 11] {
    let original = make_canonical_i32_loop(0, trip_count, 1)
    let expected = evaluate_canonical_i32_loop(original)
    let transformed = make_canonical_i32_loop(0, trip_count, 1)
    unroll_counted_loops(transformed.func) |> ignore
    let actual = evaluate_canonical_i32_loop(transformed)
    if actual != expected {
      fail("factor-two differential mismatch at trip \{trip_count}")
    }
  }
}

///|
test "counted-loop analysis supports signed and unsigned I32 and I64 relations" {
  let cases = [
    (Type::I32, 0L, 10L, 3L, Slt, Iadd, 4, "i32 slt"),
    (Type::I32, 0L, 10L, 3L, Sle, Iadd, 4, "i32 sle"),
    (Type::I32, 10L, 0L, 3L, Sgt, Isub, 4, "i32 sgt"),
    (Type::I32, 10L, 0L, 3L, Sge, Isub, 4, "i32 sge"),
    (Type::I32, 0L, 10L, 3L, Ult, Iadd, 4, "i32 ult"),
    (Type::I32, 10L, 2L, 3L, Uge, Isub, 3, "i32 uge"),
    (Type::I64, 0L, 10L, 3L, Slt, Iadd, 4, "i64 slt"),
    (Type::I64, 0L, 10L, 3L, Sle, Iadd, 4, "i64 sle"),
    (Type::I64, 10L, 0L, 3L, Sgt, Isub, 4, "i64 sgt"),
    (Type::I64, 10L, 0L, 3L, Sge, Isub, 4, "i64 sge"),
    (Type::I64, 10L, 0L, -3L, Sgt, Iadd, 4, "i64 negative add"),
    (Type::I64, 0L, 10L, -3L, Slt, Isub, 4, "i64 negative sub"),
    (Type::I64, 0L, 10L, 3L, Ult, Iadd, 4, "i64 ult"),
    (Type::I64, 0L, 10L, 3L, Ule, Iadd, 4, "i64 ule"),
    (Type::I64, 10L, 2L, 3L, Ugt, Isub, 3, "i64 ugt"),
    (Type::I64, 10L, 2L, 3L, Uge, Isub, 3, "i64 uge"),
  ]
  for item in cases {
    let (ty, initial, bound, step, cc, update, expected, label) = item
    let fixture = make_counted_loop(
      ty,
      initial,
      bound,
      step,
      cc,
      update,
      false,
      ContinueOnTrue,
    )
    let loops = CFG::build(fixture.func).find_loops()
    match
      analyze_counted_loop(
        fixture.func,
        CFG::build(fixture.func),
        loops[0],
        MAX_FACTOR_TWO_TRIP_COUNT,
      ) {
      Apply(plan) =>
        if plan.trip_count != expected {
          fail("unexpected trip count for \{label}")
        }
      Skip(reason) => fail("\{label}: \{reason}")
    }
  }
}

///|
test "counted-loop analysis normalizes reversed operands and branch polarity" {
  let reversed = make_counted_loop(
    I64,
    0L,
    10L,
    3L,
    Sgt,
    Iadd,
    true,
    ContinueOnTrue,
  )
  require_counted_trip_count(reversed.func, 4)
  let false_branch = make_counted_loop(
    I64,
    0L,
    10L,
    3L,
    Sge,
    Iadd,
    false,
    ContinueOnFalseWithBrz,
  )
  require_counted_trip_count(false_branch.func, 4)
}

///|
test "counted-loop analysis handles valid signed and unsigned boundaries" {
  let signed_i32_high = make_counted_loop(
    I32,
    2147483646L,
    2147483647L,
    1L,
    Slt,
    Iadd,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(signed_i32_high.func, 1)
  let unsigned_i32_high = make_counted_loop(
    I32,
    -2L,
    -1L,
    1L,
    Ult,
    Iadd,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(unsigned_i32_high.func, 1)
  let signed_high = make_counted_loop(
    I64,
    9223372036854775806L,
    9223372036854775807L,
    1L,
    Slt,
    Iadd,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(signed_high.func, 1)
  let signed_low = make_counted_loop(
    I64,
    -9223372036854775807L,
    -9223372036854775808L,
    1L,
    Sgt,
    Isub,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(signed_low.func, 1)
  let unsigned_high = make_counted_loop(
    I64,
    -2L,
    -1L,
    1L,
    Ult,
    Iadd,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(unsigned_high.func, 1)
  let unsigned_low = make_counted_loop(
    I64,
    1L,
    0L,
    1L,
    Ugt,
    Isub,
    false,
    ContinueOnTrue,
  )
  require_counted_trip_count(unsigned_low.func, 1)
}

///|
test "counted-loop analysis rejects wraparound and invalid directions unchanged" {
  let cases = [
    make_counted_loop(
      I32,
      2147483646L,
      2147483647L,
      2L,
      Slt,
      Iadd,
      false,
      ContinueOnTrue,
    ),
    make_counted_loop(I32, -2L, -1L, 2L, Ult, Iadd, false, ContinueOnTrue),
    make_counted_loop(
      I64,
      9223372036854775806L,
      9223372036854775807L,
      2L,
      Slt,
      Iadd,
      false,
      ContinueOnTrue,
    ),
    make_counted_loop(
      I64,
      -9223372036854775807L,
      -9223372036854775808L,
      2L,
      Sgt,
      Isub,
      false,
      ContinueOnTrue,
    ),
    make_counted_loop(
      I64,
      9223372036854775806L,
      9223372036854775807L,
      1L,
      Sle,
      Iadd,
      false,
      ContinueOnTrue,
    ),
    make_counted_loop(I64, -2L, -1L, 2L, Ult, Iadd, false, ContinueOnTrue),
    make_counted_loop(I64, -2L, -1L, 1L, Ule, Iadd, false, ContinueOnTrue),
    make_counted_loop(I64, 0L, 10L, 0L, Slt, Iadd, false, ContinueOnTrue),
    make_counted_loop(I64, 0L, 10L, 1L, Slt, Isub, false, ContinueOnTrue),
    make_counted_loop(
      I64,
      -9223372036854775808L,
      9223372036854775807L,
      1L,
      Slt,
      Iadd,
      false,
      ContinueOnTrue,
    ),
  ]
  for fixture in cases {
    require_unroll_skip_without_mutation(fixture.func)
  }
  let dynamic = make_counted_loop(
    I64,
    0L,
    10L,
    1L,
    Slt,
    Iadd,
    false,
    ContinueOnTrue,
  )
  let dynamic_bound = dynamic.func.add_param(I64)
  dynamic.func.blocks[1].instructions[0].operands[1] = dynamic_bound
  require_unroll_skip_without_mutation(dynamic.func)
}

///|
test "counted-loop unrolling transforms verified I64 loops" {
  let fixture = make_counted_loop(
    I64,
    0L,
    10L,
    3L,
    Slt,
    Iadd,
    false,
    ContinueOnTrue,
  )
  inspect(unroll_counted_loops(fixture.func).changed, content="true")
  fixture.func.verify()
}

///|
test "O3 invokes safe counted-loop unrolling" {
  let fixture = make_carried_effect_loop(10)
  optimize_with_level(fixture.func, O3) |> ignore
  let mut indirect_calls = 0
  for block in fixture.func.blocks {
    for inst in block.instructions {
      if inst.opcode is CallIndirect(_) {
        indirect_calls = indirect_calls + 1
      }
    }
  }
  inspect(indirect_calls, content="2")
  fixture.func.verify()
}

///|
test "full-unroll analysis skips reversed predicates and dynamic bounds" {
  let reversed = make_canonical_i32_loop(0, 4, 1)
  let compare = reversed.header.instructions[0]
  let lhs = compare.operands[0]
  compare.operands[0] = compare.operands[1]
  compare.operands[1] = lhs
  require_unroll_skip_without_mutation(reversed.func)
  let dynamic = make_canonical_i32_loop(0, 4, 1)
  let dynamic_bound = dynamic.func.add_param(I32)
  dynamic.header.instructions[0].operands[1] = dynamic_bound
  require_unroll_skip_without_mutation(dynamic.func)
  let header_dependency = make_canonical_i32_loop(0, 4, 1)
  header_dependency.body.instructions[0].operands[0] = header_dependency.header.instructions[0].results[0]
  require_unroll_skip_without_mutation(header_dependency.func)
}

///|
test "full-unroll analysis skips multiple latches and early exits" {
  let multiple_latches = make_canonical_i32_loop(0, 4, 1)
  let branch_condition = multiple_latches.func.add_param(I32)
  let second_latch = multiple_latches.func.new_block([])
  multiple_latches.body.set_terminator(
    Branch(branch_condition, multiple_latches.latch.id, [], second_latch.id, []),
  )
  let second_next = multiple_latches.func.new_value(I32)
  second_latch.append_inst(
    multiple_latches.func.new_inst(
      Iadd,
      [multiple_latches.induction, multiple_latches.step],
      [second_next],
    ),
  )
  second_latch.set_terminator(Jump(multiple_latches.header.id, [second_next]))
  require_unroll_skip_without_mutation(multiple_latches.func)
  let early_exit = make_canonical_i32_loop(0, 4, 1)
  let exit_condition = early_exit.func.add_param(I32)
  early_exit.body.set_terminator(
    Branch(exit_condition, early_exit.latch.id, [], early_exit.exit.id, []),
  )
  require_unroll_skip_without_mutation(early_exit.func)
}

///|
test "full-unroll analysis skips unsafe arithmetic and excessive growth" {
  let overflowing = make_canonical_i32_loop(2147483646, 2147483647, 2)
  require_unroll_skip_without_mutation(overflowing.func)
  let too_large = make_canonical_i32_loop(0, MAX_FACTOR_TWO_TRIP_COUNT + 1, 1)
  require_unroll_skip_without_mutation(too_large.func)
  let too_wide = make_canonical_i32_loop(0, MAX_FULL_UNROLL_TRIP_COUNT, 1)
  for _ in 0..<62 {
    let result = too_wide.func.new_value(I32)
    too_wide.body.append_inst(
      too_wide.func.new_inst(Iadd, [too_wide.induction, too_wide.step], [result]),
    )
  }
  require_unroll_skip_without_mutation(too_wide.func)
}
