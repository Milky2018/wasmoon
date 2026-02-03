// AArch64-Specific Instruction Selection Patterns
// Target-specific lowering rules for ARM64 architecture
//
// This module provides:
// 1. AArch64-specific pattern matching rules
// 2. Rewrite result types for AArch64 instruction selection
// 3. Helper functions for immediate validation
//
// Note: AArch64-specific opcodes (Madd, Msub, Mneg, AddShifted, etc.) are
// defined in vcode.mbt as part of VCodeOpcode. This design choice keeps
// VCode self-contained for a single target (AArch64). If multi-target support
// is needed in the future, a separate AArch64Inst type should be introduced.

// ============ AArch64 Rule Application Results ============

///|
/// Result of applying an AArch64-specific rule
pub enum AArch64RewriteResult {
  // Emit add with shifted operand
  AddShifted(Int, Int, Int) // src1_idx, src2_idx, shift_amount
  // Emit sub with shifted operand
  SubShifted(Int, Int, Int) // src1_idx, src2_idx, shift_amount
  // Emit multiply-add
  Madd(Int, Int, Int) // acc_idx, src1_idx, src2_idx
  // Emit multiply-sub
  Msub(Int, Int, Int) // acc_idx, src1_idx, src2_idx
  // Emit negated multiply
  Mneg(Int, Int) // src1_idx, src2_idx
  // Emit and/or/xor with shifted operand
  LogicalShifted(@instr.VCodeOpcode, Int, Int, Int) // op, src1_idx, src2_idx, shift
  // No AArch64-specific optimization applies
  NoMatch
}

// ============ AArch64 Lowering Rules ============

///|
/// Check if an immediate can be encoded in AArch64 add/sub instruction
/// AArch64 allows 12-bit immediates, optionally shifted left by 12
pub fn is_valid_add_imm(val : Int64) -> Bool {
  // Check if value fits in 12 bits (0-4095)
  if val >= 0L && val <= 4095L {
    return true
  }
  // Check if value fits in shifted form (0x000000 to 0xFFF000)
  if val >= 0L && (val & 0xFFFL) == 0L && logical_shift_right(val, 12L) <= 4095L {
    return true
  }
  false
}

///|
/// Check if an immediate can be encoded in AArch64 logical instructions
/// Uses bitmask immediate encoding: a repeating pattern of consecutive 1s
/// that can be rotated within an element of size 2, 4, 8, 16, 32, or 64 bits.
pub fn is_valid_logical_imm(val : Int64) -> Bool {
  @instr.aarch64_logic_imm_enc_bits(val, true) is Some(_)
}

///|
/// Check if a value has consecutive 1s in binary representation
pub fn is_consecutive_ones(val : Int64) -> Bool {
  if val == 0L {
    return false
  }
  // A value has consecutive 1s if (val + (val & -val)) is a power of 2 or 0
  let lowest_bit = val & -val
  let sum = val + lowest_bit
  // sum should be 0 or a power of 2
  sum == 0L || (sum & (sum - 1L)) == 0L
}

