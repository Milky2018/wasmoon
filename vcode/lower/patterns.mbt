// Pattern Matching for Instruction Selection
// Implements pattern-based lowering rules SSA-based IR DSL
//
// This module provides:
// 1. Pattern definitions for matching IR instruction trees
// 2. Rewrite rules for instruction combining and optimization
// 3. Target-agnostic peephole optimizations

// ============ Pattern Definitions ============

///|
/// A pattern that matches IR instruction trees
/// Patterns can match opcodes, operands, and constants
pub enum Pattern {
  // Match any value (captures into a variable)
  Any
  // Match a specific constant
  ConstInt(Int64)
  ConstFloat(Double)
  // Match any integer constant (captures the value)
  AnyConstInt
  // Match an instruction with specific opcode and operand patterns
  Inst(PatternOpcode, Array[Pattern])
}

///|
/// Pattern opcodes - simplified version of IR opcodes for matching
pub enum PatternOpcode {
  // Arithmetic
  Iadd
  Isub
  Imul
  Sdiv
  Udiv
  // Bitwise
  Band
  Bor
  Bxor
  Ishl
  Sshr
  Ushr
  // Float
  Fadd
  Fsub
  Fmul
  Fdiv
  // Constants
  Iconst
  Fconst
  // Comparisons
  Icmp
  Fcmp
  // Note: Load/Store removed - use LoadPtr/StorePtr now
  // Misc
  Copy
  Select
}

///|
/// Convert IR Opcode to Pattern Opcode for matching
fn opcode_to_pattern(opcode : @ir.Opcode) -> PatternOpcode? {
  match opcode {
    @ir.Opcode::Iadd => Some(Iadd)
    @ir.Opcode::Isub => Some(Isub)
    @ir.Opcode::Imul => Some(Imul)
    @ir.Opcode::Sdiv => Some(Sdiv)
    @ir.Opcode::Udiv => Some(Udiv)
    @ir.Opcode::Band => Some(Band)
    @ir.Opcode::Bor => Some(Bor)
    @ir.Opcode::Bxor => Some(Bxor)
    @ir.Opcode::Ishl => Some(Ishl)
    @ir.Opcode::Sshr => Some(Sshr)
    @ir.Opcode::Ushr => Some(Ushr)
    @ir.Opcode::Fadd => Some(Fadd)
    @ir.Opcode::Fsub => Some(Fsub)
    @ir.Opcode::Fmul => Some(Fmul)
    @ir.Opcode::Fdiv => Some(Fdiv)
    @ir.Opcode::Iconst(_) => Some(Iconst)
    @ir.Opcode::Fconst(_) => Some(Fconst)
    @ir.Opcode::Icmp(_) => Some(Icmp)
    @ir.Opcode::Fcmp(_) => Some(Fcmp)
    // Note: Load/Store with memidx removed - use LoadPtr/StorePtr now
    @ir.Opcode::Copy => Some(Copy)
    @ir.Opcode::Select => Some(Select)
    _ => None
  }
}

// ============ Match Results ============

///|
/// Result of a pattern match - captured values and constants
struct MatchResult {
  // Captured IR values (in order of appearance in pattern)
  values : Array[@ir.Value]
  // Captured constants
  int_consts : Array[Int64]
  float_consts : Array[Double]
}

///|
fn MatchResult::new() -> MatchResult {
  { values: [], int_consts: [], float_consts: [] }
}

///|
fn MatchResult::add_value(self : MatchResult, v : @ir.Value) -> Unit {
  self.values.push(v)
}

///|
fn MatchResult::add_int_const(self : MatchResult, c : Int64) -> Unit {
  self.int_consts.push(c)
}

///|
fn MatchResult::add_float_const(self : MatchResult, c : Double) -> Unit {
  self.float_consts.push(c)
}

// ============ Pattern Matching Engine ============

///|
/// Try to match a pattern against an IR instruction
pub fn match_pattern(
  pattern : Pattern,
  inst : @ir.Inst,
  ctx : LoweringContext,
) -> MatchResult? {
  let result = MatchResult::new()
  if match_pattern_impl(pattern, inst, ctx, result) {
    Some(result)
  } else {
    None
  }
}

