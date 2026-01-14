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
test "table import: call_indirect with imported table" {
  // Create a store with a shared table
  let store = @runtime.Store::new()
  let shared_table = @runtime.Table::new(@types.ValueType::FuncRef, 2, None)
  let table_addr = store.alloc_table(shared_table)

  // Create two functions: add and sub
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let sub_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Sub],
  }

  // The type for add/sub functions
  let binary_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }

  // Allocate the functions in store with their type
  let add_addr = store.alloc_func(add_func, func_type=binary_type)
  let sub_addr = store.alloc_func(sub_func, func_type=binary_type)

  // Set function references in table
  shared_table.set(0, @types.Value::FuncRef(add_addr)) catch {
    _ => fail("Failed to set table")
  }
  shared_table.set(1, @types.Value::FuncRef(sub_addr)) catch {
    _ => fail("Failed to set table")
  }

  // Create a module that imports the table and uses call_indirect
  // apply(op, a, b) -> call_indirect(op, a, b)
  let apply_func : @types.FunctionCode = {
    locals: [],
    body: [
      LocalGet(1), // a
      LocalGet(2), // b
      LocalGet(0), // op (table index)
      CallIndirect(0, 0),
    ],
  } // type 0, table 0
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
    imports: [
      {
        mod_name: "env",
        name: "table",
        desc: Table({
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 2, max: None },
          is_table64: false,
        }),
      },
    ],
    funcs: [1], // apply has type 1
    tables: [], // No local tables, only imported
    memories: [],
    globals: [],
    exports: [{ name: "apply", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [apply_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let imports = @runtime.Imports::new()
  imports.add_table("env", "table", table_addr)
  let instance = instantiate_module_with_imports(store, mod, imports)

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
test "global variables: global.get and global.set" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [GlobalGet(0), I32Const(5), I32Add, GlobalSet(0), GlobalGet(0)],
      "test",
    ),
    globals: [
      {
        type_: { value_type: @types.ValueType::I32, mutable: true },
        init: [I32Const(10)],
      },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="15")
    _ => fail("Expected I32 result")
  }
}

///|
test "global variables: multiple globals" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [GlobalGet(0), GlobalGet(1), I32Add],
      "test",
    ),
    globals: [
      {
        type_: { value_type: @types.ValueType::I32, mutable: true },
        init: [I32Const(7)],
      },
      {
        type_: { value_type: @types.ValueType::I32, mutable: false },
        init: [I32Const(100)],
      },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="107")
    _ => fail("Expected I32 result")
  }
}

///|
test "global variables: i64 global" {
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I64], [GlobalGet(0)], "test"),
    globals: [
      {
        type_: { value_type: @types.ValueType::I64, mutable: false },
        init: [I64Const(9999999999L)],
      },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I64(n) => inspect(n, content="9999999999")
    _ => fail("Expected I64 result")
  }
}

///|
test "global import: imported global" {
  let store = @runtime.Store::new()
  let global_inst = @runtime.GlobalInstance::new(
    { value_type: @types.ValueType::I32, mutable: true },
    @types.Value::I32(42),
  )
  let global_addr = store.alloc_global(global_inst)
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I32], [GlobalGet(0)], "get"),
    imports: [
      {
        mod_name: "env",
        name: "g",
        desc: Global({ value_type: @types.ValueType::I32, mutable: true }),
      },
    ],
  }
  let imports = @runtime.Imports::new()
  imports.add_global("env", "g", global_addr)
  let instance = instantiate_module_with_imports(store, mod, imports)
  let results = call_exported_func(store, instance, "get", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "table operations: table.size" {
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I32], [TableSize(0)], "test"),
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 4, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="4")
    _ => fail("Expected I32 result")
  }
}

///|
test "table operations: table.grow" {
  // Test table.grow instruction with ref.null
  // Creates module with:
  // - table $t of 2 funcref
  // - grow function: (ref.null func) (i32.const 3) (table.grow $t)
  // - size function: (table.size $t)
  let table_type : @types.TableType = {
    elem_type: @types.ValueType::FuncRef,
    limits: { min: 2, max: None },
    is_table64: false,
  }
  let table : @types.Table = { type_: table_type, init: None }
  // Function type: () -> i32
  let func_type : @types.SubType = {
    final_: true,
    supertypes: [],
    composite: Func({ params: [], results: [@types.ValueType::I32] }),
  }
  let mod : @types.Module = {
    types: [func_type],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0], // two functions, both with type 0
    tables: [table],
    memories: [],
    globals: [],
    exports: [
      { name: "grow", desc: @types.ExportDesc::Func(0) },
      { name: "size", desc: @types.ExportDesc::Func(1) },
    ],
    start: None,
    elems: [],
    codes: [
      // grow function: ref.null func, i32.const 3, table.grow 0
      {
        locals: [],
        body: [RefNull(@types.ValueType::FuncRef), I32Const(3), TableGrow(0)],
      },
      // size function: table.size 0
      { locals: [], body: [TableSize(0)] },
    ],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)
  // Grow table by 3, should return old size (2)
  let grow_result = call_exported_func(store, instance, "grow", [])
  inspect(grow_result, content="[I32(2)]")
  // New size should be 5
  let size_result = call_exported_func(store, instance, "size", [])
  inspect(size_result, content="[I32(5)]")
}

