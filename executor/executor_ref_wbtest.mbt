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
