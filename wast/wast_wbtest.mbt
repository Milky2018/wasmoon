// Tests for WAST parser - public API only

// ============================================================
// WAST command parsing tests
// ============================================================

///|
test "parse simple module" {
  let input =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add)
    #|)
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(_, _) else {
    fail("Expected Module command")
  }
}

///|
test "parse assert_return" {
  let input =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add)
    #|)
    #|(assert_return (invoke "add" (i32.const 1) (i32.const 2)) (i32.const 3))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  if script.commands[1].0 is AssertReturn(Invoke(_, "add", args), expected) {
    inspect(args.length(), content="2")
    inspect(expected.length(), content="1")
  } else {
    fail("Expected AssertReturn command")
  }
}

///|
test "parse assert_trap" {
  let input =
    #|(module
    #|  (func (export "div") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.div_s)
    #|)
    #|(assert_trap (invoke "div" (i32.const 1) (i32.const 0)) "integer divide by zero")
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  if script.commands[1].0 is AssertTrap(Invoke(_, "div", _), msg) {
    inspect(msg, content="integer divide by zero")
  } else {
    fail("Expected AssertTrap command")
  }
}

///|
test "parse register command" {
  let input =
    #|(module)
    #|(register "M1")
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  guard script.commands[1].0 is Register("M1", None) else {
    fail("Expected Register command")
  }
}

///|
test "parse i32 const values" {
  let input =
    #|(module
    #|  (func (export "f") (result i32) i32.const 42)
    #|)
    #|(assert_return (invoke "f") (i32.const 42))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  if script.commands[1].0 is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="42")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}

///|
test "parse hex numbers" {
  let input =
    #|(module
    #|  (func (export "f") (result i32) i32.const 0)
    #|)
    #|(assert_return (invoke "f") (i32.const 0xff))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  if script.commands[1].0 is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="255")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}

///|
test "collect_module_text reconstruction" {
  let wast_text =
    #|(module
    #|  (func $dummy)
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
    #|(assert_return (invoke "test") (i32.const 1))
  let script = parse(wast_text)
  match script.commands[0].0 {
    Module(mod_, _) => {
      // With explicit types first: 3 types instead of 4
      // Type 0: $check (i32, i32) -> i32 (explicit)
      // Type 1: () -> () ($dummy's implicit type)
      // Type 2: () -> i32 (test's implicit type)
      // $func reuses type 0 since it matches $check
      inspect(mod_.types.length(), content="3")
      inspect(mod_.funcs.length(), content="3")
      inspect(mod_.elems.length(), content="1")
      // Check elem init is correct (should be 1, func index of $func)
      inspect(mod_.elems[0].init[0], content="[RefFunc(1)]")
      // Check call_indirect type index (should be 0, index of $check - explicit type first)
      let test_func = mod_.codes[mod_.codes.length() - 1]
      inspect(
        test_func.body,
        content="[I32Const(1), I32Const(2), I32Const(0), CallIndirect(0, 0)]",
      )
    }
    _ => fail("expected module")
  }
}

///|
test "regression: Unicode function names in WAST" {
  // Test that WAST parser preserves Unicode code points > 0xFF correctly
  // Previously, escape_string_to would truncate Unicode code points,
  // e.g., U+FEFF (65279) would become 0xFF (255)
  let wast_input = "(module (func (export \"﻿\") (result i32) (i32.const 15)))\n(assert_return (invoke \"﻿\") (i32.const 15))"
  let script = parse(wast_input) catch { e => fail("Parse error: \{e}") }

  // First command should be Module
  let (cmd1, _) = script.commands[0]
  if cmd1 is Module(mod, _) {
    let export_name = mod.exports[0].name
    inspect(export_name.length(), content="1")
    // BOM character U+FEFF = 65279
    inspect(export_name.code_unit_at(0).to_int(), content="65279")
  } else {
    fail("Expected Module command")
  }

  // Second command should be AssertReturn - the function name must match
  let (cmd2, _) = script.commands[1]
  if cmd2 is AssertReturn(Invoke(_, func_name, _), _) {
    inspect(func_name.length(), content="1")
    // Function name in invoke must also be U+FEFF = 65279, not 0xFF (255)
    inspect(func_name.code_unit_at(0).to_int(), content="65279")
  } else {
    fail("Expected AssertReturn command")
  }
}
