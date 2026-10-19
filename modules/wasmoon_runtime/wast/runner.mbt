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
/// Build imports from registered modules
pub fn CoreWastContext::build_imports(
  self : CoreWastContext,
) -> @runtime.Imports {
  let imports = @runtime.Imports::Imports(self.store)
  for entry in self.registered_modules.iter() {
    let (mod_name, instance) = entry
    // Add all exports from this module as imports
    for exp in instance.exports {
      match exp.desc {
        Func(func_idx) => {
          let addr = instance.func_addrs[func_idx]
          imports.add_func(mod_name, exp.name, addr)
        }
        Memory(mem_idx) => {
          let addr = instance.mem_addrs[mem_idx]
          imports.add_memory(mod_name, exp.name, addr)
        }
        Table(table_idx) => {
          let addr = instance.table_addrs[table_idx]
          imports.add_table(mod_name, exp.name, addr)
        }
        Global(global_idx) => {
          let addr = instance.global_addrs[global_idx]
          imports.add_global(mod_name, exp.name, addr)
        }
        Tag(tag_idx) => {
          let addr = instance.tag_addrs[tag_idx]
          imports.add_tag(mod_name, exp.name, addr)
        }
      }
    }
  }
  imports
}

///|
pub fn run_wast_command(
  ctx : CoreWastContext,
  cmd : @wat.WastCommand,
  line : Int32,
  result : WastResult,
  base_dir : String,
  show_success : Bool,
) -> Unit {
  ignore(base_dir)
  if ctx.closed {
    result.failed += 1
    result.failures.push("line \{line}: WAST context is closed")
    return
  }
  match cmd {
    Module(mod_, name) => run_wast_module(ctx, mod_, name, line, result)
    ModuleQuote(parts) => {
      let mod_ = @wat.parse(parts.join(""), implicit_module=true) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push("line \{line}: quoted module parse failed: \{e}")
          return
        }
      }
      run_wast_module(ctx, mod_, None, line, result)
    }
    ModuleBinaryFailed(err) => {
      result.failed = result.failed + 1
      result.failures.push("line \{line}: binary parse failed: \{err}")
    }
    ModuleDefinition(mod_, name) => {
      // Module definition - validates and stores for later instantiation
      // Used with (module instance ...) to create multiple instances
      ctx.validate_core_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: module definition validation failed: \{e}",
          )
          return
        }
      }
      ctx.current_definition = Some(mod_)
      // Store the module definition for later instantiation via (module instance ...)
      if name is Some(n) {
        ctx.module_definitions.set(n, mod_)
      }
      result.passed = result.passed + 1
    }
    ModuleInstance(instance_name, def_name) => {
      // Instantiate a previously defined module
      let definition = match def_name {
        Some(name) => ctx.module_definitions.get(name)
        None => ctx.current_definition
      }
      guard definition is Some(mod_) else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: module definition '\{def_name.unwrap_or("<latest>")}' not found",
        )
        return
      }
      run_wast_module(ctx, mod_, instance_name, line, result)
    }
    AssertReturn(action, _)
    | AssertTrap(action, _)
    | AssertSuspension(action, _)
    | AssertException(action)
    | AssertExhaustion(action, _)
    | Action(action) => {
      let outcome = try invoke_action(ctx, action) catch {
        error => Err(error)
      } noraise {
        values => Ok(values)
      }
      if outcome is Err(UnsupportedCapability(detail)) {
        result.unsupported.push("line \{line}: \{detail}")
        return
      }
      finish_wast_action(ctx, cmd, action, line, result, show_success, outcome)
    }
    AssertModuleTrap(source, msg) => {
      // Try to instantiate - should trap during instantiation (e.g., start function)
      // Unlike assert_unlinkable, this tests for runtime traps, not linking errors
      let trapped = try_instantiate_source_traps(ctx, source, msg)
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
      let invalid = @assertions.module_is_invalid(
        source,
        bulk_memory=true,
        stack_switching=ctx.stack_switching,
      ) catch {
        UnsupportedCapability(detail) => {
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
      let parsed = parse_module_source(source)
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
      let linked = try_instantiate_source(ctx, source) catch {
        UnsupportedCapability(detail) => {
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
      // Register module for imports
      let inst : @runtime.ModuleInstance? = match module_name {
        Some(n) =>
          match ctx.named_modules.get(n) {
            Some(i) => Some(i)
            None => ctx.current_module
          }
        None => ctx.current_module
      }
      if inst is Some(i) {
        ctx.registered_modules.set(name, i)
        // Also add to named_modules for later reference
        ctx.named_modules.set(name, i)
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
  ctx : CoreWastContext,
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
  let instance = match module_name {
    Some(name) => ctx.named_modules.get(name)
    None => ctx.current_module
  }
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
fn[T] succeeds(body : () -> T raise) -> Bool {
  try body() catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn parse_module_source(source : @wat.WastModuleSource) -> Bool {
  match source {
    Binary(bytes) => succeeds(() => @parser.parse_module(bytes))
    Quote(parts) =>
      succeeds(() => @wat.parse(parts.join(""), implicit_module=true))
    Inline(_) => true // Already parsed successfully
    FailedToParse(_) => false // Module failed to parse
  }
}

///|
fn try_instantiate_source(
  ctx : CoreWastContext,
  source : @wat.WastModuleSource,
) -> Bool raise WastRunnerError {
  // A build failure cannot satisfy an assertion about instantiation. The
  // pinned adapter does include start-function traps in instantiation errors.
  let mod_ = try {
    match source {
      Binary(bytes) => @parser.parse_module(bytes)
      Quote(parts) => @wat.parse(parts.join(""), implicit_module=true)
      Inline(mod_) => mod_
      FailedToParse(message) => raise WastRunnerError::RuntimeError(message)
    }
  } catch {
    error => raise RuntimeError("module parsing failed: \{error}")
  }
  ctx.validate_core_module(mod_) catch {
    error => raise RuntimeError("module validation failed: \{error}")
  }
  let imports = ctx.build_imports()
  try {
    @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
    |> ignore
    true
  } catch {
    UnsupportedHostCapability(detail) => raise UnsupportedCapability(detail)
    _ => false
  }
}

///|
fn CoreWastContext::validate_core_module(
  self : CoreWastContext,
  module_ : @types.Module,
) -> Unit raise {
  @validator.validate_module(
    module_,
    bulk_memory=true,
    stack_switching=self.stack_switching,
  )
  @executor.validate_continuation_gc_storage(module_)
}

///|
pub fn invoke_action(
  ctx : CoreWastContext,
  action : @wat.WastAction,
) -> Array[@types.Value] raise WastRunnerError {
  match action {
    Invoke(module_name, func_name, args) => {
      // Get instance for validation
      let instance = match module_name {
        Some(name) =>
          match ctx.named_modules.get(name) {
            Some(inst) => inst
            None => raise ModuleNotFound(name)
          }
        None =>
          match ctx.current_module {
            Some(inst) => inst
            None => raise NoCurrentModule
          }
      }
      let runtime_args = args.map(value => {
        wast_value_to_runtime(value, func_addrs=instance.func_addrs)
      })
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
        ctx.store,
        instance,
        index,
        runtime_args,
      ) catch {
        error => raise classify_runtime_failure(error)
      }
      match outcome {
        Returned(values) => values
        Thrown(_, _) => raise GuestException
        HostFailed(error) => raise RuntimeError(error.to_string())
      }
    }
    Get(module_name, global_name) => {
      let instance = match module_name {
        Some(name) =>
          match ctx.named_modules.get(name) {
            Some(inst) => inst
            None => raise ModuleNotFound(name)
          }
        None =>
          match ctx.current_module {
            Some(inst) => inst
            None => raise NoCurrentModule
          }
      }
      let value = @executor.get_exported_global(
        ctx.store,
        instance,
        global_name,
      ) catch {
        e => raise RuntimeError(e.to_string())
      }
      [value]
    }
  }
}

///|
/// Check an already completed action without invoking guest code again.
fn finish_wast_action(
  ctx : CoreWastContext,
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
      check_assert_return(ctx, action, expected, values)
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
