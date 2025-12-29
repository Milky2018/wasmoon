// SIMD Unit Tests

///|
/// Helper to create v128 bytes from 16 byte values
fn make_v128(
  b0 : Int,
  b1 : Int,
  b2 : Int,
  b3 : Int,
  b4 : Int,
  b5 : Int,
  b6 : Int,
  b7 : Int,
  b8 : Int,
  b9 : Int,
  b10 : Int,
  b11 : Int,
  b12 : Int,
  b13 : Int,
  b14 : Int,
  b15 : Int,
) -> Bytes {
  Bytes::from_array([
    b0.to_byte(),
    b1.to_byte(),
    b2.to_byte(),
    b3.to_byte(),
    b4.to_byte(),
    b5.to_byte(),
    b6.to_byte(),
    b7.to_byte(),
    b8.to_byte(),
    b9.to_byte(),
    b10.to_byte(),
    b11.to_byte(),
    b12.to_byte(),
    b13.to_byte(),
    b14.to_byte(),
    b15.to_byte(),
  ])
}

///|
/// Helper to create v128 from i32x4 lanes
fn make_i32x4(lane0 : Int, lane1 : Int, lane2 : Int, lane3 : Int) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for lane in [lane0, lane1, lane2, lane3] {
    buf.write_byte(lane.to_byte())
    buf.write_byte((lane >> 8).to_byte())
    buf.write_byte((lane >> 16).to_byte())
    buf.write_byte((lane >> 24).to_byte())
  }
  buf.contents()
}

///|
/// Test helper function: sign extension for i8
test "sign_i8" {
  inspect(sign_i8(0), content="0")
  inspect(sign_i8(127), content="127")
  inspect(sign_i8(128), content="-128")
  inspect(sign_i8(255), content="-1")
  inspect(sign_i8(1), content="1")
}

///|
/// Test helper function: sign extension for i16
test "sign_i16" {
  inspect(sign_i16(0), content="0")
  inspect(sign_i16(32767), content="32767")
  inspect(sign_i16(32768), content="-32768")
  inspect(sign_i16(65535), content="-1")
}

///|
/// Test saturating add for signed i8
test "sat_add_i8_s" {
  // Normal cases
  inspect(sat_add_i8_s(10, 20).to_int(), content="30")
  inspect(sat_add_i8_s(100, 20).to_int(), content="120")
  // Saturation cases
  inspect(sat_add_i8_s(127, 1).to_int(), content="127") // saturate at max
  inspect(sat_add_i8_s(100, 100).to_int(), content="127") // saturate at max
  // Negative saturation (128 in unsigned = -128 in signed, represented as 0x80)
  inspect(sat_add_i8_s(128, 128).to_int(), content="128") // -128 + -128 saturates to -128 (0x80)
}

///|
/// Test saturating add for unsigned i8
test "sat_add_i8_u" {
  inspect(sat_add_i8_u(10, 20).to_int(), content="30")
  inspect(sat_add_i8_u(200, 100).to_int(), content="255") // saturate at 255
  inspect(sat_add_i8_u(255, 1).to_int(), content="255")
  inspect(sat_add_i8_u(0, 0).to_int(), content="0")
}

///|
/// Test saturating sub for signed i8
test "sat_sub_i8_s" {
  inspect(sat_sub_i8_s(30, 10).to_int(), content="20")
  inspect(sat_sub_i8_s(0, 127).to_int(), content="129") // -127 as unsigned byte = 129
  // 0 - 128(=-128) = 128, which is clamped to 127
  inspect(sat_sub_i8_s(0, 128).to_int(), content="127")
}

///|
/// Test saturating sub for unsigned i8
test "sat_sub_i8_u" {
  inspect(sat_sub_i8_u(30, 10).to_int(), content="20")
  inspect(sat_sub_i8_u(10, 30).to_int(), content="0") // clamp to 0
  inspect(sat_sub_i8_u(0, 255).to_int(), content="0")
}

///|
/// Test popcount for 8-bit values
test "popcount8" {
  inspect(popcount8(0), content="0")
  inspect(popcount8(1), content="1")
  inspect(popcount8(0xFF), content="8")
  inspect(popcount8(0x55), content="4") // 01010101
  inspect(popcount8(0xAA), content="4") // 10101010
}

