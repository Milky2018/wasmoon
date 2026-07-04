///|
test "emit MachV function into object-like records" {
  let func = @machv.Function::new("entry")
  let entry = func.new_block()
  let value = func.new_vreg(Int)
  let target = func.new_inst(Target("x64.iadd"))
  target.add_operand(@machv.Operand::def(Virtual(value)))
  entry.append(target)
  entry.append(func.new_inst(Return))
  let object = emit_function(func)
  inspect(object.code.length(), content="5")
  inspect(object.debug_entries.length(), content="2")
  inspect(object.relocations.length(), content="0")
}

///|
test "emit generic relocations and stack maps" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  let call = func.new_inst(Call("wasmoon.runtime.helper"))
  call.set_stack_effect(CallFrame(16))
  entry.append(call)
  entry.append(func.new_inst(Jump(1)))
  let exit = func.new_block()
  exit.append(func.new_inst(Return))
  let object = emit_function(func)
  inspect(object.relocations.length(), content="2")
  inspect(object.fixups.length(), content="1")
  inspect(object.stack_maps.length(), content="1")
  inspect(object.debug_entries.length(), content="3")
}
