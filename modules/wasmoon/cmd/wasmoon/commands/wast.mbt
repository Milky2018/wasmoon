///|
let wast_jit_compiled_modules : Ref[Int] = { val: 0, }

///|
let wast_jit_compiled_functions : Ref[Int] = { val: 0, }

///|
let wast_jit_attempts : Ref[Int] = { val: 0, }

///|
fn is_truthy_env(v : String) -> Bool {
  v == "1" || v == "true" || v == "TRUE" || v == "yes" || v == "YES"
}

///|
/// Run a WAST test script
fn run_wast(wast_path : String, use_jit : Bool, show_success : Bool) -> Int {
  wast_jit_compiled_modules.val = 0
  wast_jit_compiled_functions.val = 0
  wast_jit_attempts.val = 0
  // Read WAST file
  let content = @fs.read_file_to_string(wast_path) catch {
    IOError(message) => {
      @logger.error("reading file: \{message}")
      return 1
    }
  }

  // Parse WAST script
  let script = @wast.parse(content) catch {
    e => {
      @logger.error("parsing WAST: \{e}")
      return 1
    }
  }

  // Only now that there is a script to run: this heading introduces the
  // report below it, and a heading with no report reads like a run that was
  // cut short rather than one that never started.
  println("Running WAST script: \{wast_path}")
  let jit_status = if use_jit { "enabled" } else { "disabled" }
  println("JIT: \{jit_status}")
  println("=".repeat(50))

  // Run WAST commands with JIT compiler callback
  let base_dir = find_base_dir(wast_path)
  let jit_compiler : @wast.JITCompiler? = if use_jit {
    Some(JITCompiler(try_compile_jit))
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
  if (match @env.get_env_var("WASMOON_WAST_JIT_TRACE") {
      Some(v) => is_truthy_env(v)
      None => false
    }) {
    println(
      "WAST JIT trace: attempts=\{wast_jit_attempts.val} compiled_modules=\{wast_jit_compiled_modules.val} compiled_functions=\{wast_jit_compiled_functions.val}",
    )
  }
  println("=".repeat(50))
  // A test runner reports its verdict through its exit status. Printing the
  // tally and exiting 0 makes every failure invisible to `set -e`, to `&&`
  // chains, and to any harness that does not parse this text — which is why
  // `scripts/run_all_wast.py` had to infer the verdict from stdout.
  if result.failed > 0 {
    return 1
  }
  0
}

///|
fn remap_index(idx : Int, alias_map : Map[Int, Int]) -> Int {
  match alias_map.get(idx) {
    Some(mapped) => mapped
    None => idx
  }
}

///|
fn build_alias_map(addrs : Array[Int]) -> Map[Int, Int] {
  let first_idx_by_addr : Map[Int, Int] = Map([])
  let alias_map : Map[Int, Int] = Map([])
  for idx, addr in addrs {
    match first_idx_by_addr.get(addr) {
      Some(first_idx) => if first_idx != idx { alias_map.set(idx, first_idx) }
      None => first_idx_by_addr.set(addr, idx)
    }
  }
  alias_map
}

///|
fn rewrite_instr_indices(
  instrs : Array[@types.Instruction],
  global_alias_map : Map[Int, Int],
  tag_alias_map : Map[Int, Int],
) -> Array[@types.Instruction] {
  let rewritten : Array[@types.Instruction] = []
  for instr in instrs {
    match instr {
      GlobalGet(idx) =>
        rewritten.push(GlobalGet(remap_index(idx, global_alias_map)))
      GlobalSet(idx) =>
        rewritten.push(GlobalSet(remap_index(idx, global_alias_map)))
      Throw(tag_idx) =>
        rewritten.push(Throw(remap_index(tag_idx, tag_alias_map)))
      TryTable(block_type, handlers, body) => {
        let rewritten_handlers : Array[@types.CatchHandler] = []
        for handler in handlers {
          match handler {
            Catch(tag_idx, label_idx) =>
              rewritten_handlers.push(
                Catch(remap_index(tag_idx, tag_alias_map), label_idx),
              )
            CatchRef(tag_idx, label_idx) =>
              rewritten_handlers.push(
                CatchRef(remap_index(tag_idx, tag_alias_map), label_idx),
              )
            CatchAll(label_idx) => rewritten_handlers.push(CatchAll(label_idx))
            CatchAllRef(label_idx) =>
              rewritten_handlers.push(CatchAllRef(label_idx))
          }
        }
        rewritten.push(
          TryTable(
            block_type,
            rewritten_handlers,
            rewrite_instr_indices(body, global_alias_map, tag_alias_map),
          ),
        )
      }
      Block(block_type, body) =>
        rewritten.push(
          Block(
            block_type,
            rewrite_instr_indices(body, global_alias_map, tag_alias_map),
          ),
        )
      Loop(block_type, body) =>
        rewritten.push(
          Loop(
            block_type,
            rewrite_instr_indices(body, global_alias_map, tag_alias_map),
          ),
        )
      If(block_type, then_body, else_body) =>
        rewritten.push(
          If(
            block_type,
            rewrite_instr_indices(then_body, global_alias_map, tag_alias_map),
            rewrite_instr_indices(else_body, global_alias_map, tag_alias_map),
          ),
        )
      _ => rewritten.push(instr)
    }
  }
  rewritten
}

///|
fn rewrite_module_alias_indices_for_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
) -> @types.Module {
  let global_alias_map = build_alias_map(instance.global_addrs)
  let tag_alias_map = build_alias_map(instance.tag_addrs)
  if global_alias_map.is_empty() && tag_alias_map.is_empty() {
    return mod_
  }

  let rewritten_codes : Array[@types.FunctionCode] = []
  for code in mod_.codes {
    rewritten_codes.push({
      locals: code.locals,
      body: rewrite_instr_indices(code.body, global_alias_map, tag_alias_map),
    })
  }

  let rewritten_globals : Array[@types.Global] = []
  for global in mod_.globals {
    rewritten_globals.push({
      type_: global.type_,
      init: rewrite_instr_indices(global.init, global_alias_map, tag_alias_map),
    })
  }

  let rewritten_elems : Array[@types.Element] = []
  for elem in mod_.elems {
    let rewritten_mode = match elem.mode {
      Active(table_idx, offset_expr) =>
        @types.ElemMode::Active(
          table_idx,
          rewrite_instr_indices(offset_expr, global_alias_map, tag_alias_map),
        )
      Passive => Passive
      Declarative => Declarative
    }
    let rewritten_init : Array[Array[@types.Instruction]] = []
    for expr in elem.init {
      rewritten_init.push(
        rewrite_instr_indices(expr, global_alias_map, tag_alias_map),
      )
    }
    rewritten_elems.push({
      mode: rewritten_mode,
      type_: elem.type_,
      init: rewritten_init,
    })
  }

  let rewritten_datas : Array[@types.Data] = []
  for data in mod_.datas {
    rewritten_datas.push({
      memory_idx: data.memory_idx,
      offset: rewrite_instr_indices(
        data.offset,
        global_alias_map,
        tag_alias_map,
      ),
      init: data.init,
    })
  }

  {
    types: mod_.types,
    type_rec_groups: mod_.type_rec_groups,
    imports: mod_.imports,
    funcs: mod_.funcs,
    tables: mod_.tables,
    memories: mod_.memories,
    globals: rewritten_globals,
    exports: mod_.exports,
    start: mod_.start,
    elems: rewritten_elems,
    codes: rewritten_codes,
    datas: rewritten_datas,
    tags: mod_.tags,
    func_names: mod_.func_names,
  }
}

