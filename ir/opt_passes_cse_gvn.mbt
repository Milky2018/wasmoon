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
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
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
  // Expression environment: key -> value
  // We use an array as a stack to track which expressions to pop on leaving a block
  let expressions : @hashmap.HashMap[Inst, Value] = @hashmap.new()
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added in this block (to pop later)
    let local_keys : Array[Inst] = []
    // Process instructions
    let mut i = 0
    while i < block.instructions.length() {
      let inst = block.instructions[i]
      // Skip instructions with side effects or no result
      if has_side_effects(inst) {
        i = i + 1
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if expressions.get(key) is Some(existing) {
          // Replace this instruction with a copy to the existing value
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
          // Don't add this to expressions (it's now a copy)
        } else {
          // Record this expression as available
          expressions.set(key, result_val)
          local_keys.push(key)
        }
      }
      i = i + 1
    }
    // Recurse to dominated children
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Pop this block's expressions from environment
    for key in local_keys {
      expressions.remove(key)
    }
  }

  // Start DFS from entry block (block 0)
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
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
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
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
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, (Value, Bool)?)] = []
    // Process instructions
    for inst in block.instructions {
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
