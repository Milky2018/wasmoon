// Tests for WAST parser

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
  guard script.commands[0] is Module(_, _) else {
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
  if script.commands[1] is AssertReturn(Invoke(_, "add", args), expected) {
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
  if script.commands[1] is AssertTrap(Invoke(_, "div", _), msg) {
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
  guard script.commands[1] is Register("M1", None) else {
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
  if script.commands[1] is AssertReturn(_, expected) {
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
  if script.commands[1] is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="255")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}