///|
test "table operations: table.fill" {
  // Test table.fill via direct runtime manipulation
  let store = @runtime.Store::new()
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 5, None)
  store.alloc_table(table) |> ignore
  // Fill table[1..4] with FuncRef(42)
  table.fill(1, @types.Value::FuncRef(42), 3) catch {
    _ => fail("table.fill failed")
  }

  // Verify: table[0] should be Null, table[1..3] should be FuncRef(42), table[4] should be Null
  inspect(table.get(0), content="Null")
  inspect(table.get(1), content="FuncRef(42)")
  inspect(table.get(2), content="FuncRef(42)")
  inspect(table.get(3), content="FuncRef(42)")
  inspect(table.get(4), content="Null")
}

///|
test "table operations: table.copy same table" {
  // Test table.copy within the same table
  let store = @runtime.Store::new()
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 6, None)
  store.alloc_table(table) |> ignore
  // Set some initial values
  table.set(0, @types.Value::FuncRef(10)) catch {
    _ => ()
  }
  table.set(1, @types.Value::FuncRef(20)) catch {
    _ => ()
  }
  table.set(2, @types.Value::FuncRef(30)) catch {
    _ => ()
  }

  // Copy table[0..3] to table[3..6]
  table.copy_from(3, table, 0, 3) catch {
    _ => fail("table.copy failed")
  }
  inspect(table.get(0), content="FuncRef(10)")
  inspect(table.get(1), content="FuncRef(20)")
  inspect(table.get(2), content="FuncRef(30)")
  inspect(table.get(3), content="FuncRef(10)")
  inspect(table.get(4), content="FuncRef(20)")
  inspect(table.get(5), content="FuncRef(30)")
}

///|
test "table operations: table.copy between tables" {
  // Test table.copy between different tables
  let store = @runtime.Store::new()
  let table1 = @runtime.Table::new(@types.ValueType::FuncRef, 4, None)
  let table2 = @runtime.Table::new(@types.ValueType::FuncRef, 4, None)
  store.alloc_table(table1) |> ignore
  store.alloc_table(table2) |> ignore
  // Set values in table1
  table1.set(0, @types.Value::FuncRef(100)) catch {
    _ => ()
  }
  table1.set(1, @types.Value::FuncRef(200)) catch {
    _ => ()
  }

  // Copy table1[0..2] to table2[1..3]
  table2.copy_from(1, table1, 0, 2) catch {
    _ => fail("table.copy failed")
  }
  inspect(table2.get(0), content="Null")
  inspect(table2.get(1), content="FuncRef(100)")
  inspect(table2.get(2), content="FuncRef(200)")
  inspect(table2.get(3), content="Null")
}

///|
test "table operations: table.copy overlapping backward" {
  // Test table.copy with overlapping regions (dest > src)
  let store = @runtime.Store::new()
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 6, None)
  store.alloc_table(table) |> ignore
  // Set initial values: [1, 2, 3, 0, 0, 0]
  table.set(0, @types.Value::FuncRef(1)) catch {
    _ => ()
  }
  table.set(1, @types.Value::FuncRef(2)) catch {
    _ => ()
  }
  table.set(2, @types.Value::FuncRef(3)) catch {
    _ => ()
  }

  // Copy table[0..3] to table[2..5] (overlapping, dest > src)
  // Expected: [1, 2, 1, 2, 3, 0]
  table.copy_from(2, table, 0, 3) catch {
    _ => fail("table.copy failed")
  }
  inspect(table.get(0), content="FuncRef(1)")
  inspect(table.get(1), content="FuncRef(2)")
  inspect(table.get(2), content="FuncRef(1)")
  inspect(table.get(3), content="FuncRef(2)")
  inspect(table.get(4), content="FuncRef(3)")
  inspect(table.get(5), content="Null")
}

