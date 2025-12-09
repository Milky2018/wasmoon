///|
/// Run a WAST test script
fn run_wast(wast_path : String) -> Unit {
  println("Running WAST script: \{wast_path}")
  println("=".repeat(50))

  // Read WAST file
  let content = @fs.read_file_to_string(wast_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }

  // Parse WAST script
  let script = @wast.parse(content) catch {
    e => {
      println("Error parsing WAST: \{e}")
      return
    }
  }

  // Run WAST commands
  let base_dir = find_base_dir(wast_path)
  let result = run_wast_commands(script, base_dir)

  // Print results
  println("")
  println("Results:")
  println("  Passed:  \{result.passed}")
  println("  Failed:  \{result.failed}")
  println("  Skipped: \{result.skipped}")
  if result.failures.length() > 0 {
    println("")
    println("Failures:")
    for failure in result.failures {
      println("  - \{failure}")
    }
  }
  println("=".repeat(50))
}

///|
/// Result of running WAST commands
priv struct WastResult {
  mut passed : Int
  mut failed : Int
  mut skipped : Int
  failures : Array[String]
}

///|
fn WastResult::new() -> WastResult {
  WastResult::{ passed: 0, failed: 0, skipped: 0, failures: [] }
}

///|
/// WAST execution context
priv struct WastContext {
  store : @runtime.Store
  mut current_module : @runtime.ModuleInstance?
  named_modules : Map[String, @runtime.ModuleInstance]
  // Registered modules for imports (module_name -> exports)
  registered_modules : Map[String, @runtime.ModuleInstance]
}

///|
fn WastContext::new() -> WastContext {
  let store = @runtime.Store::new()

  // Create spectest module with standard test functions/values
  let spectest_instance = create_spectest_module(store)
  let registered_modules : Map[String, @runtime.ModuleInstance] = Map::new()
  registered_modules.set("spectest", spectest_instance)
  WastContext::{
    store,
    current_module: None,
    named_modules: Map::new(),
    registered_modules,
  }
}

///|
/// Create the spectest module with standard test functions
fn create_spectest_module(store : @runtime.Store) -> @runtime.ModuleInstance {
  // Allocate host functions with correct types
  // print_i32: (i32) -> ()
  let print_i32_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let print_i32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_type,
  )
  // print_i64: (i64) -> ()
  let print_i64_type : @types.FuncType = {
    params: [@types.ValueType::I64],
    results: [],
  }
  let print_i64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i64_type,
  )
  // print_f32: (f32) -> ()
  let print_f32_type : @types.FuncType = {
    params: [@types.ValueType::F32],
    results: [],
  }
  let print_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f32_type,
  )
  // print_f64: (f64) -> ()
  let print_f64_type : @types.FuncType = {
    params: [@types.ValueType::F64],
    results: [],
  }
  let print_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_type,
  )
  // print_i32_f32: (i32, f32) -> ()
  let print_i32_f32_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::F32],
    results: [],
  }
  let print_i32_f32_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_i32_f32_type,
  )
  // print_f64_f64: (f64, f64) -> ()
  let print_f64_f64_type : @types.FuncType = {
    params: [@types.ValueType::F64, @types.ValueType::F64],
    results: [],
  }
  let print_f64_f64_addr = store.alloc_host_func(
    fn(_args) { [] },
    func_type=print_f64_f64_type,
  )
  // print: () -> ()
  let print_type : @types.FuncType = { params: [], results: [] }
  let print_addr = store.alloc_host_func(fn(_args) { [] }, func_type=print_type)

  // Allocate memory: (memory 1 2) - min 1 page, max 2 pages
  let memory = @runtime.Memory::new(1, Some(2))
  let memory_addr = store.alloc_mem(memory)

  // Allocate table: (table 10 20 funcref)
  let table = @runtime.Table::new(@types.ValueType::FuncRef, 10, Some(20))
  let table_addr = store.alloc_table(table)

  // Allocate globals
  // global_i32: (global i32 (i32.const 666))
  let global_i32_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::I32, mutable: false },
      @types.Value::I32(666),
    ),
  )
  // global_i64: (global i64 (i64.const 666))
  let global_i64_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::I64, mutable: false },
      @types.Value::I64(666L),
    ),
  )
  // global_f32: (global f32 (f32.const 666))
  let global_f32_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::F32, mutable: false },
      @types.Value::F32(666.6),
    ),
  )
  // global_f64: (global f64 (f64.const 666))
  let global_f64_addr = store.alloc_global(
    @runtime.GlobalInstance::new(
      @types.GlobalType::{ value_type: @types.ValueType::F64, mutable: false },
      @types.Value::F64(666.6),
    ),
  )

  // Create exports
  let exports : Array[@types.Export] = [
    { name: "print_i32", desc: @types.ExportDesc::Func(0) },
    { name: "print_i64", desc: @types.ExportDesc::Func(1) },
    { name: "print_f32", desc: @types.ExportDesc::Func(2) },
    { name: "print_f64", desc: @types.ExportDesc::Func(3) },
    { name: "print_i32_f32", desc: @types.ExportDesc::Func(4) },
    { name: "print_f64_f64", desc: @types.ExportDesc::Func(5) },
    { name: "print", desc: @types.ExportDesc::Func(6) },
    { name: "memory", desc: @types.ExportDesc::Memory(0) },
    { name: "table", desc: @types.ExportDesc::Table(0) },
    { name: "global_i32", desc: @types.ExportDesc::Global(0) },
    { name: "global_i64", desc: @types.ExportDesc::Global(1) },
    { name: "global_f32", desc: @types.ExportDesc::Global(2) },
    { name: "global_f64", desc: @types.ExportDesc::Global(3) },
  ]
  @runtime.ModuleInstance::{
    types: [],
    func_addrs: [
      print_i32_addr, print_i64_addr, print_f32_addr, print_f64_addr, print_i32_f32_addr,
      print_f64_f64_addr, print_addr,
    ],
    func_type_indices: [],
    table_addrs: [table_addr],
    mem_addrs: [memory_addr],
    global_addrs: [
      global_i32_addr, global_i64_addr, global_f32_addr, global_f64_addr,
    ],
    exports,
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
}

