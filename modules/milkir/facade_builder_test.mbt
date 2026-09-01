///|
test "public signature construction materializes canonical parameters" {
  let signature = @milkir.Signature::Signature([I32, I64], [I64])
  let func = @milkir.Function::with_signature("signature", signature)
  debug_inspect(
    func.param(0),
    content=(
      #|Some({ id: 0, ty: I32 })
    ),
  )
  debug_inspect(
    func.param(1),
    content=(
      #|Some({ id: 1, ty: I64 })
    ),
  )
  debug_inspect(
    func.signature(),
    content=(
      #|{ params: [I32, I64], results: [I64] }
    ),
  )
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
  let join_block = builder.create_block()
  let selected = builder.add_block_param(join_block, I64)
  builder.branch(condition, join_block, [on_true], join_block, [on_false])
  builder.switch_to_block(join_block)
  builder.return_([selected])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function choose(v0:i32, v1:i64, v2:i64) -> i64 {
      #|block0:
      #|    branch v0, block1(v1), block1(v2)
      #|block1(v3:i64):
      #|    return v3
      #|}
      #|
    ),
  )
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
  debug_inspect(
    params,
    content=(
      #|[{ id: 2, ty: I32 }, { id: 3, ty: I64 }]
    ),
  )
  builder.jump(target, [first, second])
  builder.switch_to_block(target)
  builder.return_([params[1]])
  let func = builder.finalize()
  inspect(
    func.print(),
    content=(
      #|function forward_parameters(v0:i32, v1:i64) -> i64 {
      #|block0:
      #|    jump block1(v0, v1)
      #|block1(v2:i32, v3:i64):
      #|    return v3
      #|}
      #|
    ),
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
  debug_inspect(
    inst.metadata,
    content=(
      #|[SourceLoc("input.mbt:1"), Comment("generated constant")]
    ),
  )
  debug_inspect(
    inst.first_result(),
    content=(
      #|Some({ id: 0, ty: I32 })
    ),
  )
  debug_inspect(
    inst.all_results(),
    content=(
      #|[{ id: 0, ty: I32 }]
    ),
  )
}