///|
test "module initialization: start function execution" {
  // Module with a start function that sets a global
  // func 0: init() - sets global to 42
  // start: 0
  let init_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(42), GlobalSet(0)],
  }
  let get_func : @types.FunctionCode = { locals: [], body: [GlobalGet(0)] }
  let init_type : @types.FuncType = { params: [], results: [] }
  let get_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let global : @types.Global = {
    type_: { value_type: @types.ValueType::I32, mutable: true },
    init: [I32Const(0)],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(init_type),
      @types.SubType::from_func(get_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1],
    tables: [],
    memories: [],
    globals: [global],
    exports: [{ name: "get", desc: @types.ExportDesc::Func(1) }],
    start: Some(0), // start function is func 0
    elems: [],
    codes: [init_func, get_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  // Start function should have set global to 42
  let results = call_exported_func(store, instance, "get", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "module initialization: data segment" {
  let data_bytes = Bytes::from_array([b'\x2A', b'\x00', b'\x00', b'\x00'])
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [I32Const(0), I32Load(0, 2, 0)],
      "read",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: data_bytes }],
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  let results = call_exported_func(store, instance, "read", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "module initialization: data segment with offset" {
  let data_bytes = Bytes::from_array([b'\x78', b'\x56', b'\x34', b'\x12'])
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [I32Const(100), I32Load(0, 2, 0)],
      "read",
    ),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    datas: [{ memory_idx: 0, offset: [I32Const(100)], init: data_bytes }],
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  let results = call_exported_func(store, instance, "read", [])
  match results[0] {
    I32(n) => inspect(n, content="305419896")
    _ => fail("Expected I32 result")
  }
}

///|
test "module initialization: element segment" {
  // This test verifies element segment initialization works
  // (already tested in call_indirect test, but let's be explicit)
  let func0 : @types.FunctionCode = { locals: [], body: [I32Const(100)] }
  let func1 : @types.FunctionCode = { locals: [], body: [I32Const(200)] }
  let call_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), CallIndirect(0, 0)],
  }
  let ret_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let call_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(ret_type),
      @types.SubType::from_func(call_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 0, 1], // func0, func1 have type 0; call_func has type 1
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
    exports: [{ name: "call", desc: @types.ExportDesc::Func(2) }],
    start: None,
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)], [RefFunc(1)]],
      },
    ],
    codes: [func0, func1, call_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  // call(0) should call func0, return 100
  let results1 = call_exported_func(store, instance, "call", [I32(0)])
  match results1[0] {
    I32(n) => inspect(n, content="100")
    _ => fail("Expected I32 result")
  }
  // call(1) should call func1, return 200
  let results2 = call_exported_func(store, instance, "call", [I32(1)])
  match results2[0] {
    I32(n) => inspect(n, content="200")
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: memory.fill" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(0x42),
        I32Const(4),
        MemoryFill(0),
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
    I32(n) => inspect(n, content="1111638594")
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: memory.copy non-overlapping" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(0x12345678),
        I32Store(0, 2, 0),
        I32Const(100),
        I32Const(0),
        I32Const(4),
        MemoryCopy(0, 0),
        I32Const(100),
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
    I32(n) => inspect(n, content="305419896")
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: memory.copy overlapping backward" {
  let mod = {
    ..@types.Module::simple(
      [],
      [@types.ValueType::I32],
      [
        I32Const(0),
        I32Const(0x04030201),
        I32Store(0, 2, 0),
        I32Const(2),
        I32Const(0),
        I32Const(4),
        MemoryCopy(0, 0),
        I32Const(2),
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
    I32(n) => inspect(n, content="67305985")
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: memory.init from data segment" {
  // Module with a data segment, use memory.init to copy part of it
  let body : Array[@types.Instruction] = [
    I32Const(100), // dest in memory
    I32Const(0), // src offset in data segment
    I32Const(4), // len
    MemoryInit(0, 0), // init from data segment 0
    I32Const(100),
    I32Load(0, 2, 0),
  ]
  // Data: 0xDEADBEEF in little-endian
  let data_bytes = Bytes::from_array([b'\xEF', b'\xBE', b'\xAD', b'\xDE'])
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I32], body, "test"),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: data_bytes }],
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="-559038737") // 0xDEADBEEF as signed i32
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: memory.init with offset" {
  // Use memory.init with non-zero source offset
  let body : Array[@types.Instruction] = [
    I32Const(0), // dest in memory
    I32Const(2), // src offset in data segment (skip first 2 bytes)
    I32Const(2), // len (copy last 2 bytes)
    MemoryInit(0, 0),
    I32Const(0),
    I32Load16U(0, 1, 0), // load 16-bit unsigned
  ]
  // Data: [0x11, 0x22, 0x33, 0x44]
  let data_bytes = Bytes::from_array([b'\x11', b'\x22', b'\x33', b'\x44'])
  let mod = {
    ..@types.Module::simple([], [@types.ValueType::I32], body, "test"),
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: data_bytes }],
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    // Reading [0x33, 0x44] as little-endian u16: 0x4433 = 17459
    I32(n) => inspect(n, content="17459")
    _ => fail("Expected I32 result")
  }
}

