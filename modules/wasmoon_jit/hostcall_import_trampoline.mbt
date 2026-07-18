///|
/// Machine-code bytes for Wasm-ABI import trampolines that call the
/// `wasmoon_jit_hostcall` C bridge.
pub(all) struct HostcallImportTrampolineCode {
  code : Array[Int]
  func_addr_fixups : Array[@cwasm.FuncAddrFixup]
}

///|
pub suberror HostcallImportTrampolineError {
  UnsupportedHostcallImportTrampoline(message~ : String)
} derive(Debug, Eq)

///|
priv enum RuntimeValueBridge {
  Hostcall(Int)
}

///|
priv enum HostcallRegClass {
  Int
  Float32
  Float64
  Vector
}

///|
priv struct HostcallPReg {
  index : Int
}

///|
priv enum HostcallAbiValueLocation {
  Reg(HostcallPReg)
  Stack(offset~ : Int, size~ : Int)
  ReturnArea(offset~ : Int, size~ : Int)
}

///|
fn hostcall_abi_location_stack_size(location : HostcallAbiValueLocation) -> Int {
  match location {
    Reg(_) => 0
    Stack(size~, ..) | ReturnArea(size~, ..) => size
  }
}

///|
fn RuntimeValueBridge::bridge_arg(self : RuntimeValueBridge) -> Int64 {
  match self {
    Hostcall(host_func_addr) => host_func_addr.to_int64()
  }
}

///|
fn RuntimeValueBridge::aarch64_runtime_fixup(self : RuntimeValueBridge) -> Int {
  match self {
    Hostcall(_) => jit_runtime_fixup_idx(13)
  }
}

///|
fn RuntimeValueBridge::x64_bridge_ptr(self : RuntimeValueBridge) -> Int64 {
  match self {
    Hostcall(_) => @jit_ffi.c_jit_get_hostcall_ptr()
  }
}

///|
pub impl Show for HostcallImportTrampolineError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn unsupported_hostcall_import(
  message : String,
) -> Unit raise HostcallImportTrampolineError {
  raise UnsupportedHostcallImportTrampoline(message~)
}

///|
fn hostcall_scalar_class(ty : @types.ValueType) -> HostcallRegClass {
  match ty {
    I32 | I64 => Int
    F32 => Float32
    F64 => Float64
    V128 => Vector
    _ => Int
  }
}

///|
fn hostcall_abi_stack_align(ty : @types.ValueType) -> Int {
  match ty {
    V128 => 16
    _ => 8
  }
}

///|
fn hostcall_abi_stack_location(
  ty : @types.ValueType,
  offset : Int,
) -> HostcallAbiValueLocation {
  let size = hostcall_value_byte_count(ty)
  let align = hostcall_abi_stack_align(ty)
  align |> ignore
  Stack(offset~, size~)
}

///|
fn hostcall_param_locations(
  param_types : Array[@types.ValueType],
  int_arg_regs : Array[Int],
  float_arg_reg_count : Int,
) -> Array[HostcallAbiValueLocation] {
  let locations : Array[HostcallAbiValueLocation] = []
  let mut int_seen = 0
  let mut float_seen = 0
  let mut stack_offset = 0
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int =>
        if int_seen < int_arg_regs.length() {
          locations.push(Reg({ index: int_arg_regs[int_seen] }))
          int_seen = int_seen + 1
        } else {
          let align = hostcall_abi_stack_align(ty)
          let offset = align_to(stack_offset, align)
          let location = hostcall_abi_stack_location(ty, offset)
          locations.push(location)
          stack_offset = offset + hostcall_abi_location_stack_size(location)
          int_seen = int_seen + 1
        }
      Float32 | Float64 | Vector =>
        if float_seen < float_arg_reg_count {
          locations.push(Reg({ index: float_seen }))
          float_seen = float_seen + 1
        } else {
          let align = hostcall_abi_stack_align(ty)
          let offset = align_to(stack_offset, align)
          let location = hostcall_abi_stack_location(ty, offset)
          locations.push(location)
          stack_offset = offset + hostcall_abi_location_stack_size(location)
          float_seen = float_seen + 1
        }
    }
  }
  locations
}

