///|
/// Cross-module JIT tests
/// Tests for importing functions from one module to another in JIT mode

///|
/// Error type for cross-module JIT operations
pub suberror CrossModuleError {
  CrossModuleError(String)
}

///|
/// Test: simple cross-module function call
/// Module A exports `add(i32, i32) -> i32`
/// Module B imports it and calls it
test "cross-module: simple function import" {
  let mod_a_src = "(module (func (export \"add\") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))"
  let mod_b_src = "(module (import \"mod_a\" \"add\" (func $add (param i32 i32) (result i32))) (func (export \"call_add\") (param i32 i32) (result i32) local.get 0 local.get 1 call $add))"
  let result = compare_cross_module_jit_interp(
    [("mod_a", mod_a_src)],
    mod_b_src,
    "call_add",
    [@types.Value::I32(3), @types.Value::I32(5)],
  )
  inspect(result, content="matched")
}

///|
/// Test: cross-module with multiple imports
test "cross-module: multiple function imports" {
  let mod_a_src = "(module (func (export \"add\") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add) (func (export \"sub\") (param i32 i32) (result i32) local.get 0 local.get 1 i32.sub))"
  let mod_b_src = "(module (import \"mod_a\" \"add\" (func $add (param i32 i32) (result i32))) (import \"mod_a\" \"sub\" (func $sub (param i32 i32) (result i32))) (func (export \"add_then_sub\") (param i32 i32 i32) (result i32) local.get 0 local.get 1 call $add local.get 2 call $sub))"
  let result = compare_cross_module_jit_interp(
    [("mod_a", mod_a_src)],
    mod_b_src,
    "add_then_sub",
    [@types.Value::I32(10), @types.Value::I32(5), @types.Value::I32(3)],
  )
  inspect(result, content="matched")
}

///|
/// Test: cross-module with float functions
test "cross-module: float function import" {
  let mod_a_src = "(module (func (export \"addf\") (param f32 f32) (result f32) local.get 0 local.get 1 f32.add))"
  let mod_b_src = "(module (import \"mod_a\" \"addf\" (func $addf (param f32 f32) (result f32))) (func (export \"call_addf\") (param f32 f32) (result f32) local.get 0 local.get 1 call $addf))"
  let result = compare_cross_module_jit_interp(
    [("mod_a", mod_a_src)],
    mod_b_src,
    "call_addf",
    [@types.Value::F32(1.5), @types.Value::F32(2.5)],
  )
  inspect(result, content="matched")
}

///|
/// Test: chain of module imports (A -> B -> C)
test "cross-module: chain imports" {
  let mod_a_src = "(module (func (export \"double\") (param i32) (result i32) local.get 0 local.get 0 i32.add))"
  let mod_b_src = "(module (import \"mod_a\" \"double\" (func $double (param i32) (result i32))) (func (export \"quadruple\") (param i32) (result i32) local.get 0 call $double call $double))"
  let mod_c_src = "(module (import \"mod_b\" \"quadruple\" (func $quad (param i32) (result i32))) (func (export \"octuple\") (param i32) (result i32) local.get 0 call $quad call $quad))"
  let result = compare_cross_module_jit_interp(
    [("mod_a", mod_a_src), ("mod_b", mod_b_src)],
    mod_c_src,
    "octuple",
    [@types.Value::I32(1)],
  )
  // 1 * 8 = 8
  inspect(result, content="matched")
}

