///|
test "build simple MachV function" {
  let func = Function::new("copy")
  let entry = func.new_block()
  let src = func.new_vreg(Int)
  let dst = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(Operand::use_reg(Virtual(src)))
  mov.add_operand(Operand::def(Virtual(dst)))
  entry.append(mov)
  inspect(func.blocks.length(), content="1")
  inspect(entry.instructions.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "represent call clobbers and stack slots" {
  let func = Function::new("call")
  let entry = func.new_block()
  let spill = func.new_stack_slot(8, 8)
  let call = func.new_inst(Call("host.fn"))
  call.add_clobber({ index: 0, class: Int })
  call.set_stack_effect(CallFrame(16))
  entry.append(func.new_inst(Store(spill)))
  entry.append(call)
  inspect(func.stack_slots.length(), content="1")
  inspect(entry.instructions.length(), content="2")
}

///|
test "print MachV function" {
  let func = Function::new("printed")
  let p0 = func.add_param(Int)
  func.add_result(Int)
  let entry = func.new_block()
  let dst = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(Operand::use_reg(Virtual(p0)))
  mov.add_operand(Operand::def(Virtual(dst)))
  entry.append(mov)
  entry.set_terminator(TermReturn([Virtual(dst)]))
  inspect(
    func.print(),
    content=(
      #|function printed(v0) -> (int) {
      #|block0:
      #|    i0: Move use v0, def v1
      #|    return v1
      #|}
      #|
    ),
  )
}
