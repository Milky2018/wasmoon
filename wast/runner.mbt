// WAST Runner - Execute WAST test scripts

// Reference encoding constants - re-exported from @types for convenience

///|
pub const NULL_REF : Int64 = @types.NULL_REF

///|
pub const EXTERNREF_TAG : Int64 = @types.EXTERNREF_TAG

///|
pub const FUNCREF_TAG : Int64 = @types.FUNCREF_TAG

///|
/// Convert 8 bytes from Bytes at given offset to Int64 (little-endian)
fn bytes_to_int64_le(bytes : Bytes, offset : Int) -> Int64 {
  let b0 = bytes[offset].to_int64() & 0xFFL
  let b1 = bytes[offset + 1].to_int64() & 0xFFL
  let b2 = bytes[offset + 2].to_int64() & 0xFFL
  let b3 = bytes[offset + 3].to_int64() & 0xFFL
  let b4 = bytes[offset + 4].to_int64() & 0xFFL
  let b5 = bytes[offset + 5].to_int64() & 0xFFL
  let b6 = bytes[offset + 6].to_int64() & 0xFFL
  let b7 = bytes[offset + 7].to_int64() & 0xFFL
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
/// Convert two Int64 (low and high) to V128 Bytes (16 bytes, little-endian)
fn int64_pair_to_v128_le(low : Int64, high : Int64) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  // Write low 8 bytes
  buf.write_byte((low & 0xFFL).to_byte())
  buf.write_byte(((low >> 8) & 0xFFL).to_byte())
  buf.write_byte(((low >> 16) & 0xFFL).to_byte())
  buf.write_byte(((low >> 24) & 0xFFL).to_byte())
  buf.write_byte(((low >> 32) & 0xFFL).to_byte())
  buf.write_byte(((low >> 40) & 0xFFL).to_byte())
  buf.write_byte(((low >> 48) & 0xFFL).to_byte())
  buf.write_byte(((low >> 56) & 0xFFL).to_byte())
  // Write high 8 bytes
  buf.write_byte((high & 0xFFL).to_byte())
  buf.write_byte(((high >> 8) & 0xFFL).to_byte())
  buf.write_byte(((high >> 16) & 0xFFL).to_byte())
  buf.write_byte(((high >> 24) & 0xFFL).to_byte())
  buf.write_byte(((high >> 32) & 0xFFL).to_byte())
  buf.write_byte(((high >> 40) & 0xFFL).to_byte())
  buf.write_byte(((high >> 48) & 0xFFL).to_byte())
  buf.write_byte(((high >> 56) & 0xFFL).to_byte())
  buf.contents()
}

