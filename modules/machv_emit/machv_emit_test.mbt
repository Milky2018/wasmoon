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
test "emit X64 integer division bytes" {
  let func = @machv.Function::new("x64_int_div")
  let entry = func.new_block()
  let signed_div = func.new_inst(IntDiv(true))
  signed_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  signed_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 10, class: Int })),
  )
  signed_div.add_operand(
    @machv.Operand::def(Physical({ index: 0, class: Int })),
  )
  signed_div.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  entry.append(signed_div)
  let unsigned_div = func.new_inst(IntDiv(false))
  unsigned_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  unsigned_div.add_operand(
    @machv.Operand::use_reg(Physical({ index: 11, class: Int })),
  )
  unsigned_div.add_operand(
    @machv.Operand::def(Physical({ index: 0, class: Int })),
  )
  unsigned_div.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  entry.append(unsigned_div)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[72, 153, 73, 247, 250, 49, 210, 73, 247, 243, 195]",
  )
}

///|
test "emit X64 integer multiply-high bytes" {
  let func = @machv.Function::new("x64_int_mul_high")
  let entry = func.new_block()
  let unsigned = func.new_inst(IntMulHigh(false))
  unsigned.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  unsigned.add_operand(
    @machv.Operand::use_reg(Physical({ index: 10, class: Int })),
  )
  unsigned.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  unsigned.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(unsigned)
  let signed = func.new_inst(IntMulHigh(true))
  signed.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  signed.add_operand(
    @machv.Operand::use_reg(Physical({ index: 11, class: Int })),
  )
  signed.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  signed.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(signed)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(object.code, content="[73, 247, 226, 73, 247, 235, 195]")
}

///|
test "emit X64 integer remainder bytes" {
  let func = @machv.Function::new("x64_int_rem")
  let entry = func.new_block()
  let signed_rem = func.new_inst(IntRem(true))
  signed_rem.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  signed_rem.add_operand(
    @machv.Operand::use_reg(Physical({ index: 10, class: Int })),
  )
  signed_rem.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  signed_rem.add_operand(
    @machv.Operand::def(Physical({ index: 0, class: Int })),
  )
  entry.append(signed_rem)
  let unsigned_rem = func.new_inst(IntRem(false))
  unsigned_rem.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  unsigned_rem.add_operand(
    @machv.Operand::use_reg(Physical({ index: 11, class: Int })),
  )
  unsigned_rem.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  unsigned_rem.add_operand(
    @machv.Operand::def(Physical({ index: 0, class: Int })),
  )
  entry.append(unsigned_rem)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[72, 153, 73, 247, 250, 49, 210, 73, 247, 243, 195]",
  )
}

///|
test "emit X64 integer not bytes" {
  let func = @machv.Function::new("x64_int_not")
  let entry = func.new_block()
  let not = func.new_inst(IntNot)
  not.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  not.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(not)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(object.code, content="[77, 137, 211, 73, 247, 211, 195]")
}

///|
test "emit X64 integer compare bytes" {
  let func = @machv.Function::new("x64_int_cmp")
  let entry = func.new_block()
  let cmp = func.new_inst(IntCmp(Lt))
  cmp.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  cmp.add_operand(@machv.Operand::use_reg(Physical({ index: 11, class: Int })))
  cmp.add_operand(@machv.Operand::def(Physical({ index: 9, class: Int })))
  entry.append(cmp)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[77, 57, 218, 65, 15, 156, 193, 69, 15, 182, 201, 195]",
  )
}

