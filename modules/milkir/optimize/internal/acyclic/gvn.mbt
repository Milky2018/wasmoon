// ============ Global Value Numbering with Load CSE ============

///|
priv struct PtrAccess {
  base_id : Int32
  offset_id : Int32
  region : @milkir.AliasRegion
}

///|
priv struct PtrLocationKey {
  base_id : Int32
  offset_id : Int32
  region : @milkir.AliasRegion
} derive(Eq, Hash)

///|
priv struct StoreVersion {
  block_id : Int32
  inst_id : Int32
} derive(Eq, Hash)

///|
priv struct LastStoreState {
  mut heap : @hashmap.HashMap[Int32, StoreVersion]
  mut heap_default : StoreVersion?
  mut table : @hashmap.HashMap[Int32, StoreVersion]
  mut table_default : StoreVersion?
  mut context : StoreVersion?
  mut other : StoreVersion?
}

///|
priv enum MemoryWriteScope {
  NoWrite
  WriteRegion(@milkir.AliasRegion)
  WriteAll
}

///|
priv struct MemoryValueKey {
  last_store : StoreVersion?
  location : PtrLocationKey
  ty : @milkir.Type
} derive(Eq, Hash)

///|
priv struct MemoryValueEntry {
  def_block_id : Int32
  def_inst_index : Int32
  value : @milkir.Value
}

///|
fn PtrAccess::location_key(self : PtrAccess) -> PtrLocationKey {
  { base_id: self.base_id, offset_id: self.offset_id, region: self.region, }
}

///|
fn LastStoreState::LastStoreState() -> LastStoreState {
  {
    heap: HashMap([]),
    heap_default: None,
    table: HashMap([]),
    table_default: None,
    context: None,
    other: None,
  }
}

///|
fn LastStoreState::clone(self : LastStoreState) -> LastStoreState {
  let heap : @hashmap.HashMap[Int32, StoreVersion] = HashMap([])
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    heap.set(memidx, token)
  }
  let table : @hashmap.HashMap[Int32, StoreVersion] = HashMap([])
  for entry in self.table.iter() {
    let (tableidx, token) = entry
    table.set(tableidx, token)
  }
  {
    heap,
    heap_default: self.heap_default,
    table,
    table_default: self.table_default,
    context: self.context,
    other: self.other,
  }
}

///|
fn indexed_store_maps_equal(
  left : @hashmap.HashMap[Int32, StoreVersion],
  right : @hashmap.HashMap[Int32, StoreVersion],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for entry in left.iter() {
    if right.get(entry.0) != Some(entry.1) {
      return false
    }
  }
  true
}

///|
fn meet_last_store_token(
  a : StoreVersion?,
  b : StoreVersion?,
  join_token : StoreVersion,
) -> StoreVersion? {
  match (a, b) {
    (None, None) => None
    // None is the initial memory version, not an unvisited predecessor.
    // In a loop, treating it as bottom equates a call from the previous
    // iteration with the same static call executed again in this iteration.
    (Some(_), None) | (None, Some(_)) => Some(join_token)
    (Some(lhs), Some(rhs)) =>
      if lhs == rhs {
        Some(lhs)
      } else {
        Some(join_token)
      }
  }
}

///|
fn indexed_store_token(
  entries : @hashmap.HashMap[Int32, StoreVersion],
  default : StoreVersion?,
  index : Int32,
) -> StoreVersion? {
  match entries.get(index) {
    Some(token) => Some(token)
    None => default
  }
}

