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
pub(all) enum Type {
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
    // Typed function references are represented as I64 (function index)
    RefFuncTyped(_) | RefNullFuncTyped(_) => Type::I64
    RefFunc => Type::I64
    RefExtern => Type::I64
    // GC reference types - all use 64-bit representation (heap index)
    NullFuncRef => Type::FuncRef
    NullExternRef => Type::ExternRef
    AnyRef | NullRef | ExnRef | NullExnRef => Type::I64
    // Struct and array references - use I64 (heap index)
    RefStruct(_) | RefNullStruct(_) | RefArray(_) | RefNullArray(_) => Type::I64
    // i31 references - use I64 (tagged small integer)
    RefI31 | RefNullI31 => Type::I64
    // Eq and any abstract types
    RefEq | RefNullEq | RefAny => Type::I64
    _ => Type::I32 // Fallback for V128 or future types
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
  result : Value? // The primary value produced (None for void instructions)
  extra_results : Array[Value] // Additional results for multi-value returns (e.g., call returning multiple values)
  mut opcode : Opcode // The operation
  operands : Array[Value] // Input values
} derive(Show)

///|
fn Inst::new(result : Value?, opcode : Opcode, operands : Array[Value]) -> Inst {
  { result, extra_results: [], opcode, operands }
}

///|
/// Create an instruction with multiple results (for multi-value call)
pub fn Inst::new_multi(
  results : Array[Value],
  opcode : Opcode,
  operands : Array[Value],
) -> Inst {
  let (result, extra_results) = if results.length() == 0 {
    (None, [])
  } else {
    let extra : Array[Value] = []
    for i in 1..<results.length() {
      extra.push(results[i])
    }
    (Some(results[0]), extra)
  }
  { result, extra_results, opcode, operands }
}

