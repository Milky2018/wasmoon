///|
const AARCH64_DIVISION_BY_ZERO_BRK : UInt = 4U

///|
const AARCH64_INTEGER_OVERFLOW_BRK : UInt = 5U

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
  FrameOffsetOutOfRange(offset~ : Int)
  InvalidScalarMemoryAccess
  InvalidFloatInstruction
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
  if amount < 0 || amount > 4095 {
    raise FrameOffsetOutOfRange(offset=amount)
  }
  let base = if subtract { 0xD1000000U } else { 0x91000000U }
  buffer.emit_word(
    base | (amount.reinterpret_as_uint() << 10) | (31U << 5) | 31U,
  )
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
    IntUnary(width, operation) =>
      buffer.emit_word(encode_int_unary(width, operation, reg(1), reg(0)))
    IntBinary(width, operation) =>
      buffer.emit_word(
        encode_int_binary(width, operation, reg(2), reg(0), reg(1)),
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
    FloatUnary(ty, operation) => {
      guard float_unary_base(ty, operation) is Some(base) else {
        raise InvalidFloatInstruction
      }
      buffer.emit_word(base | (reg_bits(reg(0)) << 5) | reg_bits(reg(1)))
    }
    FloatBinary(ty, operation) => {
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
