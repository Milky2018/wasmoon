///|
fn format_reg_list(regs : Array[Reg]) -> String {
  regs.map(fn(reg) { reg.to_string() }).join(", ")
}

///|
fn format_operand(operand : Operand) -> String {
  let role = match operand.role {
    Use => "use"
    Def => "def"
    UseDef => "use_def"
  }
  "\{role} \{operand.reg}"
}

///|
fn format_instruction(inst : Instruction) -> String {
  let operands = inst.operands.map(format_operand).join(", ")
  if operands.length() == 0 {
    "    i\{inst.id}: \{to_repr(inst.opcode)}"
  } else {
    "    i\{inst.id}: \{to_repr(inst.opcode)} \{operands}"
  }
}

///|
fn format_target_args(target : Int, args : Array[Reg]) -> String {
  if args.length() == 0 {
    "block\{target}"
  } else {
    "block\{target}(\{format_reg_list(args)})"
  }
}

///|
fn format_terminator(term : Terminator) -> String {
  match term {
    TermJump(target, args) => "    jump \{format_target_args(target, args)}"
    TermBranch(cond, true_target, true_args, false_target, false_args) =>
      "    branch \{cond}, \{format_target_args(true_target, true_args)}, \{format_target_args(false_target, false_args)}"
    TermBranchCmp(
      lhs,
      rhs,
      cond,
      _,
      true_target,
      true_args,
      false_target,
      false_args
    ) => {
      let cond_text = to_repr(cond).to_string()
      "    branch_cmp \{lhs}, \{rhs}, \{cond_text}, \{format_target_args(true_target, true_args)}, \{format_target_args(false_target, false_args)}"
    }
    TermBranchZero(
      reg,
      is_nonzero,
      _,
      true_target,
      true_args,
      false_target,
      false_args
    ) =>
      "    branch_zero \{reg}, nonzero=\{is_nonzero}, \{format_target_args(true_target, true_args)}, \{format_target_args(false_target, false_args)}"
    TermBranchCmpImm(
      reg,
      imm,
      cond,
      _,
      true_target,
      true_args,
      false_target,
      false_args
    ) => {
      let cond_text = to_repr(cond).to_string()
      "    branch_cmp_imm \{reg}, \{imm}, \{cond_text}, \{format_target_args(true_target, true_args)}, \{format_target_args(false_target, false_args)}"
    }
    TermReturn(values) => "    return \{format_reg_list(values)}"
    TermTrap(reason) => "    trap \{reason}"
    TermBrTable(index, targets, default_target) => {
      let targets_text = targets.map(fn(t) { t.to_string() }).join(", ")
      "    br_table \{index}, [\{targets_text}], block\{default_target}"
    }
  }
}

///|
fn format_block_header(block : Block) -> String {
  if block.params.length() == 0 {
    "block\{block.id}:"
  } else {
    let params = block.params.map(fn(param) { param.to_string() }).join(", ")
    "block\{block.id}(\{params}):"
  }
}

///|
pub fn AbstractFunction::print(self : AbstractFunction) -> String {
  let lines : Array[String] = []
  let params = self.params.map(fn(param) { param.to_string() }).join(", ")
  let results = self.results.map(fn(class) { class.to_string() }).join(", ")
  if results.length() == 0 {
    lines.push("function \{self.name}(\{params}) {")
  } else {
    lines.push("function \{self.name}(\{params}) -> (\{results}) {")
  }
  for block in self.blocks {
    lines.push(format_block_header(block))
    for inst in block.instructions {
      lines.push(format_instruction(inst))
    }
    if block.terminator is Some(term) {
      lines.push(format_terminator(term))
    }
  }
  lines.push("}")
  lines.join("\n") + "\n"
}
