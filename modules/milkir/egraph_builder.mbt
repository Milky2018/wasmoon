// EGraph IR Integration - converts IR to/from EGraph
// ============================================================================
// IR Integration - Convert IR instructions to/from EGraph
// ============================================================================

///|
/// Builder for constructing an EGraph from IR instructions
priv struct EGraphBuilder {
  egraph : @egraph.EGraph
  // Dense map from IR Value id to EClassId (Cranelift SecondaryMap style).
  value_map : Array[@egraph.EClassId?]
  // Reverse map from (canonical EClassId, Type) to an in-scope IR Value (for operand rewriting)
  class_to_value : Map[RepKey, Value]
  // Dense map from IR Value id to its defining instruction.
  def_map : Array[Inst?]
  // Dense map from IR Value id to its e-graph-encodable opcode (if pure/admitted).
  def_eop_map : Array[@egraph.EOpcode?]
  // Ruleset for eager optimization
  ruleset : @egraph.IndexedRuleSet
  // Rewrite limits (Cranelift-style hard caps).
  saturation_limits : @egraph.SaturationLimits
}

///|
/// Key used for mapping an e-class to an in-scope IR value of a specific type.
/// Note: an e-class may contain values of multiple IR types (e.g., shared constants),
/// so the Type must be part of the key to avoid producing ill-typed IR.
priv struct RepKey {
  class_id : Int
  ty : Type
} derive(Eq, Hash)

///|
/// Event for the explicit dominator-tree walk: `Enter` rewrites a block and
/// schedules its children, `Exit` restores the representative bindings that
/// block introduced.
priv enum DomWalkEvent {
  Enter(Int)
  Exit(Array[(RepKey, Value?)])
}

///|
fn EGraphBuilder::new_with_limits_and_ruleset(
  saturation_limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
) -> EGraphBuilder {
  {
    egraph: EGraph(),
    value_map: [],
    class_to_value: Map([]),
    def_map: [],
    def_eop_map: [],
    ruleset,
    saturation_limits,
  }
}

///|
fn EGraphBuilder::ensure_value_slot(
  self : EGraphBuilder,
  value_id : Int,
) -> Unit {
  if value_id < 0 {
    return
  }
  while self.value_map.length() <= value_id {
    self.value_map.push(None)
  }
  while self.def_map.length() <= value_id {
    self.def_map.push(None)
  }
  while self.def_eop_map.length() <= value_id {
    self.def_eop_map.push(None)
  }
}

///|
fn EGraphBuilder::reserve_value_slots(
  self : EGraphBuilder,
  count : Int,
) -> Unit {
  if count <= 0 {
    return
  }
  while self.value_map.length() < count {
    self.value_map.push(None)
  }
  while self.def_map.length() < count {
    self.def_map.push(None)
  }
  while self.def_eop_map.length() < count {
    self.def_eop_map.push(None)
  }
}

