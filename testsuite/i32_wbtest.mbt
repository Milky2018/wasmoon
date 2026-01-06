// Tests for i32 operations from official wasm-testsuite
// These tests are extracted from the official WebAssembly testsuite

///|
/// Create i32 test module programmatically (simplified version for testing)
fn create_i32_add_module() -> @types.Module {
  // Function: add(a, b) -> a + b
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "add", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [add_func],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
/// Test i32.add from official testsuite
test "wasm-testsuite: i32.add" {
  let mod = create_i32_add_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "add" (i32.const 1) (i32.const 1)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(2)")
  // (assert_return (invoke "add" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "add" (i32.const -1) (i32.const -1)) (i32.const -2))
  // Note: -1 in unsigned i32 is 0xFFFFFFFF = 4294967295
  // -1 + -1 = -2 which is 0xFFFFFFFE = 4294967294
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(-1),
    I32(-1),
  ])
  inspect(result[0], content="I32(-2)")
  // (assert_return (invoke "add" (i32.const -1) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(-1),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "add" (i32.const 0x7fffffff) (i32.const 1)) (i32.const 0x80000000))
  // 2147483647 + 1 = -2147483648 (overflow)
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(2147483647),
    I32(1),
  ])
  inspect(result[0], content="I32(-2147483648)")
}

///|
/// Create i32 arithmetic test module
fn create_i32_arithmetic_module() -> @types.Module {
  // Multiple functions for arithmetic operations
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let sub_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Sub],
  }
  let mul_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Mul],
  }
  let div_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32DivS],
  }
  let div_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32DivU],
  }
  let rem_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32RemS],
  }
  let rem_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32RemU],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0, 0, 0, 0, 0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "add", desc: @types.ExportDesc::Func(0) },
      { name: "sub", desc: @types.ExportDesc::Func(1) },
      { name: "mul", desc: @types.ExportDesc::Func(2) },
      { name: "div_s", desc: @types.ExportDesc::Func(3) },
      { name: "div_u", desc: @types.ExportDesc::Func(4) },
      { name: "rem_s", desc: @types.ExportDesc::Func(5) },
      { name: "rem_u", desc: @types.ExportDesc::Func(6) },
    ],
    start: None,
    elems: [],
    codes: [
      add_func, sub_func, mul_func, div_s_func, div_u_func, rem_s_func, rem_u_func,
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i32.sub" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "sub" (i32.const 1) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "sub" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "sub" (i32.const -1) (i32.const -1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I32(-1),
    I32(-1),
  ])
  inspect(result[0], content="I32(0)")
}

///|
test "wasm-testsuite: i32.mul" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "mul" (i32.const 1) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "mul" (i32.const 1) (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "mul" (i32.const -1) (i32.const -1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I32(-1),
    I32(-1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "mul" (i32.const 0x10000000) (i32.const 4096)) (i32.const 0))
  // Overflow: 268435456 * 4096 = 2^40, which overflows to 0
  let result = @executor.call_exported_func(store, instance, "mul", [
    I32(0x10000000),
    I32(4096),
  ])
  inspect(result[0], content="I32(0)")
}

///|
test "wasm-testsuite: i32.div_s trap on zero" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_trap (invoke "div_s" (i32.const 1) (i32.const 0)) "integer divide by zero")
  inspect(
    try? @executor.call_exported_func(store, instance, "div_s", [I32(1), I32(0)]),
    content="Err(integer divide by zero)",
  )
}

///|
test "wasm-testsuite: i32.div_s trap on overflow" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_trap (invoke "div_s" (i32.const 0x80000000) (i32.const -1)) "integer overflow")
  // -2147483648 / -1 overflows because result would be 2147483648 which doesn't fit in i32
  inspect(
    try? @executor.call_exported_func(store, instance, "div_s", [
      I32(-2147483648),
      I32(-1),
    ]),
    content="Err(integer overflow)",
  )
}

///|
test "wasm-testsuite: i32.div_s normal cases" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "div_s" (i32.const 1) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "div_s" (i32.const 0) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I32(0),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "div_s" (i32.const -1) (i32.const -1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I32(-1),
    I32(-1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "div_s" (i32.const 5) (i32.const 2)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I32(5),
    I32(2),
  ])
  inspect(result[0], content="I32(2)")
  // (assert_return (invoke "div_s" (i32.const -5) (i32.const 2)) (i32.const -2))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I32(-5),
    I32(2),
  ])
  inspect(result[0], content="I32(-2)")
}

