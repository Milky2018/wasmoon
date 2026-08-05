///|
/// v128 exception payloads, JIT against interpreter (ISS-400).
///
/// A payload crosses the runtime as a flat run of i64 words, and a v128 takes
/// two of them, so every value after a vector sits one word further along than
/// its position suggests. The throw side packs from the operand types and the
/// catch side walks the tag's declared types; these pin that the two agree.

///|
test "exception v128: a vector payload survives throw and catch" {
  let source =
    #|(module
    #|  (tag $t (param v128))
    #|  (func (export "test") (result v128)
    #|    (block $b (result v128)
    #|      (try_table (result v128) (catch $t $b)
    #|        (throw $t (v128.const i32x4 1 2 3 4))
    #|        (v128.const i32x4 0 0 0 0)))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// The scalar before the vector: its offset is unaffected, so this passing
/// while `mid_i64` fails would mean the walk starts right and drifts.
test "exception v128: the scalar before a vector payload" {
  let source =
    #|(module
    #|  (tag $t (param i32 v128 i64))
    #|  (func (export "test") (result i32)
    #|    (local $a i32) (local $v v128) (local $c i64)
    #|    (block $b (result i32 v128 i64)
    #|      (try_table (result i32 v128 i64) (catch $t $b)
    #|        (throw $t (i32.const 11) (v128.const i32x4 5 6 7 8) (i64.const 99))
    #|        (unreachable)))
    #|    (local.set $c) (local.set $v) (local.set $a)
    #|    (local.get $a)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "exception v128: a vector between two scalars" {
  let source =
    #|(module
    #|  (tag $t (param i32 v128 i64))
    #|  (func (export "test") (result v128)
    #|    (local $a i32) (local $v v128) (local $c i64)
    #|    (block $b (result i32 v128 i64)
    #|      (try_table (result i32 v128 i64) (catch $t $b)
    #|        (throw $t (i32.const 11) (v128.const i32x4 5 6 7 8) (i64.const 99))
    #|        (unreachable)))
    #|    (local.set $c) (local.set $v) (local.set $a)
    #|    (local.get $v)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// The scalar after the vector, which is where a one-word-per-value walk
/// would read the vector's upper half instead.
test "exception v128: the scalar after a vector payload" {
  let source =
    #|(module
    #|  (tag $t (param i32 v128 i64))
    #|  (func (export "test") (result i64)
    #|    (local $a i32) (local $v v128) (local $c i64)
    #|    (block $b (result i32 v128 i64)
    #|      (try_table (result i32 v128 i64) (catch $t $b)
    #|        (throw $t (i32.const 11) (v128.const i32x4 5 6 7 8) (i64.const 99))
    #|        (unreachable)))
    #|    (local.set $c) (local.set $v) (local.set $a)
    #|    (local.get $c)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "exception v128: two vector payloads stay distinct" {
  let source =
    #|(module
    #|  (tag $t (param v128 v128))
    #|  (func (export "test") (result v128)
    #|    (local $x v128) (local $y v128)
    #|    (block $b (result v128 v128)
    #|      (try_table (result v128 v128) (catch $t $b)
    #|        (throw $t (v128.const i64x2 1 2) (v128.const i64x2 3 4))
    #|        (unreachable)))
    #|    (local.set $y) (local.set $x)
    #|    (local.get $y)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "exception v128: a scalar following a leading vector" {
  let source =
    #|(module
    #|  (tag $t (param v128 i32))
    #|  (func (export "test") (result i32)
    #|    (local $v v128) (local $n i32)
    #|    (block $b (result v128 i32)
    #|      (try_table (result v128 i32) (catch $t $b)
    #|        (throw $t (v128.const i32x4 9 9 9 9) (i32.const 42))
    #|        (unreachable)))
    #|    (local.set $n) (local.set $v)
    #|    (local.get $n)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// A vector held in a local across a try, which goes through the spilled-local
/// path rather than the payload one. This already worked; it is here so that
/// changing one path cannot quietly break the other.
test "exception v128: a vector local survives a caught throw" {
  let source =
    #|(module
    #|  (tag $t)
    #|  (func (export "test") (result v128)
    #|    (local $v v128)
    #|    (local.set $v (v128.const i32x4 7 8 9 10))
    #|    (block $b
    #|      (try_table (catch $t $b) (throw $t)))
    #|    (local.get $v)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
