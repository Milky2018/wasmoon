///|
fn frame_chain_module() -> @types.Module raise {
  @wat.parse(
    (
      #|(module (memory 1)
      #| (func (export "leaf") (param i32) (result i32) local.get 0 i32.load)
      #| (func (export "middle") (param i32) (result i32) local.get 0 call 0 i32.const 1 i32.add)
      #| (func (export "outer") (param i32) (result i32) local.get 0 call 1 i32.const 1 i32.add)
      #| (func (export "run") i32.const 65536 call 2 drop))
    ),
  )
}

///|
fn trigger_frame_chain(
  context : @wast.JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  entry : Int32,
) -> @wasmoon_jit.TrapReport raise {
  try {
    let mut outcome = context.call_core_func_resumable(store, instance, entry, [])
    while outcome is NativeCoreSuspended(_, continuation) {
      outcome = continuation.continue_execution()
    }
    fail("expected native guest trap")
  } catch {
    error =>
      assert_true(error.to_string().contains("Trap"), msg=error.to_string())
  }
  guard context.jit_module.get_last_trap_report() is Some(report) else {
    fail("missing owned report")
  }
  report
}

///|
test "resumable traps own every non-tail guest caller including leaf frames" {
  for level in [0, 2] {
    let module_ = frame_chain_module()
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
      opt_level=level,
    )
    defer context.close()
    assert_true(context.jit_module.configure_native_fiber_stack_size(16777216L))
    let dwarf = context.jit_module.register_dwarf()
    defer dwarf.destroy()
    let report = trigger_frame_chain(context, store, instance, 3)
    assert_eq(report.wasm_frames.map(frame => frame.func_idx), [0, 1, 2, 3])
    let backtrace = dwarf
      .capture_backtrace()
      .filter(frame => frame.func_idx >= 0)
    assert_eq(backtrace.map(frame => frame.func_idx), [0, 1, 2, 3])
    context.close()
    store.close()
    assert_eq(report.wasm_frames.map(frame => frame.func_name), [
      "leaf", "middle", "outer", "run",
    ])
  }
}

///|
test "another active DWARF owner cannot truncate a module's guest callers" {
  let module_ = frame_chain_module()
  let first_store = @runtime.Store::with_c_heap()
  defer first_store.close()
  let first_instance = @executor.instantiate_module_with_imports(
    first_store,
    module_,
    Imports(first_store),
  )
  let first = prepare_async_jit_context(
    module_,
    first_instance,
    first_store,
    cooperative=true,
  )
  defer first.close()
  let first_debug = first.jit_module.register_dwarf()
  defer first_debug.destroy()
  let second_store = @runtime.Store::with_c_heap()
  defer second_store.close()
  let second_instance = @executor.instantiate_module_with_imports(
    second_store,
    module_,
    Imports(second_store),
  )
  let second = prepare_async_jit_context(
    module_,
    second_instance,
    second_store,
    cooperative=true,
  )
  defer second.close()
  let second_debug = second.jit_module.register_dwarf()
  defer second_debug.destroy()
  let report = trigger_frame_chain(first, first_store, first_instance, 3)
  assert_eq(report.wasm_frames.map(frame => frame.func_idx), [0, 1, 2, 3])
  assert_eq(
    first_debug
    .capture_backtrace()
    .filter(frame => frame.func_idx >= 0)
    .map(frame => frame.func_idx),
    [0, 1, 2, 3],
  )
}

