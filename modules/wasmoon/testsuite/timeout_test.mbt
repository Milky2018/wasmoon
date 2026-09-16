///|
fn timeout_module() -> @types.Module raise {
  @wat.parse(
    (
      #|(module
      #|  (func (export "run") (param i32) (result i32)
      #|    local.get 0
      #|    if (loop $forever br $forever) end
      #|    i32.const 42))
    ),
  )
}

///|
test "interpreter timeout bounds loops and preserves subsequent calls" {
  let (store, instance) = @executor.instantiate_module(timeout_module())
  defer store.close()
  for pair in [(0, 0), (2, 1)] {
    let (timeout, arg) = pair
    let result = @executor.call_exported_func_with_options(
      store,
      instance,
      "run",
      [I32(arg)],
      options=@executor.CallExportOptions(timeout_ms=Some(timeout)),
    )
    guard result is Err(failure) else { fail("expected timeout") }
    assert_true(failure.kind is TimedOut)
  }
  let invalid = @executor.call_exported_func_with_options(
    store,
    instance,
    "run",
    [I32(0)],
    options=@executor.CallExportOptions(timeout_ms=Some(-1)),
  )
  guard invalid is Err(failure) else { fail("expected invalid timeout") }
  assert_true(failure.kind is InvalidOption)
  let result = @executor.call_exported_func_with_options(
    store,
    instance,
    "run",
    [I32(0)],
    options=@executor.CallExportOptions(timeout_ms=Some(10000)),
  )
  assert_true(result is Ok([I32(42)]))
}

///|
fn timeout_jit(instrumented : Bool) -> @jit.JITModule raise {
  let mod_ = timeout_module()
  guard @commands.compile_module_to_jit(
      mod_,
      false,
      false,
      0,
      false,
      enable_cancellation=instrumented,
    )
    is Some((artifact, debug_db)) else {
    fail("JIT compilation failed")
  }
  @jit.JITModule::load_artifact(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(mod_),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
}

///|
test "JIT timeout bounds loops and preserves subsequent calls" {
  let jm = timeout_jit(true)
  defer jm.close()
  guard jm.get_func_by_name("run") is Some(func) else {
    fail("missing function")
  }
  assert_true(
    jm.call_with_context_controlled(func, [0L], timeout_ms=Some(0)) is TimedOut,
  )
  assert_true(
    jm.call_with_context_controlled(func, [1L], timeout_ms=Some(2)) is TimedOut,
  )
  assert_true(
    jm.call_with_context_controlled(func, [0L], timeout_ms=Some(-1))
    is InvalidTimeout,
  )
  assert_true(
    jm.call_with_context_controlled(func, [0L], timeout_ms=Some(10000))
    is Completed([42L]),
  )
  assert_true(jm.call_with_context_controlled(func, [0L]) is Completed([42L]))
}

///|
test "JIT timeout requires cancellation instrumentation" {
  let jm = timeout_jit(false)
  defer jm.close()
  guard jm.get_func_by_name("run") is Some(func) else {
    fail("missing function")
  }
  assert_true(
    jm.call_with_context_controlled(func, [0L], timeout_ms=Some(10))
    is UnsupportedCancellation,
  )
}

///|
async test "invocation deadline includes suspended host time" {
  guard @wasmoon_jit.InvocationControl::new(Some(1), None) is Some(control) else {
    fail("valid timeout rejected")
  }
  @async.sleep(10)
  assert_true(control.poll())
  assert_true(control.expired())
}

///|
test "interpreter timeout includes a final blocking host call" {
  let mod_ = @wat.parse(
    (
      #|(module
      #|  (import "host" "slow" (func $slow (result i32)))
      #|  (func (export "run") (result i32) call $slow))
    ),
  )
  let store = @runtime.Store::Store()
  defer store.close()
  let addr = store.alloc_host_func_with_caller(
    (_caller, _args) => {
      guard @wasmoon_jit.InvocationControl::new(Some(5), None) is Some(wait) else {
        raise @runtime.Unreachable
      }
      while !wait.expired() {
        ()
      }
      [I32(42)]
    },
    func_type={ params: [], results: [I32], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("host", "slow", addr)
  let instance = @executor.instantiate_module_with_imports(store, mod_, imports)
  let result = @executor.call_exported_func_with_options(
    store,
    instance,
    "run",
    [],
    options=@executor.CallExportOptions(timeout_ms=Some(1)),
  )
  guard result is Err(failure) else {
    fail("expected timeout after host return")
  }
  assert_true(failure.kind is TimedOut)
  assert_true(
    @executor.call_exported_func_with_options(store, instance, "run", [])
    is Ok([I32(42)]),
  )
}
