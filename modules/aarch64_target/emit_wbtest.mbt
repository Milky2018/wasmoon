///|
test "AArch64 stack access encodings preserve width and scaled offset" {
  let buffer = CodeBuffer::new()
  emit_stack_access(buffer, false, I64, @vcode.PhysicalReg::new(19, Int), 16)
  emit_stack_access(buffer, true, I64, @vcode.PhysicalReg::new(20, Int), 16)
  emit_stack_access(buffer, false, I32, @vcode.PhysicalReg::new(0, Int), 12)
  emit_stack_access(buffer, true, I32, @vcode.PhysicalReg::new(1, Int), 12)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="f30b00f9f40b40f9e00f00b9e10f40b9",
  )
}

///|
test "AArch64 Spectre guard emits conditional select followed by CSDB" {
  let buffer = CodeBuffer::new()
  emit_spectre_guard(
    buffer,
    @vcode.PhysicalReg::new(0, Int),
    @vcode.PhysicalReg::new(1, Int),
    @vcode.PhysicalReg::new(2, Int),
    @vcode.PhysicalReg::new(3, Int),
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="1f0000712310829a9f2203d5",
  )
}

///|
test "AArch64 far stack accesses use IP0 and fall back to IP1 on conflict" {
  let buffer = CodeBuffer::new()
  emit_stack_access(buffer, false, I32, @vcode.PhysicalReg::new(0, Int), 17600)
  emit_stack_access(
    buffer,
    true,
    F32,
    @vcode.PhysicalReg::new(0, FpVector),
    17600,
  )
  emit_stack_access(
    buffer,
    true,
    V128,
    @vcode.PhysicalReg::new(1, FpVector),
    65536,
  )
  emit_stack_access(buffer, true, I64, stack_address_scratch(), 32768)
  emit_stack_access(buffer, false, I64, stack_address_scratch(), 32768)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="f013409110021391000200b9f013409110021391000240bdf04340910102c03d" +
      "f0234091100240f9f1234091300200f9",
  )
}

///|
test "AArch64 stack address fallback preserves SP above immediate range" {
  let buffer = CodeBuffer::new()
  emit_stack_address(buffer, stack_address_scratch(), 4095 * 4096 + 4095)
  emit_stack_address(buffer, stack_address_scratch(), 4096 * 4096)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="f0ff7f9110fe3f911020a052f063308b",
  )
}

///|
test "AArch64 stack allocation probes every guard-page interval" {
  let buffer = CodeBuffer::new()
  emit_sp_adjust(buffer, true, 8192)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="ff0740d1f00340f9ff0740d1f00340f9",
  )
}

///|
test "AArch64 unsigned i32 extension writes the register when coalesced" {
  let buffer = CodeBuffer::new()
  let register = @vcode.PhysicalReg::new(3, Int)
  emit_conversion(buffer, ExtendI32ToI64(Unsigned), register, register)
  debug_inspect(buffer.code, content="[0xe3, 0x03, 0x03, 0x2a]")
}

///|
test "AArch64 integer unary encodings place source in the correct field" {
  let source = @vcode.PhysicalReg::new(3, Int)
  let destination = @vcode.PhysicalReg::new(5, Int)
  let buffer = CodeBuffer::new()
  buffer.emit_word(encode_int_unary(W32, Mvn, destination, source))
  buffer.emit_word(encode_int_unary(W64, Mvn, destination, source))
  buffer.emit_word(encode_int_unary(W32, Clz, destination, source))
  buffer.emit_word(encode_int_unary(W64, Clz, destination, source))
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="e503232ae50323aa6510c05a6510c0da",
  )
}

///|
test "AArch64 immediate shift encodings cover both widths and boundaries" {
  let source = @vcode.PhysicalReg::new(3, Int)
  let destination = @vcode.PhysicalReg::new(5, Int)
  debug_inspect(
    [
      encode_shift_immediate(W32, Lsl, 0, destination, source),
      encode_shift_immediate(W32, Lsl, 31, destination, source),
      encode_shift_immediate(W32, Lsr, 0, destination, source),
      encode_shift_immediate(W32, Lsr, 31, destination, source),
      encode_shift_immediate(W32, Asr, 0, destination, source),
      encode_shift_immediate(W32, Asr, 31, destination, source),
      encode_shift_immediate(W32, Ror, 0, destination, source),
      encode_shift_immediate(W32, Ror, 31, destination, source),
      encode_shift_immediate(W64, Lsl, 0, destination, source),
      encode_shift_immediate(W64, Lsl, 63, destination, source),
      encode_shift_immediate(W64, Lsr, 0, destination, source),
      encode_shift_immediate(W64, Lsr, 63, destination, source),
      encode_shift_immediate(W64, Asr, 0, destination, source),
      encode_shift_immediate(W64, Asr, 63, destination, source),
      encode_shift_immediate(W64, Ror, 0, destination, source),
      encode_shift_immediate(W64, Ror, 63, destination, source),
      encode_add_shifted_left(
        W32,
        31,
        destination,
        source,
        @vcode.PhysicalReg::new(4, Int),
      ),
      encode_add_shifted_left(
        W64,
        63,
        destination,
        source,
        @vcode.PhysicalReg::new(4, Int),
      ),
    ],
    content=(
      #|[
      #|  1392540773,
      #|  1392574565,
      #|  1392540773,
      #|  1394572389,
      #|  318798949,
      #|  320830565,
      #|  327352421,
      #|  327384165,
      #|  3544251493,
      #|  3544252517,
      #|  3544251493,
      #|  3548380261,
      #|  2470509669,
      #|  2474638437,
      #|  2479030373,
      #|  2479094885,
      #|  184843365,
      #|  2332359781,
      #|]
    ),
  )
}

