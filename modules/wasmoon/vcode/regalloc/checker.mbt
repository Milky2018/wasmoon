///|
/// Register allocation verifier (Cranelift-inspired)
///
/// This is a best-effort consistency check over:
/// - core regalloc assignment invariants via `@core_regalloc.verify_allocation`
/// - call-clobber safety (values live across calls not placed in caller-saved regs)
/// - reserved/scratch registers not assigned
///
/// It is intentionally conservative and does not attempt to validate all
/// constraint move insertions.

///|
fn checker_reg_class_to_core(class : @abi.RegClass) -> @core_regalloc.RegClass {
  match class {
    Int => Int
    Float32 | Float64 => Float
    Vector => Vector
  }
}

///|
fn checker_preg_to_core(preg : @abi.PReg) -> @core_regalloc.PhysicalReg {
  { id: preg.index, class: checker_reg_class_to_core(preg.class) }
}

///|
fn remember_vreg_class(
  classes : Map[Int, @abi.RegClass],
  reg : @abi.Reg,
) -> Unit {
  if reg is Virtual(vreg) && classes.get(vreg.id) is None {
    classes.set(vreg.id, vreg.class)
  }
}

///|
fn remember_vreg_classes_from_term(
  classes : Map[Int, @abi.RegClass],
  term : @instr.VCodeTerminator,
) -> Unit {
  match term {
    Jump(_, args) | Return(args) =>
      for arg in args {
        remember_vreg_class(classes, arg)
      }
    Branch(cond, _, _) => remember_vreg_class(classes, cond)
    BranchCmp(lhs, rhs, _, _, _, _) => {
      remember_vreg_class(classes, lhs)
      remember_vreg_class(classes, rhs)
    }
    BranchCmpImm(lhs, _, _, _, _, _)
    | BranchZero(lhs, _, _, _, _)
    | BrTable(lhs, _, _) => remember_vreg_class(classes, lhs)
    Trap(_) => ()
  }
}

///|
fn collect_vreg_classes(func : VCodeFunction) -> Map[Int, @abi.RegClass] {
  let classes : Map[Int, @abi.RegClass] = {}
  for param in func.params {
    classes.set(param.id, param.class)
  }
  for block in func.blocks {
    for param in block.params {
      classes.set(param.id, param.class)
    }
    for inst in block.insts {
      for def in inst.defs {
        remember_vreg_class(classes, def.reg)
      }
      for use_ in inst.uses {
        remember_vreg_class(classes, use_)
      }
    }
    if block.terminator is Some(term) {
      remember_vreg_classes_from_term(classes, term)
    }
  }
  classes
}

///|
fn checker_vreg_to_core(
  vreg_id : Int,
  classes : Map[Int, @abi.RegClass],
  fallback : @abi.RegClass,
) -> @core_regalloc.VirtualReg {
  let class = classes.get(vreg_id).unwrap_or(fallback)
  { id: vreg_id, class: checker_reg_class_to_core(class) }
}

///|
fn allocation_to_core(
  alloc : RegAllocResult,
  classes : Map[Int, @abi.RegClass],
) -> @core_regalloc.Allocation {
  let out = @core_regalloc.Allocation::new()
  for vreg_id, preg in alloc.assignments {
    out.assign(
      checker_vreg_to_core(vreg_id, classes, preg.class),
      Reg(checker_preg_to_core(preg)),
    )
  }
  for vreg_id, slot in alloc.spill_slots {
    out.assign(checker_vreg_to_core(vreg_id, classes, Int), Spill(slot))
  }
  out
}

///|
fn verify_core_allocation(func : VCodeFunction, alloc : RegAllocResult) -> Unit {
  let program = @machv_regalloc.project_function(func.to_machv(), [])
  let core_alloc = allocation_to_core(alloc, collect_vreg_classes(func))
  @core_regalloc.verify_allocation(program, core_alloc) catch {
    _ => abort("regalloc verifier: core verifier rejected allocation")
  }
}

///|
fn build_index_set(regs : Array[@abi.PReg]) -> @hashset.HashSet[Int] {
  let set : @hashset.HashSet[Int] = HashSet([])
  for r in regs {
    set.add(r.index) |> ignore
  }
  set
}

///|
fn build_index_set_int(xs : Array[Int]) -> @hashset.HashSet[Int] {
  let set : @hashset.HashSet[Int] = HashSet([])
  for x in xs {
    set.add(x) |> ignore
  }
  set
}

///|
fn union_sets(
  a : @hashset.HashSet[Int],
  b : @hashset.HashSet[Int],
) -> @hashset.HashSet[Int] {
  for x in b {
    a.add(x) |> ignore
  }
  a
}

