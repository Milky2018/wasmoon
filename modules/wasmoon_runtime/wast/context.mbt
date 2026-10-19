///|
/// Core conformance adapter shared by native and wasm-hosted interpreter runs.
/// Filesystem access belongs to the command, not this runner or the interpreter.
pub struct CoreWastContext {
  store : @runtime.Store
  mut closed : Bool
  mut current_module : @runtime.ModuleInstance?
  named_modules : Map[String, @runtime.ModuleInstance]
  module_definitions : Map[String, @types.Module]
  mut current_definition : @types.Module?
  registered_modules : Map[String, @runtime.ModuleInstance]
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
    current_module: None,
    named_modules: Map([]),
    module_definitions: Map([]),
    current_definition: None,
    registered_modules: registered,
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
  self.current_module = None
  self.current_definition = None
  self.named_modules.clear()
  self.module_definitions.clear()
  self.registered_modules.clear()
}

///|
fn run_wast_module(
  ctx : CoreWastContext,
  module_ : @types.Module,
  name : String?,
  line : Int32,
  result : WastResult,
) -> Unit {
  try {
    ctx.validate_core_module(module_)
    let instance = @executor.instantiate_module_with_imports(
      ctx.store,
      module_,
      ctx.build_imports(),
    )
    ctx.current_module = Some(instance)
    if name is Some(name) {
      ctx.named_modules.set(name, instance)
    }
  } catch {
    @runtime.RuntimeError::UnsupportedHostCapability(detail) =>
      result.unsupported.push("line \{line}: \{detail}")
    error => {
      result.failed += 1
      result.failures.push(
        "line \{line}: module instantiation failed: \{error}",
      )
    }
  }
}

///|
fn try_instantiate_source_traps(
  ctx : CoreWastContext,
  source : @wat.WastModuleSource,
  expected : String,
) -> Bool {
  let module_ = match source {
    Binary(bytes) => @parser.parse_module(bytes) catch { _ => return false }
    Inline(module_) => module_
    Quote(parts) =>
      @wat.parse(parts.join(""), implicit_module=true) catch {
        _ => return false
      }
    FailedToParse(_) => return false
  }
  ctx.validate_core_module(module_) catch {
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
    run_wast_command(ctx, command.0, command.1, result, "", false)
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
