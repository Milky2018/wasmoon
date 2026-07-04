///|
/// Test for br instruction - simplified from br.wast
/// The issue is handling of "unreachable" code after br

///|
/// Simple test: br exits block immediately
test "br_simple" {
  let source =
    #|(module
    #|  (func (export "simple") (result i32)
    #|    (block (result i32)
    #|      (br 0 (i32.const 42))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "simple", [])
  inspect(result, content="matched")
}

///|
/// Test br in nested block with dead code after br
test "br_dead_code" {
  let source =
    #|(module
    #|  (func (export "dead-code") (result i32)
    #|    (block (result i32)
    #|      (br 0 (i32.const 1))
    #|      (i32.const 2)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "dead-code", [])
  inspect(result, content="matched")
}

///|
/// Test br in nested block
test "br_as_block_first" {
  let source =
    #|(module
    #|  (func $dummy)
    #|  (func (export "as-block-first")
    #|    (block (br 0) (call $dummy))
    #|  )
    #|)
  let result = compare_jit_interp(source, "as-block-first", [])
  inspect(result, content="matched")
}

///|
/// The problematic case: br inside an expression
/// (block (drop (i32.ctz (br 0))))
/// After br 0, i32.ctz is unreachable dead code
/// The translator tries to pop operand for i32.ctz but stack is empty
test "br_type_i32" {
  let source =
    #|(module
    #|  (func (export "type-i32") (block (drop (i32.ctz (br 0)))))
    #|)
  let result = compare_jit_interp(source, "type-i32", [])
  inspect(result, content="matched")
}

///|
/// nested-block-value from br.wast line 290
/// Expected result: 9 (1 + 8)
test "br_nested_block_value" {
  let source =
    #|(module
    #|  (func $dummy)
    #|  (func (export "nested-block-value") (result i32)
    #|    (i32.add
    #|      (i32.const 1)
    #|      (block (result i32)
    #|        (call $dummy)
    #|        (i32.add (i32.const 4) (br 0 (i32.const 8)))
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "nested-block-value", [])
  inspect(result, content="matched")
}

///|
/// Test break-bare: br followed by unreachable code
test "break_bare" {
  let source =
    #|(module
    #|  (func (export "break-bare") (result i32)
    #|    (block (br 0) (unreachable))
    #|    (block (br_if 0 (i32.const 1)) (unreachable))
    #|    (block (br_table 0 (i32.const 0)) (unreachable))
    #|    (block (br_table 0 0 0 (i32.const 1)) (unreachable))
    #|    (i32.const 19)
    #|  )
    #|)
  let result = compare_jit_interp(source, "break-bare", [])
  inspect(result, content="matched")
}

///|
/// Test as-call-value: call internal function with block result
test "as_call_value" {
  let source =
    #|(module
    #|  (func $f (param i32) (result i32) (local.get 0))
    #|  (func (export "as-call-value") (result i32)
    #|    (call $f (block (result i32) (i32.const 1)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "as-call-value", [])
  inspect(result, content="matched")
}
