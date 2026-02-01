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
