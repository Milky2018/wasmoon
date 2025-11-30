// Wasmoon Benchmarks
// Performance testing for the WebAssembly runtime

// ============================================================
// Helper Functions
// ============================================================

///|
fn create_test_module(
  code : @types.FunctionCode,
) -> (@runtime.Store, @runtime.ModuleInstance) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [code],
    datas: [],
  }
  @executor.instantiate_module(mod)
}

///|
fn create_fibonacci_module() -> (@runtime.Store, @runtime.ModuleInstance) {
  // Iterative fibonacci: fib(n)
  // local 0 = n, local 1 = a = 0, local 2 = b = 1, local 3 = temp
  let fib_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let fib_code : @types.FunctionCode = {
    locals: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    body: [
      // a = 0
      @types.I32Const(0),
      @types.LocalSet(1),
      // b = 1
      @types.I32Const(1),
      @types.LocalSet(2),
      // loop while n > 0
      @types.Block(@types.BlockType::Empty, [
        @types.Loop(@types.BlockType::Empty, [
          // if n <= 0, break
          @types.LocalGet(0),
          @types.I32Const(0),
          @types.I32LeS,
          @types.BrIf(1),
          // temp = a + b
          @types.LocalGet(1),
          @types.LocalGet(2),
          @types.I32Add,
          @types.LocalSet(3),
          // a = b
          @types.LocalGet(2),
          @types.LocalSet(1),
          // b = temp
          @types.LocalGet(3),
          @types.LocalSet(2),
          // n = n - 1
          @types.LocalGet(0),
          @types.I32Const(1),
          @types.I32Sub,
          @types.LocalSet(0),
          // continue loop
          @types.Br(0),
        ]),
      ]),
      // return a
      @types.LocalGet(1),
    ],
  }
  let mod : @types.Module = {
    types: [fib_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "fib", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [fib_code],
    datas: [],
  }
  @executor.instantiate_module(mod)
}

// ============================================================
// Part 1: Basic Interpreter Benchmarks (Baseline)
// ============================================================

///|
test "bench_interp_simple_add" (b : @bench.T) {
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [@types.LocalGet(0), @types.LocalGet(1), @types.I32Add],
  }
  let (store, instance) = create_test_module(add_func)
  let args = [@types.Value::I32(42), @types.Value::I32(58)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "test", args)
      |> ignore)
    },
    name="interpreter/simple_add",
  )
}

///|
test "bench_interp_arithmetic_chain" (b : @bench.T) {
  // (a + b) * (a - b) / 2
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Add,
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Sub,
      @types.I32Mul,
      @types.I32Const(2),
      @types.I32DivS,
    ],
  }
  let (store, instance) = create_test_module(func)
  let args = [@types.Value::I32(100), @types.Value::I32(50)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "test", args)
      |> ignore)
    },
    name="interpreter/arithmetic_chain",
  )
}

///|
test "bench_interp_fibonacci" (b : @bench.T) {
  let (store, instance) = create_fibonacci_module()
  let args = [@types.Value::I32(20)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "fib", args) |> ignore)
    },
    name="interpreter/fibonacci_20",
  )
}

///|
test "bench_interp_bitwise" (b : @bench.T) {
  // (a & b) | (a ^ b) with shifts
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32And,
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Xor,
      @types.I32Or,
      @types.I32Const(2),
      @types.I32Shl,
      @types.I32Const(1),
      @types.I32ShrU,
    ],
  }
  let (store, instance) = create_test_module(func)
  let args = [@types.Value::I32(0xFF00), @types.Value::I32(0x00FF)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "test", args)
      |> ignore)
    },
    name="interpreter/bitwise_ops",
  )
}

///|
test "bench_interp_locals" (b : @bench.T) {
  // Heavy local variable usage
  let func : @types.FunctionCode = {
    locals: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    body: [
      @types.LocalGet(0),
      @types.LocalSet(2),
      @types.LocalGet(1),
      @types.LocalSet(3),
      @types.LocalGet(2),
      @types.LocalGet(3),
      @types.I32Add,
      @types.LocalSet(4),
      @types.LocalGet(2),
      @types.LocalGet(3),
      @types.I32Sub,
      @types.LocalSet(5),
      @types.LocalGet(4),
      @types.LocalGet(5),
      @types.I32Mul,
    ],
  }
  let (store, instance) = create_test_module(func)
  let args = [@types.Value::I32(20), @types.Value::I32(10)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "test", args)
      |> ignore)
    },
    name="interpreter/local_vars",
  )
}