///|
let wast_selective_compile_threshold : Int = 0

///|
fn mark_wast_reachable_local_func(
  func_idx : Int,
  num_imports : Int,
  compile_mask : Array[Bool],
  pending_locals : Array[Int],
) -> Unit {
  let local_idx = func_idx - num_imports
  if local_idx < 0 || local_idx >= compile_mask.length() {
    return
  }
  if !compile_mask[local_idx] {
    compile_mask[local_idx] = true
    pending_locals.push(local_idx)
  }
}

///|
fn collect_wast_reachable_from_instrs(
  instrs : Array[@types.Instruction],
  num_imports : Int,
  compile_mask : Array[Bool],
  pending_locals : Array[Int],
) -> Unit {
  for instr in instrs {
    match instr {
      Call(func_idx) =>
        mark_wast_reachable_local_func(
          func_idx, num_imports, compile_mask, pending_locals,
        )
      ReturnCall(func_idx) =>
        mark_wast_reachable_local_func(
          func_idx, num_imports, compile_mask, pending_locals,
        )
      RefFunc(func_idx) =>
        mark_wast_reachable_local_func(
          func_idx, num_imports, compile_mask, pending_locals,
        )
      Block(_, body) =>
        collect_wast_reachable_from_instrs(
          body, num_imports, compile_mask, pending_locals,
        )
      Loop(_, body) =>
        collect_wast_reachable_from_instrs(
          body, num_imports, compile_mask, pending_locals,
        )
      If(_, then_body, else_body) => {
        collect_wast_reachable_from_instrs(
          then_body, num_imports, compile_mask, pending_locals,
        )
        collect_wast_reachable_from_instrs(
          else_body, num_imports, compile_mask, pending_locals,
        )
      }
      TryTable(_, _, body) =>
        collect_wast_reachable_from_instrs(
          body, num_imports, compile_mask, pending_locals,
        )
      _ => ()
    }
  }
}

