///|
test "cooperative JIT preserves guest work and parked GC references" {
  let source =
    #|(module
    #| (type $value (struct (field i32)))
    #| (global $count (mut i32) (i32.const 0))
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  (local $value (ref null $value))
    #|  i32.const 42 struct.new $value local.set $value
    #|  (loop $again
    #|   global.get $count i32.const 1 i32.add global.set $count
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining
    #|   br_if $again)
    #|  global.get $count local.get $value struct.get $value 0 i32.add))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let mut outcome = context.call_core_func_resumable(store, instance, 0, [
    I32(10000),
  ])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    store.collect_garbage() |> ignore
    outcome = continuation.continue_execution()
  }
  assert_true(yields > 1)
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  debug_inspect(values, content="[I32(10042)]")
}

///|
test "cooperative JIT wait is notified by interpreter and cancellation dequeues" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports(store)
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  for cancel in [false, true] {
    let outcome = context.call_core_func_resumable(store, instance, 0, [])
    guard outcome is NativeCoreSuspended(AtomicWait, continuation) else {
      fail("expected native atomic wait suspension")
    }
    defer continuation.cancel()
    if cancel {
      continuation.cancel()
      continuation.cancel()
    }
    let notified = @executor.call_exported_func(store, instance, "notify", [])
    assert_eq(notified, [I32(if cancel { 0 } else { 1 })])
    if !cancel {
      guard continuation.continue_execution() is NativeCoreReturned(values) else {
        fail("notified native wait did not return")
      }
      debug_inspect(values, content="[I32(0)]")
    }
  }
}

///|
test "synchronous JIT wait is woken by a native notifier" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports(store)
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  let worker = @native_test_support.atomic_notify_start(memory.desc_ptr(), 0L)
  guard worker != 0L else { fail("native notifier allocation failed") }
  defer @native_test_support.atomic_notify_finish(worker) |> ignore
  debug_inspect(
    context.call_core_func(store, instance, 0, []),
    content="[I32(0)]",
  )
}

///|
test "controlled JIT cancellation releases an indefinitely blocked atomic wait" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports(store)
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(false))
  let polls = Ref(0)
  debug_inspect(
    context.jit_module.call_with_context_controlled(
      context.jit_module.get_func(0).unwrap(),
      [],
      cancel=Some(() => {
        polls.val += 1
        polls.val >= 3
      }),
    ),
    content="Cancelled",
  )
  inspect(memory.atomic_notify(0L, 0xffffffffU), content="0")
}

