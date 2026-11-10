///|
fn v128_replace_lane(
  v128 : Bytes,
  lane : Int32,
  val : Int64,
  width : Int32,
) -> Bytes {
  let offset = lane * width
  Bytes::makei(16, i => {
    if i >= offset && i < offset + width {
      (val >> ((i - offset) * 8)).to_byte()
    } else {
      v128[i]
    }
  })
}

///|
fn v128_replace_i8(v128 : Bytes, lane : Int32, val : Byte) -> Bytes {
  v128_replace_lane(v128, lane, val.to_int64(), 1)
}

///|
fn v128_replace_i16(v128 : Bytes, lane : Int32, val : Int32) -> Bytes {
  v128_replace_lane(v128, lane, val.to_int64(), 2)
}

///|
fn v128_replace_i32(v128 : Bytes, lane : Int32, val : Int32) -> Bytes {
  v128_replace_lane(v128, lane, val.to_int64(), 4)
}

///|
fn v128_replace_i64(v128 : Bytes, lane : Int32, val : Int64) -> Bytes {
  v128_replace_lane(v128, lane, val, 8)
}

///|
fn sign_i8(v : Int32) -> Int32 {
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
fn ExecContext::exec_v128_cmp_i8(
  self : ExecContext,
  cmp : (Int32, Int32) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<16 {
    let result = if cmp(a[i].to_int(), b[i].to_int()) { 0xFF } else { 0 }
    buf.write_byte(result.to_byte())
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i8(
  self : ExecContext,
  op : (Int32, Int32) -> Byte,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<16 {
    buf.write_byte(op(a[i].to_int(), b[i].to_int()))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i8(
  self : ExecContext,
  op : (Int32) -> Byte,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<16 {
    buf.write_byte(op(a[i].to_int()))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn sign_i16(v : Int32) -> Int32 {
  if v >= 32768 {
    v - 65536
  } else {
    v
  }
}

///|
fn get_i16_lane(v : Bytes, lane : Int32) -> Int32 {
  let offset = lane * 2
  v[offset].to_int() | (v[offset + 1].to_int() << 8)
}

///|
fn get_i32_lane(v : Bytes, lane : Int32) -> Int32 {
  let offset = lane * 4
  v[offset].to_int() |
  (v[offset + 1].to_int() << 8) |
  (v[offset + 2].to_int() << 16) |
  (v[offset + 3].to_int() << 24)
}

///|
fn get_i64_lane(v : Bytes, lane : Int32) -> Int64 {
  let offset = lane * 8
  v[offset].to_int().to_int64() |
  (v[offset + 1].to_int().to_int64() << 8) |
  (v[offset + 2].to_int().to_int64() << 16) |
  (v[offset + 3].to_int().to_int64() << 24) |
  (v[offset + 4].to_int().to_int64() << 32) |
  (v[offset + 5].to_int().to_int64() << 40) |
  (v[offset + 6].to_int().to_int64() << 48) |
  (v[offset + 7].to_int().to_int64() << 56)
}

///|
fn get_f32_lane(v : Bytes, lane : Int32) -> Float {
  Float::reinterpret_from_int(get_i32_lane(v, lane))
}

///|
fn get_f64_lane(v : Bytes, lane : Int32) -> Double {
  get_i64_lane(v, lane).reinterpret_as_double()
}

///|
fn write_i16_lane(buf : @buffer.Buffer, v : Int32) -> Unit {
  buf.write_byte(v.to_byte())
  buf.write_byte((v >> 8).to_byte())
}

///|
fn sign_extend_i8(v : Int32) -> Int32 {
  if (v & 0x80) != 0 {
    v | 0xFFFFFF00
  } else {
    v & 0xFF
  }
}

///|
fn sign_extend_i16(v : Int32) -> Int32 {
  if (v & 0x8000) != 0 {
    v | 0xFFFF0000
  } else {
    v & 0xFFFF
  }
}

///|
fn ExecContext::exec_v128_cmp_i16(
  self : ExecContext,
  cmp : (Int32, Int32) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<8 {
    let result = if cmp(get_i16_lane(a, i), get_i16_lane(b, i)) {
      0xFFFF
    } else {
      0
    }
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i16(
  self : ExecContext,
  op : (Int32, Int32) -> Int32,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<8 {
    let result = op(get_i16_lane(a, i), get_i16_lane(b, i))
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i16(
  self : ExecContext,
  op : (Int32) -> Int32,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<8 {
    let result = op(get_i16_lane(a, i))
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_i32(
  self : ExecContext,
  cmp : (Int32, Int32) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    let result = if cmp(get_i32_lane(a, i), get_i32_lane(b, i)) {
      -1
    } else {
      0
    }
    buf.write_int_le(result)
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i32(
  self : ExecContext,
  op : (Int32, Int32) -> Int32,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    buf.write_int_le(op(get_i32_lane(a, i), get_i32_lane(b, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i32(
  self : ExecContext,
  op : (Int32) -> Int32,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    buf.write_int_le(op(get_i32_lane(a, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_i64(
  self : ExecContext,
  cmp : (Int64, Int64) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    let result : Int64 = if cmp(get_i64_lane(a, i), get_i64_lane(b, i)) {
      -1L
    } else {
      0L
    }
    buf.write_int64_le(result)
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i64(
  self : ExecContext,
  op : (Int64, Int64) -> Int64,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    buf.write_int64_le(op(get_i64_lane(a, i), get_i64_lane(b, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i64(
  self : ExecContext,
  op : (Int64) -> Int64,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    buf.write_int64_le(op(get_i64_lane(a, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_f32(
  self : ExecContext,
  cmp : (Float, Float) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    let result = if cmp(get_f32_lane(a, i), get_f32_lane(b, i)) {
      -1
    } else {
      0
    }
    buf.write_int_le(result)
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_f32(
  self : ExecContext,
  op : (Float, Float) -> Float,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    buf.write_float_le(op(get_f32_lane(a, i), get_f32_lane(b, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_f32(
  self : ExecContext,
  op : (Float) -> Float,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<4 {
    buf.write_float_le(op(get_f32_lane(a, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_f64(
  self : ExecContext,
  cmp : (Double, Double) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    let result : Int64 = if cmp(get_f64_lane(a, i), get_f64_lane(b, i)) {
      -1L
    } else {
      0L
    }
    buf.write_int64_le(result)
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_f64(
  self : ExecContext,
  op : (Double, Double) -> Double,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    buf.write_double_le(op(get_f64_lane(a, i), get_f64_lane(b, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_f64(
  self : ExecContext,
  op : (Double) -> Double,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = Buffer(size_hint=16)
  for i in 0..<2 {
    buf.write_double_le(op(get_f64_lane(a, i)))
  }
  self.stack.push(V128(buf.contents()))
}

///|
fn sat_add_i8_s(a : Int32, b : Int32) -> Byte {
  let sa = sign_i8(a)
  let sb = sign_i8(b)
  let result = sa + sb
  if result > @types.I8_MAX {
    b'\x7F'
  } else if result < -128 {
    b'\x80'
  } else {
    (result & @types.U8_MAX).to_byte()
  }
}

///|
fn sat_add_i8_u(a : Int32, b : Int32) -> Byte {
  let result = a + b
  if result > @types.U8_MAX {
    b'\xFF'
  } else {
    result.to_byte()
  }
}

///|
fn sat_sub_i8_s(a : Int32, b : Int32) -> Byte {
  let sa = sign_i8(a)
  let sb = sign_i8(b)
  let result = sa - sb
  if result > @types.I8_MAX {
    b'\x7F'
  } else if result < -128 {
    b'\x80'
  } else {
    (result & @types.U8_MAX).to_byte()
  }
}

///|
fn sat_sub_i8_u(a : Int32, b : Int32) -> Byte {
  let result = a - b
  if result < 0 {
    b'\x00'
  } else {
    result.to_byte()
  }
}

///|
fn sat_add_i16_s(a : Int32, b : Int32) -> Int32 {
  let sa = sign_i16(a)
  let sb = sign_i16(b)
  let result = sa + sb
  if result > 32767 {
    32767
  } else if result < -32768 {
    -32768 & 0xFFFF
  } else {
    result & 0xFFFF
  }
}

///|
fn sat_add_i16_u(a : Int32, b : Int32) -> Int32 {
  let result = a + b
  if result > 65535 {
    65535
  } else {
    result
  }
}

///|
fn sat_sub_i16_s(a : Int32, b : Int32) -> Int32 {
  let sa = sign_i16(a)
  let sb = sign_i16(b)
  let result = sa - sb
  if result > 32767 {
    32767
  } else if result < -32768 {
    -32768 & 0xFFFF
  } else {
    result & 0xFFFF
  }
}

///|
fn sat_sub_i16_u(a : Int32, b : Int32) -> Int32 {
  let result = a - b
  if result < 0 {
    0
  } else {
    result
  }
}

///|
fn popcount8(v : Int32) -> Int32 {
  let mut n = v
  let mut count = 0
  while n != 0 {
    count = count + (n & 1)
    n = n >> 1
  }
  count
}

///|
fn sat_i16_to_i8_s(v : Int32) -> Byte {
  let sv = sign_i16(v)
  if sv > @types.I8_MAX {
    b'\x7F'
  } else if sv < -128 {
    b'\x80'
  } else {
    (sv & @types.U8_MAX).to_byte()
  }
}

///|
fn sat_i16_to_u8(v : Int32) -> Byte {
  let sv = sign_i16(v)
  if sv > @types.U8_MAX {
    b'\xFF'
  } else if sv < 0 {
    b'\x00'
  } else {
    sv.to_byte()
  }
}

///|
fn sat_i32_to_i16_s(v : Int32) -> Int32 {
  if v > 32767 {
    32767
  } else if v < -32768 {
    -32768 & 0xFFFF
  } else {
    v & 0xFFFF
  }
}

///|
fn sat_i32_to_u16(v : Int32) -> Int32 {
  if v > 65535 {
    65535
  } else if v < 0 {
    0
  } else {
    v
  }
}

///|
fn f32_min(a : Float, b : Float) -> Float {
  // NaN handling: if either is NaN, return NaN
  if a.is_nan() || b.is_nan() {
    return Float::reinterpret_from_int(0x7fc00000)
  }
  // +0 and -0 handling
  if a == 0.0 && b == 0.0 {
    // Return -0 if either is -0
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    // -0.0 has high bit set, so higher unsigned value
    if a_bits > b_bits {
      return a
    }
    return b
  }
  if a < b {
    a
  } else {
    b
  }
}

///|
fn f32_max(a : Float, b : Float) -> Float {
  if a.is_nan() || b.is_nan() {
    return Float::reinterpret_from_int(0x7fc00000)
  }
  if a == 0.0 && b == 0.0 {
    let a_bits = a.reinterpret_as_uint()
    let b_bits = b.reinterpret_as_uint()
    // +0.0 has lower unsigned value
    if a_bits < b_bits {
      return a
    }
    return b
  }
  if a > b {
    a
  } else {
    b
  }
}

///|
fn f64_min(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    return 0x7ff8000000000000L.reinterpret_as_double()
  }
  if a == 0.0 && b == 0.0 {
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    // Return -0 if either is -0 (higher bit pattern for -0.0)
    if a_bits > b_bits {
      return a
    }
    return b
  }
  if a < b {
    a
  } else {
    b
  }
}

///|
fn f64_max(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    return 0x7ff8000000000000L.reinterpret_as_double()
  }
  if a == 0.0 && b == 0.0 {
    let a_bits = a.reinterpret_as_uint64()
    let b_bits = b.reinterpret_as_uint64()
    // +0.0 has lower unsigned value
    if a_bits < b_bits {
      return a
    }
    return b
  }
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Round with sign preservation (for -0.0)
fn f32_ceil_signed(a : Float) -> Float {
  if a.is_nan() {
    return Float::reinterpret_from_int(a.reinterpret_as_int() | 0x00400000)
  }
  let result = a.ceil()
  // If result is 0 but input was negative, preserve -0.0
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U) // -0.0
  } else {
    result
  }
}

///|
fn f32_floor_signed(a : Float) -> Float {
  if a.is_nan() {
    return Float::reinterpret_from_int(a.reinterpret_as_int() | 0x00400000)
  }
  let result = a.floor()
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U)
  } else {
    result
  }
}

///|
fn f32_trunc_signed(a : Float) -> Float {
  if a.is_nan() {
    return Float::reinterpret_from_int(a.reinterpret_as_int() | 0x00400000)
  }
  let result = a.trunc()
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U)
  } else {
    result
  }
}

///|
fn f32_nearest_signed(a : Float) -> Float {
  if a.is_nan() {
    return Float::reinterpret_from_int(a.reinterpret_as_int() | 0x00400000)
  }
  // Values at this magnitude are already integral, including infinity.
  if a.abs() >= 8388608.0 {
    return a
  }
  // WebAssembly uses "round to nearest even" (banker's rounding)
  let d = a.to_double()
  let floor_val = d.floor()
  let ceil_val = d.ceil()
  let diff_floor = d - floor_val
  let diff_ceil = ceil_val - d
  let result : Float = if diff_floor < diff_ceil {
    Float::from_double(floor_val)
  } else if diff_floor > diff_ceil {
    Float::from_double(ceil_val)
  } else {
    // Exactly halfway - round to even
    let floor_int = floor_val.to_int()
    if floor_int % 2 == 0 {
      Float::from_double(floor_val)
    } else {
      Float::from_double(ceil_val)
    }
  }
  // Preserve -0.0 sign
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U)
  } else {
    result
  }
}

///|
fn f64_ceil_signed(a : Double) -> Double {
  if a.is_nan() {
    return (a.reinterpret_as_int64() | 0x0008000000000000L).reinterpret_as_double()
  }
  let result = a.ceil()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double() // -0.0
  } else {
    result
  }
}

///|
fn f64_floor_signed(a : Double) -> Double {
  if a.is_nan() {
    return (a.reinterpret_as_int64() | 0x0008000000000000L).reinterpret_as_double()
  }
  let result = a.floor()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    result
  }
}

///|
fn f64_trunc_signed(a : Double) -> Double {
  if a.is_nan() {
    return (a.reinterpret_as_int64() | 0x0008000000000000L).reinterpret_as_double()
  }
  let result = a.trunc()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    result
  }
}

///|
fn f64_nearest_signed(a : Double) -> Double {
  if a.is_nan() {
    return (a.reinterpret_as_int64() | 0x0008000000000000L).reinterpret_as_double()
  }
  // Values at this magnitude are already integral, including infinity.
  if a.abs() >= 4503599627370496.0 {
    return a
  }
  // WebAssembly uses "round to nearest even" (banker's rounding)
  let floor_val = a.floor()
  let ceil_val = a.ceil()
  let diff_floor = a - floor_val
  let diff_ceil = ceil_val - a
  let result = if diff_floor < diff_ceil {
    floor_val
  } else if diff_floor > diff_ceil {
    ceil_val
  } else {
    // Exactly halfway - round to even
    let floor_int = floor_val.to_int64()
    if floor_int % 2L == 0L {
      floor_val
    } else {
      ceil_val
    }
  }
  // Preserve -0.0 sign
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    result
  }
}
