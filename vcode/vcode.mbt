// VCode - Virtual-register code representation
// A low-level IR that is closer to machine code than the high-level IR
//
// VCode is structured with traditional basic blocks, where each block is
// terminated by an unconditional branch, conditional branch, or return.
// Register slots can refer to virtual registers in addition to physical registers.

// ============ Virtual Registers ============

///|
/// Virtual register - an abstract register before register allocation
pub(all) struct VReg {
  id : Int
  class : RegClass // Which register class this vreg belongs to
}

///|
fn VReg::to_string(self : VReg) -> String {
  match self.class {
    Int => "v\{self.id}"
    Float => "f\{self.id}"
  }
}

///|
pub impl Show for VReg with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Register class - categorizes registers by their purpose
pub(all) enum RegClass {
  Int // Integer/general-purpose registers
  Float // Floating-point registers
}

///|
fn RegClass::to_string(self : RegClass) -> String {
  match self {
    Int => "int"
    Float => "float"
  }
}

///|
pub impl Show for RegClass with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Physical register - a real machine register
pub(all) struct PReg {
  index : Int // Register number (e.g., x0-x30 for AArch64)
  class : RegClass
}

///|
fn PReg::to_string(self : PReg) -> String {
  match self.class {
    Int => "x\{self.index}"
    Float => "d\{self.index}"
  }
}

///|
pub impl Show for PReg with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A register reference - either virtual or physical
pub enum Reg {
  Virtual(VReg)
  Physical(PReg)
}

///|
fn Reg::to_string(self : Reg) -> String {
  match self {
    Virtual(vreg) => vreg.to_string()
    Physical(preg) => preg.to_string()
  }
}

///|
pub impl Show for Reg with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A writable register reference (for instruction destinations)
pub(all) struct Writable {
  reg : Reg
}

///|
fn Writable::to_string(self : Writable) -> String {
  self.reg.to_string()
}

///|
pub impl Show for Writable with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Operands ============

///|
/// Operand - an instruction operand with constraints
pub(all) struct Operand {
  reg : VReg
  kind : OperandKind
  constraint : OperandConstraint
}

///|
/// Operand kind - how the operand is used
#warnings("-unused_constructor")
pub enum OperandKind {
  Use // Read from
  Def // Written to
  UseDef // Both read and written
}

///|
#warnings("-unused_value")
fn OperandKind::to_string(self : OperandKind) -> String {
  match self {
    Use => "use"
    Def => "def"
    UseDef => "use-def"
  }
}

///|
/// Operand constraint - register allocation constraint
#warnings("-unused_constructor")
pub enum OperandConstraint {
  Any // Any register in the class
  Fixed(PReg) // Must be this specific physical register
  Reuse(Int) // Must reuse the same register as operand at index
}

///|
#warnings("-unused_value")
fn OperandConstraint::to_string(self : OperandConstraint) -> String {
  match self {
    Any => "any"
    Fixed(preg) => "fixed(\{preg})"
    Reuse(idx) => "reuse(\{idx})"
  }
}

// ============ VCode Structure ============

///|
/// VCode block - a basic block in VCode
pub(all) struct VCodeBlock {
  id : Int
  insts : Array[VCodeInst] // Instructions in this block
  params : Array[VReg] // Block parameters
  mut terminator : VCodeTerminator? // How the block ends
}

///|
pub fn VCodeBlock::new(id : Int) -> VCodeBlock {
  { id, insts: [], params: [], terminator: None }
}

///|
pub fn VCodeBlock::add_inst(self : VCodeBlock, inst : VCodeInst) -> Unit {
  self.insts.push(inst)
}

///|
pub fn VCodeBlock::set_terminator(
  self : VCodeBlock,
  term : VCodeTerminator,
) -> Unit {
  self.terminator = Some(term)
}

///|
/// VCode instruction - a machine-level instruction with virtual registers
pub(all) struct VCodeInst {
  opcode : VCodeOpcode
  defs : Array[Writable] // Registers defined (written)
  uses : Array[Reg] // Registers used (read)
}

///|
pub fn VCodeInst::new(opcode : VCodeOpcode) -> VCodeInst {
  { opcode, defs: [], uses: [] }
}

