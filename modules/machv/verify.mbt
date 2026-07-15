///|
pub suberror VerifyError {
  EmptyFunction
  MissingTerminator(block_id~ : Int)
  DuplicateBlockId(block_id~ : Int)
  InvalidBlockLayout(block_id~ : Int, expected_index~ : Int)
  InvalidBlockTarget(block_id~ : Int)
  ArityMismatch(message~ : String)
  RegisterClassMismatch(message~ : String)
  DuplicateVRegDefinition(vreg_id~ : Int)
  UndefinedVReg(vreg_id~ : Int)
  UseBeforeDefinition(vreg_id~ : Int)
  NonDominatingUse(vreg_id~ : Int, defining_block~ : Int, use_block~ : Int)
  InvalidInstruction(message~ : String)
} derive(Debug, Eq)

///|
priv enum VRegDefinition {
  FunctionParameter(@abi.RegClass)
  BlockParameter(@abi.RegClass, Int, Int)
  InstructionResult(@abi.RegClass, Int, Int, Int)
}

///|
priv struct ControlFlowGraph {
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
}

///|
pub impl Show for VerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn VerifyError::invalid_instruction(message : String) -> VerifyError {
  InvalidInstruction(message~)
}

///|
fn reg_class(reg : @abi.Reg) -> @abi.RegClass {
  match reg {
    Virtual(vreg) => vreg.class
    Physical(preg) => preg.class
  }
}

///|
fn writable_reg_class(writable : @abi.Writable) -> @abi.RegClass {
  reg_class(writable.reg)
}

///|
fn require_target(
  blocks : Map[Int, @block.Block],
  id : Int,
) -> @block.Block raise VerifyError {
  match blocks.get(id) {
    Some(block) => block
    None => raise InvalidBlockTarget(block_id=id)
  }
}

///|
fn require_same_class(
  actual : @abi.RegClass,
  expected : @abi.RegClass,
  message : String,
) -> Unit raise VerifyError {
  if actual != expected {
    raise RegisterClassMismatch(
      message="\{message} has class \{actual}, expected \{expected}",
    )
  }
}

///|
fn require_target_without_args(
  blocks : Map[Int, @block.Block],
  source_id : Int,
  target_id : Int,
) -> Unit raise VerifyError {
  let target = require_target(blocks, target_id)
  if !target.params.is_empty() {
    raise ArityMismatch(
      message="branch from block \{source_id} cannot pass \{target.params.length()} arguments required by block \{target_id}",
    )
  }
}

///|
fn terminator_target_ids(term : @instr.Terminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Branch(_, then_id, else_id)
    | BranchCmp(_, _, _, _, then_id, else_id)
    | BranchZero(_, _, _, then_id, else_id)
    | BranchCmpImm(_, _, _, _, then_id, else_id) => [then_id, else_id]
    BrTable(_, targets, default_id) => {
      let result = targets.copy()
      result.push(default_id)
      result
    }
    Return(_) | Trap(_) => []
  }
}

///|
fn ControlFlowGraph::build(func : Function) -> ControlFlowGraph {
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  for _ in func.blocks {
    preds.push([])
    succs.push([])
  }
  let block_indices : Map[Int, Int] = Map([])
  for i, block in func.blocks {
    block_indices.set(block.id, i)
  }
  for block_index, block in func.blocks {
    if block.terminator is Some(term) {
      for target_id in terminator_target_ids(term) {
        if block_indices.get(target_id) is Some(target_index) {
          succs[block_index].push(target_index)
          preds[target_index].push(block_index)
        }
      }
    }
  }
  { preds, succs }
}

///|
fn ControlFlowGraph::postorder(self : ControlFlowGraph) -> Array[Int] {
  let visited = Array::make(self.succs.length(), false)
  let result : Array[Int] = []
  if !self.succs.is_empty() {
    let stack : Array[(Int, Int)] = [(0, 0)]
    visited[0] = true
    while !stack.is_empty() {
      let top = stack.length() - 1
      let (block, successor_index) = stack[top]
      if successor_index < self.succs[block].length() {
        stack[top] = (block, successor_index + 1)
        let successor = self.succs[block][successor_index]
        if !visited[successor] {
          visited[successor] = true
          stack.push((successor, 0))
        }
      } else {
        stack.pop() |> ignore
        result.push(block)
      }
    }
  }
  result
}

