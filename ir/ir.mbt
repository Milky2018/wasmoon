// Intermediate Representation (IR) for WebAssembly
// Based on SSA (Static Single Assignment) form, similar to Cranelift's CLIF

///|
/// IR Value - represents a virtual register in SSA form
/// Each value is defined exactly once and can be used multiple times
pub(all) struct Value {
  id : Int // Unique identifier within a function
  ty : Type // The type of this value
} derive(Show)

///|
fn Value::new(id : Int, ty : Type) -> Value {
  { id, ty }
}

///|
/// IR Type system - corresponds to WASM value types
pub enum Type {
  I32
  I64
  F32
  F64
  FuncRef
  ExternRef
} derive(Show)

///|
/// Convert from WASM ValueType to IR Type
pub fn Type::from_wasm(wasm_type : @types.ValueType) -> Type {
  match wasm_type {
    I32 => Type::I32
    I64 => Type::I64
    F32 => Type::F32
    F64 => Type::F64
    FuncRef => Type::FuncRef
    ExternRef => Type::ExternRef
    _ => Type::I32 // Fallback
  }
}

///|
/// Block - represents a basic block in the control flow graph
/// A basic block is a sequence of instructions with:
/// - One entry point (the first instruction)
/// - One exit point (the last instruction, a terminator)
pub(all) struct Block {
  id : Int // Unique block identifier
  params : Array[(Value, Type)] // Block parameters (for phi nodes)
  instructions : Array[Inst] // Instructions in this block
  mut terminator : Terminator? // How this block ends
} derive(Show)

///|
fn Block::new(id : Int) -> Block {
  { id, params: [], instructions: [], terminator: None }
}

///|
/// Add a parameter to this block (for SSA phi nodes)
pub fn Block::add_param(self : Block, value : Value, ty : Type) -> Unit {
  self.params.push((value, ty))
}

///|
/// Add an instruction to this block
pub fn Block::add_inst(self : Block, inst : Inst) -> Unit {
  self.instructions.push(inst)
}

///|
/// Set the terminator for this block
pub fn Block::set_terminator(self : Block, term : Terminator) -> Unit {
  self.terminator = Some(term)
}

///|
/// Instruction - an SSA instruction that produces a value
pub(all) struct Inst {
  result : Value? // The value produced (None for void instructions)
  opcode : Opcode // The operation
  operands : Array[Value] // Input values
} derive(Show)

///|
fn Inst::new(result : Value?, opcode : Opcode, operands : Array[Value]) -> Inst {
  { result, opcode, operands }
}

///|
/// Opcode - the operation performed by an instruction
pub enum Opcode {
  // Constants
  Iconst(Int64) // Integer constant
  Fconst(Double) // Float constant

  // Integer arithmetic
  Iadd // Integer add
  Isub // Integer subtract
  Imul // Integer multiply
  Sdiv // Signed divide
  Udiv // Unsigned divide
  Srem // Signed remainder
  Urem // Unsigned remainder

  // Bitwise operations
  Band // Bitwise and
  Bor // Bitwise or
  Bxor // Bitwise xor
  Bnot // Bitwise not
  Ishl // Shift left
  Sshr // Signed shift right
  Ushr // Unsigned shift right
  Rotl // Rotate left
  Rotr // Rotate right

  // Comparisons (return i32 0 or 1)
  Icmp(IntCC) // Integer compare

  // Floating point arithmetic
  Fadd // Float add
  Fsub // Float subtract
  Fmul // Float multiply
  Fdiv // Float divide
  Fmin // Float minimum
  Fmax // Float maximum

  // Floating point comparisons
  Fcmp(FloatCC) // Float compare

  // Floating point unary
  Fneg // Float negate
  Fabs // Float absolute value
  Fsqrt // Float square root
  Fceil // Float ceiling
  Ffloor // Float floor
  Ftrunc // Float truncate
  Fnearest // Float nearest

  // Conversions
  Ireduce // Reduce integer width (e.g., i64 -> i32)
  Sextend // Sign extend (e.g., i32 -> i64)
  Uextend // Zero extend (e.g., i32 -> i64)
  Fpromote // Promote float (f32 -> f64)
  Fdemote // Demote float (f64 -> f32)
  FcvtToSint // Float to signed int
  FcvtToUint // Float to unsigned int
  SintToFcvt // Signed int to float
  UintToFcvt // Unsigned int to float
  Bitcast // Reinterpret bits

  // Memory operations
  Load(Type, Int) // Load from memory (type, offset)
  Store(Type, Int) // Store to memory (type, offset)

  // Misc
  Select // Conditional select (cond ? a : b)
  Copy // Copy value (for register allocation)

  // Function calls
  Call(Int) // Direct call (function index)
  CallIndirect(Int) // Indirect call (type index)
} derive(Show)

///|
/// Integer comparison condition codes
pub enum IntCC {
  Eq // Equal
  Ne // Not equal
  Slt // Signed less than
  Sle // Signed less than or equal
  Sgt // Signed greater than
  Sge // Signed greater than or equal
  Ult // Unsigned less than
  Ule // Unsigned less than or equal
  Ugt // Unsigned greater than
  Uge // Unsigned greater than or equal
} derive(Show)

///|
/// Floating point comparison condition codes
pub enum FloatCC {
  Eq // Equal (ordered)
  Ne // Not equal (unordered)
  Lt // Less than (ordered)
  Le // Less than or equal (ordered)
  Gt // Greater than (ordered)
  Ge // Greater than or equal (ordered)
} derive(Show)

///|
/// Terminator - how a basic block ends
pub enum Terminator {
  // Unconditional jump
  Jump(Int, Array[Value]) // target block, arguments

  // Conditional branch
  Brz(Value, Int, Int) // condition, true block, false block
  Brnz(Value, Int, Int) // condition, true block, false block

  // Multi-way branch (for br_table)
  BrTable(Value, Array[Int], Int) // index, targets, default

  // Return from function
  Return(Array[Value]) // return values

  // Trap/Unreachable
  Trap(String) // trap reason
} derive(Show)

///|
/// Function - a complete IR function
pub(all) struct Function {
  name : String
  params : Array[(Value, Type)] // Function parameters
  results : Array[Type] // Return types
  blocks : Array[Block] // Basic blocks (block 0 is entry)
  mut next_value_id : Int // For generating unique value IDs
  mut next_block_id : Int // For generating unique block IDs
} derive(Show)

///|
pub fn Function::new(name : String) -> Function {
  {
    name,
    params: [],
    results: [],
    blocks: [],
    next_value_id: 0,
    next_block_id: 0,
  }
}

///|
/// Create a new value with a unique ID
pub fn Function::new_value(self : Function, ty : Type) -> Value {
  let id = self.next_value_id
  self.next_value_id = self.next_value_id + 1
  Value::new(id, ty)
}

///|
/// Create a new basic block
pub fn Function::new_block(self : Function) -> Block {
  let id = self.next_block_id
  self.next_block_id = self.next_block_id + 1
  let block = Block::new(id)
  self.blocks.push(block)
  block
}

///|
/// Add a parameter to the function
pub fn Function::add_param(self : Function, ty : Type) -> Value {
  let v = self.new_value(ty)
  self.params.push((v, ty))
  v
}

///|
/// Add a result type to the function
pub fn Function::add_result(self : Function, ty : Type) -> Unit {
  self.results.push(ty)
}