///|
test "AArch64 overflow arithmetic encodes every width and signedness" {
  let buffer = CodeBuffer::new()
  let operations : Array[@lowering.IntOverflowOp] = [
    Add(Signed),
    Add(Unsigned),
    Sub(Signed),
    Sub(Unsigned),
    Mul(Signed),
    Mul(Unsigned),
  ]
  for width in [GprWidth::W32, W64] {
    for operation in operations {
      emit_int_with_overflow(
        buffer,
        width,
        operation,
        @vcode.PhysicalReg::new(0, Int),
        @vcode.PhysicalReg::new(1, Int),
        @vcode.PhysicalReg::new(2, Int),
        @vcode.PhysicalReg::new(3, Int),
      )
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="0200012be3779f9a0200012be3379f9a0200016be3779f9a0200016be3279f9a" +
      "107c219b027e40931f0202ebe3079f9a107ca19be203102a1f0202ebe3079f9a" +
      "020001abe3779f9a020001abe3379f9a020001ebe3779f9a020001ebe3279f9a" +
      "027c019b107c419b1ffe82ebe3079f9a027c019b107cc19b1f0200f1e3079f9a",
  )
}

///|
test "AArch64 vector foundation encodings preserve lanes and aliases" {
  let buffer = CodeBuffer::new()
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  let vector0 = @vcode.PhysicalReg::new(0, FpVector)
  let vector1 = @vcode.PhysicalReg::new(1, FpVector)
  let vector2 = @vcode.PhysicalReg::new(2, FpVector)
  let vector3 = @vcode.PhysicalReg::new(3, FpVector)
  emit_vector_constant(buffer, vector3, 0UL, 0UL)
  emit_vector_constant(
    buffer, vector3, 0x0706050403020100UL, 0x0F0E0D0C0B0A0908UL,
  )
  let integer_lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in integer_lanes {
    emit_vector_splat(buffer, lane, int0, vector1)
  }
  let float_lanes : Array[@lowering.VectorLane] = [F32x4, F64x2]
  for lane in float_lanes {
    emit_vector_splat(buffer, lane, vector0, vector1)
  }
  emit_vector_bitwise(buffer, Not, vector0, vector0, vector0, vector3)
  emit_vector_bitwise(buffer, And, vector0, vector1, vector1, vector3)
  emit_vector_bitwise(buffer, Or, vector0, vector1, vector1, vector3)
  emit_vector_bitwise(buffer, Xor, vector0, vector1, vector1, vector3)
  emit_vector_bitwise(buffer, AndNot, vector0, vector1, vector1, vector3)
  emit_vector_bitwise(buffer, BitSelect, vector0, vector1, vector2, vector2)
  emit_vector_bitwise(buffer, BitSelect, vector0, vector1, vector2, vector1)
  emit_vector_bitwise(buffer, BitSelect, vector0, vector1, vector2, vector3)
  emit_vector_select(buffer, int0, vector1, vector2, vector1)
  emit_vector_select(buffer, int1, vector1, vector2, vector2)
  emit_vector_select(buffer, int0, vector1, vector2, vector3)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="03e4006f03e4006f102080d25060a0f290a0c0f2d0e0e0f2031e084e102181d2" +
      "5061a1f290a1c1f2d0e1e1f2031e184e010c014e010c024e010c044e010c084e" +
      "0104044e0104084e0358206e031c214e031ca14e031c216e031c614e021c616e" +
      "011c216e211c624e211c206e031c216e631c224e631c216e211ca14e40000035" +
      "411ca24e421ca24e41000034221ca14e431ca24e40000034231ca14e",
  )
}

