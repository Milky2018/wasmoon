///|
fn dead_constant_function(name : String, count : Int) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  for i in 0..<count {
    builder.iconst_i32(i) |> ignore
  }
  builder.return_([])
  builder.get_function()
}

///|
fn copy_chain_function(name : String, count : Int) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let mut value = input
  for _ in 0..<count {
    value = builder.copy(value)
  }
  builder.return_([value])
  builder.get_function()
}

///|
fn foldable_chain_function(name : String, count : Int) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  builder.add_result(I32)
  let zero = builder.iconst_i32(0)
  let mut value = builder.iconst_i32(1)
  for _ in 2..<count {
    value = builder.iadd(value, zero)
  }
  builder.return_([value])
  builder.get_function()
}

///|
fn duplicate_expression_function(
  name : String,
  count : Int,
) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  let mut value = lhs
  for _ in 0..<count {
    value = builder.iadd(lhs, rhs)
  }
  builder.return_([value])
  builder.get_function()
}

///|
test "O1 mandatory cleanup removes 300 dead constants" {
  let func = dead_constant_function("o1_dead_300", 300)
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="0")
}

///|
test "O1 mandatory cleanup canonicalizes a 300-copy chain" {
  let func = copy_chain_function("o1_alias_300", 300)
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="0")
  inspect(func.verify(), content="()")
}

///|
test "O1 folds a 300-instruction live arithmetic chain" {
  let func = foldable_chain_function("o1_fold_300", 300)
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="1")
  inspect(func.verify(), content="()")
}

///|
test "O0 O1 and O2 mandatory cleanup cross size boundaries" {
  let counts = [299, 300, 301, 599, 600, 601]
  let remaining : Array[Int] = []
  for level in [O0, O1, O2] {
    for count in counts {
      let func = dead_constant_function("dead_boundary", count)
      optimize_with_level(func, level) |> ignore
      remaining.push(instruction_count(func))
    }
  }
  debug_inspect(
    remaining,
    content=(
      #|[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ),
  )
}

///|
test "mandatory cleanup preserves effects above size boundaries" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("effectful_600")
  for i in 0..<600 {
    builder.iconst_i32(i) |> ignore
  }
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.return_([])
  let func = builder.get_function()
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="1")
  inspect(
    func.block_instruction_at(func.blocks[0], 0).unwrap().opcode is Call(_),
    content="true",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN memory budget does not stop cheap expression numbering" {
  let func = duplicate_expression_function("gvn_partial", 5)
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    2,
    FunctionAnalysis::build(func),
  )
  inspect(stats.work_done, content="2")
  inspect(stats.budget_exhausted, content="true")
  inspect(
    func.block_instruction_at(func.blocks[0], 1).unwrap().opcode,
    content="Scalar(Copy)",
  )
  inspect(
    func.block_instruction_at(func.blocks[0], 2).unwrap().opcode,
    content="Scalar(Copy)",
  )
  inspect(
    func.block_instruction_at(func.blocks[0], 4).unwrap().opcode,
    content="Scalar(Copy)",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN early termination preserves external effects" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gvn_partial_effect")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  builder.iadd(lhs, rhs) |> ignore
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  let result = builder.iadd(lhs, rhs)
  builder.return_([result])
  let func = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    2,
    FunctionAnalysis::build(func),
  )
  inspect(stats.budget_exhausted, content="true")
  inspect(
    func.block_instruction_at(func.blocks[0], 1).unwrap().opcode is Call(_),
    content="true",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN uses work units instead of a function-size switch" {
  debug_inspect(
    [
      acyclic_memory_work_budget(299, O2),
      acyclic_memory_work_budget(300, O2),
      acyclic_memory_work_budget(301, O2),
      acyclic_memory_work_budget(600, O2),
    ],
    content="[299, 300, 300, 300]",
  )
}

///|
test "O3 receives a larger but bounded memory-analysis budget" {
  debug_inspect(
    [
      acyclic_memory_work_budget(300, O2),
      acyclic_memory_work_budget(301, O2),
      acyclic_memory_work_budget(301, O3),
      acyclic_memory_work_budget(1200, O3),
      acyclic_memory_work_budget(1201, O3),
    ],
    content="[300, 300, 301, 1200, 1200]",
  )
}

///|
test "GVN retains memory forwarding in a large function budget prefix" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "gvn_large_memory_prefix",
  )
  let pointer = builder.add_param(Ptr)
  let stored = builder.add_param(I32)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  builder.store_ptr(I32, pointer, stored, offset)
  let loaded = builder.load_ptr(I32, pointer, offset)
  for i in 0..<300 {
    builder.iconst_i32(i) |> ignore
  }
  builder.return_([loaded])
  let func = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    300,
    FunctionAnalysis::build(func),
  )
  inspect(stats.work_done, content="300")
  inspect(stats.budget_exhausted, content="true")
  inspect(
    func.block_instruction_at(func.blocks[0], 2).unwrap().opcode,
    content="Scalar(Copy)",
  )
  inspect(func.verify(), content="()")
}

