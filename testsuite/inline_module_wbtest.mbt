// Integration tests for inline module parsing
// Tests that inline modules (WAST format without explicit module wrapper) work correctly

///|
/// Run an inline module WAST script and return results
fn run_inline_module(
  wast_source : String,
  func_name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  // Parse the WAST source (will handle inline module format)
  let script = @wat.parse_wast(wast_source) catch {
    e => {
      println("Failed to parse WAST: \{e}")
      return []
    }
  }

  // Get the first command which should be a Module
  guard script.commands.length() > 0 else { return [] }
  let (cmd, _line) = script.commands[0]
  guard cmd is @wat.Module(mod_, _) else {
    println("First command is not a module")
    return []
  }

  // Instantiate the module
  let (store, instance) = @executor.instantiate_module(mod_)

  // Call the function
  @executor.call_exported_func(store, instance, func_name, args)
}

///|
test "inline module: simple function call" {
  // Inline module with a simple function
  let wast = "(func (export \"answer\") (result i32) (i32.const 42))"
  let result = run_inline_module(wast, "answer", [])
  inspect(result.length(), content="1")
  inspect(result[0], content="I32(42)")
}

///|
test "inline module: function with parameters" {
  // Inline module with a function that takes parameters
  let wast =
    #|(func (export "add") (param i32 i32) (result i32)
    #|  (i32.add (local.get 0) (local.get 1)))
  let result = run_inline_module(wast, "add", [I32(10), I32(32)])
  inspect(result.length(), content="1")
  inspect(result[0], content="I32(42)")
}

///|
test "inline module: multiple functions" {
  // Inline module with multiple functions
  let wast =
    #|(func (export "double") (param i32) (result i32)
    #|  (i32.mul (local.get 0) (i32.const 2)))
    #|(func (export "triple") (param i32) (result i32)
    #|  (i32.mul (local.get 0) (i32.const 3)))
  let result1 = run_inline_module(wast, "double", [I32(21)])
  inspect(result1[0], content="I32(42)")
  let result2 = run_inline_module(wast, "triple", [I32(14)])
  inspect(result2[0], content="I32(42)")
}

///|
test "inline module: with memory" {
  // Inline module with memory and memory operations
  let wast =
    #|(memory 1)
    #|(func (export "store_and_load") (param i32) (result i32)
    #|  (i32.store (i32.const 0) (local.get 0))
    #|  (i32.load (i32.const 0)))
  let result = run_inline_module(wast, "store_and_load", [I32(12345)])
  inspect(result[0], content="I32(12345)")
}

///|
test "inline module: with global" {
  // Inline module with global variable
  let wast =
    #|(global $counter (mut i32) (i32.const 0))
    #|(func (export "increment") (result i32)
    #|  (global.set $counter (i32.add (global.get $counter) (i32.const 1)))
    #|  (global.get $counter))
  let result = run_inline_module(wast, "increment", [])
  inspect(result[0], content="I32(1)")
}

///|
test "inline module: with type definition" {
  // Inline module with explicit type definition
  let wast =
    #|(type $binop (func (param i32 i32) (result i32)))
    #|(func (export "sub") (param i32 i32) (result i32)
    #|  (i32.sub (local.get 0) (local.get 1)))
  let result = run_inline_module(wast, "sub", [I32(100), I32(58)])
  inspect(result[0], content="I32(42)")
}

///|
test "inline module: function calling another function" {
  // Inline module with internal function calls
  let wast =
    #|(func $helper (param i32) (result i32)
    #|  (i32.mul (local.get 0) (i32.const 2)))
    #|(func (export "quad") (param i32) (result i32)
    #|  (call $helper (call $helper (local.get 0))))
  let result = run_inline_module(wast, "quad", [I32(10)])
  inspect(result[0], content="I32(40)")
}

///|
test "inline module: with table" {
  // Inline module with table - simplified without call_indirect
  let wast =
    #|(table 2 funcref)
    #|(func (export "get_table_size") (result i32)
    #|  (i32.const 2))
  let result = run_inline_module(wast, "get_table_size", [])
  inspect(result[0], content="I32(2)")
}

///|
test "inline module: matches spec/inline-module.wast format" {
  // Test the exact format from spec/inline-module.wast
  let wast = "(func) (memory 0) (func (export \"f\"))"
  let result = run_inline_module(wast, "f", [])
  // Function returns nothing, should be empty
  inspect(result.length(), content="0")
}

///|
test "inline module: with memory operations" {
  // Inline module with memory operations - testing memory access
  let wast =
    #|(memory 1)
    #|(func (export "test_memory") (result i32)
    #|  (i32.store (i32.const 0) (i32.const 0x48656C6C))
    #|  (i32.load (i32.const 0)))
  let result = run_inline_module(wast, "test_memory", [])
  // 0x48656C6C = "Hell" in little-endian
  inspect(result[0], content="I32(1214606444)")
}

///|
test "inline module: control flow" {
  // Inline module with control flow (if/else)
  let wast =
    #|(func (export "abs") (param i32) (result i32)
    #|  (if (result i32) (i32.lt_s (local.get 0) (i32.const 0))
    #|    (then (i32.sub (i32.const 0) (local.get 0)))
    #|    (else (local.get 0))))
  let result1 = run_inline_module(wast, "abs", [I32(-42)])
  inspect(result1[0], content="I32(42)")
  let result2 = run_inline_module(wast, "abs", [I32(42)])
  inspect(result2[0], content="I32(42)")
}

///|
test "inline module: loop" {
  // Inline module with loop (factorial)
  let wast =
    #|(func (export "factorial") (param i32) (result i32)
    #|  (local $result i32)
    #|  (local.set $result (i32.const 1))
    #|  (block $done
    #|    (loop $loop
    #|      (br_if $done (i32.le_s (local.get 0) (i32.const 0)))
    #|      (local.set $result (i32.mul (local.get $result) (local.get 0)))
    #|      (local.set 0 (i32.sub (local.get 0) (i32.const 1)))
    #|      (br $loop)))
    #|  (local.get $result))
  let result = run_inline_module(wast, "factorial", [I32(5)])
  inspect(result[0], content="I32(120)")
}
