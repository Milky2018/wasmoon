///|
const X64_DIVISION_BY_ZERO_BRK : UInt = 4U

///|
const X64_INTEGER_OVERFLOW_BRK : UInt = 5U

///|
const X64_INVALID_CONVERSION_BRK : UInt = 3U

///|
fn trap_brk_payload(reason : @native.TrapReason) -> UInt {
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
priv struct X64RelativeFixup {
  displacement_offset : Int
  next_instruction_offset : Int
  target_block : Int
}

///|
priv struct CodeBuffer {
  code : Array[Byte]
  x64_fixups : Array[X64RelativeFixup]
  relocations : Array[@code_object.Relocation]
}

///|
pub suberror X64EmitError {
  InvalidFrame(cause~ : X64FrameError)
  InvalidCodeObject(cause~ : @code_object.CodeObjectVerifyError)
  InvalidParallelMove(cause~ : @vcode.MoveResolveError)
  InvalidCallTransfer(cause~ : @vcode.CallTransferError)
  UnresolvedStackMove
  MissingStackObjectArea
  MissingResultArea
  MissingEmergencyMoveArea
  UnexpectedStackOperand(instruction~ : @vcode.Instruction, operand~ : Int)
  FrameOffsetOutOfRange(offset~ : Int)
  InvalidScalarMemoryAccess
  InvalidFloatInstruction
  InvalidVectorInstruction
  ScratchRegisterUnavailable
  InvalidConversionInstruction
  BranchTargetMissing(block~ : @vcode.Block)
  BranchOutOfRange(offset~ : Int, bits~ : Int)
} derive(Debug)

///|
pub impl Show for X64EmitError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn CodeBuffer::new() -> CodeBuffer {
  { code: [], x64_fixups: [], relocations: [], }
}

///|
fn CodeBuffer::emit_byte(self : CodeBuffer, byte : Int) -> Unit {
  self.code.push((byte & 0xFF).to_byte())
}

///|
fn CodeBuffer::current_pos(self : CodeBuffer) -> Int {
  self.position()
}

///|
fn CodeBuffer::add_x86_rel32_fixup(
  self : CodeBuffer,
  target_block : Int,
  displacement_offset : Int,
  next_instruction_offset : Int,
) -> Unit {
  self.x64_fixups.push({
    displacement_offset,
    next_instruction_offset,
    target_block,
  })
}

///|
fn CodeBuffer::position(self : CodeBuffer) -> Int {
  self.code.length()
}

///|
fn CodeBuffer::patch_word(self : CodeBuffer, offset : Int, word : UInt) -> Unit {
  self.code[offset] = (word & 0xFFU).to_byte()
  self.code[offset + 1] = ((word >> 8) & 0xFFU).to_byte()
  self.code[offset + 2] = ((word >> 16) & 0xFFU).to_byte()
  self.code[offset + 3] = ((word >> 24) & 0xFFU).to_byte()
}

///|
fn emit_move(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  to : @vcode.PhysicalReg,
  from : @vcode.PhysicalReg,
) -> Unit {
  if to == from {
    return
  }
  match ty {
    I32 => buffer.x86_emit_mov_rr32(to.id, from.id)
    I64 | Ptr64 | GcRef64 => buffer.x86_emit_mov_rr(to.id, from.id)
    F32 => buffer.x86_emit_movss_xmm_xmm(to.id, from.id)
    F64 => buffer.x86_emit_movsd_xmm_xmm(to.id, from.id)
    V128 => buffer.x86_emit_movaps_xmm_xmm(to.id, from.id)
  }
}

///|
fn emit_constant(
  buffer : CodeBuffer,
  width : GprWidth,
  destination : @vcode.PhysicalReg,
  bits : UInt64,
) -> Unit {
  let value = if width == W32 { bits & 0xFFFFFFFFUL } else { bits }
  buffer.x86_emit_mov_imm64(destination.id, value.reinterpret_as_int64())
}

///|
fn emit_stack_access(
  buffer : CodeBuffer,
  load : Bool,
  ty : @native.ValueType,
  reg : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise X64EmitError {
  if offset < 0 || offset > 0x7FFFFFFF {
    raise FrameOffsetOutOfRange(offset~)
  }
  match (load, ty) {
    (true, I32) => buffer.x86_emit_mov_r32_m32(reg.id, 4, offset)
    (false, I32) => buffer.x86_emit_mov_m32_r32(4, offset, reg.id)
    (true, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_r64_m64(reg.id, 4, offset)
    (false, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_m64_r64(4, offset, reg.id)
    (true, F32) => buffer.x86_emit_movss_xmm_m32(reg.id, 4, offset)
    (false, F32) => buffer.x86_emit_movss_m32_xmm(4, offset, reg.id)
    (true, F64) => buffer.x86_emit_movsd_xmm_m64(reg.id, 4, offset)
    (false, F64) => buffer.x86_emit_movsd_m64_xmm(4, offset, reg.id)
    (true, V128) => buffer.x86_emit_movdqu_xmm_m128(reg.id, 4, offset)
    (false, V128) => buffer.x86_emit_movdqu_m128_xmm(4, offset, reg.id)
  }
}

///|
fn emit_result_area_access(
  buffer : CodeBuffer,
  load : Bool,
  ty : @native.ValueType,
  address~ : @vcode.PhysicalReg,
  value~ : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise X64EmitError {
  if offset < 0 || offset > 0x7FFFFFFF {
    raise FrameOffsetOutOfRange(offset~)
  }
  match (load, ty) {
    (true, I32) => buffer.x86_emit_mov_r32_m32(value.id, address.id, offset)
    (false, I32) => buffer.x86_emit_mov_m32_r32(address.id, offset, value.id)
    (true, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_r64_m64(value.id, address.id, offset)
    (false, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_m64_r64(address.id, offset, value.id)
    (true, F32) => buffer.x86_emit_movss_xmm_m32(value.id, address.id, offset)
    (false, F32) => buffer.x86_emit_movss_m32_xmm(address.id, offset, value.id)
    (true, F64) => buffer.x86_emit_movsd_xmm_m64(value.id, address.id, offset)
    (false, F64) => buffer.x86_emit_movsd_m64_xmm(address.id, offset, value.id)
    (true, V128) =>
      buffer.x86_emit_movdqu_xmm_m128(value.id, address.id, offset)
    (false, V128) =>
      buffer.x86_emit_movdqu_m128_xmm(address.id, offset, value.id)
  }
}

///|
fn scalar_memory_address(
  buffer : CodeBuffer,
  address : @vcode.PhysicalReg,
  width : @native.AccessWidth,
  offset : UInt64,
) -> (@vcode.PhysicalReg, Int) {
  ignore(width)
  if offset <= 0x7FFFFFFFUL {
    return (address, offset.to_int())
  }
  let immediate = @vcode.PhysicalReg::new(10, Int)
  let scratch = @vcode.PhysicalReg::new(11, Int)
  emit_constant(buffer, W64, immediate, offset)
  buffer.x86_emit_mov_rr(scratch.id, address.id)
  buffer.x86_emit_add_rr(scratch.id, immediate.id)
  (scratch, 0)
}

///|
fn emit_scalar_load(
  buffer : CodeBuffer,
  width : @native.AccessWidth,
  extension : @native.LoadExtension,
  result_type : @native.ValueType,
  address : @vcode.PhysicalReg,
  offset : Int,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match (width, extension, result_type) {
    (W8, Signed, I32 | I64) =>
      buffer.x86_emit_movsx_r64_m8(destination.id, address.id, offset)
    (W8, Unsigned, I32 | I64) =>
      buffer.x86_emit_movzx_r32_m8(destination.id, address.id, offset)
    (W16, Signed, I32 | I64) =>
      buffer.x86_emit_movsx_r64_m16(destination.id, address.id, offset)
    (W16, Unsigned, I32 | I64) =>
      buffer.x86_emit_movzx_r32_m16(destination.id, address.id, offset)
    (W32, None, I32) | (W32, Unsigned, I64) =>
      buffer.x86_emit_mov_r32_m32(destination.id, address.id, offset)
    (W32, Signed, I64) =>
      buffer.x86_emit_movsxd_r64_m32(destination.id, address.id, offset)
    (W64, None, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_r64_m64(destination.id, address.id, offset)
    (W32, None, F32) =>
      buffer.x86_emit_movss_xmm_m32(destination.id, address.id, offset)
    (W64, None, F64) =>
      buffer.x86_emit_movsd_xmm_m64(destination.id, address.id, offset)
    _ => raise InvalidScalarMemoryAccess
  }
}

///|
fn emit_scalar_store(
  buffer : CodeBuffer,
  width : @native.AccessWidth,
  value_type : @native.ValueType,
  address : @vcode.PhysicalReg,
  offset : Int,
  source : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match (width, value_type) {
    (W8, I32 | I64) => buffer.x86_emit_mov_m8_r8(address.id, offset, source.id)
    (W16, I32 | I64) =>
      buffer.x86_emit_mov_m16_r16(address.id, offset, source.id)
    (W32, I32 | I64) =>
      buffer.x86_emit_mov_m32_r32(address.id, offset, source.id)
    (W64, I64 | Ptr64 | GcRef64) =>
      buffer.x86_emit_mov_m64_r64(address.id, offset, source.id)
    (W32, F32) => buffer.x86_emit_movss_m32_xmm(address.id, offset, source.id)
    (W64, F64) => buffer.x86_emit_movsd_m64_xmm(address.id, offset, source.id)
    _ => raise InvalidScalarMemoryAccess
  }
}

///|
fn atomic_operation_width(width : @native.AccessWidth) -> GprWidth {
  if width == W64 {
    W64
  } else {
    W32
  }
}

///|
fn emit_atomic_rmw(
  buffer : CodeBuffer,
  width : @native.AccessWidth,
  operation : @lowering.AtomicRmwOp,
  address : @vcode.PhysicalReg,
  value : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
) -> Int raise X64EmitError {
  if width == W128 {
    raise InvalidScalarMemoryAccess
  }
  let operation_width = atomic_operation_width(width)
  match operation {
    Add | Sub | Exchange => {
      let working = if result == value {
        value
      } else {
        let scratch = @vcode.PhysicalReg::new(10, Int)
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
        scratch
      }
      if operation == Sub {
        if operation_width == W64 {
          buffer.x86_emit_neg_r64(working.id)
        } else {
          buffer.x86_emit_neg_r32(working.id)
        }
      }
      let offset = buffer.position()
      if operation == Exchange {
        buffer.x86_emit_xchg_memory(width, address.id, working.id)
      } else {
        buffer.x86_emit_lock_xadd(width, address.id, working.id)
      }
      emit_move(
        buffer,
        if operation_width == W64 {
          I64
        } else {
          I32
        },
        result,
        working,
      )
      offset
    }
    And | Or | Xor => {
      let desired = @vcode.PhysicalReg::new(2, Int)
      let offset = buffer.position()
      match width {
        W8 => buffer.x86_emit_movzx_r32_m8(result.id, address.id, 0)
        W16 => buffer.x86_emit_movzx_r32_m16(result.id, address.id, 0)
        W32 => buffer.x86_emit_mov_r32_m32(result.id, address.id, 0)
        W64 => buffer.x86_emit_mov_r64_m64(result.id, address.id, 0)
        W128 => raise InvalidScalarMemoryAccess
      }
      let loop_offset = buffer.position()
      emit_move(
        buffer,
        if operation_width == W64 {
          I64
        } else {
          I32
        },
        desired,
        result,
      )
      match (operation_width, operation) {
        (W32, And) => buffer.x86_emit_and_rr32(desired.id, value.id)
        (W64, And) => buffer.x86_emit_and_rr(desired.id, value.id)
        (W32, Or) => buffer.x86_emit_or_rr32(desired.id, value.id)
        (W64, Or) => buffer.x86_emit_or_rr(desired.id, value.id)
        (W32, Xor) => buffer.x86_emit_xor_rr32(desired.id, value.id)
        (W64, Xor) => buffer.x86_emit_xor_rr(desired.id, value.id)
        _ => abort("matched atomic bitwise operation")
      }
      buffer.x86_emit_lock_cmpxchg(width, address.id, desired.id)
      let retry = buffer.emit_local_jcc(RawNe)
      buffer.patch_local_rel32(retry, loop_offset)
      offset
    }
  }
}

///|
fn emit_atomic_compare_exchange(
  buffer : CodeBuffer,
  width : @native.AccessWidth,
  address : @vcode.PhysicalReg,
  expected : @vcode.PhysicalReg,
  replacement : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
) -> Int raise X64EmitError {
  if width == W128 {
    raise InvalidScalarMemoryAccess
  }
  ignore(expected)
  ignore(result)
  let offset = buffer.position()
  buffer.x86_emit_lock_cmpxchg(width, address.id, replacement.id)
  offset
}

///|
fn emit_sp_adjust(
  buffer : CodeBuffer,
  subtract : Bool,
  amount : Int,
  unwind? : Array[@code_object.UnwindDirective],
) -> Unit raise X64EmitError {
  if amount == 0 {
    return
  }
  if amount < 0 {
    raise FrameOffsetOutOfRange(offset=amount)
  }
  if amount > 0x7FFFFFFF {
    raise FrameOffsetOutOfRange(offset=amount)
  }
  if subtract {
    let mut remaining = amount
    while remaining >= 4096 {
      buffer.x86_emit_sub_rsp_imm32(4096)
      if unwind is Some(directives) {
        directives.push(
          @code_object.UnwindDirective::new(
            buffer.position(),
            StackAlloc(size=4096),
          ),
        )
      }
      buffer.x86_emit_mov_r64_m64(10, 4, 0)
      remaining -= 4096
    }
    if remaining > 0 {
      buffer.x86_emit_sub_rsp_imm32(remaining)
      if unwind is Some(directives) {
        directives.push(
          @code_object.UnwindDirective::new(
            buffer.position(),
            StackAlloc(size=remaining),
          ),
        )
      }
    }
  } else {
    buffer.x86_emit_add_rsp_imm32(amount)
  }
}

///|
fn emit_stack_address(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  offset : Int,
) -> Unit {
  buffer.x86_emit_mov_rr(destination.id, 4)
  if offset == 0 {
    return
  }
  if offset <= 0x7FFFFFFF {
    buffer.x86_emit_add_r_imm32(destination.id, offset)
  } else {
    let scratch = @vcode.PhysicalReg::new(10, Int)
    emit_constant(buffer, W64, scratch, offset.to_uint64())
    buffer.x86_emit_add_rr(destination.id, scratch.id)
  }
}

///|
fn raw_condition(condition : X64Condition) -> RawCondition {
  match condition {
    Eq => RawEq
    Ne => RawNe
    Hs => RawHs
    Lo => RawLo
    Hi => RawHi
    Ls => RawLs
    Ge => RawGe
    Lt => RawLt
    Gt => RawGt
    Le => RawLe
  }
}

///|
fn CodeBuffer::emit_local_jcc(
  self : CodeBuffer,
  condition : RawCondition,
) -> Int {
  self.emit_byte(0x0F)
  self.emit_byte(x86_cond_to_jcc_opcode(condition))
  let displacement = self.position()
  emit_u32_le(self, 0)
  displacement
}

///|
fn CodeBuffer::patch_local_rel32(
  self : CodeBuffer,
  displacement_offset : Int,
  target : Int,
) -> Unit {
  let displacement = target - (displacement_offset + 4)
  let bits = displacement.reinterpret_as_uint()
  for byte in 0..<4 {
    self.code[displacement_offset + byte] = ((bits >> (byte * 8)) & 0xFFU).to_byte()
  }
}

///|
fn CodeBuffer::emit_local_jmp(self : CodeBuffer) -> Int {
  self.emit_byte(0xE9)
  let displacement = self.position()
  emit_u32_le(self, 0)
  displacement
}

///|
fn emit_reverse_bits(
  width : GprWidth,
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> Unit {
  let value = @vcode.PhysicalReg::new(10, Int)
  let temporary = @vcode.PhysicalReg::new(11, Int)
  emit_move(buffer, integer_type(width), value, source)
  let stages : Array[(Int, UInt64)] = if width == W32 {
    [
      (1, 0x55555555UL),
      (2, 0x33333333UL),
      (4, 0x0F0F0F0FUL),
      (8, 0x00FF00FFUL),
      (16, 0x0000FFFFUL),
    ]
  } else {
    [
      (1, 0x5555555555555555UL),
      (2, 0x3333333333333333UL),
      (4, 0x0F0F0F0F0F0F0F0FUL),
      (8, 0x00FF00FF00FF00FFUL),
      (16, 0x0000FFFF0000FFFFUL),
      (32, 0x00000000FFFFFFFFUL),
    ]
  }
  for stage in stages {
    let (shift, mask) = stage
    emit_move(buffer, integer_type(width), temporary, value)
    if width == W32 {
      buffer.x86_emit_shr_r32_imm8(temporary.id, shift)
      emit_constant(buffer, W32, destination, mask)
      buffer.x86_emit_and_rr32(temporary.id, destination.id)
      buffer.x86_emit_and_rr32(value.id, destination.id)
      buffer.x86_emit_shl_r32_imm8(value.id, shift)
      buffer.x86_emit_or_rr32(value.id, temporary.id)
    } else {
      buffer.x86_emit_shr_r_imm8(temporary.id, shift)
      emit_constant(buffer, W64, destination, mask)
      buffer.x86_emit_and_rr(temporary.id, destination.id)
      buffer.x86_emit_and_rr(value.id, destination.id)
      buffer.x86_emit_shl_r_imm8(value.id, shift)
      buffer.x86_emit_or_rr(value.id, temporary.id)
    }
  }
  emit_move(buffer, integer_type(width), destination, value)
}

///|
fn emit_population_count(
  buffer : CodeBuffer,
  width : GprWidth,
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> Unit {
  let value = @vcode.PhysicalReg::new(10, Int)
  let temporary = @vcode.PhysicalReg::new(11, Int)
  emit_move(buffer, integer_type(width), value, source)
  emit_move(buffer, integer_type(width), temporary, value)
  if width == W32 {
    buffer.x86_emit_shr_r32_imm8(temporary.id, 1)
    emit_constant(buffer, W32, destination, 0x55555555UL)
    buffer.x86_emit_and_rr32(temporary.id, destination.id)
    buffer.x86_emit_sub_rr32(value.id, temporary.id)
    emit_move(buffer, I32, temporary, value)
    buffer.x86_emit_shr_r32_imm8(temporary.id, 2)
    emit_constant(buffer, W32, destination, 0x33333333UL)
    buffer.x86_emit_and_rr32(value.id, destination.id)
    buffer.x86_emit_and_rr32(temporary.id, destination.id)
    buffer.x86_emit_add_rr32(value.id, temporary.id)
    emit_move(buffer, I32, temporary, value)
    buffer.x86_emit_shr_r32_imm8(temporary.id, 4)
    buffer.x86_emit_add_rr32(value.id, temporary.id)
    emit_constant(buffer, W32, destination, 0x0F0F0F0FUL)
    buffer.x86_emit_and_rr32(value.id, destination.id)
    for shift in [8, 16] {
      emit_move(buffer, I32, temporary, value)
      buffer.x86_emit_shr_r32_imm8(temporary.id, shift)
      buffer.x86_emit_add_rr32(value.id, temporary.id)
    }
    emit_constant(buffer, W32, destination, 0x3FUL)
    buffer.x86_emit_and_rr32(value.id, destination.id)
    buffer.x86_emit_mov_rr32(destination.id, value.id)
  } else {
    buffer.x86_emit_shr_r_imm8(temporary.id, 1)
    emit_constant(buffer, W64, destination, 0x5555555555555555UL)
    buffer.x86_emit_and_rr(temporary.id, destination.id)
    buffer.x86_emit_sub_rr(value.id, temporary.id)
    emit_move(buffer, I64, temporary, value)
    buffer.x86_emit_shr_r_imm8(temporary.id, 2)
    emit_constant(buffer, W64, destination, 0x3333333333333333UL)
    buffer.x86_emit_and_rr(value.id, destination.id)
    buffer.x86_emit_and_rr(temporary.id, destination.id)
    buffer.x86_emit_add_rr(value.id, temporary.id)
    emit_move(buffer, I64, temporary, value)
    buffer.x86_emit_shr_r_imm8(temporary.id, 4)
    buffer.x86_emit_add_rr(value.id, temporary.id)
    emit_constant(buffer, W64, destination, 0x0F0F0F0F0F0F0F0FUL)
    buffer.x86_emit_and_rr(value.id, destination.id)
    for shift in [8, 16, 32] {
      emit_move(buffer, I64, temporary, value)
      buffer.x86_emit_shr_r_imm8(temporary.id, shift)
      buffer.x86_emit_add_rr(value.id, temporary.id)
    }
    emit_constant(buffer, W64, destination, 0x7FUL)
    buffer.x86_emit_and_rr(value.id, destination.id)
    buffer.x86_emit_mov_rr32(destination.id, value.id)
  }
}

///|
fn emit_int_unary(
  width : GprWidth,
  buffer : CodeBuffer,
  operation : X64IntUnary,
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> Unit {
  match operation {
    Mvn => {
      emit_move(buffer, integer_type(width), destination, source)
      if width == W32 {
        buffer.x86_emit_not_r32(destination.id)
      } else {
        buffer.x86_emit_not_r64(destination.id)
      }
    }
    Neg => {
      emit_move(buffer, integer_type(width), destination, source)
      if width == W32 {
        buffer.x86_emit_neg_r32(destination.id)
      } else {
        buffer.x86_emit_neg_r64(destination.id)
      }
    }
    Clz => {
      let fallback = @vcode.PhysicalReg::new(10, Int)
      let maximum = @vcode.PhysicalReg::new(11, Int)
      emit_constant(buffer, width, fallback, 0xFFFFFFFFFFFFFFFFUL)
      if width == W32 {
        buffer.x86_emit_bsr_r32_r32(destination.id, source.id)
        buffer.x86_emit_cmovcc_rr32(RawEq, destination.id, fallback.id)
        emit_constant(buffer, W32, maximum, 31UL)
        buffer.x86_emit_sub_rr32(maximum.id, destination.id)
        buffer.x86_emit_mov_rr32(destination.id, maximum.id)
      } else {
        buffer.x86_emit_bsr_r64_r64(destination.id, source.id)
        buffer.x86_emit_cmovcc_rr(RawEq, destination.id, fallback.id)
        emit_constant(buffer, W64, maximum, 63UL)
        buffer.x86_emit_sub_rr(maximum.id, destination.id)
        buffer.x86_emit_mov_rr(destination.id, maximum.id)
      }
    }
    Rbit => emit_reverse_bits(width, buffer, destination, source)
  }
}

///|
fn emit_int_binary(
  buffer : CodeBuffer,
  width : GprWidth,
  operation : X64IntBinary,
  destination : @vcode.PhysicalReg,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
) -> Unit {
  if operation == Sdiv || operation == Udiv {
    if width == W32 {
      if operation == Sdiv {
        buffer.x86_emit_cdq()
        buffer.x86_emit_idiv_r32(right.id)
      } else {
        buffer.x86_emit_xor_rr32(2, 2)
        buffer.x86_emit_div_r32(right.id)
      }
    } else if operation == Sdiv {
      buffer.x86_emit_cqo()
      buffer.x86_emit_idiv_r64(right.id)
    } else {
      buffer.x86_emit_xor_rr(2, 2)
      buffer.x86_emit_div_r64(right.id)
    }
    return
  }
  if operation is (Lsl | Asr | Lsr | Ror) {
    let working = if destination.id == 1 ||
      (destination == right && destination != left) {
      @vcode.PhysicalReg::new(10, Int)
    } else {
      destination
    }
    emit_move(buffer, integer_type(width), working, left)
    emit_move(
      buffer,
      integer_type(width),
      @vcode.PhysicalReg::new(1, Int),
      right,
    )
    match (width, operation) {
      (W32, Lsl) => buffer.x86_emit_shl_r32_cl(working.id)
      (W64, Lsl) => buffer.x86_emit_shl_r_cl(working.id)
      (W32, Asr) => buffer.x86_emit_sar_r32_cl(working.id)
      (W64, Asr) => buffer.x86_emit_sar_r_cl(working.id)
      (W32, Lsr) => buffer.x86_emit_shr_r32_cl(working.id)
      (W64, Lsr) => buffer.x86_emit_shr_r_cl(working.id)
      (W32, Ror) => buffer.x86_emit_ror_r32_cl(working.id)
      (W64, Ror) => buffer.x86_emit_ror_r_cl(working.id)
      _ => ()
    }
    emit_move(buffer, integer_type(width), destination, working)
    return
  }
  let working = if destination == right && destination != left {
    @vcode.PhysicalReg::new(10, Int)
  } else {
    destination
  }
  emit_move(buffer, integer_type(width), working, left)
  match (width, operation) {
    (W32, Add) => buffer.x86_emit_add_rr32(working.id, right.id)
    (W64, Add) => buffer.x86_emit_add_rr(working.id, right.id)
    (W32, Sub) => buffer.x86_emit_sub_rr32(working.id, right.id)
    (W64, Sub) => buffer.x86_emit_sub_rr(working.id, right.id)
    (W32, Mul) => buffer.x86_emit_imul_rr32(working.id, right.id)
    (W64, Mul) => buffer.x86_emit_imul_rr(working.id, right.id)
    (W32, And) => buffer.x86_emit_and_rr32(working.id, right.id)
    (W64, And) => buffer.x86_emit_and_rr(working.id, right.id)
    (W32, Orr) => buffer.x86_emit_or_rr32(working.id, right.id)
    (W64, Orr) => buffer.x86_emit_or_rr(working.id, right.id)
    (W32, Eor) => buffer.x86_emit_xor_rr32(working.id, right.id)
    (W64, Eor) => buffer.x86_emit_xor_rr(working.id, right.id)
    (_, Lsl | Asr | Lsr | Ror | Sdiv | Udiv) => ()
  }
  emit_move(buffer, integer_type(width), destination, working)
}

///|
fn emit_int_with_overflow(
  buffer : CodeBuffer,
  width : GprWidth,
  operation : @lowering.IntOverflowOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  result : @vcode.PhysicalReg,
  overflow : @vcode.PhysicalReg,
) -> Unit {
  match operation {
    Add(signedness) => {
      let working = if result == right && result != left {
        @vcode.PhysicalReg::new(10, Int)
      } else {
        result
      }
      emit_move(buffer, integer_type(width), working, left)
      if width == W32 {
        buffer.x86_emit_add_rr32(working.id, right.id)
      } else {
        buffer.x86_emit_add_rr(working.id, right.id)
      }
      buffer.x86_emit_setcc_r8(
        if signedness == Signed {
          RawVs
        } else {
          RawLo
        },
        overflow.id,
      )
      buffer.x86_emit_movzx_r32_r8(overflow.id, overflow.id)
      emit_move(buffer, integer_type(width), result, working)
    }
    Sub(signedness) => {
      let working = if result == right && result != left {
        @vcode.PhysicalReg::new(10, Int)
      } else {
        result
      }
      emit_move(buffer, integer_type(width), working, left)
      if width == W32 {
        buffer.x86_emit_sub_rr32(working.id, right.id)
      } else {
        buffer.x86_emit_sub_rr(working.id, right.id)
      }
      buffer.x86_emit_setcc_r8(
        if signedness == Signed {
          RawVs
        } else {
          RawLo
        },
        overflow.id,
      )
      buffer.x86_emit_movzx_r32_r8(overflow.id, overflow.id)
      emit_move(buffer, integer_type(width), result, working)
    }
    Mul(signedness) => {
      ignore(left)
      if width == W32 {
        if signedness == Signed {
          buffer.x86_emit_imul1_r32(right.id)
        } else {
          buffer.x86_emit_mul_r32(right.id)
        }
      } else if signedness == Signed {
        buffer.x86_emit_imul1_r64(right.id)
      } else {
        buffer.x86_emit_mul_r64(right.id)
      }
      buffer.x86_emit_setcc_r8(RawVs, overflow.id)
      buffer.x86_emit_movzx_r32_r8(overflow.id, overflow.id)
      ignore(result)
    }
  }
}

///|
fn emit_vector_constant(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  low : UInt64,
  high : UInt64,
) -> Unit {
  let scratch = @vcode.PhysicalReg::new(10, Int)
  emit_constant(buffer, W64, scratch, low)
  buffer.x86_emit_movq_xmm_r64(destination.id, scratch.id)
  emit_constant(buffer, W64, scratch, high)
  buffer.x86_emit_pinsrq_xmm_r64_imm8(destination.id, scratch.id, 1)
}

///|
fn emit_vector_select(
  buffer : CodeBuffer,
  condition : @vcode.PhysicalReg,
  when_true : @vcode.PhysicalReg,
  when_false : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  buffer.x86_emit_test_rr32(condition.id, condition.id)
  let false_branch = buffer.emit_local_jcc(RawEq)
  emit_move(buffer, V128, destination, when_true)
  let done = buffer.emit_local_jmp()
  buffer.patch_local_rel32(false_branch, buffer.position())
  emit_move(buffer, V128, destination, when_false)
  buffer.patch_local_rel32(done, buffer.position())
}

///|
fn emit_spectre_guard(
  buffer : CodeBuffer,
  condition : @vcode.PhysicalReg,
  true_address : @vcode.PhysicalReg,
  false_address : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  buffer.x86_emit_test_rr32(condition.id, condition.id)
  if destination == true_address {
    buffer.x86_emit_cmovcc_rr(RawEq, destination.id, false_address.id)
  } else {
    buffer.x86_emit_mov_rr(destination.id, false_address.id)
    buffer.x86_emit_cmovcc_rr(RawNe, destination.id, true_address.id)
  }
}

///|
fn emit_vector_splat(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  match lane {
    I8x16 => {
      buffer.x86_emit_movd_xmm_r32(destination.id, source.id)
      buffer.x86_emit_punpcklbw_xmm_xmm(destination.id, destination.id)
      buffer.x86_emit_pshuflw_xmm_xmm_imm8(destination.id, destination.id, 0)
      buffer.x86_emit_pshufd_xmm_xmm_imm8(destination.id, destination.id, 0)
    }
    I16x8 => {
      buffer.x86_emit_movd_xmm_r32(destination.id, source.id)
      buffer.x86_emit_pshuflw_xmm_xmm_imm8(destination.id, destination.id, 0)
      buffer.x86_emit_pshufd_xmm_xmm_imm8(destination.id, destination.id, 0)
    }
    I32x4 => {
      buffer.x86_emit_movd_xmm_r32(destination.id, source.id)
      buffer.x86_emit_pshufd_xmm_xmm_imm8(destination.id, destination.id, 0)
    }
    I64x2 => {
      buffer.x86_emit_movq_xmm_r64(destination.id, source.id)
      buffer.x86_emit_pshufd_xmm_xmm_imm8(destination.id, destination.id, 0x44)
    }
    F32x4 => {
      emit_move(buffer, F32, destination, source)
      buffer.x86_emit_shufps_xmm_xmm_imm8(destination.id, destination.id, 0)
    }
    F64x2 => {
      emit_move(buffer, F64, destination, source)
      buffer.x86_emit_shufpd_xmm_xmm_imm8(destination.id, destination.id, 0)
    }
  }
}

///|
fn emit_vector_extract_lane(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  index : Int,
  extension : @native.Signedness?,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  match lane {
    I8x16 => {
      buffer.x86_emit_pextrb_r32_xmm_imm8(destination.id, source.id, index)
      if extension is Some(Signed) {
        buffer.x86_emit_movsx_r32_r8(destination.id, destination.id)
      }
    }
    I16x8 => {
      buffer.x86_emit_pextrw_r32_xmm_imm8(destination.id, source.id, index)
      if extension is Some(Signed) {
        buffer.x86_emit_movsx_r32_r16(destination.id, destination.id)
      }
    }
    I32x4 =>
      buffer.x86_emit_pextrd_r32_xmm_imm8(destination.id, source.id, index)
    I64x2 =>
      buffer.x86_emit_pextrq_r64_xmm_imm8(destination.id, source.id, index)
    F32x4 => {
      emit_move(buffer, V128, destination, source)
      if index != 0 {
        buffer.x86_emit_pshufd_xmm_xmm_imm8(
          destination.id,
          destination.id,
          (index & 3) * 0x55,
        )
      }
    }
    F64x2 => {
      emit_move(buffer, V128, destination, source)
      if index == 1 {
        buffer.x86_emit_pshufd_xmm_xmm_imm8(
          destination.id,
          destination.id,
          0xEE,
        )
      }
    }
  }
}

///|
fn emit_vector_replace_lane(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  index : Int,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  match lane {
    I8x16 =>
      buffer.x86_emit_pinsrb_xmm_r32_imm8(destination.id, source.id, index)
    I16x8 =>
      buffer.x86_emit_pinsrw_xmm_r32_imm8(destination.id, source.id, index)
    I32x4 =>
      buffer.x86_emit_pinsrd_xmm_r32_imm8(destination.id, source.id, index)
    I64x2 =>
      buffer.x86_emit_pinsrq_xmm_r64_imm8(destination.id, source.id, index)
    F32x4 =>
      buffer.x86_emit_insertps_xmm_xmm_imm8(
        destination.id,
        source.id,
        (index & 3) << 4,
      )
    F64x2 =>
      if index == 0 {
        buffer.x86_emit_movsd_xmm_xmm(destination.id, source.id)
      } else {
        buffer.x86_emit_movlhps_xmm_xmm(destination.id, source.id)
      }
  }
}

///|
fn emit_vector_table_lookup(
  buffer : CodeBuffer,
  table : @vcode.PhysicalReg,
  indices : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit {
  let mask = @vcode.PhysicalReg::new(15, FpVector)
  let constant = @vcode.PhysicalReg::new(14, FpVector)
  emit_move(buffer, V128, destination, table)
  emit_move(buffer, V128, mask, indices)
  emit_vector_constant(
    buffer, constant, 0x7070707070707070UL, 0x7070707070707070UL,
  )
  buffer.x86_emit_paddusb_xmm_xmm(mask.id, constant.id)
  buffer.x86_emit_pshufb_xmm_xmm(destination.id, mask.id)
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
  let first_copy = @vcode.PhysicalReg::new(14, FpVector)
  let second_copy = @vcode.PhysicalReg::new(15, FpVector)
  emit_move(buffer, V128, first_copy, first)
  emit_move(buffer, V128, second_copy, second)
  emit_vector_constant(buffer, destination, first_low, first_high)
  buffer.x86_emit_pshufb_xmm_xmm(first_copy.id, destination.id)
  emit_vector_constant(buffer, destination, second_low, second_high)
  buffer.x86_emit_pshufb_xmm_xmm(second_copy.id, destination.id)
  emit_move(buffer, V128, destination, first_copy)
  buffer.x86_emit_por_xmm_xmm(destination.id, second_copy.id)
}

///|
fn raw_integer_lane(
  lane : @lowering.VectorLane,
) -> RawLaneSize raise X64EmitError {
  match lane {
    I8x16 => B8
    I16x8 => H16
    I32x4 => S32
    I64x2 => D64
    F32x4 | F64x2 => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_int_unary(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : X64VectorIntUnary,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let raw_lane = raw_integer_lane(lane)
  match operation {
    Absolute =>
      match lane {
        I8x16 => buffer.x86_emit_pabsb_xmm_xmm(destination.id, source.id)
        I16x8 => buffer.x86_emit_pabsw_xmm_xmm(destination.id, source.id)
        I32x4 => buffer.x86_emit_pabsd_xmm_xmm(destination.id, source.id)
        I64x2 => {
          let sign = @vcode.PhysicalReg::new(14, FpVector)
          emit_move(buffer, V128, destination, source)
          emit_move(buffer, V128, sign, source)
          buffer.x86_emit_psrad_xmm_imm8(sign.id, 31)
          buffer.x86_emit_pshufd_xmm_xmm_imm8(sign.id, sign.id, 0xF5)
          buffer.x86_emit_pxor_xmm_xmm(destination.id, sign.id)
          buffer.x86_emit_psub_xmm_xmm(D64, destination.id, sign.id)
        }
        _ => raise InvalidVectorInstruction
      }
    Negate => {
      let source_reg = if destination == source {
        let scratch = @vcode.PhysicalReg::new(14, FpVector)
        emit_move(buffer, V128, scratch, source)
        scratch
      } else {
        source
      }
      buffer.x86_emit_pxor_xmm_xmm(destination.id, destination.id)
      buffer.x86_emit_psub_xmm_xmm(raw_lane, destination.id, source_reg.id)
    }
    PopulationCount => {
      if lane != I8x16 {
        raise InvalidVectorInstruction
      }
      let source_copy = @vcode.PhysicalReg::new(14, FpVector)
      let table = @vcode.PhysicalReg::new(15, FpVector)
      emit_move(buffer, V128, source_copy, source)
      emit_vector_constant(
        buffer, destination, 0x0F0F0F0F0F0F0F0FUL, 0x0F0F0F0F0F0F0F0FUL,
      )
      buffer.x86_emit_pand_xmm_xmm(destination.id, source_copy.id)
      emit_vector_constant(
        buffer, table, 0x0302020102010100UL, 0x0403030203020201UL,
      )
      buffer.x86_emit_pshufb_xmm_xmm(table.id, destination.id)
      emit_move(buffer, V128, destination, source_copy)
      buffer.x86_emit_psrlw_xmm_imm8(destination.id, 4)
      emit_vector_constant(
        buffer, source_copy, 0x0F0F0F0F0F0F0F0FUL, 0x0F0F0F0F0F0F0F0FUL,
      )
      buffer.x86_emit_pand_xmm_xmm(destination.id, source_copy.id)
      emit_vector_constant(
        buffer, source_copy, 0x0302020102010100UL, 0x0403030203020201UL,
      )
      buffer.x86_emit_pshufb_xmm_xmm(source_copy.id, destination.id)
      buffer.x86_emit_padd_xmm_xmm(B8, table.id, source_copy.id)
      emit_move(buffer, V128, destination, table)
    }
    ExtendAddPairwise(signedness) =>
      match lane {
        I16x8 => {
          let ones = @vcode.PhysicalReg::new(14, FpVector)
          let input = if signedness == Signed && destination == source {
            let preserved = @vcode.PhysicalReg::new(15, FpVector)
            emit_move(buffer, V128, preserved, source)
            preserved
          } else {
            source
          }
          emit_vector_constant(
            buffer, ones, 0x0101010101010101UL, 0x0101010101010101UL,
          )
          if signedness == Signed {
            emit_move(buffer, V128, destination, ones)
            buffer.x86_emit_pmaddubsw_xmm_xmm(destination.id, input.id)
          } else {
            emit_move(buffer, V128, destination, source)
            buffer.x86_emit_pmaddubsw_xmm_xmm(destination.id, ones.id)
          }
        }
        I32x4 => {
          let ones = @vcode.PhysicalReg::new(14, FpVector)
          emit_move(buffer, V128, destination, source)
          if signedness == Unsigned {
            emit_vector_constant(
              buffer, ones, 0x8000800080008000UL, 0x8000800080008000UL,
            )
            buffer.x86_emit_pxor_xmm_xmm(destination.id, ones.id)
          }
          emit_vector_constant(
            buffer, ones, 0x0001000100010001UL, 0x0001000100010001UL,
          )
          buffer.x86_emit_pmaddwd_xmm_xmm(destination.id, ones.id)
          if signedness == Unsigned {
            emit_vector_constant(
              buffer, ones, 0x0001000000010000UL, 0x0001000000010000UL,
            )
            buffer.x86_emit_padd_xmm_xmm(S32, destination.id, ones.id)
          }
        }
        I64x2 => {
          let even = @vcode.PhysicalReg::new(14, FpVector)
          let odd = @vcode.PhysicalReg::new(15, FpVector)
          buffer.x86_emit_pshufd_xmm_xmm_imm8(even.id, source.id, 0x88)
          buffer.x86_emit_pshufd_xmm_xmm_imm8(odd.id, source.id, 0xDD)
          if signedness == Signed {
            buffer.x86_emit_pmovsxdq_xmm_xmm(even.id, even.id)
            buffer.x86_emit_pmovsxdq_xmm_xmm(odd.id, odd.id)
          } else {
            buffer.x86_emit_pmovzxdq_xmm_xmm(even.id, even.id)
            buffer.x86_emit_pmovzxdq_xmm_xmm(odd.id, odd.id)
          }
          buffer.x86_emit_padd_xmm_xmm(D64, even.id, odd.id)
          emit_move(buffer, V128, destination, even)
        }
        _ => raise InvalidVectorInstruction
      }
  }
}

///|
fn emit_vector_int_binary(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : X64VectorIntBinary,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let raw_lane = raw_integer_lane(lane)
  match operation {
    Add | Sub => {
      let source = prepare_xmm_two_operand(buffer, destination, left, right)
      if operation == Add {
        buffer.x86_emit_padd_xmm_xmm(raw_lane, destination.id, source.id)
      } else {
        buffer.x86_emit_psub_xmm_xmm(raw_lane, destination.id, source.id)
      }
    }
    Mul =>
      if lane == I8x16 {
        let right_copy = @vcode.PhysicalReg::new(14, FpVector)
        let high = @vcode.PhysicalReg::new(15, FpVector)
        emit_move(buffer, V128, destination, left)
        emit_move(buffer, V128, right_copy, right)
        emit_vector_constant(
          buffer, high, 0x00FF00FF00FF00FFUL, 0x00FF00FF00FF00FFUL,
        )
        buffer.x86_emit_pand_xmm_xmm(destination.id, high.id)
        buffer.x86_emit_pand_xmm_xmm(right_copy.id, high.id)
        buffer.x86_emit_pmullw_xmm_xmm(destination.id, right_copy.id)
        emit_move(buffer, V128, right_copy, left)
        buffer.x86_emit_psrlw_xmm_imm8(right_copy.id, 8)
        emit_move(buffer, V128, high, right)
        buffer.x86_emit_psrlw_xmm_imm8(high.id, 8)
        buffer.x86_emit_pmullw_xmm_xmm(right_copy.id, high.id)
        buffer.x86_emit_psllw_xmm_imm8(right_copy.id, 8)
        emit_vector_constant(
          buffer, high, 0x00FF00FF00FF00FFUL, 0x00FF00FF00FF00FFUL,
        )
        buffer.x86_emit_pand_xmm_xmm(destination.id, high.id)
        buffer.x86_emit_por_xmm_xmm(destination.id, right_copy.id)
      } else if lane == I16x8 || lane == I32x4 {
        let source = prepare_xmm_two_operand(buffer, destination, left, right)
        if lane == I16x8 {
          buffer.x86_emit_pmullw_xmm_xmm(destination.id, source.id)
        } else {
          buffer.x86_emit_pmulld_xmm_xmm(destination.id, source.id)
        }
      } else if lane == I64x2 {
        let left_source = if destination == left {
          let preserved = @vcode.PhysicalReg::new(14, FpVector)
          emit_move(buffer, V128, preserved, left)
          preserved
        } else {
          left
        }
        let right_source = if destination == right {
          if right == left {
            left_source
          } else {
            let preserved = @vcode.PhysicalReg::new(15, FpVector)
            emit_move(buffer, V128, preserved, right)
            preserved
          }
        } else {
          right
        }
        for index in 0..<2 {
          buffer.x86_emit_pextrq_r64_xmm_imm8(10, left_source.id, index)
          buffer.x86_emit_pextrq_r64_xmm_imm8(11, right_source.id, index)
          buffer.x86_emit_imul_rr(10, 11)
          if index == 0 {
            buffer.x86_emit_movq_xmm_r64(destination.id, 10)
          } else {
            buffer.x86_emit_pinsrq_xmm_r64_imm8(destination.id, 10, 1)
          }
        }
      } else {
        raise InvalidVectorInstruction
      }
    AverageUnsigned => {
      let source = prepare_xmm_two_operand(buffer, destination, left, right)
      if lane == I8x16 {
        buffer.x86_emit_pavgb_xmm_xmm(destination.id, source.id)
      } else if lane == I16x8 {
        buffer.x86_emit_pavgw_xmm_xmm(destination.id, source.id)
      } else {
        raise InvalidVectorInstruction
      }
    }
    Min(signedness) | Max(signedness) =>
      if lane == I64x2 {
        let left_source = if destination == left {
          let preserved = @vcode.PhysicalReg::new(14, FpVector)
          emit_move(buffer, V128, preserved, left)
          preserved
        } else {
          left
        }
        let right_source = if destination == right {
          if right == left {
            left_source
          } else {
            let preserved = @vcode.PhysicalReg::new(15, FpVector)
            emit_move(buffer, V128, preserved, right)
            preserved
          }
        } else {
          right
        }
        let choose_right = match (operation, signedness) {
          (Min(_), Signed) => RawGt
          (Min(_), Unsigned) => RawHi
          (Max(_), Signed) => RawLt
          (Max(_), Unsigned) => RawLo
          _ => RawAl
        }
        for index in 0..<2 {
          buffer.x86_emit_pextrq_r64_xmm_imm8(10, left_source.id, index)
          buffer.x86_emit_pextrq_r64_xmm_imm8(11, right_source.id, index)
          buffer.x86_emit_cmp_rr(10, 11)
          buffer.x86_emit_cmovcc_rr(choose_right, 10, 11)
          if index == 0 {
            buffer.x86_emit_movq_xmm_r64(destination.id, 10)
          } else {
            buffer.x86_emit_pinsrq_xmm_r64_imm8(destination.id, 10, 1)
          }
        }
      } else {
        let source = prepare_xmm_two_operand(buffer, destination, left, right)
        match (operation, signedness, lane) {
          (Min(_), Signed, I8x16) =>
            buffer.x86_emit_pminsb_xmm_xmm(destination.id, source.id)
          (Min(_), Signed, I16x8) =>
            buffer.x86_emit_pminsw_xmm_xmm(destination.id, source.id)
          (Min(_), Signed, I32x4) =>
            buffer.x86_emit_pminsd_xmm_xmm(destination.id, source.id)
          (Min(_), Unsigned, I8x16) =>
            buffer.x86_emit_pminub_xmm_xmm(destination.id, source.id)
          (Min(_), Unsigned, I16x8) =>
            buffer.x86_emit_pminuw_xmm_xmm(destination.id, source.id)
          (Min(_), Unsigned, I32x4) =>
            buffer.x86_emit_pminud_xmm_xmm(destination.id, source.id)
          (Max(_), Signed, I8x16) =>
            buffer.x86_emit_pmaxsb_xmm_xmm(destination.id, source.id)
          (Max(_), Signed, I16x8) =>
            buffer.x86_emit_pmaxsw_xmm_xmm(destination.id, source.id)
          (Max(_), Signed, I32x4) =>
            buffer.x86_emit_pmaxsd_xmm_xmm(destination.id, source.id)
          (Max(_), Unsigned, I8x16) =>
            buffer.x86_emit_pmaxub_xmm_xmm(destination.id, source.id)
          (Max(_), Unsigned, I16x8) =>
            buffer.x86_emit_pmaxuw_xmm_xmm(destination.id, source.id)
          (Max(_), Unsigned, I32x4) =>
            buffer.x86_emit_pmaxud_xmm_xmm(destination.id, source.id)
          _ => raise InvalidVectorInstruction
        }
      }
    SaturatingAdd(signedness) | SaturatingSub(signedness) => {
      let source = prepare_xmm_two_operand(buffer, destination, left, right)
      match (operation, signedness, lane) {
        (SaturatingAdd(_), Signed, I8x16) =>
          buffer.x86_emit_paddsb_xmm_xmm(destination.id, source.id)
        (SaturatingAdd(_), Signed, I16x8) =>
          buffer.x86_emit_paddsw_xmm_xmm(destination.id, source.id)
        (SaturatingAdd(_), Unsigned, I8x16) =>
          buffer.x86_emit_paddusb_xmm_xmm(destination.id, source.id)
        (SaturatingAdd(_), Unsigned, I16x8) =>
          buffer.x86_emit_paddusw_xmm_xmm(destination.id, source.id)
        (SaturatingSub(_), Signed, I8x16) =>
          buffer.x86_emit_psubsb_xmm_xmm(destination.id, source.id)
        (SaturatingSub(_), Signed, I16x8) =>
          buffer.x86_emit_psubsw_xmm_xmm(destination.id, source.id)
        (SaturatingSub(_), Unsigned, I8x16) =>
          buffer.x86_emit_psubusb_xmm_xmm(destination.id, source.id)
        (SaturatingSub(_), Unsigned, I16x8) =>
          buffer.x86_emit_psubusw_xmm_xmm(destination.id, source.id)
        _ => raise InvalidVectorInstruction
      }
    }
    ExtendMultiply(half, signedness) => {
      let first = @vcode.PhysicalReg::new(14, FpVector)
      let second = @vcode.PhysicalReg::new(15, FpVector)
      emit_vector_extension(buffer, lane, half == High, signedness, left, first)
      emit_vector_extension(
        buffer,
        lane,
        half == High,
        signedness,
        right,
        second,
      )
      emit_vector_int_binary(buffer, lane, Mul, first, second, destination)
    }
    Dot16To32Signed => {
      let source = prepare_xmm_two_operand(buffer, destination, left, right)
      buffer.x86_emit_pmaddwd_xmm_xmm(destination.id, source.id)
    }
    Q15MultiplyRoundedSaturating => {
      let source = prepare_xmm_two_operand(buffer, destination, left, right)
      buffer.x86_emit_pmulhrsw_xmm_xmm(destination.id, source.id)
      let minimum = @vcode.PhysicalReg::new(14, FpVector)
      let mask = @vcode.PhysicalReg::new(15, FpVector)
      emit_vector_constant(
        buffer, minimum, 0x8000800080008000UL, 0x8000800080008000UL,
      )
      emit_move(buffer, V128, mask, destination)
      buffer.x86_emit_pcmpeq_xmm_xmm(H16, mask.id, minimum.id)
      buffer.x86_emit_pxor_xmm_xmm(destination.id, mask.id)
    }
  }
}

///|
fn emit_vector_extension(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  high : Bool,
  signedness : @native.Signedness,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let input = if high {
    emit_move(buffer, V128, destination, source)
    if lane == I64x2 {
      buffer.x86_emit_pshufd_xmm_xmm_imm8(destination.id, destination.id, 0xEE)
    } else {
      buffer.x86_emit_palignr_xmm_xmm_imm8(destination.id, destination.id, 8)
    }
    destination
  } else {
    source
  }
  match (lane, signedness) {
    (I16x8, Signed) =>
      buffer.x86_emit_pmovsxbw_xmm_xmm(destination.id, input.id)
    (I16x8, Unsigned) =>
      buffer.x86_emit_pmovzxbw_xmm_xmm(destination.id, input.id)
    (I32x4, Signed) =>
      buffer.x86_emit_pmovsxwd_xmm_xmm(destination.id, input.id)
    (I32x4, Unsigned) =>
      buffer.x86_emit_pmovzxwd_xmm_xmm(destination.id, input.id)
    (I64x2, Signed) =>
      buffer.x86_emit_pmovsxdq_xmm_xmm(destination.id, input.id)
    (I64x2, Unsigned) =>
      buffer.x86_emit_pmovzxdq_xmm_xmm(destination.id, input.id)
    _ => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_narrow(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  signedness : @native.Signedness,
  low : @vcode.PhysicalReg,
  high : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let high_source = prepare_xmm_two_operand(buffer, destination, low, high)
  match (lane, signedness) {
    (I8x16, Signed) =>
      buffer.x86_emit_packsswb_xmm_xmm(destination.id, high_source.id)
    (I8x16, Unsigned) =>
      buffer.x86_emit_packuswb_xmm_xmm(destination.id, high_source.id)
    (I16x8, Signed) =>
      buffer.x86_emit_packssdw_xmm_xmm(destination.id, high_source.id)
    (I16x8, Unsigned) =>
      buffer.x86_emit_packusdw_xmm_xmm(destination.id, high_source.id)
    _ => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_conversion(
  buffer : CodeBuffer,
  conversion : X64VectorConversion,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let first = @vcode.PhysicalReg::new(14, FpVector)
  let second = @vcode.PhysicalReg::new(15, FpVector)
  match conversion {
    FloatToInt(F32x4, signedness) =>
      if signedness == Signed {
        emit_move(buffer, V128, first, source)
        buffer.x86_emit_cmpps_xmm_xmm_imm8(first.id, first.id, 0)
        emit_move(buffer, V128, destination, source)
        buffer.x86_emit_andps_xmm_xmm(destination.id, first.id)
        buffer.x86_emit_pxor_xmm_xmm(first.id, destination.id)
        buffer.x86_emit_cvttps2dq_xmm_xmm(destination.id, destination.id)
        buffer.x86_emit_pand_xmm_xmm(first.id, destination.id)
        buffer.x86_emit_psrad_xmm_imm8(first.id, 31)
        buffer.x86_emit_pxor_xmm_xmm(destination.id, first.id)
      } else {
        buffer.x86_emit_pxor_xmm_xmm(second.id, second.id)
        emit_move(buffer, V128, destination, source)
        buffer.x86_emit_maxps_xmm_xmm(destination.id, second.id)
        buffer.x86_emit_pcmpeqd_xmm_xmm(second.id, second.id)
        buffer.x86_emit_psrld_xmm_imm8(second.id, 1)
        buffer.x86_emit_cvtdq2ps_xmm_xmm(second.id, second.id)
        emit_move(buffer, V128, first, destination)
        buffer.x86_emit_cvttps2dq_xmm_xmm(destination.id, destination.id)
        buffer.x86_emit_subps_xmm_xmm(first.id, second.id)
        buffer.x86_emit_cmpps_xmm_xmm_imm8(second.id, first.id, 2)
        buffer.x86_emit_cvttps2dq_xmm_xmm(first.id, first.id)
        buffer.x86_emit_pxor_xmm_xmm(first.id, second.id)
        buffer.x86_emit_pxor_xmm_xmm(second.id, second.id)
        buffer.x86_emit_pmaxsd_xmm_xmm(first.id, second.id)
        buffer.x86_emit_padd_xmm_xmm(S32, destination.id, first.id)
      }
    FloatToInt(F64x2, signedness) =>
      if signedness == Signed {
        emit_move(buffer, V128, first, source)
        buffer.x86_emit_cmppd_xmm_xmm_imm8(first.id, first.id, 0)
        emit_vector_constant(
          buffer, second, 0x41DFFFFFFFC00000UL, 0x41DFFFFFFFC00000UL,
        )
        buffer.x86_emit_andpd_xmm_xmm(first.id, second.id)
        emit_move(buffer, V128, destination, source)
        buffer.x86_emit_minpd_xmm_xmm(destination.id, first.id)
        buffer.x86_emit_cvttpd2dq_xmm_xmm(destination.id, destination.id)
      } else {
        buffer.x86_emit_xorpd_xmm_xmm(second.id, second.id)
        emit_move(buffer, V128, destination, source)
        buffer.x86_emit_maxpd_xmm_xmm(destination.id, second.id)
        emit_vector_constant(
          buffer, first, 0x41EFFFFFFFE00000UL, 0x41EFFFFFFFE00000UL,
        )
        buffer.x86_emit_minpd_xmm_xmm(destination.id, first.id)
        buffer.x86_emit_roundpd_xmm_xmm_imm8(destination.id, destination.id, 3)
        emit_vector_constant(
          buffer, first, 0x4330000000000000UL, 0x4330000000000000UL,
        )
        buffer.x86_emit_addpd_xmm_xmm(destination.id, first.id)
        buffer.x86_emit_shufps_xmm_xmm_imm8(destination.id, second.id, 0x88)
      }
    IntToFloat(F32x4, signedness) =>
      if signedness == Signed {
        buffer.x86_emit_cvtdq2ps_xmm_xmm(destination.id, source.id)
      } else {
        emit_move(buffer, V128, first, source)
        buffer.x86_emit_pslld_xmm_imm8(first.id, 16)
        buffer.x86_emit_psrld_xmm_imm8(first.id, 16)
        emit_move(buffer, V128, second, source)
        buffer.x86_emit_psub_xmm_xmm(S32, second.id, first.id)
        buffer.x86_emit_cvtdq2ps_xmm_xmm(first.id, first.id)
        buffer.x86_emit_psrld_xmm_imm8(second.id, 1)
        buffer.x86_emit_cvtdq2ps_xmm_xmm(second.id, second.id)
        buffer.x86_emit_addps_xmm_xmm(second.id, second.id)
        emit_move(buffer, V128, destination, second)
        buffer.x86_emit_addps_xmm_xmm(destination.id, first.id)
      }
    IntToFloat(F64x2, signedness) =>
      if signedness == Signed {
        buffer.x86_emit_cvtdq2pd_xmm_xmm(destination.id, source.id)
      } else {
        emit_vector_constant(buffer, first, 0x4330000043300000UL, 0UL)
        emit_move(buffer, V128, destination, source)
        buffer.x86_emit_unpcklps_xmm_xmm(destination.id, first.id)
        emit_vector_constant(
          buffer, first, 0x4330000000000000UL, 0x4330000000000000UL,
        )
        buffer.x86_emit_subpd_xmm_xmm(destination.id, first.id)
      }
    PromoteLowF32x4 =>
      buffer.x86_emit_cvtps2pd_xmm_xmm(destination.id, source.id)
    DemoteZeroF64x2 => {
      let input = if destination == source {
        emit_move(buffer, V128, first, source)
        first
      } else {
        source
      }
      buffer.x86_emit_xorps_xmm_xmm(destination.id, destination.id)
      buffer.x86_emit_cvtpd2ps_xmm_xmm(destination.id, input.id)
    }
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
  predicate : X64VectorPredicate,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  if predicate is BitMask(lane) {
    emit_vector_bitmask(buffer, lane, source, destination)
    return
  }
  let zero = @vcode.PhysicalReg::new(14, FpVector)
  let work = @vcode.PhysicalReg::new(15, FpVector)
  buffer.x86_emit_pxor_xmm_xmm(zero.id, zero.id)
  emit_move(buffer, V128, work, source)
  match predicate {
    AnyTrue => buffer.x86_emit_pcmpeq_xmm_xmm(B8, work.id, zero.id)
    AllTrue(I8x16) => buffer.x86_emit_pcmpeq_xmm_xmm(B8, work.id, zero.id)
    AllTrue(I16x8) => buffer.x86_emit_pcmpeq_xmm_xmm(H16, work.id, zero.id)
    AllTrue(I32x4) => buffer.x86_emit_pcmpeq_xmm_xmm(S32, work.id, zero.id)
    AllTrue(I64x2) => {
      buffer.x86_emit_pcmpeq_xmm_xmm(S32, work.id, zero.id)
      buffer.x86_emit_pshufd_xmm_xmm_imm8(zero.id, work.id, 0xB1)
      buffer.x86_emit_pand_xmm_xmm(work.id, zero.id)
    }
    AllTrue(F32x4 | F64x2) => raise InvalidVectorInstruction
    BitMask(_) => raise InvalidVectorInstruction
  }
  buffer.x86_emit_pmovmskb_r32_xmm(destination.id, work.id)
  buffer.x86_emit_cmp_r32_imm32(
    destination.id,
    if predicate == AnyTrue {
      0xFFFF
    } else {
      0
    },
  )
  buffer.x86_emit_setcc_r8(
    if predicate == AnyTrue {
      RawNe
    } else {
      RawEq
    },
    destination.id,
  )
  buffer.x86_emit_movzx_r32_r8(destination.id, destination.id)
}

///|
fn emit_vector_bitmask(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match lane {
    I8x16 => buffer.x86_emit_pmovmskb_r32_xmm(destination.id, source.id)
    I32x4 => buffer.x86_emit_movmskps_r32_xmm(destination.id, source.id)
    I64x2 => buffer.x86_emit_movmskpd_r32_xmm(destination.id, source.id)
    I16x8 => {
      let packed = @vcode.PhysicalReg::new(10, Int)
      let bit = @vcode.PhysicalReg::new(11, Int)
      buffer.x86_emit_pmovmskb_r32_xmm(packed.id, source.id)
      emit_constant(buffer, W32, destination, 0UL)
      for index in 0..<8 {
        buffer.x86_emit_mov_rr32(bit.id, packed.id)
        buffer.x86_emit_shr_r32_imm8(bit.id, index * 2 + 1)
        buffer.x86_emit_and_r_imm8_sxb64(bit.id, 1)
        if index > 0 {
          buffer.x86_emit_shl_r32_imm8(bit.id, index)
        }
        buffer.x86_emit_or_rr32(destination.id, bit.id)
      }
    }
    F32x4 | F64x2 => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_int_shift(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : @lowering.VectorIntShiftOp,
  source : @vcode.PhysicalReg,
  amount : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let raw_lane = raw_integer_lane(lane)
  let mask = match lane {
    I8x16 => 7
    I16x8 => 15
    I32x4 => 31
    I64x2 => 63
    _ => raise InvalidVectorInstruction
  }
  buffer.x86_emit_mov_rr32(10, amount.id)
  buffer.x86_emit_and_r_imm8_sxb64(10, mask)
  buffer.x86_emit_movd_xmm_r32(15, 10)
  emit_move(buffer, V128, destination, source)
  match operation {
    Left =>
      if lane == I8x16 {
        let low = @vcode.PhysicalReg::new(14, FpVector)
        emit_move(buffer, V128, low, source)
        buffer.x86_emit_pxor_xmm_xmm(15, 15)
        buffer.x86_emit_punpcklbw_xmm_xmm(low.id, 15)
        buffer.x86_emit_punpckhbw_xmm_xmm(destination.id, 15)
        buffer.x86_emit_movd_xmm_r32(15, 10)
        buffer.x86_emit_psll_xmm_xmm(H16, low.id, 15)
        buffer.x86_emit_psll_xmm_xmm(H16, destination.id, 15)
        emit_vector_constant(
          buffer,
          @vcode.PhysicalReg::new(15, FpVector),
          0x00FF00FF00FF00FFUL,
          0x00FF00FF00FF00FFUL,
        )
        buffer.x86_emit_pand_xmm_xmm(low.id, 15)
        buffer.x86_emit_pand_xmm_xmm(destination.id, 15)
        buffer.x86_emit_packuswb_xmm_xmm(low.id, destination.id)
        emit_move(buffer, V128, destination, low)
      } else {
        buffer.x86_emit_psll_xmm_xmm(raw_lane, destination.id, 15)
      }
    Right(Unsigned) =>
      if lane == I8x16 {
        let low = @vcode.PhysicalReg::new(14, FpVector)
        emit_move(buffer, V128, low, source)
        buffer.x86_emit_pxor_xmm_xmm(15, 15)
        buffer.x86_emit_punpcklbw_xmm_xmm(low.id, 15)
        buffer.x86_emit_punpckhbw_xmm_xmm(destination.id, 15)
        buffer.x86_emit_movd_xmm_r32(15, 10)
        buffer.x86_emit_psrl_xmm_xmm(H16, low.id, 15)
        buffer.x86_emit_psrl_xmm_xmm(H16, destination.id, 15)
        buffer.x86_emit_packuswb_xmm_xmm(low.id, destination.id)
        emit_move(buffer, V128, destination, low)
      } else {
        buffer.x86_emit_psrl_xmm_xmm(raw_lane, destination.id, 15)
      }
    Right(Signed) =>
      match lane {
        I8x16 => {
          let low = @vcode.PhysicalReg::new(14, FpVector)
          emit_move(buffer, V128, low, source)
          buffer.x86_emit_punpcklbw_xmm_xmm(low.id, low.id)
          buffer.x86_emit_punpckhbw_xmm_xmm(destination.id, destination.id)
          buffer.x86_emit_add_r_imm8(10, 8)
          buffer.x86_emit_movd_xmm_r32(15, 10)
          buffer.x86_emit_psra_xmm_xmm(H16, low.id, 15)
          buffer.x86_emit_psra_xmm_xmm(H16, destination.id, 15)
          buffer.x86_emit_packsswb_xmm_xmm(low.id, destination.id)
          emit_move(buffer, V128, destination, low)
        }
        I16x8 | I32x4 =>
          buffer.x86_emit_psra_xmm_xmm(raw_lane, destination.id, 15)
        I64x2 => {
          let sign = @vcode.PhysicalReg::new(14, FpVector)
          emit_vector_constant(
            buffer, sign, 0x8000000000000000UL, 0x8000000000000000UL,
          )
          buffer.x86_emit_psrl_xmm_xmm(D64, sign.id, 15)
          buffer.x86_emit_psrl_xmm_xmm(D64, destination.id, 15)
          buffer.x86_emit_pxor_xmm_xmm(destination.id, sign.id)
          buffer.x86_emit_psub_xmm_xmm(D64, destination.id, sign.id)
        }
        _ => raise InvalidVectorInstruction
      }
  }
}

///|
fn emit_vector_int_compare(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  comparison : @lowering.VectorIntComparison,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let raw_lane = raw_integer_lane(lane)
  if lane == I64x2 {
    let left_source = if destination == left {
      let preserved = @vcode.PhysicalReg::new(14, FpVector)
      emit_move(buffer, V128, preserved, left)
      preserved
    } else {
      left
    }
    let right_source = if destination == right {
      if right == left {
        left_source
      } else {
        let preserved = @vcode.PhysicalReg::new(15, FpVector)
        emit_move(buffer, V128, preserved, right)
        preserved
      }
    } else {
      right
    }
    let condition = match comparison {
      Equal => RawEq
      NotEqual => RawNe
      LessThan(Signed) => RawLt
      LessThan(Unsigned) => RawLo
      LessOrEqual(Signed) => RawLe
      LessOrEqual(Unsigned) => RawLs
      GreaterThan(Signed) => RawGt
      GreaterThan(Unsigned) => RawHi
      GreaterOrEqual(Signed) => RawGe
      GreaterOrEqual(Unsigned) => RawHs
    }
    for index in 0..<2 {
      buffer.x86_emit_pextrq_r64_xmm_imm8(10, left_source.id, index)
      buffer.x86_emit_pextrq_r64_xmm_imm8(11, right_source.id, index)
      buffer.x86_emit_cmp_rr(10, 11)
      buffer.x86_emit_setcc_r8(condition, 10)
      buffer.x86_emit_movzx_r32_r8(10, 10)
      buffer.x86_emit_neg_r64(10)
      if index == 0 {
        buffer.x86_emit_movq_xmm_r64(destination.id, 10)
      } else {
        buffer.x86_emit_pinsrq_xmm_r64_imm8(destination.id, 10, 1)
      }
    }
    return
  }
  if comparison == Equal || comparison == NotEqual {
    let source = prepare_xmm_two_operand(buffer, destination, left, right)
    buffer.x86_emit_pcmpeq_xmm_xmm(raw_lane, destination.id, source.id)
    if comparison == NotEqual {
      let ones = @vcode.PhysicalReg::new(14, FpVector)
      buffer.x86_emit_pcmpeqd_xmm_xmm(ones.id, ones.id)
      buffer.x86_emit_pxor_xmm_xmm(destination.id, ones.id)
    }
    return
  }
  let (first, second, signedness, invert) = match comparison {
    GreaterThan(signedness) => (left, right, signedness, false)
    LessThan(signedness) => (right, left, signedness, false)
    GreaterOrEqual(signedness) => (right, left, signedness, true)
    LessOrEqual(signedness) => (left, right, signedness, true)
    _ => raise InvalidVectorInstruction
  }
  if signedness == Signed {
    let source = prepare_xmm_two_operand(buffer, destination, first, second)
    buffer.x86_emit_pcmpgt_xmm_xmm(raw_lane, destination.id, source.id)
  } else {
    let mask = @vcode.PhysicalReg::new(14, FpVector)
    let second_copy = @vcode.PhysicalReg::new(15, FpVector)
    let pattern = match lane {
      I8x16 => 0x8080808080808080UL
      I16x8 => 0x8000800080008000UL
      I32x4 => 0x8000000080000000UL
      _ => 0UL
    }
    emit_vector_constant(buffer, mask, pattern, pattern)
    emit_move(buffer, V128, second_copy, second)
    emit_move(buffer, V128, destination, first)
    buffer.x86_emit_pxor_xmm_xmm(destination.id, mask.id)
    buffer.x86_emit_pxor_xmm_xmm(second_copy.id, mask.id)
    buffer.x86_emit_pcmpgt_xmm_xmm(raw_lane, destination.id, second_copy.id)
  }
  if invert {
    let ones = @vcode.PhysicalReg::new(14, FpVector)
    buffer.x86_emit_pcmpeqd_xmm_xmm(ones.id, ones.id)
    buffer.x86_emit_pxor_xmm_xmm(destination.id, ones.id)
  }
}

///|
fn emit_vector_float_unary(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : @lowering.VectorFloatUnaryOp,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let f32 = lane == F32x4
  if !f32 && lane != F64x2 {
    raise InvalidVectorInstruction
  }
  match operation {
    Absolute | Negate => {
      emit_move(buffer, V128, destination, source)
      let mask = @vcode.PhysicalReg::new(14, FpVector)
      buffer.x86_emit_pcmpeqd_xmm_xmm(mask.id, mask.id)
      if operation == Absolute {
        if f32 {
          buffer.x86_emit_psrld_xmm_imm8(mask.id, 1)
        } else {
          buffer.x86_emit_psrlq_xmm_imm8(mask.id, 1)
        }
        buffer.x86_emit_pand_xmm_xmm(destination.id, mask.id)
      } else {
        if f32 {
          buffer.x86_emit_pslld_xmm_imm8(mask.id, 31)
        } else {
          buffer.x86_emit_psllq_xmm_imm8(mask.id, 63)
        }
        buffer.x86_emit_pxor_xmm_xmm(destination.id, mask.id)
      }
    }
    SquareRoot =>
      if f32 {
        buffer.x86_emit_sqrtps_xmm_xmm(destination.id, source.id)
      } else {
        buffer.x86_emit_sqrtpd_xmm_xmm(destination.id, source.id)
      }
    Ceil | Floor | Truncate | Nearest => {
      let mode = match operation {
        Nearest => 0
        Floor => 1
        Ceil => 2
        Truncate => 3
        _ => 0
      }
      if f32 {
        buffer.x86_emit_roundps_xmm_xmm_imm8(destination.id, source.id, mode)
      } else {
        buffer.x86_emit_roundpd_xmm_xmm_imm8(destination.id, source.id, mode)
      }
    }
  }
}

///|
fn emit_vector_float_binary(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : @lowering.VectorFloatBinaryOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let f32 = lane == F32x4
  if !f32 && lane != F64x2 {
    raise InvalidVectorInstruction
  }
  if operation == Min || operation == Max {
    let first = @vcode.PhysicalReg::new(14, FpVector)
    let second = @vcode.PhysicalReg::new(15, FpVector)
    emit_move(buffer, V128, first, left)
    emit_move(buffer, V128, second, right)
    if operation == Min {
      if f32 {
        buffer.x86_emit_minps_xmm_xmm(first.id, right.id)
        buffer.x86_emit_minps_xmm_xmm(second.id, left.id)
      } else {
        buffer.x86_emit_minpd_xmm_xmm(first.id, right.id)
        buffer.x86_emit_minpd_xmm_xmm(second.id, left.id)
      }
      buffer.x86_emit_por_xmm_xmm(first.id, second.id)
      if f32 {
        buffer.x86_emit_cmpps_xmm_xmm_imm8(second.id, first.id, 3)
      } else {
        buffer.x86_emit_cmppd_xmm_xmm_imm8(second.id, first.id, 3)
      }
      buffer.x86_emit_por_xmm_xmm(first.id, second.id)
      if f32 {
        buffer.x86_emit_psrld_xmm_imm8(second.id, 10)
      } else {
        buffer.x86_emit_psrlq_xmm_imm8(second.id, 13)
      }
      buffer.x86_emit_pandn_xmm_xmm(second.id, first.id)
      emit_move(buffer, V128, destination, second)
    } else {
      if f32 {
        buffer.x86_emit_maxps_xmm_xmm(first.id, right.id)
        buffer.x86_emit_maxps_xmm_xmm(second.id, left.id)
      } else {
        buffer.x86_emit_maxpd_xmm_xmm(first.id, right.id)
        buffer.x86_emit_maxpd_xmm_xmm(second.id, left.id)
      }
      buffer.x86_emit_pxor_xmm_xmm(second.id, first.id)
      buffer.x86_emit_por_xmm_xmm(first.id, second.id)
      if f32 {
        buffer.x86_emit_subps_xmm_xmm(first.id, second.id)
      } else {
        buffer.x86_emit_subpd_xmm_xmm(first.id, second.id)
      }
      emit_move(buffer, V128, second, first)
      if f32 {
        buffer.x86_emit_cmpps_xmm_xmm_imm8(second.id, second.id, 3)
        buffer.x86_emit_psrld_xmm_imm8(second.id, 10)
      } else {
        buffer.x86_emit_cmppd_xmm_xmm_imm8(second.id, second.id, 3)
        buffer.x86_emit_psrlq_xmm_imm8(second.id, 13)
      }
      buffer.x86_emit_pandn_xmm_xmm(second.id, first.id)
      emit_move(buffer, V128, destination, second)
    }
    return
  }
  if operation == PseudoMin || operation == PseudoMax {
    let source = prepare_xmm_two_operand(buffer, destination, right, left)
    if f32 {
      if operation == PseudoMin {
        buffer.x86_emit_minps_xmm_xmm(destination.id, source.id)
      } else {
        buffer.x86_emit_maxps_xmm_xmm(destination.id, source.id)
      }
    } else if operation == PseudoMin {
      buffer.x86_emit_minpd_xmm_xmm(destination.id, source.id)
    } else {
      buffer.x86_emit_maxpd_xmm_xmm(destination.id, source.id)
    }
    return
  }
  let source = prepare_xmm_two_operand(buffer, destination, left, right)
  match (f32, operation) {
    (true, Add) => buffer.x86_emit_addps_xmm_xmm(destination.id, source.id)
    (false, Add) => buffer.x86_emit_addpd_xmm_xmm(destination.id, source.id)
    (true, Sub) => buffer.x86_emit_subps_xmm_xmm(destination.id, source.id)
    (false, Sub) => buffer.x86_emit_subpd_xmm_xmm(destination.id, source.id)
    (true, Mul) => buffer.x86_emit_mulps_xmm_xmm(destination.id, source.id)
    (false, Mul) => buffer.x86_emit_mulpd_xmm_xmm(destination.id, source.id)
    (true, Div) => buffer.x86_emit_divps_xmm_xmm(destination.id, source.id)
    (false, Div) => buffer.x86_emit_divpd_xmm_xmm(destination.id, source.id)
    _ => raise InvalidVectorInstruction
  }
}

///|
fn emit_vector_float_compare(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  comparison : @lowering.VectorFloatComparison,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let f32 = lane == F32x4
  if !f32 && lane != F64x2 {
    raise InvalidVectorInstruction
  }
  let (first, second, predicate) = match comparison {
    Equal => (left, right, 0)
    NotEqual => (left, right, 4)
    LessThan => (left, right, 1)
    LessOrEqual => (left, right, 2)
    GreaterThan => (right, left, 1)
    GreaterOrEqual => (right, left, 2)
  }
  let source = prepare_xmm_two_operand(buffer, destination, first, second)
  if f32 {
    buffer.x86_emit_cmpps_xmm_xmm_imm8(destination.id, source.id, predicate)
  } else {
    buffer.x86_emit_cmppd_xmm_xmm_imm8(destination.id, source.id, predicate)
  }
}

///|
fn emit_vector_float_ternary(
  buffer : CodeBuffer,
  lane : @lowering.VectorLane,
  operation : @lowering.FloatTernaryOp,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  addend : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let f64 = if lane == F64x2 {
    true
  } else if lane == F32x4 {
    false
  } else {
    raise InvalidVectorInstruction
  }
  let selected = match operation {
    FusedMultiplyAdd => Fmadd
    FusedMultiplySubtract => Fmsub
    FusedNegatedMultiplyAdd => Fnmadd
    FusedNegatedMultiplySubtract => Fnmsub
  }
  let right_reg = if destination == right {
    let scratch = @vcode.PhysicalReg::new(14, FpVector)
    emit_move(buffer, V128, scratch, right)
    scratch
  } else {
    right
  }
  let addend_reg = if destination == addend {
    let scratch = @vcode.PhysicalReg::new(15, FpVector)
    emit_move(buffer, V128, scratch, addend)
    scratch
  } else {
    addend
  }
  emit_move(buffer, V128, destination, left)
  buffer.x86_emit_fma213(
    false,
    f64,
    selected,
    destination.id,
    right_reg.id,
    addend_reg.id,
  )
}

///|
fn emit_vector_relaxed_dot8_to16(
  buffer : CodeBuffer,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let source = prepare_xmm_two_operand(buffer, destination, right, left)
  buffer.x86_emit_pmaddubsw_xmm_xmm(destination.id, source.id)
}

///|
fn emit_vector_bitwise(
  buffer : CodeBuffer,
  operation : @lowering.VectorBitwiseOp,
  first : @vcode.PhysicalReg,
  second : @vcode.PhysicalReg,
  mask : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match operation {
    Not => {
      emit_move(buffer, V128, destination, first)
      let ones = @vcode.PhysicalReg::new(14, FpVector)
      buffer.x86_emit_pcmpeqd_xmm_xmm(ones.id, ones.id)
      buffer.x86_emit_pxor_xmm_xmm(destination.id, ones.id)
    }
    And | Or | Xor => {
      let source = prepare_xmm_two_operand(buffer, destination, first, second)
      match operation {
        And => buffer.x86_emit_pand_xmm_xmm(destination.id, source.id)
        Or => buffer.x86_emit_por_xmm_xmm(destination.id, source.id)
        Xor => buffer.x86_emit_pxor_xmm_xmm(destination.id, source.id)
        _ => ()
      }
    }
    AndNot => {
      let scratch = @vcode.PhysicalReg::new(14, FpVector)
      emit_move(buffer, V128, scratch, second)
      buffer.x86_emit_pandn_xmm_xmm(scratch.id, first.id)
      emit_move(buffer, V128, destination, scratch)
    }
    BitSelect => {
      let second_copy = @vcode.PhysicalReg::new(15, FpVector)
      let mask_copy = @vcode.PhysicalReg::new(14, FpVector)
      emit_move(buffer, V128, second_copy, second)
      emit_move(buffer, V128, mask_copy, mask)
      emit_move(buffer, V128, destination, first)
      buffer.x86_emit_pxor_xmm_xmm(destination.id, second_copy.id)
      buffer.x86_emit_pand_xmm_xmm(destination.id, mask_copy.id)
      buffer.x86_emit_pxor_xmm_xmm(destination.id, second_copy.id)
    }
  }
}

///|
fn prepare_xmm_two_operand(
  buffer : CodeBuffer,
  destination : @vcode.PhysicalReg,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
) -> @vcode.PhysicalReg raise X64EmitError {
  if destination == left {
    return right
  }
  if destination == right {
    let scratch = if left.id != 14 && right.id != 14 {
      @vcode.PhysicalReg::new(14, FpVector)
    } else if left.id != 15 && right.id != 15 {
      @vcode.PhysicalReg::new(15, FpVector)
    } else {
      raise ScratchRegisterUnavailable
    }
    buffer.x86_emit_movaps_xmm_xmm(scratch.id, right.id)
    buffer.x86_emit_movaps_xmm_xmm(destination.id, left.id)
    return scratch
  }
  buffer.x86_emit_movaps_xmm_xmm(destination.id, left.id)
  right
}

///|
fn materialize_scalar_mask(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  bits : UInt64,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let scratch = @vcode.PhysicalReg::new(10, Int)
  match ty {
    F32 => {
      emit_constant(buffer, W32, scratch, bits)
      buffer.x86_emit_movd_xmm_r32(destination.id, scratch.id)
    }
    F64 => {
      emit_constant(buffer, W64, scratch, bits)
      buffer.x86_emit_movq_xmm_r64(destination.id, scratch.id)
    }
    _ => raise InvalidFloatInstruction
  }
}

///|
fn emit_float_unary(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  operation : X64FloatUnary,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match operation {
    SquareRoot =>
      if ty == F32 {
        buffer.x86_emit_sqrtss_xmm_xmm(destination.id, source.id)
      } else if ty == F64 {
        buffer.x86_emit_sqrtsd_xmm_xmm(destination.id, source.id)
      } else {
        raise InvalidFloatInstruction
      }
    Ceil | Floor | Truncate | Nearest => {
      let mode = match operation {
        Nearest => 0
        Floor => 1
        Ceil => 2
        Truncate => 3
        _ => 0
      }
      if ty == F32 {
        buffer.x86_emit_roundss_xmm_xmm_imm8(destination.id, source.id, mode)
      } else if ty == F64 {
        buffer.x86_emit_roundsd_xmm_xmm_imm8(destination.id, source.id, mode)
      } else {
        raise InvalidFloatInstruction
      }
    }
    Negate | Absolute => {
      emit_move(buffer, ty, destination, source)
      let mask = @vcode.PhysicalReg::new(
        if destination.id == 14 {
          15
        } else {
          14
        },
        FpVector,
      )
      let bits = match (ty, operation) {
        (F32, Negate) => 0x80000000UL
        (F64, Negate) => 0x8000000000000000UL
        (F32, Absolute) => 0x7FFFFFFFUL
        (F64, Absolute) => 0x7FFFFFFFFFFFFFFFUL
        _ => raise InvalidFloatInstruction
      }
      materialize_scalar_mask(buffer, ty, bits, mask)
      match (ty, operation) {
        (F32, Negate) => buffer.x86_emit_xorps_xmm_xmm(destination.id, mask.id)
        (F64, Negate) => buffer.x86_emit_xorpd_xmm_xmm(destination.id, mask.id)
        (F32, Absolute) =>
          buffer.x86_emit_andps_xmm_xmm(destination.id, mask.id)
        (F64, Absolute) =>
          buffer.x86_emit_andpd_xmm_xmm(destination.id, mask.id)
        _ => raise InvalidFloatInstruction
      }
    }
  }
}

///|
fn emit_scalar_min_max(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  minimum : Bool,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let scratch = @vcode.PhysicalReg::new(
    if destination.id == 14 {
      15
    } else {
      14
    },
    FpVector,
  )
  let left_reg = if destination == right {
    left
  } else if destination == left {
    buffer.x86_emit_movaps_xmm_xmm(scratch.id, left.id)
    buffer.x86_emit_movaps_xmm_xmm(destination.id, right.id)
    scratch
  } else {
    buffer.x86_emit_movaps_xmm_xmm(destination.id, right.id)
    left
  }
  if ty == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(destination.id, left_reg.id)
  } else if ty == F64 {
    buffer.x86_emit_ucomisd_xmm_xmm(destination.id, left_reg.id)
  } else {
    raise InvalidFloatInstruction
  }
  let do_native = buffer.emit_local_jcc(RawNe)
  let propagate_nan = buffer.emit_local_jcc(RawPs)
  match (ty, minimum) {
    (F32, true) => buffer.x86_emit_orps_xmm_xmm(destination.id, left_reg.id)
    (F32, false) => buffer.x86_emit_andps_xmm_xmm(destination.id, left_reg.id)
    (F64, true) => buffer.x86_emit_orpd_xmm_xmm(destination.id, left_reg.id)
    (F64, false) => buffer.x86_emit_andpd_xmm_xmm(destination.id, left_reg.id)
    _ => raise InvalidFloatInstruction
  }
  let ordered_done = buffer.emit_local_jmp()
  buffer.patch_local_rel32(propagate_nan, buffer.position())
  if ty == F32 {
    buffer.x86_emit_addss_xmm_xmm(destination.id, left_reg.id)
  } else {
    buffer.x86_emit_addsd_xmm_xmm(destination.id, left_reg.id)
  }
  let nan_done = buffer.emit_local_jmp()
  buffer.patch_local_rel32(do_native, buffer.position())
  match (ty, minimum) {
    (F32, true) => buffer.x86_emit_minss_xmm_xmm(destination.id, left_reg.id)
    (F32, false) => buffer.x86_emit_maxss_xmm_xmm(destination.id, left_reg.id)
    (F64, true) => buffer.x86_emit_minsd_xmm_xmm(destination.id, left_reg.id)
    (F64, false) => buffer.x86_emit_maxsd_xmm_xmm(destination.id, left_reg.id)
    _ => raise InvalidFloatInstruction
  }
  buffer.patch_local_rel32(ordered_done, buffer.position())
  buffer.patch_local_rel32(nan_done, buffer.position())
}

///|
fn emit_float_binary(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  operation : X64FloatBinary,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  if operation == Min || operation == Max {
    emit_scalar_min_max(buffer, ty, operation == Min, left, right, destination)
    return
  }
  let source = prepare_xmm_two_operand(buffer, destination, left, right)
  match (ty, operation) {
    (F32, Add) => buffer.x86_emit_addss_xmm_xmm(destination.id, source.id)
    (F64, Add) => buffer.x86_emit_addsd_xmm_xmm(destination.id, source.id)
    (F32, Sub) => buffer.x86_emit_subss_xmm_xmm(destination.id, source.id)
    (F64, Sub) => buffer.x86_emit_subsd_xmm_xmm(destination.id, source.id)
    (F32, Mul) => buffer.x86_emit_mulss_xmm_xmm(destination.id, source.id)
    (F64, Mul) => buffer.x86_emit_mulsd_xmm_xmm(destination.id, source.id)
    (F32, Div) => buffer.x86_emit_divss_xmm_xmm(destination.id, source.id)
    (F64, Div) => buffer.x86_emit_divsd_xmm_xmm(destination.id, source.id)
    _ => raise InvalidFloatInstruction
  }
}

///|
fn emit_float_copy_sign(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  magnitude : @vcode.PhysicalReg,
  sign : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let int_scratch = @vcode.PhysicalReg::new(10, Int)
  let fp_scratch = @vcode.PhysicalReg::new(
    if destination.id == 14 {
      15
    } else {
      14
    },
    FpVector,
  )
  match ty {
    F32 => {
      emit_constant(buffer, W32, int_scratch, 0x80000000UL)
      buffer.x86_emit_movd_xmm_r32(fp_scratch.id, int_scratch.id)
    }
    F64 => {
      emit_constant(buffer, W64, int_scratch, 0x8000000000000000UL)
      buffer.x86_emit_movq_xmm_r64(fp_scratch.id, int_scratch.id)
    }
    _ => raise InvalidFloatInstruction
  }
  emit_move(buffer, ty, destination, magnitude)
  match ty {
    F32 => {
      buffer.x86_emit_andps_xmm_xmm(fp_scratch.id, sign.id)
      let clear = @vcode.PhysicalReg::new(
        if fp_scratch.id == 14 {
          15
        } else {
          14
        },
        FpVector,
      )
      materialize_scalar_mask(buffer, F32, 0x7FFFFFFFUL, clear)
      buffer.x86_emit_andps_xmm_xmm(destination.id, clear.id)
      buffer.x86_emit_orps_xmm_xmm(destination.id, fp_scratch.id)
    }
    F64 => {
      buffer.x86_emit_andpd_xmm_xmm(fp_scratch.id, sign.id)
      let clear = @vcode.PhysicalReg::new(
        if fp_scratch.id == 14 {
          15
        } else {
          14
        },
        FpVector,
      )
      materialize_scalar_mask(buffer, F64, 0x7FFFFFFFFFFFFFFFUL, clear)
      buffer.x86_emit_andpd_xmm_xmm(destination.id, clear.id)
      buffer.x86_emit_orpd_xmm_xmm(destination.id, fp_scratch.id)
    }
    _ => raise InvalidFloatInstruction
  }
}

///|
fn emit_float_compare(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  condition : X64FloatCondition,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let swapped = condition == LessThan || condition == LessOrEqual
  let first = if swapped { right } else { left }
  let second = if swapped { left } else { right }
  if ty == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(first.id, second.id)
  } else if ty == F64 {
    buffer.x86_emit_ucomisd_xmm_xmm(first.id, second.id)
  } else {
    raise InvalidFloatInstruction
  }
  let result = destination.id
  let scratch = 10
  match condition {
    Equal => {
      buffer.x86_emit_setcc_r8(RawEq, result)
      buffer.x86_emit_setcc_r8(RawPc, scratch)
      buffer.x86_emit_movzx_r32_r8(result, result)
      buffer.x86_emit_movzx_r32_r8(scratch, scratch)
      buffer.x86_emit_and_rr32(result, scratch)
    }
    NotEqual => {
      buffer.x86_emit_setcc_r8(RawNe, result)
      buffer.x86_emit_setcc_r8(RawPs, scratch)
      buffer.x86_emit_movzx_r32_r8(result, result)
      buffer.x86_emit_movzx_r32_r8(scratch, scratch)
      buffer.x86_emit_or_rr32(result, scratch)
    }
    LessThan | GreaterThan => {
      buffer.x86_emit_setcc_r8(RawHi, result)
      buffer.x86_emit_movzx_r32_r8(result, result)
    }
    LessOrEqual | GreaterOrEqual => {
      buffer.x86_emit_setcc_r8(RawHs, result)
      buffer.x86_emit_movzx_r32_r8(result, result)
    }
    Ordered => {
      buffer.x86_emit_setcc_r8(RawPc, result)
      buffer.x86_emit_movzx_r32_r8(result, result)
    }
    Unordered => {
      buffer.x86_emit_setcc_r8(RawPs, result)
      buffer.x86_emit_movzx_r32_r8(result, result)
    }
  }
}

///|
fn emit_float_trap(
  buffer : CodeBuffer,
  ty : @native.ValueType,
  condition : X64FloatTrapCondition,
  left : @vcode.PhysicalReg,
  right : @vcode.PhysicalReg,
) -> Int raise X64EmitError {
  let second = if condition == Unordered { left } else { right }
  if ty == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(left.id, second.id)
  } else if ty == F64 {
    buffer.x86_emit_ucomisd_xmm_xmm(left.id, second.id)
  } else {
    raise InvalidFloatInstruction
  }
  let trap_condition = match condition {
    Unordered => RawPs
    LessThan => RawLo
    LessOrEqual => RawLs
    GreaterOrEqual => RawHs
  }
  let skip = buffer.emit_local_jcc(
    match trap_condition {
      RawPs => RawPc
      RawLo => RawHs
      RawLs => RawHi
      RawHs => RawLo
      _ => RawAl
    },
  )
  let trap_offset = buffer.position()
  buffer.x86_emit_trap_imm16(X64_INVALID_CONVERSION_BRK.reinterpret_as_int())
  buffer.patch_local_rel32(skip, buffer.position())
  trap_offset
}

///|
fn emit_unchecked_float_to_int(
  buffer : CodeBuffer,
  float : @native.FloatType,
  integer : @native.IntegerType,
  signedness : @native.Signedness,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  if signedness == Signed {
    match (float, integer) {
      (F32, I32) => buffer.x86_emit_cvttss2si_r32_xmm(destination.id, source.id)
      (F32, I64) => buffer.x86_emit_cvttss2si_r64_xmm(destination.id, source.id)
      (F64, I32) => buffer.x86_emit_cvttsd2si_r32_xmm(destination.id, source.id)
      (F64, I64) => buffer.x86_emit_cvttsd2si_r64_xmm(destination.id, source.id)
    }
  } else if integer == I32 {
    if float == F32 {
      buffer.x86_emit_cvttss2si_r64_xmm(destination.id, source.id)
    } else {
      buffer.x86_emit_cvttsd2si_r64_xmm(destination.id, source.id)
    }
  } else {
    let scalar_type : @native.ValueType = if float == F32 { F32 } else { F64 }
    let threshold = @vcode.PhysicalReg::new(15, FpVector)
    let adjusted = @vcode.PhysicalReg::new(14, FpVector)
    materialize_scalar_mask(
      buffer,
      scalar_type,
      if float == F32 {
        0x5F000000UL
      } else {
        0x43E0000000000000UL
      },
      threshold,
    )
    if float == F32 {
      buffer.x86_emit_ucomiss_xmm_xmm(source.id, threshold.id)
    } else {
      buffer.x86_emit_ucomisd_xmm_xmm(source.id, threshold.id)
    }
    let below = buffer.emit_local_jcc(RawLo)
    emit_move(buffer, scalar_type, adjusted, source)
    if float == F32 {
      buffer.x86_emit_subss_xmm_xmm(adjusted.id, threshold.id)
      buffer.x86_emit_cvttss2si_r64_xmm(destination.id, adjusted.id)
    } else {
      buffer.x86_emit_subsd_xmm_xmm(adjusted.id, threshold.id)
      buffer.x86_emit_cvttsd2si_r64_xmm(destination.id, adjusted.id)
    }
    emit_constant(
      buffer,
      W64,
      @vcode.PhysicalReg::new(10, Int),
      0x8000000000000000UL,
    )
    buffer.x86_emit_or_rr(destination.id, 10)
    let done = buffer.emit_local_jmp()
    buffer.patch_local_rel32(below, buffer.position())
    if float == F32 {
      buffer.x86_emit_cvttss2si_r64_xmm(destination.id, source.id)
    } else {
      buffer.x86_emit_cvttsd2si_r64_xmm(destination.id, source.id)
    }
    buffer.patch_local_rel32(done, buffer.position())
  }
}

///|
fn emit_saturating_float_to_int(
  buffer : CodeBuffer,
  float : @native.FloatType,
  integer : @native.IntegerType,
  signedness : @native.Signedness,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  let scalar_type : @native.ValueType = if float == F32 { F32 } else { F64 }
  let width = if integer == I32 { W32 } else { W64 }
  let (lower_bits, upper_bits, minimum, maximum) = match
    (float, integer, signedness) {
    (F32, I32, Signed) =>
      (0xCF000000UL, 0x4F000000UL, 0x80000000UL, 0x7FFFFFFFUL)
    (F32, I32, Unsigned) => (0UL, 0x4F800000UL, 0UL, 0xFFFFFFFFUL)
    (F32, I64, Signed) =>
      (0xDF000000UL, 0x5F000000UL, 0x8000000000000000UL, 0x7FFFFFFFFFFFFFFFUL)
    (F32, I64, Unsigned) => (0UL, 0x5F800000UL, 0UL, 0xFFFFFFFFFFFFFFFFUL)
    (F64, I32, Signed) =>
      (0xC1E0000000000000UL, 0x41E0000000000000UL, 0x80000000UL, 0x7FFFFFFFUL)
    (F64, I32, Unsigned) => (0UL, 0x41F0000000000000UL, 0UL, 0xFFFFFFFFUL)
    (F64, I64, Signed) =>
      (
        0xC3E0000000000000UL, 0x43E0000000000000UL, 0x8000000000000000UL, 0x7FFFFFFFFFFFFFFFUL,
      )
    (F64, I64, Unsigned) =>
      (0UL, 0x43F0000000000000UL, 0UL, 0xFFFFFFFFFFFFFFFFUL)
  }
  if float == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(source.id, source.id)
  } else {
    buffer.x86_emit_ucomisd_xmm_xmm(source.id, source.id)
  }
  let nan = buffer.emit_local_jcc(RawPs)
  let threshold = @vcode.PhysicalReg::new(15, FpVector)
  materialize_scalar_mask(buffer, scalar_type, lower_bits, threshold)
  if float == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(source.id, threshold.id)
  } else {
    buffer.x86_emit_ucomisd_xmm_xmm(source.id, threshold.id)
  }
  let below = buffer.emit_local_jcc(
    if signedness == Signed {
      RawLo
    } else {
      RawLs
    },
  )
  materialize_scalar_mask(buffer, scalar_type, upper_bits, threshold)
  if float == F32 {
    buffer.x86_emit_ucomiss_xmm_xmm(source.id, threshold.id)
  } else {
    buffer.x86_emit_ucomisd_xmm_xmm(source.id, threshold.id)
  }
  let above = buffer.emit_local_jcc(RawHs)
  emit_unchecked_float_to_int(
    buffer, float, integer, signedness, source, destination,
  )
  let normal_done = buffer.emit_local_jmp()
  let zero_label = buffer.position()
  buffer.patch_local_rel32(nan, zero_label)
  if signedness == Unsigned {
    buffer.patch_local_rel32(below, zero_label)
  }
  emit_constant(buffer, width, destination, 0UL)
  let zero_done = buffer.emit_local_jmp()
  let mut minimum_done : Int? = None
  if signedness == Signed {
    buffer.patch_local_rel32(below, buffer.position())
    emit_constant(buffer, width, destination, minimum)
    minimum_done = Some(buffer.emit_local_jmp())
  }
  buffer.patch_local_rel32(above, buffer.position())
  emit_constant(buffer, width, destination, maximum)
  let done = buffer.position()
  buffer.patch_local_rel32(normal_done, done)
  buffer.patch_local_rel32(zero_done, done)
  if minimum_done is Some(branch) {
    buffer.patch_local_rel32(branch, done)
  }
}

///|
fn emit_conversion(
  buffer : CodeBuffer,
  conversion : X64Conversion,
  source : @vcode.PhysicalReg,
  destination : @vcode.PhysicalReg,
) -> Unit raise X64EmitError {
  match conversion {
    WrapI64ToI32 => emit_move(buffer, I32, destination, source)
    ExtendI32ToI64(Unsigned) =>
      buffer.x86_emit_mov_rr32(destination.id, source.id)
    ExtendI32ToI64(Signed) =>
      buffer.x86_emit_movsxd_r64_r32(destination.id, source.id)
    SignExtend(integer, width) =>
      match (integer, width) {
        (I32, W8) => buffer.x86_emit_movsx_r32_r8(destination.id, source.id)
        (I32, W16) => buffer.x86_emit_movsx_r32_r16(destination.id, source.id)
        (I64, W8) => buffer.x86_emit_movsx_r64_r8(destination.id, source.id)
        (I64, W16) => buffer.x86_emit_movsx_r64_r16(destination.id, source.id)
        (I64, W32) => buffer.x86_emit_movsxd_r64_r32(destination.id, source.id)
        _ => raise InvalidConversionInstruction
      }
    DemoteF64ToF32 =>
      buffer.x86_emit_cvtsd2ss_xmm_xmm(destination.id, source.id)
    PromoteF32ToF64 =>
      buffer.x86_emit_cvtss2sd_xmm_xmm(destination.id, source.id)
    Bitcast(from, to) =>
      match (from, to) {
        (I32, F32) => buffer.x86_emit_movd_xmm_r32(destination.id, source.id)
        (F32, I32) => buffer.x86_emit_movd_r32_xmm(destination.id, source.id)
        (I64 | Ptr64, F64) =>
          buffer.x86_emit_movq_xmm_r64(destination.id, source.id)
        (F64, I64 | Ptr64) =>
          buffer.x86_emit_movq_r64_xmm(destination.id, source.id)
        _ =>
          if @vcode.reg_class_for_value_type(from) ==
            @vcode.reg_class_for_value_type(to) {
            emit_move(buffer, to, destination, source)
          } else {
            raise InvalidConversionInstruction
          }
      }
    IntToFloat(integer, float, signedness) =>
      match (integer, float, signedness) {
        (I32, F32, Signed) =>
          buffer.x86_emit_cvtsi2ss_xmm_r32(destination.id, source.id)
        (I32, F64, Signed) =>
          buffer.x86_emit_cvtsi2sd_xmm_r32(destination.id, source.id)
        (I64, F32, Signed) =>
          buffer.x86_emit_cvtsi2ss_xmm_r64(destination.id, source.id)
        (I64, F64, Signed) =>
          buffer.x86_emit_cvtsi2sd_xmm_r64(destination.id, source.id)
        (I32, F32, Unsigned) => {
          let zero_extended = @vcode.PhysicalReg::new(10, Int)
          buffer.x86_emit_mov_rr32(zero_extended.id, source.id)
          buffer.x86_emit_cvtsi2ss_xmm_r64(destination.id, zero_extended.id)
        }
        (I32, F64, Unsigned) => {
          let zero_extended = @vcode.PhysicalReg::new(10, Int)
          buffer.x86_emit_mov_rr32(zero_extended.id, source.id)
          buffer.x86_emit_cvtsi2sd_xmm_r64(destination.id, zero_extended.id)
        }
        (I64, F32 | F64, Unsigned) => {
          buffer.x86_emit_test_rr(source.id, source.id)
          let nonnegative = buffer.emit_local_jcc(RawPl)
          let first = @vcode.PhysicalReg::new(10, Int)
          let second = @vcode.PhysicalReg::new(11, Int)
          buffer.x86_emit_mov_rr(first.id, source.id)
          buffer.x86_emit_shr_r_imm8(first.id, 1)
          buffer.x86_emit_mov_rr(second.id, source.id)
          buffer.x86_emit_and_r_imm8_sxb64(second.id, 1)
          buffer.x86_emit_or_rr(second.id, first.id)
          if float == F32 {
            buffer.x86_emit_cvtsi2ss_xmm_r64(destination.id, second.id)
            buffer.x86_emit_addss_xmm_xmm(destination.id, destination.id)
          } else {
            buffer.x86_emit_cvtsi2sd_xmm_r64(destination.id, second.id)
            buffer.x86_emit_addsd_xmm_xmm(destination.id, destination.id)
          }
          let done = buffer.emit_local_jmp()
          buffer.patch_local_rel32(nonnegative, buffer.position())
          if float == F32 {
            buffer.x86_emit_cvtsi2ss_xmm_r64(destination.id, source.id)
          } else {
            buffer.x86_emit_cvtsi2sd_xmm_r64(destination.id, source.id)
          }
          buffer.patch_local_rel32(done, buffer.position())
        }
      }
    FloatToInt(float, integer, signedness) =>
      emit_unchecked_float_to_int(
        buffer, float, integer, signedness, source, destination,
      )
    FloatToIntSaturating(float, integer, signedness) =>
      emit_saturating_float_to_int(
        buffer, float, integer, signedness, source, destination,
      )
  }
}

///|
fn emit_register_save_or_restore(
  buffer : CodeBuffer,
  load : Bool,
  reg : @vcode.PhysicalReg,
  offset : Int,
) -> Unit raise X64EmitError {
  match reg.class {
    Int => emit_stack_access(buffer, load, I64, reg, offset)
    Float | Vector | FpVector =>
      emit_stack_access(buffer, load, V128, reg, offset)
  }
}

///|
fn emit_prologue(
  buffer : CodeBuffer,
  frame : X64Frame,
  unwind : Array[@code_object.UnwindDirective],
) -> Unit raise X64EmitError {
  if frame.has_setup_area() {
    buffer.x86_emit_push_r64(5)
    unwind.push(
      @code_object.UnwindDirective::new(buffer.position(), StackAlloc(size=8)),
    )
    unwind.push(
      @code_object.UnwindDirective::new(
        buffer.position(),
        SaveRegister(Int, 5, cfa_offset=-16),
      ),
    )
    buffer.x86_emit_mov_rr(5, 4)
    unwind.push(
      @code_object.UnwindDirective::new(
        buffer.position(),
        SetFramePointer(Int, 5, cfa_offset=16),
      ),
    )
  }
  emit_sp_adjust(buffer, true, frame.allocation_size(), unwind~)
  for saved in frame.saved_registers() {
    let (reg, offset) = saved
    emit_register_save_or_restore(buffer, false, reg, offset)
    let bank : @code_object.RegisterBank = match reg.class {
      Int => Int
      Float | Vector | FpVector => FpVector
    }
    unwind.push(
      @code_object.UnwindDirective::new(
        buffer.position(),
        SaveRegister(
          bank,
          reg.id,
          cfa_offset=offset - frame.allocation_size() - 16,
        ),
      ),
    )
  }
}

///|
fn emit_epilogue(
  buffer : CodeBuffer,
  frame : X64Frame,
) -> Unit raise X64EmitError {
  let saved = frame.saved_registers()
  for reverse_index in 0..<saved.length() {
    let (reg, offset) = saved[saved.length() - reverse_index - 1]
    emit_register_save_or_restore(buffer, true, reg, offset)
  }
  emit_sp_adjust(buffer, false, frame.allocation_size())
  if frame.has_setup_area() {
    buffer.x86_emit_pop_r64(5)
  }
}

///|
fn[Inst] edit_parallel_moves(
  function : @vcode.Function[Inst],
  allocation : @vcode.Allocation,
  instruction : @vcode.Instruction,
  placement : @vcode.PointPlacement,
) -> Array[@vcode.ParallelMove] {
  let moves : Array[@vcode.ParallelMove] = []
  for edit in allocation.edits_at(instruction, placement) {
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
  moves
}

///|
fn[Inst] emit_edits_at(
  buffer : CodeBuffer,
  function : @vcode.Function[Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  instruction : @vcode.Instruction,
  placement : @vcode.PointPlacement,
) -> Unit raise X64EmitError {
  if allocation.edits_at(instruction, placement).is_empty() {
    return
  }
  let resolved = @vcode.plan_parallel_moves(
    edit_parallel_moves(function, allocation, instruction, placement),
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
}

///|
fn emit_call_arguments(
  buffer : CodeBuffer,
  allocation : @vcode.Allocation,
  frame : X64Frame,
  instruction : @vcode.Instruction,
  types : Array[@native.ValueType],
  locations : Array[CallArgumentLocation],
  stack_size : Int,
  operand_start? : Int = 0,
  stack_base? : Int = 0,
  callee? : (Int, @vcode.PhysicalReg),
  result_area? : (Int, @vcode.PhysicalReg),
) -> Unit raise X64EmitError {
  let transfers : Array[@vcode.CallTransfer] = []
  for index, ty in types {
    let source = allocation
      .operand_location(instruction, operand_start + index)
      .unwrap()
    match locations[index] {
      CallRegister(destination) =>
        transfers.push(
          @vcode.CallTransfer::to_register(ty, source, destination),
        )
      CallStack(offset) =>
        transfers.push(
          @vcode.CallTransfer::to_stack(ty, source, stack_base + offset),
        )
    }
  }
  if callee is Some((operand_index, destination)) {
    transfers.push(
      @vcode.CallTransfer::to_register(
        Ptr64,
        allocation.operand_location(instruction, operand_index).unwrap(),
        destination,
      ),
    )
  }
  if result_area is Some((operand_index, destination)) {
    transfers.push(
      @vcode.CallTransfer::to_register(
        Ptr64,
        allocation.operand_location(instruction, operand_index).unwrap(),
        destination,
      ),
    )
  }
  let int_scratch : Array[@vcode.PhysicalReg] = []
  for id in [10, 11, 0] {
    let used_by_callee = callee is Some((_, destination)) &&
      destination.id == id
    let used_by_result_area = result_area is Some((_, destination)) &&
      destination.id == id
    if !used_by_callee && !used_by_result_area {
      int_scratch.push(@vcode.PhysicalReg::new(id, Int))
    }
  }
  let plan = @vcode.plan_resolved_call_transfers(
    allocation,
    transfers,
    stack_base,
    stack_size,
    int_scratch,
    [
      @vcode.PhysicalReg::new(14, FpVector),
      @vcode.PhysicalReg::new(15, FpVector),
    ],
    int_transfer_scratch(),
    fp_transfer_scratch(),
    allocation.safepoint_roots(instruction).map(entry => entry.1),
  ) catch {
    error => raise InvalidCallTransfer(cause=error)
  }
  for transfer in plan.stack_transfers {
    let source = match transfer.source {
      Register(reg) => reg
      Stack(slot) => {
        let scratch = transfer.scratch.unwrap()
        emit_stack_access(
          buffer,
          true,
          transfer.ty,
          scratch,
          frame.slot_offset(slot).unwrap(),
        )
        scratch
      }
    }
    // Integer call slots are eight bytes. Write the full slot so its upper
    // half is canonical for callees that consume the native-width value.
    let stack_type : @native.ValueType = if transfer.ty == I32 {
      I64
    } else {
      transfer.ty
    }
    emit_stack_access(buffer, false, stack_type, source, transfer.offset)
  }
  emit_resolved_moves(buffer, frame, plan.register_moves)
}

///|
fn emit_tail_return_thunk_setup(
  buffer : CodeBuffer,
  plan : TailCallFramePlan,
) -> Int? raise X64EmitError {
  if plan.synthetic_return_size > 0 {
    emit_sp_adjust(buffer, true, plan.transfer_size)
    emit_rex_w(buffer, 1, 0)
    buffer.emit_byte(0x8D)
    emit_modrm(buffer, 0, 10, 5)
    let displacement = buffer.position()
    emit_u32_le(buffer, 0)
    buffer.x86_emit_mov_m64_r64(4, 0, 10)
    return Some(displacement)
  }
  None
}

///|
fn emit_tail_return_thunk(
  buffer : CodeBuffer,
  plan : TailCallFramePlan,
  thunk_address : Int?,
) -> Unit raise X64EmitError {
  if plan.synthetic_return_size > 0 {
    buffer.patch_local_rel32(thunk_address.unwrap(), buffer.position())
    emit_sp_adjust(buffer, false, plan.thunk_cleanup_size)
    buffer.x86_emit_ret()
  }
}

///|
fn is_incoming_call_result(instruction : X64Inst) -> Bool {
  match instruction {
    IncomingCallResult(_, _) | IncomingCallAreaResult(_, _) => true
    _ => false
  }
}

///|
fn is_function_input(instruction : X64Inst) -> Bool {
  match instruction {
    IncomingReg(_, _) | IncomingStack(_, _) | IncomingResultArea(_) => true
    _ => false
  }
}

///|
fn value_home(
  function : @vcode.Function[X64Inst],
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
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise X64EmitError {
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
  let stack_inputs : Array[(@vcode.Instruction, @native.ValueType, Int)] = []
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
  let resolved = @vcode.plan_parallel_moves(
    register_moves,
    int_transfer_scratch(),
    fp_transfer_scratch(),
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
          frame.frame_size() + 8 + offset,
        )
      Stack(slot) => {
        let scratch = @vcode.PhysicalReg::new(
          if @vcode.reg_class_for_value_type(ty) == Int {
            10
          } else {
            14
          },
          @vcode.reg_class_for_value_type(ty),
        )
        emit_stack_access(
          buffer,
          true,
          ty,
          scratch,
          frame.frame_size() + 8 + offset,
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
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise X64EmitError {
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
  let area_results : Array[(@vcode.Instruction, @native.ValueType, Int)] = []
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
  let resolved = @vcode.plan_parallel_moves(
    register_moves,
    int_transfer_scratch(),
    fp_transfer_scratch(),
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
fn is_function_output(instruction : X64Inst) -> Bool {
  match instruction {
    OutgoingReg(_, _) | OutgoingAreaResult(_, _) => true
    _ => false
  }
}

///|
fn is_abi_materialization(instruction : X64Inst) -> Bool {
  is_function_input(instruction) ||
  is_incoming_call_result(instruction) ||
  is_function_output(instruction)
}

///|
fn emit_function_outputs(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
) -> Unit raise X64EmitError {
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
  let area_results : Array[(@vcode.Instruction, @native.ValueType, Int)] = []
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
        let scratch = @vcode.PhysicalReg::new(10, Int)
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
          11
        } else {
          14
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
  let resolved = @vcode.plan_parallel_moves(
    register_moves,
    int_transfer_scratch(),
    fp_transfer_scratch(),
  ) catch {
    error => raise InvalidParallelMove(cause=error)
  }
  emit_resolved_moves(buffer, frame, resolved)
}

///|
fn emit_instruction(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
  block : @vcode.Block,
  instruction : @vcode.Instruction,
  next_block : @vcode.Block?,
) -> Int raise X64EmitError {
  let instruction_index = function.instruction_index(instruction).unwrap()
  let reg = fn(index : Int) -> @vcode.PhysicalReg raise X64EmitError {
    let location = allocation
      .allocated_operand_location_at(instruction_index, index)
      .unwrap()
    if location.is_register() {
      location.register_unchecked()
    } else {
      raise UnexpectedStackOperand(instruction~, operand=index)
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
      let immediate_offset = buffer.position() + 2
      buffer.x86_emit_mov_imm64(reg(0).id, 0L)
      buffer.relocations.push(
        @code_object.Relocation::new(immediate_offset, Absolute64, target),
      )
    }
    StackAddress(object) =>
      match frame.stack_object_offset(object) {
        Some(offset) => emit_stack_address(buffer, reg(0), offset)
        None => raise MissingStackObjectArea
      }
    LoadFloatConstant(ty, bits) => {
      let scratch = @vcode.PhysicalReg::new(10, Int)
      if ty == F32 {
        emit_constant(buffer, W32, scratch, bits)
        buffer.x86_emit_movd_xmm_r32(reg(0).id, scratch.id)
      } else if ty == F64 {
        emit_constant(buffer, W64, scratch, bits)
        buffer.x86_emit_movq_xmm_r64(reg(0).id, scratch.id)
      } else {
        raise InvalidFloatInstruction
      }
    }
    Move(ty) => emit_move(buffer, ty, reg(1), reg(0))
    CarrierMove(_, to) => emit_move(buffer, to, reg(1), reg(0))
    Select(ty) => {
      buffer.x86_emit_test_rr32(reg(0).id, reg(0).id)
      match ty {
        I32 =>
          if reg(3) == reg(1) {
            buffer.x86_emit_cmovcc_rr32(RawEq, reg(3).id, reg(2).id)
          } else {
            buffer.x86_emit_mov_rr32(reg(3).id, reg(2).id)
            buffer.x86_emit_cmovcc_rr32(RawNe, reg(3).id, reg(1).id)
          }
        I64 | Ptr64 | GcRef64 =>
          if reg(3) == reg(1) {
            buffer.x86_emit_cmovcc_rr(RawEq, reg(3).id, reg(2).id)
          } else {
            buffer.x86_emit_mov_rr(reg(3).id, reg(2).id)
            buffer.x86_emit_cmovcc_rr(RawNe, reg(3).id, reg(1).id)
          }
        F32 => {
          buffer.x86_emit_movd_r32_xmm(10, reg(1).id)
          buffer.x86_emit_movd_r32_xmm(11, reg(2).id)
          buffer.x86_emit_cmovcc_rr32(RawNe, 11, 10)
          buffer.x86_emit_movd_xmm_r32(reg(3).id, 11)
        }
        F64 => {
          buffer.x86_emit_movq_r64_xmm(10, reg(1).id)
          buffer.x86_emit_movq_r64_xmm(11, reg(2).id)
          buffer.x86_emit_cmovcc_rr(RawNe, 11, 10)
          buffer.x86_emit_movq_xmm_r64(reg(3).id, 11)
        }
        V128 => raise InvalidFloatInstruction
      }
    }
    SpectreGuard =>
      // CMOV preserves the bounds-condition data dependency without creating
      // a second branch for the processor to mispredict.
      emit_spectre_guard(buffer, reg(0), reg(1), reg(2), reg(3))
    VectorSelect => emit_vector_select(buffer, reg(0), reg(1), reg(2), reg(3))
    VectorSplat(lane) => emit_vector_splat(buffer, lane, reg(0), reg(1))
    VectorExtractLane(lane, index, extension) =>
      emit_vector_extract_lane(buffer, lane, index, extension, reg(0), reg(1))
    VectorReplaceLane(lane, index) => {
      emit_move(buffer, V128, reg(2), reg(0))
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
    VectorPairwiseAddI16x8 => {
      let source = prepare_xmm_two_operand(buffer, reg(2), reg(0), reg(1))
      buffer.x86_emit_phaddw_xmm_xmm(reg(2).id, source.id)
    }
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
      emit_int_unary(width, buffer, operation, reg(1), reg(0))
    IntBinary(width, operation) =>
      emit_int_binary(buffer, width, operation, reg(2), reg(0), reg(1))
    PopulationCount(width) =>
      emit_population_count(buffer, width, reg(1), reg(0))
    IntHighMultiply(width, signedness) =>
      if width == W64 {
        if signedness == Signed {
          buffer.x86_emit_imul1_r64(reg(1).id)
        } else {
          buffer.x86_emit_mul_r64(reg(1).id)
        }
      } else if signedness == Signed {
        buffer.x86_emit_imul1_r32(reg(1).id)
      } else {
        buffer.x86_emit_mul_r32(reg(1).id)
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
    IntRemainder(width, signedness) =>
      if signedness == Signed {
        if width == W32 {
          buffer.x86_emit_cmp_r32_imm32(reg(1).id, -1)
        } else {
          buffer.x86_emit_cmp_r_imm32(reg(1).id, -1)
        }
        let divide = buffer.emit_local_jcc(RawNe)
        if width == W32 {
          buffer.x86_emit_xor_rr32(reg(2).id, reg(2).id)
        } else {
          buffer.x86_emit_xor_rr(reg(2).id, reg(2).id)
        }
        let done = buffer.emit_local_jmp()
        buffer.patch_local_rel32(divide, buffer.position())
        emit_int_binary(buffer, width, Sdiv, reg(0), reg(0), reg(1))
        buffer.patch_local_rel32(done, buffer.position())
      } else {
        emit_int_binary(buffer, width, Udiv, reg(0), reg(0), reg(1))
      }
    TrapIfZero(width) => {
      if width == W32 {
        buffer.x86_emit_test_rr32(reg(0).id, reg(0).id)
      } else {
        buffer.x86_emit_test_rr(reg(0).id, reg(0).id)
      }
      let nonzero = buffer.emit_local_jcc(RawNe)
      metadata_offset = buffer.position()
      buffer.x86_emit_trap_imm16(X64_DIVISION_BY_ZERO_BRK.reinterpret_as_int())
      buffer.patch_local_rel32(nonzero, buffer.position())
    }
    TrapIfSignedDivOverflow(width) => {
      if width == W32 {
        buffer.x86_emit_cmp_r32_imm32(reg(1).id, -1)
      } else {
        buffer.x86_emit_cmp_r_imm32(reg(1).id, -1)
      }
      let divisor_is_safe = buffer.emit_local_jcc(RawNe)
      let minimum = @vcode.PhysicalReg::new(10, Int)
      emit_constant(
        buffer,
        width,
        minimum,
        if width == W32 {
          0x80000000UL
        } else {
          0x8000000000000000UL
        },
      )
      if width == W32 {
        buffer.x86_emit_cmp_rr32(reg(0).id, minimum.id)
      } else {
        buffer.x86_emit_cmp_rr(reg(0).id, minimum.id)
      }
      let dividend_is_safe = buffer.emit_local_jcc(RawNe)
      metadata_offset = buffer.position()
      buffer.x86_emit_trap_imm16(X64_INTEGER_OVERFLOW_BRK.reinterpret_as_int())
      buffer.patch_local_rel32(divisor_is_safe, buffer.position())
      buffer.patch_local_rel32(dividend_is_safe, buffer.position())
    }
    CompareSet(width, condition) => {
      if width == W32 {
        buffer.x86_emit_cmp_rr32(reg(0).id, reg(1).id)
      } else {
        buffer.x86_emit_cmp_rr(reg(0).id, reg(1).id)
      }
      buffer.x86_emit_setcc_r8(raw_condition(condition), reg(2).id)
      buffer.x86_emit_movzx_r32_r8(reg(2).id, reg(2).id)
    }
    ReferenceCompareSet(_, condition) => {
      buffer.x86_emit_cmp_rr(reg(0).id, reg(1).id)
      buffer.x86_emit_setcc_r8(raw_condition(condition), reg(2).id)
      buffer.x86_emit_movzx_r32_r8(reg(2).id, reg(2).id)
    }
    FloatUnary(ty, operation) =>
      emit_float_unary(buffer, ty, operation, reg(0), reg(1))
    FloatBinary(ty, operation) =>
      if operation == CopySign {
        emit_float_copy_sign(buffer, ty, reg(0), reg(1), reg(2))
      } else {
        emit_float_binary(buffer, ty, operation, reg(0), reg(1), reg(2))
      }
    FloatTernary(ty, operation) => {
      let right = if reg(3) == reg(1) {
        let scratch = @vcode.PhysicalReg::new(14, FpVector)
        emit_move(buffer, ty, scratch, reg(1))
        scratch
      } else {
        reg(1)
      }
      let addend = if reg(3) == reg(2) {
        let scratch = @vcode.PhysicalReg::new(15, FpVector)
        emit_move(buffer, ty, scratch, reg(2))
        scratch
      } else {
        reg(2)
      }
      emit_move(buffer, ty, reg(3), reg(0))
      buffer.x86_emit_fma213(
        true,
        ty == F64,
        operation,
        reg(3).id,
        right.id,
        addend.id,
      )
    }
    FloatCompareSet(ty, condition) =>
      emit_float_compare(buffer, ty, condition, reg(0), reg(1), reg(2))
    TrapIfFloat(ty, condition) => {
      let left = reg(0)
      let right = if condition == Unordered { left } else { reg(1) }
      metadata_offset = emit_float_trap(buffer, ty, condition, left, right)
    }
    Convert(conversion) => emit_conversion(buffer, conversion, reg(0), reg(1))
    AddAddress => emit_int_binary(buffer, W64, Add, reg(2), reg(0), reg(1))
    ScalarLoad(width, extension, result_type, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      metadata_offset = buffer.position()
      emit_scalar_load(
        buffer,
        width,
        extension,
        result_type,
        address,
        immediate,
        reg(1),
      )
    }
    ScalarStore(width, value_type, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      metadata_offset = buffer.position()
      emit_scalar_store(buffer, width, value_type, address, immediate, reg(1))
    }
    VectorLoad128(offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W128,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.x86_emit_movdqu_xmm_m128(reg(1).id, address.id, immediate)
    }
    VectorStore128(offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W128,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.x86_emit_movdqu_m128_xmm(address.id, immediate, reg(1).id)
    }
    VectorLoadSplat(lane, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W64,
        offset,
      )
      metadata_offset = buffer.position()
      match lane {
        I8x16 => {
          buffer.x86_emit_movzx_r32_m8(10, address.id, immediate)
          emit_vector_splat(
            buffer,
            lane,
            @vcode.PhysicalReg::new(10, Int),
            reg(1),
          )
        }
        I16x8 => {
          buffer.x86_emit_movzx_r32_m16(10, address.id, immediate)
          emit_vector_splat(
            buffer,
            lane,
            @vcode.PhysicalReg::new(10, Int),
            reg(1),
          )
        }
        I32x4 => {
          buffer.x86_emit_mov_r32_m32(10, address.id, immediate)
          emit_vector_splat(
            buffer,
            lane,
            @vcode.PhysicalReg::new(10, Int),
            reg(1),
          )
        }
        I64x2 => {
          buffer.x86_emit_mov_r64_m64(10, address.id, immediate)
          emit_vector_splat(
            buffer,
            lane,
            @vcode.PhysicalReg::new(10, Int),
            reg(1),
          )
        }
        F32x4 => {
          buffer.x86_emit_movss_xmm_m32(reg(1).id, address.id, immediate)
          buffer.x86_emit_shufps_xmm_xmm_imm8(reg(1).id, reg(1).id, 0)
        }
        F64x2 => {
          buffer.x86_emit_movsd_xmm_m64(reg(1).id, address.id, immediate)
          buffer.x86_emit_shufpd_xmm_xmm_imm8(reg(1).id, reg(1).id, 0)
        }
      }
    }
    VectorLoadExtend(lane, signedness, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W64,
        offset,
      )
      metadata_offset = buffer.position()
      buffer.x86_emit_movsd_xmm_m64(reg(1).id, address.id, immediate)
      emit_vector_extension(buffer, lane, false, signedness, reg(1), reg(1))
    }
    VectorLoadZero(width, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        width,
        offset,
      )
      metadata_offset = buffer.position()
      if width == W32 {
        buffer.x86_emit_movss_xmm_m32(reg(1).id, address.id, immediate)
      } else if width == W64 {
        buffer.x86_emit_movsd_xmm_m64(reg(1).id, address.id, immediate)
      } else {
        raise InvalidVectorInstruction
      }
    }
    VectorLoadLane(lane, index, offset) => {
      emit_move(buffer, V128, reg(2), reg(1))
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W64,
        offset,
      )
      metadata_offset = buffer.position()
      match lane {
        I8x16 => {
          buffer.x86_emit_movzx_r32_m8(10, address.id, immediate)
          buffer.x86_emit_pinsrb_xmm_r32_imm8(reg(2).id, 10, index)
        }
        I16x8 => {
          buffer.x86_emit_movzx_r32_m16(10, address.id, immediate)
          buffer.x86_emit_pinsrw_xmm_r32_imm8(reg(2).id, 10, index)
        }
        I32x4 | F32x4 => {
          buffer.x86_emit_mov_r32_m32(10, address.id, immediate)
          buffer.x86_emit_pinsrd_xmm_r32_imm8(reg(2).id, 10, index)
        }
        I64x2 | F64x2 => {
          buffer.x86_emit_mov_r64_m64(10, address.id, immediate)
          buffer.x86_emit_pinsrq_xmm_r64_imm8(reg(2).id, 10, index)
        }
      }
    }
    VectorStoreLane(lane, index, offset) => {
      let (address, immediate) = scalar_memory_address(
        buffer,
        reg(0),
        W64,
        offset,
      )
      metadata_offset = buffer.position()
      match lane {
        I8x16 => {
          buffer.x86_emit_pextrb_r32_xmm_imm8(10, reg(1).id, index)
          buffer.x86_emit_mov_m8_r8(address.id, immediate, 10)
        }
        I16x8 => {
          buffer.x86_emit_pextrw_r32_xmm_imm8(10, reg(1).id, index)
          buffer.x86_emit_mov_m16_r16(address.id, immediate, 10)
        }
        I32x4 | F32x4 => {
          buffer.x86_emit_pextrd_r32_xmm_imm8(10, reg(1).id, index)
          buffer.x86_emit_mov_m32_r32(address.id, immediate, 10)
        }
        I64x2 | F64x2 => {
          buffer.x86_emit_pextrq_r64_xmm_imm8(10, reg(1).id, index)
          buffer.x86_emit_mov_m64_r64(address.id, immediate, 10)
        }
      }
    }
    AtomicLoad(width, ty) => {
      metadata_offset = buffer.position()
      emit_scalar_load(
        buffer,
        width,
        if width == W8 || width == W16 || (width == W32 && ty == I64) {
          Unsigned
        } else {
          None
        },
        ty,
        reg(0),
        0,
        reg(1),
      )
    }
    AtomicStore(width, _) => {
      metadata_offset = buffer.position()
      buffer.x86_emit_xchg_memory(width, reg(0).id, reg(1).id)
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
    AtomicFence => buffer.x86_emit_mfence()
    SafepointMarker => {
      metadata_offset = buffer.position()
      buffer.emit_byte(0x90)
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
        layout.stack_size,
      )
      metadata_offset = buffer.position()
      buffer.emit_byte(0xE8)
      let displacement = buffer.position()
      emit_u32_le(buffer, 0)
      buffer.relocations.push(
        @code_object.Relocation::new(
          displacement,
          X64PcRelative32,
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
        plan.stack_size,
      )
      if result_area_register(plan) is Some(destination) {
        guard frame.result_area_offset() is Some(offset) else {
          raise MissingResultArea
        }
        emit_stack_address(buffer, destination, offset)
      }
      metadata_offset = buffer.position()
      buffer.emit_byte(0xE8)
      let displacement = buffer.position()
      emit_u32_le(buffer, 0)
      buffer.relocations.push(
        @code_object.Relocation::new(
          displacement,
          X64PcRelative32,
          Code(target),
        ),
      )
    }
    InternalCallIndirect(signature, plan) => {
      let callee_register = @vcode.PhysicalReg::new(0, Int)
      emit_call_arguments(
        buffer,
        allocation,
        frame,
        instruction,
        signature.params,
        plan.arguments,
        plan.stack_size,
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
      buffer.x86_emit_call_r64(callee_register.id)
    }
    TailCallDirect(target, signature, plan) => {
      let tail_frame = frame.tail_call_plan(plan.stack_size)
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
        plan.stack_size,
        stack_base=tail_frame.stack_argument_base,
        result_area?,
      )
      emit_epilogue(buffer, frame)
      let thunk_address = emit_tail_return_thunk_setup(buffer, tail_frame)
      metadata_offset = buffer.position()
      buffer.emit_byte(0xE9)
      let displacement = buffer.position()
      emit_u32_le(buffer, 0)
      buffer.relocations.push(
        @code_object.Relocation::new(
          displacement,
          X64PcRelative32,
          Code(target),
        ),
      )
      emit_tail_return_thunk(buffer, tail_frame, thunk_address)
    }
    TailCallIndirect(signature, plan) => {
      let tail_frame = frame.tail_call_plan(plan.stack_size)
      let callee_register = @vcode.PhysicalReg::new(0, Int)
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
        plan.stack_size,
        operand_start=1,
        stack_base=tail_frame.stack_argument_base,
        callee=(0, callee_register),
        result_area?,
      )
      emit_epilogue(buffer, frame)
      let thunk_address = emit_tail_return_thunk_setup(buffer, tail_frame)
      metadata_offset = buffer.position()
      buffer.x86_emit_jmp_r64(callee_register.id)
      emit_tail_return_thunk(buffer, tail_frame, thunk_address)
    }
    Jump => {
      emit_edge_moves(buffer, function, allocation, frame, block, 0)
      let target = threaded_branch_target(
        function,
        allocation,
        function.instruction_successor_at(instruction, 0).unwrap().target,
      )
      if next_block != Some(target) {
        buffer.x86_emit_jmp_rel32(function.block_index(target).unwrap())
      }
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
        next_block,
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
      buffer.x86_emit_trap_imm16(trap_brk_payload(reason).reinterpret_as_int())
    }
    Return => {
      emit_epilogue(buffer, frame)
      buffer.x86_emit_ret()
    }
  }
  metadata_offset
}

///|
fn patch_branches(
  buffer : CodeBuffer,
  function : @vcode.Function[X64Inst],
  block_offsets : Array[Int],
) -> Unit raise X64EmitError {
  for fixup in buffer.x64_fixups {
    let target = block_offsets[fixup.target_block]
    if target < 0 {
      raise BranchTargetMissing(
        block=function.block_at(fixup.target_block).unwrap(),
      )
    }
    patch_relative_branch(
      buffer,
      fixup.displacement_offset,
      target,
      32,
      next_instruction_offset=fixup.next_instruction_offset,
    )
  }
}

///|
fn patch_relative_branch(
  buffer : CodeBuffer,
  offset : Int,
  target : Int,
  bits : Int,
  next_instruction_offset? : Int = offset + 4,
) -> Unit raise X64EmitError {
  let delta = target - next_instruction_offset
  if bits != 32 || delta < -0x80000000 || delta > 0x7FFFFFFF {
    raise BranchOutOfRange(offset=delta, bits~)
  }
  buffer.patch_word(offset, delta.reinterpret_as_uint())
}

///|
fn emit_verified(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
) -> @code_object.UnlinkedCodeObject raise X64EmitError {
  let buffer = CodeBuffer::new()
  let block_offsets = Array::make(function.block_count(), -1)
  let sources : Array[@code_object.SourceSite] = []
  let traps : Array[@code_object.TrapSite] = []
  let safepoints : Array[@code_object.SafepointSite] = []
  let unwind : Array[@code_object.UnwindDirective] = []
  emit_prologue(buffer, frame, unwind)
  let layout = function.layout()
  for block_index, block in layout {
    block_offsets[function.block_index(block).unwrap()] = buffer.position()
    for instruction in function.block_body(block) {
      let abi_materialization = is_abi_materialization(
        function.instruction(instruction).unwrap(),
      )
      if !abi_materialization {
        emit_edits_at(buffer, function, allocation, frame, instruction, Before)
      }
      let instruction_offset = emit_instruction(
        buffer,
        function,
        allocation,
        frame,
        block,
        instruction,
        None,
      )
      record_instruction_metadata(
        buffer, function, allocation, frame, instruction, instruction_offset, sources,
        traps, safepoints,
      )
      if !abi_materialization {
        emit_edits_at(buffer, function, allocation, frame, instruction, After)
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    let next_block = layout.get(block_index + 1)
    emit_edits_at(buffer, function, allocation, frame, terminator, Before)
    let terminator_offset = emit_instruction(
      buffer, function, allocation, frame, block, terminator, next_block,
    )
    record_instruction_metadata(
      buffer, function, allocation, frame, terminator, terminator_offset, sources,
      traps, safepoints,
    )
    emit_edits_at(buffer, function, allocation, frame, terminator, After)
  }
  patch_branches(buffer, function, block_offsets)
  let relocations = buffer.relocations
  @code_object.build(
    X64,
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

///|
pub fn emit(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
  frame : X64Frame,
) -> @code_object.UnlinkedCodeObject raise X64EmitError {
  verify_frame(function, allocation, frame) catch {
    error => raise InvalidFrame(cause=error)
  }
  emit_verified(function, allocation, frame)
}
