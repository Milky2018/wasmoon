///|
/// Find base directory from a file path
fn find_base_dir(path : String) -> String {
  let mut last_slash = -1
  for i in 0..<path.length() {
    if path[i] == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 {
    let builder = StringBuilder::new()
    for i in 0..<last_slash {
      builder.write_char(path[i].unsafe_to_char())
    }
    builder.to_string()
  } else {
    "."
  }
}

///|
/// Run testsuite with a JSON spec file
async fn run_testsuite(json_path : String) -> Unit {
  println("Running testsuite: \{json_path}")
  println("=".repeat(50))
  // Read JSON file
  let json_data = @fs.read_file(json_path)
  let json_content = json_data.text() catch {
    e => {
      println("Error reading JSON file: \{e}")
      return
    }
  }
  // Determine base directory
  let base_dir = find_base_dir(json_path)
  // Run tests - use a wrapper that calls async
  let result = run_tests_internal(json_content, base_dir) catch {
    _ => {
      println("Error running tests")
      return
    }
  }
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
/// Internal test runner that handles file reading
async fn run_tests_internal(
  json_content : String,
  base_dir : String,
) -> @testsuite.TestResult raise Error {
  let parsed = @testsuite.parse_json_test_file(json_content)
  let result = @testsuite.TestResult::new()
  result.source_filename = parsed.source_filename
  let ctx = @testsuite.TestContext::new()
  for cmd in parsed.commands {
    run_test_command_async(ctx, cmd.command, cmd.line, result, base_dir)
  }
  result
}

///|
/// Read wasm file for a command that needs it
async fn read_wasm_file(base_dir : String, filename : String) -> Bytes? {
  let wasm_path = base_dir + "/" + filename
  let data = Some(@fs.read_file(wasm_path)) catch { _ => None }
  match data {
    Some(d) => Some(d.binary())
    None => None
  }
}

///|
/// Async wrapper for running a test command - handles file I/O inline
async fn run_test_command_async(
  ctx : @testsuite.TestContext,
  cmd : @testsuite.TestCommand,
  line : Int?,
  result : @testsuite.TestResult,
  base_dir : String,
) -> Unit {
  let line_prefix = match line {
    Some(n) => "[line \{n}] "
    None => ""
  }
  match cmd {
    Module(filename) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) =>
          try {
            let instance = ctx.load_module(b, None)
            ctx.set_current_module(instance)
          } catch {
            e =>
              result.add_failed(
                "\{line_prefix}Failed to load module \{filename}: \{e}",
              )
          }
        None => {
          result.add_skipped()
          println("\{line_prefix}File not found: \{filename}")
        }
      }
    }
    AssertReturn(action, expected) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = @testsuite.run_assert_return(
            ctx, module_name, func_name, args, expected,
          )
          if success {
            result.add_passed()
          } else {
            result.add_failed(
              "\{line_prefix}assert_return failed: \{func_name}",
            )
          }
        }
        Get(_module_name, field) => {
          result.add_skipped()
          println("\{line_prefix}Skipping assert_return (get): \{field}")
        }
      }
    AssertTrap(action, expected_msg) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = @testsuite.run_assert_trap(
            ctx, module_name, func_name, args, expected_msg,
          )
          if success {
            result.add_passed()
          } else {
            result.add_failed("\{line_prefix}assert_trap failed: \{func_name}")
          }
        }
        Get(_, field) => {
          result.add_skipped()
          println("\{line_prefix}Skipping assert_trap (get): \{field}")
        }
      }
    AssertInvalid(filename, _msg) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) => {
          let valid = try {
            let mod = @parser.parse_module(b)
            @validator.validate_module(mod)
            true
          } catch {
            _ => false
          }
          if valid {
            result.add_failed(
              "\{line_prefix}assert_invalid should have failed: \{filename}",
            )
          } else {
            result.add_passed()
          }
        }
        None => result.add_skipped()
      }
    }
    AssertMalformed(filename, _msg) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) => {
          let parsed = try {
            @parser.parse_module(b) |> ignore
            true
          } catch {
            _ => false
          }
          if parsed {
            result.add_failed(
              "\{line_prefix}assert_malformed should have failed: \{filename}",
            )
          } else {
            result.add_passed()
          }
        }
        None => result.add_skipped()
      }
    }
    AssertUninstantiable(filename, _msg) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) => {
          let instantiated = try {
            ctx.load_module(b, None) |> ignore
            true
          } catch {
            _ => false
          }
          if instantiated {
            result.add_failed(
              "\{line_prefix}assert_uninstantiable should have failed: \{filename}",
            )
          } else {
            result.add_passed()
          }
        }
        None => result.add_skipped()
      }
    }
    Register(as_, name) =>
      match ctx.get_current_module() {
        Some(inst) => {
          ctx.named_modules.set(as_, inst)
          match name {
            Some(n) => ctx.named_modules.set(n, inst)
            None => ()
          }
        }
        None =>
          println("\{line_prefix}Warning: Register without current module")
      }
    Action(action) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let runtime_args = args.map(@testsuite.parse_test_value)
          try ctx.invoke(module_name, func_name, runtime_args) |> ignore catch {
            e => println("\{line_prefix}Action invoke error: \{e}")
          }
        }
        Get(_, _) => ()
      }
  }
}

