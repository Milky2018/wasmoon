///|
/// GC JIT Tests - Compare JIT and interpreter execution for GC operations

///|
test "gc jit: i31.new and i31.get_u" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i31.get_u
    #|      (ref.i31 (i32.const 123))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: i31.new and i31.get_s" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (i31.get_s
    #|      (ref.i31 (i32.const 123))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: struct.new and struct.get" {
  let source =
    #|(module
    #|  (type $point (struct (field i32) (field i32)))
    #|  (func (export "test") (result i32)
    #|    (struct.get $point 0
    #|      (struct.new $point (i32.const 10) (i32.const 20))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: struct.new and struct.get second field" {
  let source =
    #|(module
    #|  (type $point (struct (field i32) (field i32)))
    #|  (func (export "test") (result i32)
    #|    (struct.get $point 1
    #|      (struct.new $point (i32.const 10) (i32.const 20))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: struct.new_default" {
  let source =
    #|(module
    #|  (type $point (struct (field i32) (field i64)))
    #|  (func (export "test") (result i32)
    #|    (struct.get $point 0
    #|      (struct.new_default $point)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: struct.set" {
  let source =
    #|(module
    #|  (type $point (struct (field (mut i32)) (field i32)))
    #|  (func (export "test") (result i32)
    #|    (local $p (ref $point))
    #|    (local.set $p (struct.new $point (i32.const 10) (i32.const 20)))
    #|    (struct.set $point 0 (local.get $p) (i32.const 100))
    #|    (struct.get $point 0 (local.get $p))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.new and array.len" {
  let source =
    #|(module
    #|  (type $arr (array i32))
    #|  (func (export "test") (result i32)
    #|    (array.len
    #|      (array.new $arr (i32.const 42) (i32.const 5))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.new and array.get" {
  let source =
    #|(module
    #|  (type $arr (array i32))
    #|  (func (export "test") (result i32)
    #|    (array.get $arr
    #|      (array.new $arr (i32.const 42) (i32.const 5))
    #|      (i32.const 2)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.new_default" {
  let source =
    #|(module
    #|  (type $arr (array i32))
    #|  (func (export "test") (result i32)
    #|    (array.get $arr
    #|      (array.new_default $arr (i32.const 3))
    #|      (i32.const 1)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.new_fixed" {
  let source =
    #|(module
    #|  (type $arr (array i32))
    #|  (func (export "test") (result i32)
    #|    (array.get $arr
    #|      (array.new_fixed $arr 3 (i32.const 10) (i32.const 20) (i32.const 30))
    #|      (i32.const 1)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.set" {
  let source =
    #|(module
    #|  (type $arr (array (mut i32)))
    #|  (func (export "test") (result i32)
    #|    (local $a (ref $arr))
    #|    (local.set $a (array.new $arr (i32.const 0) (i32.const 5)))
    #|    (array.set $arr (local.get $a) (i32.const 2) (i32.const 99))
    #|    (array.get $arr (local.get $a) (i32.const 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: array.fill" {
  let source =
    #|(module
    #|  (type $arr (array (mut i32)))
    #|  (func (export "test") (result i32)
    #|    (local $a (ref $arr))
    #|    (local.set $a (array.new $arr (i32.const 0) (i32.const 5)))
    #|    (array.fill $arr (local.get $a) (i32.const 1) (i32.const 42) (i32.const 3))
    #|    (i32.add
    #|      (array.get $arr (local.get $a) (i32.const 0))
    #|      (i32.add
    #|        (array.get $arr (local.get $a) (i32.const 1))
    #|        (i32.add
    #|          (array.get $arr (local.get $a) (i32.const 2))
    #|          (array.get $arr (local.get $a) (i32.const 3))
    #|        )
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: ref.eq same struct" {
  let source =
    #|(module
    #|  (type $point (struct (field i32)))
    #|  (func (export "test") (result i32)
    #|    (local $p (ref $point))
    #|    (local.set $p (struct.new $point (i32.const 10)))
    #|    (ref.eq (local.get $p) (local.get $p))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: ref.eq different structs" {
  let source =
    #|(module
    #|  (type $point (struct (field i32)))
    #|  (func (export "test") (result i32)
    #|    (ref.eq
    #|      (struct.new $point (i32.const 10))
    #|      (struct.new $point (i32.const 10))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc jit: null struct arg is_null" {
  // Test that null GC args are encoded correctly (P1 fix)
  let source =
    #|(module
    #|  (type $point (struct (field i32)))
    #|  (func (export "test") (param (ref null $point)) (result i32)
    #|    (ref.is_null (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [@types.Value::Null])
  inspect(result, content="matched")
}

///|
test "gc jit: ref.eq null refs" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (ref.eq
    #|      (ref.null none)
    #|      (ref.null none)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
