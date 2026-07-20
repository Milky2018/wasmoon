///|
const AARCH64_DIVISION_BY_ZERO_BRK : UInt = 4U

///|
const AARCH64_INTEGER_OVERFLOW_BRK : UInt = 5U

///|
const AARCH64_INVALID_CONVERSION_BRK : UInt = 3U

///|
fn trap_brk_payload(reason : @semantic.TrapReason) -> UInt {
  match reason {
    Unreachable => 0U
    MemoryOutOfBounds | TableOutOfBounds => 1U
    IndirectCallTypeMismatch => 2U
    InvalidConversionToInteger => 3U
    IntegerDivisionByZero => 4U
    IntegerOverflow => 5U
    NullReference | UnalignedAtomic | UnsupportedOperation | StackOverflow => 6U
    User(payload) => payload.reinterpret_as_uint() & 0xFFFFU
  }
}

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
  MissingResultArea
  UnexpectedStackOperand(instruction~ : @vcode.Instruction, operand~ : Int)
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
fn emit_result_area_access(
  buffer : CodeBuffer,
  load : Bool,
  ty : @semantic.ValueType,
  address~ : @vcode.PhysicalReg,
  value~ : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise AArch64EmitError {
  let width : @semantic.AccessWidth = match ty {
    I32 | F32 => W32
    I64 | Ptr64 | GcRef64 | F64 => W64
    V128 => W128
  }
  let (load_base, store_base) = match ty {
    I32 => (0xB9400000U, 0xB9000000U)
    I64 | Ptr64 | GcRef64 => (0xF9400000U, 0xF9000000U)
    F32 => (0xBD400000U, 0xBD000000U)
    F64 => (0xFD400000U, 0xFD000000U)
    V128 => (0x3DC00000U, 0x3D800000U)
  }
  let (base, immediate) = scalar_memory_address(
    buffer,
    address,
    width,
    offset.to_uint64(),
  )
  buffer.emit_word(
    (if load { load_base } else { store_base }) |
    (immediate << 10) |
    (reg_bits(base) << 5) |
    reg_bits(value),
  )
}

///|
fn result_area_register(plan : InternalCallPlan) -> @vcode.PhysicalReg? {
  for result in plan.results {
    if result is CallResultArea(_, reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn scalar_memory_scale(width : @semantic.AccessWidth) -> UInt64? {
  match width {
    W8 => Some(1UL)
    W16 => Some(2UL)
    W32 => Some(4UL)
    W64 => Some(8UL)
    W128 => Some(16UL)
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
fn vector_structure_address(
  buffer : CodeBuffer,
  address : @vcode.PhysicalReg,
  offset : UInt64,
) -> @vcode.PhysicalReg {
  if offset == 0UL {
    return address
  }
  let scratch = @vcode.PhysicalReg::new(16, Int)
  emit_constant(buffer, W64, scratch, offset)
  buffer.emit_word(
    encode_three_register(0x8B000000U, scratch, address, scratch),
  )
  scratch
}

///|
fn vector_lane_memory_word(
  load : Bool,
  lane : @semantic.VectorLane,
  index : Int,
  address : @vcode.PhysicalReg,
  vector : @vcode.PhysicalReg,
) -> UInt raise AArch64EmitError {
  let load_bit = if load { 0x00400000U } else { 0U }
  let (base, lane_bits) = match lane {
    I8x16 =>
      (
        0x0D000000U,
        ((index >> 3).reinterpret_as_uint() << 30) |
        (((index >> 2) & 1).reinterpret_as_uint() << 12) |
        ((index & 3).reinterpret_as_uint() << 10),
      )
    I16x8 =>
      (
        0x0D004000U,
        ((index >> 2).reinterpret_as_uint() << 30) |
        (((index >> 1) & 1).reinterpret_as_uint() << 12) |
        ((index & 1).reinterpret_as_uint() << 11),
      )
    I32x4 | F32x4 =>
      (
        0x0D008000U,
        ((index >> 1).reinterpret_as_uint() << 30) |
        ((index & 1).reinterpret_as_uint() << 12),
      )
    I64x2 | F64x2 => (0x0D008400U, (index & 1).reinterpret_as_uint() << 30)
  }
  let lane_count = match lane {
    I8x16 => 16
    I16x8 => 8
    I32x4 | F32x4 => 4
    I64x2 | F64x2 => 2
  }
  if index < 0 || index >= lane_count {
    raise InvalidVectorInstruction
  }
  base | load_bit | lane_bits | (reg_bits(address) << 5) | reg_bits(vector)
}

///|
fn vector_splat_load_base(lane : @semantic.VectorLane) -> UInt {
  match lane {
    I8x16 => 0x4D40C000U
    I16x8 => 0x4D40C400U
    I32x4 | F32x4 => 0x4D40C800U
    I64x2 | F64x2 => 0x4D40CC00U
  }
}

///|
fn atomic_load_base(width : @semantic.AccessWidth, exclusive : Bool) -> UInt {
  match (width, exclusive) {
    (W8, false) => 0x08DFFC00U
    (W16, false) => 0x48DFFC00U
    (W32, false) => 0x88DFFC00U
    (W64, false) => 0xC8DFFC00U
    (W8, true) => 0x085FFC00U
    (W16, true) => 0x485FFC00U
    (W32, true) => 0x885FFC00U
    (W64, true) => 0xC85FFC00U
    (W128, _) => 0U
  }
}

///|
fn atomic_store_base(width : @semantic.AccessWidth, exclusive : Bool) -> UInt {
  match (width, exclusive) {
    (W8, false) => 0x089FFC00U
    (W16, false) => 0x489FFC00U
    (W32, false) => 0x889FFC00U
    (W64, false) => 0xC89FFC00U
    (W8, true) => 0x0800FC00U
    (W16, true) => 0x4800FC00U
    (W32, true) => 0x8800FC00U
    (W64, true) => 0xC800FC00U
    (W128, _) => 0U
  }
}

///|
fn atomic_operation_width(width : @semantic.AccessWidth) -> GprWidth {
  if width == W64 {
    W64
  } else {
    W32
  }
}

///|
fn emit_atomic_rmw(
  buffer : CodeBuffer,
  width : @semantic.AccessWidth,
  operation : @semantic.AtomicRmwOp,
  address : @vcode.PhysicalReg,
  value : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
) -> Int raise AArch64EmitError {
  if width == W128 {
    raise InvalidScalarMemoryAccess
  }
  let scratch = @vcode.PhysicalReg::new(16, Int)
  let status = @vcode.PhysicalReg::new(17, Int)
  let loop_offset = buffer.position()
  buffer.emit_word(
    atomic_load_base(width, true) | (reg_bits(address) << 5) | reg_bits(result),
  )
  let operation_width = atomic_operation_width(width)
  match operation {
    Add =>
      buffer.emit_word(
        encode_int_binary(operation_width, Add, scratch, result, value),
      )
    Sub =>
      buffer.emit_word(
        encode_int_binary(operation_width, Sub, scratch, result, value),
      )
    And =>
      buffer.emit_word(
        encode_int_binary(operation_width, And, scratch, result, value),
      )
    Or =>
      buffer.emit_word(
        encode_int_binary(operation_width, Orr, scratch, result, value),
      )
    Xor =>
      buffer.emit_word(
        encode_int_binary(operation_width, Eor, scratch, result, value),
      )
    Exchange =>
      emit_move(
        buffer,
        if operation_width == W64 {
          I64
        } else {
          I32
        },
        scratch,
        value,
      )
  }
  buffer.emit_word(
    atomic_store_base(width, true) |
    (reg_bits(status) << 16) |
    (reg_bits(address) << 5) |
    reg_bits(scratch),
  )
  let retry = buffer.position()
  buffer.emit_word(0x35000000U | reg_bits(status))
  patch_relative_branch(buffer, retry, loop_offset, 19)
  loop_offset
}

///|
fn emit_atomic_compare_exchange(
  buffer : CodeBuffer,
  width : @semantic.AccessWidth,
  address : @vcode.PhysicalReg,
  expected : @vcode.PhysicalReg,
  replacement : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
) -> Int raise AArch64EmitError {
  if width == W128 {
    raise InvalidScalarMemoryAccess
  }
  let expected_value = if width == W8 || width == W16 {
    let scratch = @vcode.PhysicalReg::new(16, Int)
    let base = if width == W8 { 0x53001C00U } else { 0x53003C00U }
    buffer.emit_word(base | (reg_bits(expected) << 5) | reg_bits(scratch))
    scratch
  } else {
    expected
  }
  let status = @vcode.PhysicalReg::new(17, Int)
  let loop_offset = buffer.position()
  buffer.emit_word(
    atomic_load_base(width, true) | (reg_bits(address) << 5) | reg_bits(result),
  )
  let compare_base = if width == W64 { 0xEB00001FU } else { 0x6B00001FU }
  buffer.emit_word(
    compare_base | (reg_bits(expected_value) << 16) | (reg_bits(result) << 5),
  )
  buffer.emit_word(0x54000000U | (3U << 5))
  buffer.emit_word(0xD5033F5FU)
  buffer.emit_word(0x14000000U | 3U)
  buffer.emit_word(
    atomic_store_base(width, true) |
    (reg_bits(status) << 16) |
    (reg_bits(address) << 5) |
    reg_bits(replacement),
  )
  let retry = buffer.position()
  buffer.emit_word(0x35000000U | reg_bits(status))
  patch_relative_branch(buffer, retry, loop_offset, 19)
  loop_offset
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
  unwind? : Array[@code_object.UnwindDirective],
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
    if subtract {
      buffer.emit_word(base | (1U << 22) | (1U << 10) | (31U << 5) | 31U)
      if unwind is Some(directives) {
        directives.push(
          @code_object.UnwindDirective::new(
            buffer.position(),
            StackAlloc(size=4096),
          ),
        )
      }
      emit_stack_access(buffer, true, I64, @vcode.PhysicalReg::new(16, Int), 0)
      remaining -= 4096
    } else {
      let pages = Int::min(remaining / 4096, 4095)
      buffer.emit_word(
        base |
        (1U << 22) |
        (pages.reinterpret_as_uint() << 10) |
        (31U << 5) |
        31U,
      )
      remaining -= pages * 4096
    }
  }
  if remaining > 0 {
    buffer.emit_word(
      base | (remaining.reinterpret_as_uint() << 10) | (31U << 5) | 31U,
    )
    if subtract && unwind is Some(directives) {
      directives.push(
        @code_object.UnwindDirective::new(
          buffer.position(),
          StackAlloc(size=remaining),
        ),
      )
    }
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
    PopulationCount =>
      match lane {
        I8x16 => 0x4E205800U
        I16x8 | I32x4 | I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
      }
    ExtendAddPairwise(signedness) => {
      let signed = signedness is Signed
      match lane {
        I16x8 => if signed { 0x4E202800U } else { 0x6E202800U }
        I32x4 => if signed { 0x4E602800U } else { 0x6E602800U }
        I64x2 => if signed { 0x4EA02800U } else { 0x6EA02800U }
        I8x16 | F32x4 | F64x2 => raise InvalidVectorInstruction
      }
    }
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
  if lane == I64x2 && operation is Min(signedness) {
    let mask = @vcode.PhysicalReg::new(16, FpVector)
    emit_vector_int_compare(
      buffer,
      I64x2,
      GreaterThan(signedness),
      left,
      right,
      mask,
    )
    emit_vector_bitwise(buffer, BitSelect, right, left, mask, destination)
    return
  }
  if lane == I64x2 && operation is Max(signedness) {
    let mask = @vcode.PhysicalReg::new(16, FpVector)
    emit_vector_int_compare(
      buffer,
      I64x2,
      GreaterThan(signedness),
      left,
      right,
      mask,
    )
    emit_vector_bitwise(buffer, BitSelect, left, right, mask, destination)
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
    AverageUnsigned =>
      match lane {
        I8x16 => 0x6E201400U
        I16x8 => 0x6E601400U
        I32x4 | I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
      }
    ExtendMultiply(half, signedness) => {
      let high = half is High
      let signed = signedness is Signed
      let prefix = match (high, signed) {
        (false, true) => 0x0E000000U
        (false, false) => 0x2E000000U
        (true, true) => 0x4E000000U
        (true, false) => 0x6E000000U
      }
      let body = match lane {
        I16x8 => 0x0020C000U
        I32x4 => 0x0060C000U
        I64x2 => 0x00A0C000U
        I8x16 | F32x4 | F64x2 => raise InvalidVectorInstruction
      }
      prefix | body
    }
    Dot16To32Signed => {
      if lane != I32x4 {
        raise InvalidVectorInstruction
      }
      let low = @vcode.PhysicalReg::new(16, FpVector)
      let high = @vcode.PhysicalReg::new(17, FpVector)
      buffer.emit_word(
        0x0E60C000U |
        (reg_bits(right) << 16) |
        (reg_bits(left) << 5) |
        reg_bits(low),
      )
      buffer.emit_word(
        0x4E60C000U |
        (reg_bits(right) << 16) |
        (reg_bits(left) << 5) |
        reg_bits(high),
      )
      buffer.emit_word(
        0x4EA0BC00U |
        (reg_bits(high) << 16) |
        (reg_bits(low) << 5) |
        reg_bits(destination),
      )
      return
    }
    Q15MultiplyRoundedSaturating => {
      if lane != I16x8 {
        raise InvalidVectorInstruction
      }
      0x6E60B400U
    }
    Min(signedness) =>
      if signedness is Signed {
        match lane {
          I8x16 => 0x4E206C00U
          I16x8 => 0x4E606C00U
          I32x4 => 0x4EA06C00U
          I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
        }
      } else {
        match lane {
          I8x16 => 0x6E206C00U
          I16x8 => 0x6E606C00U
          I32x4 => 0x6EA06C00U
          I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
        }
      }
    Max(signedness) =>
      if signedness is Signed {
        match lane {
          I8x16 => 0x4E206400U
          I16x8 => 0x4E606400U
          I32x4 => 0x4EA06400U
          I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
        }
      } else {
        match lane {
          I8x16 => 0x6E206400U
          I16x8 => 0x6E606400U
          I32x4 => 0x6EA06400U
          I64x2 | F32x4 | F64x2 => raise InvalidVectorInstruction
        }
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
fn emit_vector_extension(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  high : Bool,
  signedness : @semantic.Signedness,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let signed = signedness is Signed
  let prefix = match (high, signed) {
    (false, true) => 0x0F000000U
    (false, false) => 0x2F000000U
    (true, true) => 0x4F000000U
    (true, false) => 0x6F000000U
  }
  let body = match lane {
    I16x8 => 0x0008A400U
    I32x4 => 0x0010A400U
    I64x2 => 0x0020A400U
    I8x16 | F32x4 | F64x2 => raise InvalidVectorInstruction
  }
  buffer.emit_word(
    prefix | body | (reg_bits(source) << 5) | reg_bits(destination),
  )
}

///|
fn emit_vector_narrow(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  signedness : @semantic.Signedness,
  low : @vcode.PhysicalReg,
  high : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let high_source = if destination == high {
    let scratch = @vcode.PhysicalReg::new(16, FpVector)
    emit_move(buffer, V128, scratch, high)
    scratch
  } else {
    high
  }
  let (low_base, high_base) = match (lane, signedness) {
    (I8x16, Signed) => (0x0E214800U, 0x4E214800U)
    (I8x16, Unsigned) => (0x2E212800U, 0x6E212800U)
    (I16x8, Signed) => (0x0E614800U, 0x4E614800U)
    (I16x8, Unsigned) => (0x2E612800U, 0x6E612800U)
    (I32x4 | I64x2 | F32x4 | F64x2, _) => raise InvalidVectorInstruction
  }
  buffer.emit_word(low_base | (reg_bits(low) << 5) | reg_bits(destination))
  buffer.emit_word(
    high_base | (reg_bits(high_source) << 5) | reg_bits(destination),
  )
}

///|
fn emit_vector_conversion(
  buffer : CodeBuffer,
  conversion : AArch64VectorConversion,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let scratch = @vcode.PhysicalReg::new(16, FpVector)
  match conversion {
    FloatToInt(F32x4, signedness) => {
      let base = if signedness is Signed { 0x4EA1B800U } else { 0x6EA1B800U }
      buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
    }
    FloatToInt(F64x2, signedness) => {
      let convert = if signedness is Signed { 0x4EE1B800U } else { 0x6EE1B800U }
      buffer.emit_word(convert | (reg_bits(source) << 5) | reg_bits(scratch))
      let narrow = if signedness is Signed { 0x0EA14800U } else { 0x2EA14800U }
      buffer.emit_word(
        narrow | (reg_bits(scratch) << 5) | reg_bits(destination),
      )
    }
    IntToFloat(F32x4, signedness) => {
      let base = if signedness is Signed { 0x4E21D800U } else { 0x6E21D800U }
      buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
    }
    IntToFloat(F64x2, signedness) => {
      let extend_base = if signedness is Signed {
        0x0F20A400U
      } else {
        0x2F20A400U
      }
      buffer.emit_word(
        extend_base | (reg_bits(source) << 5) | reg_bits(scratch),
      )
      let convert = if signedness is Signed { 0x4E61D800U } else { 0x6E61D800U }
      buffer.emit_word(
        convert | (reg_bits(scratch) << 5) | reg_bits(destination),
      )
    }
    PromoteLowF32x4 =>
      buffer.emit_word(
        0x0E617800U | (reg_bits(source) << 5) | reg_bits(destination),
      )
    DemoteZeroF64x2 =>
      buffer.emit_word(
        0x0E616800U | (reg_bits(source) << 5) | reg_bits(destination),
      )
    ExtendLow(_, _) | ExtendHigh(_, _) | Narrow(_, _) =>
      raise InvalidVectorInstruction
    FloatToInt(I8x16 | I16x8 | I32x4 | I64x2, _)
    | IntToFloat(I8x16 | I16x8 | I32x4 | I64x2, _) =>
      raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_predicate(
  buffer : CodeBuffer,
  predicate : AArch64VectorPredicate,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  if predicate is BitMask(lane) {
    emit_vector_bitmask(buffer, lane, source, destination)
    return
  }
  let vector_scratch = @vcode.PhysicalReg::new(16, FpVector)
  let int_scratch = @vcode.PhysicalReg::new(16, Int)
  let reduction_base = match predicate {
    AnyTrue => 0x6E30A800U
    AllTrue(I8x16) => 0x6E31A800U
    AllTrue(I16x8) => 0x6E71A800U
    AllTrue(I32x4) => 0x6EB1A800U
    AllTrue(I64x2) => {
      let second = @vcode.PhysicalReg::new(17, Int)
      emit_vector_extract_lane(buffer, I64x2, 0, None, source, int_scratch)
      emit_vector_extract_lane(buffer, I64x2, 1, None, source, second)
      buffer.emit_word(0xF100001FU | (reg_bits(int_scratch) << 5))
      buffer.emit_word(
        0xFA400800U | (condition_code(Ne) << 12) | (reg_bits(second) << 5) | 4U,
      )
      emit_overflow_flag(buffer, destination, condition_code(Ne))
      return
    }
    AllTrue(F32x4 | F64x2) => raise InvalidVectorInstruction
    BitMask(_) => raise InvalidVectorInstruction
  }
  buffer.emit_word(
    reduction_base | (reg_bits(source) << 5) | reg_bits(vector_scratch),
  )
  buffer.emit_word(
    0x9E660000U | (reg_bits(vector_scratch) << 5) | reg_bits(int_scratch),
  )
  buffer.emit_word(0xF100001FU | (reg_bits(int_scratch) << 5))
  emit_overflow_flag(buffer, destination, condition_code(Ne))
}

///|
fn emit_vector_bitmask(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  if lane == I8x16 {
    let weights = @vcode.PhysicalReg::new(16, FpVector)
    let work = @vcode.PhysicalReg::new(17, FpVector)
    let low = @vcode.PhysicalReg::new(16, Int)
    let high = @vcode.PhysicalReg::new(17, Int)
    buffer.emit_word(0x6F090400U | (reg_bits(source) << 5) | reg_bits(work))
    emit_constant(buffer, W64, low, 0x8040201008040201UL)
    buffer.emit_word(0x9E670000U | (reg_bits(low) << 5) | reg_bits(weights))
    buffer.emit_word(0x4E080400U | (reg_bits(weights) << 5) | reg_bits(weights))
    buffer.emit_word(
      0x4E209C00U |
      (reg_bits(weights) << 16) |
      (reg_bits(work) << 5) |
      reg_bits(work),
    )
    buffer.emit_word(0x6E202800U | (reg_bits(work) << 5) | reg_bits(work))
    buffer.emit_word(0x6E602800U | (reg_bits(work) << 5) | reg_bits(work))
    buffer.emit_word(0x6EA02800U | (reg_bits(work) << 5) | reg_bits(work))
    emit_vector_extract_lane(buffer, I64x2, 0, None, work, low)
    emit_vector_extract_lane(buffer, I64x2, 1, None, work, high)
    buffer.emit_word(
      0x2A000000U |
      (reg_bits(high) << 16) |
      (8U << 10) |
      (reg_bits(low) << 5) |
      reg_bits(destination),
    )
    return
  }
  let (lane_count, sign_shift, lsr_base) = match lane {
    I16x8 => (8, 15U, 0x53007C00U)
    I32x4 => (4, 31U, 0x53007C00U)
    I64x2 => (2, 63U, 0xD340FC00U)
    I8x16 | F32x4 | F64x2 => raise InvalidVectorInstruction
  }
  let scratch = @vcode.PhysicalReg::new(16, Int)
  for index in 0..<lane_count {
    let lane_result = if index == 0 { destination } else { scratch }
    emit_vector_extract_lane(buffer, lane, index, None, source, lane_result)
    buffer.emit_word(
      lsr_base |
      (sign_shift << 16) |
      (reg_bits(lane_result) << 5) |
      reg_bits(lane_result),
    )
    if index > 0 {
      buffer.emit_word(
        0x2A000000U |
        (reg_bits(scratch) << 16) |
        (index.reinterpret_as_uint() << 10) |
        (reg_bits(destination) << 5) |
        reg_bits(destination),
      )
    }
  }
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
fn vector_float_lane_encoding(
  lane : @semantic.VectorLane,
  f32_base : UInt,
  f64_base : UInt,
) -> UInt raise AArch64EmitError {
  match lane {
    F32x4 => f32_base
    F64x2 => f64_base
    I8x16 | I16x8 | I32x4 | I64x2 => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_float_unary(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : @semantic.VectorFloatUnaryOp,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let base = match operation {
    Absolute => vector_float_lane_encoding(lane, 0x4EA0F800U, 0x4EE0F800U)
    Negate => vector_float_lane_encoding(lane, 0x6EA0F800U, 0x6EE0F800U)
    SquareRoot => vector_float_lane_encoding(lane, 0x6EA1F800U, 0x6EE1F800U)
    Ceil => vector_float_lane_encoding(lane, 0x4EA18800U, 0x4EE18800U)
    Floor => vector_float_lane_encoding(lane, 0x4E219800U, 0x4E619800U)
    Truncate => vector_float_lane_encoding(lane, 0x4EA19800U, 0x4EE19800U)
    Nearest => vector_float_lane_encoding(lane, 0x4E218800U, 0x4E618800U)
  }
  buffer.emit_word(base | (reg_bits(source) << 5) | reg_bits(destination))
}

///|
fn emit_vector_float_binary(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : @semantic.VectorFloatBinaryOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let base = match operation {
    Add => Some(vector_float_lane_encoding(lane, 0x4E20D400U, 0x4E60D400U))
    Sub => Some(vector_float_lane_encoding(lane, 0x4EA0D400U, 0x4EE0D400U))
    Mul => Some(vector_float_lane_encoding(lane, 0x6E20DC00U, 0x6E60DC00U))
    Div => Some(vector_float_lane_encoding(lane, 0x6E20FC00U, 0x6E60FC00U))
    Min => Some(vector_float_lane_encoding(lane, 0x4EA0F400U, 0x4EE0F400U))
    Max => Some(vector_float_lane_encoding(lane, 0x4E20F400U, 0x4E60F400U))
    PseudoMin | PseudoMax => None
  }
  if base is Some(base) {
    emit_vector_binary(buffer, base, left, right, destination)
    return
  }
  let mask = @vcode.PhysicalReg::new(16, FpVector)
  let (first, second) = match operation {
    PseudoMin => (left, right)
    PseudoMax => (right, left)
    Add | Sub | Mul | Div | Min | Max => raise InvalidVectorInstruction
  }
  let compare_base = vector_float_lane_encoding(lane, 0x6EA0E400U, 0x6EE0E400U)
  emit_vector_binary(buffer, compare_base, first, second, mask)
  emit_vector_binary(buffer, 0x6E601C00U, right, left, mask)
  emit_move(buffer, V128, destination, mask)
}

///|
fn emit_vector_float_compare(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  comparison : @semantic.VectorFloatComparison,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let (base, first, second, invert) = match comparison {
    Equal => (0x4E20E400U, left, right, false)
    NotEqual => (0x4E20E400U, left, right, true)
    LessThan => (0x6EA0E400U, right, left, false)
    LessOrEqual => (0x6E20E400U, right, left, false)
    GreaterThan => (0x6EA0E400U, left, right, false)
    GreaterOrEqual => (0x6E20E400U, left, right, false)
  }
  emit_vector_binary(
    buffer,
    vector_float_lane_encoding(lane, base, base | 0x00400000U),
    first,
    second,
    destination,
  )
  if invert {
    buffer.emit_word(
      0x6E205800U | (reg_bits(destination) << 5) | reg_bits(destination),
    )
  }
}

///|
fn emit_vector_float_ternary(
  buffer : CodeBuffer,
  lane : @semantic.VectorLane,
  operation : @semantic.FloatTernaryOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  addend : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise AArch64EmitError {
  let left_copy = @vcode.PhysicalReg::new(16, FpVector)
  let right_copy = @vcode.PhysicalReg::new(17, FpVector)
  emit_move(buffer, V128, left_copy, left)
  emit_move(buffer, V128, right_copy, right)
  emit_move(buffer, V128, destination, addend)
  let subtract_addend = match operation {
    FusedMultiplySubtract | FusedNegatedMultiplySubtract => true
    FusedMultiplyAdd | FusedNegatedMultiplyAdd => false
  }
  if subtract_addend {
    emit_vector_float_unary(buffer, lane, Negate, destination, destination)
  }
  let subtract_product = match operation {
    FusedNegatedMultiplyAdd | FusedNegatedMultiplySubtract => true
    FusedMultiplyAdd | FusedMultiplySubtract => false
  }
  let base = if subtract_product {
    vector_float_lane_encoding(lane, 0x4EA0CC00U, 0x4EE0CC00U)
  } else {
    vector_float_lane_encoding(lane, 0x4E20CC00U, 0x4E60CC00U)
  }
  emit_vector_binary(buffer, base, left_copy, right_copy, destination)
}

///|
fn emit_vector_relaxed_dot8_to16(
  buffer : CodeBuffer,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let left_copy = @vcode.PhysicalReg::new(16, FpVector)
  let right_copy = @vcode.PhysicalReg::new(17, FpVector)
  emit_move(buffer, V128, left_copy, left)
  emit_move(buffer, V128, right_copy, right)
  emit_vector_binary(buffer, 0x0E20C000U, left_copy, right_copy, destination)
  emit_vector_binary(buffer, 0x4E20C000U, left_copy, right_copy, left_copy)
  emit_vector_binary(buffer, 0x4E60BC00U, destination, left_copy, destination)
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
    WrapI64ToI32 => emit_move(buffer, I32, destination, source)
    ExtendI32ToI64(Unsigned) =>
      buffer.emit_word(
        0x2A0003E0U | (reg_bits(source) << 16) | reg_bits(destination),
      )
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
  unwind : Array[@code_object.UnwindDirective],
) -> Unit raise AArch64EmitError {
  emit_sp_adjust(buffer, true, frame.frame_size(), unwind~)
  for saved in frame.saved_registers() {
    let (reg, offset) = saved
    emit_register_save_or_restore(buffer, false, reg, offset)
    let bank : @code_object.RegisterBank = match reg.class {
      Int => Int
      FpVector => FpVector
    }
    unwind.push(
      @code_object.UnwindDirective::new(
        buffer.position(),
        SaveRegister(bank, reg.id, cfa_offset=offset - frame.frame_size()),
      ),
    )
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
fn[Inst] emit_edits_at(
  buffer : CodeBuffer,
  function : @vcode.Function[Inst],
  frame : AArch64Frame,
  edits : Array[@vcode.Edit],
  instruction : @vcode.Instruction,
  placement : @vcode.PointPlacement,
) -> Unit raise AArch64EmitError {
  let moves : Array[@vcode.ParallelMove] = []
  for edit in edits {
    if edit.point() is Some(point) &&
      point.instruction() == instruction &&
      point.placement() == placement {
      match edit.kind() {
        Spill(value~, reg~, slot~) =>
          moves.push(
            @vcode.ParallelMove::new(
              function.value_type(value).unwrap(),
              Register(reg),
              Stack(slot),
            ),
          )
        Reload(value~, slot~, reg~) =>
          moves.push(
            @vcode.ParallelMove::new(
              function.value_type(value).unwrap(),
              Stack(slot),
              Register(reg),
            ),
          )
        Move(value~, from~, to~) =>
          moves.push(
            @vcode.ParallelMove::new(
              function.value_type(value).unwrap(),
              Register(from),
              Register(to),
            ),
          )
        EdgeMove(..) => ()
      }
    }
  }
  let resolved = @vcode.resolve_parallel_moves(
    moves,
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)],
    [
      @vcode.PhysicalReg::new(16, FpVector),
      @vcode.PhysicalReg::new(17, FpVector),
    ],
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
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
  result_area? : (Int, @vcode.PhysicalReg),
) -> Unit raise AArch64EmitError {
  let moves : Array[@vcode.ParallelMove] = []
  for index, ty in types {
    let source = allocation
      .operand_location(instruction, operand_start + index)
      .unwrap()
    match locations[index] {
      CallRegister(destination) =>
        moves.push(@vcode.ParallelMove::new(ty, source, Register(destination)))
      CallStack(offset) => {
        let source_reg = match source {
          Register(reg) => reg
          Stack(slot) => {
            let scratch = @vcode.PhysicalReg::new(
              16,
              @vcode.reg_class_for_value_type(ty),
            )
            emit_stack_access(
              buffer,
              true,
              ty,
              scratch,
              frame.slot_offset(slot).unwrap(),
            )
            scratch
          }
        }
        emit_stack_access(buffer, false, ty, source_reg, stack_base + offset)
      }
    }
  }
  if callee is Some((operand_index, destination)) {
    moves.push(
      @vcode.ParallelMove::new(
        Ptr64,
        allocation.operand_location(instruction, operand_index).unwrap(),
        Register(destination),
      ),
    )
  }
  if result_area is Some((operand_index, destination)) {
    moves.push(
      @vcode.ParallelMove::new(
        Ptr64,
        allocation.operand_location(instruction, operand_index).unwrap(),
        Register(destination),
      ),
    )
  }
  let int_scratch = if callee is Some(_) || result_area is Some(_) {
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
fn emit_tail_return_thunk_setup(
  buffer : CodeBuffer,
  frame : AArch64Frame,
  callee_args_size : Int,
) -> Unit raise AArch64EmitError {
  if callee_args_size > frame.incoming_args_size() {
    emit_sp_adjust(buffer, true, callee_args_size + 16)
    emit_stack_access(
      buffer,
      false,
      I64,
      @vcode.PhysicalReg::new(30, Int),
      callee_args_size,
    )
    // ADR X30, +8: the branch is the next instruction and the cleanup thunk
    // starts immediately after it.
    buffer.emit_word(0x1000005EU)
  }
}

///|
fn emit_tail_return_thunk(
  buffer : CodeBuffer,
  frame : AArch64Frame,
  callee_args_size : Int,
) -> Unit raise AArch64EmitError {
  if callee_args_size > frame.incoming_args_size() {
    let return_address = @vcode.PhysicalReg::new(16, Int)
    emit_stack_access(buffer, true, I64, return_address, callee_args_size)
    emit_sp_adjust(buffer, false, callee_args_size + 16)
    buffer.emit_word(0xD61F0000U | (reg_bits(return_address) << 5))
  }
}

///|
fn is_incoming_call_result(instruction : AArch64Inst) -> Bool {
  match instruction {
    IncomingCallResult(_, _) | IncomingCallAreaResult(_, _) => true
    _ => false
  }
}

///|
fn is_function_input(instruction : AArch64Inst) -> Bool {
  match instruction {
    IncomingReg(_, _) | IncomingStack(_, _) | IncomingResultArea(_) => true
    _ => false
  }
}

///|
fn value_home(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  instruction : @vcode.Instruction,
  operand_index : Int,
) -> @vcode.Location {
  let value = function
    .instruction_operand_at(instruction, operand_index)
    .unwrap().value
  allocation.value_location(value).unwrap()
}

///|
fn emit_function_inputs(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise AArch64EmitError {
  let body = function.block_body(block)
  let mut current_index = -1
  for index, candidate in body {
    if candidate == instruction {
      current_index = index
      break
    }
  }
  if current_index < 0 {
    return
  }
  if current_index > 0 &&
    is_function_input(function.instruction(body[current_index - 1]).unwrap()) {
    return
  }
  let register_moves : Array[@vcode.ParallelMove] = []
  let stack_inputs : Array[(@vcode.Instruction, @semantic.ValueType, Int)] = []
  let mut index = current_index
  while index < body.length() {
    let input_instruction = body[index]
    match function.instruction(input_instruction).unwrap() {
      IncomingReg(ty, source) =>
        register_moves.push(
          @vcode.ParallelMove::new(
            ty,
            Register(source),
            value_home(function, allocation, input_instruction, 1),
          ),
        )
      IncomingStack(ty, offset) =>
        stack_inputs.push((input_instruction, ty, offset))
      IncomingResultArea(source) =>
        register_moves.push(
          @vcode.ParallelMove::new(
            Ptr64,
            Register(source),
            value_home(function, allocation, input_instruction, 0),
          ),
        )
      _ => break
    }
    index += 1
  }
  let resolved = @vcode.resolve_parallel_moves(
    register_moves,
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)],
    [
      @vcode.PhysicalReg::new(16, FpVector),
      @vcode.PhysicalReg::new(17, FpVector),
    ],
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
  for input in stack_inputs {
    let (input_instruction, ty, offset) = input
    match value_home(function, allocation, input_instruction, 0) {
      Register(destination) =>
        emit_stack_access(
          buffer,
          true,
          ty,
          destination,
          frame.frame_size() + offset,
        )
      Stack(slot) => {
        let scratch = @vcode.PhysicalReg::new(
          16,
          @vcode.reg_class_for_value_type(ty),
        )
        emit_stack_access(
          buffer,
          true,
          ty,
          scratch,
          frame.frame_size() + offset,
        )
        emit_stack_access(
          buffer,
          false,
          ty,
          scratch,
          frame.slot_offset(slot).unwrap(),
        )
      }
    }
  }
}

///|
fn emit_incoming_call_results(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise AArch64EmitError {
  let body = function.block_body(block)
  let mut current_index = -1
  for index, candidate in body {
    if candidate == instruction {
      current_index = index
      break
    }
  }
  if current_index < 0 {
    return
  }
  if current_index > 0 &&
    is_incoming_call_result(
      function.instruction(body[current_index - 1]).unwrap(),
    ) {
    return
  }
  let register_moves : Array[@vcode.ParallelMove] = []
  let area_results : Array[(@vcode.Instruction, @semantic.ValueType, Int)] = []
  let mut index = current_index
  while index < body.length() {
    let result_instruction = body[index]
    match function.instruction(result_instruction).unwrap() {
      IncomingCallResult(ty, source) =>
        register_moves.push(
          @vcode.ParallelMove::new(
            ty,
            Register(source),
            value_home(function, allocation, result_instruction, 0),
          ),
        )
      IncomingCallAreaResult(ty, offset) =>
        area_results.push((result_instruction, ty, offset))
      _ => break
    }
    index += 1
  }
  let resolved = @vcode.resolve_parallel_moves(
    register_moves,
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)],
    [
      @vcode.PhysicalReg::new(16, FpVector),
      @vcode.PhysicalReg::new(17, FpVector),
    ],
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
  guard frame.result_area_offset() is Some(result_area_base) else {
    if !area_results.is_empty() {
      raise MissingResultArea
    }
    return
  }
  for result in area_results {
    let (result_instruction, ty, offset) = result
    match value_home(function, allocation, result_instruction, 0) {
      Register(destination) =>
        emit_stack_access(
          buffer,
          true,
          ty,
          destination,
          result_area_base + offset,
        )
      Stack(slot) => {
        let scratch = @vcode.PhysicalReg::new(
          16,
          @vcode.reg_class_for_value_type(ty),
        )
        emit_stack_access(buffer, true, ty, scratch, result_area_base + offset)
        emit_stack_access(
          buffer,
          false,
          ty,
          scratch,
          frame.slot_offset(slot).unwrap(),
        )
      }
    }
  }
}

///|
fn is_function_output(instruction : AArch64Inst) -> Bool {
  match instruction {
    OutgoingReg(_, _) | OutgoingAreaResult(_, _) => true
    _ => false
  }
}

///|
fn is_abi_materialization(instruction : AArch64Inst) -> Bool {
  is_function_input(instruction) ||
  is_incoming_call_result(instruction) ||
  is_function_output(instruction)
}

///|
fn emit_function_outputs(
  buffer : CodeBuffer,
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
  frame : AArch64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise AArch64EmitError {
  let body = function.block_body(block)
  let mut current_index = -1
  for index, candidate in body {
    if candidate == instruction {
      current_index = index
      break
    }
  }
  if current_index < 0 {
    return
  }
  if current_index > 0 &&
    is_function_output(function.instruction(body[current_index - 1]).unwrap()) {
    return
  }
  let register_moves : Array[@vcode.ParallelMove] = []
  let area_results : Array[(@vcode.Instruction, @semantic.ValueType, Int)] = []
  let mut index = current_index
  while index < body.length() {
    let output_instruction = body[index]
    match function.instruction(output_instruction).unwrap() {
      OutgoingReg(ty, destination) =>
        register_moves.push(
          @vcode.ParallelMove::new(
            ty,
            value_home(function, allocation, output_instruction, 0),
            Register(destination),
          ),
        )
      OutgoingAreaResult(ty, offset) =>
        area_results.push((output_instruction, ty, offset))
      _ => break
    }
    index += 1
  }
  for result in area_results {
    let (output_instruction, ty, offset) = result
    let address = match
      value_home(function, allocation, output_instruction, 0) {
      Register(address) => address
      Stack(slot) => {
        let scratch = @vcode.PhysicalReg::new(16, Int)
        emit_stack_access(
          buffer,
          true,
          Ptr64,
          scratch,
          frame.slot_offset(slot).unwrap(),
        )
        scratch
      }
    }
    let value = match value_home(function, allocation, output_instruction, 1) {
      Register(value) => value
      Stack(slot) => {
        let scratch_id = if @vcode.reg_class_for_value_type(ty) == Int {
          17
        } else {
          16
        }
        let scratch = @vcode.PhysicalReg::new(
          scratch_id,
          @vcode.reg_class_for_value_type(ty),
        )
        emit_stack_access(
          buffer,
          true,
          ty,
          scratch,
          frame.slot_offset(slot).unwrap(),
        )
        scratch
      }
    }
    emit_result_area_access(buffer, false, ty, address~, value~, offset)
  }
  let resolved = @vcode.resolve_parallel_moves(
    register_moves,
    [@vcode.PhysicalReg::new(16, Int), @vcode.PhysicalReg::new(17, Int)],
    [
      @vcode.PhysicalReg::new(16, FpVector),
      @vcode.PhysicalReg::new(17, FpVector),
    ],
  ) catch {
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
  let reg = fn(index : Int) -> @vcode.PhysicalReg raise AArch64EmitError {
    match allocation.operand_location(instruction, index).unwrap() {
      Register(reg) => reg
      Stack(_) => raise UnexpectedStackOperand(instruction~, operand=index)
    }
  }
  let mut metadata_offset = buffer.position()
  match function.instruction(instruction).unwrap() {
    IncomingReg(_, _) | IncomingStack(_, _) | IncomingResultArea(_) =>
      emit_function_inputs(
        buffer, function, allocation, frame, block, instruction,
      )
    IncomingCallResult(_, _) | IncomingCallAreaResult(_, _) =>
      emit_incoming_call_results(
        buffer, function, allocation, frame, block, instruction,
      )
    OutgoingReg(_, _) | OutgoingAreaResult(_, _) =>
      emit_function_outputs(
        buffer, function, allocation, frame, block, instruction,
      )
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
    VectorConvert(conversion) =>
      match conversion {
        ExtendLow(lane, signedness) =>
          emit_vector_extension(buffer, lane, false, signedness, reg(0), reg(1))
        ExtendHigh(lane, signedness) =>
          emit_vector_extension(buffer, lane, true, signedness, reg(0), reg(1))
        Narrow(lane, signedness) =>
          emit_vector_narrow(buffer, lane, signedness, reg(0), reg(1), reg(2))
        FloatToInt(_, _)
        | IntToFloat(_, _)
        | PromoteLowF32x4
        | DemoteZeroF64x2 =>
          emit_vector_conversion(buffer, conversion, reg(0), reg(1))
      }
    VectorPredicate(predicate) =>
      emit_vector_predicate(buffer, predicate, reg(0), reg(1))
    VectorFloatUnary(lane, operation) =>
      emit_vector_float_unary(buffer, lane, operation, reg(0), reg(1))
    VectorFloatBinary(lane, operation) =>
      emit_vector_float_binary(buffer, lane, operation, reg(0), reg(1), reg(2))
    VectorFloatTernary(lane, operation) =>
      emit_vector_float_ternary(
        buffer,
        lane,
        operation,
        reg(0),
        reg(1),
        reg(2),
        reg(3),
      )
    VectorFloatCompare(lane, comparison) =>
      emit_vector_float_compare(
        buffer,
        lane,
        comparison,
        reg(0),
        reg(1),
        reg(2),
      )
    VectorPairwiseAddI16x8 =>
      emit_vector_binary(buffer, 0x4E60BC00U, reg(0), reg(1), reg(2))
    VectorRelaxedDot8To16 =>
      emit_vector_relaxed_dot8_to16(buffer, reg(0), reg(1), reg(2))
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
    VectorLoad128(offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W128,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(
        0x3DC00000U |
        (immediate << 10) |
        (reg_bits(address) << 5) |
        reg_bits(reg(1)),
      )
    }
    VectorStore128(offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W128,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(
        0x3D800000U |
        (immediate << 10) |
        (reg_bits(address) << 5) |
        reg_bits(reg(1)),
      )
    }
    VectorLoadSplat(lane, offset) => {
      let address = vector_structure_address(buffer, reg(0), offset)
      metadata_offset = buffer.position()
      buffer.emit_word(
        vector_splat_load_base(lane) |
        (reg_bits(address) << 5) |
        reg_bits(reg(1)),
      )
    }
    VectorLoadExtend(lane, signedness, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W64,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.emit_word(
        0xFD400000U |
        (immediate << 10) |
        (reg_bits(address) << 5) |
        reg_bits(reg(1)),
      )
      emit_vector_extension(buffer, lane, false, signedness, reg(1), reg(1))
    }
    VectorLoadZero(width, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      let base = if width == W32 {
        0xBD400000U
      } else if width == W64 {
        0xFD400000U
      } else {
        raise InvalidVectorInstruction
      }
      metadata_offset = buffer.position()
      buffer.emit_word(
        base | (immediate << 10) | (reg_bits(address) << 5) | reg_bits(reg(1)),
      )
    }
    VectorLoadLane(lane, index, offset) => {
      emit_move(buffer, V128, reg(2), reg(1))
      let address = vector_structure_address(buffer, reg(0), offset)
      metadata_offset = buffer.position()
      buffer.emit_word(
        vector_lane_memory_word(true, lane, index, address, reg(2)),
      )
    }
    VectorStoreLane(lane, index, offset) => {
      let address = vector_structure_address(buffer, reg(0), offset)
      metadata_offset = buffer.position()
      buffer.emit_word(
        vector_lane_memory_word(false, lane, index, address, reg(1)),
      )
    }
    AtomicLoad(width, _) => {
      metadata_offset = buffer.position()
      buffer.emit_word(
        atomic_load_base(width, false) |
        (reg_bits(reg(0)) << 5) |
        reg_bits(reg(1)),
      )
    }
    AtomicStore(width, _) => {
      metadata_offset = buffer.position()
      buffer.emit_word(
        atomic_store_base(width, false) |
        (reg_bits(reg(0)) << 5) |
        reg_bits(reg(1)),
      )
    }
    AtomicRmw(width, _, operation) =>
      metadata_offset = emit_atomic_rmw(
        buffer,
        width,
        operation,
        reg(0),
        reg(1),
        reg(2),
      )
    AtomicCompareExchange(width, _) =>
      metadata_offset = emit_atomic_compare_exchange(
        buffer,
        width,
        reg(0),
        reg(1),
        reg(2),
        reg(3),
      )
    AtomicFence => buffer.emit_word(0xD5033BBFU)
    SafepointMarker => {
      metadata_offset = buffer.position()
      buffer.emit_word(0xD503201FU)
    }
    PlatformCall(target, signature)
    | ReturnsTwicePlatformCall(target, signature) => {
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
      if result_area_register(plan) is Some(destination) {
        guard frame.result_area_offset() is Some(offset) else {
          raise MissingResultArea
        }
        emit_stack_address(buffer, destination, offset)
      }
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
      if result_area_register(plan) is Some(destination) {
        guard frame.result_area_offset() is Some(offset) else {
          raise MissingResultArea
        }
        emit_stack_address(buffer, destination, offset)
      }
      metadata_offset = buffer.position()
      buffer.emit_word(0xD63F0000U | (reg_bits(callee_register) << 5))
    }
    TailCallDirect(target, signature, plan) => {
      let result_area = result_area_register(plan).map(destination => {
        (signature.params.length(), destination)
      })
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        stack_base=frame.tail_call_stack_base(plan.stack_size),
        result_area?,
      )
      emit_epilogue(buffer, frame)
      emit_tail_return_thunk_setup(buffer, frame, plan.stack_size)
      metadata_offset = buffer.position()
      buffer.emit_word(0x14000000U)
      buffer.relocations.push(
        @code_object.Relocation::new(
          metadata_offset,
          AArch64Jump26,
          Code(target),
        ),
      )
      emit_tail_return_thunk(buffer, frame, plan.stack_size)
    }
    TailCallIndirect(signature, plan) => {
      let callee_register = @vcode.PhysicalReg::new(17, Int)
      let result_area = result_area_register(plan).map(destination => {
        (signature.params.length() + 1, destination)
      })
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        operand_start=1,
        stack_base=frame.tail_call_stack_base(plan.stack_size),
        callee=(0, callee_register),
        result_area?,
      )
      emit_epilogue(buffer, frame)
      emit_tail_return_thunk_setup(buffer, frame, plan.stack_size)
      metadata_offset = buffer.position()
      buffer.emit_word(0xD61F0000U | (reg_bits(callee_register) << 5))
      emit_tail_return_thunk(buffer, frame, plan.stack_size)
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
    Switch(width, cases) =>
      emit_switch_edges(
        buffer,
        function,
        allocation,
        frame,
        block,
        instruction,
        width,
        cases,
        reg(0),
      )
    Trap(reason) => {
      metadata_offset = buffer.position()
      buffer.emit_word(0xD4200000U | (trap_brk_payload(reason) << 5))
    }
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
  let mask = if bits == 26 { 0x03FFFFFFU } else { 0x7FFFFU }
  let shift = if bits == 19 { 5 } else { 0 }
  let original = buffer.code[offset].to_uint() |
    (buffer.code[offset + 1].to_uint() << 8) |
    (buffer.code[offset + 2].to_uint() << 16) |
    (buffer.code[offset + 3].to_uint() << 24)
  let base = original & (mask << shift).lnot()
  buffer.patch_word(
    offset,
    base | ((words.reinterpret_as_uint() & mask) << shift),
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
  let unwind : Array[@code_object.UnwindDirective] = []
  emit_prologue(buffer, frame, unwind)
  for block in function.layout() {
    block_offsets[function.block_index(block).unwrap()] = buffer.position()
    for instruction in function.block_body(block) {
      let abi_materialization = is_abi_materialization(
        function.instruction(instruction).unwrap(),
      )
      if !abi_materialization {
        emit_edits_at(buffer, function, frame, edits, instruction, Before)
      }
      let instruction_offset = emit_instruction(
        buffer, function, allocation, frame, block, instruction,
      )
      record_instruction_metadata(
        buffer, function, allocation, frame, instruction, instruction_offset, sources,
        traps, safepoints,
      )
      if !abi_materialization {
        emit_edits_at(buffer, function, frame, edits, instruction, After)
      }
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
    unwind~,
  ) catch {
    error => raise InvalidCodeObject(cause=error)
  }
}
