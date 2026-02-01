///|
fn v128_replace_i8(v128 : Bytes, lane : Int, val : Byte) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<16 {
    if i == lane {
      buf.write_byte(val)
    } else {
      buf.write_byte(v128[i])
    }
  }
  buf.contents()
}

///|
fn v128_replace_i16(v128 : Bytes, lane : Int, val : Int) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  let offset = lane * 2
  for i in 0..<16 {
    if i == offset {
      buf.write_byte(val.to_byte())
    } else if i == offset + 1 {
      buf.write_byte((val >> 8).to_byte())
    } else {
      buf.write_byte(v128[i])
    }
  }
  buf.contents()
}

///|
fn v128_replace_i32(v128 : Bytes, lane : Int, val : Int) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  let offset = lane * 4
  for i in 0..<16 {
    if i == offset {
      buf.write_byte(val.to_byte())
    } else if i == offset + 1 {
      buf.write_byte((val >> 8).to_byte())
    } else if i == offset + 2 {
      buf.write_byte((val >> 16).to_byte())
    } else if i == offset + 3 {
      buf.write_byte((val >> 24).to_byte())
    } else {
      buf.write_byte(v128[i])
    }
  }
  buf.contents()
}

///|
fn v128_replace_i64(v128 : Bytes, lane : Int, val : Int64) -> Bytes {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  let offset = lane * 8
  for i in 0..<16 {
    if i == offset {
      buf.write_byte(val.to_byte())
    } else if i == offset + 1 {
      buf.write_byte((val >> 8).to_byte())
    } else if i == offset + 2 {
      buf.write_byte((val >> 16).to_byte())
    } else if i == offset + 3 {
      buf.write_byte((val >> 24).to_byte())
    } else if i == offset + 4 {
      buf.write_byte((val >> 32).to_byte())
    } else if i == offset + 5 {
      buf.write_byte((val >> 40).to_byte())
    } else if i == offset + 6 {
      buf.write_byte((val >> 48).to_byte())
    } else if i == offset + 7 {
      buf.write_byte((val >> 56).to_byte())
    } else {
      buf.write_byte(v128[i])
    }
  }
  buf.contents()
}

