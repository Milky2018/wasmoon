///|
fn finalized_function_with_removed_definition() -> @milkir.Function raise {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "mutated_after_finalize",
  )
  builder.add_result(I32)
  let result = builder.iconst_i32(1)
  builder.return_([result])
  let func = builder.finalize()
  func.blocks[0].instructions.clear()
  func
}

///|
test "core lowering rejects a function mutated after finalization" {
  let func = finalized_function_with_removed_definition()
  try @lower.lower_function(func, run_ir_opt=false) catch {
    err => inspect(err, content="UndefinedValue(value_id=0)")
  } noraise {
    _ => fail("expected core lowering to return the validation error")
  }
}

///|
test "dialect lowering rejects a function mutated after finalization" {
  let func = finalized_function_with_removed_definition()
  try
    @lower.lower_dialect_function(
      func,
      "demo",
      fn(_) { None },
      fn(_, _, block, _) { Handled(block) },
      run_ir_opt=false,
    )
  catch {
    err => inspect(err, content="UndefinedValue(value_id=0)")
  } noraise {
    _ => fail("expected dialect lowering to return the validation error")
  }
}

///|
test "dialect lowering applies its explicit adapter verifier" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("invalid_dialect")
  builder.emit_void_ext_inst(ExtOp("demo", "invalid", []), [])
  builder.return_([])
  let func = builder.finalize()
  try
    @lower.lower_dialect_function(
      func,
      "demo",
      fn(_) { Some("demo adapter rejected the extension") },
      fn(_, _, block, _) { Handled(block) },
      run_ir_opt=false,
    )
  catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="demo adapter rejected the extension")
        ),
      )
  } noraise {
    _ => fail("expected dialect lowering to apply adapter validation")
  }
}

///|
test "conditional edge arguments lower through explicit jump blocks" {
  let signature = @milkir.Signature::Signature([], [I64])
  let func = @milkir.Function::with_signature("branch_edges", signature)
  let cond = func.new_value(I32)
  let true_value = func.new_value(I64)
  let false_value = func.new_value(I64)
  let true_param = func.new_value(I64)
  let false_param = func.new_value(I64)
  let entry = func.new_block([])
  let then_block = func.new_block([true_param])
  let else_block = func.new_block([false_param])
  entry.append_inst(func.new_inst(Scalar(IntConst(1L)), [], [cond]))
  entry.append_inst(func.new_inst(Scalar(IntConst(42L)), [], [true_value]))
  entry.append_inst(func.new_inst(Scalar(IntConst(7L)), [], [false_value]))
  entry.set_terminator(
    Branch(cond, then_block.id, [true_value], else_block.id, [false_value]),
  )
  then_block.set_terminator(Return([true_param]))
  else_block.set_terminator(Return([false_param]))
  let call_conv : @abi.CallConventionLayout = {
    context_arg: { index: 27, class: Int },
    user_arg_gprs: [],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [],
  }
  let embedding_abi = @abi.EmbeddingABI::EmbeddingABI(
    call_conv,
    reserve_context_role=false,
  )
  let lowered = @lower.lower_function(
    func,
    run_ir_opt=false,
    embedding_abi=Some(embedding_abi),
  )
  inspect(
    lowered.print(),
    content=(
      #|machv branch_edges() -> int {
      #|block0:
      #|    v2 = ldi 1
      #|    v3 = ldi 42
      #|    v4 = ldi 7
      #|    branch v2, block3, block4
      #|block1(v0:int):
      #|    ret v0
      #|block2(v1:int):
      #|    ret v1
      #|block3:
      #|    jump block1 (v3)
      #|block4:
      #|    jump block2 (v4)
      #|}
      #|
    ),
  )
}
