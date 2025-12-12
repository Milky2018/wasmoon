///|
/// Tests for br_table instruction - simplified from br_table.wast
/// Excludes the "large" function test which has ~16000 targets

///|
test "br_table_empty" {
  let source =
    #|(module
    #|  (func (export "empty") (param i32) (result i32)
    #|    (block (br_table 0 (local.get 0)) (return (i32.const 21)))
    #|    (i32.const 22)
    #|  )
    #|)
  inspect(compare_jit_interp(source, "empty", [I32(0)]), content="matched")
  inspect(compare_jit_interp(source, "empty", [I32(1)]), content="matched")
  inspect(compare_jit_interp(source, "empty", [I32(-1)]), content="matched")
}

///|
test "br_table_singleton" {
  let source =
    #|(module
    #|  (func (export "singleton") (param i32) (result i32)
    #|    (block
    #|      (block
    #|        (br_table 1 0 (local.get 0))
    #|        (return (i32.const 21))
    #|      )
    #|      (return (i32.const 20))
    #|    )
    #|    (i32.const 22)
    #|  )
    #|)
  // index 0 -> branch to label 1 -> returns 22
  inspect(compare_jit_interp(source, "singleton", [I32(0)]), content="matched")
  // index 1 -> branch to label 0 (default) -> returns 20
  inspect(compare_jit_interp(source, "singleton", [I32(1)]), content="matched")
  // index >= table length -> use default (label 0) -> returns 20
  inspect(compare_jit_interp(source, "singleton", [I32(11)]), content="matched")
  inspect(compare_jit_interp(source, "singleton", [I32(-1)]), content="matched")
}

///|
test "br_table_singleton_value" {
  let source =
    #|(module
    #|  (func (export "singleton-value") (param i32) (result i32)
    #|    (block (result i32)
    #|      (drop
    #|        (block (result i32)
    #|          (br_table 0 1 (i32.const 33) (local.get 0))
    #|          (return (i32.const 31))
    #|        )
    #|      )
    #|      (i32.const 32)
    #|    )
    #|  )
    #|)
  // index 0 -> label 0 (inner block) with value 33, dropped, returns 32
  inspect(
    compare_jit_interp(source, "singleton-value", [I32(0)]),
    content="matched",
  )
  // index 1 -> label 1 (outer block, default) with value 33, returns 33
  inspect(
    compare_jit_interp(source, "singleton-value", [I32(1)]),
    content="matched",
  )
  // index >= 2 -> default (label 1) with value 33, returns 33
  inspect(
    compare_jit_interp(source, "singleton-value", [I32(11)]),
    content="matched",
  )
}

///|
test "br_table_multiple" {
  let source =
    #|(module
    #|  (func (export "multiple") (param i32) (result i32)
    #|    (block
    #|      (block
    #|        (block
    #|          (block
    #|            (block
    #|              (br_table 3 2 1 0 4 (local.get 0))
    #|              (return (i32.const 99))
    #|            )
    #|            (return (i32.const 100))
    #|          )
    #|          (return (i32.const 101))
    #|        )
    #|        (return (i32.const 102))
    #|      )
    #|      (return (i32.const 103))
    #|    )
    #|    (i32.const 104)
    #|  )
    #|)
  // index 0 -> label 3 -> return 103
  inspect(compare_jit_interp(source, "multiple", [I32(0)]), content="matched")
  // index 1 -> label 2 -> return 102
  inspect(compare_jit_interp(source, "multiple", [I32(1)]), content="matched")
  // index 2 -> label 1 -> return 101
  inspect(compare_jit_interp(source, "multiple", [I32(2)]), content="matched")
  // index 3 -> label 0 -> return 100
  inspect(compare_jit_interp(source, "multiple", [I32(3)]), content="matched")
  // index 4 -> label 4 (default) -> return 104
  inspect(compare_jit_interp(source, "multiple", [I32(4)]), content="matched")
  // index >= 5 -> default -> return 104
  inspect(compare_jit_interp(source, "multiple", [I32(5)]), content="matched")
  inspect(compare_jit_interp(source, "multiple", [I32(-1)]), content="matched")
}

///|
test "br_table_nested_br_table_loop_block" {
  let source =
    #|(module
    #|  (func (export "nested-br_table-loop-block") (param i32) (result i32)
    #|    (local.set 0
    #|      (loop (result i32)
    #|        (block
    #|          (br_table 1 0 0 (local.get 0))
    #|        )
    #|        (i32.const 0)
    #|      )
    #|    )
    #|    (loop (result i32)
    #|      (block
    #|        (br_table 0 1 1 (local.get 0))
    #|      )
    #|      (i32.const 3)
    #|    )
    #|  )
    #|)
  // With input 1:
  // First loop: index=1 -> label 0 (block) -> continue to i32.const 0 -> local 0 = 0
  // Second loop: index=0 -> label 0 (block) -> continue to i32.const 3 -> return 3
  inspect(
    compare_jit_interp(source, "nested-br_table-loop-block", [I32(1)]),
    content="matched",
  )
}

///|
test "br_table_as_block_value" {
  let source =
    #|(module
    #|  (func $dummy)
    #|  (func (export "as-block-value") (result i32)
    #|    (block (result i32)
    #|      (nop) (call $dummy) (br_table 0 0 0 (i32.const 2) (i32.const 0))
    #|    )
    #|  )
    #|)
  inspect(compare_jit_interp(source, "as-block-value", []), content="matched")
}

///|
test "br_table_as_loop_first" {
  let source =
    #|(module
    #|  (func (export "as-loop-first") (result i32)
    #|    (loop (result i32) (br_table 1 1 (i32.const 3) (i32.const 0)) (i32.const 1))
    #|  )
    #|)
  inspect(compare_jit_interp(source, "as-loop-first", []), content="matched")
}
