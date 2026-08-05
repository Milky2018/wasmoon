///|
/// v128 inside GC aggregates, JIT against interpreter (ISS-397).
///
/// The corpus tested GC in 14 files and SIMD in 67 and never crossed them, so
/// storing a vector in a struct or array went unexercised and aborted the
/// process. Every op that moves a value in or out of a GC object is here,
/// because the encoding is what was wrong and it sits under all of them.

///|
test "gc v128: struct.new then struct.get returns the same vector" {
  let source =
    #|(module
    #|  (type $s (struct (field v128)))
    #|  (func (export "test") (result v128)
    #|    (struct.get $s 0 (struct.new $s (v128.const i32x4 1 2 3 4)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: struct.set overwrites a vector field" {
  let source =
    #|(module
    #|  (type $s (struct (field (mut v128))))
    #|  (func (export "test") (result v128)
    #|    (local $r (ref $s))
    #|    (local.set $r (struct.new $s (v128.const i32x4 9 9 9 9)))
    #|    (struct.set $s 0 (local.get $r) (v128.const i64x2 -1 -2))
    #|    (struct.get $s 0 (local.get $r))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// A v128 field's default is a zero vector. It used to fall through to the
/// catch-all for reference types and come back null.
test "gc v128: struct.new_default zeroes a vector field" {
  let source =
    #|(module
    #|  (type $s (struct (field v128)))
    #|  (func (export "test") (result v128)
    #|    (struct.get $s 0 (struct.new_default $s))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// A vector between scalars and a reference: this is what pins the slot
/// layout, since every neighbour would shift if the stride were wrong.
test "gc v128: a vector field between an i32, a reference and an i64" {
  let source =
    #|(module
    #|  (type $leaf (struct (field v128)))
    #|  (type $mix (struct (field i32) (field v128) (field (ref $leaf)) (field i64)))
    #|  (func (export "test") (result v128)
    #|    (struct.get $mix 1
    #|      (struct.new $mix (i32.const 7) (v128.const i32x4 11 22 33 44)
    #|                       (struct.new $leaf (v128.const i32x4 5 5 5 5))
    #|                       (i64.const 123)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// The reference stored beside vector payload must still be followable.
test "gc v128: a reference field neighbouring vector payload" {
  let source =
    #|(module
    #|  (type $leaf (struct (field v128)))
    #|  (type $mix (struct (field i32) (field v128) (field (ref $leaf)) (field i64)))
    #|  (func (export "test") (result v128)
    #|    (struct.get $leaf 0
    #|      (struct.get $mix 2
    #|        (struct.new $mix (i32.const 7) (v128.const i32x4 11 22 33 44)
    #|                         (struct.new $leaf (v128.const i32x4 5 5 5 5))
    #|                         (i64.const 123))))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: the scalar fields around a vector keep their values" {
  let source =
    #|(module
    #|  (type $mix (struct (field i32) (field v128) (field i64)))
    #|  (func (export "test") (result i64)
    #|    (struct.get $mix 2
    #|      (struct.new $mix (i32.const 7) (v128.const i32x4 11 22 33 44)
    #|                       (i64.const 123)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: array.new fills every element with the vector" {
  let source =
    #|(module
    #|  (type $a (array v128))
    #|  (func (export "test") (result v128)
    #|    (array.get $a (array.new $a (v128.const i32x4 6 7 8 9) (i32.const 4))
    #|                  (i32.const 3))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: array.set writes one element" {
  let source =
    #|(module
    #|  (type $a (array (mut v128)))
    #|  (func (export "test") (result v128)
    #|    (local $r (ref $a))
    #|    (local.set $r (array.new_default $a (i32.const 3)))
    #|    (array.set $a (local.get $r) (i32.const 1) (v128.const i32x4 -1 -2 -3 -4))
    #|    (array.get $a (local.get $r) (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// A neighbouring element must be untouched -- a wrong element stride would
/// show up here and nowhere else.
test "gc v128: array.set leaves the next element alone" {
  let source =
    #|(module
    #|  (type $a (array (mut v128)))
    #|  (func (export "test") (result v128)
    #|    (local $r (ref $a))
    #|    (local.set $r (array.new_default $a (i32.const 3)))
    #|    (array.set $a (local.get $r) (i32.const 1) (v128.const i32x4 -1 -2 -3 -4))
    #|    (array.get $a (local.get $r) (i32.const 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: array.fill writes a range of elements" {
  let source =
    #|(module
    #|  (type $a (array (mut v128)))
    #|  (func (export "test") (result v128)
    #|    (local $r (ref $a))
    #|    (local.set $r (array.new_default $a (i32.const 4)))
    #|    (array.fill $a (local.get $r) (i32.const 1)
    #|                   (v128.const i32x4 4 3 2 1) (i32.const 2))
    #|    (array.get $a (local.get $r) (i32.const 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: array.new_fixed keeps its elements distinct" {
  let source =
    #|(module
    #|  (type $a (array v128))
    #|  (func (export "test") (result v128)
    #|    (array.get $a (array.new_fixed $a 2 (v128.const i32x4 1 0 0 0)
    #|                                        (v128.const i32x4 0 0 0 2))
    #|                  (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "gc v128: array.copy moves whole vectors" {
  let source =
    #|(module
    #|  (type $a (array (mut v128)))
    #|  (func (export "test") (result v128)
    #|    (local $src (ref $a))
    #|    (local $dst (ref $a))
    #|    (local.set $src (array.new_fixed $a 2 (v128.const i32x4 10 20 30 40)
    #|                                          (v128.const i32x4 50 60 70 80)))
    #|    (local.set $dst (array.new_default $a (i32.const 2)))
    #|    (array.copy $a $a (local.get $dst) (i32.const 0)
    #|                      (local.get $src) (i32.const 0) (i32.const 2))
    #|    (array.get $a (local.get $dst) (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Allocate enough to make the collector run while vectors and references
/// share objects. Only a slot's low word holds references, so a vector whose
/// bits look like one must not cost the chain its links.
test "gc v128: references survive collection beside vector payload" {
  let source =
    #|(module
    #|  (type $leaf (struct (field v128)))
    #|  (type $node (struct (field (ref null $node)) (field v128) (field (ref $leaf))))
    #|  (func (export "test") (result i32)
    #|    (local $head (ref null $node))
    #|    (local $i i32)
    #|    (local $count i32)
    #|    (loop $build
    #|      (local.set $head
    #|        (struct.new $node (local.get $head)
    #|                          (v128.const i64x2 2 4)
    #|                          (struct.new $leaf (v128.const i64x2 -7 -8))))
    #|      (drop (struct.new $leaf (v128.const i32x4 9 9 9 9)))
    #|      (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|      (br_if $build (i32.lt_u (local.get $i) (i32.const 200))))
    #|    (block $done
    #|      (loop $walk
    #|        (br_if $done (ref.is_null (local.get $head)))
    #|        (local.set $count (i32.add (local.get $count) (i32.const 1)))
    #|        (local.set $head
    #|          (struct.get $node 0 (ref.as_non_null (local.get $head))))
    #|        (br $walk)))
    #|    (local.get $count)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
