///|
fn context_global_fixture(
  name : String,
  stability : GlobalValueStability,
  memidx : Int,
) -> (FunctionBuilder, Value, GlobalValue) {
  let builder = FunctionBuilder::FunctionBuilder(name)
  let context = builder.add_param(Ptr)
  let field = ContextField::new("test", 0, [memidx], I64)
  let global = builder
    .get_function()
    .declare_global_value(
      GlobalValueData::context_field(field, stability, Heap(memidx)),
    )
  (builder, context, global)
}

///|
test "GVN reuses a mutable context global across heap stores" {
  let (builder, context, global) = context_global_fixture(
    "mutable_global_heap_store",
    Mutable,
    0,
  )
  builder.add_result(I64)
  let first = builder.global_value(global, context)
  let dynamic_offset = builder.add_param(I64)
  let address = builder.iadd(first, dynamic_offset)
  let zero = builder.iconst_i32(0)
  let no_offset = builder.iconst_i64(0L)
  builder.store_ptr(I32, address, zero, no_offset)
  let second = builder.global_value(global, context)
  builder.return_([second])
  let function = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    function,
    instruction_count(function),
    FunctionAnalysis::build(function),
  )
  |> ignore
  debug_inspect(
    test_block_instructions(function, function.blocks[0]).map(inst => {
      inst.opcode
    }),
    content=(
      #|[
      #|  GlobalValue({ id: 0 }),
      #|  Scalar(IntBinary(Add)),
      #|  Scalar(IntConst(0)),
      #|  Scalar(IntConst(0)),
      #|  Memory(Store(I32)),
      #|  Scalar(Copy),
      #|]
    ),
  )
  function.verify()
}

///|
test "GVN reloads a mutable context global after an unknown store" {
  let (builder, context, global) = context_global_fixture(
    "mutable_global_unknown_store",
    Mutable,
    0,
  )
  let unknown_address = builder.add_param(Ptr)
  builder.add_result(I64)
  builder.global_value(global, context) |> ignore
  let zero = builder.iconst_i32(0)
  let no_offset = builder.iconst_i64(0L)
  builder.store_ptr(I32, unknown_address, zero, no_offset)
  let second = builder.global_value(global, context)
  builder.return_([second])
  let function = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    function,
    instruction_count(function),
    FunctionAnalysis::build(function),
  )
  |> ignore
  debug_inspect(
    test_block_instructions(function, function.blocks[0]).map(inst => {
      inst.opcode
    }),
    content=(
      #|[
      #|  GlobalValue({ id: 0 }),
      #|  Scalar(IntConst(0)),
      #|  Scalar(IntConst(0)),
      #|  Memory(Store(I32)),
      #|  GlobalValue({ id: 0 }),
      #|]
    ),
  )
  function.verify()
}

///|
test "GVN reuses a stable context global" {
  let (builder, context, global) = context_global_fixture(
    "stable_global_reuse",
    Stable,
    0,
  )
  builder.add_result(I64)
  builder.global_value(global, context) |> ignore
  builder.global_value(global, context) |> ignore
  builder.global_value(global, context) |> ignore
  let last = builder.global_value(global, context)
  builder.return_([last])
  let function = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    function,
    instruction_count(function),
    FunctionAnalysis::build(function),
  )
  |> ignore
  debug_inspect(
    test_block_instructions(function, function.blocks[0]).map(inst => {
      inst.opcode
    }),
    content="[GlobalValue({ id: 0 }), Scalar(Copy), Scalar(Copy), Scalar(Copy)]",
  )
  function.verify()
}

