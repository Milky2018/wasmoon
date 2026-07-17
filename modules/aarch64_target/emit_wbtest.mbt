///|
test "AArch64 stack access encodings preserve width and scaled offset" {
  let buffer = CodeBuffer::new()
  emit_stack_access(buffer, false, I64, @vcode.PhysicalReg::new(19, Int), 16)
  emit_stack_access(buffer, true, I64, @vcode.PhysicalReg::new(20, Int), 16)
  emit_stack_access(buffer, false, I32, @vcode.PhysicalReg::new(0, Int), 12)
  emit_stack_access(buffer, true, I32, @vcode.PhysicalReg::new(1, Int), 12)
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0xf3,
      #|  0x0b,
      #|  0x00,
      #|  0xf9,
      #|  0xf4,
      #|  0x0b,
      #|  0x40,
      #|  0xf9,
      #|  0xe0,
      #|  0x0f,
      #|  0x00,
      #|  0xb9,
      #|  0xe1,
      #|  0x0f,
      #|  0x40,
      #|  0xb9,
      #|]
    ),
  )
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0xe5,
      #|  0x03,
      #|  0x23,
      #|  0x2a,
      #|  0xe5,
      #|  0x03,
      #|  0x23,
      #|  0xaa,
      #|  0x65,
      #|  0x10,
      #|  0xc0,
      #|  0x5a,
      #|  0x65,
      #|  0x10,
      #|  0xc0,
      #|  0xda,
      #|]
    ),
  )
}

