// Build Cranelift-style regalloc `Output` for emission.
//
// This pass does not rewrite VCode instructions. Instead, it produces:
// - Per-operand allocations for each instruction/terminator.
// - An edit stream (moves between regs and spill slots) that the emitter
//   interleaves with instructions.

///|
fn assigned_preg_of(
  vreg_id : Int,
  assigned_pregs : Array[@abi.PReg?],
) -> @abi.PReg? {
  if vreg_id >= 0 && vreg_id < assigned_pregs.length() {
    assigned_pregs[vreg_id]
  } else {
    None
  }
}

///|
fn spill_slot_of(vreg_id : Int, spill_slots : Array[Int]) -> Int {
  if vreg_id >= 0 && vreg_id < spill_slots.length() {
    spill_slots[vreg_id]
  } else {
    -1
  }
}

///|
fn vreg_home_loc_dense(
  vreg : @abi.VReg,
  assigned_pregs : Array[@abi.PReg?],
  spill_slots : Array[Int],
) -> Loc {
  if assigned_preg_of(vreg.id, assigned_pregs) is Some(preg) {
    Reg(preg)
  } else {
    let slot = spill_slot_of(vreg.id, spill_slots)
    if slot >= 0 {
      Spill(slot)
    } else {
      abort("missing allocation for vreg \{vreg.id}")
    }
  }
}

///|
fn reg_home_loc_dense(
  reg : @abi.Reg,
  assigned_pregs : Array[@abi.PReg?],
  spill_slots : Array[Int],
) -> Loc {
  match reg {
    @abi.Physical(preg) => Reg(preg)
    @abi.Virtual(vreg) => vreg_home_loc_dense(vreg, assigned_pregs, spill_slots)
  }
}

///|
fn fixed_use_preg(inst : @instr.VCodeInst, idx : Int) -> @abi.PReg? {
  if idx < inst.use_constraints.length() {
    match inst.use_constraints[idx] {
      @abi.FixedReg(preg) => Some(preg)
      _ => None
    }
  } else {
    None
  }
}

///|
fn fixed_def_preg(inst : @instr.VCodeInst, idx : Int) -> @abi.PReg? {
  if idx < inst.def_constraints.length() {
    match inst.def_constraints[idx] {
      @abi.FixedReg(preg) => Some(preg)
      _ => None
    }
  } else {
    None
  }
}

///|
fn mark_used_reg(mask : Array[Bool], idx : Int) -> Unit {
  if idx < 0 {
    return
  }
  while idx >= mask.length() {
    mask.push(false)
  }
  mask[idx] = true
}

///|
fn is_used_reg(mask : Array[Bool], idx : Int) -> Bool {
  idx >= 0 && idx < mask.length() && mask[idx]
}

///|
fn add_used_reg(
  used_int : Array[Bool],
  used_fp : Array[Bool],
  preg : @abi.PReg,
) -> Unit {
  match preg.class {
    @abi.Int => mark_used_reg(used_int, preg.index)
    _ => mark_used_reg(used_fp, preg.index)
  }
}

///|
const USED_REG_MARK_CAP : Int = 128

///|
fn mark_used(used_marks : Array[Int], idx : Int, epoch : Int) -> Unit {
  guard idx >= 0 && idx < used_marks.length() else {
    abort("preg index out of range for used-mark table: \{idx}")
  }
  used_marks[idx] = epoch
}

///|
fn is_used(used_marks : Array[Int], idx : Int, epoch : Int) -> Bool {
  idx >= 0 && idx < used_marks.length() && used_marks[idx] == epoch
}

///|
fn add_used_reg_marks(
  used_int_marks : Array[Int],
  used_fp_marks : Array[Int],
  epoch : Int,
  preg : @abi.PReg,
) -> Unit {
  match preg.class {
    @abi.Int => mark_used(used_int_marks, preg.index, epoch)
    _ => mark_used(used_fp_marks, preg.index, epoch)
  }
}

///|
fn active_reload_get(
  active_reload_epoch : Array[Int],
  active_reload_preg_idx : Array[Int],
  slot : Int,
  cls : @abi.RegClass,
  epoch : Int,
) -> @abi.PReg? {
  if slot < 0 || slot >= active_reload_epoch.length() {
    return None
  }
  if active_reload_epoch[slot] == epoch {
    Some(@abi.PReg::{ index: active_reload_preg_idx[slot], class: cls })
  } else {
    None
  }
}

