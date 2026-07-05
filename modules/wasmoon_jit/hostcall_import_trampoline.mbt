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
  Interpcall(Int)
}

///|
fn RuntimeValueBridge::bridge_arg(self : RuntimeValueBridge) -> Int64 {
  match self {
    Hostcall(host_func_addr) => host_func_addr.to_int64()
    Interpcall(func_idx) => func_idx.to_int64()
  }
}

///|
fn RuntimeValueBridge::aarch64_runtime_fixup(self : RuntimeValueBridge) -> Int {
  match self {
    Hostcall(_) => jit_runtime_fixup_idx(13)
    Interpcall(_) => jit_runtime_fixup_idx(14)
  }
}

///|
fn RuntimeValueBridge::x64_bridge_ptr(self : RuntimeValueBridge) -> Int64 {
  match self {
    Hostcall(_) => @jit_ffi.c_jit_get_hostcall_ptr()
    Interpcall(_) => @jit_ffi.c_jit_get_interpcall_ptr()
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
fn hostcall_scalar_class(
  ty : @types.ValueType,
) -> @machv.RegClass raise HostcallImportTrampolineError {
  match ty {
    I32 | I64 => Int
    F32 => Float32
    F64 => Float64
    V128 =>
      raise UnsupportedHostcallImportTrampoline(
        message="TODO(ISS-026): hostcall import trampolines need V128 lane packing",
      )
    _ => Int
  }
}

///|
fn validate_hostcall_import_signature(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  max_int_regs : Int,
  max_float_regs : Int,
) -> Unit raise HostcallImportTrampolineError {
  let mut int_seen = 0
  let mut float_seen = 0
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int => int_seen = int_seen + 1
      Float32 | Float64 | Vector => float_seen = float_seen + 1
    }
  }
  if int_seen > max_int_regs || float_seen > max_float_regs {
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampolines need incoming stack-argument support",
    )
  }
  let mut int_results = 0
  let mut float_results = 0
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int => int_results = int_results + 1
      Float32 | Float64 | Vector => float_results = float_results + 1
    }
  }
  if int_results > 8 || float_results > 8 {
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampolines need overflow result areas",
    )
  }
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
  if imm < 0 || imm > 4095 {
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline stack adjustment needs large-immediate splitting",
    )
  }
  a64_emit(
    code,
    0x91000000 | ((imm & 0xfff) << 10) | ((rn & 31) << 5) | (rd & 31),
  )
}

///|
fn a64_emit_sub_imm(
  code : Array[Int],
  rd : Int,
  rn : Int,
  imm : Int,
) -> Unit raise HostcallImportTrampolineError {
  if imm < 0 || imm > 4095 {
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline stack adjustment needs large-immediate splitting",
    )
  }
  a64_emit(
    code,
    0xd1000000 | ((imm & 0xfff) << 10) | ((rn & 31) << 5) | (rd & 31),
  )
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
fn a64_emit_ldr_x(
  code : Array[Int],
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  if offset % 8 != 0 || offset < 0 || offset / 8 > 4095 {
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 load offsets",
    )
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
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 store offsets",
    )
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
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 f32 load offsets",
    )
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
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 f32 store offsets",
    )
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
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 f64 load offsets",
    )
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
    unsupported_hostcall_import(
      "TODO(ISS-026): hostcall import trampoline needs general AArch64 f64 store offsets",
    )
  }
  a64_emit(
    code,
    0xfd000000 | ((offset / 8) << 10) | ((rn & 31) << 5) | (rt & 31),
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
  match ty {
    F32 => a64_emit_str_s(code, reg, 31, offset)
    F64 => a64_emit_str_d(code, reg, 31, offset)
    _ => a64_emit_str_x(code, reg, 31, offset)
  }
}

