///|
const AARCH64_DIVISION_BY_ZERO_BRK : UInt = 4U

///|
const AARCH64_INTEGER_OVERFLOW_BRK : UInt = 5U

///|
const AARCH64_INVALID_CONVERSION_BRK : UInt = 3U

///|
priv struct BranchFixup {
  offset : Int
  target : @vcode.Block
  bits : Int
}

///|
priv struct CodeBuffer {
  code : Array[Byte]
  fixups : Array[BranchFixup]
  relocations : Array[@code_object.Relocation]
}

///|
pub suberror AArch64EmitError {
  InvalidFrame(cause~ : AArch64FrameError)
  InvalidCodeObject(cause~ : @code_object.CodeObjectVerifyError)
  InvalidParallelMove(cause~ : @vcode.MoveResolveError)
  UnresolvedStackMove
  MissingStackObjectArea
  FrameOffsetOutOfRange(offset~ : Int)
  InvalidScalarMemoryAccess
  InvalidFloatInstruction
  InvalidVectorInstruction
  InvalidConversionInstruction
  BranchTargetMissing(block~ : @vcode.Block)
  BranchOutOfRange(offset~ : Int, bits~ : Int)
} derive(Debug)

///|
pub impl Show for AArch64EmitError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn CodeBuffer::new() -> CodeBuffer {
  { code: [], fixups: [], relocations: [] }
}

///|
fn CodeBuffer::position(self : CodeBuffer) -> Int {
  self.code.length()
}

///|
fn CodeBuffer::emit_word(self : CodeBuffer, word : UInt) -> Unit {
  self.code.push((word & 0xFFU).to_byte())
  self.code.push(((word >> 8) & 0xFFU).to_byte())
  self.code.push(((word >> 16) & 0xFFU).to_byte())
  self.code.push(((word >> 24) & 0xFFU).to_byte())
}

///|
fn CodeBuffer::patch_word(self : CodeBuffer, offset : Int, word : UInt) -> Unit {
  self.code[offset] = (word & 0xFFU).to_byte()
  self.code[offset + 1] = ((word >> 8) & 0xFFU).to_byte()
  self.code[offset + 2] = ((word >> 16) & 0xFFU).to_byte()
  self.code[offset + 3] = ((word >> 24) & 0xFFU).to_byte()
}

///|
fn CodeBuffer::emit_branch(
  self : CodeBuffer,
  target : @vcode.Block,
  bits : Int,
  base : UInt,
) -> Unit {
  let offset = self.position()
  self.emit_word(base)
  self.fixups.push({ offset, target, bits })
}

///|
fn reg_bits(reg : @vcode.PhysicalReg) -> UInt {
  reg.id.reinterpret_as_uint() & 31U
}

///|
fn encode_three_register(
  base : UInt,
  rd : @vcode.PhysicalReg,
  rn : @vcode.PhysicalReg,
  rm : @vcode.PhysicalReg,
) -> UInt {
  base | (reg_bits(rm) << 16) | (reg_bits(rn) << 5) | reg_bits(rd)
}

///|
fn emit_move(
  buffer : CodeBuffer,
  ty : @semantic.ValueType,
  to : @vcode.PhysicalReg,
  from : @vcode.PhysicalReg,
) -> Unit {
  if to == from {
    return
  }
  match ty {
    I32 => buffer.emit_word(0x2A0003E0U | (reg_bits(from) << 16) | reg_bits(to))
    I64 | Ptr64 | GcRef64 =>
      buffer.emit_word(0xAA0003E0U | (reg_bits(from) << 16) | reg_bits(to))
    F32 | F64 | V128 =>
      buffer.emit_word(
        0x4EA01C00U |
        (reg_bits(from) << 16) |
        (reg_bits(from) << 5) |
        reg_bits(to),
      )
  }
}

///|
fn emit_constant(
  buffer : CodeBuffer,
  width : GprWidth,
  destination : @vcode.PhysicalReg,
  bits : UInt64,
) -> Unit {
  let halfword_count = if width == W32 { 2 } else { 4 }
  let movz_base = if width == W32 { 0x52800000U } else { 0xD2800000U }
  let movk_base = if width == W32 { 0x72800000U } else { 0xF2800000U }
  let mut first = true
  for index in 0..<halfword_count {
    let halfword = ((bits >> (index * 16)) & 0xFFFFUL).to_uint()
    if halfword != 0U || (first && index == halfword_count - 1) {
      let base = if first { movz_base } else { movk_base }
      buffer.emit_word(
        base |
        (index.reinterpret_as_uint() << 21) |
        (halfword << 5) |
        reg_bits(destination),
      )
      first = false
    }
  }
}