///|
/// Get AArch64-specific optimization rules
pub fn get_aarch64_rules() -> Array[RewriteRule] {
  [
    // add(x, shl(y, n)) -> add_shifted(x, y, lsl #n)
    // This pattern combines shift-and-add into a single instruction
    RewriteRule::new(
      "aarch64_add_shifted",
      Inst(Iadd, [Any, Inst(Ishl, [Any, AnyConstInt])]),
      20,
    ),
    // add(shl(x, n), y) -> add_shifted(y, x, lsl #n) (commutative)
    RewriteRule::new(
      "aarch64_shifted_add",
      Inst(Iadd, [Inst(Ishl, [Any, AnyConstInt]), Any]),
      20,
    ),
    // sub(x, shl(y, n)) -> sub_shifted(x, y, lsl #n)
    RewriteRule::new(
      "aarch64_sub_shifted",
      Inst(Isub, [Any, Inst(Ishl, [Any, AnyConstInt])]),
      20,
    ),
    // add(a, mul(b, c)) -> madd(a, b, c)
    RewriteRule::new(
      "aarch64_madd",
      Inst(Iadd, [Any, Inst(Imul, [Any, Any])]),
      25,
    ),
    // add(mul(a, b), c) -> madd(c, a, b) (commutative)
    RewriteRule::new(
      "aarch64_madd_comm",
      Inst(Iadd, [Inst(Imul, [Any, Any]), Any]),
      25,
    ),
    // sub(a, mul(b, c)) -> msub(a, b, c)
    RewriteRule::new(
      "aarch64_msub",
      Inst(Isub, [Any, Inst(Imul, [Any, Any])]),
      25,
    ),
    // sub(0, mul(a, b)) -> mneg(a, b)
    RewriteRule::new(
      "aarch64_mneg",
      Inst(Isub, [ConstInt(0L), Inst(Imul, [Any, Any])]),
      25,
    ),
    // and(x, shl(y, n)) -> and_shifted(x, y, lsl #n)
    RewriteRule::new(
      "aarch64_and_shifted",
      Inst(Band, [Any, Inst(Ishl, [Any, AnyConstInt])]),
      20,
    ),
    // or(x, shl(y, n)) -> orr_shifted(x, y, lsl #n)
    RewriteRule::new(
      "aarch64_orr_shifted",
      Inst(Bor, [Any, Inst(Ishl, [Any, AnyConstInt])]),
      20,
    ),
    // xor(x, shl(y, n)) -> eor_shifted(x, y, lsl #n)
    RewriteRule::new(
      "aarch64_eor_shifted",
      Inst(Bxor, [Any, Inst(Ishl, [Any, AnyConstInt])]),
      20,
    ),
  ]
}

// ============ AArch64 Rule Application ============

///|
/// Apply an AArch64-specific rule
pub fn apply_aarch64_rule(
  rule_name : String,
  result : MatchResult,
  inst : @ir.Inst,
  ctx : LoweringContext,
) -> AArch64RewriteResult {
  ignore(inst)
  ignore(ctx)
  match rule_name {
    // add(x, shl(y, n)) -> add_shifted(x, y, lsl #n)
    "aarch64_add_shifted" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          AArch64RewriteResult::AddShifted(0, 1, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    // add(shl(x, n), y) -> add_shifted(y, x, lsl #n)
    "aarch64_shifted_add" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          // Note: operands are swapped
          AArch64RewriteResult::AddShifted(2, 0, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    // sub(x, shl(y, n)) -> sub_shifted(x, y, lsl #n)
    "aarch64_sub_shifted" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          AArch64RewriteResult::SubShifted(0, 1, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    // add(a, mul(b, c)) -> madd(a, b, c)
    "aarch64_madd" => AArch64RewriteResult::Madd(0, 1, 2)
    // add(mul(a, b), c) -> madd(c, a, b)
    "aarch64_madd_comm" => AArch64RewriteResult::Madd(2, 0, 1)
    // sub(a, mul(b, c)) -> msub(a, b, c)
    "aarch64_msub" => AArch64RewriteResult::Msub(0, 1, 2)
    // sub(0, mul(a, b)) -> mneg(a, b)
    "aarch64_mneg" => AArch64RewriteResult::Mneg(0, 1)
    // Logical operations with shifted operand
    "aarch64_and_shifted" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          AArch64RewriteResult::LogicalShifted(And(true), 0, 1, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    "aarch64_orr_shifted" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          AArch64RewriteResult::LogicalShifted(Or(true), 0, 1, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    "aarch64_eor_shifted" =>
      if result.int_consts.length() > 0 {
        let shift = result.int_consts[0].to_int()
        if shift >= 0 && shift <= 63 {
          AArch64RewriteResult::LogicalShifted(Xor(true), 0, 1, shift)
        } else {
          AArch64RewriteResult::NoMatch
        }
      } else {
        AArch64RewriteResult::NoMatch
      }
    _ => AArch64RewriteResult::NoMatch
  }
}

// ============ Helpers ============

///|
fn logical_shift_right(val : Int64, shift : Int64) -> Int64 {
  (val.reinterpret_as_uint64() >> shift.to_int()).reinterpret_as_int64()
}
