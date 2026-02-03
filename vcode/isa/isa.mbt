///|
/// ISA layer (Cranelift-style) for target-specific policy used by the JIT backend.
///
/// Step 1 goal: centralize ABI/ISA policy (regalloc env + call-clobbered sets)
/// behind a stable interface so future AMD64 support can plug in cleanly.
///
/// Note: Wasmoon currently only generates AArch64 machine code. `ISA::current()`
/// always returns `AArch64` for now; x86_64 is a stub and must compile only.

///|
#warnings("-unused_constructor")
pub(all) enum ISA {
  AArch64
  X86_64
}

///|
pub fn ISA::current() -> ISA {
  match c_host_arch() {
    1 => X86_64
    0 => AArch64
    _ => AArch64
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
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
  reserve_mem0_desc? : Bool = false,
  reserve_func_table? : Bool = false,
  reserve_extra_results_ptr? : Bool = false,
) -> MachineEnv {
  match self {
    AArch64 =>
      MachineEnv::from_data(
        @aarch64.build_machine_env(
          settings, reserve_mem0_desc, reserve_func_table, reserve_extra_results_ptr,
        ),
      )
    X86_64 =>
      MachineEnv::from_data(
        @x86_64.build_machine_env(
          settings, reserve_mem0_desc, reserve_func_table, reserve_extra_results_ptr,
        ),
      )
  }
}

///|
pub fn ISA::call_clobbered_gprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_gprs()
    X86_64 => @x86_64.call_clobbered_gprs()
  }
}

///|
pub fn ISA::call_clobbered_fprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_fprs()
    X86_64 => @x86_64.call_clobbered_fprs()
  }
}

///|
pub fn ISA::call_clobbered_fprs_same_abi(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.call_clobbered_fprs_same_abi()
    X86_64 => @x86_64.call_clobbered_fprs_same_abi()
  }
}

///|
/// Wasmoon's internal Wasm-to-Wasm calling convention: VMContext argument register.
pub fn ISA::wasm_vmctx_arg_preg(self : ISA) -> @abi.PReg {
  match self {
    AArch64 => @aarch64.wasm_vmctx_arg_preg()
    X86_64 => @x86_64.wasm_vmctx_arg_preg()
  }
}

///|
/// Wasmoon's internal Wasm-to-Wasm calling convention: user integer argument registers.
pub fn ISA::wasm_user_arg_gprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.wasm_user_arg_gprs()
    X86_64 => @x86_64.wasm_user_arg_gprs()
  }
}

///|
/// Wasmoon's internal Wasm-to-Wasm calling convention: float argument registers.
pub fn ISA::wasm_arg_fprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.wasm_arg_fprs()
    X86_64 => @x86_64.wasm_arg_fprs()
  }
}

///|
/// Wasmoon's internal Wasm-to-Wasm calling convention: integer return registers.
pub fn ISA::wasm_ret_gprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.wasm_ret_gprs()
    X86_64 => @x86_64.wasm_ret_gprs()
  }
}

///|
/// Wasmoon's internal Wasm-to-Wasm calling convention: float return registers.
pub fn ISA::wasm_ret_fprs(self : ISA) -> Array[@abi.PReg] {
  match self {
    AArch64 => @aarch64.wasm_ret_fprs()
    X86_64 => @x86_64.wasm_ret_fprs()
  }
}

///|
/// Query an ISA-dependent integer register index for a given role.
pub fn ISA::int_reg_index(self : ISA, role : @spec.IntRegRole) -> Int {
  match self {
    AArch64 => @aarch64.int_reg_index(role)
    X86_64 => @x86_64.int_reg_index(role)
  }
}

///|
/// Convenience: get an integer physical register for a role.
pub fn ISA::int_reg(self : ISA, role : @spec.IntRegRole) -> @abi.PReg {
  { index: self.int_reg_index(role), class: @abi.Int }
}

///|
pub fn ISA::vmctx_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::Vmctx)
}

///|
pub fn ISA::mem0_desc_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::Mem0Desc)
}

///|
pub fn ISA::func_table_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::FuncTable)
}

///|
pub fn ISA::extra_results_ptr_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::ExtraResultsPtr)
}

///|
pub fn ISA::scratch_reg_1_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::Scratch1)
}

///|
pub fn ISA::scratch_reg_2_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::Scratch2)
}

///|
pub fn ISA::fp_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::FP)
}

///|
pub fn ISA::lr_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::LR)
}

///|
pub fn ISA::sret_reg_index(self : ISA) -> Int {
  self.int_reg_index(@spec.IntRegRole::SRet)
}

///|
pub fn ISA::vmctx_preg(self : ISA) -> @abi.PReg {
  { index: self.vmctx_reg_index(), class: @abi.Int }
}
