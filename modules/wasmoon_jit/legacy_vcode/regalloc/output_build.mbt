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
    Physical(preg) => Reg(preg)
    Virtual(vreg) => vreg_home_loc_dense(vreg, assigned_pregs, spill_slots)
  }
}

///|
fn fixed_use_preg(inst : @instr.VCodeInst, idx : Int) -> @abi.PReg? {
  if idx < inst.use_constraints.length() {
    match inst.use_constraints[idx] {
      FixedReg(preg) => Some(preg)
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
      FixedReg(preg) => Some(preg)
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
fn add_used_reg(
  used_int : Array[Bool],
  used_fp : Array[Bool],
  preg : @abi.PReg,
) -> Unit {
  match preg.class {
    Int => mark_used_reg(used_int, preg.index)
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
fn add_used_reg_marks(
  used_int_marks : Array[Int],
  used_fp_marks : Array[Int],
  epoch : Int,
  preg : @abi.PReg,
) -> Unit {
  match preg.class {
    Int => mark_used(used_int_marks, preg.index, epoch)
    _ => mark_used(used_fp_marks, preg.index, epoch)
  }
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
  fn core_class(class : @abi.RegClass) -> @core_regalloc.RegClass {
    match class {
      Int => Int
      Float32 | Float64 => Float
      Vector => Vector
    }
  }

  fn used_ids(marks : Array[Int], epoch : Int) -> Array[Int] {
    let ids : Array[Int] = []
    for idx, mark in marks {
      if mark == epoch {
        ids.push(idx)
      }
    }
    ids
  }

  fn append_indices(out : Array[Int], regs : Array[@abi.PReg]) -> Unit {
    for reg in regs {
      out.push(reg.index)
    }
  }

  let (used, pool, fallback, reserved) = match cls {
    Int => {
      let candidates : Array[Int] = []
      append_indices(candidates, env.preferred_int)
      append_indices(candidates, env.nonpreferred_int)
      (
        used_ids(used_int_marks, used_epoch),
        temp_int_pool,
        candidates,
        [
          isa.scratch_reg_1_index(),
          isa.scratch_reg_2_index(),
          isa.func_table_reg_index(),
          isa.vmctx_reg_index(),
          isa.mem0_desc_reg_index(),
          isa.extra_results_ptr_reg_index(),
        ],
      )
    }
    Vector => {
      let candidates : Array[Int] = []
      append_indices(candidates, env.preferred_vector)
      append_indices(candidates, env.nonpreferred_vector)
      (used_ids(used_fp_marks, used_epoch), temp_vec_pool, candidates, [])
    }
    _ => {
      let candidates : Array[Int] = []
      append_indices(candidates, env.preferred_float)
      append_indices(candidates, env.nonpreferred_float)
      (used_ids(used_fp_marks, used_epoch), temp_fp_pool, candidates, [])
    }
  }
  let choice = @core_regalloc.choose_temp_register(
    core_class(cls),
    used,
    pool,
    fallback,
    reserved,
    need_preserve,
    cursor,
    out.num_spillslots,
  )
  out.num_spillslots = choice.next_spill_slot
  let preg : @abi.PReg = { index: choice.preg.id, class: cls }
  match cls {
    Int => mark_used(used_int_marks, preg.index, used_epoch)
    _ => mark_used(used_fp_marks, preg.index, used_epoch)
  }
  (preg, choice.next_cursor, choice.save_slot)
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

  fn preg_indices(regs : Array[@abi.PReg]) -> Array[Int] {
    let out : Array[Int] = []
    for reg in regs {
      out.push(reg.index)
    }
    out
  }

  let temp_int_pool = @core_regalloc.plan_temp_register_pool(
    used_int_regs,
    env.scratch_int,
    preg_indices(env.nonpreferred_int),
    preg_indices(env.preferred_int),
  )
  let temp_fp_pool = @core_regalloc.plan_temp_register_pool(
    used_fp_regs,
    env.scratch_float,
    preg_indices(env.nonpreferred_float),
    preg_indices(env.preferred_float),
  )
  // Vector temps share the same physical register bank as floats on current ISAs.
  let temp_vec_pool = @core_regalloc.plan_temp_register_pool(
    used_fp_regs,
    env.scratch_float,
    preg_indices(env.nonpreferred_vector),
    preg_indices(env.preferred_vector),
  )

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
      out.push_edit(block_id, inst_idx, pos, Move(mv.from, mv.to, mv.class))
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
  let active_reloads = @core_regalloc.ActiveReloadCache::new(
    alloc.num_spill_slots,
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
        if use_reg is Virtual(vreg) &&
          assigned_preg_of(vreg.id, assigned_pregs) is None &&
          fixed_use_preg(inst, i) is None {
          needs_spill_temps = true
          break
        }
      }
      if !needs_spill_temps {
        for i, def in inst.defs {
          if def.reg is Virtual(vreg) &&
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
                Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
                Virtual(vreg) =>
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
                Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
                Virtual(vreg) =>
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
              Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              Virtual(vreg) =>
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
              Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              Virtual(vreg) =>
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
        if use_reg is Virtual(vreg) &&
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
          if active_reloads.get(slot, reload_epoch) is Some(preg_id) {
            let rp : @abi.PReg = { index: preg_id, class: vreg.class }
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
              Move(Spill(slot), Reg(rp), vreg.class),
            )
            active_reloads.set(slot, rp.index, reload_epoch)
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
              Move(Reg(tmp), Spill(s), vreg.class),
            )
            out.push_edit(
              block_id,
              inst_idx,
              After,
              Move(Spill(s), Reg(tmp), vreg.class),
            )
          }
          out.push_edit(
            block_id,
            inst_idx,
            Before,
            Move(Spill(slot), Reg(tmp), vreg.class),
          )
          spill_use_tmp_epoch[vreg.id] = spill_epoch
          spill_use_tmp_idx[vreg.id] = tmp.index
          add_used_reg_marks(used_int_marks, used_fp_marks, epoch, tmp)
        }
      }

      // Allocate spilled defs to temps and store after the instruction.
      for i, def in inst.defs {
        if def.reg is Virtual(vreg) &&
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
              Move(Reg(tmp), Spill(s), vreg.class),
            )
          }
          out.push_edit(
            block_id,
            inst_idx,
            After,
            Move(Reg(tmp), Spill(slot), vreg.class),
          )
          if save_slot is Some(s) {
            out.push_edit(
              block_id,
              inst_idx,
              After,
              Move(Spill(s), Reg(tmp), vreg.class),
            )
          }
          // If this slot had an active reload register, it is now stale.
          active_reloads.clear(slot)
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
              Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              Virtual(vreg) =>
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
              Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              Virtual(vreg) =>
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
        Jump(target, args) => {
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
            Branch(cond, _, _) => [cond]
            BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
            BranchZero(r, _, _, _, _) => [r]
            BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
            Return(values) => values
            BrTable(index, _, _) => [index]
            Trap(_) => []
            Jump(_, _) => []
          }
          for r in use_regs {
            match r {
              Physical(preg) =>
                add_used_reg_marks(used_int_marks, used_fp_marks, epoch, preg)
              Virtual(vreg) =>
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
            if r is Virtual(vreg) &&
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
              if active_reloads.get(slot, reload_epoch) is Some(preg_id) {
                let rp : @abi.PReg = { index: preg_id, class: vreg.class }
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
                Move(Spill(slot), Reg(tmp), vreg.class),
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
              Physical(preg) => out.push_inst_alloc_loc(Reg(preg))
              Virtual(vreg) =>
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
