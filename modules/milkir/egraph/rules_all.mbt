// Standard rules collection (indexed for efficient application)

///|
/// Global singleton for indexed ruleset - built once, reused everywhere
let global_indexed_ruleset : Ref[IndexedRuleSet?] = { val: None, }

///|
let compact_indexed_ruleset : Ref[IndexedRuleSet?] = { val: None, }

///|
/// Get the global indexed ruleset (singleton pattern for performance).
///
/// Default rule registration and matcher conditions live in
/// `rules_matcher.schema`; the package build generates both from that source.
pub fn get_global_ruleset() -> IndexedRuleSet {
  match global_indexed_ruleset.val {
    Some(rs) => rs
    None => {
      let rs = generated_build_indexed_ruleset()
      global_indexed_ruleset.val = Some(rs)
      rs
    }
  }
}

///|
/// Get a compact ruleset for large functions where compile-time predictability
/// matters more than chasing deep algebraic rewrites.
pub fn get_compact_ruleset() -> IndexedRuleSet {
  match compact_indexed_ruleset.val {
    Some(rs) => rs
    None => {
      let rs = build_compact_indexed_ruleset()
      compact_indexed_ruleset.val = Some(rs)
      rs
    }
  }
}

///|
/// Rules that require frontend- or target-provided definedness facts.
///
/// These are intentionally not part of `get_global_ruleset` because generic
/// MilkIR does not yet model whether division/remainder operations are total,
/// trapping, or poison-producing. A frontend adapter may use this collection
/// only after proving the required non-zero and overflow preconditions.
pub fn legality_sensitive_rules() -> IndexedRuleSet {
  let rs = IndexedRuleSet::IndexedRuleSet()
  rs.add_rule(rule_udiv_pow2(), [TUdiv])
  rs.add_rule(rule_urem_pow2(), [TUrem])
  rs.add_rule(rule_sdiv_neg_one(), [TSdiv])
  rs.add_rule(rule_srem_neg_one(), [TSrem])
  rs.add_rule(rule_div_one(), [TSdiv, TUdiv])
  rs.add_rule(rule_rem_one(), [TSrem, TUrem])
  rs.add_rule(rule_udiv_select_pow2(), [TUdiv])
  rs
}

///|
fn build_compact_indexed_ruleset() -> IndexedRuleSet {
  let rs = IndexedRuleSet::IndexedRuleSet()
  // Keep the same core simplifications Cranelift relies on frequently,
  // while avoiding expensive long-tail algebraic exploration.
  rs.add_rule(rule_const_fold(), [])
  rs.add_rule(rule_add_zero(), [TAdd])
  rs.add_rule(rule_sub_zero(), [TSub])
  rs.add_rule(rule_sub_self(), [TSub])
  rs.add_rule(rule_mul_one(), [TMul])
  rs.add_rule(rule_mul_zero(), [TMul])
  // TODO(ISS-017): compact rules intentionally exclude div/rem rewrites until
  // MilkIR has explicit definedness facts for those opcodes.
  rs.add_rule(rule_and_zero(), [TAnd])
  rs.add_rule(rule_or_zero(), [TOr])
  rs.add_rule(rule_xor_zero(), [TXor])
  rs.add_rule(rule_and_all_ones(), [TAnd])
  rs.add_rule(rule_or_all_ones(), [TOr])
  rs.add_rule(rule_or_self(), [TOr])
  rs.add_rule(rule_xor_self(), [TXor])
  rs.add_rule(rule_double_bnot(), [TBnot])
  rs.add_rule(rule_shl_zero(), [TShl])
  rs.add_rule(rule_shr_zero(), [TSshr, TUshr])
  rs.add_rule(rule_shift_of_zero(), [TShl, TSshr, TUshr])
  rs.add_rule(rule_rot_zero(), [TRotl, TRotr])
  rs.add_rule(rule_select_const(), [TSelect])
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
  rs
}