///|
pub fn VCodeInst::add_def(self : VCodeInst, reg : Writable) -> Unit {
  self.defs.push(reg)
}

///|
pub fn VCodeInst::add_use(self : VCodeInst, reg : Reg) -> Unit {
  self.uses.push(reg)
}

///|
fn VCodeInst::to_string(self : VCodeInst) -> String {
  let mut result = ""
  // Print definitions
  if self.defs.length() > 0 {
    for i, def in self.defs {
      if i > 0 {
        result = result + ", "
      }
      result = result + def.to_string()
    }
    result = result + " = "
  }
  // Print opcode
  result = result + self.opcode.to_string()
  // Print uses
  if self.uses.length() > 0 {
    result = result + " "
    for i, use_ in self.uses {
      if i > 0 {
        result = result + ", "
      }
      result = result + use_.to_string()
    }
  }
  result
}

///|
pub impl Show for VCodeInst with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Shift type for shifted operand instructions
pub(all) enum ShiftType {
  Lsl // Logical shift left
  Lsr // Logical shift right
  Asr // Arithmetic shift right
}

///|
fn ShiftType::to_string(self : ShiftType) -> String {
  match self {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
}

///|
pub impl Show for ShiftType with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// VCode opcode - machine-level operation (target-independent subset)
#warnings("-unused_constructor")
pub enum VCodeOpcode {
  // Integer arithmetic
  Add
  AddImm(Int) // ADD Xd, Xn, #imm (immediate add)
  Sub
  Mul
  SDiv
  UDiv
  // Bitwise operations
  And
  Or
  Xor
  Shl
  AShr // Arithmetic shift right
  LShr // Logical shift right
  // Floating-point operations
  FAdd
  FSub
  FMul
  FDiv
  // Memory operations
  Load(MemType, Int) // type, offset
  Store(MemType, Int) // type, offset
  // Narrow load operations (8/16-bit with sign/zero extension)
  Load8S(Int) // Load 8-bit signed, sign-extend to 32/64-bit (offset)
  Load8U(Int) // Load 8-bit unsigned, zero-extend to 32/64-bit (offset)
  Load16S(Int) // Load 16-bit signed, sign-extend to 32/64-bit (offset)
  Load16U(Int) // Load 16-bit unsigned, zero-extend to 32/64-bit (offset)
  Load32S(Int) // Load 32-bit signed, sign-extend to 64-bit (offset)
  Load32U(Int) // Load 32-bit unsigned, zero-extend to 64-bit (offset)
  // Moves
  Move
  LoadConst(Int64) // Load immediate
  LoadConstF32(Int) // Load f32 immediate (stored as bits)
  LoadConstF64(Int64) // Load f64 immediate (stored as bits)
  // Comparisons (result is 0 or 1)
  Cmp(CmpKind)
  FCmp(FCmpKind)
  // Conversions
  Extend(ExtendKind)
  Truncate
  IntToFloat
  FloatToInt
  // Special
  Nop
  // Memory bounds check (for WASM linear memory safety)
  // BoundsCheck(offset, access_size): checks wasm_addr + offset + access_size <= memory_size
  // Uses: [wasm_addr], traps if out of bounds
  BoundsCheck(Int, Int)
  // AArch64-specific: shifted operand instructions
  // These combine an arithmetic/logical op with a shift in one instruction
  AddShifted(ShiftType, Int) // ADD Xd, Xn, Xm, shift #amount
  SubShifted(ShiftType, Int) // SUB Xd, Xn, Xm, shift #amount
  AndShifted(ShiftType, Int) // AND Xd, Xn, Xm, shift #amount
  OrShifted(ShiftType, Int) // ORR Xd, Xn, Xm, shift #amount
  XorShifted(ShiftType, Int) // EOR Xd, Xn, Xm, shift #amount
  // AArch64-specific: multiply-accumulate instructions
  Madd // Xd = Xa + Xn * Xm (3 uses: acc, src1, src2)
  Msub // Xd = Xa - Xn * Xm (3 uses: acc, src1, src2)
  Mneg // Xd = -(Xn * Xm) (2 uses: src1, src2)
  // Function calls
  // CallIndirect: call through a function pointer in a register
  // Uses: [func_ptr, arg0, arg1, ...]
  // Defs: [result] (if has_result)
  // Parameters: num_args, has_result
  CallIndirect(Int, Bool)
  // Stack operations for spilling
  // StackLoad(offset): Load from [SP + offset] into the def register
  // StackStore(offset): Store the use register to [SP + offset]
  StackLoad(Int)
  StackStore(Int)
}

///|
fn VCodeOpcode::to_string(self : VCodeOpcode) -> String {
  match self {
    Add => "add"
    AddImm(imm) => "add #\{imm}"
    Sub => "sub"
    Mul => "mul"
    SDiv => "sdiv"
    UDiv => "udiv"
    And => "and"
    Or => "or"
    Xor => "xor"
    Shl => "shl"
    AShr => "ashr"
    LShr => "lshr"
    FAdd => "fadd"
    FSub => "fsub"
    FMul => "fmul"
    FDiv => "fdiv"
    Load(ty, offset) => "load.\{ty} +\{offset}"
    Store(ty, offset) => "store.\{ty} +\{offset}"
    Load8S(offset) => "load8s +\{offset}"
    Load8U(offset) => "load8u +\{offset}"
    Load16S(offset) => "load16s +\{offset}"
    Load16U(offset) => "load16u +\{offset}"
    Load32S(offset) => "load32s +\{offset}"
    Load32U(offset) => "load32u +\{offset}"
    Move => "mov"
    LoadConst(v) => "ldi \{v}"
    LoadConstF32(v) => {
      // Convert i32 bits to f32 value for display
      let f = Float::reinterpret_from_uint(v.reinterpret_as_uint())
      "ldf \{f}"
    }
    LoadConstF64(v) => {
      // Convert i64 bits to f64 value for display
      let f = v.reinterpret_as_double()
      "ldf \{f}"
    }
    Cmp(kind) => "cmp.\{kind}"
    FCmp(kind) => "fcmp.\{kind}"
    Extend(kind) => "extend.\{kind}"
    Truncate => "trunc"
    IntToFloat => "i2f"
    FloatToInt => "f2i"
    Nop => "nop"
    BoundsCheck(offset, size) => "bounds_check +\{offset}, \{size}"
    // AArch64-specific
    AddShifted(shift, amount) => "add.\{shift} #\{amount}"
    SubShifted(shift, amount) => "sub.\{shift} #\{amount}"
    AndShifted(shift, amount) => "and.\{shift} #\{amount}"
    OrShifted(shift, amount) => "or.\{shift} #\{amount}"
    XorShifted(shift, amount) => "xor.\{shift} #\{amount}"
    Madd => "madd"
    Msub => "msub"
    Mneg => "mneg"
    CallIndirect(num_args, has_result) => {
      let ret_ty = if has_result { "i64" } else { "void" }
      "call_indirect(\{num_args}) -> \{ret_ty}"
    }
    StackLoad(offset) => "stack_load [sp+\{offset}]"
    StackStore(offset) => "stack_store [sp+\{offset}]"
  }
}

///|
pub impl Show for VCodeOpcode with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Memory type for load/store
pub enum MemType {
  I8
  I16
  I32
  I64
  F32
  F64
}

///|
fn MemType::to_string(self : MemType) -> String {
  match self {
    I8 => "i8"
    I16 => "i16"
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
  }
}

///|
pub impl Show for MemType with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Comparison kind for integer comparisons
pub(all) enum CmpKind {
  Eq
  Ne
  Slt
  Sle
  Sgt
  Sge
  Ult
  Ule
  Ugt
  Uge
}

///|
fn CmpKind::to_string(self : CmpKind) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Slt => "slt"
    Sle => "sle"
    Sgt => "sgt"
    Sge => "sge"
    Ult => "ult"
    Ule => "ule"
    Ugt => "ugt"
    Uge => "uge"
  }
}