///|
test "AArch64 vector lane movement encodings preserve lane kind and index" {
  let buffer = CodeBuffer::new()
  let vector3 = @vcode.PhysicalReg::new(3, FpVector)
  let vector6 = @vcode.PhysicalReg::new(6, FpVector)
  let int5 = @vcode.PhysicalReg::new(5, Int)
  let int7 = @vcode.PhysicalReg::new(7, Int)
  let vector7 = @vcode.PhysicalReg::new(7, FpVector)
  let vector9 = @vcode.PhysicalReg::new(9, FpVector)
  emit_vector_extract_lane(buffer, I8x16, 15, Some(Signed), vector3, int7)
  emit_vector_extract_lane(buffer, I8x16, 15, Some(Unsigned), vector3, int7)
  emit_vector_extract_lane(buffer, I16x8, 7, Some(Signed), vector3, int7)
  emit_vector_extract_lane(buffer, I16x8, 7, Some(Unsigned), vector3, int7)
  emit_vector_extract_lane(buffer, I32x4, 3, None, vector3, int7)
  emit_vector_extract_lane(buffer, I64x2, 1, None, vector3, int7)
  emit_vector_extract_lane(buffer, F32x4, 2, None, vector3, vector7)
  emit_vector_extract_lane(buffer, F64x2, 1, None, vector3, vector7)
  emit_vector_replace_lane(buffer, I8x16, 15, int5, vector9)
  emit_vector_replace_lane(buffer, I16x8, 7, int5, vector9)
  emit_vector_replace_lane(buffer, I32x4, 3, int5, vector9)
  emit_vector_replace_lane(buffer, I64x2, 1, int5, vector9)
  emit_vector_replace_lane(buffer, F32x4, 2, vector6, vector9)
  emit_vector_replace_lane(buffer, F64x2, 1, vector6, vector9)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="672c1f0e673c1f0e672c1e0e673c1e0e673c1c0e673c184e6704145e6704185e" +
      "a91c1f4ea91c1e4ea91c1c4ea91c184ec904146ec904186e",
  )
}

///|
test "AArch64 vector permutation encodings use table lookup" {
  let buffer = CodeBuffer::new()
  let vector0 = @vcode.PhysicalReg::new(0, FpVector)
  let vector1 = @vcode.PhysicalReg::new(1, FpVector)
  let vector2 = @vcode.PhysicalReg::new(2, FpVector)
  emit_vector_table_lookup(buffer, vector0, vector1, vector2)
  let mask : FixedArray[Int32] = [
    0, 17, 2, 19, 4, 21, 6, 23, 8, 25, 10, 27, 12, 29, 14, 31,
  ]
  emit_vector_shuffle(buffer, mask, vector0, vector1, vector2)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="0200014e10e4006f100090d25000b0f29000d0f2d000f0f2101e084e100190d2" +
      "5001b0f29001d0f2d001f0f2101e184e1000104e11e4006f103080d21070a0f2" +
      "10b0c0f210f0e0f2111e084e103081d21070a1f210b0c1f210f0e1f2111e184e" +
      "3100114e021eb14e",
  )
}

///|
test "AArch64 basic vector integer encodings preserve every lane width" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    emit_vector_int_unary(buffer, lane, Absolute, left, destination)
    emit_vector_int_unary(buffer, lane, Negate, left, destination)
    emit_vector_int_binary(buffer, lane, Add, left, right, destination)
    emit_vector_int_binary(buffer, lane, Sub, left, right, destination)
    emit_vector_int_binary(buffer, lane, Mul, left, right, destination)
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="67b8204e67b8206e6784254e6784256e679c254e67b8604e67b8606e6784654e" +
      "6784656e679c654e67b8a04e67b8a06e6784a54e6784a56e679ca54e67b8e04e" +
      "67b8e06e6784e54e6784e56e701ca34eb11ca54e103e084e313e084e107e119b" +
      "071e084e103e184e313e184e107e119b071e184e",
  )
}

///|
test "AArch64 vector integer shift encodings preserve width and signedness" {
  let buffer = CodeBuffer::new()
  let vector3 = @vcode.PhysicalReg::new(3, FpVector)
  let int5 = @vcode.PhysicalReg::new(5, Int)
  let vector7 = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    emit_vector_int_shift(buffer, lane, Left, vector3, int5, vector7)
    emit_vector_int_shift(buffer, lane, Right(Signed), vector3, int5, vector7)
    emit_vector_int_shift(buffer, lane, Right(Unsigned), vector3, int5, vector7)
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="b00840d3100e014e6744304eb00840d3f00310cb100e014e6744304eb00840d3" +
      "f00310cb100e014e6744306eb00c40d3100e024e6744704eb00c40d3f00310cb" +
      "100e024e6744704eb00c40d3f00310cb100e024e6744706eb01040d3100e044e" +
      "6744b04eb01040d3f00310cb100e044e6744b04eb01040d3f00310cb100e044e" +
      "6744b06eb01440d3100e084e6744f04eb01440d3f00310cb100e084e6744f04e" +
      "b01440d3f00310cb100e084e6744f06e",
  )
}

///|
test "AArch64 vector integer comparison encodings cover the full relation matrix" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let comparisons : Array[@lowering.VectorIntComparison] = [
    Equal,
    NotEqual,
    LessThan(Signed),
    LessThan(Unsigned),
    LessOrEqual(Signed),
    LessOrEqual(Unsigned),
    GreaterThan(Signed),
    GreaterThan(Unsigned),
    GreaterOrEqual(Signed),
    GreaterOrEqual(Unsigned),
  ]
  for lane in lanes {
    for comparison in comparisons {
      emit_vector_int_compare(
        buffer, lane, comparison, left, right, destination,
      )
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="678c256e678c256ee758206ea734234ea734236ea73c234ea73c236e6734254e" +
      "6734256e673c254e673c256e678c656e678c656ee758206ea734634ea734636e" +
      "a73c634ea73c636e6734654e6734656e673c654e673c656e678ca56e678ca56e" +
      "e758206ea734a34ea734a36ea73ca34ea73ca36e6734a54e6734a56e673ca54e" +
      "673ca56e678ce56e678ce56ee758206ea734e34ea734e36ea73ce34ea73ce36e" +
      "6734e54e6734e56e673ce54e673ce56e",
  )
}