///|
fn hostcall_abi_return_area_location(
  ty : @types.ValueType,
  offset : Int,
) -> HostcallAbiValueLocation {
  let size = hostcall_value_byte_count(ty)
  let align = hostcall_abi_stack_align(ty)
  align |> ignore
  ReturnArea(offset~, size~)
}

///|
fn hostcall_result_locations(
  result_types : Array[@types.ValueType],
  int_result_regs : Array[Int],
  float_result_reg_count : Int,
) -> Array[HostcallAbiValueLocation] {
  let locations : Array[HostcallAbiValueLocation] = []
  let mut int_seen = 0
  let mut float_seen = 0
  let mut return_area_offset = 0
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int =>
        if int_seen < int_result_regs.length() {
          locations.push(Reg({ index: int_result_regs[int_seen] }))
          int_seen = int_seen + 1
        } else {
          let align = hostcall_abi_stack_align(ty)
          let offset = align_to(return_area_offset, align)
          let location = hostcall_abi_return_area_location(ty, offset)
          locations.push(location)
          return_area_offset = offset +
            hostcall_abi_location_stack_size(location)
          int_seen = int_seen + 1
        }
      Float32 | Float64 | Vector =>
        if float_seen < float_result_reg_count {
          locations.push(Reg({ index: float_seen }))
          float_seen = float_seen + 1
        } else {
          let align = hostcall_abi_stack_align(ty)
          let offset = align_to(return_area_offset, align)
          let location = hostcall_abi_return_area_location(ty, offset)
          locations.push(location)
          return_area_offset = offset +
            hostcall_abi_location_stack_size(location)
          float_seen = float_seen + 1
        }
    }
  }
  locations
}

///|
fn hostcall_stack_arg_size(locations : Array[HostcallAbiValueLocation]) -> Int {
  let mut size = 0
  for location in locations {
    if location is Stack(offset~, ..) {
      let end = offset + hostcall_abi_location_stack_size(location)
      if end > size {
        size = end
      }
    }
  }
  align_to(size, 16)
}

///|
fn hostcall_return_area_size(
  locations : Array[HostcallAbiValueLocation],
) -> Int {
  let mut size = 0
  for location in locations {
    if location is ReturnArea(offset~, ..) {
      let end = offset + hostcall_abi_location_stack_size(location)
      if end > size {
        size = end
      }
    }
  }
  align_to(size, 16)
}