///|
fn meet_indexed_store_maps(
  left : @hashmap.HashMap[Int32, StoreVersion],
  left_default : StoreVersion?,
  right : @hashmap.HashMap[Int32, StoreVersion],
  right_default : StoreVersion?,
  merged_default : StoreVersion?,
  join_token : StoreVersion,
) -> @hashmap.HashMap[Int32, StoreVersion] {
  let merged : @hashmap.HashMap[Int32, StoreVersion] = HashMap([])
  for entry in left.iter() {
    let token = meet_last_store_token(
      Some(entry.1),
      indexed_store_token(right, right_default, entry.0),
      join_token,
    )
    if token is Some(value) && token != merged_default {
      merged.set(entry.0, value)
    }
  }
  for entry in right.iter() {
    if left.get(entry.0) is None {
      let token = meet_last_store_token(left_default, Some(entry.1), join_token)
      if token is Some(value) && token != merged_default {
        merged.set(entry.0, value)
      }
    }
  }
  merged
}

///|
fn LastStoreState::meet_from(
  self : LastStoreState,
  other : LastStoreState,
  join_token : StoreVersion,
) -> Bool {
  let context = meet_last_store_token(self.context, other.context, join_token)
  let other_token = meet_last_store_token(self.other, other.other, join_token)
  let heap_default = meet_last_store_token(
    self.heap_default,
    other.heap_default,
    join_token,
  )
  let merged_heap = meet_indexed_store_maps(
    self.heap,
    self.heap_default,
    other.heap,
    other.heap_default,
    heap_default,
    join_token,
  )
  let table_default = meet_last_store_token(
    self.table_default,
    other.table_default,
    join_token,
  )
  let merged_table = meet_indexed_store_maps(
    self.table,
    self.table_default,
    other.table,
    other.table_default,
    table_default,
    join_token,
  )
  let changed = context != self.context ||
    other_token != self.other ||
    heap_default != self.heap_default ||
    table_default != self.table_default ||
    !indexed_store_maps_equal(merged_heap, self.heap) ||
    !indexed_store_maps_equal(merged_table, self.table)
  self.context = context
  self.other = other_token
  self.heap_default = heap_default
  self.table_default = table_default
  self.heap = merged_heap
  self.table = merged_table
  changed
}

///|
fn LastStoreState::get_region_token(
  self : LastStoreState,
  region : @milkir.AliasRegion,
) -> StoreVersion? {
  match region {
    Heap(index) => indexed_store_token(self.heap, self.heap_default, index)
    Table(index) => indexed_store_token(self.table, self.table_default, index)
    Context => self.context
    Other => self.other
  }
}

///|
fn LastStoreState::set_region_token(
  self : LastStoreState,
  region : @milkir.AliasRegion,
  token : StoreVersion,
) -> Unit {
  // Unknown readers can alias every concrete region.
  self.other = Some(token)
  match region {
    Heap(index) => self.heap.set(index, token)
    Table(index) => self.table.set(index, token)
    Context => self.context = Some(token)
    Other => self.other = Some(token)
  }
}

///|
fn LastStoreState::set_all_tokens(
  self : LastStoreState,
  token : StoreVersion,
) -> Unit {
  self.heap.clear()
  self.heap_default = Some(token)
  self.table.clear()
  self.table_default = Some(token)
  self.context = Some(token)
  self.other = Some(token)
}

///|
fn instruction_memory_write_scope(
  inst : @milkir.Inst,
  ptr_base_infos : Array[@milkir.AliasRegion?],
) -> MemoryWriteScope {
  let is_store = match inst.opcode {
    Memory(Store(_) | StoreNarrow(_) | Vector(StoreLane(_, _))) => true
    _ => false
  }
  if is_store && ptr_access_from_inst(inst, ptr_base_infos) is Some(access) {
    return if access.region == Other {
      WriteAll
    } else {
      WriteRegion(access.region)
    }
  }
  if inst.opcode is Ext(extension, _) && extension.effects is Some(effects) {
    return match effects.write {
      Some(Other) => WriteAll
      Some(region) => WriteRegion(region)
      None => NoWrite
    }
  }
  if opcode_semantics(inst.opcode).memory.may_write_memory() {
    WriteAll
  } else {
    NoWrite
  }
}

