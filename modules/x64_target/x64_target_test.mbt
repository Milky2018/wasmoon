///|
test "x64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="6")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
fn custom_test_call_conv() -> @abi.CallConventionLayout {
  let arg_fprs : Array[@abi.PReg] = []
  let ret_fprs : Array[@abi.PReg] = []
  for i in 0..<8 {
    arg_fprs.push({ index: i, class: Float64 })
    ret_fprs.push({ index: i, class: Float64 })
  }
  {
    context_arg: { index: 7, class: Int },
    user_arg_gprs: [
      { index: 6, class: Int },
      { index: 2, class: Int },
      { index: 1, class: Int },
      { index: 8, class: Int },
      { index: 9, class: Int },
    ],
    arg_fprs,
    ret_gprs: [
      { index: 0, class: Int },
      { index: 2, class: Int },
      { index: 1, class: Int },
      { index: 8, class: Int },
      { index: 9, class: Int },
      { index: 6, class: Int },
      { index: 7, class: Int },
      { index: 10, class: Int },
    ],
    ret_fprs,
  }
}

///|
fn simple_add_function() -> @milkir.Function {
  let builder = @milkir.FunctionBuilder("add64")
  let lhs = builder.add_param(I64)
  let rhs = builder.add_param(I64)
  builder.add_result(I64)
  builder.return_([builder.iadd(lhs, rhs)])
  builder.get_function()
}

///|
test "x64 wrapper lowers MilkIR through canonical MachV" {
  let lowered = lower_function(simple_add_function())
  inspect(lowered.name, content="add64")
  inspect(lowered.blocks.length(), content="1")
  inspect(
    lowered.blocks[0].insts.any(fn(inst) { inst.opcode is Add(_) }),
    content="true",
  )
  inspect(lowered.blocks[0].terminator is Some(Return(_)), content="true")
}

///|
test "x64 wrapper accepts an explicit call convention" {
  let lowered = lower_function_with_call_conv(
    simple_add_function(),
    custom_test_call_conv(),
  )
  inspect(lowered.params.length(), content="2")
  inspect(lowered.results.length(), content="1")
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
