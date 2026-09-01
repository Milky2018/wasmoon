///|
async test "JIT async host function parks and resumes its native fiber" {
  let func_type : @types.FuncType = { params: [I32], results: [I32], }
  let mod_ : @types.Module = {
    ..@types.Module::empty(),
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "host", name: "double", desc: Func(0), }],
    funcs: [0],
    codes: [{ locals: [], body: [LocalGet(0), Call(0), I32Const(1), I32Add], }],
    exports: [{ name: "run", desc: Func(1), }],
  }
  let events : Array[String] = []
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      events.push("host started")
      @async.sleep(10)
      events.push("host ready")
      match args[0] {
        I32(value) => [I32(value * 2)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type~,
  )
  let store = linker.get_store()
  let instance = @executor.instantiate_with_linker(linker, "guest", mod_)
  guard @commands.compile_module_to_jit(mod_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("JIT compilation failed")
  }
  let loaded = @commands.verify_compiled_jit_artifact(artifact)
  let jit_module = @jit.JITModule::load_artifact_with_imports(
    loaded,
    @wast.build_func_signatures(mod_),
    @wast.build_external_imports_for_jit(mod_, instance, store),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  defer jit_module.close()
  @wast.register_instance_funcrefs_for_jit(jit_module, instance, store)
  jit_module.configure_native_fiber_stack_size(1048576L) |> ignore
  guard @wast.init_jit_memories_from_store(instance, store, jit_module)
    is Some(_) else {
    fail("JIT memory initialization failed")
  }
  let globals_ptr = @wast.init_jit_globals_from_store(
    instance, store, jit_module,
  )
  @wast.init_elem_segments(
    mod_,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  )
  @wast.init_bulk_segments(
    mod_,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  )
  @wast.sync_tables_to_jit(
    instance,
    store,
    jit_module,
    use_subtype_indirect_check=true,
  )
  let jit_context = @wast.JITModuleContext(
    jit_module,
    globals_ptr,
    instance.global_addrs.copy(),
    instance.table_addrs.copy(),
    instance.func_addrs.copy(),
    instance.func_type_indices.copy(),
    instance.canonical_type_indices.copy(),
    mod_.types.copy(),
    mod_.type_rec_groups.copy(),
    true,
  )
  @wast.install_jit_hostcall_dispatcher(
    jit_module, store, instance, jit_context,
  )
  let sync_error = try
    jit_context.call_core_func(store, instance, 1, [I32(20)])
  catch {
    error => error.to_string()
  } noraise {
    _ => fail("expected the synchronous JIT call to fail")
  }
  inspect(
    sync_error,
    content=(
      #|HostInvocation("async host function requires an async wasm call")
    ),
  )
  let result = @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(20)])
    })
    group.spawn_bg() <| () => {
      @async.sleep(1)
      events.push("other task ran")
    }
    call.wait()
  })
  debug_inspect(result, content="[I32(41)]")
  debug_inspect(
    events,
    content="[\"host started\", \"other task ran\", \"host ready\"]",
  )
  let cancellation = @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(10)])
    })
    @async.sleep(1)
    call.cancel()
    try call.wait() catch {
      error => error.to_string()
    } noraise {
      _ => fail("expected the asynchronous JIT call to be cancelled")
    }
  })
  inspect(cancellation, content="Cancelled")
  let after_cancellation = jit_context.call_core_func_async(
    store,
    instance,
    1,
    [I32(5)],
  )
  debug_inspect(after_cancellation, content="[I32(11)]")
}
