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
    let expressions : @hashmap.HashMap[Inst, Value] = HashMap([])
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
          inst.opcode = Copy
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
    let seen : @hashmap.HashMap[Int64, Value] = HashMap([])
    // Key: opcode/base/offset for vmctx field loads.
    let seen_vmctx_loads : @hashmap.HashMap[String, Value] = HashMap([])
    for inst in block.instructions {
      match inst.opcode {
        LoadMemBase(memidx) =>
          if inst.first_result() is Some(r) && inst.operands.length() == 1 {
            let vmctx = inst.operands[0]
            let key = (memidx.to_int64() << 32) |
              (vmctx.id.to_int64() & 0xFFFF_FFFFL)
            match seen.get(key) {
              Some(existing) => {
                inst.opcode = Copy
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
                  inst.opcode = Copy
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
                  inst.opcode = Copy
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
        | WasmCall(_)
        | WasmCallIndirect(_, _)
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

///|
/// Eliminate redundant `LoadMemBase` across basic blocks with CFG meet.
///
/// This mirrors Cranelift-style dataflow:
/// - forward-propagate available memory-base loads,
/// - meet at merge points (keep only identical dominating values),
/// - invalidate on operations that may mutate memory base.
pub fn eliminate_redundant_mem_base_loads_global(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  let cfg = CFG::build(func)
  if !cfg.is_valid(0) {
    return result
  }
  let block_idx : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  let iconst_values = collect_iconst_values(func)
  let ptr_base_infos = collect_ptr_base_infos(func, iconst_values)

  fn copy_state(
    src : @hashmap.HashMap[Int64, Value],
  ) -> @hashmap.HashMap[Int64, Value] {
    let dst : @hashmap.HashMap[Int64, Value] = HashMap([])
    for entry in src.iter() {
      let (k, v) = entry
      dst.set(k, v)
    }
    dst
  }

  fn invalidates_mem_base(
    inst : Inst,
    ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
  ) -> Bool {
    match inst.opcode {
      MemoryGrow(_, _)
      | WasmCall(_)
      | WasmCallIndirect(_, _)
      | CallRef(_)
      | ReturnCall(_)
      | ReturnCallIndirect(_, _)
      | ReturnCallRef(_)
      | CallPtr(_, _)
      | TableGrow(_) => true
      StorePtr(_) | StorePtrNarrow(_) =>
        if ptr_access_from_inst(inst, ptr_base_infos) is Some(access) {
          access.region is Vmctx
        } else {
          false
        }
      _ => false
    }
  }

  fn transfer_mem_base_state(
    in_state : @hashmap.HashMap[Int64, Value],
    block : Block,
    ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo],
  ) -> @hashmap.HashMap[Int64, Value] {
    let out_state = copy_state(in_state)
    for inst in block.instructions {
      if invalidates_mem_base(inst, ptr_base_infos) {
        out_state.clear()
        continue
      }
      if inst.opcode is LoadMemBase(memidx) &&
        inst.first_result() is Some(r) &&
        inst.operands.length() == 1 {
        let vmctx = inst.operands[0]
        let key = (memidx.to_int64() << 32) |
          (vmctx.id.to_int64() & 0xFFFF_FFFFL)
        if out_state.get(key) is None {
          out_state.set(key, r)
        }
      }
    }
    out_state
  }

  fn update_meet_state(
    dst : @hashmap.HashMap[Int64, Value],
    incoming : @hashmap.HashMap[Int64, Value],
  ) -> Bool {
    let next : @hashmap.HashMap[Int64, Value] = HashMap([])
    for entry in dst.iter() {
      let (k, old_v) = entry
      if incoming.get(k) is Some(in_v) && in_v.id == old_v.id {
        next.set(k, old_v)
      }
    }
    let mut changed = dst.length() != next.length()
    if !changed {
      for entry in next.iter() {
        let (k, v) = entry
        if dst.get(k) is Some(old_v) {
          if old_v.id != v.id {
            changed = true
            break
          }
        } else {
          changed = true
          break
        }
      }
    }
    if changed {
      dst.clear()
      for entry in next.iter() {
        let (k, v) = entry
        dst.set(k, v)
      }
    }
    changed
  }

  // Block input state: block_id -> available (memidx, vmctx) -> dominating value.
  let block_input : @hashmap.HashMap[Int, @hashmap.HashMap[Int64, Value]] = HashMap([],
  )
  block_input.set(0, HashMap([]))
  let worklist : Array[Int] = [0]
  let in_worklist : @hashset.HashSet[Int] = HashSet([])
  in_worklist.add(0) |> ignore

  while worklist.length() > 0 {
    let block_id = worklist.pop().unwrap()
    in_worklist.remove(block_id) |> ignore
    let block_i = match block_idx.get(block_id) {
      Some(i) => i
      None => continue
    }
    let in_state = match block_input.get(block_id) {
      Some(state) => state
      None => continue
    }
    let out_state = transfer_mem_base_state(
      in_state,
      func.blocks[block_i],
      ptr_base_infos,
    )
    for succ in cfg.get_successors(block_id) {
      if !cfg.is_valid(succ) {
        continue
      }
      match block_input.get(succ) {
        None => {
          block_input.set(succ, copy_state(out_state))
          if !in_worklist.contains(succ) {
            worklist.push(succ)
            in_worklist.add(succ) |> ignore
          }
        }
        Some(succ_state) =>
          if update_meet_state(succ_state, out_state) &&
            !in_worklist.contains(succ) {
            worklist.push(succ)
            in_worklist.add(succ) |> ignore
          }
      }
    }
  }

  // Rewrite using computed block input states.
  for block in func.blocks {
    let state = match block_input.get(block.id) {
      Some(s) => copy_state(s)
      None => HashMap([])
    }
    for inst in block.instructions {
      if invalidates_mem_base(inst, ptr_base_infos) {
        state.clear()
        continue
      }
      if inst.opcode is LoadMemBase(memidx) &&
        inst.first_result() is Some(r) &&
        inst.operands.length() == 1 {
        let vmctx = inst.operands[0]
        let key = (memidx.to_int64() << 32) |
          (vmctx.id.to_int64() & 0xFFFF_FFFFL)
        if state.get(key) is Some(existing) {
          inst.opcode = Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          state.set(key, r)
        }
      }
    }
  }

  result
}

///|
/// Reassociate wasm memory addresses in a V8-like style.
///
/// This mirrors the intent of V8's `WasmAddressReassociation` pass:
/// - separate register and immediate address components,
/// - canonicalize memory ops to a shared `(base + reg)` plus per-op immediate.
///
/// Our IR models memory ops as `load/store(base, offset_imm_value)`, where
/// dynamic offsets often appear folded into `base` as add-chains. We rewrite:
/// - `mem(iadd(iadd(base, reg), k), off)` -> `mem(iadd(base, reg), off+k)`
/// but only for `(base, reg)` pairs used by more than one memory op in the
/// same block (same profitability guard as V8's multi-use heuristic).
pub fn reassociate_wasm_addresses(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }

  fn mem_addr_operand_indices(inst : Inst) -> (Int, Int)? {
    match inst.opcode {
      LoadPtr(_) | LoadPtrNarrow(_, _, _) =>
        if inst.operands.length() >= 2 {
          Some((0, 1))
        } else {
          None
        }
      StorePtr(_) | StorePtrNarrow(_) =>
        if inst.operands.length() >= 3 {
          Some((0, 2))
        } else {
          None
        }
      _ => None
    }
  }

  fn pair_key(a : Value, b : Value) -> String {
    let a_id = a.id
    let b_id = b.id
    if a_id <= b_id {
      "\{a_id}:\{b_id}"
    } else {
      "\{b_id}:\{a_id}"
    }
  }

  fn extract_pair_with_imm(
    base : Value,
    off_imm : Int64,
    def_inst : @hashmap.HashMap[Int, Inst],
    iconst_values : @hashmap.HashMap[Int, Int64],
  ) -> (Value, Value, Value, Int64)? {
    let mut current = base
    let mut imm = off_imm
    while true {
      let inst = match def_inst.get(current.id) {
        Some(i) => i
        None => return None
      }
      match inst.opcode {
        Copy =>
          if inst.operands.length() >= 1 {
            current = inst.operands[0]
            continue
          } else {
            return None
          }
        Iadd => {
          guard inst.operands.length() >= 2 else { return None }
          let lhs = inst.operands[0]
          let rhs = inst.operands[1]
          let lhs_const = iconst_values.get(lhs.id)
          let rhs_const = iconst_values.get(rhs.id)
          match (lhs_const, rhs_const) {
            (Some(c), None) => {
              imm = imm + c
              current = rhs
              continue
            }
            (None, Some(c)) => {
              imm = imm + c
              current = lhs
              continue
            }
            (None, None) =>
              if current.ty is I64 && lhs.ty is I64 && rhs.ty is I64 {
                return Some((current, lhs, rhs, imm))
              } else {
                return None
              }
            (Some(_), Some(_)) => return None
          }
        }
        _ => return None
      }
    }
    None
  }

  let iconst_values = collect_iconst_values(func)
  let def_inst : @hashmap.HashMap[Int, Inst] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.first_result() is Some(r) {
        def_inst.set(r.id, inst)
      }
    }
  }

  let has_mem_base_cache : @hashmap.HashMap[Int, Bool] = HashMap([])

  fn has_wasm_mem_base(
    value : Value,
    def_inst : @hashmap.HashMap[Int, Inst],
    cache : @hashmap.HashMap[Int, Bool],
  ) -> Bool {
    if cache.get(value.id) is Some(cached) {
      return cached
    }
    let stack : Array[Value] = [value]
    let visited : @hashset.HashSet[Int] = HashSet([])
    while stack.length() > 0 {
      let current = stack.pop().unwrap()
      if visited.contains(current.id) {
        continue
      }
      visited.add(current.id) |> ignore
      if def_inst.get(current.id) is Some(inst) {
        match inst.opcode {
          LoadMemBase(_) => {
            cache.set(value.id, true)
            return true
          }
          Copy | Bitcast | Uextend | Sextend | Ireduce =>
            if inst.operands.length() > 0 {
              stack.push(inst.operands[0])
            }
          Iadd | Isub =>
            if inst.operands.length() >= 2 {
              stack.push(inst.operands[0])
              stack.push(inst.operands[1])
            }
          Select =>
            if inst.operands.length() >= 3 {
              stack.push(inst.operands[1])
              stack.push(inst.operands[2])
            }
          _ => ()
        }
      }
    }
    cache.set(value.id, false)
    false
  }

  for block in func.blocks {
    let pair_use_count : @hashmap.HashMap[String, Int] = HashMap([])
    // Pass 1: count candidate `(base, reg)` pairs in this block.
    for inst in block.instructions {
      guard mem_addr_operand_indices(inst) is Some((base_idx, off_idx)) else {
        continue
      }
      let base = inst.operands[base_idx]
      guard has_wasm_mem_base(base, def_inst, has_mem_base_cache) else {
        continue
      }
      let off = inst.operands[off_idx]
      guard off.ty is I64 else { continue }
      let off_imm = match iconst_values.get(off.id) {
        Some(v) => v
        None => continue
      }
      let base = inst.operands[base_idx]
      if extract_pair_with_imm(base, off_imm, def_inst, iconst_values)
        is Some((_, lhs, rhs, _)) {
        let key = pair_key(lhs, rhs)
        let n = match pair_use_count.get(key) {
          Some(v) => v
          None => 0
        }
        pair_use_count.set(key, n + 1)
      }
    }
    if pair_use_count.length() == 0 {
      continue
    }

    // Pass 2: rewrite memory ops to shared pair-base + immediate offset.
    let shared_pairs : @hashmap.HashMap[String, Value] = HashMap([])
    let local_consts : @hashmap.HashMap[Int64, Value] = HashMap([])
    let new_insts : Array[Inst] = []
    let orig_len = block.instructions.length()

    for inst in block.instructions {
      let mut changed_inst = false
      if mem_addr_operand_indices(inst) is Some((base_idx, off_idx)) {
        if has_wasm_mem_base(
            inst.operands[base_idx],
            def_inst,
            has_mem_base_cache,
          ) {
          let off = inst.operands[off_idx]
          if off.ty is I64 {
            if iconst_values.get(off.id) is Some(off_imm) {
              let base = inst.operands[base_idx]
              if extract_pair_with_imm(base, off_imm, def_inst, iconst_values)
                is Some((pair_v, lhs, rhs, new_imm)) {
                let key = pair_key(lhs, rhs)
                let count = match pair_use_count.get(key) {
                  Some(v) => v
                  None => 0
                }
                if count > 1 {
                  let shared_base = match shared_pairs.get(key) {
                    Some(v) => v
                    None => {
                      shared_pairs.set(key, pair_v)
                      pair_v
                    }
                  }
                  if inst.operands[base_idx].id != shared_base.id {
                    inst.operands[base_idx] = shared_base
                    changed_inst = true
                  }
                  if new_imm != off_imm {
                    let new_off = match local_consts.get(new_imm) {
                      Some(v) => v
                      None => {
                        let v = func.new_value(I64)
                        new_insts.push(Inst::new(Some(v), Iconst(new_imm), []))
                        local_consts.set(new_imm, v)
                        v
                      }
                    }
                    if inst.operands[off_idx].id != new_off.id {
                      inst.operands[off_idx] = new_off
                      changed_inst = true
                    }
                  }
                }
              }
            }
          }
        }
      }
      if changed_inst {
        result.mark_changed()
      }
      new_insts.push(inst)
    }

    if new_insts.length() != orig_len {
      block.instructions.clear()
      for inst in new_insts {
        block.instructions.push(inst)
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
    WasmCall(_)
    | WasmCallIndirect(_, _)
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
  { heap: HashMap([]), heap_default: None, vmctx: None, other: None }
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
  let result : @hashmap.HashMap[Int, Int64] = HashMap([])
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
  let result : @hashmap.HashMap[Int, PtrBaseInfo] = HashMap([])
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
    HashMap([])
  }
  let ptr_base_infos : @hashmap.HashMap[Int, PtrBaseInfo] = if enable_memory {
    collect_ptr_base_infos(func, iconst_values)
  } else {
    HashMap([])
  }
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
  let block_input_state : @hashmap.HashMap[Int, LastStoreState] = if enable_memory {
    compute_block_input_last_store_states(func, cfg, block_idx, ptr_base_infos)
  } else {
    HashMap([])
  }
  let memory_values : @hashmap.HashMap[MemoryValueKey, MemoryValueEntry] = HashMap([],
  )
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
            inst.opcode = Copy
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
          inst.opcode = Copy
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
    let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = HashMap([])
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
          inst.opcode = Copy
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
