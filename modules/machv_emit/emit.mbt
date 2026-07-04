///|
fn opcode_debug_name(opcode : @machv.Opcode) -> String {
  match opcode {
    Target(name) => name
    _ => "machv." + to_repr(opcode).to_string()
  }
}

///|
fn terminator_debug_name(term : @machv.Terminator) -> String {
  "machv." + to_repr(term).to_string()
}

///|
pub suberror EmitError {
  UnsupportedOpcode(opcode~ : String)
  UnsupportedOperand(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for EmitError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn emit_u32_le(object : CodeObject, word : Int) -> Unit {
  object.code.push(word & 0xff)
  object.code.push((word >> 8) & 0xff)
  object.code.push((word >> 16) & 0xff)
  object.code.push((word >> 24) & 0xff)
}

///|
fn emit_u64_le(object : CodeObject, word : Int64) -> Unit {
  let mut x = word
  for _ in 0..<8 {
    object.code.push((x & 0xffL).to_int())
    x = x >> 8
  }
}

///|
fn emit_x64_rex_w(object : CodeObject, r : Int, b : Int) -> Unit {
  object.code.push(0x48 | ((r & 1) << 2) | (b & 1))
}

///|
fn emit_x64_modrm(object : CodeObject, mod_ : Int, reg : Int, rm : Int) -> Unit {
  object.code.push(((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7))
}

///|
fn emit_x64_mov_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x89)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_add_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: add r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x01)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_sub_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: sub r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x29)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_and_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: and r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x21)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_or_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: or r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x09)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_xor_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: xor r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x31)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_imul_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: imul r64, r/m64.
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0xaf)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_mov_imm64(object : CodeObject, dst : Int, imm : Int64) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r64, imm64.
  emit_x64_rex_w(object, 0, (dst >> 3) & 1)
  object.code.push(0xb8 + (dst & 7))
  emit_u64_le(object, imm)
}

///|
fn emit_x64_test_rr(object : CodeObject, reg : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: test r/m64, r64.
  emit_x64_rex_w(object, (reg >> 3) & 1, (reg >> 3) & 1)
  object.code.push(0x85)
  emit_x64_modrm(object, 3, reg, reg)
}

///|
fn emit_x64_cmp_rr(object : CodeObject, lhs : Int, rhs : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: cmp r/m64, r64.
  emit_x64_rex_w(object, (rhs >> 3) & 1, (lhs >> 3) & 1)
  object.code.push(0x39)
  emit_x64_modrm(object, 3, rhs, lhs)
}

///|
fn emit_x64_cmp_imm32(object : CodeObject, lhs : Int, imm : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: cmp r/m64, imm32.
  emit_x64_rex_w(object, 0, (lhs >> 3) & 1)
  object.code.push(0x81)
  emit_x64_modrm(object, 3, 7, lhs)
  emit_u32_le(object, imm)
}

///|
fn emit_x64_rex_if_needed(object : CodeObject, r : Int, b : Int) -> Unit {
  if r != 0 || b != 0 {
    object.code.push(0x40 | ((r & 1) << 2) | (b & 1))
  }
}

///|
fn emit_x64_load_base_disp32(
  object : CodeObject,
  dst : Int,
  base : Int,
  offset : Int,
  is_64 : Bool,
) -> Unit {
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  if is_64 {
    emit_x64_rex_w(object, r, b)
  } else {
    emit_x64_rex_if_needed(object, r, b)
  }
  object.code.push(0x8b)
  emit_x64_modrm(object, 2, dst, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_store_base_disp32(
  object : CodeObject,
  base : Int,
  src : Int,
  offset : Int,
  is_64 : Bool,
) -> Unit {
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  if is_64 {
    emit_x64_rex_w(object, r, b)
  } else {
    emit_x64_rex_if_needed(object, r, b)
  }
  object.code.push(0x89)
  emit_x64_modrm(object, 2, src, base)
  emit_u32_le(object, offset)
}

///|
fn x64_jcc_opcode(cond : @machv.Cond) -> Int {
  match cond {
    Eq => 0x84
    Ne => 0x85
    Lt => 0x8c
    Le => 0x8e
    Gt => 0x8f
    Ge => 0x8d
    Ult => 0x82
    Ule => 0x86
    Ugt => 0x87
    Uge => 0x83
    Custom(name) =>
      abort("x64_jcc_opcode: unsupported custom condition \{name}")
  }
}

///|
fn aarch64_cond_bits(cond : @machv.Cond) -> Int {
  match cond {
    Eq => 0
    Ne => 1
    Uge => 2
    Ult => 3
    Ugt => 8
    Ule => 9
    Ge => 10
    Lt => 11
    Gt => 12
    Le => 13
    Custom(name) =>
      abort("aarch64_cond_bits: unsupported custom condition \{name}")
  }
}

///|
fn emit_x64_jcc_rel32(object : CodeObject, cond : @machv.Cond) -> Unit {
  object.code.push(0x0f)
  object.code.push(x64_jcc_opcode(cond))
  emit_u32_le(object, 0)
}

///|
fn emit_x64_jmp_rel32(object : CodeObject) -> Unit {
  object.code.push(0xe9)
  emit_u32_le(object, 0)
}

///|
fn emit_aarch64_b_cond(object : CodeObject, cond : @machv.Cond) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: B.cond with patched imm19.
  emit_u32_le(object, 0x54000000 | aarch64_cond_bits(cond))
}

///|
fn emit_aarch64_cbz(
  object : CodeObject,
  reg : Int,
  is_nonzero : Bool,
  is_64 : Bool,
) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: CBZ/CBNZ with patched imm19.
  let base = match (is_nonzero, is_64) {
    (false, true) => 0xb4000000
    (true, true) => 0xb5000000
    (false, false) => 0x34000000
    (true, false) => 0x35000000
  }
  emit_u32_le(object, base | (reg & 0x1f))
}