// ============================================================
// Part 2: JIT Profiler & Strategy Benchmarks
// ============================================================

///|
test "bench_jit_profiler_record" (b : @bench.T) {
  let profiler = @jit.Profiler::new(@jit.HotThreshold::default())
  b.bench(
    fn() {
      for i in 0..<100 {
        profiler.record_call(i % 10) |> ignore
      }
    },
    name="jit/profiler_record_100",
  )
}

///|
test "bench_jit_profiler_hotness" (b : @bench.T) {
  let profiler = @jit.Profiler::new(@jit.HotThreshold::default())
  // Pre-warm some functions
  for _ in 0..<1000 {
    profiler.record_call(0) |> ignore
  }
  for _ in 0..<500 {
    profiler.record_call(1) |> ignore
  }
  for _ in 0..<100 {
    profiler.record_call(2) |> ignore
  }
  b.bench(
    fn() {
      for i in 0..<100 {
        profiler.get_function_temperature(i % 3) |> ignore
      }
    },
    name="jit/profiler_temperature_check",
  )
}

///|
test "bench_jit_strategy_decide" (b : @bench.T) {
  let strategy = @jit.CompilationStrategy::new(@jit.TieredConfig::default())
  // Simulate some history
  for i in 0..<50 {
    for _ in 0..<(i * 10) {
      strategy.decide(i) |> ignore
    }
  }
  b.bench(
    fn() {
      for i in 0..<100 {
        strategy.decide(i % 50) |> ignore
      }
    },
    name="jit/strategy_decide_100",
  )
}

///|
test "bench_jit_compilation_queue" (b : @bench.T) {
  let queue = @jit.CompilationQueue::new(100)
  b.bench(
    fn() {
      // Enqueue 50 requests
      for i in 0..<50 {
        queue.enqueue(
          @jit.CompilationRequest::new(i, @jit.CompilationMode::Baseline),
        )
        |> ignore
      }
      // Dequeue all
      while !queue.is_empty() {
        queue.dequeue() |> ignore
      }
    },
    name="jit/queue_enqueue_dequeue_50",
  )
}

///|
test "bench_jit_engine_call" (b : @bench.T) {
  let engine = @jit.JITEngine::default()
  b.bench(
    fn() {
      for i in 0..<100 {
        engine.on_call(i % 10) |> ignore
      }
    },
    name="jit/engine_on_call_100",
  )
}

// ============================================================
// Part 3: IR Translation Benchmarks
// ============================================================

///|
test "bench_ir_translate_simple" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [@types.LocalGet(0), @types.LocalGet(1), @types.I32Add]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "add",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      translator.translate(instructions) |> ignore
    },
    name="ir/translate_simple",
  )
}

///|
test "bench_ir_translate_complex" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // More complex instruction sequence
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
    @types.I32Const(2),
    @types.I32DivS,
    @types.I32Const(0xFF),
    @types.I32And,
    @types.I32Const(4),
    @types.I32Shl,
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "complex",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      translator.translate(instructions) |> ignore
    },
    name="ir/translate_complex",
  )
}

///|
test "bench_ir_translate_with_control_flow" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Fibonacci-like control flow
  let instructions = [
    @types.I32Const(0),
    @types.LocalSet(1),
    @types.I32Const(1),
    @types.LocalSet(2),
    @types.Block(@types.BlockType::Empty, [
      @types.Loop(@types.BlockType::Empty, [
        @types.LocalGet(0),
        @types.I32Const(0),
        @types.I32LeS,
        @types.BrIf(1),
        @types.LocalGet(1),
        @types.LocalGet(2),
        @types.I32Add,
        @types.LocalSet(3),
        @types.LocalGet(2),
        @types.LocalSet(1),
        @types.LocalGet(3),
        @types.LocalSet(2),
        @types.LocalGet(0),
        @types.I32Const(1),
        @types.I32Sub,
        @types.LocalSet(0),
        @types.Br(0),
      ]),
    ]),
    @types.LocalGet(1),
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "fib",
        func_type,
        [@types.ValueType::I32, @types.ValueType::I32, @types.ValueType::I32],
        [func_type],
        [0],
        0,
      )
      translator.translate(instructions) |> ignore
    },
    name="ir/translate_control_flow",
  )
}

