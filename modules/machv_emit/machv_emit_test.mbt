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
test "emit X64 integer constants and arithmetic bytes" {
  let func = @machv.Function::new("int_ops")
  let entry = func.new_block()
  let c = func.new_inst(IntConst(42L))
  c.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(c)
  let sub = func.new_inst(IntSub)
  sub.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  sub.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  sub.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(sub)
  let mul = func.new_inst(IntMul)
  mul.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  mul.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  mul.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(mul)
  let and_ = func.new_inst(IntAnd)
  and_.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  and_.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  and_.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(and_)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  72,
      #|  184,
      #|  42,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
      #|  72,
      #|  137,
      #|  194,
      #|  72,
      #|  41,
      #|  202,
      #|  72,
      #|  15,
      #|  175,
      #|  209,
      #|  72,
      #|  33,
      #|  202,
      #|  195,
      #|]
    ),
  )
}

///|
test "emit X64 pointer memory bytes" {
  let func = @machv.Function::new("mem")
  let entry = func.new_block()
  let load = func.new_inst(LoadPtr(MemI64, 8))
  load.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  load.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(load)
  let store = func.new_inst(StorePtr(MemI64, 16))
  store.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  store.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  entry.append(store)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[72, 139, 136, 8, 0, 0, 0, 72, 137, 136, 16, 0, 0, 0, 195]",
  )
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
test "emit MachV terminators as target bytes" {
  let func = @machv.Function::new("term")
  let entry = func.new_block()
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(object.code, content="[195]")
  inspect(object.debug_entries.length(), content="1")
  inspect(object.debug_entries[0].inst_id, content="-1")
}

///|
test "emit X64 conditional branch terminator" {
  let func = @machv.Function::new("branch")
  let entry = func.new_block()
  let then_block = func.new_block()
  let else_block = func.new_block()
  entry.set_terminator(
    TermBranchZero(
      Physical({ index: 0, class: Int }),
      true,
      true,
      then_block.id,
      [],
      else_block.id,
      [],
    ),
  )
  then_block.set_terminator(TermReturn([]))
  else_block.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[72, 133, 192, 15, 133, 5, 0, 0, 0, 233, 1, 0, 0, 0, 195, 195]",
  )
  inspect(object.relocations.length(), content="2")
  inspect(object.fixups.length(), content="2")
  inspect(object.debug_entries.length(), content="3")
}

///|
test "emit AArch64 compare branch terminator" {
  let func = @machv.Function::new("branch_cmp")
  let entry = func.new_block()
  let then_block = func.new_block()
  let else_block = func.new_block()
  entry.set_terminator(
    TermBranchCmp(
      Physical({ index: 0, class: Int }),
      Physical({ index: 1, class: Int }),
      Eq,
      true,
      then_block.id,
      [],
      else_block.id,
      [],
    ),
  )
  then_block.set_terminator(TermReturn([]))
  else_block.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  31,
      #|  0,
      #|  1,
      #|  235,
      #|  64,
      #|  0,
      #|  0,
      #|  84,
      #|  2,
      #|  0,
      #|  0,
      #|  20,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
  inspect(object.relocations.length(), content="2")
  inspect(object.fixups.length(), content="2")
  inspect(object.debug_entries.length(), content="3")
}

