// Executor Tests

///|
test "execute simple add function" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32, @types.ValueType::I32],
    [@types.ValueType::I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "add",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "add", [
    @types.Value::I32(5),
    @types.Value::I32(10),
  ])
  match results[0] {
    I32(n) => inspect(n, content="15")
    _ => fail("Expected I32 result")
  }
}

///|
test "execute function with local variables" {
  // Function: (a, b) => { let tmp = a + b; return tmp * 2 }
  let body : Array[@types.Instruction] = [
    LocalGet(0), // get a
    LocalGet(1), // get b
    I32Add, // a + b
    LocalSet(2), // store in local (index 2)
    LocalGet(2), // get local
    I32Const(2), // constant 2
    I32Mul, // tmp * 2
  ]
  let mod = {
    ..@types.Module::simple(
      [@types.ValueType::I32, @types.ValueType::I32],
      [@types.ValueType::I32],
      body,
      "double_sum",
    ),
    codes: [{ locals: [@types.ValueType::I32], body }],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "double_sum", [
    @types.Value::I32(3),
    @types.Value::I32(4),
  ])
  match results[0] {
    I32(n) => inspect(n, content="14") // (3 + 4) * 2 = 14
    _ => fail("Expected I32 result")
  }
}

///|
test "execute i64 addition" {
  let mod = @types.Module::simple(
    [@types.ValueType::I64, @types.ValueType::I64],
    [@types.ValueType::I64],
    [LocalGet(0), LocalGet(1), I64Add],
    "i64_add",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [
    @types.Value::I64(1000000000000L),
    @types.Value::I64(2000000000000L),
  ]
  let results = call_exported_func(store, instance, "i64_add", args)
  match results[0] {
    I64(n) => inspect(n, content="3000000000000")
    _ => fail("Expected I64 result")
  }
}

///|
test "execute f32 arithmetic" {
  let mod = @types.Module::simple(
    [@types.ValueType::F32, @types.ValueType::F32],
    [@types.ValueType::F32],
    [LocalGet(1), F32Const(2.0), F32Mul, LocalGet(0), F32Add],
    "f32_test",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::F32(3.5), @types.Value::F32(4.0)]
  let results = call_exported_func(store, instance, "f32_test", args)
  match results[0] {
    F32(f) => inspect(f, content="11.5") // 3.5 + 4.0 * 2.0 = 11.5
    _ => fail("Expected F32 result")
  }
}

///|
test "execute f64 arithmetic" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64, @types.ValueType::F64],
    [@types.ValueType::F64],
    [LocalGet(0), LocalGet(1), F64Sub, F64Const(0.5), F64Mul],
    "f64_test",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::F64(10.0), @types.Value::F64(6.0)]
  let results = call_exported_func(store, instance, "f64_test", args)
  match results[0] {
    F64(d) => inspect(d, content="2") // (10.0 - 6.0) * 0.5 = 2.0
    _ => fail("Expected F64 result")
  }
}

///|
test "execute i64 comparison" {
  let mod = @types.Module::simple(
    [@types.ValueType::I64, @types.ValueType::I64],
    [@types.ValueType::I32],
    [LocalGet(0), LocalGet(1), I64LtS],
    "i64_lt",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::I64(100L), @types.Value::I64(200L)]
  let results = call_exported_func(store, instance, "i64_lt", args)
  match results[0] {
    I32(n) => inspect(n, content="1") // 100 < 200 = true (1)
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i32.wrap_i64" {
  let mod = @types.Module::simple(
    [@types.ValueType::I64],
    [@types.ValueType::I32],
    [LocalGet(0), I32WrapI64],
    "wrap",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::I64(4294967301L)]
  let results = call_exported_func(store, instance, "wrap", args)
  match results[0] {
    I32(n) => inspect(n, content="5")
    _ => fail("Expected I32 result")
  }
}

///|
test "numeric conversion: i64.extend_i32_s" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::I64],
    [LocalGet(0), I64ExtendI32S],
    "extend_s",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::I32(-1)]
  let results = call_exported_func(store, instance, "extend_s", args)
  match results[0] {
    I64(n) => inspect(n, content="-1")
    _ => fail("Expected I64 result")
  }
}

///|
test "numeric conversion: f64.convert_i32_s" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::F64],
    [LocalGet(0), F64ConvertI32S],
    "convert",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::I32(-42)]
  let results = call_exported_func(store, instance, "convert", args)
  match results[0] {
    F64(d) => inspect(d, content="-42")
    _ => fail("Expected F64 result")
  }
}