///|
/// Disassemble a WASM file
async fn run_disasm(wasm_path : String) -> Unit {
  let data = @fs.read_file(wasm_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let bytes = data.binary()
  let mod_ = @parser.parse_module(bytes) catch {
    e => {
      println("Error parsing module: \{e}")
      return
    }
  }
  let output = @disasm.disassemble(mod_)
  println(output)
}

///|
/// Format a WASM value for display
fn format_value(v : @types.Value) -> String {
  match v {
    I32(n) => n.to_string()
    I64(n) => n.to_string()
    F32(n) => n.to_string()
    F64(n) => n.to_string()
    Null => "null"
    FuncRef(idx) => "funcref(\{idx})"
    ExternRef(idx) => "externref(\{idx})"
  }
}

///|
/// Run a WASM module
/// If invoke is specified, call that function with args
/// Otherwise, run the start function or _start export
async fn run_wasm(
  wasm_path : String,
  invoke : String?,
  func_args : Array[String],
  preloads : Array[String],
) -> Unit {
  // Create linker for module linking
  let linker = @runtime.Linker::new()
  // Load preloaded modules
  for preload in preloads {
    // Parse NAME=PATH format
    let parts = split_preload(preload)
    match parts {
      Some((name, path)) => {
        let preload_mod = load_module_from_path(path) catch {
          e => {
            println("Error loading preload module '\{name}': \{e}")
            return
          }
        }
        let preload_instance = @executor.instantiate_with_linker(
          linker, name, preload_mod,
        ) catch {
          e => {
            println("Error instantiating preload module '\{name}': \{e}")
            return
          }
        }
        linker.register(name, preload_instance)
      }
      None => {
        println(
          "Error: invalid preload format '\{preload}', expected NAME=PATH",
        )
        return
      }
    }
  }
  // Load main module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      println("Error: \{e}")
      return
    }
  }
  // Instantiate the main module
  let store = linker.get_store()
  let imports = linker.build_imports()
  let instance = @executor.instantiate_module_with_imports(store, mod_, imports) catch {
    e => {
      println("Error instantiating module: \{e}")
      return
    }
  }
  // Determine which function to call
  let func_name = match invoke {
    Some(name) => name
    None => "_start" // Default to WASI-style entry point
  }
  // Find the function type to parse arguments correctly
  let func_type = find_exported_func_type(mod_, func_name)
  match func_type {
    Some(ft) => {
      // Parse arguments according to function type
      let args = parse_func_args(ft.params, func_args) catch {
        e => {
          println("Error parsing arguments: \{e}")
          return
        }
      }
      // Call the function
      let results = @executor.call_exported_func(
        store, instance, func_name, args,
      ) catch {
        e => {
          println("Error: \{e}")
          return
        }
      }
      // Print results
      if results.length() > 0 {
        let result_strs = results.map(format_value)
        println(result_strs.join(" "))
      }
    }
    None =>
      // No exported function found, check if there's a start function
      match invoke {
        Some(name) => println("Error: function '\{name}' not found")
        None =>
          // Module was already initialized with start function if present
          ()
      }
  }
}

