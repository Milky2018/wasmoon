///|
/// Result of running WAST commands
pub struct WastResult {
  mut passed : Int32
  mut failed : Int32
  skipped : Int32
  failures : Array[String]
  unsupported : Array[String]
}

///|
pub fn WastResult::WastResult() -> WastResult {
  { passed: 0, failed: 0, skipped: 0, failures: [], unsupported: [], }
}

///|
pub fn WastResult::record_pass(self : WastResult) -> Unit {
  self.passed += 1
}

///|
pub fn WastResult::record_failure(self : WastResult, message : String) -> Unit {
  self.failed += 1
  self.failures.push(message)
}

///|
pub(open) trait WastEngine {
  fn modules(Self) -> WastModules
  fn store(Self) -> @runtime.Store
  fn closed(Self) -> Bool
  fn instantiate(Self, @types.Module, String?) -> Unit raise
  fn validate(Self, @types.Module) -> Unit raise
  fn invoke(Self, @wat.WastAction) -> Array[@types.Value] raise WastRunnerError
  fn source_is_invalid(Self, @wat.WastModuleSource, String) -> Bool raise WastRunnerError
  fn source_traps(Self, @wat.WastModuleSource, String) -> Bool
  fn registered(Self, String) -> Unit
}

///|
fn[E : WastEngine] instantiate_command(
  engine : E,
  module_ : @types.Module,
  name : String?,
  line : Int32,
  result : WastResult,
  track_unsupported : Bool,
) -> Unit {
  engine.instantiate(module_, name) catch {
    @runtime.RuntimeError::UnsupportedHostCapability(detail) if track_unsupported =>
      result.unsupported.push("line \{line}: \{detail}")
    error =>
      result.record_failure(
        "line \{line}: module instantiation failed: \{error}",
      )
  }
}

///|
pub fn[E : WastEngine] execute_command(
  engine : E,
  cmd : @wat.WastCommand,
  line : Int32,
  result : WastResult,
  show_success : Bool,
  track_unsupported~ : Bool = false,
) -> Unit {
  if engine.closed() {
    result.failed += 1
    result.failures.push("line \{line}: WAST context is closed")
    return
  }
  let modules = engine.modules()
  match cmd {
    Module(mod_, name) =>
      instantiate_command(engine, mod_, name, line, result, track_unsupported)
    ModuleQuote(parts) => {
      let mod_ = @wat.parse(parts.join(""), implicit_module=true) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push("line \{line}: quoted module parse failed: \{e}")
          return
        }
      }
      instantiate_command(engine, mod_, None, line, result, track_unsupported)
    }
    ModuleBinaryFailed(err) => {
      result.failed = result.failed + 1
      result.failures.push("line \{line}: binary parse failed: \{err}")
    }
    ModuleDefinition(mod_, name) => {
      // Module definition - validates and stores for later instantiation
      // Used with (module instance ...) to create multiple instances
      engine.validate(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: module definition validation failed: \{e}",
          )
          return
        }
      }
      modules.record_definition(mod_, name)
      result.passed = result.passed + 1
    }
    ModuleInstance(instance_name, def_name) => {
      // Instantiate a previously defined module
      let definition = modules.definition(def_name)
      guard definition is Some(mod_) else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: module definition '\{def_name.unwrap_or("<latest>")}' not found",
        )
        return
      }
      instantiate_command(
        engine, mod_, instance_name, line, result, track_unsupported,
      )
    }
    AssertReturn(action, _)
    | AssertTrap(action, _)
    | AssertSuspension(action, _)
    | AssertException(action)
    | AssertExhaustion(action, _)
    | Action(action) => {
      let outcome = try engine.invoke(action) catch {
        error => Err(error)
      } noraise {
        values => Ok(values)
      }
      if track_unsupported && outcome is Err(UnsupportedCapability(detail)) {
        result.unsupported.push("line \{line}: \{detail}")
        return
      }
      finish_action(modules, cmd, action, line, result, show_success, outcome)
    }
    AssertModuleTrap(source, msg) => {
      // Try to instantiate - should trap during instantiation (e.g., start function)
      // Unlike assert_unlinkable, this tests for runtime traps, not linking errors
      let trapped = engine.source_traps(source, msg)
      if trapped {
        result.passed = result.passed + 1
        if show_success {
          println("line \{line}: assert_trap (module): PASSED")
        }
      } else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_trap (module): expected trap during instantiation (expected: \{msg})",
        )
      }
    }
    AssertInvalid(source, msg) => {
      let invalid = engine.source_is_invalid(source, msg) catch {
        UnsupportedCapability(detail) if track_unsupported => {
          result.unsupported.push("line \{line}: \{detail}")
          return
        }
        error => {
          result.failed += 1
          result.failures.push("line \{line}: assert_invalid: \{error}")
          return
        }
      }
      if !invalid {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_invalid: module should have been invalid (expected: \{msg})",
        )
      } else {
        result.passed = result.passed + 1
        if show_success {
          println("line \{line}: assert_invalid: PASSED")
        }
      }
    }
    AssertMalformed(source, msg) => {
      let parsed = try @assertions.parse_module_source(source) catch {
        _ => false
      } noraise {
        _ => true
      }
      if parsed {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_malformed: module should have been malformed (expected: \{msg})",
        )
      } else {
        result.passed = result.passed + 1
        if show_success {
          println("line \{line}: assert_malformed: PASSED")
        }
      }
    }
    AssertUnlinkable(source, msg) => {
      let linked = try_instantiate_source(engine, source, track_unsupported) catch {
        UnsupportedCapability(detail) if track_unsupported => {
          result.unsupported.push("line \{line}: \{detail}")
          return
        }
        error => {
          result.failed += 1
          result.failures.push(
            "line \{line}: assert_unlinkable: module must build before linking: \{error}",
          )
          return
        }
      }
      if linked {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_unlinkable: module should have been unlinkable (expected: \{msg})",
        )
      } else {
        result.passed = result.passed + 1
        if show_success {
          println("line \{line}: assert_unlinkable: PASSED")
        }
      }
    }
    Register(name, module_name) => {
      let instance = match modules.instance(module_name) {
        Some(instance) => Some(instance)
        None => modules.instance(None)
      }
      if instance is Some(instance) {
        modules.register(name, instance)
        engine.registered(name)
      }
    }
    Thread(_, _, _) | Wait(_) => {
      result.failed += 1
      result.failures.push(
        "line \{line}: thread directives require a complete WAST script",
      )
    }
  }
}

