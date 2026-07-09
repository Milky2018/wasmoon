///|
test "AArch64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="8")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
fn custom_test_call_conv() -> @abi.CallConventionLayout {
  fn regs(start : Int, count : Int, class : @abi.RegClass) -> Array[@abi.PReg] {
    let out : Array[@abi.PReg] = []
    for i in start..<(start + count) {
      out.push({ index: i, class })
    }
    out
  }
  {
    context_arg: { index: 0, class: Int },
    user_arg_gprs: [
      { index: 1, class: Int },
      { index: 2, class: Int },
      { index: 3, class: Int },
      { index: 4, class: Int },
      { index: 5, class: Int },
      { index: 6, class: Int },
      { index: 7, class: Int },
    ],
    arg_fprs: regs(0, 8, Float64),
    ret_gprs: regs(0, 8, Int),
    ret_fprs: regs(0, 8, Float64),
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
test "AArch64 wrapper lowers MilkIR through canonical MachV" {
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
test "AArch64 wrapper accepts an explicit call convention" {
  let lowered = lower_function_with_call_conv(
    simple_add_function(),
    custom_test_call_conv(),
  )
  inspect(lowered.params.length(), content="2")
  inspect(lowered.results.length(), content="1")
}

///|
test "AArch64 allocatable regs include floating point registers" {
  let regs = allocatable_regs()
  inspect(regs.any(fn(r) { r.class == Float32 }), content="true")
  inspect(regs.any(fn(r) { r.class == Float64 }), content="true")
  inspect(regs.any(fn(r) { r.class == Vector }), content="true")
}
