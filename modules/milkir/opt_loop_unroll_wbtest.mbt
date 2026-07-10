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
fn require_full_unroll_plan(func : Function) -> FullUnrollPlan raise {
  let loops = CFG::build(func).find_loops()
  if loops.length() != 1 {
    fail("expected exactly one loop")
  }
  match analyze_i32_full_unroll(func, CFG::build(func), loops[0]) {
    Apply(plan) => plan
    Skip(reason) => fail("expected an unroll plan, got: \{reason}")
  }
}

///|
fn require_unroll_skip_without_mutation(func : Function) -> Unit raise {
  let before = func.print()
  let result = full_unroll_i32_loops(func)
  if result.changed {
    fail("unsupported loop was transformed")
  }
  if func.print() != before {
    fail("unsupported loop was mutated")
  }
  func.verify()
}

///|
test "full-unroll analysis counts canonical I32 trips from zero through the bound" {
  for expected in 0..<(MAX_FULL_UNROLL_TRIP_COUNT + 1) {
    let fixture = make_canonical_i32_loop(0, expected, 1)
    let plan = require_full_unroll_plan(fixture.func)
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
  let result = full_unroll_i32_loops(fixture.func)
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
  let too_large = make_canonical_i32_loop(0, MAX_FULL_UNROLL_TRIP_COUNT + 1, 1)
  require_unroll_skip_without_mutation(too_large.func)
  let too_wide = make_canonical_i32_loop(0, MAX_FULL_UNROLL_TRIP_COUNT, 1)
  for _ in 0..<6 {
    let result = too_wide.func.new_value(I32)
    too_wide.body.append_inst(
      too_wide.func.new_inst(Iadd, [too_wide.induction, too_wide.step], [result]),
    )
  }
  require_unroll_skip_without_mutation(too_wide.func)
}
