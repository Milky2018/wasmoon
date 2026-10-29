///|
test "precise function frames survive collection and hidden-result direct and indirect tails" {
  let results = "(result (ref $s) i64 i64 i64 i64 i64 i64 i64 i64 i64)"
  let values = Array::makei(9, index => "i64.const \{index + 1}").join(" ")
  let drops = Array::make(9, "drop").join(" ")
  let source =
    $|(module (type $s (struct (field i32)))
    $| (type $f (func (param (ref $s)) \{results}))
    $| (import "h" "collect" (func $collect))
    $| (table 1 funcref) (elem (i32.const 0) $body)
    $| (func $body (type $f) call $collect local.get 0 \{values})
    $| (func $direct (type $f) local.get 0 return_call $body)
    $| (func $indirect (type $f) local.get 0 i32.const 0 return_call_indirect (type $f))
    $| (func (export "direct") (result i32)
    $|  i32.const 42 struct.new $s call $direct \{drops} struct.get $s 0)
    $| (func (export "indirect") (result i32)
    $|  i32.const 42 struct.new $s call $indirect \{drops} struct.get $s 0))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let collections = Ref(0)
    let collect = store.alloc_host_func(fn(_) {
      collections.val += 1
      store.collect_garbage() |> ignore
      []
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", collect)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    for index in [4, 5] {
      assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
      assert_eq(store.collect_garbage(), 1)
    }
    assert_eq(collections.val, 2)
  }
}

///|
test "frame areas preserve independent maxima across calls results objects and tails" {
  let args17 = Array::makei(17, index => "i64.const \{index + 1}").join(" ")
  let args25 = Array::makei(25, index => "i64.const \{index + 1}").join(" ")
  let params17 = "i64 ".repeat(17)
  let params25 = "i64 ".repeat(25)
  let adds = "i64.add ".repeat(16)
  let source =
    $|(module (type $keep (array (mut i64)))
    $| (import "h" "collect" (func $collect))
    $| (func $arguments (param \{params17}) (result i64)
    $|  call $collect local.get 0 local.get 16 i64.add)
    $| (func $results (result \{params17}) call $collect \{args17})
    $| (func $tail (param \{params25}) (result i64)
    $|  call $collect local.get 0 local.get 24 i64.add)
    $| (func $caller (param $tail_path i32) (result i64)
    $|  (local $root (ref null $keep)) (local $sum i64)
    $|  i64.const 7 i32.const 1 array.new $keep local.set $root
    $|  local.get $tail_path (if (then \{args25} return_call $tail))
    $|  \{args17} call $arguments local.set $sum
    $|  call $results \{adds} local.get $sum i64.add
    $|  local.get $root i32.const 0 array.get $keep i64.add)
    $| (func (export "probe") (result i32)
    $|  i32.const 0 call $caller i64.const 178 i64.eq
    $|  i32.const 1 call $caller i64.const 26 i64.eq i32.and))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2] {
    for native in [false, true] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let collections = Ref(0)
      let collect = store.alloc_host_func(fn(_) {
        collections.val += 1
        store.collect_garbage() |> ignore
        []
      })
      let imports = @runtime.Imports::Imports(store)
      imports.add_func("h", "collect", collect)
      let instance = @executor.instantiate_module_with_imports(
        store, module_, imports,
      )
      let result = if native {
        let context = build_gc_root_context(
          module_,
          instance,
          store,
          opt_level~,
        )
        defer context.close()
        context.install_hostcall_dispatcher(store, instance)
        context.call_core_func(store, instance, 5, [])
      } else {
        @executor.call_exported_func(store, instance, "probe", [])
      }
      assert_eq(result, [I32(1)], msg="native=\{native}, level=\{opt_level}")
      assert_eq(collections.val, 3)
    }
  }
}

///|
test "dense initializer roots survive every nested collecting call through their frame" {
  let count = 96
  let members = Array::makei(count, index => "i32.const \{index} call $make").join(
    "\n",
  )
  let source =
    $|(module
    $| (type $node (struct (field i32)))
    $| (type $refs (array (ref $node)))
    $| (import "h" "collect" (func $collect))
    $| (func $make (param i32) (result (ref $node))
    $|  (local $object (ref null $node))
    $|  local.get 0 struct.new $node local.set $object
    $|  call $collect local.get $object ref.as_non_null)
    $| (func (export "probe") (result i32)
    $|  (local $all (ref null $refs)) (local $i i32) (local $sum i32)
    $|  \{members} array.new_fixed $refs \{count} local.set $all
    $|  call $collect
    $|  loop $check
    $|   local.get $sum local.get $all local.get $i array.get $refs
    $|   struct.get $node 0 i32.add local.set $sum
    $|   local.get $i i32.const 1 i32.add local.tee $i
    $|   i32.const \{count} i32.lt_u br_if $check
    $|  end
    $|  local.get $sum i32.const \{count * (count - 1) / 2} i32.eq))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let collections = Ref(0)
    let collect = store.alloc_host_func(fn(_) {
      collections.val += 1
      store.collect_garbage() |> ignore
      []
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", collect)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    assert_eq(context.call_core_func(store, instance, 2, []), [I32(1)])
    assert_eq(collections.val, count + 1)
    assert_eq(store.collect_garbage(), count + 1)
    assert_true(store.native_heap().unwrap().verify())
  }
}
