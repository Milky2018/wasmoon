///|
fn instantiate_gc_types(
  store : @runtime.Store,
  source : String,
) -> @runtime.ModuleInstance raise {
  @executor.instantiate_module_with_imports(
    store,
    @wat.parse(source),
    Imports(store),
  )
}

///|
fn first_gc_global(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Int32 raise {
  match store.get_global(instance.global_addrs[0]).get() {
    StructRef(reference) | ArrayRef(reference) => reference
    _ => fail("expected a GC global")
  }
}

///|
test "GC global initialization preserves repeated struct and array allocations" {
  let source = StringBuilder()
  source.write_string(
    "(module (type $s (struct (field i32))) (type $a (array (mut (ref null $s))))",
  )
  for index in 0..<50 {
    source.write_string(
      "(global $s\{index} (ref $s) (struct.new $s (i32.const \{index})))",
    )
    source.write_string(
      "(global $a\{index} (ref $a) (array.new $a (global.get $s\{index}) (i32.const 1)))",
    )
  }
  source.write_string(
    "(func (export \"run\") (result i32) global.get $a49 i32.const 0 array.get $a ref.as_non_null struct.get $s 0))",
  )
  let store = @runtime.Store()
  defer store.close()
  let instance = instantiate_gc_types(store, source.to_string())
  assert_eq(store.counts().heap_live, 100)
  store.collect_garbage() |> ignore
  assert_eq(store.counts().heap_live, 100)
  assert_eq(@executor.call_exported_func(store, instance, "run", []), [I32(49)])
}

///|
test "GC graphs preserve recursive equivalence across shifted module indices" {
  let store = @runtime.Store()
  defer store.close()
  let original = instantiate_gc_types(
    store,
    (
      #|(module
      #| (rec (type $s (struct (field (ref null $a))))
      #|      (type $a (array (mut (ref null $s)))))
      #| (global (ref $s) (struct.new $s (ref.null $a))))
    ),
  )
  let shifted = instantiate_gc_types(
    store,
    (
      #|(module
      #| (type $padding (func (param i64)))
      #| (rec (type $s (struct (field (ref null $a))))
      #|      (type $a (array (mut (ref null $s)))))
      #| (global (ref $s) (struct.new $s (ref.null $a))))
    ),
  )
  let a = store.native_type_indices(original)
  let b = store.native_type_indices(shifted)
  assert_eq(a[0], b[1])
  assert_eq(a[1], b[2])
  assert_true(
    store.gc_type_is_subtype(first_gc_global(store, original), shifted, 1),
  )
  assert_true(
    store.gc_type_is_subtype(first_gc_global(store, shifted), original, 0),
  )
  // Public mapping snapshots cannot mutate the registered graph.
  b[1] = -1
  assert_eq(store.native_type_indices(shifted)[1], a[0])
  let different = instantiate_gc_types(
    store,
    (
      #|(module
      #| (rec (type $s (struct (field (ref null $a))))
      #|      (type $a (array (mut i64))))
      #| (global (ref $s) (struct.new $s (ref.null $a))))
    ),
  )
  let c = store.native_type_indices(different)
  assert_false(a[0] == c[0])
  assert_false(a[1] == c[1])
  assert_false(
    store.gc_type_is_subtype(first_gc_global(store, original), different, 0),
  )
}

///|
test "GC graph cache distinguishes recursive group boundaries and Stores" {
  let grouped_source =
    #|(module
    #| (rec (type $s (struct (field i32))) (type $a (array (mut i32))))
    #| (global (ref $s) (struct.new $s (i32.const 1))))
  let split_source =
    #|(module
    #| (type $s (struct (field i32))) (type $a (array (mut i32)))
    #| (global (ref $s) (struct.new $s (i32.const 2))))
  let store = @runtime.Store()
  defer store.close()
  let grouped = instantiate_gc_types(store, grouped_source)
  let split = instantiate_gc_types(store, split_source)
  let a = store.native_type_indices(grouped)
  let b = store.native_type_indices(split)
  assert_false(a[0] == b[0])
  assert_false(a[1] == b[1])
  assert_false(
    store.gc_type_is_subtype(first_gc_global(store, grouped), split, 0),
  )
  let other_store = @runtime.Store()
  defer other_store.close()
  let foreign = instantiate_gc_types(other_store, grouped_source)
  assert_true(store.native_type_indices(foreign).is_empty())
  assert_false(
    store.gc_type_is_subtype(first_gc_global(store, grouped), foreign, 0),
  )
}

///|
test "failed GC instantiation restores the current graph and permits reuse" {
  let budget = @runtime.ResourceBudget::new(gc_objects=3L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let source =
    #|(module (type $s (struct (field i32)))
    #| (global (ref $s) (struct.new $s (i32.const 42))))
  let baseline = instantiate_gc_types(store, source)
  let before = store.counts()
  try
    instantiate_gc_types(
      store,
      (
        #|(module (type $s (struct (field i64)))
        #| (func)
        #| (global (ref $s) (struct.new $s (i64.const 9)))
        #| (global (ref $s) (struct.new $s (i64.const 10)))
        #| (global (ref $s) (struct.new $s (i64.const 11))))
      ),
    )
  catch {
    @runtime.RuntimeError::ResourceLimitExceeded(GcObjects) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("GC global initialization did not exhaust its object budget")
  }
  let after = store.counts()
  assert_eq(after.funcs, before.funcs)
  assert_eq(after.instances, before.instances)
  assert_eq(after.globals, before.globals)
  assert_eq(after.heap_live, before.heap_live)
  assert_eq(budget.used(GcObjects), 1L)
  assert_true(store.current_types()[:] == baseline.types[:])
  let allocated = store.alloc_struct(0, [I32(55)])
  assert_true(store.gc_type_is_subtype(allocated, baseline, 0))
  let next = instantiate_gc_types(store, source)
  assert_eq(
    store.native_type_indices(next)[0],
    store.native_type_indices(baseline)[0],
  )
  assert_true(
    store.gc_type_is_subtype(first_gc_global(store, next), baseline, 0),
  )
}

///|
test "nested host instantiation cannot replace outer GC type identities" {
  let store = @runtime.Store()
  defer store.close()
  let inner = @wat.parse(
    "(module (type $s (struct (field i64))) (global (ref $s) (struct.new $s (i64.const 9))))",
  )
  let nested : Ref[@runtime.ModuleInstance?] = Ref(None)
  let host = store.alloc_host_func(_ => {
    nested.val = Some(
      @executor.instantiate_module_with_imports(store, inner, Imports(store)),
    )
    []
  })
  let imports = @runtime.Imports(store)
  imports.add_func("host", "nest", host)
  let outer = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      (
        #|(module (type $s (struct (field i32)))
        #| (import "host" "nest" (func $nest))
        #| (global (ref $s) (struct.new $s (i32.const 42)))
        #| (func $start call $nest) (start $start)
        #| (func (export "make") (result (ref $s)) i32.const 77 struct.new $s))
      ),
    ),
    imports,
  )
  let inner = nested.val.unwrap()
  let values = @executor.call_exported_func(store, outer, "make", [])
  guard values is [StructRef(reference)] else { fail("expected a struct") }
  assert_true(store.gc_type_is_subtype(reference, outer, 0))
  assert_false(store.gc_type_is_subtype(reference, inner, 0))
  assert_false(
    store.gc_type_is_subtype(first_gc_global(store, inner), outer, 0),
  )
}

