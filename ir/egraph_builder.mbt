// EGraph IR Integration - converts IR to/from EGraph
// ============================================================================
// IR Integration - Convert IR instructions to/from EGraph
// ============================================================================

///|
/// Builder for constructing an EGraph from IR instructions
struct EGraphBuilder {
  egraph : @egraph.EGraph
  // Map from IR Value id to EClassId
  value_map : Map[Int, @egraph.EClassId]
  // Reverse map from (canonical EClassId, Type) to an in-scope IR Value (for operand rewriting)
  class_to_value : Map[RepKey, Value]
  // Map from IR Value id to its defining instruction
  def_map : Map[Int, Inst]
  // Ruleset for eager optimization
  ruleset : @egraph.IndexedRuleSet
  // Rewrite limits (Cranelift-style hard caps).
  saturation_limits : @egraph.SaturationLimits
}

///|
/// Key used for mapping an e-class to an in-scope IR value of a specific type.
/// Note: an e-class may contain values of multiple IR types (e.g., shared constants),
/// so the Type must be part of the key to avoid producing ill-typed IR.
struct RepKey {
  class_id : Int
  ty : Type
} derive(Eq, Hash, Show)

///|
pub fn EGraphBuilder::new() -> EGraphBuilder {
  EGraphBuilder::new_with_limits(@egraph.SaturationLimits::cranelift_default())
}

///|
pub fn EGraphBuilder::new_with_limits(
  saturation_limits : @egraph.SaturationLimits,
) -> EGraphBuilder {
  {
    egraph: @egraph.EGraph::new(),
    value_map: {},
    class_to_value: {},
    def_map: {},
    ruleset: @egraph.get_global_ruleset(),
    saturation_limits,
  }
}

///|
/// Register an instruction's definition
pub fn EGraphBuilder::register_def(self : EGraphBuilder, inst : Inst) -> Unit {
  if inst.first_result() is Some(v) {
    self.def_map.set(v.id, inst)
  }
}

///|
/// Convert IntCC to an ordinal value
fn intcc_to_ordinal(cc : IntCC) -> Int {
  match cc {
    Eq => 0
    Ne => 1
    Slt => 2
    Sle => 3
    Sgt => 4
    Sge => 5
    Ult => 6
    Ule => 7
    Ugt => 8
    Uge => 9
  }
}

///|
/// Get bit width from IR Type
fn type_bits(ty : Type) -> Int {
  match ty {
    I32 => 32
    I64 => 64
    F32 => 32
    F64 => 64
    V128 => 128
    FuncRef | ExternRef => 64 // Pointer-sized
  }
}

///|

///|
/// Whether an opcode currently has an e-graph encoding in `@egraph.EOpcode`.
///
/// This is intentionally narrower than generic IR purity: admission also needs
/// an explicit encoding in the e-graph node language.
fn opcode_has_egraph_encoding(opcode : Opcode) -> Bool {
  match opcode {
    Iconst(_) => true
    Iadd | Isub | Imul => true
    Band | Bor | Bxor | Bnot => true
    Ishl | Sshr | Ushr | Rotl | Rotr => true
    Clz | Ctz | Popcnt => true
    Icmp(_) => true
    Select => true
    Ireduce | Uextend | Sextend => true
    _ => false
  }
}

///|
/// Cranelift-aligned e-graph purity boundary:
/// - exactly one result
/// - no side effects / trapping semantics (per IR side-effect model)
/// - opcode has a representable e-graph encoding
fn inst_is_egraph_pure(inst : Inst) -> Bool {
  inst.all_results().length() == 1 &&
  !has_side_effects(inst) &&
  opcode_has_egraph_encoding(inst.opcode)
}

