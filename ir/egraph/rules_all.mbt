// Standard rules collection (indexed for efficient application)

///|
/// Global singleton for indexed ruleset - built once, reused everywhere
let global_indexed_ruleset : Ref[IndexedRuleSet?] = { val: None }

///|
/// Get the global indexed ruleset (singleton pattern for performance)
pub fn get_global_ruleset() -> IndexedRuleSet {
  match global_indexed_ruleset.val {
    Some(rs) => rs
    None => {
      let rs = build_indexed_ruleset()
      global_indexed_ruleset.val = Some(rs)
      rs
    }
  }
}

///|
/// Get all standard rewrite rules indexed by their matching opcodes
/// Note: For production code, prefer get_global_ruleset() which caches the result.
/// This function is kept for backwards compatibility with tests.
pub fn standard_rules_indexed() -> IndexedRuleSet {
  build_indexed_ruleset()
}

///|
/// Build the indexed ruleset (internal, called once by get_global_ruleset)
fn build_indexed_ruleset() -> IndexedRuleSet {
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
  rs.add_rule(rule_rot_zero(), [TRotl, TRotr])
  rs.add_rule(rule_shl_shl(), [TShl])
  rs.add_rule(rule_ushr_ushr(), [TUshr])
  rs.add_rule(rule_sshr_sshr(), [TSshr])
  rs.add_rule(rule_rotl_rotr_cancel(), [TRotl])
  rs.add_rule(rule_rotr_rotl_cancel(), [TRotr])
  rs.add_rule(rule_ushr_shl_mask(), [TShl])
  rs.add_rule(rule_shl_ushr_mask(), [TUshr])
  rs.add_rule(rule_band_shl_shl(), [TAnd])
  rs.add_rule(rule_sub_shl_shl(), [TSub])
  rs.add_rule(rule_add_shl_shl(), [TAdd])
  rs.add_rule(rule_ushr_band_shl(), [TUshr])
  rs.add_rule(rule_shl_ushr_to_rotl(), [TOr])
  rs.add_rule(rule_neg_ushr_to_sshr(), [TNeg])
  rs.add_rule(rule_shl_shl_overflow(), [TShl])
  rs.add_rule(rule_ushr_ushr_overflow(), [TUshr])
  // Rotation combining
  rs.add_rule(rule_rotl_rotl_combine(), [TRotl])
  rs.add_rule(rule_rotr_rotr_combine(), [TRotr])
  rs.add_rule(rule_rotr_rotl_to_rotl(), [TRotr])
  rs.add_rule(rule_rotl_rotr_to_rotr(), [TRotl])
  // Shift amount extend/reduce removal
  rs.add_rule(rule_shift_extend_amount(), [TShl, TUshr, TSshr, TRotl, TRotr])
  rs.add_rule(rule_shift_reduce_amount(), [TShl, TUshr, TSshr, TRotl, TRotr])
  // Strength reduction
  rs.add_rule(rule_mul_pow2(), [TMul])
  // Constant reassociation should run before lowering mul to shift/add forms.
  rs.add_rule(rule_reassoc_mul_const(), [TMul])
  rs.add_rule(rule_mul_shl_const(), [TMul])
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
  rs.add_rule(rule_neg_sub_swap(), [TNeg])
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
  // Vector splat lifting: op(splat(x), splat(y)) -> splat(op(x, y))
  rs.add_rule(rule_band_splat_splat(), [TAnd])
  rs.add_rule(rule_bor_splat_splat(), [TOr])
  rs.add_rule(rule_bxor_splat_splat(), [TXor])
  rs.add_rule(rule_bnot_splat(), [TBnot])
  rs.add_rule(rule_iadd_splat_splat(), [TAdd])
  rs.add_rule(rule_isub_splat_splat(), [TSub])
  rs.add_rule(rule_imul_splat_splat(), [TMul])
  rs.add_rule(rule_ineg_splat(), [TNeg])
  rs.add_rule(rule_iabs_splat(), [TIabs])
  rs.add_rule(rule_popcnt_splat(), [TPopcnt])
  rs.add_rule(rule_smin_splat_splat(), [TSmin])
  rs.add_rule(rule_umin_splat_splat(), [TUmin])
  rs.add_rule(rule_smax_splat_splat(), [TSmax])
  rs.add_rule(rule_umax_splat_splat(), [TUmax])
  // Shift/rotate with splat on first operand only
  rs.add_rule(rule_rotl_splat(), [TRotl])
  rs.add_rule(rule_rotr_splat(), [TRotr])
  rs.add_rule(rule_ishl_splat(), [TShl])
  rs.add_rule(rule_ushr_splat(), [TUshr])
  rs.add_rule(rule_sshr_splat(), [TSshr])
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
  // Uextend comparison optimizations (uextend values are always non-negative)
  rs.add_rule(rule_slt_uextend_zero(), [TIcmp])
  rs.add_rule(rule_sge_uextend_zero(), [TIcmp])
  // Masking with type masks
  rs.add_rule(rule_band_uextend_mask(), [TAnd])
  rs.add_rule(rule_band_sextend_mask(), [TAnd])
  // Type-dependent extend/reduce rules (use bit width info)
  rs.add_rule(rule_ireduce_const(), [TIreduce])
  rs.add_rule(rule_uextend_const(), [TUextend])
  rs.add_rule(rule_sextend_const(), [TSextend])
  rs.add_rule(rule_uextend_identity(), [TUextend])
  rs.add_rule(rule_sextend_identity(), [TSextend])
  rs.add_rule(rule_ireduce_identity(), [TIreduce])
  rs.add_rule(rule_band_uextend_mask_precise(), [TAnd])
  rs.add_rule(rule_ireduce_uextend_skip(), [TIreduce])
  rs.add_rule(rule_ireduce_sextend_skip(), [TIreduce])
  rs.add_rule(rule_ireduce_uextend_to_extend(), [TIreduce])
  rs.add_rule(rule_ireduce_sextend_to_extend(), [TIreduce])
  // Canonicalization rules (push constants to the right)
  // Push constants to the right: (k + x) -> (x + k)
  rs.add_rule(rule_canon_add(), [TAdd])
  rs.add_rule(rule_canon_mul(), [TMul])
  rs.add_rule(rule_canon_and(), [TAnd])
  rs.add_rule(rule_canon_or(), [TOr])
  rs.add_rule(rule_canon_xor(), [TXor])
  // Tree rebalancing rules (improve ILP)
  // Rebalance 4-deep chains: a op (b op (c op d)) -> (a op b) op (c op d)
  rs.add_rule(rule_rebalance_add_right(), [TAdd])
  rs.add_rule(rule_rebalance_add_left(), [TAdd])
  rs.add_rule(rule_rebalance_mul_right(), [TMul])
  rs.add_rule(rule_rebalance_mul_left(), [TMul])
  rs.add_rule(rule_rebalance_and_right(), [TAnd])
  rs.add_rule(rule_rebalance_and_left(), [TAnd])
  rs.add_rule(rule_rebalance_xor_right(), [TXor])
  rs.add_rule(rule_rebalance_xor_left(), [TXor])
  // Add/Sub mixed rebalancing rules
  rs.add_rule(rule_sub_sub_sub_right(), [TSub])
  rs.add_rule(rule_sub_sub_add_right(), [TSub])
  rs.add_rule(rule_sub_add_sub_right(), [TSub])
  rs.add_rule(rule_sub_add_add_right(), [TSub])
  rs.add_rule(rule_add_sub_sub_right(), [TAdd])
  rs.add_rule(rule_add_sub_add_right(), [TAdd])
  rs.add_rule(rule_add_add_sub_right(), [TAdd])
  rs.add_rule(rule_sub_sub_sub_left(), [TSub])
  rs.add_rule(rule_sub_sub_add_left(), [TAdd])
  rs.add_rule(rule_sub_add_sub_left(), [TSub])
  rs.add_rule(rule_sub_add_add_left(), [TAdd])
  rs.add_rule(rule_add_sub_sub_left(), [TSub])
  rs.add_rule(rule_add_sub_add_left(), [TAdd])
  rs.add_rule(rule_add_add_sub_left(), [TSub])
  // Integer comparison optimizations
  rs.add_rule(rule_eq_self(), [TEq])
  rs.add_rule(rule_ne_self(), [TNe])
  rs.add_rule(rule_icmp_self(), [TIcmp])
  rs.add_rule(rule_ne_icmp_zero(), [TNe])
  rs.add_rule(rule_eq_icmp_zero(), [TEq])
  rs.add_rule(rule_ne_icmp_one(), [TNe])
  rs.add_rule(rule_eq_icmp_one(), [TEq])
  rs.add_rule(rule_band_icmp_one(), [TAnd])
  rs.add_rule(rule_ult_zero(), [TIcmp])
  rs.add_rule(rule_ule_zero(), [TIcmp])
  rs.add_rule(rule_ugt_zero(), [TIcmp])
  rs.add_rule(rule_uge_zero(), [TIcmp])
  rs.add_rule(rule_uge_one_to_ne_zero(), [TIcmp])
  rs.add_rule(rule_ult_one_to_eq_zero(), [TIcmp])
  rs.add_rule(rule_sge_one_to_sgt_zero(), [TIcmp])
  rs.add_rule(rule_slt_one_to_sle_zero(), [TIcmp])
  rs.add_rule(rule_sgt_neg_one_to_sge_zero(), [TIcmp])
  rs.add_rule(rule_sle_neg_one_to_slt_zero(), [TIcmp])
  rs.add_rule(rule_eq_add_cancel(), [TEq])
  rs.add_rule(rule_ne_add_cancel(), [TNe])
  rs.add_rule(rule_eq_xor_self(), [TEq])
  rs.add_rule(rule_ne_xor_self(), [TNe])
  rs.add_rule(rule_ugt_sub_self(), [TIcmp])
  rs.add_rule(rule_ule_sub_self(), [TIcmp])
  rs.add_rule(rule_ult_bnot_swap(), [TIcmp])
  rs.add_rule(rule_slt_bnot_swap(), [TIcmp])
  rs.add_rule(rule_xor_cmp_to_ne(), [TXor])
  rs.add_rule(rule_band_contradictory_cmp(), [TAnd])
  rs.add_rule(rule_select_uextend_icmp(), [TSelect])
  // Comparison reassociation with constants
  rs.add_rule(rule_eq_add_const(), [TEq])
  rs.add_rule(rule_ne_add_const(), [TNe])
  rs.add_rule(rule_eq_sub_const(), [TEq])
  rs.add_rule(rule_ne_sub_const(), [TNe])
  // icmp swap and add-add comparison
  rs.add_rule(rule_icmp_swap_const(), [TIcmp, TEq, TNe])
  rs.add_rule(rule_eq_add_add_const(), [TEq])
  rs.add_rule(rule_ne_add_add_const(), [TNe])
  // Select optimization rules
  rs.add_rule(rule_select_same(), [TSelect])
  rs.add_rule(rule_select_icmp_one_zero(), [TSelect])
  rs.add_rule(rule_select_icmp_zero_one(), [TSelect])
  rs.add_rule(rule_select_nested_same_cond_right(), [TSelect])
  rs.add_rule(rule_select_nested_same_cond_left(), [TSelect])
  rs.add_rule(rule_select_uextend_cond(), [TSelect])
  rs.add_rule(rule_add_select_const(), [TAdd])
  // Select-to-min/max rules
  rs.add_rule(rule_select_to_smax(), [TSelect])
  rs.add_rule(rule_select_to_smin(), [TSelect])
  rs.add_rule(rule_select_to_umax(), [TSelect])
  rs.add_rule(rule_select_to_umin(), [TSelect])
  rs.add_rule(rule_select_to_smax_swapped(), [TSelect])
  rs.add_rule(rule_select_to_smin_swapped(), [TSelect])
  rs.add_rule(rule_select_to_umax_swapped(), [TSelect])
  rs.add_rule(rule_select_to_umin_swapped(), [TSelect])
  // Select-to-iabs rules
  rs.add_rule(rule_select_to_iabs_positive(), [TSelect])
  rs.add_rule(rule_select_to_iabs_negative(), [TSelect])
  // Min/max comparison rules
  rs.add_rule(rule_smin_never_greater(), [TIcmp])
  rs.add_rule(rule_never_less_than_smin(), [TIcmp])
  rs.add_rule(rule_umin_never_greater(), [TIcmp])
  rs.add_rule(rule_never_less_than_umin(), [TIcmp])
  // Type-aware comparison rules (use type bounds UMAX, SMIN, SMAX)
  rs.add_rule(rule_ugt_umax(), [TIcmp])
  rs.add_rule(rule_uge_umax(), [TIcmp])
  rs.add_rule(rule_ule_umax(), [TIcmp])
  rs.add_rule(rule_sgt_smax(), [TIcmp])
  rs.add_rule(rule_sge_smax(), [TIcmp])
  rs.add_rule(rule_slt_smin(), [TIcmp])
  rs.add_rule(rule_sle_smin(), [TIcmp])
  rs.add_rule(rule_sge_smin(), [TIcmp])
  rs.add_rule(rule_sle_smax(), [TIcmp])
  // Rematerialization rules (mark cheap-to-recompute expressions)
  rs.add_rule(rule_remat_iadd_iconst_left(), [TAdd])
  rs.add_rule(rule_remat_iadd_iconst_right(), [TAdd])
  rs.add_rule(rule_remat_isub_iconst_left(), [TSub])
  rs.add_rule(rule_remat_isub_iconst_right(), [TSub])
  rs.add_rule(rule_remat_band_iconst_left(), [TAnd])
  rs.add_rule(rule_remat_band_iconst_right(), [TAnd])
  rs.add_rule(rule_remat_bor_iconst_left(), [TOr])
  rs.add_rule(rule_remat_bor_iconst_right(), [TOr])
  rs.add_rule(rule_remat_bxor_iconst_left(), [TXor])
  rs.add_rule(rule_remat_bxor_iconst_right(), [TXor])
  rs.add_rule(rule_remat_bnot(), [TBnot])
  rs.add_rule(rule_remat_iconst(), [TConst])
  rs.add_rule(rule_remat_fconst(), [TFconst])
  // Skeleton rules (side-effect simplifications)
  rs.add_rule(rule_udiv_select_pow2(), [TUdiv])
  // Spaceship comparison simplification rules
  rs.add_rule(rule_spaceship_eq_zero(), [TEq, TIcmp])
  rs.add_rule(rule_spaceship_ne_zero(), [TNe, TIcmp])
  rs.add_rule(rule_spaceship_s_lt_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_u_lt_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_s_le_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_u_le_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_s_gt_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_u_gt_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_s_ge_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_u_ge_zero(), [TIcmp])
  rs.add_rule(rule_spaceship_s_eq_neg_one(), [TEq, TIcmp])
  rs.add_rule(rule_spaceship_u_eq_neg_one(), [TEq, TIcmp])
  rs.add_rule(rule_spaceship_s_ne_neg_one(), [TNe, TIcmp])
  rs.add_rule(rule_spaceship_u_ne_neg_one(), [TNe, TIcmp])
  rs.add_rule(rule_spaceship_s_eq_one(), [TEq, TIcmp])
  rs.add_rule(rule_spaceship_u_eq_one(), [TEq, TIcmp])
  rs.add_rule(rule_spaceship_s_ne_one(), [TNe, TIcmp])
  rs.add_rule(rule_spaceship_u_ne_one(), [TNe, TIcmp])
  rs
}
