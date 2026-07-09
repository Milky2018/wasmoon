///|
fn test_embedding_abi() -> @abi.EmbeddingABI {
  let call_conv : @abi.CallConventionLayout = {
    context_arg: { index: 27, class: Int },
    user_arg_gprs: [
      { index: 0, class: Int },
      { index: 1, class: Int },
      { index: 2, class: Int },
      { index: 3, class: Int },
    ],
    arg_fprs: [
      { index: 0, class: Float64 },
      { index: 1, class: Float64 },
      { index: 2, class: Float64 },
      { index: 3, class: Float64 },
    ],
    ret_gprs: [{ index: 0, class: Int }, { index: 1, class: Int }],
    ret_fprs: [{ index: 0, class: Float64 }, { index: 1, class: Float64 }],
  }
  EmbeddingABI(call_conv, reserve_context_role=false)
}

///|
fn copy_function() -> @machv.Function {
  let builder = @machv.FunctionBuilder::FunctionBuilder("copy")
  let src = builder.add_param(Int)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  builder.finish()
}

///|
test "allocate canonical MachV function through backtracking path" {
  let allocated = allocate_registers_backtracking_with_isa(
    copy_function(),
    AArch64,
    embedding_abi=Some(test_embedding_abi()),
  )
  inspect(allocated.name, content="copy")
  inspect(allocated.blocks.length(), content="1")
  inspect(allocated.blocks[0].terminator is Some(Return(_)), content="true")
}

///|
test "output path keeps MachV virtual-register IR and reports allocations" {
  let (func, output) = allocate_registers_backtracking_output_with_isa(
    copy_function(),
    AArch64,
    embedding_abi=Some(test_embedding_abi()),
  )
  inspect(func.blocks[0].insts.length(), content="1")
  inspect(output.get_num_spillslots(), content="0")
  inspect(output.inst_def_loc(0, 0, false, 0) is Reg(_), content="true")
  inspect(output.inst_use_loc(0, 0, false, 0) is Reg(_), content="true")
}

///|
test "fixed constraints are consumed by canonical MachV regalloc" {
  let builder = @machv.FunctionBuilder::FunctionBuilder("fixed")
  let src = builder.add_param(Int)
  let dst = builder.new_vreg(Int)
  let fixed : @abi.PReg = { index: 1, class: Int }
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }], def_constraints=[
    FixedReg(fixed),
  ])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let (_func, output) = allocate_registers_backtracking_output_with_isa(
    builder.finish(),
    AArch64,
    embedding_abi=Some(test_embedding_abi()),
  )
  inspect(output.inst_def_loc(0, 0, false, 0), content="x1")
}
