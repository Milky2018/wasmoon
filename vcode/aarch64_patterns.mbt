// AArch64-Specific Instruction Selection Patterns
// Target-specific lowering rules for ARM64 architecture
//
// This module provides:
// 1. AArch64-specific pattern matching rules
// 2. Instruction forms optimized for ARM64 (e.g., shifted operands)
// 3. Addressing mode selection
// 4. AArch64-specific peephole optimizations

// ============ AArch64 Instruction Opcodes ============

///|
/// AArch64-specific VCode opcodes
/// These represent actual ARM64 instructions more closely
pub enum AArch64Opcode {
  // Arithmetic with optional shifted operand
  AddShifted(AArch64Shift, Int) // ADD Xd, Xn, Xm, shift #amount
  SubShifted(AArch64Shift, Int) // SUB Xd, Xn, Xm, shift #amount
  // Arithmetic with immediate
  AddImm(Int64) // ADD Xd, Xn, #imm
  SubImm(Int64) // SUB Xd, Xn, #imm
  // Logical with shifted operand
  AndShifted(AArch64Shift, Int)
  OrrShifted(AArch64Shift, Int)
  EorShifted(AArch64Shift, Int)
  // Logical with immediate
  AndImm(Int64)
  OrrImm(Int64)
  EorImm(Int64)
  // Multiply-add/subtract
  Madd // Xd = Xa + Xn * Xm
  Msub // Xd = Xa - Xn * Xm
  Mneg // Xd = -(Xn * Xm)
  // Load with addressing modes
  LdrOffset(Int) // LDR Xd, [Xn, #offset]
  LdrPreIndex(Int) // LDR Xd, [Xn, #offset]!
  LdrPostIndex(Int) // LDR Xd, [Xn], #offset
  LdrRegister(AArch64Extend) // LDR Xd, [Xn, Xm, extend]
  // Store with addressing modes
  StrOffset(Int) // STR Xd, [Xn, #offset]
  StrPreIndex(Int) // STR Xd, [Xn, #offset]!
  StrPostIndex(Int) // STR Xd, [Xn], #offset
  StrRegister(AArch64Extend) // STR Xd, [Xn, Xm, extend]
  // Compare and branch
  Cbz // CBZ Xn, label
  Cbnz // CBNZ Xn, label
  Tbz(Int) // TBZ Xn, #bit, label
  Tbnz(Int) // TBNZ Xn, #bit, label
  // Conditional operations
  Csel(AArch64Cond) // CSEL Xd, Xn, Xm, cond
  Csinc(AArch64Cond) // CSINC Xd, Xn, Xm, cond
  Csneg(AArch64Cond) // CSNEG Xd, Xn, Xm, cond
  Csinv(AArch64Cond) // CSINV Xd, Xn, Xm, cond
  // Bit manipulation
  Ubfx(Int, Int) // UBFX Xd, Xn, #lsb, #width
  Sbfx(Int, Int) // SBFX Xd, Xn, #lsb, #width
  Bfi(Int, Int) // BFI Xd, Xn, #lsb, #width
  Bfxil(Int, Int) // BFXIL Xd, Xn, #lsb, #width
  // Move with immediate (for constant generation)
  Movz(Int) // MOVZ Xd, #imm, LSL #shift
  Movn(Int) // MOVN Xd, #imm, LSL #shift
  Movk(Int) // MOVK Xd, #imm, LSL #shift
}

///|
/// AArch64 shift types for shifted operand instructions
pub enum AArch64Shift {
  Lsl // Logical shift left
  Lsr // Logical shift right
  Asr // Arithmetic shift right
  Ror // Rotate right
}

///|
/// AArch64 extend types for register operand instructions
pub enum AArch64Extend {
  Uxtb // Unsigned extend byte
  Uxth // Unsigned extend halfword
  Uxtw // Unsigned extend word
  Uxtx // Unsigned extend doubleword (no-op for 64-bit)
  Sxtb // Signed extend byte
  Sxth // Signed extend halfword
  Sxtw // Signed extend word
  Sxtx // Signed extend doubleword (no-op for 64-bit)
}