///|
test "emit AArch64 integer constants and arithmetic bytes" {
  let func = @machv.Function::new("int_ops")
  let entry = func.new_block()
  let c = func.new_inst(IntConst(42L))
  c.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(c)
  let sub = func.new_inst(IntSub)
  sub.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  sub.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  sub.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(sub)
  let and_ = func.new_inst(IntAnd)
  and_.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  and_.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  and_.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  entry.append(and_)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[64, 5, 128, 210, 2, 0, 1, 203, 67, 0, 1, 138, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 wide integer constants" {
  let func = @machv.Function::new("wide_consts")
  let entry = func.new_block()
  let minus_one = func.new_inst(IntConst(-1L))
  minus_one.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(minus_one)
  let shifted = func.new_inst(IntConst(0x10000L))
  shifted.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(shifted)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[1, 0, 128, 146, 34, 0, 160, 210, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 integer division bytes" {
  let func = @machv.Function::new("int_div")
  let entry = func.new_block()
  let signed_div = func.new_inst(IntDiv(true))
  signed_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  signed_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  signed_div.add_operand(
    @machv.Operand::def(Physical({ index: 2, class: Int })),
  )
  entry.append(signed_div)
  let unsigned_div = func.new_inst(IntDiv(false))
  unsigned_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  unsigned_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  unsigned_div.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  entry.append(unsigned_div)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[2, 12, 193, 154, 67, 8, 193, 154, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 pointer memory bytes" {
  let func = @machv.Function::new("mem")
  let entry = func.new_block()
  let load = func.new_inst(LoadPtr(MemI64, 8))
  load.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  load.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(load)
  let store = func.new_inst(StorePtr(MemI64, 16))
  store.add_operand(@machv.Operand::use_reg(Physical({ index: 0, class: Int })))
  store.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  entry.append(store)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[1, 4, 64, 249, 1, 8, 0, 249, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 scalar floating point bytes" {
  let func = @machv.Function::new("float_ops")
  let entry = func.new_block()
  let add = func.new_inst(FloatAdd)
  add.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float64 })),
  )
  add.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float64 })),
  )
  add.add_operand(@machv.Operand::def(Physical({ index: 0, class: Float64 })))
  entry.append(add)
  let sqrt = func.new_inst(FloatSqrt)
  sqrt.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float32 })),
  )
  sqrt.add_operand(@machv.Operand::def(Physical({ index: 3, class: Float32 })))
  entry.append(sqrt)
  let abs = func.new_inst(FloatAbs)
  abs.add_operand(
    @machv.Operand::use_reg(Physical({ index: 5, class: Float64 })),
  )
  abs.add_operand(@machv.Operand::def(Physical({ index: 6, class: Float64 })))
  entry.append(abs)
  let neg = func.new_inst(FloatNeg)
  neg.add_operand(
    @machv.Operand::use_reg(Physical({ index: 7, class: Float32 })),
  )
  neg.add_operand(@machv.Operand::def(Physical({ index: 8, class: Float32 })))
  entry.append(neg)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  32,
      #|  40,
      #|  98,
      #|  30,
      #|  131,
      #|  192,
      #|  33,
      #|  30,
      #|  166,
      #|  192,
      #|  96,
      #|  30,
      #|  232,
      #|  64,
      #|  33,
      #|  30,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
}

///|
test "emit X64 scalar floating point bytes" {
  let func = @machv.Function::new("x64_float_ops")
  let entry = func.new_block()
  let add = func.new_inst(FloatAdd)
  add.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float64 })),
  )
  add.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float64 })),
  )
  add.add_operand(@machv.Operand::def(Physical({ index: 0, class: Float64 })))
  entry.append(add)
  let sqrt = func.new_inst(FloatSqrt)
  sqrt.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float32 })),
  )
  sqrt.add_operand(@machv.Operand::def(Physical({ index: 3, class: Float32 })))
  entry.append(sqrt)
  let abs = func.new_inst(FloatAbs)
  abs.add_operand(
    @machv.Operand::use_reg(Physical({ index: 5, class: Float64 })),
  )
  abs.add_operand(@machv.Operand::def(Physical({ index: 6, class: Float64 })))
  entry.append(abs)
  let neg = func.new_inst(FloatNeg)
  neg.add_operand(
    @machv.Operand::use_reg(Physical({ index: 7, class: Float32 })),
  )
  neg.add_operand(@machv.Operand::def(Physical({ index: 8, class: Float32 })))
  entry.append(neg)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  242,
      #|  15,
      #|  16,
      #|  193,
      #|  242,
      #|  15,
      #|  88,
      #|  194,
      #|  243,
      #|  15,
      #|  81,
      #|  220,
      #|  242,
      #|  15,
      #|  16,
      #|  245,
      #|  102,
      #|  69,
      #|  15,
      #|  118,
      #|  246,
      #|  102,
      #|  65,
      #|  15,
      #|  115,
      #|  214,
      #|  1,
      #|  102,
      #|  65,
      #|  15,
      #|  84,
      #|  246,
      #|  243,
      #|  68,
      #|  15,
      #|  16,
      #|  199,
      #|  102,
      #|  69,
      #|  15,
      #|  118,
      #|  246,
      #|  102,
      #|  65,
      #|  15,
      #|  114,
      #|  246,
      #|  31,
      #|  69,
      #|  15,
      #|  87,
      #|  198,
      #|  195,
      #|]
    ),
  )
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
    content="[0, 0, 0, 148, 1, 0, 0, 20, 192, 3, 95, 214]",
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

///|
test "stack frame layout computes spill and save regions" {
  let frame = StackFrameLayout::build(
    [20, 25, 26],
    [8, 9],
    5,
    true,
    16,
    outgoing_args_size=16,
  )
  inspect(frame.gpr_save_size, content="32")
  inspect(frame.fpr_save_size, content="16")
  inspect(frame.spill_size, content="48")
  inspect(frame.outgoing_args_size, content="16")
  inspect(frame.frame_size, content="112")
  inspect(frame.total_size, content="128")
  inspect(frame.get_spill_offset(1), content="24")
}

///|
test "stack frame layout supports x64 setup size" {
  let frame = StackFrameLayout::build([], [], 5, true, 8)
  inspect(frame.spill_size, content="48")
  inspect(frame.total_size, content="56")
  inspect(frame.total_size % 16, content="8")
}