///|
fn emit_stack_access(
  buffer : CodeBuffer,
  load : Bool,
  ty : @semantic.ValueType,
  reg : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise AArch64EmitError {
  let (scale, load_base, store_base) = match ty {
    I32 => (4, 0xB9400000U, 0xB9000000U)
    I64 | Ptr64 | GcRef64 => (8, 0xF9400000U, 0xF9000000U)
    F32 => (4, 0xBD400000U, 0xBD000000U)
    F64 => (8, 0xFD400000U, 0xFD000000U)
    V128 => (16, 0x3DC00000U, 0x3D800000U)
  }
  if offset < 0 || offset % scale != 0 || offset / scale > 4095 {
    raise FrameOffsetOutOfRange(offset~)
  }
  let base = if load { load_base } else { store_base }
  buffer.emit_word(
    base |
    ((offset / scale).reinterpret_as_uint() << 10) |
    (31U << 5) |
    reg_bits(reg),
  )
}

///|
fn scalar_memory_scale(width : @semantic.AccessWidth) -> UInt64? {
  match width {
    W8 => Some(1UL)
    W16 => Some(2UL)
    W32 => Some(4UL)
    W64 => Some(8UL)
    W128 => None
  }
}

///|
fn scalar_memory_address(
  buffer : CodeBuffer,
  address : @vcode.PhysicalReg,
  width : @semantic.AccessWidth,
  offset : UInt64,
) -> (@vcode.PhysicalReg, UInt) raise AArch64EmitError {
  guard scalar_memory_scale(width) is Some(scale) else {
    raise InvalidScalarMemoryAccess
  }
  if offset % scale == 0UL && offset / scale <= 4095UL {
    return (address, (offset / scale).to_uint())
  }
  let scratch = @vcode.PhysicalReg::new(16, Int)
  emit_constant(buffer, W64, scratch, offset)
  buffer.emit_word(
    encode_three_register(0x8B000000U, scratch, address, scratch),
  )
  (scratch, 0U)
}

///|
fn scalar_load_base(
  width : @semantic.AccessWidth,
  extension : @semantic.LoadExtension,
  result_type : @semantic.ValueType,
) -> UInt? {
  match (result_type, width, extension) {
    (I32 | I64, W8, Unsigned) => Some(0x39400000U)
    (I32, W8, Signed) => Some(0x39C00000U)
    (I64, W8, Signed) => Some(0x39800000U)
    (I32 | I64, W16, Unsigned) => Some(0x79400000U)
    (I32, W16, Signed) => Some(0x79C00000U)
    (I64, W16, Signed) => Some(0x79800000U)
    (I32, W32, None) | (I64, W32, Unsigned) => Some(0xB9400000U)
    (I64, W32, Signed) => Some(0xB9800000U)
    (I64 | Ptr64 | GcRef64, W64, None) => Some(0xF9400000U)
    (F32, W32, None) => Some(0xBD400000U)
    (F64, W64, None) => Some(0xFD400000U)
    _ => None
  }
}

///|
fn scalar_store_base(
  width : @semantic.AccessWidth,
  value_type : @semantic.ValueType,
) -> UInt? {
  match (value_type, width) {
    (I32 | I64, W8) => Some(0x39000000U)
    (I32 | I64, W16) => Some(0x79000000U)
    (I32 | I64, W32) => Some(0xB9000000U)
    (I64 | Ptr64 | GcRef64, W64) => Some(0xF9000000U)
    (F32, W32) => Some(0xBD000000U)
    (F64, W64) => Some(0xFD000000U)
    _ => None
  }
}

///|
fn emit_sp_adjust(
  buffer : CodeBuffer,
  subtract : Bool,
  amount : Int,
) -> Unit raise AArch64EmitError {
  if amount == 0 {
    return
  }
  if amount < 0 {
    raise FrameOffsetOutOfRange(offset=amount)
  }
  let base = if subtract { 0xD1000000U } else { 0x91000000U }
  let mut remaining = amount
  while remaining >= 4096 {
    let pages = Int::min(remaining / 4096, 4095)
    buffer.emit_word(
      base | (1U << 22) | (pages.reinterpret_as_uint() << 10) | (31U << 5) | 31U,
    )
    remaining -= pages * 4096
  }
  if remaining > 0 {
    buffer.emit_word(
      base | (remaining.reinterpret_as_uint() << 10) | (31U << 5) | 31U,
    )
  }
}

///|
fn emit_stack_address(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  offset : Int,
) -> Unit {
  if offset <= 4095 {
    buffer.emit_word(
      0x91000000U |
      (offset.reinterpret_as_uint() << 10) |
      (31U << 5) |
      reg_bits(destination),
    )
  } else if offset % 4096 == 0 && offset / 4096 <= 4095 {
    buffer.emit_word(
      0x91400000U |
      ((offset / 4096).reinterpret_as_uint() << 10) |
      (31U << 5) |
      reg_bits(destination),
    )
  } else {
    buffer.emit_word(0x910003E0U | reg_bits(destination))
    let scratch = @vcode.PhysicalReg::new(16, Int)
    emit_constant(buffer, W64, scratch, offset.to_uint64())
    buffer.emit_word(
      encode_three_register(0x8B000000U, destination, destination, scratch),
    )
  }
}

///|
fn condition_code(condition : AArch64Condition) -> UInt {
  match condition {
    Eq => 0U
    Ne => 1U
    Hs => 2U
    Lo => 3U
    Hi => 8U
    Ls => 9U
    Ge => 10U
    Lt => 11U
    Gt => 12U
    Le => 13U
  }
}

///|
fn encode_int_unary(
  width : GprWidth,
  operation : AArch64IntUnary,
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> UInt {
  match (width, operation) {
    (W32, Mvn) => 0x2A2003E0U | (reg_bits(source) << 16) | reg_bits(destination)
    (W64, Mvn) => 0xAA2003E0U | (reg_bits(source) << 16) | reg_bits(destination)
    (W32, Clz) => 0x5AC01000U | (reg_bits(source) << 5) | reg_bits(destination)
    (W64, Clz) => 0xDAC01000U | (reg_bits(source) << 5) | reg_bits(destination)
    (W32, Rbit) => 0x5AC00000U | (reg_bits(source) << 5) | reg_bits(destination)
    (W64, Rbit) => 0xDAC00000U | (reg_bits(source) << 5) | reg_bits(destination)
    (W32, Neg) => 0x4B0003E0U | (reg_bits(source) << 16) | reg_bits(destination)
    (W64, Neg) => 0xCB0003E0U | (reg_bits(source) << 16) | reg_bits(destination)
  }
}

///|
fn encode_int_binary(
  width : GprWidth,
  operation : AArch64IntBinary,
  destination : @vcode.PhysicalReg,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
) -> UInt {
  let base = match (width, operation) {
    (W32, Add) => 0x0B000000U
    (W64, Add) => 0x8B000000U
    (W32, Sub) => 0x4B000000U
    (W64, Sub) => 0xCB000000U
    (W32, Mul) => 0x1B007C00U
    (W64, Mul) => 0x9B007C00U
    (W32, And) => 0x0A000000U
    (W64, And) => 0x8A000000U
    (W32, Orr) => 0x2A000000U
    (W64, Orr) => 0xAA000000U
    (W32, Eor) => 0x4A000000U
    (W64, Eor) => 0xCA000000U
    (W32, Lsl) => 0x1AC02000U
    (W64, Lsl) => 0x9AC02000U
    (W32, Lsr) => 0x1AC02400U
    (W64, Lsr) => 0x9AC02400U
    (W32, Asr) => 0x1AC02800U
    (W64, Asr) => 0x9AC02800U
    (W32, Ror) => 0x1AC02C00U
    (W64, Ror) => 0x9AC02C00U
    (W32, Sdiv) => 0x1AC00C00U
    (W64, Sdiv) => 0x9AC00C00U
    (W32, Udiv) => 0x1AC00800U
    (W64, Udiv) => 0x9AC00800U
  }
  encode_three_register(base, destination, left, right)
}

///|
fn emit_overflow_flag(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  condition : UInt,
) -> Unit {
  buffer.emit_word(
    0x9A9F07E0U | ((condition ^ 1U) << 12) | reg_bits(destination),
  )
}

///|
fn emit_int_with_overflow(
  buffer : CodeBuffer,
  width : GprWidth,
  operation : @semantic.IntOverflowOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
  overflow : @vcode.PhysicalReg,
) -> Unit {
  match operation {
    Add(signedness) => {
      let base = if width == W32 { 0x2B000000U } else { 0xAB000000U }
      buffer.emit_word(encode_three_register(base, result, left, right))
      emit_overflow_flag(
        buffer,
        overflow,
        if signedness == Signed {
          6U
        } else {
          2U
        },
      )
    }
    Sub(signedness) => {
      let base = if width == W32 { 0x6B000000U } else { 0xEB000000U }
      buffer.emit_word(encode_three_register(base, result, left, right))
      emit_overflow_flag(
        buffer,
        overflow,
        if signedness == Signed {
          6U
        } else {
          3U
        },
      )
    }
    Mul(signedness) => {
      let scratch = @vcode.PhysicalReg::new(16, Int)
      if width == W64 {
        buffer.emit_word(encode_int_binary(W64, Mul, result, left, right))
        let high_base = if signedness == Signed {
          0x9B407C00U
        } else {
          0x9BC07C00U
        }
        buffer.emit_word(encode_three_register(high_base, scratch, left, right))
        if signedness == Signed {
          buffer.emit_word(
            0xEB00001FU |
            (2U << 22) |
            (reg_bits(result) << 16) |
            (63U << 10) |
            (reg_bits(scratch) << 5),
          )
        } else {
          buffer.emit_word(0xF100001FU | (reg_bits(scratch) << 5))
        }
      } else {
        let wide_base = if signedness == Signed {
          0x9B207C00U
        } else {
          0x9BA07C00U
        }
        buffer.emit_word(encode_three_register(wide_base, scratch, left, right))
        if signedness == Signed {
          buffer.emit_word(
            0x93407C00U | (reg_bits(scratch) << 5) | reg_bits(result),
          )
        } else {
          emit_move(buffer, I32, result, scratch)
        }
        buffer.emit_word(
          0xEB00001FU | (reg_bits(result) << 16) | (reg_bits(scratch) << 5),
        )
      }
      emit_overflow_flag(buffer, overflow, 1U)
    }
  }
}

///|
fn encode_vector_move(
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> UInt {
  0x4EA01C00U |
  (reg_bits(source) << 16) |
  (reg_bits(source) << 5) |
  reg_bits(destination)
}

///|
fn emit_vector_constant(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  low : UInt64,
  high : UInt64,
) -> Unit {
  buffer.emit_word(0x6F00E400U | reg_bits(destination))
  let scratch = @vcode.PhysicalReg::new(16, Int)
  if low != 0UL {
    emit_constant(buffer, W64, scratch, low)
    buffer.emit_word(
      0x4E081C00U | (reg_bits(scratch) << 5) | reg_bits(destination),
    )
  }
  if high != 0UL {
    emit_constant(buffer, W64, scratch, high)
    buffer.emit_word(
      0x4E181C00U | (reg_bits(scratch) << 5) | reg_bits(destination),
    )
  }
}

///|
fn emit_vector_select(
  buffer : CodeBuffer,
  condition : @vcode.PhysicalReg,
  when_true : @vcode.PhysicalReg,
  when_false : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  if destination == when_true {
    buffer.emit_word(encode_vector_move(destination, when_true))
    buffer.emit_word(0x35000000U | (2U << 5) | reg_bits(condition))
    buffer.emit_word(encode_vector_move(destination, when_false))
  } else {
    buffer.emit_word(encode_vector_move(destination, when_false))
    buffer.emit_word(0x34000000U | (2U << 5) | reg_bits(condition))
    buffer.emit_word(encode_vector_move(destination, when_true))
  }
}

///|
fn emit_vector_splat(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let base : UInt = match lane {
    I8x16 => 0x4E010C00U
    I16x8 => 0x4E020C00U
    I32x4 => 0x4E040C00U
    I64x2 => 0x4E080C00U
    F32x4 => 0x4E040400U
    F64x2 => 0x4E080400U
  }
  buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
}

///|
fn emit_vector_extract_lane(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  index : Int,
  extension : @semantic.Signedness?,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let base : UInt = match lane {
    I8x16 => if extension is Some(Signed) { 0x0E012C00U } else { 0x0E013C00U }
    I16x8 => if extension is Some(Signed) { 0x0E022C00U } else { 0x0E023C00U }
    I32x4 => 0x0E043C00U
    I64x2 => 0x4E083C00U
    F32x4 => 0x5E040400U
    F64x2 => 0x5E080400U
  }
  let shift = match lane {
    I8x16 => 17
    I16x8 => 18
    I32x4 | F32x4 => 19
    I64x2 | F64x2 => 20
  }
  buffer.emit_word(
    base |
    (index.reinterpret_as_uint() << shift) |
    (reg_bits(source) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_replace_lane(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  index : Int,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let (lane_shift, lane_code) = match lane {
    I8x16 => (1, 1)
    I16x8 => (2, 2)
    I32x4 | F32x4 => (3, 4)
    I64x2 | F64x2 => (4, 8)
  }
  let immediate = (index << lane_shift) | lane_code
  let base = if lane == F32x4 || lane == F64x2 {
    0x6E000400U
  } else {
    0x4E001C00U
  }
  buffer.emit_word(
    base |
    (immediate.reinterpret_as_uint() << 16) |
    (reg_bits(source) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_table_lookup(
  buffer : CodeBuffer,
  table : @vcode.PhysicalReg,
  indices : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  buffer.emit_word(
    0x4E000000U |
    (reg_bits(indices) << 16) |
    (reg_bits(table) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_shuffle(
  buffer : CodeBuffer,
  mask : FixedArray[Int],
  first : @vcode.PhysicalReg,
  second : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let mut first_low = 0UL
  let mut first_high = 0UL
  let mut second_low = 0UL
  let mut second_high = 0UL
  for index in 0..<16 {
    let lane = mask[index]
    let shift = index % 8 * 8
    let first_index = if lane < 16 { lane } else { 0x80 }
    let second_index = if lane >= 16 { lane - 16 } else { 0x80 }
    if index < 8 {
      first_low = first_low | (first_index.to_uint64() << shift)
      second_low = second_low | (second_index.to_uint64() << shift)
    } else {
      first_high = first_high | (first_index.to_uint64() << shift)
      second_high = second_high | (second_index.to_uint64() << shift)
    }
  }
  let first_indices = @vcode.PhysicalReg::new(16, FpVector)
  let second_indices = @vcode.PhysicalReg::new(17, FpVector)
  emit_vector_constant(buffer, first_indices, first_low, first_high)
  emit_vector_table_lookup(buffer, first, first_indices, first_indices)
  emit_vector_constant(buffer, second_indices, second_low, second_high)
  emit_vector_table_lookup(buffer, second, second_indices, second_indices)
  buffer.emit_word(
    0x4EA01C00U |
    (reg_bits(second_indices) << 16) |
    (reg_bits(first_indices) << 5) |
    reg_bits(destination),
  )
}

///|
fn vector_lane_encoding(
  lane : @semantic.VectorLane,
  byte_base : UInt,
  half_base : UInt,
  word_base : UInt,
  double_base : UInt,
) -> UInt raise AArch64EmitError {
  match lane {
    I8x16 => byte_base
    I16x8 => half_base
    I32x4 => word_base
    I64x2 => double_base
    F32x4 | F64x2 => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_int_unary(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : AArch64VectorIntUnary,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let base = match operation {
    Absolute =>
      vector_lane_encoding(
        lane, 0x4E20B800U, 0x4E60B800U, 0x4EA0B800U, 0x4EE0B800U,
      )
    Negate =>
      vector_lane_encoding(
        lane, 0x6E20B800U, 0x6E60B800U, 0x6EA0B800U, 0x6EE0B800U,
      )
  }
  buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
}

///|
fn emit_vector_int_binary(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : AArch64VectorIntBinary,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  if operation == Mul && lane == I64x2 {
    let left_copy = @vcode.PhysicalReg::new(16, FpVector)
    let right_copy = @vcode.PhysicalReg::new(17, FpVector)
    let left_scalar = @vcode.PhysicalReg::new(16, Int)
    let right_scalar = @vcode.PhysicalReg::new(17, Int)
    emit_move(buffer, V128, left_copy, left)
    emit_move(buffer, V128, right_copy, right)
    for index in 0..<2 {
      emit_vector_extract_lane(
        buffer,
        I64x2,
        index,
        None,
        left_copy,
        left_scalar,
      )
      emit_vector_extract_lane(
        buffer,
        I64x2,
        index,
        None,
        right_copy,
        right_scalar,
      )
      buffer.emit_word(
        encode_int_binary(W64, Mul, left_scalar, left_scalar, right_scalar),
      )
      emit_vector_replace_lane(buffer, I64x2, index, left_scalar, destination)
    }
    return
  }
  let base = match operation {
    Add =>
      vector_lane_encoding(
        lane, 0x4E208400U, 0x4E608400U, 0x4EA08400U, 0x4EE08400U,
      )
    Sub =>
      vector_lane_encoding(
        lane, 0x6E208400U, 0x6E608400U, 0x6EA08400U, 0x6EE08400U,
      )
    Mul =>
      match lane {
        I8x16 => 0x4E209C00U
        I16x8 => 0x4E609C00U
        I32x4 => 0x4EA09C00U
        I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
      }
    SaturatingAdd(signedness) =>
      if signedness is Signed {
        vector_lane_encoding(
          lane, 0x4E200C00U, 0x4E600C00U, 0x4EA00C00U, 0x4EE00C00U,
        )
      } else {
        vector_lane_encoding(
          lane, 0x6E200C00U, 0x6E600C00U, 0x6EA00C00U, 0x6EE00C00U,
        )
      }
    SaturatingSub(signedness) =>
      if signedness is Signed {
        vector_lane_encoding(
          lane, 0x4E202C00U, 0x4E602C00U, 0x4EA02C00U, 0x4EE02C00U,
        )
      } else {
        vector_lane_encoding(
          lane, 0x6E202C00U, 0x6E602C00U, 0x6EA02C00U, 0x6EE02C00U,
        )
      }
  }
  buffer.emit_word(
    base |
    (reg_bits(right) << 16) |
    (reg_bits(left) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_int_shift(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : @semantic.VectorIntShiftOp,
  source : @vcode.PhysicalReg,
  amount : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let width_bits = match lane {
    I8x16 => 3
    I16x8 => 4
    I32x4 => 5
    I64x2 => 6
    F32x4 | F64x2 => raise InvalidVectorInstruction
  }
  let int_scratch = @vcode.PhysicalReg::new(16, Int)
  let vector_scratch = @vcode.PhysicalReg::new(16, FpVector)
  buffer.emit_word(
    0xD3400000U |
    ((width_bits - 1).reinterpret_as_uint() << 10) |
    (reg_bits(amount) << 5) |
    reg_bits(int_scratch),
  )
  let right_shift = operation is Right(_)
  if right_shift {
    buffer.emit_word(
      0xCB0003E0U | (reg_bits(int_scratch) << 16) | reg_bits(int_scratch),
    )
  }
  let duplicate_base = vector_lane_encoding(
    lane, 0x4E010C00U, 0x4E020C00U, 0x4E040C00U, 0x4E080C00U,
  )
  buffer.emit_word(
    duplicate_base | (reg_bits(int_scratch) << 5) | reg_bits(vector_scratch),
  )
  let unsigned_right = operation is Right(Unsigned)
  let shift_base = if unsigned_right {
    vector_lane_encoding(
      lane, 0x6E204400U, 0x6E604400U, 0x6EA04400U, 0x6EE04400U,
    )
  } else {
    vector_lane_encoding(
      lane, 0x4E204400U, 0x4E604400U, 0x4EA04400U, 0x4EE04400U,
    )
  }
  buffer.emit_word(
    shift_base |
    (reg_bits(vector_scratch) << 16) |
    (reg_bits(source) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_int_compare(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  comparison : @semantic.VectorIntComparison,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let default_signedness : @semantic.Signedness = Signed
  let (kind, signedness, swap, invert) = match comparison {
    Equal => (0, default_signedness, false, false)
    NotEqual => (0, default_signedness, false, true)
    LessThan(signedness) => (1, signedness, true, false)
    LessOrEqual(signedness) => (2, signedness, true, false)
    GreaterThan(signedness) => (1, signedness, false, false)
    GreaterOrEqual(signedness) => (2, signedness, false, false)
  }
  let (first, second) = if swap { (right, left) } else { (left, right) }
  let base = match kind {
    0 =>
      vector_lane_encoding(
        lane, 0x6E208C00U, 0x6E608C00U, 0x6EA08C00U, 0x6EE08C00U,
      )
    1 if signedness is Signed =>
      vector_lane_encoding(
        lane, 0x4E203400U, 0x4E603400U, 0x4EA03400U, 0x4EE03400U,
      )
    1 =>
      vector_lane_encoding(
        lane, 0x6E203400U, 0x6E603400U, 0x6EA03400U, 0x6EE03400U,
      )
    2 if signedness is Signed =>
      vector_lane_encoding(
        lane, 0x4E203C00U, 0x4E603C00U, 0x4EA03C00U, 0x4EE03C00U,
      )
    2 =>
      vector_lane_encoding(
        lane, 0x6E203C00U, 0x6E603C00U, 0x6EA03C00U, 0x6EE03C00U,
      )
    _ => raise InvalidVectorInstruction
  }
  buffer.emit_word(
    base |
    (reg_bits(second) << 16) |
    (reg_bits(first) << 5) |
    reg_bits(destination),
  )
  if invert {
    buffer.emit_word(
      0x6E205800U | (reg_bits(destination) << 5) | reg_bits(destination),
    )
  }
}

///|
fn emit_vector_binary(
  buffer : CodeBuffer,
  base : UInt,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  buffer.emit_word(
    base |
    (reg_bits(right) << 16) |
    (reg_bits(left) << 5) |
    reg_bits(destination),
  )
}

///|
fn emit_vector_bitwise(
  buffer : CodeBuffer,
  operation : @semantic.VectorBitwiseOp,
  first : @vcode.PhysicalReg,
  second : @vcode.PhysicalReg,
  mask : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  match operation {
    Not =>
      buffer.emit_word(
        0x6E205800U | (reg_bits(first) << 5) | reg_bits(destination),
      )
    And => emit_vector_binary(buffer, 0x4E201C00U, first, second, destination)
    Or => emit_vector_binary(buffer, 0x4EA01C00U, first, second, destination)
    Xor => emit_vector_binary(buffer, 0x6E201C00U, first, second, destination)
    AndNot =>
      emit_vector_binary(buffer, 0x4E601C00U, first, second, destination)
    BitSelect =>
      if destination == mask {
        emit_vector_binary(buffer, 0x6E601C00U, first, second, destination)
      } else if destination == second {
        emit_vector_binary(buffer, 0x6E201C00U, first, second, destination)
        emit_vector_binary(buffer, 0x4E601C00U, destination, mask, destination)
        emit_vector_binary(buffer, 0x6E201C00U, destination, first, destination)
      } else {
        emit_vector_binary(buffer, 0x6E201C00U, first, second, destination)
        emit_vector_binary(buffer, 0x4E201C00U, destination, mask, destination)
        emit_vector_binary(
          buffer, 0x6E201C00U, destination, second, destination,
        )
      }
  }
}

///|
fn float_unary_base(
  ty : @semantic.ValueType,
  operation : AArch64FloatUnary,
) -> UInt? {
  match (ty, operation) {
    (F32, Negate) => Some(0x1E214000U)
    (F64, Negate) => Some(0x1E614000U)
    (F32, Absolute) => Some(0x1E20C000U)
    (F64, Absolute) => Some(0x1E60C000U)
    (F32, SquareRoot) => Some(0x1E21C000U)
    (F64, SquareRoot) => Some(0x1E61C000U)
    (F32, Ceil) => Some(0x1E24C000U)
    (F64, Ceil) => Some(0x1E64C000U)
    (F32, Floor) => Some(0x1E254000U)
    (F64, Floor) => Some(0x1E654000U)
    (F32, Truncate) => Some(0x1E25C000U)
    (F64, Truncate) => Some(0x1E65C000U)
    (F32, Nearest) => Some(0x1E244000U)
    (F64, Nearest) => Some(0x1E644000U)
    _ => None
  }
}

///|
fn float_binary_base(
  ty : @semantic.ValueType,
  operation : AArch64FloatBinary,
) -> UInt? {
  match (ty, operation) {
    (F32, Add) => Some(0x1E202800U)
    (F64, Add) => Some(0x1E602800U)
    (F32, Sub) => Some(0x1E203800U)
    (F64, Sub) => Some(0x1E603800U)
    (F32, Mul) => Some(0x1E200800U)
    (F64, Mul) => Some(0x1E600800U)
    (F32, Div) => Some(0x1E201800U)
    (F64, Div) => Some(0x1E601800U)
    (F32, Min) => Some(0x1E205800U)
    (F64, Min) => Some(0x1E605800U)
    (F32, Max) => Some(0x1E204800U)
    (F64, Max) => Some(0x1E604800U)
    _ => None
  }
}

///|
fn emit_float_copy_sign(
  buffer : CodeBuffer,
  ty : @semantic.ValueType,
  magnitude : @vcode.PhysicalReg,
  sign : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let int_scratch = @vcode.PhysicalReg::new(16, Int)
  let fp_scratch = @vcode.PhysicalReg::new(16, FpVector)
  match ty {
    F32 => {
      emit_constant(buffer, W32, int_scratch, 0x80000000UL)
      buffer.emit_word(
        0x1E270000U | (reg_bits(int_scratch) << 5) | reg_bits(fp_scratch),
      )
    }
    F64 => {
      emit_constant(buffer, W64, int_scratch, 0x8000000000000000UL)
      buffer.emit_word(
        0x9E670000U | (reg_bits(int_scratch) << 5) | reg_bits(fp_scratch),
      )
    }
    _ => raise InvalidFloatInstruction
  }
  buffer.emit_word(
    0x6E601C00U |
    (reg_bits(magnitude) << 16) |
    (reg_bits(sign) << 5) |
    reg_bits(fp_scratch),
  )
  emit_move(buffer, ty, destination, fp_scratch)
}

///|
fn float_ternary_base(
  ty : @semantic.ValueType,
  operation : AArch64FloatTernary,
) -> UInt? {
  match (ty, operation) {
    (F32, Fmadd) => Some(0x1F000000U)
    (F64, Fmadd) => Some(0x1F400000U)
    (F32, Fmsub) => Some(0x1F008000U)
    (F64, Fmsub) => Some(0x1F408000U)
    (F32, Fnmadd) => Some(0x1F200000U)
    (F64, Fnmadd) => Some(0x1F600000U)
    (F32, Fnmsub) => Some(0x1F208000U)
    (F64, Fnmsub) => Some(0x1F608000U)
    _ => None
  }
}

///|
fn float_condition_code(condition : AArch64FloatCondition) -> UInt {
  match condition {
    Equal => 0U
    NotEqual => 1U
    LessThan => 4U
    LessOrEqual => 9U
    GreaterThan => 12U
    GreaterOrEqual => 10U
    Ordered => 7U
    Unordered => 6U
  }
}

///|
fn float_trap_condition_code(condition : AArch64FloatTrapCondition) -> UInt {
  match condition {
    Unordered => 6U
    LessThan => 4U
    LessOrEqual => 9U
    GreaterOrEqual => 10U
  }
}

///|
fn emit_conversion(
  buffer : CodeBuffer,
  conversion : AArch64Conversion,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  match conversion {
    WrapI64ToI32 | ExtendI32ToI64(Unsigned) =>
      emit_move(buffer, I32, destination, source)
    ExtendI32ToI64(Signed) =>
      buffer.emit_word(
        0x93407C00U | (reg_bits(source) << 5) | reg_bits(destination),
      )
    SignExtend(integer, width) => {
      let base = if integer == I32 { 0x13000000U } else { 0x93400000U }
      let highest_bit : UInt = match width {
        W8 => 7U
        W16 => 15U
        W32 => 31U
        _ => raise InvalidConversionInstruction
      }
      buffer.emit_word(
        base |
        (highest_bit << 10) |
        (reg_bits(source) << 5) |
        reg_bits(destination),
      )
    }
    DemoteF64ToF32 =>
      buffer.emit_word(
        0x1E624000U | (reg_bits(source) << 5) | reg_bits(destination),
      )
    PromoteF32ToF64 =>
      buffer.emit_word(
        0x1E22C000U | (reg_bits(source) << 5) | reg_bits(destination),
      )
    Bitcast(from, to) =>
      match (from, to) {
        (I32, F32) =>
          buffer.emit_word(
            0x1E270000U | (reg_bits(source) << 5) | reg_bits(destination),
          )
        (F32, I32) =>
          buffer.emit_word(
            0x1E260000U | (reg_bits(source) << 5) | reg_bits(destination),
          )
        (I64 | Ptr64, F64) =>
          buffer.emit_word(
            0x9E670000U | (reg_bits(source) << 5) | reg_bits(destination),
          )
        (F64, I64 | Ptr64) =>
          buffer.emit_word(
            0x9E660000U | (reg_bits(source) << 5) | reg_bits(destination),
          )
        _ =>
          if @vcode.reg_class_for_value_type(from) ==
            @vcode.reg_class_for_value_type(to) {
            emit_move(buffer, to, destination, source)
          } else {
            raise InvalidConversionInstruction
          }
      }
    IntToFloat(integer, float, signedness) => {
      let base : UInt = match (integer, float, signedness) {
        (I32, F32, Signed) => 0x1E220000U
        (I32, F32, Unsigned) => 0x1E230000U
        (I64, F32, Signed) => 0x9E220000U
        (I64, F32, Unsigned) => 0x9E230000U
        (I32, F64, Signed) => 0x1E620000U
        (I32, F64, Unsigned) => 0x1E630000U
        (I64, F64, Signed) => 0x9E620000U
        (I64, F64, Unsigned) => 0x9E630000U
      }
      buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
    }
    FloatToInt(float, integer, signedness) => {
      let base : UInt = match (float, integer, signedness) {
        (F32, I32, Signed) => 0x1E380000U
        (F32, I32, Unsigned) => 0x1E390000U
        (F32, I64, Signed) => 0x9E380000U
        (F32, I64, Unsigned) => 0x9E390000U
        (F64, I32, Signed) => 0x1E780000U
        (F64, I32, Unsigned) => 0x1E790000U
        (F64, I64, Signed) => 0x9E780000U
        (F64, I64, Unsigned) => 0x9E790000U
      }
      buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
    }
  }
}

///|
fn emit_register_save_or_restore(
  buffer : CodeBuffer,
  load : Bool,
  reg : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise AArch64EmitError {
  match reg.class {
    Int => emit_stack_access(buffer, load, I64, reg, offset)
    FpVector => {
      if offset < 0 || offset % 8 != 0 || offset / 8 > 4095 {
        raise FrameOffsetOutOfRange(offset~)
      }
      let base = if load { 0xFD400000U } else { 0xFD000000U }
      buffer.emit_word(
        base |
        ((offset / 8).reinterpret_as_uint() << 10) |
        (31U << 5) |
        reg_bits(reg),
      )
    }
  }
}

///|
fn emit_prologue(
  buffer : CodeBuffer,
  frame : AArch64Frame,
) -> Unit raise AArch64EmitError {
  emit_sp_adjust(buffer, true, frame.frame_size())
  for saved in frame.saved_registers() {
    let (reg, offset) = saved
    emit_register_save_or_restore(buffer, false, reg, offset)
  }
}

///|
fn emit_epilogue(
  buffer : CodeBuffer,
  frame : AArch64Frame,
) -> Unit raise AArch64EmitError {
  let saved = frame.saved_registers()
  for reverse_index in 0..<saved.length() {
    let (reg, offset) = saved[saved.length() - reverse_index - 1]
    emit_register_save_or_restore(buffer, true, reg, offset)
  }
  emit_sp_adjust(buffer, false, frame.frame_size())
}

///|
fn[Inst] emit_edit(
  buffer : CodeBuffer,
  function : @vcode.Function[Inst],
  frame : AArch64Frame,
  edit : @vcode.Edit,
) -> Unit raise AArch64EmitError {
  match edit.kind() {
    Spill(value~, reg~, slot~) =>
      emit_stack_access(
        buffer,
        false,
        function.value_type(value).unwrap(),
        reg,
        frame.slot_offset(slot).unwrap(),
      )
    Reload(value~, slot~, reg~) =>
      emit_stack_access(
        buffer,
        true,
        function.value_type(value).unwrap(),
        reg,
        frame.slot_offset(slot).unwrap(),
      )
    Move(value~, from~, to~) =>
      emit_move(buffer, function.value_type(value).unwrap(), to, from)
    EdgeMove(..) => ()
  }
}

///|
fn[Inst] emit_edits_at(
  buffer : CodeBuffer,
  function : @vcode.Function[Inst],
  frame : AArch64Frame,
  edits : Array[@vcode.Edit],
  instruction : @vcode.Instruction,
  placement : @vcode.PointPlacement,
) -> Unit raise AArch64EmitError {
  for edit in edits {
    if edit.point() is Some(point) &&
      point.instruction() == instruction &&
      point.placement() == placement {
      emit_edit(buffer, function, frame, edit)
    }
  }
}

///|
fn emit_call_arguments(
  buffer : CodeBuffer,
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  instruction : @vcode.Instruction,
  types : Array[@semantic.ValueType],
  locations : Array[CallArgumentLocation],
  operand_start? : Int = 0,
  stack_base? : Int = 0,
  callee? : (Int, @vcode.PhysicalReg),
) -> Unit raise AArch64EmitError {
  let moves : Array[@vcode.ParallelMove] = []
  for index, ty in types {
    let source = allocation
      .operand_location(instruction, operand_start + index)
      .unwrap()
    match locations[index] {
      CallRegister(destination) =>
        moves.push(
          @vcode.ParallelMove::new(ty, Register(source), Register(destination)),
        )
      CallStack(offset) =>
        emit_stack_access(buffer, false, ty, source, stack_base + offset)
    }
  }
  if callee is Some((operand_index, destination)) {
    moves.push(
      @vcode.ParallelMove::new(
        Ptr64,
        Register(
          allocation.operand_location(instruction, operand_index).unwrap(),
        ),
        Register(destination),
      ),
    )
  }
  let int_scratch = if callee is Some(_) {
    [@vcode.PhysicalReg::new(16, Int)]
  } else {
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)]
  }
  let resolved = @vcode.resolve_parallel_moves(moves, int_scratch, [
    @vcode.PhysicalReg::new(16, FpVector),
    @vcode.PhysicalReg::new(17, FpVector),
  ]) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
}

///|
fn emit_instruction(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Int raise AArch64EmitError {
  let reg = fn(index) {
    allocation.operand_location(instruction, index).unwrap()
  }
  let mut metadata_offset = buffer.position()
  match function.instruction(instruction).unwrap() {
    IncomingReg(ty, _) => emit_move(buffer, ty, reg(1), reg(0))
    IncomingStack(ty, offset) =>
      emit_stack_access(buffer, true, ty, reg(0), frame.frame_size() + offset)
    IncomingCallResult(ty, source) => emit_move(buffer, ty, reg(0), source)
    OutgoingReg(ty, destination) => emit_move(buffer, ty, destination, reg(0))
    KeepAlive(_) => ()
    LoadConstant(width, bits) => emit_constant(buffer, width, reg(0), bits)
    LoadVectorConstant(low, high) =>
      emit_vector_constant(buffer, reg(0), low, high)
    LoadNull(_) => emit_constant(buffer, W64, reg(0), 0UL)
    LoadAddress(address) => {
      let target : @code_object.RelocationTarget = match address {
        Code(symbol) => Code(symbol)
        External(symbol) => External(symbol)
        Data(symbol) => Data(symbol)
      }
      let page_offset = buffer.position()
      buffer.emit_word(0x90000000U | reg_bits(reg(0)))
      buffer.relocations.push(
        @code_object.Relocation::new(page_offset, AArch64Page21, target),
      )
      let add_offset = buffer.position()
      buffer.emit_word(0x91000000U | (reg_bits(reg(0)) << 5) | reg_bits(reg(0)))
      buffer.relocations.push(
        @code_object.Relocation::new(add_offset, AArch64PageOffset12, target),
      )
    }
    StackAddress(object) =>
      match frame.stack_object_offset(object) {
        Some(offset) => emit_stack_address(buffer, reg(0), offset)
        None => raise MissingStackObjectArea
      }
    LoadFloatConstant(ty, bits) => {
      let scratch = @vcode.PhysicalReg::new(16, Int)
      if ty == F32 {
        emit_constant(buffer, W32, scratch, bits)
        buffer.emit_word(
          0x1E270000U | (reg_bits(scratch) << 5) | reg_bits(reg(0)),
        )
      } else if ty == F64 {
        emit_constant(buffer, W64, scratch, bits)
        buffer.emit_word(
          0x9E670000U | (reg_bits(scratch) << 5) | reg_bits(reg(0)),
        )
      } else {
        raise InvalidFloatInstruction
      }
    }
    Move(ty) => emit_move(buffer, ty, reg(1), reg(0))
    CarrierMove(_, to) => emit_move(buffer, to, reg(1), reg(0))
    Select(ty) => {
      buffer.emit_word(0x7100001FU | (reg_bits(reg(0)) << 5))
      let base : UInt = match ty {
        I32 => 0x1A800000U
        I64 | Ptr64 | GcRef64 => 0x9A800000U
        F32 => 0x1E200C00U
        F64 => 0x1E600C00U
        V128 => raise InvalidFloatInstruction
      }
      buffer.emit_word(
        base |
        (reg_bits(reg(2)) << 16) |
        (1U << 12) |
        (reg_bits(reg(1)) << 5) |
        reg_bits(reg(3)),
      )
    }
    VectorSelect => emit_vector_select(buffer, reg(0), reg(1), reg(2), reg(3))
    VectorSplat(lane) => emit_vector_splat(buffer, lane, reg(0), reg(1))
    VectorExtractLane(lane, index, extension) =>
      emit_vector_extract_lane(buffer, lane, index, extension, reg(0), reg(1))
    VectorReplaceLane(lane, index) => {
      if reg(0) != reg(2) {
        raise InvalidVectorInstruction
      }
      emit_vector_replace_lane(buffer, lane, index, reg(1), reg(2))
    }
    VectorShuffle(mask) =>
      emit_vector_shuffle(buffer, mask, reg(0), reg(1), reg(2))
    VectorSwizzle => emit_vector_table_lookup(buffer, reg(0), reg(1), reg(2))
    VectorIntUnary(lane, operation) =>
      emit_vector_int_unary(buffer, lane, operation, reg(0), reg(1))
    VectorIntBinary(lane, operation) =>
      emit_vector_int_binary(buffer, lane, operation, reg(0), reg(1), reg(2))
    VectorIntShift(lane, operation) =>
      emit_vector_int_shift(buffer, lane, operation, reg(0), reg(1), reg(2))
    VectorIntCompare(lane, comparison) =>
      emit_vector_int_compare(buffer, lane, comparison, reg(0), reg(1), reg(2))
    VectorBitwise(operation) =>
      match operation {
        Not => emit_vector_bitwise(buffer, Not, reg(0), reg(0), reg(0), reg(1))
        And | Or | Xor | AndNot =>
          emit_vector_bitwise(buffer, operation, reg(0), reg(1), reg(1), reg(2))
        BitSelect =>
          emit_vector_bitwise(buffer, BitSelect, reg(0), reg(1), reg(2), reg(3))
      }
    IntUnary(width, operation) =>
      buffer.emit_word(encode_int_unary(width, operation, reg(1), reg(0)))
    IntBinary(width, operation) =>
      buffer.emit_word(
        encode_int_binary(width, operation, reg(2), reg(0), reg(1)),
      )
    PopulationCount(width) => {
      let scratch = @vcode.PhysicalReg::new(16, FpVector)
      let move_to_vector = if width == W32 { 0x1E270000U } else { 0x9E670000U }
      buffer.emit_word(
        move_to_vector | (reg_bits(reg(0)) << 5) | reg_bits(scratch),
      )
      buffer.emit_word(
        0x0E205800U | (reg_bits(scratch) << 5) | reg_bits(scratch),
      )
      buffer.emit_word(
        0x0E31B800U | (reg_bits(scratch) << 5) | reg_bits(scratch),
      )
      buffer.emit_word(
        0x1E260000U | (reg_bits(scratch) << 5) | reg_bits(reg(1)),
      )
    }
    IntHighMultiply(width, signedness) =>
      if width == W64 {
        let base = if signedness == Signed { 0x9B407C00U } else { 0x9BC07C00U }
        buffer.emit_word(encode_three_register(base, reg(2), reg(0), reg(1)))
      } else {
        let scratch = @vcode.PhysicalReg::new(16, Int)
        let base = if signedness == Signed { 0x9B207C00U } else { 0x9BA07C00U }
        buffer.emit_word(encode_three_register(base, scratch, reg(0), reg(1)))
        buffer.emit_word(
          0xD360FC00U | (reg_bits(scratch) << 5) | reg_bits(reg(2)),
        )
      }
    IntWithOverflow(width, operation) =>
      emit_int_with_overflow(
        buffer,
        width,
        operation,
        reg(0),
        reg(1),
        reg(2),
        reg(3),
      )
    IntRemainder(width, signedness) => {
      let quotient = @vcode.PhysicalReg::new(16, Int)
      let division = if signedness == Signed { Sdiv } else { Udiv }
      buffer.emit_word(
        encode_int_binary(width, division, quotient, reg(0), reg(1)),
      )
      let base = if width == W32 { 0x1B008000U } else { 0x9B008000U }
      buffer.emit_word(
        base |
        (reg_bits(reg(1)) << 16) |
        (reg_bits(reg(0)) << 10) |
        (reg_bits(quotient) << 5) |
        reg_bits(reg(2)),
      )
    }
    TrapIfZero(width) => {
      let base = if width == W32 { 0x35000000U } else { 0xB5000000U }
      buffer.emit_word(base | (2U << 5) | reg_bits(reg(0)))
      metadata_offset = buffer.position()
      buffer.emit_word(0xD4200000U | (AARCH64_DIVISION_BY_ZERO_BRK << 5))
    }
    TrapIfSignedDivOverflow(width) => {
      let adds_base = if width == W32 { 0x31000000U } else { 0xB1000000U }
      buffer.emit_word(adds_base | (1U << 10) | (reg_bits(reg(1)) << 5) | 31U)
      let ccmp_base = if width == W32 { 0x7A400800U } else { 0xFA400800U }
      buffer.emit_word(ccmp_base | (1U << 16) | (reg_bits(reg(0)) << 5))
      buffer.emit_word(0x54000000U | (2U << 5) | 7U)
      metadata_offset = buffer.position()
      buffer.emit_word(0xD4200000U | (AARCH64_INTEGER_OVERFLOW_BRK << 5))
    }
    CompareSet(width, condition) => {
      let compare_base = if width == W32 { 0x6B00001FU } else { 0xEB00001FU }
      buffer.emit_word(
        compare_base | (reg_bits(reg(1)) << 16) | (reg_bits(reg(0)) << 5),
      )
      let inverse = condition_code(condition) ^ 1U
      buffer.emit_word(0x9A9F07E0U | (inverse << 12) | reg_bits(reg(2)))
    }
    ReferenceCompareSet(_, condition) => {
      buffer.emit_word(
        0xEB00001FU | (reg_bits(reg(1)) << 16) | (reg_bits(reg(0)) << 5),
      )
      let inverse = condition_code(condition) ^ 1U
      buffer.emit_word(0x9A9F07E0U | (inverse << 12) | reg_bits(reg(2)))
    }
    FloatUnary(ty, operation) => {
      guard float_unary_base(ty, operation) is Some(base) else {
        raise InvalidFloatInstruction
      }
      buffer.emit_word(base | (reg_bits(reg(0)) << 5) | reg_bits(reg(1)))
    }
    FloatBinary(ty, operation) =>
      if operation == CopySign {
        emit_float_copy_sign(buffer, ty, reg(0), reg(1), reg(2))
      } else {
        guard float_binary_base(ty, operation) is Some(base) else {
          raise InvalidFloatInstruction
        }
        buffer.emit_word(
          base |
          (reg_bits(reg(1)) << 16) |
          (reg_bits(reg(0)) << 5) |
          reg_bits(reg(2)),
        )
      }
    FloatTernary(ty, operation) => {
      guard float_ternary_base(ty, operation) is Some(base) else {
        raise InvalidFloatInstruction
      }
      buffer.emit_word(
        base |
        (reg_bits(reg(1)) << 16) |
        (reg_bits(reg(2)) << 10) |
        (reg_bits(reg(0)) << 5) |
        reg_bits(reg(3)),
      )
    }
    FloatCompareSet(ty, condition) => {
      let base = if ty == F32 {
        0x1E202000U
      } else if ty == F64 {
        0x1E602000U
      } else {
        raise InvalidFloatInstruction
      }
      buffer.emit_word(
        base | (reg_bits(reg(1)) << 16) | (reg_bits(reg(0)) << 5),
      )
      let inverse = float_condition_code(condition) ^ 1U
      buffer.emit_word(0x9A9F07E0U | (inverse << 12) | reg_bits(reg(2)))
    }
    TrapIfFloat(ty, condition) => {
      let base = if ty == F32 {
        0x1E202000U
      } else if ty == F64 {
        0x1E602000U
      } else {
        raise InvalidFloatInstruction
      }
      let right = if condition == Unordered { reg(0) } else { reg(1) }
      buffer.emit_word(base | (reg_bits(right) << 16) | (reg_bits(reg(0)) << 5))
      let skip = float_trap_condition_code(condition) ^ 1U
      buffer.emit_word(0x54000000U | (2U << 5) | skip)
      metadata_offset = buffer.position()
      buffer.emit_word(0xD4200000U | (AARCH64_INVALID_CONVERSION_BRK << 5))
    }
    Convert(conversion) => emit_conversion(buffer, conversion, reg(0), reg(1))
    AddAddress =>
      buffer.emit_word(
        encode_three_register(0x8B000000U, reg(2), reg(0), reg(1)),
      )
    ScalarLoad(width, extension, result_type, offset) => {
      guard scalar_load_base(width, extension, result_type) is Some(base) else {
        raise InvalidScalarMemoryAccess
      }
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(
        base | (immediate << 10) | (reg_bits(address) << 5) | reg_bits(reg(1)),
      )
    }
    ScalarStore(width, value_type, offset) => {
      guard scalar_store_base(width, value_type) is Some(base) else {
        raise InvalidScalarMemoryAccess
      }
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(
        base | (immediate << 10) | (reg_bits(address) << 5) | reg_bits(reg(1)),
      )
    }
    PlatformCall(target, signature) => {
      let layout = platform_call_layout(signature.params)
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        layout.arguments,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(0x94000000U)
      buffer.relocations.push(
        @code_object.Relocation::new(
          metadata_offset,
          AArch64Call26,
          External(target),
        ),
      )
    }
    InternalCall(target, signature, plan) => {
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(0x94000000U)
      buffer.relocations.push(
        @code_object.Relocation::new(
          metadata_offset,
          AArch64Call26,
          Code(target),
        ),
      )
    }
    InternalCallIndirect(signature, plan) => {
      let callee_register = @vcode.PhysicalReg::new(17, Int)
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        operand_start=1,
        callee=(0, callee_register),
      )
      metadata_offset = buffer.position()
      buffer.emit_word(0xD63F0000U | (reg_bits(callee_register) << 5))
    }
    TailCallDirect(target, signature, plan) => {
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        stack_base=frame.frame_size(),
      )
      emit_epilogue(buffer, frame)
      metadata_offset = buffer.position()
      buffer.emit_word(0x14000000U)
      buffer.relocations.push(
        @code_object.Relocation::new(
          metadata_offset,
          AArch64Jump26,
          Code(target),
        ),
      )
    }
    TailCallIndirect(signature, plan) => {
      let callee_register = @vcode.PhysicalReg::new(17, Int)
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        operand_start=1,
        stack_base=frame.frame_size(),
        callee=(0, callee_register),
      )
      emit_epilogue(buffer, frame)
      metadata_offset = buffer.position()
      buffer.emit_word(0xD61F0000U | (reg_bits(callee_register) << 5))
    }
    Jump => {
      emit_edge_moves(buffer, function, allocation, frame, block, 0)
      buffer.emit_branch(
        function.instruction_successor_at(instruction, 0).unwrap().target,
        26,
        0x14000000U,
      )
    }
    BranchNonZero32 =>
      emit_conditional_edges(
        buffer,
        function,
        allocation,
        frame,
        block,
        instruction,
        reg(0),
      )
    Return => {
      emit_epilogue(buffer, frame)
      buffer.emit_word(0xD65F03C0U)
    }
  }
  metadata_offset
}

///|
fn patch_branches(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  block_offsets : Array[Int],
) -> Unit raise AArch64EmitError {
  for fixup in buffer.fixups {
    let block_index = function.block_index(fixup.target).unwrap()
    let target = block_offsets[block_index]
    if target < 0 {
      raise BranchTargetMissing(block=fixup.target)
    }
    patch_relative_branch(buffer, fixup.offset, target, fixup.bits)
  }
}

///|
fn patch_relative_branch(
  buffer : CodeBuffer,
  offset : Int,
  target : Int,
  bits : Int,
) -> Unit raise AArch64EmitError {
  let delta = target - offset
  let words = delta / 4
  let minimum = -(1 << (bits - 1))
  let maximum = (1 << (bits - 1)) - 1
  if delta % 4 != 0 || words < minimum || words > maximum {
    raise BranchOutOfRange(offset=delta, bits~)
  }
  let base = if bits == 26 {
    0x14000000U
  } else {
    0x35000000U | (buffer.code[offset].to_uint() & 31U)
  }
  let mask = if bits == 26 { 0x03FFFFFFU } else { 0x7FFFFU }
  buffer.patch_word(
    offset,
    base |
    ((words.reinterpret_as_uint() & mask) << (if bits == 19 { 5 } else { 0 })),
  )
}

///|
pub fn emit(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
) -> @code_object.UnlinkedCodeObject raise AArch64EmitError {
  verify_frame(function, allocation, frame) catch {
    error => raise InvalidFrame(cause=error)
  }
  let buffer = CodeBuffer::new()
  let block_offsets = Array::make(function.block_count(), -1)
  let edits = allocation.edits()
  let sources : Array[@code_object.SourceSite] = []
  let traps : Array[@code_object.TrapSite] = []
  let safepoints : Array[@code_object.SafepointSite] = []
  emit_prologue(buffer, frame)
  for block in function.layout() {
    block_offsets[function.block_index(block).unwrap()] = buffer.position()
    for instruction in function.block_body(block) {
      emit_edits_at(buffer, function, frame, edits, instruction, Before)
      let instruction_offset = emit_instruction(
        buffer, function, allocation, frame, block, instruction,
      )
      record_instruction_metadata(
        buffer, function, allocation, frame, instruction, instruction_offset, sources,
        traps, safepoints,
      )
      emit_edits_at(buffer, function, frame, edits, instruction, After)
    }
    let terminator = function.block_terminator(block).unwrap()
    emit_edits_at(buffer, function, frame, edits, terminator, Before)
    let terminator_offset = emit_instruction(
      buffer, function, allocation, frame, block, terminator,
    )
    record_instruction_metadata(
      buffer, function, allocation, frame, terminator, terminator_offset, sources,
      traps, safepoints,
    )
    emit_edits_at(buffer, function, frame, edits, terminator, After)
  }
  patch_branches(buffer, function, block_offsets)
  let relocations = buffer.relocations
  @code_object.build(
    AArch64,
    buffer.code,
    relocations~,
    sources~,
    traps~,
    safepoints~,
  ) catch {
    error => raise InvalidCodeObject(cause=error)
  }
}
