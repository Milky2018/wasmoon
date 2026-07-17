///|
fn test_embedding_abi() -> @abi.EmbeddingABI {
  let call_conv : @abi.CallConventionLayout = {
    context_arg: { index: 12, class: Int },
    user_arg_gprs: [
      { index: 7, class: Int },
      { index: 6, class: Int },
      { index: 2, class: Int },
      { index: 1, class: Int },
    ],
    arg_fprs: [
      { index: 0, class: Float64 },
      { index: 1, class: Float64 },
      { index: 2, class: Float64 },
      { index: 3, class: Float64 },
    ],
    ret_gprs: [{ index: 0, class: Int }, { index: 2, class: Int }],
    ret_fprs: [{ index: 0, class: Float64 }, { index: 1, class: Float64 }],
  }
  EmbeddingABI(call_conv, reserve_context_role=false)
}

///|
fn copy_function() -> @machv.Function raise @machv.VerifyError {
  let builder = @machv.FunctionBuilder::FunctionBuilder("copy")
  let src = builder.add_param(Int)
  builder.add_result(I64)
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
    AMD64,
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
    AMD64,
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
  builder.add_result(I64)
  let dst = builder.new_vreg(Int)
  let fixed : @abi.PReg = { index: 1, class: Int }
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }], def_constraints=[
    FixedReg(fixed),
  ])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let (_func, output) = allocate_registers_backtracking_output_with_isa(
    builder.finish(),
    AMD64,
    embedding_abi=Some(test_embedding_abi()),
  )
  inspect(output.inst_def_loc(0, 0, false, 0), content="x1")
}

///|
test "regalloc rejects invalid MachV before analysis" {
  let func = @machv.Function::Function("invalid_regalloc_input")
  func.new_block() |> ignore
  try allocate_registers_backtracking_with_isa(func, AMD64) catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected regalloc input verification to fail")
  }
}

///|
test "regalloc rejects non-canonical block id layout" {
  let func = @machv.Function::Function("reordered_blocks")
  func.new_block().set_terminator(Return([]))
  func.new_block().set_terminator(Return([]))
  func.get_blocks().rev_in_place()
  try allocate_registers_backtracking_with_isa(func, AMD64) catch {
    err =>
      inspect(err, content="InvalidBlockLayout(block_id=1, expected_index=0)")
  } noraise {
    _ => fail("expected regalloc input verification to fail")
  }
}

///|
test "regalloc rejects the removed legacy AArch64 target" {
  let output = Output::Output()
  try output.validate_for_isa(AArch64) catch {
    err =>
      inspect(
        err,
        content=(
          #|InvalidInstruction(message="legacy AArch64 register allocation has been removed")
        ),
      )
  } noraise {
    _ => fail("expected regalloc output verification to fail")
  }
}
