///|
fn main {
  println("Wasmoon - WebAssembly Runtime in MoonBit")
  println("=".repeat(50))
  println("")

  // Demo 1: Simple addition
  println("Demo 1: Simple Addition (5 + 10)")
  let add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [@wasmoon.LocalGet(0), @wasmoon.LocalGet(1), @wasmoon.I32Add],
  }
  let func_type : @wasmoon.FuncType = {
    params: [@wasmoon.ValueType::I32, @wasmoon.ValueType::I32],
    results: [@wasmoon.ValueType::I32],
  }
  let mod1 : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [add_func],
    datas: [],
  }
  let (store1, instance1) = @wasmoon.instantiate_module(mod1)
  let args1 = [@wasmoon.Value::I32(5), @wasmoon.Value::I32(10)]
  try {
    let results = @wasmoon.call_exported_func(store1, instance1, "add", args1)
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
  let mul_add_func : @wasmoon.FunctionCode = {
    locals: [],
    body: [
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Mul,
      @wasmoon.I32Const(1),
      @wasmoon.I32Add,
    ],
  }
  let mod2 : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "mul_add", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [mul_add_func],
    datas: [],
  }
  let (store2, instance2) = @wasmoon.instantiate_module(mod2)
  let args2 = [@wasmoon.Value::I32(7), @wasmoon.Value::I32(6)]
  try {
    let results = @wasmoon.call_exported_func(
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
  let local_func : @wasmoon.FunctionCode = {
    locals: [@wasmoon.ValueType::I32],
    body: [
      @wasmoon.LocalGet(0),
      @wasmoon.LocalGet(1),
      @wasmoon.I32Add,
      @wasmoon.LocalSet(2),
      @wasmoon.LocalGet(2),
      @wasmoon.I32Const(2),
      @wasmoon.I32Mul,
    ],
  }
  let mod3 : @wasmoon.Module = {
    types: [func_type],
    imports: [],
    funcs: [0],
    tables: [],
    memories: [],
    globals: [],
    exports: [{ name: "double_sum", desc: @wasmoon.ExportDesc::Func(0) }],
    start: None,
    elems: [],
    codes: [local_func],
    datas: [],
  }
  let (store3, instance3) = @wasmoon.instantiate_module(mod3)
  let args3 = [@wasmoon.Value::I32(3), @wasmoon.Value::I32(4)]
  try {
    let results = @wasmoon.call_exported_func(
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
  println("MVP completed successfully!")
  println("Supported features:")
  println("  - i32 arithmetic operations (add, sub, mul, div)")
  println("  - i32 comparison and bitwise operations")
  println("  - Local variables (get, set, tee)")
  println("  - Function calls with parameters and return values")
}