///|
fn intersect_dominators(
  idom : Array[Int],
  rpo_number : Array[Int],
  first_init : Int,
  second_init : Int,
) -> Int {
  let mut first = first_init
  let mut second = second_init
  while first != second {
    while rpo_number[first] > rpo_number[second] {
      first = idom[first]
    }
    while rpo_number[second] > rpo_number[first] {
      second = idom[second]
    }
  }
  first
}

///|
fn ControlFlowGraph::compute_dominators(self : ControlFlowGraph) -> Array[Int] {
  let count = self.succs.length()
  let idom = Array::make(count, -1)
  if count == 0 {
    return idom
  }
  idom[0] = 0
  let rpo = self.postorder()
  rpo.rev_in_place()
  let rpo_number = Array::make(count, -1)
  for i, block in rpo {
    rpo_number[block] = i
  }
  let mut changed = true
  while changed {
    changed = false
    for block in rpo {
      if block == 0 {
        continue
      }
      let mut new_idom = -1
      for predecessor in self.preds[block] {
        if idom[predecessor] != -1 {
          new_idom = if new_idom == -1 {
            predecessor
          } else {
            intersect_dominators(idom, rpo_number, new_idom, predecessor)
          }
        }
      }
      if new_idom != -1 && idom[block] != new_idom {
        idom[block] = new_idom
        changed = true
      }
    }
  }
  idom
}

///|
fn dominates(idom : Array[Int], defining_block : Int, use_block : Int) -> Bool {
  if defining_block == use_block {
    return true
  }
  let mut current = use_block
  while current != -1 && current != 0 {
    current = idom[current]
    if current == defining_block {
      return true
    }
  }
  defining_block == 0 && current == 0
}

///|
fn record_definition(
  vreg : @abi.VReg,
  definition : VRegDefinition,
  definitions : Array[VRegDefinition?],
) -> Unit raise VerifyError {
  if vreg.id < 0 || vreg.id >= definitions.length() {
    raise InvalidInstruction(
      message="definition uses virtual register id \{vreg.id} outside the function register range",
    )
  }
  if definitions[vreg.id] is Some(_) {
    raise DuplicateVRegDefinition(vreg_id=vreg.id)
  }
  definitions[vreg.id] = Some(definition)
}

///|
fn definition_class(definition : VRegDefinition) -> @abi.RegClass {
  match definition {
    FunctionParameter(class)
    | BlockParameter(class, _, _)
    | InstructionResult(class, _, _, _) => class
  }
}

///|
fn verify_virtual_use(
  vreg : @abi.VReg,
  definitions : Array[VRegDefinition?],
  use_block_index : Int,
  use_block_id : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  if vreg.id < 0 || vreg.id >= definitions.length() {
    raise UndefinedVReg(vreg_id=vreg.id)
  }
  match definitions[vreg.id] {
    None => raise UndefinedVReg(vreg_id=vreg.id)
    Some(definition) => {
      require_same_class(
        vreg.class,
        definition_class(definition),
        "virtual register \{vreg.id}",
      )
      match definition {
        FunctionParameter(_) => ()
        BlockParameter(_, defining_index, defining_id) =>
          if !dominates(idom, defining_index, use_block_index) {
            raise NonDominatingUse(
              vreg_id=vreg.id,
              defining_block=defining_id,
              use_block=use_block_id,
            )
          }
        InstructionResult(_, defining_index, defining_id, defining_position) =>
          if defining_index == use_block_index {
            if defining_position >= use_position {
              raise UseBeforeDefinition(vreg_id=vreg.id)
            }
          } else if !dominates(idom, defining_index, use_block_index) {
            raise NonDominatingUse(
              vreg_id=vreg.id,
              defining_block=defining_id,
              use_block=use_block_id,
            )
          }
      }
    }
  }
}

///|
fn verify_reg_use(
  reg : @abi.Reg,
  definitions : Array[VRegDefinition?],
  use_block_index : Int,
  use_block_id : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  if reg is Virtual(vreg) {
    verify_virtual_use(
      vreg, definitions, use_block_index, use_block_id, use_position, idom,
    )
  }
}