///|
/// AArch64 condition codes
pub enum AArch64Cond {
  Eq // Equal
  Ne // Not equal
  Cs // Carry set (unsigned >=)
  Cc // Carry clear (unsigned <)
  Mi // Minus/negative
  Pl // Plus/positive or zero
  Vs // Overflow
  Vc // No overflow
  Hi // Unsigned higher (>)
  Ls // Unsigned lower or same (<=)
  Ge // Signed greater than or equal
  Lt // Signed less than
  Gt // Signed greater than
  Le // Signed less than or equal
  Al // Always (unconditional)
  Nv // Never (unconditional, same as AL)
}

///|
fn AArch64Shift::to_string(self : AArch64Shift) -> String {
  match self {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
    Ror => "ror"
  }
}

///|
fn AArch64Extend::to_string(self : AArch64Extend) -> String {
  match self {
    Uxtb => "uxtb"
    Uxth => "uxth"
    Uxtw => "uxtw"
    Uxtx => "uxtx"
    Sxtb => "sxtb"
    Sxth => "sxth"
    Sxtw => "sxtw"
    Sxtx => "sxtx"
  }
}

///|
fn AArch64Cond::to_string(self : AArch64Cond) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Cs => "cs"
    Cc => "cc"
    Mi => "mi"
    Pl => "pl"
    Vs => "vs"
    Vc => "vc"
    Hi => "hi"
    Ls => "ls"
    Ge => "ge"
    Lt => "lt"
    Gt => "gt"
    Le => "le"
    Al => "al"
    Nv => "nv"
  }
}

// ============ AArch64 Pattern Matching ============

///|
/// AArch64-specific pattern for matching complex instruction forms
pub enum AArch64Pattern {
  // Match add with shifted operand: add(x, shl(y, n))
  AddWithShift(Int) // shift amount
  // Match add with extend: add(x, extend(y))
  AddWithExtend(AArch64Extend)
  // Match multiply-accumulate: add(a, mul(b, c))
  MultiplyAdd
  // Match multiply-subtract: sub(a, mul(b, c))
  MultiplySub
  // Match negated multiply: sub(0, mul(a, b))
  MultiplyNeg
  // Match conditional select based on compare: select(cmp(a,b), x, y)
  ConditionalSelect(CmpKind)
  // Match bit field extract: and(shr(x, lsb), mask)
  BitFieldExtract(Int, Int) // lsb, width
  // Match compare and branch zero: brz(x, target)
  CompareAndBranchZero
  // Match test bit and branch: brz(and(x, 1 << n), target)
  TestBitAndBranch(Int)
}

// ============ AArch64 Lowering Rules ============

///|
/// Check if an immediate can be encoded in AArch64 add/sub instruction
/// AArch64 allows 12-bit immediates, optionally shifted left by 12
fn is_valid_add_imm(val : Int64) -> Bool {
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
/// Uses bitmask immediate encoding (complicated pattern)
fn is_valid_logical_imm(val : Int64) -> Bool {
  // Simplified check - in practice this is more complex
  // AArch64 uses a special encoding for bitmask immediates
  // For now, just allow simple cases
  if val == 0L || val == -1L {
    return false // Can't encode all-zeros or all-ones
  }
  // Check if it's a simple mask (consecutive 1s)
  is_consecutive_ones(val)
}

///|
/// Check if a value has consecutive 1s in binary representation
fn is_consecutive_ones(val : Int64) -> Bool {
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
  LogicalShifted(VCodeOpcode, Int, Int, Int) // op, src1_idx, src2_idx, shift
  // No AArch64-specific optimization applies
  NoMatch
}

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
          AArch64RewriteResult::LogicalShifted(And, 0, 1, shift)
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
          AArch64RewriteResult::LogicalShifted(Or, 0, 1, shift)
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
          AArch64RewriteResult::LogicalShifted(Xor, 0, 1, shift)
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
  val.reinterpret_as_uint64().shr(shift.to_int()).reinterpret_as_int64()
}