///|
test "wasm-testsuite: i32.div_u" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "div_u" (i32.const 1) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "div_u" (i32.const 0) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I32(0),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "div_u" (i32.const 5) (i32.const 2)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I32(5),
    I32(2),
  ])
  inspect(result[0], content="I32(2)")
}

///|
test "wasm-testsuite: i32.rem_s" {
  let mod = create_i32_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "rem_s" (i32.const 7) (i32.const 3)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rem_s", [
    I32(7),
    I32(3),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rem_s" (i32.const -7) (i32.const 3)) (i32.const -1))
  let result = @executor.call_exported_func(store, instance, "rem_s", [
    I32(-7),
    I32(3),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "rem_s" (i32.const 7) (i32.const -3)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rem_s", [
    I32(7),
    I32(-3),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rem_s" (i32.const -7) (i32.const -3)) (i32.const -1))
  let result = @executor.call_exported_func(store, instance, "rem_s", [
    I32(-7),
    I32(-3),
  ])
  inspect(result[0], content="I32(-1)")
}

///|
/// Create i32 bitwise test module
fn create_i32_bitwise_module() -> @types.Module {
  let and_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32And],
  }
  let or_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Or],
  }
  let xor_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Xor],
  }
  let shl_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Shl],
  }
  let shr_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32ShrS],
  }
  let shr_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32ShrU],
  }
  let rotl_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Rotl],
  }
  let rotr_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Rotr],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0, 0, 0, 0, 0, 0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "and", desc: @types.ExportDesc::Func(0) },
      { name: "or", desc: @types.ExportDesc::Func(1) },
      { name: "xor", desc: @types.ExportDesc::Func(2) },
      { name: "shl", desc: @types.ExportDesc::Func(3) },
      { name: "shr_s", desc: @types.ExportDesc::Func(4) },
      { name: "shr_u", desc: @types.ExportDesc::Func(5) },
      { name: "rotl", desc: @types.ExportDesc::Func(6) },
      { name: "rotr", desc: @types.ExportDesc::Func(7) },
    ],
    start: None,
    elems: [],
    codes: [
      and_func, or_func, xor_func, shl_func, shr_s_func, shr_u_func, rotl_func, rotr_func,
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i32.and" {
  let mod = create_i32_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "and" (i32.const 1) (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "and", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "and" (i32.const 0) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "and", [
    I32(0),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "and" (i32.const 1) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "and", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "and" (i32.const 0xf0f0f0f0) (i32.const 0xffff)) (i32.const 0xf0f0))
  let result = @executor.call_exported_func(store, instance, "and", [
    I32(-252645136),
    I32(65535),
  ])
  inspect(result[0], content="I32(61680)")
}

///|
test "wasm-testsuite: i32.or" {
  let mod = create_i32_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "or" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "or", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "or" (i32.const 0xf0f0f0f0) (i32.const 0xffff)) (i32.const 0xf0f0ffff))
  let result = @executor.call_exported_func(store, instance, "or", [
    I32(-252645136),
    I32(65535),
  ])
  inspect(result[0], content="I32(-252641281)")
}

///|
test "wasm-testsuite: i32.shl" {
  let mod = create_i32_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "shl" (i32.const 1) (i32.const 1)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "shl", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(2)")
  // (assert_return (invoke "shl" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "shl", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "shl" (i32.const 0x7fffffff) (i32.const 1)) (i32.const 0xfffffffe))
  // 2147483647 << 1 = -2 (as signed)
  let result = @executor.call_exported_func(store, instance, "shl", [
    I32(2147483647),
    I32(1),
  ])
  inspect(result[0], content="I32(-2)")
}

///|
test "wasm-testsuite: i32.shr_s" {
  let mod = create_i32_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "shr_s" (i32.const 1) (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "shr_s", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "shr_s" (i32.const -1) (i32.const 1)) (i32.const -1))
  let result = @executor.call_exported_func(store, instance, "shr_s", [
    I32(-1),
    I32(1),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "shr_s" (i32.const 0x80000000) (i32.const 1)) (i32.const 0xc0000000))
  // -2147483648 >> 1 = -1073741824 (sign extended)
  let result = @executor.call_exported_func(store, instance, "shr_s", [
    I32(-2147483648),
    I32(1),
  ])
  inspect(result[0], content="I32(-1073741824)")
}