///|
/// Convert an IR Opcode to an EOpcode (if optimizable and purity-safe).
/// Takes the instruction to extract type information for extend/reduce ops.
fn opcode_to_eopcode(inst : Inst) -> @egraph.EOpcode? {
  if !inst_is_egraph_pure(inst) {
    return None
  }
  match inst.opcode {
    Iconst(c) => Some(@egraph.EOpcode::Const(c))
    Iadd => Some(@egraph.EOpcode::Add)
    Isub => Some(@egraph.EOpcode::Sub)
    Imul => Some(@egraph.EOpcode::Mul)
    Band => Some(@egraph.EOpcode::And)
    Bor => Some(@egraph.EOpcode::Or)
    Bxor => Some(@egraph.EOpcode::Xor)
    Bnot => Some(@egraph.EOpcode::Bnot)
    Ishl => Some(@egraph.EOpcode::Shl)
    Sshr => Some(@egraph.EOpcode::Sshr)
    Ushr => Some(@egraph.EOpcode::Ushr)
    Rotl => Some(@egraph.EOpcode::Rotl)
    Rotr => Some(@egraph.EOpcode::Rotr)
    Clz => Some(@egraph.EOpcode::Clz)
    Ctz => Some(@egraph.EOpcode::Ctz)
    Popcnt => Some(@egraph.EOpcode::Popcnt)
    Icmp(cc) => Some(@egraph.EOpcode::Icmp(intcc_to_ordinal(cc)))
    Select => Some(@egraph.EOpcode::Select)
    Ireduce => {
      // ireduce: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        64 // default
      }
      let to_bits = match inst.first_result() {
        Some(v) => type_bits(v.ty)
        None => 32 // default
      }
      Some(@egraph.EOpcode::Ireduce(from_bits, to_bits))
    }
    Uextend => {
      // uextend: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        32 // default
      }
      let to_bits = match inst.first_result() {
        Some(v) => type_bits(v.ty)
        None => 64 // default
      }
      Some(@egraph.EOpcode::Uextend(from_bits, to_bits))
    }
    Sextend => {
      // sextend: from_bits = operand type, to_bits = result type
      let from_bits = if inst.operands.length() > 0 {
        type_bits(inst.operands[0].ty)
      } else {
        32 // default
      }
      let to_bits = match inst.first_result() {
        Some(v) => type_bits(v.ty)
        None => 64 // default
      }
      Some(@egraph.EOpcode::Sextend(from_bits, to_bits))
    }
    _ => None // Not optimizable via e-graph
  }
}

///|
/// Add an IR value to the e-graph, recursively adding its definition
/// Uses eager optimization: rules are applied immediately when adding nodes
pub fn EGraphBuilder::add_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId {
  // Check if already converted
  if self.value_map.get(value.id) is Some(id) {
    return self.egraph.find(id) // Return canonical id
  }

  // Get the bit width from the value's type
  let bits = type_bits(value.ty)

  // Look up the defining instruction
  let class_id = if self.def_map.get(value.id) is Some(inst) {
    // Try to convert the opcode (pass full instruction for type info)
    match opcode_to_eopcode(inst) {
      None => {
        // Not an optimizable opcode - treat as variable
        let id = self.egraph.add_var(value.id)
        self.egraph.set_type(id, bits)
        id
      }
      Some(eop) =>
        match eop {
          Const(c) => {
            let id = self.egraph.add_const(c)
            self.egraph.set_type(id, bits)
            id
          }
          _ => {
            // Recursively add operands
            let children : Array[@egraph.EClassId] = []
            for operand in inst.operands {
              children.push(self.add_value(operand))
            }
            // Add the node with type info; rewriting happens in a later saturation step.
            self.egraph.add_typed({ op: eop, children }, bits)
          }
        }
    }
  } else {
    // No definition found - treat as a variable (parameter or external)
    let id = self.egraph.add_var(value.id)
    self.egraph.set_type(id, bits)
    id
  }
  self.value_map.set(value.id, class_id)
  class_id
}

///|
/// Run optimization on the e-graph
/// With eager optimization, this only needs to rebuild to restore invariants
pub fn EGraphBuilder::optimize(self : EGraphBuilder) -> Unit {
  // One-pass, directed simplification (Cranelift-style aegraph).
  // Additional improvement opportunities are handled by later passes.
  self.egraph.saturate_indexed_with_limits(
    self.ruleset,
    1,
    self.saturation_limits,
  )
  |> ignore
}

