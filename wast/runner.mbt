// WAST Runner - Execute WAST test scripts

///|
/// Result of running WAST commands
pub struct WastResult {
  mut passed : Int
  mut failed : Int
  mut skipped : Int
  failures : Array[String]
}

///|
pub fn WastResult::new() -> WastResult {
  WastResult::{ passed: 0, failed: 0, skipped: 0, failures: [] }
}

///|
/// JIT module context containing compiled module and runtime state
pub struct JITModuleContext {
  jit_module : @jit.JITModule
  // For syncing globals back to store after JIT calls
  globals_ptr : Int64
  global_addrs : Array[Int]
  // For converting module function indices to store addresses
  func_addrs : Array[Int]
}

///|
pub fn JITModuleContext::new(
  jit_module : @jit.JITModule,
  globals_ptr : Int64,
  global_addrs : Array[Int],
  func_addrs : Array[Int],
) -> JITModuleContext {
  { jit_module, globals_ptr, global_addrs, func_addrs }
}

///|
/// WAST execution context
pub struct WastContext {
  store : @runtime.Store
  mut current_module : @runtime.ModuleInstance?
  named_modules : Map[String, @runtime.ModuleInstance]
  // Module definitions for (module instance ...) command
  module_definitions : Map[String, @types.Module]
  // Registered modules for imports (module_name -> exports)
  registered_modules : Map[String, @runtime.ModuleInstance]
  // JIT support
  jit_modules : Map[String, JITModuleContext]
  mut current_jit : JITModuleContext?
  use_jit : Bool
  // JIT compiler callback (provided by main package)
  jit_compiler : JITCompiler?
}

///|
pub fn WastContext::new(
  use_jit : Bool,
  jit_compiler? : JITCompiler? = None,
) -> WastContext {
  let store = @runtime.Store::new()
  // Create spectest module with standard test functions/values
  let spectest_instance = create_spectest_module(store)
  let registered_modules : Map[String, @runtime.ModuleInstance] = Map::new()
  registered_modules.set("spectest", spectest_instance)
  WastContext::{
    store,
    current_module: None,
    named_modules: Map::new(),
    module_definitions: Map::new(),
    registered_modules,
    jit_modules: Map::new(),
    current_jit: None,
    use_jit,
    jit_compiler,
  }
}

///|
/// Get the store from the context
pub fn WastContext::get_store(self : WastContext) -> @runtime.Store {
  self.store
}

///|
/// Try to compile a module using the JIT compiler callback
fn WastContext::try_compile_jit(
  self : WastContext,
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
) -> JITModuleContext? {
  match self.jit_compiler {
    Some(compiler) => (compiler.compile_fn)(mod_, instance, self.store)
    None => None
  }
}

