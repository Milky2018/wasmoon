// Executor Tests

///|
test "execute simple add function" {
  // Create a simple module that adds two i32 values
  // Function signature: (i32, i32) -> i32
  // Function body: local.get 0, local.get 1, i32.add

  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
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
    exports: [{ name: "add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [add_func],
    datas: [],
  }

  // Instantiate and call
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(5), @wasmoon.Value::I32(10)]
  let results = call_exported_func(store, instance, "add", args)
  match results[0] {
    I32(n) => inspect(n, content="15")
    _ => fail("Expected I32 result")
  }
}

///|
test "execute function with local variables" {
  // Function: (a, b) => { let tmp = a + b; return tmp * 2 }

  let func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32], // one local variable
    body: [
      LocalGet(0), // get a
      LocalGet(1), // get b
      I32Add, // a + b
      LocalSet(2), // store in local (index 2)
      LocalGet(2), // get local
      I32Const(2), // constant 2
      I32Mul, // tmp * 2
    ],
  }
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
    exports: [{ name: "double_sum", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(3), @wasmoon.Value::I32(4)]
  let results = call_exported_func(store, instance, "double_sum", args)
  match results[0] {
    I32(n) => inspect(n, content="14") // (3 + 4) * 2 = 14
    _ => fail("Expected I32 result")
  }
}

///|
test "execute i64 addition" {
  // Test i64 arithmetic: (a, b) => a + b
  let i64_add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64Add],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64, @wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "i64_add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [i64_add_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [
    @wasmoon.Value::I64(1000000000000L),
    @wasmoon.Value::I64(2000000000000L),
  ]
  let results = call_exported_func(store, instance, "i64_add", args)
  match results[0] {
    I64(n) => inspect(n, content="3000000000000")
    _ => fail("Expected I64 result")
  }
}

///|
test "execute f32 arithmetic" {
  // Test f32 operations: (a, b) => a + b * 2.0
  let f32_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(1), // b
      F32Const(2.0), // 2.0
      F32Mul, // b * 2.0
      LocalGet(0), // a
      F32Add,
    ],
  } // a + (b * 2.0)
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32, @wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::F32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f32_test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [f32_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::F32(3.5), @wasmoon.Value::F32(4.0)]
  let results = call_exported_func(store, instance, "f32_test", args)
  match results[0] {
    F32(f) => inspect(f, content="11.5") // 3.5 + 4.0 * 2.0 = 11.5
    _ => fail("Expected F32 result")
  }
}

///|
test "execute f64 arithmetic" {
  // Test f64 operations: (a, b) => (a - b) * 0.5
  let f64_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(0), // a
      LocalGet(1), // b
      F64Sub, // a - b
      F64Const(0.5), // 0.5
      F64Mul,
    ],
  } // (a - b) * 0.5
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F64, @wasmoon.ValueType::F64],
    results: [@wasmoon.ValueType::F64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "f64_test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [f64_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::F64(10.0), @wasmoon.Value::F64(6.0)]
  let results = call_exported_func(store, instance, "f64_test", args)
  match results[0] {
    F64(d) => inspect(d, content="2") // (10.0 - 6.0) * 0.5 = 2.0
    _ => fail("Expected F64 result")
  }
}

///|
test "execute i64 comparison" {
  // Test i64 comparison: (a, b) => a < b
  let i64_cmp_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I64LtS],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64, @wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "i64_lt", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [i64_cmp_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I64(100L), @wasmoon.Value::I64(200L)]
  let results = call_exported_func(store, instance, "i64_lt", args)
  match results[0] {
    I32(n) => inspect(n, content="1") // 100 < 200 = true (1)
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i32.wrap_i64" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32WrapI64],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "wrap", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 0x0000000100000005 -> 0x00000005 = 5
  let args = [@wasmoon.Value::I64(4294967301L)]
  let results = call_exported_func(store, instance, "wrap", args)
  match results[0] {
    I32(n) => inspect(n, content="5")
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i64.extend_i32_s" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I64ExtendI32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "extend_s", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // -1 (i32) -> -1 (i64)
  let args = [@wasmoon.Value::I32(-1)]
  let results = call_exported_func(store, instance, "extend_s", args)
  match results[0] {
    I64(n) => inspect(n, content="-1")
    _ => fail("Expected I64 result")
  }
}

///|
test "numeric conversion: f64.convert_i32_s" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), F64ConvertI32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::F64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "convert", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let args = [@wasmoon.Value::I32(-42)]
  let results = call_exported_func(store, instance, "convert", args)
  match results[0] {
    F64(d) => inspect(d, content="-42")
    _ => fail("Expected F64 result")
  }
}

