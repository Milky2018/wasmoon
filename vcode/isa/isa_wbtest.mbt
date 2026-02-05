///|
/// Whitebox tests for the ISA policy layer.
///
/// Keep these tests lightweight; CI acceptance uses full WAST runners.
test "ISA::current is AArch64 for now" {
  inspect(ISA::current() is ISA::AArch64, content="true")
}

///|
test "AArch64 call-clobbered sets basic shape" {
  let isa = ISA::AArch64
  // AArch64 caller-saved GPRs: x0-x17 => 18 regs.
  inspect(isa.call_clobbered_gprs().length(), content="18")
  // C-call clobbered FPRs: v0-v31 => 32 regs.
  inspect(isa.call_clobbered_fprs().length(), content="32")
}

///|
test "AArch64 MachineEnv reserves scratch regs" {
  let env = ISA::AArch64.machine_env()
  inspect(env.scratch_int, content="[16, 17]")
  inspect(env.scratch_float, content="[16, 17]")
}