///|
test "numeric conversion: i32.reinterpret_f32" {
  let mod = @types.Module::simple(
    [@types.ValueType::F32],
    [@types.ValueType::I32],
    [LocalGet(0), I32ReinterpretF32],
    "reinterpret",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::F32(1.0)]
  let results = call_exported_func(store, instance, "reinterpret", args)
  match results[0] {
    I32(n) => inspect(n, content="1065353216")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f32_s overflow" {
  let mod = @types.Module::simple(
    [@types.ValueType::F32],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncSatF32S],
    "trunc_sat",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::F32(3000000000.0)]
  let results = call_exported_func(store, instance, "trunc_sat", args)
  match results[0] {
    I32(n) => inspect(n, content="2147483647")
    _ => fail("Expected I32 result")
  }
}

///|
test "saturating truncation: i32.trunc_sat_f64_u negative" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncSatF64U],
    "trunc_sat_u",
  )
  let (store, instance) = instantiate_module(mod)
  let args = [@types.Value::F64(-100.0)]
  let results = call_exported_func(store, instance, "trunc_sat_u", args)
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "memory: i32.store and i32.load" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(42),
        I32Store(0, 2, 0),
        I32Const(0),
        I32Load(0, 2, 0),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I64],
      [
        I32Const(0),
        I64Const(1234567890123L),
        I64Store(0, 3, 0),
        I32Const(0),
        I64Load(0, 3, 0),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::F32],
      [
        I32Const(0),
        F32Const(3.14),
        F32Store(0, 2, 0),
        I32Const(0),
        F32Load(0, 2, 0),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    F32(f) => {
      let diff = (f - 3.14).abs()
      inspect(diff < 0.001, content="true")
    }
    _ => fail("Expected F32 result")
  }
}

///|
test "memory: load with offset" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(8),
        I32Const(100),
        I32Store(0, 2, 0),
        I32Const(0),
        I32Load(0, 2, 8),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(255),
        I32Store8(0, 0, 0),
        I32Const(0),
        I32Load8S(0, 0, 0),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(255),
        I32Store8(0, 0, 0),
        I32Const(0),
        I32Load8U(0, 0, 0),
      ],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [MemorySize(0), Drop, I32Const(2), MemoryGrow(0), Drop, MemorySize(0)],
      "test",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
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
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [Block(Value(@types.ValueType::I32), [I32Const(42)])],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br exits block" {
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [Block(Value(@types.ValueType::I32), [I32Const(10), Br(0), I32Const(20)])],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: br_if conditional" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::I32],
    [
      Block(Value(@types.ValueType::I32), [
        I32Const(100),
        LocalGet(0),
        BrIf(0),
        Drop,
        I32Const(200),
      ]),
    ],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="200")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: loop with br" {
  // Sum 1 to 5 using loop
  let body : Array[@types.Instruction] = [
    I32Const(1),
    LocalSet(0),
    I32Const(0),
    LocalSet(1),
    Loop(Empty, [
      LocalGet(1),
      LocalGet(0),
      I32Add,
      LocalSet(1),
      LocalGet(0),
      I32Const(1),
      I32Add,
      LocalSet(0),
      LocalGet(0),
      I32Const(5),
      I32LeS,
      BrIf(0),
    ]),
    LocalGet(1),
  ]
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I32], body, "test"),
    codes: [{ locals: [@types.ValueType::I32, @types.ValueType::I32], body }],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="15")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: if-else" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::I32],
    [
      LocalGet(0),
      If(Value(@types.ValueType::I32), [I32Const(111)], [I32Const(222)]),
    ],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
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
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [
      Block(Value(@types.ValueType::I32), [
        Block(Empty, [I32Const(50), Br(1)]),
        I32Const(99),
      ]),
    ],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="50")
    _ => fail("Expected I32 result")
  }
}