///|
fn check_assert_return(
  modules : WastModules,
  action : @wat.WastAction,
  expected : Array[@wat.WastValue],
  results : Array[@types.Value],
) -> String? {
  if results.length() != expected.length() {
    return Some(
      "result count mismatch: expected \{expected.length()}, got \{results.length()}",
    )
  }
  let module_name = match action {
    Invoke(name, _, _) | Get(name, _) => name
  }
  let instance = modules.instance(module_name)
  let func_addrs = match instance {
    Some(instance) => instance.func_addrs
    None => []
  }
  for i in 0..<results.length() {
    if !values_match(results[i], expected[i], func_addrs~) {
      return Some(
        "result[\{i}] mismatch: expected \{expected[i]}, got \{results[i]}",
      )
    }
  }
  None // success
}

///|
fn[E : WastEngine] try_instantiate_source(
  engine : E,
  source : @wat.WastModuleSource,
  track_unsupported : Bool,
) -> Bool raise WastRunnerError {
  // Parse and validation failures cannot satisfy an instantiation assertion.
  let module_ = @assertions.parse_module_source(source)
  engine.validate(module_) catch {
    error => raise RuntimeError("module validation failed: \{error}")
  }
  let store = engine.store()
  try
    @executor.instantiate_module_with_imports(
      store,
      module_,
      engine.modules().build_imports(store),
    )
  catch {
    UnsupportedHostCapability(detail) if track_unsupported =>
      raise UnsupportedCapability(detail)
    _ => false
  } noraise {
    _ => true
  }
}

///|
pub fn invoke_script_action(
  store : @runtime.Store,
  modules : WastModules,
  action : @wat.WastAction,
  invoke_native? : (
    String?,
    @runtime.ModuleInstance,
    String,
    Array[@types.Value],
  ) -> Array[@types.Value]? raise WastRunnerError,
) -> Array[@types.Value] raise WastRunnerError {
  let name = match action {
    Invoke(name, _, _) | Get(name, _) => name
  }
  guard modules.instance(name) is Some(instance) else {
    match name {
      Some(name) => raise ModuleNotFound(name)
      None => raise NoCurrentModule
    }
  }
  match action {
    Invoke(module_name, func_name, args) => {
      // Get instance for validation
      let runtime_args = args.map(value => {
        wast_value_to_runtime(value, func_addrs=instance.func_addrs)
      })
      if invoke_native is Some(invoke) &&
        invoke(module_name, instance, func_name, runtime_args) is Some(values) {
        return values
      }
      let mut func_idx = None
      for export_ in instance.exports {
        if export_.name == func_name && export_.desc is Func(index) {
          func_idx = Some(index)
          break
        }
      }
      guard func_idx is Some(index) else {
        raise RuntimeError("unknown exported function: \{func_name}")
      }
      let outcome = @executor.call_func_by_index_with_exception(
        store, instance, index, runtime_args,
      ) catch {
        error => raise classify_runtime_failure(error)
      }
      match outcome {
        Returned(values) => values
        Thrown(_, _) => raise GuestException
        HostFailed(error) => raise RuntimeError(error.to_string())
      }
    }
    Get(_, global_name) => {
      let value = @executor.get_exported_global(store, instance, global_name) catch {
        e => raise RuntimeError(e.to_string())
      }
      [value]
    }
  }
}

///|
/// Check an already completed action without invoking guest code again.
pub fn finish_action(
  modules : WastModules,
  command : @wat.WastCommand,
  action : @wat.WastAction,
  line : Int32,
  result : WastResult,
  show_success : Bool,
  outcome : Result[Array[@types.Value], WastRunnerError],
) -> Unit {
  let description = @assertions.format_action(action)
  let return_failure = match (command, outcome) {
    (AssertReturn(_, expected), Ok(values)) =>
      check_assert_return(modules, action, expected, values)
    _ => None
  }
  let (label, failure) = @assertions.check_action_outcome(
    command, action, outcome, return_failure,
  )
  match failure {
    Some(message) => {
      result.failed += 1
      result.failures.push("line \{line}: \{label}: \{message}")
    }
    None =>
      if !(command is Action(_)) {
        result.passed += 1
        if show_success {
          let success_label = if command is AssertTrap(_, _) {
            "assert_trap \{description}"
          } else {
            label
          }
          println("line \{line}: \{success_label}: PASSED")
        }
      }
  }
}
