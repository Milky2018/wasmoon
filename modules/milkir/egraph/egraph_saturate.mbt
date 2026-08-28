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
}

///|
fn IndexedRuleSet::IndexedRuleSet() -> IndexedRuleSet {
  { by_opcode: Map([]), universal: [], }
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
  self.last_rule_applications = 0
  self.last_matches_limit_hits = 0
  self.last_eclass_size_limit_hits = 0
  if max_iterations <= 0 {
    return 0
  }
  let mut iters = 0
  while iters < max_iterations {
    let (changed, applied) = self.apply_indexed_rules_once(ruleset, limits)
    self.last_rule_applications = self.last_rule_applications + applied
    iters = iters + 1
    if !changed {
      break
    }
  }
  iters
}

///|
/// Apply the indexed ruleset once over the current e-graph snapshot.
/// Returns true if any rule reported changes.
fn EGraph::apply_indexed_rules_once(
  self : EGraph,
  ruleset : IndexedRuleSet,
  limits : SaturationLimits,
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

    // Apply opcode-indexed rules for any opcode present in the class.
    let tags : Array[EOpcodeTag] = []
    for node in nodes {
      let tag = node.op.tag()
      let mut exists = false
      for t in tags {
        if t == tag {
          exists = true
          break
        }
      }
      if !exists {
        tags.push(tag)
      }
    }
    for tag in tags {
      if class_capped {
        break
      }
      if ruleset.by_opcode.get(tag) is Some(rules) {
        for indexed_rule in rules {
          if class_matches >= limits.matches_limit {
            self.last_matches_limit_hits = self.last_matches_limit_hits + 1
            class_capped = true
            break
          }
          if (indexed_rule.rule.apply)(self, class_id) {
            changed = true
            applied = applied + 1
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
    }
    if class_capped {
      continue
    }
    for indexed_rule in ruleset.universal {
      if class_matches >= limits.matches_limit {
        self.last_matches_limit_hits = self.last_matches_limit_hits + 1
        break
      }
      if (indexed_rule.rule.apply)(self, class_id) {
        changed = true
        applied = applied + 1
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
