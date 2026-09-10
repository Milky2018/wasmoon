///|
test "guest continuation interpreter: suspension differs from traps and exceptions" {
  let source =
    #|(module
    #|  (type $f (func)) (type $c (cont $f)) (tag $yield)
    #|  (func $body suspend $yield)
    #|  (elem declare func $body)
    #|  (func (export "yield") (resume $c (cont.new $c (ref.func $body))))
    #|  (func (export "trap") unreachable)
    #|  (func (export "throw") throw $yield))
    #|(assert_suspension (invoke "yield") "unhandled")
    #|(assert_trap (invoke "trap") "unreachable")
    #|(assert_exception (invoke "throw"))
  let result = @wast.run_wast_commands(
    @wast.parse(source),
    ".",
    false,
    false,
    stack_switching=true,
  )
  assert_eq(result.failed, 0, msg=result.failures.join("\n"))
  debug_inspect((result.passed, result.failed), content="(3, 0)")
  for
    assertion in [
      "(assert_trap (invoke \"yield\") \"unhandled\")", "(assert_suspension (invoke \"trap\") \"unhandled\")",
      "(assert_exception (invoke \"yield\"))",
    ] {
    let result = @wast.run_wast_commands(
      @wast.parse(source + assertion),
      ".",
      false,
      false,
      stack_switching=true,
    )
    debug_inspect((result.passed, result.failed), content="(3, 1)")
  }
}

///|
test "guest continuation interpreter: resuspended owner survives stale alias trap" {
  let source =
    #|(module
    #|  (type $f (func (result i32))) (type $c (cont $f))
    #|  (tag $yield)
    #|  (global $old (mut (ref null $c)) (ref.null $c))
    #|  (global $next (mut (ref null $c)) (ref.null $c))
    #|  (func $body (result i32) suspend $yield suspend $yield i32.const 42)
    #|  (elem declare func $body)
    #|  (func (export "start")
    #|    (block $s (result (ref $c))
    #|      (resume $c (on $yield $s) (cont.new $c (ref.func $body)))
    #|      unreachable)
    #|    global.set $old
    #|    (block $s (result (ref $c))
    #|      (resume $c (on $yield $s) (global.get $old))
    #|      unreachable)
    #|    global.set $next)
    #|  (func (export "stale") (resume $c (global.get $old)) drop)
    #|  (func (export "finish") (result i32) (resume $c (global.get $next))))
    #|(assert_return (invoke "start"))
    #|(assert_trap (invoke "stale") "continuation already consumed")
    #|(assert_return (invoke "finish") (i32.const 42))
  let result = @wast.run_wast_commands(
    @wast.parse(source),
    ".",
    false,
    false,
    stack_switching=true,
  )
  assert_eq(result.failed, 0, msg=result.failures.join("\n"))
  debug_inspect((result.passed, result.failed), content="(3, 0)")
}

///|
test "guest continuation interpreter: parked locals root GC values until completion" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $f (func (param (ref $s)) (result i32)))
    #|  (type $c (cont $f))
    #|  (type $rest (func (result i32))) (type $k (cont $rest))
    #|  (tag $yield)
    #|  (global $next (mut (ref null $k)) (ref.null $k))
    #|  (func $body (type $f) suspend $yield local.get 0 struct.get $s 0)
    #|  (elem declare func $body)
    #|  (func (export "start") (param (ref $s))
    #|    (block $suspended (result (ref $k))
    #|      (resume $c (on $yield $suspended) (local.get 0) (cont.new $c (ref.func $body)))
    #|      unreachable)
    #|    global.set $next)
    #|  (func (export "finish") (result i32) (resume $k (global.get $next))))
  for native_heap in [false, true] {
    let module_ = @wat.parse(source)
    @validator.validate_module(module_, stack_switching=true)
    let store = if native_heap {
      @runtime.Store::with_c_heap()
    } else {
      @runtime.Store()
    }
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      @runtime.Imports(),
    )
    let rooted = store.alloc_struct(0, [I32(42)])
    @executor.call_exported_func(store, instance, "start", [StructRef(rooted)])
    |> ignore
    inspect(store.collect_garbage(), content="0")
    debug_inspect(
      @executor.call_exported_func(store, instance, "finish", []),
      content="[I32(42)]",
    )
    inspect(store.collect_garbage(), content="1")
    inspect(store.is_gc_valid(rooted), content="false")
  }
}

///|
test "guest continuation GC capability: unused storage types remain valid" {
  let types = "(type $f (func)) (type $c (cont $f)) (type $s (struct (field (ref null $c))))"
  let unused = "(module " +
    types +
    " (func (export \"run\") (result i32) i32.const 42))"
  let used = "(module " + types + " (func struct.new_default $s drop))"
  // The module is valid WebAssembly; the restriction belongs to the engine.
  @validator.validate_module(@wat.parse(used), stack_switching=true)
  let script = unused +
    "(assert_return (invoke \"run\") (i32.const 42))" +
    "(assert_invalid " +
    used +
    " \"Stack switching feature not compatible with GC\")"
  let result = @wast.run_wast_commands(
    @wast.parse(script),
    ".",
    false,
    false,
    stack_switching=true,
  )
  debug_inspect((result.passed, result.failed), content="(2, 0)")
}
