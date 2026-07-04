///|
fn cond_to_machv(cond : @instr.Cond) -> @machv.Cond {
  match cond {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Le => Le
    Gt => Gt
    Ge => Ge
    Hi => Ugt
    Hs => Uge
    Lo => Ult
    Ls => Ule
    other => Custom("\{other}")
  }
}

///|
fn opcode_to_machv(opcode : @instr.VCodeOpcode) -> @machv.Opcode {
  match opcode {
    Move => Move
    opcode => {
      let text = "\{opcode}"
      match opcode.call_type() {
        Regular | TailCall => Call(text)
        None => Target(text)
      }
    }
  }
}

///|
fn add_constraint(
  out : @machv.Instruction,
  operand_index : Int,
  constraint : @abi.OperandConstraint,
) -> Unit {
  match constraint {
    Any => ()
    FixedReg(preg) =>
      out.add_constraint({ operand_index, allowed_regs: [preg] })
  }
}

///|
fn @instr.VCodeInst::to_machv(
  self : @instr.VCodeInst,
  id : Int,
) -> @machv.Instruction {
  let out = @machv.Instruction::new(id, opcode_to_machv(self.opcode))
  for i, def in self.defs {
    out.add_operand(@machv.Operand::def(def.reg))
    add_constraint(out, i, self.def_constraints[i])
  }
  let use_base = self.defs.length()
  for i, use_ in self.uses {
    out.add_operand(@machv.Operand::use_reg(use_))
    add_constraint(out, use_base + i, self.use_constraints[i])
  }
  out
}

///|
fn @instr.VCodeTerminator::to_machv(
  self : @instr.VCodeTerminator,
) -> @machv.Terminator {
  match self {
    Jump(target, args) => TermJump(target, args)
    Branch(cond, then_b, else_b) => TermBranch(cond, then_b, else_b)
    BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) =>
      TermBranchCmp(lhs, rhs, cond_to_machv(cond), is_64, then_b, else_b)
    BranchZero(reg, is_nonzero, is_64, then_b, else_b) =>
      TermBranchZero(reg, is_nonzero, is_64, then_b, else_b)
    BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) =>
      TermBranchCmpImm(lhs, imm, cond_to_machv(cond), is_64, then_b, else_b)
    Return(values) => TermReturn(values)
    Trap(message) => TermTrap(message)
    BrTable(index, targets, default) => TermBrTable(index, targets, default)
  }
}

///|
fn @block.VCodeBlock::to_machv(self : @block.VCodeBlock) -> @machv.Block {
  let out = @machv.Block::new(self.id)
  for param in self.params {
    out.add_param(param)
  }
  for i, inst in self.insts {
    out.append(inst.to_machv(i))
  }
  if self.terminator is Some(term) {
    out.set_terminator(term.to_machv())
  }
  out
}

///|
pub fn VCodeFunction::to_machv(self : VCodeFunction) -> @machv.Function {
  let out = @machv.Function::new(self.name)
  for param in self.params {
    out.push_param(param)
  }
  for result in self.results {
    out.add_result(result)
  }
  out.set_num_spill_slots(self.num_spill_slots)
  out.set_int_stack_params(self.int_stack_params)
  out.update_max_outgoing_args_size(self.max_outgoing_args_size)
  for preg in self.param_pregs {
    out.add_param_preg(preg)
  }
  for block in self.blocks {
    out.blocks.push(block.to_machv())
  }
  out.next_block_id = self.blocks.length()
  out.next_vreg_id = self.next_vreg_id
  out
}
