///|
test "public verifier rejects a missing terminator" {
  let func = @machv.Function::Function("missing_terminator")
  func.new_block() |> ignore
  try func.verify() catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "public verifier rejects an empty function" {
  let func = @machv.Function::Function("empty")
  try func.verify() catch {
    err => inspect(err, content="EmptyFunction")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "public builder finish rejects a missing terminator" {
  let builder = @machv.FunctionBuilder::FunctionBuilder("unfinished")
  try builder.finish() catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected MachV builder finish to fail")
  }
}

///|
test "verifier rejects an invalid jump target" {
  let func = @machv.Function::Function("invalid_target")
  let entry = func.new_block()
  entry.set_terminator(Jump(7, []))
  try func.verify() catch {
    err => inspect(err, content="InvalidBlockTarget(block_id=7)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks jump argument arity" {
  let func = @machv.Function::Function("jump_arity")
  let entry = func.new_block()
  let target = func.new_block()
  target.params.push(func.new_vreg(Int))
  entry.set_terminator(Jump(target.id, []))
  target.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|ArityMismatch(message="jump from block 0 passes 0 arguments to block 1 with 1 parameters")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks jump argument register classes" {
  let func = @machv.Function::Function("jump_class")
  let entry = func.new_block()
  let target = func.new_block()
  let argument = func.add_param(Int)
  target.params.push(func.new_vreg(Float64))
  entry.set_terminator(Jump(target.id, [Virtual(argument)]))
  target.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|RegisterClassMismatch(message="jump argument 0 from block 0 has class int, expected double")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects parameterized targets for branches without arguments" {
  let func = @machv.Function::Function("branch_parameter")
  let entry = func.new_block()
  let target = func.new_block()
  let fallback = func.new_block()
  let condition = func.add_param(Int)
  target.params.push(func.new_vreg(Int))
  entry.set_terminator(Branch(Virtual(condition), target.id, fallback.id))
  target.set_terminator(Return([]))
  fallback.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|ArityMismatch(message="branch from block 0 cannot pass 1 arguments required by block 1")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks return arity" {
  let func = @machv.Function::Function("return_arity")
  func.add_result_kind(I64)
  func.new_block().set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|ArityMismatch(message="return in block 0 has 0 values, expected 1")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks return register classes" {
  let func = @machv.Function::Function("return_class")
  func.add_result_kind(F64)
  let value = func.add_param(Int)
  func.new_block().set_terminator(Return([Virtual(value)]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|RegisterClassMismatch(message="return value 0 in block 0 has class int, expected double")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects undefined virtual registers" {
  let func = @machv.Function::Function("undefined_vreg")
  func.add_result_kind(I64)
  func.new_block().set_terminator(Return([Virtual({ id: 99, class: Int })]))
  try func.verify() catch {
    err => inspect(err, content="UndefinedVReg(vreg_id=99)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects duplicate virtual register definitions" {
  let func = @machv.Function::Function("duplicate_definition")
  let block = func.new_block()
  let value = func.new_vreg(Int)
  let first = @machv.Inst::Inst(LoadConst(1L))
  first.add_def({ reg: Virtual(value) })
  block.add_inst(first)
  let second = @machv.Inst::Inst(LoadConst(2L))
  second.add_def({ reg: Virtual(value) })
  block.add_inst(second)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="DuplicateVRegDefinition(vreg_id=0)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects use before definition" {
  let func = @machv.Function::Function("use_before_definition")
  let block = func.new_block()
  let source = func.new_vreg(Int)
  let result = func.new_vreg(Int)
  let copy = @machv.Inst::Inst(Move)
  copy.add_use(Virtual(source))
  copy.add_def({ reg: Virtual(result) })
  block.add_inst(copy)
  let constant = @machv.Inst::Inst(LoadConst(1L))
  constant.add_def({ reg: Virtual(source) })
  block.add_inst(constant)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="UseBeforeDefinition(vreg_id=0)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects non-dominating definitions" {
  let func = @machv.Function::Function("non_dominating_definition")
  let entry = func.new_block()
  let then_block = func.new_block()
  let else_block = func.new_block()
  let cond = func.add_param(Int)
  let value = func.new_vreg(Int)
  let copy = func.new_vreg(Int)
  entry.set_terminator(Branch(Virtual(cond), then_block.id, else_block.id))
  let constant = @machv.Inst::Inst(LoadConst(1L))
  constant.add_def({ reg: Virtual(value) })
  then_block.add_inst(constant)
  then_block.set_terminator(Return([]))
  let copy_inst = @machv.Inst::Inst(Move)
  copy_inst.add_use(Virtual(value))
  copy_inst.add_def({ reg: Virtual(copy) })
  else_block.add_inst(copy_inst)
  else_block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|NonDominatingUse(vreg_id=1, defining_block=1, use_block=2)
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks operand constraint arrays" {
  let func = @machv.Function::Function("constraint_arity")
  let block = func.new_block()
  let value = func.new_vreg(Int)
  let inst = @machv.Inst::Inst(LoadConst(1L))
  inst.add_def({ reg: Virtual(value) })
  inst.def_constraints.clear()
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|InvalidInstruction(message="instruction 0 in block 0 has 1 defs but 0 def constraints")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier rejects duplicate block ids through mutable block arrays" {
  let func = @machv.Function::Function("duplicate_blocks")
  let block = func.new_block()
  block.set_terminator(Return([]))
  func.get_blocks().push(block)
  try func.verify() catch {
    err => inspect(err, content="DuplicateBlockId(block_id=0)")
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks opcode operand arity" {
  let func = @machv.Function::Function("move_arity")
  let block = func.new_block()
  let result = func.new_vreg(Int)
  let inst = @machv.Inst::Inst(Move)
  inst.add_def({ reg: Virtual(result) })
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|InvalidInstruction(message="instruction 0 in block 0 (mov) has 0 uses and 1 defs, expected 1 uses and 1 defs")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks scalar opcode register classes" {
  let func = @machv.Function::Function("add_classes")
  let block = func.new_block()
  let lhs = func.add_param(Float64)
  let rhs = func.add_param(Float64)
  let result = func.new_vreg(Float64)
  let inst = @machv.Inst::Inst(Add(true))
  inst.add_use(Virtual(lhs))
  inst.add_use(Virtual(rhs))
  inst.add_def({ reg: Virtual(result) })
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|RegisterClassMismatch(message="use 0 of instruction 0 in block 0 has class double, expected int")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks call result classes" {
  let func = @machv.Function::Function("call_result_class")
  let block = func.new_block()
  let callee = func.add_param(Int)
  let result = func.new_vreg(Int)
  let inst = @machv.Inst::Inst(CallPtr(0, [Float64], Foreign))
  inst.add_use(Virtual(callee))
  inst.add_def({ reg: Virtual(result) })
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|RegisterClassMismatch(message="def 0 of instruction 0 in block 0 has class int, expected double")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks call argument metadata" {
  let func = @machv.Function::Function("call_argument_count")
  let block = func.new_block()
  let callee = func.add_param(Int)
  let argument = func.add_param(Int)
  let inst = @machv.Inst::Inst(CallPtr(0, [], Foreign))
  inst.add_use(Virtual(callee))
  inst.add_use(Virtual(argument))
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|InvalidInstruction(message="pointer call in block 0 has 2 uses for 0 arguments")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "verifier checks vector-memory opcode classes" {
  let func = @machv.Function::Function("vector_load_class")
  let block = func.new_block()
  let base = func.add_param(Int)
  let result = func.new_vreg(Int)
  let inst = @machv.Inst::Inst(SIMDLoad(0))
  inst.add_use(Virtual(base))
  inst.add_def({ reg: Virtual(result) })
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|RegisterClassMismatch(message="def 0 of instruction 0 in block 0 has class int, expected vector")
        ),
      )
  } noraise {
    _ => fail("expected MachV verification to fail")
  }
}

///|
test "ISA verifier rejects out-of-range physical registers" {
  let func = @machv.Function::Function("invalid_amd64_register")
  let block = func.new_block()
  let inst = @machv.Inst::Inst(Move)
  inst.add_use(Physical({ index: 20, class: Int }))
  inst.add_def({ reg: Physical({ index: 0, class: Int }) })
  block.add_inst(inst)
  block.set_terminator(Return([]))
  try func.verify_for_isa(AMD64) catch {
    err =>
      inspect(
        err,
        content=(
          #|InvalidInstruction(message="invalid physical register x20 for amd64 at block 0 instruction 0 use 0")
        ),
      )
  } noraise {
    _ => fail("expected MachV ISA verification to fail")
  }
}