///|
test "emit X64 scalar float compare bytes" {
  let func = @machv.Function::new("x64_float_cmp")
  let entry = func.new_block()
  let cmp_eq = func.new_inst(FloatCmp(Eq))
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Float64 })),
  )
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float64 })),
  )
  cmp_eq.add_operand(@machv.Operand::def(Physical({ index: 8, class: Int })))
  cmp_eq.add_operand(
    @machv.Operand::use_def(Physical({ index: 11, class: Int })),
  )
  entry.append(cmp_eq)
  let cmp_lt = func.new_inst(FloatCmp(Lt))
  cmp_lt.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float32 })),
  )
  cmp_lt.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Float32 })),
  )
  cmp_lt.add_operand(@machv.Operand::def(Physical({ index: 9, class: Int })))
  entry.append(cmp_lt)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  102,
      #|  15,
      #|  46,
      #|  193,
      #|  65,
      #|  15,
      #|  148,
      #|  192,
      #|  65,
      #|  15,
      #|  155,
      #|  195,
      #|  69,
      #|  15,
      #|  182,
      #|  192,
      #|  69,
      #|  15,
      #|  182,
      #|  219,
      #|  69,
      #|  33,
      #|  216,
      #|  15,
      #|  46,
      #|  218,
      #|  65,
      #|  15,
      #|  151,
      #|  193,
      #|  69,
      #|  15,
      #|  182,
      #|  201,
      #|  195,
      #|]
    ),
  )
}

///|
test "emit X64 integer shift bytes" {
  let func = @machv.Function::new("x64_int_shift")
  let entry = func.new_block()
  let shl = func.new_inst(IntShl)
  shl.add_operand(@machv.Operand::use_reg(Physical({ index: 8, class: Int })))
  shl.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  shl.add_operand(@machv.Operand::def(Physical({ index: 10, class: Int })))
  entry.append(shl)
  let ushr = func.new_inst(IntShr(false))
  ushr.add_operand(@machv.Operand::use_reg(Physical({ index: 8, class: Int })))
  ushr.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  ushr.add_operand(@machv.Operand::def(Physical({ index: 8, class: Int })))
  entry.append(ushr)
  let sshr = func.new_inst(IntShr(true))
  sshr.add_operand(@machv.Operand::use_reg(Physical({ index: 9, class: Int })))
  sshr.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  sshr.add_operand(@machv.Operand::def(Physical({ index: 9, class: Int })))
  entry.append(sshr)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[77, 137, 194, 73, 211, 226, 73, 211, 232, 73, 211, 249, 195]",
  )
}

///|
test "emit X64 integer rotate bytes" {
  let func = @machv.Function::new("x64_int_rotate")
  let entry = func.new_block()
  let rotl = func.new_inst(IntRotl)
  rotl.add_operand(@machv.Operand::use_reg(Physical({ index: 8, class: Int })))
  rotl.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  rotl.add_operand(@machv.Operand::def(Physical({ index: 10, class: Int })))
  entry.append(rotl)
  let rotr = func.new_inst(IntRotr)
  rotr.add_operand(@machv.Operand::use_reg(Physical({ index: 9, class: Int })))
  rotr.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  rotr.add_operand(@machv.Operand::def(Physical({ index: 9, class: Int })))
  entry.append(rotr)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[77, 137, 194, 73, 211, 194, 73, 211, 201, 195]",
  )
}

///|
test "emit X64 bitcast bytes" {
  let func = @machv.Function::new("x64_bitcast")
  let entry = func.new_block()
  let int_to_float = func.new_inst(Bitcast)
  int_to_float.add_operand(
    @machv.Operand::use_reg(Physical({ index: 10, class: Int })),
  )
  int_to_float.add_operand(
    @machv.Operand::def(Physical({ index: 15, class: Float64 })),
  )
  entry.append(int_to_float)
  let float_to_int = func.new_inst(Bitcast)
  float_to_int.add_operand(
    @machv.Operand::use_reg(Physical({ index: 15, class: Float64 })),
  )
  float_to_int.add_operand(
    @machv.Operand::def(Physical({ index: 10, class: Int })),
  )
  entry.append(float_to_int)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[102, 77, 15, 110, 250, 102, 77, 15, 126, 250, 195]",
  )
}

///|
test "emit X64 sign-extension bytes" {
  let func = @machv.Function::new("x64_sext")
  let entry = func.new_block()
  let s8 = func.new_inst(Sextend8)
  s8.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  s8.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(s8)
  let s16 = func.new_inst(Sextend16)
  s16.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  s16.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(s16)
  let s32 = func.new_inst(Sextend32)
  s32.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  s32.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(s32)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[77, 15, 190, 218, 77, 15, 191, 218, 77, 99, 218, 195]",
  )
}