///|
test "AArch64 saturating vector arithmetic encodings cover every lane width" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let operations : Array[AArch64VectorIntBinary] = [
    SaturatingAdd(Signed),
    SaturatingAdd(Unsigned),
    SaturatingSub(Signed),
    SaturatingSub(Unsigned),
  ]
  for lane in lanes {
    for operation in operations {
      emit_vector_int_binary(buffer, lane, operation, left, right, destination)
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="670c254e670c256e672c254e672c256e670c654e670c656e672c654e672c656e" +
      "670ca54e670ca56e672ca54e672ca56e670ce54e670ce56e672ce54e672ce56e",
  )
}

///|
test "AArch64 vector integer min and max cover direct and legalized lanes" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  let operations : Array[AArch64VectorIntBinary] = [
    Min(Signed),
    Min(Unsigned),
    Max(Signed),
    Max(Unsigned),
  ]
  for lane in lanes {
    for operation in operations {
      emit_vector_int_binary(buffer, lane, operation, left, right, destination)
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="676c254e676c256e6764254e6764256e676c654e676c656e6764654e6764656e" +
      "676ca54e676ca56e6764a54e6764a56e7034e54ea71c236ee71c304ee71c236e" +
      "7034e56ea71c236ee71c304ee71c236e7034e54e671c256ee71c304ee71c256e" +
      "7034e56e671c256ee71c304ee71c256e",
  )
}

///|
test "AArch64 vector unsigned average uses URHADD for legal lanes" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  emit_vector_int_binary(
    buffer,
    I8x16,
    AverageUnsigned,
    left,
    right,
    destination,
  )
  emit_vector_int_binary(
    buffer,
    I16x8,
    AverageUnsigned,
    left,
    right,
    destination,
  )
  debug_inspect(
    buffer.code,
    content="[0x67, 0x14, 0x25, 0x6e, 0x67, 0x14, 0x65, 0x6e]",
  )
}

///|
test "AArch64 vector byte population count uses CNT" {
  let buffer = CodeBuffer::new()
  let source = @vcode.PhysicalReg::new(3, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  emit_vector_int_unary(buffer, I8x16, PopulationCount, source, destination)
  debug_inspect(buffer.code, content="[0x67, 0x58, 0x20, 0x4e]")
}

///|
test "AArch64 widening vector integer encodings cover every legal form" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I16x8, I32x4, I64x2]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for signedness in signednesses {
      emit_vector_int_unary(
        buffer,
        lane,
        ExtendAddPairwise(signedness),
        left,
        destination,
      )
    }
  }
  let halves : Array[@lowering.VectorHalf] = [Low, High]
  for lane in lanes {
    for half in halves {
      for signedness in signednesses {
        emit_vector_int_binary(
          buffer,
          lane,
          ExtendMultiply(half, signedness),
          left,
          right,
          destination,
        )
      }
    }
  }
  emit_vector_int_binary(
    buffer,
    I32x4,
    Dot16To32Signed,
    left,
    right,
    destination,
  )
  emit_vector_int_binary(
    buffer,
    I16x8,
    Q15MultiplyRoundedSaturating,
    left,
    right,
    destination,
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="6728204e6728206e6728604e6728606e6728a04e6728a06e67c0250e67c0252e" +
      "67c0254e67c0256e67c0650e67c0652e67c0654e67c0656e67c0a50e67c0a52e" +
      "67c0a54e67c0a56e70c0650e71c0654e07beb14e67b4656e",
  )
}

///|
test "AArch64 vector integer extension encodings cover every legal form" {
  let buffer = CodeBuffer::new()
  let source = @vcode.PhysicalReg::new(3, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I16x8, I32x4, I64x2]
  let halves : Array[@lowering.VectorHalf] = [Low, High]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for half in halves {
      for signedness in signednesses {
        emit_vector_extension(
          buffer,
          lane,
          half is High,
          signedness,
          source,
          destination,
        )
      }
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="67a4080f67a4082f67a4084f67a4086f67a4100f67a4102f67a4104f67a4106f" +
      "67a4200f67a4202f67a4204f67a4206f",
  )
}

///|
test "AArch64 saturating vector narrowing handles every form and alias" {
  let buffer = CodeBuffer::new()
  let low = @vcode.PhysicalReg::new(3, FpVector)
  let high = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8]
  let signednesses : Array[@native.Signedness] = [Signed, Unsigned]
  for lane in lanes {
    for signedness in signednesses {
      emit_vector_narrow(buffer, lane, signedness, low, high, destination)
    }
  }
  emit_vector_narrow(buffer, I8x16, Signed, low, high, high)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="6748210ea748214e6728212ea728216e6748610ea748614e6728612ea728616e" +
      "b01ca54e6548210e054a214e",
  )
}

