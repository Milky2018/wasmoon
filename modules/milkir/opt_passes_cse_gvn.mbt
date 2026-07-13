// ============ Global Value Numbering with Load CSE ============

///|
/// Check if an instruction reads from memory
fn reads_memory(opcode : Opcode) -> Bool {
  match opcode {
    Memory(MemoryOp::Load(_) | MemoryOp::LoadNarrow(_, _, _))
    | Vector(
      VectorOp::LoadExtend(_, _)
      | VectorOp::LoadSplat(_)
      | VectorOp::LoadZero(_)
      | VectorOp::LoadLane(_, _)
    ) => true
    Call(_) => true
    Ext(_, _) => true
    _ => false
  }
}

///|
/// Check if an instruction may write to memory or have other side effects
/// that could invalidate memory-based expressions
fn may_write_memory(opcode : Opcode) -> Bool {
  match opcode {
    // Direct memory writes
    Memory(MemoryOp::Store(_) | MemoryOp::StoreNarrow(_))
    | Vector(VectorOp::StoreLane(_, _)) => true
    Call(_) => true
    Ext(_, _) => true
    _ => false
  }
}

///|
priv struct PtrAccess {
  base_id : Int
  offset_id : Int
  region : PtrAliasRegion
}

///|
priv enum PtrAliasRegion {
  Other
} derive(Eq, Hash)

///|
priv struct PtrBaseInfo {
  region : PtrAliasRegion
}

///|
priv struct PtrLocationKey {
  base_id : Int
  offset_id : Int
  region : PtrAliasRegion
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
  mut context : StoreVersion?
  mut other : StoreVersion?
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
  { heap: HashMap([]), heap_default: None, context: None, other: None }
}