///|
/// Result of running WAST commands
pub struct WastResult {
  mut passed : Int
  mut failed : Int
  skipped : Int
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
pub fn WastContext::new(
  use_jit : Bool,
  jit_compiler? : JITCompiler? = None,
) -> WastContext {
  // Use c_heap when JIT is enabled for GC support
  let store = if use_jit {
    @runtime.Store::with_c_heap()
  } else {
    @runtime.Store::new()
  }

  // Create WASI context with default configuration for tests
  let wasi_builder = @wasi.WasiContextBuilder::new()
  wasi_builder.inherit_stdin() |> ignore
  wasi_builder.inherit_stdout() |> ignore
  wasi_builder.inherit_stderr() |> ignore
  let wasi_ctx = wasi_builder.build()

  // Create spectest module with standard test functions/values
  let spectest_instance = create_spectest_module(store)

  // Create WASI module using Linker (to reuse wasi::register_wasi)
  let linker = @runtime.Linker::with_store(store)
  // Register spectest with linker so WASI functions can use it if needed
  linker.register("spectest", spectest_instance)
  // Register all WASI functions - this creates the wasi_snapshot_preview1 module
  @wasi.register_wasi(linker, wasi_ctx)
  // Get the WASI module instance that was created by register_wasi
  let wasi_instance = match linker.get_module("wasi_snapshot_preview1") {
    Some(instance) => instance
    None => @runtime.ModuleInstance::new() // Fallback: shouldn't happen
  }
  let registered_modules : Map[String, @runtime.ModuleInstance] = Map::new()
  registered_modules.set("spectest", spectest_instance)
  registered_modules.set("wasi_snapshot_preview1", wasi_instance)
  WastContext::{
    store,
    current_module: None,
    named_modules: Map::new(),
    module_definitions: Map::new(),
    registered_modules,
    overridden_builtin_modules: @hashset.new(),
    jit_modules: Map::new(),
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
) -> JITModuleContext? {
  // Check if module imports from any overridden built-in modules
  // JIT cannot use these since the built-in trampolines don't match the overridden implementation
  for imp in mod_.imports {
    if self.overridden_builtin_modules.contains(imp.mod_name) {
      return None // Fall back to interpreter for overridden modules
    }
  }
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
          result.failed = result.failed + 1
          result.failures.push("line \{line}: quoted module parse failed: \{e}")
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
      match ctx.try_compile_jit(mod_, instance) {
        Some(jit_ctx) if ctx.use_jit => ctx.current_jit = Some(jit_ctx)
        _ => ctx.current_jit = None
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
                  RefExtern(n) => i64_args.push(@jit.encode_externref(n))
                  RefHost(n) => i64_args.push(@jit.encode_externref(n))
                  RefFunc => i64_args.push(NULL_REF) // placeholder
                  RefExternAny => i64_args.push(NULL_REF) // placeholder
                  // GC reference types - these shouldn't appear as args but handle them
                  RefArray | RefStruct | RefEq | RefI31 | RefAny =>
                    i64_args.push(NULL_REF)
                  // V128: push 16 bytes as two Int64 (low then high) in little-endian
                  V128(bytes) => {
                    let low = bytes_to_int64_le(bytes, 0)
                    i64_args.push(low)
                    let high = bytes_to_int64_le(bytes, 8)
                    i64_args.push(high)
                  }
                  V128Pattern(_) =>
                    abort("V128Pattern not valid as JIT argument")
                  Either(_) => abort("Either not valid as JIT argument")
                }
              }
              // Set up GC heap for JIT execution if c_heap is available
              match ctx.store.c_heap {
                Some(heap) => {
                  // Compute canonical type indices for proper type equivalence checking
                  let canonical = @types.compute_canonical_type_indices(
                    ctx.store.module_types,
                    type_rec_groups=ctx.store.module_rec_groups,
                  )
                  // Remap func_type_indices: JIT func_idx -> store func_addr -> type_idx
                  // The JIT func_table has entries for this module's functions, but
                  // the Store's func_type_indices has entries for ALL functions.
                  // We need to create a mapping from JIT func_idx to type_idx.
                  let jit_func_type_indices : Array[Int] = []
                  for func_addr in jit.func_addrs {
                    if func_addr >= 0 &&
                      func_addr < ctx.store.func_type_indices.length() {
                      jit_func_type_indices.push(
                        ctx.store.func_type_indices[func_addr],
                      )
                    } else {
                      jit_func_type_indices.push(-1) // Invalid/unknown type
                    }
                  }
                  // Pass function type indices for funcref subtyping checks
                  // Also pass func_table pointer for looking up func_idx from tagged pointer funcrefs
                  @jit.gc_setup(
                    heap,
                    ctx.store.module_types,
                    canonical,
                    func_type_indices=jit_func_type_indices,
                    func_table_ptr=jit.jit_module.get_func_table_ptr(),
                    num_funcs=jit.jit_module.get_func_count(),
                  )
                  // Set GC heap in VMContext for inline allocation
                  jit.jit_module.set_gc_heap(heap.get_ptr())
                }
                None => ()
              }
              // Note: We don't sync interpreter tables to JIT tables here because:
              // - If init was run via JIT, the JIT tables already have the correct values
              // - Syncing from interpreter (which has nulls) would overwrite the JIT values
              // TODO: Implement bidirectional sync when mixing interpreter/JIT execution
              let results = jit.jit_module.call_with_context(f, i64_args) catch {
                @jit.JITExit(code) => {
                  // Tear down GC context on exit
                  @jit.gc_teardown()
                  // Sync globals even on exit
                  sync_jit_globals_to_store(jit, ctx.store)
                  raise RuntimeError("WASI exit: \{code}")
                }
                @jit.JITTrap(msg) => {
                  // Tear down GC context on trap
                  @jit.gc_teardown()
                  // Sync globals even on trap (in case globals were modified before trap)
                  sync_jit_globals_to_store(jit, ctx.store)
                  raise RuntimeError(msg)
                }
              }
              // Tear down GC context after JIT call
              @jit.gc_teardown()
              // Sync JIT globals back to store after successful call
              sync_jit_globals_to_store(jit, ctx.store)
              // Convert results back to Values based on function return types
              // V128 results take two slots (low then high 8 bytes)
              let values : Array[@types.Value] = []
              let mut result_idx = 0
              for result_type in f.result_types {
                if result_idx >= results.length() {
                  break
                }
                match result_type {
                  @types.ValueType::V128 => {
                    // V128 uses two slots: low (first) and high (second)
                    if result_idx + 1 >= results.length() {
                      break
                    }
                    let low = results[result_idx]
                    let high = results[result_idx + 1]
                    let bytes = int64_pair_to_v128_le(low, high)
                    values.push(@types.Value::V128(bytes))
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
  c_heap : @jit.CHeap?,
) -> @types.Value {
  match ty {
    I32 => @types.Value::I32(@types.FromInt64::from_int64_bits(v))
    I64 => @types.Value::I64(@types.FromInt64::from_int64_bits(v))
    F32 => @types.Value::F32(@types.FromInt64::from_int64_bits(v))
    F64 => @types.Value::F64(@types.FromInt64::from_int64_bits(v))
    // Reference types: JIT null is 0.
    // Funcref may be IR-encoded as negative: value = -(func_idx + 1).
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      if v == NULL_REF {
        @types.Value::Null
      } else if v < 0L {
        let func_idx = (-(v + 1L)).to_int()
        @types.Value::FuncRef(func_idx)
      } else {
        // Tagged pointer funcref (bit 61 set) - keep previous decoding fallback.
        let func_idx = (v & 0x1FFFFFFFFFFFFFFFL).to_int()
        @types.Value::FuncRef(func_idx)
      }
    ExternRef | RefExtern | NullExternRef =>
      // Externref encoding: null=0, non-null=EXTERNREF_TAG | (host_idx << 1)
      if v == NULL_REF {
        @types.Value::Null
      } else {
        match @jit.decode_externref(v) {
          Some(idx) => @types.Value::ExternRef(idx)
          None => @types.Value::ExternRef(v.to_int())
        }
      }
    // GC reference types - decode using c_heap encoding
    // Encoding: StructRef/ArrayRef = (gc_ref - 1) << 1 (even), i31 = (value << 1) | 1 (odd), null = NULL_REF
    // Note: ExternRef can also appear here after any.convert_extern, tagged with EXTERNREF_TAG
    AnyRef | RefAny | RefEq | RefNullEq =>
      if v == NULL_REF {
        @types.Value::Null
      } else if (v & EXTERNREF_TAG) != 0L {
        // Host externref that was converted to anyref via any.convert_extern
        match @jit.decode_externref(v) {
          Some(idx) => @types.Value::ExternRef(idx)
          None => @types.Value::ExternRef(v.to_int())
        }
      } else if (v & 1L) == 1L {
        // i31 (odd)
        @types.Value::I31((v >> 1).to_int())
      } else {
        // Struct/array ref (even, non-zero) - query heap for the actual kind
        // JIT encodes as gc_ref << 1 where gc_ref is 1-based
        // CHeap::is_array expects 0-based index, so subtract 1
        let gc_ref = (v >> 1).to_int()
        let heap_idx = gc_ref - 1
        match c_heap {
          Some(heap) =>
            if heap.is_array(heap_idx) {
              @types.Value::ArrayRef(heap_idx)
            } else {
              @types.Value::StructRef(heap_idx)
            }
          None =>
            // No heap available, default to StructRef
            @types.Value::StructRef(heap_idx)
        }
      }
    StructRef | RefStructAbs | RefStruct(_) | RefNullStruct(_) =>
      if v == NULL_REF {
        @types.Value::Null
      } else {
        let gc_ref = (v >> 1).to_int()
        @types.Value::StructRef(gc_ref - 1)
      }
    ArrayRef | RefArrayAbs | RefArray(_) | RefNullArray(_) =>
      if v == NULL_REF {
        @types.Value::Null
      } else {
        let gc_ref = (v >> 1).to_int()
        @types.Value::ArrayRef(gc_ref - 1)
      }
    RefI31 | RefNullI31 =>
      if v == NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::I31((v >> 1).to_int())
      }
    NullRef | ExnRef | NullExnRef | RefNone => @types.Value::Null
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
    V128(bytes) => @types.Value::V128(bytes)
    F32CanonicalNan | F32ArithmeticNan =>
      @types.Value::F32((0.0 : Float) / (0.0 : Float))
    F64CanonicalNan | F64ArithmeticNan => @types.Value::F64(0.0 / 0.0)
    V128Pattern(_) =>
      // For patterns, use a placeholder - actual matching is done in values_match
      @types.Value::V128(Bytes::make(16, b'\x00'))
    RefNull(_) => @types.Value::Null
    RefExtern(n) => @types.Value::ExternRef(n)
    RefHost(n) => @types.Value::ExternRef(n) // ref.host is like ref.extern for testing
    RefFunc => @types.Value::FuncRef(0) // Placeholder
    RefExternAny => @types.Value::ExternRef(0) // Placeholder for matching
    // GC reference types - these are abstract type matchers, not concrete values
    RefArray | RefStruct | RefEq | RefI31 | RefAny => @types.Value::Null // Placeholder
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
          if not(actual_f == e || (actual_f.is_nan() && e.is_nan())) {
            return false
          }
        F32CanonicalNan | F32ArithmeticNan =>
          if not(actual_f.is_nan()) {
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
          if not(actual_f == e || (actual_f.is_nan() && e.is_nan())) {
            return false
          }
        F64CanonicalNan | F64ArithmeticNan =>
          if not(actual_f.is_nan()) {
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