///|
test "cross-module: shared memory export/import (jit + interp)" {
  let mod_a_src =
    #|(module
    #|  (memory (export "mem") 1 3)
    #|  (func (export "set0") (param i32)
    #|    (i32.store (i32.const 0) (local.get 0)))
    #|  (func (export "get0") (result i32)
    #|    (i32.load (i32.const 0)))
    #|  (func (export "get1") (result i32)
    #|    (i32.load (i32.const 65536))))
  let mod_b_src =
    #|(module
    #|  (import "mod_a" "mem" (memory 1 3))
    #|  (func (export "grow") (result i32)
    #|    (memory.grow (i32.const 1)))
    #|  (func (export "read0") (result i32)
    #|    (i32.load (i32.const 0)))
    #|  (func (export "read1") (result i32)
    #|    (i32.load (i32.const 65536)))
    #|  (func (export "write1") (param i32)
    #|    (i32.store (i32.const 65536) (local.get 0))))
  let linker = @runtime.Linker::new()
  let mod_a = @wat.parse(mod_a_src) catch { _ => abort("parse a failed") }
  let inst_a = @executor.instantiate_with_linker(linker, "mod_a", mod_a) catch {
    _ => abort("instantiate a failed")
  }
  linker.register("mod_a", inst_a)
  let store = linker.get_store()
  let mod_b = @wat.parse(mod_b_src) catch { _ => abort("parse b failed") }
  let inst_b = @executor.instantiate_with_linker(linker, "mod_b", mod_b) catch {
    _ => abort("instantiate b failed")
  }

  // Interpreter writes, interpreter reads through import.
  @executor.call_exported_func(store, inst_a, "set0", [@types.Value::I32(11)])
  |> ignore
  let b0 = @executor.call_exported_func(store, inst_b, "read0", [])
  inspect(b0, content="[I32(11)]")

  // Compile module B to JIT and point it at the store's shared memory descriptor.
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let func_signatures = @wast.build_func_signatures(mod_b)
  let num_imports = @wast.count_func_imports(mod_b.imports)
  for i, _ in mod_b.codes {
    let func_idx = num_imports + i
    let type_idx = mod_b.funcs[i]
    let func_type = mod_b.get_func_type(type_idx)
    let func_name = @wast.get_func_name(mod_b, func_idx)
    let ir_func = @ir.translate_function(mod_b, i, name=func_name)
    let vcode_func = @lower.lower_function(ir_func)
    let allocated = @regalloc.allocate_registers_backtracking(vcode_func)
    let mc = @emit.emit_function(allocated)
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    precompiled.add_function(
      func_idx,
      func_name,
      compiled,
      func_type.params.length(),
      func_type.results.length(),
    )
  }
  guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
    abort("jit load failed")
  }
  guard @wast.init_jit_memories_from_store(inst_b, store, jm) is Some(_) else {
    abort("init jit memories failed")
  }
  let f_read0 = jm.get_func_by_name("read0").unwrap()
  let r0 = jm.call_with_context(f_read0, [])
  inspect(r0, content="[11]")

  // Grow via JIT and write into the new page; interpreter observes immediately.
  let f_grow = jm.get_func_by_name("grow").unwrap()
  let _ = jm.call_with_context(f_grow, [])
  let f_write1 = jm.get_func_by_name("write1").unwrap()
  let _ = jm.call_with_context(f_write1, [42L])
  let a1 = @executor.call_exported_func(store, inst_a, "get1", [])
  inspect(a1, content="[I32(42)]")

  // JIT-only: compile module A as well and verify JIT↔JIT sharing.
  let precompiled_a = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let func_signatures_a = @wast.build_func_signatures(mod_a)
  let num_imports_a = @wast.count_func_imports(mod_a.imports)
  for i, _ in mod_a.codes {
    let func_idx = num_imports_a + i
    let type_idx = mod_a.funcs[i]
    let func_type = mod_a.get_func_type(type_idx)
    let func_name = @wast.get_func_name(mod_a, func_idx)
    let ir_func = @ir.translate_function(mod_a, i, name=func_name)
    let vcode_func = @lower.lower_function(ir_func)
    let allocated = @regalloc.allocate_registers_backtracking(vcode_func)
    let mc = @emit.emit_function(allocated)
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    precompiled_a.add_function(
      func_idx,
      func_name,
      compiled,
      func_type.params.length(),
      func_type.results.length(),
    )
  }
  guard @jit.JITModule::load(precompiled_a, func_signatures_a) is Some(jm_a) else {
    abort("jit load (a) failed")
  }
  guard @wast.init_jit_memories_from_store(inst_a, store, jm_a) is Some(_) else {
    abort("init jit memories (a) failed")
  }

  // JIT(A) writes, JIT(B) reads.
  let f_set0 = jm_a.get_func_by_name("set0").unwrap()
  let _ = jm_a.call_with_context(f_set0, [13L])
  let r0b = jm.call_with_context(f_read0, [])
  inspect(r0b, content="[13]")

  // JIT(B) writes, JIT(A) reads from grown page.
  let _ = jm.call_with_context(f_write1, [99L])
  let f_get1 = jm_a.get_func_by_name("get1").unwrap()
  let r1a = jm_a.call_with_context(f_get1, [])
  inspect(r1a, content="[99]")
}