///|
pub fn verify_allocation(
  func : VCodeFunction,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  isa : @isa.ISA,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> Unit {
  verify_core_allocation(func, alloc)

  // Rebuild live ranges to verify with holes.
  let ranges = build_live_ranges(func, liveness)

  // Rebuild MachineEnv to compute allocatable + scratch sets.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  let needs_x20_reserved = func.should_cache_mem0_desc()
  let needs_x21_reserved = func.should_cache_func_table()
  let env = isa.machine_env(
    settings~,
    reserve_mem0_desc=needs_x20_reserved,
    reserve_func_table=needs_x21_reserved,
    reserve_extra_results_ptr=needs_x23_reserved,
  )
  let allowed_int = union_sets(
    build_index_set(env.preferred_int),
    build_index_set(env.nonpreferred_int),
  )
  let allowed_float = union_sets(
    build_index_set(env.preferred_float),
    build_index_set(env.nonpreferred_float),
  )
  let allowed_vector = union_sets(
    build_index_set(env.preferred_vector),
    build_index_set(env.nonpreferred_vector),
  )
  let scratch_int = build_index_set_int(env.scratch_int)
  let scratch_float = build_index_set_int(env.scratch_float)

  // Function parameters and block parameters may legitimately reside in ABI
  // argument registers (x0-x7/v0-v7). Block params are SSA phis and often
  // coalesce with incoming args.
  let param_ids : @hashset.HashSet[Int] = HashSet([])
  for p in func.params {
    param_ids.add(p.id) |> ignore
  }
  for b in func.blocks {
    for p in b.params {
      param_ids.add(p.id) |> ignore
    }
  }
  let wasm_int_arg_regs : @hashset.HashSet[Int] = HashSet([])
  wasm_int_arg_regs.add(isa.wasm_vmctx_arg_preg().index) |> ignore
  for preg in isa.wasm_user_arg_gprs() {
    wasm_int_arg_regs.add(preg.index) |> ignore
  }
  let wasm_float_arg_regs = build_index_set(isa.wasm_arg_fprs())

  // Call-clobbered sets.
  let call_clobbered_int : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_gprs() {
    call_clobbered_int.add(r.index) |> ignore
  }
  // For scalar FPR values crossing C calls, model low-64-bit preservation of
  // V8-V15 (AAPCS64) the same way as same-ABI calls.
  //
  // Vector values are handled separately below and must never cross calls.
  let call_clobbered_float_c : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_fprs_same_abi() {
    call_clobbered_float_c.add(r.index) |> ignore
  }
  // For Wasm-to-Wasm calls (same ABI), allow V8-V15 as callee-saved (low 64 bits).
  let call_clobbered_float_wasm : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_fprs_same_abi() {
    call_clobbered_float_wasm.add(r.index) |> ignore
  }
  fn has_any_fixed_constraint_to(lr : LiveRange, preg : @abi.PReg) -> Bool {
    // Treat any FixedReg at any point as justification for using a register
    // outside the main allocatable pool (e.g. call-arg registers x0-x7).
    for use_pos in lr.uses {
      if use_pos.constraint is FixedReg(fr) {
        // Compare by bank (int vs float/vector) and index.
        let same_bank = match (fr.class, preg.class) {
          (Int, Int) => true
          (Float32 | Float64 | Vector, Float32 | Float64 | Vector) => true
          _ => false
        }
        if same_bank && fr.index == preg.index {
          return true
        }
      }
    }
    false
  }

  for entry in alloc.assignments {
    let (vreg_id, preg) = entry
    if ranges.get_by_vreg(vreg_id) is Some(lr) {
      // Scratch regs must never be assigned.
      if preg.class is Int && scratch_int.contains(preg.index) {
        abort("regalloc verifier: assigned scratch GPR x\{preg.index}")
      }
      if (
          preg.class is Float32 || preg.class is Float64 || preg.class is Vector
        ) &&
        scratch_float.contains(preg.index) {
        abort("regalloc verifier: assigned scratch V\{preg.index}")
      }

      // Allocatable set checks.
      let fixed_reg = lr.get_fixed_reg()
      match lr.vreg.class {
        Int =>
          if !allowed_int.contains(preg.index) {
            // Allow parameters in ABI argument registers.
            let is_arg_gpr = wasm_int_arg_regs.contains(preg.index)
            if !(param_ids.contains(vreg_id) && is_arg_gpr) &&
              !(is_arg_gpr && !lr.crosses_call) &&
              !(fixed_reg is Some(fr) && fr.index == preg.index) &&
              !has_any_fixed_constraint_to(lr, preg) {
              abort(
                "regalloc verifier: v\{vreg_id} assigned non-allocatable GPR x\{preg.index}",
              )
            }
          }
        Float32 | Float64 =>
          if !allowed_float.contains(preg.index) &&
            !(param_ids.contains(vreg_id) &&
            wasm_float_arg_regs.contains(preg.index)) &&
            !(fixed_reg is Some(fr) && fr.index == preg.index) {
            abort(
              "regalloc verifier: v\{vreg_id} assigned non-allocatable FPR v\{preg.index}",
            )
          }
        Vector =>
          if !allowed_vector.contains(preg.index) &&
            !(param_ids.contains(vreg_id) &&
            wasm_float_arg_regs.contains(preg.index)) &&
            !(fixed_reg is Some(fr) && fr.index == preg.index) {
            abort(
              "regalloc verifier: v\{vreg_id} assigned non-allocatable vector v\{preg.index}",
            )
          }
      }

      // Call-clobber safety.
      if lr.crosses_call {
        if lr.vreg.class is Vector {
          abort("regalloc verifier: vector value live across call must spill")
        }
        if preg.class is Int && call_clobbered_int.contains(preg.index) {
          abort(
            "regalloc verifier: value live across call assigned to caller-saved x\{preg.index}",
          )
        }
        if preg.class is Float32 || preg.class is Float64 {
          // If this value crosses any C call, use the scalar same-ABI
          // caller-saved subset (V8-V15 low 64-bit remain preserved).
          if lr.crosses_c_call && call_clobbered_float_c.contains(preg.index) {
            abort(
              "regalloc verifier: value live across C call assigned to caller-saved v\{preg.index}",
            )
          }
          // If this value crosses any Wasm call, treat the standard caller-saved subset as clobbered.
          if lr.crosses_wasm_call &&
            call_clobbered_float_wasm.contains(preg.index) {
            abort(
              "regalloc verifier: value live across Wasm call assigned to caller-saved v\{preg.index}",
            )
          }
        }
      }
    }
  }
}

///|
/// Backwards-compatible wrapper for existing call sites.
pub fn verify_allocation_aarch64(
  func : VCodeFunction,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> Unit {
  verify_allocation(func, liveness, alloc, AArch64, settings~)
}
