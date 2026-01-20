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
    @abi.Int => 0
    @abi.Float32 | @abi.Float64 | @abi.Vector => 1
  }
}

///|
fn alias_key(preg : @abi.PReg) -> Int {
  preg.index * 2 + reg_kind(preg)
}

///|
fn build_index_set(regs : Array[@abi.PReg]) -> @hashset.HashSet[Int] {
  let set : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for r in regs {
    set.add(r.index) |> ignore
  }
  set
}

///|
fn build_index_set_int(xs : Array[Int]) -> @hashset.HashSet[Int] {
  let set : @hashset.HashSet[Int] = @hashset.HashSet::new()
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
pub fn verify_allocation_aarch64(
  func : VCodeFunction,
  liveness : LivenessResult,
  alloc : RegAllocResult,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> Unit {
  // Rebuild live ranges to verify with holes.
  let ranges = build_live_ranges(func, liveness)
  let block_order = liveness.block_order

  // Rebuild MachineEnv to compute allocatable + scratch sets.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  let needs_x20_reserved = func.uses_mem0()
  let needs_x21_reserved = func.uses_func_table()
  let env = @abi.build_aarch64_machine_env(
    settings~,
    reserve_mem0_desc=needs_x20_reserved,
    reserve_func_table=needs_x21_reserved,
    reserve_x23=needs_x23_reserved,
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
  let param_ids : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for p in func.params {
    param_ids.add(p.id) |> ignore
  }
  for b in func.blocks {
    for p in b.params {
      param_ids.add(p.id) |> ignore
    }
  }

  // Call-clobbered sets.
  let call_clobbered_int : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for r in @abi.call_clobbered_gprs() {
    call_clobbered_int.add(r.index) |> ignore
  }
  // For C calls, be conservative like Cranelift: clobber all V0-V31.
  let call_clobbered_float_c : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for r in @abi.call_clobbered_fprs() {
    call_clobbered_float_c.add(r.index) |> ignore
  }
  // For Wasm-to-Wasm calls (same ABI), allow V8-V15 as callee-saved (low 64 bits).
  let call_clobbered_float_wasm : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for r in @abi.call_clobbered_fprs_same_abi() {
    call_clobbered_float_wasm.add(r.index) |> ignore
  }
  fn has_any_fixed_constraint_to(lr : LiveRange, preg : @abi.PReg) -> Bool {
    // Treat any FixedReg at any point as justification for using a register
    // outside the main allocatable pool (e.g. call-arg registers x0-x7).
    for use_pos in lr.uses {
      match use_pos.constraint {
        FixedReg(fr) => {
          // Compare by bank (int vs float/vector) and index.
          let same_bank = match (fr.class, preg.class) {
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
          if same_bank && fr.index == preg.index {
            return true
          }
        }
        AnyReg => ()
      }
    }
    false
  }

  // Build per-preg span lists for overlap checking.
  let preg_spans : Map[Int, Array[ProgPointRange]] = {}
  for entry in alloc.assignments {
    let (vreg_id, preg) = entry
    match ranges.get_by_vreg(vreg_id) {
      Some(lr) => {
        // Scratch regs must never be assigned.
        if preg.class is @abi.Int && scratch_int.contains(preg.index) {
          abort("regalloc verifier: assigned scratch GPR x\{preg.index}")
        }
        if preg.class is @abi.Float32 ||
          preg.class is @abi.Float64 ||
          preg.class is @abi.Vector {
          if scratch_float.contains(preg.index) {
            abort("regalloc verifier: assigned scratch V\{preg.index}")
          }
        }

        // Allocatable set checks.
        let fixed_reg = lr.get_fixed_reg()
        match lr.vreg.class {
          @abi.Int =>
            if !allowed_int.contains(preg.index) {
              // Allow parameters in ABI argument registers.
              let is_arg_gpr = preg.index >= 0 &&
                preg.index < @abi.MAX_REG_PARAMS
              if !(param_ids.contains(vreg_id) && is_arg_gpr) &&
                !(is_arg_gpr && !lr.crosses_call) &&
                !(fixed_reg is Some(fr) && fr.index == preg.index) &&
                !has_any_fixed_constraint_to(lr, preg) {
                abort(
                  "regalloc verifier: v\{vreg_id} assigned non-allocatable GPR x\{preg.index}",
                )
              }
            }
          @abi.Float32 | @abi.Float64 =>
            if !allowed_float.contains(preg.index) {
              if !(param_ids.contains(vreg_id) &&
                preg.index >= 0 &&
                preg.index < @abi.MAX_FLOAT_REG_PARAMS) &&
                !(fixed_reg is Some(fr) && fr.index == preg.index) {
                abort(
                  "regalloc verifier: v\{vreg_id} assigned non-allocatable FPR v\{preg.index}",
                )
              }
            }
          @abi.Vector =>
            if !allowed_vector.contains(preg.index) {
              if !(param_ids.contains(vreg_id) &&
                preg.index >= 0 &&
                preg.index < @abi.MAX_FLOAT_REG_PARAMS) &&
                !(fixed_reg is Some(fr) && fr.index == preg.index) {
                abort(
                  "regalloc verifier: v\{vreg_id} assigned non-allocatable vector v\{preg.index}",
                )
              }
            }
        }

        // Call-clobber safety.
        if lr.crosses_call {
          if lr.vreg.class is @abi.Vector {
            abort("regalloc verifier: vector value live across call must spill")
          }
          if preg.class is @abi.Int && call_clobbered_int.contains(preg.index) {
            abort(
              "regalloc verifier: value live across call assigned to caller-saved x\{preg.index}",
            )
          }
          if preg.class is @abi.Float32 || preg.class is @abi.Float64 {
            // If this value crosses any C call, treat all V regs as clobbered.
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
        let key = alias_key(preg)
        if preg_spans.get(key) is None {
          preg_spans.set(key, [])
        }
        let spans = preg_spans.get(key).unwrap()
        for span in lr.ranges {
          spans.push(span)
        }
      }
      None => ()
    }
  }

  // Overlap check: for each physical register location (bank+index), spans must not overlap.
  for entry in preg_spans {
    let (_, spans) = entry
    if spans.length() <= 1 {
      continue
    }
    spans.sort_by(fn(a, b) { a.start.compare_with_order(b.start, block_order) })
    for i in 1..<spans.length() {
      let prev = spans[i - 1]
      let cur = spans[i]
      if prev.overlaps(cur, block_order) {
        abort("regalloc verifier: overlapping allocations in same preg")
      }
    }
  }
}
