///|
test "numeric array access regions preserve aliases packed values and cold traps" {
  for
    (storage, value, get, equal) in [
      ("i8", "i32.const 511", "array.get_u", "i32.const 255 i32.eq"),
      ("i16", "i32.const 65535", "array.get_s", "i32.const -1 i32.eq"),
      ("i32", "i32.const -42", "array.get", "i32.const -42 i32.eq"),
      (
        "i64", "i64.const -4294967297", "array.get", "i64.const -4294967297 i64.eq",
      ),
      ("f32", "f32.const -42.25", "array.get", "f32.const -42.25 f32.eq"),
      ("f64", "f64.const -42.25", "array.get", "f64.const -42.25 f64.eq"),
    ] {
    let module_ = @wat.parse(
      (
        $|(module (type $a (array (mut \{storage})))
        $|(func (export "test") (result i32) (local $a (ref $a)) (local $b (ref $a))
        $| i32.const 4 array.new_default $a local.tee $a local.set $b
        $| local.get $a i32.const 1 \{value} array.set $a
        $| local.get $b i32.const 1 \{get} $a \{equal}
        $| local.get $a i32.const 2 \{value} array.set $a
        $| local.get $b i32.const 2 \{get} $a \{equal} i32.and)
        $|(func (export "bounds") (local $a (ref $a))
        $| i32.const 1 array.new_default $a local.set $a
        $| local.get $a i32.const 0 \{get} $a drop
        $| local.get $a i32.const -1 \{value} array.set $a)
        $|(func (export "null") (param $a (ref null $a))
        $| local.get $a i32.const 0 \{get} $a drop
        $| local.get $a i32.const 0 \{value} array.set $a)
        $|(func (export "loop") (result i32) (local $a (ref $a)) (local $i i32) (local $ok i32)
        $| i32.const 4 array.new_default $a local.set $a
        $| local.get $a array.len drop i32.const 1 local.set $ok
        $| (loop $again
        $|  local.get $a local.get $i \{value} array.set $a
        $|  local.get $a local.get $i \{get} $a \{equal} local.get $ok i32.and local.set $ok
        $|  local.get $i i32.const 1 i32.add local.tee $i i32.const 4 i32.lt_u br_if $again)
        $| local.get $ok)
        $|(func (export "zero") (param $a (ref null $a)) (param $n i32) (result i32)
        $| (block $done (loop $again
        $|  local.get $n i32.eqz br_if $done
        $|  local.get $a i32.const 0 \{get} $a drop
        $|  local.get $a i32.const 0 \{value} array.set $a
        $|  local.get $n i32.const 1 i32.sub local.set $n br $again)) i32.const 42)
        $|(func (export "wide") (param $a (ref $a)) (result i32)
        $| local.get $a i32.const 0 \{get} $a drop
        $| local.get $a i32.const 0 \{value} array.set $a
        $| local.get $a i32.const 0 \{get} $a \{equal}))
      ),
    )
    @validator.validate_module(module_)
    for
      (opt_level, enable_cancellation) in [
        (0, false),
        (2, false),
        (3, false),
        (2, true),
      ] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      let context = build_gc_root_context(
        module_,
        instance,
        store,
        opt_level~,
        enable_cancellation~,
      )
      defer context.close()
      assert_eq(context.call_core_func(store, instance, 0, []), [I32(1)])
      assert_eq(context.call_core_func(store, instance, 3, []), [I32(1)])
      // Low-level host allocations can legitimately have wide physical slots.
      let wide = store
        .native_heap()
        .unwrap()
        .alloc_array_from_values(0, [I64(0L)])
      assert_eq(context.call_core_func(store, instance, 5, [ArrayRef(wide)]), [
        I32(1),
      ])
      assert_eq(context.call_core_func(store, instance, 4, [Null, I32(0)]), [
        I32(42),
      ])
      for
        (index, arguments, message) in [
          (1, [], "out of bounds array access"),
          (2, [@types.Value::Null], "null reference"),
        ] {
        try context.call_core_func(store, instance, index, arguments) catch {
          Trap(actual) => assert_eq(actual, message)
          error => fail(error.to_string())
        } noraise {
          _ => fail("array region suppressed its trap")
        }
      }
    }
  }
}

///|
test "array regions end at host reentry and relocating collection" {
  let module_ = @wat.parse(
    (
      #|(module (type $a (array (mut i32)))
      #| (import "h" "collect" (func $collect (param (ref $a))))
      #| (func (export "test") (result i32) (local $a (ref $a))
      #|  i32.const 0 i32.const 1024 array.new $a drop
      #|  i32.const 7 i32.const 4 array.new $a local.set $a
      #|  local.get $a i32.const 0 array.get $a drop
      #|  local.get $a i32.const 1 array.get $a drop
      #|  local.get $a call $collect
      #|  local.get $a i32.const 0 array.get $a
      #|  local.get $a i32.const 1 array.get $a i32.add))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let calls = Ref(0)
    let host = store.alloc_host_func(
      fn(args) raise @runtime.RuntimeError {
        guard args is [ArrayRef(array)] else { raise TypeMismatch }
        calls.val += 1
        store.collect_garbage(additional_roots=[ArrayRef(array)]) |> ignore
        store.array_set(array, 0, I32(35))
        []
      },
      func_type={ params: [RefArray(0)], results: [], },
    )
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", host)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    for _ in 0..<3 {
      assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
      store.collect_garbage() |> ignore
    }
    assert_eq(calls.val, 3)
  }
}

///|
test "native entry validates nullability object kind and concrete array subtyping" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (sub (array (mut i32))))
      #| (type $b (sub $a (array (mut i32))))
      #| (type $s (struct (field i32)))
      #| (func (export "typed") (param (ref $a)) (result i32) local.get 0 array.len)
      #| (func (export "abstract") (param (ref array)) (result i32) local.get 0 array.len))
    ),
  )
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let array = store.alloc_array(1, [I32(7), I32(42)], instance~)
  let struct_ = store.alloc_struct(2, [I32(42)], instance~)
  let context = build_gc_root_context(module_, instance, store, opt_level=2)
  defer context.close()
  for index in [0, 1] {
    assert_eq(
      context.call_core_func(store, instance, index, [ArrayRef(array)]),
      [I32(2)],
    )
    for
      invalid in [
        @types.Value::Null,
        StructRef(struct_),
        ArrayRef(struct_),
        ArrayRef(999999),
      ] {
      try context.call_core_func(store, instance, index, [invalid]) catch {
        HostInvocation(TypeMismatch) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("invalid raw reference entered native code")
      }
      try
        context.call_core_func_resumable(store, instance, index, [invalid])
      catch {
        HostInvocation(TypeMismatch) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("invalid raw reference entered a native fiber")
      }
    }
  }
}