///|
test "GVN reuses a stable context global after the memory budget" {
  let (builder, context, global) = context_global_fixture(
    "stable_global_after_memory_budget",
    Stable,
    0,
  )
  builder.add_result(I64)
  for i in 0..<300 {
    builder.iconst_i32(i) |> ignore
  }
  builder.global_value(global, context) |> ignore
  builder.global_value(global, context) |> ignore
  builder.global_value(global, context) |> ignore
  for i in 0..<17 {
    builder.iconst_i32(i) |> ignore
  }
  builder.global_value(global, context) |> ignore
  let last = builder.global_value(global, context)
  builder.return_([last])
  let function = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    function,
    300,
    FunctionAnalysis::build(function),
  )
  inspect(stats.work_done, content="300")
  inspect(stats.budget_exhausted, content="true")
  debug_inspect(
    [300, 301, 302, 320, 321].map(index => {
      function.block_instruction_at(function.blocks[0], index).unwrap().opcode
    }),
    content=(
      #|[
      #|  GlobalValue({ id: 0 }),
      #|  Scalar(Copy),
      #|  GlobalValue({ id: 0 }),
      #|  GlobalValue({ id: 0 }),
      #|  Scalar(Copy),
      #|]
    ),
  )
  function.verify()
}

///|
test "GVN invalidates mutable context globals after the memory budget" {
  let (builder, context, global) = context_global_fixture(
    "mutable_global_after_memory_budget",
    Mutable,
    0,
  )
  let unknown_address = builder.add_param(Ptr)
  builder.add_result(I64)
  let zero = builder.iconst_i32(0)
  let no_offset = builder.iconst_i64(0L)
  for i in 0..<300 {
    builder.iconst_i32(i) |> ignore
  }
  builder.global_value(global, context) |> ignore
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  builder.global_value(global, context) |> ignore
  builder.store_ptr(I32, unknown_address, zero, no_offset)
  builder.global_value(global, context) |> ignore
  let last = builder.global_value(global, context)
  builder.return_([last])
  let function = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    function,
    300,
    FunctionAnalysis::build(function),
  )
  inspect(stats.work_done, content="300")
  inspect(stats.budget_exhausted, content="true")
  debug_inspect(
    test_block_instructions(function, function.blocks[0])[302:].map(inst => {
      inst.opcode
    }),
    content=(
      #|[
      #|  GlobalValue({ id: 0 }),
      #|  Call(Direct({ name: "effect" }, { params: [], results: [] })),
      #|  GlobalValue({ id: 0 }),
      #|  Memory(Store(I32)),
      #|  GlobalValue({ id: 0 }),
      #|  Scalar(Copy),
      #|]
    ),
  )
  function.verify()
}

///|
test "GVN reloads mutable context globals after calls" {
  let (builder, context, global) = context_global_fixture(
    "mutable_global_call",
    Mutable,
    0,
  )
  builder.add_result(I64)
  builder.global_value(global, context) |> ignore
  let symbol = builder.get_function().declare_external_symbol("effect")
  builder.call_symbol(symbol, None, []) |> ignore
  let second = builder.global_value(global, context)
  builder.return_([second])
  let function = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    function,
    instruction_count(function),
    FunctionAnalysis::build(function),
  )
  |> ignore
  debug_inspect(
    test_block_instructions(function, function.blocks[0]).map(inst => {
      inst.opcode
    }),
    content=(
      #|[
      #|  GlobalValue({ id: 0 }),
      #|  Call(Direct({ name: "effect" }, { params: [], results: [] })),
      #|  GlobalValue({ id: 0 }),
      #|]
    ),
  )
  function.verify()
}

///|
test "GVN does not merge distinct context globals" {
  let builder = FunctionBuilder::FunctionBuilder("distinct_globals")
  let context = builder.add_param(Ptr)
  builder.add_result(I64)
  let memory0 = builder
    .get_function()
    .declare_global_value(
      GlobalValueData::context_field(
        ContextField::new("test", 0, [0], I64),
        Stable,
        Heap(0),
      ),
    )
  let memory1 = builder
    .get_function()
    .declare_global_value(
      GlobalValueData::context_field(
        ContextField::new("test", 0, [1], I64),
        Stable,
        Heap(1),
      ),
    )
  builder.global_value(memory0, context) |> ignore
  let second = builder.global_value(memory1, context)
  builder.return_([second])
  let function = builder.get_function()
  run_acyclic_optimization_with_budget_and_analysis(
    function,
    instruction_count(function),
    FunctionAnalysis::build(function),
  )
  |> ignore
  debug_inspect(
    test_block_instructions(function, function.blocks[0]).map(inst => {
      inst.opcode
    }),
    content=(
      #|[GlobalValue({ id: 0 }), GlobalValue({ id: 1 })]
    ),
  )
  function.verify()
}