///|
/// Get the optimized e-graph
pub fn EGraphBuilder::get_egraph(self : EGraphBuilder) -> @egraph.EGraph {
  self.egraph
}

///|
/// Extract the best expression for a given IR value
pub fn EGraphBuilder::extract(
  self : EGraphBuilder,
  value : Value,
) -> (Int, @egraph.ENode)? {
  match self.value_map.get(value.id) {
    Some(class_id) => Some(self.egraph.extract(class_id))
    None => None
  }
}

///|
/// Optimize a single basic block's arithmetic expressions
/// Returns a map from original Value id to optimized ENode
pub fn optimize_block(block : Block) -> Map[Int, (Int, @egraph.ENode)] {
  optimize_block_with_limits(
    block,
    @egraph.SaturationLimits::cranelift_default(),
  )
}

///|
pub fn optimize_block_with_limits(
  block : Block,
  limits : @egraph.SaturationLimits,
) -> Map[Int, (Int, @egraph.ENode)] {
  let builder = EGraphBuilder::new_with_limits(limits)

  // First pass: register all definitions
  for inst in block.instructions {
    builder.register_def(inst)
  }

  // Second pass: add all arithmetic values to e-graph
  for inst in block.instructions {
    if inst.first_result() is Some(v) && opcode_to_eopcode(inst) is Some(_) {
      // Only add if it's an optimizable operation
      builder.add_value(v) |> ignore
    }
  }

  // Run saturation
  builder.optimize()

  // Extract optimized results
  let results : Map[Int, (Int, @egraph.ENode)] = {}
  for inst in block.instructions {
    if inst.first_result() is Some(v) && builder.extract(v) is Some(result) {
      results.set(v.id, result)
    }
  }
  results
}

///|
/// Check if the extracted expression is a constant folding result
/// Returns Some(Iconst(c)) if constant folding found, None otherwise
/// NOTE: Only handles constant folding. Complex rewrites (like x*3 -> (x<<1)+x)
/// are not handled because they would require operand reconstruction.
pub fn EGraphBuilder::get_simplified_opcode(
  self : EGraphBuilder,
  value : Value,
) -> Opcode? {
  match self.value_map.get(value.id) {
    None => None
    Some(class_id) => {
      let (_, best_node) = self.egraph.extract(class_id)
      // Only handle constant folding - returns Iconst if the result is a constant
      match best_node.op {
        Const(c) => Some(Iconst(c))
        // Don't change opcode for non-constant results - would need operand reconstruction
        _ => None
      }
    }
  }
}

///|
/// Get the simplified value for an operand (for operand rewriting)
/// If the operand's e-class has a simpler representation that maps to
/// an existing IR value, return that value; otherwise return None.
pub fn EGraphBuilder::get_simplified_operand(
  self : EGraphBuilder,
  value : Value,
) -> Value? {
  match self.value_map.get(value.id) {
    None => None
    Some(class_id) => {
      // Get the canonical class after optimization
      let canonical = self.egraph.find(class_id)
      // Check if this class maps to a different (simpler) value with same IR type
      let key : RepKey = { class_id: canonical.0, ty: value.ty }
      match self.class_to_value.get(key) {
        None => None
        Some(simplified_value) =>
          // Only return if it's different from the original
          if simplified_value.id != value.id {
            Some(simplified_value)
          } else {
            None
          }
      }
    }
  }
}

///|
/// Recompute per-block representatives for operand rewriting.
/// This ensures the representative:
/// - has the correct IR type for the use site
/// - is defined early enough in the block (dominates subsequent uses in the block)
fn EGraphBuilder::recompute_representatives_for_block(
  self : EGraphBuilder,
  block : Block,
) -> Unit {
  self.class_to_value.clear()
  fn try_add_rep(self : EGraphBuilder, value : Value) -> Unit {
    if self.value_map.get(value.id) is Some(class_id) {
      let canonical = self.egraph.find(class_id)
      let key : RepKey = { class_id: canonical.0, ty: value.ty }
      if !self.class_to_value.contains(key) {
        self.class_to_value.set(key, value)
      }
    }
  }

  // Block params dominate all instructions in the block.
  for pair in block.params {
    let (v, _) = pair
    try_add_rep(self, v)
  }

  // Instruction order within the block defines dominance.
  for inst in block.instructions {
    for op in inst.operands {
      try_add_rep(self, op)
    }
    if inst.first_result() is Some(v) {
      try_add_rep(self, v)
    }
  }
}