///|
fn match_pattern_impl(
  pattern : Pattern,
  inst : @ir.Inst,
  ctx : LoweringContext,
  result : MatchResult,
) -> Bool {
  match pattern {
    Any => {
      // Any pattern always matches, capture the result value
      if inst.first_result() is Some(v) {
        result.add_value(v)
      }
      true
    }
    ConstInt(expected) =>
      // Check if this is an iconst with the expected value
      if inst.opcode is @ir.Opcode::Iconst(val) {
        val == expected
      } else {
        false
      }
    ConstFloat(expected) =>
      // Check if this is an fconst with the expected value
      if inst.opcode is @ir.Opcode::Fconst(val) {
        // For F32, bits are packed in the lower 32 bits of the Double
        // For F64, the Double is the actual value
        if inst.first_result() is Some(r) && r.ty is @ir.Type::F32 {
          let stored_bits = val.reinterpret_as_int64().to_int()
          let expected_bits = Float::from_double(expected).reinterpret_as_int()
          stored_bits == expected_bits
        } else {
          val == expected
        }
      } else {
        false
      }
    AnyConstInt =>
      // Match any integer constant
      if inst.opcode is @ir.Opcode::Iconst(val) {
        result.add_int_const(val)
        true
      } else {
        false
      }
    Inst(pat_op, sub_patterns) => {
      // Check if opcode matches
      let inst_pat_op = opcode_to_pattern(inst.opcode)
      match inst_pat_op {
        Some(op) => if !pattern_opcode_eq(op, pat_op) { return false }
        None => return false
      }
      // For iconst/fconst, capture the constant
      if inst.opcode is @ir.Opcode::Iconst(v) {
        result.add_int_const(v)
      } else if inst.opcode is @ir.Opcode::Fconst(v) {
        result.add_float_const(v)
      }
      // Match sub-patterns against operands
      if sub_patterns.length() != inst.operands.length() {
        return false
      }
      for i, sub_pat in sub_patterns {
        // For sub-patterns, we need to look up the defining instruction
        let operand = inst.operands[i]
        match sub_pat {
          Any => result.add_value(operand)
          ConstInt(expected) => {
            // Try to find the defining instruction
            let def_inst = find_defining_inst(ctx, operand)
            match def_inst {
              Some(def) =>
                if def.opcode is @ir.Opcode::Iconst(val) {
                  if val != expected {
                    return false
                  }
                  result.add_int_const(val)
                } else {
                  return false
                }
              None => return false
            }
          }
          ConstFloat(expected) => {
            let def_inst = find_defining_inst(ctx, operand)
            match def_inst {
              Some(def) =>
                if def.opcode is @ir.Opcode::Fconst(val) {
                  // For F32, bits are packed in the lower 32 bits of the Double
                  let matches = if def.first_result() is Some(r) &&
                    r.ty is @ir.Type::F32 {
                    let stored_bits = val.reinterpret_as_int64().to_int()
                    let expected_bits = Float::from_double(expected).reinterpret_as_int()
                    stored_bits == expected_bits
                  } else {
                    val == expected
                  }
                  if !matches {
                    return false
                  }
                  result.add_float_const(val)
                } else {
                  return false
                }
              None => return false
            }
          }
          AnyConstInt => {
            // Match any integer constant
            let def_inst = find_defining_inst(ctx, operand)
            match def_inst {
              Some(def) =>
                if def.opcode is @ir.Opcode::Iconst(val) {
                  result.add_int_const(val)
                } else {
                  return false
                }
              None => return false
            }
          }
          Inst(_, _) => {
            // Recursively match instruction tree
            let def_inst = find_defining_inst(ctx, operand)
            match def_inst {
              Some(def) =>
                if !match_pattern_impl(sub_pat, def, ctx, result) {
                  return false
                }
              None => return false
            }
          }
        }
      }
      // Capture the result value
      if inst.first_result() is Some(v) {
        result.add_value(v)
      }
      true
    }
  }
}