///|
test "rewrite insertion preserves cross-block memory versions" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("rewrite_before_store")
  let pointer = builder.add_param(Ptr)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let next = builder.create_block()
  let offset = builder.iconst_i64(0L)
  let eight = builder.iconst_i32(8)
  let product = builder.imul(input, eight)
  builder.store_ptr(I32, pointer, product, offset)
  builder.jump(next, [])
  builder.switch_to_block(next)
  let loaded = builder.load_ptr(I32, pointer, offset)
  builder.return_([loaded])
  let func = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(
    func.block_instruction_at(func.blocks[1], 0).unwrap().opcode,
    content="Scalar(Copy)",
  )
  inspect(func.print().contains("ishl"), content="true")
  inspect(func.verify(), content="()")
}

///|
test "bounded memory GVN keeps unknown block entries conservative" {
  let build = fn(name : String, trailing : Int) -> @milkir.Function {
    let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
    let pointer = builder.add_param(Ptr)
    let stored = builder.add_param(I32)
    builder.add_result(I32)
    let next = builder.create_block()
    let offset = builder.iconst_i64(0L)
    builder.store_ptr(I32, pointer, stored, offset)
    builder.jump(next, [])
    builder.switch_to_block(next)
    let loaded = builder.load_ptr(I32, pointer, offset)
    for i in 0..<trailing {
      builder.iconst_i32(i) |> ignore
    }
    builder.return_([loaded])
    builder.get_function()
  }
  let small = build("gvn_complete_block_input", 0)
  run_acyclic_optimization_with_budget_and_analysis(
    small,
    instruction_count(small),
    FunctionAnalysis::build(small),
  )
  |> ignore
  inspect(
    small.block_instruction_at(small.blocks[1], 0).unwrap().opcode,
    content="Scalar(Copy)",
  )
  let large = build("gvn_unknown_bounded_block_input", 300)
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    large,
    300,
    FunctionAnalysis::build(large),
  )
  inspect(stats.work_done, content="300")
  inspect(stats.budget_exhausted, content="true")
  inspect(
    large.block_instruction_at(large.blocks[1], 0).unwrap().opcode,
    content="Memory(Load(I32))",
  )
  inspect(small.verify(), content="()")
  inspect(large.verify(), content="()")
}

///|
test "GVN metrics count only instructions visited in reachable blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gvn_reachable_work")
  builder.iconst_i32(1) |> ignore
  builder.return_([])
  let dead_block = builder.create_block()
  builder.switch_to_block(dead_block)
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.return_([])
  let func = builder.get_function()
  inspect(instruction_count(func), content="2")
  inspect(func.verify(), content="()")

  let events : Array[OptimizationPassMetric] = []
  let mut now = 0L
  install_optimization_metrics_sink(
    OptimizationMetricsSink::new(
      fn() {
        now = now + 10L
        now
      },
      fn(event) { events.push(event) },
    ),
  )
  run_acyclic_optimization_pass_with_analysis_at_level(
    func,
    FunctionAnalysis::build(func),
    O2,
  )
  |> ignore
  clear_optimization_metrics_sink()
  inspect(events.length(), content="1")
  inspect(events[0].name, content="acyclic_optimize")
  debug_inspect(events[0].work_done, content="Some(1)")
  debug_inspect(events[0].budget_exhausted, content="Some(false)")
}

///|
test "optimization metrics sink receives pass events and can be cleared" {
  let events : Array[OptimizationPassMetric] = []
  let mut now = 0L
  install_optimization_metrics_sink(
    OptimizationMetricsSink::new(
      fn() {
        now = now + 10L
        now
      },
      fn(event) { events.push(event) },
    ),
  )
  let func = dead_constant_function("metrics", 1)
  run_opt_pass(func, "test_dce", eliminate_dead_code) |> ignore
  clear_optimization_metrics_sink()
  inspect(events.length(), content="1")
  inspect(events[0].name, content="test_dce")
  inspect(events[0].duration_us, content="10")
  inspect(events[0].before_insts, content="1")
  inspect(events[0].after_insts, content="0")
  inspect(events[0].changed, content="true")

  let after_clear = dead_constant_function("metrics_cleared", 1)
  run_opt_pass(after_clear, "cleared_dce", eliminate_dead_code) |> ignore
  inspect(events.length(), content="1")
}

///|
test "O3 runs one acyclic pipeline after structural loop transforms" {
  let events : Array[OptimizationPassMetric] = []
  let mut now = 0L
  install_optimization_metrics_sink(
    OptimizationMetricsSink::new(
      fn() {
        now = now + 10L
        now
      },
      fn(event) { events.push(event) },
    ),
  )
  let func = dead_constant_function("o3_pipeline_order", 1)
  optimize_with_level(func, O3) |> ignore
  clear_optimization_metrics_sink()
  let mut acyclic_count = 0
  let mut acyclic_index = -1
  let mut strength_reduce_index = -1
  for index, event in events {
    if event.name == "acyclic_optimize" {
      acyclic_count = acyclic_count + 1
      acyclic_index = index
    }
    if event.name == "loop_strength_reduce" {
      strength_reduce_index = index
    }
  }
  inspect(acyclic_count, content="1")
  inspect(strength_reduce_index >= 0, content="true")
  inspect(acyclic_index > strength_reduce_index, content="true")
}

