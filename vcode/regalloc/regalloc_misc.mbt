// ============ Dead Code Elimination ============

///|
/// Check if an opcode has side effects (cannot be eliminated even if dead)
fn has_side_effects(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    // Loads can trap (e.g. guard pages / invalid pointers), so must not be eliminated.
    LoadPtr(_, _) | LoadPtrRegOffset(_, _, _) | LoadPtrNarrow(_, _, _) => true
    // Memory stores have side effects
    Store(_, _) | StackStore(_) | StorePtr(_, _) | StorePtrRegOffset(_, _, _) =>
      true
    // Type check can trap
    TypeCheckIndirect(_) => true
    TypeCheckSubtypeIndirect(_) => true
    // Function calls have side effects
    ReturnCallIndirect(_, _) | CallPtr(_, _, _) | CallDirect(_, _, _, _) => true
    // Traps must not be eliminated
    TrapIfZero(_, _) | TrapIfUge(_) | TrapIfUgt(_) | TrapIf(_, _) => true
    // Everything else is pure computation
    _ => false
  }
}

///|
/// Eliminate dead code from a VCode function
/// Removes instructions that define vregs which are never used
pub fn eliminate_dead_code(func : VCodeFunction) -> VCodeFunction {
  // Step 1: Collect all used vregs
  let used_vregs : Set[Int] = Set::new()

  // Add function parameters (they're implicitly used)
  for param in func.params {
    used_vregs.add(param.id)
  }

  // Scan all instructions and terminators for uses
  for block in func.blocks {
    // Block parameters are used (they receive values from jumps)
    for param in block.params {
      used_vregs.add(param.id)
    }

    // Instruction uses
    for inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          used_vregs.add(vreg.id)
        }
      }
    }

    // Terminator uses
    if block.terminator is Some(term) {
      match term {
        Branch(cond, _, _) =>
          if cond is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BranchCmp(lhs, rhs, _, _, _, _) => {
          if lhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
          if rhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          if lhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BranchZero(reg, _, _, _, _) =>
          if reg is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BrTable(index, _, _) =>
          if index is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        Return(values) =>
          for v in values {
            if v is @abi.Virtual(vreg) {
              used_vregs.add(vreg.id)
            }
          }
        Jump(_, args) =>
          for a in args {
            if a is @abi.Virtual(vreg) {
              used_vregs.add(vreg.id)
            }
          }
        Trap(_) => ()
      }
    }
  }

  // Step 2: Build new function without dead instructions
  let new_func = VCodeFunction::new(func.name)
  new_func.next_vreg_id = func.next_vreg_id
  new_func.int_stack_params = func.int_stack_params
  new_func.max_outgoing_args_size = func.max_outgoing_args_size

  // Copy params and results
  for param in func.params {
    new_func.params.push(param)
  }
  for result in func.results {
    new_func.results.push(result)
  }
  // Copy result types for multi-value return support
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }

  // Copy blocks, filtering out dead instructions
  for block in func.blocks {
    let new_block = new_func.new_block()

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Filter instructions: keep if has side effects OR defines a used vreg
    for inst in block.insts {
      let should_keep = if has_side_effects(inst.opcode) {
        true
      } else {
        // Keep if any defined vreg is used
        let mut any_def_used = false
        for def in inst.defs {
          if def.reg is @abi.Virtual(vreg) {
            if used_vregs.contains(vreg.id) {
              any_def_used = true
            }
          } else {
            any_def_used = true // Always keep physical reg defs
          }
        }
        // Also keep instructions with no defs (shouldn't happen for pure ops, but be safe)
        any_def_used || inst.defs.is_empty()
      }
      if should_keep {
        new_block.add_inst(inst)
      }
    }

    // Copy terminator
    if block.terminator is Some(term) {
      new_block.set_terminator(term)
    }
  }
  new_func
}

// ============ Convenience API ============

///|
/// Build the register pools for AArch64 allocation
fn build_aarch64_reg_pools(
  func : VCodeFunction,
  settings : @abi.ABISettings,
) -> (
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
) {
  // Check if function needs extra results buffer (uses X23)
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  // Cache memory0 descriptor pointer in X20 when needed.
  let needs_x20_reserved = func.uses_mem0()
  // Cache func_table pointer in X21 when needed.
  let needs_x21_reserved = func.uses_func_table()

  // Build MachineEnv (Cranelift-inspired) and derive pools.
  let env = @abi.build_aarch64_machine_env(
    settings~,
    reserve_mem0_desc=needs_x20_reserved,
    reserve_func_table=needs_x21_reserved,
    reserve_x23=needs_x23_reserved,
  )
  let int_regs : Array[@abi.PReg] = []
  for r in env.preferred_int {
    int_regs.push(r)
  }
  let callee_saved_int_regs = env.callee_saved_int
  for r in env.nonpreferred_int {
    int_regs.push(r)
  }
  let float_regs : Array[@abi.PReg] = []
  for r in env.preferred_float {
    float_regs.push(r)
  }
  let callee_saved_float_regs = env.callee_saved_float
  for r in env.nonpreferred_float {
    float_regs.push(r)
  }
  let vector_regs : Array[@abi.PReg] = []
  for r in env.preferred_vector {
    vector_regs.push(r)
  }
  for r in env.nonpreferred_vector {
    vector_regs.push(r)
  }
  (
    int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )
}