///|
test "AArch64 vector truth predicate encodings cover every lane" {
  let buffer = CodeBuffer::new()
  let source = @vcode.PhysicalReg::new(3, FpVector)
  let destination = @vcode.PhysicalReg::new(7, Int)
  emit_vector_predicate(buffer, AnyTrue, source, destination)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    emit_vector_predicate(buffer, AllTrue(lane), source, destination)
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="70a8306e1002669e1f0200f1e7079f9a70a8316e1002669e1f0200f1e7079f9a" +
      "70a8716e1002669e1f0200f1e7079f9a70a8b16e1002669e1f0200f1e7079f9a" +
      "703c084e713c184e1f0200f1241a40fae7079f9a",
  )
}

///|
test "AArch64 vector integer bitmask encodings cover every lane" {
  let buffer = CodeBuffer::new()
  let source = @vcode.PhysicalReg::new(3, FpVector)
  let destination = @vcode.PhysicalReg::new(7, Int)
  let lanes : Array[@lowering.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    emit_vector_bitmask(buffer, lane, source, destination)
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="7104096f304080d29000a1f21002c4f21008f0f21002679e1006084e319e304e" +
      "312a206e312a606e312aa06e303e084e313e184e0722112a673c020ee77c0f53" +
      "703c060e107e0f53e704102a703c0a0e107e0f53e708102a703c0e0e107e0f53" +
      "e70c102a703c120e107e0f53e710102a703c160e107e0f53e714102a703c1a0e" +
      "107e0f53e718102a703c1e0e107e0f53e71c102a673c040ee77c1f53703c0c0e" +
      "107e1f53e704102a703c140e107e1f53e708102a703c1c0e107e1f53e70c102a" +
      "673c084ee7fc7fd3703c184e10fe7fd3e704102a",
  )
}

///|
test "AArch64 vector float encodings cover every non-fused operation" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let unary_operations : Array[@lowering.VectorFloatUnaryOp] = [
    Absolute,
    Negate,
    SquareRoot,
    Ceil,
    Floor,
    Truncate,
    Nearest,
  ]
  let binary_operations : Array[@lowering.VectorFloatBinaryOp] = [
    Add,
    Sub,
    Mul,
    Div,
    Min,
    Max,
    PseudoMin,
    PseudoMax,
  ]
  let comparisons : Array[@lowering.VectorFloatComparison] = [
    Equal,
    NotEqual,
    LessThan,
    LessOrEqual,
    GreaterThan,
    GreaterOrEqual,
  ]
  let lanes : Array[@lowering.VectorLane] = [F32x4, F64x2]
  for lane in lanes {
    for operation in unary_operations {
      emit_vector_float_unary(buffer, lane, operation, left, destination)
    }
    for operation in binary_operations {
      emit_vector_float_binary(
        buffer, lane, operation, left, right, destination,
      )
    }
    for comparison in comparisons {
      emit_vector_float_compare(
        buffer, lane, comparison, left, right, destination,
      )
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="67f8a04e67f8a06e67f8a16e6788a14e6798214e6798a14e6788214e67d4254e" +
      "67d4a54e67dc256e67fc256e67f4a54e67f4254e70e4a56eb01c636e071eb04e" +
      "b0e4a36eb01c636e071eb04e67e4254e67e4254ee758206ea7e4a36ea7e4236e" +
      "67e4a56e67e4256e67f8e04e67f8e06e67f8e16e6788e14e6798614e6798e14e" +
      "6788614e67d4654e67d4e54e67dc656e67fc656e67f4e54e67f4654e70e4e56e" +
      "b01c636e071eb04eb0e4e36eb01c636e071eb04e67e4654e67e4654ee758206e" +
      "a7e4e36ea7e4636e67e4e56e67e4656e",
  )
}

///|
test "AArch64 vector fused encodings cover both lanes and every sign form" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let addend = @vcode.PhysicalReg::new(7, FpVector)
  let destination = @vcode.PhysicalReg::new(9, FpVector)
  let operations : Array[@lowering.FloatTernaryOp] = [
    FusedMultiplyAdd,
    FusedNegatedMultiplyAdd,
    FusedMultiplySubtract,
    FusedNegatedMultiplySubtract,
  ]
  let lanes : Array[@lowering.VectorLane] = [F32x4, F64x2]
  for lane in lanes {
    for operation in operations {
      emit_vector_float_ternary(
        buffer, lane, operation, left, right, addend, destination,
      )
    }
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="701ca34eb11ca54ee91ca74e09ce314e701ca34eb11ca54ee91ca74e09ceb14e" +
      "701ca34eb11ca54ee91ca74e29f9a06e09ce314e701ca34eb11ca54ee91ca74e" +
      "29f9a06e09ceb14e701ca34eb11ca54ee91ca74e09ce714e701ca34eb11ca54e" +
      "e91ca74e09cef14e701ca34eb11ca54ee91ca74e29f9e06e09ce714e701ca34e" +
      "b11ca54ee91ca74e29f9e06e09cef14e",
  )
}