///|
/// Register an instruction's definition
fn EGraphBuilder::register_def(self : EGraphBuilder, inst : Inst) -> Unit {
  if inst.first_result() is Some(v) {
    self.ensure_value_slot(v.id)
    self.def_map[v.id] = Some(inst)
    self.def_eop_map[v.id] = opcode_to_eopcode(inst)
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
    Ptr | Ref | CallableRef | OpaqueRef => 64 // Fixed by the MilkIR contract
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
    Scalar(IntConst(_)) => true
    Scalar(
      IntBinary(
        Add
        | Sub
        | Mul
        | And
        | Or
        | Xor
        | ShiftLeft
        | SignedShiftRight
        | UnsignedShiftRight
        | RotateLeft
        | RotateRight
      )
    ) => true
    Scalar(
      IntUnary(Not | CountLeadingZeros | CountTrailingZeros | PopulationCount)
    ) => true
    Scalar(IntCompare(_) | Select) => true
    Scalar(Convert(IntReduce | UnsignedExtend | SignedExtend)) => true
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
  !inst.opcode.semantics().must_preserve_if_unused() &&
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
    Scalar(IntConst(c)) => Some(Const(c))
    Scalar(IntBinary(Add)) => Some(Add)
    Scalar(IntBinary(Sub)) => Some(Sub)
    Scalar(IntBinary(Mul)) => Some(Mul)
    Scalar(IntBinary(And)) => Some(And)
    Scalar(IntBinary(Or)) => Some(Or)
    Scalar(IntBinary(Xor)) => Some(Xor)
    Scalar(IntUnary(Not)) => Some(Bnot)
    Scalar(IntBinary(ShiftLeft)) => Some(Shl)
    Scalar(IntBinary(SignedShiftRight)) => Some(Sshr)
    Scalar(IntBinary(UnsignedShiftRight)) => Some(Ushr)
    Scalar(IntBinary(RotateLeft)) => Some(Rotl)
    Scalar(IntBinary(RotateRight)) => Some(Rotr)
    Scalar(IntUnary(CountLeadingZeros)) => Some(Clz)
    Scalar(IntUnary(CountTrailingZeros)) => Some(Ctz)
    Scalar(IntUnary(PopulationCount)) => Some(Popcnt)
    Scalar(IntCompare(cc)) => Some(Icmp(intcc_to_ordinal(cc)))
    Scalar(Select) => Some(Select)
    Scalar(Convert(IntReduce)) => {
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
      Some(Ireduce(from_bits, to_bits))
    }
    Scalar(Convert(UnsignedExtend)) => {
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
      Some(Uextend(from_bits, to_bits))
    }
    Scalar(Convert(SignedExtend)) => {
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
      Some(Sextend(from_bits, to_bits))
    }
    _ => None // Not optimizable via e-graph
  }
}

///|
/// Look up the already-converted class for a value, if any.
fn EGraphBuilder::lookup_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId? {
  if value.id >= 0 &&
    value.id < self.value_map.length() &&
    self.value_map[value.id] is Some(id) {
    Some(self.egraph.find(id))
  } else {
    None
  }
}

///|
/// Add a leaf class (variable or constant) for a value that has no operands
/// to convert first.
fn EGraphBuilder::add_leaf_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId {
  let bits = type_bits(value.ty)
  let class_id = if value.id >= 0 &&
    value.id < self.def_map.length() &&
    self.def_map[value.id] is Some(_) &&
    self.def_eop_map[value.id] is Some(Const(c)) {
    self.egraph.add_const(c)
  } else {
    self.egraph.add_var(value.id)
  }
  self.egraph.set_type(class_id, bits)
  class_id
}

///|
/// Whether a value's definition contributes operand children to the e-graph.
fn EGraphBuilder::value_has_children(
  self : EGraphBuilder,
  value : Value,
) -> Bool {
  value.id >= 0 &&
  value.id < self.def_map.length() &&
  self.def_map[value.id] is Some(_) &&
  self.def_eop_map[value.id] is Some(eop) &&
  !(eop is Const(_))
}

///|
/// Add an IR value to the e-graph, converting its operand chain first.
///
/// Operand chains are walked with an explicit stack: a value is pushed once
/// to request its children and revisited once they are all converted, so a
/// long dependency chain costs heap rather than native stack (ISS-380).
fn EGraphBuilder::add_value(
  self : EGraphBuilder,
  value : Value,
) -> @egraph.EClassId {
  if self.lookup_value(value) is Some(id) {
    return id
  }
  // Each frame is (value, expanded): `expanded` marks the revisit after the
  // frame's operands have been pushed.
  let stack : Array[(Value, Bool)] = [(value, false)]
  while stack.pop() is Some((current, expanded)) {
    if self.lookup_value(current) is Some(_) {
      continue
    }
    if !self.value_has_children(current) {
      let class_id = self.add_leaf_value(current)
      self.ensure_value_slot(current.id)
      self.value_map[current.id] = Some(class_id)
      continue
    }
    guard self.def_map[current.id] is Some(inst) else { continue }
    guard self.def_eop_map[current.id] is Some(eop) else { continue }
    if expanded {
      let children : Array[@egraph.EClassId] = []
      for operand in inst.operands {
        // Operands are converted by now; a self-referential operand (only
        // reachable through malformed IR) falls back to a variable leaf.
        match self.lookup_value(operand) {
          Some(child) => children.push(child)
          None => children.push(self.add_leaf_value(operand))
        }
      }
      let class_id = self.egraph.add_typed(
        { op: eop, children },
        type_bits(current.ty),
      )
      self.ensure_value_slot(current.id)
      self.value_map[current.id] = Some(class_id)
    } else {
      stack.push((current, true))
      for operand in inst.operands {
        if self.lookup_value(operand) is None {
          stack.push((operand, false))
        }
      }
    }
  }
  match self.lookup_value(value) {
    Some(id) => id
    // Unreachable for well-formed IR; keep the conversion total.
    None => self.add_leaf_value(value)
  }
}