///|
fn LastStoreState::clone(self : LastStoreState) -> LastStoreState {
  let heap : @hashmap.HashMap[Int, StoreVersion] = HashMap([])
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    heap.set(memidx, token)
  }
  {
    heap,
    heap_default: self.heap_default,
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
    self.context != other.context ||
    self.other != other.other ||
    self.heap.length() != other.heap.length() {
    return false
  }
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    if other.heap.get(memidx) != Some(token) {
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
}

///|
fn LastStoreState::get_region_token(
  self : LastStoreState,
  region : PtrAliasRegion,
) -> StoreVersion? {
  match region {
    Other => self.other
  }
}

///|
fn LastStoreState::set_region_token(
  self : LastStoreState,
  region : PtrAliasRegion,
  token : StoreVersion,
) -> Unit {
  match region {
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
  self.context = Some(token)
  self.other = Some(token)
}

///|
fn update_last_store_state(
  state : LastStoreState,
  inst : Inst,
  inst_version : StoreVersion,
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
) -> Unit {
  let is_store = match inst.opcode {
    Memory(MemoryOp::Store(_) | MemoryOp::StoreNarrow(_))
    | Vector(VectorOp::StoreLane(_, _)) => true
    _ => false
  }
  if is_store && ptr_access_from_inst(inst, ptr_base_infos) is Some(access) {
    state.set_region_token(access.region, inst_version)
    return
  }
  if may_write_memory(inst.opcode) {
    state.set_all_tokens(inst_version)
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
          Scalar(ScalarOp::IntConst(value)) => result.set(v.id, value)
          Scalar(ScalarOp::Copy) =>
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
    result.set(param.0.id, { region: Other })
  }
  if func.blocks.length() > 0 {
    for param in func.blocks[0].params {
      result.set(param.0.id, { region: Other })
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      for inst in block.instructions {
        if inst.first_result() is Some(v) && result.get(v.id) is None {
          let inferred : PtrBaseInfo? = match inst.opcode {
            Ext(_, _) => None
            Scalar(ScalarOp::Copy)
            | Scalar(ScalarOp::Convert(ConversionOp::Bitcast))
            | Scalar(ScalarOp::Convert(ConversionOp::UnsignedExtend))
            | Scalar(ScalarOp::Convert(ConversionOp::SignedExtend))
            | Scalar(ScalarOp::Convert(ConversionOp::IntReduce)) =>
              if inst.operands.length() > 0 {
                result.get(inst.operands[0].id)
              } else {
                None
              }
            Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)) =>
              if inst.operands.length() >= 2 {
                let lhs = inst.operands[0]
                let rhs = inst.operands[1]
                if result.get(lhs.id) is Some(base) &&
                  is_known_iconst(rhs.id, iconst_values) {
                  Some(base)
                } else if result.get(rhs.id) is Some(base) &&
                  is_known_iconst(lhs.id, iconst_values) {
                  Some(base)
                } else {
                  None
                }
              } else {
                None
              }
            Scalar(ScalarOp::IntBinary(IntBinaryOp::Sub)) =>
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
            Scalar(ScalarOp::Select) =>
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
    Memory(MemoryOp::Load(_)) =>
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
    Memory(MemoryOp::LoadNarrow(_, _, _)) =>
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
    Memory(MemoryOp::Store(_)) =>
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
    Memory(MemoryOp::StoreNarrow(_)) =>
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
/// This includes pure operations plus loads (which read but don't write)
fn is_gvn_candidate(inst : Inst) -> Bool {
  // Replacement currently emits one copy, so only single-result instructions
  // can participate in GVN.
  if inst.results.length() != 1 {
    return false
  }
  // Use the existing has_side_effects check - if it has side effects, skip it
  if has_side_effects(inst) {
    return false
  }
  // Instructions that write memory are handled by invalidation, not skipped
  // But we still need to skip them as candidates
  match inst.opcode {
    // Division/remainder can trap, not suitable
    Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedDiv))
    | Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedDiv))
    | Scalar(ScalarOp::IntBinary(IntBinaryOp::SignedRem))
    | Scalar(ScalarOp::IntBinary(IntBinaryOp::UnsignedRem)) => false
    // Float-to-int can trap
    Scalar(ScalarOp::Convert(ConversionOp::FloatToSignedInt))
    | Scalar(ScalarOp::Convert(ConversionOp::FloatToUnsignedInt)) => false
    // Memory writes are handled by may_write_memory, skip as candidates
    Memory(MemoryOp::Store(_) | MemoryOp::StoreNarrow(_))
    | Vector(VectorOp::StoreLane(_, _)) => false
    // All other non-side-effect instructions are candidates
    _ => true
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
  // Expression environment: key -> (value, reads_memory flag)
  let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = HashMap([])
  // Track memory-reading keys separately for O(1) invalidation lookup
  let memory_keys : @hashset.HashSet[Inst] = HashSet([])
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
    let local_entries : Array[(Inst, (Value, Bool)?)] = []
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
      if inst.opcode is Memory(MemoryOp::Load(load_ty)) &&
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
          inst.opcode = Scalar(ScalarOp::Copy)
          inst.operands.clear()
          inst.operands.push(entry.value)
          result.mark_changed()
          replaced_by_memory = true
        }
      }
      if inst.opcode is Memory(MemoryOp::Store(store_ty)) &&
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
      // Check if this instruction may invalidate memory-based expressions.
      if may_write_memory(inst.opcode) {
        // Invalidate all memory-reading expressions using tracked set.
        for key in memory_keys {
          if value_table.get(key) is Some((v, _)) {
            local_entries.push((key, Some((v, true))))
          }
        }
        for key in memory_keys {
          value_table.remove(key)
        }
        memory_keys.clear()
        continue
      }
      // Skip non-candidates
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy. The type check is defensive:
          // Inst identity includes result types, so a mismatch is not expected.
          if existing.ty == result_val.ty {
            inst.opcode = Scalar(ScalarOp::Copy)
            inst.operands.clear()
            inst.operands.push(existing)
            result.mark_changed()
          }
        } else {
          // Record previous value (None if new)
          let prev = value_table.get(key)
          local_entries.push((key, prev))
          // Add to value table with memory-read flag
          let is_memory_read = reads_memory(inst.opcode)
          value_table.set(key, (result_val, is_memory_read))
          if is_memory_read {
            memory_keys.add(key)
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
          if v.1 {
            memory_keys.add(key)
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
fn cse_gvn_global(func : Function) -> OptResult {
  run_global_value_numbering_with_budget(func, instruction_count(func)).result
}
