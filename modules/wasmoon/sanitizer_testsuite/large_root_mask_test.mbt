///|
test "large sparse function masks clear dead roots across sibling paths" {
  let count = 320
  let prefix =
    #|(module
    #| (type $s (struct (field i32)))
    #| (import "host" "gc" (func $gc (result i32)))
    #| (func $observe (param $object (ref $s)) (result i32)
    #|   call $gc drop local.get $object struct.get $s 0)
    #| (func (export "probe") (param $side i32)
  let parts = [prefix]
  for index in 0..<count {
    parts.push("(param $r\{index} (ref null $s))")
  }
  parts.push(
    "(result i32) (local $left (ref $s)) (local $right (ref $s)) (local $sum i32)\n" +
    "(local.set $left (struct.new $s (i32.const 42)))\n" +
    "(local.set $right (struct.new $s (i32.const 43)))\n" +
    "call $gc drop",
  )
  // Keep all parameter roots live through the first collection, then leave
  // only the branch-selected, guest-allocated object live at the second one.
  for index in 0..<count {
    parts.push(
      "(local.set $sum (i32.add (local.get $sum) (ref.is_null (local.get $r\{index}))))",
    )
  }
  parts.push(
    "(i32.add (local.get $sum) (if (result i32) (local.get $side) " +
    "(then (call $observe (local.get $left))) " +
    "(else (call $observe (local.get $right)))))))",
  )
  let module_ = @wat.parse(parts.join("\n"))
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let reclaimed = Ref(0)
    linker.add_host_func(
      "host",
      "gc",
      fn(_) {
        reclaimed.val += store.collect_garbage()
        [I32(0)]
      },
      func_type={ params: [], results: [I32], },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    for side in [1, 0] {
      reclaimed.val = 0
      let arguments : Array[@types.Value] = [I32(side)]
      for _ in 0..<count {
        arguments.push(Null)
      }
      assert_eq(context.call_core_func(store, instance, 2, arguments), [
        I32(count + (if side == 0 { 43 } else { 42 })),
      ])
      reclaimed.val += store.collect_garbage()
      assert_eq(reclaimed.val, 2)
      assert_true(store.native_heap().unwrap().verify())
    }
  }
}

///|
test "large dense function masks preserve every live object during collection" {
  let count = 320
  let prefix =
    #|(module
    #| (type $s (struct (field i32)))
    #| (type $refs (array (ref null $s)))
    #| (import "host" "gc" (func $gc (result i32)))
    #| (func $pack
  let parts = [prefix]
  for index in 0..<count {
    parts.push("(param $r\{index} (ref null $s))")
  }
  parts.push("(result (ref $refs)) call $gc drop")
  for index in 0..<count {
    parts.push("local.get $r\{index}")
  }
  parts.push(
    "array.new_fixed $refs \{count}) (func (export \"probe\") (result (ref $refs))",
  )
  // Put a distinct live object in every full bitmap word. A tail call retires
  // the creator's root frame, so only $pack's dense mask can retain them.
  for index in 0..<5 {
    parts.push("(local $o\{index} (ref $s))")
  }
  for index in 0..<5 {
    parts.push("(local.set $o\{index} (struct.new $s (i32.const \{index})))")
  }
  parts.push("(return_call $pack")
  for index in 0..<count {
    parts.push(
      if index % 64 == 0 {
        "local.get $o\{index / 64}"
      } else {
        "ref.null $s"
      },
    )
  }
  parts.push(")))")
  let module_ = @wat.parse(parts.join("\n"))
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let reclaimed = Ref(0)
    linker.add_host_func(
      "host",
      "gc",
      fn(_) {
        reclaimed.val += store.collect_garbage()
        [I32(0)]
      },
      func_type={ params: [], results: [I32], },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    guard context.call_core_func(store, instance, 2, []) is [ArrayRef(array)] else {
      fail("missing array of live roots")
    }
    let roots = store.pin_gc_roots([ArrayRef(array)])
    defer roots.release()
    assert_eq(reclaimed.val, 0)
    assert_eq(store.collect_garbage(), 0)
    for index in 0..<count {
      if index % 64 == 0 {
        guard store.array_get(array, index) is StructRef(object) else {
          fail("missing live root \{index}")
        }
        assert_eq(store.struct_get(object, 0), I32(index / 64))
      } else {
        assert_eq(store.array_get(array, index), Null)
      }
    }
    roots.release()
    assert_eq(store.collect_garbage(), 6)
    assert_true(store.native_heap().unwrap().verify())
  }
}

///|
test "repeated mixed mask words retain alternating live payloads exactly" {
  let count = 320
  let locals = Array::makei(count, i => "(local $r\{i} (ref null $node))").join(
    " ",
  )
  let load = Array::makei(count, i => {
    "i32.const \{i} table.get $roots local.set $r\{i}\n" +
    "i32.const \{i} ref.null $node table.set $roots"
  }).join("\n")
  let consume = fn(parity : Int32) -> String {
    Array::makei(count / 2, index => {
      let i = index * 2 + parity
      "local.get $sum local.get $r\{i} struct.get $node 0 i32.add local.set $sum\n" +
      "ref.null $node local.set $r\{i}"
    }).join("\n")
  }
  let source =
    $|(module (type $node (struct (field i32)))
    $| (import "h" "collect" (func $collect))
    $| (table $roots \{count} (ref null $node))
    $| (func $seed (local $i i32)
    $|  loop $again local.get $i local.get $i struct.new $node table.set $roots
    $|   local.get $i i32.const 1 i32.add local.tee $i
    $|   i32.const \{count} i32.lt_u br_if $again end)
    $| (func (export "probe") (result i32) \{locals} (local $sum i32)
    $|  \{load} call $collect
    $|  \{consume(1)} call $collect
    $|  \{consume(0)} local.get $sum i32.const \{count * (count - 1) / 2} i32.eq))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let reclaimed : Array[Int32] = []
    let collect = store.alloc_host_func(fn(_) {
      reclaimed.push(store.collect_garbage())
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
    assert_eq(context.call_core_func(store, instance, 1, []), [])
    assert_eq(context.call_core_func(store, instance, 2, []), [I32(1)])
    assert_eq(reclaimed, [0, count / 2])
    assert_eq(store.collect_garbage(), count / 2)
    assert_true(store.native_heap().unwrap().verify())
  }
}