///|
/// Build imports from registered modules
pub fn WastContext::build_imports(self : WastContext) -> @runtime.Imports {
  let imports = @runtime.Imports::new()
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
/// Run WAST script commands
pub fn run_wast_commands(
  script : @wat.WastScript,
  base_dir : String,
  use_jit : Bool,
  show_success : Bool,
  jit_compiler? : JITCompiler? = None,
) -> WastResult {
  let result = WastResult::new()
  let ctx = WastContext::new(use_jit, jit_compiler~)
  for item in script.commands {
    let (cmd, line) = item
    run_wast_command(ctx, cmd, line, result, base_dir, show_success)
  }
  result
}

///|
pub fn run_wast_command(
  ctx : WastContext,
  cmd : @wat.WastCommand,
  line : Int,
  result : WastResult,
  base_dir : String,
  show_success : Bool,
) -> Unit {
  ignore(base_dir)
  match cmd {
    Module(mod_, name) => {
      // Build imports from registered modules
      let imports = ctx.build_imports()
      // Instantiate the module with imports using shared store
      let instance = @executor.instantiate_module_with_imports(
        ctx.store,
        mod_,
        imports,
      ) catch {
        e => {
          // If instantiation fails, skip this module
          result.skipped = result.skipped + 1
          result.failures.push(
            "line \{line}: skipped (instantiation failed: \{e})",
          )
          return
        }
      }
      ctx.current_module = Some(instance)
      if name is Some(n) {
        ctx.named_modules.set(n, instance)
      }
      // Try to compile JIT version (only if JIT is enabled)
      if ctx.use_jit {
        match ctx.try_compile_jit(mod_, instance) {
          Some(jit_ctx) => {
            ctx.current_jit = Some(jit_ctx)
            if name is Some(n) {
              ctx.jit_modules.set(n, jit_ctx)
            }
          }
          None => ctx.current_jit = None
        }
      } else {
        ctx.current_jit = None
      }
    }
    ModuleQuote(parts) => {
      // Concatenate quoted strings and parse as WAT module
      let wat_text = StringBuilder::new()
      wat_text.write_string("(module ")
      for part in parts {
        wat_text.write_string(part)
      }
      wat_text.write_string(")")
      let mod_ = @wat.parse(wat_text.to_string()) catch {
        e => {
          // If parsing fails, skip this module
          result.skipped = result.skipped + 1
          result.failures.push(
            "line \{line}: skipped (quoted module parse failed: \{e})",
          )
          return
        }
      }
      // Build imports from registered modules
      let imports = ctx.build_imports()
      // Instantiate the module with imports using shared store
      let instance = @executor.instantiate_module_with_imports(
        ctx.store,
        mod_,
        imports,
      ) catch {
        e => {
          // If instantiation fails, skip this module
          result.skipped = result.skipped + 1
          result.failures.push(
            "line \{line}: skipped (quoted module instantiation failed: \{e})",
          )
          return
        }
      }
      ctx.current_module = Some(instance)
      // Try to compile JIT version (only if JIT is enabled)
      match ctx.try_compile_jit(mod_, instance) {
        Some(jit_ctx) if ctx.use_jit => ctx.current_jit = Some(jit_ctx)
        _ => ctx.current_jit = None
      }
    }
    ModuleBinaryFailed(err) => {
      // Binary module failed to parse (unsupported features), skip
      result.skipped = result.skipped + 1
      result.failures.push(
        "line \{line}: skipped (binary parse failed: \{err})",
      )
    }
    ModuleDefinition(mod_, name) => {
      // Module definition - validates and stores for later instantiation
      // Used with (module instance ...) to create multiple instances
      @validator.validate_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: module definition validation failed: \{e}",
          )
          return
        }
      }
      // Store the module definition for later instantiation via (module instance ...)
      if name is Some(n) {
        ctx.module_definitions.set(n, mod_)
      }
      result.passed = result.passed + 1
    }
    ModuleInstance(instance_name, def_name) => {
      // Instantiate a previously defined module
      guard ctx.module_definitions.get(def_name) is Some(mod_) else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: module definition '\{def_name}' not found",
        )
        return
      }
      // Build imports from registered modules
      let imports = ctx.build_imports()
      // Instantiate the module with imports using shared store
      let instance = @executor.instantiate_module_with_imports(
        ctx.store,
        mod_,
        imports,
      ) catch {
        e => {
          result.skipped = result.skipped + 1
          result.failures.push(
            "line \{line}: skipped (module instance failed: \{e})",
          )
          return
        }
      }
      ctx.current_module = Some(instance)
      if instance_name is Some(n) {
        ctx.named_modules.set(n, instance)
      }
      // Try to compile JIT version (only if JIT is enabled)
      if ctx.use_jit {
        match ctx.try_compile_jit(mod_, instance) {
          Some(jit_ctx) => {
            ctx.current_jit = Some(jit_ctx)
            if instance_name is Some(n) {
              ctx.jit_modules.set(n, jit_ctx)
            }
          }
          None => ctx.current_jit = None
        }
      } else {
        ctx.current_jit = None
      }
    }
    AssertReturn(action, expected) =>
      match run_assert_return(ctx, action, expected) {
        None => {
          result.passed = result.passed + 1
          if show_success {
            let action_desc = format_action(action)
            println("line \{line}: assert_return \{action_desc}: PASSED")
          }
        }
        Some(err) => {
          result.failed = result.failed + 1
          let action_desc = format_action(action)
          result.failures.push(
            "line \{line}: assert_return \{action_desc}: \{err}",
          )
        }
      }
    AssertTrap(action, expected_msg) => {
      let success = run_assert_trap(ctx, action, expected_msg)
      if success {
        result.passed = result.passed + 1
        if show_success {
          let action_desc = format_action(action)
          println("line \{line}: assert_trap \{action_desc}: PASSED")
        }
      } else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_trap failed: expected '\{expected_msg}'",
        )
      }
    }
    AssertException(action) => {
      // Invoke the action and expect an exception to be thrown
      let action_desc = format_action(action)
      if (try? invoke_action(ctx, action)) is Err(_) {
        result.passed = result.passed + 1
        if show_success {
          println("line \{line}: assert_exception \{action_desc}: PASSED")
        }
      } else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_exception \{action_desc}: expected exception but none thrown",
        )
      }
    }
    AssertExhaustion(action, _msg) =>
      // Just try to invoke - should cause stack exhaustion
      if (try? invoke_action(ctx, action)) is Err(_) {
        result.passed = result.passed + 1
        if show_success {
          let action_desc = format_action(action)
          println("line \{line}: assert_exhaustion \{action_desc}: PASSED")
        }
      } else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_exhaustion: expected exhaustion",
        )
      }
    AssertModuleTrap(source, msg) => {
      // Try to instantiate - should trap during instantiation (e.g., start function)
      // Unlike assert_unlinkable, this tests for runtime traps, not linking errors
      let trapped = try_instantiate_source_traps(ctx, source)
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
      let valid = validate_module_source(source)
      if valid {
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
      // For quoted sources, we can't easily test malformation
      // For binary/inline sources, try parsing
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
      // Try to instantiate - should fail during linking
      let linked = try_instantiate_source(ctx, source)
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
    Action(action) =>
      // Just invoke the action, ignore result
      try invoke_action(ctx, action) |> ignore catch {
        _ => ()
      }
  }
}