///|
fn a64_emit_load_slot(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit raise HostcallImportTrampolineError {
  match ty {
    F32 => a64_emit_ldr_s(code, reg, 31, offset)
    F64 => a64_emit_ldr_d(code, reg, 31, offset)
    _ => a64_emit_ldr_x(code, reg, 31, offset)
  }
}

///|
fn build_aarch64_hostcall_import_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  bridge : RuntimeValueBridge,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  validate_hostcall_import_signature(param_types, result_types, 7, 8)
  let code : Array[Int] = []
  let layout = plan_hostcall_import_trampoline_layout(
    param_types, result_types, 7, 8,
  )
  let frame_size = align_to(layout.values_vec_bytes + 8, 16)
  if frame_size > 0 {
    a64_emit_sub_imm(code, 31, 31, frame_size)
    a64_emit_str_x(code, 30, 31, frame_size - 8)
  }
  let mut offset = 0
  let mut int_seen = 0
  let mut float_seen = 0
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int => {
        a64_emit_store_slot(code, ty, 1 + int_seen, offset)
        int_seen = int_seen + 1
      }
      Float32 | Float64 | Vector => {
        a64_emit_store_slot(code, ty, float_seen, offset)
        float_seen = float_seen + 1
      }
    }
    offset = offset + hostcall_value_byte_count(ty)
  }
  a64_emit_add_imm(code, 0, 21, 0)
  a64_emit_load_imm64_fixed(code, 1, bridge.bridge_arg())
  a64_emit_add_imm(code, 2, 31, 0)
  a64_emit_load_imm64_fixed(code, 3, layout.arg_slots.to_int64())
  a64_emit_load_imm64_fixed(code, 4, layout.result_slots.to_int64())
  let fixup_offset = code.length()
  a64_emit_load_imm64_fixed(code, 16, 0L)
  a64_emit_blr(code, 16)
  let mut result_offset = offset
  let mut int_result_seen = 0
  let mut float_result_seen = 0
  let int_result_regs = [0, 1, 2, 3, 4, 5, 6, 7]
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int => {
        a64_emit_load_slot(
          code,
          ty,
          int_result_regs[int_result_seen],
          result_offset,
        )
        int_result_seen = int_result_seen + 1
      }
      Float32 | Float64 | Vector => {
        a64_emit_load_slot(code, ty, float_result_seen, result_offset)
        float_result_seen = float_result_seen + 1
      }
    }
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  if frame_size > 0 {
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
fn x64_sib_rsp(code : Array[Int]) -> Unit {
  code.push(0x24)
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
fn x64_mov_m64_r64_rsp(code : Array[Int], offset : Int, src : Int) -> Unit {
  x64_rex(code, true, src, 4)
  code.push(0x89)
  x64_modrm(code, 2, src, 4)
  x64_sib_rsp(code)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_mov_r64_m64_rsp(code : Array[Int], dst : Int, offset : Int) -> Unit {
  x64_rex(code, true, dst, 4)
  code.push(0x8b)
  x64_modrm(code, 2, dst, 4)
  x64_sib_rsp(code)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movsd_m64_xmm_rsp(code : Array[Int], offset : Int, src : Int) -> Unit {
  code.push(0xf2)
  x64_rex(code, false, src, 4)
  code.push(0x0f)
  code.push(0x11)
  x64_modrm(code, 2, src, 4)
  x64_sib_rsp(code)
  hostcall_append_u32_le(code, offset)
}

///|
fn x64_movsd_xmm_m64_rsp(code : Array[Int], dst : Int, offset : Int) -> Unit {
  code.push(0xf2)
  x64_rex(code, false, dst, 4)
  code.push(0x0f)
  code.push(0x10)
  x64_modrm(code, 2, dst, 4)
  x64_sib_rsp(code)
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
  match ty {
    F32 | F64 => x64_movsd_m64_xmm_rsp(code, offset, reg)
    _ => x64_mov_m64_r64_rsp(code, offset, reg)
  }
}

///|
fn x64_emit_load_slot(
  code : Array[Int],
  ty : @types.ValueType,
  reg : Int,
  offset : Int,
) -> Unit {
  match ty {
    F32 | F64 => x64_movsd_xmm_m64_rsp(code, reg, offset)
    _ => x64_mov_r64_m64_rsp(code, reg, offset)
  }
}

///|
fn build_x64_hostcall_import_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  bridge : RuntimeValueBridge,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  validate_hostcall_import_signature(param_types, result_types, 5, 8)
  let code : Array[Int] = []
  let layout = plan_hostcall_import_trampoline_layout(
    param_types, result_types, 5, 8,
  )
  let frame_size = align_to(layout.values_vec_bytes + 8, 16)
  x64_sub_rsp(code, frame_size)
  let mut offset = 0
  let mut int_seen = 0
  let mut float_seen = 0
  let int_arg_regs = [6, 2, 1, 8, 9]
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int => {
        x64_emit_store_slot(code, ty, int_arg_regs[int_seen], offset)
        int_seen = int_seen + 1
      }
      Float32 | Float64 | Vector => {
        x64_emit_store_slot(code, ty, float_seen, offset)
        float_seen = float_seen + 1
      }
    }
    offset = offset + hostcall_value_byte_count(ty)
  }
  x64_mov_rr(code, 7, 15)
  x64_mov_imm64(code, 6, bridge.bridge_arg())
  x64_mov_rr(code, 2, 4)
  x64_mov_imm64(code, 1, layout.arg_slots.to_int64())
  x64_mov_imm64(code, 8, layout.result_slots.to_int64())
  x64_mov_imm64(code, 11, bridge.x64_bridge_ptr())
  x64_call_reg(code, 11)
  let mut result_offset = offset
  let mut int_result_seen = 0
  let mut float_result_seen = 0
  let int_result_regs = [0, 2, 1, 8, 9, 6, 7, 10]
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int => {
        x64_emit_load_slot(
          code,
          ty,
          int_result_regs[int_result_seen],
          result_offset,
        )
        int_result_seen = int_result_seen + 1
      }
      Float32 | Float64 | Vector => {
        x64_emit_load_slot(code, ty, float_result_seen, result_offset)
        float_result_seen = float_result_seen + 1
      }
    }
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
        message="TODO(ISS-026): hostcall import trampoline needs a concrete target architecture",
      )
  }
}

