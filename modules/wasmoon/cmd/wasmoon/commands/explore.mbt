///|
/// Compiled function data for HTML report
priv struct CompiledFunc {
  name : String
  type_str : String
  source : String // WAT source code
  ir : String
  ir_opt : String
  machv : String
  regalloc : String
  mc : String
}

///|
/// Explore WASM compilation process
pub fn run_explore(
  wasm_path : String,
  func_index : Int?,
  opt_level : Int,
  stages : Array[String],
  html_output : Bool,
  debug : Bool,
) -> Unit {
  debug |> ignore
  // Parse stages - empty means show all
  let show_all = stages.is_empty()
  let show_source = show_all || stages.contains("source")
  let show_ir = show_all || stages.contains("ir")
  let show_opt_ir = show_all || stages.contains("opt-ir")
  let show_regalloc = show_all || stages.contains("regalloc")
  let show_mc = show_all || stages.contains("mc")
  let show_milkir = show_all || stages.contains("milkir")
  let show_opt_milkir = show_all || stages.contains("opt-milkir")
  let show_machv = show_all || stages.contains("machv")
  let show_machv_mc = show_all || stages.contains("machv-mc")
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
          if exp.desc is Func(idx) && idx == actual_func_idx {
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

    let env = @wasmoon.wasm_frontend_embedding_environment()
    let milk_result = @wasm_frontend.translate_function(
      env,
      mod_,
      local_idx,
      name=func_name,
    ) catch {
      err => {
        let text = "error: \{to_repr(err)}"
        if !html_output {
          println("")
          println("── Compiler Infrastructure ──")
          println(text)
        }
        if html_output {
          compiled_funcs.push({
            name: func_name,
            type_str: format_func_type(func_type),
            source: source_text,
            ir: text,
            ir_opt: text,
            machv: text,
            regalloc: text,
            mc: text,
          })
        }
        continue
      }
    }
    let ir_text = milk_result.print()
    if !html_output && show_ir {
      println("")
      println("── MilkIR (ir alias) ──")
      println(ir_text)
    }

    @milkir.optimize_with_level(
      milk_result,
      @milkir.OptLevel::from_int(opt_level),
    )
    |> ignore
    let ir_optimized = milk_result.print()
    if !html_output && show_opt_ir {
      println("")
      println("── Optimized MilkIR (opt-ir alias) ──")
      println(ir_optimized)
    }

    let target : @machv_emit.EmitTarget = match
      @wasmoon_jit.host_target_arch() {
      AArch64 => AArch64
      X86_64 => X64
      Unknown => X64
    }
    let mach_result = @wasmoon_jit.lower_wasm_body_milkir_for_target(
      milk_result, target,
    ) catch {
      err => {
        if !html_output {
          println("MilkIR lowering error: \{err}")
        }
        continue
      }
    }
    let machv_text = mach_result.print()
    if !html_output && show_machv {
      println("")
      println("── MachV ──")
      println(machv_text)
    }

    let allocated_text = "MachV register allocation is integrated into the wasmoon_jit planning pipeline."
    if !html_output && show_regalloc {
      println("")
      println("── Register Allocation ──")
      println(allocated_text)
    }

    let plan = @wasmoon_jit.plan_wasm_body_milkir_integration_for_target(
      milk_result, target,
    ) catch {
      err => {
        if !html_output {
          println("MilkIR planning error: \{err}")
        }
        continue
      }
    }
    let mc_text = plan.object
      .get_bytes()
      .map(fn(b) { @types.to_hex_byte(b) })
      .join(" ")
    if !html_output && show_mc {
      println("")
      println("── Machine Code ──")
      println(mc_text)
    }

    if !html_output &&
      (show_milkir || show_opt_milkir || show_machv || show_machv_mc) {
      if show_milkir {
        println("")
        println("── MilkIR ──")
        println(ir_text)
      }
      if show_opt_milkir {
        println("")
        println("── Optimized MilkIR ──")
        println(ir_optimized)
      }
      if show_machv {
        println("")
        println("── MachV ──")
        println(machv_text)
      }
      if show_machv_mc {
        println("")
        println("── MachV Machine Code ──")
        println(mc_text)
      }
    }

    // Collect for HTML
    if html_output {
      compiled_funcs.push({
        name: func_name,
        type_str: format_func_type(func_type),
        source: source_text,
        ir: ir_text,
        ir_opt: ir_optimized,
        machv: machv_text,
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
      wasm_path[:wasm_path.length() - 4].to_owned() + ".html"
    } else if wasm_path.has_suffix(".wasm") {
      wasm_path[:wasm_path.length() - 5].to_owned() + ".html"
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