///|
test "numeric conversion: i32.reinterpret_f32" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32ReinterpretF32],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "reinterpret", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 1.0f32 的 IEEE 754 表示是 0x3F800000 = 1065353216
  let args = [@wasmoon.Value::F32(1.0)]
  let results = call_exported_func(store, instance, "reinterpret", args)
  match results[0] {
    I32(n) => inspect(n, content="1065353216")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f32_s overflow" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32TruncSatF32S],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "trunc_sat", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 超出 i32 最大值，应该饱和到 2147483647
  let args = [@wasmoon.Value::F32(3000000000.0)]
  let results = call_exported_func(store, instance, "trunc_sat", args)
  match results[0] {
    I32(n) => inspect(n, content="2147483647")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f64_u negative" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32TruncSatF64U],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::F64],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "trunc_sat_u", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // 负数对于无符号饱和截断应该返回 0
  let args = [@wasmoon.Value::F64(-100.0)]
  let results = call_exported_func(store, instance, "trunc_sat_u", args)
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.store and i32.load" {
  // Function: store value 42 at address 0, then load and return it
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(42), // value
      I32Store(2, 0), // align=2, offset=0
      I32Const(0), // address
      I32Load(2, 0),
    ],
  } // align=2, offset=0
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i64.store and i64.load" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I64Const(1234567890123L), // value
      I64Store(3, 0), // align=3, offset=0
      I32Const(0), // address
      I64Load(3, 0),
    ],
  } // load
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I64],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I64(n) => inspect(n, content="1234567890123")
    _ => fail("Expected I64 result")
  }
}

///|
test "memory: f32.store and f32.load" {
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      F32Const(3.14), // value
      F32Store(2, 0), // store
      I32Const(0), // address
      F32Load(2, 0),
    ],
  } // load
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::F32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    F32(f) => {
      // f32 has limited precision, check approximately
      let diff = (f - 3.14).abs()
      inspect(diff < 0.001, content="true")
    }
    _ => fail("Expected F32 result")
  }
}

