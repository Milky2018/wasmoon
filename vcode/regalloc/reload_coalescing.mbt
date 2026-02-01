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
    // Key: spill_slot, Value: (first_inst, last_inst, vreg_class)
    let slot_uses : Map[Int, (Int, Int, @abi.RegClass)] = {}
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            // Do not reload-coalesce vector values: there is no safe
            // non-allocatable vector scratch register bank, and AAPCS64 only
            // guarantees preserving the low 64 bits of V8-V15.
            if vreg.class is @abi.Vector {
              continue
            }
            match slot_uses.get(slot) {
              Some((first, _, cls)) =>
                slot_uses.set(slot, (first, inst_idx, cls))
              None => slot_uses.set(slot, (inst_idx, inst_idx, vreg.class))
            }
          }
        }
      }
    }
    // Create reload intervals for slots used multiple times.
    for slot, info in slot_uses {
      let (first_inst, last_inst, vreg_class) = info
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
  // - X19 is reserved for vmctx-related loads in the prologue when needed.
  used_int_regs.add(19) |> ignore
  // - X21 is the pinned VMContext register (enable_pinned_reg).
  used_int_regs.add(@abi.REG_VMCTX) |> ignore
  // - X20 is reserved for cached memory0 descriptor pointer when needed.
  if func.uses_mem0() {
    used_int_regs.add(@abi.REG_MEM0_DESC) |> ignore
  }
  // - X23 is reserved for extra_results_buffer when needed.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  if needs_x23_reserved {
    used_int_regs.add(23) |> ignore
  }

  // Candidate callee-saved registers for reload coalescing.
  // Only use registers that are NOT allocated to any vreg to avoid clobbering
  // live values (including parameters that may stay live across a block).
  let reload_int_regs = [20, 22, 23, 24, 25, 26, 27, 28]
  let reload_float_regs = [8, 9, 10, 11, 12, 13, 14, 15]

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
