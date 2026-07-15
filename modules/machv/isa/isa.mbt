///|
/// ISA layer (Cranelift-style) for target-specific policy used by the JIT backend.
///
/// Centralize ABI/ISA policy (regalloc env + call-clobbered sets) behind a
/// stable interface. Host selection belongs to the embedding layer, which must
/// pass the chosen ISA explicitly into lowering, allocation, and emission.
pub(all) enum ISA {
  AArch64
  AMD64
} derive(Debug, Eq)

///|
/// Target-owned direct remainder instruction and its implicit register roles.
pub struct DirectRemainderPlan {
  opcode : @instr.Opcode
  dividend : @abi.PReg
  divisor : @abi.PReg
  result : @abi.PReg
  clobbers : Array[@abi.PReg]
}

///|
/// Return a direct remainder plan when the target has an architectural form.
/// Targets without one let lowering expand remainder through division and
/// multiply-subtract.
pub fn ISA::direct_remainder_plan(
  self : ISA,
  signed : Bool,
  is_64 : Bool,
) -> DirectRemainderPlan? {
  match self {
    AArch64 => None
    AMD64 => {
      let opcode : @instr.Opcode = if signed {
        AMD64(SRem(is_64))
      } else {
        AMD64(URem(is_64))
      }
      Some({
        opcode,
        dividend: { index: 0, class: Int }, // rax
        divisor: { index: 10, class: Int }, // reserved r10 scratch
        result: { index: 2, class: Int }, // rdx
        clobbers: [{ index: 0, class: Int }, { index: 2, class: Int }],
      })
    }
  }
}

///|
/// Condition set by an unordered floating-point comparison.
pub fn ISA::unordered_float_condition(self : ISA) -> @instr.Cond {
  match self {
    AArch64 => Vs
    AMD64 => AMD64(ParitySet)
  }
}

///|
/// Fixed register used by variable shifts when the target requires one.
pub fn ISA::shift_count_register(self : ISA) -> @abi.PReg? {
  match self {
    AArch64 => None
    AMD64 => Some({ index: 1, class: Int }) // rcx
  }
}

///|
/// Target-independent machine environment used by regalloc/checker.
///
/// This describes allocator preferences, callee-saved subsets and explicitly
/// reserved scratch registers for a given ISA + ABI settings combination.
pub struct MachineEnv {
  preferred_int : Array[@abi.PReg]
  nonpreferred_int : Array[@abi.PReg]
  preferred_float : Array[@abi.PReg]
  nonpreferred_float : Array[@abi.PReg]
  preferred_vector : Array[@abi.PReg]
  nonpreferred_vector : Array[@abi.PReg]
  callee_saved_int : Array[@abi.PReg]
  callee_saved_float : Array[@abi.PReg]

  // Scratch registers that are explicitly non-allocatable.
  scratch_int : Array[Int]
  scratch_float : Array[Int]
}

///|
fn MachineEnv::from_data(data : @spec.MachineEnvData) -> MachineEnv {
  {
    preferred_int: data.preferred_int,
    nonpreferred_int: data.nonpreferred_int,
    preferred_float: data.preferred_float,
    nonpreferred_float: data.nonpreferred_float,
    preferred_vector: data.preferred_vector,
    nonpreferred_vector: data.nonpreferred_vector,
    callee_saved_int: data.callee_saved_int,
    callee_saved_float: data.callee_saved_float,
    scratch_int: data.scratch_int,
    scratch_float: data.scratch_float,
  }
}

///|
pub fn ISA::machine_env(
  self : ISA,
  reserved_int_regs? : Array[Int] = [],
) -> MachineEnv {
  match self {
    AArch64 =>
      MachineEnv::from_data(@aarch64.build_machine_env(reserved_int_regs))
    AMD64 => MachineEnv::from_data(@amd64.build_machine_env(reserved_int_regs))
  }
}

///|
pub fn ISA::call_clobbered_gprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_gprs()
    AMD64 => @amd64.call_clobbered_gprs()
  }
}

///|
pub fn ISA::call_clobbered_fprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_fprs()
    AMD64 => @amd64.call_clobbered_fprs()
  }
}

///|
pub fn ISA::call_clobbered_fprs_same_abi(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_fprs_same_abi()
    AMD64 => @amd64.call_clobbered_fprs_same_abi()
  }
}

///|
/// Query an ISA-dependent integer register index for a given role.
pub fn ISA::int_reg_index(self : ISA, role : @spec.IntRegRole) -> Int {
  match self {
    AArch64 => @aarch64.int_reg_index(role)
    AMD64 => @amd64.int_reg_index(role)
  }
}

///|
/// Convenience: get an integer physical register for a role.
pub fn ISA::int_reg(self : ISA, role : @spec.IntRegRole) -> @abi.PReg {
  { index: self.int_reg_index(role), class: Int }
}

///|
pub fn ISA::scratch_reg_1_index(self : ISA) -> Int {
  self.int_reg_index(Scratch1)
}

///|
pub fn ISA::scratch_reg_2_index(self : ISA) -> Int {
  self.int_reg_index(Scratch2)
}

///|
pub fn ISA::fp_reg_index(self : ISA) -> Int {
  self.int_reg_index(FP)
}

///|
pub fn ISA::link_register_index(self : ISA) -> Int? {
  match self {
    AArch64 => Some(@aarch64.link_register_index())
    AMD64 => None
  }
}

///|
pub fn ISA::sret_reg_index(self : ISA) -> Int {
  self.int_reg_index(SRet)
}