///|
test "guard-page recursion keeps repeated guest frames and a reusable context" {
  // Wide frames also cross pages that Windows guard restoration can protect.
  for extra_parameters in [0, 128] {
    let parameters = Array::make(extra_parameters, " i64").join("")
    let forwarded = Array::makei(extra_parameters, i => "local.get \{i + 1}").join(
      " ",
    )
    let initial = Array::make(extra_parameters, "i64.const 0").join(" ")
    let module_ = @wat.parse(
      (
        $|(module
        $| (func (export "recurse") (param i32\{parameters}) (result i32)
        $|  local.get 0 i32.const 1 i32.add \{forwarded} call 0 i32.const 1 i32.add)
        $| (func (export "run") i32.const 0 \{initial} call 0 drop)
        $| (func (export "healthy") (result i32) i32.const 42))
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
    assert_true(context.jit_module.configure_native_fiber_stack_size(65536L))
    let report = trigger_frame_chain(context, store, instance, 1)
    assert_true(
      report.trap_kind.contains("call stack exhausted"),
      msg=report.trap_kind,
    )
    assert_true(
      report.wasm_frames.length() >= 8,
      msg="parameters=\{extra_parameters}, frames=\{report.wasm_frames.length()}",
    )
    for index, frame in report.wasm_frames {
      assert_true(
        frame.func_idx == 0 ||
        (
          extra_parameters > 0 &&
          index == report.wasm_frames.length() - 1 &&
          frame.func_idx == 1
        ),
      )
    }
    debug_inspect(
      context.call_core_func(store, instance, 2, []),
      content="[I32(42)]",
    )
  }
}

///|
async test "native callers survive cooperative and async host suspension before a trap" {
  let module_ = @wat.parse(
    (
      #|(module (import "h" "pause" (func)) (memory 1)
      #| (func (export "leaf") (param i32) (result i32) call 0 local.get 0 i32.load)
      #| (func (export "middle") (param i32) (result i32) local.get 0 call 1 i32.const 1 i32.add)
      #| (func (export "outer") (param i32) (result i32) local.get 0 call 2 i32.const 1 i32.add)
      #| (func (export "run") (local i32)
      #|  i32.const 10000 local.set 0
      #|  loop local.get 0 i32.const 1 i32.sub local.tee 0 br_if 0 end
      #|  i32.const 65536 call 3 drop))
    ),
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let imports = @runtime.Imports(store)
  let called = Ref(false)
  imports.add_func(
    "h",
    "pause",
    store.alloc_async_host_func(async fn(_) {
      called.val = true
      @async.sleep(1)
      []
    }),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
    opt_level=2,
  )
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  // The raw sync entry can park cooperatively but must not run async imports.
  guard context.call_core_func_resumable(store, instance, 4, [])
    is NativeCoreSuspended(CooperativeYield, first) else {
    fail("expected cooperative suspension before host import")
  }
  first.cancel()
  try context.call_core_func_async(store, instance, 4, []) catch {
    error =>
      assert_true(error.to_string().contains("Trap"), msg=error.to_string())
  } noraise {
    _ => fail("expected resumed native trap")
  }
  assert_true(called.val)
  guard context.jit_module.get_last_trap_report() is Some(report) else {
    fail("missing resumed report")
  }
  assert_eq(report.wasm_frames.map(frame => frame.func_idx), [1, 2, 3, 4])
}

///|
test "nested native modules keep separate owned caller reports" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let child_module = frame_chain_module()
  let child_instance = @executor.instantiate_module_with_imports(
    store,
    child_module,
    Imports(store),
  )
  let child = prepare_async_jit_context(
    child_module,
    child_instance,
    store,
    cooperative=true,
  )
  defer child.close()
  let nested : Ref[@wasmoon_jit.TrapReport?] = Ref(None)
  let host = store.alloc_host_func(fn(
    _,
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    nested.val = Some(
      trigger_frame_chain(child, store, child_instance, 3) catch {
        error => raise AsyncHostError(error.to_string())
      },
    )
    []
  })
  let module_ = @wat.parse(
    "(module (import \"h\" \"nested\" (func)) (func (export \"leaf-parent\") call 0 unreachable) (func (export \"run-parent\") call 1 nop))",
  )
  let imports = @runtime.Imports(store)
  imports.add_func("h", "nested", host)
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let parent = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer parent.close()
  parent.install_hostcall_dispatcher(store, instance)
  let report = trigger_frame_chain(parent, store, instance, 2)
  assert_eq(report.wasm_frames.map(frame => frame.func_idx), [1, 2])
  assert_eq(report.wasm_frames.map(frame => frame.func_name), [
    "leaf-parent", "run-parent",
  ])
  guard nested.val is Some(child_report) else { fail("child did not run") }
  assert_eq(child_report.wasm_frames.map(frame => frame.func_idx), [0, 1, 2, 3])
  parent.close()
  child.close()
  assert_eq(child_report.wasm_frames[0].func_name, "leaf")
}