// ============================================================
// Part 4: IR Optimization Pass Benchmarks
// ============================================================

///|
fn create_optimizable_function() -> @ir.Function {
  let builder = @ir.IRBuilder::new("opt_test")
  let p0 = builder.add_param(@ir.Type::I32)
  let p1 = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // Create some redundant operations for optimization
  // x + 0, x * 1, x - x patterns
  let zero = builder.iconst_i32(0)
  let one = builder.iconst_i32(1)
  let add_zero = builder.iadd(p0, zero)
  let mul_one = builder.imul(add_zero, one)
  let copy1 = builder.copy(mul_one)
  let copy2 = builder.copy(copy1)
  let result = builder.iadd(copy2, p1)
  builder.return_([result])
  builder.get_function()
}

///|
test "bench_opt_constant_folding" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.fold_constants(func) |> ignore
    },
    name="opt/constant_folding",
  )
}

///|
test "bench_opt_copy_propagation" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.propagate_copies(func) |> ignore
    },
    name="opt/copy_propagation",
  )
}

///|
test "bench_opt_dead_code_elimination" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.eliminate_dead_code(func) |> ignore
    },
    name="opt/dead_code_elim",
  )
}

///|
test "bench_opt_strength_reduction" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.reduce_strength(func) |> ignore
    },
    name="opt/strength_reduction",
  )
}

///|
test "bench_opt_full_pipeline" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.optimize(func) |> ignore
    },
    name="opt/full_pipeline",
  )
}

///|
test "bench_opt_cse" (b : @bench.T) {
  b.bench(
    fn() {
      let func = create_optimizable_function()
      @ir.eliminate_common_subexpressions(func) |> ignore
    },
    name="opt/common_subexpr_elim",
  )
}

// ============================================================
// Part 5: VCode Generation Benchmarks
// ============================================================

///|
test "bench_vcode_builder_simple" (b : @bench.T) {
  b.bench(
    fn() {
      let builder = @vcode.VCodeBuilder::new("add")
      let p0 = builder.add_param(@vcode.RegClass::Int)
      let p1 = builder.add_param(@vcode.RegClass::Int)
      builder.add_result(@vcode.RegClass::Int)
      let entry = builder.create_block()
      builder.switch_to_block(entry)
      let sum = builder.add(p0, p1)
      builder.return_([sum])
      builder.get_function() |> ignore
    },
    name="vcode/builder_simple",
  )
}

///|
test "bench_vcode_builder_complex" (b : @bench.T) {
  b.bench(
    fn() {
      let builder = @vcode.VCodeBuilder::new("complex")
      let p0 = builder.add_param(@vcode.RegClass::Int)
      let p1 = builder.add_param(@vcode.RegClass::Int)
      builder.add_result(@vcode.RegClass::Int)
      let entry = builder.create_block()
      let then_block = builder.create_block()
      let else_block = builder.create_block()
      builder.switch_to_block(entry)
      let sum = builder.add(p0, p1)
      let diff = builder.sub(p0, p1)
      let prod = builder.mul(sum, diff)
      let cmp = builder.cmp(@vcode.CmpKind::Sgt, p0, p1)
      builder.branch(cmp, then_block, else_block)
      builder.switch_to_block(then_block)
      builder.return_([prod])
      builder.switch_to_block(else_block)
      let negated = builder.sub(builder.iconst(0L), prod)
      builder.return_([negated])
      builder.get_function() |> ignore
    },
    name="vcode/builder_complex",
  )
}

///|
test "bench_vcode_lowering" (b : @bench.T) {
  let func = create_optimizable_function()
  b.bench(
    fn() { @vcode.lower_function(func) |> ignore },
    name="vcode/lowering_basic",
  )
}

