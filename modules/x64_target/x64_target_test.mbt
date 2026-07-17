///|
test "x64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="6")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
test "x64 target owns SystemV machine environment policy" {
  inspect(call_clobbered_gprs().length(), content="9")
  inspect(call_clobbered_fprs().length(), content="16")
  inspect(int_reg_index(Scratch1), content="10")
  let env = build_machine_env(reserved_int_regs=[12, 13, 14, 15])
  inspect(env.preferred_int.length(), content="7")
  inspect(env.nonpreferred_int.length(), content="1")
  inspect(env.callee_saved_int.length(), content="1")
  inspect(env.scratch_int.length(), content="2")
  inspect(env.scratch_float.length(), content="2")
}

///|
test "x64 allocatable regs include floating point registers" {
  let regs = allocatable_regs()
  inspect(regs.any(fn(r) { r.class == Float32 }), content="true")
  inspect(regs.any(fn(r) { r.class == Float64 }), content="true")
  inspect(regs.any(fn(r) { r.class == Vector }), content="true")
}
