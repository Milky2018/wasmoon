// WAST Runner - Execute WAST test scripts

// Reference encoding constants - re-exported from @types for convenience

///|
pub const NULL_REF : Int64 = @wasm_milkir.NULL_REF

///|
pub const EXTERNREF_TAG : Int64 = @wasm_milkir.EXTERNREF_TAG

///|
pub const FUNCREF_TAG : Int64 = @wasm_milkir.FUNCREF_TAG

///|
/// Result of running WAST commands
pub struct WastResult {
  mut passed : Int
  mut failed : Int
  skipped : Int
  failures : Array[String]
}

///|
pub fn WastResult::WastResult() -> WastResult {
  { passed: 0, failed: 0, skipped: 0, failures: [], }
}

///|
priv struct ImportedWasmCallContinuation {
  func_addr : Int
  continuation : @executor.ExecutionContinuation
}

///|
/// JIT module context containing compiled module and runtime state
pub struct JITModuleContext {
  jit_module : @jit.JITModule
  // For syncing globals back to store after JIT calls
  globals_ptr : Int64
  global_addrs : Array[Int]
  // Tables owned/imported by this module instance
  table_addrs : Array[Int]
  // For converting module function indices to store addresses
  func_addrs : Array[Int]
  // Function type indices in module index space (imports + locals)
  func_type_indices : Array[Int]
  // Module canonical type indices
  canonical_type_indices : Array[Int]
  // Module-local type graph used by GC type checks
  module_types : Array[@types.SubType]
  module_rec_groups : Array[Int]
  // Whether this module uses subtype helper for call_indirect checks
  use_subtype_indirect_check : Bool
  priv async_host_drivers : Map[Int64, @runtime.AsyncHostCallDriver]
  priv async_host_errors : Map[Int64, @runtime.RuntimeError]
  priv imported_wasm_continuations : Map[Int64, ImportedWasmCallContinuation]
}

///|
pub fn JITModuleContext::JITModuleContext(
  jit_module : @jit.JITModule,
  globals_ptr : Int64,
  global_addrs : Array[Int],
  table_addrs : Array[Int],
  func_addrs : Array[Int],
  func_type_indices : Array[Int],
  canonical_type_indices : Array[Int],
  module_types : Array[@types.SubType],
  module_rec_groups : Array[Int],
  use_subtype_indirect_check : Bool,
) -> JITModuleContext {
  {
    jit_module,
    globals_ptr,
    global_addrs,
    table_addrs,
    func_addrs,
    func_type_indices,
    canonical_type_indices,
    module_types,
    module_rec_groups,
    use_subtype_indirect_check,
    async_host_drivers: Map([]),
    async_host_errors: Map([]),
    imported_wasm_continuations: Map([]),
  }
}

///|
/// Release the native module after every call and continuation has ended.
pub fn JITModuleContext::close(self : JITModuleContext) -> Unit {
  self.jit_module.close()
}

///|
/// Modules that have built-in JIT trampolines
pub fn builtin_jit_modules() -> Array[String] {
  ["spectest", "wasi_snapshot_preview1"]
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
  // Built-in modules that have been overridden by Register command
  // JIT cannot use trampolines for these since they've been replaced
  overridden_builtin_modules : @hashset.HashSet[String]
  // JIT support
  jit_modules : Map[String, JITModuleContext]
  mut current_jit : JITModuleContext?
  use_jit : Bool
  // JIT compiler callback (provided by main package)
  jit_compiler : JITCompiler?
  // WASI context (for WASI function support in tests)
  wasi_ctx : @wasi.WasiContext
}