///|
test "emit X64 generic integer width conversion bytes" {
  let func = @machv.Function::new("x64_width")
  let entry = func.new_block()
  let sext = func.new_inst(Sextend)
  sext.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  sext.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(sext)
  let uext = func.new_inst(Uextend)
  uext.add_operand(@machv.Operand::use_reg(Physical({ index: 10, class: Int })))
  uext.add_operand(@machv.Operand::def(Physical({ index: 11, class: Int })))
  entry.append(uext)
  let reduce = func.new_inst(Ireduce)
  reduce.add_operand(
    @machv.Operand::use_reg(Physical({ index: 8, class: Int })),
  )
  reduce.add_operand(@machv.Operand::def(Physical({ index: 9, class: Int })))
  entry.append(reduce)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[77, 99, 218, 69, 137, 211, 69, 137, 193, 195]",
  )
}

///|
test "emit X64 integer select bytes" {
  let func = @machv.Function::new("x64_select")
  let entry = func.new_block()
  let select = func.new_inst(Select)
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Int })),
  )
  select.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(select)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[133, 201, 72, 137, 216, 72, 15, 69, 194, 195]",
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
test "emit AArch64 integer multiply-high bytes" {
  let func = @machv.Function::new("int_mul_high")
  let entry = func.new_block()
  let unsigned = func.new_inst(IntMulHigh(false))
  unsigned.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  unsigned.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  unsigned.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(unsigned)
  let signed = func.new_inst(IntMulHigh(true))
  signed.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Int })),
  )
  signed.add_operand(
    @machv.Operand::use_reg(Physical({ index: 5, class: Int })),
  )
  signed.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  entry.append(signed)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[32, 124, 194, 155, 131, 124, 69, 155, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 integer not bytes" {
  let func = @machv.Function::new("int_not")
  let entry = func.new_block()
  let not = func.new_inst(IntNot)
  not.add_operand(@machv.Operand::use_reg(Physical({ index: 4, class: Int })))
  not.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  entry.append(not)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(object.code, content="[227, 3, 36, 170, 192, 3, 95, 214]")
}

///|
test "emit AArch64 integer compare bytes" {
  let func = @machv.Function::new("int_cmp")
  let entry = func.new_block()
  let cmp_eq = func.new_inst(IntCmp(Eq))
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Int })),
  )
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  cmp_eq.add_operand(@machv.Operand::def(Physical({ index: 5, class: Int })))
  entry.append(cmp_eq)
  let cmp_ult = func.new_inst(IntCmp(Ult))
  cmp_ult.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  cmp_ult.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Int })),
  )
  cmp_ult.add_operand(@machv.Operand::def(Physical({ index: 6, class: Int })))
  entry.append(cmp_ult)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  31,
      #|  0,
      #|  1,
      #|  235,
      #|  229,
      #|  23,
      #|  159,
      #|  154,
      #|  95,
      #|  0,
      #|  3,
      #|  235,
      #|  230,
      #|  39,
      #|  159,
      #|  154,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
}

///|
test "emit AArch64 scalar float compare bytes" {
  let func = @machv.Function::new("float_cmp")
  let entry = func.new_block()
  let cmp_eq = func.new_inst(FloatCmp(Eq))
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 0, class: Float64 })),
  )
  cmp_eq.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float64 })),
  )
  cmp_eq.add_operand(@machv.Operand::def(Physical({ index: 5, class: Int })))
  entry.append(cmp_eq)
  let cmp_ne = func.new_inst(FloatCmp(Ne))
  cmp_ne.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float32 })),
  )
  cmp_ne.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Float32 })),
  )
  cmp_ne.add_operand(@machv.Operand::def(Physical({ index: 6, class: Int })))
  entry.append(cmp_ne)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  0,
      #|  32,
      #|  97,
      #|  30,
      #|  229,
      #|  23,
      #|  159,
      #|  154,
      #|  64,
      #|  32,
      #|  35,
      #|  30,
      #|  230,
      #|  7,
      #|  159,
      #|  154,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
}

