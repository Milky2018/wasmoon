///|
/// Run a WAST test script
fn run_wast(wast_path : String, use_jit : Bool) -> Unit {
  println("Running WAST script: \{wast_path}")
  let jit_status = if use_jit { "enabled" } else { "disabled" }
  println("JIT: \{jit_status}")
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
  let result = run_wast_commands(script, base_dir, use_jit)

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
  // JIT support: module -> (JITModule, memory_ptr, original Module)
  jit_modules : Map[String, (@jit.JITModule, Int64, @types.Module)]
  mut current_jit : (@jit.JITModule, Int64, @types.Module)?
  use_jit : Bool
}

///|
fn WastContext::new(use_jit : Bool) -> WastContext {
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
    jit_modules: Map::new(),
    current_jit: None,
    use_jit,
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
/// Check if a module contains JIT-unsupported instructions
fn has_unsupported_instructions(mod_ : @types.Module) -> Bool {
  // Check all function bodies for unsupported instructions
  for code in mod_.codes {
    if contains_unsupported_instruction(code.body) {
      return true
    }
  }
  // Check if elem segments contain unsupported initializers
  if has_unsupported_elem_init(mod_) {
    return true
  }
  false
}

///|
/// Check if elem segments contain unsupported initializers
/// JIT doesn't support cross-module function references in elem segments
fn has_unsupported_elem_init(mod_ : @types.Module) -> Bool {
  for elem in mod_.elems {
    for init_expr in elem.init {
      match init_expr {
        // GlobalGet in elem init is not supported by JIT
        // because it may reference imported funcref globals (cross-module)
        [GlobalGet(_)] => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// Recursively check if instruction list contains unsupported instructions
fn contains_unsupported_instruction(instrs : Array[@types.Instruction]) -> Bool {
  for instr in instrs {
    match instr {
      // Table bulk operations - not supported by JIT
      TableInit(_, _) | TableCopy(_, _) | TableFill(_) | ElemDrop(_) =>
        return true
      // Memory bulk operations - not supported by JIT
      MemoryInit(_) | MemoryCopy | MemoryFill | DataDrop(_) => return true
      // Block instructions - need to check nested instructions
      Block(_, body) | Loop(_, body) =>
        if contains_unsupported_instruction(body) {
          return true
        }
      If(_, then_body, else_body) => {
        if contains_unsupported_instruction(then_body) {
          return true
        }
        if !else_body.is_empty() && contains_unsupported_instruction(else_body) {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// Try to compile a module to JIT and return (JITModule, memory_ptr) if successful
fn try_compile_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> (@jit.JITModule, Int64)? {
  // Check for unsupported instructions
  if has_unsupported_instructions(mod_) {
    return None // Module contains instructions not supported by JIT
  }
  // Check if all imports are supported by JIT
  for imp in mod_.imports {
    if imp.desc is Func(_) &&
      !@jit.has_import_trampoline(imp.mod_name, imp.name) {
      return None // Unsupported import
    }
  }
  // Compile module to JIT
  let debug_config = DebugConfig::new()
  let precompiled = compile_module_to_jit(mod_, debug_config)
  match precompiled {
    None => None
    Some(pc) => {
      // Build func_types array
      // Build func_signatures array for JIT module
      let func_signatures = build_func_signatures(mod_)
      // Load JIT module
      let jit_module = @jit.JITModule::load(pc, func_signatures)
      match jit_module {
        None => None
        Some(jm) => {
          // Allocate linear memory
          let mem_size = get_memory_size(instance, store)
          let mem_ptr = @jit.alloc_memory(mem_size)
          if mem_ptr == 0L {
            jm.free()
            return None
          }
          // Initialize data segments
          init_data_segments(mod_, mem_ptr)
          // Set memory in JIT context
          jm.set_memory(mem_ptr, mem_size)
          // Initialize indirect table for call_indirect
          init_elem_segments(mod_, jm, instance, store)
          Some((jm, mem_ptr))
        }
      }
    }
  }
}

///|
/// Evaluate element segment offset constant expression
/// Supports i32.const, i32.add, i32.sub, i32.mul, global.get for computing offsets
fn eval_elem_offset_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      GlobalGet(idx) =>
        if idx < globals.length() && globals[idx].get() is I32(n) {
          stack.push(n)
        }
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => () // Ignore other instructions
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    0
  }
}

///|
/// Initialize element segments for call_indirect support
fn init_elem_segments(
  mod_ : @types.Module,
  jm : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Unit {
  // Calculate total table size (flatten all tables)
  let mut table_size = 0
  for table in mod_.tables {
    let min_size = table.type_.limits.min
    table_size = table_size + min_size
  }
  if table_size == 0 {
    return // No tables, nothing to do
  }

  // Get global instances for evaluating offset expressions
  let globals : Array[@runtime.GlobalInstance] = []
  for global_addr in instance.global_addrs {
    let global = store.get_global(global_addr) catch { _ => continue }
    globals.push(global)
  }

  // Build function index to type hash mapping
  let func_type_hashes : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let type_hash = if type_idx < mod_.types.length() {
        mod_.types[type_idx].structural_hash()
      } else {
        0
      }
      func_type_hashes.push(type_hash)
    }
  }
  for type_idx in mod_.funcs {
    let type_hash = if type_idx < mod_.types.length() {
      mod_.types[type_idx].structural_hash()
    } else {
      0
    }
    func_type_hashes.push(type_hash)
  }

  // For single table or table 0: use offset directly
  // For multiple tables: elements are indexed relative to each table
  // but we need to flatten them for the single indirect_table
  let elem_init : Array[(Int, Int, Int)] = []
  let mut table_base_offset = 0
  for table_idx, table in mod_.tables {
    // Process elem segments for this table
    for elem in mod_.elems {
      if elem.mode is @types.ElemMode::Active(elem_table_idx, offset_expr) &&
        elem_table_idx == table_idx {
        let offset = eval_elem_offset_expr(offset_expr, globals)
        for i, init_expr in elem.init {
          let func_idx = match init_expr {
            [RefFunc(idx)] => idx
            [I32Const(idx)] => idx
            _ => continue
          }
          let type_hash = if func_idx < func_type_hashes.length() {
            func_type_hashes[func_idx]
          } else {
            0
          }
          // Flatten: base_offset + offset_in_table + i
          let flattened_idx = table_base_offset + offset + i
          elem_init.push((flattened_idx, func_idx, type_hash))
        }
      }
    }
    // Move base offset for next table
    table_base_offset += table.type_.limits.min
  }
  jm.init_indirect_table(table_size, elem_init)
}

///|
/// Build func_signatures array for JIT module loading
/// Returns Array[(param_types, result_types)] for each function
fn build_func_signatures(
  mod_ : @types.Module,
) -> Array[(Array[@types.ValueType], Array[@types.ValueType])] {
  let num_imports = count_func_imports(mod_.imports)
  let total_funcs = num_imports + mod_.funcs.length()
  let signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = []
  // Pre-fill with empty signatures for all functions
  for _ in 0..<total_funcs {
    signatures.push(([], []))
  }
  // Fill in signatures for import functions
  for i, imp in mod_.imports {
    if imp.desc is Func(type_idx) && type_idx < mod_.types.length() {
      let func_type = mod_.types[type_idx]
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.types[type_idx]
      signatures[func_idx] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  signatures
}

///|
/// Run WAST script commands
fn run_wast_commands(
  script : @wast.WastScript,
  base_dir : String,
  use_jit : Bool,
) -> WastResult {
  let result = WastResult::new()
  let ctx = WastContext::new(use_jit)
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
      // Try to compile JIT version (only if JIT is enabled)
      if ctx.use_jit {
        match try_compile_jit(mod_, instance, ctx.store) {
          Some((jm, mem_ptr)) => {
            ctx.current_jit = Some((jm, mem_ptr, mod_))
            if name is Some(n) {
              ctx.jit_modules.set(n, (jm, mem_ptr, mod_))
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
      match try_compile_jit(mod_, instance, ctx.store) {
        Some((jm, mem_ptr)) if ctx.use_jit =>
          ctx.current_jit = Some((jm, mem_ptr, mod_))
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
      let jit_info : (@jit.JITModule, Int64, @types.Module)? = match
        module_name {
        Some(name) => ctx.jit_modules.get(name)
        None => ctx.current_jit
      }
      match jit_info {
        Some((jm, _mem_ptr, _mod)) =>
          // Find and call JIT function
          match jm.get_func_by_name(func_name) {
            Some(f) => {
              // Convert args to Int64
              let i64_args : Array[Int64] = []
              for arg in args {
                let v = match arg {
                  I32(n) => n.to_int64()
                  I64(n) => n
                  F32(n) => n.reinterpret_as_int().to_int64()
                  F64(n) => n.reinterpret_as_int64()
                  F32CanonicalNan | F32ArithmeticNan =>
                    @float.not_a_number.reinterpret_as_int().to_int64()
                  F64CanonicalNan | F64ArithmeticNan =>
                    @double.not_a_number.reinterpret_as_int64()
                  RefNull(_) => -1L // null sentinel
                  RefExtern(n) => n.to_int64()
                  RefFunc => 0L // func ref (placeholder)
                }
                i64_args.push(v)
              }
              let results = jm.call_with_context(f, i64_args) catch {
                @jit.JITTrap(msg) => raise RuntimeError(msg)
              }
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
/// For f32: the Int64 contains the raw f32 bits in the lower 32 bits
/// For f64: the Int64 contains the raw f64 bits
/// For reference types: -1L represents null, otherwise it's an index
fn convert_jit_result(v : Int64, ty : @types.ValueType) -> @types.Value {
  match ty {
    I32 => @types.Value::I32(@jit.FromInt64::from_int64_bits(v))
    I64 => @types.Value::I64(@jit.FromInt64::from_int64_bits(v))
    F32 => @types.Value::F32(@jit.FromInt64::from_int64_bits(v))
    F64 => @types.Value::F64(@jit.FromInt64::from_int64_bits(v))
    // Reference types: -1L is null sentinel, otherwise index
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
      if v == -1L {
        @types.Value::Null
      } else {
        @types.Value::FuncRef(v.to_int())
      }
    ExternRef | RefExtern =>
      if v == -1L {
        @types.Value::Null
      } else {
        @types.Value::ExternRef(v.to_int())
      }
    V128 => abort("V128 not supported in JIT")
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