///|
/// Split preload string in NAME=PATH format
fn split_preload(s : String) -> (String, String)? {
  let mut eq_idx = -1
  for i in 0..<s.length() {
    if s[i] == '=' {
      eq_idx = i
      break
    }
  }
  if eq_idx <= 0 {
    return None
  }
  // Build name and path strings manually
  let name_builder = StringBuilder::new()
  for i in 0..<eq_idx {
    name_builder.write_char(s[i].unsafe_to_char())
  }
  let path_builder = StringBuilder::new()
  for i = eq_idx + 1; i < s.length(); i = i + 1 {
    path_builder.write_char(s[i].unsafe_to_char())
  }
  Some((name_builder.to_string(), path_builder.to_string()))
}

///|
/// Load a module from file path (supports both .wasm and .wat)
async fn load_module_from_path(path : String) -> @types.Module raise Error {
  let is_wat = path.has_suffix(".wat")
  if is_wat {
    let data = @fs.read_file(path)
    let content = data.text() catch { e => raise e }
    @wat.parse(content) catch {
      e => raise e
    }
  } else {
    let data = @fs.read_file(path)
    let bytes = data.binary()
    @parser.parse_module(bytes) catch {
      e => raise e
    }
  }
}

///|
/// Find the type of an exported function
fn find_exported_func_type(
  mod_ : @types.Module,
  func_name : String,
) -> @types.FuncType? {
  for exp in mod_.exports {
    if exp.name == func_name {
      if exp.desc is Func(idx) {
        // Get the type index for this function
        // Account for imported functions
        let num_imports = count_func_imports(mod_.imports)
        let type_idx = if idx < num_imports {
          // It's an imported function
          get_import_func_type_idx(mod_.imports, idx)
        } else {
          // It's a defined function
          let func_idx = idx - num_imports
          if func_idx < mod_.funcs.length() {
            Some(mod_.funcs[func_idx])
          } else {
            None
          }
        }
        if type_idx is Some(tidx) && tidx < mod_.types.length() {
          return Some(mod_.types[tidx])
        }
      }
    }
  }
  None
}

///|
/// Count function imports
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Get type index for an imported function
fn get_import_func_type_idx(imports : Array[@types.Import], idx : Int) -> Int? {
  let mut func_count = 0
  for imp in imports {
    match imp.desc {
      Func(type_idx) => {
        if func_count == idx {
          return Some(type_idx)
        }
        func_count = func_count + 1
      }
      _ => ()
    }
  }
  None
}

///|
/// Parse function arguments according to parameter types
fn parse_func_args(
  params : Array[@types.ValueType],
  args : Array[String],
) -> Array[@types.Value] raise Error {
  if args.length() != params.length() {
    raise Failure("Expected \{params.length()} arguments, got \{args.length()}")
  }
  let result : Array[@types.Value] = []
  for i, param in params {
    let arg = args[i]
    let value = match param {
      I32 => {
        let n = @strconv.parse_int(arg) catch {
          _ => {
            // Try parsing as unsigned
            let u = @strconv.parse_uint(arg) catch {
              _ => raise Failure("Invalid i32 value: \{arg}")
            }
            u.reinterpret_as_int()
          }
        }
        @types.Value::I32(n)
      }
      I64 => {
        let n = @strconv.parse_int64(arg) catch {
          _ => {
            let u = @strconv.parse_uint64(arg) catch {
              _ => raise Failure("Invalid i64 value: \{arg}")
            }
            u.reinterpret_as_int64()
          }
        }
        @types.Value::I64(n)
      }
      F32 => {
        let n = @strconv.parse_double(arg) catch {
          _ => raise Failure("Invalid f32 value: \{arg}")
        }
        @types.Value::F32(n.to_float())
      }
      F64 => {
        let n = @strconv.parse_double(arg) catch {
          _ => raise Failure("Invalid f64 value: \{arg}")
        }
        @types.Value::F64(n)
      }
      FuncRef => raise Failure("Cannot pass funcref as argument")
      ExternRef => raise Failure("Cannot pass externref as argument")
      _ => raise Failure("Unknown parameter type")
    }
    result.push(value)
  }
  result
}

