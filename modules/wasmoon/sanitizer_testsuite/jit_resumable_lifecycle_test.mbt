///|
fn build_resumable_lifecycle_context(
  mod_ : @types.Module,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  valid_func_type_indices~ : Bool = true,
) -> @wast.JITModuleContext raise {
  guard @commands.compile_module_to_jit(mod_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("JIT compile returned unsupported")
  }
  let jm = @jit.JITModule::load_artifact(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(mod_),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  jm.configure_native_fiber_stack_size(1024L * 1024L) |> ignore
  let globals_ptr = @wast.init_jit_globals_from_store(instance, store, jm)
  let func_type_indices : Array[Int32] = []
  if valid_func_type_indices {
    for type_idx in instance.func_type_indices {
      func_type_indices.push(type_idx)
    }
  }
  let canonical_type_indices : Array[Int32] = []
  for canonical_idx in instance.canonical_type_indices {
    canonical_type_indices.push(canonical_idx)
  }
  let module_types : Array[@types.SubType] = []
  for subtype in mod_.types {
    module_types.push(subtype)
  }
  JITModuleContext(
    jm,
    globals_ptr,
    [],
    [],
    instance.func_addrs[:].to_owned(),
    func_type_indices,
    canonical_type_indices,
    module_types,
    mod_.type_rec_groups.copy(),
    true,
  )
}

///|
test "resumable JIT leaves GC state clear when execution admission is sealed" {
  let mod_ = @wat.parse("(module (func (export \"run\")))")
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  store.enable_c_heap()
  let instance = @executor.instantiate_with_linker(linker, "test", mod_)
  let context = build_resumable_lifecycle_context(mod_, store, instance)
  let state = store.native_execution_state()
  state.seal()
  let error = try {
    context.call_core_func_resumable(store, instance, 0, []) |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  } noraise {
    result => result
  }
  debug_inspect(
    (
      error,
      state.active_depth(),
      state.live_count(),
      context.jit_module.gc_environment_is_clear(),
    ),
    content="(\"ExecutionStateFailure(ExecutionStateSealed)\", 0, 0, true)",
  )
  store.close()
  context.close()
}

///|
test "resumable JIT rejects inconsistent function metadata before admission" {
  let mod_ = @wat.parse("(module (func (export \"run\")))")
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  store.enable_c_heap()
  let instance = @executor.instantiate_with_linker(linker, "test", mod_)
  let context = build_resumable_lifecycle_context(
    mod_,
    store,
    instance,
    valid_func_type_indices=false,
  )
  let state = store.native_execution_state()
  let error = try {
    context.call_core_func_resumable(store, instance, 0, []) |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  } noraise {
    result => result
  }
  debug_inspect(
    (
      error,
      state.active_depth(),
      state.live_count(),
      context.jit_module.gc_environment_is_clear(),
    ),
    content="(\"HostInvocation(InvalidHandle)\", 0, 0, true)",
  )
  store.close()
  context.close()
}

///|
test "parked table synchronization retains GC roots and releases cancellation state" {
  let source =
    #|(module
    #| (type $value (struct (field i32)))
    #| (table 1 (ref null $value))
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  i32.const 0 i32.const 42 struct.new $value table.set
    #|  (loop $again
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining br_if $again)
    #|  i32.const 0 table.get struct.get $value 0))
  let module_ = @wat.parse(source)
  for cancel in [false, true] {
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
      enable_cancellation=true,
    )
    defer context.close()
    assert_true(context.jit_module.set_cooperative_scheduling(true))
    let state = store.native_execution_state()
    let mut outcome = context.call_core_func_resumable(store, instance, 0, [
      I32(10000),
    ])
    defer (if outcome is NativeCoreSuspended(_, continuation) {
      continuation.cancel()
    })
    let table = store.get_table(instance.table_addrs[0])
    let native = store.get_jit_table(instance.table_addrs[0]).unwrap().raw_ptr()
    let revision = native.revision()
    let mut yields = 0
    while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
      yields += 1
      assert_eq(state.active_depth(), 0)
      guard table.get(0) is StructRef(_) else {
        fail("table root was not published")
      }
      store.collect_garbage() |> ignore
      assert_eq(native.revision(), revision)
      if cancel {
        continuation.cancel()
        continuation.cancel()
        break
      }
      outcome = continuation.continue_execution()
    }
    if !cancel {
      assert_true(yields > 1)
      guard outcome is NativeCoreReturned(values) else {
        fail("unexpected suspension")
      }
      assert_eq(values, [I32(42)])
    } else {
      assert_eq(yields, 1)
    }
    assert_eq(state.active_depth(), 0)
    assert_eq(state.live_count(), 0)
    context.close()
    store.close()
    assert_true(context.jit_module.gc_environment_is_clear())
  }
}
