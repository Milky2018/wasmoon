///|
/// Instantiation and compilation finish before the selected engine runs start.
priv struct PreparedWastModule {
  instance : @runtime.ModuleInstance
  jit : JITModuleContext?
  name : String?
}

///|
fn prepare_wast_module(
  ctx : WastContext,
  module_ : @types.Module,
  name : String?,
  cooperative~ : Bool = false,
) -> PreparedWastModule raise WastRunnerError {
  ctx.validate_core_module(module_) catch {
    error => raise RuntimeError("module validation failed: \{error}")
  }
  let instance = @executor.instantiate_module_with_imports_unstarted(
    ctx.store,
    module_,
    ctx.build_imports(),
  ) catch {
    error => raise classify_runtime_failure(error)
  }
  let jit = if ctx.use_jit {
    match ctx.try_compile_jit(module_, instance) {
      Ok(context) => {
        if cooperative && !context.jit_module.set_cooperative_scheduling(true) {
          raise RuntimeError("WAST scheduling requires instrumented JIT code")
        }
        Some(context)
      }
      Err(message) =>
        raise RuntimeError("JIT module compile failed: \{message}")
    }
  } else {
    None
  }
  { instance, jit, name, }
}

///|
fn publish_wast_module(
  ctx : WastContext,
  prepared : PreparedWastModule,
) -> Unit {
  ctx.modules.publish(prepared.instance, prepared.name)
  ctx.current_jit = prepared.jit
  if prepared.name is Some(name) {
    match prepared.jit {
      Some(jit) => ctx.jit_modules.set(name, jit)
      None => ctx.jit_modules.remove(name)
    }
    if ctx.register_named_modules {
      ctx.modules.register(name, prepared.instance)
      if name == "spectest" || name == "wasi_snapshot_preview1" {
        ctx.overridden_builtin_modules.add(name)
      }
    }
  }
}

///|
fn instantiate_script_module(
  ctx : WastContext,
  module_ : @types.Module,
  name : String?,
) -> Unit raise WastRunnerError {
  let prepared = prepare_wast_module(ctx, module_, name)
  if module_.start is Some(index) {
    let (instance, jit, index) = resolve_wast_call(
      ctx,
      prepared.instance,
      prepared.jit,
      index,
    )
    let _ = match jit {
      Some(jit) =>
        jit.call_core_func(ctx.store, instance, index, []) catch {
          error => raise classify_jit_failure(error)
        }
      None =>
        @executor.call_func_by_index(ctx.store, instance, index, []) catch {
          error => raise classify_runtime_failure(error)
        }
    }
  }
  publish_wast_module(ctx, prepared)
}

///|
/// Imported entries belong to their defining instance or to the host.
fn resolve_wast_call(
  ctx : WastContext,
  instance : @runtime.ModuleInstance,
  jit : JITModuleContext?,
  index : Int32,
) -> (@runtime.ModuleInstance, JITModuleContext?, Int32) raise WastRunnerError {
  guard jit is Some(compiled) else { return (instance, None, index) }
  if compiled.jit_module.get_func(index) is Some(_) {
    return (instance, jit, index)
  }
  let address = instance.func_addrs[index]
  let function = ctx.store.get_func_inst(address) catch {
    error => raise classify_runtime_failure(error)
  }
  match function {
    HostFunc(_) | ThrowingHostFunc(_) | AsyncHostFunc(_) =>
      (instance, None, index)
    WasmFunc(_) => {
      guard ctx.store.get_func_owner(address) is Some(owner) else {
        raise RuntimeError("imported function has no defining instance")
      }
      for candidate in ctx.compiled_modules {
        for local_index, local_address in candidate.func_addrs {
          if local_address == address &&
            candidate.jit_module.get_func(local_index) is Some(_) {
            return (owner, Some(candidate), local_index)
          }
        }
      }
      raise RuntimeError("imported function has no compiled defining instance")
    }
  }
}

///|
fn classify_jit_failure(error : JITCoreCallError) -> WastRunnerError {
  match error {
    Trap(message) =>
      if message.has_prefix("uncaught exception") {
        GuestException
      } else if message.has_prefix("unhandled suspension") {
        GuestSuspension
      } else if message.has_prefix("call stack exhausted") ||
        message.has_prefix("stack overflow") {
        GuestExhaustion(message)
      } else {
        GuestTrap(message)
      }
    error => RuntimeError(error.to_string())
  }
}