///|
/// Cross-module comparison result
struct CrossModuleResult {
  jit_result : Result[Array[@types.Value], String]
  interp_result : Result[Array[@types.Value], String]
  matched : Bool
}

///|
pub impl Show for CrossModuleResult with output(self, logger) {
  if self.matched {
    logger.write_string("matched")
  } else {
    logger.write_string("JIT: ")
    logger.write_object(self.jit_result)
    logger.write_string(", Interp: ")
    logger.write_object(self.interp_result)
  }
}

///|
/// Compare cross-module execution between JIT and interpreter
fn compare_cross_module_jit_interp(
  dependencies : Array[(String, String)],
  main_module : String,
  func_name : String,
  args : Array[@types.Value],
) -> CrossModuleResult {
  // Run with interpreter
  let interp_result : Result[Array[@types.Value], String] = Ok(
    run_cross_module_interp(dependencies, main_module, func_name, args),
  ) catch {
    CrossModuleError(e) => Err("Interpreter: \{e}")
  }
  // Run with JIT
  let jit_result : Result[Array[@types.Value], String] = Ok(
    run_cross_module_jit(dependencies, main_module, func_name, args),
  ) catch {
    CrossModuleError(e) => Err("JIT: \{e}")
  }
  // Compare results
  let matched = match (jit_result, interp_result) {
    (Ok(jit_vals), Ok(interp_vals)) =>
      @testsuite.values_array_equal(jit_vals, interp_vals)
    (Err(_), Err(_)) => true
    _ => false
  }
  { jit_result, interp_result, matched }
}

