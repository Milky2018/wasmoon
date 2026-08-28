// ============ Global Value Numbering with Load CSE ============

///|
priv struct PtrAccess {
  base_id : Int
  offset_id : Int
  region : AliasRegion
}

///|
priv struct PtrBaseInfo {
  region : AliasRegion
}

///|
priv struct PtrLocationKey {
  base_id : Int
  offset_id : Int
  region : AliasRegion
} derive(Eq, Hash)

///|
priv struct StoreVersion {
  block_id : Int
  inst_index : Int
} derive(Eq, Hash)

///|
priv struct LastStoreState {
  mut heap : @hashmap.HashMap[Int, StoreVersion]
  mut heap_default : StoreVersion?
  mut table : @hashmap.HashMap[Int, StoreVersion]
  mut table_default : StoreVersion?
  mut context : StoreVersion?
  mut other : StoreVersion?
}

///|
priv enum MemoryWriteScope {
  NoWrite
  WriteRegion(AliasRegion)
  WriteAll
}

///|
priv struct MemoryValueKey {
  last_store : StoreVersion?
  location : PtrLocationKey
  ty : Type
} derive(Eq, Hash)

///|
priv struct MemoryValueEntry {
  def_block_id : Int
  def_inst_index : Int
  value : Value
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
  let heap : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    heap.set(memidx, token)
  }
  let table : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
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
  left : @hashmap.HashMap[Int, StoreVersion],
  right : @hashmap.HashMap[Int, StoreVersion],
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
    (Some(lhs), None) => Some(lhs)
    (None, Some(rhs)) => Some(rhs)
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
  entries : @hashmap.HashMap[Int, StoreVersion],
  default : StoreVersion?,
  index : Int,
) -> StoreVersion? {
  match entries.get(index) {
    Some(token) => Some(token)
    None => default
  }
}

///|
fn meet_indexed_store_maps(
  left : @hashmap.HashMap[Int, StoreVersion],
  left_default : StoreVersion?,
  right : @hashmap.HashMap[Int, StoreVersion],
  right_default : StoreVersion?,
  merged_default : StoreVersion?,
  join_token : StoreVersion,
) -> @hashmap.HashMap[Int, StoreVersion] {
  let merged : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
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
  region : AliasRegion,
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
  region : AliasRegion,
  token : StoreVersion,
) -> Unit {
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
  inst : Inst,
  ptr_base_infos : Array[PtrBaseInfo?],
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
  if inst.opcode.semantics().memory.may_write_memory() {
    WriteAll
  } else {
    NoWrite
  }
}

///|
fn update_last_store_state(
  state : LastStoreState,
  inst : Inst,
  inst_version : StoreVersion,
  ptr_base_infos : Array[PtrBaseInfo?],
) -> Unit {
  match instruction_memory_write_scope(inst, ptr_base_infos) {
    NoWrite => ()
    WriteRegion(region) => state.set_region_token(region, inst_version)
    WriteAll => state.set_all_tokens(inst_version)
  }
}