///|
pub fn WastContext::WastContext(
  use_jit : Bool,
  jit_compiler? : JITCompiler? = None,
) -> WastContext {
  // Use c_heap when JIT is enabled for GC support
  let store = if use_jit { @runtime.Store::with_c_heap() } else { Store() }

  // Create WASI context with default configuration for tests
  let wasi_builder = @wasi.WasiContextBuilder::WasiContextBuilder()
  wasi_builder.inherit_stdin() |> ignore
  wasi_builder.inherit_stdout() |> ignore
  wasi_builder.inherit_stderr() |> ignore
  let wasi_ctx = wasi_builder.build()

  // Create spectest module with standard test functions/values
  let spectest_instance = try! create_spectest_module(store)

  // Create WASI module using Linker (to reuse wasi::register_wasi)
  let linker = @runtime.Linker::with_store(store)
  // Register spectest with linker so WASI functions can use it if needed
  try! linker.register("spectest", spectest_instance)
  // Register all WASI functions - this creates the wasi_snapshot_preview1 module
  try! @wasi.register_wasi(linker, wasi_ctx)
  // Get the WASI module instance that was created by register_wasi
  let wasi_instance = match linker.get_module("wasi_snapshot_preview1") {
    Some(instance) => instance
    None => ModuleInstance() // Fallback: shouldn't happen
  }
  let registered_modules : Map[String, @runtime.ModuleInstance] = Map([])
  registered_modules.set("spectest", spectest_instance)
  registered_modules.set("wasi_snapshot_preview1", wasi_instance)
  {
    store,
    current_module: None,
    named_modules: Map([]),
    module_definitions: Map([]),
    registered_modules,
    overridden_builtin_modules: HashSet([]),
    jit_modules: Map([]),
    current_jit: None,
    use_jit,
    jit_compiler,
    wasi_ctx,
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
) -> Result[JITModuleContext, String] {
  if !self.use_jit {
    return Err("JIT is disabled")
  }
  match self.jit_compiler {
    Some(compiler) => (compiler.compile_fn)(mod_, instance, self.store)
    None => Err("WAST JIT strict mode: JIT compiler callback is missing")
  }
}

///|
/// Build imports from registered modules
pub fn WastContext::build_imports(self : WastContext) -> @runtime.Imports {
  let imports = @runtime.Imports::Imports()
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
  let result = WastResult::WastResult()
  let ctx = WastContext::WastContext(use_jit, jit_compiler~)
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
      @validator.validate_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push("line \{line}: module validation failed: \{e}")
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
          result.failed = result.failed + 1
          result.failures.push("line \{line}: instantiation failed: \{e}")
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
          Ok(jit_ctx) => {
            ctx.current_jit = Some(jit_ctx)
            if name is Some(n) {
              ctx.jit_modules.set(n, jit_ctx)
            }
          }
          Err(err) => {
            ctx.current_jit = None
            if name is Some(n) {
              ctx.jit_modules.remove(n) |> ignore
            }
            result.failed = result.failed + 1
            result.failures.push(
              "line \{line}: JIT module compile failed: \{err}",
            )
            return
          }
        }
      } else {
        ctx.current_jit = None
      }
    }
    ModuleQuote(parts) => {
      // Concatenate quoted strings and parse as WAT module
      let wat_text = StringBuilder::StringBuilder()
      wat_text.write_string("(module ")
      for part in parts {
        wat_text.write_string(part)
      }
      wat_text.write_string(")")
      let mod_ = @wat.parse(wat_text.to_string()) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push("line \{line}: quoted module parse failed: \{e}")
          return
        }
      }
      @validator.validate_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: quoted module validation failed: \{e}",
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
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: quoted module instantiation failed: \{e}",
          )
          return
        }
      }
      ctx.current_module = Some(instance)
      // Try to compile JIT version (only if JIT is enabled)
      if ctx.use_jit {
        match ctx.try_compile_jit(mod_, instance) {
          Ok(jit_ctx) => ctx.current_jit = Some(jit_ctx)
          Err(err) => {
            ctx.current_jit = None
            result.failed = result.failed + 1
            result.failures.push(
              "line \{line}: JIT quoted module compile failed: \{err}",
            )
            return
          }
        }
      } else {
        ctx.current_jit = None
      }
    }
    ModuleBinaryFailed(err) => {
      result.failed = result.failed + 1
      result.failures.push("line \{line}: binary parse failed: \{err}")
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
      @validator.validate_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: module instance validation failed: \{e}",
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
          result.failed = result.failed + 1
          result.failures.push("line \{line}: module instance failed: \{e}")
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
          Ok(jit_ctx) => {
            ctx.current_jit = Some(jit_ctx)
            if instance_name is Some(n) {
              ctx.jit_modules.set(n, jit_ctx)
            }
          }
          Err(err) => {
            ctx.current_jit = None
            if instance_name is Some(n) {
              ctx.jit_modules.remove(n) |> ignore
            }
            result.failed = result.failed + 1
            result.failures.push(
              "line \{line}: JIT module instance compile failed: \{err}",
            )
            return
          }
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
      try invoke_action(ctx, action) catch {
        _ => {
          result.passed = result.passed + 1
          if show_success {
            println("line \{line}: assert_exception \{action_desc}: PASSED")
          }
        }
      } noraise {
        values => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: assert_exception \{action_desc}: expected exception but none thrown (returned \{Repr(values)})",
          )
        }
      }
    }
    AssertExhaustion(action, expected_msg) => {
      // Try to invoke - should cause stack exhaustion with matching message
      let action_desc = format_action(action)
      try invoke_action(ctx, action) catch {
        e => {
          let err_str = e.to_string()
          if err_str.contains(expected_msg) {
            result.passed = result.passed + 1
            if show_success {
              println("line \{line}: assert_exhaustion \{action_desc}: PASSED")
            }
          } else {
            result.failed = result.failed + 1
            result.failures.push(
              "line \{line}: assert_exhaustion \{action_desc}: expected '\{expected_msg}', got '\{err_str}'",
            )
          }
        }
      } noraise {
        _ => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: assert_exhaustion \{action_desc}: expected exhaustion but succeeded",
          )
        }
      }
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
        // Track if this overrides a built-in JIT module
        // JIT cannot use built-in trampolines for overridden modules
        for builtin in builtin_jit_modules() {
          if name == builtin {
            ctx.overridden_builtin_modules.add(name)
          }
        }
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
  !succeeds(() => invoke_action(ctx, action))
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
/// Error types for WAST runner
pub(all) suberror WastRunnerError {
  ModuleNotFound(String)
  NoCurrentModule
  RuntimeError(String)
}

