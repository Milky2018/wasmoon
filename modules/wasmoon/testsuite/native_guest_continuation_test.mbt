///|
test "native guest continuation binds retain GC arguments after suspension" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $f (func (result i32))) (type $c (cont $f))
    #|  (type $f1 (func (param (ref $s)) (result i32))) (type $k (cont $f1))
    #|  (tag $yield (result (ref $s)))
    #|  (global $saved (mut (ref null $c)) (ref.null $c))
    #|  (func $body (result i32) suspend $yield struct.get $s 0)
    #|  (elem declare func $body)
    #|  (func (export "start") (param (ref $s)) (local $k (ref $k))
    #|    (block $suspended (result (ref $k))
    #|      (resume $c (on $yield $suspended) (cont.new $c (ref.func $body)))
    #|      unreachable)
    #|    local.set $k
    #|    (global.set $saved (cont.bind $k $c (local.get 0) (local.get $k))))
    #|  (func (export "finish") (result i32) (resume $c (global.get $saved))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_, stack_switching=true)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  let reference = store.alloc_struct(0, [I32(42)], instance~)
  context.call_core_func(store, instance, 1, [StructRef(reference)]) |> ignore
  inspect(store.collect_garbage(), content="0")
  debug_inspect(
    context.call_core_func(store, instance, 2, []),
    content="[I32(42)]",
  )
  inspect(store.collect_garbage(), content="1")
}

///|
test "native guest continuation cancellation releases occupied child stacks" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $f (func (param (ref $s)))) (type $c (cont $f))
    #|  (func $body (type $f)
    #|    (loop $again (drop (struct.get $s 0 (local.get 0))) br $again))
    #|  (elem declare func $body)
    #|  (func (export "run") (param (ref $s))
    #|    (resume $c (local.get 0) (cont.new $c (ref.func $body)))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_, stack_switching=true)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    @runtime.Imports(),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let reference = store.alloc_struct(0, [I32(42)], instance~)
  guard context.call_core_func_resumable(store, instance, 1, [
      StructRef(reference),
    ])
    is NativeCoreSuspended(CooperativeYield, continuation) else {
    fail("expected guest cooperative suspension")
  }
  defer continuation.cancel()
  inspect(store.collect_garbage(), content="0")
  continuation.cancel()
  continuation.cancel()
  inspect(store.native_execution_state().live_count(), content="0")
  inspect(store.collect_garbage(), content="1")
}

///|
test "native guest continuation inherits the resumer scheduling context" {
  let owner_module = @wat.parse(
    (
      #|(module
      #|  (type $f (func (result i32))) (type $c (cont $f))
      #|  (func $body (result i32) (local $count i32)
      #|    i32.const 10000 local.set $count
      #|    (loop $again local.get $count i32.const 1 i32.sub local.tee $count br_if $again)
      #|    i32.const 42)
      #|  (elem declare func $body)
      #|  (func (export "make") (result (ref $c)) (cont.new $c (ref.func $body))))
    ),
  )
  let caller_module = @wat.parse(
    (
      #|(module
      #|  (type $f (func (result i32))) (type $c (cont $f))
      #|  (import "owner" "make" (func $make (result (ref $c))))
      #|  (func (export "run") (result i32) (resume $c (call $make))))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let owner = @executor.instantiate_with_linker(linker, "owner", owner_module)
  let owner_code = prepare_async_jit_context(
    owner_module,
    owner,
    store,
    cooperative=true,
  )
  defer owner_code.close()
  assert_true(owner_code.jit_module.set_cooperative_scheduling(false))
  let caller = @executor.instantiate_with_linker(
    linker, "caller", caller_module,
  )
  let caller_code = prepare_async_jit_context(
    caller_module,
    caller,
    store,
    cooperative=true,
  )
  defer caller_code.close()
  let mut outcome = caller_code.call_core_func_resumable(store, caller, 1, [])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    outcome = continuation.continue_execution()
  }
  assert_true(yields > 1)
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  debug_inspect(values, content="[I32(42)]")
}

///|
test "native guest continuation restores an environment across another module" {
  let owner_module = @wat.parse(
    (
      #|(module
      #|  (type $f (func (result i32))) (type $c (cont $f))
      #|  (func (export "call") (param (ref $f)) (result i32)
      #|    (resume $c (cont.new $c (local.get 0)))))
    ),
  )
  let caller_module = @wat.parse(
    (
      #|(module
      #|  (type $f (func (result i32))) (type $c (cont $f))
      #|  (import "owner" "call" (func $call (param (ref $f)) (result i32)))
      #|  (func $value (result i32) i32.const 42)
      #|  (func $inner (result i32) (resume $c (cont.new $c (ref.func $value))))
      #|  (func (export "run") (result i32) (call $call (ref.func $inner)))
      #|  (elem declare func $value $inner))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let owner = @executor.instantiate_with_linker(linker, "owner", owner_module)
  let owner_code = prepare_async_jit_context(owner_module, owner, store)
  defer owner_code.close()
  let caller = @executor.instantiate_with_linker(
    linker, "caller", caller_module,
  )
  let caller_code = prepare_async_jit_context(caller_module, caller, store)
  defer caller_code.close()
  debug_inspect(
    caller_code.call_core_func(store, caller, 3, []),
    content="[I32(42)]",
  )
}
