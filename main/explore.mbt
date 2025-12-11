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

  // Determine which function to explore
  let func_idx = match func_index {
    Some(idx) => idx
    None => 0 // Default to first function
  }
  if func_idx >= mod_.codes.length() {
    println(
      "Error: function index \{func_idx} out of range (0..\{mod_.codes.length()})",
    )
    return
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
  let type_idx = mod_.funcs[func_idx]
  let func_type = mod_.types[type_idx]
  let code = mod_.codes[func_idx]
  if !html_output {
    println("== Function \{func_idx} ==")
    println("Type: \{format_func_type(func_type)}")
    println("Locals: \{code.locals.length()}")
    println("")

    // Stage 1: WASM instructions
    if show_wasm {
      println("== Stage 1: WASM Instructions ==")
      println("  Instructions: \{code.body.length()}")
      for i, instr in code.body {
        println("    \{i}: \{instr}")
      }
      println("")
    }
  }

  // Stage 2: IR (SSA form)
  let translator = @ir.Translator::new(
    "func_\{func_idx}",
    func_type,
    code.locals,
    mod_.types,
    mod_.funcs,
    num_imports,
    import_func_type_indices,
  )
  let ir_func = translator.translate(code.body)
  let ir_text = ir_func.print()
  if !html_output && show_ir {
    println("== Stage 2: IR (SSA Form) ==")
    println(ir_text)
    println("")
  }

  // Stage 3: Optimized IR
  let level = @ir.OptLevel::from_int(opt_level)
  @ir.optimize_with_level(ir_func, level) |> ignore
  let ir_optimized = ir_func.print()
  if !html_output && show_opt_ir {
    println("== Stage 3: Optimized IR (O\{opt_level}) ==")
    println(ir_optimized)
    println("")
  }

  // Stage 4: VCode (Low-level IR)
  let vcode_func = @vcode.lower_function(ir_func)
  let vcode_text = vcode_func.to_string()
  if !html_output && show_vcode {
    println("== Stage 4: VCode (Low-level IR) ==")
    println(vcode_text)
    println("")
  }

  // Stage 5: Register Allocation
  let allocated = @vcode.allocate_registers_aarch64(vcode_func)
  let allocated_text = allocated.to_string()
  if !html_output && show_regalloc {
    println("== Stage 5: After Register Allocation ==")
    println(allocated_text)
    println("")
  }

  // Stage 6: Machine Code
  let mc = @vcode.emit_function(allocated)
  if !html_output && show_mc {
    println("== Stage 6: Machine Code ==")
    println(mc.dump_disasm())
  }
  if !html_output {
    println("=".repeat(60))
    println("Exploration complete!")
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
    let html = generate_html_report(
      wasm_path, func_idx, func_type, code, ir_func, ir_optimized, vcode_text, allocated_text,
      opt_level,
    )
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