///|
fn pattern_opcode_eq(a : PatternOpcode, b : PatternOpcode) -> Bool {
  match (a, b) {
    (Iadd, Iadd) => true
    (Isub, Isub) => true
    (Imul, Imul) => true
    (Sdiv, Sdiv) => true
    (Udiv, Udiv) => true
    (Band, Band) => true
    (Bor, Bor) => true
    (Bxor, Bxor) => true
    (Ishl, Ishl) => true
    (Sshr, Sshr) => true
    (Ushr, Ushr) => true
    (Fadd, Fadd) => true
    (Fsub, Fsub) => true
    (Fmul, Fmul) => true
    (Fdiv, Fdiv) => true
    (Iconst, Iconst) => true
    (Fconst, Fconst) => true
    (Icmp, Icmp) => true
    (Fcmp, Fcmp) => true
    (Copy, Copy) => true
    (Select, Select) => true
    _ => false
  }
}

///|
/// Find the instruction that defines a given value
fn find_defining_inst(ctx : LoweringContext, value : @ir.Value) -> @ir.Inst? {
  // Search through all blocks and instructions to find the definition
  for block in ctx.ir_func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(result) && result.id == value.id {
        return Some(inst)
      }
    }
  }
  None
}

// ============ Rewrite Rules ============

///|
/// Check if a value is a power of 2 and return the exponent
fn is_power_of_2(val : Int64) -> Int? {
  if val <= 0L {
    return None
  }
  // Check if val is a power of 2: (val & (val - 1)) == 0
  if (val & (val - 1L)) != 0L {
    return None
  }
  // Count trailing zeros to get the exponent
  let mut n = val.reinterpret_as_uint64()
  let mut count = 0
  while (n & 1UL) == 0UL {
    n = n >> 1
    count = count + 1
  }
  Some(count)
}

///|
/// A rewrite rule - matches a pattern and produces optimized VCode
struct RewriteRule {
  name : String
  pattern : Pattern
  // Priority - higher priority rules are tried first
  priority : Int
}

///|
fn RewriteRule::new(
  name : String,
  pattern : Pattern,
  priority : Int,
) -> RewriteRule {
  { name, pattern, priority }
}

///|
/// Built-in optimization rules
pub fn get_optimization_rules() -> Array[RewriteRule] {
  [
    // add(x, 0) -> x (identity)
    RewriteRule::new("add_zero", Inst(Iadd, [Any, ConstInt(0L)]), 10),
    // add(0, x) -> x (identity, commutative)
    RewriteRule::new("zero_add", Inst(Iadd, [ConstInt(0L), Any]), 10),
    // sub(x, 0) -> x (identity)
    RewriteRule::new("sub_zero", Inst(Isub, [Any, ConstInt(0L)]), 10),
    // mul(x, 1) -> x (identity)
    RewriteRule::new("mul_one", Inst(Imul, [Any, ConstInt(1L)]), 10),
    // mul(1, x) -> x (identity, commutative)
    RewriteRule::new("one_mul", Inst(Imul, [ConstInt(1L), Any]), 10),
    // mul(x, 0) -> 0
    RewriteRule::new("mul_zero", Inst(Imul, [Any, ConstInt(0L)]), 10),
    // mul(0, x) -> 0 (commutative)
    RewriteRule::new("zero_mul", Inst(Imul, [ConstInt(0L), Any]), 10),
    // and(x, 0) -> 0
    RewriteRule::new("and_zero", Inst(Band, [Any, ConstInt(0L)]), 10),
    // and(0, x) -> 0 (commutative)
    RewriteRule::new("zero_and", Inst(Band, [ConstInt(0L), Any]), 10),
    // and(x, -1) -> x (all ones)
    RewriteRule::new("and_ones", Inst(Band, [Any, ConstInt(-1L)]), 10),
    // or(x, 0) -> x
    RewriteRule::new("or_zero", Inst(Bor, [Any, ConstInt(0L)]), 10),
    // or(0, x) -> x (commutative)
    RewriteRule::new("zero_or", Inst(Bor, [ConstInt(0L), Any]), 10),
    // xor(x, 0) -> x
    RewriteRule::new("xor_zero", Inst(Bxor, [Any, ConstInt(0L)]), 10),
    // xor(0, x) -> x (commutative)
    RewriteRule::new("zero_xor", Inst(Bxor, [ConstInt(0L), Any]), 10),
    // shl(x, 0) -> x
    RewriteRule::new("shl_zero", Inst(Ishl, [Any, ConstInt(0L)]), 10),
    // shr(x, 0) -> x
    RewriteRule::new("sshr_zero", Inst(Sshr, [Any, ConstInt(0L)]), 10),
    RewriteRule::new("ushr_zero", Inst(Ushr, [Any, ConstInt(0L)]), 10),
    // fadd(x, 0.0) -> x (float identity, be careful with -0.0)
    RewriteRule::new("fadd_zero", Inst(Fadd, [Any, ConstFloat(0.0)]), 5),
    // fmul(x, 1.0) -> x
    RewriteRule::new("fmul_one", Inst(Fmul, [Any, ConstFloat(1.0)]), 5),
    // fmul(1.0, x) -> x (commutative)
    RewriteRule::new("one_fmul", Inst(Fmul, [ConstFloat(1.0), Any]), 5),
    // Strength reduction: mul(x, power_of_2) -> shl(x, log2)
    // Use lower priority so specific constants (like 0, 1) match first
    RewriteRule::new("mul_pow2", Inst(Imul, [Any, AnyConstInt]), 3),
    RewriteRule::new("pow2_mul", Inst(Imul, [AnyConstInt, Any]), 3),
    // div(x, power_of_2) -> shr(x, log2) for unsigned
    RewriteRule::new("udiv_pow2", Inst(Udiv, [Any, AnyConstInt]), 3),
  ]
}