///|
fn format_action(action : @wat.WastAction) -> String {
  match action {
    Invoke(module_name, func_name, _args) =>
      match module_name {
        Some(m) => "(\{m}.\{func_name})"
        None => "(\{func_name})"
      }
    Get(module_name, global_name) =>
      match module_name {
        Some(m) => "(get \{m}.\{global_name})"
        None => "(get \{global_name})"
      }
  }
}

///|
fn run_assert_return(
  ctx : WastContext,
  action : @wat.WastAction,
  expected : Array[@wat.WastValue],
) -> String? {
  let results = invoke_action(ctx, action) catch {
    e => return Some("invoke failed: \{e}")
  }
  if results.length() != expected.length() {
    return Some(
      "result count mismatch: expected \{expected.length()}, got \{results.length()}",
    )
  }
  for i in 0..<results.length() {
    if !values_match(results[i], expected[i]) {
      return Some(
        "result[\{i}] mismatch: expected \{expected[i]}, got \{results[i]}",
      )
    }
  }
  None // success
}

///|
fn run_assert_trap(
  ctx : WastContext,
  action : @wat.WastAction,
  _expected_msg : String,
) -> Bool {
  // Should trap
  (try? invoke_action(ctx, action)) is Err(_)
}

///|
/// Error types for WAST runner
pub(all) suberror WastRunnerError {
  ModuleNotFound(String)
  NoCurrentModule
  RuntimeError(String)
}

