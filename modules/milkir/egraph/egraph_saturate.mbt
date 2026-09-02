// Equality saturation: the rule set, its opcode index, and the scheduling
// that applies rules to fixpoint or to a limit.
//
// This is the only part that decides *when* the e-graph grows; the rules
// themselves are in the `rules_*.mbt` files.

// ============================================================================
// Rewrite rules
// ============================================================================

///|
/// Saturation bounds (Cranelift-style):
/// - matches_limit: max successful rewrites to keep per class per pass
/// - eclass_enode_limit: max eclass node budget before skipping further rewrites
pub struct SaturationLimits {
  matches_limit : Int
  eclass_enode_limit : Int
} derive(Debug)

///|
pub fn SaturationLimits::SaturationLimits(
  matches_limit : Int,
  eclass_enode_limit : Int,
) -> SaturationLimits {
  { matches_limit, eclass_enode_limit, }
}

///|
pub fn SaturationLimits::cranelift_default() -> SaturationLimits {
  // Cranelift uses small hard caps for predictability.
  { matches_limit: 5, eclass_enode_limit: 5, }
}

///|
pub fn SaturationLimits::matches_limit(self : SaturationLimits) -> Int {
  self.matches_limit
}

///|
pub fn SaturationLimits::eclass_enode_limit(self : SaturationLimits) -> Int {
  self.eclass_enode_limit
}

///|
/// Global work bounds for one transient e-graph region.
///
/// Per-class caps keep a single equivalence class small. These bounds are
/// complementary: they cap aggregate work when a region contains many small
/// classes, which the Cranelift-style per-class limits alone cannot do.
pub struct SaturationBudget {
  max_nodes : Int
  max_rule_attempts : Int
  max_rule_applications : Int
}

///|
pub fn SaturationBudget::SaturationBudget(
  max_nodes : Int,
  max_rule_attempts : Int,
  max_rule_applications : Int,
) -> SaturationBudget {
  { max_nodes, max_rule_attempts, max_rule_applications, }
}

///|
fn SaturationBudget::unlimited() -> SaturationBudget {
  {
    max_nodes: @int.MAX_VALUE,
    max_rule_attempts: @int.MAX_VALUE,
    max_rule_applications: @int.MAX_VALUE,
  }
}

///|
priv struct SaturationBudgetState {
  budget : SaturationBudget
  mut rule_attempts : Int
  mut rule_applications : Int
  mut current_nodes : Int
  mut exhausted : Bool
}

///|
fn SaturationBudgetState::can_attempt(self : SaturationBudgetState) -> Bool {
  if self.rule_attempts >= self.budget.max_rule_attempts ||
    self.rule_applications >= self.budget.max_rule_applications ||
    self.current_nodes >= self.budget.max_nodes {
    self.exhausted = true
    false
  } else {
    self.rule_attempts = self.rule_attempts + 1
    true
  }
}

///|
/// A rewrite rule matches a pattern and produces equivalent expressions
priv struct RewriteRule {
  apply : (EGraph, EClassId) -> Bool // Returns true if any changes were made
}

///|
/// An indexed rule with its RewriteRule
priv struct IndexedRule {
  rule : RewriteRule
}

///|
/// An indexed rule set for efficient rule application
struct IndexedRuleSet {
  // Rules indexed by the opcode they match
  by_opcode : Map[EOpcodeTag, Array[IndexedRule]]
  // Rules that match any opcode (e.g., constant folding)
  universal : Array[IndexedRule]
  mut generated_matcher : Bool
}

///|
fn IndexedRuleSet::IndexedRuleSet() -> IndexedRuleSet {
  { by_opcode: Map([]), universal: [], generated_matcher: false, }
}

///|
fn IndexedRuleSet::use_generated_matcher(self : IndexedRuleSet) -> Unit {
  for tag, rules in self.by_opcode {
    if generated_rule_bucket_size(tag) != rules.length() {
      abort("generated e-graph matcher does not match the rule registry")
    }
  }
  self.generated_matcher = true
}

///|
/// Add a rule that matches specific opcodes
fn IndexedRuleSet::add_rule(
  self : IndexedRuleSet,
  rule : RewriteRule,
  tags : Array[EOpcodeTag],
) -> Unit {
  let indexed = { rule, }
  if tags.is_empty() {
    self.universal.push(indexed)
  } else {
    for tag in tags {
      match self.by_opcode.get(tag) {
        Some(rules) => rules.push(indexed)
        None => self.by_opcode.set(tag, [indexed])
      }
    }
  }
}

///|
/// Apply rules using opcode index for efficiency
pub fn EGraph::saturate_indexed(
  self : EGraph,
  ruleset : IndexedRuleSet,
  max_iterations : Int,
) -> Int {
  self.saturate_indexed_with_limits(
    ruleset,
    max_iterations,
    SaturationLimits::cranelift_default(),
  )
}

///|
/// Apply rules using opcode index for efficiency with explicit rewrite caps.
pub fn EGraph::saturate_indexed_with_limits(
  self : EGraph,
  ruleset : IndexedRuleSet,
  max_iterations : Int,
  limits : SaturationLimits,
) -> Int {
  self.saturate_indexed_with_budget(
    ruleset,
    max_iterations,
    limits,
    SaturationBudget::unlimited(),
  )
}