///|
pub impl Show for CmpKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Comparison kind for float comparisons
pub enum FCmpKind {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
}

///|
fn FCmpKind::to_string(self : FCmpKind) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Lt => "lt"
    Le => "le"
    Gt => "gt"
    Ge => "ge"
  }
}

///|
pub impl Show for FCmpKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Extend kind - how to extend a value
#warnings("-unused_constructor")
pub enum ExtendKind {
  Signed8To32
  Signed8To64
  Signed16To32
  Signed16To64
  Signed32To64
  Unsigned8To32
  Unsigned8To64
  Unsigned16To32
  Unsigned16To64
  Unsigned32To64
}

///|
fn ExtendKind::to_string(self : ExtendKind) -> String {
  match self {
    Signed8To32 => "s8_32"
    Signed8To64 => "s8_64"
    Signed16To32 => "s16_32"
    Signed16To64 => "s16_64"
    Signed32To64 => "s32_64"
    Unsigned8To32 => "u8_32"
    Unsigned8To64 => "u8_64"
    Unsigned16To32 => "u16_32"
    Unsigned16To64 => "u16_64"
    Unsigned32To64 => "u32_64"
  }
}

///|
pub impl Show for ExtendKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// VCode terminator - how a block ends
pub enum VCodeTerminator {
  Jump(Int) // Unconditional jump to block
  Branch(Reg, Int, Int) // Conditional: condition, then-block, else-block
  Return(Array[Reg]) // Return with values
  Trap(String) // Trap with message
}

