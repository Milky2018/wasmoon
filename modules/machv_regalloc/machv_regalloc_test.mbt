///|
test "project and allocate MachV function" {
  let func = @machv.Function::new("copy")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(@machv.Operand::def(Virtual(v0)))
  mov.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(mov)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(allocation.spill_count, content="0")
  inspect(allocation.assignments.length(), content="2")
}

///|
test "apply materializes MachV spill slots" {
  let func = @machv.Function::new("spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let inst = func.new_inst(Target("pair"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::def(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let result = allocate_and_apply_linear_scan(func, [p0])
  inspect(result.allocation.spill_count, content="1")
  inspect(result.spill_slots.length(), content="1")
  inspect(func.stack_slots.length(), content="1")
}

///|
test "apply materializes aligned vector spill slots" {
  let func = @machv.Function::new("vector_spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Vector)
  let v1 = func.new_vreg(Vector)
  let inst = func.new_inst(Target("vector_pair"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::def(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Vector }
  let result = allocate_and_apply_linear_scan(func, [p0])
  inspect(result.allocation.spill_count, content="1")
  inspect(result.spill_slots[0].size, content="16")
  inspect(result.spill_slots[0].align, content="16")
}

///|
test "apply rewrites allocated virtual operands to physical registers" {
  let func = @machv.Function::new("rewrite")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let inst = func.new_inst(Move)
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  allocate_and_apply_linear_scan(func, [p0, p1]) |> ignore
  inspect(entry.instructions[0].operands[0].reg is Physical(_), content="true")
  inspect(entry.instructions[0].operands[1].reg is Physical(_), content="true")
}

///|
test "apply preserves MachV float width classes when rewriting operands" {
  let func = @machv.Function::new("float_width")
  let entry = func.new_block()
  let f32_value = func.new_vreg(Float32)
  let f64_value = func.new_vreg(Float64)
  let inst = func.new_inst(Fpromote)
  inst.add_operand(@machv.Operand::use_reg(Virtual(f32_value)))
  inst.add_operand(@machv.Operand::def(Virtual(f64_value)))
  entry.append(inst)
  let f0_32 : @machv.PReg = { index: 0, class: Float32 }
  let f0_64 : @machv.PReg = { index: 0, class: Float64 }
  let f1_32 : @machv.PReg = { index: 1, class: Float32 }
  let f1_64 : @machv.PReg = { index: 1, class: Float64 }
  allocate_and_apply_linear_scan(func, [f0_32, f0_64, f1_32, f1_64]) |> ignore
  inspect(
    entry.instructions[0].operands[0].reg is Physical({ class: Float32, .. }),
    content="true",
  )
  inspect(
    entry.instructions[0].operands[1].reg is Physical({ class: Float64, .. }),
    content="true",
  )
}

///|
test "projected MachV constraints guide fixed register allocation" {
  let func = @machv.Function::new("fixed")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let inst = func.new_inst(Target("fixed_def"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  inst.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  entry.append(inst)
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    Some(Reg({ id: 1, class: Int })),
    content="true",
  )
}

///|
test "apply materializes call fixed constraints as moves" {
  let func = @machv.Function::new("call_fixed_moves")
  let entry = func.new_block()
  let value = func.new_vreg(Int)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let def_value = func.new_inst(Target("def_value"))
  def_value.add_operand(@machv.Operand::def(Virtual(value)))
  def_value.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  entry.append(def_value)
  let call0 = func.new_inst(Call("first"))
  call0.add_operand(@machv.Operand::use_reg(Virtual(value)))
  call0.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  entry.append(call0)
  let call1 = func.new_inst(Call("second"))
  call1.add_operand(@machv.Operand::use_reg(Virtual(value)))
  call1.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  entry.append(call1)
  allocate_and_apply_linear_scan(func, [p0, p1]) |> ignore
  inspect(entry.instructions.length(), content="4")
  inspect(entry.instructions[1].operands[0].reg, content="x0")
  inspect(entry.instructions[2].opcode is Move, content="true")
  debug_inspect(
    entry.instructions[2].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 1, class: Int }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 0, class: Int }), role: Use, tie_id: -1 },
      #|]
    ),
  )
  inspect(entry.instructions[3].operands[0].reg, content="x1")
}

