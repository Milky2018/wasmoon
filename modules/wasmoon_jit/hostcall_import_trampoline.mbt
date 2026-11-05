///|
/// Machine-code bytes for Wasm-ABI import trampolines that call the
/// `wasmoon_jit_hostcall` C bridge.
pub(all) struct HostcallImportTrampolineCode {
  code : Array[Int32]
}

///|
#derive(Debug, Eq)
pub suberror HostcallImportTrampolineError {
  UnsupportedHostcallImportTrampoline(message~ : String)
}

///|
pub impl Show for HostcallImportTrampolineError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn unsupported_hostcall_import(
  message : String,
) -> Unit raise HostcallImportTrampolineError {
  raise UnsupportedHostcallImportTrampoline(message~)
}

///|
fn hostcall_append_u32_le(code : Array[Int32], word : Int32) -> Unit {
  code.push(word & 0xff)
  code.push((word >> 8) & 0xff)
  code.push((word >> 16) & 0xff)
  code.push((word >> 24) & 0xff)
}

///|
fn hostcall_append_u64_le(code : Array[Int32], word : Int64) -> Unit {
  let mut x = word
  for _ in 0..<8 {
    code.push((x & 0xffL).to_int())
    x = x >> 8
  }
}

///|
fn align_to(value : Int32, align : Int32) -> Int32 {
  if value == 0 {
    0
  } else {
    (value + align - 1) / align * align
  }
}

///|
fn a64_emit(code : Array[Int32], word : Int32) -> Unit {
  hostcall_append_u32_le(code, word)
}

///|
fn a64_emit_add_imm(
  code : Array[Int32],
  rd : Int32,
  rn : Int32,
  imm : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if imm < 0 {
    unsupported_hostcall_import(
      "hostcall import trampoline stack adjustment must be non-negative",
    )
  }
  if imm == 0 {
    a64_emit(code, 0x91000000 | ((rn & 31) << 5) | (rd & 31))
    return
  }
  let mut remaining = imm
  while remaining > 0 {
    let chunk = if remaining > 4095 { 4095 } else { remaining }
    a64_emit(
      code,
      0x91000000 | ((chunk & 0xfff) << 10) | ((rn & 31) << 5) | (rd & 31),
    )
    remaining = remaining - chunk
  }
}

///|
fn a64_emit_sub_imm(
  code : Array[Int32],
  rd : Int32,
  rn : Int32,
  imm : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if imm < 0 {
    unsupported_hostcall_import(
      "hostcall import trampoline stack adjustment must be non-negative",
    )
  }
  if imm == 0 {
    a64_emit(code, 0xd1000000 | ((rn & 31) << 5) | (rd & 31))
    return
  }
  let mut remaining = imm
  while remaining > 0 {
    let chunk = if remaining > 4095 { 4095 } else { remaining }
    a64_emit(
      code,
      0xd1000000 | ((chunk & 0xfff) << 10) | ((rn & 31) << 5) | (rd & 31),
    )
    remaining = remaining - chunk
  }
}

///|
fn a64_emit_movz(
  code : Array[Int32],
  rd : Int32,
  imm16 : Int32,
  shift : Int32,
) -> Unit {
  let hw = shift / 16
  a64_emit(
    code,
    0xd2800000 | ((hw & 3) << 21) | ((imm16 & 0xffff) << 5) | (rd & 31),
  )
}

///|
fn a64_emit_movk(
  code : Array[Int32],
  rd : Int32,
  imm16 : Int32,
  shift : Int32,
) -> Unit {
  let hw = shift / 16
  a64_emit(
    code,
    0xf2800000 | ((hw & 3) << 21) | ((imm16 & 0xffff) << 5) | (rd & 31),
  )
}

///|
fn a64_emit_load_imm64_fixed(
  code : Array[Int32],
  rd : Int32,
  value : Int64,
) -> Unit {
  a64_emit_movz(code, rd, (value & 0xffffL).to_int(), 0)
  a64_emit_movk(code, rd, ((value >> 16) & 0xffffL).to_int(), 16)
  a64_emit_movk(code, rd, ((value >> 32) & 0xffffL).to_int(), 32)
  a64_emit_movk(code, rd, ((value >> 48) & 0xffffL).to_int(), 48)
}

