///|
let wast_jit_compiled_modules : Ref[Int32] = { val: 0, }

///|
let wast_jit_compiled_functions : Ref[Int32] = { val: 0, }

///|
let wast_jit_attempts : Ref[Int32] = { val: 0, }

///|
fn is_truthy_env(v : String) -> Bool {
  v == "1" || v == "true" || v == "TRUE" || v == "yes" || v == "YES"
}

///|
/// Run a WAST test script
fn run_wast(
  wast_path : String,
  use_jit : Bool,
  show_success : Bool,
  bulk_memory : Bool,
  stack_switching : Bool,
  nan_canonicalization : Bool,
  wasmtime_validation : Bool,
) -> Int32 {
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
  let jit_compiler : @core_jit.JITCompiler? = if use_jit {
    Some(JITCompiler(try_compile_jit))
  } else {
    None
  }
  let result = @wast.run_wast_commands(
    script,
    use_jit,
    show_success,
    bulk_memory~,
    stack_switching~,
    nan_canonicalization~,
    wasmtime_validation~,
    jit_compiler~,
    register_named_modules=match
      @env.get_env_var("WASMOON_WAST_REGISTER_NAMED_MODULES") {
      Some(value) => is_truthy_env(value)
      None => false
    },
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
fn remap_index(idx : Int32, alias_map : Map[Int32, Int32]) -> Int32 {
  match alias_map.get(idx) {
    Some(mapped) => mapped
    None => idx
  }
}

///|
fn build_alias_map(addrs : ArrayView[Int32]) -> Map[Int32, Int32] {
  let first_idx_by_addr : Map[Int32, Int32] = Map([])
  let alias_map : Map[Int32, Int32] = Map([])
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
  instrs : ArrayView[@types.Instruction],
  global_alias_map : Map[Int32, Int32],
  tag_alias_map : Map[Int32, Int32],
) -> ReadOnlyArray[@types.Instruction] {
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
            ReadOnlyArray::from_array(rewritten_handlers),
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
  ReadOnlyArray::from_array(rewritten)
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
    let rewritten_init : Array[ReadOnlyArray[@types.Instruction]] = []
    for expr in elem.init {
      rewritten_init.push(
        rewrite_instr_indices(expr, global_alias_map, tag_alias_map),
      )
    }
    rewritten_elems.push({
      mode: rewritten_mode,
      type_: elem.type_,
      init: ReadOnlyArray::from_array(rewritten_init),
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
    ..mod_,
    globals: rewritten_globals,
    elems: rewritten_elems,
    codes: rewritten_codes,
    datas: rewritten_datas,
  }
}

///|
fn count_true(mask : Array[Bool]) -> Int32 {
  let mut count = 0
  for v in mask {
    if v {
      count = count + 1
    }
  }
  count
}

///|
fn build_export_compile_mask(mod_ : @types.Module) -> Array[Bool]? {
  let roots = []
  for exported in mod_.exports {
    if exported.desc is Func(index) {
      roots.push(index)
    }
  }
  build_compile_mask(mod_, roots)
}

///|
fn try_compile_jit_with_suspension(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  classify_suspension : (@runtime.RuntimeError) -> Bool,
) -> Result[@core_jit.JITModuleContext, String] {
  wast_jit_attempts.val += 1
  match
    compile_native_module_context(
      mod_,
      instance,
      store,
      0, // Keep WAST compilation within the unchanged harness deadlines.
      fn(compiled_functions) {
        wast_jit_compiled_modules.val += 1
        wast_jit_compiled_functions.val += compiled_functions
      },
      classify_suspension,
    ) {
    Ok(context) => Ok(context)
    Err(message) => Err("WAST " + message)
  }
}

///|
fn try_compile_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Result[@core_jit.JITModuleContext, String] {
  try_compile_jit_with_suspension(mod_, instance, store, fn(_error) { false })
}

///|
/// Run testsuite with a WAST file
pub fn run_testsuite(
  wast_path : String,
  use_jit : Bool,
  show_success : Bool,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
  nan_canonicalization~ : Bool = false,
  wasmtime_validation~ : Bool = false,
) -> Int32 {
  run_wast(
    wast_path, use_jit, show_success, bulk_memory, stack_switching, nan_canonicalization,
    wasmtime_validation,
  )
}