///|
test "control flow: select" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32, @types.ValueType::I32, @types.ValueType::I32],
    [@types.ValueType::I32],
    [LocalGet(0), LocalGet(1), LocalGet(2), Select],
    "test",
  )
  let (store, instance) = instantiate_module(mod)
  let results1 = call_exported_func(store, instance, "test", [
    I32(10),
    I32(20),
    I32(1),
  ])
  match results1[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
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
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let main_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(3), I32Const(4), Call(0)],
  }
  let add_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let main_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(add_type),
      @types.SubType::from_func(main_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1], // func 0 has type 0, func 1 has type 1
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [add_func, main_func],
    datas: [],
    tags: [],
    func_names: {},
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
  let double_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Const(2), I32Mul],
  }
  let add_one_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), I32Const(1), I32Add],
  }
  let main_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), Call(0), Call(1)], // double then add_one
  }
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(unary_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0, 0], // all functions have type 0
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @types.ExportDesc::Func(2) }],
    start: None,
    elems: [],
    codes: [double_func, add_one_func, main_func],
    datas: [],
    tags: [],
    func_names: {},
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
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let sub_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Sub],
  }
  let apply_func : @types.FunctionCode = {
    locals: [],
    body: [
      LocalGet(1), // a
      LocalGet(2), // b
      LocalGet(0), // op (table index)
      CallIndirect(0, 0),
    ],
  } // type 0, table 0
  let binary_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let apply_type : @types.FuncType = {
    params: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(binary_type),
      @types.SubType::from_func(apply_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 0, 1], // add and sub have type 0, apply has type 1
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 2, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "apply", desc: @types.ExportDesc::Func(2) }],
    start: None,
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)], [RefFunc(1)]],
      },
    ],
    codes: [ // table[0] = func 0 (add), table[1] = func 1 (sub)
      add_func, sub_func, apply_func,
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
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
  let host_fn : (Array[@types.Value]) -> Array[@types.Value] raise @runtime.RuntimeError = fn(
    args,
  ) {
    match args[0] {
      I32(n) => [I32(n * 2)]
      _ => raise @runtime.TypeMismatch
    }
  }
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let host_addr = store.alloc_host_func(host_fn, func_type=unary_type)

  // Create a module that imports and calls the host function
  // func 0: imported host function (double)
  // func 1: main(x) -> call double(x)
  let main_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), Call(0)], // call imported function at index 0
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(unary_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "env", name: "double", desc: Func(0) }],
    funcs: [0], // main has type 0
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "main", desc: @types.ExportDesc::Func(1) }], // func 1 is main (after import)
    start: None,
    elems: [],
    codes: [main_func],
    datas: [],
    tags: [],
    func_names: {},
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
test "host function: caller can access exported memory" {
  let store = @runtime.Store::new()

  // Host function writes 7 into caller-exported memory "mem" at address 0.
  let host_fn : (@runtime.Caller, Array[@types.Value]) -> Array[@types.Value] raise @runtime.RuntimeError = fn(
    caller,
    args,
  ) {
    if args.length() != 0 {
      raise @runtime.TypeMismatch
    }
    let mem = caller.get_exported_memory("mem")
    match mem {
      Some(m) => {
        m.store_i32(0, 7)
        []
      }
      None => raise @runtime.UndefinedElement
    }
  }
  let host_type : @types.FuncType = { params: [], results: [] }
  let host_addr = store.alloc_host_func_with_caller(
    host_fn,
    func_type=host_type,
  )

  // Define a module that:
  // - exports a memory as "mem"
  // - imports "env.write_mem0" and calls it
  // - reads mem[0] and returns it
  let main_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let main_func : @types.FunctionCode = {
    locals: [],
    body: [Call(0), I32Const(0), I32Load(0, 2, 0)],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(host_type),
      @types.SubType::from_func(main_type),
    ],
    type_rec_groups: [0, 1],
    imports: [{ mod_name: "env", name: "write_mem0", desc: Func(0) }],
    funcs: [1],
    tables: [],
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    globals: [],
    exports: [
      { name: "mem", desc: @types.ExportDesc::Memory(0) },
      { name: "main", desc: @types.ExportDesc::Func(1) },
    ],
    start: None,
    elems: [],
    codes: [main_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let imports = @runtime.Imports::new()
  imports.add_func("env", "write_mem0", host_addr)
  let instance = instantiate_module_with_imports(store, mod, imports)
  let results = call_exported_func(store, instance, "main", [])
  match results[0] {
    I32(n) => inspect(n, content="7")
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
  let read_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(0), I32Load(0, 2, 0)], // load from address 0
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [
      {
        mod_name: "env",
        name: "memory",
        desc: Memory({
          limits: { min: 1, max: None },
          is_memory64: false,
          page_size_log2: 16,
        }),
      },
    ],
    funcs: [0],
    tables: [],
    memories: [], // No local memories, only imported
    globals: [],
    exports: [{ name: "read", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [read_func],
    datas: [],
    tags: [],
    func_names: {},
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
  let write_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(100), I32Const(42), I32Store(0, 2, 0)],
  }
  let func_type : @types.FuncType = { params: [], results: [] }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [
      {
        mod_name: "env",
        name: "mem",
        desc: Memory({
          limits: { min: 1, max: None },
          is_memory64: false,
          page_size_log2: 16,
        }),
      },
    ],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "write", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [write_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let imports = @runtime.Imports::new()
  imports.add_memory("env", "mem", mem_addr)
  let instance = instantiate_module_with_imports(store, mod, imports)
  call_exported_func(store, instance, "write", []) |> ignore
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
  let func : @types.FunctionCode = { locals: [], body: [I32Const(1)] }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "env", name: "missing_func", desc: Func(0) }],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [],
    func_names: {},
  }

  // Empty imports - should fail
  let imports = @runtime.Imports::new()

  // Should raise UnknownImport
  inspect(
    try? instantiate_module_with_imports(store, mod, imports),
    content="Err(unknown import: env.missing_func)",
  )
}

///|
