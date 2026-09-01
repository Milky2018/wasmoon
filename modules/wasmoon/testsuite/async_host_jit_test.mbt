///|
fn prepare_async_jit_context(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> @wast.JITModuleContext raise {
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
  JITModuleContext(
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
}

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
        I32(value) if value < 0 => raise @runtime.DivisionByZero
        I32(value) => [I32(value * 2)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type~,
  )
  let store = linker.get_store()
  let instance = @executor.instantiate_with_linker(linker, "guest", mod_)
  let jit_context = prepare_async_jit_context(mod_, instance, store)
  defer jit_context.close()
  jit_context.install_hostcall_dispatcher(store, instance)
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
      #|HostInvocation(AsyncHostRequiresAsyncCall)
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
  let isolated = @async.with_task_group(group => {
    let outer = group.spawn(no_wait=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(6)])
    })
    @async.sleep(1)
    let nested_error = try
      jit_context.call_core_func(store, instance, 1, [I32(7)])
    catch {
      error => error
    } noraise {
      _ => fail("expected synchronous entry to reject the async import")
    }
    (nested_error, outer.wait())
  })
  debug_inspect(
    isolated,
    content=(
      #|(HostInvocation(AsyncHostRequiresAsyncCall), [I32(13)])
    ),
  )
  let overlapping = @async.with_task_group(group => {
    let first = group.spawn(no_wait=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(2)])
    })
    let second = group.spawn(no_wait=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(3)])
    })
    (first.wait(), second.wait())
  })
  debug_inspect(overlapping, content="([I32(5)], [I32(7)])")
  let host_error = try
    jit_context.call_core_func_async(store, instance, 1, [I32(-1)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the asynchronous host function to fail")
  }
  debug_inspect(host_error, content="HostInvocation(DivisionByZero)")
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

///|
async test "JIT propagates async suspension through an imported wasm function" {
  let func_type : @types.FuncType = { params: [I32], results: [I32], }
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      match args[0] {
        I32(value) if value == 99 => {
          @async.sleep(1000)
          [I32(value * 2)]
        }
        I32(value) if value < 0 => {
          @async.sleep(1)
          raise @runtime.DivisionByZero
        }
        I32(value) => {
          @async.sleep(1)
          [I32(value * 2)]
        }
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type~,
  )
  let callee = @wat.parse(
    (
      #|(module
      #|  (type $unary (func (param i32) (result i32)))
      #|  (import "host" "double" (func $double (type $unary)))
      #|  (func (export "run") (type $unary) (param i32) (result i32)
      #|    local.get 0
      #|    call $double
      #|    call $double
      #|    i32.const 1
      #|    i32.add))
    ),
  )
  @executor.instantiate_with_linker(linker, "callee", callee) |> ignore
  let caller = @wat.parse(
    (
      #|(module
      #|  (type $unary (func (param i32) (result i32)))
      #|  (import "callee" "run" (func $run (type $unary)))
      #|  (func (export "entry") (type $unary) (param i32) (result i32)
      #|    local.get 0
      #|    call $run
      #|    i32.const 2
      #|    i32.add))
    ),
  )
  let instance = @executor.instantiate_with_linker(linker, "caller", caller)
  let store = linker.get_store()
  let jit_context = prepare_async_jit_context(caller, instance, store)
  defer jit_context.close()
  jit_context.install_hostcall_dispatcher(store, instance)
  let sync_error = try
    jit_context.call_core_func(store, instance, 1, [I32(20)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the synchronous call to reject the async import")
  }
  inspect(sync_error, content="HostInvocation(AsyncHostRequiresAsyncCall)")
  let result = jit_context.call_core_func_async(store, instance, 1, [I32(20)])
  debug_inspect(result, content="[I32(83)]")
  let host_error = try
    jit_context.call_core_func_async(store, instance, 1, [I32(-1)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the asynchronous host function to fail")
  }
  inspect(host_error, content="HostInvocation(DivisionByZero)")
  let cancellation = @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      jit_context.call_core_func_async(store, instance, 1, [I32(99)])
    })
    @async.sleep(1)
    call.cancel()
    try call.wait() catch {
      error => error.to_string()
    } noraise {
      _ => fail("expected the cross-module call to be cancelled")
    }
  })
  inspect(cancellation, content="Cancelled")
  let after_cancellation = jit_context.call_core_func_async(
    store,
    instance,
    1,
    [I32(5)],
  )
  debug_inspect(after_cancellation, content="[I32(23)]")
}
