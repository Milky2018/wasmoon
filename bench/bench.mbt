// Wasmoon Benchmarks
// Performance testing for the WebAssembly runtime

// Helper function to create a simple WASM module

///|
fn create_test_module(
  code : @wasmoon.FunctionCode,
) -> (@wasmoon.Store, @wasmoon.ModuleInstance) {
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [code],
    datas: [],
  }
  @wasmoon.instantiate_module(mod)
}

// Benchmark 1: Simple Addition

///|
test "bench_simple_add" (b : @bench.T) {
  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [@wasmoon.LocalGet(0), @wasmoon.LocalGet(1), @wasmoon.I32Add],
  }
  let (store, instance) = create_test_module(add_func)
  let args = [@wasmoon.Value::I32(42), @wasmoon.Value::I32(58)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="simple_add",
  )
}

// Benchmark 2: Complex Arithmetic

///|
test "bench_complex_arithmetic" (b : @bench.T) {
  // (a + b) * (a - b) / 2
  let complex_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Add,
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Sub,
      @wasmoon.I32Mul,
      @wasmoon.I32Const(2),
      @wasmoon.I32DivS,
    ],
  }
  let (store, instance) = create_test_module(complex_func)
  let args = [@wasmoon.Value::I32(100), @wasmoon.Value::I32(50)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="complex_arithmetic",
  )
}

// Benchmark 3: Local Variables

///|
test "bench_local_variables" (b : @bench.T) {
  // Store to local and retrieve multiple times
  let local_func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    body: [
      // Store a to local 2
      @wasmoon.LocalGet(0),
      @wasmoon.LocalSet(2),
      // Store b to local 3
      @wasmoon.LocalGet(1),
      @wasmoon.LocalSet(3),
      // Compute (local2 + local3) * (local2 - local3)
      @wasmoon.LocalGet(2),
      @wasmoon.LocalGet(3),
      @wasmoon.I32Add,
      @wasmoon.LocalGet(2),
      @wasmoon.LocalGet(3),
      @wasmoon.I32Sub,
      @wasmoon.I32Mul,
    ],
  }
  let (store, instance) = create_test_module(local_func)
  let args = [@wasmoon.Value::I32(20), @wasmoon.Value::I32(10)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="local_variables",
  )
}

// Benchmark 4: Bitwise Operations

///|
test "bench_bitwise_ops" (b : @bench.T) {
  // (a & b) | (a ^ b)
  let bitwise_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32And,
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Xor,
      @wasmoon.I32Or,
    ],
  }
  let (store, instance) = create_test_module(bitwise_func)
  let args = [@wasmoon.Value::I32(0xFF00), @wasmoon.Value::I32(0x00FF)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="bitwise_ops",
  )
}

// Benchmark 5: Comparison Operations

///|
test "bench_comparisons" (b : @bench.T) {
  // (a < b) ? (a + b) : (a - b)
  // Implemented as: (a < b) * (a + b) + (a >= b) * (a - b)
  let cmp_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      // (a < b) as 0 or 1
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32LtS,
      // (a + b)
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Add,
      // multiply
      @wasmoon.I32Mul,
      // (a >= b) as 0 or 1
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32GeS,
      // (a - b)
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Sub,
      // multiply
      @wasmoon.I32Mul,
      // add both branches
      @wasmoon.I32Add,
    ],
  }
  let (store, instance) = create_test_module(cmp_func)
  let args = [@wasmoon.Value::I32(30), @wasmoon.Value::I32(20)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="comparisons",
  )
}

// Benchmark 6: Iterative Computation (sum 1 to N)

///|
test "bench_iterative_sum" (b : @bench.T) {
  // Compute sum from 1 to n using repeated additions
  // We'll approximate with a simpler calculation for now
  let sum_func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32], // accumulator
    body: [
      // acc = 0
      @wasmoon.I32Const(0),
      @wasmoon.LocalSet(2),
      // acc = acc + 1
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(1),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      // acc = acc + 2
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(2),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      // acc = acc + 3
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(3),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      // acc = acc + 4
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(4),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      // acc = acc + 5
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(5),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      // return acc
      @wasmoon.LocalGet(2),
    ],
  }
  let (store, instance) = create_test_module(sum_func)
  let args = [@wasmoon.Value::I32(0), @wasmoon.Value::I32(0)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="iterative_sum",
  )
}

// Benchmark 7: Stack-Heavy Operations

///|
test "bench_stack_operations" (b : @bench.T) {
  // Push many values to stack and perform operations
  let stack_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      @wasmoon.I32Const(1),
      @wasmoon.I32Const(2),
      @wasmoon.I32Add,
      @wasmoon.I32Const(3),
      @wasmoon.I32Add,
      @wasmoon.I32Const(4),
      @wasmoon.I32Add,
      @wasmoon.I32Const(5),
      @wasmoon.I32Add,
      @wasmoon.I32Const(6),
      @wasmoon.I32Add,
      @wasmoon.I32Const(7),
      @wasmoon.I32Add,
      @wasmoon.I32Const(8),
      @wasmoon.I32Add,
      @wasmoon.I32Const(9),
      @wasmoon.I32Add,
      @wasmoon.I32Const(10),
      @wasmoon.I32Add,
    ],
  }
  let (store, instance) = create_test_module(stack_func)
  let args = [@wasmoon.Value::I32(0), @wasmoon.Value::I32(0)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="stack_operations",
  )
}

// Benchmark 8: Module Instantiation

///|
test "bench_module_instantiation" (b : @bench.T) {
  let simple_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [@wasmoon.LocalGet(0), @wasmoon.LocalGet(1), @wasmoon.I32Add],
  }
  b.bench(
    fn() {
      let _result = create_test_module(simple_func)

    },
    name="module_instantiation",
  )
}

// Comparison: Native MoonBit vs Wasmoon

///|
test "compare_native_vs_wasm" (b : @bench.T) {
  // Native MoonBit computation
  b.bench(
    fn() {
      let a = 42
      let b = 58
      let _result = a + b

    },
    name="native_add",
  )

  // Wasmoon computation
  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [@wasmoon.LocalGet(0), @wasmoon.LocalGet(1), @wasmoon.I32Add],
  }
  let (store, instance) = create_test_module(add_func)
  let args = [@wasmoon.Value::I32(42), @wasmoon.Value::I32(58)]
  b.bench(
    fn() {
      try! (@wasmoon.call_exported_func(store, instance, "test", args) |> ignore)
    },
    name="wasm_add",
  )
}
