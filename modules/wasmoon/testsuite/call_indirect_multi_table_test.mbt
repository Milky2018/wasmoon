///|
test "call_indirect with multiple tables" {
  let source =
    #|(module
    #|  (type $ii-i (func (param i32 i32) (result i32)))
    #|
    #|  (table $t1 funcref (elem $f $g))
    #|  (table $t2 funcref (elem $h $i $j))
    #|
    #|  (func $f (type $ii-i) (i32.add (local.get 0) (local.get 1)))
    #|  (func $g (type $ii-i) (i32.sub (local.get 0) (local.get 1)))
    #|  (func $h (type $ii-i) (i32.mul (local.get 0) (local.get 1)))
    #|  (func $i (type $ii-i) (i32.div_u (local.get 0) (local.get 1)))
    #|  (func $j (type $ii-i) (i32.rem_u (local.get 0) (local.get 1)))
    #|
    #|  (func (export "call-1") (param i32 i32 i32) (result i32)
    #|    (call_indirect $t1 (type $ii-i) (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|  (func (export "call-2") (param i32 i32 i32) (result i32)
    #|    (call_indirect $t2 (type $ii-i) (local.get 0) (local.get 1) (local.get 2))
    #|  )
    #|)
  let result1 = compare_jit_interp(source, "call-1", [I32(2), I32(3), I32(0)])
  inspect(result1, content="matched")
  let result2 = compare_jit_interp(source, "call-1", [I32(2), I32(3), I32(1)])
  inspect(result2, content="matched")
  let result3 = compare_jit_interp(source, "call-2", [I32(2), I32(3), I32(0)])
  inspect(result3, content="matched")
  let result4 = compare_jit_interp(source, "call-2", [I32(2), I32(3), I32(1)])
  inspect(result4, content="matched")
}

///|
/// Non-zero tables use the table array in VMContext rather than table 0's
/// dedicated fast-path fields. Their live base and size must move together.
test "call_indirect uses live bounds after growing a non-zero table" {
  let source =
    #|(module
    #|  (type $result-i32 (func (result i32)))
    #|  (table 1 funcref)
    #|  (table $target 1 2 funcref)
    #|  (func $answer (type $result-i32) (result i32)
    #|    i32.const 42)
    #|  (elem declare func $answer)
    #|  (func (export "test") (result i32)
    #|    ref.null func
    #|    i32.const 1
    #|    table.grow $target
    #|    drop
    #|    i32.const 1
    #|    ref.func $answer
    #|    table.set $target
    #|    i32.const 1
    #|    call_indirect $target (type $result-i32)))
  inspect(
    compare_jit_interp_with_opt_level(source, "test", [], 2),
    content="matched",
  )
}
