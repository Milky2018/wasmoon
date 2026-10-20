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
  mut passed : Int32
  mut failed : Int32
  skipped : Int32
  failures : Array[String]
}

///|
pub fn WastResult::WastResult() -> WastResult {
  { passed: 0, failed: 0, skipped: 0, failures: [], }
}

///|
/// Modules that have built-in JIT trampolines
pub fn builtin_jit_modules() -> Array[String] {
  ["spectest", "wasi_snapshot_preview1"]
}

///|
/// WAST execution context
pub struct WastContext {
  priv mut closed : Bool
  priv compiled_modules : Array[JITModuleContext]
  store : @runtime.Store
  mut current_module : @runtime.ModuleInstance?
  named_modules : Map[String, @runtime.ModuleInstance]
  // Module definitions for (module instance ...) command
  module_definitions : Map[String, @types.Module]
  mut current_definition : @types.Module?
  // Registered modules for imports (module_name -> exports)
  registered_modules : Map[String, @runtime.ModuleInstance]
  // Built-in modules that have been overridden by Register command
  // JIT cannot use trampolines for these since they've been replaced
  overridden_builtin_modules : @hashset.HashSet[String]
  // JIT support
  jit_modules : Map[String, JITModuleContext]
  mut current_jit : JITModuleContext?
  use_jit : Bool
  bulk_memory : Bool
  stack_switching : Bool
  register_named_modules : Bool
  priv wasmtime_validation : Bool
  // JIT compiler callback (provided by main package)
  jit_compiler : JITCompiler?
  // WASI context (for WASI function support in tests)
  wasi_ctx : @wasi.WasiContext
}

///|
pub fn WastContext::WastContext(
  use_jit : Bool,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
  nan_canonicalization~ : Bool = false,
  jit_compiler~ : JITCompiler? = None,
  register_named_modules~ : Bool = false,
  wasmtime_validation~ : Bool = false,
) -> WastContext raise @runtime.RuntimeError {
  // Use c_heap when JIT is enabled for GC support
  let store = if use_jit {
    @runtime.Store::with_c_heap(nan_canonicalization~)
  } else {
    Store(nan_canonicalization~)
  }

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
  try! linker.add_host_func("wasmtime", "gc", fn(_args) {
    store.collect_garbage() |> ignore
    []
  })
  let registered_modules : Map[String, @runtime.ModuleInstance] = Map([])
  registered_modules.set("wasmtime", linker.get_module("wasmtime").unwrap())
  registered_modules.set("spectest", spectest_instance)
  registered_modules.set("wasi_snapshot_preview1", wasi_instance)
  {
    closed: false,
    compiled_modules: [],
    store,
    current_module: None,
    named_modules: Map([]),
    module_definitions: Map([]),
    current_definition: None,
    registered_modules,
    overridden_builtin_modules: HashSet([]),
    jit_modules: Map([]),
    current_jit: None,
    use_jit,
    bulk_memory,
    stack_switching,
    register_named_modules,
    wasmtime_validation,
    jit_compiler,
    wasi_ctx,
  }
}

///|
/// Release a script's resources after every command and invocation has ended.
/// Repeated close is harmless; the context cannot execute further commands.
pub fn WastContext::close(self : WastContext) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.store.native_execution_state().retire_continuations()
  // Track compilation ownership separately from names: rebinding a name or
  // replacing the current module must not orphan its executable mappings.
  for context in self.compiled_modules {
    context.close()
  }
  self.compiled_modules.clear()
  self.current_jit = None
  self.jit_modules.clear()
  self.current_module = None
  self.named_modules.clear()
  self.registered_modules.clear()
  self.module_definitions.clear()
  self.current_definition = None
  self.overridden_builtin_modules.clear()
  // Store funcref leases keep code alive until the last callable is removed.
  self.store.close()
  for _, file in self.wasi_ctx.open_files {
    @wasi.native_close(file.native_fd) |> ignore
  }
  self.wasi_ctx.open_files.clear()
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
    Some(compiler) => {
      let result = (compiler.compile_fn)(mod_, instance, self.store)
      if result is Ok(context) {
        self.compiled_modules.push(context)
      }
      result
    }
    None => Err("WAST JIT strict mode: JIT compiler callback is missing")
  }
}