///|
/// Generate output path from input path
fn generate_output_path(input_path : String) -> String {
  // Replace .wasm or .wat with .cwasm
  if input_path.has_suffix(".wasm") {
    let builder = StringBuilder::new()
    for i = 0; i < input_path.length() - 5; i = i + 1 {
      builder.write_char(input_path[i].unsafe_to_char())
    }
    builder.write_string(".cwasm")
    builder.to_string()
  } else if input_path.has_suffix(".wat") {
    let builder = StringBuilder::new()
    for i = 0; i < input_path.length() - 4; i = i + 1 {
      builder.write_char(input_path[i].unsafe_to_char())
    }
    builder.write_string(".cwasm")
    builder.to_string()
  } else {
    input_path + ".cwasm"
  }
}

///|
/// Compile a WASM module to precompiled format
async fn run_compile(
  input_path : String,
  output_path : String?,
  emit_ir : String?,
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

  // Emit IR if requested
  match emit_ir {
    Some(ir_path) => {
      let ir_output = StringBuilder::new()
      ir_output.write_string(";; IR for \{input_path}\n")
      ir_output.write_string(";; Functions: \{mod_.codes.length()}\n\n")

      // For now, just list the functions
      for i, _code in mod_.codes {
        let num_imports = count_func_imports(mod_.imports)
        let func_idx = num_imports + i
        ir_output.write_string(";; Function \{func_idx}\n")
      }

      // Convert string to bytes
      let content = ir_output.to_string()
      let bytes = Bytes::from_iter(
        content.iter().map(fn(c) { c.to_int().to_byte() }),
      )

      // Write IR file
      @fs.write_file(ir_path, bytes) catch {
        e => {
          println("Error writing IR file: \{e}")
          return
        }
      }
      println("Wrote IR to \{ir_path}")
    }
    None => ()
  }

  // Create precompiled module (placeholder - actual compilation would happen here)
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)

  // For now, we just create an empty precompiled module
  // In a full implementation, we would:
  // 1. Translate each function to IR
  // 2. Apply optimizations
  // 3. Lower to VCode
  // 4. Do register allocation
  // 5. Emit machine code

  println("Compiling \{mod_.codes.length()} functions...")

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
  @fs.write_file(out_path, out_bytes) catch {
    e => {
      println("Error writing output: \{e}")
      return
    }
  }
  println("Wrote precompiled module to \{out_path}")
  println("Format: cwasm v1 (aarch64)")
  println("Functions: \{precompiled.function_count()}")
  println("Size: \{cwasm_bytes.length()} bytes")
}

