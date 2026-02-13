// ============ Reload Coalescing ============
//
// This logic is shared by the legacy "apply allocation" path and the
// Cranelift-style regalloc-output path.
//
// Goal: when the same spill slot is used multiple times within a block, keep it
// live in a chosen register for the duration of the block interval to avoid
// redundant StackLoad instructions.

///|
/// A reload interval tracks where a reloaded value can be kept alive
/// to eliminate redundant loads from the same spill slot.
priv struct ReloadInterval {
  vreg_class : @abi.RegClass // Register class
  mut preg : @abi.PReg? // Allocated register (None = no coalescing)
}

///|
/// Compute reload intervals for spilled values in each block.
/// Returns a map: (block_id, spill_slot) -> ReloadInterval.
fn compute_reload_intervals(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> Map[(Int, Int), ReloadInterval] {
  let intervals : Map[(Int, Int), ReloadInterval] = {}
  for block_idx, block in func.blocks {
    // Track uses of spilled vregs in this block.
    // Key: spill_slot, Value: (first_inst, last_inst, vreg_class, vreg_id)
    //
    // Important: spill slots may be reused across different spilled values
    // (post-regalloc compaction). Reload coalescing is only safe when a spill
    // slot refers to a single vreg within a block; otherwise we might keep a
    // stale value in a register across a point where the slot's content
    // changes. Therefore, we disable coalescing for any spill slot that is
    // used by multiple vregs within the block.
    let slot_uses : Map[Int, (Int, Int, @abi.RegClass, Int)] = {}
    let conflicting_slots : @hashset.HashSet[Int] = @hashset.HashSet::new()
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            if conflicting_slots.contains(slot) {
              continue
            }
            // Do not reload-coalesce vector values: there is no safe
            // non-allocatable vector scratch register bank, and AAPCS64 only
            // guarantees preserving the low 64 bits of V8-V15.
            if vreg.class is @abi.Vector {
              continue
            }
            match slot_uses.get(slot) {
              Some((first, _, cls, owner_id)) =>
                if owner_id == vreg.id {
                  slot_uses.set(slot, (first, inst_idx, cls, owner_id))
                } else {
                  // Slot reused within block by different values: disable.
                  slot_uses.remove(slot) |> ignore
                  conflicting_slots.add(slot) |> ignore
                }
              None =>
                slot_uses.set(slot, (inst_idx, inst_idx, vreg.class, vreg.id))
            }
          }
        }
      }
    }
    // Create reload intervals for slots used multiple times.
    for slot, info in slot_uses {
      let (first_inst, last_inst, vreg_class, _vreg_id) = info
      if last_inst > first_inst {
        // Multiple uses - worth coalescing.
        intervals.set((block_idx, slot), { vreg_class, preg: None })
      }
    }
  }
  intervals
}

///|
/// Try to allocate registers for reload intervals.
/// Uses callee-saved registers that aren't already in use.
fn allocate_reload_registers(
  func : VCodeFunction,
  alloc : RegAllocResult,
  intervals : Map[(Int, Int), ReloadInterval],
) -> Unit {
  // Collect which registers are already allocated to virtual registers.
  // Reload coalescing must NOT clobber any register that the allocator uses
  // (including live-ins like vmctx), otherwise a StackLoad can overwrite a
  // still-live value and cause memory corruption / traps.
  let used_int_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  let used_float_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for _, preg in alloc.assignments {
    match preg.class {
      @abi.Int => used_int_regs.add(preg.index) |> ignore
      _ => used_float_regs.add(preg.index) |> ignore
    }
  }

  // Reserve special registers that are not part of the allocator pool but are
  // used by the ABI / codegen.
  let isa = @isa.ISA::current()
  // - The pinned VMContext register (AArch64: x21).
  used_int_regs.add(isa.vmctx_reg_index()) |> ignore
  // - The cached memory0 descriptor pointer register when needed.
  if func.should_cache_mem0_desc() {
    used_int_regs.add(isa.mem0_desc_reg_index()) |> ignore
  }
  if func.should_cache_func_table() {
    used_int_regs.add(isa.func_table_reg_index()) |> ignore
  }
  // - Extra results pointer register when needed.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  if needs_x23_reserved {
    used_int_regs.add(isa.extra_results_ptr_reg_index()) |> ignore
  }

  // Candidate registers for reload coalescing.
  //
  // Only use registers that are NOT allocated to any vreg to avoid clobbering
  // live values (including parameters that may stay live across a block).
  //
  // On amd64, we prefer using the ISA's callee-saved pool (minus pinned/cached
  // roles) as returned by the MachineEnv. SysV has no callee-saved XMM regs, so
  // we disable float reload coalescing there.
  let reload_int_regs : Array[Int] = []
  let reload_float_regs : Array[Int] = []
  match isa {
    @isa.AArch64 => {
      // AArch64: use a subset of callee-saved regs that are not used by Wasmoon's ABI roles.
      for idx in [20, 22, 23, 24, 25, 26, 27, 28] {
        reload_int_regs.push(idx)
      }
      for idx in [8, 9, 10, 11, 12, 13, 14, 15] {
        reload_float_regs.push(idx)
      }
    }
    @isa.AMD64 => {
      let env = isa.machine_env(
        reserve_mem0_desc=func.should_cache_mem0_desc(),
        reserve_func_table=func.should_cache_func_table(),
        reserve_extra_results_ptr=needs_x23_reserved,
      )
      for r in env.callee_saved_int {
        // rbp is already excluded from MachineEnv; still, keep it out here too.
        if r.index == isa.fp_reg_index() {
          continue
        }
        reload_int_regs.push(r.index)
      }
    }
  }

  // Per-block allocation to avoid conflicts within a block.
  for block_idx, _block in func.blocks {
    // Track which reload registers are in use within this block.
    let block_int_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    let block_float_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    // Allocate reload registers for intervals in this block.
    for key, interval in intervals {
      let (b_idx, _) = key
      if b_idx != block_idx {
        continue
      }
      match interval.vreg_class {
        @abi.Int =>
          for idx in reload_int_regs {
            if used_int_regs.contains(idx) || block_int_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_int_used.add(idx) |> ignore
            break
          }
        @abi.Vector => ()
        _ =>
          for idx in reload_float_regs {
            if used_float_regs.contains(idx) || block_float_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_float_used.add(idx) |> ignore
            break
          }
      }
    }
  }
}
