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
  BranchFixupError(message~ : String)
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
fn emit_x64_div_r64(object : CodeObject, rhs : Int, signed : Bool) -> Unit {
  emit_x64_rex_w(object, 0, (rhs >> 3) & 1)
  object.code.push(0xf7)
  emit_x64_modrm(object, 3, if signed { 7 } else { 6 }, rhs)
}

///|
fn emit_x64_not_r64(object : CodeObject, reg : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: not r/m64.
  emit_x64_rex_w(object, 0, (reg >> 3) & 1)
  object.code.push(0xf7)
  emit_x64_modrm(object, 3, 2, reg)
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
fn require_float_preg(
  operand : @machv.Operand,
  context : String,
) -> (Int, @machv.RegClass) raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if (preg.class == Float32 || preg.class == Float64) && !preg.is_spilled() {
        (preg.index, preg.class)
      } else {
        raise UnsupportedOperand(
          message="\{context} requires a floating-point physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn require_same_float_class(
  lhs : @machv.RegClass,
  rhs : @machv.RegClass,
  context : String,
) -> Unit raise EmitError {
  guard lhs == rhs else {
    raise UnsupportedOperand(
      message="\{context} requires matching floating-point register classes",
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
fn emit_aarch64_int_not(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "not"), "not source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "not"),
    "not destination",
  )
  // TODO(machv_emit): encode 32-bit integer not once MachV carries lane width.
  emit_u32_le(
    object,
    (dst & 31) |
    ((31 & 7) << 5) |
    (((31 >> 3) & 3) << 8) |
    (((src & 31) | 32) << 16) |
    (170 << 24),
  )
}

///|
fn emit_aarch64_movz(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0xd2800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
  )
}

///|
fn emit_aarch64_movn(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0x92800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
  )
}

///|
fn emit_aarch64_movk(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0xf2800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
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
  let halfwords = FixedArray::make(4, 0)
  for i in 0..<4 {
    halfwords[i] = ((imm >> (i * 16)) & 0xffffL).to_int()
  }
  let mut non_zero = 0
  let mut non_ffff = 0
  for i in 0..<4 {
    if halfwords[i] != 0 {
      non_zero = non_zero + 1
    }
    if halfwords[i] != 0xffff {
      non_ffff = non_ffff + 1
    }
  }
  let movz_count = if non_zero == 0 { 1 } else { non_zero }
  let movn_count = if non_ffff == 0 { 1 } else { non_ffff }
  if movn_count < movz_count {
    if non_ffff == 0 {
      emit_aarch64_movn(object, dst, 0, 0)
    } else {
      let mut first = 0
      while first < 4 && halfwords[first] == 0xffff {
        first = first + 1
      }
      emit_aarch64_movn(object, dst, halfwords[first] ^ 0xffff, first * 16)
      for i in 0..<4 {
        if i != first && halfwords[i] != 0xffff {
          emit_aarch64_movk(object, dst, halfwords[i], i * 16)
        }
      }
    }
  } else if non_zero == 0 {
    emit_aarch64_movz(object, dst, 0, 0)
  } else {
    let mut first = 0
    while first < 4 && halfwords[first] == 0 {
      first = first + 1
    }
    emit_aarch64_movz(object, dst, halfwords[first], first * 16)
    for i in 0..<4 {
      if i != first && halfwords[i] != 0 {
        emit_aarch64_movk(object, dst, halfwords[i], i * 16)
      }
    }
  }
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
fn emit_aarch64_float_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  f32_mid : Int,
  f64_mid : Int,
  context : String,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, lhs_class, context)
  require_same_float_class(dst_class, rhs_class, context)
  let mid = match dst_class {
    Float32 => f32_mid
    Float64 => f64_mid
    _ => abort("unreachable float class")
  }
  emit_u32_le(
    object,
    (dst & 31) |
    ((lhs & 7) << 5) |
    (((lhs >> 3) & 3) << 8) |
    (mid << 8) |
    ((rhs & 31) << 16) |
    (0x1e << 24),
  )
}

