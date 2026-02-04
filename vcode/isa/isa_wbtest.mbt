///|
/// Whitebox tests for the ISA policy layer.
///
/// Keep these tests lightweight; CI acceptance uses full WAST runners.
test "ISA::current matches host arch" {
  match c_host_arch() {
    0 => inspect(ISA::current() is ISA::AArch64, content="true")
    1 => inspect(ISA::current() is ISA::X86_64, content="true")
    _ => inspect(ISA::current() is ISA::AArch64, content="true")
  }
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
test "Wasm ABI arg/ret reg counts (shape)" {
  let a = ISA::AArch64
  inspect(a.wasm_vmctx_arg_preg().index, content="0")
  inspect(a.wasm_user_arg_gprs().length(), content="7")
  inspect(a.wasm_arg_fprs().length(), content="8")
  inspect(a.wasm_ret_gprs().length(), content="8")
  inspect(a.wasm_ret_fprs().length(), content="8")
  let x = ISA::X86_64
  inspect(x.wasm_vmctx_arg_preg().index, content="7")
  inspect(x.wasm_user_arg_gprs().length(), content="6")
  inspect(x.wasm_arg_fprs().length(), content="8")
  inspect(x.wasm_ret_gprs().length(), content="8")
  inspect(x.wasm_ret_fprs().length(), content="8")
}

///|
test "AArch64 MachineEnv reserves scratch regs" {
  let env = ISA::AArch64.machine_env()
  inspect(env.scratch_int, content="[16, 17]")
  inspect(env.scratch_float, content="[16, 17]")
}

///|
test "x86_64 call-clobbered sets basic shape" {
  let isa = ISA::X86_64
  // SysV AMD64 caller-saved GPRs: rax,rcx,rdx,rsi,rdi,r8-r11 => 9 regs.
  inspect(isa.call_clobbered_gprs().length(), content="9")
  // SysV AMD64 clobbers all XMM0-XMM15 => 16 regs.
  inspect(isa.call_clobbered_fprs().length(), content="16")
}

///|
test "x86_64 MachineEnv reserves scratch regs" {
  let env = ISA::X86_64.machine_env()
  inspect(env.scratch_int, content="[10, 11]")
  inspect(env.scratch_float, content="[14, 15]")
}