///|
/// Create i32 comparison test module
fn create_i32_cmp_module() -> @types.Module {
  let eq_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Eq],
  }
  let ne_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Ne],
  }
  let lt_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32LtS],
  }
  let lt_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32LtU],
  }
  let le_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32LeS],
  }
  let gt_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32GtS],
  }
  let ge_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32GeU],
  }
  let eqz_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Eqz],
  }
  let binary_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [
      @types.SubType::from_func(binary_type),
      @types.SubType::from_func(unary_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 0, 0, 0, 0, 0, 0, 1],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "eq", desc: @types.ExportDesc::Func(0) },
      { name: "ne", desc: @types.ExportDesc::Func(1) },
      { name: "lt_s", desc: @types.ExportDesc::Func(2) },
      { name: "lt_u", desc: @types.ExportDesc::Func(3) },
      { name: "le_s", desc: @types.ExportDesc::Func(4) },
      { name: "gt_s", desc: @types.ExportDesc::Func(5) },
      { name: "ge_u", desc: @types.ExportDesc::Func(6) },
      { name: "eqz", desc: @types.ExportDesc::Func(7) },
    ],
    start: None,
    elems: [],
    codes: [
      eq_func, ne_func, lt_s_func, lt_u_func, le_s_func, gt_s_func, ge_u_func, eqz_func,
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i32.eq" {
  let mod = create_i32_cmp_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "eq" (i32.const 0) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "eq", [
    I32(0),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "eq" (i32.const 1) (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "eq", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
}

///|
test "wasm-testsuite: i32.lt_s" {
  let mod = create_i32_cmp_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "lt_s" (i32.const 0) (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "lt_s", [
    I32(0),
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "lt_s" (i32.const 0) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "lt_s", [
    I32(0),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "lt_s" (i32.const -1) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "lt_s", [
    I32(-1),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "lt_s" (i32.const 0x80000000) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "lt_s", [
    I32(-2147483648),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
}

///|
test "wasm-testsuite: i32.eqz" {
  let mod = create_i32_cmp_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "eqz" (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "eqz", [I32(0)])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "eqz" (i32.const 1)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "eqz", [I32(1)])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "eqz" (i32.const 0x80000000)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "eqz", [
    I32(-2147483648),
  ])
  inspect(result[0], content="I32(0)")
}

///|
/// Create i32 unary test module for clz, ctz, popcnt
fn create_i32_unary_module() -> @types.Module {
  let clz_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Clz],
  }
  let ctz_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Ctz],
  }
  let popcnt_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Popcnt],
  }
  let extend8_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Extend8S],
  }
  let extend16_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Extend16S],
  }
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [@types.SubType::from_func(unary_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0, 0, 0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "clz", desc: @types.ExportDesc::Func(0) },
      { name: "ctz", desc: @types.ExportDesc::Func(1) },
      { name: "popcnt", desc: @types.ExportDesc::Func(2) },
      { name: "extend8_s", desc: @types.ExportDesc::Func(3) },
      { name: "extend16_s", desc: @types.ExportDesc::Func(4) },
    ],
    start: None,
    elems: [],
    codes: [clz_func, ctz_func, popcnt_func, extend8_s_func, extend16_s_func],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i32.clz" {
  let mod = create_i32_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "clz" (i32.const 0xffffffff)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "clz", [I32(-1)])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "clz" (i32.const 0)) (i32.const 32))
  let result = @executor.call_exported_func(store, instance, "clz", [I32(0)])
  inspect(result[0], content="I32(32)")
  // (assert_return (invoke "clz" (i32.const 0x00008000)) (i32.const 16))
  let result = @executor.call_exported_func(store, instance, "clz", [I32(32768)])
  inspect(result[0], content="I32(16)")
  // (assert_return (invoke "clz" (i32.const 1)) (i32.const 31))
  let result = @executor.call_exported_func(store, instance, "clz", [I32(1)])
  inspect(result[0], content="I32(31)")
  // (assert_return (invoke "clz" (i32.const 0x80000000)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "clz", [
    I32(-2147483648),
  ])
  inspect(result[0], content="I32(0)")
}