///|
test "AArch64 overflow arithmetic encodes every width and signedness" {
  let buffer = CodeBuffer::new()
  let operations : Array[@semantic.IntOverflowOp] = [
    Add(Signed),
    Add(Unsigned),
    Sub(Signed),
    Sub(Unsigned),
    Mul(Signed),
    Mul(Unsigned),
  ]
  for width in [W32, W64] {
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0x2b,
      #|  0xe3,
      #|  0x77,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0x2b,
      #|  0xe3,
      #|  0x37,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0x6b,
      #|  0xe3,
      #|  0x77,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0x6b,
      #|  0xe3,
      #|  0x27,
      #|  0x9f,
      #|  0x9a,
      #|  0x10,
      #|  0x7c,
      #|  0x21,
      #|  0x9b,
      #|  0x02,
      #|  0x7e,
      #|  0x40,
      #|  0x93,
      #|  0x1f,
      #|  0x02,
      #|  0x02,
      #|  0xeb,
      #|  0xe3,
      #|  0x07,
      #|  0x9f,
      #|  0x9a,
      #|  0x10,
      #|  0x7c,
      #|  0xa1,
      #|  0x9b,
      #|  0xe2,
      #|  0x03,
      #|  0x10,
      #|  0x2a,
      #|  0x1f,
      #|  0x02,
      #|  0x02,
      #|  0xeb,
      #|  0xe3,
      #|  0x07,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0xab,
      #|  0xe3,
      #|  0x77,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0xab,
      #|  0xe3,
      #|  0x37,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0xeb,
      #|  0xe3,
      #|  0x77,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0xeb,
      #|  0xe3,
      #|  0x27,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x7c,
      #|  0x01,
      #|  0x9b,
      #|  0x10,
      #|  0x7c,
      #|  0x41,
      #|  0x9b,
      #|  0x1f,
      #|  0xfe,
      #|  0x82,
      #|  0xeb,
      #|  0xe3,
      #|  0x07,
      #|  0x9f,
      #|  0x9a,
      #|  0x02,
      #|  0x7c,
      #|  0x01,
      #|  0x9b,
      #|  0x10,
      #|  0x7c,
      #|  0xc1,
      #|  0x9b,
      #|  0x1f,
      #|  0x02,
      #|  0x00,
      #|  0xf1,
      #|  0xe3,
      #|  0x07,
      #|  0x9f,
      #|  0x9a,
      #|]
    ),
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
  let integer_lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in integer_lanes {
    emit_vector_splat(buffer, lane, int0, vector1)
  }
  let float_lanes : Array[@semantic.VectorLane] = [F32x4, F64x2]
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x03,
      #|  0xe4,
      #|  0x00,
      #|  0x6f,
      #|  0x03,
      #|  0xe4,
      #|  0x00,
      #|  0x6f,
      #|  0x10,
      #|  0x20,
      #|  0x80,
      #|  0xd2,
      #|  0x50,
      #|  0x60,
      #|  0xa0,
      #|  0xf2,
      #|  0x90,
      #|  0xa0,
      #|  0xc0,
      #|  0xf2,
      #|  0xd0,
      #|  0xe0,
      #|  0xe0,
      #|  0xf2,
      #|  0x03,
      #|  0x1e,
      #|  0x08,
      #|  0x4e,
      #|  0x10,
      #|  0x21,
      #|  0x81,
      #|  0xd2,
      #|  0x50,
      #|  0x61,
      #|  0xa1,
      #|  0xf2,
      #|  0x90,
      #|  0xa1,
      #|  0xc1,
      #|  0xf2,
      #|  0xd0,
      #|  0xe1,
      #|  0xe1,
      #|  0xf2,
      #|  0x03,
      #|  0x1e,
      #|  0x18,
      #|  0x4e,
      #|  0x01,
      #|  0x0c,
      #|  0x01,
      #|  0x4e,
      #|  0x01,
      #|  0x0c,
      #|  0x02,
      #|  0x4e,
      #|  0x01,
      #|  0x0c,
      #|  0x04,
      #|  0x4e,
      #|  0x01,
      #|  0x0c,
      #|  0x08,
      #|  0x4e,
      #|  0x01,
      #|  0x04,
      #|  0x04,
      #|  0x4e,
      #|  0x01,
      #|  0x04,
      #|  0x08,
      #|  0x4e,
      #|  0x03,
      #|  0x58,
      #|  0x20,
      #|  0x6e,
      #|  0x03,
      #|  0x1c,
      #|  0x21,
      #|  0x4e,
      #|  0x03,
      #|  0x1c,
      #|  0xa1,
      #|  0x4e,
      #|  0x03,
      #|  0x1c,
      #|  0x21,
      #|  0x6e,
      #|  0x03,
      #|  0x1c,
      #|  0x61,
      #|  0x4e,
      #|  0x02,
      #|  0x1c,
      #|  0x61,
      #|  0x6e,
      #|  0x01,
      #|  0x1c,
      #|  0x21,
      #|  0x6e,
      #|  0x21,
      #|  0x1c,
      #|  0x62,
      #|  0x4e,
      #|  0x21,
      #|  0x1c,
      #|  0x20,
      #|  0x6e,
      #|  0x03,
      #|  0x1c,
      #|  0x21,
      #|  0x6e,
      #|  0x63,
      #|  0x1c,
      #|  0x22,
      #|  0x4e,
      #|  0x63,
      #|  0x1c,
      #|  0x21,
      #|  0x6e,
      #|  0x21,
      #|  0x1c,
      #|  0xa1,
      #|  0x4e,
      #|  0x40,
      #|  0x00,
      #|  0x00,
      #|  0x35,
      #|  0x41,
      #|  0x1c,
      #|  0xa2,
      #|  0x4e,
      #|  0x42,
      #|  0x1c,
      #|  0xa2,
      #|  0x4e,
      #|  0x41,
      #|  0x00,
      #|  0x00,
      #|  0x34,
      #|  0x22,
      #|  0x1c,
      #|  0xa1,
      #|  0x4e,
      #|  0x43,
      #|  0x1c,
      #|  0xa2,
      #|  0x4e,
      #|  0x40,
      #|  0x00,
      #|  0x00,
      #|  0x34,
      #|  0x23,
      #|  0x1c,
      #|  0xa1,
      #|  0x4e,
      #|]
    ),
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x67,
      #|  0x2c,
      #|  0x1f,
      #|  0x0e,
      #|  0x67,
      #|  0x3c,
      #|  0x1f,
      #|  0x0e,
      #|  0x67,
      #|  0x2c,
      #|  0x1e,
      #|  0x0e,
      #|  0x67,
      #|  0x3c,
      #|  0x1e,
      #|  0x0e,
      #|  0x67,
      #|  0x3c,
      #|  0x1c,
      #|  0x0e,
      #|  0x67,
      #|  0x3c,
      #|  0x18,
      #|  0x4e,
      #|  0x67,
      #|  0x04,
      #|  0x14,
      #|  0x5e,
      #|  0x67,
      #|  0x04,
      #|  0x18,
      #|  0x5e,
      #|  0xa9,
      #|  0x1c,
      #|  0x1f,
      #|  0x4e,
      #|  0xa9,
      #|  0x1c,
      #|  0x1e,
      #|  0x4e,
      #|  0xa9,
      #|  0x1c,
      #|  0x1c,
      #|  0x4e,
      #|  0xa9,
      #|  0x1c,
      #|  0x18,
      #|  0x4e,
      #|  0xc9,
      #|  0x04,
      #|  0x14,
      #|  0x6e,
      #|  0xc9,
      #|  0x04,
      #|  0x18,
      #|  0x6e,
      #|]
    ),
  )
}