///|
fn count_true(mask : Array[Bool]) -> Int {
  let mut count = 0
  for v in mask {
    if v {
      count = count + 1
    }
  }
  count
}

///|
fn build_wast_compile_mask(mod_ : @types.Module) -> Array[Bool]? {
  let total_local_funcs = mod_.codes.length()
  if total_local_funcs <= wast_selective_compile_threshold {
    return None
  }
  let num_imports = @wast.count_func_imports(mod_.imports)
  let compile_mask : Array[Bool] = []
  for _ in 0..<total_local_funcs {
    compile_mask.push(false)
  }
  let pending_locals : Array[Int] = []

  for exp in mod_.exports {
    if exp.desc is Func(func_idx) {
      mark_wast_reachable_local_func(
        func_idx, num_imports, compile_mask, pending_locals,
      )
    }
  }
  if mod_.start is Some(func_idx) {
    mark_wast_reachable_local_func(
      func_idx, num_imports, compile_mask, pending_locals,
    )
  }
  for global in mod_.globals {
    collect_wast_reachable_from_instrs(
      global.init,
      num_imports,
      compile_mask,
      pending_locals,
    )
  }
  for elem in mod_.elems {
    if elem.mode is Active(_, offset_expr) {
      collect_wast_reachable_from_instrs(
        offset_expr, num_imports, compile_mask, pending_locals,
      )
    }
    for expr in elem.init {
      collect_wast_reachable_from_instrs(
        expr, num_imports, compile_mask, pending_locals,
      )
    }
  }

  for cursor = 0; cursor < pending_locals.length(); {
    let local_idx = pending_locals[cursor]
    collect_wast_reachable_from_instrs(
      mod_.codes[local_idx].body,
      num_imports,
      compile_mask,
      pending_locals,
    )
    continue cursor + 1
  }

  let selected = count_true(compile_mask)
  if selected == 0 || selected >= total_local_funcs {
    None
  } else {
    Some(compile_mask)
  }
}