///|
test "apply materializes overlapping call fixed constraints in reverse order" {
  let func = @machv.Function::new("call_fixed_overlap")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let p2 : @machv.PReg = { index: 2, class: Int }
  let p3 : @machv.PReg = { index: 3, class: Int }
  let defs = func.new_inst(Target("defs"))
  defs.add_operand(@machv.Operand::def(Virtual(v0)))
  defs.add_operand(@machv.Operand::def(Virtual(v1)))
  defs.add_operand(@machv.Operand::def(Virtual(v2)))
  defs.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  defs.add_constraint({ operand_index: 1, allowed_regs: [p1] })
  defs.add_constraint({ operand_index: 2, allowed_regs: [p2] })
  entry.append(defs)
  let call = func.new_inst(Call("callee"))
  call.add_operand(@machv.Operand::use_reg(Virtual(v0)))
  call.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  call.add_operand(@machv.Operand::use_reg(Virtual(v2)))
  call.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  call.add_constraint({ operand_index: 1, allowed_regs: [p2] })
  call.add_constraint({ operand_index: 2, allowed_regs: [p3] })
  entry.append(call)
  allocate_and_apply_linear_scan(func, [p0, p1, p2, p3]) |> ignore
  inspect(entry.instructions.length(), content="5")
  inspect(entry.instructions[1].opcode is Move, content="true")
  inspect(entry.instructions[2].opcode is Move, content="true")
  inspect(entry.instructions[3].opcode is Move, content="true")
  debug_inspect(
    entry.instructions[1].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 3, class: Int }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 2, class: Int }), role: Use, tie_id: -1 },
      #|]
    ),
  )
  debug_inspect(
    entry.instructions[2].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 2, class: Int }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 1, class: Int }), role: Use, tie_id: -1 },
      #|]
    ),
  )
  debug_inspect(
    entry.instructions[3].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 1, class: Int }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 0, class: Int }), role: Use, tie_id: -1 },
      #|]
    ),
  )
}

///|
test "apply keeps fixed call inputs out of cycle scratch registers" {
  let func = @machv.Function::new("call_fixed_protected_scratch")
  let entry = func.new_block()
  let vmctx = func.new_vreg(Int)
  let delta = func.new_vreg(Int)
  let memidx = func.new_vreg(Int)
  let max_pages = func.new_vreg(Int)
  let result = func.new_vreg(Int)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let p2 : @machv.PReg = { index: 2, class: Int }
  let p3 : @machv.PReg = { index: 3, class: Int }
  let p4 : @machv.PReg = { index: 4, class: Int }
  let defs = func.new_inst(Target("defs"))
  defs.add_operand(@machv.Operand::def(Virtual(vmctx)))
  defs.add_operand(@machv.Operand::def(Virtual(delta)))
  defs.add_operand(@machv.Operand::def(Virtual(memidx)))
  defs.add_operand(@machv.Operand::def(Virtual(max_pages)))
  defs.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  defs.add_constraint({ operand_index: 1, allowed_regs: [p1] })
  defs.add_constraint({ operand_index: 2, allowed_regs: [p2] })
  defs.add_constraint({ operand_index: 3, allowed_regs: [p3] })
  entry.append(defs)
  let call = func.new_inst(Call("wasm.runtime.memory_grow"))
  call.add_operand(@machv.Operand::use_reg(Virtual(vmctx)))
  call.add_operand(@machv.Operand::use_reg(Virtual(memidx)))
  call.add_operand(@machv.Operand::use_reg(Virtual(delta)))
  call.add_operand(@machv.Operand::use_reg(Virtual(max_pages)))
  call.add_operand(@machv.Operand::def(Virtual(result)))
  call.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  call.add_constraint({ operand_index: 1, allowed_regs: [p1] })
  call.add_constraint({ operand_index: 2, allowed_regs: [p2] })
  call.add_constraint({ operand_index: 3, allowed_regs: [p3] })
  call.add_constraint({ operand_index: 4, allowed_regs: [p0] })
  entry.append(call)
  allocate_and_apply_linear_scan(func, [p0, p1, p2, p3, p4]) |> ignore
  let mut call_index = -1
  for i, inst in entry.instructions {
    if inst.opcode is Call(_) {
      call_index = i
    }
  }
  inspect(call_index > 0, content="true")
  for i in 1..<call_index {
    let inst = entry.instructions[i]
    if inst.opcode is Move {
      for operand in inst.operands {
        inspect(operand.reg != Physical(p0), content="true")
      }
    }
  }
  inspect(entry.instructions[call_index].operands[0].reg, content="x0")
}