///|
fn sign_i8(v : Int) -> Int {
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
fn ExecContext::exec_v128_cmp_i8(
  self : ExecContext,
  cmp : (Int, Int) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<16 {
    let result = if cmp(a[i].to_int(), b[i].to_int()) { 0xFF } else { 0 }
    buf.write_byte(result.to_byte())
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i8(
  self : ExecContext,
  op : (Int, Int) -> Byte,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<16 {
    buf.write_byte(op(a[i].to_int(), b[i].to_int()))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i8(
  self : ExecContext,
  op : (Int) -> Byte,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<16 {
    buf.write_byte(op(a[i].to_int()))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn sign_i16(v : Int) -> Int {
  if v >= 32768 {
    v - 65536
  } else {
    v
  }
}

///|
fn get_i16_lane(v : Bytes, lane : Int) -> Int {
  let offset = lane * 2
  v[offset].to_int() | (v[offset + 1].to_int() << 8)
}

///|
fn get_i32_lane(v : Bytes, lane : Int) -> Int {
  let offset = lane * 4
  v[offset].to_int() |
  (v[offset + 1].to_int() << 8) |
  (v[offset + 2].to_int() << 16) |
  (v[offset + 3].to_int() << 24)
}

///|
fn get_i64_lane(v : Bytes, lane : Int) -> Int64 {
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
fn get_f32_lane(v : Bytes, lane : Int) -> Float {
  Float::reinterpret_from_int(get_i32_lane(v, lane))
}

///|
fn get_f64_lane(v : Bytes, lane : Int) -> Double {
  get_i64_lane(v, lane).reinterpret_as_double()
}

///|
fn write_i32_lane(buf : @buffer.Buffer, v : Int) -> Unit {
  buf.write_byte(v.to_byte())
  buf.write_byte((v >> 8).to_byte())
  buf.write_byte((v >> 16).to_byte())
  buf.write_byte((v >> 24).to_byte())
}

///|
fn write_i64_lane(buf : @buffer.Buffer, v : Int64) -> Unit {
  buf.write_byte(v.to_byte())
  buf.write_byte((v >> 8).to_byte())
  buf.write_byte((v >> 16).to_byte())
  buf.write_byte((v >> 24).to_byte())
  buf.write_byte((v >> 32).to_byte())
  buf.write_byte((v >> 40).to_byte())
  buf.write_byte((v >> 48).to_byte())
  buf.write_byte((v >> 56).to_byte())
}

///|
fn write_f32_lane(buf : @buffer.Buffer, v : Float) -> Unit {
  write_i32_lane(buf, v.reinterpret_as_int())
}

///|
fn write_f64_lane(buf : @buffer.Buffer, v : Double) -> Unit {
  write_i64_lane(buf, v.reinterpret_as_int64())
}

///|
fn write_i16_lane(buf : @buffer.Buffer, v : Int) -> Unit {
  buf.write_byte(v.to_byte())
  buf.write_byte((v >> 8).to_byte())
}

///|
fn sign_extend_i8(v : Int) -> Int {
  if (v & 0x80) != 0 {
    v | 0xFFFFFF00
  } else {
    v & 0xFF
  }
}

///|
fn sign_extend_i16(v : Int) -> Int {
  if (v & 0x8000) != 0 {
    v | 0xFFFF0000
  } else {
    v & 0xFFFF
  }
}

///|
fn trunc_sat_f32_to_i32_u(f : Float) -> Int {
  if f.is_nan() {
    return 0
  }
  if f <= 0.0 {
    return 0
  }
  if f >= 4294967296.0 {
    return -1 // 0xFFFFFFFF as signed int
  }
  f.to_double().to_uint().reinterpret_as_int()
}

///|
fn trunc_sat_f64_to_i32_u(f : Double) -> Int {
  if f.is_nan() {
    return 0
  }
  if f <= 0.0 {
    return 0
  }
  if f >= 4294967296.0 {
    return -1 // 0xFFFFFFFF as signed int
  }
  f.to_uint().reinterpret_as_int()
}

///|
fn ExecContext::exec_v128_cmp_i16(
  self : ExecContext,
  cmp : (Int, Int) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<8 {
    let result = if cmp(get_i16_lane(a, i), get_i16_lane(b, i)) {
      0xFFFF
    } else {
      0
    }
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i16(
  self : ExecContext,
  op : (Int, Int) -> Int,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<8 {
    let result = op(get_i16_lane(a, i), get_i16_lane(b, i))
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i16(
  self : ExecContext,
  op : (Int) -> Int,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<8 {
    let result = op(get_i16_lane(a, i))
    buf.write_byte(result.to_byte())
    buf.write_byte((result >> 8).to_byte())
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_i32(
  self : ExecContext,
  cmp : (Int, Int) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    let result = if cmp(get_i32_lane(a, i), get_i32_lane(b, i)) {
      -1
    } else {
      0
    }
    write_i32_lane(buf, result)
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i32(
  self : ExecContext,
  op : (Int, Int) -> Int,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    write_i32_lane(buf, op(get_i32_lane(a, i), get_i32_lane(b, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i32(
  self : ExecContext,
  op : (Int) -> Int,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    write_i32_lane(buf, op(get_i32_lane(a, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_i64(
  self : ExecContext,
  cmp : (Int64, Int64) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    let result : Int64 = if cmp(get_i64_lane(a, i), get_i64_lane(b, i)) {
      -1L
    } else {
      0L
    }
    write_i64_lane(buf, result)
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_i64(
  self : ExecContext,
  op : (Int64, Int64) -> Int64,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    write_i64_lane(buf, op(get_i64_lane(a, i), get_i64_lane(b, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_i64(
  self : ExecContext,
  op : (Int64) -> Int64,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    write_i64_lane(buf, op(get_i64_lane(a, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_f32(
  self : ExecContext,
  cmp : (Float, Float) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    let result = if cmp(get_f32_lane(a, i), get_f32_lane(b, i)) {
      -1
    } else {
      0
    }
    write_i32_lane(buf, result)
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_f32(
  self : ExecContext,
  op : (Float, Float) -> Float,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    write_f32_lane(buf, op(get_f32_lane(a, i), get_f32_lane(b, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_f32(
  self : ExecContext,
  op : (Float) -> Float,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<4 {
    write_f32_lane(buf, op(get_f32_lane(a, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_cmp_f64(
  self : ExecContext,
  cmp : (Double, Double) -> Bool,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    let result : Int64 = if cmp(get_f64_lane(a, i), get_f64_lane(b, i)) {
      -1L
    } else {
      0L
    }
    write_i64_lane(buf, result)
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_binop_f64(
  self : ExecContext,
  op : (Double, Double) -> Double,
) -> Unit raise {
  let b = self.stack.pop_v128()
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    write_f64_lane(buf, op(get_f64_lane(a, i), get_f64_lane(b, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn ExecContext::exec_v128_unop_f64(
  self : ExecContext,
  op : (Double) -> Double,
) -> Unit raise {
  let a = self.stack.pop_v128()
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  for i in 0..<2 {
    write_f64_lane(buf, op(get_f64_lane(a, i)))
  }
  self.stack.push(@types.Value::V128(buf.contents()))
}

///|
fn sat_add_i8_s(a : Int, b : Int) -> Byte {
  let sa = sign_i8(a)
  let sb = sign_i8(b)
  let result = sa + sb
  if result > 127 {
    b'\x7F'
  } else if result < -128 {
    b'\x80'
  } else {
    (result & 0xFF).to_byte()
  }
}

///|
fn sat_add_i8_u(a : Int, b : Int) -> Byte {
  let result = a + b
  if result > 255 {
    b'\xFF'
  } else {
    result.to_byte()
  }
}

///|
fn sat_sub_i8_s(a : Int, b : Int) -> Byte {
  let sa = sign_i8(a)
  let sb = sign_i8(b)
  let result = sa - sb
  if result > 127 {
    b'\x7F'
  } else if result < -128 {
    b'\x80'
  } else {
    (result & 0xFF).to_byte()
  }
}

///|
fn sat_sub_i8_u(a : Int, b : Int) -> Byte {
  let result = a - b
  if result < 0 {
    b'\x00'
  } else {
    result.to_byte()
  }
}

///|
fn sat_add_i16_s(a : Int, b : Int) -> Int {
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
fn sat_add_i16_u(a : Int, b : Int) -> Int {
  let result = a + b
  if result > 65535 {
    65535
  } else {
    result
  }
}

///|
fn sat_sub_i16_s(a : Int, b : Int) -> Int {
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
fn sat_sub_i16_u(a : Int, b : Int) -> Int {
  let result = a - b
  if result < 0 {
    0
  } else {
    result
  }
}

///|
fn popcount8(v : Int) -> Int {
  let mut n = v
  let mut count = 0
  while n != 0 {
    count = count + (n & 1)
    n = n >> 1
  }
  count
}

///|
fn sat_i16_to_i8_s(v : Int) -> Byte {
  let sv = sign_i16(v)
  if sv > 127 {
    b'\x7F'
  } else if sv < -128 {
    b'\x80'
  } else {
    (sv & 0xFF).to_byte()
  }
}

///|
fn sat_i16_to_u8(v : Int) -> Byte {
  let sv = sign_i16(v)
  if sv > 255 {
    b'\xFF'
  } else if sv < 0 {
    b'\x00'
  } else {
    sv.to_byte()
  }
}

///|
fn sat_i32_to_i16_s(v : Int) -> Int {
  if v > 32767 {
    32767
  } else if v < -32768 {
    -32768 & 0xFFFF
  } else {
    v & 0xFFFF
  }
}

///|
fn sat_i32_to_u16(v : Int) -> Int {
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
    return @float.not_a_number
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
    return @float.not_a_number
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
    return @double.not_a_number
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
    return @double.not_a_number
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
fn trunc_sat_f32_to_i32_s(f : Float) -> Int {
  if f.is_nan() {
    return 0
  }
  if f >= 2147483648.0 {
    return 2147483647
  }
  if f <= -2147483649.0 {
    return -2147483648
  }
  f.to_int()
}

///|
fn trunc_sat_f32_to_u32(f : Float) -> UInt {
  if f.is_nan() {
    return 0U
  }
  if f <= 0.0 {
    return 0U
  }
  if f >= 4294967296.0 {
    return 4294967295U
  }
  f.to_double().to_uint()
}

///|
fn trunc_sat_f64_to_i32_s(f : Double) -> Int {
  if f.is_nan() {
    return 0
  }
  if f >= 2147483648.0 {
    return 2147483647
  }
  if f <= -2147483649.0 {
    return -2147483648
  }
  f.to_int()
}

///|
fn trunc_sat_f64_to_u32(f : Double) -> UInt {
  if f.is_nan() {
    return 0U
  }
  if f <= 0.0 {
    return 0U
  }
  if f >= 4294967296.0 {
    return 4294967295U
  }
  f.to_uint()
}

///|
/// Round with sign preservation (for -0.0)
fn f32_ceil_signed(a : Float) -> Float {
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
  let result = a.floor()
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U)
  } else {
    result
  }
}

///|
fn f32_trunc_signed(a : Float) -> Float {
  let result = a.trunc()
  if result == 0.0 && a.reinterpret_as_uint() >= 0x80000000U {
    Float::reinterpret_from_uint(0x80000000U)
  } else {
    result
  }
}

///|
fn f32_nearest_signed(a : Float) -> Float {
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
  let result = a.ceil()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double() // -0.0
  } else {
    result
  }
}

///|
fn f64_floor_signed(a : Double) -> Double {
  let result = a.floor()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    result
  }
}

///|
fn f64_trunc_signed(a : Double) -> Double {
  let result = a.trunc()
  if result == 0.0 && a.reinterpret_as_uint64() >= 0x8000000000000000UL {
    0x8000000000000000UL.reinterpret_as_double()
  } else {
    result
  }
}

///|
fn f64_nearest_signed(a : Double) -> Double {
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