///|
test "emit AArch64 integer bitcount bytes" {
  let func = @machv.Function::new("int_bitcount")
  let entry = func.new_block()
  let clz = func.new_inst(IntClz)
  clz.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  clz.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(clz)
  let ctz = func.new_inst(IntCtz)
  ctz.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  ctz.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  entry.append(ctz)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[32, 16, 192, 218, 67, 0, 192, 218, 99, 16, 192, 218, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 integer shift bytes" {
  let func = @machv.Function::new("int_shift")
  let entry = func.new_block()
  let shl = func.new_inst(IntShl)
  shl.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  shl.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  shl.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(shl)
  let ushr = func.new_inst(IntShr(false))
  ushr.add_operand(@machv.Operand::use_reg(Physical({ index: 4, class: Int })))
  ushr.add_operand(@machv.Operand::use_reg(Physical({ index: 5, class: Int })))
  ushr.add_operand(@machv.Operand::def(Physical({ index: 3, class: Int })))
  entry.append(ushr)
  let sshr = func.new_inst(IntShr(true))
  sshr.add_operand(@machv.Operand::use_reg(Physical({ index: 7, class: Int })))
  sshr.add_operand(@machv.Operand::use_reg(Physical({ index: 8, class: Int })))
  sshr.add_operand(@machv.Operand::def(Physical({ index: 6, class: Int })))
  entry.append(sshr)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  32,
      #|  32,
      #|  194,
      #|  154,
      #|  131,
      #|  36,
      #|  197,
      #|  154,
      #|  230,
      #|  40,
      #|  200,
      #|  154,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
}

///|
test "emit AArch64 integer rotate-right bytes" {
  let func = @machv.Function::new("int_rotr")
  let entry = func.new_block()
  let rotr = func.new_inst(IntRotr)
  rotr.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  rotr.add_operand(@machv.Operand::use_reg(Physical({ index: 2, class: Int })))
  rotr.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(rotr)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(object.code, content="[32, 44, 194, 154, 192, 3, 95, 214]")
}

///|
test "emit AArch64 bitcast bytes" {
  let func = @machv.Function::new("bitcast")
  let entry = func.new_block()
  let int_to_float = func.new_inst(Bitcast)
  int_to_float.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  int_to_float.add_operand(
    @machv.Operand::def(Physical({ index: 1, class: Float64 })),
  )
  entry.append(int_to_float)
  let float_to_int = func.new_inst(Bitcast)
  float_to_int.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float64 })),
  )
  float_to_int.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Int })),
  )
  entry.append(float_to_int)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[65, 0, 103, 158, 131, 0, 102, 158, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 sign-extension bytes" {
  let func = @machv.Function::new("sext")
  let entry = func.new_block()
  let s8 = func.new_inst(Sextend8)
  s8.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  s8.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(s8)
  let s16 = func.new_inst(Sextend16)
  s16.add_operand(@machv.Operand::use_reg(Physical({ index: 3, class: Int })))
  s16.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(s16)
  let s32 = func.new_inst(Sextend32)
  s32.add_operand(@machv.Operand::use_reg(Physical({ index: 5, class: Int })))
  s32.add_operand(@machv.Operand::def(Physical({ index: 4, class: Int })))
  entry.append(s32)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[32, 28, 64, 147, 98, 60, 64, 147, 164, 124, 64, 147, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 generic integer width conversion bytes" {
  let func = @machv.Function::new("width")
  let entry = func.new_block()
  let sext = func.new_inst(Sextend)
  sext.add_operand(@machv.Operand::use_reg(Physical({ index: 1, class: Int })))
  sext.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(sext)
  let uext = func.new_inst(Uextend)
  uext.add_operand(@machv.Operand::use_reg(Physical({ index: 3, class: Int })))
  uext.add_operand(@machv.Operand::def(Physical({ index: 2, class: Int })))
  entry.append(uext)
  let reduce = func.new_inst(Ireduce)
  reduce.add_operand(
    @machv.Operand::use_reg(Physical({ index: 5, class: Int })),
  )
  reduce.add_operand(@machv.Operand::def(Physical({ index: 4, class: Int })))
  entry.append(reduce)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[32, 124, 64, 147, 226, 3, 3, 42, 228, 3, 5, 42, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 integer select bytes" {
  let func = @machv.Function::new("select")
  let entry = func.new_block()
  let select = func.new_inst(Select)
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Int })),
  )
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  select.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Int })),
  )
  select.add_operand(@machv.Operand::def(Physical({ index: 0, class: Int })))
  entry.append(select)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[63, 0, 0, 113, 64, 16, 131, 154, 192, 3, 95, 214]",
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
test "emit AArch64 float width conversion bytes" {
  let func = @machv.Function::new("float_width")
  let entry = func.new_block()
  let promote = func.new_inst(Fpromote)
  promote.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float32 })),
  )
  promote.add_operand(
    @machv.Operand::def(Physical({ index: 0, class: Float64 })),
  )
  entry.append(promote)
  let demote = func.new_inst(Fdemote)
  demote.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Float64 })),
  )
  demote.add_operand(
    @machv.Operand::def(Physical({ index: 2, class: Float32 })),
  )
  entry.append(demote)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content="[32, 192, 34, 30, 98, 64, 98, 30, 192, 3, 95, 214]",
  )
}

