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
  { base_id: self.base_id, offset_id: self.offset_id, region: self.region }
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
fn LastStoreState::equals(
  self : LastStoreState,
  other : LastStoreState,
) -> Bool {
  if self.heap_default != other.heap_default ||
    self.table_default != other.table_default ||
    self.context != other.context ||
    self.other != other.other ||
    self.heap.length() != other.heap.length() ||
    self.table.length() != other.table.length() {
    return false
  }
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    if other.heap.get(memidx) != Some(token) {
      return false
    }
  }
  for entry in self.table.iter() {
    let (tableidx, token) = entry
    if other.table.get(tableidx) != Some(token) {
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
fn LastStoreState::meet_from(
  self : LastStoreState,
  other : LastStoreState,
  join_token : StoreVersion,
) -> Unit {
  self.context = meet_last_store_token(self.context, other.context, join_token)
  self.other = meet_last_store_token(self.other, other.other, join_token)
  self.heap_default = meet_last_store_token(
    self.heap_default,
    other.heap_default,
    join_token,
  )
  let heap_keys : @hashset.HashSet[Int] = HashSet([])
  for entry in self.heap.iter() {
    let (memidx, _) = entry
    heap_keys.add(memidx)
  }
  for entry in other.heap.iter() {
    let (memidx, _) = entry
    heap_keys.add(memidx)
  }
  let merged_heap : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
  for memidx in heap_keys {
    let left = match self.heap.get(memidx) {
      Some(token) => Some(token)
      None => self.heap_default
    }
    let right = match other.heap.get(memidx) {
      Some(token) => Some(token)
      None => other.heap_default
    }
    if meet_last_store_token(left, right, join_token) is Some(token) {
      merged_heap.set(memidx, token)
    }
  }
  self.heap = merged_heap
  self.table_default = meet_last_store_token(
    self.table_default,
    other.table_default,
    join_token,
  )
  let table_keys : @hashset.HashSet[Int] = HashSet([])
  for entry in self.table.iter() {
    table_keys.add(entry.0)
  }
  for entry in other.table.iter() {
    table_keys.add(entry.0)
  }
  let merged_table : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
  for tableidx in table_keys {
    let left = indexed_store_token(self.table, self.table_default, tableidx)
    let right = indexed_store_token(other.table, other.table_default, tableidx)
    if meet_last_store_token(left, right, join_token) is Some(token) {
      merged_table.set(tableidx, token)
    }
  }
  self.table = merged_table
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
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
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
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
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
  block_idx : @hashmap.HashMap[Int, Int],
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
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
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    for inst_index, inst in block.instructions {
      update_last_store_state(
        state,
        inst,
        { block_id, inst_index },
        ptr_base_infos,
      )
    }
    for succ in cfg.get_successors(block_id) {
      let succ_idx = block_idx.get(succ).unwrap()
      let succ_block = func.blocks[succ_idx]
      let join_token = if succ_block.instructions.length() > 0 {
        { block_id: succ, inst_index: 0 }
      } else {
        { block_id: succ, inst_index: -1 }
      }
      let updated = match block_input.get(succ) {
        Some(existing) => {
          let merged = existing.clone()
          merged.meet_from(state, join_token)
          if !merged.equals(existing) {
            block_input.set(succ, merged)
            true
          } else {
            false
          }
        }
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
fn collect_iconst_values(func : Function) -> @hashmap.HashMap[Int, Int64] {
  let result : @hashmap.HashMap[Int, Int64] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(v) {
        match inst.opcode {
          Scalar(IntConst(value)) => result.set(v.id, value)
          Scalar(Copy) =>
            if inst.operands.length() > 0 &&
              result.get(inst.operands[0].id) is Some(copied) {
              result.set(v.id, copied)
            }
          _ => ()
        }
      }
    }
  }
  result
}

///|
fn is_known_iconst(
  value_id : Int,
  iconst_values : @hashmap.HashMap[Int, Int64],
) -> Bool {
  iconst_values.get(value_id) is Some(_)
}

///|
fn collect_ptr_base_infos(
  func : Function,
  iconst_values : @hashmap.HashMap[Int, Int64],
) -> @hashmap.HashMap[Int, PtrBaseInfo] {
  let result : @hashmap.HashMap[Int, PtrBaseInfo] = HashMap([])
  for param in func.params {
    if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
      result.set(param.0.id, { region: Other })
    }
  }
  if func.blocks.length() > 0 {
    for param in func.blocks[0].params {
      if param.1 is (Ptr | Ref | CallableRef | OpaqueRef) {
        result.set(param.0.id, { region: Other })
      }
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      for inst in block.instructions {
        if inst.first_result() is Some(v) && result.get(v.id) is None {
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
                result.get(inst.operands[0].id)
              } else {
                None
              }
            Scalar(IntBinary(Add)) =>
              if inst.operands.length() >= 2 {
                let lhs = inst.operands[0]
                let rhs = inst.operands[1]
                match (result.get(lhs.id), result.get(rhs.id)) {
                  (Some(base), None) | (None, Some(base)) => Some(base)
                  (Some(lhs_base), Some(rhs_base)) if lhs_base.region ==
                    rhs_base.region => Some(lhs_base)
                  _ =>
                    if result.get(lhs.id) is Some(base) &&
                      is_known_iconst(rhs.id, iconst_values) {
                      Some(base)
                    } else if result.get(rhs.id) is Some(base) &&
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
                if result.get(lhs.id) is Some(base) &&
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
                result.get(inst.operands[1].id) is Some(lhs_base) &&
                result.get(inst.operands[2].id) is Some(rhs_base) &&
                lhs_base.region == rhs_base.region {
                Some(lhs_base)
              } else {
                None
              }
            _ => None
          }
          if inferred is Some(base) {
            result.set(v.id, base)
            changed = true
          }
        }
      }
    }
  }
  result
}

///|
fn ptr_access_from_inst(
  inst : Inst,
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
) -> PtrAccess? {
  match inst.opcode {
    Memory(Load(_)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region })
      } else {
        None
      }
    Memory(LoadNarrow(_, _, _)) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region })
      } else {
        None
      }
    Memory(Store(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region })
      } else {
        None
      }
    Memory(StoreNarrow(_)) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region })
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
  { last_store, location: access.location_key(), ty }
}