///|
fn emit_aarch64_float_unop(
  object : CodeObject,
  inst : @machv.Instruction,
  f32_mid : Int,
  f64_mid : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let mid = match dst_class {
    Float32 => f32_mid
    Float64 => f64_mid
    _ => abort("unreachable float class")
  }
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    (((src >> 3) & 3) << 8) |
    (mid << 8) |
    (0x1e << 24),
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
fn emit_x64_sse_rr(
  object : CodeObject,
  prefix : Int,
  opcode : Int,
  dst : Int,
  src : Int,
) -> Unit {
  object.code.push(prefix)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_sse_rr_no_prefix(
  object : CodeObject,
  opcode : Int,
  dst : Int,
  src : Int,
) -> Unit {
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_pcmpeqd_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x76)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_pshift_imm(
  object : CodeObject,
  opcode : Int,
  ext : Int,
  dst : Int,
  amount : Int,
) -> Unit {
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, 0, (dst >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, ext, dst)
  object.code.push(amount & 0xff)
}

///|
fn emit_x64_float_move(
  object : CodeObject,
  dst : Int,
  src : Int,
  class : @machv.RegClass,
) -> Unit {
  let prefix = match class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, 0x10, dst, src)
}

///|
fn emit_x64_float_abs_or_neg(
  object : CodeObject,
  inst : @machv.Instruction,
  is_abs : Bool,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  if dst != src {
    emit_x64_float_move(object, dst, src, dst_class)
  }
  let scratch = if dst == 14 { 15 } else { 14 }
  emit_x64_pcmpeqd_rr(object, scratch, scratch)
  match (is_abs, dst_class) {
    (true, Float32) => emit_x64_pshift_imm(object, 0x72, 2, scratch, 1)
    (true, Float64) => emit_x64_pshift_imm(object, 0x73, 2, scratch, 1)
    (false, Float32) => emit_x64_pshift_imm(object, 0x72, 6, scratch, 31)
    (false, Float64) => emit_x64_pshift_imm(object, 0x73, 6, scratch, 63)
    _ => abort("unreachable float class")
  }
  let opcode = if is_abs { 0x54 } else { 0x57 }
  match dst_class {
    Float32 => emit_x64_sse_rr_no_prefix(object, opcode, dst, scratch)
    Float64 => emit_x64_sse_rr(object, 0x66, opcode, dst, scratch)
    _ => abort("unreachable float class")
  }
}

///|
fn emit_x64_float_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  opcode : Int,
  context : String,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, lhs_class, context)
  require_same_float_class(dst_class, rhs_class, context)
  if dst != lhs {
    emit_x64_float_move(object, dst, lhs, dst_class)
  }
  let prefix = match dst_class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, opcode, dst, rhs)
}

///|
fn emit_x64_float_unop(
  object : CodeObject,
  inst : @machv.Instruction,
  opcode : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let prefix = match dst_class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, opcode, dst, src)
}

///|
fn emit_x64_int_div(
  object : CodeObject,
  inst : @machv.Instruction,
  signed : Bool,
) -> Unit raise EmitError {
  let context = if signed { "idiv" } else { "div" }
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} dividend",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} divisor",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} quotient",
  )
  let rdx = require_int_preg(
    find_operand(inst, Def, 1, context),
    "\{context} rdx side effect",
  )
  if lhs != 0 || dst != 0 || rdx != 3 {
    raise UnsupportedOperand(
      message="\{context} requires dividend/result in rax and rdx side-effect def",
    )
  }
  if rhs == 0 || rhs == 3 {
    raise UnsupportedOperand(
      message="\{context} divisor must not be rax or rdx",
    )
  }
  if signed {
    // cqo: sign-extend RAX into RDX:RAX before IDIV.
    object.code.push(0x48)
    object.code.push(0x99)
  } else {
    // xor edx, edx: zero the high dividend half before DIV.
    object.code.push(0x31)
    object.code.push(0xd2)
  }
  emit_x64_div_r64(object, rhs, signed)
}

