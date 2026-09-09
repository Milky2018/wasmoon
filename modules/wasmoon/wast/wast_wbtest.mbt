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
      debug_inspect(mod_.elems[0].init[0], content="[RefFunc(1)]")
      // Check call_indirect type index (should be 0, index of $check - explicit type first)
      let test_func = mod_.codes[mod_.codes.length() - 1]
      debug_inspect(
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

///|
test "funcref registration release preserves duplicate active owner" {
  let store = @runtime.Store::Store()
  defer store.close()
  let first = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  let second = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  first.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="Some(100)")
  second.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="None")
}

///|
test "funcref registration release restores previous owner" {
  let store = @runtime.Store::Store()
  defer store.close()
  let previous = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  let replacement = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=200L),
  ])
  replacement.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="Some(100)")
  previous.release()
}

///|
test "Wasmtime named module imports are opt-in" {
  let source =
    #|(module $env (memory (export "memory") 1))
    #|(module (import "env" "memory" (memory 1))
    #|  (func (export "size") (result i32) memory.size))
    #|(assert_return (invoke "size") (i32.const 1))
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let original = run_wast_commands(script, ".", false, false)
  inspect(original.failed > 0, content="true")
  let compatible = run_wast_commands(
    script,
    ".",
    false,
    false,
    register_named_modules=true,
  )
  inspect(compatible.failed, content="0")
  inspect(compatible.passed, content="1")
}

///|
test "bare invoke traps fail the script" {
  let source =
    #|(module (func (export "trap") unreachable))
    #|(invoke "trap")
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="1")
  inspect(result.passed, content="0")
}

///|
test "active data segments are dropped after initialization" {
  let source =
    #|(module (memory 1) (data (i32.const 0) "a")
    #|  (func (export "read") (result i32) (i32.load8_u (i32.const 0)))
    #|  (func (export "init") (param i32 i32)
    #|    (memory.init 0 (i32.const 0) (local.get 0) (local.get 1))))
    #|(assert_return (invoke "read") (i32.const 97))
    #|(assert_return (invoke "init" (i32.const 0) (i32.const 0)))
    #|(assert_trap (invoke "init" (i32.const 0) (i32.const 1)) "out of bounds")
    #|(assert_trap (invoke "init" (i32.const 1) (i32.const 0)) "out of bounds")
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="0")
  inspect(result.passed, content="4")
}

///|
test "indexed ref.func expectations compare function identity" {
  let source =
    #|(module (func))
    #|(module (func $a) (func $b)
    #|  (elem declare func $a $b)
    #|  (func (export "get") (result funcref) ref.func $b))
    #|(assert_return (invoke "get") (ref.func 1))
    #|(assert_return (invoke "get") (ref.func 0))
    #|(assert_return (invoke "get") (either (ref.func 0) (ref.func 1)))
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="1")
  inspect(result.passed, content="2")
}

///|
test "table imports share the index space with local definitions" {
  let source =
    #|(module (table (export "table") 1 funcref))
    #|(register "host")
    #|(module
    #|  (table $imported (import "host" "table") (export "imported") 1 funcref)
    #|  (table $local (export "local") (export "alias") 2 funcref)
    #|  (func (export "size-imported") (result i32) table.size $imported)
    #|  (func (export "size-local") (result i32) table.size $local))
    #|(assert_return (invoke "size-imported") (i32.const 1))
    #|(assert_return (invoke "size-local") (i32.const 2))
    #|(register "tables")
    #|(module (import "tables" "alias" (table 2 funcref))
    #|  (func (export "size") (result i32) table.size))
    #|(assert_return (invoke "size") (i32.const 2))
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="0")
  inspect(result.passed, content="3")
}

///|
test "anonymous module definitions can be instantiated" {
  let source =
    #|(module definition (func (export "f") (result i32) i32.const 7))
    #|(module instance)
    #|(assert_return (invoke "f") (i32.const 7))
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="0")
  inspect(result.passed, content="2")
}

///|
test "shared memory flags participate in import compatibility" {
  let source =
    #|(module (memory (export "memory") 1 2 shared))
    #|(register "shared")
    #|(module (import "shared" "memory" (memory 1 2 shared)))
    #|(assert_unlinkable
    #|  (module (import "shared" "memory" (memory 1 2))) "incompatible import type")
    #|(module (memory (export "memory") 1 2))
    #|(register "private")
    #|(assert_unlinkable
    #|  (module (import "private" "memory" (memory 1 2 shared))) "incompatible import type")
  let script = parse(source) catch { e => fail("Parse error: \{e}") }
  let result = run_wast_commands(script, ".", false, false)
  inspect(result.failed, content="0")
  inspect(result.passed, content="2")
}

///|
fn register_funcref_entries(
  store : @runtime.Store,
  entries : Array[@runtime.StoreFuncrefEntry],
) -> FuncrefRegistration {
  { lease: store.register_jit_funcrefs(entries), }
}

///|
test "WAST assertions reject wrong trap kinds and missing actions" {
  let source =
    #| (module (tag $e) (func (export "trap") unreachable)
    #|   (func (export "throw") (throw $e)))
    #| (assert_trap (invoke "trap") "integer divide by zero")
    #| (assert_exception (invoke "trap"))
    #| (assert_trap (invoke $missing "trap") "unreachable")
    #| (assert_exception (invoke $missing "trap"))
    #| (assert_trap (invoke "missing") "undefined element")
    #| (assert_trap (invoke "throw") "uncaught exception")
    #| (assert_trap (module (func $start unreachable) (start $start)) "integer divide by zero")
    #| (assert_trap (module (import "missing" "f" (func))) "unknown import")
    #| (assert_trap (invoke "trap") "unreachable")
    #| (assert_exception (invoke "throw"))
    #| (assert_trap (module (func $start unreachable) (start $start)) "unreachable")
  let result = run_wast_commands(parse(source), ".", false, false)
  inspect(result.passed, content="3")
  inspect(result.failed, content="8")
}

///|
test "WAST assertions do not accept host errors as guest failures" {
  let ctx = WastContext(false)
  let linker = @runtime.Linker::with_store(ctx.get_store())
  linker.add_host_func("host", "trap", fn(_args) raise @runtime.RuntimeError {
    raise Unreachable
  })
  linker.add_host_func("host", "throw", fn(_args) raise @runtime.RuntimeError {
    raise UncaughtException
  })
  ctx.registered_modules.set("host", linker.get_module("host").unwrap())
  let source =
    #| (module (import "host" "trap" (func $trap))
    #|   (import "host" "throw" (func $throw))
    #|   (func (export "trap") (call $trap))
    #|   (func (export "throw") (call $throw)))
    #| (assert_trap (invoke "trap") "unreachable")
    #| (assert_exception (invoke "trap"))
    #| (assert_trap (invoke "throw") "uncaught exception")
    #| (assert_exception (invoke "throw"))
  let result = WastResult()
  for item in parse(source).commands {
    let (command, line) = item
    run_wast_command(ctx, command, line, result, ".", false)
  }
  inspect(result.passed, content="0")
  inspect(result.failed, content="4")
}

///|
test "native trap diagnostics cannot satisfy the expected trap message" {
  inspect(
    wast_trap_message_matches(
      "unreachable (sig=SIGTRAP(5), wasm=0 'integer divide by zero'+0x0)", "integer divide by zero",
    ),
    content="false",
  )
  inspect(
    wast_trap_message_matches("null reference", "null array reference"),
    content="true",
  )
  inspect(
    wast_trap_message_matches(
      "out of bounds memory access", "out of bounds table access",
    ),
    content="false",
  )
}
