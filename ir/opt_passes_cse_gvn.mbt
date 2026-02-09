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
  for block in func.blocks {
    // Key: (memidx, vmctx_value_id) packed into an Int64.
    let seen : @hashmap.HashMap[Int64, Value] = @hashmap.new()
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
        // Conservatively invalidate on operations that can mutate memory base.
        MemoryGrow(_, _)
        | Call(_)
        | CallIndirect(_, _)
        | CallRef(_)
        | ReturnCall(_)
        | ReturnCallIndirect(_, _)
        | ReturnCallRef(_)
        | CallPtr(_, _) => seen.clear()
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
  size : Int
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
priv struct StoreForwardEntry {
  ty : Type
  value : Value
  size : Int
}

///|
fn PtrAccess::location_key(self : PtrAccess) -> PtrLocationKey {
  { base_id: self.base_id, offset_id: self.offset_id, region: self.region }
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
  if func.blocks.length() > 0 && func.blocks[0].params.length() > 0 {
    // Wasm ABI: entry param 0 is vmctx; treat copy-derived pointers as vmctx-region.
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
fn type_access_size(ty : Type) -> Int {
  match ty {
    I32 | F32 => 4
    I64 | F64 => 8
    V128 => 16
    FuncRef | ExternRef => 8
  }
}

///|
fn ptr_access_from_inst(
  inst : Inst,
  ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
) -> PtrAccess? {
  match inst.opcode {
    LoadPtr(ty) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({
          base_id: base.id,
          offset_id: offset.id,
          region,
          size: type_access_size(ty),
        })
      } else {
        None
      }
    LoadPtrNarrow(_, bits, _) =>
      if inst.operands.length() >= 2 {
        let base = inst.operands[0]
        let offset = inst.operands[1]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region, size: bits / 8 })
      } else {
        None
      }
    StorePtr(ty) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({
          base_id: base.id,
          offset_id: offset.id,
          region,
          size: type_access_size(ty),
        })
      } else {
        None
      }
    StorePtrNarrow(bits) =>
      if inst.operands.length() >= 3 {
        let base = inst.operands[0]
        let offset = inst.operands[2]
        let region = match ptr_base_infos.get(base.id) {
          Some(base_info) => base_info.region
          None => Other
        }
        Some({ base_id: base.id, offset_id: offset.id, region, size: bits / 8 })
      } else {
        None
      }
    _ => None
  }
}

///|
fn store_forward_entry_from_inst(
  inst : Inst,
  access : PtrAccess,
) -> StoreForwardEntry? {
  match inst.opcode {
    StorePtr(ty) =>
      if inst.operands.length() >= 2 {
        Some({ ty, value: inst.operands[1], size: access.size })
      } else {
        None
      }
    _ => None
  }
}

///|
fn ptr_access_from_location_key(key : PtrLocationKey, size : Int) -> PtrAccess {
  { base_id: key.base_id, offset_id: key.offset_id, region: key.region, size }
}

///|
fn may_alias_ptr_access(
  a : PtrAccess,
  b : PtrAccess,
  iconst_values : @hashmap.HashMap[Int, Int64],
) -> Bool {
  // Cranelift-like disjoint abstract regions: never alias across regions.
  if a.region != b.region {
    return false
  }
  // Same base + same offset is a must-alias.
  if a.base_id == b.base_id && a.offset_id == b.offset_id {
    return true
  }
  // For the same base, disjoint constant offset ranges are non-aliasing.
  if a.base_id == b.base_id &&
    iconst_values.get(a.offset_id) is Some(a_off) &&
    iconst_values.get(b.offset_id) is Some(b_off) {
    let a_end = a_off + a.size.to_int64()
    let b_end = b_off + b.size.to_int64()
    if a_end <= b_off || b_end <= a_off {
      return false
    }
  }
  true
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
  // Last store table for selective store-to-load forwarding.
  let last_store : @hashmap.HashMap[PtrLocationKey, StoreForwardEntry] = @hashmap.new()
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, (Value, Bool)?)] = []
    // Track last-store table changes for dominator-tree restoration.
    let local_store_entries : Array[(PtrLocationKey, StoreForwardEntry?)] = []
    // Process instructions
    for inst in block.instructions {
      if enable_memory {
        // Store-to-load forwarding (Cranelift-like "last stores" direction):
        // only forward exact same-address StorePtr(ty) -> LoadPtr(ty).
        if inst.opcode is LoadPtr(load_ty) &&
          ptr_access_from_inst(inst, ptr_base_infos) is Some(load_access) {
          let load_key = load_access.location_key()
          if last_store.get(load_key) is Some(store_entry) &&
            store_entry.ty == load_ty {
            inst.opcode = Opcode::Copy
            inst.operands.clear()
            inst.operands.push(store_entry.value)
            result.mark_changed()
            continue
          }
        }
        // Store opcodes get selective alias invalidation instead of full flush.
        if inst.opcode is StorePtr(_) || inst.opcode is StorePtrNarrow(_) {
          if ptr_access_from_inst(inst, ptr_base_infos) is Some(store_access) {
            let reads_to_remove : Array[Inst] = []
            for key in memory_keys {
              match ptr_access_from_inst(key, ptr_base_infos) {
                Some(read_access) =>
                  if may_alias_ptr_access(
                      read_access, store_access, iconst_values,
                    ) {
                    reads_to_remove.push(key)
                  }
                None => reads_to_remove.push(key)
              }
            }
            for key in reads_to_remove {
              if value_table.get(key) is Some(prev) {
                local_entries.push((key, Some(prev)))
              }
              value_table.remove(key)
              memory_keys.remove(key)
            }
            let stores_to_remove : Array[PtrLocationKey] = []
            for entry in last_store.iter() {
              let (key, saved) = entry
              let previous_access = ptr_access_from_location_key(
                key,
                saved.size,
              )
              if may_alias_ptr_access(
                  previous_access, store_access, iconst_values,
                ) {
                stores_to_remove.push(key)
              }
            }
            for key in stores_to_remove {
              let prev = last_store.get(key)
              local_store_entries.push((key, prev))
              last_store.remove(key)
            }
            if store_forward_entry_from_inst(inst, store_access) is Some(saved) {
              let key = store_access.location_key()
              let prev = last_store.get(key)
              local_store_entries.push((key, prev))
              last_store.set(key, saved)
            }
            continue
          }
        }
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
          let store_keys : Array[PtrLocationKey] = []
          for entry in last_store.iter() {
            let (key, _) = entry
            store_keys.push(key)
          }
          for key in store_keys {
            let prev = last_store.get(key)
            local_store_entries.push((key, prev))
            last_store.remove(key)
          }
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
    for entry in local_store_entries.rev_iter() {
      let (key, prev) = entry
      match prev {
        Some(saved) => last_store.set(key, saved)
        None => last_store.remove(key)
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