///|
fn a64_emit_add_byte_offset(
  code : Array[Int32],
  rd : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset < 0 {
    unsupported_hostcall_import(
      "hostcall import trampoline AArch64 memory offset must be non-negative",
    )
  }
  a64_emit_add_imm(code, rd, rn, offset)
}

///|
fn a64_scratch_gpr_for(rt : Int32) -> Int32 {
  if rt == 16 {
    17
  } else {
    16
  }
}

///|
fn a64_emit_ldr_x(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 8 != 0 || offset < 0 || offset / 8 > 4095 {
    let scratch = a64_scratch_gpr_for(rt)
    a64_emit_add_byte_offset(code, scratch, rn, offset)
    a64_emit_ldr_x(code, rt, scratch, 0)
    return
  }
  a64_emit(
    code,
    0xf9400000 | ((offset / 8) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_str_x(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 8 != 0 || offset < 0 || offset / 8 > 4095 {
    let scratch = a64_scratch_gpr_for(rt)
    a64_emit_add_byte_offset(code, scratch, rn, offset)
    a64_emit_str_x(code, rt, scratch, 0)
    return
  }
  a64_emit(
    code,
    0xf9000000 | ((offset / 8) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_ldr_s(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 4 != 0 || offset < 0 || offset / 4 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_ldr_s(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0xbd400000 | ((offset / 4) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_str_s(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 4 != 0 || offset < 0 || offset / 4 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_str_s(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0xbd000000 | ((offset / 4) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_ldr_d(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 8 != 0 || offset < 0 || offset / 8 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_ldr_d(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0xfd400000 | ((offset / 8) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_str_d(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 8 != 0 || offset < 0 || offset / 8 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_str_d(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0xfd000000 | ((offset / 8) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_ldr_q(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 16 != 0 || offset < 0 || offset / 16 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_ldr_q(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0x3dc00000 | ((offset / 16) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_str_q(
  code : Array[Int32],
  rt : Int32,
  rn : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 16 != 0 || offset < 0 || offset / 16 > 4095 {
    a64_emit_add_byte_offset(code, 16, rn, offset)
    a64_emit_str_q(code, rt, 16, 0)
    return
  }
  a64_emit(
    code,
    0x3d800000 | ((offset / 16) << 10) | ((rn & 31) << 5) | (rt & 31),
  )
}

///|
fn a64_emit_blr(code : Array[Int32], rn : Int32) -> Unit {
  a64_emit(code, 0xd63f0000 | ((rn & 31) << 5))
}

///|
fn a64_emit_ret(code : Array[Int32]) -> Unit {
  a64_emit(code, 0xd65f03c0)
}

///|
fn a64_emit_store_slot(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  a64_emit_store_slot_base(code, ty, reg, 31, offset)
}

///|
fn a64_emit_store_slot_base(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  base : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  match ty {
    F32 => a64_emit_str_s(code, reg, base, offset)
    F64 => a64_emit_str_d(code, reg, base, offset)
    V128 => a64_emit_str_q(code, reg, base, offset)
    _ => a64_emit_str_x(code, reg, base, offset)
  }
}

///|
fn a64_emit_load_slot(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  a64_emit_load_slot_base(code, ty, reg, 31, offset)
}

///|
fn a64_emit_load_slot_base(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  base : Int32,
  offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  match ty {
    F32 => a64_emit_ldr_s(code, reg, base, offset)
    F64 => a64_emit_ldr_d(code, reg, base, offset)
    V128 => a64_emit_ldr_q(code, reg, base, offset)
    _ => a64_emit_ldr_x(code, reg, base, offset)
  }
}

///|
fn a64_emit_store_arg_to_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallArgumentLocation,
  values_offset : Int32,
  caller_stack_base_offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    CallRegister(preg) => a64_emit_store_slot(code, ty, preg.id, values_offset)
    CallStack(offset) => {
      let scratch = 16
      a64_emit_load_slot(code, ty, scratch, caller_stack_base_offset + offset)
      a64_emit_store_slot(code, ty, scratch, values_offset)
    }
  }
}

///|
fn a64_emit_load_result_from_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallResultLocation,
  values_offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    CallResultRegister(preg) =>
      a64_emit_load_slot(code, ty, preg.id, values_offset)
    CallResultArea(offset, _) => {
      let scratch = 16
      a64_emit_load_slot(code, ty, scratch, values_offset)
      a64_emit_store_slot_base(code, ty, scratch, 23, offset)
    }
  }
}

///|
fn a64_emit_store_result_to_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallResultLocation,
  values_offset : Int32,
  return_area_offset : Int32,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    CallResultRegister(preg) =>
      a64_emit_store_slot_base(code, ty, preg.id, 19, values_offset)
    CallResultArea(offset, _) => {
      let scratch = 16
      a64_emit_load_slot(code, ty, scratch, return_area_offset + offset)
      a64_emit_store_slot_base(code, ty, scratch, 19, values_offset)
    }
  }
}

///|
fn build_aarch64_hostcall_import_trampoline(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
  host_func_addr : Int32,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  let code : Array[Int32] = []
  let plan = wasm_internal_bridge_plan(param_types, result_types, AArch64)
  let param_locations = plan.arguments[1:]
  let result_locations = plan.results
  let layout = plan_hostcall_import_trampoline_layout(param_types, result_types)
  // Preserve x23 while using it to keep the incoming x8 result-area pointer
  // alive across the platform C call. LR occupies the final eight bytes.
  let frame_size = align_to(layout.values_vec_bytes + 16, 16)
  if frame_size > 0 {
    a64_emit_sub_imm(code, 31, 31, frame_size)
    a64_emit_str_x(code, 23, 31, frame_size - 16)
    a64_emit_str_x(code, 30, 31, frame_size - 8)
  }
  a64_emit_add_imm(code, 23, 8, 0)
  let mut offset = 0
  for i, ty in param_types {
    a64_emit_store_arg_to_values_vec(
      code,
      ty,
      param_locations[i],
      offset,
      frame_size,
    )
    offset = offset + hostcall_value_byte_count(ty)
  }
  a64_emit_load_imm64_fixed(code, 1, host_func_addr.to_int64())
  a64_emit_add_imm(code, 2, 31, 0)
  a64_emit_load_imm64_fixed(code, 3, layout.arg_slots.to_int64())
  a64_emit_load_imm64_fixed(code, 4, layout.result_slots.to_int64())
  a64_emit_load_imm64_fixed(code, 16, c_jit_get_hostcall_ptr())
  a64_emit_blr(code, 16)
  let mut result_offset = offset
  for i, ty in result_types {
    a64_emit_load_result_from_values_vec(
      code,
      ty,
      result_locations[i],
      result_offset,
    )
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  if frame_size > 0 {
    a64_emit_ldr_x(code, 23, 31, frame_size - 16)
    a64_emit_ldr_x(code, 30, 31, frame_size - 8)
    a64_emit_add_imm(code, 31, 31, frame_size)
  }
  a64_emit_ret(code)
  { code, }
}

///|
fn x64_rex(code : Array[Int32], w : Bool, r : Int32, b : Int32) -> Unit {
  code.push(
    (if w { 0x48 } else { 0x40 }) | (((r >> 3) & 1) << 2) | ((b >> 3) & 1),
  )
}

///|
fn x64_modrm(
  code : Array[Int32],
  mod_ : Int32,
  reg : Int32,
  rm : Int32,
) -> Unit {
  code.push(((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7))
}

///|
fn x64_sib_base(code : Array[Int32], base : Int32) -> Unit {
  code.push(0x20 | (base & 7))
}

///|
fn x64_modrm_base_disp32(
  code : Array[Int32],
  reg : Int32,
  base : Int32,
) -> Unit {
  x64_modrm(code, 2, reg, if (base & 7) == 4 { 4 } else { base })
  if (base & 7) == 4 {
    x64_sib_base(code, base)
  }
}

///|
fn x64_mov_rr(code : Array[Int32], dst : Int32, src : Int32) -> Unit {
  x64_rex(code, true, src, dst)
  code.push(0x89)
  x64_modrm(code, 3, src, dst)
}

///|
fn x64_mov_imm64(code : Array[Int32], dst : Int32, value : Int64) -> Unit {
  x64_rex(code, true, 0, dst)
  code.push(0xb8 + (dst & 7))
  hostcall_append_u64_le(code, value)
}

///|
fn x64_add_rsp(code : Array[Int32], imm : Int32) -> Unit {
  code.push(0x48)
  code.push(0x81)
  code.push(0xc4)
  hostcall_append_u32_le(code, imm)
}

///|
fn x64_sub_rsp(code : Array[Int32], imm : Int32) -> Unit {
  code.push(0x48)
  code.push(0x81)
  code.push(0xec)
  hostcall_append_u32_le(code, imm)
}

///|
fn x64_lea_rsp_disp32(code : Array[Int32], dst : Int32, offset : Int32) -> Unit {
  x64_rex(code, true, dst, 4)
  code.push(0x8d)
  x64_modrm_base_disp32(code, dst, 4)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_mov_m64_r64_base(
  code : Array[Int32],
  base : Int32,
  offset : Int32,
  src : Int32,
) -> Unit {
  x64_rex(code, true, src, base)
  code.push(0x89)
  x64_modrm_base_disp32(code, src, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_mov_r64_m64_base(
  code : Array[Int32],
  dst : Int32,
  base : Int32,
  offset : Int32,
) -> Unit {
  x64_rex(code, true, dst, base)
  code.push(0x8b)
  x64_modrm_base_disp32(code, dst, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movsd_m64_xmm_base(
  code : Array[Int32],
  base : Int32,
  offset : Int32,
  src : Int32,
) -> Unit {
  code.push(0xf2)
  x64_rex(code, false, src, base)
  code.push(0x0f)
  code.push(0x11)
  x64_modrm_base_disp32(code, src, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movsd_xmm_m64_base(
  code : Array[Int32],
  dst : Int32,
  base : Int32,
  offset : Int32,
) -> Unit {
  code.push(0xf2)
  x64_rex(code, false, dst, base)
  code.push(0x0f)
  code.push(0x10)
  x64_modrm_base_disp32(code, dst, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movdqu_m128_xmm_base(
  code : Array[Int32],
  base : Int32,
  offset : Int32,
  src : Int32,
) -> Unit {
  code.push(0xf3)
  x64_rex(code, false, src, base)
  code.push(0x0f)
  code.push(0x7f)
  x64_modrm_base_disp32(code, src, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movdqu_xmm_m128_base(
  code : Array[Int32],
  dst : Int32,
  base : Int32,
  offset : Int32,
) -> Unit {
  code.push(0xf3)
  x64_rex(code, false, dst, base)
  code.push(0x0f)
  code.push(0x6f)
  x64_modrm_base_disp32(code, dst, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_call_reg(code : Array[Int32], reg : Int32) -> Unit {
  x64_rex(code, false, 0, reg)
  code.push(0xff)
  x64_modrm(code, 3, 2, reg)
}

///|
fn x64_ret(code : Array[Int32]) -> Unit {
  code.push(0xc3)
}

///|
fn x64_emit_store_slot(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  offset : Int32,
) -> Unit {
  x64_emit_store_slot_base(code, ty, reg, 4, offset)
}

///|
fn x64_emit_store_slot_base(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  base : Int32,
  offset : Int32,
) -> Unit {
  match ty {
    V128 => x64_movdqu_m128_xmm_base(code, base, offset, reg)
    F32 | F64 => x64_movsd_m64_xmm_base(code, base, offset, reg)
    _ => x64_mov_m64_r64_base(code, base, offset, reg)
  }
}

///|
fn x64_emit_load_slot(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  offset : Int32,
) -> Unit {
  x64_emit_load_slot_base(code, ty, reg, 4, offset)
}

///|
fn x64_emit_load_slot_base(
  code : Array[Int32],
  ty : @types.ValueType,
  reg : Int32,
  base : Int32,
  offset : Int32,
) -> Unit {
  match ty {
    V128 => x64_movdqu_xmm_m128_base(code, reg, base, offset)
    F32 | F64 => x64_movsd_xmm_m64_base(code, reg, base, offset)
    _ => x64_mov_r64_m64_base(code, reg, base, offset)
  }
}

///|
fn x64_emit_store_arg_to_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallArgumentLocation,
  values_offset : Int32,
  caller_stack_base_offset : Int32,
) -> Unit {
  match location {
    CallRegister(preg) => x64_emit_store_slot(code, ty, preg.id, values_offset)
    CallStack(offset) => {
      let scratch = if is_hostcall_int_class(ty) { 10 } else { 15 }
      x64_emit_load_slot(code, ty, scratch, caller_stack_base_offset + offset)
      x64_emit_store_slot(code, ty, scratch, values_offset)
    }
  }
}

///|
fn x64_emit_load_result_from_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallResultLocation,
  values_offset : Int32,
) -> Unit {
  match location {
    CallResultRegister(preg) =>
      x64_emit_load_slot(code, ty, preg.id, values_offset)
    CallResultArea(offset, _) => {
      // r10 already holds the eighth integer result. r11 is call scratch.
      let scratch = if is_hostcall_int_class(ty) { 11 } else { 15 }
      x64_emit_load_slot(code, ty, scratch, values_offset)
      x64_emit_store_slot_base(code, ty, scratch, 12, offset)
    }
  }
}

///|
fn x64_emit_store_result_to_values_vec(
  code : Array[Int32],
  ty : @types.ValueType,
  location : @vcode.CallResultLocation,
  values_offset : Int32,
  return_area_offset : Int32,
) -> Unit {
  match location {
    CallResultRegister(preg) =>
      x64_emit_store_slot_base(code, ty, preg.id, 14, values_offset)
    CallResultArea(offset, _) => {
      let scratch = if is_hostcall_int_class(ty) { 10 } else { 15 }
      x64_emit_load_slot(code, ty, scratch, return_area_offset + offset)
      x64_emit_store_slot_base(code, ty, scratch, 14, values_offset)
    }
  }
}

///|
fn x64_hostcall_stack_adjust(values_vec_bytes : Int32) -> Int32 {
  // SysV x64 enters a function with rsp % 16 == 8. Keep the adjustment at
  // 8 modulo 16 so rsp is 16-byte aligned before calling the C bridge.
  align_to(values_vec_bytes, 16) + 8
}

///|
fn build_x64_hostcall_import_trampoline(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
  host_func_addr : Int32,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  let code : Array[Int32] = []
  let plan = wasm_internal_bridge_plan(param_types, result_types, X64)
  let param_locations = plan.arguments[1:]
  let result_locations = plan.results
  let layout = plan_hostcall_import_trampoline_layout(param_types, result_types)
  let frame_size = x64_hostcall_stack_adjust(layout.values_vec_bytes)
  x64_sub_rsp(code, frame_size)
  let mut offset = 0
  for i, ty in param_types {
    x64_emit_store_arg_to_values_vec(
      code,
      ty,
      param_locations[i],
      offset,
      frame_size + 8,
    )
    offset = offset + hostcall_value_byte_count(ty)
  }
  x64_mov_imm64(code, 6, host_func_addr.to_int64())
  x64_mov_rr(code, 2, 4)
  x64_mov_imm64(code, 1, layout.arg_slots.to_int64())
  x64_mov_imm64(code, 8, layout.result_slots.to_int64())
  x64_mov_imm64(code, 11, c_jit_get_hostcall_ptr())
  x64_call_reg(code, 11)
  let mut result_offset = offset
  for i, ty in result_types {
    x64_emit_load_result_from_values_vec(
      code,
      ty,
      result_locations[i],
      result_offset,
    )
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  x64_add_rsp(code, frame_size)
  x64_ret(code)
  { code, }
}

///|
pub fn build_hostcall_import_trampoline_for_target(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
  host_func_addr : Int32,
  target : NativeTarget,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  match target {
    AArch64 =>
      build_aarch64_hostcall_import_trampoline(
        param_types, result_types, host_func_addr,
      )
    X64 =>
      build_x64_hostcall_import_trampoline(
        param_types, result_types, host_func_addr,
      )
  }
}

///|
fn build_aarch64_entry_trampoline(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
) -> Array[Int32] raise HostcallImportTrampolineError {
  let code : Array[Int32] = []
  let plan = wasm_internal_bridge_plan(param_types, result_types, AArch64)
  let param_locations = plan.arguments[1:]
  let result_locations = plan.results
  let outgoing_stack_size = plan.stack_size
  let return_area_size = plan.result_area_size
  let return_area_offset = outgoing_stack_size
  let save_area_offset = return_area_offset + return_area_size
  let frame_size = align_to(save_area_offset + 32, 16)
  a64_emit_sub_imm(code, 31, 31, frame_size)
  a64_emit_str_x(code, 19, 31, save_area_offset)
  a64_emit_str_x(code, 20, 31, save_area_offset + 8)
  a64_emit_str_x(code, 23, 31, save_area_offset + 16)
  a64_emit_str_x(code, 30, 31, save_area_offset + 24)
  a64_emit_add_imm(code, 19, 1, 0)
  a64_emit_add_imm(code, 20, 2, 0)
  if return_area_size > 0 {
    a64_emit_add_imm(code, 23, 31, return_area_offset)
    a64_emit_add_imm(code, 8, 23, 0)
  }
  let mut value_offset = 0
  for i, ty in param_types {
    match param_locations[i] {
      CallRegister(preg) =>
        a64_emit_load_slot_base(code, ty, preg.id, 19, value_offset)
      CallStack(offset) => {
        let scratch = 16
        a64_emit_load_slot_base(code, ty, scratch, 19, value_offset)
        a64_emit_store_slot(code, ty, scratch, offset)
      }
    }
    value_offset = value_offset + hostcall_value_byte_count(ty)
  }
  a64_emit_blr(code, 20)
  let mut result_offset = value_offset
  for i, ty in result_types {
    a64_emit_store_result_to_values_vec(
      code,
      ty,
      result_locations[i],
      result_offset,
      return_area_offset,
    )
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  a64_emit_load_imm64_fixed(code, 0, 0L)
  a64_emit_ldr_x(code, 19, 31, save_area_offset)
  a64_emit_ldr_x(code, 20, 31, save_area_offset + 8)
  a64_emit_ldr_x(code, 23, 31, save_area_offset + 16)
  a64_emit_ldr_x(code, 30, 31, save_area_offset + 24)
  a64_emit_add_imm(code, 31, 31, frame_size)
  a64_emit_ret(code)
  code
}

///|
fn build_x64_entry_trampoline(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
) -> Array[Int32] raise HostcallImportTrampolineError {
  let code : Array[Int32] = []
  let plan = wasm_internal_bridge_plan(param_types, result_types, X64)
  let param_locations = plan.arguments[1:]
  let result_locations = plan.results
  let outgoing_stack_size = plan.stack_size
  let return_area_size = plan.result_area_size
  let return_area_offset = outgoing_stack_size
  let stack_adjust = outgoing_stack_size + return_area_size
  code.push(0x41)
  code.push(0x54) // push r12
  code.push(0x41)
  code.push(0x55) // push r13
  code.push(0x41)
  code.push(0x56) // push r14
  x64_sub_rsp(code, stack_adjust)
  x64_mov_rr(code, 14, 6)
  x64_mov_rr(code, 13, 2)
  if return_area_size > 0 {
    x64_lea_rsp_disp32(code, 12, return_area_offset)
  }
  let mut value_offset = 0
  for i, ty in param_types {
    match param_locations[i] {
      CallRegister(preg) =>
        match ty {
          V128 => x64_movdqu_xmm_m128_base(code, preg.id, 14, value_offset)
          F32 | F64 => x64_movsd_xmm_m64_base(code, preg.id, 14, value_offset)
          _ => x64_mov_r64_m64_base(code, preg.id, 14, value_offset)
        }
      CallStack(offset) => {
        let scratch = if is_hostcall_int_class(ty) { 10 } else { 15 }
        match ty {
          V128 => {
            x64_movdqu_xmm_m128_base(code, scratch, 14, value_offset)
            x64_emit_store_slot_base(code, ty, scratch, 4, offset)
          }
          F32 | F64 => {
            x64_movsd_xmm_m64_base(code, scratch, 14, value_offset)
            x64_emit_store_slot_base(code, ty, scratch, 4, offset)
          }
          _ => {
            x64_mov_r64_m64_base(code, scratch, 14, value_offset)
            x64_emit_store_slot_base(code, ty, scratch, 4, offset)
          }
        }
      }
    }
    value_offset = value_offset + hostcall_value_byte_count(ty)
  }
  x64_call_reg(code, 13)
  let mut result_offset = value_offset
  for i, ty in result_types {
    x64_emit_store_result_to_values_vec(
      code,
      ty,
      result_locations[i],
      result_offset,
      return_area_offset,
    )
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  x64_mov_imm64(code, 0, 0L)
  x64_add_rsp(code, stack_adjust)
  code.push(0x41)
  code.push(0x5e) // pop r14
  code.push(0x41)
  code.push(0x5d) // pop r13
  code.push(0x41)
  code.push(0x5c) // pop r12
  x64_ret(code)
  code
}

///|
pub fn build_entry_trampoline_for_target(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
  target : NativeTarget,
) -> Array[Int32] raise HostcallImportTrampolineError {
  match target {
    AArch64 => build_aarch64_entry_trampoline(param_types, result_types)
    X64 => build_x64_entry_trampoline(param_types, result_types)
  }
}