// ============ Rule Application ============

///|
/// Result of applying a rewrite rule
pub enum RewriteResult {
  // Use the identity value (just copy from operand)
  Identity(Int) // Index of the operand to use as identity
  // Produce a constant
  Constant(Int64)
  // Strength reduction: mul by power of 2 -> shift left
  ShiftLeft(Int, Int) // operand index, shift amount
  // Strength reduction: div by power of 2 -> logical shift right
  ShiftRight(Int, Int) // operand index, shift amount
  // No rewrite applies, use default lowering
  NoMatch
}

///|
/// Try to apply optimization rules to an instruction
pub fn try_apply_rules(
  inst : @ir.Inst,
  ctx : LoweringContext,
  rules : Array[RewriteRule],
) -> RewriteResult {
  // Sort rules by priority (higher first)
  let sorted_rules = rules.copy()
  sorted_rules.sort_by(fn(a, b) { b.priority - a.priority })
  for rule in sorted_rules {
    let match_result = match_pattern(rule.pattern, inst, ctx)
    if match_result is Some(result) {
      // Apply the rule based on its name
      return apply_rule(rule.name, result, inst, ctx)
    }
  }
  NoMatch
}

///|
/// Apply a specific rule given a match result
fn apply_rule(
  rule_name : String,
  result : MatchResult,
  inst : @ir.Inst,
  ctx : LoweringContext,
) -> RewriteResult {
  ignore(ctx)
  match rule_name {
    // Identity rules - return the first operand
    "add_zero"
    | "sub_zero"
    | "mul_one"
    | "and_ones"
    | "or_zero"
    | "xor_zero"
    | "shl_zero"
    | "sshr_zero"
    | "ushr_zero"
    | "fadd_zero"
    | "fmul_one" => Identity(0)
    // Commutative identity rules - return the second operand
    "zero_add" | "one_mul" | "zero_or" | "zero_xor" | "one_fmul" => Identity(1)
    // Zero rules - return constant 0
    "mul_zero" | "zero_mul" | "and_zero" | "zero_and" => Constant(0L)
    // Strength reduction: mul by power of 2 -> shift left
    "mul_pow2" =>
      // The constant is captured in result.int_consts[0]
      if result.int_consts.length() > 0 {
        let const_val = result.int_consts[0]
        match is_power_of_2(const_val) {
          Some(shift) => ShiftLeft(0, shift) // First operand, shift amount
          None => NoMatch // Not a power of 2, use default lowering
        }
      } else {
        NoMatch
      }
    "pow2_mul" =>
      // Commutative: constant is first operand
      if result.int_consts.length() > 0 {
        let const_val = result.int_consts[0]
        match is_power_of_2(const_val) {
          Some(shift) => ShiftLeft(1, shift) // Second operand, shift amount
          None => NoMatch
        }
      } else {
        NoMatch
      }
    // Strength reduction: unsigned div by power of 2 -> logical shift right
    "udiv_pow2" =>
      if result.int_consts.length() > 0 {
        let const_val = result.int_consts[0]
        match is_power_of_2(const_val) {
          Some(shift) => ShiftRight(0, shift)
          None => NoMatch
        }
      } else {
        NoMatch
      }
    // Default - no special handling
    _ => {
      ignore(result)
      ignore(inst)
      NoMatch
    }
  }
}