///|
test "bulk memory: data.drop" {
  // Test data.drop: after dropping, memory.init with non-zero length should trap
  // Function 0: drop data segment 0
  // Function 1: try memory.init with length 0 (should succeed even after drop)
  // Function 2: try memory.init with length > 0 (should fail after drop)
  let drop_func : @types.FunctionCode = { locals: [], body: [DataDrop(0)] } // drop data segment 0
  let init_zero_func : @types.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // dest
      I32Const(0), // src offset
      I32Const(0), // len = 0 (should work even after drop)
      MemoryInit(0, 0),
      I32Const(1),
    ],
  } // return 1 for success
  let init_nonzero_func : @types.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // dest
      I32Const(0), // src offset
      I32Const(1), // len = 1 (should fail after drop)
      MemoryInit(0, 0),
      I32Const(1),
    ],
  }
  let void_type : @types.FuncType = { params: [], results: [] }
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let data_bytes = Bytes::from_array([b'\x42'])
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(void_type),
      @types.SubType::from_func(i32_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1, 1], // drop has type 0, init funcs have type 1
    tables: [],
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    globals: [],
    exports: [
      { name: "drop", desc: @types.ExportDesc::Func(0) },
      { name: "init_zero", desc: @types.ExportDesc::Func(1) },
      { name: "init_nonzero", desc: @types.ExportDesc::Func(2) },
    ],
    start: None,
    elems: [],
    codes: [drop_func, init_zero_func, init_nonzero_func],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: data_bytes }],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }

  // Before drop: init_nonzero should work
  let result1 = call_exported_func(store, instance, "init_nonzero", [])
  match result1[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }

  // Drop the data segment
  call_exported_func(store, instance, "drop", []) |> ignore
  // After drop: init_zero should still work (length 0 is ok)
  let result2 = call_exported_func(store, instance, "init_zero", [])
  match result2[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }

  // After drop: init_nonzero should fail
  inspect(
    try? call_exported_func(store, instance, "init_nonzero", []),
    content="Err(out of bounds memory access)",
  )
}

///|
test "bulk memory: elem.drop" {
  // Test elem.drop: after dropping, the segment is marked as dropped
  // We verify by checking the instance state directly
  let drop_func : @types.FunctionCode = { locals: [], body: [ElemDrop(0)] } // drop elem segment 0
  let void_type : @types.FuncType = { params: [], results: [] }
  let dummy_func : @types.FunctionCode = { locals: [], body: [I32Const(0)] }
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(void_type),
      @types.SubType::from_func(i32_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1], // drop has type 0, dummy has type 1
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
    exports: [{ name: "drop", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(1)]],
      },
    ], // elem segment with func 1
    codes: [drop_func, dummy_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }

  // Before explicit drop: active elem segment is already implicitly dropped after initialization
  // (per WebAssembly spec, active elem segments are dropped after module instantiation)
  inspect(instance.dropped_elems[0], content="true")

  // Drop the elem segment
  call_exported_func(store, instance, "drop", []) |> ignore
  // After drop: elem segment should be marked as dropped
  inspect(instance.dropped_elems[0], content="true")
}

///|
test "bulk memory: data.drop is idempotent" {
  // Dropping a segment multiple times should be safe
  let drop_func : @types.FunctionCode = {
    locals: [],
    body: [DataDrop(0), DataDrop(0), DataDrop(0)], // drop 3 times
  }
  let void_type : @types.FuncType = { params: [], results: [] }
  let data_bytes = Bytes::from_array([b'\x42'])
  let mod : @types.Module = {
    types: [@types.SubType::from_func(void_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    globals: [],
    exports: [{ name: "drop", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [drop_func],
    datas: [{ memory_idx: 0, offset: [I32Const(0)], init: data_bytes }],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }

  // Calling drop multiple times should not cause error
  call_exported_func(store, instance, "drop", []) |> ignore
  inspect(instance.dropped_datas[0], content="true")
}

///|
test "reference types: ref.null funcref" {
  // Function: push null funcref and check if it's null
  let body : Array[@types.Instruction] = [
    RefNull(@types.ValueType::FuncRef),
    RefIsNull,
  ]
  let mod = @types.Module::simple([], [@types.ValueType::I32], body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="1") // null ref returns 1 for ref.is_null
    _ => fail("Expected I32 result")
  }
}

///|
test "reference types: ref.null externref" {
  // Function: push null externref and check if it's null
  let body : Array[@types.Instruction] = [
    RefNull(@types.ValueType::ExternRef),
    RefIsNull,
  ]
  let mod = @types.Module::simple([], [@types.ValueType::I32], body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="1") // null ref returns 1 for ref.is_null
    _ => fail("Expected I32 result")
  }
}

///|
test "reference types: ref.func" {
  // Function 0: returns 42
  // Function 1: get ref to func 0 and check it's not null
  let func0 : @types.FunctionCode = { locals: [], body: [I32Const(42)] }
  let func1 : @types.FunctionCode = {
    locals: [],
    body: [RefFunc(0), RefIsNull],
  }
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(i32_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0], // both have type 0
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [func0, func1],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="0") // non-null ref returns 0 for ref.is_null
    _ => fail("Expected I32 result")
  }
}

