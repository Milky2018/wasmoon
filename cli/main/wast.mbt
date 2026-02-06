///|
/// Run a WAST test script
fn run_wast(wast_path : String, use_jit : Bool, show_success : Bool) -> Unit {
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

  // Run WAST commands with JIT compiler callback
  let base_dir = find_base_dir(wast_path)
  let jit_compiler : @wast.JITCompiler? = if use_jit {
    Some(@wast.JITCompiler::new(try_compile_jit))
  } else {
    None
  }
  let result = @wast.run_wast_commands(
    script,
    base_dir,
    use_jit,
    show_success,
    jit_compiler~,
  )

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
/// Try to compile a module to JIT and return JITModuleContext if successful
fn try_compile_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> @wast.JITModuleContext? {
  // Check for unsupported instructions
  if @wast.has_unsupported_instructions(mod_) {
    return None // Module contains instructions not supported by JIT
  }
  // Check for cross-module imports that require state sharing
  // JIT can't properly share globals/memory/tables with other modules
  if @wast.has_cross_module_imports(mod_) {
    return None // Fall back to interpreter for cross-module scenarios
  }
  // Check if module exports memory or tables that might be imported by others
  // JIT can't share its internal memory/table storage with the interpreter
  if @wast.exports_shared_resources(mod_) {
    return None // Fall back to interpreter for potential cross-module sharing
  }
  // Check if all imports are supported by JIT
  let mut func_imp_idx = 0
  for imp in mod_.imports {
    if imp.desc is Func(_) {
      let has_builtin = @jit.get_import_trampoline(imp.mod_name, imp.name)
        is Some(_)
      if not(has_builtin) {
        let func_addr = if func_imp_idx < instance.func_addrs.length() {
          instance.func_addrs[func_imp_idx]
        } else {
          -1
        }
        if func_addr < 0 {
          return None
        }
        let inst = store.get_func_inst(func_addr) catch { _ => return None }
        if inst is @runtime.FuncInst::HostFunc(_) {
          ()
        } else {
          return None // Unsupported import
        }
      }
      func_imp_idx = func_imp_idx + 1
    }
  }
  // Get actual memory max from the store (for imported memories)
  // This is crucial for memory.grow to enforce the correct max limit
  let actual_memory_max : Int? = if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => abort("Memory not found")
    }
    let (_, max) = mem.get_limits()
    max
  } else {
    None
  }
  // Compile module to JIT
  let compiled = compile_module_to_jit(
    mod_,
    false, // debug mode off for wast tests
    false, // dump-on-trap off for wast tests
    actual_memory_max~,
    2,
    false, // DWARF off for wast tests
  )
  match compiled {
    None => None
    Some((pc, _)) => {
      // Build func_signatures array for JIT module
      let func_signatures = @wast.build_func_signatures(mod_)
      let external_imports = @wast.build_external_imports_for_jit(
        mod_, instance, store,
      )
      // Load JIT module
      let jit_module_result : Result[@jit.JITModule, @jit.JITModuleLoadError] = try? @jit.JITModule::load_with_imports(
        pc, func_signatures, external_imports,
      )
      match jit_module_result {
        Err(err) => abort("Failed to create JIT module: \{err}")
        Ok(jm) => {
          // Enable arbitrary host function imports via JIT -> hostcall bridge.
          @wast.install_jit_hostcall_dispatcher(jm, store, instance)
          // Allocate independent WASM stack with guard page (1MB)
          // This provides controlled stack overflow behavior
          let _ = jm.alloc_wasm_stack(1048576L)
          // Initialize WASI for JIT (fd_table, args, env, preopens)
          // Use quiet mode to redirect stdout/stderr to /dev/null for testing
          jm.init_wasi_quiet([], [], [])
          // Initialize all memories (multi-memory support)
          guard @wast.init_jit_memories_from_store(instance, store, jm)
            is Some(_) else {
            return None
          }
          // Initialize globals (pass jm for tagged funcref pointers)
          let globals_ptr = init_jit_globals(instance, store, jm)
          if globals_ptr != 0L {
            jm.set_globals(globals_ptr)
          }
          // Initialize indirect table for call_indirect
          @wast.init_elem_segments(mod_, jm, instance, store)
          // Initialize per-context data/elem segments for bulk ops (memory.init/table.init/etc).
          @wast.init_bulk_segments(mod_, jm, instance, store)
          // One-time sync: copy interpreter table contents (including active elem init)
          // into the shared JIT table memory before any JIT execution.
          @wast.sync_tables_to_jit(instance, store, jm)
          // NOTE: Memory and globals are owned by JITContext, GC handles cleanup
          // Store global_addrs and func_addrs for syncing after JIT calls
          let global_addrs_copy : Array[Int] = []
          for addr in instance.global_addrs {
            global_addrs_copy.push(addr)
          }
          let func_addrs_copy : Array[Int] = []
          for addr in instance.func_addrs {
            func_addrs_copy.push(addr)
          }
          Some(
            @wast.JITModuleContext::new(
              jm, globals_ptr, global_addrs_copy, func_addrs_copy,
            ),
          )
        }
      }
    }
  }
}