// ============ Integration with Lowering ============

///|
/// Lower an instruction with pattern matching optimization
pub fn lower_inst_with_patterns(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  rules : Array[RewriteRule],
) -> Bool {
  let rewrite_result = try_apply_rules(inst, ctx, rules)
  match rewrite_result {
    Identity(operand_idx) =>
      // Emit a move from the identity operand to the result
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let src = ctx.get_vreg(inst.operands[operand_idx])
        let vcode_inst = @instr.VCodeInst::new(@instr.Move)
        vcode_inst.add_def({ reg: @abi.Virtual(dst) })
        vcode_inst.add_use(@abi.Virtual(src))
        block.add_inst(vcode_inst)
        true
      } else {
        false
      }
    Constant(val) =>
      // Emit a load constant
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let vcode_inst = @instr.VCodeInst::new(@instr.LoadConst(val))
        vcode_inst.add_def({ reg: @abi.Virtual(dst) })
        block.add_inst(vcode_inst)
        true
      } else {
        false
      }
    ShiftLeft(operand_idx, shift_amount) =>
      // Strength reduction: mul by power of 2 -> shift left
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let src = ctx.get_vreg(inst.operands[operand_idx])
        // Load shift amount as constant
        let shift_vreg = ctx.vcode_func.new_vreg(Int)
        let load_shift = @instr.VCodeInst::new(
          @instr.LoadConst(shift_amount.to_int64()),
        )
        load_shift.add_def({ reg: @abi.Virtual(shift_vreg) })
        block.add_inst(load_shift)
        // Emit shift left
        let is_64 = result.ty is @ir.Type::I64
        let shl_inst = @instr.VCodeInst::new(@instr.Shl(is_64))
        shl_inst.add_def({ reg: @abi.Virtual(dst) })
        shl_inst.add_use(@abi.Virtual(src))
        shl_inst.add_use(@abi.Virtual(shift_vreg))
        block.add_inst(shl_inst)
        true
      } else {
        false
      }
    ShiftRight(operand_idx, shift_amount) =>
      // Strength reduction: unsigned div by power of 2 -> logical shift right
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let src = ctx.get_vreg(inst.operands[operand_idx])
        // Load shift amount as constant
        let shift_vreg = ctx.vcode_func.new_vreg(Int)
        let load_shift = @instr.VCodeInst::new(
          @instr.LoadConst(shift_amount.to_int64()),
        )
        load_shift.add_def({ reg: @abi.Virtual(shift_vreg) })
        block.add_inst(load_shift)
        // Emit logical shift right
        let is_64 = result.ty is @ir.Type::I64
        let lshr_inst = @instr.VCodeInst::new(@instr.LShr(is_64))
        lshr_inst.add_def({ reg: @abi.Virtual(dst) })
        lshr_inst.add_use(@abi.Virtual(src))
        lshr_inst.add_use(@abi.Virtual(shift_vreg))
        block.add_inst(lshr_inst)
        true
      } else {
        false
      }
    NoMatch => false
  }
}

///|
/// Lower a function with pattern matching optimizations enabled
pub fn lower_function_optimized(
  ir_func : @ir.Function,
) -> @regalloc.VCodeFunction {
  let ctx = LoweringContext::new(ir_func, @abi.ABISettings::default(), -1)
  let rules = get_optimization_rules()

  // Phase 1: Create VCode blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let vcode_block = ctx.vcode_func.new_block()
    ctx.block_map.set(ir_block.id, vcode_block.id)
  }

  // Phase 2: Lower function parameters
  for param in ir_func.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.vcode_func.add_param(class)
    ctx.value_map.set(value.id, vreg)
  }

  // Phase 3: Lower result types
  for ty in ir_func.results {
    let class = ir_type_to_reg_class(ty)
    ctx.vcode_func.add_result(class)
  }

  // Phase 4: Lower each block with pattern matching
  for i, ir_block in ir_func.blocks {
    lower_block_optimized(ctx, ir_block, ctx.vcode_func.blocks[i], rules)
  }
  ctx.vcode_func
}