///|
fn emit_x64_int_not(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "not"), "not source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "not"),
    "not destination",
  )
  // TODO(machv_emit): encode 32-bit integer not once MachV carries lane width.
  if dst != src {
    emit_x64_mov_rr(object, dst, src)
  }
  emit_x64_not_r64(object, dst)
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
    IntDiv(signed) =>
      emit_aarch64_int_binop3(
        object,
        inst,
        if signed {
          0x9ac00c00
        } else {
          0x9ac00800
        },
        if signed {
          "sdiv"
        } else {
          "udiv"
        },
      )
    IntNot => emit_aarch64_int_not(object, inst)
    IntAnd => emit_aarch64_int_binop3(object, inst, 0x8a000000, "and")
    IntOr => emit_aarch64_int_binop3(object, inst, 0xaa000000, "or")
    IntXor => emit_aarch64_int_binop3(object, inst, 0xca000000, "xor")
    FloatAdd => emit_aarch64_float_binop3(object, inst, 0x2028, 0x6028, "fadd")
    FloatSub => emit_aarch64_float_binop3(object, inst, 0x2038, 0x6038, "fsub")
    FloatMul => emit_aarch64_float_binop3(object, inst, 0x2008, 0x6008, "fmul")
    FloatDiv => emit_aarch64_float_binop3(object, inst, 0x2018, 0x6018, "fdiv")
    FloatMin => emit_aarch64_float_binop3(object, inst, 0x2058, 0x6058, "fmin")
    FloatMax => emit_aarch64_float_binop3(object, inst, 0x2048, 0x6048, "fmax")
    FloatSqrt => emit_aarch64_float_unop(object, inst, 0x21c0, 0x61c0, "fsqrt")
    FloatAbs => emit_aarch64_float_unop(object, inst, 0x20c0, 0x60c0, "fabs")
    FloatNeg => emit_aarch64_float_unop(object, inst, 0x2140, 0x6140, "fneg")
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
    IntDiv(signed) => emit_x64_int_div(object, inst, signed)
    IntNot => emit_x64_int_not(object, inst)
    IntAnd => emit_x64_int_binop3(object, inst, emit_x64_and_rr, "and")
    IntOr => emit_x64_int_binop3(object, inst, emit_x64_or_rr, "or")
    IntXor => emit_x64_int_binop3(object, inst, emit_x64_xor_rr, "xor")
    FloatAdd => emit_x64_float_binop3(object, inst, 0x58, "fadd")
    FloatSub => emit_x64_float_binop3(object, inst, 0x5c, "fsub")
    FloatMul => emit_x64_float_binop3(object, inst, 0x59, "fmul")
    FloatDiv => emit_x64_float_binop3(object, inst, 0x5e, "fdiv")
    FloatMin => emit_x64_float_binop3(object, inst, 0x5d, "fmin")
    FloatMax => emit_x64_float_binop3(object, inst, 0x5f, "fmax")
    FloatSqrt => emit_x64_float_unop(object, inst, 0x51, "fsqrt")
    FloatAbs => emit_x64_float_abs_or_neg(object, inst, true, "fabs")
    FloatNeg => emit_x64_float_abs_or_neg(object, inst, false, "fneg")
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
  let mut branch_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_cbz(object, preg, is_nonzero, is_64)
    X64 => {
      emit_x64_test_rr(object, preg)
      branch_offset = object.current_offset()
      emit_x64_jcc_rel32(object, if is_nonzero { Ne } else { Eq })
    }
  }
  record_branch_target(object, branch_offset, true_target)
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
fn find_block_offset(block_offsets : Array[(Int, Int)], block_id : Int) -> Int? {
  for entry in block_offsets {
    let (id, offset) = entry
    if id == block_id {
      return Some(offset)
    }
  }
  None
}

///|
fn write_i32_le_at(code : Array[Int], offset : Int, value : Int) -> Unit {
  code[offset] = value & 0xff
  code[offset + 1] = (value >> 8) & 0xff
  code[offset + 2] = (value >> 16) & 0xff
  code[offset + 3] = (value >> 24) & 0xff
}

///|
fn read_u32_le_at(code : Array[Int], offset : Int) -> Int {
  code[offset] |
  (code[offset + 1] << 8) |
  (code[offset + 2] << 16) |
  (code[offset + 3] << 24)
}

///|
fn signed_range_check(
  value : Int,
  bits : Int,
  context : String,
) -> Unit raise EmitError {
  let min = -(1 << (bits - 1))
  let max = (1 << (bits - 1)) - 1
  if value < min || value > max {
    raise BranchFixupError(
      message="\{context} displacement out of signed \{bits}-bit range",
    )
  }
}