///|
test "native quantum config changes future invocations without changing a parked countdown" {
  let module_ = @wat.parse(
    (
      #|(module (func (export "run") (param $n i32) (result i32)
      #| (loop $l local.get $n i32.const 1 i32.sub local.tee $n br_if $l) i32.const 42))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(true, quantum=1))
  assert_false(context.jit_module.set_cooperative_scheduling(true, quantum=0))
  let mut outcome = context.call_core_func_resumable(store, instance, 0, [
    I32(25),
  ])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  guard outcome is NativeCoreSuspended(CooperativeYield, _) else {
    fail("small quantum did not yield")
  }
  assert_true(
    context.jit_module.set_cooperative_scheduling(true, quantum=100000),
  )
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    outcome = continuation.continue_execution()
  }
  assert_true(yields >= 25)
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  assert_eq(values, [I32(42)])
  guard context.call_core_func_resumable(store, instance, 0, [I32(25)])
    is NativeCoreReturned(values) else {
    fail("future invocation did not use the new quantum")
  }
  assert_eq(values, [I32(42)])
}

///|
test "typed native layouts preserve packed signed loads and subtype prefixes in both engines" {
  let result = @testsuite.compare_jit_interp(
    (
      #|(module
      #| (type $base (sub (struct (field (mut i8)))))
      #| (type $child (sub $base (struct (field (mut i8)) (field i64))))
      #| (type $a (array (mut i16)))
      #| (func (export "run") (result i32) (local $s (ref $child)) (local $a (ref $a))
      #|   (local.set $s (struct.new $child (i32.const -1) (i64.const 42)))
      #|   (local.set $a (array.new $a (i32.const -2) (i32.const 8)))
      #|   (struct.set $base 0 (local.get $s) (i32.const -3))
      #|   (i32.add (struct.get_s $base 0 (local.get $s))
      #|     (i32.add (array.get_s $a (local.get $a) (i32.const 7))
      #|       (i32.wrap_i64 (struct.get $child 1 (local.get $s)))))))
    ),
    "run",
    [],
  )
  assert_true(@testsuite.compare_result_is_match(result))
}

///|
test "instrumented loop translations preserve dominance" {
  let bodies = [
    "(local.set 0 (i32.add (local.get 0) (loop (result i32) (loop (result i32) (br 1)))))",
    "(local.set 0 (i32.add (local.get 0) (loop (result i32) (i32.ctz (br 0)))))",
    "(local.set 0 (i32.add (local.get 0) (loop (result i32) (i32.ctz (loop (result i32) (br 1))))))",
  ]
  for mask in 1..<8 {
    let selected : Array[String] = []
    for index, body in bodies {
      if (mask & (1 << index)) != 0 {
        selected.push(body)
      }
    }
    let source = "(module (func (export \"run\") (result i32) (local i32) \{selected.join(" ")} (local.get 0)))"
    let module_ = @wat.parse(source)
    let ir = @wasm_frontend.translate_function(
      @wasmoon.wasm_frontend_embedding_environment(cancellation_safepoints=true),
      module_,
      0,
    )
    @wasm_milkir.verify_function(ir)
    for level in [0, 2] {
      let compiled = @commands.compile_module_to_jit(
        module_,
        false,
        false,
        level,
        false,
        enable_cancellation=true,
        stack_switching=true,
      )
      assert_true(compiled is Some(_), msg="loop mask \{mask}, O\{level}")
    }
  }
}

///|
test "cached loop polls preserve quantum and cancellation callback counts" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (memory 1)
      #| (data (i32.const 0) "\01")
      #| (func (export "run") (param $n i32) (result i32)
      #|  (loop $l local.get $n i32.const 1 i32.sub local.tee $n br_if $l)
      #|  i32.const 42)
      #| (func (export "read") (param $n i32) (param $addr i32) (result i32)
      #|  (local $sum i32)
      #|  (loop $l
      #|   local.get $n i32.const 1 i32.const 64 call $check
      #|   local.get $sum local.get $addr call $read_byte
      #|   i32.add local.set $sum
      #|   local.get $n i32.const 1 i32.sub local.tee $n br_if $l)
      #|  local.get $sum)
      #| (func $read_byte (param i32) (result i32) local.get 0 i32.load8_u)
      #| (func $check (param $n i32) (param $lo i32) (param $hi i32)
      #|  local.get $n local.get $hi i32.le_s
      #|  if local.get $n local.get $lo i32.ge_s
      #|     if else unreachable end
      #|  else unreachable end))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
    opt_level=2,
  )
  defer context.close()
  // Entry plus one loop poll per iteration. The second function also
  // charges the inlined bounds guard and memory reader before their work.
  let cases : Array[(Int32, Array[@types.Value], Int32, Int32)] = [
    (0, [I32(64)], 65, 42),
    (1, [I32(64), I32(0)], 193, 64),
  ]
  for (function, args, total_polls, result) in cases {
    for quantum in [1, 2, 3, 7, 64, 65, 128] {
      assert_true(context.jit_module.set_cooperative_scheduling(true, quantum~))
      let mut outcome = context.call_core_func_resumable(
        store, instance, function, args,
      )
      defer (if outcome is NativeCoreSuspended(_, continuation) {
        continuation.cancel()
      })
      let mut yields = 0
      while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
        yields += 1
        assert_true(yields <= total_polls)
        outcome = continuation.continue_execution()
      }
      guard outcome is NativeCoreReturned(values) else {
        fail("unexpected suspension")
      }
      assert_eq(values, [I32(result)])
      assert_eq(
        yields,
        total_polls / quantum,
        msg="function \{function}, quantum \{quantum}",
      )
    }
  }
  assert_true(context.jit_module.set_cooperative_scheduling(true, quantum=2))
  guard context.call_core_func_resumable(store, instance, 1, [
      I32(64),
      I32(65536),
    ])
    is NativeCoreSuspended(CooperativeYield, continuation) else {
    fail("the entry and header polls should yield before the faulting load")
  }
  defer continuation.cancel()
  guard continuation.continue_execution()
    is NativeCoreSuspended(CooperativeYield, before_load) else {
    fail("the inlined guard and reader must charge before the faulting load")
  }
  defer before_load.cancel()
  try before_load.continue_execution() catch {
    @wast.JITCoreCallError::Trap(message) =>
      assert_true(message.contains("out of bounds memory access"))
    error => raise error
  } noraise {
    _ => fail("expected the out-of-bounds load to trap")
  }
  guard context.call_core_func_resumable(store, instance, 1, [
      I32(65),
      I32(65536),
    ])
    is NativeCoreSuspended(CooperativeYield, before_guard) else {
    fail("entry and header should yield before the guard")
  }
  defer before_guard.cancel()
  try before_guard.continue_execution() catch {
    @wast.JITCoreCallError::Trap(message) =>
      assert_true(message.contains("unreachable"))
    error => raise error
  } noraise {
    _ => fail("the inlined guard should trap before the faulting reader")
  }
  assert_true(context.jit_module.set_cooperative_scheduling(false))
  let polls = Ref(0)
  debug_inspect(
    context.jit_module.call_with_context_controlled(
      context.jit_module.get_func(0).unwrap(),
      [64L],
      cancel=Some(() => {
        polls.val += 1
        polls.val >= 63
      }),
    ),
    content="Cancelled",
  )
  assert_eq(polls.val, 63)
}