///|
fn update_last_store_state(
  state : LastStoreState,
  inst : @milkir.Inst,
  inst_version : StoreVersion,
  ptr_base_infos : Array[@milkir.AliasRegion?],
) -> Unit {
  match instruction_memory_write_scope(inst, ptr_base_infos) {
    NoWrite => ()
    WriteRegion(region) => state.set_region_token(region, inst_version)
    WriteAll => state.set_all_tokens(inst_version)
  }
}

///|
fn compute_block_input_last_store_states(
  func : @milkir.Function,
  cfg : @milkir.CFG,
  block_idx : Array[Int32],
  ptr_base_infos : Array[@milkir.AliasRegion?],
  block_instructions : (Int32) -> ArrayView[@milkir.InstId],
) -> @hashmap.HashMap[Int32, LastStoreState] {
  let block_input : @hashmap.HashMap[Int32, LastStoreState] = HashMap([])
  if !cfg.is_valid(0) {
    return block_input
  }
  block_input.set(0, LastStoreState())
  let queue : Array[Int32] = [0]
  let queue_set : @hashset.HashSet[Int32] = HashSet([])
  queue_set.add(0)
  while queue.length() > 0 {
    let block_id = queue.pop().unwrap()
    queue_set.remove(block_id)
    let state = match block_input.get(block_id) {
      Some(existing) => existing.clone()
      None => LastStoreState()
    }
    for inst_id in block_instructions(block_id) {
      let inst = func.instruction_by_id(inst_id).unwrap()
      update_last_store_state(
        state,
        inst,
        { block_id, inst_id: inst.id, },
        ptr_base_infos,
      )
    }
    for succ in cfg.get_successors(block_id) {
      let succ_idx = block_idx[succ]
      let succ_block = func.blocks[succ_idx]
      let join_token = if succ_block.instruction_ids().length() > 0 {
        { block_id: succ, inst_id: -1, }
      } else {
        { block_id: succ, inst_id: -1, }
      }
      let updated = match block_input.get(succ) {
        Some(existing) => existing.meet_from(state, join_token)
        None => {
          block_input.set(succ, state.clone())
          true
        }
      }
      if updated && !queue_set.contains(succ) {
        queue.push(succ)
        queue_set.add(succ)
      }
    }
  }
  block_input
}

///|
fn gvn_instruction_prefix(
  func : @milkir.Function,
  work_budget : Int32,
  analysis : FunctionAnalysis,
  block_instructions : (Int32) -> ArrayView[@milkir.InstId],
) -> Array[@milkir.Inst] {
  let prefix : Array[@milkir.Inst] = []
  fn enter(block_id : Int32) -> (Unit, Bool) {
    if prefix.length() >= work_budget {
      return ((), false)
    }
    for inst_id in block_instructions(block_id) {
      if prefix.length() >= work_budget {
        break
      }
      prefix.push(func.instruction_by_id(inst_id).unwrap())
    }
    ((), prefix.length() < work_budget)
  }
  if analysis.cfg.is_valid(0) {
    @milkir.visit_dominator_tree(analysis.domtree, 0, enter, fn(_) { () })
  }
  prefix
}

///|
fn ptr_base_region(
  value_id : Int32,
  ptr_base_infos : Array[@milkir.AliasRegion?],
) -> @milkir.AliasRegion {
  if value_id >= 0 && value_id < ptr_base_infos.length() {
    match ptr_base_infos[value_id] {
      Some(region) => region
      None => Other
    }
  } else {
    // E-graph elaboration may introduce a value after pointer pre-analysis.
    // Unknown must stay conservative rather than indexing past the fact table.
    Other
  }
}

