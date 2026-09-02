// EGraph IR Integration - converts IR to/from EGraph
// ============================================================================
// IR Integration - Convert IR instructions to/from EGraph
// ============================================================================

///|
/// Builder for constructing an EGraph from IR instructions
priv struct EGraphBuilder {
  egraph : @egraph.EGraph
  // Region-local maps stay sparse: global Value ids can be arbitrarily large
  // even when this transient graph contains only a few dozen expressions.
  value_map : Map[Int, @egraph.EClassId]
  // Reverse map from (canonical EClassId, Type) to an in-scope IR Value (for operand rewriting)
  class_to_value : Map[RepKey, Value]
  // Region-local definition and encoding maps.
  def_map : Map[Int, Inst]
  def_eop_map : Map[Int, @egraph.EOpcode]
  // Ruleset for eager optimization
  ruleset : @egraph.IndexedRuleSet
  // Rewrite limits (Cranelift-style hard caps).
  saturation_limits : @egraph.SaturationLimits
  mut saturation_budget : @egraph.SaturationBudget
  mut extraction_work_budget : Int
  mut remaining_elaboration_budget : Int
  mut elaborated_instructions : Int
  mut elaboration_budget_exhausted : Bool
  // Constants are cheap leaves even when their defining instruction belongs
  // to an earlier region. Other out-of-region definitions stay opaque Vars.
  mut external_constants : Map[Int, Int64]
}

///|
/// Aggregate work limits for one transient pure-expression region.
///
/// The e-graph is a separate representation from MilkIR, unlike Cranelift's
/// DFG-backed aegraph. Keeping it regional prevents large functions from
/// paying for a second whole-function object graph while still giving every
/// part of the function an optimization opportunity.
priv struct EGraphWorkLimits {
  pure_values_per_region : Int
  block_slices_per_region : Int
  context_pure_values_per_slice : Int
  saturation_budget : @egraph.SaturationBudget
  extraction_work_per_region : Int
  elaboration_instructions_per_region : Int
}

