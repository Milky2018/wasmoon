///|
/// Compiled function data for HTML report
priv struct CompiledFunc {
  name : String
  type_str : String
  source : String // WAT source code
  ir : String
  ir_opt : String
  machv : String
  vcode : String
  regalloc : String
  code_object : String
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
  target_name? : String = "host",
) -> Int {
  debug |> ignore
  // Parse stages - empty means show all
  let show_all = stages.is_empty()
  let show_source = show_all || stages.contains("source")
  let show_milkir = show_all ||
    stages.contains("milkir") ||
    stages.contains("ir")
  let show_opt_milkir = show_all ||
    stages.contains("opt-milkir") ||
    stages.contains("opt-ir")
  let show_regalloc = show_all ||
    stages.contains("allocated-vcode") ||
    stages.contains("regalloc")
  let show_mc = show_all || stages.contains("mc") || stages.contains("machv-mc")
  let show_machv = show_all || stages.contains("machv")
  let show_vcode = show_all || stages.contains("vcode")
  let show_code_object = show_all || stages.contains("code-object")
  // Load the module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      @logger.error("loading module: \{e}")
      return 1
    }
  }

  // Validate the module
  @validator.validate_module(mod_) catch {
    e => {
      // A rejected module is a failure, so it belongs on stderr behind a
      // non-zero status. Printing it and returning 0 made `explore` claim
      // success for a module it never explored.
      @logger.error("validating module: \{e}")
      return 1
    }
  }

  // Count imports to convert between absolute and local function indices
  // Absolute index = num_imports + local_index (matches JIT error messages)
  let num_imports = count_func_imports(mod_.imports)
  // Determine which functions to explore before emitting any report output.
  // User provides an absolute WebAssembly function index (including imports),
  // matching the indices shown in JIT diagnostics.
  let func_indices : Array[Int] = match func_index {
    Some(abs_idx) => {
      let local_idx = abs_idx - num_imports
      if local_idx < 0 || local_idx >= mod_.codes.length() {
        @logger.error(
          "function index \{abs_idx} out of range (\{num_imports}..\{num_imports + mod_.codes.length() - 1})",
        )
        return 1
      }
      [local_idx]
    }
    None => Array::makei(mod_.codes.length(), fn(i) { i })
  }

  // Only now that there is a report to produce: failures above must leave
  // stdout empty so scripts can treat it as data.
  if !html_output {
    println("Exploring compilation: \{wasm_path}")
    println("=".repeat(60))
  }
  let translation_context = @wasm_frontend.translation_context_from_module(
    mod_,
    @wasmoon.wasm_frontend_embedding_environment(),
  )
  let wasm_validation_context = @wasm_frontend.wasm_validation_context(
    translation_context,
  )
  if !html_output {
    println("Module loaded: \{mod_.codes.length()} functions")
    println("")
  }

  // Compile each function
  let compiled_funcs : Array[CompiledFunc] = []
  for local_idx in func_indices {
    let type_idx = mod_.funcs[local_idx]
    let func_type = mod_.validated_func_type_at(type_idx)
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
        let text = "error: \{Repr(err)}"
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
            vcode: text,
            regalloc: text,
            code_object: text,
            mc: text,
          })
        }
        continue
      }
    }
    let ir_text = milk_result.print()
    @milkir.optimize_with_level(
      milk_result,
      @milkir.OptLevel::from_int(opt_level),
    )
    |> ignore
    let ir_optimized = milk_result.print()
    let target = match target_name {
      "x64" => @wasmoon_jit.NativeTarget::X64
      "aarch64" => AArch64
      _ =>
        @wasmoon_jit.host_native_target() catch {
          err => {
            if !html_output {
              println("Unsupported host target: \{err}")
            }
            continue
          }
        }
    }
    let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
      milk_result, wasm_validation_context, target,
    ) catch {
      err => {
        let text = "Native pipeline error: \{err}"
        if !html_output {
          println(text)
        } else {
          compiled_funcs.push({
            name: func_name,
            type_str: format_func_type(func_type),
            source: source_text,
            ir: ir_text,
            ir_opt: ir_optimized,
            machv: text,
            vcode: text,
            regalloc: text,
            code_object: text,
            mc: text,
          })
        }
        continue
      }
    }
    let machv_text = diagnostics.semantic_machv
    let vcode_text = diagnostics.target_vcode
    let allocated_text = diagnostics.allocated_vcode
    let code_object_text = diagnostics.code_object
    let mc_text = diagnostics.machine_code

    if !html_output && show_milkir {
      println("")
      println("── MilkIR ──")
      println(ir_text)
    }
    if !html_output && show_opt_milkir {
      println("")
      println("── Optimized MilkIR ──")
      println(ir_optimized)
    }
    if !html_output && show_machv {
      println("")
      println("── Semantic MachV ──")
      println(machv_text)
    }
    if !html_output && show_vcode {
      println("")
      println("── Target VCode ──")
      println(vcode_text)
    }
    if !html_output && show_regalloc {
      println("")
      println("── Allocated Target VCode ──")
      println(allocated_text)
    }
    if !html_output && show_code_object {
      println("")
      println("── Unlinked Code Object ──")
      println(code_object_text)
    }
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
        machv: machv_text,
        vcode: vcode_text,
        regalloc: allocated_text,
        code_object: code_object_text,
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
      IOError(message) => {
        @logger.error("writing HTML report: \{message}")
        return 1
      }
    }
    println("HTML report written to: \{path}")
  }
  0
}

///|
fn format_func_type(ft : @types.FuncType) -> String {
  let params = ft.params.map(fn(t) { t.to_string() }).join(", ")
  let results = ft.results.map(fn(t) { t.to_string() }).join(", ")
  "(\{params}) -> (\{results})"
}
