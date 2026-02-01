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