///|
test "projected MachV ties co-locate use-def operands" {
  let func = @machv.Function::new("tied")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_inst = func.new_inst(Target("def"))
  def_inst.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_inst)
  let tied_inst = func.new_inst(Target("tied"))
  tied_inst.add_operand(@machv.Operand::use_reg(Virtual(v0)).with_tie(0))
  tied_inst.add_operand(@machv.Operand::def(Virtual(v1)).with_tie(0))
  entry.append(tied_inst)
  let use_inst = func.new_inst(Target("use"))
  use_inst.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(use_inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
  allocate_and_apply_linear_scan(func, [p0, p1]) |> ignore
  inspect(entry.instructions[1].operands[0].reg, content="x0")
  inspect(entry.instructions[1].operands[1].reg, content="x0")
}

///|
test "allocate_function_linear_scan accepts fixed registers outside the allocatable pool" {
  let func = @machv.Function::new("fixed_outside_pool")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let inst = func.new_inst(Target("fixed_def"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_constraint({
    operand_index: 0,
    allowed_regs: [{ index: 1, class: Int }],
  })
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let allocation = allocate_function_linear_scan(func, [p0])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    Some(Reg({ id: 1, class: Int })),
    content="true",
  )
}

///|
test "allocate_function_linear_scan avoids projected clobbered registers" {
  let func = @machv.Function::new("clobber")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let def_inst = func.new_inst(Target("def"))
  def_inst.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let call_inst = func.new_inst(Target("call"))
  call_inst.add_clobber(p0)
  entry.append(call_inst)
  let use_inst = func.new_inst(Target("use"))
  use_inst.add_operand(@machv.Operand::use_reg(Virtual(v0)))
  entry.append(use_inst)
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    Some(Reg({ id: 1, class: Int })),
    content="true",
  )
}

///|
test "projected MachV terminator return keeps result live" {
  let func = @machv.Function::new("return_live")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_v0)
  let def_v1 = func.new_inst(Target("def_v1"))
  def_v1.add_operand(@machv.Operand::def(Virtual(v1)))
  def_v1.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(def_v1)
  entry.set_terminator(TermReturn([Virtual(v0)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) !=
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
}

///|
test "projected MachV successors extend live ranges across empty blocks" {
  let func = @machv.Function::new("successor_live")
  let entry = func.new_block()
  let middle = func.new_block()
  let exit = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_v0)
  entry.set_terminator(TermJump(middle.id, []))
  let def_v1 = func.new_inst(Target("def_v1"))
  def_v1.add_operand(@machv.Operand::def(Virtual(v1)))
  def_v1.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  middle.append(def_v1)
  middle.set_terminator(TermJump(exit.id, []))
  exit.set_terminator(TermReturn([Virtual(v0)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function_linear_scan(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) !=
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
}

///|
test "apply rewrites terminator virtual registers" {
  let func = @machv.Function::new("term_rewrite")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_v0)
  entry.set_terminator(TermReturn([Virtual(v0)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  allocate_and_apply_linear_scan(func, [p0]) |> ignore
  debug_inspect(
    entry.terminator,
    content="Some(TermReturn([Physical({ index: 0, class: Int })]))",
  )
}

///|
test "apply materializes jump edge args for block params" {
  let func = @machv.Function::new("edge_jump")
  let entry = func.new_block()
  let target = func.new_block()
  let source = func.new_vreg(Int)
  let param = func.new_vreg(Int)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  target.add_param(param)
  let def_source = func.new_inst(Target("def_source"))
  def_source.add_operand(@machv.Operand::def(Virtual(source)))
  def_source.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  entry.append(def_source)
  entry.set_terminator(TermJump(target.id, [Virtual(source)]))
  let use_param = func.new_inst(Target("use_param"))
  use_param.add_operand(@machv.Operand::use_reg(Virtual(param)))
  use_param.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  target.append(use_param)
  target.set_terminator(TermReturn([]))
  allocate_and_apply_linear_scan(func, [p0, p1]) |> ignore
  inspect(entry.terminator == Some(TermJump(target.id, [])), content="true")
  inspect(
    entry.instructions[entry.instructions.length() - 1].opcode is Move,
    content="true",
  )
  debug_inspect(
    entry.instructions[entry.instructions.length() - 1].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 1, class: Int }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 0, class: Int }), role: Use, tie_id: -1 },
      #|]
    ),
  )
}