///|
fn emit_aarch64_cmp_rr(
  object : CodeObject,
  lhs : Int,
  rhs : Int,
  is_64 : Bool,
) -> Unit {
  // CMP is SUBS with XZR/WZR destination.
  let base = if is_64 { 0xeb00001f } else { 0x6b00001f }
  emit_u32_le(object, base | ((rhs & 0x1f) << 16) | ((lhs & 0x1f) << 5))
}

///|
fn emit_aarch64_cmp_imm(
  object : CodeObject,
  lhs : Int,
  imm : Int,
  is_64 : Bool,
) -> Unit raise EmitError {
  guard imm >= 0 && imm <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 branch compare immediate requires an unsigned 12-bit immediate",
    )
  }
  // TODO(machv_emit): support shifted CMP immediates once target lowering preserves the immediate form.
  let base = if is_64 { 0xf100001f } else { 0x7100001f }
  emit_u32_le(object, base | ((imm & 0xfff) << 10) | ((lhs & 0x1f) << 5))
}

///|
fn emit_aarch64_b(object : CodeObject) -> Unit {
  // TODO(machv_emit): patch AArch64 B immediate once block layout is finalized.
  emit_u32_le(object, 0x14000000)
}

///|
fn require_int_preg(
  operand : @machv.Operand,
  context : String,
) -> Int raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if preg.class == Int && !preg.is_spilled() {
        preg.index
      } else {
        raise UnsupportedOperand(
          message="\{context} requires an integer physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn find_operand(
  inst : @machv.Instruction,
  role : @machv.OperandRole,
  index : Int,
  context : String,
) -> @machv.Operand raise EmitError {
  let mut seen = 0
  for operand in inst.operands {
    if operand.role == role {
      if seen == index {
        return operand
      }
      seen = seen + 1
    }
  }
  raise UnsupportedOperand(message="\{context} missing operand \{index}")
}

///|
fn emit_aarch64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "mov"), "mov source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  // TODO(machv_emit): choose 32-bit or floating-register encodings from MachV value width.
  emit_u32_le(object, 0xaa0003e0 | (src << 16) | dst)
}

///|
fn emit_aarch64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): encode 32-bit integer adds and immediate forms once MachV carries lane width/legalization info.
  emit_u32_le(object, 0x8b000000 | (rhs << 16) | (lhs << 5) | dst)
}

///|
fn emit_aarch64_int_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  base : Int,
  context : String,
) -> Unit raise EmitError {
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): encode 32-bit and immediate/legalized forms once MachV carries lane width.
  emit_u32_le(
    object,
    base | ((rhs & 0x1f) << 16) | ((lhs & 0x1f) << 5) | (dst & 0x1f),
  )
}

///|
fn emit_aarch64_int_mul(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "mul"), "mul lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "mul"), "mul rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mul"),
    "mul destination",
  )
  // Copied from legacy `vcode/emit/instructions_bytes`: MUL as MADD rd, rn, rm, xzr.
  emit_u32_le(
    object,
    0x9b000000 |
    ((rhs & 0x1f) << 16) |
    (31 << 10) |
    ((lhs & 0x1f) << 5) |
    (dst & 0x1f),
  )
}