///|
/// Parse and display a WAT file
async fn run_wat(wat_path : String) -> Unit {
  let data = @fs.read_file(wat_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let content = data.text() catch {
    e => {
      println("Error reading file as text: \{e}")
      return
    }
  }
  let mod_ = @wat.parse(content) catch {
    e => {
      println("Error parsing WAT: \{e}")
      return
    }
  }
  // Display parsed module using the disassembler
  let output = @disasm.disassemble(mod_)
  println("Parsed WAT module:")
  println(output)
}

///|
/// Explore WASM compilation process
async fn run_explore(
  wasm_path : String,
  func_index : Int?,
  opt_level : Int,
) -> Unit {
  println("Exploring compilation: \{wasm_path}")
  println("=".repeat(60))

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
  println("Module loaded: \{mod_.codes.length()} functions")
  println("")

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
  let type_idx = mod_.funcs[func_idx]
  let func_type = mod_.types[type_idx]
  let code = mod_.codes[func_idx]
  println("== Function \{func_idx} ==")
  println("Type: \{format_func_type(func_type)}")
  println("Locals: \{code.locals.length()}")
  println("")

  // Stage 1: WASM instructions
  println("== Stage 1: WASM Instructions ==")
  println("  Instructions: \{code.body.length()}")
  for i, instr in code.body {
    println("    \{i}: \{instr}")
  }
  println("")

  // Stage 2: IR (SSA form)
  println("== Stage 2: IR (SSA Form) ==")
  let translator = @ir.Translator::new(
    "func_\{func_idx}",
    func_type,
    code.locals,
    mod_.types,
    mod_.funcs,
    num_imports,
  )
  let ir_func = translator.translate(code.body)
  println(ir_func.print())
  println("")

  // Stage 3: Optimized IR
  let level = @ir.OptLevel::from_int(opt_level)
  println("== Stage 3: Optimized IR (O\{opt_level}) ==")
  @ir.optimize_with_level(ir_func, level) |> ignore
  println(ir_func.print())
  println("")

  // Stage 4: VCode (Low-level IR)
  println("== Stage 4: VCode (Low-level IR) ==")
  let vcode_func = @vcode.lower_function(ir_func)
  println(vcode_func.to_string())
  println("")

  // Stage 5: Register Allocation
  println("== Stage 5: After Register Allocation ==")
  let allocated = @vcode.allocate_registers_aarch64(vcode_func)
  println(allocated.to_string())
  println("")
  println("=".repeat(60))
  println("Exploration complete!")
}

///|
fn format_func_type(ft : @types.FuncType) -> String {
  let params = ft.params.map(fn(t) { t.to_string() }).join(", ")
  let results = ft.results.map(fn(t) { t.to_string() }).join(", ")
  "(\{params}) -> (\{results})"
}

///|
/// Inspect a precompiled .cwasm file
async fn run_objdump(cwasm_path : String) -> Unit {
  println("Inspecting: \{cwasm_path}")
  println("=".repeat(60))

  // Read the file
  let data = @fs.read_file(cwasm_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let bytes_raw = data.binary()

  // Convert Bytes to Array[Int]
  let bytes : Array[Int] = []
  for i in 0..<bytes_raw.length() {
    bytes.push(bytes_raw[i].to_int())
  }

  // Deserialize the precompiled module
  let precompiled = @cwasm.deserialize(bytes) catch {
    e => {
      println("Error parsing cwasm: \{e}")
      return
    }
  }

  // Display metadata
  println("")
  println("== Metadata ==")
  println("  Format:       cwasm")
  println("  Version:      \{precompiled.version}")
  println("  Target:       \{precompiled.target}")
  println("  Functions:    \{precompiled.functions.length()}")
  println("")

  // Calculate total code size
  let mut total_code_size = 0
  for func in precompiled.functions {
    total_code_size = total_code_size + func.code.length()
  }
  println("  Total code:   \{total_code_size} bytes")
  println("")

  // Display section info
  println("== Functions ==")
  if precompiled.functions.length() == 0 {
    println("  (no compiled functions)")
  } else {
    for func in precompiled.functions {
      println("")
      println("  Function \{func.func_idx}:")
      println("    Name:         \{func.name}")
      println("    Code size:    \{func.code.length()} bytes")
      println("    Frame size:   \{func.frame_size} bytes")
      println("    Entry offset: \{func.entry_offset}")

      // Show first few bytes of code as hex
      if func.code.length() > 0 {
        let hex_preview = StringBuilder::new()
        let preview_len = if func.code.length() > 16 {
          16
        } else {
          func.code.length()
        }
        for i in 0..<preview_len {
          if i > 0 {
            hex_preview.write_string(" ")
          }
          let b = func.code[i]
          hex_preview.write_string(to_hex_byte(b))
        }
        if func.code.length() > 16 {
          hex_preview.write_string(" ...")
        }
        println("    Code preview: \{hex_preview.to_string()}")
      }
    }
  }
  println("")
  println("=".repeat(60))
}

///|
fn to_hex_byte(b : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let high = (b >> 4) & 0xF
  let low = b & 0xF
  String::make(1, hex_chars[high].unsafe_to_char()) +
  String::make(1, hex_chars[low].unsafe_to_char())
}

///|
async fn main {
  let parser = @clap.Parser::new(
    prog="wasmoon",
    description="WebAssembly Runtime in MoonBit",
    subcmds={
      "run": @clap.SubCommand::new(help="Run a WebAssembly module", args={
        "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
        "invoke": @clap.Arg::named(help="Function to invoke"),
        "arg": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Arguments to pass to the function (can be repeated)",
        ),
        "preload": @clap.Arg::named(
          nargs=@clap.Nargs::Any,
          help="Preload module as NAME=PATH (can be repeated)",
        ),
      }),
      "compile": @clap.SubCommand::new(
        help="Compile WASM to precompiled format",
        args={
          "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
          "output": @clap.Arg::named(help="Output path (default: input.cwasm)"),
          "emit-ir": @clap.Arg::named(help="Emit IR to specified path"),
        },
      ),
      "demo": @clap.SubCommand::new(help="Run built-in demo programs"),
      "test": @clap.SubCommand::new(help="Run wasm-testsuite JSON spec file", args={
        "file": @clap.Arg::positional(help="Path to JSON spec file"),
      }),
      "disasm": @clap.SubCommand::new(
        help="Disassemble WASM file to text format",
        args={ "file": @clap.Arg::positional(help="Path to WASM file") },
      ),
      "wat": @clap.SubCommand::new(help="Parse WAT file and display as text", args={
        "file": @clap.Arg::positional(help="Path to WAT file"),
      }),
      "wast": @clap.SubCommand::new(
        help="Run WebAssembly test script (.wast format)",
        args={ "file": @clap.Arg::positional(help="Path to WAST file") },
      ),
      "explore": @clap.SubCommand::new(
        help="Explore WASM compilation process (WASM -> IR -> VCode)",
        args={
          "file": @clap.Arg::positional(help="Path to WASM or WAT file"),
          "func": @clap.Arg::named(
            help="Function index to explore (default: 0)",
          ),
          "O": @clap.Arg::named(help="Optimization level (0-3, default: 2)"),
        },
      ),
      "objdump": @clap.SubCommand::new(help="Inspect precompiled .cwasm file", args={
        "file": @clap.Arg::positional(help="Path to .cwasm file"),
      }),
      "settings": @clap.SubCommand::new(
        help="Display available compiler settings",
      ),
      "completion": @clap.SubCommand::new(
        help="Generate shell completion script",
        args={
          "shell": @clap.Arg::positional(help="Shell type: bash, zsh, fish"),
        },
      ),
    },
  )
  let help_msg = parser.gen_help_message(["wasmoon"], {})
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(help_msg)
    return
  }
  let value = @clap.SimpleValue::new("wasmoon")
  let cli_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cli_args.push(args[i])
  }
  let help_msg = parser.parse(value, cli_args[:]) catch {
    e => {
      println(e)
      println(help_msg)
      return
    }
  }
  match help_msg {
    Some(msg) => println(msg)
    None =>
      match value.subcmd {
        Some(sub) =>
          match sub.name {
            "run" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let invoke_opt : String? = match sub.args.get("invoke") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                // Get function arguments from --arg option
                let func_args : Array[String] = match sub.args.get("arg") {
                  Some(arr) => arr
                  None => []
                }
                // Get preload modules from --preload option
                let preloads : Array[String] = match sub.args.get("preload") {
                  Some(arr) => arr
                  None => []
                }
                run_wasm(positional[0], invoke_opt, func_args, preloads)
              } else {
                println("Error: missing file argument")
              }
            }
            "compile" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let output_opt : String? = match sub.args.get("output") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                let emit_ir_opt : String? = match sub.args.get("emit-ir") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(arr[0])
                    } else {
                      None
                    }
                  None => None
                }
                run_compile(positional[0], output_opt, emit_ir_opt)
              } else {
                println("Error: missing file argument")
              }
            }
            "demo" => run_demo()
            "test" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_testsuite(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "disasm" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_disasm(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "wat" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_wat(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "wast" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_wast(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "explore" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                let func_idx : Int? = match sub.args.get("func") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      Some(@strconv.parse_int(arr[0])) catch {
                        _ => None
                      }
                    } else {
                      None
                    }
                  None => None
                }
                let opt_level : Int = match sub.args.get("O") {
                  Some(arr) =>
                    if arr.length() > 0 {
                      @strconv.parse_int(arr[0]) catch {
                        _ => 2
                      }
                    } else {
                      2
                    }
                  None => 2
                }
                run_explore(positional[0], func_idx, opt_level)
              } else {
                println("Error: missing file argument")
              }
            }
            "objdump" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_objdump(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            "settings" => run_settings()
            "completion" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_completion(positional[0])
              } else {
                println(
                  "Error: missing shell argument. Usage: wasmoon completion <bash|zsh|fish>",
                )
              }
            }
            name => println("Unknown command: \{name}")
          }
        None => println("Error: no command")
      }
  }
}
