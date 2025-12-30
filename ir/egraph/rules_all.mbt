// Standard rules collection (indexed for efficient application)

///|
/// Get all standard rewrite rules indexed by their matching opcodes
pub fn standard_rules_indexed() -> IndexedRuleSet {
  let rs = IndexedRuleSet::new()
  // Identity rules - indexed by opcode
  rs.add_rule(rule_add_zero(), [TAdd])
  rs.add_rule(rule_sub_zero(), [TSub])
  rs.add_rule(rule_mul_one(), [TMul])
  rs.add_rule(rule_mul_zero(), [TMul])
  rs.add_rule(rule_idempotent(), [TAnd, TOr])
  rs.add_rule(rule_xor_self(), [TXor])
  rs.add_rule(rule_sub_self(), [TSub])
  // Bitwise identity
  rs.add_rule(rule_and_zero(), [TAnd])
  rs.add_rule(rule_or_zero(), [TOr])
  rs.add_rule(rule_xor_zero(), [TXor])
  rs.add_rule(rule_and_all_ones(), [TAnd])
  rs.add_rule(rule_or_all_ones(), [TOr])
  rs.add_rule(rule_or_self(), [TOr])
  rs.add_rule(rule_xor_all_ones(), [TXor])
  // Bitwise with not
  rs.add_rule(rule_xor_not(), [TXor])
  rs.add_rule(rule_or_not(), [TOr])
  rs.add_rule(rule_and_not(), [TAnd])
  rs.add_rule(rule_double_bnot(), [TBnot])
  rs.add_rule(rule_demorgan_or(), [TBnot])
  rs.add_rule(rule_demorgan_and(), [TBnot])
  // Bitwise algebraic
  rs.add_rule(rule_and_xor_xor(), [TXor])
  rs.add_rule(rule_or_xor_and(), [TXor])
  rs.add_rule(rule_and_or_absorb(), [TOr])
  rs.add_rule(rule_xor_xor_cancel(), [TXor])
  rs.add_rule(rule_factor_and_xor(), [TXor])
  rs.add_rule(rule_and_add_xor(), [TAdd])
  rs.add_rule(rule_or_add_and(), [TAdd])
  rs.add_rule(rule_or_and_not(), [TOr])
  rs.add_rule(rule_or_or_absorb(), [TOr])
  rs.add_rule(rule_and_and_absorb(), [TAnd])
  rs.add_rule(rule_xor_not_and(), [TAnd])
  rs.add_rule(rule_and_or_not(), [TOr])
  // Shift identity
  rs.add_rule(rule_shl_zero(), [TShl])
  rs.add_rule(rule_shr_zero(), [TSshr, TUshr])
  rs.add_rule(rule_shift_of_zero(), [TShl, TSshr, TUshr])
  rs.add_rule(rule_shl_shl(), [TShl])
  // Strength reduction
  rs.add_rule(rule_mul_pow2(), [TMul])
  rs.add_rule(rule_double(), [TAdd])
  rs.add_rule(rule_udiv_pow2(), [TUdiv])
  rs.add_rule(rule_urem_pow2(), [TUrem])
  rs.add_rule(rule_mul_3(), [TMul])
  rs.add_rule(rule_mul_5(), [TMul])
  rs.add_rule(rule_mul_7(), [TMul])
  rs.add_rule(rule_mul_9(), [TMul])
  // Negation patterns
  rs.add_rule(rule_neg_zero(), [TNeg, TSub])
  rs.add_rule(rule_sub_neg(), [TSub])
  rs.add_rule(rule_add_neg(), [TAdd])
  rs.add_rule(rule_mul_neg_one(), [TMul])
  rs.add_rule(rule_neg_mul_neg(), [TMul])
  rs.add_rule(rule_sdiv_neg_one(), [TSdiv])
  rs.add_rule(rule_srem_neg_one(), [TSrem])
  // Division/Remainder by 1
  rs.add_rule(rule_div_one(), [TSdiv, TUdiv])
  rs.add_rule(rule_rem_one(), [TSrem, TUrem])
  // Bnot patterns
  rs.add_rule(rule_bnot_add_one(), [TAdd])
  rs.add_rule(rule_bnot_sub_one(), [TSub])
  rs.add_rule(rule_bnot_add_neg_one(), [TAdd])
  // Additional patterns
  rs.add_rule(rule_or_add_neg(), [TAdd])
  rs.add_rule(rule_add_sub_or_to_and(), [TAdd])
  // Cancellation patterns
  rs.add_rule(rule_sub_add_cancel(), [TAdd])
  rs.add_rule(rule_add_sub_cancel(), [TSub])
  rs.add_rule(rule_sub_sub_cancel(), [TSub])
  // Additional strength reduction
  rs.add_rule(rule_mul_shl_one(), [TMul])
  // Constant folding - universal (operates on any opcode with const children)
  rs.add_rule(rule_const_fold(), [])
  // Reassociation
  rs.add_rule(rule_reassoc_add_const(), [TAdd])
  rs.add_rule(rule_reassoc_mul_const(), [TMul])
  rs.add_rule(rule_reassoc_sub_const(), [TSub])
  rs.add_rule(rule_reassoc_or_const(), [TOr])
  rs.add_rule(rule_reassoc_and_const(), [TAnd])
  rs.add_rule(rule_reassoc_xor_const(), [TXor])
  rs.add_rule(rule_reassoc_sub_add_const(), [TSub])
  rs.add_rule(rule_reassoc_add_sub_const(), [TAdd])
  rs.add_rule(rule_reassoc_sub_sub_const_left(), [TSub])
  rs.add_rule(rule_reassoc_add_sub_const_left(), [TAdd])
  // Shift reassociation for constant propagation
  rs.add_rule(rule_reassoc_shl_const(), [TShl])
  rs.add_rule(rule_reassoc_ushr_const(), [TUshr])
  rs.add_rule(rule_reassoc_sshr_const(), [TSshr])
  // Select simplification
  rs.add_rule(rule_select_const(), [TSelect])
  // Sub negative constant
  rs.add_rule(rule_sub_neg_const(), [TSub])
  // Tree rebalancing for constants
  rs.add_rule(rule_rebalance_add_consts(), [TAdd])
  rs.add_rule(rule_rebalance_mul_consts(), [TMul])
  rs.add_rule(rule_rebalance_and_consts(), [TAnd])
  rs.add_rule(rule_rebalance_or_consts(), [TOr])
  rs.add_rule(rule_rebalance_xor_consts(), [TXor])
  // Float constant folding
  rs.add_rule(rule_fconst_fold_binary(), [
    TFadd,
    TFsub,
    TFmul,
    TFdiv,
    TFmin,
    TFmax,
    TFcopysign,
  ])
  rs.add_rule(rule_fconst_fold_unary(), [
    TFneg,
    TFabs,
    TFsqrt,
    TFceil,
    TFfloor,
    TFtrunc,
    TFnearest,
  ])
  rs.add_rule(rule_fneg_fneg(), [TFneg])
  rs.add_rule(rule_fabs_fneg(), [TFabs])
  rs.add_rule(rule_fabs_fabs(), [TFabs])
  rs.add_rule(rule_fneg_fabs(), [TFneg])
  // Vector constant folding
  rs.add_rule(rule_splat_const(), [TSplat])
  // Extend/reduce optimizations
  rs.add_rule(rule_uextend_uextend(), [TUextend])
  rs.add_rule(rule_sextend_sextend(), [TSextend])
  rs.add_rule(rule_sextend_uextend(), [TSextend])
  rs.add_rule(rule_sextend_icmp(), [TSextend])
  rs.add_rule(rule_ireduce_uextend(), [TIreduce])
  rs.add_rule(rule_ireduce_sextend(), [TIreduce])
  rs.add_rule(rule_band_uextend(), [TAnd])
  rs.add_rule(rule_bor_uextend(), [TOr])
  rs.add_rule(rule_bxor_uextend(), [TXor])
  rs.add_rule(rule_ireduce_ineg(), [TIreduce])
  rs.add_rule(rule_ireduce_bnot(), [TIreduce])
  rs.add_rule(rule_ireduce_iadd(), [TIreduce])
  rs.add_rule(rule_ireduce_isub(), [TIreduce])
  rs.add_rule(rule_ireduce_imul(), [TIreduce])
  rs.add_rule(rule_ireduce_band(), [TIreduce])
  rs.add_rule(rule_ireduce_bor(), [TIreduce])
  rs.add_rule(rule_ireduce_bxor(), [TIreduce])
  rs.add_rule(rule_ireduce_ireduce(), [TIreduce])
  rs.add_rule(rule_ireduce_ishl(), [TIreduce])
  // Extend with comparison
  rs.add_rule(rule_eq_sextend_zero(), [TEq])
  rs.add_rule(rule_ne_sextend_zero(), [TNe])
  rs.add_rule(rule_icmp_sextend_zero(), [TIcmp])
  // Arithmetic with extends
  rs.add_rule(rule_iadd_uextend(), [TAdd])
  rs.add_rule(rule_isub_uextend(), [TSub])
  // Tree rebalancing
  rs.add_rule(rule_rebalance_add_right(), [TAdd])
  rs.add_rule(rule_rebalance_add_left(), [TAdd])
  rs.add_rule(rule_rebalance_mul_right(), [TMul])
  rs.add_rule(rule_rebalance_mul_left(), [TMul])
  rs.add_rule(rule_rebalance_and_right(), [TAnd])
  rs.add_rule(rule_rebalance_and_left(), [TAnd])
  rs.add_rule(rule_rebalance_xor_right(), [TXor])
  rs.add_rule(rule_rebalance_xor_left(), [TXor])
  // Add/Sub mixed rebalancing
  rs.add_rule(rule_rebalance_sub_sub_sub(), [TSub])
  rs.add_rule(rule_rebalance_sub_sub_add(), [TAdd])
  rs.add_rule(rule_rebalance_sub_add_sub(), [TSub])
  rs.add_rule(rule_rebalance_sub_add_add(), [TAdd])
  rs.add_rule(rule_rebalance_add_sub_sub(), [TSub])
  rs.add_rule(rule_rebalance_add_sub_add(), [TAdd])
  rs.add_rule(rule_rebalance_add_add_sub(), [TSub])
  rs.add_rule(rule_rebalance_left_sub_sub_sub(), [TSub])
  rs.add_rule(rule_rebalance_left_sub_sub_add(), [TAdd])
  rs.add_rule(rule_rebalance_left_sub_add_sub(), [TSub])
  rs.add_rule(rule_rebalance_left_sub_add_add(), [TAdd])
  rs.add_rule(rule_rebalance_left_add_sub_sub(), [TSub])
  rs.add_rule(rule_rebalance_left_add_sub_add(), [TAdd])
  rs.add_rule(rule_rebalance_left_add_add_sub(), [TSub])
  // Commutativity
  rs.add_rule(rule_add_comm(), [TAdd])
  rs.add_rule(rule_mul_comm(), [TMul])
  rs.add_rule(rule_and_comm(), [TAnd])
  rs.add_rule(rule_or_comm(), [TOr])
  rs.add_rule(rule_xor_comm(), [TXor])
  rs
}
