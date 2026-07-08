///|
/// SIMD JIT Regression Tests
/// These tests verify that JIT and interpreter produce identical results for SIMD operations

///|
test "simd: v128.const" {
  let source =
    #|(module
    #|  (func (export "v128_const") (result v128)
    #|    (v128.const i32x4 1 2 3 4))
    #|)
  let result = compare_jit_interp(source, "v128_const", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.splat" {
  let source =
    #|(module
    #|  (func (export "i32x4_splat") (param i32) (result v128)
    #|    (i32x4.splat (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "i32x4_splat", [I32(42)])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.splat" {
  let source =
    #|(module
    #|  (func (export "i8x16_splat") (param i32) (result v128)
    #|    (i8x16.splat (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "i8x16_splat", [I32(0xAB)])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.add" {
  let source =
    #|(module
    #|  (func (export "i32x4_add") (result v128)
    #|    (i32x4.add
    #|      (v128.const i32x4 1 2 3 4)
    #|      (v128.const i32x4 10 20 30 40)))
    #|)
  let result = compare_jit_interp(source, "i32x4_add", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.sub" {
  let source =
    #|(module
    #|  (func (export "i32x4_sub") (result v128)
    #|    (i32x4.sub
    #|      (v128.const i32x4 100 200 300 400)
    #|      (v128.const i32x4 10 20 30 40)))
    #|)
  let result = compare_jit_interp(source, "i32x4_sub", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.mul" {
  let source =
    #|(module
    #|  (func (export "i32x4_mul") (result v128)
    #|    (i32x4.mul
    #|      (v128.const i32x4 2 3 4 5)
    #|      (v128.const i32x4 10 10 10 10)))
    #|)
  let result = compare_jit_interp(source, "i32x4_mul", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.extract_lane_s" {
  let source =
    #|(module
    #|  (func (export "extract_s") (result i32)
    #|    (i8x16.extract_lane_s 1
    #|      (v128.const i8x16 0 0x80 0 0 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "extract_s", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.extract_lane_u" {
  let source =
    #|(module
    #|  (func (export "extract_u") (result i32)
    #|    (i8x16.extract_lane_u 1
    #|      (v128.const i8x16 0 0x80 0 0 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "extract_u", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.extract_lane" {
  let source =
    #|(module
    #|  (func (export "extract") (result i32)
    #|    (i32x4.extract_lane 2
    #|      (v128.const i32x4 10 20 30 40)))
    #|)
  let result = compare_jit_interp(source, "extract", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.replace_lane" {
  let source =
    #|(module
    #|  (func (export "replace") (param i32) (result v128)
    #|    (i8x16.replace_lane 5
    #|      (v128.const i8x16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    #|      (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "replace", [I32(0xAB)])
  inspect(result, content="matched")
}

///|
test "simd: v128.and" {
  let source =
    #|(module
    #|  (func (export "and") (result v128)
    #|    (v128.and
    #|      (v128.const i8x16 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF)
    #|      (v128.const i8x16 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F)))
    #|)
  let result = compare_jit_interp(source, "and", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.or" {
  let source =
    #|(module
    #|  (func (export "or") (result v128)
    #|    (v128.or
    #|      (v128.const i8x16 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0 0xF0)
    #|      (v128.const i8x16 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F 0x0F)))
    #|)
  let result = compare_jit_interp(source, "or", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.xor" {
  let source =
    #|(module
    #|  (func (export "xor") (result v128)
    #|    (v128.xor
    #|      (v128.const i8x16 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF)
    #|      (v128.const i8x16 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA 0xAA)))
    #|)
  let result = compare_jit_interp(source, "xor", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.not" {
  let source =
    #|(module
    #|  (func (export "not") (result v128)
    #|    (v128.not
    #|      (v128.const i8x16 0x00 0xFF 0x55 0xAA 0x00 0xFF 0x55 0xAA 0x00 0xFF 0x55 0xAA 0x00 0xFF 0x55 0xAA)))
    #|)
  let result = compare_jit_interp(source, "not", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.any_true with zeros" {
  let source =
    #|(module
    #|  (func (export "any_true_zero") (result i32)
    #|    (v128.any_true
    #|      (v128.const i8x16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "any_true_zero", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.any_true with non-zero" {
  let source =
    #|(module
    #|  (func (export "any_true_one") (result i32)
    #|    (v128.any_true
    #|      (v128.const i8x16 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "any_true_one", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.all_true" {
  let source =
    #|(module
    #|  (func (export "all_true") (result i32)
    #|    (i32x4.all_true
    #|      (v128.const i32x4 1 2 3 4)))
    #|)
  let result = compare_jit_interp(source, "all_true", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.all_true with zero" {
  let source =
    #|(module
    #|  (func (export "all_true_false") (result i32)
    #|    (i32x4.all_true
    #|      (v128.const i32x4 1 0 3 4)))
    #|)
  let result = compare_jit_interp(source, "all_true_false", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.eq" {
  let source =
    #|(module
    #|  (func (export "eq") (result v128)
    #|    (i8x16.eq
    #|      (v128.const i8x16 5 0x10 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    #|      (v128.const i8x16 5 0x20 0 0 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "eq", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.neg" {
  let source =
    #|(module
    #|  (func (export "neg") (result v128)
    #|    (i32x4.neg
    #|      (v128.const i32x4 1 -2 3 -4)))
    #|)
  let result = compare_jit_interp(source, "neg", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.shuffle" {
  let source =
    #|(module
    #|  (func (export "shuffle") (result v128)
    #|    (i8x16.shuffle 0 16 1 17 2 18 3 19 4 20 5 21 6 22 7 23
    #|      (v128.const i8x16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
    #|      (v128.const i8x16 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31)))
    #|)
  let result = compare_jit_interp(source, "shuffle", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.swizzle" {
  let source =
    #|(module
    #|  (func (export "swizzle") (result v128)
    #|    (i8x16.swizzle
    #|      (v128.const i8x16 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
    #|      (v128.const i8x16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0)))
    #|)
  let result = compare_jit_interp(source, "swizzle", [])
  inspect(result, content="matched")
}

///|
test "simd: i64x2.splat" {
  let source =
    #|(module
    #|  (func (export "i64x2_splat") (param i64) (result v128)
    #|    (i64x2.splat (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "i64x2_splat", [
    I64(0x123456789ABCDEF0L),
  ])
  inspect(result, content="matched")
}

///|
test "simd: i64x2.add" {
  let source =
    #|(module
    #|  (func (export "i64x2_add") (result v128)
    #|    (i64x2.add
    #|      (v128.const i64x2 100 200)
    #|      (v128.const i64x2 10 20)))
    #|)
  let result = compare_jit_interp(source, "i64x2_add", [])
  inspect(result, content="matched")
}

///|
test "simd: i16x8.add" {
  let source =
    #|(module
    #|  (func (export "i16x8_add") (result v128)
    #|    (i16x8.add
    #|      (v128.const i16x8 1 2 3 4 5 6 7 8)
    #|      (v128.const i16x8 10 20 30 40 50 60 70 80)))
    #|)
  let result = compare_jit_interp(source, "i16x8_add", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.add" {
  let source =
    #|(module
    #|  (func (export "i8x16_add") (result v128)
    #|    (i8x16.add
    #|      (v128.const i8x16 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
    #|      (v128.const i8x16 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)))
    #|)
  let result = compare_jit_interp(source, "i8x16_add", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.add_sat_s" {
  let source =
    #|(module
    #|  (func (export "add_sat_s") (result v128)
    #|    (i8x16.add_sat_s
    #|      (v128.const i8x16 127 100 -128 -100 0 0 0 0 0 0 0 0 0 0 0 0)
    #|      (v128.const i8x16 1 100 -1 -100 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "add_sat_s", [])
  inspect(result, content="matched")
}

///|
test "simd: i8x16.add_sat_u" {
  let source =
    #|(module
    #|  (func (export "add_sat_u") (result v128)
    #|    (i8x16.add_sat_u
    #|      (v128.const i8x16 255 200 100 0 0 0 0 0 0 0 0 0 0 0 0 0)
    #|      (v128.const i8x16 1 100 100 0 0 0 0 0 0 0 0 0 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "add_sat_u", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.lt_s" {
  let source =
    #|(module
    #|  (func (export "lt_s") (result v128)
    #|    (i32x4.lt_s
    #|      (v128.const i32x4 -1 0 1 2)
    #|      (v128.const i32x4 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "lt_s", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.gt_u" {
  let source =
    #|(module
    #|  (func (export "gt_u") (result v128)
    #|    (i32x4.gt_u
    #|      (v128.const i32x4 0xFFFFFFFF 0 1 2)
    #|      (v128.const i32x4 0 0 0 0)))
    #|)
  let result = compare_jit_interp(source, "gt_u", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.shl" {
  let source =
    #|(module
    #|  (func (export "shl") (param i32) (result v128)
    #|    (i32x4.shl
    #|      (v128.const i32x4 1 2 3 4)
    #|      (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "shl", [I32(2)])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.shr_s" {
  let source =
    #|(module
    #|  (func (export "shr_s") (param i32) (result v128)
    #|    (i32x4.shr_s
    #|      (v128.const i32x4 -8 8 -16 16)
    #|      (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "shr_s", [I32(2)])
  inspect(result, content="matched")
}

///|
test "simd: f32x4.add" {
  let source =
    #|(module
    #|  (func (export "f32x4_add") (result v128)
    #|    (f32x4.add
    #|      (v128.const f32x4 1.0 2.0 3.0 4.0)
    #|      (v128.const f32x4 0.1 0.2 0.3 0.4)))
    #|)
  let result = compare_jit_interp(source, "f32x4_add", [])
  inspect(result, content="matched")
}

///|
test "simd: f64x2.add" {
  let source =
    #|(module
    #|  (func (export "f64x2_add") (result v128)
    #|    (f64x2.add
    #|      (v128.const f64x2 1.0 2.0)
    #|      (v128.const f64x2 0.1 0.2)))
    #|)
  let result = compare_jit_interp(source, "f64x2_add", [])
  inspect(result, content="matched")
}

///|
test "simd: f32x4.mul" {
  let source =
    #|(module
    #|  (func (export "f32x4_mul") (result v128)
    #|    (f32x4.mul
    #|      (v128.const f32x4 1.0 2.0 3.0 4.0)
    #|      (v128.const f32x4 2.0 2.0 2.0 2.0)))
    #|)
  let result = compare_jit_interp(source, "f32x4_mul", [])
  inspect(result, content="matched")
}

///|
test "simd: f32x4.splat" {
  let source =
    #|(module
    #|  (func (export "f32x4_splat") (param f32) (result v128)
    #|    (f32x4.splat (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "f32x4_splat", [F32(3.14)])
  inspect(result, content="matched")
}

///|
test "simd: f64x2.splat" {
  let source =
    #|(module
    #|  (func (export "f64x2_splat") (param f64) (result v128)
    #|    (f64x2.splat (local.get 0)))
    #|)
  let result = compare_jit_interp(source, "f64x2_splat", [F64(3.14159)])
  inspect(result, content="matched")
}

///|
test "simd: f32x4.extract_lane" {
  let source =
    #|(module
    #|  (func (export "extract") (result f32)
    #|    (f32x4.extract_lane 2
    #|      (v128.const f32x4 1.0 2.0 3.0 4.0)))
    #|)
  let result = compare_jit_interp(source, "extract", [])
  inspect(result, content="matched")
}

///|
test "simd: f64x2.extract_lane" {
  let source =
    #|(module
    #|  (func (export "extract") (result f64)
    #|    (f64x2.extract_lane 1
    #|      (v128.const f64x2 1.0 2.0)))
    #|)
  let result = compare_jit_interp(source, "extract", [])
  inspect(result, content="matched")
}

///|
test "simd: v128.bitselect" {
  let source =
    #|(module
    #|  (func (export "bitselect") (result v128)
    #|    (v128.bitselect
    #|      (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA)
    #|      (v128.const i32x4 0x55555555 0x55555555 0x55555555 0x55555555)
    #|      (v128.const i32x4 0xF0F0F0F0 0xF0F0F0F0 0xF0F0F0F0 0xF0F0F0F0)))
    #|)
  let result = compare_jit_interp(source, "bitselect", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.abs" {
  let source =
    #|(module
    #|  (func (export "abs") (result v128)
    #|    (i32x4.abs
    #|      (v128.const i32x4 -1 0 1 -2147483648)))
    #|)
  let result = compare_jit_interp(source, "abs", [])
  inspect(result, content="matched")
}

///|
test "simd: i32x4.bitmask" {
  let source =
    #|(module
    #|  (func (export "bitmask") (result i32)
    #|    (i32x4.bitmask
    #|      (v128.const i32x4 -1 0 -1 0)))
    #|)
  let result = compare_jit_interp(source, "bitmask", [])
  inspect(result, content="matched")
}