///|
fn verify_constraint(
  reg : @abi.Reg,
  constraint : @abi.OperandConstraint,
  message : String,
) -> Unit raise VerifyError {
  if constraint is FixedReg(preg) {
    require_same_class(reg_class(reg), preg.class, message)
  }
}

///|
fn verify_inst_structure(
  inst : @instr.Inst,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  if inst.uses.length() != inst.use_constraints.length() {
    raise InvalidInstruction(
      message="instruction \{inst_index} in block \{block_id} has \{inst.uses.length()} uses but \{inst.use_constraints.length()} use constraints",
    )
  }
  if inst.defs.length() != inst.def_constraints.length() {
    raise InvalidInstruction(
      message="instruction \{inst_index} in block \{block_id} has \{inst.defs.length()} defs but \{inst.def_constraints.length()} def constraints",
    )
  }
  for i, reg in inst.uses {
    verify_constraint(
      reg,
      inst.use_constraints[i],
      "use constraint \{i} in block \{block_id}",
    )
  }
  for i, writable in inst.defs {
    verify_constraint(
      writable.reg,
      inst.def_constraints[i],
      "def constraint \{i} in block \{block_id}",
    )
  }
  verify_opcode_contract(inst, block_id, inst_index)
}

///|
fn verify_terminator_uses(
  term : @instr.Terminator,
  definitions : Array[VRegDefinition?],
  block_index : Int,
  block_id : Int,
  position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  fn verify(
    reg : @abi.Reg,
    definitions : Array[VRegDefinition?],
    block_index : Int,
    block_id : Int,
    position : Int,
    idom : Array[Int],
  ) -> Unit raise VerifyError {
    verify_reg_use(reg, definitions, block_index, block_id, position, idom)
  }

  match term {
    Jump(_, args) | Return(args) =>
      for reg in args {
        verify(reg, definitions, block_index, block_id, position, idom)
      }
    Branch(cond, _, _)
    | BranchZero(cond, _, _, _, _)
    | BranchCmpImm(cond, _, _, _, _, _)
    | BrTable(cond, _, _) =>
      verify(cond, definitions, block_index, block_id, position, idom)
    BranchCmp(lhs, rhs, _, _, _, _) => {
      verify(lhs, definitions, block_index, block_id, position, idom)
      verify(rhs, definitions, block_index, block_id, position, idom)
    }
    Trap(_) => ()
  }
}

///|
fn Function::verify_terminator(
  self : Function,
  blocks : Map[Int, @block.Block],
  block : @block.Block,
  term : @instr.Terminator,
) -> Unit raise VerifyError {
  match term {
    Jump(target_id, args) => {
      let target = require_target(blocks, target_id)
      if args.length() != target.params.length() {
        raise ArityMismatch(
          message="jump from block \{block.id} passes \{args.length()} arguments to block \{target_id} with \{target.params.length()} parameters",
        )
      }
      for i, arg in args {
        require_same_class(
          reg_class(arg),
          target.params[i].class,
          "jump argument \{i} from block \{block.id}",
        )
      }
    }
    Branch(cond, then_id, else_id) => {
      require_same_class(
        reg_class(cond),
        Int,
        "branch condition in block \{block.id}",
      )
      require_target_without_args(blocks, block.id, then_id)
      require_target_without_args(blocks, block.id, else_id)
    }
    BranchCmp(lhs, rhs, _, _, then_id, else_id) => {
      require_same_class(
        reg_class(rhs),
        reg_class(lhs),
        "branch comparison rhs in block \{block.id}",
      )
      require_target_without_args(blocks, block.id, then_id)
      require_target_without_args(blocks, block.id, else_id)
    }
    BranchZero(reg, _, _, then_id, else_id) => {
      require_same_class(
        reg_class(reg),
        Int,
        "branch-zero operand in block \{block.id}",
      )
      require_target_without_args(blocks, block.id, then_id)
      require_target_without_args(blocks, block.id, else_id)
    }
    BranchCmpImm(lhs, _, _, _, then_id, else_id) => {
      require_same_class(
        reg_class(lhs),
        Int,
        "branch-immediate operand in block \{block.id}",
      )
      require_target_without_args(blocks, block.id, then_id)
      require_target_without_args(blocks, block.id, else_id)
    }
    Return(values) => {
      if values.length() != self.result_kinds.length() {
        raise ArityMismatch(
          message="return in block \{block.id} has \{values.length()} values, expected \{self.result_kinds.length()}",
        )
      }
      for i, value in values {
        require_same_class(
          reg_class(value),
          self.result_kinds[i].reg_class(),
          "return value \{i} in block \{block.id}",
        )
      }
    }
    Trap(_) => ()
    BrTable(index, targets, default_id) => {
      require_same_class(
        reg_class(index),
        Int,
        "br_table index in block \{block.id}",
      )
      for target_id in targets {
        require_target_without_args(blocks, block.id, target_id)
      }
      require_target_without_args(blocks, block.id, default_id)
    }
  }
}

