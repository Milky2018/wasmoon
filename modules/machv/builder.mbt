///|
pub struct FunctionBuilder {
  func : Function
  mut current_block : @block.Block
}

///|
pub fn FunctionBuilder::FunctionBuilder(name : String) -> FunctionBuilder {
  let func = Function(name)
  let entry = func.new_block()
  { func, current_block: entry }
}

///|
pub fn FunctionBuilder::add_param(
  self : FunctionBuilder,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.func.add_param(class)
}

///|
pub fn FunctionBuilder::add_result(
  self : FunctionBuilder,
  kind : ValueKind,
) -> Unit {
  self.func.add_result_kind(kind)
}

///|
pub fn FunctionBuilder::create_block(self : FunctionBuilder) -> Int {
  self.func.new_block().id
}

///|
pub fn FunctionBuilder::switch_to_block(
  self : FunctionBuilder,
  block_id : Int,
) -> Unit {
  for block in self.func.blocks {
    if block.id == block_id {
      self.current_block = block
      return
    }
  }
  abort("unknown MachV block \{block_id}")
}

///|
pub fn FunctionBuilder::new_vreg(
  self : FunctionBuilder,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.func.new_vreg(class)
}

///|
pub fn FunctionBuilder::append(
  self : FunctionBuilder,
  opcode : @instr.Opcode,
  uses? : Array[@abi.Reg] = [],
  defs? : Array[@abi.Writable] = [],
  use_constraints? : Array[@abi.OperandConstraint] = [],
  def_constraints? : Array[@abi.OperandConstraint] = [],
) -> Int {
  let inst = @instr.Inst(opcode)
  for i, src in uses {
    if i < use_constraints.length() {
      match use_constraints[i] {
        Any => inst.add_use(src)
        FixedReg(preg) => inst.add_use_fixed(src, preg)
      }
    } else {
      inst.add_use(src)
    }
  }
  for i, def in defs {
    if i < def_constraints.length() {
      match def_constraints[i] {
        Any => inst.add_def(def)
        FixedReg(preg) => inst.add_def_fixed(def, preg)
      }
    } else {
      inst.add_def(def)
    }
  }
  self.current_block.add_inst(inst)
  self.current_block.insts.length() - 1
}

///|
pub fn FunctionBuilder::terminate(
  self : FunctionBuilder,
  term : @instr.Terminator,
) -> Unit {
  self.current_block.set_terminator(term)
}

///|
pub fn FunctionBuilder::finish(self : FunctionBuilder) -> Function {
  self.func
}

///|
pub fn Function::blocks(self : Function) -> Array[@block.Block] {
  self.blocks
}

///|
pub fn Function::params(self : Function) -> Array[@abi.VReg] {
  self.params
}
