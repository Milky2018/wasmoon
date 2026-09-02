///|
/// Test call_indirect with table containing function at non-zero index.
/// This reproduces a bug where the table element lookup used wrong function pointer
/// when there are many functions before the target function.
test "call_indirect_with_many_functions" {
  let source =
    #|(module
    #|  ;; 19 dummy functions before $func to simulate a large module
    #|  (func) (func) (func) (func) (func)
    #|  (func) (func) (func) (func) (func)
    #|  (func) (func) (func) (func) (func)
    #|  (func) (func) (func) (func)
    #|
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (call_indirect (type $check)
    #|        (block (result i32) (i32.const 1)) (i32.const 2) (i32.const 0)
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test call_indirect with simple direct arguments (no blocks).
test "call_indirect_simple" {
  let source =
    #|(module
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check) (i32.const 1) (i32.const 2) (i32.const 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test call_indirect where second argument comes from a block.
test "call_indirect_block_mid" {
  let source =
    #|(module
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (call_indirect (type $check)
    #|        (i32.const 2) (block (result i32) (i32.const 1)) (i32.const 0)
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test call_indirect where table index comes from a block.
test "call_indirect_block_last" {
  let source =
    #|(module
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (call_indirect (type $check)
    #|        (i32.const 1) (i32.const 2) (block (result i32) (i32.const 0))
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// A compiled indirect call must use the table's live size and base. Both can
/// change when `table.grow` reallocates the runtime table.
test "call_indirect uses live table bounds after grow" {
  let source =
    #|(module
    #|  (type $result-i32 (func (result i32)))
    #|  (table 1 2 funcref)
    #|  (func $answer (type $result-i32) (result i32)
    #|    i32.const 42)
    #|  (elem declare func $answer)
    #|  (func (export "test") (result i32)
    #|    ref.null func
    #|    i32.const 1
    #|    table.grow 0
    #|    drop
    #|    i32.const 1
    #|    ref.func $answer
    #|    table.set 0
    #|    i32.const 1
    #|    call_indirect (type $result-i32)))
  inspect(
    compare_jit_interp_with_opt_level(source, "test", [], 2),
    content="matched",
  )
}

///|
test "call_indirect traps on the live table bound" {
  let source =
    #|(module
    #|  (type $result-i32 (func (result i32)))
    #|  (table 1 funcref)
    #|  (func (export "test") (result i32)
    #|    i32.const 1
    #|    call_indirect (type $result-i32)))
  let result = compare_jit_interp_with_opt_level(source, "test", [], 2)
  inspect(compare_result_is_match(result), content="true")
  inspect(
    compare_result_errors_contain(result, "out of bounds"),
    content="true",
  )
}