///|
fn emit_aarch64_int_const(
  object : CodeObject,
  inst : @machv.Instruction,
  imm : Int64,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "iconst"),
    "iconst destination",
  )
  guard imm >= 0L && imm <= 0xffffL else {
    raise UnsupportedOperand(
      message="AArch64 IntConst currently supports only unsigned 16-bit immediates",
    )
  }
  // TODO(machv_emit): copy the full legacy MOVZ/MOVN/MOVK materialization sequence for arbitrary 64-bit constants.
  emit_u32_le(object, 0xd2800000 | (imm.to_int() << 5) | (dst & 0x1f))
}

///|
fn mem_access_scale(mem_type : @machv.MemType) -> Int {
  match mem_type {
    MemI32 | MemF32 => 4
    MemI64 | MemF64 | MemPtr => 8
    MemV128 => 16
  }
}

///|
fn mem_access_is_64(mem_type : @machv.MemType) -> Bool raise EmitError {
  match mem_type {
    MemI32 => false
    MemI64 | MemPtr => true
    _ =>
      raise UnsupportedOperand(
        message="machv_emit memory access currently supports only i32, i64, and ptr",
      )
  }
}

///|
fn emit_aarch64_load_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr"),
    "load_ptr base",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "load_ptr"),
    "load_ptr destination",
  )
  let scale = mem_access_scale(mem_type)
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 load_ptr requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let imm12 = offset / scale
  let base = if mem_access_is_64(mem_type) { 0xf9400000 } else { 0xb9400000 }
  emit_u32_le(
    object,
    base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (dst & 0x1f),
  )
}

///|
fn emit_aarch64_store_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr"),
    "store_ptr base",
  )
  let src = require_int_preg(
    find_operand(inst, Use, 1, "store_ptr"),
    "store_ptr source",
  )
  let scale = mem_access_scale(mem_type)
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 store_ptr requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let imm12 = offset / scale
  let base = if mem_access_is_64(mem_type) { 0xf9000000 } else { 0xb9000000 }
  emit_u32_le(
    object,
    base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (src & 0x1f),
  )
}

///|
fn emit_x64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "mov"), "mov source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  // TODO(machv_emit): choose 32-bit or floating-register encodings from MachV value width.
  emit_x64_mov_rr(object, dst, src)
}

///|
fn emit_x64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): replace this copy-first lowering with an X64 legalization pass that can pick two-address forms before emission.
  if dst != lhs {
    emit_x64_mov_rr(object, dst, lhs)
  }
  emit_x64_add_rr(object, dst, rhs)
}

///|
fn emit_x64_int_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  emit_rr : (CodeObject, Int, Int) -> Unit,
  context : String,
) -> Unit raise EmitError {
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): replace this copy-first lowering with an X64 legalization pass that can pick two-address forms before emission.
  if dst != lhs {
    emit_x64_mov_rr(object, dst, lhs)
  }
  emit_rr(object, dst, rhs)
}

///|
fn emit_x64_int_const(
  object : CodeObject,
  inst : @machv.Instruction,
  imm : Int64,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "iconst"),
    "iconst destination",
  )
  emit_x64_mov_imm64(object, dst, imm)
}

///|
fn emit_x64_load_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr"),
    "load_ptr base",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "load_ptr"),
    "load_ptr destination",
  )
  emit_x64_load_base_disp32(
    object,
    dst,
    base,
    offset,
    mem_access_is_64(mem_type),
  )
}

///|
fn emit_x64_store_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr"),
    "store_ptr base",
  )
  let src = require_int_preg(
    find_operand(inst, Use, 1, "store_ptr"),
    "store_ptr source",
  )
  emit_x64_store_base_disp32(
    object,
    base,
    src,
    offset,
    mem_access_is_64(mem_type),
  )
}

