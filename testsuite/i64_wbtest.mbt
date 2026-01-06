// Tests for i64 operations from official wasm-testsuite
// These tests are extracted from the official WebAssembly testsuite

///|
/// Create i64 arithmetic test module
fn create_i64_arithmetic_module() -> @types.Module {
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Add],
  }
  let sub_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Sub],
  }
  let mul_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Mul],
  }
  let div_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64DivS],
  }
  let div_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64DivU],
  }
  let rem_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64RemS],
  }
  let rem_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64RemU],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I64, @types.ValueType::I64],
    results: [@types.ValueType::I64],
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
test "wasm-testsuite: i64.add" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "add" (i64.const 1) (i64.const 1)) (i64.const 2))
  let result = @executor.call_exported_func(store, instance, "add", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(2)")
  // (assert_return (invoke "add" (i64.const 1) (i64.const 0)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "add", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "add" (i64.const -1) (i64.const -1)) (i64.const -2))
  let result = @executor.call_exported_func(store, instance, "add", [
    I64(-1L),
    I64(-1L),
  ])
  inspect(result[0], content="I64(-2)")
  // (assert_return (invoke "add" (i64.const -1) (i64.const 1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "add", [
    I64(-1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(0)")
}

///|
test "wasm-testsuite: i64.sub" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "sub" (i64.const 1) (i64.const 1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "sub" (i64.const 1) (i64.const 0)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "sub" (i64.const -1) (i64.const -1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "sub", [
    I64(-1L),
    I64(-1L),
  ])
  inspect(result[0], content="I64(0)")
}

///|
test "wasm-testsuite: i64.mul" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "mul" (i64.const 1) (i64.const 1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "mul" (i64.const 1) (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "mul" (i64.const -1) (i64.const -1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "mul", [
    I64(-1L),
    I64(-1L),
  ])
  inspect(result[0], content="I64(1)")
}

///|
test "wasm-testsuite: i64.div_s trap on zero" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_trap (invoke "div_s" (i64.const 1) (i64.const 0)) "integer divide by zero")
  inspect(
    try? @executor.call_exported_func(store, instance, "div_s", [
      I64(1L),
      I64(0L),
    ]),
    content="Err(integer divide by zero)",
  )
}

///|
test "wasm-testsuite: i64.div_s trap on overflow" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_trap (invoke "div_s" (i64.const 0x8000000000000000) (i64.const -1)) "integer overflow")
  // INT64_MIN / -1 overflows
  inspect(
    try? @executor.call_exported_func(store, instance, "div_s", [
      I64(-9223372036854775808L),
      I64(-1L),
    ]),
    content="Err(integer overflow)",
  )
}

///|
test "wasm-testsuite: i64.div_s normal cases" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "div_s" (i64.const 1) (i64.const 1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "div_s" (i64.const 0) (i64.const 1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I64(0L),
    I64(1L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "div_s" (i64.const -1) (i64.const -1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I64(-1L),
    I64(-1L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "div_s" (i64.const 5) (i64.const 2)) (i64.const 2))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I64(5L),
    I64(2L),
  ])
  inspect(result[0], content="I64(2)")
  // (assert_return (invoke "div_s" (i64.const -5) (i64.const 2)) (i64.const -2))
  let result = @executor.call_exported_func(store, instance, "div_s", [
    I64(-5L),
    I64(2L),
  ])
  inspect(result[0], content="I64(-2)")
}

///|
test "wasm-testsuite: i64.div_u" {
  let mod = create_i64_arithmetic_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "div_u" (i64.const 1) (i64.const 1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "div_u" (i64.const 0) (i64.const 1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I64(0L),
    I64(1L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "div_u" (i64.const 5) (i64.const 2)) (i64.const 2))
  let result = @executor.call_exported_func(store, instance, "div_u", [
    I64(5L),
    I64(2L),
  ])
  inspect(result[0], content="I64(2)")
}

///|
/// Create i64 bitwise test module
fn create_i64_bitwise_module() -> @types.Module {
  let and_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64And],
  }
  let or_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Or],
  }
  let xor_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Xor],
  }
  let shl_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Shl],
  }
  let shr_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64ShrS],
  }
  let shr_u_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64ShrU],
  }
  let rotl_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Rotl],
  }
  let rotr_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Rotr],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I64, @types.ValueType::I64],
    results: [@types.ValueType::I64],
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
test "wasm-testsuite: i64.and" {
  let mod = create_i64_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "and" (i64.const 1) (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "and", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "and" (i64.const 1) (i64.const 1)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "and", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(1)")
}

///|
test "wasm-testsuite: i64.shl" {
  let mod = create_i64_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "shl" (i64.const 1) (i64.const 1)) (i64.const 2))
  let result = @executor.call_exported_func(store, instance, "shl", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(2)")
  // (assert_return (invoke "shl" (i64.const 1) (i64.const 0)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "shl", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(1)")
}

///|
test "wasm-testsuite: i64.rotl" {
  let mod = create_i64_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "rotl" (i64.const 1) (i64.const 1)) (i64.const 2))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(2)")
  // (assert_return (invoke "rotl" (i64.const 1) (i64.const 0)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "rotl" (i64.const -1) (i64.const 1)) (i64.const -1))
  let result = @executor.call_exported_func(store, instance, "rotl", [
    I64(-1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(-1)")
}

///|
test "wasm-testsuite: i64.rotr" {
  let mod = create_i64_bitwise_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "rotr" (i64.const 1) (i64.const 1)) (i64.const 0x8000000000000000))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I64(1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(-9223372036854775808)")
  // (assert_return (invoke "rotr" (i64.const 1) (i64.const 0)) (i64.const 1))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I64(1L),
    I64(0L),
  ])
  inspect(result[0], content="I64(1)")
  // (assert_return (invoke "rotr" (i64.const -1) (i64.const 1)) (i64.const -1))
  let result = @executor.call_exported_func(store, instance, "rotr", [
    I64(-1L),
    I64(1L),
  ])
  inspect(result[0], content="I64(-1)")
}