///|
pub impl Show for WastRunnerError with fn output(self, logger) {
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
              // Convert args to Int64.
              // V128 uses two slots: low 8 bytes, then high 8 bytes.
              let i64_args : Array[Int64] = []
              for arg in args {
                match arg {
                  I32(n) => i64_args.push(@types.ToInt64::to_int64_bits(n))
                  I64(n) => i64_args.push(@types.ToInt64::to_int64_bits(n))
                  F32(n) => i64_args.push(@types.ToInt64::to_int64_bits(n))
                  F64(n) => i64_args.push(@types.ToInt64::to_int64_bits(n))
                  F32CanonicalNan | F32ArithmeticNan =>
                    i64_args.push(
                      @types.ToInt64::to_int64_bits(@float.not_a_number),
                    )
                  F64CanonicalNan | F64ArithmeticNan =>
                    i64_args.push(
                      @types.ToInt64::to_int64_bits(@double.not_a_number),
                    )
                  RefNull(_) => i64_args.push(NULL_REF)
                  // Externref uses special encoding: EXTERNREF_TAG | (host_idx << 1)
                  RefExtern(n) =>
                    i64_args.push(@wasmoon_jit.encode_externref(n))
                  RefHost(n) => i64_args.push(@wasmoon_jit.encode_externref(n))
                  RefFunc => i64_args.push(NULL_REF) // placeholder
                  RefExternAny => i64_args.push(NULL_REF) // placeholder
                  // GC reference types - these shouldn't appear as args but handle them
                  RefArray | RefStruct | RefEq | RefI31 | RefAny =>
                    i64_args.push(NULL_REF)
                  // V128: push 16 bytes as two Int64 (low then high) in little-endian
                  V128(bytes) => {
                    let low = @types.bytes_to_int64_le(bytes, 0)
                    i64_args.push(low)
                    let high = @types.bytes_to_int64_le(bytes, 8)
                    i64_args.push(high)
                  }
                  V128Pattern(_) =>
                    abort("V128Pattern not valid as JIT argument")
                  Either(_) => abort("Either not valid as JIT argument")
                }
              }
              // Set up GC heap for JIT execution if c_heap is available
              let mut temp_gc_func_table_ptr = 0L
              match ctx.store.c_heap {
                Some(heap) => {
                  // Compute canonical type indices for proper type equivalence checking
                  let canonical = @types.compute_canonical_type_indices(
                    jit.module_types,
                    type_rec_groups=jit.module_rec_groups,
                  )
                  let jit_func_type_indices : Array[Int] = []
                  for i, func_addr in jit.func_addrs {
                    if i >= 0 && i < jit.func_type_indices.length() {
                      let raw_type_idx = jit.func_type_indices[i]
                      if raw_type_idx >= 0 &&
                        raw_type_idx < jit.canonical_type_indices.length() {
                        jit_func_type_indices.push(
                          jit.canonical_type_indices[raw_type_idx],
                        )
                      } else {
                        jit_func_type_indices.push(raw_type_idx)
                      }
                    } else if func_addr >= 0 &&
                      func_addr < ctx.store.func_type_indices.length() {
                      let fallback_canonical = ctx.store.get_func_canonical_type_idx(
                        func_addr,
                      )
                      if fallback_canonical >= 0 {
                        jit_func_type_indices.push(fallback_canonical)
                      } else {
                        jit_func_type_indices.push(
                          ctx.store.func_type_indices[func_addr],
                        )
                      }
                    } else {
                      jit_func_type_indices.push(-1) // Invalid/unknown type
                    }
                  }
                  let gc_func_type_indices : Array[Int] = []
                  for type_idx in jit_func_type_indices {
                    gc_func_type_indices.push(type_idx)
                  }
                  let merged_funcref_types : Map[Int64, Int] = Map([])
                  for func_idx, _func_addr in jit.func_addrs {
                    let func_ptr = jit.jit_module.get_func_ptr(func_idx)
                    if func_ptr == 0L {
                      continue
                    }
                    if func_idx >= 0 && func_idx < gc_func_type_indices.length() {
                      merged_funcref_types.set(
                        func_ptr,
                        gc_func_type_indices[func_idx],
                      )
                    }
                  }
                  let registered_funcref_entries = collect_registered_funcref_entries(
                    ctx.store,
                  )
                  for entry in registered_funcref_entries {
                    let (func_ptr, type_idx) = entry
                    if merged_funcref_types.get(func_ptr) is None {
                      merged_funcref_types.set(func_ptr, type_idx)
                    }
                  }
                  let gc_funcref_entries : Array[(Int64, Int)] = []
                  for func_ptr, type_idx in merged_funcref_types {
                    gc_funcref_entries.push((func_ptr, type_idx))
                  }
                  if gc_funcref_entries.length() > 0 {
                    let table_size = (gc_funcref_entries.length() * 8).to_int64()
                    let table_ptr = @wasmoon_jit.alloc_memory(table_size)
                    if table_ptr != 0L {
                      temp_gc_func_table_ptr = table_ptr
                      gc_func_type_indices.clear()
                      for i, entry in gc_funcref_entries {
                        let (func_ptr, type_idx) = entry
                        @wasmoon_jit.native_value_slot_write(
                          table_ptr, i, func_ptr,
                        )
                        gc_func_type_indices.push(type_idx)
                      }
                    }
                  }
                  try {
                    if temp_gc_func_table_ptr != 0L {
                      jit.jit_module.setup_gc_with_func_table(
                        heap,
                        jit.module_types,
                        canonical,
                        gc_func_type_indices,
                        temp_gc_func_table_ptr,
                        gc_func_type_indices.length(),
                      )
                    } else {
                      jit.jit_module.setup_gc(
                        heap,
                        jit.module_types,
                        canonical,
                        gc_func_type_indices,
                      )
                    }
                  } catch {
                    err => {
                      if temp_gc_func_table_ptr != 0L {
                        @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
                        temp_gc_func_table_ptr = 0L
                      }
                      raise RuntimeError("JIT GC setup failed: \{err}")
                    }
                  }
                  // Set GC heap in VMContext for inline allocation
                  jit.jit_module.set_gc_heap(heap.get_ptr())
                }
                None => ()
              }
              // Keep JIT shared tables coherent with interpreter-visible table state
              // before each call. This is required for mixed interpreter/JIT flows
              // (e.g. assertions that instantiate/trap between JIT invocations).
              sync_store_globals_to_jit(jit, ctx.store)
              sync_tables_to_jit(
                instance,
                ctx.store,
                jit.jit_module,
                use_subtype_indirect_check=jit.use_subtype_indirect_check,
              )
              let results = jit.jit_module.call_with_context(f, i64_args) catch {
                JITExit(code) => {
                  // Tear down GC context on exit
                  jit.jit_module.teardown_gc()
                  if temp_gc_func_table_ptr != 0L {
                    @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
                    temp_gc_func_table_ptr = 0L
                  }
                  // Sync globals even on exit
                  sync_jit_globals_to_store(jit, ctx.store)
                  sync_jit_tables_to_store(jit, ctx.store)
                  raise RuntimeError("WASI exit: \{code}")
                }
                JITTrap(msg) => {
                  // Tear down GC context on trap
                  jit.jit_module.teardown_gc()
                  if temp_gc_func_table_ptr != 0L {
                    @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
                    temp_gc_func_table_ptr = 0L
                  }
                  // Sync globals even on trap (in case globals were modified before trap)
                  sync_jit_globals_to_store(jit, ctx.store)
                  sync_jit_tables_to_store(jit, ctx.store)
                  raise RuntimeError(msg)
                }
                JITNativeFiberFailure(message) => {
                  jit.jit_module.teardown_gc()
                  if temp_gc_func_table_ptr != 0L {
                    @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
                    temp_gc_func_table_ptr = 0L
                  }
                  sync_jit_globals_to_store(jit, ctx.store)
                  sync_jit_tables_to_store(jit, ctx.store)
                  raise RuntimeError("JIT native-fiber failure: \{message}")
                }
                JITCancelled => {
                  jit.jit_module.teardown_gc()
                  if temp_gc_func_table_ptr != 0L {
                    @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
                    temp_gc_func_table_ptr = 0L
                  }
                  sync_jit_globals_to_store(jit, ctx.store)
                  sync_jit_tables_to_store(jit, ctx.store)
                  raise RuntimeError("invocation cancelled")
                }
              }
              // Tear down GC context after JIT call
              jit.jit_module.teardown_gc()
              if temp_gc_func_table_ptr != 0L {
                @wasmoon_jit.free_memory(temp_gc_func_table_ptr)
              }
              // Sync JIT globals back to store after successful call
              sync_jit_globals_to_store(jit, ctx.store)
              sync_jit_tables_to_store(jit, ctx.store)
              // Convert results back to Values based on function return types
              // V128 results take two slots (low then high 8 bytes)
              let values : Array[@types.Value] = []
              let mut result_idx = 0
              for result_type in f.result_types {
                if result_idx >= results.length() {
                  break
                }
                match result_type {
                  V128 => {
                    // V128 uses two slots: low (first) and high (second)
                    if result_idx + 1 >= results.length() {
                      break
                    }
                    let low = results[result_idx]
                    let high = results[result_idx + 1]
                    let bytes = @types.int64_pair_to_v128_le(low, high)
                    values.push(V128(bytes))
                    result_idx = result_idx + 2
                  }
                  _ => {
                    values.push(
                      convert_jit_result(
                        results[result_idx],
                        result_type,
                        ctx.store.c_heap,
                      ),
                    )
                    result_idx = result_idx + 1
                  }
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
fn convert_jit_result(
  v : Int64,
  ty : @types.ValueType,
  c_heap : @wasmoon_jit.CHeap?,
) -> @types.Value {
  match ty {
    I32 => I32(@types.FromInt64::from_int64_bits(v))
    I64 => I64(@types.FromInt64::from_int64_bits(v))
    F32 => F32(@types.FromInt64::from_int64_bits(v))
    F64 => F64(@types.FromInt64::from_int64_bits(v))
    // Reference types: JIT null is 0.
    // Funcref may be IR-encoded as negative: value = -(func_idx + 1).
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      if v == NULL_REF {
        Null
      } else if v < 0L {
        let func_idx = (-(v + 1L)).to_int()
        FuncRef(func_idx)
      } else {
        // Tagged pointer funcref (bit 61 set) - keep previous decoding fallback.
        let func_idx = (v & 0x1FFFFFFFFFFFFFFFL).to_int()
        FuncRef(func_idx)
      }
    ExternRef | RefExtern | NullExternRef =>
      // Externref encoding: null=0, non-null=EXTERNREF_TAG | (host_idx << 1)
      if v == NULL_REF {
        Null
      } else {
        match @wasmoon_jit.decode_externref(v) {
          Some(idx) => ExternRef(idx)
          None => ExternRef(v.to_int())
        }
      }
    // GC reference types - decode using c_heap encoding
    // Encoding: StructRef/ArrayRef = (gc_ref - 1) << 1 (even), i31 = (value << 1) | 1 (odd), null = NULL_REF
    // Note: ExternRef can also appear here after any.convert_extern, tagged with EXTERNREF_TAG
    AnyRef | RefAny | RefEq | RefNullEq =>
      if v == NULL_REF {
        Null
      } else if (v & EXTERNREF_TAG) != 0L {
        // Host externref that was converted to anyref via any.convert_extern
        match @wasmoon_jit.decode_externref(v) {
          Some(idx) => ExternRef(idx)
          None => ExternRef(v.to_int())
        }
      } else if (v & 1L) == 1L {
        // i31 (odd)
        I31((v >> 1).to_int())
      } else {
        // Struct/array ref (even, non-zero) - query heap for the actual kind
        // JIT encodes as gc_ref << 1 where gc_ref is 1-based
        // CHeap::is_array expects 0-based index, so subtract 1
        let gc_ref = (v >> 1).to_int()
        let heap_idx = gc_ref - 1
        match c_heap {
          Some(heap) =>
            if heap.is_array(heap_idx) {
              ArrayRef(heap_idx)
            } else {
              StructRef(heap_idx)
            }
          None =>
            // No heap available, default to StructRef
            StructRef(heap_idx)
        }
      }
    StructRef | RefStructAbs | RefStruct(_) | RefNullStruct(_) =>
      if v == NULL_REF {
        Null
      } else {
        let gc_ref = (v >> 1).to_int()
        StructRef(gc_ref - 1)
      }
    ArrayRef | RefArrayAbs | RefArray(_) | RefNullArray(_) =>
      if v == NULL_REF {
        Null
      } else {
        let gc_ref = (v >> 1).to_int()
        ArrayRef(gc_ref - 1)
      }
    RefI31 | RefNullI31 =>
      if v == NULL_REF {
        Null
      } else {
        I31((v >> 1).to_int())
      }
    NullRef | ExnRef | NullExnRef | RefNone => Null
    V128 => abort("V128 not supported in JIT")
  }
}

///|
pub fn wast_value_to_runtime(v : @wat.WastValue) -> @types.Value {
  match v {
    I32(n) => I32(n)
    I64(n) => I64(n)
    F32(n) => F32(n)
    F64(n) => F64(n)
    V128(bytes) => V128(bytes)
    F32CanonicalNan | F32ArithmeticNan => F32((0.0 : Float) / (0.0 : Float))
    F64CanonicalNan | F64ArithmeticNan => F64(0.0 / 0.0)
    V128Pattern(_) =>
      // For patterns, use a placeholder - actual matching is done in values_match
      V128(Bytes::make(16, b'\x00'))
    RefNull(_) => Null
    RefExtern(n) => ExternRef(n)
    RefHost(n) => ExternRef(n) // ref.host is like ref.extern for testing
    RefFunc => FuncRef(0) // Placeholder
    RefExternAny => ExternRef(0) // Placeholder for matching
    // GC reference types - these are abstract type matchers, not concrete values
    RefArray | RefStruct | RefEq | RefI31 | RefAny => Null // Placeholder
    // Either is for matching, not for conversion to runtime value
    Either(_) => abort("Either not valid as runtime value")
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
    (ExternRef(_), RefExternAny) => true // any non-null externref
    (ExternRef(a), RefHost(e)) => a == e // ref.host is like ref.extern
    // GC reference type matching
    (ArrayRef(_), RefArray) => true
    (StructRef(_), RefStruct) => true
    // ref.eq matches i31, struct, and array references
    (I31(_), RefEq) => true
    (StructRef(_), RefEq) => true
    (ArrayRef(_), RefEq) => true
    // ref.i31 matches i31 references
    (I31(_), RefI31) => true
    // ref.any matches any GC reference
    (I31(_), RefAny) => true
    (StructRef(_), RefAny) => true
    (ArrayRef(_), RefAny) => true
    // V128 matching
    (V128(a), V128(e)) => bytes_equal(a, e)
    (V128(a), V128Pattern(lanes)) => v128_pattern_match(a, lanes)
    // Relaxed SIMD: Either matches if any alternative matches
    (_, Either(alternatives)) =>
      alternatives.iter().any(fn(alt) { values_match(actual, alt) })
    _ => false
  }
}

///|
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn v128_pattern_match(
  actual : Bytes,
  lanes : Array[@wat.WastLaneValue],
) -> Bool {
  // Match lane by lane
  if lanes.length() == 4 {
    // f32x4 - 4 lanes
    for i in 0..<4 {
      let offset = i * 4
      let lane_bits = actual[offset].to_int() |
        (actual[offset + 1].to_int() << 8) |
        (actual[offset + 2].to_int() << 16) |
        (actual[offset + 3].to_int() << 24)
      let actual_f = Float::reinterpret_from_int(lane_bits)
      match lanes[i] {
        F32(e) =>
          if !(actual_f == e || (actual_f.is_nan() && e.is_nan())) {
            return false
          }
        F32CanonicalNan | F32ArithmeticNan =>
          if !actual_f.is_nan() {
            return false
          }
        _ => return false
      }
    }
    true
  } else if lanes.length() == 2 {
    // f64x2 - 2 lanes
    for i in 0..<2 {
      let offset = i * 8
      let lane_bits = actual[offset].to_int().to_int64() |
        (actual[offset + 1].to_int().to_int64() << 8) |
        (actual[offset + 2].to_int().to_int64() << 16) |
        (actual[offset + 3].to_int().to_int64() << 24) |
        (actual[offset + 4].to_int().to_int64() << 32) |
        (actual[offset + 5].to_int().to_int64() << 40) |
        (actual[offset + 6].to_int().to_int64() << 48) |
        (actual[offset + 7].to_int().to_int64() << 56)
      let actual_f = lane_bits.reinterpret_as_double()
      match lanes[i] {
        F64(e) =>
          if !(actual_f == e || (actual_f.is_nan() && e.is_nan())) {
            return false
          }
        F64CanonicalNan | F64ArithmeticNan =>
          if !actual_f.is_nan() {
            return false
          }
        _ => return false
      }
    }
    true
  } else {
    false
  }
}

///|
fn validate_module_source(source : @wat.WastModuleSource) -> Bool {
  match source {
    Binary(bytes) =>
      succeeds(() => {
        let mod_ = @parser.parse_module(bytes)
        @validator.validate_module(mod_)
      })
    Quote(parts) => {
      // Join quoted parts and parse as WAT
      let wat_source = "(module " +
        parts.iter().fold(init="", fn(acc, s) { acc + s }) +
        ")"
      succeeds(() => {
        let mod_ = @wat.parse(wat_source)
        @validator.validate_module(mod_)
      })
    }
    Inline(mod_) => succeeds(() => @validator.validate_module(mod_))
    FailedToParse(_) => false // Module failed to parse, so it's invalid
  }
}

///|
fn parse_module_source(source : @wat.WastModuleSource) -> Bool {
  match source {
    Binary(bytes) => succeeds(() => @parser.parse_module(bytes))
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
      succeeds(() => {
        let mod_ = @parser.parse_module(bytes)
        @validator.validate_module(mod_)
        let instance = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )
        ctx.current_module = Some(instance)
      })
    Inline(mod_) =>
      succeeds(() => {
        @validator.validate_module(mod_)
        let instance = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )
        ctx.current_module = Some(instance)
      })
    Quote(_) => false
    FailedToParse(_) => false // Module failed to parse, can't instantiate
  }
}

///|
fn build_partial_instance_for_trapped_module(
  ctx : WastContext,
  mod_ : @types.Module,
  imports : @runtime.Imports,
  before_funcs : Int,
  before_tables : Int,
  before_mems : Int,
  before_globals : Int,
  before_tags : Int,
) -> @runtime.ModuleInstance? {
  let after_funcs = ctx.store.funcs.length()
  if after_funcs <= before_funcs {
    return None
  }

  let func_addrs : Array[Int] = []
  let func_type_indices : Array[Int] = []
  let table_addrs : Array[Int] = []
  let mem_addrs : Array[Int] = []
  let global_addrs : Array[Int] = []
  let tag_addrs : Array[Int] = []

  for imp in mod_.imports {
    match imp.desc {
      Func(type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Func(addr)) => {
            func_addrs.push(addr)
            func_type_indices.push(type_idx)
          }
          _ => ()
        }
      Table(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Table(addr)) => table_addrs.push(addr)
          _ => ()
        }
      Memory(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Memory(addr)) => mem_addrs.push(addr)
          _ => ()
        }
      Global(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Global(addr)) => global_addrs.push(addr)
          _ => ()
        }
      Tag(type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Tag(addr)) => {
            tag_addrs.push(addr)
            ignore(type_idx)
          }
          _ => ()
        }
    }
  }

  for i, type_idx in mod_.funcs {
    let addr = before_funcs + i
    if addr >= 0 && addr < after_funcs {
      func_addrs.push(addr)
      func_type_indices.push(type_idx)
    }
  }

  let after_tables = ctx.store.tables.length()
  for i in 0..<mod_.tables.length() {
    let addr = before_tables + i
    if addr >= 0 && addr < after_tables {
      table_addrs.push(addr)
    }
  }

  let after_mems = ctx.store.mems.length()
  for i in 0..<mod_.memories.length() {
    let addr = before_mems + i
    if addr >= 0 && addr < after_mems {
      mem_addrs.push(addr)
    }
  }

  let after_globals = ctx.store.globals.length()
  for i in 0..<mod_.globals.length() {
    let addr = before_globals + i
    if addr >= 0 && addr < after_globals {
      global_addrs.push(addr)
    }
  }

  let after_tags = ctx.store.tags.length()
  for i in 0..<mod_.tags.length() {
    let addr = before_tags + i
    if addr >= 0 && addr < after_tags {
      tag_addrs.push(addr)
    }
  }

  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod_.types,
    type_rec_groups=mod_.type_rec_groups,
  )
  let dropped_elems = Array::make(mod_.elems.length(), false)
  let dropped_datas = Array::make(mod_.datas.length(), false)

  Some({
    types: mod_.types,
    type_rec_groups: mod_.type_rec_groups,
    canonical_type_indices,
    store_idx: -1,
    func_addrs,
    func_type_indices,
    table_addrs,
    mem_addrs,
    global_addrs,
    tag_addrs,
    exports: mod_.exports,
    elem_segments: mod_.elems,
    data_segments: mod_.datas,
    dropped_elems,
    dropped_datas,
  })
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
    Binary(bytes) => {
      let mod_ = @parser.parse_module(bytes) catch { _ => return false }
      @validator.validate_module(mod_) catch {
        _ => return false
      }
      let before_instances = ctx.store.instances.length()
      let before_funcs = ctx.store.funcs.length()
      let before_tables = ctx.store.tables.length()
      let before_mems = ctx.store.mems.length()
      let before_globals = ctx.store.globals.length()
      let before_tags = ctx.store.tags.length()
      let trapped = !succeeds(() => {
        @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
        |> ignore
      })
      if trapped && ctx.use_jit && ctx.jit_compiler is Some(_) {
        if ctx.store.instances.length() > before_instances {
          let trapped_instance = ctx.store.instances[ctx.store.instances.length() -
            1]
          match ctx.try_compile_jit(mod_, trapped_instance) {
            Ok(_) => ()
            Err(_) => return false
          }
        } else {
          match
            build_partial_instance_for_trapped_module(
              ctx, mod_, imports, before_funcs, before_tables, before_mems, before_globals,
              before_tags,
            ) {
            Some(partial_instance) =>
              match ctx.try_compile_jit(mod_, partial_instance) {
                Ok(_) => ()
                Err(_) => return false
              }
            None => ()
          }
        }
      }
      trapped
    }
    Inline(mod_) => {
      @validator.validate_module(mod_) catch {
        _ => return false
      }
      let before_instances = ctx.store.instances.length()
      let before_funcs = ctx.store.funcs.length()
      let before_tables = ctx.store.tables.length()
      let before_mems = ctx.store.mems.length()
      let before_globals = ctx.store.globals.length()
      let before_tags = ctx.store.tags.length()
      let trapped = !succeeds(() => {
        @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
        |> ignore
      })
      if trapped && ctx.use_jit && ctx.jit_compiler is Some(_) {
        if ctx.store.instances.length() > before_instances {
          let trapped_instance = ctx.store.instances[ctx.store.instances.length() -
            1]
          match ctx.try_compile_jit(mod_, trapped_instance) {
            Ok(_) => ()
            Err(_) => return false
          }
        } else {
          match
            build_partial_instance_for_trapped_module(
              ctx, mod_, imports, before_funcs, before_tables, before_mems, before_globals,
              before_tags,
            ) {
            Some(partial_instance) =>
              match ctx.try_compile_jit(mod_, partial_instance) {
                Ok(_) => ()
                Err(_) => return false
              }
            None => ()
          }
        }
      }
      trapped
    }
    Quote(_) => false // Quoted source - can't test
    FailedToParse(_) => false // Module failed to parse, doesn't count as trap
  }
}