///|
fn write_aarch64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match inst.opcode {
    IntConst(imm) => emit_aarch64_int_const(object, inst, imm)
    Move => emit_aarch64_move(object, inst)
    IntAdd => emit_aarch64_int_add(object, inst)
    IntSub => emit_aarch64_int_binop3(object, inst, 0xcb000000, "sub")
    IntMul => emit_aarch64_int_mul(object, inst)
    IntAnd => emit_aarch64_int_binop3(object, inst, 0x8a000000, "and")
    IntOr => emit_aarch64_int_binop3(object, inst, 0xaa000000, "or")
    IntXor => emit_aarch64_int_binop3(object, inst, 0xca000000, "xor")
    LoadPtr(mem_type, offset) =>
      emit_aarch64_load_ptr(object, inst, mem_type, offset)
    StorePtr(mem_type, offset) =>
      emit_aarch64_store_ptr(object, inst, mem_type, offset)
    Call(_) =>
      // TODO(machv_emit): resolve and range-check AArch64 BL relocations during real object linking.
      emit_u32_le(object, 0x94000000)
    Jump(_) => emit_aarch64_b(object)
    Return => emit_u32_le(object, 0xd65f03c0)
    Trap(_) =>
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      emit_u32_le(object, 0xd4200000)
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_x64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match inst.opcode {
    IntConst(imm) => emit_x64_int_const(object, inst, imm)
    Move => emit_x64_move(object, inst)
    IntAdd => emit_x64_int_add(object, inst)
    IntSub => emit_x64_int_binop3(object, inst, emit_x64_sub_rr, "sub")
    IntMul => emit_x64_int_binop3(object, inst, emit_x64_imul_rr, "mul")
    IntAnd => emit_x64_int_binop3(object, inst, emit_x64_and_rr, "and")
    IntOr => emit_x64_int_binop3(object, inst, emit_x64_or_rr, "or")
    IntXor => emit_x64_int_binop3(object, inst, emit_x64_xor_rr, "xor")
    LoadPtr(mem_type, offset) =>
      emit_x64_load_ptr(object, inst, mem_type, offset)
    StorePtr(mem_type, offset) =>
      emit_x64_store_ptr(object, inst, mem_type, offset)
    Call(_) => {
      // TODO(machv_emit): patch X64 call rel32 displacement during object linking.
      object.code.push(0xe8)
      emit_u32_le(object, 0)
    }
    Jump(_) =>
      // TODO(machv_emit): patch X64 jump rel32 displacement after block layout.
      emit_x64_jmp_rel32(object)
    Return => object.code.push(0xc3)
    Trap(_) => {
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      object.code.push(0xcc)
      object.code.push(0)
      object.code.push(0)
    }
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_inst_bytes(
  object : CodeObject,
  target : EmitTarget,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  match target {
    AArch64 => write_aarch64_inst_bytes(object, inst)
    X64 => write_x64_inst_bytes(object, inst)
  }
}

///|
fn record_relocations(
  object : CodeObject,
  offset : Int,
  opcode : @machv.Opcode,
) -> Unit {
  match opcode {
    Call(symbol) =>
      object.relocations.push({ offset, kind: ExternalSymbol(symbol) })
    Jump(target) => {
      object.relocations.push({ offset, kind: BlockTarget(target) })
      object.fixups.push({ offset, block_id: target })
    }
    Branch(true_target, false_target) => {
      object.relocations.push({ offset, kind: BlockTarget(true_target) })
      object.relocations.push({
        offset: offset + 1,
        kind: BlockTarget(false_target),
      })
      object.fixups.push({ offset, block_id: true_target })
      object.fixups.push({ offset: offset + 1, block_id: false_target })
    }
    _ => ()
  }
}

///|
fn record_stack_map(
  object : CodeObject,
  offset : Int,
  inst : @machv.Instruction,
) -> Unit {
  if inst.stack_effect != None {
    object.stack_maps.push({ offset, effect: inst.stack_effect })
  }
}

///|
fn record_branch_target(
  object : CodeObject,
  offset : Int,
  target : Int,
) -> Unit {
  object.relocations.push({ offset, kind: BlockTarget(target) })
  object.fixups.push({ offset, block_id: target })
}

///|
fn emit_instruction(
  object : CodeObject,
  target : EmitTarget,
  block_id : Int,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let offset = object.current_offset()
  write_inst_bytes(object, target, inst)
  record_relocations(object, offset, inst.opcode)
  record_stack_map(object, offset, inst)
  object.debug_entries.push({
    offset,
    block_id,
    inst_id: inst.id,
    opcode: opcode_debug_name(inst.opcode),
  })
}

///|
fn opcode_for_terminator(
  term : @machv.Terminator,
) -> @machv.Opcode raise EmitError {
  match term {
    TermReturn(_) => Return
    TermJump(target, _) => Jump(target)
    TermTrap(reason) => Trap(reason)
    _ => raise UnsupportedOpcode(opcode=terminator_debug_name(term))
  }
}

///|
fn emit_branch_fallthrough_jump(
  object : CodeObject,
  target : EmitTarget,
) -> Int {
  let jump_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b(object)
    X64 => emit_x64_jmp_rel32(object)
  }
  jump_offset
}

///|
fn require_branch_reg(
  reg : @machv.Reg,
  context : String,
) -> Int raise EmitError {
  match reg {
    Physical(preg) =>
      if preg.class == Int && !preg.is_spilled() {
        preg.index
      } else {
        raise UnsupportedOperand(
          message="\{context} requires an integer physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn emit_branch_zero(
  object : CodeObject,
  target : EmitTarget,
  reg : @machv.Reg,
  is_nonzero : Bool,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let preg = require_branch_reg(reg, "branch-zero")
  let cond_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_cbz(object, preg, is_nonzero, is_64)
    X64 => {
      emit_x64_test_rr(object, preg)
      emit_x64_jcc_rel32(object, if is_nonzero { Ne } else { Eq })
    }
  }
  record_branch_target(object, cond_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_branch_cmp(
  object : CodeObject,
  target : EmitTarget,
  lhs : @machv.Reg,
  rhs : @machv.Reg,
  cond : @machv.Cond,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let lhs_reg = require_branch_reg(lhs, "branch-cmp lhs")
  let rhs_reg = require_branch_reg(rhs, "branch-cmp rhs")
  match target {
    AArch64 => emit_aarch64_cmp_rr(object, lhs_reg, rhs_reg, is_64)
    X64 => emit_x64_cmp_rr(object, lhs_reg, rhs_reg)
  }
  let cond_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b_cond(object, cond)
    X64 => emit_x64_jcc_rel32(object, cond)
  }
  record_branch_target(object, cond_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_branch_cmp_imm(
  object : CodeObject,
  target : EmitTarget,
  lhs : @machv.Reg,
  imm : Int,
  cond : @machv.Cond,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let lhs_reg = require_branch_reg(lhs, "branch-cmp-imm lhs")
  match target {
    AArch64 => emit_aarch64_cmp_imm(object, lhs_reg, imm, is_64)
    X64 => emit_x64_cmp_imm32(object, lhs_reg, imm)
  }
  let cond_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b_cond(object, cond)
    X64 => emit_x64_jcc_rel32(object, cond)
  }
  record_branch_target(object, cond_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_conditional_terminator(
  object : CodeObject,
  target : EmitTarget,
  term : @machv.Terminator,
) -> Unit raise EmitError {
  // TODO(machv_emit): materialize block argument transfers before branch emission.
  match term {
    TermBranch(cond, true_target, _, false_target, _) =>
      emit_branch_zero(
        object, target, cond, true, true, true_target, false_target,
      )
    TermBranchZero(reg, is_nonzero, is_64, true_target, _, false_target, _) =>
      emit_branch_zero(
        object, target, reg, is_nonzero, is_64, true_target, false_target,
      )
    TermBranchCmp(lhs, rhs, cond, is_64, true_target, _, false_target, _) =>
      emit_branch_cmp(
        object, target, lhs, rhs, cond, is_64, true_target, false_target,
      )
    TermBranchCmpImm(lhs, imm, cond, is_64, true_target, _, false_target, _) =>
      emit_branch_cmp_imm(
        object, target, lhs, imm, cond, is_64, true_target, false_target,
      )
    _ => raise UnsupportedOpcode(opcode=terminator_debug_name(term))
  }
}

///|
fn emit_terminator(
  object : CodeObject,
  target : EmitTarget,
  block_id : Int,
  term : @machv.Terminator,
) -> Unit raise EmitError {
  match term {
    TermBranch(_, _, _, _, _)
    | TermBranchZero(_, _, _, _, _, _, _)
    | TermBranchCmp(_, _, _, _, _, _, _, _)
    | TermBranchCmpImm(_, _, _, _, _, _, _, _) => {
      let offset = object.current_offset()
      emit_conditional_terminator(object, target, term)
      object.debug_entries.push({
        offset,
        block_id,
        inst_id: -1,
        opcode: terminator_debug_name(term),
      })
      return
    }
    _ => ()
  }
  let opcode = opcode_for_terminator(term)
  let inst = @machv.Instruction::new(-1, opcode)
  let offset = object.current_offset()
  write_inst_bytes(object, target, inst)
  record_relocations(object, offset, opcode)
  object.debug_entries.push({
    offset,
    block_id,
    inst_id: -1,
    opcode: opcode_debug_name(opcode),
  })
}

///|
pub fn emit_function_for_target(
  func : @machv.Function,
  target : EmitTarget,
) -> CodeObject raise EmitError {
  let object = CodeObject::new()
  for block in func.blocks {
    for inst in block.instructions {
      emit_instruction(object, target, block.id, inst)
    }
    if block.terminator is Some(term) {
      emit_terminator(object, target, block.id, term)
    }
  }
  object
}

///|
pub fn emit_function(func : @machv.Function) -> CodeObject raise EmitError {
  // TODO(machv_emit): require callers to pass target metadata instead of relying on this temporary AArch64 default.
  emit_function_for_target(func, AArch64)
}