///|
fn validate_hostcall_import_signature(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Unit {
  param_types |> ignore
  result_types |> ignore
}

///|
fn hostcall_append_u32_le(code : Array[Int], word : Int) -> Unit {
  code.push(word & 0xff)
  code.push((word >> 8) & 0xff)
  code.push((word >> 16) & 0xff)
  code.push((word >> 24) & 0xff)
}

///|
fn hostcall_append_u64_le(code : Array[Int], word : Int64) -> Unit {
  let mut x = word
  for _ in 0..<8 {
    code.push((x & 0xffL).to_int())
    x = x >> 8
  }
}

///|
fn align_to(value : Int, align : Int) -> Int {
  if value == 0 {
    0
  } else {
    (value + align - 1) / align * align
  }
}

///|
fn a64_emit(code : Array[Int], word : Int) -> Unit {
  hostcall_append_u32_le(code, word)
}

///|
fn a64_emit_add_imm(
  code : Array[Int],
  rd : Int,
  rn : Int,
  imm : Int,
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
  code : Array[Int],
  rd : Int,
  rn : Int,
  imm : Int,
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
fn a64_emit_movz(code : Array[Int], rd : Int, imm16 : Int, shift : Int) -> Unit {
  let hw = shift / 16
  a64_emit(
    code,
    0xd2800000 | ((hw & 3) << 21) | ((imm16 & 0xffff) << 5) | (rd & 31),
  )
}

///|
fn a64_emit_movk(code : Array[Int], rd : Int, imm16 : Int, shift : Int) -> Unit {
  let hw = shift / 16
  a64_emit(
    code,
    0xf2800000 | ((hw & 3) << 21) | ((imm16 & 0xffff) << 5) | (rd & 31),
  )
}

///|
fn a64_emit_load_imm64_fixed(
  code : Array[Int],
  rd : Int,
  value : Int64,
) -> Unit {
  a64_emit_movz(code, rd, (value & 0xffffL).to_int(), 0)
  a64_emit_movk(code, rd, ((value >> 16) & 0xffffL).to_int(), 16)
  a64_emit_movk(code, rd, ((value >> 32) & 0xffffL).to_int(), 32)
  a64_emit_movk(code, rd, ((value >> 48) & 0xffffL).to_int(), 48)
}

///|
fn a64_emit_add_byte_offset(
  code : Array[Int],
  rd : Int,
  rn : Int,
  offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  if offset < 0 {
    unsupported_hostcall_import(
      "hostcall import trampoline AArch64 memory offset must be non-negative",
    )
  }
  a64_emit_add_imm(code, rd, rn, offset)
}

///|
fn a64_scratch_gpr_for(rt : Int) -> Int {
  if rt == 16 {
    17
  } else {
    16
  }
}

///|
fn a64_emit_ldr_x(
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
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
fn a64_emit_blr(code : Array[Int], rn : Int) -> Unit {
  a64_emit(code, 0xd63f0000 | ((rn & 31) << 5))
}

///|
fn a64_emit_ret(code : Array[Int]) -> Unit {
  a64_emit(code, 0xd65f03c0)
}

///|
fn a64_emit_store_slot(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  a64_emit_store_slot_base(code, ty, reg, 31, offset)
}

///|
fn a64_emit_store_slot_base(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  base : Int,
  offset : Int,
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
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  a64_emit_load_slot_base(code, ty, reg, 31, offset)
}

///|
fn a64_emit_load_slot_base(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  base : Int,
  offset : Int,
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
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
  caller_stack_base_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) => a64_emit_store_slot(code, ty, preg.index, values_offset)
    Stack(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 16
        Float32 | Float64 | Vector => 16
      }
      a64_emit_load_slot(code, ty, scratch, caller_stack_base_offset + offset)
      a64_emit_store_slot(code, ty, scratch, values_offset)
    }
    ReturnArea(..) =>
      unsupported_hostcall_import(
        "hostcall import trampoline parameters cannot live in return areas",
      )
  }
}

///|
fn a64_emit_load_result_from_values_vec(
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) => a64_emit_load_slot(code, ty, preg.index, values_offset)
    ReturnArea(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 16
        Float32 | Float64 | Vector => 16
      }
      a64_emit_load_slot(code, ty, scratch, values_offset)
      a64_emit_store_slot_base(code, ty, scratch, 23, offset)
    }
    Stack(..) =>
      unsupported_hostcall_import(
        "hostcall import trampoline results cannot live in stack argument slots",
      )
  }
}

///|
fn a64_emit_store_result_to_values_vec(
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
  return_area_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) =>
      a64_emit_store_slot_base(code, ty, preg.index, 19, values_offset)
    ReturnArea(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 16
        Float32 | Float64 | Vector => 16
      }
      a64_emit_load_slot(code, ty, scratch, return_area_offset + offset)
      a64_emit_store_slot_base(code, ty, scratch, 19, values_offset)
    }
    Stack(..) =>
      unsupported_hostcall_import(
        "entry trampoline results cannot live in stack argument slots",
      )
  }
}