///|
/// A single straight-line chain of `count` blocks, each jumping to the next.
/// The dominator tree is one long spine, so optimizer walks must be iterative.
fn deep_block_chain_function(name : String, count : Int) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i32(0)
  let mut value = input
  for _ in 0..<count {
    let next = builder.create_block()
    builder.jump(next, [])
    builder.switch_to_block(next)
    value = builder.iadd(value, zero)
  }
  builder.return_([value])
  builder.get_function()
}

///|
/// The same spine with nothing in the blocks but their terminator. GVN walks
/// the complete dominator tree even after its precise-memory budget runs out,
/// so this locks down the non-recursive traversal at extreme depth.
fn deep_empty_block_chain_function(
  name : String,
  count : Int,
) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  // The entry block carries the only instructions. Nothing below it spends
  // the precise-memory budget, but every dominated block is still visited.
  let zero = builder.iconst_i32(0)
  let value = builder.iadd(input, zero)
  for _ in 0..<count {
    let next = builder.create_block()
    builder.jump(next, [])
    builder.switch_to_block(next)
  }
  builder.return_([value])
  builder.get_function()
}

///|
test "global value numbering survives a deep spine of empty blocks" {
  let func = deep_empty_block_chain_function("gvn_deep_empty_blocks", 100000)
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(func.verify(), content="()")
}

///|
/// One long chain of `iadd`s, each consuming the previous result.
fn deep_operand_chain_function(name : String, count : Int) -> @milkir.Function {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(name)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let one = builder.iconst_i32(1)
  let mut value = input
  for _ in 0..<count {
    value = builder.iadd(value, one)
  }
  builder.return_([value])
  builder.get_function()
}

///|
test "acyclic optimization survives a deep block spine" {
  let func = deep_block_chain_function("acyclic_deep_blocks", 100000)
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(func.verify(), content="()")
}

///|
test "the optimizer pipeline survives a deep dominator spine" {
  // Alias canonicalization and acyclic optimization both traverse the full
  // dominator tree, so drive the complete pipeline to cover their composition.
  let func = deep_block_chain_function("optimize_deep_blocks", 100000)
  optimize_with_level(func, O3) |> ignore
  inspect(func.verify(), content="()")
}

///|
test "acyclic optimization survives a deep operand chain" {
  let func = deep_operand_chain_function("acyclic_deep_operands", 100000)
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite creates a strength-reduced MilkIR form" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("rewrite_mul_pow2")
  let x = builder.add_param(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let product = builder.imul(x, eight)
  builder.return_([product])
  let func = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(func.verify(), content="()")
  let text = func.print()
  inspect(text.contains("ishl"), content="true")
  inspect(text.contains("imul"), content="false")
}

///|
test "acyclic extraction keeps equal-cost integer addition" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("keep_equal_cost_add")
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let doubled = builder.iadd(input, input)
  builder.return_([doubled])
  let func = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  let text = func.print()
  inspect(text.contains("iadd"), content="true")
  inspect(text.contains("ishl"), content="false")
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite reduces integer constants to the result width" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "reduce_constant_width",
  )
  builder.add_result(I32)
  let wide = builder.iconst_i64(0x100000000L)
  let reduced = builder.ireduce(I32, wide)
  builder.return_([reduced])
  let func = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  inspect(
    func.block_instruction_at(func.blocks[0], 1).unwrap().opcode,
    content="Scalar(IntConst(0))",
  )
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite dispatch is linear in reachable instructions" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("effect_heavy_rewrite")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let effect = builder.get_function().declare_external_symbol("effect")
  for _ in 0..<600 {
    builder.call_symbol(effect, None, []) |> ignore
  }
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  builder.return_([product])
  let func = builder.get_function()
  let before = instruction_count(func)
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    before,
    FunctionAnalysis::build(func),
  )
  inspect(stats.rewrite_stats.attempts, content=before.to_string())
  inspect(stats.rewrite_stats.applied, content="1")
  // The selected alternative materializes its shift amount and root as two
  // staged DFG instructions; the old root becomes an alias for final cleanup.
  inspect(stats.rewrite_stats.created_instructions, content="2")
  inspect(func.verify(), content="()")
}

///|
test "acyclic rewrite does not expand a shared definition" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_definition")
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let one = builder.iconst_i32(1)
  let two = builder.iconst_i32(2)
  let base = builder.iadd(input, one)
  let combined = builder.iadd(base, two)
  let result = builder.iadd(base, combined)
  builder.return_([result])
  let func = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  |> ignore
  let text = func.print()
  inspect(text.contains("iadd v0, v1"), content="true")
  inspect(text.contains("iadd v3, v2"), content="true")
  inspect(func.verify(), content="()")
}