///|
test "memory: load with offset" {
  // Store 100 at address 8, then load from address 0 with offset 8
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(8), // address
      I32Const(100), // value
      I32Store(2, 0), // store at address 8
      I32Const(0), // base address
      I32Load(2, 8),
    ],
  } // load from 0 + offset 8 = 8
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.load8_s sign extension" {
  // Store 0xFF at address 0 (as i32), then load as signed byte
  // 0xFF as signed byte is -1
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(255), // value (0xFF)
      I32Store8(0, 0), // store as byte
      I32Const(0), // address
      I32Load8S(0, 0),
    ],
  } // load as signed byte
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="-1")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.load8_u zero extension" {
  // Store 0xFF at address 0, then load as unsigned byte
  // 0xFF as unsigned byte is 255
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // address
      I32Const(255), // value (0xFF)
      I32Store8(0, 0), // store as byte
      I32Const(0), // address
      I32Load8U(0, 0),
    ],
  } // load as unsigned byte
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="255")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: memory.size and memory.grow" {
  // Check initial size (1 page), grow by 2 pages, return new size
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      MemorySize, // get current size (1)
      Drop, // discard
      I32Const(2), // delta
      MemoryGrow, // grow by 2, returns old size (1)
      Drop, // discard old size
      MemorySize,
    ],
  } // get new size (3)
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [{ limits: { min: 1, max: None } }],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="3")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: simple block" {
  // block returns value from inner expression
  // (block (result i32) (i32.const 42))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [Block(Value(@wasmoon.ValueType::I32), [I32Const(42)])],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br exits block" {
  // (block (result i32)
  //   (i32.const 10)
  //   (br 0)
  //   (i32.const 20)  ;; unreachable
  // )
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [I32Const(10), Br(0), I32Const(20)]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br_if conditional" {
  // (func (param i32) (result i32)
  //   (block (result i32)
  //     (i32.const 100)
  //     (local.get 0)
  //     (br_if 0)  ;; if param != 0, exit with 100
  //     (drop)
  //     (i32.const 200)
  //   ))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [
        I32Const(100),
        LocalGet(0),
        BrIf(0),
        Drop,
        I32Const(200),
      ]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // Test with condition true (1) - should return 100
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
  // Test with condition false (0) - should return 200
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="200")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: loop with br" {
  // Sum 1 to 5 using loop
  // (func (result i32)
  //   (local i32 i32)  ;; counter, sum
  //   (local.set 0 (i32.const 1))  ;; counter = 1
  //   (local.set 1 (i32.const 0))  ;; sum = 0
  //   (loop
  //     (local.set 1 (i32.add (local.get 1) (local.get 0)))  ;; sum += counter
  //     (local.set 0 (i32.add (local.get 0) (i32.const 1)))  ;; counter++
  //     (br_if 0 (i32.le_s (local.get 0) (i32.const 5)))     ;; if counter <= 5, loop
  //   )
  //   (local.get 1))  ;; return sum
  let func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32], // counter, sum
    body: [
      I32Const(1),
      LocalSet(0), // counter = 1
      I32Const(0),
      LocalSet(1), // sum = 0
      Loop(Empty, [
        LocalGet(1),
        LocalGet(0),
        I32Add,
        LocalSet(1), // sum += counter
        LocalGet(0),
        I32Const(1),
        I32Add,
        LocalSet(0), // counter++
        LocalGet(0),
        I32Const(5),
        I32LeS,
        BrIf(0),
      ]), // if counter <= 5, continue
      LocalGet(1),
    ],
  } // return sum
  let func_type : @wasmoon.FuncType = {
    params: [],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="15") // 1+2+3+4+5 = 15
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: if-else" {
  // (func (param i32) (result i32)
  //   (if (result i32) (local.get 0)
  //     (then (i32.const 111))
  //     (else (i32.const 222))))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(0),
      If(Value(@wasmoon.ValueType::I32), [I32Const(111)], [I32Const(222)]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // Test with true (1)
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="111")
    _ => fail("Expected I32 result")
  }
  // Test with false (0)
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="222")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: nested blocks with br" {
  // (block $outer (result i32)
  //   (block $inner
  //     (i32.const 50)
  //     (br 1)  ;; jump to outer
  //   )
  //   (i32.const 99))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      Block(Value(@wasmoon.ValueType::I32), [
        Block(Empty, [I32Const(50), Br(1)]),
        I32Const(99),
      ]),
    ],
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="50")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: select" {
  // (func (param i32 i32 i32) (result i32)
  //   (select (local.get 0) (local.get 1) (local.get 2)))
  let func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), LocalGet(2), Select],
  }
  let func_type : @wasmoon.FuncType = {
    params: [
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
    ],
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
    codes: [func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  // select(10, 20, 1) -> 10 (condition true)
  let results1 = call_exported_func(store, instance, "test", [
    I32(10),
    I32(20),
    I32(1),
  ])
  match results1[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
  // select(10, 20, 0) -> 20 (condition false)
  let results2 = call_exported_func(store, instance, "test", [
    I32(10),
    I32(20),
    I32(0),
  ])
  match results2[0] {
    I32(n) => inspect(n, content="20")
    _ => fail("Expected I32 result")
  }
}

///|
test "function call: call instruction" {
  // Module with two functions:
  // func 0: add(a, b) -> a + b
  // func 1: main() -> call add(3, 4)
  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let main_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [I32Const(3), I32Const(4), Call(0)],
  }
  let add_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let main_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [add_type, main_type],
    imports: [],
    funcs: [0, 1], // func 0 has type 0, func 1 has type 1
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @wasmoon.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [add_func, main_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "main", [])
  match results[0] {
    I32(n) => inspect(n, content="7") // 3 + 4 = 7
    _ => fail("Expected I32 result")
  }
}

///|
test "function call: nested calls" {
  // Module with three functions:
  // func 0: double(x) -> x * 2
  // func 1: add_one(x) -> x + 1
  // func 2: main(x) -> add_one(double(x))
  let double_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Const(2), I32Mul],
  }
  let add_one_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Const(1), I32Add],
  }
  let main_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), Call(0), Call(1)], // double then add_one
  }
  let unary_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [unary_type],
    imports: [],
    funcs: [0, 0, 0], // all functions have type 0
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @wasmoon.ExportDesc::Func(2) }],
    start: None,
    elems: [],
    codes: [double_func, add_one_func, main_func],
    datas: [],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "main", [I32(5)])
  match results[0] {
    I32(n) => inspect(n, content="11") // (5 * 2) + 1 = 11
    _ => fail("Expected I32 result")
  }
}

