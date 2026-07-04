///|
test "build and verify minimal MilkIR function" {
  let signature = Signature::new([I32, I32], [I32])
  let func = Function::new("add", signature)
  let lhs = func.new_value(I32)
  let rhs = func.new_value(I32)
  let sum = func.new_value(I32)
  let entry = func.new_block([])
  let add = func.new_inst(Iadd, [lhs, rhs], [sum])
  add.add_metadata(Comment("lowered from frontend add"))
  entry.append_inst(add)
  entry.set_terminator(Return([sum]))
  inspect(func.blocks.length(), content="1")
  inspect(entry.instructions.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "builder prints generic SSA function" {
  let builder = IRBuilder::new("add")
  let p0 = builder.add_param(I32)
  let p1 = builder.add_param(I32)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.iadd(p0, p1)
  builder.return_([sum])
  inspect(
    builder.print(),
    content=(
      #|function add(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(builder.get_function().verify(), content="()")
}

///|
test "builder prints pointer operations" {
  let builder = IRBuilder::new("load_store")
  let addr = builder.add_param(Ptr)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let offset0 = builder.iconst_i64(0L)
  let loaded = builder.load_ptr(I32, addr, offset0)
  let one = builder.iconst_i32(1)
  let added = builder.iadd(loaded, one)
  let offset4 = builder.iconst_i64(4L)
  builder.store_ptr(I32, addr, added, offset4)
  builder.return_([added])
  inspect(
    builder.print(),
    content=(
      #|function load_store(v0:ptr) -> i32 {
      #|block0:
      #|    v1:i64 = iconst 0
      #|    v2:i32 = load_ptr.i32 v0, v1
      #|    v3:i32 = iconst 1
      #|    v4:i32 = iadd v2, v3
      #|    v5:i64 = iconst 4
      #|    store_ptr.i32 v0, v4, v5
      #|    return v4
      #|}
      #|
    ),
  )
}

///|
test "builder and CFG support branches and block params" {
  let builder = IRBuilder::new("loop_sum")
  let n = builder.add_param(I32)
  builder.add_result(I32)
  let entry = builder.create_block()
  let loop_header = builder.create_block()
  let loop_body = builder.create_block()
  let exit_block = builder.create_block()
  builder.switch_to_block(entry)
  let init_sum = builder.iconst_i32(0)
  let init_counter = builder.iconst_i32(0)
  builder.jump(loop_header, [init_sum, init_counter])
  let sum_param = builder.add_block_param(loop_header, I32)
  let counter_param = builder.add_block_param(loop_header, I32)
  builder.switch_to_block(loop_header)
  let cmp = builder.icmp_slt(counter_param, n)
  builder.brnz(cmp, loop_body, exit_block)
  builder.switch_to_block(loop_body)
  let new_sum = builder.iadd(sum_param, counter_param)
  let one = builder.iconst_i32(1)
  let new_counter = builder.iadd(counter_param, one)
  builder.jump(loop_header, [new_sum, new_counter])
  builder.switch_to_block(exit_block)
  builder.return_([sum_param])
  let cfg = CFG::build(builder.get_function())
  let entry_successors = cfg.get_successors(0)
  let header_successors = cfg.get_successors(1)
  inspect(entry_successors.length(), content="1")
  inspect(entry_successors[0], content="1")
  inspect(header_successors.length(), content="2")
  inspect(header_successors[0], content="2")
  inspect(header_successors[1], content="3")
  inspect(cfg.dominates(1, 2), content="true")
}

///|
test "verify catches missing terminator" {
  let func = Function::new("bad", Signature::new([], []))
  func.new_block([]) |> ignore
  try func.verify() catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected missing terminator")
  }
}

///|
test "verify catches undefined operands" {
  let func = Function::new("bad_use", Signature::new([], []))
  let entry = func.new_block([])
  let bogus : Value = { id: 99, ty: I32 }
  let result = func.new_value(I32)
  entry.append_inst(func.new_inst(Iadd, [bogus, bogus], [result]))
  entry.set_terminator(Return([result]))
  try func.verify() catch {
    err => inspect(err, content="UndefinedValue(value_id=99)")
  } noraise {
    _ => fail("expected undefined value")
  }
}

///|
test "optimizer folds integer constants" {
  let builder = IRBuilder::new("const_add")
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(20)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O1)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="3")
  inspect(
    func.print(),
    content=(
      #|function const_add() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 10
      #|    v1:i32 = iconst 20
      #|    v2:i32 = iconst 30
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer leaves trap-prone division unfused" {
  let builder = IRBuilder::new("no_fold_div")
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(0)
  let result = builder.get_function().new_value(I32)
  entry.append_inst(builder.get_function().new_inst(Sdiv, [lhs, rhs], [result]))
  builder.return_([result])
  let func = builder.get_function()
  let opt = optimize_with_level(func, O2)
  inspect(opt.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function no_fold_div() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 10
      #|    v1:i32 = iconst 0
      #|    v2:i32 = sdiv v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O0 does not rewrite constants" {
  let builder = IRBuilder::new("o0")
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O0)
  inspect(result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function o0() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O2 removes dead pure instructions after folding" {
  let builder = IRBuilder::new("o2_dce")
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function o2_dce() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 3
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "dead code pass keeps unused loads without alias metadata" {
  let builder = IRBuilder::new("keep_load")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let offset = builder.iconst_i64(0L)
  let _loaded = builder.load_ptr(I32, ptr, offset)
  let result = builder.iconst_i32(7)
  builder.return_([result])
  let func = builder.get_function()
  let opt = eliminate_dead_code(func)
  inspect(opt.changed, content="false")
  inspect(instruction_count(func), content="3")
}