///|
#cfg(target="native")
test "C heap global type registration shares equivalent module identities" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let source =
    #|(module (type $s (struct (field i32)))
    #| (global (ref $s) (struct.new $s (i32.const 42)))
    #| (func (export "run") (result i32) global.get 0 struct.get $s 0))
  let first = instantiate_gc_types(store, source)
  let second = instantiate_gc_types(store, source)
  let reference = first_gc_global(store, first)
  assert_true(store.gc_type_is_subtype(reference, second, 0))
  assert_eq(store.native_type_indices(first), store.native_type_indices(second))
  store.collect_garbage() |> ignore
  assert_eq(@executor.call_exported_func(store, second, "run", []), [I32(42)])
}

///|
test "closing a Store during type graph rollback remains terminal" {
  let store = @runtime.Store()
  store.set_module_types([
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: false, }], }),
    ),
  ])
  store.alloc_struct(0, [I32(1)]) |> ignore
  try
    store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
      store.set_module_types([
        @types.SubType::simple(
          Array({ element: { storage_type: Val(I64), mutable: true, }, }),
        ),
      ])
      store.alloc_array(0, [I64(2)]) |> ignore
      store.close()
      raise Unreachable
    })
  catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("transaction did not fail")
  }
  assert_true(store.is_closed())
  assert_true(store.current_types().is_empty())
  assert_eq(store.counts().heap_live, 0)
  store.close()
}