///|
test "apply preserves float32 class in edge transfers" {
  let func = @machv.Function::new("edge_jump_f32")
  let entry = func.new_block()
  let target = func.new_block()
  let source = func.new_vreg(Float32)
  let param = func.new_vreg(Float32)
  let f0 : @machv.PReg = { index: 0, class: Float32 }
  let f1 : @machv.PReg = { index: 1, class: Float32 }
  target.add_param(param)
  let def_source = func.new_inst(Target("def_source"))
  def_source.add_operand(@machv.Operand::def(Virtual(source)))
  def_source.add_constraint({ operand_index: 0, allowed_regs: [f0] })
  entry.append(def_source)
  entry.set_terminator(TermJump(target.id, [Virtual(source)]))
  let use_param = func.new_inst(Target("use_param"))
  use_param.add_operand(@machv.Operand::use_reg(Virtual(param)))
  use_param.add_constraint({ operand_index: 0, allowed_regs: [f1] })
  target.append(use_param)
  target.set_terminator(TermReturn([]))
  allocate_and_apply_linear_scan(func, [f0, f1]) |> ignore
  debug_inspect(
    entry.instructions[entry.instructions.length() - 1].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 1, class: Float32 }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 0, class: Float32 }), role: Use, tie_id: -1 },
      #|]
    ),
  )
}

///|
test "apply preserves vector class in edge transfers" {
  let func = @machv.Function::new("edge_jump_vector")
  let entry = func.new_block()
  let target = func.new_block()
  let source = func.new_vreg(Vector)
  let param = func.new_vreg(Vector)
  let v0 : @machv.PReg = { index: 0, class: Vector }
  let v1 : @machv.PReg = { index: 1, class: Vector }
  target.add_param(param)
  let def_source = func.new_inst(Target("def_source"))
  def_source.add_operand(@machv.Operand::def(Virtual(source)))
  def_source.add_constraint({ operand_index: 0, allowed_regs: [v0] })
  entry.append(def_source)
  entry.set_terminator(TermJump(target.id, [Virtual(source)]))
  let use_param = func.new_inst(Target("use_param"))
  use_param.add_operand(@machv.Operand::use_reg(Virtual(param)))
  use_param.add_constraint({ operand_index: 0, allowed_regs: [v1] })
  target.append(use_param)
  target.set_terminator(TermReturn([]))
  allocate_and_apply_linear_scan(func, [v0, v1]) |> ignore
  debug_inspect(
    entry.instructions[entry.instructions.length() - 1].operands,
    content=(
      #|[
      #|  { reg: Physical({ index: 1, class: Vector }), role: Def, tie_id: -1 },
      #|  { reg: Physical({ index: 0, class: Vector }), role: Use, tie_id: -1 },
      #|]
    ),
  )
}