///|
/// Create i64 unary test module for clz, ctz, popcnt
fn create_i64_unary_module() -> @types.Module {
  let clz_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Clz],
  }
  let ctz_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Ctz],
  }
  let popcnt_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Popcnt],
  }
  let extend8_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Extend8S],
  }
  let extend16_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Extend16S],
  }
  let extend32_s_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64Extend32S],
  }
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [@types.ValueType::I64],
  }
  {
    types: [@types.SubType::from_func(unary_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0, 0, 0, 0, 0],
    tables: [],
    memories: [],
    globals: [],
    exports: [
      { name: "clz", desc: @types.ExportDesc::Func(0) },
      { name: "ctz", desc: @types.ExportDesc::Func(1) },
      { name: "popcnt", desc: @types.ExportDesc::Func(2) },
      { name: "extend8_s", desc: @types.ExportDesc::Func(3) },
      { name: "extend16_s", desc: @types.ExportDesc::Func(4) },
      { name: "extend32_s", desc: @types.ExportDesc::Func(5) },
    ],
    start: None,
    elems: [],
    codes: [
      clz_func, ctz_func, popcnt_func, extend8_s_func, extend16_s_func, extend32_s_func,
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
}

///|
test "wasm-testsuite: i64.clz" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "clz" (i64.const -1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "clz", [I64(-1L)])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "clz" (i64.const 0)) (i64.const 64))
  let result = @executor.call_exported_func(store, instance, "clz", [I64(0L)])
  inspect(result[0], content="I64(64)")
  // (assert_return (invoke "clz" (i64.const 1)) (i64.const 63))
  let result = @executor.call_exported_func(store, instance, "clz", [I64(1L)])
  inspect(result[0], content="I64(63)")
}

///|
test "wasm-testsuite: i64.ctz" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "ctz" (i64.const -1)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "ctz", [I64(-1L)])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "ctz" (i64.const 0)) (i64.const 64))
  let result = @executor.call_exported_func(store, instance, "ctz", [I64(0L)])
  inspect(result[0], content="I64(64)")
}

///|
test "wasm-testsuite: i64.popcnt" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "popcnt" (i64.const -1)) (i64.const 64))
  let result = @executor.call_exported_func(store, instance, "popcnt", [
    I64(-1L),
  ])
  inspect(result[0], content="I64(64)")
  // (assert_return (invoke "popcnt" (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "popcnt", [I64(0L)])
  inspect(result[0], content="I64(0)")
}

///|
test "wasm-testsuite: i64.extend8_s" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "extend8_s" (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I64(0L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "extend8_s" (i64.const 0x7f)) (i64.const 127))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I64(127L),
  ])
  inspect(result[0], content="I64(127)")
  // (assert_return (invoke "extend8_s" (i64.const 0x80)) (i64.const -128))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I64(128L),
  ])
  inspect(result[0], content="I64(-128)")
  // (assert_return (invoke "extend8_s" (i64.const 0xff)) (i64.const -1))
  let result = @executor.call_exported_func(store, instance, "extend8_s", [
    I64(255L),
  ])
  inspect(result[0], content="I64(-1)")
}

///|
test "wasm-testsuite: i64.extend16_s" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "extend16_s" (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I64(0L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "extend16_s" (i64.const 0x7fff)) (i64.const 32767))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I64(32767L),
  ])
  inspect(result[0], content="I64(32767)")
  // (assert_return (invoke "extend16_s" (i64.const 0x8000)) (i64.const -32768))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I64(32768L),
  ])
  inspect(result[0], content="I64(-32768)")
  // (assert_return (invoke "extend16_s" (i64.const 0xffff)) (i64.const -1))
  let result = @executor.call_exported_func(store, instance, "extend16_s", [
    I64(65535L),
  ])
  inspect(result[0], content="I64(-1)")
}

///|
test "wasm-testsuite: i64.extend32_s" {
  let mod = create_i64_unary_module()
  let (store, instance) = @executor.instantiate_module(mod)
  // (assert_return (invoke "extend32_s" (i64.const 0)) (i64.const 0))
  let result = @executor.call_exported_func(store, instance, "extend32_s", [
    I64(0L),
  ])
  inspect(result[0], content="I64(0)")
  // (assert_return (invoke "extend32_s" (i64.const 0x7fffffff)) (i64.const 2147483647))
  let result = @executor.call_exported_func(store, instance, "extend32_s", [
    I64(2147483647L),
  ])
  inspect(result[0], content="I64(2147483647)")
  // (assert_return (invoke "extend32_s" (i64.const 0x80000000)) (i64.const -2147483648))
  let result = @executor.call_exported_func(store, instance, "extend32_s", [
    I64(2147483648L),
  ])
  inspect(result[0], content="I64(-2147483648)")
  // (assert_return (invoke "extend32_s" (i64.const 0xffffffff)) (i64.const -1))
  let result = @executor.call_exported_func(store, instance, "extend32_s", [
    I64(4294967295L),
  ])
  inspect(result[0], content="I64(-1)")
}
