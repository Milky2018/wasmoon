// Standard rules collection

///|
pub fn standard_rules() -> Array[RewriteRule] {
  [
    // Identity rules
    rule_add_zero(),
    rule_sub_zero(),
    rule_mul_one(),
    rule_mul_zero(),
    rule_idempotent(),
    rule_xor_self(),
    rule_sub_self(),
    // Bitwise identity
    rule_and_zero(),
    rule_or_zero(),
    rule_xor_zero(),
    rule_and_all_ones(),
    rule_or_all_ones(),
    rule_or_self(),
    rule_xor_all_ones(),
    // Bitwise with not
    rule_xor_not(),
    rule_or_not(),
    rule_and_not(),
    rule_double_bnot(),
    rule_demorgan_or(),
    rule_demorgan_and(),
    // Bitwise algebraic
    rule_and_xor_xor(),
    rule_or_xor_and(),
    rule_and_or_absorb(),
    rule_xor_xor_cancel(),
    rule_factor_and_xor(),
    rule_and_add_xor(),
    rule_or_add_and(),
    rule_or_and_not(),
    rule_or_or_absorb(),
    rule_and_and_absorb(),
    rule_xor_not_and(),
    rule_and_or_not(),
    // Shift identity
    rule_shl_zero(),
    rule_shr_zero(),
    rule_shift_of_zero(),
    rule_shl_shl(),
    // Strength reduction
    rule_mul_pow2(),
    rule_double(),
    rule_udiv_pow2(),
    rule_urem_pow2(),
    rule_mul_3(),
    rule_mul_5(),
    rule_mul_7(),
    rule_mul_9(),
    // Negation patterns
    rule_neg_zero(),
    rule_sub_neg(),
    rule_add_neg(),
    rule_mul_neg_one(),
    rule_neg_mul_neg(),
    rule_sdiv_neg_one(),
    rule_srem_neg_one(),
    // Division/Remainder by 1
    rule_div_one(),
    rule_rem_one(),
    // Bnot patterns
    rule_bnot_add_one(),
    rule_bnot_sub_one(),
    rule_bnot_add_neg_one(),
    // Additional patterns
    rule_or_add_neg(),
    rule_add_sub_or_to_and(),
    // Cancellation patterns
    rule_sub_add_cancel(),
    rule_add_sub_cancel(),
    rule_sub_sub_cancel(),
    // Additional strength reduction
    rule_mul_shl_one(),
    // Constant folding and reassociation
    rule_const_fold(),
    rule_reassoc_add_const(),
    rule_reassoc_mul_const(),
    rule_reassoc_sub_const(),
    rule_reassoc_or_const(),
    rule_reassoc_and_const(),
    rule_reassoc_xor_const(),
    rule_reassoc_sub_add_const(),
    rule_reassoc_add_sub_const(),
    rule_reassoc_sub_sub_const_left(),
    rule_reassoc_add_sub_const_left(),
    // Shift reassociation for constant propagation
    rule_reassoc_shl_const(),
    rule_reassoc_ushr_const(),
    rule_reassoc_sshr_const(),
    // Select simplification
    rule_select_const(),
    // Sub negative constant
    rule_sub_neg_const(),
    // Tree rebalancing for constants
    rule_rebalance_add_consts(),
    rule_rebalance_mul_consts(),
    rule_rebalance_and_consts(),
    rule_rebalance_or_consts(),
    rule_rebalance_xor_consts(),
    // Float constant folding
    rule_fconst_fold_binary(),
    rule_fconst_fold_unary(),
    rule_fneg_fneg(),
    rule_fabs_fneg(),
    rule_fabs_fabs(),
    rule_fneg_fabs(),
    // Vector constant folding
    rule_splat_const(),
    // Tree rebalancing (uses subsume to avoid infinite loops with commutativity)
    rule_rebalance_add_right(),
    rule_rebalance_add_left(),
    rule_rebalance_mul_right(),
    rule_rebalance_mul_left(),
    rule_rebalance_and_right(),
    rule_rebalance_and_left(),
    rule_rebalance_xor_right(),
    rule_rebalance_xor_left(),
    // Add/Sub mixed rebalancing
    rule_rebalance_sub_sub_sub(),
    rule_rebalance_sub_sub_add(),
    rule_rebalance_sub_add_sub(),
    rule_rebalance_sub_add_add(),
    rule_rebalance_add_sub_sub(),
    rule_rebalance_add_sub_add(),
    rule_rebalance_add_add_sub(),
    rule_rebalance_left_sub_sub_sub(),
    rule_rebalance_left_sub_sub_add(),
    rule_rebalance_left_sub_add_sub(),
    rule_rebalance_left_sub_add_add(),
    rule_rebalance_left_add_sub_sub(),
    rule_rebalance_left_add_sub_add(),
    rule_rebalance_left_add_add_sub(),
    // Commutativity (put last as they can cause explosion)
    rule_add_comm(),
    rule_mul_comm(),
    rule_and_comm(),
    rule_or_comm(),
    rule_xor_comm(),
  ]
}

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
  rs.add_rule(rule_sub_add_cancel(), [TSub])
  rs.add_rule(rule_add_sub_cancel(), [TAdd])
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
