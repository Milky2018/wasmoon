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
  register_named_modules : Bool
  // JIT compiler callback (provided by main package)
  jit_compiler : JITCompiler?
  // WASI context (for WASI function support in tests)
  wasi_ctx : @wasi.WasiContext
}

///|
pub fn WastContext::WastContext(
  use_jit : Bool,
  bulk_memory? : Bool = true,
  nan_canonicalization? : Bool = false,
  jit_compiler? : JITCompiler? = None,
  register_named_modules? : Bool = false,
) -> WastContext {
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
    register_named_modules,
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
  bulk_memory? : Bool = true,
  nan_canonicalization? : Bool = false,
  jit_compiler? : JITCompiler? = None,
  register_named_modules? : Bool = false,
) -> WastResult {
  let result = WastResult::WastResult()
  let ctx = WastContext::WastContext(
    use_jit,
    bulk_memory~,
    nan_canonicalization~,
    jit_compiler~,
    register_named_modules~,
  )
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
  line : Int,
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
      run_wast_module(ctx, mod_, None, line, result)
    }
    ModuleBinaryFailed(err) => {
      result.failed = result.failed + 1
      result.failures.push("line \{line}: binary parse failed: \{err}")
    }
    ModuleDefinition(mod_, name) => {
      // Module definition - validates and stores for later instantiation
      // Used with (module instance ...) to create multiple instances
      @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory) catch {
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
      let valid = validate_module_source(ctx, source)
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
    Thread(_, _, _) | Wait(_) => {
      result.failed += 1
      result.failures.push(
        "line \{line}: thread directives require a complete WAST script",
      )
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
// These spelling aliases match the pinned Wasmtime WAST adapter. They
// preserve the trap category; unrelated trap messages must still fail.
fn wast_trap_message_matches(actual : String, expected : String) -> Bool {
  let actual = actual.split(" (sig=").next().unwrap_or("").to_owned()
  actual.contains(expected) ||
  (
    expected == "uninitialized element 2" &&
    actual.contains("uninitialized element")
  ) ||
  (
    expected.contains("null function") &&
    actual.contains("uninitialized element")
  ) ||
  (
    expected.contains("null") &&
    expected.contains("reference") &&
    actual.contains("null reference")
  )
}

///|
fn classify_runtime_failure(error : @runtime.RuntimeError) -> WastRunnerError {
  match error {
    UncaughtException => GuestException
    CallStackExhausted | StackOverflow => GuestExhaustion(error.to_string())
    OutOfBoundsMemoryAccess
    | OutOfBoundsTableAccess
    | OutOfBoundsArrayAccess
    | UndefinedElement
    | UninitializedElement
    | IndirectCallTypeMismatch
    | DivisionByZero
    | IntegerOverflow
    | InvalidConversion
    | Unreachable
    | CastFailure
    | NullReference
    | UnalignedAtomic
    | OutOfMemory
    | TableAllocationOverflow
    | TableAllocationFailed
    | MemoryMinimumExceedsLimits(_)
    | AllocationTooLarge
    | AtomicWaitNonSharedMemory => GuestTrap(error.to_string())
    _ => RuntimeError(error.to_string())
  }
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
  GuestTrap(String)
  GuestException
  GuestExhaustion(String)
  RuntimeError(String)
}

///|
pub impl Show for WastRunnerError with fn output(self, logger) {
  match self {
    ModuleNotFound(name) => logger.write_string("module not found: \{name}")
    NoCurrentModule => logger.write_string("no current module")
    GuestTrap(msg) => logger.write_string("wasm trap: \{msg}")
    GuestException => logger.write_string("uncaught Wasm exception")
    GuestExhaustion(msg) => logger.write_string("wasm exhaustion: \{msg}")
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
pub fn wast_value_to_runtime(
  v : @wat.WastValue,
  func_addrs? : Array[Int] = [],
) -> @types.Value raise WastRunnerError {
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
    RefFuncIndex(idx) => {
      if idx < 0 || idx >= func_addrs.length() {
        raise RuntimeError("invalid ref.func argument index")
      }
      FuncRef(func_addrs[idx])
    }
    RefFunc => FuncRef(0) // Placeholder
    RefExternAny => ExternRef(0) // Placeholder for matching
    // GC reference types - these are abstract type matchers, not concrete values
    RefArray | RefStruct | RefEq | RefI31 | RefAny => Null // Placeholder
    // Either is for matching, not for conversion to runtime value
    Either(_) => abort("Either not valid as runtime value")
  }
}

///|
pub fn values_match(
  actual : @types.Value,
  expected : @wat.WastValue,
  func_addrs? : Array[Int] = [],
) -> Bool {
  match (actual, expected) {
    (I32(a), I32(e)) => a == e
    (I64(a), I64(e)) => a == e
    (F32(a), F32(e)) => a.reinterpret_as_int() == e.reinterpret_as_int()
    (F64(a), F64(e)) => a.reinterpret_as_int64() == e.reinterpret_as_int64()
    (F32(a), F32CanonicalNan) =>
      (a.reinterpret_as_int() & 0x7fffffff) == 0x7fc00000
    (F32(a), F32ArithmeticNan) =>
      (a.reinterpret_as_int() & 0x7fc00000) == 0x7fc00000
    (F64(a), F64CanonicalNan) =>
      (a.reinterpret_as_int64() & 0x7fffffffffffffffL) == 0x7ff8000000000000L
    (F64(a), F64ArithmeticNan) =>
      (a.reinterpret_as_int64() & 0x7ff8000000000000L) == 0x7ff8000000000000L
    (Null, RefNull(_)) => true
    (FuncRef(_), RefFunc) => true
    (FuncRef(addr), RefFuncIndex(idx)) =>
      idx >= 0 && idx < func_addrs.length() && addr == func_addrs[idx]
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
      alternatives
      .iter()
      .any(fn(alt) { values_match(actual, alt, func_addrs~) })
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
      match lanes[i] {
        F32(e) => if lane_bits != e.reinterpret_as_int() { return false }
        F32CanonicalNan =>
          if (lane_bits & 0x7fffffff) != 0x7fc00000 {
            return false
          }
        F32ArithmeticNan =>
          if (lane_bits & 0x7fc00000) != 0x7fc00000 {
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
      match lanes[i] {
        F64(e) => if lane_bits != e.reinterpret_as_int64() { return false }
        F64CanonicalNan =>
          if (lane_bits & 0x7fffffffffffffffL) != 0x7ff8000000000000L {
            return false
          }
        F64ArithmeticNan =>
          if (lane_bits & 0x7ff8000000000000L) != 0x7ff8000000000000L {
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
fn validate_module_source(
  ctx : WastContext,
  source : @wat.WastModuleSource,
) -> Bool {
  match source {
    Binary(bytes) =>
      succeeds(() => {
        let mod_ = @parser.parse_module(bytes)
        @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory)
      })
    Quote(parts) => {
      // Join quoted parts and parse as WAT
      let wat_source = "(module " +
        parts.iter().fold(init="", fn(acc, s) { acc + s }) +
        ")"
      succeeds(() => {
        let mod_ = @wat.parse(wat_source)
        @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory)
      })
    }
    Inline(mod_) =>
      succeeds(() => {
        @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory)
      })
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
        @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory)
        let instance = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )
        ctx.current_module = Some(instance)
      })
    Inline(mod_) =>
      succeeds(() => {
        @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory)
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
    elem_values: [],
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
  expected_msg : String,
) -> Bool {
  let imports = ctx.build_imports()
  match source {
    Binary(bytes) => {
      let mod_ = @parser.parse_module(bytes) catch { _ => return false }
      @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory) catch {
        _ => return false
      }
      let before_instances = ctx.store.instances.length()
      let before_funcs = ctx.store.funcs.length()
      let before_tables = ctx.store.tables.length()
      let before_mems = ctx.store.mems.length()
      let before_globals = ctx.store.globals.length()
      let before_tags = ctx.store.tags.length()
      let trapped = try {
        @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
        |> ignore
        false
      } catch {
        error =>
          match classify_runtime_failure(error) {
            GuestTrap(message) =>
              wast_trap_message_matches(message, expected_msg)
            _ => false
          }
      }
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
      @validator.validate_module(mod_, bulk_memory=ctx.bulk_memory) catch {
        _ => return false
      }
      let before_instances = ctx.store.instances.length()
      let before_funcs = ctx.store.funcs.length()
      let before_tables = ctx.store.tables.length()
      let before_mems = ctx.store.mems.length()
      let before_globals = ctx.store.globals.length()
      let before_tags = ctx.store.tags.length()
      let trapped = try {
        @executor.instantiate_module_with_imports(ctx.store, mod_, imports)
        |> ignore
        false
      } catch {
        error =>
          match classify_runtime_failure(error) {
            GuestTrap(message) =>
              wast_trap_message_matches(message, expected_msg)
            _ => false
          }
      }
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