///|
fn build_aarch64_hostcall_import_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  bridge : RuntimeValueBridge,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  validate_hostcall_import_signature(param_types, result_types)
  let code : Array[Int] = []
  let param_locations = hostcall_param_locations(
    param_types,
    [1, 2, 3, 4, 5, 6, 7],
    8,
  )
  let result_locations = hostcall_result_locations(
    result_types,
    [0, 1, 2, 3, 4, 5, 6, 7],
    8,
  )
  let layout = plan_hostcall_import_trampoline_layout(
    param_types, result_types, 7, 8,
  )
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
  a64_emit_load_imm64_fixed(code, 1, bridge.bridge_arg())
  a64_emit_add_imm(code, 2, 31, 0)
  a64_emit_load_imm64_fixed(code, 3, layout.arg_slots.to_int64())
  a64_emit_load_imm64_fixed(code, 4, layout.result_slots.to_int64())
  let fixup_offset = code.length()
  a64_emit_load_imm64_fixed(code, 16, 0L)
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
  {
    code,
    func_addr_fixups: [
      {
        offset: fixup_offset,
        func_idx: bridge.aarch64_runtime_fixup(),
        reg: 16,
      },
    ],
  }
}

///|
fn x64_rex(code : Array[Int], w : Bool, r : Int, b : Int) -> Unit {
  code.push(
    (if w { 0x48 } else { 0x40 }) | (((r >> 3) & 1) << 2) | ((b >> 3) & 1),
  )
}