///|
test "bench_vcode_lowering_optimized" (b : @bench.T) {
  let func = create_optimizable_function()
  b.bench(
    fn() { @vcode.lower_function_optimized(func) |> ignore },
    name="vcode/lowering_optimized",
  )
}

// ============================================================
// Part 6: Register Allocation Benchmarks
// ============================================================

///|
test "bench_regalloc_liveness" (b : @bench.T) {
  let builder = @vcode.VCodeBuilder::new("liveness_test")
  let p0 = builder.add_param(@vcode.RegClass::Int)
  let p1 = builder.add_param(@vcode.RegClass::Int)
  builder.add_result(@vcode.RegClass::Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let v1 = builder.add(p0, p1)
  let v2 = builder.mul(v1, p0)
  let v3 = builder.sub(v2, p1)
  let v4 = builder.add(v3, v1)
  builder.return_([v4])
  let func = builder.get_function()
  b.bench(
    fn() { @vcode.compute_liveness(func) |> ignore },
    name="regalloc/liveness",
  )
}

///|
test "bench_regalloc_full" (b : @bench.T) {
  let builder = @vcode.VCodeBuilder::new("regalloc_test")
  let p0 = builder.add_param(@vcode.RegClass::Int)
  let p1 = builder.add_param(@vcode.RegClass::Int)
  builder.add_result(@vcode.RegClass::Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let v1 = builder.add(p0, p1)
  let v2 = builder.mul(v1, p0)
  let v3 = builder.sub(v2, p1)
  builder.return_([v3])
  let func = builder.get_function()
  b.bench(
    fn() { @vcode.allocate_registers_aarch64(func) |> ignore },
    name="regalloc/full_aarch64",
  )
}

// ============================================================
// Part 7: Code Emission Benchmarks
// ============================================================

///|
test "bench_emit_instructions" (b : @bench.T) {
  b.bench(
    fn() {
      let mc = @vcode.MachineCode::new()
      // Emit a sequence of common instructions
      for _ in 0..<10 {
        @vcode.emit_add_reg(mc, 0, 1, 2)
        @vcode.emit_sub_reg(mc, 3, 4, 5)
        @vcode.emit_mul(mc, 6, 7, 8)
        @vcode.emit_mov_reg(mc, 9, 10)
        @vcode.emit_cmp_reg(mc, 11, 12)
      }
    },
    name="emit/instruction_sequence",
  )
}

///|
test "bench_emit_load_store" (b : @bench.T) {
  b.bench(
    fn() {
      let mc = @vcode.MachineCode::new()
      for _ in 0..<20 {
        @vcode.emit_ldr_imm(mc, 0, 1, 0)
        @vcode.emit_str_imm(mc, 2, 3, 8)
        @vcode.emit_ldr_w_imm(mc, 4, 5, 16)
        @vcode.emit_str_w_imm(mc, 6, 7, 24)
      }
    },
    name="emit/load_store_sequence",
  )
}

///|
test "bench_emit_branches" (b : @bench.T) {
  b.bench(
    fn() {
      let mc = @vcode.MachineCode::new()
      for i in 0..<10 {
        @vcode.emit_b(mc, i * 4)
        @vcode.emit_b_cond(mc, @vcode.cond_eq(), i * 8)
        @vcode.emit_cbz(mc, 0, i * 12)
        @vcode.emit_cbnz(mc, 1, i * 16)
      }
    },
    name="emit/branch_sequence",
  )
}

///|
test "bench_emit_function" (b : @bench.T) {
  let builder = @vcode.VCodeBuilder::new("emit_test")
  let p0 = builder.add_param(@vcode.RegClass::Int)
  let p1 = builder.add_param(@vcode.RegClass::Int)
  builder.add_result(@vcode.RegClass::Int)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.add(p0, p1)
  builder.return_([sum])
  let func = builder.get_function()
  b.bench(
    fn() { @vcode.emit_function(func) |> ignore },
    name="emit/full_function",
  )
}

// ============================================================
// Part 8: JIT Runtime Benchmarks
// ============================================================

///|
test "bench_jit_runtime_lookup" (b : @bench.T) {
  let runtime = @vcode.JITRuntime::new(1024 * 1024, 64 * 1024)
  // Pre-register some compiled functions
  for i in 0..<10 {
    let mc = @vcode.MachineCode::new()
    @vcode.emit_nop(mc)
    @vcode.emit_ret(mc, 30)
    let cf = @vcode.CompiledFunction::new("func_\{i}", mc, 0)
    runtime.register(i, cf) |> ignore
  }
  b.bench(
    fn() {
      for i in 0..<100 {
        runtime.lookup(i % 10) |> ignore
      }
    },
    name="jit_runtime/lookup_100",
  )
}

///|
test "bench_jit_code_cache" (b : @bench.T) {
  let cache = @vcode.CodeCache::new(10 * 1024 * 1024)
  // Pre-populate cache
  for i in 0..<20 {
    let mc = @vcode.MachineCode::new()
    @vcode.emit_nop(mc)
    let cf = @vcode.CompiledFunction::new("func_\{i}", mc, 0)
    cache.insert(i, cf)
  }
  b.bench(
    fn() {
      for i in 0..<100 {
        cache.get(i % 20) |> ignore
      }
    },
    name="jit_runtime/cache_lookup_100",
  )
}

// ============================================================
// Part 9: End-to-End Compilation Pipeline Benchmarks
// ============================================================

///|
test "bench_pipeline_translate_only" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "test",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      translator.translate(instructions) |> ignore
    },
    name="pipeline/translate_only",
  )
}