///|
fn lower_block_optimized(
  ctx : LoweringContext,
  ir_block : @ir.Block,
  vcode_block : @block.VCodeBlock,
  rules : Array[RewriteRule],
) -> Unit {
  // Lower block parameters
  for param in ir_block.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.vcode_func.new_vreg(class)
    ctx.value_map.set(value.id, vreg)
    vcode_block.params.push(vreg)
  }

  // Lower instructions with pattern matching
  for inst in ir_block.instructions {
    // First try pattern-based optimization
    if !lower_inst_with_patterns(ctx, inst, vcode_block, rules) {
      // Fall back to default lowering
      lower_inst_default(ctx, inst, vcode_block)
    }
  }

  // Lower terminator
  if ir_block.terminator is Some(term) {
    lower_terminator(ctx, term, vcode_block)
  }
}

///|
/// Default instruction lowering (same as before, but extracted for use with patterns)
fn lower_inst_default(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  match inst.opcode {
    // Constants
    @ir.Opcode::Iconst(val) => lower_iconst(ctx, inst, block, val)
    @ir.Opcode::Fconst(val) => lower_fconst(ctx, inst, block, val)

    // Integer arithmetic
    @ir.Opcode::Iadd => lower_iadd(ctx, inst, block)
    @ir.Opcode::Isub => lower_isub(ctx, inst, block)
    @ir.Opcode::Imul => lower_imul(ctx, inst, block)
    @ir.Opcode::Sdiv => lower_div(ctx, inst, block, signed=true)
    @ir.Opcode::Udiv => lower_div(ctx, inst, block, signed=false)

    // Bitwise operations
    @ir.Opcode::Band => lower_binary_int(ctx, inst, block, @instr.And)
    @ir.Opcode::Bor => lower_binary_int(ctx, inst, block, @instr.Or)
    @ir.Opcode::Bxor => lower_binary_int(ctx, inst, block, @instr.Xor)
    @ir.Opcode::Ishl =>
      lower_shift(ctx, inst, block, fn(is_64) { @instr.Shl(is_64) })
    @ir.Opcode::Sshr =>
      lower_shift(ctx, inst, block, fn(is_64) { @instr.AShr(is_64) })
    @ir.Opcode::Ushr =>
      lower_shift(ctx, inst, block, fn(is_64) { @instr.LShr(is_64) })

    // Integer comparisons
    @ir.Opcode::Icmp(cc) => lower_icmp(ctx, inst, block, cc)

    // Floating point arithmetic
    @ir.Opcode::Fadd => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fsub => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fmul => lower_binary_float(ctx, inst, block)
    @ir.Opcode::Fdiv => lower_binary_float(ctx, inst, block)

    // Floating point comparisons
    @ir.Opcode::Fcmp(cc) => lower_fcmp(ctx, inst, block, cc)

    // Note: Load/Store with memidx removed - use LoadPtr/StorePtr via FuncEnvironment

    // Conversions
    @ir.Opcode::Sextend => lower_extend(ctx, inst, block, signed=true)
    @ir.Opcode::Uextend => lower_extend(ctx, inst, block, signed=false)
    @ir.Opcode::Ireduce => lower_truncate(ctx, inst, block)
    @ir.Opcode::FcvtToSint => lower_float_to_int(ctx, inst, block, signed=true)
    @ir.Opcode::FcvtToUint => lower_float_to_int(ctx, inst, block, signed=false)
    @ir.Opcode::SintToFcvt => lower_int_to_float(ctx, inst, block, signed=true)
    @ir.Opcode::UintToFcvt => lower_int_to_float(ctx, inst, block, signed=false)

    // Misc
    @ir.Opcode::Copy => lower_copy(ctx, inst, block)
    @ir.Opcode::Select => lower_select(ctx, inst, block)
    opcode => abort("unimplemented vcode lowering for opcode \{opcode}")
  }
}
