// ============ Common Subexpression Elimination ============

///|
/// Common Subexpression Elimination (CSE)
/// Replaces duplicate computations with references to the first computation
/// Note: This is local CSE - expressions are only reused within the same basic block
/// to avoid incorrectly using values from non-dominating blocks (e.g., sibling branches)
pub fn eliminate_common_subexpressions(func : Function) -> OptResult {
  let result = OptResult::new()
  for block in func.blocks {
    // Reset expressions map for each block to avoid cross-block CSE issues
    // (e.g., using values defined in sibling branches of if-else)
    let expressions : @hashmap.HashMap[Inst, Value] = @hashmap.new()
    let mut i = 0
    while i < block.instructions.length() {
      let inst = block.instructions[i]
      // Skip instructions with side effects or no result
      if has_side_effects(inst) {
        i = i + 1
        continue
      }
      if inst.first_result() is Some(result_val) {
        if expressions.get(inst) is Some(existing) {
          // Replace this instruction with a copy
          inst.opcode = Opcode::Copy
          // Clear operands and add the existing value
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          // Record this expression
          expressions.set(inst, result_val)
        }
      }
      i = i + 1
    }
  }
  result
}

///|
/// Global Common Subexpression Elimination using dominance analysis
/// Expressions in dominating blocks can be reused in dominated blocks
pub fn eliminate_common_subexpressions_global(func : Function) -> OptResult {
  run_global_value_numbering(func, PureCSE)
}

// ============ LoadMemBase Elimination ============

///|
/// Eliminate redundant `LoadMemBase` instructions within a basic block.
///
/// `LoadMemBase` reads global runtime state (the memory descriptor), so it must
/// not be CSE'd across calls or `memory.grow`. This pass performs a simple
/// forward scan with conservative invalidation on any call-like instruction and
/// `MemoryGrow`.
pub fn eliminate_redundant_mem_base_loads(func : Function) -> OptResult {
  let result = OptResult::new()
  let iconst_values = collect_iconst_values(func)
  let ptr_base_infos = collect_ptr_base_infos(func, iconst_values)
  for block in func.blocks {
    // Key: (memidx, vmctx_value_id) packed into an Int64.
    let seen : @hashmap.HashMap[Int64, Value] = @hashmap.new()
    // Key: opcode/base/offset for vmctx field loads.
    let seen_vmctx_loads : @hashmap.HashMap[String, Value] = @hashmap.new()
    for inst in block.instructions {
      match inst.opcode {
        LoadMemBase(memidx) =>
          if inst.first_result() is Some(r) && inst.operands.length() == 1 {
            let vmctx = inst.operands[0]
            let key = (memidx.to_int64() << 32) |
              (vmctx.id.to_int64() & 0xFFFF_FFFFL)
            match seen.get(key) {
              Some(existing) => {
                inst.opcode = Opcode::Copy
                inst.operands.clear()
                inst.operands.push(existing)
                result.mark_changed()
              }
              None => seen.set(key, r)
            }
          }
        LoadPtr(ty) =>
          if inst.first_result() is Some(r) && inst.operands.length() >= 2 {
            let base = inst.operands[0]
            let offset = inst.operands[1]
            if ptr_base_infos.get(base.id) is Some(base_info) &&
              base_info.region is Vmctx {
              let key = "load_ptr:\{ty}:\{base.id}:\{offset.id}"
              match seen_vmctx_loads.get(key) {
                Some(existing) => {
                  inst.opcode = Opcode::Copy
                  inst.operands.clear()
                  inst.operands.push(existing)
                  result.mark_changed()
                }
                None => seen_vmctx_loads.set(key, r)
              }
            }
          }
        LoadPtrNarrow(ty, bits, signed) =>
          if inst.first_result() is Some(r) && inst.operands.length() >= 2 {
            let base = inst.operands[0]
            let offset = inst.operands[1]
            if ptr_base_infos.get(base.id) is Some(base_info) &&
              base_info.region is Vmctx {
              let key = "load_ptr_narrow:\{ty}:\{bits}:\{signed}:\{base.id}:\{offset.id}"
              match seen_vmctx_loads.get(key) {
                Some(existing) => {
                  inst.opcode = Opcode::Copy
                  inst.operands.clear()
                  inst.operands.push(existing)
                  result.mark_changed()
                }
                None => seen_vmctx_loads.set(key, r)
              }
            }
          }
        // Conservatively invalidate on operations that can mutate memory base.
        MemoryGrow(_, _)
        | Call(_)
        | CallIndirect(_, _)
        | CallRef(_)
        | ReturnCall(_)
        | ReturnCallIndirect(_, _)
        | ReturnCallRef(_)
        | CallPtr(_, _)
        | TableGrow(_) => {
          seen.clear()
          seen_vmctx_loads.clear()
        }
        StorePtr(_) | StorePtrNarrow(_) =>
          if ptr_access_from_inst(inst, ptr_base_infos) is Some(store_access) &&
            store_access.region is Vmctx {
            seen_vmctx_loads.clear()
          }
        _ => ()
      }
    }
  }
  result
}

