///|
/// GC Instructions Integration Tests

///|
/// Helper to run WAT code through interpreter and return results
fn run_wat(wat : String) -> Array[@types.Value] raise {
  let mod = @wat.parse(wat)
  let (store, instance) = @executor.instantiate_module_with_init(mod)
  @executor.call_exported_func(store, instance, "test", [])
}

///|
test "gc: struct.new and struct.get" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $point (struct (field i32) (field i32)))
      #|  (func (export "test") (result i32)
      #|    (struct.get $point 0
      #|      (struct.new $point (i32.const 10) (i32.const 20))
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(10)]")
}

///|
test "gc: struct.new and struct.get second field" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $point (struct (field i32) (field i32)))
      #|  (func (export "test") (result i32)
      #|    (struct.get $point 1
      #|      (struct.new $point (i32.const 10) (i32.const 20))
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(20)]")
}

///|
test "gc: struct.new_default" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $point (struct (field i32) (field i64)))
      #|  (func (export "test") (result i32)
      #|    (struct.get $point 0
      #|      (struct.new_default $point)
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(0)]")
}

///|
test "gc: struct.set" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $point (struct (field (mut i32)) (field i32)))
      #|  (func (export "test") (result i32)
      #|    (local $p (ref $point))
      #|    (local.set $p (struct.new $point (i32.const 10) (i32.const 20)))
      #|    (struct.set $point 0 (local.get $p) (i32.const 100))
      #|    (struct.get $point 0 (local.get $p))
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(100)]")
}

///|
test "gc: array.new and array.len" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $arr (array i32))
      #|  (func (export "test") (result i32)
      #|    (array.len
      #|      (array.new $arr (i32.const 42) (i32.const 5))
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(5)]")
}

///|
test "gc: array.new and array.get" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $arr (array i32))
      #|  (func (export "test") (result i32)
      #|    (array.get $arr
      #|      (array.new $arr (i32.const 42) (i32.const 5))
      #|      (i32.const 2)
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(42)]")
}

///|
test "gc: array.new_default" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $arr (array i32))
      #|  (func (export "test") (result i32)
      #|    (array.get $arr
      #|      (array.new_default $arr (i32.const 3))
      #|      (i32.const 1)
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(0)]")
}

///|
test "gc: array.new_fixed" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $arr (array i32))
      #|  (func (export "test") (result i32)
      #|    (array.get $arr
      #|      (array.new_fixed $arr 3 (i32.const 10) (i32.const 20) (i32.const 30))
      #|      (i32.const 1)
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(20)]")
}

///|
test "gc: array.set" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (type $arr (array (mut i32)))
      #|  (func (export "test") (result i32)
      #|    (local $a (ref $arr))
      #|    (local.set $a (array.new $arr (i32.const 0) (i32.const 5)))
      #|    (array.set $arr (local.get $a) (i32.const 2) (i32.const 99))
      #|    (array.get $arr (local.get $a) (i32.const 2))
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(99)]")
}

///|
test "gc: array.fill" {
  let results = run_wat(
    (
      #|
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
    ),
  )
  // arr[0]=0, arr[1]=42, arr[2]=42, arr[3]=42, arr[4]=0
  // sum of 0+1+2+3 = 0 + 42 + 42 + 42 = 126
  inspect(results, content="[I32(126)]")
}

///|
test "gc: ref.i31 and i31.get_u" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (func (export "test") (result i32)
      #|    (i31.get_u
      #|      (ref.i31 (i32.const 123))
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(123)]")
}

///|
test "gc: ref.i31 and i31.get_s positive" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (func (export "test") (result i32)
      #|    (i31.get_s
      #|      (ref.i31 (i32.const 123))
      #|    )
      #|  )
      #|)
    ),
  )
  inspect(results, content="[I32(123)]")
}

///|
test "gc: ref.i31 high bits" {
  let results = run_wat(
    (
      #|
      #|(module
      #|  (func (export "test") (result i32)
      #|    (i31.get_u
      #|      (ref.i31 (i32.const 0x7FFFFFFF))
      #|    )
      #|  )
      #|)
    ),
  )
  // 0x7FFFFFFF should be preserved (max positive i31)
  inspect(results, content="[I32(2147483647)]")
}
