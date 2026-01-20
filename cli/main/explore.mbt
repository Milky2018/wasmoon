///|
/// Compiled function data for HTML report
struct CompiledFunc {
  name : String
  type_str : String
  source : String // WAT source code
  ir : String
  ir_opt : String
  vcode : String
  regalloc : String
  mc : String
}

///|
/// Explore WASM compilation process
fn run_explore(
  wasm_path : String,
  func_index : Int?,
  opt_level : Int,
  stages : Array[String],
  html_output : Bool,
  debug : Bool,
) -> Unit {
  // Parse stages - empty means show all
  let show_all = stages.is_empty()
  let show_source = show_all || stages.contains("source")
  let show_ir = show_all || stages.contains("ir")
  let show_opt_ir = show_all || stages.contains("opt-ir")
  let show_vcode = show_all || stages.contains("vcode")
  let show_regalloc = show_all || stages.contains("regalloc")
  let show_mc = show_all || stages.contains("mc")
  if !html_output {
    println("Exploring compilation: \{wasm_path}")
    println("=".repeat(60))
  }

  // Load the module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      println("Error loading module: \{e}")
      return
    }
  }

  // Validate the module
  @validator.validate_module(mod_) catch {
    e => {
      println("Validation error: \{e}")
      return
    }
  }
  // Count imports to convert between absolute and local function indices
  // Absolute index = num_imports + local_index (matches JIT error messages)
  let num_imports = count_func_imports(mod_.imports)
  if !html_output {
    println("Module loaded: \{mod_.codes.length()} functions")
    println("")
  }

  // Determine which functions to explore
  // User provides absolute WebAssembly function index (including imports)
  // This matches the indices shown in JIT error messages (wasm=N)
  let func_indices : Array[Int] = match func_index {
    Some(abs_idx) => {
      // Convert absolute index to local index
      let local_idx = abs_idx - num_imports
      if local_idx < 0 || local_idx >= mod_.codes.length() {
        println(
          "Error: function index \{abs_idx} out of range (\{num_imports}..\{num_imports + mod_.codes.length() - 1})",
        )
        return
      }
      [local_idx]
    }
    None => Array::makei(mod_.codes.length(), fn(i) { i })
  }

  // Compile each function
  let compiled_funcs : Array[CompiledFunc] = []
  for local_idx in func_indices {
    let type_idx = mod_.funcs[local_idx]
    let func_type = mod_.get_func_type(type_idx)
    let code = mod_.codes[local_idx]
    // Find function name: prefer internal name, then export name, then anonymous
    let actual_func_idx = num_imports + local_idx
    // First, check for internal name from WAT parsing (e.g., $some_func -> "some_func")
    let func_name : String = match mod_.func_names.get(actual_func_idx) {
      Some(name) => name
      None => {
        // Fall back to export name
        let mut export_name = ""
        for exp in mod_.exports {
          if exp.desc is @types.ExportDesc::Func(idx) && idx == actual_func_idx {
            export_name = exp.name
            break
          }
        }
        if export_name == "" {
          "func_\{actual_func_idx}"
        } else {
          export_name
        }
      }
    }
    // Generate WAT source text for this function
    let source_text = func_to_wat(func_name, func_type, code.locals, code.body)
    if !html_output {
      println("")
      println("╔" + "═".repeat(58) + "╗")
      println("║  \{func_name} \{format_func_type(func_type)}")
      println("╚" + "═".repeat(58) + "╝")

      // Stage 1: WAT Source
      if show_source {
        println("")
        println("── WAT Source ──")
        println(source_text)
      }
    }

    // Stage 2: IR (SSA form) - use simplified from_module API
    let ir_func = @ir.translate_function(mod_, local_idx)
    let ir_text = ir_func.print()
    if !html_output && show_ir {
      println("")
      println("── IR (SSA Form) ──")
      println(ir_text)
    }

    // Stage 3: Optimized IR
    let level = @ir.OptLevel::from_int(opt_level)
    @ir.optimize_with_level(ir_func, level) |> ignore
    let ir_optimized = ir_func.print()
    if !html_output && show_opt_ir {
      println("")
      println("── Optimized IR ──")
      println(ir_optimized)
    }

    // Stage 4: VCode (Low-level IR)
    let vcode_func = @lower.lower_function(
      ir_func,
      num_imports=mod_.imports.length(),
    )
    let vcode_text = vcode_func.to_string()
    if !html_output && show_vcode {
      println("")
      println("── VCode ──")
      println(vcode_text)
    }

    // Stage 5: Register Allocation
    let allocated = @regalloc.allocate_registers_backtracking(vcode_func)
    let allocated_text = allocated.to_string()
    if !html_output && show_regalloc {
      println("")
      println("── Register Allocation ──")
      println(allocated_text)
    }

    // Stage 6: Machine Code
    let debug_func_idx = if debug { Some(actual_func_idx) } else { None }
    let mc = @emit.emit_function(allocated, debug_func_idx~)
    let mc_text = mc.dump_disasm()
    if !html_output && show_mc {
      println("")
      println("── Machine Code ──")
      println(mc_text)
    }

    // Collect for HTML
    if html_output {
      compiled_funcs.push({
        name: func_name,
        type_str: format_func_type(func_type),
        source: source_text,
        ir: ir_text,
        ir_opt: ir_optimized,
        vcode: vcode_text,
        regalloc: allocated_text,
        mc: mc_text,
      })
    }
  }
  if !html_output {
    println("")
  }

  // Generate HTML report if requested
  if html_output {
    // Generate output path from input file: foo.wat -> foo.html
    let path = if wasm_path.has_suffix(".wat") {
      try! (wasm_path[:wasm_path.length() - 4].to_string() + ".html")
    } else if wasm_path.has_suffix(".wasm") {
      try! (wasm_path[:wasm_path.length() - 5].to_string() + ".html")
    } else {
      wasm_path + ".html"
    }
    let html = generate_html_report(compiled_funcs)
    @fs.write_string_to_file(path, html) catch {
      e => {
        println("Error writing HTML report: \{e}")
        return
      }
    }
    println("HTML report written to: \{path}")
  }
}

///|
fn format_func_type(ft : @types.FuncType) -> String {
  let params = ft.params.map(fn(t) { t.to_string() }).join(", ")
  let results = ft.results.map(fn(t) { t.to_string() }).join(", ")
  "(\{params}) -> (\{results})"
}
