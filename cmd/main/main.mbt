///|
fn run_demo() -> Unit {
  println("Wasmoon Demo Programs")
  println("=".repeat(50))
  println("")

  // Demo 1: Simple addition
  println("Demo 1: Simple Addition (5 + 10)")
  let add_func : @types.FunctionCode = {
    locals: [],
    body: [@types.LocalGet(0), @types.LocalGet(1), @types.I32Add],
  }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let mod1 : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "add", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [add_func],
    datas: [],
  }
  let (store1, instance1) = @executor.instantiate_module(mod1)
  let args1 = [@types.Value::I32(5), @types.Value::I32(10)]
  try {
    let results = @executor.call_exported_func(store1, instance1, "add", args1)
    match results[0] {
      I32(n) => println("Result: \{n}")
      _ => println("Error: unexpected result type")
    }
  } catch {
    e => println("Error: \{e}")
  }
  println("")

  // Demo 2: Multiply and add
  println("Demo 2: Multiply and Add (7 * 6 + 1)")
  let mul_add_func : @types.FunctionCode = {
    locals: [],
    body: [
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Mul,
      @types.I32Const(1),
      @types.I32Add,
    ],
  }
  let mod2 : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "mul_add", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [mul_add_func],
    datas: [],
  }
  let (store2, instance2) = @executor.instantiate_module(mod2)
  let args2 = [@types.Value::I32(7), @types.Value::I32(6)]
  try {
    let results = @executor.call_exported_func(
      store2, instance2, "mul_add", args2,
    )
    match results[0] {
      I32(n) => println("Result: \{n}")
      _ => println("Error: unexpected result type")
    }
  } catch {
    e => println("Error: \{e}")
  }
  println("")

  // Demo 3: Local variables
  println("Demo 3: Using Local Variables ((3 + 4) * 2)")
  let local_func : @types.FunctionCode = {
    locals: [@types.ValueType::I32],
    body: [
      @types.LocalGet(0),
      @types.LocalGet(1),
      @types.I32Add,
      @types.LocalSet(2),
      @types.LocalGet(2),
      @types.I32Const(2),
      @types.I32Mul,
    ],
  }
  let mod3 : @types.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "double_sum", desc: @types.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [local_func],
    datas: [],
  }
  let (store3, instance3) = @executor.instantiate_module(mod3)
  let args3 = [@types.Value::I32(3), @types.Value::I32(4)]
  try {
    let results = @executor.call_exported_func(
      store3, instance3, "double_sum", args3,
    )
    match results[0] {
      I32(n) => println("Result: \{n}")
      _ => println("Error: unexpected result type")
    }
  } catch {
    e => println("Error: \{e}")
  }
  println("")
  println("=".repeat(50))
  println("Demo completed successfully!")
  println("Supported features:")
  println("  - i32/i64 arithmetic operations")
  println("  - f32/f64 floating point operations")
  println("  - Comparison and bitwise operations")
  println("  - Local variables (get, set, tee)")
  println("  - Function calls with parameters and return values")
}

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
  let commands = @testsuite.parse_json_test_file(json_content)
  let result = @testsuite.TestResult::new()
  let ctx = @testsuite.TestContext::new()
  for cmd in commands {
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
            e => result.add_failed("\{line_prefix}Failed to load module \{filename}: \{e}")
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
            result.add_failed("\{line_prefix}assert_return failed: \{func_name}")
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
            @parser.parse_module(b) |> ignore
            true
          } catch {
            _ => false
          }
          if valid {
            result.add_failed("\{line_prefix}assert_invalid should have failed: \{filename}")
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
        None => println("\{line_prefix}Warning: Register without current module")
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
async fn main {
  let parser = @clap.Parser::new(
    prog="wasmoon",
    description="WebAssembly Runtime in MoonBit",
    subcmds={
      "demo": @clap.SubCommand::new(help="Run built-in demo programs"),
      "test": @clap.SubCommand::new(help="Run wasm-testsuite JSON spec file", args={
        "file": @clap.Arg::positional(help="Path to JSON spec file"),
      }),
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
            "demo" => run_demo()
            "test" => {
              let positional = sub.positional_args
              if positional.length() > 0 {
                run_testsuite(positional[0])
              } else {
                println("Error: missing file argument")
              }
            }
            name => println("Unknown command: \{name}")
          }
        None => println("Error: no command")
      }
  }
}