///|
test "AArch64 vector numeric conversion encodings cover every form" {
  let buffer = CodeBuffer::new()
  let source = @vcode.PhysicalReg::new(3, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let conversions : Array[AArch64VectorConversion] = [
    FloatToInt(F32x4, Signed),
    FloatToInt(F32x4, Unsigned),
    FloatToInt(F64x2, Signed),
    FloatToInt(F64x2, Unsigned),
    IntToFloat(F32x4, Signed),
    IntToFloat(F32x4, Unsigned),
    IntToFloat(F64x2, Signed),
    IntToFloat(F64x2, Unsigned),
    PromoteLowF32x4,
    DemoteZeroF64x2,
  ]
  for conversion in conversions {
    emit_vector_conversion(buffer, conversion, source, destination)
  }
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="67b8a14e67b8a16e70b8e14e074aa10e70b8e16e074aa12e67d8214e67d8216e" +
      "70a4200f07da614e70a4202f07da616e6778610e6768610e",
  )
}

///|
test "AArch64 relaxed dot8-to16 uses baseline NEON" {
  let buffer = CodeBuffer::new()
  emit_vector_relaxed_dot8_to16(
    buffer,
    @vcode.PhysicalReg::new(3, FpVector),
    @vcode.PhysicalReg::new(5, FpVector),
    @vcode.PhysicalReg::new(7, FpVector),
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="701ca34eb11ca54e07c2310e10c2314ee7bc704e",
  )
}

///|
test "AArch64 vector memory encodings cover every lane arrangement" {
  let address = @vcode.PhysicalReg::new(3, Int)
  let vector = @vcode.PhysicalReg::new(5, FpVector)
  debug_inspect(
    (
      [
        vector_splat_load_base(I8x16),
        vector_splat_load_base(I16x8),
        vector_splat_load_base(I32x4),
        vector_splat_load_base(I64x2),
        vector_splat_load_base(F32x4),
        vector_splat_load_base(F64x2),
      ],
      [
        vector_lane_memory_word(true, I8x16, 15, address, vector),
        vector_lane_memory_word(true, I16x8, 7, address, vector),
        vector_lane_memory_word(true, I32x4, 3, address, vector),
        vector_lane_memory_word(true, I64x2, 1, address, vector),
        vector_lane_memory_word(true, F32x4, 3, address, vector),
        vector_lane_memory_word(true, F64x2, 1, address, vector),
      ],
      [
        vector_lane_memory_word(false, I8x16, 15, address, vector),
        vector_lane_memory_word(false, I16x8, 7, address, vector),
        vector_lane_memory_word(false, I32x4, 3, address, vector),
        vector_lane_memory_word(false, I64x2, 1, address, vector),
        vector_lane_memory_word(false, F32x4, 3, address, vector),
        vector_lane_memory_word(false, F64x2, 1, address, vector),
      ],
    ),
    content=(
      #|(
      #|  [
      #|    1296089088,
      #|    1296090112,
      #|    1296091136,
      #|    1296092160,
      #|    1296091136,
      #|    1296092160,
      #|  ],
      #|  [
      #|    1296047205,
      #|    1296062565,
      #|    1296076901,
      #|    1296073829,
      #|    1296076901,
      #|    1296073829,
      #|  ],
      #|  [
      #|    1291852901,
      #|    1291868261,
      #|    1291882597,
      #|    1291879525,
      #|    1291882597,
      #|    1291879525,
      #|  ],
      #|)
    ),
  )
}