///|
/// Apply the indexed ruleset with both per-class and aggregate work bounds.
pub fn EGraph::saturate_indexed_with_budget(
  self : EGraph,
  ruleset : IndexedRuleSet,
  max_iterations : Int,
  limits : SaturationLimits,
  budget : SaturationBudget,
) -> Int {
  self.last_rule_applications = 0
  self.last_rule_attempts = 0
  self.last_saturation_budget_exhausted = false
  self.last_matches_limit_hits = 0
  self.last_eclass_size_limit_hits = 0
  if max_iterations <= 0 {
    return 0
  }
  let state : SaturationBudgetState = {
    budget,
    rule_attempts: 0,
    rule_applications: 0,
    current_nodes: self.num_nodes(),
    exhausted: false,
  }
  let mut iters = 0
  while iters < max_iterations {
    let (changed, applied) = self.apply_indexed_rules_once(
      ruleset, limits, state,
    )
    self.last_rule_applications = self.last_rule_applications + applied
    iters = iters + 1
    if !changed || state.exhausted {
      break
    }
  }
  self.last_rule_attempts = state.rule_attempts
  self.last_saturation_budget_exhausted = state.exhausted
  iters
}

///|
/// Apply the indexed ruleset once over the current e-graph snapshot.
/// Returns true if any rule reported changes.
fn EGraph::apply_indexed_rules_once(
  self : EGraph,
  ruleset : IndexedRuleSet,
  limits : SaturationLimits,
  budget : SaturationBudgetState,
) -> (Bool, Int) {
  let mut changed = false
  let mut applied = 0

  // Snapshot the current class ids in deterministic order.
  let uf_len = self.uf.parent.length()
  let ids : Array[EClassId] = []
  let mut i = 0
  while i < uf_len {
    if self.class_at(i) is Some(_) {
      ids.push(EClassId(i))
    }
    i = i + 1
  }
  for id in ids {
    if budget.exhausted {
      break
    }
    let canonical = self.find(id).0
    guard self.class_at(canonical) is Some(_) else { continue }
    let class_id = EClassId(canonical)
    let nodes = self.get_nodes(class_id)
    guard !nodes.is_empty() else { continue }
    if limits.eclass_enode_limit <= 0 ||
      nodes.length() >= limits.eclass_enode_limit {
      self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits + 1
      continue
    }
    if limits.matches_limit <= 0 {
      self.last_matches_limit_hits = self.last_matches_limit_hits + 1
      continue
    }
    let mut class_matches = 0
    let mut class_capped = false

    // Apply opcode-indexed rules once per opcode present in the class. Classes
    // admitted by the size limit contain at most a handful of nodes, so a
    // scan of prior nodes is cheaper than allocating a temporary tag array for
    // every class.
    let node_count = nodes.length()
    let mut node_index = 0
    while node_index < node_count {
      if class_capped {
        break
      }
      let tag = nodes[node_index].op.tag()
      let mut duplicate = false
      let mut prior = 0
      while prior < node_index {
        if nodes[prior].op.tag() == tag {
          duplicate = true
          break
        }
        prior = prior + 1
      }
      if !duplicate && ruleset.by_opcode.get(tag) is Some(rules) {
        let mut match_bits = if ruleset.generated_matcher {
          generated_rule_match_bits(self, class_id, tag)
        } else {
          0xFFFFFFFFFFFFFFFFUL
        }
        for rule_index, indexed_rule in rules {
          if class_matches >= limits.matches_limit {
            self.last_matches_limit_hits = self.last_matches_limit_hits + 1
            class_capped = true
            break
          }
          if !budget.can_attempt() {
            class_capped = true
            break
          }
          if (match_bits & (1UL << rule_index)) == 0UL {
            continue
          }
          if (indexed_rule.rule.apply)(self, class_id) {
            changed = true
            applied = applied + 1
            budget.rule_applications = budget.rule_applications + 1
            budget.current_nodes = self.num_nodes()
            if ruleset.generated_matcher {
              match_bits = generated_rule_match_bits(self, class_id, tag)
            }
            class_matches = class_matches + 1
            let current_nodes = self.get_nodes(class_id).length()
            if current_nodes >= limits.eclass_enode_limit {
              self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits +
                1
              class_capped = true
              break
            }
          }
        }
      }
      node_index = node_index + 1
    }
    if class_capped {
      continue
    }
    for indexed_rule in ruleset.universal {
      if class_matches >= limits.matches_limit {
        self.last_matches_limit_hits = self.last_matches_limit_hits + 1
        break
      }
      if !budget.can_attempt() {
        break
      }
      if (indexed_rule.rule.apply)(self, class_id) {
        changed = true
        applied = applied + 1
        budget.rule_applications = budget.rule_applications + 1
        budget.current_nodes = self.num_nodes()
        class_matches = class_matches + 1
        let current_nodes = self.get_nodes(class_id).length()
        if current_nodes >= limits.eclass_enode_limit {
          self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits +
            1
          break
        }
      }
    }
  }
  if changed {
    self.rebuild()
  }
  (changed, applied)
}
