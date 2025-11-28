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
fn main {
  let parser = @clap.Parser::new(
    prog="wasmoon",
    description="WebAssembly Runtime in MoonBit",
    subcmds={ "demo": @clap.SubCommand::new(help="Run built-in demo programs") },
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
        Some({ name: "demo", .. }) => run_demo()
        Some({ name, .. }) => println("Unknown command: \{name}")
        None => println("Error: no command")
      }
  }
}
