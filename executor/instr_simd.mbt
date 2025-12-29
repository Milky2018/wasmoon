///|
/// SIMD (V128) instruction execution for WebAssembly interpreter

///|
fn ExecContext::exec_simd(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    V128Const(bytes) => self.stack.push(@types.Value::V128(bytes))

    // Splat operations - broadcast scalar to all lanes
    I8x16Splat => {
      let v = self.stack.pop_i32()
      let b = v.to_byte()
      let bytes = Bytes::make(16, b)
      self.stack.push(@types.Value::V128(bytes))
    }
    I16x8Splat => {
      let v = self.stack.pop_i32()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<8 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4Splat => {
      let v = self.stack.pop_i32()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<4 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
        buf.write_byte((v >> 16).to_byte())
        buf.write_byte((v >> 24).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2Splat => {
      let v = self.stack.pop_i64()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<2 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
        buf.write_byte((v >> 16).to_byte())
        buf.write_byte((v >> 24).to_byte())
        buf.write_byte((v >> 32).to_byte())
        buf.write_byte((v >> 40).to_byte())
        buf.write_byte((v >> 48).to_byte())
        buf.write_byte((v >> 56).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4Splat => {
      let f = self.stack.pop_f32()
      let v = f.reinterpret_as_int()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<4 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
        buf.write_byte((v >> 16).to_byte())
        buf.write_byte((v >> 24).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2Splat => {
      let f = self.stack.pop_f64()
      let v = f.reinterpret_as_int64()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<2 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
        buf.write_byte((v >> 16).to_byte())
        buf.write_byte((v >> 24).to_byte())
        buf.write_byte((v >> 32).to_byte())
        buf.write_byte((v >> 40).to_byte())
        buf.write_byte((v >> 48).to_byte())
        buf.write_byte((v >> 56).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // Extract lane operations
    I8x16ExtractLaneS(lane) => {
      let v128 = self.stack.pop_v128()
      let v = v128[lane].to_int()
      // Sign-extend from i8
      let result = if v >= 128 { v - 256 } else { v }
      self.stack.push(@types.Value::I32(result))
    }
    I8x16ExtractLaneU(lane) => {
      let v128 = self.stack.pop_v128()
      self.stack.push(@types.Value::I32(v128[lane].to_int()))
    }
    I16x8ExtractLaneS(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 2
      let v = v128[offset].to_int() | (v128[offset + 1].to_int() << 8)
      // Sign-extend from i16
      let result = if v >= 32768 { v - 65536 } else { v }
      self.stack.push(@types.Value::I32(result))
    }
    I16x8ExtractLaneU(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 2
      let v = v128[offset].to_int() | (v128[offset + 1].to_int() << 8)
      self.stack.push(@types.Value::I32(v))
    }
    I32x4ExtractLane(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 4
      let v = v128[offset].to_int() |
        (v128[offset + 1].to_int() << 8) |
        (v128[offset + 2].to_int() << 16) |
        (v128[offset + 3].to_int() << 24)
      self.stack.push(@types.Value::I32(v))
    }
    I64x2ExtractLane(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 8
      let v = v128[offset].to_int().to_int64() |
        (v128[offset + 1].to_int().to_int64() << 8) |
        (v128[offset + 2].to_int().to_int64() << 16) |
        (v128[offset + 3].to_int().to_int64() << 24) |
        (v128[offset + 4].to_int().to_int64() << 32) |
        (v128[offset + 5].to_int().to_int64() << 40) |
        (v128[offset + 6].to_int().to_int64() << 48) |
        (v128[offset + 7].to_int().to_int64() << 56)
      self.stack.push(@types.Value::I64(v))
    }
    F32x4ExtractLane(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 4
      let bits = v128[offset].to_int() |
        (v128[offset + 1].to_int() << 8) |
        (v128[offset + 2].to_int() << 16) |
        (v128[offset + 3].to_int() << 24)
      self.stack.push(@types.Value::F32(Float::reinterpret_from_int(bits)))
    }
    F64x2ExtractLane(lane) => {
      let v128 = self.stack.pop_v128()
      let offset = lane * 8
      let bits = v128[offset].to_int().to_int64() |
        (v128[offset + 1].to_int().to_int64() << 8) |
        (v128[offset + 2].to_int().to_int64() << 16) |
        (v128[offset + 3].to_int().to_int64() << 24) |
        (v128[offset + 4].to_int().to_int64() << 32) |
        (v128[offset + 5].to_int().to_int64() << 40) |
        (v128[offset + 6].to_int().to_int64() << 48) |
        (v128[offset + 7].to_int().to_int64() << 56)
      self.stack.push(@types.Value::F64(bits.reinterpret_as_double()))
    }

    // Replace lane operations
    I8x16ReplaceLane(lane) => {
      let v = self.stack.pop_i32()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i8(v128, lane, v.to_byte())
      self.stack.push(@types.Value::V128(result))
    }
    I16x8ReplaceLane(lane) => {
      let v = self.stack.pop_i32()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i16(v128, lane, v)
      self.stack.push(@types.Value::V128(result))
    }
    I32x4ReplaceLane(lane) => {
      let v = self.stack.pop_i32()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i32(v128, lane, v)
      self.stack.push(@types.Value::V128(result))
    }
    I64x2ReplaceLane(lane) => {
      let v = self.stack.pop_i64()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i64(v128, lane, v)
      self.stack.push(@types.Value::V128(result))
    }
    F32x4ReplaceLane(lane) => {
      let f = self.stack.pop_f32()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i32(v128, lane, f.reinterpret_as_int())
      self.stack.push(@types.Value::V128(result))
    }
    F64x2ReplaceLane(lane) => {
      let f = self.stack.pop_f64()
      let v128 = self.stack.pop_v128()
      let result = v128_replace_i64(v128, lane, f.reinterpret_as_int64())
      self.stack.push(@types.Value::V128(result))
    }

    // Bitwise operations
    V128Not => {
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((a[i].to_int() ^ 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128And => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((a[i].to_int() & b[i].to_int()).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128AndNot => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((a[i].to_int() & (b[i].to_int() ^ 0xFF)).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Or => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((a[i].to_int() | b[i].to_int()).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Xor => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((a[i].to_int() ^ b[i].to_int()).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Bitselect => {
      let c = self.stack.pop_v128() // mask
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let mask = c[i].to_int()
        let val = (a[i].to_int() & mask) | (b[i].to_int() & (mask ^ 0xFF))
        buf.write_byte(val.to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128AnyTrue => {
      let v = self.stack.pop_v128()
      let mut any = false
      for i in 0..<16 {
        if v[i] != b'\x00' {
          any = true
          break
        }
      }
      self.stack.push(@types.Value::I32(if any { 1 } else { 0 }))
    }

    // i8x16 comparisons
    I8x16Eq => self.exec_v128_cmp_i8(fn(a, b) { a == b })
    I8x16Ne => self.exec_v128_cmp_i8(fn(a, b) { a != b })
    I8x16LtS => self.exec_v128_cmp_i8(fn(a, b) { sign_i8(a) < sign_i8(b) })
    I8x16LtU => self.exec_v128_cmp_i8(fn(a, b) { a < b })
    I8x16GtS => self.exec_v128_cmp_i8(fn(a, b) { sign_i8(a) > sign_i8(b) })
    I8x16GtU => self.exec_v128_cmp_i8(fn(a, b) { a > b })
    I8x16LeS => self.exec_v128_cmp_i8(fn(a, b) { sign_i8(a) <= sign_i8(b) })
    I8x16LeU => self.exec_v128_cmp_i8(fn(a, b) { a <= b })
    I8x16GeS => self.exec_v128_cmp_i8(fn(a, b) { sign_i8(a) >= sign_i8(b) })
    I8x16GeU => self.exec_v128_cmp_i8(fn(a, b) { a >= b })

    // i8x16 arithmetic
    I8x16Add => self.exec_v128_binop_i8(fn(a, b) { ((a + b) & 0xFF).to_byte() })
    I8x16Sub => self.exec_v128_binop_i8(fn(a, b) { ((a - b) & 0xFF).to_byte() })
    I8x16AddSatS => self.exec_v128_binop_i8(fn(a, b) { sat_add_i8_s(a, b) })
    I8x16AddSatU => self.exec_v128_binop_i8(fn(a, b) { sat_add_i8_u(a, b) })
    I8x16SubSatS => self.exec_v128_binop_i8(fn(a, b) { sat_sub_i8_s(a, b) })
    I8x16SubSatU => self.exec_v128_binop_i8(fn(a, b) { sat_sub_i8_u(a, b) })
    I8x16MinS =>
      self.exec_v128_binop_i8(fn(a, b) {
        if sign_i8(a) < sign_i8(b) {
          a.to_byte()
        } else {
          b.to_byte()
        }
      })
    I8x16MinU =>
      self.exec_v128_binop_i8(fn(a, b) {
        if a < b {
          a.to_byte()
        } else {
          b.to_byte()
        }
      })
    I8x16MaxS =>
      self.exec_v128_binop_i8(fn(a, b) {
        if sign_i8(a) > sign_i8(b) {
          a.to_byte()
        } else {
          b.to_byte()
        }
      })
    I8x16MaxU =>
      self.exec_v128_binop_i8(fn(a, b) {
        if a > b {
          a.to_byte()
        } else {
          b.to_byte()
        }
      })
    I8x16AvgrU =>
      self.exec_v128_binop_i8(fn(a, b) { ((a + b + 1) / 2).to_byte() })
    I8x16Abs =>
      self.exec_v128_unop_i8(fn(a) {
        if sign_i8(a) < 0 {
          (-sign_i8(a) & 0xFF).to_byte()
        } else {
          a.to_byte()
        }
      })
    I8x16Neg => self.exec_v128_unop_i8(fn(a) { (-a & 0xFF).to_byte() })
    I8x16Popcnt => self.exec_v128_unop_i8(fn(a) { popcount8(a).to_byte() })
    I8x16AllTrue => {
      let v = self.stack.pop_v128()
      let mut all = true
      for i in 0..<16 {
        if v[i] == b'\x00' {
          all = false
          break
        }
      }
      self.stack.push(@types.Value::I32(if all { 1 } else { 0 }))
    }
    I8x16Bitmask => {
      let v = self.stack.pop_v128()
      let mut result = 0
      for i in 0..<16 {
        if v[i].to_int() >= 128 {
          result = result | (1 << i)
        }
      }
      self.stack.push(@types.Value::I32(result))
    }
    I8x16Shl => {
      let shift = self.stack.pop_i32() & 7 // mod 8
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte(((v[i].to_int() << shift) & 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16ShrS => {
      let shift = self.stack.pop_i32() & 7
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let signed = sign_i8(v[i].to_int())
        buf.write_byte(((signed >> shift) & 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16ShrU => {
      let shift = self.stack.pop_i32() & 7
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte((v[i].to_int() >> shift).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16NarrowI16x8S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let va = get_i16_lane(a, i)
        buf.write_byte(sat_i16_to_i8_s(va))
      }
      for i in 0..<8 {
        let vb = get_i16_lane(b, i)
        buf.write_byte(sat_i16_to_i8_s(vb))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16NarrowI16x8U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let va = get_i16_lane(a, i)
        buf.write_byte(sat_i16_to_u8(va))
      }
      for i in 0..<8 {
        let vb = get_i16_lane(b, i)
        buf.write_byte(sat_i16_to_u8(vb))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // i16x8 comparisons
    I16x8Eq => self.exec_v128_cmp_i16(fn(a, b) { a == b })
    I16x8Ne => self.exec_v128_cmp_i16(fn(a, b) { a != b })
    I16x8LtS => self.exec_v128_cmp_i16(fn(a, b) { sign_i16(a) < sign_i16(b) })
    I16x8LtU => self.exec_v128_cmp_i16(fn(a, b) { a < b })
    I16x8GtS => self.exec_v128_cmp_i16(fn(a, b) { sign_i16(a) > sign_i16(b) })
    I16x8GtU => self.exec_v128_cmp_i16(fn(a, b) { a > b })
    I16x8LeS => self.exec_v128_cmp_i16(fn(a, b) { sign_i16(a) <= sign_i16(b) })
    I16x8LeU => self.exec_v128_cmp_i16(fn(a, b) { a <= b })
    I16x8GeS => self.exec_v128_cmp_i16(fn(a, b) { sign_i16(a) >= sign_i16(b) })
    I16x8GeU => self.exec_v128_cmp_i16(fn(a, b) { a >= b })

    // i16x8 arithmetic
    I16x8Add => self.exec_v128_binop_i16(fn(a, b) { (a + b) & 0xFFFF })
    I16x8Sub => self.exec_v128_binop_i16(fn(a, b) { (a - b) & 0xFFFF })
    I16x8Mul => self.exec_v128_binop_i16(fn(a, b) { (a * b) & 0xFFFF })
    I16x8AddSatS => self.exec_v128_binop_i16(fn(a, b) { sat_add_i16_s(a, b) })
    I16x8AddSatU => self.exec_v128_binop_i16(fn(a, b) { sat_add_i16_u(a, b) })
    I16x8SubSatS => self.exec_v128_binop_i16(fn(a, b) { sat_sub_i16_s(a, b) })
    I16x8SubSatU => self.exec_v128_binop_i16(fn(a, b) { sat_sub_i16_u(a, b) })
    I16x8MinS =>
      self.exec_v128_binop_i16(fn(a, b) {
        if sign_i16(a) < sign_i16(b) {
          a
        } else {
          b
        }
      })
    I16x8MinU =>
      self.exec_v128_binop_i16(fn(a, b) { if a < b { a } else { b } })
    I16x8MaxS =>
      self.exec_v128_binop_i16(fn(a, b) {
        if sign_i16(a) > sign_i16(b) {
          a
        } else {
          b
        }
      })
    I16x8MaxU =>
      self.exec_v128_binop_i16(fn(a, b) { if a > b { a } else { b } })
    I16x8AvgrU => self.exec_v128_binop_i16(fn(a, b) { (a + b + 1) / 2 })
    I16x8Abs =>
      self.exec_v128_unop_i16(fn(a) {
        if sign_i16(a) < 0 {
          -sign_i16(a) & 0xFFFF
        } else {
          a
        }
      })
    I16x8Neg => self.exec_v128_unop_i16(fn(a) { -a & 0xFFFF })
    I16x8Q15MulrSatS =>
      self.exec_v128_binop_i16(fn(a, b) {
        let sa = sign_i16(a)
        let sb = sign_i16(b)
        let result = (sa * sb + 0x4000) >> 15
        // saturate
        if result > 32767 {
          32767
        } else if result < -32768 {
          -32768 & 0xFFFF
        } else {
          result & 0xFFFF
        }
      })
    I16x8AllTrue => {
      let v = self.stack.pop_v128()
      let mut all = true
      for i in 0..<8 {
        if get_i16_lane(v, i) == 0 {
          all = false
          break
        }
      }
      self.stack.push(@types.Value::I32(if all { 1 } else { 0 }))
    }
    I16x8Bitmask => {
      let v = self.stack.pop_v128()
      let mut result = 0
      for i in 0..<8 {
        if get_i16_lane(v, i) >= 32768 {
          result = result | (1 << i)
        }
      }
      self.stack.push(@types.Value::I32(result))
    }
    I16x8Shl => {
      let shift = self.stack.pop_i32() & 15
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let lane = get_i16_lane(v, i)
        let shifted = (lane << shift) & 0xFFFF
        buf.write_byte(shifted.to_byte())
        buf.write_byte((shifted >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ShrS => {
      let shift = self.stack.pop_i32() & 15
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let lane = sign_i16(get_i16_lane(v, i))
        let shifted = (lane >> shift) & 0xFFFF
        buf.write_byte(shifted.to_byte())
        buf.write_byte((shifted >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ShrU => {
      let shift = self.stack.pop_i32() & 15
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let lane = get_i16_lane(v, i)
        let shifted = lane >> shift
        buf.write_byte(shifted.to_byte())
        buf.write_byte((shifted >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8NarrowI32x4S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let v = sat_i32_to_i16_s(get_i32_lane(a, i))
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      for i in 0..<4 {
        let v = sat_i32_to_i16_s(get_i32_lane(b, i))
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8NarrowI32x4U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let v = sat_i32_to_u16(get_i32_lane(a, i))
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      for i in 0..<4 {
        let v = sat_i32_to_u16(get_i32_lane(b, i))
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtendLowI8x16S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let b = sign_i8(v[i].to_int())
        buf.write_byte((b & 0xFF).to_byte())
        buf.write_byte(((b >> 8) & 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtendHighI8x16S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 8..<16 {
        let b = sign_i8(v[i].to_int())
        buf.write_byte((b & 0xFF).to_byte())
        buf.write_byte(((b >> 8) & 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtendLowI8x16U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        buf.write_byte(v[i])
        buf.write_byte(b'\x00')
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtendHighI8x16U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 8..<16 {
        buf.write_byte(v[i])
        buf.write_byte(b'\x00')
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtAddPairwiseI8x16S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let a = sign_i8(v[i * 2].to_int())
        let b = sign_i8(v[i * 2 + 1].to_int())
        let sum = (a + b) & 0xFFFF
        buf.write_byte(sum.to_byte())
        buf.write_byte((sum >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtAddPairwiseI8x16U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let a = v[i * 2].to_int()
        let b = v[i * 2 + 1].to_int()
        let sum = a + b
        buf.write_byte(sum.to_byte())
        buf.write_byte((sum >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtMulLowI8x16S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let va = sign_i8(a[i].to_int())
        let vb = sign_i8(b[i].to_int())
        let prod = (va * vb) & 0xFFFF
        buf.write_byte(prod.to_byte())
        buf.write_byte((prod >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtMulHighI8x16S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 8..<16 {
        let va = sign_i8(a[i].to_int())
        let vb = sign_i8(b[i].to_int())
        let prod = (va * vb) & 0xFFFF
        buf.write_byte(prod.to_byte())
        buf.write_byte((prod >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtMulLowI8x16U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let prod = a[i].to_int() * b[i].to_int()
        buf.write_byte(prod.to_byte())
        buf.write_byte((prod >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8ExtMulHighI8x16U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 8..<16 {
        let prod = a[i].to_int() * b[i].to_int()
        buf.write_byte(prod.to_byte())
        buf.write_byte((prod >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // i32x4 comparisons
    I32x4Eq => self.exec_v128_cmp_i32(fn(a, b) { a == b })
    I32x4Ne => self.exec_v128_cmp_i32(fn(a, b) { a != b })
    I32x4LtS => self.exec_v128_cmp_i32(fn(a, b) { a < b }) // i32 is already signed
    I32x4LtU =>
      self.exec_v128_cmp_i32(fn(a, b) {
        a.reinterpret_as_uint() < b.reinterpret_as_uint()
      })
    I32x4GtS => self.exec_v128_cmp_i32(fn(a, b) { a > b })
    I32x4GtU =>
      self.exec_v128_cmp_i32(fn(a, b) {
        a.reinterpret_as_uint() > b.reinterpret_as_uint()
      })
    I32x4LeS => self.exec_v128_cmp_i32(fn(a, b) { a <= b })
    I32x4LeU =>
      self.exec_v128_cmp_i32(fn(a, b) {
        a.reinterpret_as_uint() <= b.reinterpret_as_uint()
      })
    I32x4GeS => self.exec_v128_cmp_i32(fn(a, b) { a >= b })
    I32x4GeU =>
      self.exec_v128_cmp_i32(fn(a, b) {
        a.reinterpret_as_uint() >= b.reinterpret_as_uint()
      })

    // i32x4 arithmetic
    I32x4Add => self.exec_v128_binop_i32(fn(a, b) { a + b })
    I32x4Sub => self.exec_v128_binop_i32(fn(a, b) { a - b })
    I32x4Mul => self.exec_v128_binop_i32(fn(a, b) { a * b })
    I32x4MinS =>
      self.exec_v128_binop_i32(fn(a, b) { if a < b { a } else { b } })
    I32x4MinU =>
      self.exec_v128_binop_i32(fn(a, b) {
        if a.reinterpret_as_uint() < b.reinterpret_as_uint() {
          a
        } else {
          b
        }
      })
    I32x4MaxS =>
      self.exec_v128_binop_i32(fn(a, b) { if a > b { a } else { b } })
    I32x4MaxU =>
      self.exec_v128_binop_i32(fn(a, b) {
        if a.reinterpret_as_uint() > b.reinterpret_as_uint() {
          a
        } else {
          b
        }
      })
    I32x4Abs => self.exec_v128_unop_i32(fn(a) { if a < 0 { -a } else { a } })
    I32x4Neg => self.exec_v128_unop_i32(fn(a) { -a })
    I32x4AllTrue => {
      let v = self.stack.pop_v128()
      let mut all = true
      for i in 0..<4 {
        if get_i32_lane(v, i) == 0 {
          all = false
          break
        }
      }
      self.stack.push(@types.Value::I32(if all { 1 } else { 0 }))
    }
    I32x4Bitmask => {
      let v = self.stack.pop_v128()
      let mut result = 0
      for i in 0..<4 {
        if get_i32_lane(v, i) < 0 {
          result = result | (1 << i)
        }
      }
      self.stack.push(@types.Value::I32(result))
    }
    I32x4Shl => {
      let shift = self.stack.pop_i32() & 31
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let lane = get_i32_lane(v, i) << shift
        write_i32_lane(buf, lane)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ShrS => {
      let shift = self.stack.pop_i32() & 31
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let lane = get_i32_lane(v, i) >> shift
        write_i32_lane(buf, lane)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ShrU => {
      let shift = self.stack.pop_i32() & 31
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let lane = get_i32_lane(v, i).reinterpret_as_uint() >> shift
        write_i32_lane(buf, lane.reinterpret_as_int())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtendLowI16x8S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let h = sign_i16(get_i16_lane(v, i))
        write_i32_lane(buf, h)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtendHighI16x8S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 4..<8 {
        let h = sign_i16(get_i16_lane(v, i))
        write_i32_lane(buf, h)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtendLowI16x8U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        write_i32_lane(buf, get_i16_lane(v, i))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtendHighI16x8U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 4..<8 {
        write_i32_lane(buf, get_i16_lane(v, i))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtAddPairwiseI16x8S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let a = sign_i16(get_i16_lane(v, i * 2))
        let b = sign_i16(get_i16_lane(v, i * 2 + 1))
        write_i32_lane(buf, a + b)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtAddPairwiseI16x8U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let a = get_i16_lane(v, i * 2)
        let b = get_i16_lane(v, i * 2 + 1)
        write_i32_lane(buf, a + b)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtMulLowI16x8S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let va = sign_i16(get_i16_lane(a, i))
        let vb = sign_i16(get_i16_lane(b, i))
        write_i32_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtMulHighI16x8S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 4..<8 {
        let va = sign_i16(get_i16_lane(a, i))
        let vb = sign_i16(get_i16_lane(b, i))
        write_i32_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtMulLowI16x8U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        write_i32_lane(buf, get_i16_lane(a, i) * get_i16_lane(b, i))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4ExtMulHighI16x8U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 4..<8 {
        write_i32_lane(buf, get_i16_lane(a, i) * get_i16_lane(b, i))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4DotI16x8S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let a0 = sign_i16(get_i16_lane(a, i * 2))
        let a1 = sign_i16(get_i16_lane(a, i * 2 + 1))
        let b0 = sign_i16(get_i16_lane(b, i * 2))
        let b1 = sign_i16(get_i16_lane(b, i * 2 + 1))
        write_i32_lane(buf, a0 * b0 + a1 * b1)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // i64x2 comparisons
    I64x2Eq => self.exec_v128_cmp_i64(fn(a, b) { a == b })
    I64x2Ne => self.exec_v128_cmp_i64(fn(a, b) { a != b })
    I64x2LtS => self.exec_v128_cmp_i64(fn(a, b) { a < b })
    I64x2GtS => self.exec_v128_cmp_i64(fn(a, b) { a > b })
    I64x2LeS => self.exec_v128_cmp_i64(fn(a, b) { a <= b })
    I64x2GeS => self.exec_v128_cmp_i64(fn(a, b) { a >= b })

    // i64x2 arithmetic
    I64x2Add => self.exec_v128_binop_i64(fn(a, b) { a + b })
    I64x2Sub => self.exec_v128_binop_i64(fn(a, b) { a - b })
    I64x2Mul => self.exec_v128_binop_i64(fn(a, b) { a * b })
    I64x2Abs => self.exec_v128_unop_i64(fn(a) { if a < 0L { -a } else { a } })
    I64x2Neg => self.exec_v128_unop_i64(fn(a) { -a })
    I64x2AllTrue => {
      let v = self.stack.pop_v128()
      let mut all = true
      for i in 0..<2 {
        if get_i64_lane(v, i) == 0L {
          all = false
          break
        }
      }
      self.stack.push(@types.Value::I32(if all { 1 } else { 0 }))
    }
    I64x2Bitmask => {
      let v = self.stack.pop_v128()
      let mut result = 0
      for i in 0..<2 {
        if get_i64_lane(v, i) < 0L {
          result = result | (1 << i)
        }
      }
      self.stack.push(@types.Value::I32(result))
    }
    I64x2Shl => {
      let shift = self.stack.pop_i32() & 63
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let lane = get_i64_lane(v, i) << shift
        write_i64_lane(buf, lane)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ShrS => {
      let shift = self.stack.pop_i32() & 63
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let lane = get_i64_lane(v, i) >> shift
        write_i64_lane(buf, lane)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ShrU => {
      let shift = self.stack.pop_i32() & 63
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let lane = get_i64_lane(v, i).reinterpret_as_uint64() >> shift
        write_i64_lane(buf, lane.reinterpret_as_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtendLowI32x4S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        write_i64_lane(buf, get_i32_lane(v, i).to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtendHighI32x4S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 2..<4 {
        write_i64_lane(buf, get_i32_lane(v, i).to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtendLowI32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        write_i64_lane(buf, get_i32_lane(v, i).reinterpret_as_uint().to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtendHighI32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 2..<4 {
        write_i64_lane(buf, get_i32_lane(v, i).reinterpret_as_uint().to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtMulLowI32x4S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let va = get_i32_lane(a, i).to_int64()
        let vb = get_i32_lane(b, i).to_int64()
        write_i64_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtMulHighI32x4S => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 2..<4 {
        let va = get_i32_lane(a, i).to_int64()
        let vb = get_i32_lane(b, i).to_int64()
        write_i64_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtMulLowI32x4U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let va = get_i32_lane(a, i).reinterpret_as_uint().to_int64()
        let vb = get_i32_lane(b, i).reinterpret_as_uint().to_int64()
        write_i64_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2ExtMulHighI32x4U => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 2..<4 {
        let va = get_i32_lane(a, i).reinterpret_as_uint().to_int64()
        let vb = get_i32_lane(b, i).reinterpret_as_uint().to_int64()
        write_i64_lane(buf, va * vb)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // f32x4 comparisons
    F32x4Eq => self.exec_v128_cmp_f32(fn(a, b) { a == b })
    F32x4Ne => self.exec_v128_cmp_f32(fn(a, b) { a != b })
    F32x4Lt => self.exec_v128_cmp_f32(fn(a, b) { a < b })
    F32x4Gt => self.exec_v128_cmp_f32(fn(a, b) { a > b })
    F32x4Le => self.exec_v128_cmp_f32(fn(a, b) { a <= b })
    F32x4Ge => self.exec_v128_cmp_f32(fn(a, b) { a >= b })

    // f32x4 arithmetic
    F32x4Add => self.exec_v128_binop_f32(fn(a, b) { a + b })
    F32x4Sub => self.exec_v128_binop_f32(fn(a, b) { a - b })
    F32x4Mul => self.exec_v128_binop_f32(fn(a, b) { a * b })
    F32x4Div => self.exec_v128_binop_f32(fn(a, b) { a / b })
    F32x4Min => self.exec_v128_binop_f32(fn(a, b) { f32_min(a, b) })
    F32x4Max => self.exec_v128_binop_f32(fn(a, b) { f32_max(a, b) })
    F32x4Pmin =>
      self.exec_v128_binop_f32(fn(a, b) { if b < a { b } else { a } })
    F32x4Pmax =>
      self.exec_v128_binop_f32(fn(a, b) { if a < b { b } else { a } })
    F32x4Abs => self.exec_v128_unop_f32(fn(a) { a.abs() })
    F32x4Neg => self.exec_v128_unop_f32(fn(a) { -a })
    F32x4Sqrt => self.exec_v128_unop_f32(fn(a) { a.sqrt() })
    F32x4Ceil => self.exec_v128_unop_f32(f32_ceil_signed)
    F32x4Floor => self.exec_v128_unop_f32(f32_floor_signed)
    F32x4Trunc => self.exec_v128_unop_f32(f32_trunc_signed)
    F32x4Nearest => self.exec_v128_unop_f32(f32_nearest_signed)

    // f64x2 comparisons
    F64x2Eq => self.exec_v128_cmp_f64(fn(a, b) { a == b })
    F64x2Ne => self.exec_v128_cmp_f64(fn(a, b) { a != b })
    F64x2Lt => self.exec_v128_cmp_f64(fn(a, b) { a < b })
    F64x2Gt => self.exec_v128_cmp_f64(fn(a, b) { a > b })
    F64x2Le => self.exec_v128_cmp_f64(fn(a, b) { a <= b })
    F64x2Ge => self.exec_v128_cmp_f64(fn(a, b) { a >= b })

    // f64x2 arithmetic
    F64x2Add => self.exec_v128_binop_f64(fn(a, b) { a + b })
    F64x2Sub => self.exec_v128_binop_f64(fn(a, b) { a - b })
    F64x2Mul => self.exec_v128_binop_f64(fn(a, b) { a * b })
    F64x2Div => self.exec_v128_binop_f64(fn(a, b) { a / b })
    F64x2Min => self.exec_v128_binop_f64(fn(a, b) { f64_min(a, b) })
    F64x2Max => self.exec_v128_binop_f64(fn(a, b) { f64_max(a, b) })
    F64x2Pmin =>
      self.exec_v128_binop_f64(fn(a, b) { if b < a { b } else { a } })
    F64x2Pmax =>
      self.exec_v128_binop_f64(fn(a, b) { if a < b { b } else { a } })
    F64x2Abs => self.exec_v128_unop_f64(fn(a) { a.abs() })
    F64x2Neg => self.exec_v128_unop_f64(fn(a) { -a })
    F64x2Sqrt => self.exec_v128_unop_f64(fn(a) { a.sqrt() })
    F64x2Ceil => self.exec_v128_unop_f64(f64_ceil_signed)
    F64x2Floor => self.exec_v128_unop_f64(f64_floor_signed)
    F64x2Trunc => self.exec_v128_unop_f64(f64_trunc_signed)
    F64x2Nearest => self.exec_v128_unop_f64(f64_nearest_signed)

    // Conversions
    I32x4TruncSatF32x4S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let f = get_f32_lane(v, i)
        let r = trunc_sat_f32_to_i32_s(f)
        write_i32_lane(buf, r)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4TruncSatF32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let f = get_f32_lane(v, i)
        let r = trunc_sat_f32_to_u32(f)
        write_i32_lane(buf, r.reinterpret_as_int())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4ConvertI32x4S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let n = get_i32_lane(v, i)
        write_f32_lane(buf, Float::from_int(n))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4ConvertI32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let n = get_i32_lane(v, i).reinterpret_as_uint().to_int64().to_double()
        write_f32_lane(buf, Float::from_double(n))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4TruncSatF64x2SZero => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f64_lane(v, i)
        let r = trunc_sat_f64_to_i32_s(f)
        write_i32_lane(buf, r)
      }
      write_i32_lane(buf, 0)
      write_i32_lane(buf, 0)
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4TruncSatF64x2UZero => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f64_lane(v, i)
        let r = trunc_sat_f64_to_u32(f)
        write_i32_lane(buf, r.reinterpret_as_int())
      }
      write_i32_lane(buf, 0)
      write_i32_lane(buf, 0)
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2ConvertLowI32x4S => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let n = get_i32_lane(v, i)
        write_f64_lane(buf, n.to_double())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2ConvertLowI32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let n = get_i32_lane(v, i).reinterpret_as_uint().to_int64().to_double()
        write_f64_lane(buf, n)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4DemoteF64x2Zero => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f64_lane(v, i)
        write_f32_lane(buf, Float::from_double(f))
      }
      write_f32_lane(buf, 0.0)
      write_f32_lane(buf, 0.0)
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2PromoteLowF32x4 => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f32_lane(v, i)
        write_f64_lane(buf, f.to_double())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // Shuffle and Swizzle
    I8x16Shuffle(lanes) => {
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let lane = lanes[i]
        if lane < 16 {
          buf.write_byte(a[lane])
        } else {
          buf.write_byte(b[lane - 16])
        }
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16Swizzle => {
      let s = self.stack.pop_v128() // selector
      let a = self.stack.pop_v128() // source
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let idx = s[i].to_int()
        if idx < 16 {
          buf.write_byte(a[idx])
        } else {
          buf.write_byte(b'\x00')
        }
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // Memory operations
    V128Load(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 16L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        buf.write_byte(mem.load_byte(effective_addr.to_int() + i))
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Store(memidx, _align, offset) => {
      let v = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 16L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      for i in 0..<16 {
        mem.store_byte(effective_addr.to_int() + i, v[i])
      }
    }
    V128Load8Splat(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let b = mem.load_byte(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<16 {
        buf.write_byte(b)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load16Splat(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = mem.load_i32_16u(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<8 {
        buf.write_byte(v.to_byte())
        buf.write_byte((v >> 8).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load32Splat(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = mem.load_i32(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<4 {
        write_i32_lane(buf, v)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load64Splat(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = mem.load_i64(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for _ in 0..<2 {
        write_i64_lane(buf, v)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load32Zero(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = mem.load_i32(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      write_i32_lane(buf, v)
      for _ in 0..<12 {
        buf.write_byte(b'\x00')
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load64Zero(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = mem.load_i64(effective_addr.to_int())
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      write_i64_lane(buf, v)
      for _ in 0..<8 {
        buf.write_byte(b'\x00')
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load8x8S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let b = mem.load_byte(effective_addr.to_int() + i)
        let v = sign_i8(b.to_int())
        buf.write_byte((v & 0xFF).to_byte())
        buf.write_byte(((v >> 8) & 0xFF).to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load8x8U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let b = mem.load_byte(effective_addr.to_int() + i)
        buf.write_byte(b)
        buf.write_byte(b'\x00')
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load16x4S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let h = mem.load_i32_16s(effective_addr.to_int() + i * 2)
        write_i32_lane(buf, h)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load16x4U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let h = mem.load_i32_16u(effective_addr.to_int() + i * 2)
        write_i32_lane(buf, h)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load32x2S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let w = mem.load_i32(effective_addr.to_int() + i * 4)
        write_i64_lane(buf, w.to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load32x2U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let w = mem.load_i32(effective_addr.to_int() + i * 4)
        write_i64_lane(buf, w.reinterpret_as_uint().to_int64())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    V128Load8Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let b = mem.load_byte(effective_addr.to_int())
      let result = v128_replace_i8(v128, lane, b)
      self.stack.push(@types.Value::V128(result))
    }
    V128Load16Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let h = mem.load_i32_16u(effective_addr.to_int())
      let result = v128_replace_i16(v128, lane, h)
      self.stack.push(@types.Value::V128(result))
    }
    V128Load32Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let w = mem.load_i32(effective_addr.to_int())
      let result = v128_replace_i32(v128, lane, w)
      self.stack.push(@types.Value::V128(result))
    }
    V128Load64Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let d = mem.load_i64(effective_addr.to_int())
      let result = v128_replace_i64(v128, lane, d)
      self.stack.push(@types.Value::V128(result))
    }
    V128Store8Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_byte(effective_addr.to_int(), v128[lane])
    }
    V128Store16Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = get_i16_lane(v128, lane)
      mem.store_i32_16(effective_addr.to_int(), v)
    }
    V128Store32Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = get_i32_lane(v128, lane)
      mem.store_i32(effective_addr.to_int(), v)
    }
    V128Store64Lane(memidx, _align, offset, lane) => {
      let v128 = self.stack.pop_v128()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let v = get_i64_lane(v128, lane)
      mem.store_i64(effective_addr.to_int(), v)
    }

    // =========================================
    // Relaxed SIMD instructions
    // =========================================

    I8x16RelaxedSwizzle => {
      // Same as swizzle - out-of-range indices return 0 on ARM (TBL behavior)
      let s = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let idx = s[i].to_int()
        if idx < 16 {
          buf.write_byte(a[idx])
        } else {
          buf.write_byte(b'\x00')
        }
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedTruncF32x4S => {
      // Use native truncation - same as saturating for most values
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let f = get_f32_lane(v, i)
        let n = trunc_sat_f32_to_i32_s(f)
        write_i32_lane(buf, n)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedTruncF32x4U => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let f = get_f32_lane(v, i)
        let n = trunc_sat_f32_to_i32_u(f)
        write_i32_lane(buf, n)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedTruncF64x2SZero => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f64_lane(v, i)
        let n = trunc_sat_f64_to_i32_s(f)
        write_i32_lane(buf, n)
      }
      // Zero-extend: add two zero i32 lanes
      write_i32_lane(buf, 0)
      write_i32_lane(buf, 0)
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedTruncF64x2UZero => {
      let v = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let f = get_f64_lane(v, i)
        let n = trunc_sat_f64_to_i32_u(f)
        write_i32_lane(buf, n)
      }
      write_i32_lane(buf, 0)
      write_i32_lane(buf, 0)
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4RelaxedMadd => {
      // FMA: a * b + c (may or may not be fused)
      let c = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let fa = get_f32_lane(a, i)
        let fb = get_f32_lane(b, i)
        let fc = get_f32_lane(c, i)
        let result = fa * fb + fc
        write_f32_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4RelaxedNmadd => {
      // -a * b + c
      let c = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let fa = get_f32_lane(a, i)
        let fb = get_f32_lane(b, i)
        let fc = get_f32_lane(c, i)
        let result = -fa * fb + fc
        write_f32_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2RelaxedMadd => {
      let c = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let fa = get_f64_lane(a, i)
        let fb = get_f64_lane(b, i)
        let fc = get_f64_lane(c, i)
        let result = fa * fb + fc
        write_f64_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F64x2RelaxedNmadd => {
      let c = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let fa = get_f64_lane(a, i)
        let fb = get_f64_lane(b, i)
        let fc = get_f64_lane(c, i)
        let result = -fa * fb + fc
        write_f64_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I8x16RelaxedLaneselect => {
      // BSL: (a & mask) | (b & ~mask) - same as bitselect
      let mask = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<16 {
        let result = (a[i].to_int() & mask[i].to_int()) |
          (b[i].to_int() & mask[i].to_int().lnot())
        buf.write_byte(result.to_byte())
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8RelaxedLaneselect => {
      let mask = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let va = get_i16_lane(a, i)
        let vb = get_i16_lane(b, i)
        let vm = get_i16_lane(mask, i)
        let result = (va & vm) | (vb & vm.lnot())
        write_i16_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedLaneselect => {
      let mask = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let va = get_i32_lane(a, i)
        let vb = get_i32_lane(b, i)
        let vm = get_i32_lane(mask, i)
        let result = (va & vm) | (vb & vm.lnot())
        write_i32_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I64x2RelaxedLaneselect => {
      let mask = self.stack.pop_v128()
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<2 {
        let va = get_i64_lane(a, i)
        let vb = get_i64_lane(b, i)
        let vm = get_i64_lane(mask, i)
        let result = (va & vm) | (vb & vm.lnot())
        write_i64_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    F32x4RelaxedMin =>
      // Use native min (may differ in NaN handling)
      self.exec_v128_binop_f32(fn(a, b) { f32_min(a, b) })
    F32x4RelaxedMax => self.exec_v128_binop_f32(fn(a, b) { f32_max(a, b) })
    F64x2RelaxedMin => self.exec_v128_binop_f64(fn(a, b) { f64_min(a, b) })
    F64x2RelaxedMax => self.exec_v128_binop_f64(fn(a, b) { f64_max(a, b) })
    I16x8RelaxedQ15mulrS => {
      // Same as q15mulr_sat_s - SQRDMULH on ARM
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let va = sign_extend_i16(get_i16_lane(a, i))
        let vb = sign_extend_i16(get_i16_lane(b, i))
        let product = va * vb
        let result = ((product + 0x4000) >> 15) & 0xFFFF
        write_i16_lane(buf, result)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I16x8RelaxedDotI8x16I7x16S => {
      // Dot product: pairs of i8*i8 summed to i16
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<8 {
        let a0 = sign_extend_i8(a[i * 2].to_int())
        let a1 = sign_extend_i8(a[i * 2 + 1].to_int())
        let b0 = sign_extend_i8(b[i * 2].to_int())
        let b1 = sign_extend_i8(b[i * 2 + 1].to_int())
        let sum = a0 * b0 + a1 * b1
        write_i16_lane(buf, sum)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }
    I32x4RelaxedDotI8x16I7x16AddS => {
      // Dot product with accumulator: 4 pairs of i8*i8 summed + i32 acc
      let c = self.stack.pop_v128() // accumulator
      let b = self.stack.pop_v128()
      let a = self.stack.pop_v128()
      let buf : @buffer.Buffer = @buffer.new(size_hint=16)
      for i in 0..<4 {
        let mut sum = get_i32_lane(c, i)
        for j in 0..<4 {
          let idx = i * 4 + j
          let va = sign_extend_i8(a[idx].to_int())
          let vb = sign_extend_i8(b[idx].to_int())
          sum = sum + va * vb
        }
        write_i32_lane(buf, sum)
      }
      self.stack.push(@types.Value::V128(buf.contents()))
    }

    // All remaining instructions handled
    _ => abort("SIMD instruction not yet implemented: \{instr}")
  }
}

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