///|
/// Test lane access helpers
test "get_i16_lane" {
  // Create v128: [0, 1, 2, ..., 15]
  let bytes = make_v128(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
  // Little-endian: lane 0 = bytes[0..2] = 0x0100 = 256
  inspect(get_i16_lane(bytes, 0), content="256")
  // lane 1 = bytes[2..4] = 0x0302 = 770
  inspect(get_i16_lane(bytes, 1), content="770")
}

///|
/// Test lane access for i32
test "get_i32_lane" {
  let bytes = make_v128(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
  // lane 0 = bytes[0..4] = 0x03020100 = 50462976
  inspect(get_i32_lane(bytes, 0), content="50462976")
}

///|
/// Test lane access for i64
test "get_i64_lane" {
  let bytes = make_v128(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
  // lane 0 = bytes[0..8] = 0x0706050403020100
  inspect(get_i64_lane(bytes, 0), content="506097522914230528")
}

///|
/// Test f32 min/max with NaN handling
test "f32_min_max" {
  // Normal cases
  inspect(f32_min(1.0, 2.0), content="1")
  inspect(f32_max(1.0, 2.0), content="2")
  // NaN propagation
  let nan = @float.not_a_number
  inspect(f32_min(nan, 1.0).is_nan(), content="true")
  inspect(f32_max(1.0, nan).is_nan(), content="true")
}

///|
/// Test f64 min/max with NaN handling
test "f64_min_max" {
  inspect(f64_min(1.0, 2.0), content="1")
  inspect(f64_max(1.0, 2.0), content="2")
  let nan = @double.not_a_number
  inspect(f64_min(nan, 1.0).is_nan(), content="true")
  inspect(f64_max(1.0, nan).is_nan(), content="true")
}

///|
/// Test truncation saturation functions
test "trunc_sat_f32_to_i32_s" {
  inspect(trunc_sat_f32_to_i32_s(1.5), content="1")
  inspect(trunc_sat_f32_to_i32_s(-1.5), content="-1")
  inspect(trunc_sat_f32_to_i32_s(@float.not_a_number), content="0")
  inspect(trunc_sat_f32_to_i32_s(3000000000.0), content="2147483647") // saturate
  inspect(trunc_sat_f32_to_i32_s(-3000000000.0), content="-2147483648") // saturate
}

///|
/// Test truncation saturation for unsigned
test "trunc_sat_f32_to_u32" {
  inspect(trunc_sat_f32_to_u32(1.5), content="1")
  inspect(trunc_sat_f32_to_u32(-1.0), content="0") // negative -> 0
  inspect(trunc_sat_f32_to_u32(@float.not_a_number), content="0")
  inspect(trunc_sat_f32_to_u32(5000000000.0), content="4294967295") // saturate
}

///|
/// Test SIMD v128.const execution
test "exec_v128_const" {
  let bytes = make_v128(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(bytes)],
    "get_v128",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "get_v128", [])
  match results[0] {
    V128(result) => {
      inspect(result[0].to_int(), content="1")
      inspect(result[15].to_int(), content="16")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i32x4.splat
test "exec_i32x4_splat" {
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::V128],
    [LocalGet(0), I32x4Splat],
    "splat",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "splat", [
    @types.Value::I32(0x12345678),
  ])
  match results[0] {
    V128(result) => {
      // Check first lane (little-endian: 0x78, 0x56, 0x34, 0x12)
      inspect(result[0].to_int(), content="120") // 0x78
      inspect(result[1].to_int(), content="86") // 0x56
      inspect(result[2].to_int(), content="52") // 0x34
      inspect(result[3].to_int(), content="18") // 0x12
      // All 4 lanes should be the same
      inspect(result[4].to_int(), content="120")
      inspect(result[8].to_int(), content="120")
      inspect(result[12].to_int(), content="120")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i32x4.add
test "exec_i32x4_add" {
  // a = [1, 2, 3, 4] as i32x4
  let a = make_i32x4(1, 2, 3, 4)
  // b = [10, 20, 30, 40] as i32x4
  let b = make_i32x4(10, 20, 30, 40)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), I32x4Add],
    "add",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "add", [])
  match results[0] {
    V128(result) => {
      // Result should be [11, 22, 33, 44]
      inspect(get_i32_lane(result, 0), content="11")
      inspect(get_i32_lane(result, 1), content="22")
      inspect(get_i32_lane(result, 2), content="33")
      inspect(get_i32_lane(result, 3), content="44")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i8x16.extract_lane_s
test "exec_i8x16_extract_lane_s" {
  // bytes[1] = 0x80 = 128 -> -128 when sign-extended
  let bytes = make_v128(0x7F, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(bytes), I8x16ExtractLaneS(1)], // Extract lane 1 (value 0x80 = -128)
    "extract",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "extract", [])
  match results[0] {
    I32(n) => inspect(n, content="-128")
    _ => fail("Expected I32 result")
  }
}

///|
/// Test i8x16.extract_lane_u
test "exec_i8x16_extract_lane_u" {
  let bytes = make_v128(0, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(bytes), I8x16ExtractLaneU(1)],
    "extract",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "extract", [])
  match results[0] {
    I32(n) => inspect(n, content="128")
    _ => fail("Expected I32 result")
  }
}

///|
/// Test i8x16.replace_lane
test "exec_i8x16_replace_lane" {
  let bytes = make_v128(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  let mod = @types.Module::simple(
    [@types.ValueType::I32],
    [@types.ValueType::V128],
    [V128Const(bytes), LocalGet(0), I8x16ReplaceLane(5)], // Replace lane 5
    "replace",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "replace", [
    @types.Value::I32(0xAB),
  ])
  match results[0] {
    V128(result) => {
      inspect(result[0].to_int(), content="0")
      inspect(result[5].to_int(), content="171") // 0xAB = 171
      inspect(result[15].to_int(), content="0")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test v128.and
test "exec_v128_and" {
  let a = make_v128(
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF,
  )
  let b = make_v128(
    0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F,
    0x0F, 0x0F, 0x0F,
  )
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), V128And],
    "and",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "and", [])
  match results[0] {
    V128(result) => {
      // 0xFF & 0x0F = 0x0F for all bytes
      inspect(result[0].to_int(), content="15")
      inspect(result[15].to_int(), content="15")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test v128.or
test "exec_v128_or" {
  let a = make_v128(
    0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0,
    0xF0, 0xF0, 0xF0,
  )
  let b = make_v128(
    0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F,
    0x0F, 0x0F, 0x0F,
  )
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), V128Or],
    "or",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "or", [])
  match results[0] {
    V128(result) =>
      // 0xF0 | 0x0F = 0xFF for all bytes
      inspect(result[0].to_int(), content="255")
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i8x16.eq (comparison)
test "exec_i8x16_eq" {
  let a = make_v128(5, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  let b = make_v128(5, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), I8x16Eq],
    "eq",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "eq", [])
  match results[0] {
    V128(result) => {
      inspect(result[0].to_int(), content="255") // Equal -> 0xFF
      inspect(result[1].to_int(), content="0") // Not equal -> 0x00
      inspect(result[2].to_int(), content="255") // Both 0 -> equal
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i8x16.shuffle
test "exec_i8x16_shuffle" {
  let a = make_v128(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
  let b = make_v128(
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  )

  // Shuffle: interleave lanes from a and b
  let lanes : FixedArray[Int] = [
    0, 16, 1, 17, 2, 18, 3, 19, 4, 20, 5, 21, 6, 22, 7, 23,
  ]
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), I8x16Shuffle(lanes)],
    "shuffle",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "shuffle", [])
  match results[0] {
    V128(result) => {
      inspect(result[0].to_int(), content="0") // from a[0]
      inspect(result[1].to_int(), content="16") // from b[0]
      inspect(result[2].to_int(), content="1") // from a[1]
      inspect(result[3].to_int(), content="17") // from b[1]
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i32x4.sub
test "exec_i32x4_sub" {
  let a = make_i32x4(100, 200, 300, 400)
  let b = make_i32x4(10, 20, 30, 40)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), I32x4Sub],
    "sub",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "sub", [])
  match results[0] {
    V128(result) => {
      inspect(get_i32_lane(result, 0), content="90")
      inspect(get_i32_lane(result, 1), content="180")
      inspect(get_i32_lane(result, 2), content="270")
      inspect(get_i32_lane(result, 3), content="360")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test i32x4.mul
test "exec_i32x4_mul" {
  let a = make_i32x4(2, 3, 4, 5)
  let b = make_i32x4(10, 10, 10, 10)
  let mod = @types.Module::simple(
    [],
    [@types.ValueType::V128],
    [V128Const(a), V128Const(b), I32x4Mul],
    "mul",
  )
  let (store, instance) = instantiate_module(mod)
  let results = call_exported_func(store, instance, "mul", [])
  match results[0] {
    V128(result) => {
      inspect(get_i32_lane(result, 0), content="20")
      inspect(get_i32_lane(result, 1), content="30")
      inspect(get_i32_lane(result, 2), content="40")
      inspect(get_i32_lane(result, 3), content="50")
    }
    _ => fail("Expected V128 result")
  }
}

///|
/// Test v128.any_true
test "exec_v128_any_true" {
  let zero = make_v128(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  let nonzero = make_v128(0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)

  // Test with all zeros
  let mod1 = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(zero), V128AnyTrue],
    "any_true",
  )
  let (store1, instance1) = instantiate_module(mod1)
  let results1 = call_exported_func(store1, instance1, "any_true", [])
  match results1[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }

  // Test with one non-zero byte
  let mod2 = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(nonzero), V128AnyTrue],
    "any_true",
  )
  let (store2, instance2) = instantiate_module(mod2)
  let results2 = call_exported_func(store2, instance2, "any_true", [])
  match results2[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }
}

///|
/// Test i32x4.all_true
test "exec_i32x4_all_true" {
  let all_nonzero = make_i32x4(1, 2, 3, 4)
  let has_zero = make_i32x4(1, 0, 3, 4)

  // Test with all non-zero lanes
  let mod1 = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(all_nonzero), I32x4AllTrue],
    "all_true",
  )
  let (store1, instance1) = instantiate_module(mod1)
  let results1 = call_exported_func(store1, instance1, "all_true", [])
  match results1[0] {
    I32(n) => inspect(n, content="1")
    _ => fail("Expected I32 result")
  }

  // Test with one zero lane
  let mod2 = @types.Module::simple(
    [],
    [@types.ValueType::I32],
    [V128Const(has_zero), I32x4AllTrue],
    "all_true",
  )
  let (store2, instance2) = instantiate_module(mod2)
  let results2 = call_exported_func(store2, instance2, "all_true", [])
  match results2[0] {
    I32(n) => inspect(n, content="0")
    _ => fail("Expected I32 result")
  }
}
