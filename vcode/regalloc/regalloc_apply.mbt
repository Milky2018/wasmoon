// ============ Apply Allocation ============

// Scratch registers for spill/reload (not allocatable)
// X16 is used for integer spills, we can use X17 if needed

///|
/// Convert a `Loc` that must be a register into a `PReg`.
fn loc_as_preg(loc : Loc) -> @abi.PReg {
  match loc {
    Reg(preg) => preg
    Spill(_) => abort("expected register loc")
  }
}

///|
/// Decode the historical spilled-PReg encoding into `Loc`.
fn preg_to_loc(preg : @abi.PReg) -> Loc {
  if preg.is_spilled() {
    Spill(preg.get_spill_slot())
  } else {
    Reg(preg)
  }
}

///|
/// Apply register allocation results to a VCode function
/// Handles spilled registers by inserting StackLoad/StackStore instructions
pub fn apply_allocation(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> VCodeFunction {
  let new_func = func.clone_base()
  new_func.set_num_spill_slots(alloc.num_spill_slots)

  // Compute reload intervals for spill coalescing
  let reload_intervals = compute_reload_intervals(func, alloc)
  allocate_reload_registers(func, alloc, reload_intervals)

  // Convert function parameters
  // Note: all params use X0-X7 (int) or V0-V7 (float)
  // vmctx is an explicit param in the function signature
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
  let mut int_idx = 0
  let mut float_idx = 0

  // For spilled params, we must store the incoming ABI register to the spill slot
  // in the entry block so subsequent reloads see the correct value.
  let spilled_param_stores : Array[(@abi.PReg, Int)] = []
  for param in func.params {
    match alloc.assignments.get(param.id) {
      Some(preg) => {
        // Parameter is assigned to physical register
        let new_vreg : @abi.VReg = { id: param.id, class: param.class }
        new_func.params.push(new_vreg)
        // Check if param is in register or on stack, and whether it needs a move
        let (default_preg_opt, is_int) : (@abi.PReg?, Bool) = match
          param.class {
          @abi.Int =>
            if int_idx < max_int_params {
              (Some(@abi.PReg::{ index: int_idx, class: @abi.Int }), true)
            } else {
              (None, true) // Stack param
            }
          @abi.Float32 =>
            if float_idx < max_float_params {
              (
                Some(@abi.PReg::{ index: float_idx, class: @abi.Float32 }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Float64 =>
            if float_idx < max_float_params {
              (
                Some(@abi.PReg::{ index: float_idx, class: @abi.Float64 }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Vector =>
            // Vector uses same Vn registers as Float
            if float_idx < max_float_params {
              (Some(@abi.PReg::{ index: float_idx, class: @abi.Vector }), false)
            } else {
              (None, false)
            }
        }
        // Update counters
        if is_int {
          int_idx += 1
        } else {
          float_idx += 1
        }
        // Decide whether to store preg in param_pregs
        match default_preg_opt {
          Some(default_preg) =>
            if preg.index != default_preg.index {
              new_func.param_pregs.push(Some(preg))
            } else {
              new_func.param_pregs.push(None) // No move needed
            }
          None =>
            // Stack param - always store the assigned register
            new_func.param_pregs.push(Some(preg))
        }
      }
      None => {
        new_func.params.push(param)
        new_func.param_pregs.push(None)

        // If the param is spilled, capture a store from the incoming ABI register
        // to its spill slot. This makes spilling params safe.
        if alloc.spill_slots.get(param.id) is Some(slot) {
          match param.class {
            @abi.Int =>
              if int_idx < max_int_params {
                spilled_param_stores.push(
                  ({ index: int_idx, class: @abi.Int }, slot),
                )
              }
            @abi.Float32 | @abi.Float64 =>
              if float_idx < max_float_params {
                spilled_param_stores.push(
                  ({ index: float_idx, class: @abi.Float64 }, slot),
                )
              }
            @abi.Vector =>
              if float_idx < max_float_params {
                spilled_param_stores.push(
                  ({ index: float_idx, class: @abi.Vector }, slot),
                )
              }
          }
        }

        // Still need to increment indices for unassigned params
        match param.class {
          @abi.Int => int_idx += 1
          @abi.Float32 | @abi.Float64 | @abi.Vector => float_idx += 1
        }
      }
    }
  }

  // Copy results
  for r in func.results {
    new_func.results.push(r)
  }

  // Copy result types for multi-value return support
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }

  // Process each block
  for block_idx, block in func.blocks {
    let new_block = new_func.new_block()

    // Entry block: materialize spilled params into spill slots.
    if block_idx == 0 {
      for entry in spilled_param_stores {
        let (src_preg, slot) = entry
        let store_inst = @instr.VCodeInst::new(@instr.StackStore(slot * 8))
        store_inst.add_use(@abi.Physical(src_preg))
        new_block.add_inst(store_inst)
      }
    }

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Block-level scratch register counter to avoid aliasing across instructions
    let mut block_scratch_idx = 0

    // Track which spill slots have been loaded into coalesced reload registers
    // Key: spill_slot, Value: preg holding the reloaded value
    let active_reloads : Map[Int, @abi.PReg] = {}

    // Precompute per-block defs/uses for swap-aware jump-arg handling.
    let vreg_def_info : Map[Int, (Int, Int)] = {}
    let vreg_used_in_insts : Set[Int] = Set::new()
    let vreg_used_in_term : Set[Int] = Set::new()
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          vreg_used_in_insts.add(vreg.id)
        }
      }
      for def_pos, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
          vreg_def_info.set(vreg.id, (inst_idx, def_pos))
        }
      }
    }
    if block.terminator is Some(term) {
      let term_uses = match term {
        @instr.VCodeTerminator::Jump(_, args)
        | @instr.VCodeTerminator::Return(args) => args
        @instr.VCodeTerminator::Branch(cond, _, _)
        | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
        | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
        @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
        @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
        @instr.VCodeTerminator::Trap(_) => []
      }
      for use_reg in term_uses {
        if use_reg is @abi.Virtual(vreg) {
          vreg_used_in_term.add(vreg.id)
        }
      }
    }
    let jump_arg_candidates : Map[Int, (Int, Int)] = {}
    let jump_arg_counts : Map[Int, Int] = {}
    if block.terminator is Some(@instr.VCodeTerminator::Jump(_, args)) {
      for arg in args {
        if arg is @abi.Virtual(vreg) &&
          vreg_used_in_term.contains(vreg.id) &&
          !vreg_used_in_insts.contains(vreg.id) {
          let count = jump_arg_counts.get(vreg.id).unwrap_or(0)
          jump_arg_counts.set(vreg.id, count + 1)
          if vreg_def_info.get(vreg.id) is Some((def_idx, def_pos)) {
            let def_inst = block.insts[def_idx]
            let has_fixed = def_pos < def_inst.def_constraints.length() &&
              def_inst.def_constraints[def_pos] is @abi.FixedReg(_)
            if !has_fixed {
              jump_arg_candidates.set(vreg.id, (def_idx, def_pos))
            }
          }
        }
      }
    }
    let orig_inst_to_new_idx : Map[Int, Int] = {}

    // Process instructions
    for inst_idx, inst in block.insts {
      // First, insert reload instructions for any spilled uses
      // Track which scratch registers are used for each spilled vreg
      let spill_regs : Map[Int, @abi.PReg] = {}

      // X16, X17 are the only truly safe scratch registers because:
      // - X0-X7: parameter registers
      // - X8-X15: caller-saved temporaries (may be in use)
      // - X18: platform reserved (TLS on some platforms)
      // - X19+: allocatable callee-saved registers
      //
      // For uses with FixedReg constraints (e.g., CallPtr/ReturnCallIndirect args),
      // constraint edits will handle the reload, so we skip normal spilled use handling.

      // First, collect registers that are in use by non-spilled uses
      // to avoid clobbering them with scratch register reloads
      let used_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          match alloc.assignments.get(vreg.id) {
            Some(preg) => used_regs.add(preg.index) |> ignore
            None => ()
          }
        }
      }
      let mut inst_spill_idx = 0
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None {
          // This vreg is spilled, need to reload
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            let scratch_class = match vreg.class {
              @abi.Float32 | @abi.Float64 => @abi.Float64
              _ => vreg.class
            }

            // Determine how to handle this spilled use
            // Check FixedReg constraint first - constraint edits will handle the reload
            if i < inst.use_constraints.length() &&
              inst.use_constraints[i] is @abi.FixedReg(_) {
              // This use has a FixedReg constraint - constraint edits will handle the reload
              // Use spilled encoding so use rewriting puts the fixed register
              let spilled_preg = @abi.PReg::spilled(slot, scratch_class)
              spill_regs.set(vreg.id, spilled_preg)
            } else if active_reloads.get(slot) is Some(reload_preg) {
              // Regular spilled uses (non-CallIndirect instructions)
              // Check if we have a coalesced reload register for this slot
              // Value already loaded - reuse the register (no new load needed)
              spill_regs.set(vreg.id, reload_preg)
            } else if reload_intervals.get((block_idx, slot)) is Some(interval) &&
              interval.preg is Some(reload_preg) {
              // First use of this slot in the interval - load into coalesced register
              spill_regs.set(vreg.id, reload_preg)
              active_reloads.set(slot, reload_preg)
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(reload_preg) })
              new_block.add_inst(reload_inst)
            } else {
              // No coalescing available - use scratch registers X16, X17
              let scratch_candidates = [16, 17]
              let mut scratch_idx = inst_spill_idx % 2
              // Find a scratch register that's not already in use
              let mut attempts = 0
              while used_regs.contains(scratch_candidates[scratch_idx]) &&
                    attempts < 2 {
                scratch_idx = (scratch_idx + 1) % 2
                attempts += 1
              }
              let scratch_preg : @abi.PReg = {
                index: scratch_candidates[scratch_idx],
                class: scratch_class,
              }
              inst_spill_idx = inst_spill_idx + 1
              block_scratch_idx = block_scratch_idx + 1
              spill_regs.set(vreg.id, scratch_preg)
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              new_block.add_inst(reload_inst)
            }
          }
        }
      }

      // Check if any definitions are spilled - collect spilled defs WITHOUT fixed constraints
      // Defs with fixed constraints are handled by process_constraints, not here
      let spilled_defs : Array[(@abi.VReg, Int)] = []
      for i, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None &&
          alloc.spill_slots.get(vreg.id) is Some(slot) {
          // Skip defs with fixed constraints - they are handled by constraint processing
          let has_fixed_constraint = if i < inst.def_constraints.length() {
            inst.def_constraints[i] is @abi.FixedReg(_)
          } else {
            false
          }
          if !has_fixed_constraint {
            spilled_defs.push((vreg, slot))
          }
        }
      }

      // Create new instruction with rewritten registers
      let new_inst = @instr.VCodeInst::new(inst.opcode)

      // Rewrite definitions - use X16, X17 as scratch for spilled defs
      // But for defs with fixed constraints, use the fixed register
      let spill_scratch_map : Map[Int, @abi.PReg] = {} // vreg.id -> scratch preg
      for i, def in inst.defs {
        match def.reg {
          @abi.Virtual(vreg) => {
            let fixed_preg_opt = if i < inst.def_constraints.length() {
              match inst.def_constraints[i] {
                @abi.FixedReg(preg) => Some(preg)
                _ => None
              }
            } else {
              None
            }
            match fixed_preg_opt {
              Some(fixed_preg) =>
                // Use the fixed register - constraint processing handles any move/spill.
                new_inst.add_def({ reg: @abi.Physical(fixed_preg) })
              None =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => new_inst.add_def({ reg: @abi.Physical(preg) })
                  None => {
                    // Spilled without constraint: use X16, X17 as scratch registers
                    let scratch_class = match vreg.class {
                      @abi.Float32 | @abi.Float64 => @abi.Float64
                      _ => vreg.class
                    }
                    let scratch_indices = [16, 17]
                    let scratch_preg : @abi.PReg = {
                      index: scratch_indices[block_scratch_idx % 2],
                      class: scratch_class,
                    }
                    block_scratch_idx = block_scratch_idx + 1
                    spill_scratch_map.set(vreg.id, scratch_preg)
                    new_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                  }
                }
            }
          }
          @abi.Physical(_) => new_inst.add_def(def)
        }
      }

      // Rewrite uses
      for i, use_reg in inst.uses {
        match use_reg {
          @abi.Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => {
                // Preserve FixedReg constraints in the rewritten instruction.
                // Constraint processing already inserts the needed move(s).
                let fixed_preg_opt = if i < inst.use_constraints.length() {
                  match inst.use_constraints[i] {
                    @abi.FixedReg(fixed_preg) => Some(fixed_preg)
                    _ => None
                  }
                } else {
                  None
                }
                match fixed_preg_opt {
                  Some(fixed_preg) =>
                    new_inst.add_use(@abi.Physical(fixed_preg))
                  None => new_inst.add_use(@abi.Physical(preg))
                }
              }
              None =>
                // Spilled: use the scratch register we reloaded into
                match spill_regs.get(vreg.id) {
                  Some(scratch_preg) =>
                    // Check if scratch_preg is a spilled encoding (meaning FixedReg constraint)
                    if scratch_preg.is_spilled() {
                      // Use the fixed register from the constraint
                      // Constraint edits will load the value there
                      guard i < inst.use_constraints.length() else {
                        abort("spilled encoding without constraint")
                      }
                      guard inst.use_constraints[i] is @abi.FixedReg(fixed_preg) else {
                        abort("spilled encoding without FixedReg constraint")
                      }
                      new_inst.add_use(@abi.Physical(fixed_preg))
                    } else {
                      new_inst.add_use(@abi.Physical(scratch_preg))
                    }
                  None => {
                    // Fallback: use X16 if somehow not in spill_regs
                    let scratch_preg : @abi.PReg = {
                      index: 16,
                      class: vreg.class,
                    }
                    new_inst.add_use(@abi.Physical(scratch_preg))
                  }
                }
            }
          @abi.Physical(preg) => {
            let fixed_preg_opt = if i < inst.use_constraints.length() {
              match inst.use_constraints[i] {
                @abi.FixedReg(fixed_preg) => Some(fixed_preg)
                _ => None
              }
            } else {
              None
            }
            match fixed_preg_opt {
              Some(fixed_preg) => new_inst.add_use(@abi.Physical(fixed_preg))
              None => new_inst.add_use(@abi.Physical(preg))
            }
          }
        }
      }

      // Process constraint edits: insert moves before the instruction
      // Fixed register constraint handling
      // Use parallel move resolver to handle cyclic dependencies
      if alloc.inst_edits.get((block_idx, inst_idx)) is Some(edits) {
        let resolved_moves = resolve_parallel_moves(edits.before)
        // Track which spill slots have been reloaded in this batch for coalescing
        let reloaded_slots : Map[Int, @abi.PReg] = {}
        for mv in resolved_moves {
          if mv.to.is_spilled() {
            // Store to spill slot.
            let to_slot = mv.to.get_spill_slot()
            if mv.from.is_spilled() {
              // Spill-to-spill move: reload via scratch, then store.
              let from_slot = mv.from.get_spill_slot()
              if reloaded_slots.get(from_slot) is Some(source_preg) {
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(source_preg))
                new_block.add_inst(store_inst)
              } else {
                let scratch_class = match mv.class {
                  @abi.Float32 | @abi.Float64 => @abi.Float64
                  _ => mv.class
                }
                let scratch_preg : @abi.PReg = {
                  index: 16,
                  class: scratch_class,
                }
                let reload_inst = @instr.VCodeInst::new(
                  StackLoad(from_slot * 8),
                )
                reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                new_block.add_inst(reload_inst)
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(scratch_preg))
                new_block.add_inst(store_inst)
              }
            } else {
              let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
              store_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
              new_block.add_inst(store_inst)
            }
          } else if mv.from.is_spilled() {
            // Reload from spill slot into a register.
            let slot = mv.from.get_spill_slot()
            if reloaded_slots.get(slot) is Some(source_preg) {
              // This slot was already reloaded - use mov instead of another load
              let move_inst = @instr.VCodeInst::new(Move)
              move_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
              move_inst.add_use(@abi.Physical(source_preg))
              new_block.add_inst(move_inst)
            } else {
              // First reload of this slot - emit StackLoad and record
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
              new_block.add_inst(reload_inst)
              reloaded_slots.set(slot, loc_as_preg(mv.to))
            }
          } else {
            // Register to register move
            let move_inst = @instr.VCodeInst::new(Move)
            move_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
            move_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
            new_block.add_inst(move_inst)
          }
        }
      }
      new_block.add_inst(new_inst)
      orig_inst_to_new_idx.set(inst_idx, new_block.insts.length() - 1)

      // Process constraint edits: insert moves after the instruction
      // Use parallel move resolver for consistency (though after moves rarely conflict)
      if alloc.inst_edits.get((block_idx, inst_idx)) is Some(edits) {
        let resolved_moves = resolve_parallel_moves(edits.after)
        for mv in resolved_moves {
          if mv.to.is_spilled() {
            // Store to spill slot from source register
            let slot = mv.to.get_spill_slot()
            let store_inst = @instr.VCodeInst::new(StackStore(slot * 8))
            store_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
            new_block.add_inst(store_inst)
          } else {
            // Register to register move
            let move_inst = @instr.VCodeInst::new(Move)
            move_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
            move_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
            new_block.add_inst(move_inst)
          }
        }
      }

      // Insert spill instructions after the defining instruction for ALL spilled defs
      for entry in spilled_defs {
        let (vreg, slot) = entry
        let spill_inst = @instr.VCodeInst::new(StackStore(slot * 8))
        let scratch_preg = spill_scratch_map.get(vreg.id).unwrap()
        spill_inst.add_use(@abi.Physical(scratch_preg))
        new_block.add_inst(spill_inst)
      }
    }

    // Rewrite terminator
    if block.terminator is Some(term) {
      let new_term = match term {
        Jump(target, args) => {
          // Implement SSA block argument passing at the machine level.
          // Block params are SSA defs at target entry; here we materialize the
          // incoming values into the allocated locations for those params.

          fn vreg_location(vreg : @abi.VReg) -> @abi.PReg {
            match alloc.assignments.get(vreg.id) {
              Some(p) => p
              None =>
                match alloc.spill_slots.get(vreg.id) {
                  Some(slot) => @abi.PReg::spilled(slot, vreg.class)
                  None => abort("missing allocation")
                }
            }
          }

          fn reg_location(reg : @abi.Reg) -> @abi.PReg {
            match reg {
              @abi.Physical(p) => p
              @abi.Virtual(v) => vreg_location(v)
            }
          }

          let moves : Array[RegMove] = []
          let move_src_vregs : Array[Int?] = []
          if target >= 0 && target < func.blocks.length() {
            let target_block = func.blocks[target]
            for i, param in target_block.params {
              if i >= args.length() {
                break
              }
              let from_preg = reg_location(args[i])
              let to_preg = vreg_location(param)

              // Same location: nothing to do.
              // Compare both index and register bank (int vs float/vector).
              let same_bank = match (from_preg.class, to_preg.class) {
                (@abi.Int, @abi.Int) => true
                (
                  @abi.Float32
                  | @abi.Float64
                  | @abi.Vector,
                  @abi.Float32
                  | @abi.Float64
                  | @abi.Vector,
                ) => true
                _ => false
              }
              if from_preg.index == to_preg.index && same_bank {
                continue
              }
              moves.push({
                from: preg_to_loc(from_preg),
                to: preg_to_loc(to_preg),
                class: param.class,
              })
              let src_vreg_id = match args[i] {
                @abi.Virtual(vreg) => Some(vreg.id)
                _ => None
              }
              move_src_vregs.push(src_vreg_id)
            }
          }

          // Swap-aware jump-arg coalescing: avoid 2-cycle swaps by redirecting
          // a locally-defined jump arg into a scratch register when possible.
          if !moves.is_empty() && !jump_arg_candidates.is_empty() {
            fn same_preg(a : @abi.PReg, b : @abi.PReg) -> Bool {
              a.index == b.index
            }

            fn inst_uses_preg(
              inst : @instr.VCodeInst,
              preg : @abi.PReg,
            ) -> Bool {
              for def in inst.defs {
                if def.reg is @abi.Physical(p) && same_preg(p, preg) {
                  return true
                }
              }
              for use_reg in inst.uses {
                if use_reg is @abi.Physical(p) && same_preg(p, preg) {
                  return true
                }
              }
              false
            }

            fn scratch_available(
              new_block : @block.VCodeBlock,
              def_new_idx : Int,
              preg : @abi.PReg,
            ) -> Bool {
              for i in (def_new_idx + 1)..<new_block.insts.length() {
                if inst_uses_preg(new_block.insts[i], preg) {
                  return false
                }
              }
              true
            }

            fn pick_scratch_reg(
              new_block : @block.VCodeBlock,
              def_new_idx : Int,
            ) -> @abi.PReg? {
              let scratch_regs = [@abi.SCRATCH_REG_1, @abi.SCRATCH_REG_2]
              for reg_idx in scratch_regs {
                let preg : @abi.PReg = { index: reg_idx, class: @abi.Int }
                if scratch_available(new_block, def_new_idx, preg) {
                  return Some(preg)
                }
              }
              None
            }

            let rewritten : Set[Int] = Set::new()
            let mut broke_cycle = false
            for i in 0..<moves.length() {
              if broke_cycle {
                break
              }
              let mv_i = moves[i]
              if mv_i.from.is_spilled() || mv_i.to.is_spilled() {
                continue
              }
              if mv_i.class is @abi.Int {
                ()
              } else {
                continue
              }
              for j in (i + 1)..<moves.length() {
                let mv_j = moves[j]
                if mv_j.from.is_spilled() || mv_j.to.is_spilled() {
                  continue
                }
                if mv_j.class is @abi.Int {
                  ()
                } else {
                  continue
                }
                if !same_preg(loc_as_preg(mv_i.from), loc_as_preg(mv_j.to)) ||
                  !same_preg(loc_as_preg(mv_i.to), loc_as_preg(mv_j.from)) {
                  continue
                }
                fn try_rewrite_move(
                  move_idx : Int,
                  moves : Array[RegMove],
                  move_src_vregs : Array[Int?],
                  jump_arg_candidates : Map[Int, (Int, Int)],
                  jump_arg_counts : Map[Int, Int],
                  alloc : RegAllocResult,
                  orig_inst_to_new_idx : Map[Int, Int],
                  new_block : @block.VCodeBlock,
                  rewritten : Set[Int],
                ) -> Bool {
                  guard move_idx < move_src_vregs.length() else { return false }
                  guard move_src_vregs[move_idx] is Some(vreg_id) else {
                    return false
                  }
                  if jump_arg_counts.get(vreg_id).unwrap_or(0) != 1 {
                    return false
                  }
                  if rewritten.contains(vreg_id) {
                    return false
                  }
                  guard jump_arg_candidates.get(vreg_id)
                    is Some((def_idx, def_pos)) else {
                    return false
                  }
                  guard alloc.assignments.get(vreg_id) is Some(assigned_preg) else {
                    return false
                  }
                  if assigned_preg.class is @abi.Int {
                    ()
                  } else {
                    return false
                  }
                  guard orig_inst_to_new_idx.get(def_idx) is Some(def_new_idx) else {
                    return false
                  }
                  let new_inst = new_block.insts[def_new_idx]
                  if new_inst.defs.length() != 1 {
                    return false
                  }
                  guard pick_scratch_reg(new_block, def_new_idx)
                    is Some(scratch_preg) else {
                    return false
                  }
                  new_inst.defs[def_pos] = { reg: @abi.Physical(scratch_preg) }
                  moves[move_idx] = {
                    from: Reg(scratch_preg),
                    to: moves[move_idx].to,
                    class: moves[move_idx].class,
                  }
                  rewritten.add(vreg_id)
                  true
                }

                if try_rewrite_move(
                    i, moves, move_src_vregs, jump_arg_candidates, jump_arg_counts,
                    alloc, orig_inst_to_new_idx, new_block, rewritten,
                  ) ||
                  try_rewrite_move(
                    j, moves, move_src_vregs, jump_arg_candidates, jump_arg_counts,
                    alloc, orig_inst_to_new_idx, new_block, rewritten,
                  ) {
                  broke_cycle = true
                  break
                }
              }
            }
          }

          // Resolve all moves together (including spill destinations), otherwise
          // a register move can clobber a source before it is stored to a spill slot.
          let resolved_moves = resolve_parallel_moves(moves)
          for mv in resolved_moves {
            if mv.to.is_spilled() {
              let to_slot = mv.to.get_spill_slot()
              if mv.from.is_spilled() {
                let from_slot = mv.from.get_spill_slot()
                let scratch_class = match mv.class {
                  @abi.Float32 | @abi.Float64 => @abi.Float64
                  _ => mv.class
                }
                let scratch_preg : @abi.PReg = {
                  index: 16,
                  class: scratch_class,
                }
                let reload_inst = @instr.VCodeInst::new(
                  StackLoad(from_slot * 8),
                )
                reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                new_block.add_inst(reload_inst)
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(scratch_preg))
                new_block.add_inst(store_inst)
              } else {
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
                new_block.add_inst(store_inst)
              }
            } else if mv.from.is_spilled() {
              let slot = mv.from.get_spill_slot()
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
              new_block.add_inst(reload_inst)
            } else {
              let move_inst = @instr.VCodeInst::new(Move)
              move_inst.add_def({ reg: @abi.Physical(loc_as_preg(mv.to)) })
              move_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
              new_block.add_inst(move_inst)
            }
          }

          // After materializing block args, the jump itself has no args.
          @instr.Jump(target, [])
        }
        Branch(cond, then_b, else_b) => {
          // Handle spilled condition register
          let new_cond = rewrite_reg_with_spill(cond, alloc, new_block)
          Branch(new_cond, then_b, else_b)
        }
        BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
          // Handle spilled registers
          let new_lhs = rewrite_reg_with_spill(lhs, alloc, new_block)
          let new_rhs = rewrite_reg_with_spill(rhs, alloc, new_block)
          BranchCmp(new_lhs, new_rhs, cond, is_64, then_b, else_b)
        }
        BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
          // Handle spilled register
          let new_lhs = rewrite_reg_with_spill(lhs, alloc, new_block)
          BranchCmpImm(new_lhs, imm, cond, is_64, then_b, else_b)
        }
        BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
          // Handle spilled register
          let new_reg = rewrite_reg_with_spill(reg, alloc, new_block)
          BranchZero(new_reg, is_nonzero, is_64, then_b, else_b)
        }
        BrTable(index, targets, default) => {
          // Handle spilled index register
          let new_index = rewrite_reg_with_spill(index, alloc, new_block)
          BrTable(new_index, targets, default)
        }
        Return(values) => {
          // Handle Return specially to use block-level scratch counter
          // This ensures each spilled value uses a different scratch register
          let new_values : Array[@abi.Reg] = []
          for v in values {
            if v is @abi.Virtual(vreg) &&
              alloc.assignments.get(vreg.id) is Some(preg) {
              new_values.push(@abi.Physical(preg))
              // Spilled: insert reload and use scratch register from block pool
            } else if v is @abi.Virtual(vreg) &&
              alloc.spill_slots.get(vreg.id) is Some(slot) {
              // Use X16, X17 as scratch registers
              // These are the only safe scratch registers
              let scratch_class = match vreg.class {
                @abi.Float32 | @abi.Float64 => @abi.Float64
                _ => vreg.class
              }
              let scratch_indices = [16, 17]
              let scratch_preg : @abi.PReg = {
                index: scratch_indices[block_scratch_idx % 2],
                class: scratch_class,
              }
              block_scratch_idx = block_scratch_idx + 1
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              new_block.add_inst(reload_inst)
              new_values.push(@abi.Physical(scratch_preg))
            } else {
              new_values.push(v)
            }
          }
          Return(new_values)
        }
        Trap(msg) => Trap(msg)
      }
      new_block.set_terminator(new_term)
    }
  }
  eliminate_trivial_moves(new_func)
}

