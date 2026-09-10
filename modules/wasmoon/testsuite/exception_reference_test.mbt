///|
test "native exception references preserve GC payloads across calls and collection" {
  let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
    Ok(prepare_async_jit_context(mod_, instance, store)) catch {
      error => Err("\{error}")
    }
  })
  let context = @wast.WastContext(true, jit_compiler=Some(compiler))
  defer context.close()
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (tag $e (param (ref $s)))
    #|  (global $saved (mut exnref) (ref.null exn))
    #|  (func $make (param i32) (result exnref)
    #|    (block $caught (result exnref)
    #|      (try_table (catch_all_ref $caught)
    #|        (throw $e (struct.new $s (local.get 0))))
    #|      unreachable))
    #|  (func (export "save")
    #|    (global.set $saved (call $make (i32.const 42)))
    #|    (drop (call $make (i32.const 99))))
    #|  (func (export "restore") (result i32)
    #|    (struct.get $s 0
    #|      (block $caught (result (ref $s))
    #|        (try_table (catch $e $caught) (throw_ref (global.get $saved)))
    #|        unreachable))))
    #|(assert_return (invoke "save"))
  let result = @wast.WastResult()
  for entry in @wast.parse(source).commands {
    let (command, line) = entry
    @wast.run_wast_command(context, command, line, result, ".", false)
  }
  assert_eq(result.failed, 0, msg=result.failures.join("\n"))
  guard context.get_store().c_heap is Some(heap) else {
    fail("missing native heap")
  }
  inspect(heap.collect([]), content="0")
  for
    entry in @wast.parse("(assert_return (invoke \"restore\") (i32.const 42))").commands {
    let (command, line) = entry
    @wast.run_wast_command(context, command, line, result, ".", false)
  }
  assert_eq(result.failed, 0, msg=result.failures.join("\n"))
  inspect(result.passed, content="2")
}

///|
test "native exception references cross interpreter arguments results and GC fields" {
  let module_ = @wat.parse(
    (
      #|(module
      #|  (type $box (struct (field (mut exnref))))
      #|  (tag $e (param i32))
      #|  (func (export "make") (param i32) (result exnref)
      #|    (block $caught (result exnref)
      #|      (try_table (catch_all_ref $caught) (throw $e (local.get 0)))
      #|      unreachable))
      #|  (func (export "read") (param exnref) (result i32)
      #|    (block $caught (result i32)
      #|      (try_table (catch $e $caught) (throw_ref (local.get 0)))
      #|      unreachable))
      #|  (func (export "boxed") (param (ref $box)) (result i32)
      #|    (call 1 (struct.get $box 0 (local.get 0)))))
    ),
  )
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  let interpreted = @executor.call_exported_func(store, instance, "make", [
    I32(11),
  ])
  let compiled = context.call_core_func(store, instance, 0, [I32(22)])
  debug_inspect(
    context.call_core_func(store, instance, 1, interpreted),
    content="[I32(11)]",
  )
  debug_inspect(
    @executor.call_exported_func(store, instance, "read", compiled),
    content="[I32(22)]",
  )
  let box = store.alloc_struct(0, interpreted, instance~)
  debug_inspect(
    context.call_core_func(store, instance, 2, [StructRef(box)]),
    content="[I32(11)]",
  )
  store.struct_set(box, 0, compiled[0])
  debug_inspect(
    context.call_core_func(store, instance, 2, [StructRef(box)]),
    content="[I32(22)]",
  )
  assert_eq(store.struct_get(box, 0), compiled[0])
}