///|
test "emit AArch64 scalar float rounding bytes" {
  let func = @machv.Function::new("float_round")
  let entry = func.new_block()
  let ceil = func.new_inst(FloatCeil)
  ceil.add_operand(
    @machv.Operand::use_reg(Physical({ index: 1, class: Float32 })),
  )
  ceil.add_operand(@machv.Operand::def(Physical({ index: 0, class: Float32 })))
  entry.append(ceil)
  let floor = func.new_inst(FloatFloor)
  floor.add_operand(
    @machv.Operand::use_reg(Physical({ index: 3, class: Float64 })),
  )
  floor.add_operand(@machv.Operand::def(Physical({ index: 2, class: Float64 })))
  entry.append(floor)
  let trunc = func.new_inst(FloatTrunc)
  trunc.add_operand(
    @machv.Operand::use_reg(Physical({ index: 5, class: Float32 })),
  )
  trunc.add_operand(@machv.Operand::def(Physical({ index: 4, class: Float32 })))
  entry.append(trunc)
  let nearest = func.new_inst(FloatNearest)
  nearest.add_operand(
    @machv.Operand::use_reg(Physical({ index: 7, class: Float64 })),
  )
  nearest.add_operand(
    @machv.Operand::def(Physical({ index: 6, class: Float64 })),
  )
  entry.append(nearest)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  32,
      #|  192,
      #|  36,
      #|  30,
      #|  98,
      #|  64,
      #|  101,
      #|  30,
      #|  164,
      #|  192,
      #|  37,
      #|  30,
      #|  230,
      #|  64,
      #|  100,
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
test "emit X64 float width conversion bytes" {
  let func = @machv.Function::new("x64_float_width")
  let entry = func.new_block()
  let promote = func.new_inst(Fpromote)
  promote.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float32 })),
  )
  promote.add_operand(
    @machv.Operand::def(Physical({ index: 1, class: Float64 })),
  )
  entry.append(promote)
  let demote = func.new_inst(Fdemote)
  demote.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float64 })),
  )
  demote.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Float32 })),
  )
  entry.append(demote)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content="[243, 15, 90, 202, 242, 15, 90, 220, 195]",
  )
}