///|
/// Run cross-module test with interpreter
fn run_cross_module_interp(
  dependencies : Array[(String, String)],
  main_module : String,
  func_name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise CrossModuleError {
  let linker = @runtime.Linker::new()
  // Instantiate and register each dependency module
  for dep in dependencies {
    let (name, source) = dep
    let mod_ = @wat.parse(source) catch {
      e => raise CrossModuleError("parse error: \{e}")
    }
    let instance = @executor.instantiate_with_linker(linker, name, mod_) catch {
      e => raise CrossModuleError("instantiate error: \{e}")
    }
    linker.register(name, instance)
  }
  // Instantiate and run main module
  let main_mod = @wat.parse(main_module) catch {
    e => raise CrossModuleError("parse main error: \{e}")
  }
  let store = linker.get_store()
  let main_instance = @executor.instantiate_with_linker(
    linker, "main", main_mod,
  ) catch {
    e => raise CrossModuleError("instantiate main error: \{e}")
  }
  @executor.call_exported_func(store, main_instance, func_name, args) catch {
    e => raise CrossModuleError("call error: \{e}")
  }
}

///|
/// Run cross-module test with JIT using merged compilation
/// All modules are compiled together with globally unique function indices
fn run_cross_module_jit(
  dependencies : Array[(String, String)],
  main_module : String,
  func_name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise CrossModuleError {
  // Parse all modules first
  let parsed_modules : Array[(String, @types.Module)] = []
  for dep in dependencies {
    let (name, source) = dep
    let mod_ = @wat.parse(source) catch {
      e => raise CrossModuleError("parse error: \{e}")
    }
    parsed_modules.push((name, mod_))
  }
  let main_mod = @wat.parse(main_module) catch {
    e => raise CrossModuleError("parse main error: \{e}")
  }
  parsed_modules.push(("main", main_mod))

  // Calculate global function indices for each module
  // module_func_base[i] = starting global index for module i's functions
  let module_func_base : Array[Int] = []
  let mut global_func_idx = 0
  for entry in parsed_modules {
    let (_, mod_) = entry
    module_func_base.push(global_func_idx)
    let num_imports = @wast.count_func_imports(mod_.imports)
    let num_funcs = mod_.codes.length()
    global_func_idx = global_func_idx + num_imports + num_funcs
  }

  // Build export map: module_name -> func_name -> global_func_idx
  let export_map : Map[String, Map[String, Int]] = {}
  for i, entry in parsed_modules {
    let (name, mod_) = entry
    let base = module_func_base[i]
    let mod_exports : Map[String, Int] = {}
    for exp in mod_.exports {
      guard exp.desc is @types.ExportDesc::Func(local_idx) else { continue }
      mod_exports.set(exp.name, base + local_idx)
    }
    export_map.set(name, mod_exports)
  }

  // Build merged PrecompiledModule with all functions
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let all_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = Array::make(
    global_func_idx,
    ([], []),
  )
  let func_name_to_idx : Map[String, Int] = {}
  for mod_idx, entry in parsed_modules {
    let (mod_name, mod_) = entry
    let base = module_func_base[mod_idx]
    let num_imports = @wast.count_func_imports(mod_.imports)

    // Build import function type indices for this module
    let import_func_type_indices : Array[Int] = []
    for imp in mod_.imports {
      guard imp.desc is Func(type_idx) else { continue }
      import_func_type_indices.push(type_idx)
    }

    // Get memory max from module
    let memory_max : Int? = if mod_.memories.length() > 0 {
      mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
    } else {
      None
    }

    // Build memory_is_64 array for memory64 support
    let memory_is_64 = mod_.memories.map(fn(m) { m.is_memory64 })
    let memory_page_size_log2 = mod_.memories.map(fn(m) { m.page_size_log2 })

    // Compile each function in this module
    for i, code in mod_.codes {
      let local_func_idx = num_imports + i
      let global_idx = base + local_func_idx
      let type_idx = mod_.funcs[i]
      let func_type = mod_.get_func_type(type_idx)
      let f_name = get_exported_func_name(mod_, local_func_idx)

      // For cross-module calls, remap import indices to global indices
      // Create a remapped imports array
      let import_remap : Array[Int] = []
      for imp in mod_.imports {
        guard imp.desc is Func(_) else { continue }
        // Look up the global index for this import
        guard export_map.get(imp.mod_name) is Some(mod_exports) else {
          raise CrossModuleError(
            "Module '\{imp.mod_name}' not found for import '\{imp.name}'",
          )
        }
        guard mod_exports.get(imp.name) is Some(target_global_idx) else {
          raise CrossModuleError(
            "Function '\{imp.name}' not found in module '\{imp.mod_name}'",
          )
        }
        import_remap.push(target_global_idx)
      }

      // Translate to IR with import remapping
      let translator = @ir.Translator::new(
        f_name,
        func_type,
        code.locals,
        @types.extract_func_types(mod_.types),
        mod_.funcs,
        num_imports,
        import_func_type_indices,
        memory_max~,
        memory_is_64~,
        memory_page_size_log2~,
        tables=mod_.tables,
        type_rec_groups=mod_.type_rec_groups,
        func_base=base,
        import_remap~,
      )
      let ir_func = translator.translate(code.body)
      let vcode = @lower.lower_function(ir_func)
      let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
      let mc = @emit.emit_function(allocated_func)
      let compiled = @vcode.CompiledFunction::new(f_name, mc, 0)
      precompiled.add_function(
        global_idx,
        f_name,
        compiled,
        func_type.params.length(),
        func_type.results.length(),
      )
      all_signatures[global_idx] = (func_type.params, func_type.results)

      // Track main module's exported function
      if mod_name == "main" {
        func_name_to_idx.set(f_name, global_idx)
      }
    }
  }

  // Load merged JIT module
  guard @jit.JITModule::load(precompiled, all_signatures) is Some(jm) else {
    raise CrossModuleError("Failed to create merged JIT module")
  }

  // Allocate memory (guarded for memory32 memory 0)
  let mem_pages = 1
  let mem_size = mem_pages.to_int64() * 65536L
  let mem_desc_ptr = jm.alloc_guarded_memory(mem_pages, None)
  if mem_desc_ptr == 0L && mem_size > 0L {
    raise CrossModuleError("Failed to allocate memory")
  }
  let memories = [@jit.MemoryInfo::new(mem_desc_ptr, mem_size, None)]
  jm.set_memory_pointers(memories)

  // Get target function's result types
  guard func_name_to_idx.get(func_name) is Some(target_idx) else {
    raise CrossModuleError("Function '\{func_name}' not found in main module")
  }
  let (_, result_types) = all_signatures[target_idx]

  // Call the target function
  guard jm.get_func_by_name(func_name) is Some(f) else {
    raise CrossModuleError("Failed to get JIT function '\{func_name}'")
  }
  let jit_args = args.map(@testsuite.value_to_jit_arg)
  let raw_results = jm.call_with_context(f, jit_args) catch {
    e => raise CrossModuleError("JIT call error: \{e}")
  }
  @testsuite.jit_results_to_values(raw_results, result_types)
}

///|
fn get_exported_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  for exp in mod_.exports {
    if exp.desc is @types.ExportDesc::Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  "func_\{func_idx}"
}