///|
pub fn build_interpreter_fallback_trampoline_for_target(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  func_idx : Int,
  target : @cwasm.TargetArch,
) -> HostcallImportTrampolineCode raise HostcallImportTrampolineError {
  match target {
    AArch64 =>
      build_aarch64_hostcall_import_trampoline(
        param_types,
        result_types,
        Interpcall(func_idx),
      )
    X86_64 =>
      build_x64_hostcall_import_trampoline(
        param_types,
        result_types,
        Interpcall(func_idx),
      )
    Unknown =>
      raise UnsupportedHostcallImportTrampoline(
        message="TODO(ISS-026): interpreter fallback trampoline needs a concrete target architecture",
      )
  }
}

///|
fn validate_entry_trampoline_signature(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  max_int_regs : Int,
  max_float_regs : Int,
) -> Unit raise HostcallImportTrampolineError {
  validate_hostcall_import_signature(
    param_types, result_types, max_int_regs, max_float_regs,
  )
}

///|
fn build_aarch64_entry_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Array[Int] raise HostcallImportTrampolineError {
  validate_entry_trampoline_signature(param_types, result_types, 7, 8)
  let code : Array[Int] = []
  a64_emit_sub_imm(code, 31, 31, 32)
  a64_emit_str_x(code, 19, 31, 0)
  a64_emit_str_x(code, 20, 31, 8)
  a64_emit_str_x(code, 30, 31, 24)
  a64_emit_add_imm(code, 19, 1, 0)
  a64_emit_add_imm(code, 20, 2, 0)
  let mut offset = 0
  let mut int_seen = 0
  let mut float_seen = 0
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int => {
        a64_emit_load_slot(code, ty, 1 + int_seen, offset)
        int_seen = int_seen + 1
      }
      Float32 | Float64 | Vector => {
        a64_emit_load_slot(code, ty, float_seen, offset)
        float_seen = float_seen + 1
      }
    }
    offset = offset + hostcall_value_byte_count(ty)
  }
  a64_emit_blr(code, 20)
  let mut result_offset = offset
  let mut int_result_seen = 0
  let mut float_result_seen = 0
  let int_result_regs = [0, 1, 2, 3, 4, 5, 6, 7]
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int => {
        a64_emit_store_slot(
          code,
          ty,
          int_result_regs[int_result_seen],
          result_offset,
        )
        int_result_seen = int_result_seen + 1
      }
      Float32 | Float64 | Vector => {
        a64_emit_store_slot(code, ty, float_result_seen, result_offset)
        float_result_seen = float_result_seen + 1
      }
    }
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  a64_emit_load_imm64_fixed(code, 0, 0L)
  a64_emit_ldr_x(code, 19, 31, 0)
  a64_emit_ldr_x(code, 20, 31, 8)
  a64_emit_ldr_x(code, 30, 31, 24)
  a64_emit_add_imm(code, 31, 31, 32)
  a64_emit_ret(code)
  code
}