///|
fn active_reload_set(
  active_reload_epoch : Array[Int],
  active_reload_preg_idx : Array[Int],
  slot : Int,
  preg : @abi.PReg,
  epoch : Int,
) -> Unit {
  if slot < 0 || slot >= active_reload_epoch.length() {
    return
  }
  active_reload_epoch[slot] = epoch
  active_reload_preg_idx[slot] = preg.index
}

///|
fn active_reload_clear(active_reload_epoch : Array[Int], slot : Int) -> Unit {
  if slot < 0 || slot >= active_reload_epoch.length() {
    return
  }
  active_reload_epoch[slot] = 0
}

///|
fn pick_temp_preg(
  out : Output,
  isa : @isa.ISA,
  env : @isa.MachineEnv,
  cls : @abi.RegClass,
  used_int_marks : Array[Int],
  used_fp_marks : Array[Int],
  used_epoch : Int,
  temp_int_pool : Array[Int],
  temp_fp_pool : Array[Int],
  temp_vec_pool : Array[Int],
  need_preserve : Bool,
  cursor : Int,
) -> (@abi.PReg, Int, Int?) {
  let scratch1 = isa.scratch_reg_1_index()
  let scratch2 = isa.scratch_reg_2_index()
  let vmctx = isa.vmctx_reg_index()
  let mem0_desc = isa.mem0_desc_reg_index()
  let func_table = isa.func_table_reg_index()
  let extra_results_ptr = isa.extra_results_ptr_reg_index()
  fn alloc_temp_spill_slot(out : Output, cls : @abi.RegClass) -> Int {
    // Spill slots are counted in 8-byte units.
    // Keep the same rules as BundleSet::new_spill_bundle.
    match cls {
      @abi.Vector => {
        if out.num_spillslots % 2 != 0 {
          out.num_spillslots += 1
        }
        let slot = out.num_spillslots
        out.num_spillslots += 2
        slot
      }
      _ => {
        let slot = out.num_spillslots
        out.num_spillslots += 1
        slot
      }
    }
  }

  match cls {
    @abi.Int => {
      for i in 0..<temp_int_pool.length() {
        let idx = temp_int_pool[(cursor + i) % temp_int_pool.length()]
        if !is_used(used_int_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Int }
          mark_used(used_int_marks, idx, used_epoch)
          return (preg, cursor + 1, None)
        }
      }
      // Fallback: steal any allocatable GPR not used by this instruction,
      // save/restore via a fresh spill slot.
      let candidates : Array[@abi.PReg] = []
      for p in env.preferred_int {
        candidates.push(p)
      }
      for p in env.nonpreferred_int {
        candidates.push(p)
      }
      for p in candidates {
        let idx = p.index
        // Skip special-purpose registers.
        if idx == scratch1 ||
          idx == scratch2 ||
          idx == func_table ||
          idx == vmctx ||
          idx == mem0_desc ||
          idx == extra_results_ptr {
          continue
        }
        if !is_used(used_int_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Int }
          mark_used(used_int_marks, idx, used_epoch)
          if need_preserve {
            let save_slot = alloc_temp_spill_slot(out, @abi.Int)
            return (preg, cursor + 1, Some(save_slot))
          } else {
            return (preg, cursor + 1, None)
          }
        }
      }
      abort("no free integer temp register (even after stealing)")
    }
    @abi.Vector => {
      for i in 0..<temp_vec_pool.length() {
        let idx = temp_vec_pool[(cursor + i) % temp_vec_pool.length()]
        if !is_used(used_fp_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Vector }
          mark_used(used_fp_marks, idx, used_epoch)
          return (preg, cursor + 1, None)
        }
      }
      // Fallback: steal any allocatable vector reg not used by this instruction.
      let candidates : Array[@abi.PReg] = []
      for p in env.preferred_vector {
        candidates.push(p)
      }
      for p in env.nonpreferred_vector {
        candidates.push(p)
      }
      for p in candidates {
        let idx = p.index
        if !is_used(used_fp_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Vector }
          mark_used(used_fp_marks, idx, used_epoch)
          if need_preserve {
            let save_slot = alloc_temp_spill_slot(out, @abi.Vector)
            return (preg, cursor + 1, Some(save_slot))
          } else {
            return (preg, cursor + 1, None)
          }
        }
      }
      abort("no free vector temp register (even after stealing)")
    }
    _ => {
      for i in 0..<temp_fp_pool.length() {
        let idx = temp_fp_pool[(cursor + i) % temp_fp_pool.length()]
        if !is_used(used_fp_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: cls }
          mark_used(used_fp_marks, idx, used_epoch)
          return (preg, cursor + 1, None)
        }
      }
      // Fallback: steal any allocatable FPR not used by this instruction.
      let candidates : Array[@abi.PReg] = []
      for p in env.preferred_float {
        candidates.push(p)
      }
      for p in env.nonpreferred_float {
        candidates.push(p)
      }
      for p in candidates {
        let idx = p.index
        if !is_used(used_fp_marks, idx, used_epoch) {
          let preg = @abi.PReg::{ index: idx, class: cls }
          mark_used(used_fp_marks, idx, used_epoch)
          if need_preserve {
            let save_slot = alloc_temp_spill_slot(out, cls)
            return (preg, cursor + 1, Some(save_slot))
          } else {
            return (preg, cursor + 1, None)
          }
        }
      }
      abort("no free float temp register (even after stealing)")
    }
  }
}