///|
/// Remove redundant Move instructions where source and destination alias.
fn eliminate_trivial_moves(func : VCodeFunction) -> VCodeFunction {
  fn same_location(a : @abi.PReg, b : @abi.PReg) -> Bool {
    let same_bank = match (a.class, b.class) {
      (@abi.Int, @abi.Int) => true
      (
        @abi.Float32
        | @abi.Float64
        | @abi.Vector,
        @abi.Float32
        | @abi.Float64
        | @abi.Vector,
      ) => true
      _ => false
    }
    a.index == b.index && same_bank
  }

  let new_func = func.clone_base()
  new_func.set_num_spill_slots(func.num_spill_slots)
  for param in func.params {
    new_func.params.push(param)
  }
  for preg in func.param_pregs {
    new_func.param_pregs.push(preg)
  }
  for result in func.results {
    new_func.results.push(result)
  }
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }
  for block in func.blocks {
    let new_block = new_func.new_block()
    for param in block.params {
      new_block.params.push(param)
    }
    for inst in block.insts {
      let mut skip = false
      if inst.opcode is @instr.Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        match (inst.defs[0].reg, inst.uses[0]) {
          (@abi.Physical(dst), @abi.Physical(src)) =>
            if same_location(src, dst) {
              skip = true
            }
          _ => ()
        }
      }
      if !skip {
        new_block.add_inst(inst)
      }
    }
    if block.terminator is Some(term) {
      new_block.set_terminator(term)
    }
  }
  new_func
}

///|
/// Rewrite a register, inserting reload if spilled
fn rewrite_reg_with_spill(
  reg : @abi.Reg,
  alloc : RegAllocResult,
  block : @block.VCodeBlock,
) -> @abi.Reg {
  match reg {
    @abi.Virtual(vreg) =>
      match alloc.assignments.get(vreg.id) {
        Some(preg) => @abi.Physical(preg)
        None =>
          // Spilled: insert reload and use scratch register
          match alloc.spill_slots.get(vreg.id) {
            Some(slot) => {
              let scratch_preg : @abi.PReg = { index: 16, class: vreg.class }
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              block.add_inst(reload_inst)
              @abi.Physical(scratch_preg)
            }
            None => reg // Should not happen
          }
      }
    @abi.Physical(_) => reg
  }
}