///|
test "AArch64 atomic encodings cover widths, RMW operations, and compare-exchange" {
  let address = @vcode.PhysicalReg::new(3, Int)
  let value = @vcode.PhysicalReg::new(5, Int)
  let result = @vcode.PhysicalReg::new(7, Int)
  let rmw_code : Array[Array[Byte]] = []
  let rmw_operations : Array[@lowering.AtomicRmwOp] = [
    Add,
    Sub,
    And,
    Or,
    Xor,
    Exchange,
  ]
  for operation in rmw_operations {
    let buffer = CodeBuffer::new()
    emit_atomic_rmw(buffer, W32, operation, address, value, result) |> ignore
    rmw_code.push(buffer.code)
  }
  let compare_exchange_code : Array[Array[Byte]] = []
  let widths : Array[@native.AccessWidth] = [W8, W16, W32, W64]
  for width in widths {
    let buffer = CodeBuffer::new()
    emit_atomic_compare_exchange(
      buffer,
      width,
      address,
      value,
      @vcode.PhysicalReg::new(6, Int),
      result,
    )
    |> ignore
    compare_exchange_code.push(buffer.code)
  }
  debug_inspect(
    (
      [
        atomic_load_base(W8, false),
        atomic_load_base(W16, false),
        atomic_load_base(W32, false),
        atomic_load_base(W64, false),
        atomic_store_base(W8, false),
        atomic_store_base(W16, false),
        atomic_store_base(W32, false),
        atomic_store_base(W64, false),
      ],
      rmw_code,
      compare_exchange_code,
    ),
    content=(
      #|(
      #|  [
      #|    148896768,
      #|    1222638592,
      #|    2296380416,
      #|    3370122240,
      #|    144702464,
      #|    1218444288,
      #|    2292186112,
      #|    3365927936,
      #|  ],
      #|  [
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x00,
      #|      0x05,
      #|      0x0b,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x00,
      #|      0x05,
      #|      0x4b,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x00,
      #|      0x05,
      #|      0x0a,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x00,
      #|      0x05,
      #|      0x2a,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x00,
      #|      0x05,
      #|      0x4a,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xf0,
      #|      0x03,
      #|      0x05,
      #|      0x2a,
      #|      0x70,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0xb1,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|  ],
      #|  [
      #|    [
      #|      0xb0,
      #|      0x1c,
      #|      0x00,
      #|      0x53,
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x08,
      #|      0xff,
      #|      0x00,
      #|      0x10,
      #|      0x6b,
      #|      0x60,
      #|      0x00,
      #|      0x00,
      #|      0x54,
      #|      0x5f,
      #|      0x3f,
      #|      0x03,
      #|      0xd5,
      #|      0x03,
      #|      0x00,
      #|      0x00,
      #|      0x14,
      #|      0x66,
      #|      0xfc,
      #|      0x11,
      #|      0x08,
      #|      0x51,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0xb0,
      #|      0x3c,
      #|      0x00,
      #|      0x53,
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x48,
      #|      0xff,
      #|      0x00,
      #|      0x10,
      #|      0x6b,
      #|      0x60,
      #|      0x00,
      #|      0x00,
      #|      0x54,
      #|      0x5f,
      #|      0x3f,
      #|      0x03,
      #|      0xd5,
      #|      0x03,
      #|      0x00,
      #|      0x00,
      #|      0x14,
      #|      0x66,
      #|      0xfc,
      #|      0x11,
      #|      0x48,
      #|      0x51,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0x88,
      #|      0xff,
      #|      0x00,
      #|      0x05,
      #|      0x6b,
      #|      0x60,
      #|      0x00,
      #|      0x00,
      #|      0x54,
      #|      0x5f,
      #|      0x3f,
      #|      0x03,
      #|      0xd5,
      #|      0x03,
      #|      0x00,
      #|      0x00,
      #|      0x14,
      #|      0x66,
      #|      0xfc,
      #|      0x11,
      #|      0x88,
      #|      0x51,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|    [
      #|      0x67,
      #|      0xfc,
      #|      0x5f,
      #|      0xc8,
      #|      0xff,
      #|      0x00,
      #|      0x05,
      #|      0xeb,
      #|      0x60,
      #|      0x00,
      #|      0x00,
      #|      0x54,
      #|      0x5f,
      #|      0x3f,
      #|      0x03,
      #|      0xd5,
      #|      0x03,
      #|      0x00,
      #|      0x00,
      #|      0x14,
      #|      0x66,
      #|      0xfc,
      #|      0x11,
      #|      0xc8,
      #|      0x51,
      #|      0xff,
      #|      0xff,
      #|      0x35,
      #|    ],
      #|  ],
      #|)
    ),
  )
}

///|
test "AAPCS64 platform call layout preserves mixed overflow order" {
  let layout = platform_call_layout([
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    I64,
    V128,
    I32,
    F32,
  ])
  debug_inspect(
    (layout.arguments.to_owned(), layout.stack_size),
    content=(
      #|(
      #|  [
      #|    CallRegister(p0:int),
      #|    CallRegister(p1:int),
      #|    CallRegister(p2:int),
      #|    CallRegister(p3:int),
      #|    CallRegister(p4:int),
      #|    CallRegister(p5:int),
      #|    CallRegister(p6:int),
      #|    CallRegister(p7:int),
      #|    CallRegister(p0:fpvec),
      #|    CallRegister(p1:fpvec),
      #|    CallRegister(p2:fpvec),
      #|    CallRegister(p3:fpvec),
      #|    CallRegister(p4:fpvec),
      #|    CallRegister(p5:fpvec),
      #|    CallRegister(p6:fpvec),
      #|    CallRegister(p7:fpvec),
      #|    CallStack(0),
      #|    CallStack(16),
      #|    CallStack(32),
      #|    CallStack(40),
      #|  ],
      #|  48,
      #|)
    ),
  )
}

///|
test "validated internal ABI derives context, overflow, and result locations" {
  let abi = InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let layout = abi.call_layout(
    @native.Signature::new(
      [
        Ptr64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        V128,
      ],
      [I64, F64],
    ),
  )
  let results = abi.result_layout([I64, F64])
  debug_inspect(
    (
      layout.arguments.to_owned(),
      layout.stack_size,
      (results.0.to_owned(), results.1),
    ),
    content=(
      #|(
      #|  [
      #|    CallRegister(p0:int),
      #|    CallRegister(p1:int),
      #|    CallRegister(p2:int),
      #|    CallRegister(p3:int),
      #|    CallRegister(p4:int),
      #|    CallRegister(p5:int),
      #|    CallRegister(p6:int),
      #|    CallRegister(p7:int),
      #|    CallStack(0),
      #|    CallRegister(p0:fpvec),
      #|    CallRegister(p1:fpvec),
      #|    CallRegister(p2:fpvec),
      #|    CallRegister(p3:fpvec),
      #|    CallRegister(p4:fpvec),
      #|    CallRegister(p5:fpvec),
      #|    CallRegister(p6:fpvec),
      #|    CallRegister(p7:fpvec),
      #|    CallStack(16),
      #|  ],
      #|  32,
      #|  ([CallResultRegister(p0:int), CallResultRegister(p0:fpvec)], 0),
      #|)
    ),
  )
}

