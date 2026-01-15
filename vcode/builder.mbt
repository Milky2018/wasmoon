// VCode Builder - helper for constructing VCode functions
// Provides a convenient API for emitting machine-level instructions

///|
/// VCode builder for constructing VCode functions
struct VCodeBuilder {
  func : @regalloc.VCodeFunction
  mut current_block : @block.VCodeBlock?
}

///|
pub fn VCodeBuilder::new(name : String) -> VCodeBuilder {
  { func: @regalloc.VCodeFunction::new(name), current_block: None }
}

///|
pub fn VCodeBuilder::add_param(
  self : VCodeBuilder,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.func.add_param(class)
}

///|
pub fn VCodeBuilder::add_result(
  self : VCodeBuilder,
  class : @abi.RegClass,
) -> Unit {
  self.func.add_result(class)
}

///|
pub fn VCodeBuilder::create_block(self : VCodeBuilder) -> @block.VCodeBlock {
  self.func.new_block()
}

///|
pub fn VCodeBuilder::switch_to_block(
  self : VCodeBuilder,
  block : @block.VCodeBlock,
) -> Unit {
  self.current_block = Some(block)
}

///|
pub fn VCodeBuilder::current_block(self : VCodeBuilder) -> @block.VCodeBlock? {
  self.current_block
}

///|
pub fn VCodeBuilder::get_function(
  self : VCodeBuilder,
) -> @regalloc.VCodeFunction {
  self.func
}

///|
pub fn VCodeBuilder::print(self : VCodeBuilder) -> String {
  self.func.print()
}

///|
fn VCodeBuilder::new_vreg(
  self : VCodeBuilder,
  class : @abi.RegClass,
) -> @abi.VReg {
  self.func.new_vreg(class)
}

///|
fn VCodeBuilder::emit(self : VCodeBuilder, inst : @instr.VCodeInst) -> Unit {
  if self.current_block is Some(block) {
    block.add_inst(inst)
  }
}

// ============ Integer Arithmetic ============

///|
pub fn VCodeBuilder::add(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Add(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::sub(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Sub(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::mul(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Mul(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::sdiv(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(SDiv(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::udiv(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(UDiv(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Bitwise Operations ============

///|
pub fn VCodeBuilder::band(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(And)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::bor(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Or)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::bxor(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Xor)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::shl(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Shl(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::ashr(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(AShr(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::lshr(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(LShr(is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Floating Point ============

///|
pub fn VCodeBuilder::fadd(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Float64)
  let inst = @instr.VCodeInst::new(FAdd(false)) // f64 operation
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fsub(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Float64)
  let inst = @instr.VCodeInst::new(FSub(false)) // f64 operation
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fmul(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Float64)
  let inst = @instr.VCodeInst::new(FMul(false)) // f64 operation
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fdiv(
  self : VCodeBuilder,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Float64)
  let inst = @instr.VCodeInst::new(FDiv(false)) // f64 operation
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
  ty : @instr.MemType,
  addr : @abi.VReg,
  offset : Int,
) -> @abi.VReg {
  let class = match ty {
    F32 => @abi.Float32
    F64 => @abi.Float64
    _ => @abi.Int
  }
  let result = self.new_vreg(class)
  let inst = @instr.VCodeInst::new(Load(ty, offset))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(addr))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::store(
  self : VCodeBuilder,
  ty : @instr.MemType,
  addr : @abi.VReg,
  value : @abi.VReg,
  offset : Int,
) -> Unit {
  let inst = @instr.VCodeInst::new(Store(ty, offset))
  inst.add_use(Virtual(addr))
  inst.add_use(Virtual(value))
  self.emit(inst)
}

// ============ Moves and Constants ============

///|
pub fn VCodeBuilder::mov(self : VCodeBuilder, src : @abi.VReg) -> @abi.VReg {
  let result = self.new_vreg(src.class)
  let inst = @instr.VCodeInst::new(Move)
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(src))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::iconst(self : VCodeBuilder, value : Int64) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(LoadConst(value))
  inst.add_def({ reg: Virtual(result) })
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fconst(self : VCodeBuilder, value : Double) -> @abi.VReg {
  // This builder method defaults to F64
  let result = self.new_vreg(Float64)
  let bits = value.reinterpret_as_int64()
  let inst = @instr.VCodeInst::new(LoadConstF64(bits))
  inst.add_def({ reg: Virtual(result) })
  self.emit(inst)
  result
}

// ============ Comparisons ============

///|
pub fn VCodeBuilder::cmp(
  self : VCodeBuilder,
  kind : @instr.CmpKind,
  a : @abi.VReg,
  b : @abi.VReg,
  is_64? : Bool = true,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(Cmp(kind, is_64))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

///|
pub fn VCodeBuilder::fcmp(
  self : VCodeBuilder,
  kind : @instr.FCmpKind,
  a : @abi.VReg,
  b : @abi.VReg,
) -> @abi.VReg {
  let result = self.new_vreg(Int)
  let inst = @instr.VCodeInst::new(FCmp(kind))
  inst.add_def({ reg: Virtual(result) })
  inst.add_use(Virtual(a))
  inst.add_use(Virtual(b))
  self.emit(inst)
  result
}

// ============ Terminators ============

///|
pub fn VCodeBuilder::jump(
  self : VCodeBuilder,
  target : @block.VCodeBlock,
  args? : Array[@abi.VReg] = [],
) -> Unit {
  if self.current_block is Some(block) {
    let regs : Array[@abi.Reg] = []
    for v in args {
      regs.push(@abi.Virtual(v))
    }
    block.set_terminator(@instr.VCodeTerminator::Jump(target.id, regs))
  }
}

///|
pub fn VCodeBuilder::branch(
  self : VCodeBuilder,
  cond : @abi.VReg,
  then_block : @block.VCodeBlock,
  else_block : @block.VCodeBlock,
) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(
      @instr.VCodeTerminator::Branch(
        Virtual(cond),
        then_block.id,
        else_block.id,
      ),
    )
  }
}

///|
pub fn VCodeBuilder::return_(
  self : VCodeBuilder,
  values : Array[@abi.VReg],
) -> Unit {
  if self.current_block is Some(block) {
    let regs : Array[@abi.Reg] = []
    for v in values {
      regs.push(Virtual(v))
    }
    block.set_terminator(@instr.VCodeTerminator::Return(regs))
  }
}

///|
pub fn VCodeBuilder::trap(self : VCodeBuilder, msg : String) -> Unit {
  if self.current_block is Some(block) {
    block.set_terminator(@instr.VCodeTerminator::Trap(msg))
  }
}
