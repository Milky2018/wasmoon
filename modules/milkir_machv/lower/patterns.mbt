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
  // Memory operations are not part of scalar expression patterns.
  // Misc
  Copy
  Select
}

///|
/// Convert IR Opcode to Pattern Opcode for matching
fn opcode_to_pattern(opcode : @milkir.Opcode) -> PatternOpcode? {
  match opcode {
    Scalar(IntBinary(Add)) => Some(Iadd)
    Scalar(IntBinary(Sub)) => Some(Isub)
    Scalar(IntBinary(Mul)) => Some(Imul)
    Scalar(IntBinary(SignedDiv)) => Some(Sdiv)
    Scalar(IntBinary(UnsignedDiv)) => Some(Udiv)
    Scalar(IntBinary(And)) => Some(Band)
    Scalar(IntBinary(Or)) => Some(Bor)
    Scalar(IntBinary(Xor)) => Some(Bxor)
    Scalar(IntBinary(ShiftLeft)) => Some(Ishl)
    Scalar(IntBinary(SignedShiftRight)) => Some(Sshr)
    Scalar(IntBinary(UnsignedShiftRight)) => Some(Ushr)
    Scalar(FloatBinary(Add)) => Some(Fadd)
    Scalar(FloatBinary(Sub)) => Some(Fsub)
    Scalar(FloatBinary(Mul)) => Some(Fmul)
    Scalar(FloatBinary(Div)) => Some(Fdiv)
    Scalar(IntConst(_)) => Some(Iconst)
    Scalar(FloatConst32(_)) | Scalar(FloatConst64(_)) => Some(Fconst)
    Scalar(IntCompare(_)) => Some(Icmp)
    Scalar(FloatCompare(_)) => Some(Fcmp)
    // Memory operations are handled by the memory lowering path.
    Scalar(Copy) => Some(Copy)
    Scalar(Select) => Some(Select)
    _ => None
  }
}

///|
fn float_const_value(opcode : @milkir.Opcode) -> Double? {
  match opcode {
    Scalar(FloatConst32(bits)) =>
      Some(Float::reinterpret_from_uint(bits).to_double())
    Scalar(FloatConst64(bits)) => Some(bits.reinterpret_as_double())
    _ => None
  }
}

///|
fn float_const_matches(opcode : @milkir.Opcode, expected : Double) -> Bool {
  match opcode {
    Scalar(FloatConst32(bits)) =>
      bits == Float::from_double(expected).reinterpret_as_uint()
    Scalar(FloatConst64(bits)) => bits == expected.reinterpret_as_uint64()
    _ => false
  }
}

// ============ Match Results ============

///|
/// Result of a pattern match - captured values and constants
struct MatchResult {
  // Captured IR values (in order of appearance in pattern)
  values : Array[@milkir.Value]
  // Captured constants
  int_consts : Array[Int64]
  float_consts : Array[Double]
}

///|
fn MatchResult::MatchResult() -> MatchResult {
  { values: [], int_consts: [], float_consts: [] }
}

///|
fn MatchResult::add_value(self : MatchResult, v : @milkir.Value) -> Unit {
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
  inst : @milkir.Inst,
  ctx : LoweringContext,
) -> MatchResult? {
  let result = MatchResult::MatchResult()
  if match_pattern_impl(pattern, inst, ctx, result) {
    Some(result)
  } else {
    None
  }
}