///|
test "bench_pipeline_translate_and_optimize" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "test",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      let ir_func = translator.translate(instructions)
      @ir.optimize(ir_func) |> ignore
    },
    name="pipeline/translate_and_optimize",
  )
}

///|
test "bench_pipeline_translate_optimize_lower" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "test",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      let ir_func = translator.translate(instructions)
      @ir.optimize(ir_func) |> ignore
      @vcode.lower_function_optimized(ir_func) |> ignore
    },
    name="pipeline/translate_optimize_lower",
  )
}

///|
test "bench_pipeline_full" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
  ]
  b.bench(
    fn() {
      let translator = @ir.Translator::new(
        "test",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      let ir_func = translator.translate(instructions)
      @ir.optimize(ir_func) |> ignore
      let vcode_func = @vcode.lower_function_optimized(ir_func)
      let allocated = @vcode.allocate_registers_aarch64(vcode_func)
      @vcode.emit_function(allocated) |> ignore
    },
    name="pipeline/full_compilation",
  )
}

// ============================================================
// Part 10: Comparison Benchmarks
// ============================================================

///|
test "bench_compare_native_moonbit" (b : @bench.T) {
  b.bench(
    fn() {
      let a = 42
      let c = 58
      let _result = (a + c) * (a - c)

    },
    name="compare/native_moonbit",
  )
}

///|
test "bench_compare_interpreter" (b : @bench.T) {
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Add,
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Sub,
      @types.I32Mul,
    ],
  }
  let (store, instance) = create_test_module(func)
  let args = [@types.Value::I32(42), @types.Value::I32(58)]
  b.bench(
    fn() {
      try! (@executor.call_exported_func(store, instance, "test", args)
      |> ignore)
    },
    name="compare/interpreter",
  )
}

///|
test "bench_compare_compilation_overhead" (b : @bench.T) {
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instructions = [
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Add,
    @types.LocalGet(0),
    @types.LocalGet(1),
    @types.I32Sub,
    @types.I32Mul,
  ]
  b.bench(
    fn() {
      // Full compilation pipeline
      let translator = @ir.Translator::new(
        "test",
        func_type,
        [],
        [func_type],
        [0],
        0,
      )
      let ir_func = translator.translate(instructions)
      @ir.optimize(ir_func) |> ignore
      let vcode_func = @vcode.lower_function_optimized(ir_func)
      let allocated = @vcode.allocate_registers_aarch64(vcode_func)
      @vcode.emit_function(allocated) |> ignore
    },
    name="compare/compilation_overhead",
  )
}

///|
test "bench_compare_module_instantiation" (b : @bench.T) {
  let simple_func : @types.FunctionCode = {
    locals: [],
    body: [@types.LocalGet(0), @types.LocalGet(1), @types.I32Add],
  }
  b.bench(
    fn() { create_test_module(simple_func) |> ignore },
    name="compare/module_instantiation",
  )
}
