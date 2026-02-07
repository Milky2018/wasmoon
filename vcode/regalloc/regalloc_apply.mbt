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
  let block_id_to_index : Map[Int, Int] = {}
  for i, block in func.blocks {
    block_id_to_index.set(block.id, i)
  }
  let isa = @isa.ISA::current()
  let wasm_vmctx_arg = isa.wasm_vmctx_arg_preg()
  let wasm_user_gprs = isa.wasm_user_arg_gprs()
  let wasm_arg_fprs = isa.wasm_arg_fprs()
  let env = isa.machine_env()
  guard env.scratch_int.length() >= 2 && env.scratch_float.length() >= 2 else {
    abort(
      "regalloc_apply: ISA machine env must reserve at least 2 scratch regs",
    )
  }
  let scratch_int_indices = env.scratch_int
  let scratch_float_indices = env.scratch_float
  fn scratch_indices_for_class(class : @abi.RegClass) -> Array[Int] {
    match class {
      @abi.Int => scratch_int_indices
      _ => scratch_float_indices
    }
  }

  fn invalidate_reload_slot(
    active_reloads : Map[Int, @abi.PReg],
    slot : Int,
  ) -> Unit {
    if active_reloads.get(slot) is Some(_) {
      active_reloads.remove(slot) |> ignore
    }
  }

  fn fold_stack_slot_loads(block : @block.VCodeBlock) -> Unit {
    fn same_mem_type(a : @instr.MemType, b : @instr.MemType) -> Bool {
      match (a, b) {
        (@instr.I32, @instr.I32) => true
        (@instr.I64, @instr.I64) => true
        (@instr.F32, @instr.F32) => true
        (@instr.F64, @instr.F64) => true
        (@instr.V128, @instr.V128) => true
        _ => false
      }
    }

    fn invalidate_cached_preg(
      slot_cache : Map[Int, @abi.PReg],
      preg : @abi.PReg,
    ) -> Unit {
      let to_remove : Array[Int] = []
      for slot, cached in slot_cache {
        if cached.index == preg.index && cached.class == preg.class {
          to_remove.push(slot)
        }
      }
      for slot in to_remove {
        slot_cache.remove(slot) |> ignore
      }
    }

    let optimized : Array[@instr.VCodeInst] = []
    let slot_cache : Map[Int, @abi.PReg] = {}
    for inst in block.insts {
      let mut emitted = false
      match inst.opcode {
        @instr.StackLoad(offset) =>
          if inst.defs.length() == 1 && inst.defs[0].reg is @abi.Physical(dst) {
            if slot_cache.get(offset) is Some(src) && src.class == dst.class {
              if src.index != dst.index {
                let mv = @instr.VCodeInst::new(@instr.Move)
                mv.add_def({ reg: @abi.Physical(dst) })
                mv.add_use(@abi.Physical(src))
                optimized.push(mv)
              }
              emitted = true
            }
          }
        @instr.LoadPtr(load_ty, load_offset) =>
          if inst.defs.length() == 1 &&
            inst.defs[0].reg is @abi.Physical(dst) &&
            inst.uses.length() == 1 &&
            inst.uses[0] is @abi.Physical(base_reg) &&
            optimized.length() > 0 {
            let prev = optimized[optimized.length() - 1]
            match prev.opcode {
              @instr.StorePtr(store_ty, store_offset) =>
                if same_mem_type(store_ty, load_ty) &&
                  store_offset == load_offset &&
                  prev.uses.length() == 2 &&
                  prev.uses[0] is @abi.Physical(store_base) &&
                  prev.uses[1] is @abi.Physical(src_reg) &&
                  store_base.index == base_reg.index &&
                  store_base.class == base_reg.class &&
                  src_reg.class == dst.class &&
                  src_reg.class is @abi.Int {
                  if src_reg.index != dst.index {
                    let mv = @instr.VCodeInst::new(@instr.Move)
                    mv.add_def({ reg: @abi.Physical(dst) })
                    mv.add_use(@abi.Physical(src_reg))
                    optimized.push(mv)
                  }
                  emitted = true
                }
              _ => ()
            }
          }
        _ => ()
      }
      if !emitted {
        optimized.push(inst)
      }
      for def in inst.defs {
        if def.reg is @abi.Physical(preg) {
          invalidate_cached_preg(slot_cache, preg)
        }
      }
      match inst.opcode {
        @instr.StackStore(offset) =>
          if inst.uses.length() == 1 && inst.uses[0] is @abi.Physical(src) {
            slot_cache.set(offset, src)
          } else {
            slot_cache.remove(offset) |> ignore
          }
        @instr.StackLoad(offset) =>
          if inst.defs.length() == 1 && inst.defs[0].reg is @abi.Physical(dst) {
            slot_cache.set(offset, dst)
          } else {
            slot_cache.remove(offset) |> ignore
          }
        _ => ()
      }
    }
    block.insts.clear()
    for inst in optimized {
      block.add_inst(inst)
    }
  }

  // Compute reload intervals for spill coalescing
  let reload_intervals = compute_reload_intervals(func, alloc)
  allocate_reload_registers(func, alloc, reload_intervals)

  // Convert function parameters
  // Parameters use Wasmoon's internal Wasm ABI (ISA-dependent).
  // vmctx is an explicit param in the function signature.
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
            if int_idx == 0 {
              (Some(wasm_vmctx_arg), true)
            } else {
              let user_idx = int_idx - 1
              if user_idx < wasm_user_gprs.length() {
                (Some(wasm_user_gprs[user_idx]), true)
              } else {
                (None, true) // Stack param
              }
            }
          @abi.Float32 =>
            if float_idx < wasm_arg_fprs.length() {
              (
                Some(@abi.PReg::{
                  index: wasm_arg_fprs[float_idx].index,
                  class: @abi.Float32,
                }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Float64 =>
            if float_idx < wasm_arg_fprs.length() {
              (
                Some(@abi.PReg::{
                  index: wasm_arg_fprs[float_idx].index,
                  class: @abi.Float64,
                }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Vector =>
            // Vector uses same Vn registers as Float
            if float_idx < wasm_arg_fprs.length() {
              (
                Some(@abi.PReg::{
                  index: wasm_arg_fprs[float_idx].index,
                  class: @abi.Vector,
                }),
                false,
              )
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
          let incoming_preg_opt : @abi.PReg? = match param.class {
            @abi.Int =>
              if int_idx == 0 {
                Some(wasm_vmctx_arg)
              } else {
                let user_idx = int_idx - 1
                if user_idx < wasm_user_gprs.length() {
                  Some(wasm_user_gprs[user_idx])
                } else {
                  None
                }
              }
            @abi.Float32 | @abi.Float64 =>
              if float_idx < wasm_arg_fprs.length() {
                Some(@abi.PReg::{
                  index: wasm_arg_fprs[float_idx].index,
                  class: @abi.Float64,
                })
              } else {
                None
              }
            @abi.Vector =>
              if float_idx < wasm_arg_fprs.length() {
                Some(@abi.PReg::{
                  index: wasm_arg_fprs[float_idx].index,
                  class: @abi.Vector,
                })
              } else {
                None
              }
          }
          match incoming_preg_opt {
            Some(src_preg) => spilled_param_stores.push((src_preg, slot))
            None => ()
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
              let scratch_candidates = scratch_indices_for_class(scratch_class)
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
                    let scratch_indices = scratch_indices_for_class(
                      scratch_class,
                    )
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
                    // Fallback: use the first reserved scratch reg for this bank.
                    let scratch_class = match vreg.class {
                      @abi.Float32 | @abi.Float64 => @abi.Float64
                      _ => vreg.class
                    }
                    let scratch_indices = scratch_indices_for_class(
                      scratch_class,
                    )
                    let scratch_preg : @abi.PReg = {
                      index: scratch_indices[0],
                      class: scratch_class,
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
                invalidate_reload_slot(active_reloads, to_slot)
              } else {
                let scratch_class = match mv.class {
                  @abi.Float32 | @abi.Float64 => @abi.Float64
                  _ => mv.class
                }
                let scratch_indices = scratch_indices_for_class(scratch_class)
                let scratch_preg : @abi.PReg = {
                  index: scratch_indices[0],
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
                invalidate_reload_slot(active_reloads, to_slot)
              }
            } else {
              let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
              store_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
              new_block.add_inst(store_inst)
              invalidate_reload_slot(active_reloads, to_slot)
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
            invalidate_reload_slot(active_reloads, slot)
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
        invalidate_reload_slot(active_reloads, slot)
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
          if block_id_to_index.get(target) is Some(target_idx) {
            let target_block = func.blocks[target_idx]
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
                let scratch_indices = scratch_indices_for_class(scratch_class)
                let scratch_preg : @abi.PReg = {
                  index: scratch_indices[0],
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
                invalidate_reload_slot(active_reloads, to_slot)
              } else {
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(loc_as_preg(mv.from)))
                new_block.add_inst(store_inst)
                invalidate_reload_slot(active_reloads, to_slot)
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
          // Handle spilled condition register (single input).
          let new_cond = rewrite_reg_with_spill(
            cond,
            alloc,
            new_block,
            scratch_int_indices[0],
          )
          Branch(new_cond, then_b, else_b)
        }
        BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
          // Handle spilled registers. IMPORTANT: if both sides are spilled, we must
          // reload into distinct scratch registers, otherwise we clobber one side.
          let new_lhs = rewrite_reg_with_spill(
            lhs,
            alloc,
            new_block,
            scratch_int_indices[0],
          )
          let new_rhs = rewrite_reg_with_spill(
            rhs,
            alloc,
            new_block,
            scratch_int_indices[1],
          )
          BranchCmp(new_lhs, new_rhs, cond, is_64, then_b, else_b)
        }
        BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
          // Handle spilled register (single input).
          let new_lhs = rewrite_reg_with_spill(
            lhs,
            alloc,
            new_block,
            scratch_int_indices[0],
          )
          BranchCmpImm(new_lhs, imm, cond, is_64, then_b, else_b)
        }
        BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
          // Handle spilled register (single input).
          let new_reg = rewrite_reg_with_spill(
            reg,
            alloc,
            new_block,
            scratch_int_indices[0],
          )
          BranchZero(new_reg, is_nonzero, is_64, then_b, else_b)
        }
        BrTable(index, targets, default) => {
          // Handle spilled index register (single input).
          let new_index = rewrite_reg_with_spill(
            index,
            alloc,
            new_block,
            scratch_int_indices[0],
          )
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
              let scratch_indices = scratch_indices_for_class(scratch_class)
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
      fold_stack_slot_loads(new_block)
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
  scratch_idx : Int,
) -> @abi.Reg {
  match reg {
    @abi.Virtual(vreg) =>
      match alloc.assignments.get(vreg.id) {
        Some(preg) => @abi.Physical(preg)
        None =>
          // Spilled: insert reload and use scratch register
          match alloc.spill_slots.get(vreg.id) {
            Some(slot) => {
              let scratch_class = match vreg.class {
                @abi.Float32 | @abi.Float64 => @abi.Float64
                _ => vreg.class
              }
              let scratch_preg : @abi.PReg = {
                index: scratch_idx,
                class: scratch_class,
              }
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