///|
test "aarch64 vector and-not remains one BIC with overlapping outputs" {
  let first = @vcode.PhysicalReg::new(0, FpVector)
  let second = @vcode.PhysicalReg::new(1, FpVector)
  for destination in 0..<3 {
    let buffer = CodeBuffer::new()
    emit_vector_bitwise(
      buffer,
      AndNot,
      first,
      second,
      second,
      @vcode.PhysicalReg::new(destination, FpVector),
    )
    // bic vD.16b, v0.16b, v1.16b.
    inspect(
      buffer.code == [destination.to_byte(), 0x1c, 0x61, 0x4e],
      content="true",
    )
  }
}

///|
test "AArch64 constants choose shorter inverted and logical forms" {
  let cases : Array[(GprWidth, UInt64, Array[UInt32])] = [
    (W64, 0xffffffffffffffffUL, [0x92e00000U]),
    (W32, 0xffffffc0UL, [0x128007e0U]),
    (W64, 0x00ff00ff00ff00ffUL, [0xb2009fe0U]),
    (W32, 0x00ff00ffUL, [0x32009fe0U]),
    (W64, 0xffff1234ffff5678UL, [0x929530e0U, 0xf2c24680U]),
    (W64, 0UL, [0x52a00000U]),
    (W32, 0UL, [0x52a00000U]),
    (W64, 0x1234UL, [0x52824680U]),
    (W64, 0xffff1234UL, [0x129db960U]),
    (W64, 0x00ff00ffUL, [0x32009fe0U]),
    (W64, 0xffffffc0UL, [0x128007e0U]),
    (W64, 0x12345678UL, [0x528acf00U, 0x72a24680U]),
    (W64, 0xffffffffUL, [0x12a00000U]),
    (W64, 0x100000000UL, [0xd2c00020U]),
    (W64, 0xffffffffffff1234UL, [0x929db960U]),
  ]
  for (width, bits, expected) in cases {
    let buffer = CodeBuffer::new()
    emit_constant(buffer, width, @vcode.PhysicalReg::new(0, Int), bits)
    let words = Array::makei(buffer.code.length() / 4, fn(i) {
      let offset = i * 4
      buffer.code[offset].to_uint() |
      (buffer.code[offset + 1].to_uint() << 8) |
      (buffer.code[offset + 2].to_uint() << 16) |
      (buffer.code[offset + 3].to_uint() << 24)
    })
    inspect(words == expected, content="true")
  }
}

///|
test "aarch64_target internal leaf functions establish an unwindable frame record" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_protocol(
    "leaf_frame",
    Internal,
    [Ptr64],
    [],
  )
  builder.set_terminator(
    builder.entry_block(),
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_vcode(function)
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  assert_eq(frame.frame_size(), 16)
  let object = emit(function, allocation, frame)
  let expected : Array[@code_object.UnwindDirective] = [
    @code_object.UnwindDirective::new(4, StackAlloc(size=16)),
    @code_object.UnwindDirective::new(4, SaveRegister(Int, 29, cfa_offset=-16)),
    @code_object.UnwindDirective::new(4, SaveRegister(Int, 30, cfa_offset=-8)),
    @code_object.UnwindDirective::new(
      8,
      SetFramePointer(Int, 29, cfa_offset=16),
    ),
  ]
  assert_eq(object.unwind(), expected)
  let code = object.code()
  assert_eq(
    code[0:4].to_owned(),
    [0xFDU, 0x7BU, 0xBFU, 0xA9U].map(x => x.to_byte()),
  )
  assert_eq(
    code[8:12].to_owned(),
    [0xFDU, 0x7BU, 0xC1U, 0xA8U].map(x => x.to_byte()),
  )
  assert_eq(code.length(), 16)
}

///|
test "AArch64 LSE atomic add encodes each access width and retains its trap offset" {
  let address = @vcode.PhysicalReg::new(3, Int)
  let value = @vcode.PhysicalReg::new(1, Int)
  let result = @vcode.PhysicalReg::new(2, Int)
  let forms : Array[(@native.AccessWidth, Byte)] = [
    (W8, 0x38),
    (W16, 0x78),
    (W32, 0xb8),
    (W64, 0xf8),
  ]
  for form in forms {
    let (width, opcode) = form
    let buffer = CodeBuffer::new(lse_atomic_add=true)
    let offset = emit_atomic_rmw(buffer, width, Add, address, value, result)
    inspect(offset, content="0")
    assert_true(buffer.code == [0x62, 0x00, 0xe1, opcode])
  }
}

///|
test "AArch64 poll prefix pointer uses the signed byte load displacement" {
  let buffer = CodeBuffer::new()
  emit_negative_scalar_load(
    buffer,
    0xF9400000U,
    @vcode.PhysicalReg::new(19, Int),
    @vcode.PhysicalReg::new(0, Int),
    -240L,
  )
  debug_inspect(buffer.code, content="[0x60, 0x02, 0x51, 0xf8]")
}