///|
test "emit X64 scalar float rounding bytes" {
  let func = @machv.Function::new("x64_float_round")
  let entry = func.new_block()
  let ceil = func.new_inst(FloatCeil)
  ceil.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Float32 })),
  )
  ceil.add_operand(@machv.Operand::def(Physical({ index: 1, class: Float32 })))
  entry.append(ceil)
  let floor = func.new_inst(FloatFloor)
  floor.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float64 })),
  )
  floor.add_operand(@machv.Operand::def(Physical({ index: 3, class: Float64 })))
  entry.append(floor)
  let trunc = func.new_inst(FloatTrunc)
  trunc.add_operand(
    @machv.Operand::use_reg(Physical({ index: 6, class: Float32 })),
  )
  trunc.add_operand(@machv.Operand::def(Physical({ index: 5, class: Float32 })))
  entry.append(trunc)
  let nearest = func.new_inst(FloatNearest)
  nearest.add_operand(
    @machv.Operand::use_reg(Physical({ index: 8, class: Float64 })),
  )
  nearest.add_operand(
    @machv.Operand::def(Physical({ index: 7, class: Float64 })),
  )
  entry.append(nearest)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  102,
      #|  15,
      #|  58,
      #|  10,
      #|  202,
      #|  2,
      #|  102,
      #|  15,
      #|  58,
      #|  11,
      #|  220,
      #|  1,
      #|  102,
      #|  15,
      #|  58,
      #|  10,
      #|  238,
      #|  3,
      #|  102,
      #|  65,
      #|  15,
      #|  58,
      #|  11,
      #|  248,
      #|  0,
      #|  195,
      #|]
    ),
  )
}

///|
test "emit AArch64 stack spill load store bytes" {
  let func = @machv.Function::new("aarch64_stack_spill")
  let entry = func.new_block()
  let slot0 = func.new_stack_slot(8, 8)
  let slot1 = func.new_stack_slot(8, 8)
  func.set_num_spill_slots(2)
  let load_int = func.new_inst(Load(slot0))
  load_int.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(load_int)
  let store_int = func.new_inst(Store(slot1))
  store_int.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  entry.append(store_int)
  let load_float = func.new_inst(Load(slot1))
  load_float.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Float64 })),
  )
  entry.append(load_float)
  let store_float = func.new_inst(Store(slot0))
  store_float.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float32 })),
  )
  entry.append(store_float)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function(func)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  225,
      #|  3,
      #|  64,
      #|  249,
      #|  226,
      #|  7,
      #|  0,
      #|  249,
      #|  227,
      #|  7,
      #|  64,
      #|  253,
      #|  228,
      #|  3,
      #|  0,
      #|  253,
      #|  192,
      #|  3,
      #|  95,
      #|  214,
      #|]
    ),
  )
}

///|
test "emit X64 stack spill load store bytes" {
  let func = @machv.Function::new("x64_stack_spill")
  let entry = func.new_block()
  let slot0 = func.new_stack_slot(8, 8)
  let slot1 = func.new_stack_slot(8, 8)
  func.set_num_spill_slots(2)
  let load_int = func.new_inst(Load(slot0))
  load_int.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(load_int)
  let store_int = func.new_inst(Store(slot1))
  store_int.add_operand(
    @machv.Operand::use_reg(Physical({ index: 2, class: Int })),
  )
  entry.append(store_int)
  let load_float = func.new_inst(Load(slot1))
  load_float.add_operand(
    @machv.Operand::def(Physical({ index: 3, class: Float64 })),
  )
  entry.append(load_float)
  let store_float = func.new_inst(Store(slot0))
  store_float.add_operand(
    @machv.Operand::use_reg(Physical({ index: 4, class: Float32 })),
  )
  entry.append(store_float)
  entry.set_terminator(TermReturn([]))
  let object = try! emit_function_for_target(func, X64)
  debug_inspect(
    object.code,
    content=(
      #|[
      #|  72,
      #|  139,
      #|  140,
      #|  36,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
      #|  72,
      #|  137,
      #|  148,
      #|  36,
      #|  8,
      #|  0,
      #|  0,
      #|  0,
      #|  242,
      #|  15,
      #|  16,
      #|  156,
      #|  36,
      #|  8,
      #|  0,
      #|  0,
      #|  0,
      #|  242,
      #|  15,
      #|  17,
      #|  164,
      #|  36,
      #|  0,
      #|  0,
      #|  0,
      #|  0,
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