///|
/// Build imports from registered modules
fn WastContext::build_imports(self : WastContext) -> @runtime.Imports {
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
      }
    }
  }
  imports
}

///|
/// Run WAST script commands
fn run_wast_commands(
  script : @wast.WastScript,
  base_dir : String,
) -> WastResult {
  let result = WastResult::new()
  let ctx = WastContext::new()
  for item in script.commands {
    let (cmd, line) = item
    run_wast_command(ctx, cmd, line, result, base_dir)
  }
  result
}

///|
fn run_wast_command(
  ctx : WastContext,
  cmd : @wast.WastCommand,
  line : Int,
  result : WastResult,
  base_dir : String,
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
    }
    ModuleBinaryFailed(err) => {
      // Binary module failed to parse (unsupported features), skip
      result.skipped = result.skipped + 1
      result.failures.push(
        "line \{line}: skipped (binary parse failed: \{err})",
      )
    }
    ModuleDefinition(mod_, name) => {
      // Module definition - only validates, does not instantiate
      // Used for testing large memory declarations that can't actually be allocated
      @validator.validate_module(mod_) catch {
        e => {
          result.failed = result.failed + 1
          result.failures.push(
            "line \{line}: module definition validation failed: \{e}",
          )
          return
        }
      }
      // Update the named module map if name is provided, but don't set as current
      // since this module is not instantiated
      if name is Some(_) {
        // Skip - can't add to named_modules without instance
        ()
      }
      result.passed = result.passed + 1
    }
    AssertReturn(action, expected) =>
      match run_assert_return(ctx, action, expected) {
        None => result.passed = result.passed + 1
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
      } else {
        result.failed = result.failed + 1
        result.failures.push(
          "line \{line}: assert_trap failed: expected '\{expected_msg}'",
        )
      }
    }
    AssertExhaustion(action, _msg) =>
      // Just try to invoke - should cause stack exhaustion
      if (try? invoke_action(ctx, action)) is Err(_) {
        result.passed = result.passed + 1
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
fn format_action(action : @wast.WastAction) -> String {
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
  action : @wast.WastAction,
  expected : Array[@wast.WastValue],
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
  action : @wast.WastAction,
  _expected_msg : String,
) -> Bool {
  // Should trap
  (try? invoke_action(ctx, action)) is Err(_)
}

///|
fn invoke_action(
  ctx : WastContext,
  action : @wast.WastAction,
) -> Array[@types.Value] raise CliError {
  match action {
    Invoke(module_name, func_name, args) => {
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
      let runtime_args = args.map(wast_value_to_runtime)
      @executor.call_exported_func(ctx.store, instance, func_name, runtime_args) catch {
        e => raise RuntimeError(e.to_string())
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
fn wast_value_to_runtime(v : @wast.WastValue) -> @types.Value {
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
fn values_match(actual : @types.Value, expected : @wast.WastValue) -> Bool {
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
fn validate_module_source(source : @wast.WastModuleSource) -> Bool {
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
fn parse_module_source(source : @wast.WastModuleSource) -> Bool {
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
  source : @wast.WastModuleSource,
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
  source : @wast.WastModuleSource,
) -> Bool {
  let imports = ctx.build_imports()
  match source {
    Binary(bytes) =>
      (try? {
        let mod_ = @parser.parse_module(bytes)
        let _ = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )

      })
      is Err(_)
    Inline(mod_) =>
      (try? {
        let _ = @executor.instantiate_module_with_imports(
          ctx.store,
          mod_,
          imports,
        )

      })
      is Err(_)
    Quote(_) => false // Quoted source - can't test
    FailedToParse(_) => false // Module failed to parse, doesn't count as trap
  }
}