///|
test "reference types: ref.is_null with non-null value" {
  // Test ref.is_null with a FuncRef value (from table)
  // Function 0: dummy function
  // Function 1: get funcref from table and check if null
  let dummy_func : @types.FunctionCode = { locals: [], body: [I32Const(0)] }
  let check_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(0), TableGet(0), RefIsNull], // get table[0], check if null
  }
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(i32_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)]],
      },
    ], // table[0] = func 0
    codes: [dummy_func, check_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module_with_init(mod) catch {
    _ => fail("instantiate_module_with_init failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="0") // non-null ref returns 0
    _ => fail("Expected I32 result")
  }
}

///|
test "reference types: ref.func used with table.set" {
  // Create function reference and store it in table, then call via call_indirect
  // func 0: returns 100
  // func 1: use ref.func to get reference to func 0, store in table, call via indirect
  let target_func : @types.FunctionCode = { locals: [], body: [I32Const(100)] }
  let test_func : @types.FunctionCode = {
    locals: [],
    body: [
      I32Const(0), // table index
      RefFunc(0), // get reference to func 0
      TableSet(0), // table[0] = ref to func 0
      I32Const(0), // table index for call_indirect
      CallIndirect(0, 0),
    ],
  } // call table[0] with type 0
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(i32_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0],
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [target_func, test_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="100") // should call func 0 and get 100
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: function returning two values" {
  // Function returns (i32, i32) pair
  let results_types = [@types.ValueType::I32, @types.ValueType::I32]
  let body : Array[@types.Instruction] = [I32Const(10), I32Const(20)]
  let mod = @types.Module::simple([], results_types, body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  inspect(results.length(), content="2")
  match results[0] {
    I32(n) => inspect(n, content="10")
    _ => fail("Expected I32 result")
  }
  match results[1] {
    I32(n) => inspect(n, content="20")
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: function returning three values" {
  // Function returns (i32, i64, f32)
  let results_types = [
    @types.ValueType::I32,
    @types.ValueType::I64,
    @types.ValueType::F32,
  ]
  let body : Array[@types.Instruction] = [
    I32Const(1),
    I64Const(2L),
    F32Const(3.0),
  ]
  let mod = @types.Module::simple([], results_types, body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  inspect(results.length(), content="3")
  match results[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }
  match results[1] {
    I64(n) => inspect(n, content="2")
    _ => fail("Expected I64 result")
  }
  match results[2] {
    F32(f) => inspect(f, content="3")
    _ => fail("Expected F32 result")
  }
}

///|
test "multi-value: function returning no values" {
  // Function returns nothing (void)
  let mod = @types.Module::simple([], [], [Nop], "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  inspect(results.length(), content="0")
}

///|
test "multi-value: call function with multi-value return" {
  // func 0: swap(a, b) -> (b, a) - returns two values
  // func 1: test() -> call swap(10, 20), then add them
  let swap_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(1), LocalGet(0)], // return (b, a)
  }
  let test_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(10), I32Const(20), Call(0), I32Add], // swap(10, 20) returns (20, 10), then add
  }
  let swap_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  let test_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(swap_type),
      @types.SubType::from_func(test_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [0, 1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [swap_func, test_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="30") // 20 + 10 = 30
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: block returning two values" {
  // Block that returns two values
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      Block(
        @types.BlockType::TypeIndex(0),
        [I32Const(100), I32Const(200)], // block returns two values
      ),
      I32Add,
    ],
  } // add them
  let block_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(block_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="300") // 100 + 200 = 300
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: if returning two values" {
  // If-else that returns two values based on condition
  let func : @types.FunctionCode = {
    locals: [],
    body: [
      LocalGet(0), // condition
      If(
        @types.BlockType::TypeIndex(0),
        [I32Const(10), I32Const(20)], // then: (10, 20)
        [I32Const(30), I32Const(40)], // else: (30, 40)
      ),
      I32Add,
    ],
  } // add results
  let block_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32, @types.ValueType::I32],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(block_type),
      @types.SubType::from_func(func_type),
    ],
    type_rec_groups: [0, 1],
    imports: [],
    funcs: [1],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let (store, instance) = instantiate_module(mod)

  // Test with true condition
  let results1 = call_exported_func(store, instance, "test", [I32(1)])
  match results1[0] {
    I32(n) => inspect(n, content="30") // 10 + 20 = 30
    _ => fail("Expected I32 result")
  }

  // Test with false condition
  let results2 = call_exported_func(store, instance, "test", [I32(0)])
  match results2[0] {
    I32(n) => inspect(n, content="70") // 30 + 40 = 70
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: block with single Value type" {
  // Block with Value(I32) returns single value (existing behavior)
  let body : Array[@types.Instruction] = [
    Block(@types.BlockType::Value(@types.ValueType::I32), [I32Const(42)]),
  ]
  let mod = @types.Module::simple([], [@types.ValueType::I32], body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "multi-value: empty block" {
  // Block with Empty type returns nothing
  let body : Array[@types.Instruction] = [
    Block(@types.BlockType::Empty, [Nop]),
    I32Const(99),
  ]
  let mod = @types.Module::simple([], [@types.ValueType::I32], body, "test")
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="99")
    _ => fail("Expected I32 result")
  }
}