///|
fn VCodeTerminator::to_string(self : VCodeTerminator) -> String {
  match self {
    Jump(target) => "jump block\{target}"
    Branch(cond, then_b, else_b) =>
      "branch \{cond}, block\{then_b}, block\{else_b}"
    Return(values) => {
      let mut result = "ret"
      if values.length() > 0 {
        result = result + " "
        for i, v in values {
          if i > 0 {
            result = result + ", "
          }
          result = result + v.to_string()
        }
      }
      result
    }
    Trap(msg) => "trap \"\{msg}\""
  }
}

///|
pub impl Show for VCodeTerminator with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ VCode Function ============

///|
/// VCode function - a complete function in VCode form
pub(all) struct VCodeFunction {
  name : String
  params : Array[VReg] // Function parameters
  results : Array[RegClass] // Result types (for return value allocation)
  blocks : Array[VCodeBlock]
  mut next_vreg_id : Int
}

///|
pub fn VCodeFunction::new(name : String) -> VCodeFunction {
  { name, params: [], results: [], blocks: [], next_vreg_id: 0 }
}

///|
pub fn VCodeFunction::new_vreg(self : VCodeFunction, class : RegClass) -> VReg {
  let id = self.next_vreg_id
  self.next_vreg_id = id + 1
  { id, class }
}

///|
pub fn VCodeFunction::add_param(self : VCodeFunction, class : RegClass) -> VReg {
  let vreg = self.new_vreg(class)
  self.params.push(vreg)
  vreg
}

///|
pub fn VCodeFunction::add_result(
  self : VCodeFunction,
  class : RegClass,
) -> Unit {
  self.results.push(class)
}

///|
pub fn VCodeFunction::new_block(self : VCodeFunction) -> VCodeBlock {
  let id = self.blocks.length()
  let block = VCodeBlock::new(id)
  self.blocks.push(block)
  block
}

///|
pub fn VCodeFunction::print(self : VCodeFunction) -> String {
  let mut result = "vcode \{self.name}("
  // Parameters
  for i, param in self.params {
    if i > 0 {
      result = result + ", "
    }
    result = result + param.to_string() + ":" + param.class.to_string()
  }
  result = result + ")"
  // Results
  if self.results.length() > 0 {
    result = result + " -> "
    if self.results.length() == 1 {
      result = result + self.results[0].to_string()
    } else {
      result = result + "("
      for i, r in self.results {
        if i > 0 {
          result = result + ", "
        }
        result = result + r.to_string()
      }
      result = result + ")"
    }
  }
  result = result + " {\n"
  // Blocks
  for block in self.blocks {
    result = result + "block\{block.id}"
    if block.params.length() > 0 {
      result = result + "("
      for i, param in block.params {
        if i > 0 {
          result = result + ", "
        }
        result = result + param.to_string() + ":" + param.class.to_string()
      }
      result = result + ")"
    }
    result = result + ":\n"
    // Instructions
    for inst in block.insts {
      result = result + "    \{inst}\n"
    }
    // Terminator
    match block.terminator {
      Some(term) => result = result + "    \{term}\n"
      None => ()
    }
  }
  result = result + "}\n"
  result
}

///|
pub impl Show for VCodeFunction with output(self, logger) {
  logger.write_string(self.print())
}
