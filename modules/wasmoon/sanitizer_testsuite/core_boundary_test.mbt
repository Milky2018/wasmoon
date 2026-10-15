///|
test "Core boundary: instance rejects a different Store" {
  let (a, instance) = @executor.instantiate_module_with_init(
    @wat.parse("(module (func (export \"f\") (result i32) i32.const 11))"),
  )
  defer a.close()
  let (b, _) = @executor.instantiate_module_with_init(
    @wat.parse("(module (func (export \"f\") (result i32) i32.const 22))"),
  )
  defer b.close()
  let result = try {
    @executor.call_exported_func(b, instance, "f", []) |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(result, content="instance belongs to another store")
}

///|
test "Core boundary: instantiation owns its function code" {
  let module_ = @wat.parse(
    "(module (func (export \"f\") (result i32) i32.const 11))",
  )
  let (store, instance) = @executor.instantiate_module_with_init(module_)
  defer store.close()
  module_.codes[0] = { locals: [], body: [I32Const(22)], }
  debug_inspect(
    @executor.call_exported_func(store, instance, "f", []),
    content="[I32(11)]",
  )
}

///|
test "Core boundary: malformed models are rejected before Store mutation" {
  let store = @runtime.Store::Store()
  defer store.close()
  let original = @wat.parse("(module (func (export \"f\")))")
  let invalid_type = original.snapshot()
  invalid_type.funcs[0] = 99
  let missing_code = original.snapshot()
  missing_code.codes.clear()
  let negative_start = original.snapshot()
  negative_start.start = Some(-1)
  let negative_export = original.snapshot()
  negative_export.exports[0] = { name: "f", desc: Func(-1), }
  let negative_local = original.snapshot()
  negative_local.codes[0] = { locals: [], body: [LocalGet(-1)], }
  for
    module_ in [
      invalid_type, missing_code, negative_start, negative_export, negative_local,
    ] {
    let rejected = try {
      @executor.instantiate_module_with_imports(store, module_, Imports(store))
      |> ignore
      false
    } catch {
      InvalidModule(_) => true
      _ => false
    }
    assert_true(rejected)
    inspect(store.counts().funcs, content="0")
    inspect(store.counts().instances, content="0")
  }
}

///|
test "Core boundary: Imports retain their Store identity" {
  let a = @runtime.Store::Store()
  defer a.close()
  let b = @runtime.Store::Store()
  defer b.close()
  let module_ = @wat.parse("(module)")
  let rejected = try {
    @executor.instantiate_module_with_imports(b, module_, Imports(a)) |> ignore
    false
  } catch {
    ForeignStore => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "Core boundary: invalid function indices and argument shapes are typed errors" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      "(module (func (export \"f\") (param i32) (result i32) local.get 0))",
    ),
  )
  defer store.close()
  for index in [-1, 1, 2147483647] {
    let rejected = try {
      @executor.call_func_by_index(store, instance, index, [I32(1)]) |> ignore
      false
    } catch {
      UndefinedElement => true
      _ => false
    }
    assert_true(rejected)
  }
  let cases : Array[Array[@types.Value]] = [[], [F32(1.0)], [I32(1), I32(2)]]
  for args in cases {
    let rejected = try {
      @executor.call_exported_func(store, instance, "f", args) |> ignore
      false
    } catch {
      TypeMismatch => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "Core boundary: rollback cannot retarget retained instances or function handles" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  let store = linker.get_store()
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  let module_ = @wat.parse(
    "(module (func (export \"f\") (result i32) i32.const 11))",
  )
  let old = @executor.instantiate_with_linker(linker, "old", module_)
  let function = @executor.Function::from_export(store, old, "f")
  defer function.close()
  let reference = function.as_value()
  defer reference.close()
  transaction.rollback()
  let fresh = @executor.instantiate_with_linker(linker, "fresh", module_)
  inspect(fresh.store_index(), content="0")
  let rejected = try {
    function.call([]) |> ignore
    false
  } catch {
    InvalidHandle => true
    _ => false
  }
  assert_true(rejected)
  let reference_rejected = try {
    store.borrow_rooted_value(reference) |> ignore
    false
  } catch {
    InvalidHandle => true
    _ => false
  }
  assert_true(reference_rejected)
  debug_inspect(
    @executor.call_exported_func(store, fresh, "f", []),
    content="[I32(11)]",
  )
}

///|
test "Core boundary: rooted references cannot cross Stores with identical addresses" {
  let module_ = @wat.parse(
    "(module (func (export \"f\") (param funcref) (result i32) local.get 0 ref.is_null))",
  )
  let (a, ai) = @executor.instantiate_module(module_)
  defer a.close()
  let (b, bi) = @executor.instantiate_module(module_)
  defer b.close()
  let af = @executor.Function::from_export(a, ai, "f")
  defer af.close()
  let bf = @executor.Function::from_export(b, bi, "f")
  defer bf.close()
  let reference = af.as_value()
  defer reference.close()
  let rejected = try {
    bf.call([reference]) |> ignore
    false
  } catch {
    ForeignStore => true
    _ => false
  }
  assert_true(rejected)
  let values = af.call([reference])
  defer (for value in values {
    value.close()
  })
  debug_inspect(values[0].scalar(), content="I32(0)")
  af.close()
  let closed = try {
    af.call([]) |> ignore
    false
  } catch {
    InvalidHandle => true
    _ => false
  }
  assert_true(closed)
}

///|
test "Core boundary: rooted guest results survive collection until released" {
  let wat =
    #|(module
    #|  (type $T (struct (field i32)))
    #|  (func (export "make") (result (ref $T)) i32.const 42 struct.new $T)
    #|  (func (export "read") (param (ref $T)) (result i32) local.get 0 struct.get $T 0))
  let (store, instance) = @executor.instantiate_module(@wat.parse(wat))
  defer store.close()
  let make = @executor.Function::from_export(store, instance, "make")
  defer make.close()
  let read = @executor.Function::from_export(store, instance, "read")
  defer read.close()
  let values = make.call([])
  inspect(store.collect_garbage(), content="0")
  let result = read.call(values)
  defer (for value in result {
    value.close()
  })
  debug_inspect(result[0].scalar(), content="I32(42)")
  values[0].close()
  inspect(store.collect_garbage(), content="1")
  let rejected = try {
    read.call(values) |> ignore
    false
  } catch {
    InvalidHandle => true
    _ => false
  }
  assert_true(rejected)
  store.close()
  let closed = try {
    make.call([]) |> ignore
    false
  } catch {
    StoreClosed => true
    _ => false
  }
  assert_true(closed)
}

///|
test "Core boundary: host return shape cannot corrupt the guest operand stack" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_host_func("host", "bad", fn(_) { [F32(1.0)] }, func_type={
    params: [],
    results: [I32],
  })
  let source = "(module (import \"host\" \"bad\" (func $bad (result i32))) (func (export \"f\") (result i32) call $bad))"
  let instance = @executor.instantiate_with_linker(
    linker,
    "guest",
    @wat.parse(source),
  )
  let rejected = try {
    @executor.call_exported_func(linker.get_store(), instance, "f", [])
    |> ignore
    false
  } catch {
    TypeMismatch => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "Core boundary: exception reads and GC initialization do not expose backing arrays" {
  let store = @runtime.Store::Store()
  defer store.close()
  let types = [
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: true, }], }),
    ),
  ]
  store.set_module_types(types)
  let fields : Array[@types.Value] = [I32(11)]
  let reference = store.alloc_struct(0, fields)
  fields[0] = I32(22)
  debug_inspect(store.struct_get(reference, 0), content="I32(11)")
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let exception = store.alloc_exn(tag, [I32(11)])
  store.get_exn(exception).values[0] = F32(0.0)
  debug_inspect(store.get_exn(exception).values, content="[I32(11)]")
}