///|
fn require_word_aligned_delta(
  delta : Int,
  context : String,
) -> Int raise EmitError {
  if delta % 4 != 0 {
    raise BranchFixupError(message="\{context} target is not 4-byte aligned")
  }
  delta / 4
}

///|
fn patch_x64_block_branch(
  object : CodeObject,
  branch_offset : Int,
  target_offset : Int,
) -> Unit raise EmitError {
  if branch_offset < 0 || branch_offset >= object.code.length() {
    raise BranchFixupError(message="X64 branch offset out of code bounds")
  }
  let opcode = object.code[branch_offset]
  if opcode == 0xe9 {
    let displacement = target_offset - (branch_offset + 5)
    write_i32_le_at(object.code, branch_offset + 1, displacement)
  } else if opcode == 0x0f && branch_offset + 5 < object.code.length() {
    let displacement = target_offset - (branch_offset + 6)
    write_i32_le_at(object.code, branch_offset + 2, displacement)
  } else {
    raise BranchFixupError(message="X64 branch fixup does not point at jmp/jcc")
  }
}

///|
fn patch_aarch64_block_branch(
  object : CodeObject,
  branch_offset : Int,
  target_offset : Int,
) -> Unit raise EmitError {
  if branch_offset < 0 || branch_offset + 3 >= object.code.length() {
    raise BranchFixupError(message="AArch64 branch offset out of code bounds")
  }
  let word = read_u32_le_at(object.code, branch_offset)
  let delta = target_offset - branch_offset
  if (word & 0x7c000000) == 0x14000000 {
    let imm26 = require_word_aligned_delta(delta, "AArch64 B/BL")
    signed_range_check(imm26, 26, "AArch64 B/BL")
    let patched = (word & 0xfc000000) | (imm26 & 0x03ffffff)
    write_i32_le_at(object.code, branch_offset, patched)
  } else if (word & 0xff000010) == 0x54000000 {
    let imm19 = require_word_aligned_delta(delta, "AArch64 B.cond")
    signed_range_check(imm19, 19, "AArch64 B.cond")
    let patched = (word & 0xff00001f) | ((imm19 & 0x7ffff) << 5)
    write_i32_le_at(object.code, branch_offset, patched)
  } else if (word & 0x7e000000) == 0x34000000 {
    let imm19 = require_word_aligned_delta(delta, "AArch64 CBZ/CBNZ")
    signed_range_check(imm19, 19, "AArch64 CBZ/CBNZ")
    let patched = (word & 0xff00001f) | ((imm19 & 0x7ffff) << 5)
    write_i32_le_at(object.code, branch_offset, patched)
  } else {
    raise BranchFixupError(
      message="AArch64 branch fixup does not point at branch",
    )
  }
}

///|
fn patch_block_fixups(
  object : CodeObject,
  target : EmitTarget,
  block_offsets : Array[(Int, Int)],
) -> Unit raise EmitError {
  for fixup in object.fixups {
    guard find_block_offset(block_offsets, fixup.block_id)
      is Some(target_offset) else {
      raise BranchFixupError(message="unknown block target \{fixup.block_id}")
    }
    match target {
      AArch64 => patch_aarch64_block_branch(object, fixup.offset, target_offset)
      X64 => patch_x64_block_branch(object, fixup.offset, target_offset)
    }
  }
}

///|
pub fn emit_function_for_target(
  func : @machv.Function,
  target : EmitTarget,
) -> CodeObject raise EmitError {
  let object = CodeObject::new()
  let block_offsets : Array[(Int, Int)] = []
  for block in func.blocks {
    block_offsets.push((block.id, object.current_offset()))
    for inst in block.instructions {
      emit_instruction(object, target, block.id, inst)
    }
    if block.terminator is Some(term) {
      emit_terminator(object, target, block.id, term)
    }
  }
  patch_block_fixups(object, target, block_offsets)
  object
}

///|
pub fn emit_function(func : @machv.Function) -> CodeObject raise EmitError {
  // TODO(machv_emit): require callers to pass target metadata instead of relying on this temporary AArch64 default.
  emit_function_for_target(func, AArch64)
}