///|
pub fn Function::verify(self : Function) -> Unit raise VerifyError {
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  let blocks : Map[Int, @block.Block] = Map([])
  for block in self.blocks {
    if block.id < 0 {
      raise InvalidBlockTarget(block_id=block.id)
    }
    if blocks.get(block.id) is Some(_) {
      raise DuplicateBlockId(block_id=block.id)
    }
    blocks.set(block.id, block)
  }
  for block in self.blocks {
    match block.terminator {
      None => raise MissingTerminator(block_id=block.id)
      Some(term) => self.verify_terminator(blocks, block, term)
    }
  }
  let definitions : Array[VRegDefinition?] = Array::make(
    self.next_vreg_id,
    None,
  )
  for param in self.params {
    record_definition(param, FunctionParameter(param.class), definitions)
  }
  for block_index, block in self.blocks {
    for param in block.params {
      record_definition(
        param,
        BlockParameter(param.class, block_index, block.id),
        definitions,
      )
    }
    for inst_index, inst in block.insts {
      verify_inst_structure(inst, block.id, inst_index)
      for writable in inst.defs {
        if writable.reg is Virtual(vreg) {
          record_definition(
            vreg,
            InstructionResult(
              writable_reg_class(writable),
              block_index,
              block.id,
              inst_index,
            ),
            definitions,
          )
        }
      }
    }
  }
  let idom = ControlFlowGraph::build(self).compute_dominators()
  for block_index, block in self.blocks {
    for inst_index, inst in block.insts {
      for reg in inst.uses {
        verify_reg_use(
          reg,
          definitions,
          block_index,
          block.id,
          inst_index,
          idom,
        )
      }
    }
    if block.terminator is Some(term) {
      verify_terminator_uses(
        term,
        definitions,
        block_index,
        block.id,
        block.insts.length(),
        idom,
      )
    }
  }
}

///|
fn verify_physical_register(
  preg : @abi.PReg,
  isa : @isa.ISA,
  location : String,
) -> Unit raise VerifyError {
  let valid = match (isa, preg.class) {
    (AArch64, Int) => preg.index >= 0 && preg.index < 32
    (AArch64, Float32 | Float64 | Vector) => preg.index >= 0 && preg.index < 32
    (AMD64, Int) =>
      preg.index >= 0 && preg.index < 16 && preg.index != 4 && preg.index != 5
    (AMD64, Float32 | Float64 | Vector) => preg.index >= 0 && preg.index < 16
  }
  if !valid {
    let isa_name = match isa {
      AArch64 => "aarch64"
      AMD64 => "amd64"
    }
    raise InvalidInstruction(
      message="invalid physical register \{preg} for \{isa_name} at \{location}",
    )
  }
}

///|
fn require_target_matches(
  func : Function,
  isa : @isa.ISA,
) -> Unit raise VerifyError {
  match func.target() {
    AArch64 if isa is AMD64 =>
      raise InvalidInstruction(
        message="MachV function targets aarch64 but was consumed as amd64",
      )
    AMD64 if isa is AArch64 =>
      raise InvalidInstruction(
        message="MachV function targets amd64 but was consumed as aarch64",
      )
    _ => ()
  }
}

///|
fn verify_condition_for_isa(
  cond : @instr.Cond,
  isa : @isa.ISA,
  location : String,
) -> Unit raise VerifyError {
  if cond is AMD64(_) && isa is AArch64 {
    raise InvalidInstruction(
      message="AMD64 condition \{cond} is not valid for aarch64 at \{location}",
    )
  }
}

