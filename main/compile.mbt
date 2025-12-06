///|
/// Compile a WASM module to precompiled format
fn run_compile(
  input_path : String,
  output_path : String?,
  emit_ir : String?,
  config : CompilerConfig,
) -> Unit {
  // Load the module
  let mod_ = load_module_from_path(input_path) catch {
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

  // Get optimization level from config
  let opt_level = @ir.OptLevel::from_int(config.opt_level)

  // Create precompiled module
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let num_imports = count_func_imports(mod_.imports)

  // Build import function type indices
  let import_func_type_indices : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      import_func_type_indices.push(type_idx)
    }
  }

  // IR output buffer (if requested)
  let ir_output = match emit_ir {
    Some(_) => Some(StringBuilder::new())
    None => None
  }
  match ir_output {
    Some(buf) => {
      buf.write_string(";; IR for \{input_path}\n")
      buf.write_string(";; Functions: \{mod_.codes.length()}\n")
      buf.write_string(";; Optimization level: O\{config.opt_level}\n\n")
    }
    None => ()
  }
  println("Compiling \{mod_.codes.length()} functions...")

  // Compile each function
  for i, code in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.types[type_idx]
    let func_name = get_func_name(mod_, func_idx)

    // Stage 1: Translate WASM to IR
    let translator = @ir.Translator::new(
      func_name,
      func_type,
      code.locals,
      mod_.types,
      mod_.funcs,
      num_imports,
      import_func_type_indices,
    )
    let ir_func = translator.translate(code.body)

    // Record IR before optimization
    match ir_output {
      Some(buf) => {
        buf.write_string(";; Function \{func_idx}: \{func_name}\n")
        buf.write_string(ir_func.print())
        buf.write_string("\n")
      }
      None => ()
    }

    // Stage 2: Optimize IR
    @ir.optimize_with_level(ir_func, opt_level) |> ignore

    // Record optimized IR
    match ir_output {
      Some(buf) => {
        buf.write_string(";; After optimization:\n")
        buf.write_string(ir_func.print())
        buf.write_string("\n")
      }
      None => ()
    }

    // Stage 3: Lower to VCode
    let vcode_func = @vcode.lower_function(ir_func)

    // Stage 4: Register allocation
    let allocated = @vcode.allocate_registers_aarch64(vcode_func)

    // Stage 5: Emit machine code
    let mc = @vcode.emit_function(allocated)

    // Stage 6: Create compiled function and add to module
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    precompiled.add_function(
      func_idx, func_name, compiled, num_params, num_results,
    )

    // Progress indicator for large modules
    if mod_.codes.length() > 10 && (i + 1) % 10 == 0 {
      println("  Compiled \{i + 1}/\{mod_.codes.length()} functions...")
    }
  }

  // Write IR file if requested
  match (emit_ir, ir_output) {
    (Some(ir_path), Some(buf)) => {
      @fs.write_string_to_file(ir_path, buf.to_string()) catch {
        e => {
          println("Error writing IR file: \{e}")
          return
        }
      }
      println("Wrote IR to \{ir_path}")
    }
    _ => ()
  }

  // Serialize the precompiled module
  let cwasm_bytes = precompiled.serialize()

  // Determine output path
  let out_path = match output_path {
    Some(p) => p
    None => generate_output_path(input_path)
  }

  // Convert to Bytes
  let out_bytes = Bytes::from_iter(
    cwasm_bytes.iter().map(fn(b) { b.to_byte() }),
  )

  // Write to file
  @fs.write_bytes_to_file(out_path, out_bytes) catch {
    e => {
      println("Error writing output: \{e}")
      return
    }
  }

  // Calculate total code size
  let mut total_code_size = 0
  for i in 0..<precompiled.function_count() {
    total_code_size = total_code_size + precompiled.functions[i].code.length()
  }
  println("Wrote precompiled module to \{out_path}")
  println("  Format:    cwasm v1 (aarch64)")
  println("  Functions: \{precompiled.function_count()}")
  println("  Code size: \{total_code_size} bytes")
  println("  File size: \{cwasm_bytes.length()} bytes")
}

///|
/// Generate output path from input path
fn generate_output_path(input_path : String) -> String {
  // Replace .wasm or .wat with .cwasm
  if input_path.has_suffix(".wasm") {
    let builder = StringBuilder::new()
    let end = input_path.length() - 5
    for i in 0..<end {
      builder.write_char(input_path.code_unit_at(i).unsafe_to_char())
    }
    builder.write_string(".cwasm")
    builder.to_string()
  } else if input_path.has_suffix(".wat") {
    let builder = StringBuilder::new()
    let end = input_path.length() - 4
    for i in 0..<end {
      builder.write_char(input_path.code_unit_at(i).unsafe_to_char())
    }
    builder.write_string(".cwasm")
    builder.to_string()
  } else {
    input_path + ".cwasm"
  }
}