///|
fn ptr_access_from_inst(
  inst : @milkir.Inst,
  ptr_base_infos : Array[@milkir.AliasRegion?],
) -> PtrAccess? {
  match inst.opcode {
    Memory(Load(_)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = ptr_base_region(base.id, ptr_base_infos)
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(LoadNarrow(_, _, _)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = ptr_base_region(base.id, ptr_base_infos)
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(Store(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = ptr_base_region(base.id, ptr_base_infos)
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(StoreNarrow(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = ptr_base_region(base.id, ptr_base_infos)
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    _ => None
  }
}

///|
fn memory_key_from_access(
  access : PtrAccess,
  ty : @milkir.Type,
  last_store : StoreVersion?,
) -> MemoryValueKey {
  { last_store, location: access.location_key(), ty, }
}

///|
fn inst_dominates(
  def_block_id : Int32,
  def_inst_index : Int32,
  use_block_id : Int32,
  use_inst_index : Int32,
  dominance : @milkir.Dominance,
) -> Bool {
  if def_block_id == use_block_id {
    return def_inst_index < use_inst_index
  }
  dominance.dominates(def_block_id, use_block_id)
}

///|
/// Check if an instruction is suitable for GVN (can be CSE'd)
/// Trapping instructions and memory operations remain excluded. Load CSE is a
/// separate correctness change even though this pass tracks memory versions.
fn is_gvn_candidate(inst : @milkir.Inst) -> Bool {
  if inst.results.length() != 1 || is_cheap_rematerializable_constant(inst) {
    return false
  }
  if inst.opcode is Ext(extension, _) &&
    extension.effects is Some(effects) &&
    effects.read is Some(_) &&
    effects.write is None &&
    !effects.observable {
    // As with load CSE, the first dominating read performs its trap. Its
    // metadata version must remain unchanged before reusing its result.
    return true
  }
  opcode_semantics(inst.opcode).can_stage_as_pure_candidate()
}

///|
fn gvn_memory_dependency(
  func : @milkir.Function,
  inst : @milkir.Inst,
  ptr_base_infos : Array[@milkir.AliasRegion?],
) -> @milkir.AliasRegion? {
  match inst.opcode {
    Ext(extension, _) if extension.effects is Some(effects) => effects.read
    GlobalValue(global_value) =>
      match func.global_value_data(global_value) {
        Some(ContextField(_, Mutable, _)) => Some(Context)
        _ => None
      }
    _ =>
      if opcode_semantics(inst.opcode).memory.reads_memory() {
        match ptr_access_from_inst(inst, ptr_base_infos) {
          Some(access) => Some(access.region)
          None => Some(Other)
        }
      } else {
        None
      }
  }
}

///|
pub struct AcyclicOptimizeStats {
  changed : Bool
  work_done : Int32
  budget_exhausted : Bool
  value_lookup_probes : Int32
  rewrite_changed : Bool
  rewrite_attempts : Int32
  rewrite_applied : Int32
  rewrite_created_instructions : Int32
}

///|
/// One available expression in the insertion-time GVN table.
priv struct AvailableExpression {
  value : @milkir.Value
  dependency : @milkir.AliasRegion?
  memory_version : StoreVersion?
  def_block_id : Int32
  def_inst_index : Int32
  position : Int32
  reuse_count : Int32
}

///|
/// One reversible mutation of a scoped available-expression stack. The stack
/// object is recorded directly so rollback never has to hash a mutable `Inst`.
priv enum ValueTableChange {
  Inserted(Array[AvailableExpression])
  Updated(Array[AvailableExpression], Int32, AvailableExpression)
}

///|
priv struct AcyclicOptimizer {
  func : @milkir.Function
  analysis : FunctionAnalysis
  session : OptimizerSession
  memory_work_budget : Int32
  ptr_base_infos : Array[@milkir.AliasRegion?]
  block_input_state : @hashmap.HashMap[Int32, LastStoreState]
  value_table : @hashmap.HashMap[@milkir.Inst, Array[AvailableExpression]]
  value_table_changes : Array[ValueTableChange]
  memory_values : @hashmap.HashMap[MemoryValueKey, MemoryValueEntry]
  mut changed : Bool
  mut work_done : Int32
  mut budget_exhausted : Bool
  mut instruction_position : Int32
  mut value_lookup_probes : Int32
}

///|
/// Keep post-budget rematerializable context values inside short live ranges.
/// Extending one AEGIS memory-base value across the complete function adds
/// enough spill traffic to outweigh the eliminated loads.
const GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_DISTANCE : Int32 = 16

///|
const GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_LIMIT : Int32 = 1

///|
fn is_stable_global_value(func : @milkir.Function, inst : @milkir.Inst) -> Bool {
  match inst.opcode {
    GlobalValue(global_value) =>
      func.global_value_data(global_value) is Some(ContextField(_, Stable, _))
    _ => false
  }
}

///|
fn AcyclicOptimizer::new(
  func : @milkir.Function,
  work_budget : Int32,
  analysis : FunctionAnalysis,
  source_block_instructions : (Int32) -> ArrayView[@milkir.InstId],
) -> AcyclicOptimizer {
  let memory_work_budget = if work_budget > 0 { work_budget } else { 0 }
  let mut total_instructions = 0
  for block in func.blocks {
    total_instructions = total_instructions +
      source_block_instructions(block.id).length()
  }
  let complete_memory_analysis = total_instructions <= memory_work_budget
  let source = if complete_memory_analysis {
    let instructions : Array[@milkir.Inst] = []
    for block in func.blocks {
      for inst_id in source_block_instructions(block.id) {
        instructions.push(func.instruction_by_id(inst_id).unwrap())
      }
    }
    instructions
  } else {
    gvn_instruction_prefix(
      func, memory_work_budget, analysis, source_block_instructions,
    )
  }
  let ptr_base_infos = @analysis.pointer_regions(func, instructions=source)
  let block_input_state = if complete_memory_analysis {
    compute_block_input_last_store_states(
      func,
      analysis.cfg,
      analysis.block_idx,
      ptr_base_infos,
      source_block_instructions,
    )
  } else {
    HashMap([])
  }
  {
    func,
    analysis,
    session: OptimizerSession::new(func),
    memory_work_budget,
    ptr_base_infos,
    block_input_state,
    value_table: HashMap([]),
    value_table_changes: [],
    memory_values: HashMap([]),
    changed: false,
    work_done: 0,
    budget_exhausted: false,
    instruction_position: 0,
    value_lookup_probes: 0,
  }
}

///|
fn AcyclicOptimizer::begin_value_scope(self : AcyclicOptimizer) -> Int32 {
  self.value_table_changes.length()
}

///|
fn AcyclicOptimizer::end_value_scope(
  self : AcyclicOptimizer,
  marker : Int32,
) -> Unit {
  while self.value_table_changes.length() > marker {
    match self.value_table_changes.pop().unwrap() {
      Inserted(entries) => entries.pop() |> ignore
      Updated(entries, index, previous) => entries[index] = previous
    }
  }
}

///|
fn AcyclicOptimizer::insert_available_expression(
  self : AcyclicOptimizer,
  inst : @milkir.Inst,
  entry : AvailableExpression,
) -> Unit {
  let entries = match self.value_table.get(inst) {
    Some(entries) => entries
    None => {
      let entries : Array[AvailableExpression] = []
      self.value_table.set(inst, entries)
      entries
    }
  }
  entries.push(entry)
  self.value_table_changes.push(Inserted(entries))
}

///|
fn AcyclicOptimizer::process_block(
  self : AcyclicOptimizer,
  block_id : Int32,
  instructions : ArrayView[@milkir.InstId],
) -> Array[@milkir.Inst] {
  let last_store_state = match self.block_input_state.get(block_id) {
    Some(state) => state.clone()
    None => {
      // A missing predecessor analysis is an unknown entry version, not
      // evidence that predecessors preserved memory (including backedges).
      let state = LastStoreState()
      state.set_all_tokens({ block_id, inst_id: -1, })
      state
    }
  }
  let rewritten : Array[@milkir.Inst] = []
  for inst_id in instructions {
    let inst = self.func.instruction_by_id(inst_id).unwrap()
    let prefix : Array[@milkir.Inst] = []
    if self.session.rewrite_inst(inst, prefix) {
      self.changed = true
    }
    for created in prefix {
      self.process_inst(
        block_id,
        rewritten.length(),
        created,
        last_store_state,
        false,
      )
      rewritten.push(created)
    }
    if self.session.canonicalize_operands(inst) {
      self.changed = true
    }
    self.process_inst(
      block_id,
      rewritten.length(),
      inst,
      last_store_state,
      true,
    )
    rewritten.push(inst)
  }
  rewritten
}

///|
fn AcyclicOptimizer::process_inst(
  self : AcyclicOptimizer,
  block_id : Int32,
  inst_index : Int32,
  inst : @milkir.Inst,
  last_store_state : LastStoreState,
  charge_memory_work : Bool,
) -> Unit {
  let position = self.instruction_position
  self.instruction_position = position + 1
  let within_memory_budget = if charge_memory_work {
    if self.work_done < self.memory_work_budget {
      self.work_done = self.work_done + 1
      true
    } else {
      self.budget_exhausted = true
      false
    }
  } else {
    // Direct rewrites create only pure helper instructions. They participate
    // in value numbering but must not consume the source IR's memory-analysis
    // budget or move a later source load outside the analyzed prefix.
    true
  }
  let mut replaced_by_memory = false
  if within_memory_budget &&
    inst.opcode is Memory(Load(load_ty)) &&
    ptr_access_from_inst(inst, self.ptr_base_infos) is Some(load_access) {
    let key = memory_key_from_access(
      load_access,
      load_ty,
      last_store_state.get_region_token(load_access.region),
    )
    if self.memory_values.get(key) is Some(entry) &&
      inst_dominates(
        entry.def_block_id,
        entry.def_inst_index,
        block_id,
        inst_index,
        self.analysis.dominance,
      ) {
      inst.set_opcode(Scalar(Copy))
      inst.operands.clear()
      inst.operands.push(entry.value)
      if inst.first_result() is Some(result) {
        self.session.record_alias(result, entry.value)
      }
      self.changed = true
      replaced_by_memory = true
    } else if inst.first_result() is Some(value) {
      // The dominating read already performed its trap. Reuse only while the
      // same alias-region version survives, never by speculating a first read.
      self.memory_values.set(key, {
        def_block_id: block_id,
        def_inst_index: inst_index,
        value,
      })
    }
  }
  if within_memory_budget &&
    inst.opcode is Memory(Store(store_ty)) &&
    ptr_access_from_inst(inst, self.ptr_base_infos) is Some(store_access) &&
    inst.operands.length() >= 2 {
    let key = memory_key_from_access(
      store_access,
      store_ty,
      Some({ block_id, inst_id: inst.id, }),
    )
    self.memory_values.set(key, {
      def_block_id: block_id,
      def_inst_index: inst_index,
      value: inst.operands[1],
    })
  }
  // Memory forwarding is budgeted, but dependency versioning is not: an
  // effect after the precision budget must still prevent reusing a mutable
  // context/global expression across that effect.
  update_last_store_state(
    last_store_state,
    inst,
    { block_id, inst_id: inst.id, },
    self.ptr_base_infos,
  )
  if replaced_by_memory || !is_gvn_candidate(inst) {
    self.session.record_definition(inst)
    return
  }
  guard inst.first_result() is Some(result_val) else { return }
  let dependency = gvn_memory_dependency(self.func, inst, self.ptr_base_infos)
  let memory_version = match dependency {
    Some(region) => last_store_state.get_region_token(region)
    None => None
  }
  let bounded_stable_global = !within_memory_budget &&
    is_stable_global_value(self.func, inst)
  let mut reusable_entries : Array[AvailableExpression]? = None
  let mut reusable_index = -1
  if self.value_table.get(inst) is Some(entries) && !entries.is_empty() {
    // Dominator-scoped rollback guarantees that the last entry is the nearest
    // definition on the current dominance path. If its memory version differs,
    // every older entry precedes the same invalidating effect and is stale too.
    let index = entries.length() - 1
    let entry = entries[index]
    self.value_lookup_probes = self.value_lookup_probes + 1
    if entry.dependency == dependency &&
      entry.memory_version == memory_version &&
      inst_dominates(
        entry.def_block_id,
        entry.def_inst_index,
        block_id,
        inst_index,
        self.analysis.dominance,
      ) {
      reusable_entries = Some(entries)
      reusable_index = index
    }
  }
  if reusable_index >= 0 && reusable_entries is Some(entries) {
    let existing = entries[reusable_index]
    if existing.value.ty == result_val.ty &&
      (
        !bounded_stable_global ||
        (
          position - existing.position <=
          GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_DISTANCE &&
          existing.reuse_count < GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_LIMIT
        )
      ) {
      inst.set_opcode(Scalar(Copy))
      inst.operands.clear()
      inst.operands.push(existing.value)
      // Post-budget stable globals are deliberately reused only at a short
      // distance. Do not transitively canonicalize their consumers here:
      // doing so turns local address recipes into long-lived values and
      // defeats the bounded-reuse policy before final alias cleanup.
      if !bounded_stable_global {
        self.session.record_alias(result_val, existing.value)
      }
      self.changed = true
      if bounded_stable_global {
        self.value_table_changes.push(
          Updated(entries, reusable_index, existing),
        )
        entries[reusable_index] = {
          ..existing,
          reuse_count: existing.reuse_count + 1,
        }
      }
      return
    }
  }
  let entry : AvailableExpression = {
    value: result_val,
    dependency,
    memory_version,
    def_block_id: block_id,
    def_inst_index: inst_index,
    position,
    reuse_count: 0,
  }
  self.insert_available_expression(inst, entry)
  self.session.record_definition(inst)
}

///|
fn AcyclicOptimizer::finish(self : AcyclicOptimizer) -> AcyclicOptimizeStats {
  // A rule that stops before commit must not leak unplaced DFG nodes through
  // an otherwise successful optimizer exit.
  self.session.discard_candidates(0)
  {
    changed: self.changed,
    work_done: self.work_done,
    budget_exhausted: self.budget_exhausted,
    value_lookup_probes: self.value_lookup_probes,
    rewrite_changed: self.session.stats.changed,
    rewrite_attempts: self.session.stats.attempts,
    rewrite_applied: self.session.stats.applied,
    rewrite_created_instructions: self.session.stats.created_instructions,
  }
}

///|
pub fn run_acyclic_optimization_with_budget_and_analysis(
  func : @milkir.Function,
  work_budget : Int32,
  analysis : FunctionAnalysis,
) -> AcyclicOptimizeStats {
  let block_instructions = fn(block_id : Int32) -> ArrayView[@milkir.InstId] {
    func.blocks[analysis.block_idx[block_id]].instruction_ids()
  }
  let stream = AcyclicOptimizer::new(
    func, work_budget, analysis, block_instructions,
  )
  fn enter(block_id : Int32) -> ((Int32, Int32), Bool) {
    let union_scope = stream.session.begin_scope()
    let value_scope = stream.begin_value_scope()
    func.blocks[analysis.block_idx[block_id]].set_instructions(
      stream.process_block(block_id, block_instructions(block_id)),
    )
    ((union_scope, value_scope), true)
  }
  if analysis.cfg.is_valid(0) {
    @milkir.visit_dominator_tree(analysis.domtree, 0, enter, fn(scope) {
      let (union_scope, value_scope) = scope
      stream.end_value_scope(value_scope)
      stream.session.end_scope(union_scope)
    })
  }
  stream.finish()
}

///|
/// Unified global optimization pass that combines pure CSE and alias-aware GVN
/// in a single dominator-tree walk.
