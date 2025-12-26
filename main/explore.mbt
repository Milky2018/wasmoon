///|
/// Compiled function data for HTML report
struct CompiledFunc {
  name : String
  type_str : String
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
) -> Unit {
  // Parse stages - empty means show all
  let show_all = stages.is_empty()
  let show_wasm = show_all || stages.contains("wasm")
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
  if !html_output {
    println("Module loaded: \{mod_.codes.length()} functions")
    println("")
  }

  // Get function info
  let num_imports = count_func_imports(mod_.imports)

  // Build import function type indices
  let import_func_type_indices : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      import_func_type_indices.push(type_idx)
    }
  }

  // Build global types array (imports + module globals)
  let global_types : Array[@types.GlobalType] = []
  for imp in mod_.imports {
    if imp.desc is Global(global_type) {
      global_types.push(global_type)
    }
  }
  for global in mod_.globals {
    global_types.push(global.type_)
  }

  // Get memory max limit from module (if memory is defined)
  let memory_max : Int? = if mod_.memories.length() > 0 {
    mod_.memories[0].limits.max
  } else {
    None
  }

  // Determine which functions to explore
  let func_indices : Array[Int] = match func_index {
    Some(idx) => {
      if idx >= mod_.codes.length() {
        println(
          "Error: function index \{idx} out of range (0..\{mod_.codes.length()})",
        )
        return
      }
      [idx]
    }
    None => Array::makei(mod_.codes.length(), fn(i) { i })
  }

  // Compile each function
  let compiled_funcs : Array[CompiledFunc] = []
  for func_idx in func_indices {
    let type_idx = mod_.funcs[func_idx]
    let func_type = mod_.get_func_type(type_idx)
    let code = mod_.codes[func_idx]
    // Find function name from exports (func_idx needs to account for imports)
    let actual_func_idx = num_imports + func_idx
    let func_name : String = {
      let mut name = ""
      for exp in mod_.exports {
        if exp.desc is @types.ExportDesc::Func(idx) && idx == actual_func_idx {
          name = exp.name
          break
        }
      }
      if name == "" {
        "func_\{func_idx}"
      } else {
        name
      }
    }
    if !html_output {
      println("")
      println("╔" + "═".repeat(58) + "╗")
      println("║  \{func_name} \{format_func_type(func_type)}")
      println("╚" + "═".repeat(58) + "╝")

      // Stage 1: WASM instructions
      if show_wasm {
        println("")
        println("── WASM Instructions ──")
        for i, instr in code.body {
          println("  \{i}: \{instr}")
        }
      }
    }

    // Stage 2: IR (SSA form)
    let translator = @ir.Translator::new(
      "func_\{func_idx}",
      func_type,
      code.locals,
      @types.extract_func_types(mod_.types),
      mod_.funcs,
      num_imports,
      import_func_type_indices,
      memory_max~,
      tables=mod_.tables,
      global_types~,
      type_rec_groups=mod_.type_rec_groups,
      module_types=mod_.types,
      tags=mod_.tags,
    )
    let ir_func = translator.translate(code.body)
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
    let vcode_func = @lower.lower_function(ir_func)
    let vcode_text = vcode_func.to_string()
    if !html_output && show_vcode {
      println("")
      println("── VCode ──")
      println(vcode_text)
    }

    // Stage 5: Register Allocation
    let allocated = @lower.allocate_registers_aarch64(vcode_func)
    let allocated_text = allocated.to_string()
    if !html_output && show_regalloc {
      println("")
      println("── Register Allocation ──")
      println(allocated_text)
    }

    // Stage 6: Machine Code
    let mc = @emit.emit_function(allocated)
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