///|
/// Apply e-graph optimization to a function
/// Returns true if any optimization was applied
pub struct EGraphOptimizeStats {
  changed : Bool
  total_classes : Int
  total_nodes : Int
  total_rule_applications : Int
}

///|
/// Apply e-graph optimization to a function and return aggregate stats.
pub fn optimize_function_with_stats(func : Function) -> EGraphOptimizeStats {
  optimize_function_with_stats_with_limits(
    func,
    @egraph.SaturationLimits::cranelift_default(),
  )
}

///|
pub fn optimize_function_with_stats_with_limits(
  func : Function,
  limits : @egraph.SaturationLimits,
) -> EGraphOptimizeStats {
  let mut changed = false
  let builder = EGraphBuilder::new_with_limits(limits)

  // Function-scoped e-graph construction (Cranelift-directional alignment):
  // build one e-graph for the whole function instead of isolated per-block
  // e-graphs.
  for block in func.blocks {
    for inst in block.instructions {
      builder.register_def(inst)
    }
  }

  for block in func.blocks {
    // Add all e-graph-admitted values from all blocks.
    for inst in block.instructions {
      if inst.first_result() is Some(v) && opcode_to_eopcode(inst) is Some(_) {
        builder.add_value(v) |> ignore
      }
    }
  }

  // Run one saturation pass on the function-wide e-graph.
  builder.optimize()
  let egraph = builder.get_egraph()
  let total_classes = egraph.num_classes()
  let total_nodes = egraph.num_nodes()
  let total_rule_applications = egraph.last_rule_applications()

  // Rewrite each block using the optimized function-wide e-graph. We still use
  // block-local representative mapping for operand rewrites to preserve
  // in-block dominance safety.
  for block in func.blocks {
    builder.recompute_representatives_for_block(block)

    // Apply optimizations: constant folding and operand rewriting
    for inst in block.instructions {
      // First, try to simplify operands (e.g., x + 0 -> x means operand can be simplified)
      for i in 0..<inst.operands.length() {
        let operand = inst.operands[i]
        if builder.get_simplified_operand(operand) is Some(simplified) {
          inst.operands[i] = simplified
          changed = true
        }
      }

      // Then, try to simplify the result value
      if inst.first_result() is Some(v) &&
        builder.get_simplified_opcode(v) is Some(op) {
        if op is Iconst(c) {
          // Replace with constant only when it materially changes the IR.
          // Otherwise we can report spurious "changed" forever.
          let mut inst_changed = false
          match inst.opcode {
            Iconst(old_c) =>
              if old_c != c || inst.operands.length() > 0 {
                inst.opcode = Iconst(c)
                inst.operands.clear()
                inst_changed = true
              }
            _ => {
              inst.opcode = Iconst(c)
              inst.operands.clear()
              inst_changed = true
            }
          }
          if inst_changed {
            changed = true
          }
        } else if inst.opcode != op {
          // Opcode changed - update it only when different.
          inst.opcode = op
          changed = true
        }
      }
    }
  }
  { changed, total_classes, total_nodes, total_rule_applications }
}

///|
/// Apply e-graph optimization to a function.
/// Returns true if any optimization was applied.
pub fn optimize_function(func : Function) -> Bool {
  optimize_function_with_limits(
    func,
    @egraph.SaturationLimits::cranelift_default(),
  )
}

///|
pub fn optimize_function_with_limits(
  func : Function,
  limits : @egraph.SaturationLimits,
) -> Bool {
  optimize_function_with_stats_with_limits(func, limits).changed
}
