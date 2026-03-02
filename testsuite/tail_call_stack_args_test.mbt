///|
test "tail call with stack overflow args (direct)" {
  let source =
    #|(module
    #|  (func $sum12
    #|    (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    #|    (result i64)
    #|    local.get 0
    #|    local.get 1
    #|    i64.add
    #|    local.get 2
    #|    i64.add
    #|    local.get 3
    #|    i64.add
    #|    local.get 4
    #|    i64.add
    #|    local.get 5
    #|    i64.add
    #|    local.get 6
    #|    i64.add
    #|    local.get 7
    #|    i64.add
    #|    local.get 8
    #|    i64.add
    #|    local.get 9
    #|    i64.add
    #|    local.get 10
    #|    i64.add
    #|    local.get 11
    #|    i64.add
    #|  )
    #|  (func (export "main") (result i64)
    #|    i64.const 1
    #|    i64.const 2
    #|    i64.const 3
    #|    i64.const 4
    #|    i64.const 5
    #|    i64.const 6
    #|    i64.const 7
    #|    i64.const 8
    #|    i64.const 9
    #|    i64.const 10
    #|    i64.const 11
    #|    i64.const 12
    #|    return_call $sum12
    #|  )
    #|)
  inspect(compare_jit_interp(source, "main", []), content="matched")
}

///|
test "tail call with stack overflow args (indirect)" {
  let source =
    #|(module
    #|  (type $t12 (func
    #|    (param i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    #|    (result i64)))
    #|  (table 1 funcref)
    #|  (elem (i32.const 0) $sum12)
    #|  (func $sum12
    #|    (type $t12)
    #|    local.get 0
    #|    local.get 1
    #|    i64.add
    #|    local.get 2
    #|    i64.add
    #|    local.get 3
    #|    i64.add
    #|    local.get 4
    #|    i64.add
    #|    local.get 5
    #|    i64.add
    #|    local.get 6
    #|    i64.add
    #|    local.get 7
    #|    i64.add
    #|    local.get 8
    #|    i64.add
    #|    local.get 9
    #|    i64.add
    #|    local.get 10
    #|    i64.add
    #|    local.get 11
    #|    i64.add
    #|  )
    #|  (func (export "main") (result i64)
    #|    i64.const 1
    #|    i64.const 2
    #|    i64.const 3
    #|    i64.const 4
    #|    i64.const 5
    #|    i64.const 6
    #|    i64.const 7
    #|    i64.const 8
    #|    i64.const 9
    #|    i64.const 10
    #|    i64.const 11
    #|    i64.const 12
    #|    i32.const 0
    #|    return_call_indirect (type $t12)
    #|  )
    #|)
  inspect(compare_jit_interp(source, "main", []), content="matched")
}