///|
test "AArch64 vector permutation encodings use table lookup" {
  let buffer = CodeBuffer::new()
  let vector0 = @vcode.PhysicalReg::new(0, FpVector)
  let vector1 = @vcode.PhysicalReg::new(1, FpVector)
  let vector2 = @vcode.PhysicalReg::new(2, FpVector)
  emit_vector_table_lookup(buffer, vector0, vector1, vector2)
  let mask : FixedArray[Int] = [
    0, 17, 2, 19, 4, 21, 6, 23, 8, 25, 10, 27, 12, 29, 14, 31,
  ]
  emit_vector_shuffle(buffer, mask, vector0, vector1, vector2)
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x02,
      #|  0x00,
      #|  0x01,
      #|  0x4e,
      #|  0x10,
      #|  0xe4,
      #|  0x00,
      #|  0x6f,
      #|  0x10,
      #|  0x00,
      #|  0x90,
      #|  0xd2,
      #|  0x50,
      #|  0x00,
      #|  0xb0,
      #|  0xf2,
      #|  0x90,
      #|  0x00,
      #|  0xd0,
      #|  0xf2,
      #|  0xd0,
      #|  0x00,
      #|  0xf0,
      #|  0xf2,
      #|  0x10,
      #|  0x1e,
      #|  0x08,
      #|  0x4e,
      #|  0x10,
      #|  0x01,
      #|  0x90,
      #|  0xd2,
      #|  0x50,
      #|  0x01,
      #|  0xb0,
      #|  0xf2,
      #|  0x90,
      #|  0x01,
      #|  0xd0,
      #|  0xf2,
      #|  0xd0,
      #|  0x01,
      #|  0xf0,
      #|  0xf2,
      #|  0x10,
      #|  0x1e,
      #|  0x18,
      #|  0x4e,
      #|  0x10,
      #|  0x00,
      #|  0x10,
      #|  0x4e,
      #|  0x11,
      #|  0xe4,
      #|  0x00,
      #|  0x6f,
      #|  0x10,
      #|  0x30,
      #|  0x80,
      #|  0xd2,
      #|  0x10,
      #|  0x70,
      #|  0xa0,
      #|  0xf2,
      #|  0x10,
      #|  0xb0,
      #|  0xc0,
      #|  0xf2,
      #|  0x10,
      #|  0xf0,
      #|  0xe0,
      #|  0xf2,
      #|  0x11,
      #|  0x1e,
      #|  0x08,
      #|  0x4e,
      #|  0x10,
      #|  0x30,
      #|  0x81,
      #|  0xd2,
      #|  0x10,
      #|  0x70,
      #|  0xa1,
      #|  0xf2,
      #|  0x10,
      #|  0xb0,
      #|  0xc1,
      #|  0xf2,
      #|  0x10,
      #|  0xf0,
      #|  0xe1,
      #|  0xf2,
      #|  0x11,
      #|  0x1e,
      #|  0x18,
      #|  0x4e,
      #|  0x31,
      #|  0x00,
      #|  0x11,
      #|  0x4e,
      #|  0x02,
      #|  0x1e,
      #|  0xb1,
      #|  0x4e,
      #|]
    ),
  )
}

