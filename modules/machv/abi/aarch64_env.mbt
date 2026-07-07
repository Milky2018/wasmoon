///|
/// AArch64 Machine Environment (Cranelift-inspired)
///
/// This describes register allocation preferences, reserved registers, and
/// call-clobber behavior in a single place.
///
/// Design goals:
/// - Keep target/ABI policy out of the allocator core.
/// - Provide ordered preferred/non-preferred register lists.
/// - Make reserved scratch registers explicit.
///
/// Note: V16/V17 are reserved as scratch temporaries in several emission paths
/// (SIMD select/popcnt/etc). Unlike Cranelift, we keep them non-allocatable
/// for now.
pub struct AArch64MachineEnv {
  preferred_int : Array[PReg]
  nonpreferred_int : Array[PReg]
  preferred_float : Array[PReg]
  nonpreferred_float : Array[PReg]
  preferred_vector : Array[PReg]
  nonpreferred_vector : Array[PReg]

  // Callee-saved subsets (used when a value must survive across calls).
  callee_saved_int : Array[PReg]
  callee_saved_float : Array[PReg]

  // Scratch registers that are explicitly non-allocatable.
  // X16/X17 are the standard AArch64 inter-procedural temporaries (IP0/IP1).
  scratch_int : Array[Int]
  // V16/V17 are reserved scratch for internal lowering/emission.
  scratch_float : Array[Int]
}

///|
const AARCH64_CONTEXT_CACHE_REG_0 : Int = 20

///|
const AARCH64_CONTEXT_CACHE_REG_1 : Int = 19

///|
/// Construct the AArch64 machine environment, optionally reserving some regs.
pub fn build_aarch64_machine_env(
  settings? : ABISettings = ABISettings::default(),
  reserve_context_cache_0? : Bool = false,
  reserve_context_cache_1? : Bool = false,
  reserve_x23? : Bool = false,
) -> AArch64MachineEnv {
  let preferred_int : Array[PReg] = []
  let nonpreferred_int : Array[PReg] = []
  let callee_saved_int : Array[PReg] = []

  // Preferred GPRs for allocation.
  //
  // Cranelift’s `create_reg_env()` prefers x0-x15, but this allocator currently
  // relies on keeping x0-x7 out of the general pool because they are heavily
  // used for call-argument constraints.
  for r in allocatable_scratch_regs() {
    preferred_int.push(r)
  }

  // Nonpreferred callee-saved GPRs: x19-x28, excluding pinned reg when enabled.
  for
    r in allocatable_callee_saved_regs(
      enable_pinned_reg=settings.enable_pinned_reg,
    ) {
    if reserve_x23 && r.index == 23 {
      continue
    }
    if reserve_context_cache_0 && r.index == AARCH64_CONTEXT_CACHE_REG_0 {
      continue
    }
    if reserve_context_cache_1 && r.index == AARCH64_CONTEXT_CACHE_REG_1 {
      continue
    }
    nonpreferred_int.push(r)
    callee_saved_int.push(r)
  }

  // Note: callee_saved_int matches nonpreferred_int for the AAPCS64 callee-saved subset.

  // Float regs:
  // Prefer argument regs V0-V7, then caller-saved V18-V31.
  // Callee-saved V8-V15 are non-preferred.
  // We keep V16/V17 non-allocatable as scratch.
  let preferred_float : Array[PReg] = []
  let nonpreferred_float : Array[PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_float.push(r)
  }
  for r in allocatable_scratch_fprs() {
    if r.index == 16 || r.index == 17 {
      continue
    }
    preferred_float.push(r)
  }
  let callee_saved_float = callee_saved_fprs()
  for r in callee_saved_float {
    nonpreferred_float.push(r)
  }

  // Vector regs share the same Vn bank as floats.
  // For now, we only use caller-saved regs to keep ABI semantics correct for
  // host calls (AAPCS64 only guarantees low 64-bit preservation of V8-V15).
  let preferred_vector : Array[PReg] = []
  let nonpreferred_vector : Array[PReg] = []
  for r in aapcs64_arg_fprs() {
    preferred_vector.push({ index: r.index, class: Vector })
  }
  for r in allocatable_scratch_fprs() {
    if r.index == 16 || r.index == 17 {
      continue
    }
    preferred_vector.push({ index: r.index, class: Vector })
  }
  {
    preferred_int,
    nonpreferred_int,
    preferred_float,
    nonpreferred_float,
    preferred_vector,
    nonpreferred_vector,
    callee_saved_int,
    callee_saved_float,
    scratch_int: [SCRATCH_REG_1, SCRATCH_REG_2],
    scratch_float: [16, 17],
  }
}