///|
test "Core boundary: Memory Table and Global cannot acquire a second Store owner" {
  let a = @runtime.Store::Store()
  defer a.close()
  let b = @runtime.Store::Store()
  defer b.close()
  let memory = @runtime.Memory::Memory(1, Some(2))
  let table = @runtime.Table::Table(FuncRef, 1, Some(2))
  let global = @runtime.GlobalInstance(
    { value_type: I32, mutable: true, },
    I32(1),
  )
  let memory_address = a.alloc_mem(memory)
  let table_address = a.alloc_table(table)
  let global_address = a.alloc_global(global)
  inspect(a.alloc_mem(memory) == memory_address, content="true")
  inspect(a.alloc_table(table) == table_address, content="true")
  inspect(a.alloc_global(global) == global_address, content="true")
  for
    operation in [
      () => b.alloc_mem(memory),
      () => b.alloc_table(table),
      () => b.alloc_global(global),
    ] {
    let rejected = try {
      operation() |> ignore
      false
    } catch {
      ForeignStore => true
      _ => false
    }
    assert_true(rejected)
  }
  inspect(b.counts().mems, content="0")
  inspect(b.counts().tables, content="0")
  inspect(b.counts().globals, content="0")
  a.close()
  let closed_table = try {
    table.get(0) |> ignore
    false
  } catch {
    StoreClosed => true
    _ => false
  }
  let closed_global = try {
    global.get() |> ignore
    false
  } catch {
    StoreClosed => true
    _ => false
  }
  assert_true(closed_table)
  assert_true(closed_global)
}