///|
fn build_x64_entry_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Array[Int] raise HostcallImportTrampolineError {
  validate_entry_trampoline_signature(param_types, result_types, 5, 8)
  let code : Array[Int] = []
  code.push(0x41)
  code.push(0x54) // push r12
  code.push(0x41)
  code.push(0x55) // push r13
  code.push(0x48)
  code.push(0x83)
  code.push(0xec)
  code.push(0x08)
  x64_mov_rr(code, 12, 6)
  x64_mov_rr(code, 13, 2)
  let mut offset = 0
  let mut int_seen = 0
  let mut float_seen = 0
  let int_arg_regs = [6, 2, 1, 8, 9]
  for ty in param_types {
    match hostcall_scalar_class(ty) {
      Int => {
        x64_rex(code, true, int_arg_regs[int_seen], 12)
        code.push(0x8b)
        x64_modrm(code, 2, int_arg_regs[int_seen], 12)
        hostcall_append_u32_le(code, offset)
        int_seen = int_seen + 1
      }
      Float32 | Float64 | Vector => {
        code.push(0xf2)
        x64_rex(code, false, float_seen, 12)
        code.push(0x0f)
        code.push(0x10)
        x64_modrm(code, 2, float_seen, 12)
        hostcall_append_u32_le(code, offset)
        float_seen = float_seen + 1
      }
    }
    offset = offset + hostcall_value_byte_count(ty)
  }
  x64_call_reg(code, 13)
  let mut result_offset = offset
  let mut int_result_seen = 0
  let mut float_result_seen = 0
  let int_result_regs = [0, 2, 1, 8, 9, 6, 7, 10]
  for ty in result_types {
    match hostcall_scalar_class(ty) {
      Int => {
        x64_rex(code, true, int_result_regs[int_result_seen], 12)
        code.push(0x89)
        x64_modrm(code, 2, int_result_regs[int_result_seen], 12)
        hostcall_append_u32_le(code, result_offset)
        int_result_seen = int_result_seen + 1
      }
      Float32 | Float64 | Vector => {
        code.push(0xf2)
        x64_rex(code, false, float_result_seen, 12)
        code.push(0x0f)
        code.push(0x11)
        x64_modrm(code, 2, float_result_seen, 12)
        hostcall_append_u32_le(code, result_offset)
        float_result_seen = float_result_seen + 1
      }
    }
    result_offset = result_offset + hostcall_value_byte_count(ty)
  }
  x64_mov_imm64(code, 0, 0L)
  code.push(0x48)
  code.push(0x83)
  code.push(0xc4)
  code.push(0x08)
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
        message="TODO(ISS-026): entry trampoline needs a concrete target architecture",
      )
  }
}
