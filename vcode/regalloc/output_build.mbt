// Build Cranelift-style regalloc `Output` for emission.
//
// This pass does not rewrite VCode instructions. Instead, it produces:
// - Per-operand allocations for each instruction/terminator.
// - An edit stream (moves between regs and spill slots) that the emitter
//   interleaves with instructions.

///|
fn vreg_home_loc(vreg : @abi.VReg, alloc : RegAllocResult) -> Loc {
  match alloc.assignments.get(vreg.id) {
    Some(preg) => Reg(preg)
    None =>
      match alloc.spill_slots.get(vreg.id) {
        Some(slot) => Spill(slot)
        None => abort("missing allocation for vreg \{vreg.id}")
      }
  }
}

///|
fn reg_home_loc(reg : @abi.Reg, alloc : RegAllocResult) -> Loc {
  match reg {
    @abi.Physical(preg) => Reg(preg)
    @abi.Virtual(vreg) => vreg_home_loc(vreg, alloc)
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
fn add_used_reg(
  used_int : @hashset.HashSet[Int],
  used_fp : @hashset.HashSet[Int],
  preg : @abi.PReg,
) -> Unit {
  match preg.class {
    @abi.Int => used_int.add(preg.index) |> ignore
    _ => used_fp.add(preg.index) |> ignore
  }
}

///|
fn pick_temp_preg(
  out : Output,
  isa : @isa.ISA,
  env : @isa.MachineEnv,
  cls : @abi.RegClass,
  used_int : @hashset.HashSet[Int],
  used_fp : @hashset.HashSet[Int],
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
        if !used_int.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Int }
          used_int.add(idx) |> ignore
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
        if !used_int.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Int }
          used_int.add(idx) |> ignore
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
        if !used_fp.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Vector }
          used_fp.add(idx) |> ignore
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
        if !used_fp.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: @abi.Vector }
          used_fp.add(idx) |> ignore
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
        if !used_fp.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: cls }
          used_fp.add(idx) |> ignore
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
        if !used_fp.contains(idx) {
          let preg = @abi.PReg::{ index: idx, class: cls }
          used_fp.add(idx) |> ignore
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
  alloc : RegAllocResult,
  isa : @isa.ISA,
  settings : @abi.ABISettings,
) -> Output {
  let out = Output::new()
  out.num_spillslots = alloc.num_spill_slots

  // Param allocations (used by the prologue).
  for p in func.params {
    out.param_locs.push(vreg_home_loc(p, alloc))
  }

  // Coalesced reload intervals.
  let reload_intervals = compute_reload_intervals(func, alloc)
  allocate_reload_registers(func, alloc, reload_intervals)

  // Temp-reg pools for local reloads when no coalescing is available.
  let used_int_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  let used_fp_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for _, preg in alloc.assignments {
    add_used_reg(used_int_regs, used_fp_regs, preg)
  }
  let reserve_extra_results_ptr = func.needs_extra_results_ptr() ||
    func.calls_multi_value_function()
  let reserve_mem0_desc = func.uses_mem0()
  let reserve_func_table = func.uses_func_table()
  let env = isa.machine_env(
    settings~,
    reserve_mem0_desc~,
    reserve_func_table~,
    reserve_extra_results_ptr~,
  )

  // Reserve dedicated scratch regs (used by the move resolver).
  for idx in env.scratch_int {
    used_int_regs.add(idx) |> ignore
  }
  for idx in env.scratch_float {
    used_fp_regs.add(idx) |> ignore
  }

  // Reserve pinned registers.
  used_int_regs.add(isa.vmctx_reg_index()) |> ignore
  if reserve_mem0_desc {
    used_int_regs.add(isa.mem0_desc_reg_index()) |> ignore
  }
  if reserve_func_table {
    used_int_regs.add(isa.func_table_reg_index()) |> ignore
  }
  if reserve_extra_results_ptr {
    used_int_regs.add(isa.extra_results_ptr_reg_index()) |> ignore
  }

  // Temp-reg pools for local reloads/move resolution:
  // - Always include scratch regs.
  // - Prefer higher-index regs (avoid common arg/return regs on most ABIs).
  fn push_temp_reg(
    pool : Array[Int],
    used : @hashset.HashSet[Int],
    idx : Int,
  ) -> Unit {
    // Pool sizes are tiny; linear scan avoids extra dependencies.
    let mut already = false
    for v in pool {
      if v == idx {
        already = true
      }
    }
    if !used.contains(idx) && !already {
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

  // Convert fixed-reg constraint edits to output edits.
  for key, edits in alloc.inst_edits {
    let (block_id, inst_idx) = key
    push_resolved_moves(out, block_id, inst_idx, Before, edits.before)
    push_resolved_moves(out, block_id, inst_idx, After, edits.after)
  }

  // Walk blocks and create per-operand allocations. Emit extra edits for spills
  // (reloads before uses, stores after defs) as needed.
  for block_id, block in func.blocks {
    let active_reloads : Map[Int, @abi.PReg] = {}
    let mut temp_cursor = 0
    for inst_idx, inst in block.insts {
      let used_int : @hashset.HashSet[Int] = @hashset.HashSet::new()
      let used_fp : @hashset.HashSet[Int] = @hashset.HashSet::new()

      // First, mark all registers that will be used by non-spilled operands at
      // this instruction (including fixed-reg constraints).
      for i, def in inst.defs {
        match fixed_def_preg(inst, i) {
          Some(preg) => add_used_reg(used_int, used_fp, preg)
          None =>
            match def.reg {
              @abi.Physical(preg) => add_used_reg(used_int, used_fp, preg)
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => add_used_reg(used_int, used_fp, preg)
                  None => ()
                }
            }
        }
      }
      for i, use_reg in inst.uses {
        match fixed_use_preg(inst, i) {
          Some(preg) => add_used_reg(used_int, used_fp, preg)
          None =>
            match use_reg {
              @abi.Physical(preg) => add_used_reg(used_int, used_fp, preg)
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => add_used_reg(used_int, used_fp, preg)
                  None => ()
                }
            }
        }
      }
      // Also reserve any registers mentioned in fixed-reg constraint edits at this point.
      // If we steal one of these registers and later restore it, we'd clobber the move result.
      match alloc.inst_edits.get((block_id, inst_idx)) {
        Some(edits) => {
          for mv in edits.before {
            match mv.from {
              Reg(p) => add_used_reg(used_int, used_fp, p)
              _ => ()
            }
            match mv.to {
              Reg(p) => add_used_reg(used_int, used_fp, p)
              _ => ()
            }
          }
          for mv in edits.after {
            match mv.from {
              Reg(p) => add_used_reg(used_int, used_fp, p)
              _ => ()
            }
            match mv.to {
              Reg(p) => add_used_reg(used_int, used_fp, p)
              _ => ()
            }
          }
        }
        None => ()
      }

      // Reload spilled uses into temps as needed.
      let spill_regs : Map[Int, @abi.PReg] = {}
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None &&
          alloc.spill_slots.get(vreg.id) is Some(slot) {
          // Fixed-reg constraints are handled by constraint edits.
          if fixed_use_preg(inst, i) is Some(_) {
            continue
          }
          // If already assigned a temp within this instruction, reuse it.
          if spill_regs.get(vreg.id) is Some(_) {
            continue
          }
          // If the slot is currently active in a coalesced reload reg, reuse it.
          if active_reloads.get(slot) is Some(rp) {
            spill_regs.set(vreg.id, rp)
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
            active_reloads.set(slot, rp)
            spill_regs.set(vreg.id, rp)
            add_used_reg(used_int, used_fp, rp)
            continue
          }
          // Otherwise, load into a scratch/temporary register local to this instruction.
          let (tmp, new_cursor, save_slot) = pick_temp_preg(
            out,
            isa,
            env,
            vreg.class,
            used_int,
            used_fp,
            temp_int_pool,
            temp_fp_pool,
            temp_vec_pool,
            true,
            temp_cursor,
          )
          temp_cursor = new_cursor
          // If we had to steal a register, save/restore around the instruction.
          match save_slot {
            Some(s) => {
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
            None => ()
          }
          out.push_edit(
            block_id,
            inst_idx,
            Before,
            Edit::Move(Spill(slot), Reg(tmp), vreg.class),
          )
          spill_regs.set(vreg.id, tmp)
          add_used_reg(used_int, used_fp, tmp)
        }
      }

      // Allocate spilled defs to temps and store after the instruction.
      let spill_def_regs : Map[Int, @abi.PReg] = {}
      for i, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None &&
          alloc.spill_slots.get(vreg.id) is Some(slot) {
          // Fixed-reg constraints are handled by constraint edits.
          if fixed_def_preg(inst, i) is Some(_) {
            continue
          }
          let (tmp, new_cursor, save_slot) = pick_temp_preg(
            out,
            isa,
            env,
            vreg.class,
            used_int,
            used_fp,
            temp_int_pool,
            temp_fp_pool,
            temp_vec_pool,
            true,
            temp_cursor,
          )
          temp_cursor = new_cursor
          spill_def_regs.set(vreg.id, tmp)
          add_used_reg(used_int, used_fp, tmp)
          match save_slot {
            Some(s) =>
              out.push_edit(
                block_id,
                inst_idx,
                Before,
                Edit::Move(Reg(tmp), Spill(s), vreg.class),
              )
            None => ()
          }
          out.push_edit(
            block_id,
            inst_idx,
            After,
            Edit::Move(Reg(tmp), Spill(slot), vreg.class),
          )
          match save_slot {
            Some(s) =>
              out.push_edit(
                block_id,
                inst_idx,
                After,
                Edit::Move(Spill(s), Reg(tmp), vreg.class),
              )
            None => ()
          }
          // If this slot had an active reload register, it is now stale.
          active_reloads.remove(slot) |> ignore
        }
      }

      // Record operand allocations for this instruction.
      let locs : Array[Loc] = []
      // defs first.
      for i, def in inst.defs {
        match fixed_def_preg(inst, i) {
          Some(preg) => locs.push(Reg(preg))
          None =>
            match def.reg {
              @abi.Physical(preg) => locs.push(Reg(preg))
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => locs.push(Reg(preg))
                  None =>
                    match spill_def_regs.get(vreg.id) {
                      Some(tmp) => locs.push(Reg(tmp))
                      None =>
                        abort("missing spilled def temp for vreg \{vreg.id}")
                    }
                }
            }
        }
      }
      // then uses.
      for i, use_reg in inst.uses {
        match fixed_use_preg(inst, i) {
          Some(preg) => locs.push(Reg(preg))
          None =>
            match use_reg {
              @abi.Physical(preg) => locs.push(Reg(preg))
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => locs.push(Reg(preg))
                  None =>
                    match spill_regs.get(vreg.id) {
                      Some(tmp) => locs.push(Reg(tmp))
                      None =>
                        abort("missing spilled use temp for vreg \{vreg.id}")
                    }
                }
            }
        }
      }
      out.push_inst_allocs(
        block_id,
        inst_idx,
        false,
        inst.defs.length(),
        inst.uses.length(),
        locs,
      )
    }

    // Terminator allocations/edits.
    if block.terminator is Some(term) {
      let term_inst = block.insts.length()

      // Jump args: materialize block params at predecessor end.
      match term {
        @instr.Jump(target, args) => {
          let target_block = func.blocks[target]
          let moves : Array[RegMove] = []
          for i, param in target_block.params {
            if i >= args.length() {
              break
            }
            let from_loc = reg_home_loc(args[i], alloc)
            let to_loc = vreg_home_loc(param, alloc)
            moves.push({ from: from_loc, to: to_loc, class: param.class })
          }
          if !moves.is_empty() {
            push_resolved_moves(out, block_id, term_inst, Before, moves)
          }
          // Jump itself doesn't consume regs in the emitter; record an empty range.
          out.push_inst_allocs(block_id, term_inst, true, 0, 0, [])
        }
        _ => {
          // For other terminators, treat their operands like uses.
          let used_int : @hashset.HashSet[Int] = @hashset.HashSet::new()
          let used_fp : @hashset.HashSet[Int] = @hashset.HashSet::new()
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
              @abi.Physical(preg) => add_used_reg(used_int, used_fp, preg)
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => add_used_reg(used_int, used_fp, preg)
                  None => ()
                }
            }
          }
          let spill_regs : Map[Int, @abi.PReg] = {}
          for r in use_regs {
            if r is @abi.Virtual(vreg) &&
              alloc.assignments.get(vreg.id) is None &&
              alloc.spill_slots.get(vreg.id) is Some(slot) {
              if spill_regs.get(vreg.id) is Some(_) {
                continue
              }
              if active_reloads.get(slot) is Some(rp) {
                spill_regs.set(vreg.id, rp)
                continue
              }
              let (tmp, new_cursor, _save_slot) = pick_temp_preg(
                out,
                isa,
                env,
                vreg.class,
                used_int,
                used_fp,
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
              spill_regs.set(vreg.id, tmp)
              add_used_reg(used_int, used_fp, tmp)
            }
          }
          let locs : Array[Loc] = []
          for r in use_regs {
            match r {
              @abi.Physical(preg) => locs.push(Reg(preg))
              @abi.Virtual(vreg) =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => locs.push(Reg(preg))
                  None =>
                    match spill_regs.get(vreg.id) {
                      Some(tmp) => locs.push(Reg(tmp))
                      None =>
                        abort(
                          "missing spilled terminator use temp for vreg \{vreg.id}",
                        )
                    }
                }
            }
          }
          out.push_inst_allocs(
            block_id,
            term_inst,
            true,
            0,
            use_regs.length(),
            locs,
          )
        }
      }
    }
  }
  out
}
