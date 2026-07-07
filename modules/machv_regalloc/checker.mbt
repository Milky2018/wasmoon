///|
/// Register allocation verifier (Cranelift-inspired)
///
/// This is a best-effort consistency check over:
/// - physical register overlaps (no two live ranges overlap in same preg bank)
/// - call-clobber safety (values live across calls not placed in caller-saved regs)
/// - reserved/scratch registers not assigned
///
/// It is intentionally conservative and does not attempt to validate all
/// constraint move insertions.

///|
fn reg_kind(preg : @abi.PReg) -> Int {
  match preg.class {
    Int => 0
    Float32 | Float64 | Vector => 1
  }
}

///|
fn alias_key(preg : @abi.PReg) -> Int {
  preg.index * 2 + reg_kind(preg)
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
  func : @machv.Function,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  isa : @isa.ISA,
  call_conv_layout : @abi.CallConventionLayout,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
  embedding_reg_roles? : @abi.EmbeddingRegRoles = @abi.EmbeddingRegRoles::none(),
) -> Unit {
  // Rebuild live ranges to verify with holes.
  let ranges = build_live_ranges(func, liveness)
  let block_order = liveness.block_order

  // Rebuild MachineEnv to compute allocatable + scratch sets.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let reserve_extra_results_ptr = needs_extra || calls_multi
  let reserved_int_regs = embedding_reg_roles.reserved_int_indices(
    reserve_context=settings.enable_pinned_reg,
    reserve_context_cache_0=func.should_cache_mem0_desc(),
    reserve_context_cache_1=func.should_cache_func_table(),
    reserve_extra_results_ptr~,
  )
  let env = isa.machine_env(settings~, reserved_int_regs~)
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
  let call_int_arg_regs : @hashset.HashSet[Int] = HashSet([])
  call_int_arg_regs.add(call_conv_layout.context_arg.index) |> ignore
  for preg in call_conv_layout.user_arg_gprs {
    call_int_arg_regs.add(preg.index) |> ignore
  }
  let call_float_arg_regs = build_index_set(call_conv_layout.arg_fprs)

  // Call-clobbered sets.
  let call_clobbered_int : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_gprs() {
    call_clobbered_int.add(r.index) |> ignore
  }
  // For scalar FPR values crossing foreign/helper calls, model low-64-bit preservation of
  // V8-V15 (AAPCS64) the same way as same-ABI calls.
  //
  // Vector values are handled separately below and must never cross calls.
  let call_clobbered_float_foreign : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_fprs_same_abi() {
    call_clobbered_float_foreign.add(r.index) |> ignore
  }
  // For internal same-ABI calls, allow V8-V15 as callee-saved (low 64 bits).
  let call_clobbered_float_internal : @hashset.HashSet[Int] = HashSet([])
  for r in isa.call_clobbered_fprs_same_abi() {
    call_clobbered_float_internal.add(r.index) |> ignore
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

  // Build per-preg span lists for overlap checking.
  let preg_spans : Map[Int, Array[(Int, ProgPointRange)]] = {}
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
            let is_arg_gpr = call_int_arg_regs.contains(preg.index)
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
            call_float_arg_regs.contains(preg.index)) &&
            !(fixed_reg is Some(fr) && fr.index == preg.index) {
            abort(
              "regalloc verifier: v\{vreg_id} assigned non-allocatable FPR v\{preg.index}",
            )
          }
        Vector =>
          if !allowed_vector.contains(preg.index) &&
            !(param_ids.contains(vreg_id) &&
            call_float_arg_regs.contains(preg.index)) &&
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
          // If this value crosses any foreign/helper call, use the scalar same-ABI
          // caller-saved subset (V8-V15 low 64-bit remain preserved).
          if lr.crosses_foreign_call &&
            call_clobbered_float_foreign.contains(preg.index) {
            abort(
              "regalloc verifier: value live across foreign call assigned to caller-saved v\{preg.index}",
            )
          }
          // If this value crosses any internal call, treat the standard caller-saved subset as clobbered.
          if lr.crosses_internal_call &&
            call_clobbered_float_internal.contains(preg.index) {
            abort(
              "regalloc verifier: value live across internal call assigned to caller-saved v\{preg.index}",
            )
          }
        }
      }
      let key = alias_key(preg)
      if preg_spans.get(key) is None {
        preg_spans.set(key, [])
      }
      let spans = preg_spans.get(key).unwrap()
      for span in lr.ranges {
        spans.push((vreg_id, span))
      }
    }
  }

  // Overlap check: for each physical register location (bank+index), spans must not overlap.
  for entry in preg_spans {
    let (key, spans) = entry
    if spans.length() <= 1 {
      continue
    }
    spans.sort_by(fn(a, b) {
      a.1.start.compare_with_order(b.1.start, block_order)
    })
    for i in 1..<spans.length() {
      let prev = spans[i - 1]
      let cur = spans[i]
      if prev.1.overlaps(cur.1, block_order) {
        abort(
          "regalloc verifier: overlapping allocations in same preg (key=\{key}, v\{prev.0} \{prev.1} overlaps v\{cur.0} \{cur.1})",
        )
      }
    }
  }
}

///|
/// Backwards-compatible wrapper for existing call sites.
pub fn verify_allocation_aarch64(
  func : @machv.Function,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  call_conv_layout : @abi.CallConventionLayout,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
  embedding_reg_roles? : @abi.EmbeddingRegRoles = @abi.EmbeddingRegRoles::none(),
) -> Unit {
  verify_allocation(
    func,
    liveness,
    alloc,
    AArch64,
    call_conv_layout,
    settings~,
    embedding_reg_roles~,
  )
}