///|
/// Get all results of this instruction
pub fn Inst::all_results(self : Inst) -> Array[Value] {
  let results : Array[Value] = []
  if self.result is Some(v) {
    results.push(v)
  }
  for v in self.extra_results {
    results.push(v)
  }
  results
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

  // Bit counting operations
  Clz // Count leading zeros
  Ctz // Count trailing zeros
  Popcnt // Population count (number of 1 bits)

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
  FcvtToSint // Float to signed int (trapping)
  FcvtToUint // Float to unsigned int (trapping)
  FcvtToSintSat // Float to signed int (saturating)
  FcvtToUintSat // Float to unsigned int (saturating)
  SintToFcvt // Signed int to float
  UintToFcvt // Unsigned int to float
  Bitcast // Reinterpret bits

  // In-place sign extension (like Cranelift's ireduce + sextend)
  // These sign-extend the low N bits to fill the full register
  Sextend8 // Sign extend from 8 bits (i32 or i64)
  Sextend16 // Sign extend from 16 bits (i32 or i64)
  Sextend32 // Sign extend from 32 bits (i64 only)

  // Memory operations
  Load(Type, Int) // Load from memory (type, offset)
  Store(Type, Int) // Store to memory (type, offset)

  // Narrow memory operations (8/16-bit with sign/zero extension)
  Load8S(Type, Int) // Load 8-bit signed and extend to Type (offset)
  Load8U(Type, Int) // Load 8-bit unsigned and extend to Type (offset)
  Load16S(Type, Int) // Load 16-bit signed and extend to Type (offset)
  Load16U(Type, Int) // Load 16-bit unsigned and extend to Type (offset)
  Load32S(Int) // Load 32-bit signed and extend to i64 (offset)
  Load32U(Int) // Load 32-bit unsigned and extend to i64 (offset)
  Store8(Int) // Store low 8 bits (offset)
  Store16(Int) // Store low 16 bits (offset)
  Store32(Int) // Store low 32 bits of i64 (offset)

  // Memory management
  MemoryGrow(Int?) // Grow memory by delta pages, returns previous size or -1. Int? = max_pages (None = no limit)
  MemorySize // Get current memory size in pages
  MemoryFill // Fill memory region with a byte value (dst, val, size)
  MemoryCopy // Copy memory region (dst, src, size)

  // Misc
  Select // Conditional select (cond ? a : b)
  Copy // Copy value (for register allocation)

  // Table operations (for reference types)
  TableGet(Int) // Get element from table (table index)
  TableSet(Int) // Set element in table (table index)
  TableSize(Int) // Get current size of table (table index)
  TableGrow(Int) // Grow table, returns previous size or -1 (table index)

  // Global operations
  GlobalGet(Int) // Get global variable value (global index)
  GlobalSet(Int) // Set global variable value (global index)

  // Function calls
  Call(Int) // Direct call (function index)
  CallIndirect(Int, Int) // Indirect call (type index, table index)
  CallRef(Int) // Call through function reference (type index)
  ReturnCall(Int) // Tail call (function index)
  ReturnCallIndirect(Int, Int) // Tail call indirect (type index, table index)
  ReturnCallRef(Int) // Tail call through function reference (type index)

  // Function reference - returns tagged function pointer for storing in tables
  GetFuncRef(Int) // Get function reference (function index) - returns tagged func_ptr

  // Raw pointer operations (for trampolines, no bounds checking)
  // These follow Cranelift's approach for host code generation
  LoadPtr(Type) // Load from pointer+offset (operand 0 = base ptr)
  StorePtr(Type) // Store to pointer+offset (operand 0 = base ptr, operand 1 = value)

  // Raw function pointer call (for trampolines)
  // CallPtr(num_args, num_results) - call via function pointer
  // operand 0 = function pointer, operands 1..n = vmctx + args
  CallPtr(Int, Int)

  // GC operations - struct
  StructNew(Int) // Allocate struct (type index) - operands are field values
  StructNewDefault(Int) // Allocate struct with default values (type index)
  StructGet(Int, Int) // Get struct field (type index, field index) - operand is structref
  StructGetS(Int, Int, Int) // Get struct field signed-extended (type index, field index, byte_width: 1=i8, 2=i16)
  StructGetU(Int, Int, Int) // Get struct field zero-extended (type index, field index, byte_width: 1=i8, 2=i16)
  StructSet(Int, Int) // Set struct field (type index, field index) - operands: structref, value

  // GC operations - array
  ArrayNew(Int) // Allocate array (type index) - operands: init_value, length
  ArrayNewDefault(Int) // Allocate array with default values (type index) - operand: length
  ArrayNewFixed(Int, Int) // Allocate fixed-size array (type index, length) - operands are element values
  ArrayGet(Int) // Get array element (type index) - operands: arrayref, index
  ArrayGetS(Int, Int) // Get array element signed-extended (type index, byte_width: 1=i8, 2=i16)
  ArrayGetU(Int, Int) // Get array element zero-extended (type index, byte_width: 1=i8, 2=i16)
  ArraySet(Int) // Set array element (type index) - operands: arrayref, index, value
  ArrayLen // Get array length - operand: arrayref
  ArrayFill(Int) // Fill array (type index) - operands: arrayref, offset, value, count
  ArrayCopy(Int, Int) // Copy array (dst_type_idx, src_type_idx) - operands: dst, dst_offset, src, src_offset, count

  // GC operations - i31
  I31New // Create i31 reference - operand: i32 value
  I31GetS // Get i31 value sign-extended - operand: i31ref
  I31GetU // Get i31 value zero-extended - operand: i31ref

  // GC operations - type checking/casting
  RefTest(Int, Bool) // Test if reference is of type (type index, nullable) - operand: ref
  RefCast(Int, Bool) // Cast reference to type (type index, nullable) - operand: ref

  // GC operations - type conversions
  AnyConvertExtern // Convert externref to anyref - operand: externref
  ExternConvertAny // Convert anyref to externref - operand: anyref

  // GC operations - reference equality
  RefEq // ref.eq - compare two references for equality - operands: ref1, ref2
} derive(Show)

///|
/// Integer comparison condition codes
pub(all) enum IntCC {
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
pub(all) enum FloatCC {
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