///|
/// Run optimization on the e-graph
/// With eager optimization, this only needs to rebuild to restore invariants
fn EGraphBuilder::optimize(self : EGraphBuilder) -> Unit {
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
fn EGraphBuilder::get_egraph(self : EGraphBuilder) -> @egraph.EGraph {
  self.egraph
}

///|
/// Check if the value's e-class folded to an integer constant.
/// Returns Some(Iconst(c)) if constant folding found, None otherwise.
/// NOTE: Only handles constant folding. Complex rewrites (like x*3 -> (x<<1)+x)
/// are not handled because they would require operand reconstruction (ISS-377).
/// The class's cached constant answers this in O(1); a constant node costs 0
/// and wins every extraction tie, so this matches what full extraction chose.
fn EGraphBuilder::get_simplified_opcode(
  self : EGraphBuilder,
  value : Value,
) -> Opcode? {
  if value.id >= 0 &&
    value.id < self.value_map.length() &&
    self.value_map[value.id] is Some(class_id) {
    match self.egraph.get_const(class_id) {
      Some(c) => Some(Scalar(IntConst(c)))
      None => None
    }
  } else {
    None
  }
}

///|
/// Get the simplified value for an operand (for operand rewriting)
/// If the operand's e-class has a simpler representation that maps to
/// an existing IR value, return that value; otherwise return None.
fn EGraphBuilder::get_simplified_operand(
  self : EGraphBuilder,
  value : Value,
) -> Value? {
  if value.id >= 0 &&
    value.id < self.value_map.length() &&
    self.value_map[value.id] is Some(class_id) {
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
  } else {
    None
  }
}

///|
fn build_block_index(func : Function) -> Map[Int, Int] {
  let index : Map[Int, Int] = Map([])
  for i, block in func.blocks {
    index.set(block.id, i)
  }
  index
}

///|
/// Apply e-graph optimization to a function
/// Returns true if any optimization was applied
priv struct EGraphOptimizeStats {
  changed : Bool
  total_classes : Int
  total_nodes : Int
  total_rule_applications : Int
}

///|
fn optimize_function_with_stats_with_limits_and_ruleset(
  func : Function,
  limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
) -> EGraphOptimizeStats {
  let mut changed = false
  let builder = EGraphBuilder::new_with_limits_and_ruleset(limits, ruleset)
  builder.reserve_value_slots(func.next_value_id)

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
      if inst.first_result() is Some(v) &&
        v.id >= 0 &&
        v.id < builder.def_eop_map.length() &&
        builder.def_eop_map[v.id] is Some(_) {
        builder.add_value(v) |> ignore
      }
    }
  }

  // Run one saturation pass on the function-wide e-graph.
  builder.optimize()
  let egraph = builder.get_egraph()
  // Extraction results are shared by every elaboration site, so the fixpoint
  // runs once here rather than per value.
  let best_nodes = egraph.best_nodes()
  let total_classes = egraph.num_classes()
  let total_nodes = egraph.num_nodes()
  let total_rule_applications = egraph.last_rule_applications()

  // Rewrite blocks with scoped representatives along the dominator tree.
  // This mirrors Cranelift's ScopedHashMap elaboration direction: each block
  // sees dominating representatives, can refine them locally, and restores on
  // scope exit.
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  let block_idx = build_block_index(func)

  // The dominator tree is walked with an explicit event stack rather than
  // native recursion, so a deep block chain costs heap (ISS-380). Enter
  // events rewrite a block and push its children; the matching exit event
  // restores the bindings that block introduced.
  fn rewrite_dominator_tree(root : Int) -> Unit {
    let stack : Array[DomWalkEvent] = [Enter(root)]
    while stack.pop() is Some(event) {
      match event {
        Exit(scoped_entries) =>
          for entry in scoped_entries.rev_iter() {
            let (key, previous) = entry
            match previous {
              Some(value) => builder.class_to_value.set(key, value)
              None => builder.class_to_value.remove(key)
            }
          }
        Enter(block_id) => {
          guard block_idx.get(block_id) is Some(idx) else { continue }
          let block = func.blocks[idx]
          let scoped_entries : Array[(RepKey, Value?)] = []

          fn bind_rep(builder : EGraphBuilder, value : Value) -> Unit {
            if value.id >= 0 &&
              value.id < builder.value_map.length() &&
              builder.value_map[value.id] is Some(class_id) {
              let canonical = builder.egraph.find(class_id)
              let key : RepKey = { class_id: canonical.0, ty: value.ty }
              let previous = builder.class_to_value.get(key)
              let should_bind = previous is None
              if should_bind {
                scoped_entries.push((key, previous))
                builder.class_to_value.set(key, value)
              }
            }
          }

          for pair in block.params {
            let (param, _) = pair
            bind_rep(builder, param)
          }

          // Apply optimizations: constant folding, operand rewriting, and
          // elaboration. Elaborated instructions are spliced in ahead of the
          // instruction that needed them, so the block is rebuilt rather
          // than mutated in place.
          let rewritten : Array[Inst] = []
          for inst in block.instructions {
            for operand in inst.operands {
              bind_rep(builder, operand)
            }
            for i in 0..<inst.operands.length() {
              let operand = inst.operands[i]
              if builder.get_simplified_operand(operand) is Some(simplified) {
                inst.operands[i] = simplified
                changed = true
              }
            }

            if inst.first_result() is Some(v) &&
              builder.get_simplified_opcode(v) is Some(op) {
              if op is Scalar(IntConst(c)) {
                let mut inst_changed = false
                match inst.opcode {
                  Scalar(IntConst(old_c)) =>
                    if old_c != c || inst.operands.length() > 0 {
                      inst.opcode = Scalar(IntConst(c))
                      inst.operands.clear()
                      inst_changed = true
                    }
                  _ => {
                    inst.opcode = Scalar(IntConst(c))
                    inst.operands.clear()
                    inst_changed = true
                  }
                }
                if inst_changed {
                  changed = true
                }
              } else if inst.opcode != op {
                inst.opcode = op
                changed = true
              }
            } else {
              // Elaboration may prepend instructions that build the operands
              // the rewritten form needs; those dominate every later use.
              let before = rewritten.length()
              if builder.elaborate_inst(func, best_nodes, inst, rewritten) {
                changed = true
              }
              for i in before..<rewritten.length() {
                if rewritten[i].first_result() is Some(v) {
                  bind_rep(builder, v)
                }
              }
            }

            rewritten.push(inst)
            if inst.first_result() is Some(v) {
              bind_rep(builder, v)
            }
          }
          block.instructions.clear()
          for inst in rewritten {
            block.instructions.push(inst)
          }

          // Exit runs after every child, so push it first.
          stack.push(Exit(scoped_entries))
          if block_id < domtree.length() {
            for child in domtree[block_id] {
              stack.push(Enter(child))
            }
          }
        }
      }
    }
  }

  if cfg.is_valid(0) {
    builder.class_to_value.clear()
    rewrite_dominator_tree(0)
  }
  { changed, total_classes, total_nodes, total_rule_applications }
}