///|
test "function call: call_indirect" {
  // Module with:
  // func 0: add(a, b) -> a + b
  // func 1: sub(a, b) -> a - b
  // func 2: apply(op, a, b) -> call_indirect(op, a, b)
  // table with [add, sub]
  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let sub_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Sub],
  }
  let apply_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      LocalGet(1), // a
      LocalGet(2), // b
      LocalGet(0), // op (table index)
      CallIndirect(0, 0),
    ],
  } // type 0, table 0
  let binary_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let apply_type : @wasmoon.FuncType = {
    params: [
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
      @wasmoon.ValueType::I32,
    ],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [binary_type, apply_type],
    imports: [],
    funcs: [0, 0, 1], // add and sub have type 0, apply has type 1
    tables: [
      { elem_type: @wasmoon.ValueType::FuncRef, limits: { min: 2, max: None } },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "apply", desc: @wasmoon.ExportDesc::Func(2) }],
    start: None,
    elems: [{ table_idx: 0, offset: [I32Const(0)], init: [0, 1] }],
    codes: [ // table[0] = func 0 (add), table[1] = func 1 (sub)
      add_func, sub_func, apply_func,
    ],
    datas: [],
  }
  let (store, instance) = instantiate_module_with_init(mod)
  // apply(0, 10, 3) -> add(10, 3) = 13
  let results1 = call_exported_func(store, instance, "apply", [
    I32(0),
    I32(10),
    I32(3),
  ])
  match results1[0] {
    I32(n) => inspect(n, content="13")
    _ => fail("Expected I32 result")
  }
  // apply(1, 10, 3) -> sub(10, 3) = 7
  let results2 = call_exported_func(store, instance, "apply", [
    I32(1),
    I32(10),
    I32(3),
  ])
  match results2[0] {
    I32(n) => inspect(n, content="7")
    _ => fail("Expected I32 result")
  }
}

