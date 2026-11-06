///|
/// Core conformance adapter shared by native and wasm-hosted interpreter runs.
/// Filesystem access belongs to the command, not this runner or the interpreter.
pub struct CoreWastContext {
  store : @runtime.Store
  mut closed : Bool
  modules : WastModules
  stack_switching : Bool
}

///|
pub fn CoreWastContext::new(
  stack_switching~ : Bool = false,
) -> CoreWastContext raise @runtime.RuntimeError {
  let store = @runtime.Store::Store()
  errdefer store.close()
  let spectest = @spectest.create_spectest_module(store, print_char=c => {
    if c >= 0 && c <= 0x7f {
      println(c.to_char().unwrap().to_string())
    }
  })
  let linker = @runtime.Linker::with_store(store)
  linker.add_host_func("wasmtime", "gc", _args => {
    store.collect_garbage() |> ignore
    []
  })
  let registered = Map([("spectest", spectest)])
  registered.set("wasmtime", linker.get_module("wasmtime").unwrap())
  {
    store,
    closed: false,
    modules: WastModules::new(registered),
    stack_switching,
  }
}

///|
pub fn CoreWastContext::close(self : CoreWastContext) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.store.close()
  self.modules.clear()
}

///|
pub fn CoreWastContext::build_imports(
  self : CoreWastContext,
) -> @runtime.Imports {
  self.modules.build_imports(self.store)
}

///|
impl WastEngine for CoreWastContext with fn modules(self) {
  self.modules
}

///|
impl WastEngine for CoreWastContext with fn store(self) {
  self.store
}

///|
impl WastEngine for CoreWastContext with fn closed(self) {
  self.closed
}

///|
impl WastEngine for CoreWastContext with fn validate(self, module_) {
  @validator.validate_module(
    module_,
    bulk_memory=true,
    stack_switching=self.stack_switching,
  )
  @executor.validate_continuation_gc_storage(module_)
}

///|
impl WastEngine for CoreWastContext with fn instantiate(self, module_, name) {
  WastEngine::validate(self, module_)
  let instance = @executor.instantiate_module_with_imports(
    self.store,
    module_,
    self.build_imports(),
  )
  self.modules.publish(instance, name)
}

///|
impl WastEngine for CoreWastContext with fn source_is_invalid(
  self,
  source,
  _expected,
) {
  @assertions.validate_module_source(
    source,
    bulk_memory=true,
    stack_switching=self.stack_switching,
  )
  is None
}

///|
impl WastEngine for CoreWastContext with fn registered(_self, _name) {
  ()
}

///|
impl WastEngine for CoreWastContext with fn invoke(self, action) {
  invoke_action(self, action)
}

///|
pub fn invoke_action(
  ctx : CoreWastContext,
  action : @wat.WastAction,
) -> Array[@types.Value] raise WastRunnerError {
  invoke_script_action(ctx.store, ctx.modules, action)
}

///|
pub fn run_wast_command(
  ctx : CoreWastContext,
  command : @wat.WastCommand,
  line : Int32,
  result : WastResult,
  show_success : Bool,
) -> Unit {
  execute_command(
    ctx,
    command,
    line,
    result,
    show_success,
    track_unsupported=true,
  )
}

///|
impl WastEngine for CoreWastContext with fn source_traps(ctx, source, expected) {
  let module_ = @assertions.parse_module_source(source) catch {
    _ => return false
  }
  WastEngine::validate(ctx, module_) catch {
    _ => return false
  }
  try {
    @executor.instantiate_module_with_imports(
      ctx.store,
      module_,
      ctx.build_imports(),
    )
    |> ignore
    false
  } catch {
    error =>
      match classify_runtime_failure(error) {
        GuestTrap(message) => wast_trap_message_matches(message, expected)
        _ => false
      }
  }
}

///|
/// Unsupported host mechanisms are reported separately; they never count as passes.
pub fn run_script(
  source : String,
  stack_switching~ : Bool = false,
) -> WastResult raise {
  let script = @wat.parse_wast(source)
  let ctx = CoreWastContext::new(stack_switching~)
  defer ctx.close()
  let result = WastResult::WastResult()
  for command in script.commands {
    if command.0 is Thread(_, _, _) || command.0 is Wait(_) {
      result.unsupported.push("thread directives require a concurrent host")
      return result
    }
  }
  for command in script.commands {
    run_wast_command(ctx, command.0, command.1, result, false)
    if !result.unsupported.is_empty() {
      break
    }
  }
  result
}

///|
pub using @assertions {
  type WastRunnerError,
  wast_value_to_runtime,
  values_match,
  wast_trap_message_matches,
  classify_runtime_failure,
}