///|
test "module linking: basic import from another module" {
  // Module A exports a function that returns 42
  // Module B imports that function and calls it
  let linker = @runtime.Linker::new()

  // Module A: exports "get_value" -> returns 42
  let func_a : @types.FunctionCode = { locals: [], body: [I32Const(42)] }
  let func_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod_a : @types.Module = {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "get_value", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [func_a],
    datas: [],
    tags: [],
    func_names: {},
  }

  // Instantiate module A
  (instantiate_with_linker(linker, "mod_a", mod_a) catch {
    _ => fail("Failed to instantiate mod_a")
  })
  |> ignore
  // Module B: imports "mod_a"."get_value", calls it
  let func_b : @types.FunctionCode = { locals: [], body: [Call(0)] } // Call imported function
  let mod_b : @types.Module = {
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [
      { mod_name: "mod_a", name: "get_value", desc: @types.ImportDesc::Func(0) },
    ],
    funcs: [0], // type index for the defined function
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }], // func 0 is import, func 1 is defined
    start: None,
    elems: [],
    codes: [func_b],
    datas: [],
    tags: [],
    func_names: {},
  }
  let instance_b = instantiate_with_linker(linker, "mod_b", mod_b) catch {
    _ => fail("Failed to instantiate mod_b")
  }
  let results = call_exported_func(linker.get_store(), instance_b, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "module linking: import memory from another module" {
  // Module A exports a memory
  // Module B imports that memory and uses it
  let linker = @runtime.Linker::new()

  // Module A: exports memory, has a function to store value
  let store_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(0), I32Const(12345), I32Store(0, 0, 0)],
  } // mem[0] = 12345
  let void_type : @types.FuncType = { params: [], results: [] }
  let mod_a : @types.Module = {
    types: [@types.SubType::from_func(void_type)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [
      { limits: { min: 1, max: None }, is_memory64: false, page_size_log2: 16 },
    ],
    globals: [],
    exports: [
      { name: "mem", desc: @types.ExportDesc::Memory(0) },
      { name: "store", desc: @types.ExportDesc::Func(0) },
    ],
    start: None,
    elems: [],
    codes: [store_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let instance_a = instantiate_with_linker(linker, "mod_a", mod_a) catch {
    _ => fail("Failed to instantiate mod_a")
  }

  // Call store function to write to memory
  call_exported_func(linker.get_store(), instance_a, "store", []) |> ignore
  // Module B: imports memory from mod_a, reads from it
  let read_func : @types.FunctionCode = {
    locals: [],
    body: [I32Const(0), I32Load(0, 0, 0)],
  } // return mem[0]
  let i32_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let mod_b : @types.Module = {
    types: [@types.SubType::from_func(i32_type)],
    type_rec_groups: [0],
    imports: [
      {
        mod_name: "mod_a",
        name: "mem",
        desc: @types.ImportDesc::Memory({
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
    exports: [{ name: "read", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [read_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let instance_b = instantiate_with_linker(linker, "mod_b", mod_b) catch {
    _ => fail("Failed to instantiate mod_b")
  }
  let results = call_exported_func(linker.get_store(), instance_b, "read", [])
  match results[0] {
    I32(n) => inspect(n, content="12345")
    _ => fail("Expected I32 result")
  }
}

///|
test "module linking: three modules chain" {
  // Module A exports add(x, y) -> x + y
  // Module B imports add from A, exports double(x) -> add(x, x)
  // Module C imports double from B, exports quad(x) -> double(double(x))
  let linker = @runtime.Linker::new()

  // Module A
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(1), I32Add],
  }
  let add_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod_a : @types.Module = {
    types: [@types.SubType::from_func(add_type)],
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
  (instantiate_with_linker(linker, "math", mod_a) catch {
    _ => fail("Failed to instantiate math")
  })
  |> ignore
  // Module B: double(x) = add(x, x)
  let double_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), LocalGet(0), Call(0)],
  } // Call imported add
  let unary_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod_b : @types.Module = {
    types: [
      @types.SubType::from_func(add_type),
      @types.SubType::from_func(unary_type),
    ],
    type_rec_groups: [0, 1],
    imports: [
      { mod_name: "math", name: "add", desc: @types.ImportDesc::Func(0) },
    ],
    funcs: [1], // double uses unary_type
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "double", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [double_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  (instantiate_with_linker(linker, "utils", mod_b) catch {
    _ => fail("Failed to instantiate utils")
  })
  |> ignore

  // Module C: quad(x) = double(double(x))
  let quad_func : @types.FunctionCode = {
    locals: [],
    body: [LocalGet(0), Call(0), Call(0)],
  } // double(double(x))
  let mod_c : @types.Module = {
    types: [@types.SubType::from_func(unary_type)],
    type_rec_groups: [0],
    imports: [
      { mod_name: "utils", name: "double", desc: @types.ImportDesc::Func(0) },
    ],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "quad", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [],
    codes: [quad_func],
    datas: [],
    tags: [],
    func_names: {},
  }
  let instance_c = instantiate_with_linker(linker, "app", mod_c) catch {
    _ => fail("Failed to instantiate app")
  }

  // quad(5) = double(double(5)) = double(10) = 20
  let results = call_exported_func(linker.get_store(), instance_c, "quad", [
    @types.Value::I32(5),
  ])
  match results[0] {
    I32(n) => inspect(n, content="20")
    _ => fail("Expected I32 result")
  }
}

///|
test "call_indirect with imports path" {
  // This simulates the path used by run.mbt with instantiate_module_with_imports
  let type_ : @types.FuncType = { params: [], results: [@types.ValueType::I32] }
  let func_code : @types.FunctionCode = { locals: [], body: [I32Const(42)] }
  let test_code : @types.FunctionCode = {
    locals: [],
    body: [I32Const(0), CallIndirect(0, 0)],
  }
  let mod : @types.Module = {
    types: [@types.SubType::from_func(type_)],
    type_rec_groups: [0],
    imports: [],
    funcs: [0, 0], // Both functions have type 0
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(1) }],
    start: None,
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(0)]],
      },
    ],
    codes: [func_code, test_code],
    datas: [],
    tags: [],
    func_names: {},
  }

  // Use instantiate_module_with_imports (same path as run.mbt)
  let store = @runtime.Store::new()
  let imports = @runtime.Imports::new()
  let instance = instantiate_module_with_imports(store, mod, imports) catch {
    _ => fail("instantiate failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="42")
    _ => fail("Expected I32 result")
  }
}

///|
test "call_indirect with multiple funcs and explicit type" {
  // This simulates the issue where $check type index was wrong
  let type_empty : @types.FuncType = { params: [], results: [] }
  let type_result_i32 : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let type_binary : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  // Types: 0 = () -> (), 1 = () -> i32, 2 = (i32, i32) -> i32, 3 = (i32, i32) -> i32
  let dummy_func : @types.FunctionCode = { locals: [], body: [] }
  let test1_func : @types.FunctionCode = { locals: [], body: [I32Const(1)] }
  let func_code : @types.FunctionCode = { locals: [], body: [LocalGet(0)] }
  let test_code : @types.FunctionCode = {
    locals: [],
    // call_indirect with type 3 (which is type_binary)
    body: [I32Const(1), I32Const(2), I32Const(0), CallIndirect(3, 0)],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(type_empty),
      @types.SubType::from_func(type_result_i32),
      @types.SubType::from_func(type_binary),
      @types.SubType::from_func(type_binary),
    ],
    type_rec_groups: [0, 1, 2, 3],
    imports: [],
    funcs: [0, 1, 2, 1], // dummy=0, test1=1, func=2, test=1
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(3) }],
    start: None,
    // elem init contains func index 2 ($func)
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(2)]],
      },
    ],
    codes: [dummy_func, test1_func, func_code, test_code],
    datas: [],
    tags: [],
    func_names: {},
  }
  let store = @runtime.Store::new()
  let imports = @runtime.Imports::new()
  let instance = instantiate_module_with_imports(store, mod, imports) catch {
    _ => fail("instantiate failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }
}

///|
test "call_indirect type index bug reproduction" {
  // Exact module structure from the failing test:
  // funcs: [0, 1, 3]  (type indices)
  // types: [() -> (), (i32,i32)->i32, (i32,i32)->i32, ()->i32]
  // elem init: [1] (func index 1, which is $func)
  // call_indirect type_idx: 2 ($check)

  let type0 : @types.FuncType = { params: [], results: [] }
  let type1 : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let type2 : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let type3 : @types.FuncType = { params: [], results: [@types.ValueType::I32] }
  let dummy_func : @types.FunctionCode = { locals: [], body: [] }
  let func_code : @types.FunctionCode = { locals: [], body: [LocalGet(0)] }
  let test_code : @types.FunctionCode = {
    locals: [],
    // call_indirect (type $check) where $check is type index 2
    body: [I32Const(1), I32Const(2), I32Const(0), CallIndirect(2, 0)],
  }
  let mod : @types.Module = {
    types: [
      @types.SubType::from_func(type0),
      @types.SubType::from_func(type1),
      @types.SubType::from_func(type2),
      @types.SubType::from_func(type3),
    ],
    type_rec_groups: [0, 1, 2, 3],
    imports: [],
    funcs: [0, 1, 3], // dummy=type0, $func=type1, test=type3
    tables: [
      {
        type_: {
          elem_type: @types.ValueType::FuncRef,
          limits: { min: 1, max: None },
          is_table64: false,
        },
        init: None,
      },
    ],
    memories: [],
    globals: [],
    exports: [{ name: "test", desc: @types.ExportDesc::Func(2) }],
    start: None,
    // elem init: func index 1 ($func)
    elems: [
      {
        mode: @types.ElemMode::Active(0, [I32Const(0)]),
        type_: @types.ValueType::FuncRef,
        init: [[RefFunc(1)]],
      },
    ],
    codes: [dummy_func, func_code, test_code],
    datas: [],
    tags: [],
    func_names: {},
  }
  let store = @runtime.Store::new()
  let imports = @runtime.Imports::new()
  let instance = instantiate_module_with_imports(store, mod, imports) catch {
    _ => fail("instantiate failed")
  }
  let results = call_exported_func(store, instance, "test", [])
  match results[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }
}

// ============================================================
// Conversion instruction tests for boundary cases
// ============================================================

///|
test "i32.trunc_f64_u: value in (-1, 0) truncates to 0" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF64U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [F64(-0.9)])
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "i32.trunc_f32_u: value in (-1, 0) truncates to 0" {
  let mod = @types.Module::simple(
    [@types.ValueType::F32],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF32U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [F32(-0.5)])
  match results[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}

///|
test "i64.trunc_f64_u: large value near 2^64" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncF64U],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_63 = @math.pow(2.0, 63.0)
  let results = call_exported_func(store, instance, "trunc", [F64(pow2_63)])
  match results[0] {
    I64(n) => inspect(n, content="-9223372036854775808")
    _ => fail("Expected I64 result")
  }
}