///|
test "AArch64 basic vector integer encodings preserve every lane width" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(3, FpVector)
  let right = @vcode.PhysicalReg::new(5, FpVector)
  let destination = @vcode.PhysicalReg::new(7, FpVector)
  let lanes : Array[@semantic.VectorLane] = [I8x16, I16x8, I32x4, I64x2]
  for lane in lanes {
    emit_vector_int_unary(buffer, lane, Absolute, left, destination)
    emit_vector_int_unary(buffer, lane, Negate, left, destination)
    emit_vector_int_binary(buffer, lane, Add, left, right, destination)
    emit_vector_int_binary(buffer, lane, Sub, left, right, destination)
  }
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x67,
      #|  0xb8,
      #|  0x20,
      #|  0x4e,
      #|  0x67,
      #|  0xb8,
      #|  0x20,
      #|  0x6e,
      #|  0x67,
      #|  0x84,
      #|  0x25,
      #|  0x4e,
      #|  0x67,
      #|  0x84,
      #|  0x25,
      #|  0x6e,
      #|  0x67,
      #|  0xb8,
      #|  0x60,
      #|  0x4e,
      #|  0x67,
      #|  0xb8,
      #|  0x60,
      #|  0x6e,
      #|  0x67,
      #|  0x84,
      #|  0x65,
      #|  0x4e,
      #|  0x67,
      #|  0x84,
      #|  0x65,
      #|  0x6e,
      #|  0x67,
      #|  0xb8,
      #|  0xa0,
      #|  0x4e,
      #|  0x67,
      #|  0xb8,
      #|  0xa0,
      #|  0x6e,
      #|  0x67,
      #|  0x84,
      #|  0xa5,
      #|  0x4e,
      #|  0x67,
      #|  0x84,
      #|  0xa5,
      #|  0x6e,
      #|  0x67,
      #|  0xb8,
      #|  0xe0,
      #|  0x4e,
      #|  0x67,
      #|  0xb8,
      #|  0xe0,
      #|  0x6e,
      #|  0x67,
      #|  0x84,
      #|  0xe5,
      #|  0x4e,
      #|  0x67,
      #|  0x84,
      #|  0xe5,
      #|  0x6e,
      #|]
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
    layout,
    content=(
      #|{
      #|  arguments: [
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
      #|  stack_size: 48,
      #|}
    ),
  )
}

///|
test "validated internal ABI derives context, overflow, and result locations" {
  let abi = InternalAbi::new(
    0,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let layout = abi.call_layout(
    @semantic.Signature::new(
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
  let results = abi.result_registers([I64, F64])
  debug_inspect(
    (layout, results),
    content=(
      #|(
      #|  {
      #|    arguments: [
      #|      CallRegister(p0:int),
      #|      CallRegister(p1:int),
      #|      CallRegister(p2:int),
      #|      CallRegister(p3:int),
      #|      CallRegister(p4:int),
      #|      CallRegister(p5:int),
      #|      CallRegister(p6:int),
      #|      CallRegister(p7:int),
      #|      CallStack(0),
      #|      CallRegister(p0:fpvec),
      #|      CallRegister(p1:fpvec),
      #|      CallRegister(p2:fpvec),
      #|      CallRegister(p3:fpvec),
      #|      CallRegister(p4:fpvec),
      #|      CallRegister(p5:fpvec),
      #|      CallRegister(p6:fpvec),
      #|      CallRegister(p7:fpvec),
      #|      CallStack(16),
      #|    ],
      #|    stack_size: 32,
      #|  },
      #|  [p0:int, p0:fpvec],
      #|)
    ),
  )
}