///|
test "wasm-testsuite: i32.ctz" {
  let mod = create_i32_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "ctz" (i32.const 0xffffffff)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "ctz", [I32(-1)])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "ctz" (i32.const 0)) (i32.const 32))
  let result = @executor.call_exported_func(store, instance, "ctz", [I32(0)])
  inspect(result[0], content="I32(32)")
  // (assert_return (invoke "ctz" (i32.const 0x00008000)) (i32.const 15))
  let result = @executor.call_exported_func(store, instance, "ctz", [I32(32768)])
  inspect(result[0], content="I32(15)")
  // (assert_return (invoke "ctz" (i32.const 0x80000000)) (i32.const 31))
  let result = @executor.call_exported_func(store, instance, "ctz", [
    I32(-2147483648),
  ])
  inspect(result[0], content="I32(31)")
}

///|
test "wasm-testsuite: i32.popcnt" {
  let mod = create_i32_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "popcnt" (i32.const 0xffffffff)) (i32.const 32))
  let result = @executor.call_exported_func(store, instance, "popcnt", [I32(-1)])
  inspect(result[0], content="I32(32)")
  // (assert_return (invoke "popcnt" (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "popcnt", [I32(0)])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "popcnt" (i32.const 0x00008000)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "popcnt", [
    I32(32768),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "popcnt" (i32.const 0x80008000)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "popcnt", [
    I32(-2147450880),
  ])
  inspect(result[0], content="I32(2)")
}

///|
test "wasm-testsuite: i32.extend8_s" {
  let mod = create_i32_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "extend8_s" (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "extend8_s" (i32.const 0x7f)) (i32.const 127))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I32(127),
  ])
  inspect(result[0], content="I32(127)")
  // (assert_return (invoke "extend8_s" (i32.const 0x80)) (i32.const -128))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I32(128),
  ])
  inspect(result[0], content="I32(-128)")
  // (assert_return (invoke "extend8_s" (i32.const 0xff)) (i32.const -1))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I32(255),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "extend8_s" (i32.const 0x012345fe)) (i32.const -2))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I32(0x012345fe),
  ])
  inspect(result[0], content="I32(-2)")
}

///|
test "wasm-testsuite: i32.extend16_s" {
  let mod = create_i32_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "extend16_s" (i32.const 0)) (i32.const 0))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I32(0),
  ])
  inspect(result[0], content="I32(0)")
  // (assert_return (invoke "extend16_s" (i32.const 0x7fff)) (i32.const 32767))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I32(32767),
  ])
  inspect(result[0], content="I32(32767)")
  // (assert_return (invoke "extend16_s" (i32.const 0x8000)) (i32.const -32768))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I32(32768),
  ])
  inspect(result[0], content="I32(-32768)")
  // (assert_return (invoke "extend16_s" (i32.const 0xffff)) (i32.const -1))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I32(65535),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "extend16_s" (i32.const 0x0123fffe)) (i32.const -2))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I32(0x0123fffe),
  ])
  inspect(result[0], content="I32(-2)")
}

///|
/// Create i32 rotate test module
fn create_i32_rotate_module() -> @types.Module {
  let rotl_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Rotl],
  }
  let rotr_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Rotr],
  }
  let binary_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  {
    types: [@types.SubType::from_func(binary_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "rotl", desc: @types.ExportDesc::Func(0) },
      { name: "rotr", desc: @types.ExportDesc::Func(1) },
    ],
    start: None,
    elems: [],
    codes: [rotl_func, rotr_func],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i32.rotl" {
  let mod = create_i32_rotate_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "rotl" (i32.const 1) (i32.const 1)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(2)")
  // (assert_return (invoke "rotl" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rotl" (i32.const 0xffffffff) (i32.const 1)) (i32.const 0xffffffff))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(-1),
    I32(1),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "rotl" (i32.const 1) (i32.const 32)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(1),
    I32(32),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rotl" (i32.const 1) (i32.const 31)) (i32.const 0x80000000))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(1),
    I32(31),
  ])
  inspect(result[0], content="I32(-2147483648)")
  // (assert_return (invoke "rotl" (i32.const 0x80000000) (i32.const 1)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I32(-2147483648),
    I32(1),
  ])
  inspect(result[0], content="I32(1)")
}

