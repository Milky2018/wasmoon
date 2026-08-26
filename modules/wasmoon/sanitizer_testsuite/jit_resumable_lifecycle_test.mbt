///|
fn build_resumable_lifecycle_context(
  mod_ : @types.Module,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  valid_func_type_indices? : Bool = true,
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
  let func_type_indices : Array[Int] = []
  if valid_func_type_indices {
    for type_idx in instance.func_type_indices {
      func_type_indices.push(type_idx)
    }
  }
  let canonical_type_indices : Array[Int] = []
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
    instance.func_addrs.copy(),
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
test "resumable JIT releases execution admission when GC setup fails" {
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
    content=(
      #|(
      #|  "GcSetupFailed(\"FuncTypeIndicesLengthMismatch(func_type_indices_len=0, num_funcs=1)\")",
      #|  0,
      #|  0,
      #|  true,
      #|)
    ),
  )
  store.close()
  context.close()
}
