// WAST Runner - Execute WAST test scripts

// Reference encoding constants - re-exported from @types for convenience

///|
pub const NULL_REF : Int64 = @wasm_milkir.NULL_REF

///|
pub const EXTERNREF_TAG : Int64 = @wasm_milkir.EXTERNREF_TAG

///|
pub const FUNCREF_TAG : Int64 = @wasm_milkir.FUNCREF_TAG

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
  modules : @core_wast.WastModules
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
    modules: @core_wast.WastModules::new(registered_modules),
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
  self.modules.clear()
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
pub fn WastContext::build_imports(self : WastContext) -> @runtime.Imports {
  self.modules.build_imports(self.store)
}

///|
/// Run WAST script commands
pub fn run_wast_commands(
  script : @wat.WastScript,
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
      result.record_failure("WAST context initialization failed: \{error}")
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
    run_threaded_wast(ctx, script, result, show_success)
    return result
  }
  for item in script.commands {
    let (cmd, line) = item
    run_wast_command(ctx, cmd, line, result, show_success)
  }
  result
}

///|
pub fn run_wast_command(
  ctx : WastContext,
  command : @wat.WastCommand,
  line : Int32,
  result : WastResult,
  show_success : Bool,
) -> Unit {
  @core_wast.execute_command(ctx, command, line, result, show_success)
}

///|
impl @core_wast.WastEngine for WastContext with fn modules(self) {
  self.modules
}

///|
impl @core_wast.WastEngine for WastContext with fn store(self) {
  self.store
}

///|
impl @core_wast.WastEngine for WastContext with fn closed(self) {
  self.closed
}

///|
impl @core_wast.WastEngine for WastContext with fn validate(self, module_) {
  self.validate_core_module(module_)
}

///|
impl @core_wast.WastEngine for WastContext with fn instantiate(
  self,
  module_,
  name,
) {
  instantiate_script_module(self, module_, name)
}

///|
impl @core_wast.WastEngine for WastContext with fn source_is_invalid(
  self,
  source,
  expected,
) {
  self.native_source_is_invalid(source, expected)
}

///|
impl @core_wast.WastEngine for WastContext with fn source_traps(
  self,
  source,
  expected,
) {
  try_instantiate_source_traps(self, source, expected)
}

///|
impl @core_wast.WastEngine for WastContext with fn registered(self, name) {
  if builtin_jit_modules().contains(name) {
    self.overridden_builtin_modules.add(name)
  }
}

///|
impl @core_wast.WastEngine for WastContext with fn invoke(self, action) {
  invoke_action(self, action)
}

///|
pub fn invoke_action(
  ctx : WastContext,
  action : @wat.WastAction,
) -> Array[@types.Value] raise WastRunnerError {
  @core_wast.invoke_script_action(ctx.store, ctx.modules, action, invoke_native=(
    name,
    instance,
    function,
    args,
  ) => {
    let jit = match name {
      Some(name) => ctx.jit_modules.get(name)
      None => ctx.current_jit
    }
    guard jit is Some(jit) &&
      jit.jit_module.get_func_by_name(function) is Some(func) else {
      return None
    }
    Some(
      jit.call_core_func(ctx.store, instance, func.func_idx, args) catch {
        error => raise classify_jit_failure(error)
      },
    )
  })
}

///|
fn WastContext::native_source_is_invalid(
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
  let mod_ = @assertions.parse_module_source(source) catch { _ => return false }
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

///|
pub using @core_wast {type WastResult}