///|
test "apply splits conditional branch edge args through copy blocks" {
  let func = @machv.Function::new("edge_branch")
  let entry = func.new_block()
  let then_block = func.new_block()
  let else_block = func.new_block()
  let source = func.new_vreg(Int)
  let param = func.new_vreg(Int)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let cond : @machv.Reg = Physical({ index: 2, class: Int })
  then_block.add_param(param)
  let def_source = func.new_inst(Target("def_source"))
  def_source.add_operand(@machv.Operand::def(Virtual(source)))
  def_source.add_constraint({ operand_index: 0, allowed_regs: [p0] })
  entry.append(def_source)
  entry.set_terminator(
    TermBranchZero(
      cond,
      true,
      true,
      then_block.id,
      [Virtual(source)],
      else_block.id,
      [],
    ),
  )
  let use_param = func.new_inst(Target("use_param"))
  use_param.add_operand(@machv.Operand::use_reg(Virtual(param)))
  use_param.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  then_block.append(use_param)
  then_block.set_terminator(TermReturn([]))
  else_block.set_terminator(TermReturn([]))
  allocate_and_apply_linear_scan(func, [p0, p1]) |> ignore
  inspect(func.blocks.length(), content="4")
  guard entry.terminator
    is Some(
      TermBranchZero(
        _,
        _,
        _,
        rewritten_then,
        true_args,
        rewritten_else,
        false_args
      )
    ) else {
    inspect(false, content="true")
    return
  }
  inspect(rewritten_then != then_block.id, content="true")
  inspect(rewritten_else == else_block.id, content="true")
  inspect(true_args.length(), content="0")
  inspect(false_args.length(), content="0")
  let edge_block = func.blocks[3]
  inspect(edge_block.instructions.length(), content="1")
  inspect(edge_block.instructions[0].opcode is Move, content="true")
  inspect(
    edge_block.terminator == Some(TermJump(then_block.id, [])),
    content="true",
  )
}

///|
test "apply reloads spilled terminator operands before terminator" {
  let func = @machv.Function::new("term_reload")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  def_v0.add_operand(@machv.Operand::use_reg(Virtual(v0)))
  entry.append(def_v0)
  let def_v1 = func.new_inst(Target("def_v1"))
  def_v1.add_operand(@machv.Operand::def(Virtual(v1)))
  def_v1.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(def_v1)
  let def_v2 = func.new_inst(Target("def_v2"))
  def_v2.add_operand(@machv.Operand::def(Virtual(v2)))
  def_v2.add_operand(@machv.Operand::use_reg(Virtual(v2)))
  entry.append(def_v2)
  entry.set_terminator(TermReturn([Virtual(v0), Virtual(v1), Virtual(v2)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = allocate_and_apply_linear_scan(func, [p0, p1])
  inspect(result.allocation.spill_count > 0, content="true")
  inspect(
    entry.instructions[entry.instructions.length() - 1].opcode is Load(_),
    content="true",
  )
  let mut virtual_terms = 0
  if entry.terminator is Some(TermReturn(regs)) {
    for reg in regs {
      if reg is Virtual(_) {
        virtual_terms = virtual_terms + 1
      }
    }
  }
  inspect(virtual_terms, content="0")
}

///|
test "apply inserts reloads and spills for stack allocated operands" {
  let func = @machv.Function::new("reload_spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let seed = func.new_inst(Target("seed"))
  seed.add_operand(@machv.Operand::def(Virtual(v0)))
  seed.add_operand(@machv.Operand::def(Virtual(v1)))
  seed.add_operand(@machv.Operand::def(Virtual(v2)))
  entry.append(seed)
  let use_spilled = func.new_inst(Target("use_spilled"))
  use_spilled.add_operand(@machv.Operand::use_reg(Virtual(v2)))
  entry.append(use_spilled)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = allocate_and_apply_linear_scan(func, [p0, p1])
  let mut loads = 0
  let mut stores = 0
  let mut virtual_operands = 0
  for inst in entry.instructions {
    match inst.opcode {
      Load(_) => loads = loads + 1
      Store(_) => stores = stores + 1
      _ => ()
    }
    for operand in inst.operands {
      if operand.reg is Virtual(_) {
        virtual_operands = virtual_operands + 1
      }
    }
  }
  inspect(result.allocation.spill_count > 0, content="true")
  inspect(loads > 0, content="true")
  inspect(stores > 0, content="true")
  inspect(virtual_operands, content="0")
}