///|
fn compute_block_input_last_store_states(
  func : Function,
  cfg : CFG,
  block_idx : Array[Int],
  ptr_base_infos : Array[PtrBaseInfo?],
) -> @hashmap.HashMap[Int, LastStoreState] {
  let block_input : @hashmap.HashMap[Int, LastStoreState] = HashMap([])
  if !cfg.is_valid(0) {
    return block_input
  }
  let queue : Array[Int] = [0]
  let queue_set : @hashset.HashSet[Int] = HashSet([])
  queue_set.add(0)
  while queue.length() > 0 {
    let block_id = queue.pop().unwrap()
    queue_set.remove(block_id)
    let state = match block_input.get(block_id) {
      Some(existing) => existing.clone()
      None => LastStoreState()
    }
    let idx = block_idx[block_id]
    let block = func.blocks[idx]
    for inst_index, inst in block.instructions {
      update_last_store_state(
        state,
        inst,
        { block_id, inst_index, },
        ptr_base_infos,
      )
    }
    for succ in cfg.get_successors(block_id) {
      let succ_idx = block_idx[succ]
      let succ_block = func.blocks[succ_idx]
      let join_token = if succ_block.instructions.length() > 0 {
        { block_id: succ, inst_index: 0, }
      } else {
        { block_id: succ, inst_index: -1, }
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
fn collect_iconst_values(
  func : Function,
  instructions? : Array[Inst],
) -> Array[Int64?] {
  let result : Array[Int64?] = Array::make(func.next_value_id, None)
  let record = fn(inst : Inst) {
    if inst.first_result() is Some(v) {
      match inst.opcode {
        Scalar(IntConst(value)) => result[v.id] = Some(value)
        Scalar(Copy) =>
          if inst.operands.length() > 0 &&
            result[inst.operands[0].id] is Some(copied) {
            result[v.id] = Some(copied)
          }
        _ => ()
      }
    }
  }
  match instructions {
    Some(prefix) =>
      for inst in prefix {
        record(inst)
      }
    None =>
      for block in func.blocks {
        for inst in block.instructions {
          record(inst)
        }
      }
  }
  result
}

///|
fn collect_ptr_base_infos(
  func : Function,
  iconst_values : Array[Int64?],
  instructions? : Array[Inst],
) -> Array[PtrBaseInfo?] {
  let result : Array[PtrBaseInfo?] = Array::make(func.next_value_id, None)
  for param in func.params {
    if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
      result[param.0.id] = Some({ region: Other, })
    }
  }
  if func.blocks.length() > 0 {
    for param in func.blocks[0].params {
      if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
        result[param.0.id] = Some({ region: Other, })
      }
    }
  }
  let dependents : Array[Array[Inst]] = Array::makei(func.next_value_id, _ => [])
  let worklist : Array[Inst] = []
  let queued = Array::make(func.next_inst_id, false)
  let enqueue = fn(inst : Inst) {
    worklist.push(inst)
    queued[inst.id] = true
    for operand in inst.operands {
      dependents[operand.id].push(inst)
    }
  }
  match instructions {
    Some(prefix) =>
      for inst in prefix {
        enqueue(inst)
      }
    None =>
      for block in func.blocks {
        for inst in block.instructions {
          enqueue(inst)
        }
      }
  }
  let mut cursor = 0
  while cursor < worklist.length() {
    let inst = worklist[cursor]
    cursor = cursor + 1
    queued[inst.id] = false
    if inst.first_result() is Some(v) && result[v.id] is None {
      let inferred : PtrBaseInfo? = match inst.opcode {
        GlobalValue(global_value) =>
          match func.global_value_data(global_value) {
            Some(ContextField(_, _, region)) => Some({ region, })
            None => None
          }
        Ext(_, _) => None
        Scalar(Copy)
        | Scalar(Convert(Bitcast))
        | Scalar(Convert(UnsignedExtend))
        | Scalar(Convert(SignedExtend))
        | Scalar(Convert(IntReduce)) =>
          if inst.operands.length() > 0 {
            result[inst.operands[0].id]
          } else {
            None
          }
        Scalar(IntBinary(Add)) =>
          if inst.operands.length() >= 2 {
            let lhs = inst.operands[0]
            let rhs = inst.operands[1]
            match (result[lhs.id], result[rhs.id]) {
              (Some(base), None) | (None, Some(base)) => Some(base)
              (Some(lhs_base), Some(rhs_base)) if lhs_base.region ==
                rhs_base.region => Some(lhs_base)
              _ =>
                if result[lhs.id] is Some(base) &&
                  is_known_iconst(rhs.id, iconst_values) {
                  Some(base)
                } else if result[rhs.id] is Some(base) &&
                  is_known_iconst(lhs.id, iconst_values) {
                  Some(base)
                } else {
                  None
                }
            }
          } else {
            None
          }
        Scalar(IntBinary(Sub)) =>
          if inst.operands.length() >= 2 {
            let lhs = inst.operands[0]
            let rhs = inst.operands[1]
            if result[lhs.id] is Some(base) &&
              is_known_iconst(rhs.id, iconst_values) {
              Some(base)
            } else {
              None
            }
          } else {
            None
          }
        Scalar(Select) =>
          if inst.operands.length() >= 3 &&
            result[inst.operands[1].id] is Some(lhs_base) &&
            result[inst.operands[2].id] is Some(rhs_base) &&
            lhs_base.region == rhs_base.region {
            Some(lhs_base)
          } else {
            None
          }
        _ => None
      }
      if inferred is Some(base) {
        result[v.id] = Some(base)
        for dependent in dependents[v.id] {
          if !queued[dependent.id] {
            worklist.push(dependent)
            queued[dependent.id] = true
          }
        }
      }
    }
  }
  result
}

///|
fn gvn_instruction_prefix(
  func : Function,
  work_budget : Int,
  analysis : FunctionAnalysis,
) -> Array[Inst] {
  let prefix : Array[Inst] = []
  fn enter(block_id : Int) -> (Unit, Bool) {
    if prefix.length() >= work_budget {
      return ((), false)
    }
    let block = func.blocks[analysis.block_idx[block_id]]
    for inst in block.instructions {
      if prefix.length() >= work_budget {
        break
      }
      prefix.push(inst)
    }
    ((), prefix.length() < work_budget)
  }
  if analysis.cfg.is_valid(0) {
    visit_dominator_tree(analysis.domtree, 0, enter, fn(_) { () })
  }
  prefix
}

///|
fn is_known_iconst(value_id : Int, iconst_values : Array[Int64?]) -> Bool {
  iconst_values[value_id] is Some(_)
}

///|
fn ptr_access_from_inst(
  inst : Inst,
  ptr_base_infos : Array[PtrBaseInfo?],
) -> PtrAccess? {
  match inst.opcode {
    Memory(Load(_)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos[base.id] {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(LoadNarrow(_, _, _)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos[base.id] {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(Store(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos[base.id] {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region, })
      } else {
        None
      }
    Memory(StoreNarrow(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos[base.id] {
          Some(base_info) => base_info.region
          None => Other
        }
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
  ty : Type,
  last_store : StoreVersion?,
) -> MemoryValueKey {
  { last_store, location: access.location_key(), ty, }
}

///|
fn inst_dominates(
  def_block_id : Int,
  def_inst_index : Int,
  use_block_id : Int,
  use_inst_index : Int,
  dominance : Dominance,
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
fn is_gvn_candidate(inst : Inst) -> Bool {
  // Replacement currently emits one copy, so only single-result instructions
  // can participate in GVN.
  if inst.results.length() != 1 {
    return false
  }
  if is_cheap_rematerializable_constant(inst) {
    return false
  }
  !inst.opcode.semantics().must_preserve_if_unused()
}

///|
fn gvn_memory_dependency(
  func : Function,
  inst : Inst,
  ptr_base_infos : Array[PtrBaseInfo?],
) -> AliasRegion? {
  match inst.opcode {
    GlobalValue(global_value) =>
      match func.global_value_data(global_value) {
        Some(ContextField(_, Mutable, _)) => Some(Context)
        _ => None
      }
    _ =>
      if inst.opcode.semantics().memory.reads_memory() {
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
priv struct GVNStats {
  result : OptResult
  work_done : Int
  budget_exhausted : Bool
}

///|
priv struct GVNValueEntry {
  key : Inst
  value : Value
  dependency : AliasRegion?
  position : Int
  reuse_count : Int
}

///|
/// Keep post-budget rematerializable context values inside short live ranges.
/// Extending one AEGIS memory-base value across the complete function adds
/// enough spill traffic to outweigh the eliminated loads.
const GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_DISTANCE : Int = 16

///|
const GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_LIMIT : Int = 1

///|
fn is_stable_global_value(func : Function, inst : Inst) -> Bool {
  match inst.opcode {
    GlobalValue(global_value) =>
      func.global_value_data(global_value) is Some(ContextField(_, Stable, _))
    _ => false
  }
}

///|
fn run_global_value_numbering_with_budget_and_analysis(
  func : Function,
  work_budget : Int,
  analysis : FunctionAnalysis,
) -> GVNStats {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return { result, work_done: 0, budget_exhausted: false, }
  }
  let memory_work_budget = if work_budget > 0 { work_budget } else { 0 }
  let complete_memory_analysis = instruction_count(func) <= memory_work_budget
  let ptr_base_infos = if complete_memory_analysis {
    collect_ptr_base_infos(func, collect_iconst_values(func))
  } else {
    let prefix = gvn_instruction_prefix(func, memory_work_budget, analysis)
    collect_ptr_base_infos(
      func,
      collect_iconst_values(func, instructions=prefix),
      instructions=prefix,
    )
  }
  // Expression environment: key -> available value and reuse state.
  let value_table : @hashmap.HashMap[Inst, GVNValueEntry] = HashMap([])
  // Track memory-dependent keys separately for scoped invalidation.
  let memory_keys : @hashmap.HashMap[Inst, AliasRegion] = HashMap([])
  let block_input_state = if complete_memory_analysis {
    compute_block_input_last_store_states(
      func,
      analysis.cfg,
      analysis.block_idx,
      ptr_base_infos,
    )
  } else {
    HashMap([])
  }
  let memory_values : @hashmap.HashMap[MemoryValueKey, MemoryValueEntry] = HashMap([],
  )
  let work_done : Ref[Int] = { val: 0, }
  let budget_exhausted : Ref[Bool] = { val: false, }
  let instruction_position : Ref[Int] = { val: 0, }
  // Walk the dominator tree
  fn enter(block_id : Int) -> (Array[(Inst, GVNValueEntry?)], Bool) {
    let idx = analysis.block_idx[block_id]
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, GVNValueEntry?)] = []
    let last_store_state = match block_input_state.get(block_id) {
      Some(state) => state.clone()
      None => LastStoreState()
    }
    // Process instructions
    for inst_index, inst in block.instructions {
      let position = instruction_position.val
      instruction_position.val = position + 1
      let within_memory_budget = work_done.val < memory_work_budget
      if within_memory_budget {
        work_done.val = work_done.val + 1
      } else {
        budget_exhausted.val = true
      }
      let mut replaced_by_memory = false
      if within_memory_budget &&
        inst.opcode is Memory(Load(load_ty)) &&
        ptr_access_from_inst(inst, ptr_base_infos) is Some(load_access) {
        let key = memory_key_from_access(
          load_access,
          load_ty,
          last_store_state.get_region_token(load_access.region),
        )
        if memory_values.get(key) is Some(entry) &&
          inst_dominates(
            entry.def_block_id,
            entry.def_inst_index,
            block_id,
            inst_index,
            analysis.dominance,
          ) {
          inst.opcode = Scalar(Copy)
          inst.operands.clear()
          inst.operands.push(entry.value)
          result.mark_changed()
          replaced_by_memory = true
        }
      }
      if within_memory_budget &&
        inst.opcode is Memory(Store(store_ty)) &&
        ptr_access_from_inst(inst, ptr_base_infos) is Some(store_access) &&
        inst.operands.length() >= 2 {
        let key = memory_key_from_access(
          store_access,
          store_ty,
          Some({ block_id, inst_index, }),
        )
        memory_values.set(key, {
          def_block_id: block_id,
          def_inst_index: inst_index,
          value: inst.operands[1],
        })
      }
      if within_memory_budget {
        update_last_store_state(
          last_store_state,
          inst,
          { block_id, inst_index, },
          ptr_base_infos,
        )
      }
      if replaced_by_memory {
        continue
      }
      // Invalidate only expressions that depend on the written abstract region.
      match instruction_memory_write_scope(inst, ptr_base_infos) {
        NoWrite => ()
        WriteRegion(written_region) => {
          let invalidated : Array[Inst] = []
          for entry in memory_keys.iter() {
            let (key, dependency) = entry
            if dependency == written_region || dependency == Other {
              invalidated.push(key)
            }
          }
          for key in invalidated {
            if value_table.get(key) is Some(previous) {
              local_entries.push((key, Some(previous)))
            }
            value_table.remove(key)
            memory_keys.remove(key)
          }
          continue
        }
        WriteAll => {
          for entry in memory_keys.iter() {
            let (key, _) = entry
            if value_table.get(key) is Some(previous) {
              local_entries.push((key, Some(previous)))
            }
          }
          for entry in memory_keys.iter() {
            value_table.remove(entry.0)
          }
          memory_keys.clear()
          continue
        }
      }
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        let bounded_stable_global = !within_memory_budget &&
          is_stable_global_value(func, inst)
        if value_table.get(key) is Some(existing_entry) {
          // Already computed - replace with copy. The type check is defensive:
          // Inst identity includes result types, so a mismatch is not expected.
          if existing_entry.value.ty == result_val.ty &&
            (
              !bounded_stable_global ||
              (
                position - existing_entry.position <=
                GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_DISTANCE &&
                existing_entry.reuse_count <
                GVN_POST_BUDGET_STABLE_GLOBAL_REUSE_LIMIT
              )
            ) {
            inst.opcode = Scalar(Copy)
            inst.operands.clear()
            inst.operands.push(existing_entry.value)
            result.mark_changed()
            if bounded_stable_global {
              local_entries.push((existing_entry.key, Some(existing_entry)))
              value_table.set(existing_entry.key, {
                ..existing_entry,
                reuse_count: existing_entry.reuse_count + 1,
              })
            }
          } else if bounded_stable_global {
            local_entries.push((existing_entry.key, Some(existing_entry)))
            value_table.set(existing_entry.key, {
              key: existing_entry.key,
              value: result_val,
              dependency: None,
              position,
              reuse_count: 0,
            })
          }
        } else {
          // Record previous value (None if new)
          let prev = value_table.get(key)
          local_entries.push((key, prev))
          let dependency = gvn_memory_dependency(func, inst, ptr_base_infos)
          value_table.set(key, {
            key,
            value: result_val,
            dependency,
            position,
            reuse_count: 0,
          })
          if dependency is Some(region) {
            memory_keys.set(key, region)
          }
        }
      }
    }
    // Cheap value numbering covers the complete dominator tree. The bounded
    // budget only disables precise memory forwarding.
    (local_entries, true)
  }

  // Restore the value table to the state it had before the block.
  fn exit(local_entries : Array[(Inst, GVNValueEntry?)]) -> Unit {
    for entry in local_entries.rev_iter() {
      let (key, prev) = entry
      match prev {
        Some(v) => {
          value_table.set(key, v)
          if v.dependency is Some(region) {
            memory_keys.set(key, region)
          }
        }
        None => {
          value_table.remove(key)
          memory_keys.remove(key)
        }
      }
    }
  }

  // Start from the entry block (block 0)
  if analysis.cfg.is_valid(0) {
    visit_dominator_tree(analysis.domtree, 0, enter, exit)
  }
  { result, work_done: work_done.val, budget_exhausted: budget_exhausted.val, }
}

///|
/// Unified global optimization pass that combines pure CSE and alias-aware GVN
/// in a single dominator-tree walk.
