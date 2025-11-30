// VCode Builder - helper for constructing VCode functions
// Provides a convenient API for emitting machine-level instructions

///|
/// VCode builder for constructing VCode functions
pub(all) struct VCodeBuilder {
  func : VCodeFunction
  mut current_block : VCodeBlock?
}

///|
pub fn VCodeBuilder::new(name : String) -> VCodeBuilder {
  { func: VCodeFunction::new(name), current_block: None }
}

///|
pub fn VCodeBuilder::add_param(self : VCodeBuilder, class : RegClass) -> VReg {
  self.func.add_param(class)
}

///|
pub fn VCodeBuilder::add_result(self : VCodeBuilder, class : RegClass) -> Unit {
  self.func.add_result(class)
}

///|
pub fn VCodeBuilder::create_block(self : VCodeBuilder) -> VCodeBlock {
  self.func.new_block()
}

///|
pub fn VCodeBuilder::switch_to_block(
  self : VCodeBuilder,
  block : VCodeBlock,
) -> Unit {
  self.current_block = Some(block)
}

///|
pub fn VCodeBuilder::current_block(self : VCodeBuilder) -> VCodeBlock? {
  self.current_block
}

///|
pub fn VCodeBuilder::get_function(self : VCodeBuilder) -> VCodeFunction {
  self.func
}

///|
pub fn VCodeBuilder::print(self : VCodeBuilder) -> String {
  self.func.print()
}

///|
fn VCodeBuilder::new_vreg(self : VCodeBuilder, class : RegClass) -> VReg {
  self.func.new_vreg(class)
}

///|
fn VCodeBuilder::emit(self : VCodeBuilder, inst : VCodeInst) -> Unit {
  match self.current_block {
    Some(block) => block.add_inst(inst)
    None => () // Silently ignore if no current block
  }
}

// ============ Integer Arithmetic ============

///|
pub fn VCodeBuilder::add(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Add)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::sub(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Sub)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::mul(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Mul)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::sdiv(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(SDiv)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::udiv(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(UDiv)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Bitwise Operations ============

///|
pub fn VCodeBuilder::band(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(And)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::bor(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Or)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::bxor(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Xor)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::shl(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Shl)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::ashr(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(AShr)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::lshr(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(LShr)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Floating Point ============

///|
pub fn VCodeBuilder::fadd(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Float)
  let inst = VCodeInst::new(FAdd)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fsub(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Float)
  let inst = VCodeInst::new(FSub)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fmul(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Float)
  let inst = VCodeInst::new(FMul)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fdiv(self : VCodeBuilder, a : VReg, b : VReg) -> VReg {
  let result = self.new_vreg(Float)
  let inst = VCodeInst::new(FDiv)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Memory Operations ============

///|
pub fn VCodeBuilder::load(
  self : VCodeBuilder,
  ty : MemType,
  addr : VReg,
  offset : Int,
) -> VReg {
  let class = match ty {
    F32 | F64 => Float
    _ => Int
  }
  let result = self.new_vreg(class)
  let inst = VCodeInst::new(Load(ty, offset))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(addr))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::store(
  self : VCodeBuilder,
  ty : MemType,
  addr : VReg,
  value : VReg,
  offset : Int,
) -> Unit {
  let inst = VCodeInst::new(Store(ty, offset))
  inst.add_use(Virtual(addr))
  inst.add_use(Virtual(value))
  self.emit(inst)
}

// ============ Moves and Constants ============

///|
pub fn VCodeBuilder::mov(self : VCodeBuilder, src : VReg) -> VReg {
  let result = self.new_vreg(src.class)
  let inst = VCodeInst::new(Move)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(src))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::iconst(self : VCodeBuilder, value : Int64) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(LoadConst(value))
  inst.add_def({ reg: Virtual(result) })
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fconst(self : VCodeBuilder, value : Double) -> VReg {
  let result = self.new_vreg(Float)
  let inst = VCodeInst::new(LoadConstF(value))
  inst.add_def({ reg: Virtual(result) })
  self.emit(inst)
  result
}

// ============ Comparisons ============

///|
pub fn VCodeBuilder::cmp(
  self : VCodeBuilder,
  kind : CmpKind,
  a : VReg,
  b : VReg,
) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(Cmp(kind))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fcmp(
  self : VCodeBuilder,
  kind : FCmpKind,
  a : VReg,
  b : VReg,
) -> VReg {
  let result = self.new_vreg(Int)
  let inst = VCodeInst::new(FCmp(kind))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Terminators ============

///|
pub fn VCodeBuilder::jump(self : VCodeBuilder, target : VCodeBlock) -> Unit {
  match self.current_block {
    Some(block) => block.set_terminator(VCodeTerminator::Jump(target.id))
    None => ()
  }
}

///|
pub fn VCodeBuilder::branch(
  self : VCodeBuilder,
  cond : VReg,
  then_block : VCodeBlock,
  else_block : VCodeBlock,
) -> Unit {
  match self.current_block {
    Some(block) =>
      block.set_terminator(
        VCodeTerminator::Branch(Virtual(cond), then_block.id, else_block.id),
      )
    None => ()
  }
}

///|
pub fn VCodeBuilder::return_(self : VCodeBuilder, values : Array[VReg]) -> Unit {
  match self.current_block {
    Some(block) => {
      let regs : Array[Reg] = []
      for v in values {
        regs.push(Virtual(v))
      }
      block.set_terminator(VCodeTerminator::Return(regs))
    }
    None => ()
  }
}

///|
pub fn VCodeBuilder::trap(self : VCodeBuilder, msg : String) -> Unit {
  match self.current_block {
    Some(block) => block.set_terminator(VCodeTerminator::Trap(msg))
    None => ()
  }
}