///|
/// Build imports from registered modules
pub fn WastContext::build_imports(self : WastContext) -> @runtime.Imports {
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
/// Run WAST script commands
pub fn run_wast_commands(
  script : @wat.WastScript,
  base_dir : String,
  use_jit : Bool,
  show_success : Bool,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
  nan_canonicalization~ : Bool = false,
  jit_compiler~ : JITCompiler? = None,
  register_named_modules~ : Bool = false,
  wasmtime_validation~ : Bool = false,
) -> WastResult {
  let result = WastResult::WastResult()
  let ctx = WastContext::WastContext(
    use_jit,
    bulk_memory~,
    stack_switching~,
    nan_canonicalization~,
    jit_compiler~,
    register_named_modules~,
    wasmtime_validation~,
  ) catch {
    error => {
      result.failed = 1
      result.failures.push("WAST context initialization failed: \{error}")
      return result
    }
  }
  defer ctx.close()
  if script.commands.any(item => {
      match item.0 {
        Thread(_, _, _) | Wait(_) => true
        _ => false
      }
    }) {
    run_threaded_wast(ctx, script, result, base_dir, show_success)
    return result
  }
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
      let invalid = ctx.source_is_invalid(source, msg) catch {
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
        // Track if this overrides a built-in JIT module
        // JIT cannot use built-in trampolines for overridden modules
        for builtin in builtin_jit_modules() {
          if name == builtin {
            ctx.overridden_builtin_modules.add(name)
          }
        }
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
  ctx : WastContext,
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
      let runtime_args = args.map(value => {
        wast_value_to_runtime(value, func_addrs=instance.func_addrs)
      })
      let jit_ctx = match module_name {
        Some(name) => ctx.jit_modules.get(name)
        None => ctx.current_jit
      }
      if jit_ctx is Some(jit) {
        if jit.jit_module.get_func_by_name(func_name) is Some(func) {
          return jit.call_core_func(
            ctx.store,
            instance,
            func.func_idx,
            runtime_args,
          ) catch {
            error => raise classify_jit_failure(error)
          }
        }
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
fn WastContext::source_is_invalid(
  self : WastContext,
  source : @wat.WastModuleSource,
  expected : String,
) -> Bool raise WastRunnerError {
  let valid_module = @assertions.validate_module_source(
    source,
    bulk_memory=self.bulk_memory,
    stack_switching=self.stack_switching,
  )
  guard valid_module is Some(module_) else { return true }
  if !self.wasmtime_validation {
    return false
  }
  // Wasmtime's assert_invalid also includes engine build restrictions. Keep
  // this explicit profile separate from Core validity and arbitrary failures.
  try @executor.validate_continuation_gc_storage(module_) catch {
    error =>
      if error is UnsupportedGcContinuationStorage {
        wast_trap_message_matches(error.to_string(), expected)
      } else {
        raise RuntimeError("engine capability check failed: \{error}")
      }
  } noraise {
    _ => false
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
  ctx : WastContext,
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
  succeeds(() => {
    @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
    |> ignore
  })
}

///|
fn build_partial_instance_for_trapped_module(
  ctx : WastContext,
  mod_ : @types.Module,
  imports : @runtime.Imports,
  before_funcs : Int32,
  before_tables : Int32,
  before_mems : Int32,
  before_globals : Int32,
  before_tags : Int32,
) -> @runtime.ModuleInstance? {
  let after_funcs = ctx.store.counts().funcs
  if after_funcs <= before_funcs {
    return None
  }

  let func_addrs : Array[Int32] = []
  let func_type_indices : Array[Int32] = []
  let table_addrs : Array[Int32] = []
  let mem_addrs : Array[Int32] = []
  let global_addrs : Array[Int32] = []
  let tag_addrs : Array[Int32] = []

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

  let after_tables = ctx.store.counts().tables
  for i in 0..<mod_.tables.length() {
    let addr = before_tables + i
    if addr >= 0 && addr < after_tables {
      table_addrs.push(addr)
    }
  }

  let after_mems = ctx.store.counts().mems
  for i in 0..<mod_.memories.length() {
    let addr = before_mems + i
    if addr >= 0 && addr < after_mems {
      mem_addrs.push(addr)
    }
  }

  let after_globals = ctx.store.counts().globals
  for i in 0..<mod_.globals.length() {
    let addr = before_globals + i
    if addr >= 0 && addr < after_globals {
      global_addrs.push(addr)
    }
  }

  let after_tags = ctx.store.counts().tags
  for i in 0..<mod_.tags.length() {
    let addr = before_tags + i
    if addr >= 0 && addr < after_tags {
      tag_addrs.push(addr)
    }
  }

  try {
    let validated = @validator.ValidatedModule::new(
      mod_,
      stack_switching=ctx.stack_switching,
    )
    Some(
      ctx.store.new_instance(
        validated,
        func_addrs~,
        table_addrs~,
        mem_addrs~,
        global_addrs~,
        tag_addrs~,
        elem_values=Array::makei(mod_.elems.length(), _ => []),
      ),
    )
  } catch {
    _ => None
  }
}

///|
/// Try to instantiate a module source and check if it traps.
/// Returns true if instantiation traps (for assert_trap with module).
fn try_instantiate_source_traps(
  ctx : WastContext,
  source : @wat.WastModuleSource,
  expected_msg : String,
) -> Bool {
  let mod_ = match source {
    Binary(bytes) => @parser.parse_module(bytes) catch { _ => return false }
    Quote(parts) =>
      @wat.parse(parts.join(""), implicit_module=true) catch {
        _ => return false
      }
    Inline(mod_) => mod_
    FailedToParse(_) => return false
  }
  let imports = ctx.build_imports()
  ctx.validate_core_module(mod_) catch {
    _ => return false
  }
  let before_instances = ctx.store.counts().instances
  let before_funcs = ctx.store.counts().funcs
  let before_tables = ctx.store.counts().tables
  let before_mems = ctx.store.counts().mems
  let before_globals = ctx.store.counts().globals
  let before_tags = ctx.store.counts().tags
  let trapped = try {
    @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
    |> ignore
    false
  } catch {
    error =>
      match classify_runtime_failure(error) {
        GuestTrap(message) => wast_trap_message_matches(message, expected_msg)
        _ => false
      }
  }
  if trapped && ctx.use_jit && ctx.jit_compiler is Some(_) {
    if ctx.store.counts().instances > before_instances {
      let trapped_instance = ctx.store.get_instance(
        ctx.store.counts().instances - 1,
      ) catch {
        _ => return false
      }
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

///|
fn WastContext::validate_core_module(
  self : WastContext,
  module_ : @types.Module,
) -> Unit raise {
  @validator.validate_module(
    module_,
    bulk_memory=self.bulk_memory,
    stack_switching=self.stack_switching,
  )
  @executor.validate_continuation_gc_storage(module_)
}

///|
pub using @assertions {
  type WastRunnerError,
  wast_value_to_runtime,
  values_match,
  wast_trap_message_matches,
  classify_runtime_failure,
}
