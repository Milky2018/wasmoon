///|
test "emit AArch64 move, add, and return bytes" {
  let func = @machv.Function::new("entry")
  let entry = func.new_block()
  let move_inst = func.new_inst(Move)
  move_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  move_inst.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(move_inst)
  let add_inst = func.new_inst(IntAdd)
  add_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  add_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  add_inst.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(add_inst)
  entry.append(func.new_inst(Return))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[224, 3, 1, 170, 32, 0, 2, 139, 192, 3, 95, 214]",
  )
  inspect(object.debug_entries.length(), content="3")
  inspect(object.relocations.length(), content="0")
}

///|
test "emit X64 move, add, and return bytes" {
  let func = @machv.Function::new("entry")
  let entry = func.new_block()
  let move_inst = func.new_inst(Move)
  move_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 7, class: Int })),
  )
  move_inst.add_operand(
    @machv.Operand::def(Physical({ index: 14, class: Int })),
  )
  entry.append(move_inst)
  let add_inst = func.new_inst(IntAdd)
  add_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  add_inst.add_operand(
    @machv.Operand::use_reg(Physical({ index: 8, class: Int })),
  )
  add_inst.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(add_inst)
  entry.append(func.new_inst(Return))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(object.code, content="[73, 137, 254, 76, 1, 192, 195]")
  inspect(object.debug_entries.length(), content="3")
  inspect(object.relocations.length(), content="0")
}

///|
test "emit X64 generic relocations and stack maps" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  let call = func.new_inst(Call("wasmoon.runtime.helper"))
  call.set_stack_effect(CallFrame(16))
  entry.append(call)
  entry.append(func.new_inst(Jump(1)))
  let exit = func.new_block()
  exit.append(func.new_inst(Return))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(object.code, content="[232, 0, 0, 0, 0, 233, 0, 0, 0, 0, 195]")
  inspect(object.relocations.length(), content="2")
  inspect(object.fixups.length(), content="1")
  inspect(object.stack_maps.length(), content="1")
  inspect(object.debug_entries.length(), content="3")
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
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[0, 0, 0, 148, 0, 0, 0, 20, 192, 3, 95, 214]",
  )
  inspect(object.relocations.length(), content="2")
  inspect(object.fixups.length(), content="1")
  inspect(object.stack_maps.length(), content="1")
  inspect(object.debug_entries.length(), content="3")
}

///|
test "reject unsupported MachV opcode instead of pseudo emitting" {
  let func = @machv.Function::new("unsupported")
  let entry = func.new_block()
  entry.append(func.new_inst(Target("x64.iadd")))
  try emit_function(func) catch {
    UnsupportedOpcode(_) => inspect("unsupported", content="unsupported")
    _ => fail("unexpected emit error")
  } noraise {
    _ => fail("expected unsupported opcode")
  }
}