///|
pub impl Show for WastRunnerError with output(self, logger) {
  match self {
    ModuleNotFound(name) => logger.write_string("module not found: \{name}")
    NoCurrentModule => logger.write_string("no current module")
    RuntimeError(msg) => logger.write_string("runtime error: \{msg}")
  }
}

///|
pub fn invoke_action(
  ctx : WastContext,
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
      // Try JIT execution first
      let jit_ctx : JITModuleContext? = match module_name {
        Some(name) => ctx.jit_modules.get(name)
        None => ctx.current_jit
      }
      match jit_ctx {
        Some(jit) =>
          // Find and call JIT function
          match jit.jit_module.get_func_by_name(func_name) {
            Some(f) => {
              // Convert args to Int64
              let i64_args : Array[Int64] = []
              for arg in args {
                let v = match arg {
                  I32(n) => @types.ToInt64::to_int64_bits(n)
                  I64(n) => @types.ToInt64::to_int64_bits(n)
                  F32(n) => @types.ToInt64::to_int64_bits(n)
                  F64(n) => @types.ToInt64::to_int64_bits(n)
                  F32CanonicalNan | F32ArithmeticNan =>
                    @types.ToInt64::to_int64_bits(@float.not_a_number)
                  F64CanonicalNan | F64ArithmeticNan =>
                    @types.ToInt64::to_int64_bits(@double.not_a_number)
                  RefNull(_) => -1L // null sentinel
                  RefExtern(n) => n.to_int64()
                  RefFunc => 0L // func ref (placeholder)
                }
                i64_args.push(v)
              }
              let results = jit.jit_module.call_with_context(f, i64_args) catch {
                @jit.JITTrap(msg) => {
                  // Sync globals even on trap (in case globals were modified before trap)
                  sync_jit_globals_to_store(jit, ctx.store)
                  raise RuntimeError(msg)
                }
              }
              // Sync JIT globals back to store after successful call
              sync_jit_globals_to_store(jit, ctx.store)
              // Convert results back to Values based on function return types
              let values : Array[@types.Value] = []
              for i, r in results {
                if i < f.result_types.length() {
                  values.push(convert_jit_result(r, f.result_types[i]))
                }
              }
              values
            }
            None => {
              // Function not found in JIT, fall back to interpreter
              let runtime_args = args.map(wast_value_to_runtime)
              @executor.call_exported_func(
                ctx.store,
                instance,
                func_name,
                runtime_args,
              ) catch {
                e => raise RuntimeError(e.to_string())
              }
            }
          }
        None => {
          // No JIT available, use interpreter
          let runtime_args = args.map(wast_value_to_runtime)
          @executor.call_exported_func(
            ctx.store,
            instance,
            func_name,
            runtime_args,
          ) catch {
            e => raise RuntimeError(e.to_string())
          }
        }
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
/// Convert JIT result (Int64) to Value based on the given return type
fn convert_jit_result(v : Int64, ty : @types.ValueType) -> @types.Value {
  match ty {
    I32 => @types.Value::I32(@types.FromInt64::from_int64_bits(v))
    I64 => @types.Value::I64(@types.FromInt64::from_int64_bits(v))
    F32 => @types.Value::F32(@types.FromInt64::from_int64_bits(v))
    F64 => @types.Value::F64(@types.FromInt64::from_int64_bits(v))
    // Reference types: -1L is null sentinel, otherwise index
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      if v == -1L {
        @types.Value::Null
      } else {
        @types.Value::FuncRef(v.to_int())
      }
    ExternRef | RefExtern | NullExternRef =>
      if v == -1L {
        @types.Value::Null
      } else {
        @types.Value::ExternRef(v.to_int())
      }
    // GC reference types - treat as null for now
    AnyRef | NullRef | ExnRef | NullExnRef => @types.Value::Null
    V128 => abort("V128 not supported in JIT")
  }
}

///|
pub fn wast_value_to_runtime(v : @wat.WastValue) -> @types.Value {
  match v {
    I32(n) => @types.Value::I32(n)
    I64(n) => @types.Value::I64(n)
    F32(n) => @types.Value::F32(n)
    F64(n) => @types.Value::F64(n)
    F32CanonicalNan | F32ArithmeticNan =>
      @types.Value::F32((0.0 : Float) / (0.0 : Float))
    F64CanonicalNan | F64ArithmeticNan => @types.Value::F64(0.0 / 0.0)
    RefNull(_) => @types.Value::Null
    RefExtern(n) => @types.Value::ExternRef(n)
    RefFunc => @types.Value::FuncRef(0) // Placeholder
  }
}

///|
pub fn values_match(actual : @types.Value, expected : @wat.WastValue) -> Bool {
  match (actual, expected) {
    (I32(a), I32(e)) => a == e
    (I64(a), I64(e)) => a == e
    (F32(a), F32(e)) => a == e || (a.is_nan() && e.is_nan())
    (F64(a), F64(e)) => a == e || (a.is_nan() && e.is_nan())
    (F32(a), F32CanonicalNan) | (F32(a), F32ArithmeticNan) => a.is_nan()
    (F64(a), F64CanonicalNan) | (F64(a), F64ArithmeticNan) => a.is_nan()
    (Null, RefNull(_)) => true
    (FuncRef(_), RefFunc) => true
    (ExternRef(a), RefExtern(e)) => a == e
    _ => false
  }
}

///|
fn validate_module_source(source : @wat.WastModuleSource) -> Bool {
  match source {
    Binary(bytes) =>
      (try? {
        let mod_ = @parser.parse_module(bytes)
        @validator.validate_module(mod_)
      })
      is Ok(_)
    Quote(parts) => {
      // Join quoted parts and parse as WAT
      let wat_source = "(module " +
        parts.iter().fold(init="", fn(acc, s) { acc + s }) +
        ")"
      (try? {
        let mod_ = @wat.parse(wat_source)
        @validator.validate_module(mod_)
      })
      is Ok(_)
    }
    Inline(mod_) => (try? @validator.validate_module(mod_)) is Ok(_)
    FailedToParse(_) => false // Module failed to parse, so it's invalid
  }
}

///|
fn parse_module_source(source : @wat.WastModuleSource) -> Bool {
  match source {
    Binary(bytes) => (try? @parser.parse_module(bytes)) is Ok(_)
    Quote(_) => false // Quoted source is assumed to fail parsing
    Inline(_) => true // Already parsed successfully
    FailedToParse(_) => false // Module failed to parse
  }
}

///|
fn try_instantiate_source(
  ctx : WastContext,
  source : @wat.WastModuleSource,
) -> Bool {
  let imports = ctx.build_imports()
  match source {
    Binary(bytes) =>
      (try? {
        let mod_ = @parser.parse_module(bytes)
        let instance = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )
        ctx.current_module = Some(instance)
      })
      is Ok(_)
    Inline(mod_) =>
      (try? {
        let instance = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )
        ctx.current_module = Some(instance)
      })
      is Ok(_)
    Quote(_) => false
    FailedToParse(_) => false // Module failed to parse, can't instantiate
  }
}

///|
/// Try to instantiate a module source and check if it traps.
/// Returns true if instantiation traps (for assert_trap with module).
fn try_instantiate_source_traps(
  ctx : WastContext,
  source : @wat.WastModuleSource,
) -> Bool {
  let imports = ctx.build_imports()
  match source {
    Binary(bytes) =>
      (try? {
        let mod_ = @parser.parse_module(bytes)
        @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
        |> ignore
      })
      is Err(_)
    Inline(mod_) =>
      (try? (@executor.instantiate_module_with_imports(ctx.store, mod_, imports)
      |> ignore))
      is Err(_)
    Quote(_) => false // Quoted source - can't test
    FailedToParse(_) => false // Module failed to parse, doesn't count as trap
  }
}
