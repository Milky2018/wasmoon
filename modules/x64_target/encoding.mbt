///|
using @encoding {
  type RawLaneSize,
  type RawCondition,
  emit_u32_le,
  emit_rex_w,
  emit_modrm,
  x86_cond_to_jcc_opcode,
}
