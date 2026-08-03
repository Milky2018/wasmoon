///|
fn dead_constant_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
  for i in 0..<count {
    builder.iconst_i32(i) |> ignore
  }
  builder.return_([])
  builder.get_function()
}

///|
fn copy_chain_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
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
fn foldable_chain_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
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
fn egraph_identity_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let zero = builder.iconst_i32(0)
  let mut value = builder.iadd(input, zero)
  for _ in 2..<count {
    value = builder.copy(value)
  }
  builder.return_([value])
  builder.get_function()
}

///|
fn duplicate_expression_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
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
test "egraph uses a bounded rewrite budget at 300 instructions" {
  let func = egraph_identity_function("egraph_300", 300)
  inspect(run_egraph_pass(func), content="true")
  inspect(func.verify(), content="()")
}

///|
test "egraph retains rewrite work at 600 instructions" {
  let func = egraph_identity_function("egraph_600", 600)
  inspect(run_egraph_pass(func), content="true")
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
  let builder = FunctionBuilder::FunctionBuilder("effectful_600")
  for i in 0..<600 {
    builder.iconst_i32(i) |> ignore
  }
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.return_([])
  let func = builder.get_function()
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="1")
  inspect(func.blocks[0].instructions[0].opcode is Call(_), content="true")
  inspect(func.verify(), content="()")
}

///|
test "egraph size tiers retain nonzero rewrite budgets" {
  let limits_299 = egraph_limits_for_function(
    copy_chain_function("limits_299", 299),
  )
  let limits_300 = egraph_limits_for_function(
    copy_chain_function("limits_300", 300),
  )
  let limits_600 = egraph_limits_for_function(
    copy_chain_function("limits_600", 600),
  )
  debug_inspect(
    [
      (limits_299.matches_limit(), limits_299.eclass_enode_limit()),
      (limits_300.matches_limit(), limits_300.eclass_enode_limit()),
      (limits_600.matches_limit(), limits_600.eclass_enode_limit()),
    ],
    content="[(5, 5), (2, 3), (1, 2)]",
  )
}

///|
test "GVN work budget stops safely after partial optimization" {
  let func = duplicate_expression_function("gvn_partial", 5)
  let stats = run_global_value_numbering_with_budget(func, 2)
  inspect(stats.work_done, content="2")
  inspect(stats.budget_exhausted, content="true")
  inspect(func.blocks[0].instructions[1].opcode, content="Scalar(Copy)")
  inspect(
    func.blocks[0].instructions[2].opcode,
    content="Scalar(IntBinary(Add))",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN early termination preserves external effects" {
  let builder = FunctionBuilder::FunctionBuilder("gvn_partial_effect")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  builder.iadd(lhs, rhs) |> ignore
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  let result = builder.iadd(lhs, rhs)
  builder.return_([result])
  let func = builder.get_function()
  let stats = run_global_value_numbering_with_budget(func, 2)
  inspect(stats.budget_exhausted, content="true")
  inspect(func.blocks[0].instructions[1].opcode is Call(_), content="true")
  inspect(func.verify(), content="()")
}

///|
test "GVN uses work units instead of a function-size switch" {
  debug_inspect(
    [
      gvn_work_budget_for_function(copy_chain_function("gvn_299", 299)),
      gvn_work_budget_for_function(copy_chain_function("gvn_300", 300)),
      gvn_work_budget_for_function(copy_chain_function("gvn_301", 301)),
      gvn_work_budget_for_function(copy_chain_function("gvn_600", 600)),
    ],
    content="[299, 300, 300, 300]",
  )
}

///|
test "GVN metrics count only instructions visited in reachable blocks" {
  let builder = FunctionBuilder::FunctionBuilder("gvn_reachable_work")
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
  run_gvn_pass(func) |> ignore
  clear_optimization_metrics_sink()
  inspect(events.length(), content="1")
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
/// A single straight-line chain of `count` blocks, each jumping to the next.
/// The dominator tree is one long spine, which the e-graph block rewriter
/// used to walk with native recursion.
fn deep_block_chain_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
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
/// One long chain of e-graph-encodable `iadd`s, each consuming the previous
/// result. The value converter used to walk this with native recursion.
/// `copy` is deliberately not used: it has no e-graph encoding, so a copy
/// chain becomes a row of leaves rather than a deep operand chain.
fn deep_operand_chain_function(name : String, count : Int) -> Function {
  let builder = FunctionBuilder::FunctionBuilder(name)
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
test "egraph survives a deep dominator spine" {
  // Well past the depth a native-stack recursion survives.
  let func = deep_block_chain_function("egraph_deep_blocks", 100000)
  run_egraph_pass(func) |> ignore
  inspect(func.verify(), content="()")
}

///|
test "egraph survives a deep operand chain" {
  let func = deep_operand_chain_function("egraph_deep_operands", 100000)
  run_egraph_pass(func) |> ignore
  inspect(func.verify(), content="()")
}