///|
/// Build a Cranelift-style regalloc output from a vreg->preg/spillslot assignment.
///
/// Notes:
/// - All instruction operands must be assigned a register at the program point
///   of the instruction. Stack locations are only used between instructions.
/// - Stack loads/stores are expressed as `Edit::Move` between `Loc::Spill` and
///   `Loc::Reg`.
fn build_output(
  func : VCodeFunction,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  isa : @isa.ISA,
  settings : @abi.ABISettings,
) -> Output {
  let out = Output::new()
  out.num_spillslots = alloc.num_spill_slots
  let max_vreg_id = func.next_vreg_id
  let assigned_pregs : Array[@abi.PReg?] = Array::make(max_vreg_id, None)
  let spill_slots : Array[Int] = Array::make(max_vreg_id, -1)
  for vreg_id, preg in alloc.assignments {
    if vreg_id >= 0 && vreg_id < max_vreg_id {
      assigned_pregs[vreg_id] = Some(preg)
    }
  }
  for vreg_id, slot in alloc.spill_slots {
    if vreg_id >= 0 && vreg_id < max_vreg_id {
      spill_slots[vreg_id] = slot
    }
  }

  // Param allocations (used by the prologue).
  for p in func.params {
    out.push_param_loc(vreg_home_loc_dense(p, assigned_pregs, spill_slots))
  }

  // Cranelift/regalloc2 does not run an extra per-block reload-coalescing pass
  // during output construction; keep this disabled on the hot path for closer
  // alignment and lower compile-time overhead.
  let enable_reload_coalescing = false
  let reload_intervals : Map[(Int, Int), ReloadInterval] = if enable_reload_coalescing {
    let intervals = compute_reload_intervals(func, alloc)
    allocate_reload_registers(func, alloc, intervals, liveness)
    intervals
  } else {
    {}
  }

  // Temp-reg pools for local reloads when no coalescing is available.
  let used_int_regs : Array[Bool] = Array::make(USED_REG_MARK_CAP, false)
  let used_fp_regs : Array[Bool] = Array::make(USED_REG_MARK_CAP, false)
  for _, preg in alloc.assignments {
    add_used_reg(used_int_regs, used_fp_regs, preg)
  }
  let reserve_extra_results_ptr = func.needs_extra_results_ptr() ||
    func.calls_multi_value_function()
  let reserve_mem0_desc = func.should_cache_mem0_desc()
  let reserve_func_table = func.should_cache_func_table()
  let env = isa.machine_env(
    settings~,
    reserve_mem0_desc~,
    reserve_func_table~,
    reserve_extra_results_ptr~,
  )

  // Reserve dedicated scratch regs (used by the move resolver).
  for idx in env.scratch_int {
    mark_used_reg(used_int_regs, idx)
  }
  for idx in env.scratch_float {
    mark_used_reg(used_fp_regs, idx)
  }

  // Reserve pinned registers.
  mark_used_reg(used_int_regs, isa.vmctx_reg_index())
  if reserve_mem0_desc {
    mark_used_reg(used_int_regs, isa.mem0_desc_reg_index())
  }
  if reserve_func_table {
    mark_used_reg(used_int_regs, isa.func_table_reg_index())
  }
  if reserve_extra_results_ptr {
    mark_used_reg(used_int_regs, isa.extra_results_ptr_reg_index())
  }

  // Temp-reg pools for local reloads/move resolution:
  // - Always include scratch regs.
  // - Prefer higher-index regs (avoid common arg/return regs on most ABIs).
  fn push_temp_reg(pool : Array[Int], used : Array[Bool], idx : Int) -> Unit {
    // Pool sizes are tiny; linear scan avoids extra dependencies.
    let mut already = false
    for v in pool {
      if v == idx {
        already = true
      }
    }
    if !is_used_reg(used, idx) && !already {
      pool.push(idx)
    }
  }

  let temp_int_pool : Array[Int] = []
  for idx in env.scratch_int {
    temp_int_pool.push(idx)
  }
  let int_candidates : Array[@abi.PReg] = []
  for r in env.nonpreferred_int {
    int_candidates.push(r)
  }
  for r in env.preferred_int {
    int_candidates.push(r)
  }
  for r in int_candidates {
    if r.index >= 8 {
      push_temp_reg(temp_int_pool, used_int_regs, r.index)
    }
  }
  for r in int_candidates {
    if r.index < 8 {
      push_temp_reg(temp_int_pool, used_int_regs, r.index)
    }
  }
  let temp_fp_pool : Array[Int] = []
  for idx in env.scratch_float {
    temp_fp_pool.push(idx)
  }
  let fp_candidates : Array[@abi.PReg] = []
  for r in env.nonpreferred_float {
    fp_candidates.push(r)
  }
  for r in env.preferred_float {
    fp_candidates.push(r)
  }
  for r in fp_candidates {
    if r.index >= 8 {
      push_temp_reg(temp_fp_pool, used_fp_regs, r.index)
    }
  }
  for r in fp_candidates {
    if r.index < 8 {
      push_temp_reg(temp_fp_pool, used_fp_regs, r.index)
    }
  }

  // Vector temps share the same physical register bank as floats on current ISAs.
  let temp_vec_pool : Array[Int] = []
  for idx in env.scratch_float {
    temp_vec_pool.push(idx)
  }
  let vec_candidates : Array[@abi.PReg] = []
  for r in env.nonpreferred_vector {
    vec_candidates.push(r)
  }
  for r in env.preferred_vector {
    vec_candidates.push(r)
  }
  for r in vec_candidates {
    if r.index >= 8 {
      push_temp_reg(temp_vec_pool, used_fp_regs, r.index)
    }
  }
  for r in vec_candidates {
    if r.index < 8 {
      push_temp_reg(temp_vec_pool, used_fp_regs, r.index)
    }
  }

  // Helper: record a resolved RegMove list as edits at a given program point.
  fn push_resolved_moves(
    out : Output,
    block_id : Int,
    inst_idx : Int,
    pos : ProgPos,
    moves : Array[RegMove],
  ) -> Unit {
    if moves.is_empty() {
      return
    }
    let resolved = resolve_parallel_moves(moves)
    for mv in resolved {
      out.push_edit(
        block_id,
        inst_idx,
        pos,
        Edit::Move(mv.from, mv.to, mv.class),
      )
    }
  }

  // regalloc2 keeps edits as a position-sorted linear stream and consumes
  // them with a forward cursor during output construction.
  fn take_point_edits(
    inst_edits : Array[(Int, Int, InstEdits)],
    cursor : Int,
    block_id : Int,
    inst_idx : Int,
  ) -> (InstEdits?, Int) {
    if cursor >= inst_edits.length() {
      return (None, cursor)
    }
    let (edit_block, edit_inst, edits) = inst_edits[cursor]
    if edit_block == block_id && edit_inst == inst_idx {
      (Some(edits), cursor + 1)
    } else if edit_block < block_id ||
      (edit_block == block_id && edit_inst < inst_idx) {
      abort(
        "inst_edits stream out of order at block=\{block_id} inst=\{inst_idx}",
      )
    } else {
      (None, cursor)
    }
  }

  // Walk blocks and create per-operand allocations. Emit extra edits for spills
  // (reloads before uses, stores after defs) as needed.
  let used_int_marks = Array::make(USED_REG_MARK_CAP, 0)
  let used_fp_marks = Array::make(USED_REG_MARK_CAP, 0)
  let mut used_epoch = 1
  let spill_use_tmp_idx = Array::make(max_vreg_id, -1)
  let spill_use_tmp_epoch = Array::make(max_vreg_id, 0)
  let spill_def_tmp_idx = Array::make(max_vreg_id, -1)
  let spill_def_tmp_epoch = Array::make(max_vreg_id, 0)
  let mut spill_tmp_epoch = 1
  let mut inst_edits_cursor = 0
  let active_reload_epoch : Array[Int] = Array::make(alloc.num_spill_slots, 0)
  let active_reload_preg_idx : Array[Int] = Array::make(
    alloc.num_spill_slots,
    -1,
  )
  let mut block_reload_epoch = 0
  for block_id, block in func.blocks {
    block_reload_epoch = block_reload_epoch + 1
    let reload_epoch = block_reload_epoch
    let mut temp_cursor = 0
    for inst_idx, inst in block.insts {
      let (point_edits, next_inst_edits_cursor) = take_point_edits(
        alloc.inst_edits,
        inst_edits_cursor,
        block_id,
        inst_idx,
      )
      inst_edits_cursor = next_inst_edits_cursor
      // Fixed-reg constraint edits at this point.
      if point_edits is Some(edits) {
        push_resolved_moves(out, block_id, inst_idx, Before, edits.before)
        push_resolved_moves(out, block_id, inst_idx, After, edits.after)
      }

      // Fast path: if this instruction has no non-fixed spilled uses/defs, we
      // do not need per-inst temp-reg selection or used-reg marking.
      let mut needs_spill_temps = false
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) &&
          assigned_preg_of(vreg.id, assigned_pregs) is None &&
          fixed_use_preg(inst, i) is None {
          needs_spill_temps = true
          break
        }
      }
      if !needs_spill_temps {
        for i, def in inst.defs {
          if def.reg is @abi.Virtual(vreg) &&
            assigned_preg_of(vreg.id, assigned_pregs) is None &&
            fixed_def_preg(inst, i) is None {
            needs_spill_temps = true
            break
          }
        }
      }
      if !needs_spill_temps {
        let (alloc_start, alloc_total) = out.begin_inst_allocs(
          block_id,
          inst_idx,
          false,
          inst.defs.length(),
          inst.uses.length(),
        )
        for i, def in inst.defs {
          match fixed_def_preg(inst, i) {
            Some(preg) => out.push_inst_alloc_loc(Reg(preg))
            None =>
              match def.reg {
                @abi.Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
                @abi.Virtual(vreg) =>
                  match assigned_preg_of(vreg.id, assigned_pregs) {
                    Some(preg) => out.push_inst_alloc_loc(Reg(preg))
                    None => abort("missing def allocation for vreg \{vreg.id}")
                  }
              }
          }
        }
        for i, use_reg in inst.uses {
          match fixed_use_preg(inst, i) {
            Some(preg) => out.push_inst_alloc_loc(Reg(preg))
            None =>
              match use_reg {
                @abi.Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
                @abi.Virtual(vreg) =>
                  match assigned_preg_of(vreg.id, assigned_pregs) {
                    Some(preg) => out.push_inst_alloc_loc(Reg(preg))
                    None => abort("missing use allocation for vreg \{vreg.id}")
                  }
              }
          }
        }
        out.end_inst_allocs(alloc_start, alloc_total)
        continue
      }

      used_epoch = used_epoch + 1
      let epoch = used_epoch

      // First, mark all registers that will be used by non-spilled operands at
      // this instruction (including fixed-reg constraints).
      for i, def in inst.defs {
        match fixed_def_preg(inst, i) {
          Some(preg) =>
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
          None =>
            match def.reg {
              @abi.Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) =>
                    add_used_reg_marks(
                      used_int_marks, used_fp_marks, epoch, preg,
                    )
                  None => ()
                }
            }
        }
      }
      for i, use_reg in inst.uses {
        match fixed_use_preg(inst, i) {
          Some(preg) =>
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
          None =>
            match use_reg {
              @abi.Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) =>
                    add_used_reg_marks(
                      used_int_marks, used_fp_marks, epoch, preg,
                    )
                  None => ()
                }
            }
        }
      }
      // Also reserve any registers mentioned in fixed-reg constraint edits at this point.
      // If we steal one of these registers and later restore it, we'd clobber the move result.
      if point_edits is Some(edits) {
        for mv in edits.before {
          if mv.from is Reg(p) {
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, p)
          }
          if mv.to is Reg(p) {
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, p)
          }
        }
        for mv in edits.after {
          if mv.from is Reg(p) {
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, p)
          }
          if mv.to is Reg(p) {
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, p)
          }
        }
      }

      // Reload spilled uses into temps as needed.
      spill_tmp_epoch = spill_tmp_epoch + 1
      let spill_epoch = spill_tmp_epoch
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) &&
          assigned_preg_of(vreg.id, assigned_pregs) is None {
          let slot = spill_slot_of(vreg.id, spill_slots)
          if slot < 0 {
            continue
          }
          // Fixed-reg constraints are handled by constraint edits.
          if fixed_use_preg(inst, i) is Some(_) {
            continue
          }
          guard vreg.id >= 0 && vreg.id < max_vreg_id else {
            abort("vreg id out of range in output build: \{vreg.id}")
          }
          // If already assigned a temp within this instruction, reuse it.
          if spill_use_tmp_epoch[vreg.id] == spill_epoch {
            continue
          }
          // If the slot is currently active in a coalesced reload reg, reuse it.
          if active_reload_get(
              active_reload_epoch,
              active_reload_preg_idx,
              slot,
              vreg.class,
              reload_epoch,
            )
            is Some(rp) {
            spill_use_tmp_epoch[vreg.id] = spill_epoch
            spill_use_tmp_idx[vreg.id] = rp.index
            continue
          }
          // If this slot has a coalesced interval reg, load once and keep active.
          if reload_intervals.get((block_id, slot)) is Some(interval) &&
            interval.preg is Some(rp) {
            out.push_edit(
              block_id,
              inst_idx,
              Before,
              Edit::Move(Spill(slot), Reg(rp), vreg.class),
            )
            active_reload_set(
              active_reload_epoch, active_reload_preg_idx, slot, rp, reload_epoch,
            )
            spill_use_tmp_epoch[vreg.id] = spill_epoch
            spill_use_tmp_idx[vreg.id] = rp.index
            add_used_reg_marks(used_int_marks, used_fp_marks, epoch, rp)
            continue
          }
          // Otherwise, load into a scratch/temporary register local to this instruction.
          let (tmp, new_cursor, save_slot) = pick_temp_preg(
            out,
            isa,
            env,
            vreg.class,
            used_int_marks,
            used_fp_marks,
            epoch,
            temp_int_pool,
            temp_fp_pool,
            temp_vec_pool,
            true,
            temp_cursor,
          )
          temp_cursor = new_cursor
          // If we had to steal a register, save/restore around the instruction.
          if save_slot is Some(s) {
            out.push_edit(
              block_id,
              inst_idx,
              Before,
              Edit::Move(Reg(tmp), Spill(s), vreg.class),
            )
            out.push_edit(
              block_id,
              inst_idx,
              After,
              Edit::Move(Spill(s), Reg(tmp), vreg.class),
            )
          }
          out.push_edit(
            block_id,
            inst_idx,
            Before,
            Edit::Move(Spill(slot), Reg(tmp), vreg.class),
          )
          spill_use_tmp_epoch[vreg.id] = spill_epoch
          spill_use_tmp_idx[vreg.id] = tmp.index
          add_used_reg_marks(used_int_marks, used_fp_marks, epoch, tmp)
        }
      }

      // Allocate spilled defs to temps and store after the instruction.
      for i, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) &&
          assigned_preg_of(vreg.id, assigned_pregs) is None {
          let slot = spill_slot_of(vreg.id, spill_slots)
          if slot < 0 {
            continue
          }
          // Fixed-reg constraints are handled by constraint edits.
          if fixed_def_preg(inst, i) is Some(_) {
            continue
          }
          guard vreg.id >= 0 && vreg.id < max_vreg_id else {
            abort("vreg id out of range in output build: \{vreg.id}")
          }
          let (tmp, new_cursor, save_slot) = pick_temp_preg(
            out,
            isa,
            env,
            vreg.class,
            used_int_marks,
            used_fp_marks,
            epoch,
            temp_int_pool,
            temp_fp_pool,
            temp_vec_pool,
            true,
            temp_cursor,
          )
          temp_cursor = new_cursor
          spill_def_tmp_epoch[vreg.id] = spill_epoch
          spill_def_tmp_idx[vreg.id] = tmp.index
          add_used_reg_marks(used_int_marks, used_fp_marks, epoch, tmp)
          if save_slot is Some(s) {
            out.push_edit(
              block_id,
              inst_idx,
              Before,
              Edit::Move(Reg(tmp), Spill(s), vreg.class),
            )
          }
          out.push_edit(
            block_id,
            inst_idx,
            After,
            Edit::Move(Reg(tmp), Spill(slot), vreg.class),
          )
          if save_slot is Some(s) {
            out.push_edit(
              block_id,
              inst_idx,
              After,
              Edit::Move(Spill(s), Reg(tmp), vreg.class),
            )
          }
          // If this slot had an active reload register, it is now stale.
          active_reload_clear(active_reload_epoch, slot)
        }
      }

      // Record operand allocations for this instruction.
      let (alloc_start, alloc_total) = out.begin_inst_allocs(
        block_id,
        inst_idx,
        false,
        inst.defs.length(),
        inst.uses.length(),
      )
      // defs first.
      for i, def in inst.defs {
        match fixed_def_preg(inst, i) {
          Some(preg) => out.push_inst_alloc_loc(Reg(preg))
          None =>
            match def.reg {
              @abi.Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) => out.push_inst_alloc_loc(Reg(preg))
                  None => {
                    guard vreg.id >= 0 && vreg.id < max_vreg_id else {
                      abort("vreg id out of range in output build: \{vreg.id}")
                    }
                    if spill_def_tmp_epoch[vreg.id] == spill_epoch {
                      let tmp = @abi.PReg::{
                        index: spill_def_tmp_idx[vreg.id],
                        class: vreg.class,
                      }
                      out.push_inst_alloc_loc(Reg(tmp))
                    } else {
                      abort("missing spilled def temp for vreg \{vreg.id}")
                    }
                  }
                }
            }
        }
      }
      // then uses.
      for i, use_reg in inst.uses {
        match fixed_use_preg(inst, i) {
          Some(preg) => out.push_inst_alloc_loc(Reg(preg))
          None =>
            match use_reg {
              @abi.Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) => out.push_inst_alloc_loc(Reg(preg))
                  None => {
                    guard vreg.id >= 0 && vreg.id < max_vreg_id else {
                      abort("vreg id out of range in output build: \{vreg.id}")
                    }
                    if spill_use_tmp_epoch[vreg.id] == spill_epoch {
                      let tmp = @abi.PReg::{
                        index: spill_use_tmp_idx[vreg.id],
                        class: vreg.class,
                      }
                      out.push_inst_alloc_loc(Reg(tmp))
                    } else {
                      abort("missing spilled use temp for vreg \{vreg.id}")
                    }
                  }
                }
            }
        }
      }
      out.end_inst_allocs(alloc_start, alloc_total)
    }

    // Terminator allocations/edits.
    if block.terminator is Some(term) {
      let term_inst = block.insts.length()
      let (term_edits, next_inst_edits_cursor) = take_point_edits(
        alloc.inst_edits,
        inst_edits_cursor,
        block_id,
        term_inst,
      )
      inst_edits_cursor = next_inst_edits_cursor
      if term_edits is Some(edits) {
        push_resolved_moves(out, block_id, term_inst, Before, edits.before)
        push_resolved_moves(out, block_id, term_inst, After, edits.after)
      }

      // Jump args: materialize block params at predecessor end.
      match term {
        @instr.Jump(target, args) => {
          let target_block = func.blocks[target]
          let moves : Array[RegMove] = []
          for i, param in target_block.params {
            if i >= args.length() {
              break
            }
            let from_loc = reg_home_loc_dense(
              args[i],
              assigned_pregs,
              spill_slots,
            )
            let to_loc = vreg_home_loc_dense(param, assigned_pregs, spill_slots)
            moves.push({ from: from_loc, to: to_loc, class: param.class })
          }
          if !moves.is_empty() {
            push_resolved_moves(out, block_id, term_inst, Before, moves)
          }
          // Jump itself doesn't consume regs in the emitter; record an empty range.
          let (alloc_start, alloc_total) = out.begin_inst_allocs(
            block_id, term_inst, true, 0, 0,
          )
          out.end_inst_allocs(alloc_start, alloc_total)
        }
        _ => {
          // For other terminators, treat their operands like uses.
          used_epoch = used_epoch + 1
          let epoch = used_epoch
          let use_regs : Array[@abi.Reg] = match term {
            @instr.Branch(cond, _, _) => [cond]
            @instr.BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
            @instr.BranchZero(r, _, _, _, _) => [r]
            @instr.BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
            @instr.Return(values) => values
            @instr.BrTable(index, _, _) => [index]
            @instr.Trap(_) => []
            @instr.Jump(_, _) => []
          }
          for r in use_regs {
            match r {
              @abi.Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) =>
                    add_used_reg_marks(
                      used_int_marks, used_fp_marks, epoch, preg,
                    )
                  None => ()
                }
            }
          }
          spill_tmp_epoch = spill_tmp_epoch + 1
          let spill_epoch = spill_tmp_epoch
          for r in use_regs {
            if r is @abi.Virtual(vreg) &&
              assigned_preg_of(vreg.id, assigned_pregs) is None {
              let slot = spill_slot_of(vreg.id, spill_slots)
              if slot < 0 {
                continue
              }
              guard vreg.id >= 0 && vreg.id < max_vreg_id else {
                abort("vreg id out of range in output build: \{vreg.id}")
              }
              if spill_use_tmp_epoch[vreg.id] == spill_epoch {
                continue
              }
              if active_reload_get(
                  active_reload_epoch,
                  active_reload_preg_idx,
                  slot,
                  vreg.class,
                  reload_epoch,
                )
                is Some(rp) {
                spill_use_tmp_epoch[vreg.id] = spill_epoch
                spill_use_tmp_idx[vreg.id] = rp.index
                continue
              }
              let (tmp, new_cursor, _save_slot) = pick_temp_preg(
                out,
                isa,
                env,
                vreg.class,
                used_int_marks,
                used_fp_marks,
                epoch,
                temp_int_pool,
                temp_fp_pool,
                temp_vec_pool,
                false,
                temp_cursor,
              )
              temp_cursor = new_cursor
              out.push_edit(
                block_id,
                term_inst,
                Before,
                Edit::Move(Spill(slot), Reg(tmp), vreg.class),
              )
              spill_use_tmp_epoch[vreg.id] = spill_epoch
              spill_use_tmp_idx[vreg.id] = tmp.index
              add_used_reg_marks(used_int_marks, used_fp_marks, epoch, tmp)
            }
          }
          let (alloc_start, alloc_total) = out.begin_inst_allocs(
            block_id,
            term_inst,
            true,
            0,
            use_regs.length(),
          )
          for r in use_regs {
            match r {
              @abi.Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              @abi.Virtual(vreg) =>
                match assigned_preg_of(vreg.id, assigned_pregs) {
                  Some(preg) => out.push_inst_alloc_loc(Reg(preg))
                  None => {
                    guard vreg.id >= 0 && vreg.id < max_vreg_id else {
                      abort("vreg id out of range in output build: \{vreg.id}")
                    }
                    if spill_use_tmp_epoch[vreg.id] == spill_epoch {
                      let tmp = @abi.PReg::{
                        index: spill_use_tmp_idx[vreg.id],
                        class: vreg.class,
                      }
                      out.push_inst_alloc_loc(Reg(tmp))
                    } else {
                      abort(
                        "missing spilled terminator use temp for vreg \{vreg.id}",
                      )
                    }
                  }
                }
            }
          }
          out.end_inst_allocs(alloc_start, alloc_total)
        }
      }
    }
  }
  guard inst_edits_cursor == alloc.inst_edits.length() else {
    abort(
      "unconsumed inst_edits entries: consumed=\{inst_edits_cursor} total=\{alloc.inst_edits.length()}",
    )
  }
  out.finalize_edits()
  out
}
