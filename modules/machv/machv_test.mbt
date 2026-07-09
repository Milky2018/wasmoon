///|
test "build simple MachV function with FunctionBuilder" {
  let builder = FunctionBuilder::FunctionBuilder("copy")
  let src = builder.add_param(Int)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let func = builder.finish()
  inspect(func.name, content="copy")
  inspect(func.params.length(), content="1")
  inspect(func.blocks.length(), content="1")
  inspect(func.blocks[0].insts.length(), content="1")
  inspect(func.blocks[0].terminator is Some(Return(_)), content="true")
}

///|
test "builder supports explicit blocks and branches" {
  let builder = FunctionBuilder::FunctionBuilder("branch")
  let cond = builder.add_param(Int)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.terminate(Branch(Virtual(cond), then_block, else_block))
  builder.switch_to_block(then_block)
  builder.terminate(Return([]))
  builder.switch_to_block(else_block)
  builder.terminate(Return([]))
  let func = builder.finish()
  inspect(func.blocks.length(), content="3")
  inspect(func.blocks[0].terminator is Some(Branch(_, _, _)), content="true")
}

///|
test "print canonical MachV function" {
  let builder = FunctionBuilder::FunctionBuilder("printed")
  let src = builder.add_param(Int)
  builder.add_result(I64)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  inspect(
    builder.finish().print(),
    content=(
      #|machv printed(v0:int) {
      #|block0:
      #|    v1 = mov v0
      #|    ret v1
      #|}
      #|
    ),
  )
}