// ============ Global Value Numbering with Load CSE ============

///|
/// Check if an instruction reads from memory
fn reads_memory(opcode : Opcode) -> Bool {
  match opcode {
    LoadPtr(_) | LoadPtrNarrow(_, _, _) => true
    // MemorySize reads the current memory size (invalidated by MemoryGrow)
    MemorySize(_) => true
    // GC struct/array gets read from memory
    StructGet(_, _) | StructGetS(_, _, _) | StructGetU(_, _, _) => true
    ArrayGet(_) | ArrayGetS(_, _) | ArrayGetU(_, _) | ArrayLen => true
    _ => false
  }
}

///|
/// Check if an instruction may write to memory or have other side effects
/// that could invalidate memory-based expressions
fn may_write_memory(opcode : Opcode) -> Bool {
  match opcode {
    // Direct memory writes
    StorePtr(_) | StorePtrNarrow(_) => true
    // Memory operations
    MemoryGrow(_, _) | MemoryFill(_) | MemoryCopy(_, _) => true
    // Calls may write memory
    Call(_)
    | CallIndirect(_, _)
    | CallRef(_)
    | ReturnCall(_)
    | ReturnCallIndirect(_, _)
    | ReturnCallRef(_)
    | CallPtr(_, _) => true
    // GC operations that modify memory
    StructSet(_, _) | ArraySet(_) | ArrayFill(_) | ArrayCopy(_, _) => true
    // GC allocations modify memory (the GC heap)
    StructNew(_) | StructNewDefault(_) => true
    ArrayNew(_) | ArrayNewDefault(_) | ArrayNewFixed(_, _) => true
    // Table operations may involve memory
    TableGrow(_) => true
    // Exception handling can modify state
    Throw(_) | ThrowRef => true
    SpillLocalsForThrow(_) => true
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
  Heap(Int)
  Vmctx
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
  mut vmctx : StoreVersion?
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
fn LastStoreState::new() -> LastStoreState {
  { heap: @hashmap.new(), heap_default: None, vmctx: None, other: None }
}

///|
fn LastStoreState::clone(self : LastStoreState) -> LastStoreState {
  let heap : @hashmap.HashMap[Int, StoreVersion] = @hashmap.new()
  for entry in self.heap.iter() {
    let (memidx, token) = entry
    heap.set(memidx, token)
  }
  {
    heap,
    heap_default: self.heap_default,
    vmctx: self.vmctx,
    other: self.other,
  }
}

///|
fn LastStoreState::equals(
  self : LastStoreState,
  other : LastStoreState,
) -> Bool {
  if self.heap_default != other.heap_default ||
    self.vmctx != other.vmctx ||
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
  self.vmctx = meet_last_store_token(self.vmctx, other.vmctx, join_token)
  self.other = meet_last_store_token(self.other, other.other, join_token)
  self.heap_default = meet_last_store_token(
    self.heap_default,
    other.heap_default,
    join_token,
  )
  let heap_keys : @hashset.HashSet[Int] = @hashset.new()
  for entry in self.heap.iter() {
    let (memidx, _) = entry
    heap_keys.add(memidx)
  }
  for entry in other.heap.iter() {
    let (memidx, _) = entry
    heap_keys.add(memidx)
  }
  let merged_heap : @hashmap.HashMap[Int, StoreVersion] = @hashmap.new()
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
    Heap(memidx) =>
      match self.heap.get(memidx) {
        Some(token) => Some(token)
        None => self.heap_default
      }
    Vmctx => self.vmctx
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
    Heap(memidx) => self.heap.set(memidx, token)
    Vmctx => self.vmctx = Some(token)
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
  self.vmctx = Some(token)
  self.other = Some(token)
}

///|
fn update_last_store_state(
  state : LastStoreState,
  inst : Inst,
  inst_version : StoreVersion,
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
) -> Unit {
  if (inst.opcode is StorePtr(_) || inst.opcode is StorePtrNarrow(_)) &&
    ptr_access_from_inst(inst, ptr_base_infos) is Some(access) {
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
  let block_input : @hashmap.HashMap[Int, LastStoreState] = @hashmap.new()
  if !cfg.is_valid(0) {
    return block_input
  }
  let queue : Array[Int] = [0]
  let queue_set : @hashset.HashSet[Int] = @hashset.new()
  queue_set.add(0)
  while queue.length() > 0 {
    let block_id = queue.pop().unwrap()
    queue_set.remove(block_id)
    let state = match block_input.get(block_id) {
      Some(existing) => existing.clone()
      None => LastStoreState::new()
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
  let result : @hashmap.HashMap[Int, Int64] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(v) {
        match inst.opcode {
          Iconst(value) => result.set(v.id, value)
          Copy =>
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
  let result : @hashmap.HashMap[Int, PtrBaseInfo] = @hashmap.new()
  if func.params.length() > 0 {
    // Wasm ABI: function param 0 is vmctx.
    let vmctx = func.params[0].0
    result.set(vmctx.id, { region: Vmctx })
  }
  if func.blocks.length() > 0 && func.blocks[0].params.length() > 0 {
    // Some IR forms thread vmctx through entry block params; keep this as a
    // secondary source of vmctx-region seeds.
    let vmctx = func.blocks[0].params[0].0
    result.set(vmctx.id, { region: Vmctx })
  }
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      for inst in block.instructions {
        if inst.first_result() is Some(v) && result.get(v.id) is None {
          let inferred : PtrBaseInfo? = match inst.opcode {
            LoadMemBase(memidx) => Some({ region: Heap(memidx) })
            Copy | Bitcast | Uextend | Sextend | Ireduce =>
              if inst.operands.length() > 0 {
                result.get(inst.operands[0].id)
              } else {
                None
              }
            Iadd =>
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
            Isub =>
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
            Select =>
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
    LoadPtr(_) =>
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
    LoadPtrNarrow(_, _, _) =>
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
    StorePtr(_) =>
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
    StorePtrNarrow(_) =>
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
  // Must have a result
  if inst.first_result() is None {
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
    Sdiv | Udiv | Srem | Urem => false
    // Float-to-int can trap
    FcvtToSint | FcvtToUint => false
    // Memory writes are handled by may_write_memory, skip as candidates
    StorePtr(_) | StorePtrNarrow(_) => false
    // All other non-side-effect instructions are candidates
    _ => true
  }
}

///|
priv enum GlobalValueNumberingMode {
  PureCSE
  AliasAwareGVN
}

///|
fn run_global_value_numbering(
  func : Function,
  mode : GlobalValueNumberingMode,
) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  let enable_memory = mode is AliasAwareGVN
  let iconst_values : @hashmap.HashMap[Int, Int64] = if enable_memory {
    collect_iconst_values(func)
  } else {
    @hashmap.new()
  }
  let ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo] = if enable_memory {
    collect_ptr_base_infos(func, iconst_values)
  } else {
    @hashmap.new()
  }
  // Build CFG and compute dominators
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Expression environment: key -> (value, reads_memory flag)
  let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = @hashmap.new()
  // Track memory-reading keys separately for O(1) invalidation lookup
  let memory_keys : @hashset.HashSet[Inst] = @hashset.new()
  let block_input_state : @hashmap.HashMap[Int, LastStoreState] = if enable_memory {
    compute_block_input_last_store_states(func, cfg, block_idx, ptr_base_infos)
  } else {
    @hashmap.new()
  }
  let memory_values : @hashmap.HashMap[MemoryValueKey, MemoryValueEntry] = @hashmap.new()
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, (Value, Bool)?)] = []
    let last_store_state = if enable_memory {
      match block_input_state.get(block_id) {
        Some(state) => state.clone()
        None => LastStoreState::new()
      }
    } else {
      LastStoreState::new()
    }
    // Process instructions
    for inst_index, inst in block.instructions {
      let mut replaced_by_memory = false
      if enable_memory {
        if inst.opcode is LoadPtr(load_ty) &&
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
            inst.opcode = Opcode::Copy
            inst.operands.clear()
            inst.operands.push(entry.value)
            result.mark_changed()
            replaced_by_memory = true
          }
        }
        if inst.opcode is StorePtr(store_ty) &&
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
      }
      if replaced_by_memory {
        continue
      }
      if enable_memory {
        // Check if this instruction may invalidate memory-based expressions
        if may_write_memory(inst.opcode) {
          // Invalidate all memory-reading expressions using tracked set
          for key in memory_keys {
            if value_table.get(key) is Some((v, _)) {
              // Record for restoration
              local_entries.push((key, Some((v, true))))
            }
          }
          // Remove all memory-reading expressions
          for key in memory_keys {
            value_table.remove(key)
          }
          memory_keys.clear()
          continue
        }
      }
      // Skip non-candidates
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
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
    if block_id < domtree.length() {
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
  result
}

///|
/// Global Value Numbering with Load CSE
/// Extends CSE to handle memory loads by tracking when stores invalidate loads
pub fn gvn(func : Function) -> OptResult {
  let result = OptResult::new()
  for block in func.blocks {
    // Value table: expression key -> (result value, reads_memory flag)
    let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = @hashmap.new()
    for inst in block.instructions {
      // Check if this instruction may invalidate memory-based expressions
      if may_write_memory(inst.opcode) {
        // Invalidate all memory-reading expressions
        let to_remove : Array[Inst] = []
        for entry in value_table.iter() {
          let (key, (_, is_memory_read)) = entry
          if is_memory_read {
            to_remove.push(key)
          }
        }
        for key in to_remove {
          value_table.remove(key)
        }
        continue
      }
      // Skip non-candidates
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          // Record in value table with memory-read flag
          let is_memory_read = reads_memory(inst.opcode)
          value_table.set(key, (result_val, is_memory_read))
        }
      }
    }
  }
  result
}

///|
/// Global Value Numbering with dominance analysis
/// Expressions in dominating blocks can be reused in dominated blocks,
/// with proper invalidation of memory-based expressions
pub fn gvn_global(func : Function) -> OptResult {
  run_global_value_numbering(func, AliasAwareGVN)
}

///|
/// Unified global optimization pass that combines pure CSE and alias-aware GVN
/// in a single dominator-tree walk.
pub fn cse_gvn_global(func : Function) -> OptResult {
  run_global_value_numbering(func, AliasAwareGVN)
}