///|
fn verify_opcode_for_isa(
  opcode : @instr.Opcode,
  isa : @isa.ISA,
  location : String,
) -> Unit raise VerifyError {
  match opcode {
    AMD64(op) if isa is AArch64 =>
      raise InvalidInstruction(
        message="AMD64 opcode \{op} is not valid for aarch64 at \{location}",
      )
    TrapIf(cond, _) | FpuSel(_, cond) =>
      verify_condition_for_isa(cond, isa, location)
    _ => ()
  }
}

///|
fn Function::verify_isa_dialect(
  self : Function,
  isa : @isa.ISA,
) -> Unit raise VerifyError {
  for block in self.blocks {
    for inst_index, inst in block.insts {
      verify_opcode_for_isa(
        inst.opcode,
        isa,
        "block \{block.id} instruction \{inst_index}",
      )
    }
    if block.terminator is Some(term) {
      match term {
        BranchCmp(_, _, cond, _, _, _) | BranchCmpImm(_, _, cond, _, _, _) =>
          verify_condition_for_isa(cond, isa, "block \{block.id} terminator")
        _ => ()
      }
    }
  }
}

///|
fn verify_reg_for_isa(
  reg : @abi.Reg,
  isa : @isa.ISA,
  location : String,
) -> Unit raise VerifyError {
  if reg is Physical(preg) {
    verify_physical_register(preg, isa, location)
  }
}

///|
fn Function::verify_isa_registers(
  self : Function,
  isa : @isa.ISA,
) -> Unit raise VerifyError {
  for i, preg in self.param_pregs {
    if preg is Some(reg) {
      verify_physical_register(reg, isa, "param_pregs[\{i}]")
    }
  }
  for block in self.blocks {
    for inst_index, inst in block.insts {
      for i, reg in inst.uses {
        verify_reg_for_isa(
          reg,
          isa,
          "block \{block.id} instruction \{inst_index} use \{i}",
        )
      }
      for i, writable in inst.defs {
        verify_reg_for_isa(
          writable.reg,
          isa,
          "block \{block.id} instruction \{inst_index} def \{i}",
        )
      }
      for i, constraint in inst.use_constraints {
        if constraint is FixedReg(preg) {
          verify_physical_register(
            preg,
            isa,
            "block \{block.id} instruction \{inst_index} use constraint \{i}",
          )
        }
      }
      for i, constraint in inst.def_constraints {
        if constraint is FixedReg(preg) {
          verify_physical_register(
            preg,
            isa,
            "block \{block.id} instruction \{inst_index} def constraint \{i}",
          )
        }
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(_, regs) | Return(regs) =>
          for i, reg in regs {
            verify_reg_for_isa(
              reg,
              isa,
              "block \{block.id} terminator use \{i}",
            )
          }
        Branch(reg, _, _)
        | BranchZero(reg, _, _, _, _)
        | BranchCmpImm(reg, _, _, _, _, _)
        | BrTable(reg, _, _) =>
          verify_reg_for_isa(reg, isa, "block \{block.id} terminator use 0")
        BranchCmp(lhs, rhs, _, _, _, _) => {
          verify_reg_for_isa(lhs, isa, "block \{block.id} terminator use 0")
          verify_reg_for_isa(rhs, isa, "block \{block.id} terminator use 1")
        }
        Trap(_) => ()
      }
    }
  }
}

///|
pub fn Function::verify_for_isa(
  self : Function,
  isa : @isa.ISA,
) -> Unit raise VerifyError {
  require_target_matches(self, isa)
  self.verify()
  self.verify_isa_dialect(isa)
  self.verify_isa_registers(isa)
}

///|
/// Verify invariants required by the register-allocation data structures,
/// which address blocks by dense numeric ID.
pub fn Function::verify_for_regalloc(self : Function) -> Unit raise VerifyError {
  self.verify()
  for index, block in self.blocks {
    if block.id != index {
      raise InvalidBlockLayout(block_id=block.id, expected_index=index)
    }
  }
}

///|
pub fn Function::verify_for_regalloc_isa(
  self : Function,
  isa : @isa.ISA,
) -> Unit raise VerifyError {
  require_target_matches(self, isa)
  self.verify_for_regalloc()
  self.verify_isa_dialect(isa)
  self.verify_isa_registers(isa)
}