///|
fn match_pattern_impl(
  pattern : Pattern,
  inst : @milkir.Inst,
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
      if inst.opcode is Scalar(IntConst(val)) {
        val == expected
      } else {
        false
      }
    ConstFloat(expected) =>
      // Check if this is an fconst with the expected value
      float_const_matches(inst.opcode, expected)
    AnyConstInt =>
      // Match any integer constant
      if inst.opcode is Scalar(IntConst(val)) {
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
      if inst.opcode is Scalar(IntConst(v)) {
        result.add_int_const(v)
      } else if float_const_value(inst.opcode) is Some(v) {
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
                if def.opcode is Scalar(IntConst(val)) {
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
              Some(def) => {
                if !float_const_matches(def.opcode, expected) {
                  return false
                }
                if float_const_value(def.opcode) is Some(value) {
                  result.add_float_const(value)
                }
              }
              None => return false
            }
          }
          AnyConstInt => {
            // Match any integer constant
            let def_inst = find_defining_inst(ctx, operand)
            match def_inst {
              Some(def) =>
                if def.opcode is Scalar(IntConst(val)) {
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
pub fn find_defining_inst(
  ctx : LoweringContext,
  value : @milkir.Value,
) -> @milkir.Inst? {
  if value.id >= 0 && value.id < ctx.def_inst_table.length() {
    ctx.def_inst_table[value.id]
  } else {
    None
  }
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
/// A rewrite rule - matches a pattern and produces optimized MachV
struct RewriteRule {
  name : String
  pattern : Pattern
  // Priority - higher priority rules are tried first
  priority : Int
}

///|
fn RewriteRule::RewriteRule(
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
    RewriteRule("add_zero", Inst(Iadd, [Any, ConstInt(0L)]), 10),
    // add(0, x) -> x (identity, commutative)
    RewriteRule("zero_add", Inst(Iadd, [ConstInt(0L), Any]), 10),
    // sub(x, 0) -> x (identity)
    RewriteRule("sub_zero", Inst(Isub, [Any, ConstInt(0L)]), 10),
    // mul(x, 1) -> x (identity)
    RewriteRule("mul_one", Inst(Imul, [Any, ConstInt(1L)]), 10),
    // mul(1, x) -> x (identity, commutative)
    RewriteRule("one_mul", Inst(Imul, [ConstInt(1L), Any]), 10),
    // mul(x, 0) -> 0
    RewriteRule("mul_zero", Inst(Imul, [Any, ConstInt(0L)]), 10),
    // mul(0, x) -> 0 (commutative)
    RewriteRule("zero_mul", Inst(Imul, [ConstInt(0L), Any]), 10),
    // and(x, 0) -> 0
    RewriteRule("and_zero", Inst(Band, [Any, ConstInt(0L)]), 10),
    // and(0, x) -> 0 (commutative)
    RewriteRule("zero_and", Inst(Band, [ConstInt(0L), Any]), 10),
    // and(x, -1) -> x (all ones)
    RewriteRule("and_ones", Inst(Band, [Any, ConstInt(-1L)]), 10),
    // or(x, 0) -> x
    RewriteRule("or_zero", Inst(Bor, [Any, ConstInt(0L)]), 10),
    // or(0, x) -> x (commutative)
    RewriteRule("zero_or", Inst(Bor, [ConstInt(0L), Any]), 10),
    // xor(x, 0) -> x
    RewriteRule("xor_zero", Inst(Bxor, [Any, ConstInt(0L)]), 10),
    // xor(0, x) -> x (commutative)
    RewriteRule("zero_xor", Inst(Bxor, [ConstInt(0L), Any]), 10),
    // shl(x, 0) -> x
    RewriteRule("shl_zero", Inst(Ishl, [Any, ConstInt(0L)]), 10),
    // shr(x, 0) -> x
    RewriteRule("sshr_zero", Inst(Sshr, [Any, ConstInt(0L)]), 10),
    RewriteRule("ushr_zero", Inst(Ushr, [Any, ConstInt(0L)]), 10),
    // fadd(x, 0.0) -> x (float identity, be careful with -0.0)
    RewriteRule("fadd_zero", Inst(Fadd, [Any, ConstFloat(0.0)]), 5),
    // fmul(x, 1.0) -> x
    RewriteRule("fmul_one", Inst(Fmul, [Any, ConstFloat(1.0)]), 5),
    // fmul(1.0, x) -> x (commutative)
    RewriteRule("one_fmul", Inst(Fmul, [ConstFloat(1.0), Any]), 5),
    // Strength reduction: mul(x, power_of_2) -> shl(x, log2)
    // Use lower priority so specific constants (like 0, 1) match first
    RewriteRule("mul_pow2", Inst(Imul, [Any, AnyConstInt]), 3),
    RewriteRule("pow2_mul", Inst(Imul, [AnyConstInt, Any]), 3),
    // div(x, power_of_2) -> shr(x, log2) for unsigned
    RewriteRule("udiv_pow2", Inst(Udiv, [Any, AnyConstInt]), 3),
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
  inst : @milkir.Inst,
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
  inst : @milkir.Inst,
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
  inst : @milkir.Inst,
  block : @block.Block,
  rules : Array[RewriteRule],
) -> Bool {
  let rewrite_result = try_apply_rules(inst, ctx, rules)
  match rewrite_result {
    Identity(operand_idx) =>
      // Emit a move from the identity operand to the result
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let src = ctx.get_vreg(inst.operands[operand_idx])
        let machv_inst = @instr.Inst(Move)
        machv_inst.add_def({ reg: Virtual(dst) })
        machv_inst.add_use(Virtual(src))
        block.add_inst(machv_inst)
        true
      } else {
        false
      }
    Constant(val) =>
      // Emit a load constant
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let machv_inst = @instr.Inst(LoadConst(val))
        machv_inst.add_def({ reg: Virtual(dst) })
        block.add_inst(machv_inst)
        true
      } else {
        false
      }
    ShiftLeft(operand_idx, shift_amount) =>
      // Strength reduction: mul by power of 2 -> shift left
      if inst.first_result() is Some(result) {
        let dst = ctx.get_vreg(result)
        let src = ctx.get_vreg(inst.operands[operand_idx])
        let is_64 = result.ty is I64
        let mask = if is_64 { 63 } else { 31 }
        let shift = shift_amount & mask
        let shl_inst = @instr.Inst(ShlImm(shift, is_64))
        shl_inst.add_def({ reg: Virtual(dst) })
        shl_inst.add_use(Virtual(src))
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
        let is_64 = result.ty is I64
        let mask = if is_64 { 63 } else { 31 }
        let shift = shift_amount & mask
        let lshr_inst = @instr.Inst(LShrImm(shift, is_64))
        lshr_inst.add_def({ reg: Virtual(dst) })
        lshr_inst.add_use(Virtual(src))
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
pub fn lower_function_optimized(ir_func : @milkir.Function) -> @machv.Function {
  let ctx = LoweringContext::LoweringContext(
    ir_func,
    AArch64,
    None,
    Map([]),
    fn(_reason) { 0 },
    None,
    -1,
  )
  let rules = get_optimization_rules()

  // Phase 1: Create MachV blocks and set up block mapping
  for ir_block in ir_func.blocks {
    let machv_block = ctx.machv_func.new_block()
    ctx.block_map.set(ir_block.id, machv_block.id)
  }

  // Phase 2: Lower function parameters
  for param in ir_func.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.machv_func.add_param(class)
    ctx.set_cached_vreg(value.id, vreg)
  }

  // Phase 3: Lower result types
  for ty in ir_func.results {
    let class = ir_type_to_reg_class(ty)
    ctx.machv_func.add_result(class)
  }

  // Phase 4: Lower each block with pattern matching
  for i, ir_block in ir_func.blocks {
    lower_block_optimized(ctx, ir_block, ctx.machv_func.blocks[i], rules)
  }
  ctx.machv_func
}

///|
fn lower_block_optimized(
  ctx : LoweringContext,
  ir_block : @milkir.Block,
  machv_block : @block.Block,
  rules : Array[RewriteRule],
) -> Unit {
  // Lower block parameters
  for param in ir_block.params {
    let (value, ty) = param
    let class = ir_type_to_reg_class(ty)
    let vreg = ctx.machv_func.new_vreg(class)
    ctx.set_cached_vreg(value.id, vreg)
    machv_block.params.push(vreg)
  }

  // Lower instructions with pattern matching
  for inst in ir_block.instructions {
    // First try pattern-based optimization
    if !lower_inst_with_patterns(ctx, inst, machv_block, rules) {
      // Fall back to default lowering
      lower_inst_default(ctx, inst, machv_block)
    }
  }

  // Lower terminator
  if ir_block.terminator is Some(term) {
    lower_terminator(ctx, term, machv_block)
  }
}

///|
/// Default instruction lowering (same as before, but extracted for use with patterns)
fn lower_inst_default(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  match inst.opcode {
    Scalar(scalar_op) => lower_scalar_inst(ctx, inst, block, scalar_op)
    opcode => abort("unimplemented machv lowering for opcode \{opcode}")
  }
}
