///|
test "public signature construction materializes canonical parameters" {
  let signature = @milkir.Signature::Signature([I32, I64], [I64])
  let func = @milkir.Function::with_signature("signature", signature)
  inspect(func.params.length(), content="2")
  guard func.param(0) is Some(first) else {
    fail("expected first function parameter")
  }
  guard func.param(1) is Some(second) else {
    fail("expected second function parameter")
  }
  inspect(first.ty, content="i32")
  inspect(second.ty, content="i64")
  inspect(func.signature() == signature, content="true")
}

///|
test "public builder finalizes and prints a scalar function" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("add_two")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let two = builder.iconst_i32(2)
  let result = builder.iadd(value, two)
  builder.return_([result])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function add_two(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 2
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "public builder passes values through block parameters" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("choose")
  let condition = builder.add_param(I32)
  let on_true = builder.add_param(I64)
  let on_false = builder.add_param(I64)
  builder.add_result(I64)
  let true_block = builder.create_block()
  let false_block = builder.create_block()
  let join_block = builder.create_block()
  let selected = builder.add_block_param(join_block, I64)
  builder.brnz(condition, true_block, false_block)
  builder.switch_to_block(true_block)
  builder.jump(join_block, [on_true])
  builder.switch_to_block(false_block)
  builder.jump(join_block, [on_false])
  builder.switch_to_block(join_block)
  builder.return_([selected])
  let func = builder.finalize()
  inspect(func.blocks.length(), content="4")
  inspect(func.print().contains("block3(v3:i64)"), content="true")
  inspect(func.print().contains("jump block3(v1)"), content="true")
  inspect(func.print().contains("jump block3(v2)"), content="true")
}

///|
test "public builder derives block parameters from function parameters" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("forward_parameters")
  let first = builder.add_param(I32)
  let second = builder.add_param(I64)
  builder.add_result(I64)
  let target = builder.create_block()
  builder.append_block_params_for_function_params(target)
  let params = builder.block_params(target)
  inspect(params.length(), content="2")
  builder.jump(target, [first, second])
  builder.switch_to_block(target)
  builder.return_([params[1]])
  let func = builder.finalize()
  debug_inspect(
    func.signature(),
    content="{ params: [I32, I64], results: [I64] }",
  )
}

///|
test "public builder exposes integer constants without inspecting instructions" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("constant_lookup")
  builder.add_result(I32)
  let forty = builder.iconst_i32(40)
  let two = builder.iconst_i32(2)
  let answer = builder.iadd(forty, two)
  builder.return_([answer])
  debug_inspect(builder.get_const_value(forty), content="Some(40)")
  debug_inspect(builder.get_const_value(answer), content="None")
  builder.finalize() |> ignore
}

///|
test "public low-level construction retains instruction metadata" {
  let func = @milkir.Function::new_empty("metadata")
  func.add_result(I32)
  let entry = func.new_block0()
  let result = func.new_value(I32)
  let inst = func.new_inst(Scalar(IntConst(7L)), [], [result])
  inst.add_metadata(SourceLoc("input.mbt:1"))
  inst.add_metadata(Comment("generated constant"))
  entry.append_inst(inst)
  entry.set_terminator(Return([result]))
  func.verify()
  inspect(inst.metadata.length(), content="2")
  inspect(inst.first_result() == Some(result), content="true")
  debug_inspect(inst.all_results(), content="[{ id: 0, ty: I32 }]")
}