///|
fn module_has_wasi_import(mod_ : @types.Module) -> Bool {
  for imp in mod_.imports {
    if imp.mod_name == "wasi_snapshot_preview1" ||
      imp.mod_name == "wasi_unstable" {
      return true
    }
  }
  false
}

///|
/// Try to compile a module to JIT and return JITModuleContext if successful
fn try_compile_jit_with_suspension(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  classify_suspension : (@runtime.RuntimeError) -> Bool,
) -> Result[@wast.JITModuleContext, String] {
  let lowered_mod = rewrite_module_alias_indices_for_jit(mod_, instance)
  let local_compile_mask = build_wast_compile_mask(lowered_mod)
  let compiled_local_funcs = match local_compile_mask {
    Some(mask) => count_true(mask)
    None => lowered_mod.codes.length()
  }
  wast_jit_attempts.val = wast_jit_attempts.val + 1
  // Check for unsupported instructions
  if @wast.has_unsupported_instructions_for_wast(lowered_mod) {
    return Err(
      "WAST JIT strict mode: module contains instructions not supported by JIT",
    )
  }
  // Get actual memory max from the store (for imported memories)
  // This is crucial for memory.grow to enforce the correct max limit
  let actual_memory_max : Int? = if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => return Err("WAST JIT strict mode: memory not found")
    }
    let (_, max) = mem.get_limits()
    max
  } else {
    None
  }
  // Compile module to JIT
  let mut compile_failure : String? = None
  let compiled = compile_module_to_jit(
    lowered_mod,
    false, // debug mode off for wast tests
    false, // dump-on-trap off for wast tests
    actual_memory_max~,
    0, // Keep WAST JIT compile latency aligned with timeout-limited harness runs.
    false, // DWARF off for wast tests
    on_progress=fn(event) {
      if event.stage is Failed {
        compile_failure = event.message
      }
      None
    },
    local_compile_mask~,
    force_subtype_indirect_check=Some(true),
  )
  match compiled {
    None =>
      return Err(
        "WAST JIT strict mode: compile_module_to_jit failed: \{compile_failure.unwrap_or("unknown compilation error")}",
      )
    Some((artifact, _)) => {
      // Build func_signatures array for JIT module
      let func_signatures = @wast.build_func_signatures(lowered_mod)
      let external_imports = @wast.build_external_imports_for_jit(
        lowered_mod, instance, store,
      )
      // Load JIT module
      let loaded = verify_compiled_jit_artifact(artifact) catch {
        err =>
          return Err(
            "WAST JIT strict mode: artifact verification failed: \{Repr(err)}",
          )
      }
      let jit_module_result : Result[@jit.JITModule, @jit.JITModuleLoadError] = try
        @jit.JITModule::load_artifact_with_imports(
          loaded,
          func_signatures,
          external_imports,
          function_names=build_jit_function_names(lowered_mod),
        )
      catch {
        e => Err(e)
      } noraise {
        jm => Ok(jm)
      }
      match jit_module_result {
        Err(err) =>
          return Err(
            "WAST JIT strict mode: failed to create JIT module: \{err}",
          )
        Ok(jm) => {
          wast_jit_compiled_modules.val = wast_jit_compiled_modules.val + 1
          wast_jit_compiled_functions.val = wast_jit_compiled_functions.val +
            compiled_local_funcs
          @wast.register_instance_funcrefs_for_jit(jm, instance, store)
          // Allocate independent WASM stack with guard page. Native JIT
          // execution and hostcall bridges use this stack, so keep it aligned
          // with `wasmoon run`.
          jm.configure_native_fiber_stack_size(16L * 1024L * 1024L) |> ignore
          // Initialize WASI only when the module imports it.
          if module_has_wasi_import(lowered_mod) {
            jm.init_wasi_quiet([], [], [])
          }
          // Initialize all memories (multi-memory support)
          guard @wast.init_jit_memories_from_store(instance, store, jm)
            is Some(_) else {
            return Err(
              "WAST JIT strict mode: failed to initialize JIT memories from store",
            )
          }
          // Initialize globals (pass jm for tagged funcref pointers)
          let globals_ptr = @wast.init_jit_globals_from_store(
            instance, store, jm,
          )
          // WAST drives heavy cross-module table/linking flows where table
          // entries can carry function refs from different type-index spaces.
          // Always use subtype-aware indirect checks to keep semantics correct.
          let use_subtype_indirect_check = true
          // Initialize indirect table for call_indirect
          @wast.init_elem_segments(
            lowered_mod,
            jm,
            instance,
            store,
            use_subtype_indirect_check~,
          )
          // Initialize per-context data/elem segments for bulk ops (memory.init/table.init/etc).
          @wast.init_bulk_segments(
            lowered_mod,
            jm,
            instance,
            store,
            use_subtype_indirect_check~,
          ) catch {
            err =>
              return Err(
                "WAST JIT strict mode: failed to initialize JIT bulk segments: \{err}",
              )
          }
          // One-time sync: copy interpreter table contents (including active elem init)
          // into the shared JIT table memory before any JIT execution.
          @wast.sync_tables_to_jit(
            instance,
            store,
            jm,
            use_subtype_indirect_check~,
          )
          // NOTE: Memory and globals are owned by JITContext, GC handles cleanup
          // Store global_addrs and func_addrs for syncing after JIT calls
          let global_addrs_copy : Array[Int] = []
          for addr in instance.global_addrs {
            global_addrs_copy.push(addr)
          }
          let table_addrs_copy : Array[Int] = []
          for addr in instance.table_addrs {
            table_addrs_copy.push(addr)
          }
          let func_addrs_copy : Array[Int] = []
          for addr in instance.func_addrs {
            func_addrs_copy.push(addr)
          }
          let func_type_indices_copy : Array[Int] = []
          for type_idx in instance.func_type_indices {
            func_type_indices_copy.push(type_idx)
          }
          let canonical_type_indices_copy : Array[Int] = []
          for canonical_idx in instance.canonical_type_indices {
            canonical_type_indices_copy.push(canonical_idx)
          }
          let module_types_copy : Array[@types.SubType] = []
          for subtype in lowered_mod.types {
            module_types_copy.push(subtype)
          }
          let module_rec_groups_copy : Array[Int] = []
          for group in lowered_mod.type_rec_groups {
            module_rec_groups_copy.push(group)
          }
          let jit_ctx = @wast.JITModuleContext::JITModuleContext(
            jm, globals_ptr, global_addrs_copy, table_addrs_copy, func_addrs_copy,
            func_type_indices_copy, canonical_type_indices_copy, module_types_copy,
            module_rec_groups_copy, use_subtype_indirect_check,
          )
          // Cross an explicit state-coherence boundary around imported host or
          // interpreter calls made from native component code.
          @wast.install_jit_hostcall_dispatcher(
            jm,
            store,
            instance,
            before_dispatch=fn() {
              @wast.sync_jit_globals_to_store(jit_ctx, store)
              @wast.sync_jit_tables_to_store(jit_ctx, store)
            },
            after_dispatch=fn() {
              @wast.sync_store_globals_to_jit(jit_ctx, store)
              @wast.sync_tables_to_jit(
                instance,
                store,
                jm,
                use_subtype_indirect_check~,
              )
            },
            classify_suspension~,
          )
          Ok(jit_ctx)
        }
      }
    }
  }
}

///|
fn try_compile_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Result[@wast.JITModuleContext, String] {
  try_compile_jit_with_suspension(mod_, instance, store, fn(_error) { false })
}

///|
/// Run testsuite with a WAST file
pub fn run_testsuite(
  wast_path : String,
  use_jit : Bool,
  show_success : Bool,
) -> Int {
  run_wast(wast_path, use_jit, show_success)
}