///|
test "wasm-testsuite: i32.rotr" {
  let mod = create_i32_rotate_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "rotr" (i32.const 1) (i32.const 1)) (i32.const 0x80000000))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(1),
    I32(1),
  ])
  inspect(result[0], content="I32(-2147483648)")
  // (assert_return (invoke "rotr" (i32.const 1) (i32.const 0)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(1),
    I32(0),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rotr" (i32.const 0xffffffff) (i32.const 1)) (i32.const 0xffffffff))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(-1),
    I32(1),
  ])
  inspect(result[0], content="I32(-1)")
  // (assert_return (invoke "rotr" (i32.const 1) (i32.const 32)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(1),
    I32(32),
  ])
  inspect(result[0], content="I32(1)")
  // (assert_return (invoke "rotr" (i32.const 1) (i32.const 31)) (i32.const 2))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(1),
    I32(31),
  ])
  inspect(result[0], content="I32(2)")
  // (assert_return (invoke "rotr" (i32.const 0x80000000) (i32.const 31)) (i32.const 1))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I32(-2147483648),
    I32(31),
  ])
  inspect(result[0], content="I32(1)")
}

///|
/// Test loading wasm file from binary (debug test)
test "wasm-testsuite: load i32.0.wasm binary" {
  // Create the binary manually - first few bytes of i32.0.wasm
  // This represents a minimal valid wasm module
  let bytes : Array[Byte] = [
    // Magic number: \0asm
    0x00, 0x61, 0x73, 0x6d,
    // Version: 1
     0x01, 0x00, 0x00, 0x00,
    // Type section (1)
     0x01, // section id
     0x0c, // section size (12 bytes)
     0x02, // 2 types
    // type 0: (i32, i32) -> i32
     0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
    // type 1: (i32) -> i32
     0x60, 0x01, 0x7f, 0x01, 0x7f,
    // Function section (3)
     0x03, // section id
     0x02, // section size
     0x01, // 1 function
     0x00, // function 0 uses type 0
    // Export section (7)
     0x07, // section id
     0x07, // section size
     0x01, // 1 export
     0x03, // name length
     0x61, 0x64, 0x64, // "add"
     0x00, // export kind: func
     0x00, // func index 0
    // Code section (10)
     0x0a, // section id
     0x09, // section size
     0x01, // 1 code
     0x07, // code 0 size
     0x00, // 0 locals
     0x20, 0x00, // local.get 0
     0x20, 0x01, // local.get 1
     0x6a, // i32.add
     0x0b, // end
  ]
  let bytes_data = Bytes::from_array(bytes)
  let mod = @parser.parse_module(bytes_data)
  inspect(mod.types.length(), content="2")
  inspect(mod.funcs.length(), content="1")
  inspect(mod.codes.length(), content="1")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="add")
  // Now instantiate and call
  let (store, instance) = @executor.instantiate_module(mod)
  let result = @executor.call_exported_func(store, instance, "add", [
    I32(3),
    I32(5),
  ])
  inspect(result[0], content="I32(8)")
}

///|
/// Test that invalid wasm is rejected by validator
test "wasm-testsuite: i32.1.wasm should fail validation" {
  // i32.1.wasm contains: type-unary-operand-empty
  // Function with empty stack tries to do i32.eqz
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, // magic
     0x01, 0x00, 0x00, 0x00, // version
     0x01, 0x04, 0x01, 0x60, 0x00, 0x00, // type section: () -> ()
     0x03, 0x02, 0x01, 0x00, // func section: 1 function, type 0
     0x0a, 0x06, 0x01, 0x04, // code section: 1 code, 4 bytes
     0x00, // 0 locals
     0x45, // i32.eqz - pops i32, but stack is empty!
     0x1a, // drop
     0x0b, // end
  ]
  let bytes_data = Bytes::from_array(bytes)
  let mod = @parser.parse_module(bytes_data)
  inspect(
    try? @validator.validate_module(mod),
    content=(
      #|Err(StackUnderflow("Expected I32, but stack is empty"))
    ),
  )
}