///|
/// Allocate registers using the Ion-style backtracking allocator
/// This allocator supports:
/// - Bundle merging for copy coalescing
/// - Priority-based allocation with eviction
/// - Bundle splitting instead of immediate spilling
pub fn allocate_registers_backtracking(
  func : VCodeFunction,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> VCodeFunction {
  // Step 0: Eliminate dead code first
  let func = eliminate_dead_code(func)
  // Cranelift-style remat for cross-block constants to reduce reg pressure.
  let func = rematerialize_cross_block_constants(func)
  // Remat may make original const-defs dead in their original blocks.
  let func = eliminate_dead_code(func)

  // Build register pools
  let (
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
  ) = build_aarch64_reg_pools(func, settings)

  // Compute liveness (Phase 1)
  let liveness = compute_liveness(func)

  // Use backtracking allocator (Phases 2-4)
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )

  // Optional safety net (Cranelift-like checker).
  // Keeps invariants honest as allocator logic evolves.
  verify_allocation_aarch64(func, liveness, alloc_result, settings~)

  // Process constraints and generate RegMove edits
  process_constraints(func, alloc_result)

  // Apply allocation
  apply_allocation(func, alloc_result)
}

///|
/// Allocate registers and return a Cranelift-style regalloc `Output`.
///
/// The returned `VCodeFunction` is *not* rewritten to physical registers; the
/// emitter consumes the returned `Output` to materialize edits and operand
/// allocations on the fly.
pub fn allocate_registers_backtracking_output(
  func : VCodeFunction,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> (VCodeFunction, Output) {
  // Step 0: Eliminate dead code first.
  let func = eliminate_dead_code(func)
  let func = rematerialize_cross_block_constants(func)
  let func = eliminate_dead_code(func)

  // Build register pools.
  let (
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
  ) = build_aarch64_reg_pools(func, settings)

  // Compute liveness (Phase 1).
  let liveness = compute_liveness(func)

  // Use backtracking allocator (Phases 2-4).
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )

  // Optional safety net (Cranelift-like checker).
  verify_allocation_aarch64(func, liveness, alloc_result, settings~)

  // Process constraints and generate RegMove edits.
  process_constraints(func, alloc_result)

  // Build output (allocs + edits). VCode remains in terms of vregs.
  let output = build_output(func, alloc_result)
  (func, output)
}

///|
/// Allocation statistics for comparison
struct AllocStats {
  mut num_vregs : Int // Total virtual registers
  mut num_spill_slots : Int // Number of spill slots used
  num_spills : Int // Number of spill operations
  num_reloads : Int // Number of reload operations
  num_moves : Int // Number of move operations inserted
  total_insts : Int // Total instructions after allocation
}

///|
fn AllocStats::to_string(self : AllocStats) -> String {
  "vregs=\{self.num_vregs}, spill_slots=\{self.num_spill_slots}, spills=\{self.num_spills}, reloads=\{self.num_reloads}, moves=\{self.num_moves}, total_insts=\{self.total_insts}"
}

///|
pub impl Show for AllocStats with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Count instructions by type in allocated function
fn count_instructions(func : VCodeFunction) -> AllocStats {
  let mut num_spills = 0
  let mut num_reloads = 0
  let mut num_moves = 0
  let mut total_insts = 0
  for block in func.blocks {
    for inst in block.insts {
      total_insts += 1
      match inst.opcode {
        @instr.StackStore(_) => num_spills += 1
        @instr.StackLoad(_) => num_reloads += 1
        @instr.Move => num_moves += 1
        _ => ()
      }
    }
  }
  {
    num_vregs: 0,
    num_spill_slots: 0,
    num_spills,
    num_reloads,
    num_moves,
    total_insts,
  }
}

///|
/// Get allocation statistics
pub fn get_alloc_stats(
  func : VCodeFunction,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> AllocStats {
  let func = eliminate_dead_code(func)
  let func = rematerialize_cross_block_constants(func)
  let func = eliminate_dead_code(func)
  let (
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
  ) = build_aarch64_reg_pools(func, settings)
  let liveness = compute_liveness(func)

  // Count vregs
  let num_vregs = liveness.intervals.length()
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )
  process_constraints(func, alloc_result)
  let allocated = apply_allocation(func, alloc_result)
  let stats = count_instructions(allocated)
  stats.num_vregs = num_vregs
  stats.num_spill_slots = alloc_result.num_spill_slots
  stats
}