///|
test "Core boundary: rolled back resource handles cannot be rebound" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  let store = linker.get_store()
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  let memory = @runtime.Memory::Memory(0, None)
  let table = @runtime.Table::Table(FuncRef, 1, None)
  let global = @runtime.GlobalInstance(
    { value_type: I32, mutable: true, },
    I32(1),
  )
  store.alloc_mem(memory) |> ignore
  store.alloc_table(table) |> ignore
  store.alloc_global(global) |> ignore
  transaction.rollback()
  for
    operation in [
      () => store.alloc_mem(memory),
      () => store.alloc_table(table),
      () => store.alloc_global(global),
    ] {
    let rejected = try {
      operation() |> ignore
      false
    } catch {
      InvalidHandle => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "Core boundary: explicit shared Memory imports preserve independent close" {
  let a = @runtime.Store::Store()
  defer a.close()
  let b = @runtime.Store::Store()
  defer b.close()
  let memory = @runtime.Memory::Memory(1, Some(2), is_shared=true)
  a.alloc_mem(memory) |> ignore
  let imported = b.get_mem(b.alloc_shared_mem(memory))
  memory.store_i32(0, 11)
  a.close()
  inspect(imported.load_i32(0), content="11")
  imported.store_i32(0, 22)
  inspect(imported.load_i32(0), content="22")
}

///|
fn drop_new_rooted_result(
  make : @executor.Function,
) -> Unit raise @runtime.RuntimeError {
  make.call([]) |> ignore
}

///|
test "Core boundary: RC releases dropped reference results in a long-lived Store" {
  for native_heap in [false, true] {
    let module_ = @wat.parse(
      "(module (type $T (struct (field i32))) (func (export \"make\") (result (ref $T)) i32.const 42 struct.new $T))",
    )
    let store = if native_heap {
      @runtime.Store::with_c_heap()
    } else {
      Store()
    }
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let make = @executor.Function::from_export(store, instance, "make")
    defer make.close()
    for _ in 0..<64 {
      drop_new_rooted_result(make)
      inspect(store.collect_garbage(), content="1")
    }
    let values = make.call([])
    inspect(store.collect_garbage(), content="0")
    values[0].close()
    values[0].close()
    inspect(store.collect_garbage(), content="1")
  }
}

///|
test "Core boundary: native contexts freeze metadata and reject foreign or stale owners" {
  let module_ = @wat.parse(
    "(module (func (export \"f\") (result i32) i32.const 11))",
  )
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  let store = linker.get_store()
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  let instance = @executor.instantiate_with_linker(linker, "old", module_)
  let original = build_gc_root_context(module_, instance, store)
  defer original.close()
  let addresses = instance.func_addrs[:].to_owned()
  let context = @wast.JITModuleContext(
    original.jit_module,
    original.globals_ptr,
    [],
    [],
    addresses,
    instance.func_type_indices,
    instance.canonical_type_indices,
    module_.types,
    module_.type_rec_groups,
    true,
  )
  addresses[0] = -1
  debug_inspect(
    context.call_core_func(store, instance, 0, []),
    content="[I32(11)]",
  )
  let (other, other_instance) = @executor.instantiate_module(module_)
  defer other.close()
  let foreign = try {
    context.call_core_func(other, other_instance, 0, []) |> ignore
    false
  } catch {
    HostInvocation(ForeignStore) => true
    _ => false
  }
  assert_true(foreign)
  let second = @executor.instantiate_with_linker(linker, "second", module_)
  let rebound = try {
    context.call_core_func(store, second, 0, []) |> ignore
    false
  } catch {
    HostInvocation(InvalidHandle) => true
    _ => false
  }
  assert_true(rebound)
  transaction.rollback()
  let fresh = @executor.instantiate_with_linker(linker, "fresh", module_)
  inspect(fresh.store_index(), content="0")
  let stale = try {
    context.call_core_func(store, fresh, 0, []) |> ignore
    false
  } catch {
    HostInvocation(InvalidHandle) => true
    _ => false
  }
  assert_true(stale)
}

///|
async test "Core boundary: async cancellation releases borrowed reference roots" {
  for native_heap in [false, true] {
    let linker = @runtime.Linker::Linker()
    defer linker.close()
    let store = linker.get_store()
    if native_heap {
      store.enable_c_heap()
    }
    let started = @async.Semaphore(1, initial_value=0)
    let parked = @async.Semaphore(1, initial_value=0)
    linker.add_async_host_func(
      "host",
      "wait",
      async fn(_) {
        started.release()
        parked.acquire()
        []
      },
      func_type={ params: [], results: [], },
    )
    let module_ = @wat.parse(
      (
        #|(module
        #|  (import "host" "wait" (func $wait))
        #|  (type $T (struct (field i32)))
        #|  (func (export "make") (result (ref $T)) i32.const 42 struct.new $T)
        #|  (func (export "wait") (param (ref $T)) call $wait))
      ),
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    let make = @executor.Function::from_export(store, instance, "make")
    defer make.close()
    let wait = @executor.Function::from_export(store, instance, "wait")
    defer wait.close()
    let values = make.call([])
    @async.with_task_group(group => {
      let task = group.spawn(no_wait=true, allow_failure=true, () => {
        wait.call_async(values)
      })
      started.acquire()
      values[0].close()
      inspect(store.collect_garbage(), content="0")
      task.cancel()
      try task.wait() |> ignore catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
    })
    inspect(store.collect_garbage(), content="1")
  }
}

///|
async test "Core boundary: host initialization cannot replace the validated start function" {
  for asynchronous in [false, true] {
    let module_ = @wat.parse(
      "(module (import \"host\" \"g\" (global i32)) (global i32 (global.get 0)) (func $start) (func $bad unreachable) (start $start))",
    )
    let store = @runtime.Store::Store()
    defer store.close()
    let global = @runtime.GlobalInstance(
      { value_type: I32, mutable: false, },
      I32(0),
    )
    global.bind_native({
      address: 0L,
      root: fn() { I32(0) },
      read: fn() {
        module_.start = Some(1)
        I32(0)
      },
      write: fn(_) raise @runtime.RuntimeError { raise TypeMismatch },
      release: fn() { () },
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_global("host", "g", store.alloc_global(global))
    if asynchronous {
      @executor.instantiate_module_with_imports_async(store, module_, imports)
      |> ignore
    } else {
      @executor.instantiate_module_with_imports(store, module_, imports)
      |> ignore
    }
    debug_inspect(module_.start, content="Some(1)")
  }
}

///|
test "Core boundary: rollback cannot retarget a host namespace function handle" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  let signature : @types.FuncType = { params: [], results: [I32], }
  linker.add_host_func(
    "host",
    "first",
    fn(_) { [I32(11)] },
    func_type=signature,
  )
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  linker.add_host_func(
    "host",
    "temporary",
    fn(_) { [I32(22)] },
    func_type=signature,
  )
  let instance = linker.get_module("host").unwrap()
  let old = @executor.Function::from_export(
    linker.get_store(),
    instance,
    "temporary",
  )
  defer old.close()
  transaction.rollback()
  linker.add_host_func(
    "host",
    "replacement",
    fn(_) { [I32(33)] },
    func_type=signature,
  )
  for
    operation in [
      fn() raise @runtime.RuntimeError { old.call([]) |> ignore },
      fn() raise @runtime.RuntimeError { old.as_value() |> ignore },
    ] {
    let rejected = try {
      operation()
      false
    } catch {
      InvalidHandle => true
      _ => false
    }
    assert_true(rejected)
  }
}