///|
fn default_egraph_work_limits() -> EGraphWorkLimits {
  {
    pure_values_per_region: 128,
    block_slices_per_region: 32,
    // Match the bounded rewrite depth used by Cranelift's aegraph design.
    context_pure_values_per_slice: 5,
    saturation_budget: SaturationBudget(1024, 8192, 512),
    extraction_work_per_region: 8192,
    elaboration_instructions_per_region: 128,
  }
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
fn EGraphBuilder::new_with_limits_and_ruleset(
  saturation_limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
) -> EGraphBuilder {
  let work_limits = default_egraph_work_limits()
  {
    egraph: EGraph(),
    value_map: Map([]),
    class_to_value: Map([]),
    def_map: Map([]),
    def_eop_map: Map([]),
    ruleset,
    saturation_limits,
    saturation_budget: work_limits.saturation_budget,
    extraction_work_budget: work_limits.extraction_work_per_region,
    remaining_elaboration_budget: work_limits.elaboration_instructions_per_region,
    elaborated_instructions: 0,
    elaboration_budget_exhausted: false,
    external_constants: Map([]),
  }
}

///|
fn EGraphBuilder::new_for_region(
  saturation_limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
  work_limits : EGraphWorkLimits,
  external_constants : Map[Int, Int64],
) -> EGraphBuilder {
  let builder = EGraphBuilder::new_with_limits_and_ruleset(
    saturation_limits, ruleset,
  )
  builder.saturation_budget = work_limits.saturation_budget
  builder.extraction_work_budget = work_limits.extraction_work_per_region
  builder.remaining_elaboration_budget = work_limits.elaboration_instructions_per_region
  builder.external_constants = external_constants
  builder
}

///|
/// Register an instruction's definition
fn EGraphBuilder::register_def(self : EGraphBuilder, inst : Inst) -> Unit {
  if inst.first_result() is Some(v) {
    self.def_map.set(v.id, inst)
    match opcode_to_eopcode(inst) {
      Some(eop) => self.def_eop_map.set(v.id, eop)
      None => self.def_eop_map.remove(v.id)
    }
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
  if self.value_map.get(value.id) is Some(id) {
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
  let class_id = if self.def_eop_map.get(value.id) is Some(Const(c)) {
    self.egraph.add_const(c)
  } else if self.external_constants.get(value.id) is Some(c) {
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
  self.def_map.get(value.id) is Some(_) &&
  self.def_eop_map.get(value.id) is Some(eop) &&
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
  stack : Array[(Value, Bool)],
) -> @egraph.EClassId {
  if self.lookup_value(value) is Some(id) {
    return id
  }
  // Each frame is (value, expanded): `expanded` marks the revisit after the
  // frame's operands have been pushed.
  stack.clear()
  stack.push((value, false))
  while stack.pop() is Some((current, expanded)) {
    if self.lookup_value(current) is Some(_) {
      continue
    }
    if !self.value_has_children(current) {
      let class_id = self.add_leaf_value(current)
      self.value_map.set(current.id, class_id)
      continue
    }
    guard self.def_map.get(current.id) is Some(inst) else { continue }
    guard self.def_eop_map.get(current.id) is Some(eop) else { continue }
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
        { op: eop, children, },
        type_bits(current.ty),
      )
      self.value_map.set(current.id, class_id)
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
  self.egraph.saturate_indexed_with_budget(
    self.ruleset,
    1,
    self.saturation_limits,
    self.saturation_budget,
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
  if self.value_map.get(value.id) is Some(class_id) {
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
  if self.is_cheap_rematerializable(value) {
    return None
  }
  if self.value_map.get(value.id) is Some(class_id) {
    // Get the canonical class after optimization
    let canonical = self.egraph.find(class_id)
    // Check if this class maps to a different (simpler) value with same IR type
    let key : RepKey = { class_id: canonical.0, ty: value.ty, }
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
fn EGraphBuilder::is_cheap_rematerializable(
  self : EGraphBuilder,
  value : Value,
) -> Bool {
  match self.def_map.get(value.id) {
    Some(inst) => {
      if is_cheap_rematerializable_constant(inst) {
        return true
      }
      match (inst.opcode, inst.operands) {
        (Scalar(Convert(UnsignedExtend)), [source]) =>
          self.def_map.get(source.id) is Some(source_inst) &&
          is_cheap_rematerializable_constant(source_inst)
        _ => false
      }
    }
    // An out-of-region constant is still a cheap leaf. Treating all such
    // constants as rematerializable is conservative for register pressure.
    None => self.external_constants.get(value.id) is Some(_)
  }
}

///|
/// Apply e-graph optimization to a function
/// Returns true if any optimization was applied
priv struct EGraphOptimizeStats {
  changed : Bool
  total_classes : Int
  total_nodes : Int
  total_rule_applications : Int
  total_rule_attempts : Int
  total_extraction_work : Int
  total_elaborated_instructions : Int
  regions : Int
  peak_nodes : Int
  budget_exhausted : Bool
}

///|
fn empty_egraph_optimize_stats() -> EGraphOptimizeStats {
  {
    changed: false,
    total_classes: 0,
    total_nodes: 0,
    total_rule_applications: 0,
    total_rule_attempts: 0,
    total_extraction_work: 0,
    total_elaborated_instructions: 0,
    regions: 0,
    peak_nodes: 0,
    budget_exhausted: false,
  }
}

///|
fn merge_egraph_optimize_stats(
  left : EGraphOptimizeStats,
  right : EGraphOptimizeStats,
) -> EGraphOptimizeStats {
  {
    changed: left.changed || right.changed,
    total_classes: left.total_classes + right.total_classes,
    total_nodes: left.total_nodes + right.total_nodes,
    total_rule_applications: left.total_rule_applications +
    right.total_rule_applications,
    total_rule_attempts: left.total_rule_attempts + right.total_rule_attempts,
    total_extraction_work: left.total_extraction_work +
    right.total_extraction_work,
    total_elaborated_instructions: left.total_elaborated_instructions +
    right.total_elaborated_instructions,
    regions: left.regions + right.regions,
    peak_nodes: if left.peak_nodes > right.peak_nodes {
      left.peak_nodes
    } else {
      right.peak_nodes
    },
    budget_exhausted: left.budget_exhausted || right.budget_exhausted,
  }
}

///|
priv struct EGraphRegionSlice {
  block : Block
  output_index : Int
  instructions : Array[Inst]
  context_start : Int
  start : Int
  end : Int
  rewritten : Array[Inst]
  completes_block : Bool
}

///|
/// Include a small read-only pure-expression window before a split point.
/// This preserves local rewrites that straddle an artificial region boundary
/// without recursively importing an unbounded producer chain.
fn egraph_region_context_start(
  instructions : Array[Inst],
  start : Int,
  pure_values : Int,
) -> Int {
  let mut index = start
  let mut remaining = pure_values
  while index > 0 && remaining > 0 {
    index = index - 1
    if inst_is_egraph_pure(instructions[index]) {
      remaining = remaining - 1
    }
  }
  index
}

///|
fn prepare_egraph_rewrite_with_stats_with_limits_and_ruleset(
  func : Function,
  limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
  on_block_ready : (Block, Array[Inst]) -> Unit,
) -> EGraphOptimizeStats {
  let work_limits = default_egraph_work_limits()
  let external_constants : Map[Int, Int64] = Map([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Scalar(IntConst(c)) && inst.first_result() is Some(v) {
        external_constants.set(v.id, c)
      }
    }
  }
  let mut aggregate = empty_egraph_optimize_stats()
  let pending : Array[EGraphRegionSlice] = []
  let rewritten_blocks : Array[(Block, Array[Inst])] = []
  let ready : Array[Bool] = []
  let next_ready : Ref[Int] = { val: 0, }
  let mut pending_pure_values = 0
  fn drain_ready() -> Unit {
    while next_ready.val < ready.length() && ready[next_ready.val] {
      let (block, rewritten) = rewritten_blocks[next_ready.val]
      on_block_ready(block, rewritten)
      next_ready.val = next_ready.val + 1
    }
  }
  fn finish_region() -> Unit {
    let stats = optimize_egraph_region(
      func, pending, limits, ruleset, work_limits, external_constants,
    )
    aggregate = merge_egraph_optimize_stats(aggregate, stats)
    for slice in pending {
      if slice.completes_block {
        ready[slice.output_index] = true
      }
    }
    pending.clear()
    pending_pure_values = 0
    drain_ready()
  }
  for block in func.blocks {
    let original = block.instructions
    let rewritten : Array[Inst] = []
    let output_index = rewritten_blocks.length()
    rewritten_blocks.push((block, rewritten))
    ready.push(false)
    let mut region_start = 0
    for index in 0..<original.length() {
      if inst_is_egraph_pure(original[index]) {
        pending_pure_values = pending_pure_values + 1
      }
      if pending_pure_values >= work_limits.pure_values_per_region {
        pending.push({
          block,
          output_index,
          instructions: original,
          context_start: egraph_region_context_start(
            original,
            region_start,
            work_limits.context_pure_values_per_slice,
          ),
          start: region_start,
          end: index + 1,
          rewritten,
          completes_block: index + 1 == original.length(),
        })
        finish_region()
        region_start = index + 1
      }
    }
    if region_start < original.length() {
      if pending_pure_values > 0 {
        pending.push({
          block,
          output_index,
          instructions: original,
          context_start: egraph_region_context_start(
            original,
            region_start,
            work_limits.context_pure_values_per_slice,
          ),
          start: region_start,
          end: original.length(),
          rewritten,
          completes_block: true,
        })
      } else {
        for index in region_start..<original.length() {
          rewritten.push(original[index])
        }
        ready[output_index] = true
        drain_ready()
      }
    } else {
      ready[output_index] = true
      drain_ready()
    }
    if pending.length() >= work_limits.block_slices_per_region {
      finish_region()
    }
  }
  if !pending.is_empty() {
    finish_region()
  }
  drain_ready()
  aggregate
}

///|
#warnings("-unused_value")
fn optimize_function_with_stats_with_limits_and_ruleset(
  func : Function,
  limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
  analysis : FunctionAnalysis,
) -> EGraphOptimizeStats {
  analysis |> ignore
  prepare_egraph_rewrite_with_stats_with_limits_and_ruleset(
    func,
    limits,
    ruleset,
    fn(block, rewritten) { block.instructions = rewritten },
  )
}

///|
fn optimize_function_and_gvn_with_stats(
  func : Function,
  limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
  analysis : FunctionAnalysis,
) -> (EGraphOptimizeStats, GVNStats) {
  let original_block_instructions = fn(block_id : Int) -> Array[Inst] {
    func.blocks[analysis.block_idx[block_id]].instructions
  }
  let original_count = instruction_count(func)
  let memory_budget = if original_count > 300 { 300 } else { 2147483647 }
  let stream = StreamingGVN::new(
    func, memory_budget, analysis, original_block_instructions,
  )
  let dom_order : Array[Int] = []
  fn collect_block(block_id : Int) -> (Unit, Bool) {
    dom_order.push(block_id)
    ((), true)
  }
  if analysis.cfg.is_valid(0) {
    visit_dominator_tree(analysis.domtree, 0, collect_block, fn(_) { () })
  }
  let prepared : Array[Array[Inst]?] = Array::make(func.next_block_id, None)
  let dom_cursor : Ref[Int] = { val: 0, }
  fn drain_dominator_order() -> Unit {
    while dom_cursor.val < dom_order.length() {
      let block_id = dom_order[dom_cursor.val]
      guard prepared[block_id] is Some(rewritten) else { break }
      stream.process_block(block_id, rewritten)
      func.blocks[analysis.block_idx[block_id]].instructions = rewritten
      prepared[block_id] = None
      dom_cursor.val = dom_cursor.val + 1
    }
  }
  let egraph_stats = prepare_egraph_rewrite_with_stats_with_limits_and_ruleset(
    func,
    limits,
    ruleset,
    fn(block, rewritten) {
      if analysis.dominance.preorder[block.id] >= 0 {
        prepared[block.id] = Some(rewritten)
        drain_dominator_order()
      } else {
        block.instructions = rewritten
      }
    },
  )
  drain_dominator_order()
  (egraph_stats, stream.finish())
}

///|
/// Optimize one bounded region spanning one or more block slices. Definitions
/// outside the region are opaque leaves, except constants, so construction
/// can never recursively pull the rest of a large function into this graph.
fn optimize_egraph_region(
  func : Function,
  slices : Array[EGraphRegionSlice],
  limits : @egraph.SaturationLimits,
  ruleset : @egraph.IndexedRuleSet,
  work_limits : EGraphWorkLimits,
  external_constants : Map[Int, Int64],
) -> EGraphOptimizeStats {
  let builder = EGraphBuilder::new_for_region(
    limits, ruleset, work_limits, external_constants,
  )
  for slice in slices {
    for index in slice.context_start..<slice.end {
      builder.register_def(slice.instructions[index])
    }
  }
  let value_stack : Array[(Value, Bool)] = []
  for slice in slices {
    for index in slice.context_start..<slice.end {
      let inst = slice.instructions[index]
      if inst.first_result() is Some(v) &&
        builder.def_eop_map.get(v.id) is Some(_) {
        builder.add_value(v, value_stack) |> ignore
      }
    }
  }
  builder.optimize()
  let egraph = builder.get_egraph()
  let best_nodes = egraph.best_nodes_with_budget(builder.extraction_work_budget)
  let nodes = egraph.num_nodes()
  let mut changed = false

  fn bind_rep(value : Value) -> Unit {
    if builder.is_cheap_rematerializable(value) {
      return
    }
    if builder.value_map.get(value.id) is Some(class_id) {
      let canonical = builder.egraph.find(class_id)
      let key : RepKey = { class_id: canonical.0, ty: value.ty, }
      if builder.class_to_value.get(key) is None {
        builder.class_to_value.set(key, value)
      }
    }
  }

  for slice in slices {
    // Never carry a representative from one block into another. The graph may
    // span sibling blocks for amortization, but reuse remains dominance-safe.
    builder.class_to_value.clear()
    for pair in slice.block.params {
      let (param, _) = pair
      bind_rep(param)
    }
    // Read-only context instructions precede this slice in the same block, so
    // their operands and results dominate every rewritten instruction here.
    // Bind them without rewriting or emitting them a second time.
    for index in slice.context_start..<slice.start {
      let context_inst = slice.instructions[index]
      for operand in context_inst.operands {
        bind_rep(operand)
      }
      if context_inst.first_result() is Some(result) {
        bind_rep(result)
      }
    }
    for index in slice.start..<slice.end {
      let inst = slice.instructions[index]
      for operand in inst.operands {
        bind_rep(operand)
      }
      for operand_index in 0..<inst.operands.length() {
        let operand = inst.operands[operand_index]
        if builder.get_simplified_operand(operand) is Some(simplified) {
          inst.operands[operand_index] = simplified
          changed = true
        }
      }
      if inst.first_result() is Some(v) &&
        builder.get_simplified_opcode(v) is Some(op) {
        if op is Scalar(IntConst(c)) {
          match inst.opcode {
            Scalar(IntConst(old_c)) =>
              if old_c != c || !inst.operands.is_empty() {
                inst.opcode = Scalar(IntConst(c))
                inst.operands.clear()
                changed = true
              }
            _ => {
              inst.opcode = Scalar(IntConst(c))
              inst.operands.clear()
              changed = true
            }
          }
        } else if inst.opcode != op {
          inst.opcode = op
          changed = true
        }
      } else {
        let before = slice.rewritten.length()
        if builder.elaborate_inst(func, best_nodes, inst, slice.rewritten) {
          changed = true
        }
        for emitted_index in before..<slice.rewritten.length() {
          if slice.rewritten[emitted_index].first_result() is Some(v) {
            bind_rep(v)
          }
        }
      }
      slice.rewritten.push(inst)
      if inst.first_result() is Some(v) {
        builder.register_def(inst)
        bind_rep(v)
      }
    }
  }
  {
    changed,
    total_classes: egraph.num_classes(),
    total_nodes: nodes,
    total_rule_applications: egraph.last_rule_applications(),
    total_rule_attempts: egraph.last_rule_attempts(),
    total_extraction_work: egraph.last_extraction_work(),
    total_elaborated_instructions: builder.elaborated_instructions,
    regions: 1,
    peak_nodes: nodes,
    budget_exhausted: egraph.last_saturation_budget_exhausted() ||
    egraph.last_extraction_budget_exhausted() ||
    builder.elaboration_budget_exhausted,
  }
}