///|
fn block_dominates_with_idom(idom : Array[Int], a : Int, b : Int) -> Bool {
  if a == b {
    return true
  }
  let mut cursor = b
  while cursor >= 0 && cursor < idom.length() {
    cursor = idom[cursor]
    if cursor == a {
      return true
    }
    if cursor == -1 {
      break
    }
  }
  false
}

///|
fn inst_dominates(
  def_block_id : Int,
  def_inst_index : Int,
  use_block_id : Int,
  use_inst_index : Int,
  idom : Array[Int],
) -> Bool {
  if def_block_id == use_block_id {
    return def_inst_index < use_inst_index
  }
  block_dominates_with_idom(idom, def_block_id, use_block_id)
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
  !inst.opcode.semantics().must_preserve_if_unused()
}

///|
fn gvn_memory_dependency(
  func : Function,
  inst : Inst,
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
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
fn run_global_value_numbering_with_budget(
  func : Function,
  work_budget : Int,
) -> GVNStats {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return { result, work_done: 0, budget_exhausted: false }
  }
  if work_budget <= 0 {
    return {
      result,
      work_done: 0,
      budget_exhausted: instruction_count(func) > 0,
    }
  }
  let iconst_values = collect_iconst_values(func)
  let ptr_base_infos = collect_ptr_base_infos(func, iconst_values)
  // Build CFG and compute dominators
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping
  let block_idx : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Expression environment: key -> (value, abstract memory dependency)
  let value_table : @hashmap.HashMap[Inst, (Value, AliasRegion?)] = HashMap([])
  // Track memory-dependent keys separately for scoped invalidation.
  let memory_keys : @hashmap.HashMap[Inst, AliasRegion] = HashMap([])
  let block_input_state = compute_block_input_last_store_states(
    func, cfg, block_idx, ptr_base_infos,
  )
  let memory_values : @hashmap.HashMap[MemoryValueKey, MemoryValueEntry] = HashMap([],
  )
  let work_done : Ref[Int] = { val: 0 }
  let budget_exhausted : Ref[Bool] = { val: false }
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    if budget_exhausted.val {
      return
    }
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, (Value, AliasRegion?)?)] = []
    let last_store_state = match block_input_state.get(block_id) {
      Some(state) => state.clone()
      None => LastStoreState()
    }
    // Process instructions
    for inst_index, inst in block.instructions {
      if work_done.val >= work_budget {
        budget_exhausted.val = true
        break
      }
      work_done.val = work_done.val + 1
      let mut replaced_by_memory = false
      if inst.opcode is Memory(Load(load_ty)) &&
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
            idom,
          ) {
          inst.opcode = Scalar(Copy)
          inst.operands.clear()
          inst.operands.push(entry.value)
          result.mark_changed()
          replaced_by_memory = true
        }
      }
      if inst.opcode is Memory(Store(store_ty)) &&
        ptr_access_from_inst(inst, ptr_base_infos) is Some(store_access) &&
        inst.operands.length() >= 2 {
        let key = memory_key_from_access(
          store_access,
          store_ty,
          Some({ block_id, inst_index }),
        )
        memory_values.set(key, {
          def_block_id: block_id,
          def_inst_index: inst_index,
          value: inst.operands[1],
        })
      }
      update_last_store_state(
        last_store_state,
        inst,
        { block_id, inst_index },
        ptr_base_infos,
      )
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
      // Skip non-candidates
      if inst.opcode is GlobalValue(global_value) &&
        func.global_value_data(global_value) is Some(ContextField(_, Stable, _)) {
        continue
      }
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy. The type check is defensive:
          // Inst identity includes result types, so a mismatch is not expected.
          if existing.ty == result_val.ty {
            inst.opcode = Scalar(Copy)
            inst.operands.clear()
            inst.operands.push(existing)
            result.mark_changed()
          }
        } else {
          // Record previous value (None if new)
          let prev = value_table.get(key)
          local_entries.push((key, prev))
          let dependency = gvn_memory_dependency(func, inst, ptr_base_infos)
          value_table.set(key, (result_val, dependency))
          if dependency is Some(region) {
            memory_keys.set(key, region)
          }
        }
      }
    }
    // Recurse to dominated children
    if !budget_exhausted.val && block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Restore value table to state before this block
    for entry in local_entries.rev_iter() {
      let (key, prev) = entry
      match prev {
        Some(v) => {
          value_table.set(key, v)
          if v.1 is Some(region) {
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

  // Start DFS from entry block (block 0)
  if cfg.is_valid(0) {
    dfs(0)
  }
  { result, work_done: work_done.val, budget_exhausted: budget_exhausted.val }
}

///|
/// Unified global optimization pass that combines pure CSE and alias-aware GVN
/// in a single dominator-tree walk.
fn cse_gvn_global(func : Function) -> GVNStats {
  run_global_value_numbering_with_budget(func, instruction_count(func))
}