///|
fn x64_modrm(code : Array[Int], mod_ : Int, reg : Int, rm : Int) -> Unit {
  code.push(((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7))
}

///|
fn x64_sib_base(code : Array[Int], base : Int) -> Unit {
  code.push(0x20 | (base & 7))
}

///|
fn x64_modrm_base_disp32(code : Array[Int], reg : Int, base : Int) -> Unit {
  x64_modrm(code, 2, reg, if (base & 7) == 4 { 4 } else { base })
  if (base & 7) == 4 {
    x64_sib_base(code, base)
  }
}

///|
fn x64_mov_rr(code : Array[Int], dst : Int, src : Int) -> Unit {
  x64_rex(code, true, src, dst)
  code.push(0x89)
  x64_modrm(code, 3, src, dst)
}

///|
fn x64_mov_imm64(code : Array[Int], dst : Int, value : Int64) -> Unit {
  x64_rex(code, true, 0, dst)
  code.push(0xb8 + (dst & 7))
  hostcall_append_u64_le(code, value)
}

///|
fn x64_add_rsp(code : Array[Int], imm : Int) -> Unit {
  code.push(0x48)
  code.push(0x81)
  code.push(0xc4)
  hostcall_append_u32_le(code, imm)
}

///|
fn x64_sub_rsp(code : Array[Int], imm : Int) -> Unit {
  code.push(0x48)
  code.push(0x81)
  code.push(0xec)
  hostcall_append_u32_le(code, imm)
}

///|
fn x64_lea_rsp_disp32(code : Array[Int], dst : Int, offset : Int) -> Unit {
  x64_rex(code, true, dst, 4)
  code.push(0x8d)
  x64_modrm_base_disp32(code, dst, 4)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_mov_m64_r64_base(
  code : Array[Int],
  base : Int,
  offset : Int,
  src : Int,
) -> Unit {
  x64_rex(code, true, src, base)
  code.push(0x89)
  x64_modrm_base_disp32(code, src, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_mov_r64_m64_base(
  code : Array[Int],
  dst : Int,
  base : Int,
  offset : Int,
) -> Unit {
  x64_rex(code, true, dst, base)
  code.push(0x8b)
  x64_modrm_base_disp32(code, dst, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movsd_m64_xmm_base(
  code : Array[Int],
  base : Int,
  offset : Int,
  src : Int,
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
  code : Array[Int],
  dst : Int,
  base : Int,
  offset : Int,
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
  code : Array[Int],
  base : Int,
  offset : Int,
  src : Int,
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
  code : Array[Int],
  dst : Int,
  base : Int,
  offset : Int,
) -> Unit {
  code.push(0xf3)
  x64_rex(code, false, dst, base)
  code.push(0x0f)
  code.push(0x6f)
  x64_modrm_base_disp32(code, dst, base)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_call_reg(code : Array[Int], reg : Int) -> Unit {
  x64_rex(code, false, 0, reg)
  code.push(0xff)
  x64_modrm(code, 3, 2, reg)
}

///|
fn x64_ret(code : Array[Int]) -> Unit {
  code.push(0xc3)
}

///|
fn x64_emit_store_slot(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit {
  x64_emit_store_slot_base(code, ty, reg, 4, offset)
}

///|
fn x64_emit_store_slot_base(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  base : Int,
  offset : Int,
) -> Unit {
  match ty {
    V128 => x64_movdqu_m128_xmm_base(code, base, offset, reg)
    F32 | F64 => x64_movsd_m64_xmm_base(code, base, offset, reg)
    _ => x64_mov_m64_r64_base(code, base, offset, reg)
  }
}

///|
fn x64_emit_load_slot(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit {
  x64_emit_load_slot_base(code, ty, reg, 4, offset)
}

///|
fn x64_emit_load_slot_base(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  base : Int,
  offset : Int,
) -> Unit {
  match ty {
    V128 => x64_movdqu_xmm_m128_base(code, reg, base, offset)
    F32 | F64 => x64_movsd_xmm_m64_base(code, reg, base, offset)
    _ => x64_mov_r64_m64_base(code, reg, base, offset)
  }
}

///|
fn x64_emit_store_arg_to_values_vec(
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
  caller_stack_base_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) => x64_emit_store_slot(code, ty, preg.index, values_offset)
    Stack(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 10
        Float32 | Float64 | Vector => 15
      }
      x64_emit_load_slot(code, ty, scratch, caller_stack_base_offset + offset)
      x64_emit_store_slot(code, ty, scratch, values_offset)
    }
    ReturnArea(..) =>
      unsupported_hostcall_import(
        "hostcall import trampoline parameters cannot live in return areas",
      )
  }
}

///|
fn x64_emit_load_result_from_values_vec(
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) => x64_emit_load_slot(code, ty, preg.index, values_offset)
    ReturnArea(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 10
        Float32 | Float64 | Vector => 15
      }
      x64_emit_load_slot(code, ty, scratch, values_offset)
      x64_emit_store_slot_base(code, ty, scratch, 12, offset)
    }
    Stack(..) =>
      unsupported_hostcall_import(
        "hostcall import trampoline results cannot live in stack argument slots",
      )
  }
}

///|
fn x64_emit_store_result_to_values_vec(
  code : Array[Int],
  ty : @types.ValueType,
  location : HostcallAbiValueLocation,
  values_offset : Int,
  return_area_offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match location {
    Reg(preg) =>
      x64_emit_store_slot_base(code, ty, preg.index, 14, values_offset)
    ReturnArea(offset~, ..) => {
      let scratch = match hostcall_scalar_class(ty) {
        Int => 10
        Float32 | Float64 | Vector => 15
      }
      x64_emit_load_slot(code, ty, scratch, return_area_offset + offset)
      x64_emit_store_slot_base(code, ty, scratch, 14, values_offset)
    }
    Stack(..) =>
      unsupported_hostcall_import(
        "entry trampoline results cannot live in stack argument slots",
      )
  }
}

///|
fn x64_hostcall_stack_adjust(values_vec_bytes : Int) -> Int {
  // SysV x64 enters a function with rsp % 16 == 8. Keep the adjustment at
  // 8 modulo 16 so rsp is 16-byte aligned before calling the C bridge.
  align_to(values_vec_bytes, 16) + 8
}

///|
fn build_x64_hostcall_import_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  bridge : RuntimeValueBridge,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  validate_hostcall_import_signature(param_types, result_types)
  let code : Array[Int] = []
  let int_arg_regs = [6, 2, 1, 8, 9]
  let param_locations = hostcall_param_locations(param_types, int_arg_regs, 8)
  let result_locations = hostcall_result_locations(
    result_types,
    [0, 2, 1, 8, 9, 6, 7, 10],
    8,
  )
  let layout = plan_hostcall_import_trampoline_layout(
    param_types, result_types, 5, 8,
  )
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
  x64_mov_imm64(code, 6, bridge.bridge_arg())
  x64_mov_rr(code, 2, 4)
  x64_mov_imm64(code, 1, layout.arg_slots.to_int64())
  x64_mov_imm64(code, 8, layout.result_slots.to_int64())
  x64_mov_imm64(code, 11, bridge.x64_bridge_ptr())
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
  { code, func_addr_fixups: [] }
}

///|
pub fn build_hostcall_import_trampoline_for_target(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  host_func_addr : Int,
  target : @cwasm.TargetArch,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  match target {
    AArch64 =>
      build_aarch64_hostcall_import_trampoline(
        param_types,
        result_types,
        Hostcall(host_func_addr),
      )
    X86_64 =>
      build_x64_hostcall_import_trampoline(
        param_types,
        result_types,
        Hostcall(host_func_addr),
      )
    Unknown =>
      raise UnsupportedHostcallImportTrampoline(
        message="hostcall import trampoline needs a concrete target architecture",
      )
  }
}

///|
fn validate_entry_trampoline_signature(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Unit {
  validate_hostcall_import_signature(param_types, result_types)
}

///|
fn build_aarch64_entry_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Array[Int] raise HostcallImportTrampolineError {
  validate_entry_trampoline_signature(param_types, result_types)
  let code : Array[Int] = []
  let param_locations = hostcall_param_locations(
    param_types,
    [1, 2, 3, 4, 5, 6, 7],
    8,
  )
  let result_locations = hostcall_result_locations(
    result_types,
    [0, 1, 2, 3, 4, 5, 6, 7],
    8,
  )
  let outgoing_stack_size = hostcall_stack_arg_size(param_locations)
  let return_area_size = hostcall_return_area_size(result_locations)
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
      Reg(preg) =>
        a64_emit_load_slot_base(code, ty, preg.index, 19, value_offset)
      Stack(offset~, ..) => {
        let scratch = match hostcall_scalar_class(ty) {
          Int => 16
          Float32 | Float64 | Vector => 16
        }
        a64_emit_load_slot_base(code, ty, scratch, 19, value_offset)
        a64_emit_store_slot(code, ty, scratch, offset)
      }
      ReturnArea(..) =>
        unsupported_hostcall_import(
          "entry trampoline parameters cannot live in return areas",
        )
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
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Array[Int] raise HostcallImportTrampolineError {
  validate_entry_trampoline_signature(param_types, result_types)
  let code : Array[Int] = []
  let int_arg_regs = [6, 2, 1, 8, 9]
  let param_locations = hostcall_param_locations(param_types, int_arg_regs, 8)
  let result_locations = hostcall_result_locations(
    result_types,
    [0, 2, 1, 8, 9, 6, 7, 10],
    8,
  )
  let outgoing_stack_size = hostcall_stack_arg_size(param_locations)
  let return_area_size = hostcall_return_area_size(result_locations)
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
      Reg(preg) =>
        match ty {
          V128 => x64_movdqu_xmm_m128_base(code, preg.index, 14, value_offset)
          F32 | F64 =>
            x64_movsd_xmm_m64_base(code, preg.index, 14, value_offset)
          _ => x64_mov_r64_m64_base(code, preg.index, 14, value_offset)
        }
      Stack(offset~, ..) => {
        let scratch = match hostcall_scalar_class(ty) {
          Int => 10
          Float32 | Float64 | Vector => 15
        }
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
      ReturnArea(..) =>
        unsupported_hostcall_import(
          "entry trampoline parameters cannot live in return areas",
        )
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
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  target : @cwasm.TargetArch,
) -> Array[Int] raise HostcallImportTrampolineError {
  match target {
    AArch64 => build_aarch64_entry_trampoline(param_types, result_types)
    X86_64 => build_x64_entry_trampoline(param_types, result_types)
    Unknown =>
      raise UnsupportedHostcallImportTrampoline(
        message="entry trampoline needs a concrete target architecture",
      )
  }
}