///|
test "i64.trunc_sat_f64_u: large value saturates correctly" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncSatF64U],
    "trunc_sat",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_64 = @math.pow(2.0, 64.0)
  let results = call_exported_func(store, instance, "trunc_sat", [F64(pow2_64)])
  match results[0] {
    I64(n) => inspect(n, content="-1")
    _ => fail("Expected I64 result")
  }
}

///|
test "i64.trunc_sat_f64_u: value in range converts correctly" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I64],
    [LocalGet(0), I64TruncSatF64U],
    "trunc_sat",
  )
  let (store, instance) = instantiate_module(mod)
  let pow2_63 = @math.pow(2.0, 63.0)
  let results = call_exported_func(store, instance, "trunc_sat", [F64(pow2_63)])
  match results[0] {
    I64(n) => inspect(n, content="-9223372036854775808")
    _ => fail("Expected I64 result")
  }
}

///|
test "i32.trunc_f64_s: boundary near INT32_MIN" {
  let mod = @types.Module::simple(
    [@types.ValueType::F64],
    [@types.ValueType::I32],
    [LocalGet(0), I32TruncF64S],
    "trunc",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "trunc", [
    F64(-2147483648.0),
  ])
  match results[0] {
    I32(n) => inspect(n, content="-2147483648")
    _ => fail("Expected I32 result")
  }
}