///|
test "host function: simple call" {
  // Create a store and add host function to it
  let store = @runtime.Store::new()
  let host_fn : (Array[@wasmoon.Value]) -> Array[@wasmoon.Value] raise @runtime.RuntimeError = fn(
    args,
  ) {
    match args[0] {
      I32(n) => [I32(n * 2)]
      _ => raise @runtime.TypeMismatch
    }
  }
  let host_addr = store.alloc_host_func(host_fn)

  // Create a module that imports and calls the host function
  // func 0: imported host function (double)
  // func 1: main(x) -> call double(x)
  let main_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [LocalGet(0), Call(0)], // call imported function at index 0
  }
  let unary_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [unary_type],
    imports: [{ mod_name: "env", name: "double", desc: Func(0) }],
    funcs: [0], // main has type 0
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @wasmoon.ExportDesc::Func(1) }], // func 1 is main (after import)
    start: None,
    elems: [],
    codes: [main_func],
    datas: [],
  }

  // Set up imports
  let imports = @runtime.Imports::new()
  imports.add_func("env", "double", host_addr)

  // Instantiate with the existing store
  let instance = instantiate_module_with_imports(store, mod, imports)
  let results = call_exported_func(store, instance, "main", [I32(21)])
  match results[0] {
    I32(n) => inspect(n, content="42") // 21 * 2 = 42
    _ => fail("Expected I32 result")
  }
}

///|
test "memory import: shared memory between modules" {
  // Create a store and allocate a shared memory
  let store = @runtime.Store::new()
  let shared_mem = @runtime.Memory::new(1, None) // 1 page
  let mem_addr = store.alloc_mem(shared_mem)

  // Write a value to the shared memory
  shared_mem.store_i32(0, 12345) catch {
    _ => fail("Failed to store")
  }

  // Create a module that imports this memory and reads from it
  // Function: read value at address 0
  let read_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [I32Const(0), I32Load(2, 0)], // load from address 0
  }
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [
      {
        mod_name: "env",
        name: "memory",
        desc: Memory({ limits: { min: 1, max: None } }),
      },
    ],
    funcs: [0],
    tables: [],
    memories: [], // No local memories, only imported
    globals: [],
    exports: [{ name: "read", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [read_func],
    datas: [],
  }

  // Set up imports
  let imports = @runtime.Imports::new()
  imports.add_memory("env", "memory", mem_addr)

  // Instantiate with the existing store
  let instance = instantiate_module_with_imports(store, mod, imports)
  let results = call_exported_func(store, instance, "read", [])
  match results[0] {
    I32(n) => inspect(n, content="12345")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory import: write to imported memory" {
  // Create a store and allocate a shared memory
  let store = @runtime.Store::new()
  let shared_mem = @runtime.Memory::new(1, None)
  let mem_addr = store.alloc_mem(shared_mem)

  // Create a module that imports this memory and writes to it
  // Function: write value 42 at address 100
  let write_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [I32Const(100), I32Const(42), I32Store(2, 0)],
  }
  let func_type : @wasmoon.FuncType = { params: [], results: [] }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [
      {
        mod_name: "env",
        name: "mem",
        desc: Memory({ limits: { min: 1, max: None } }),
      },
    ],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "write", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [write_func],
    datas: [],
  }
  let imports = @runtime.Imports::new()
  imports.add_memory("env", "mem", mem_addr)
  let instance = instantiate_module_with_imports(store, mod, imports)
  let _ = call_exported_func(store, instance, "write", [])

  // Verify the write by reading from the shared memory directly
  let value = shared_mem.load_i32(100) catch {
    _ => {
      fail("Failed to load")
      0
    }
  }
  inspect(value, content="42")
}

///|
test "import validation: missing import raises error" {
  let store = @runtime.Store::new()

  // Create a module that requires an import but don't provide it
  let func : @wasmoon.FunctionCode = { locals: [], body: [I32Const(1)] }
  let func_type : @wasmoon.FuncType = {
    params: [],
    results: [@wasmoon.ValueType::I32],
  }
  let mod : @wasmoon.Module = {
    types: [func_type],
    imports: [{ mod_name: "env", name: "missing_func", desc: Func(0) }],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @wasmoon.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
  }

  // Empty imports - should fail
  let imports = @runtime.Imports::new()

  // Should raise UnknownImport
  let result = try {
    let _ = instantiate_module_with_imports(store, mod, imports)
    false // Should not reach here
  } catch {
    @runtime.UnknownImport => true // Expected
    _ => false
  }
  inspect(result, content="true")
}
