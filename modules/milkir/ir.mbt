// MilkIR intermediate representation.
// Based on SSA (Static Single Assignment) form

///|
/// IR Value - represents a virtual register in SSA form
/// Each value is defined exactly once and can be used multiple times
pub struct Value {
  id : Int // Unique identifier within a function
  ty : Type // The type of this value
} derive(Eq, Debug, Hash)

///|
pub fn Value::Value(id : Int, ty : Type) -> Value {
  { id, ty }
}

///|
/// IR type system for scalar, vector, pointer, and reference-typed values.
pub(all) enum Type {
  I32
  I64
  F32
  F64
  V128 // SIMD 128-bit vector
  Ptr
  Ref
  CallableRef
  OpaqueRef
} derive(Debug, Eq, Hash)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for Type with fn output(self, logger) {
  logger.write_string(
    match self {
      I32 => "i32"
      I64 => "i64"
      F32 => "f32"
      F64 => "f64"
      V128 => "v128"
      Ptr => "ptr"
      Ref => "ref"
      CallableRef => "callable_ref"
      OpaqueRef => "opaque_ref"
    },
  )
}

///|
pub struct Signature {
  params : Array[Type]
  results : Array[Type]
} derive(Eq, Debug, Hash)

///|
pub fn Signature::Signature(
  params : Array[Type],
  results : Array[Type],
) -> Signature {
  { params, results }
}

///|
pub struct ExternalSymbol {
  name : String
} derive(Eq, Debug, Hash)

///|
pub fn ExternalSymbol::ExternalSymbol(name : String) -> ExternalSymbol {
  { name, }
}

///|
pub struct ExtOp {
  dialect : String
  opcode : String
  immediates : FixedArray[Int]
} derive(Debug)

///|
pub(all) struct ExtOpDescriptor {
  dialect : String
  opcode : String
  min_immediates : Int
  max_immediates : Int
} derive(Eq, Debug, Hash)

///|
pub fn ExtOpDescriptor::ExtOpDescriptor(
  dialect : String,
  opcode : String,
  immediate_count : Int,
) -> ExtOpDescriptor {
  {
    dialect,
    opcode,
    min_immediates: immediate_count,
    max_immediates: immediate_count,
  }
}

///|
pub fn ExtOpDescriptor::with_immediate_range(
  dialect : String,
  opcode : String,
  min_immediates : Int,
  max_immediates : Int,
) -> ExtOpDescriptor {
  { dialect, opcode, min_immediates, max_immediates }
}

///|
pub fn ExtOpDescriptor::accepts_immediate_count(
  self : ExtOpDescriptor,
  count : Int,
) -> Bool {
  count >= self.min_immediates && count <= self.max_immediates
}

///|
pub fn ExtOpDescriptor::expected_immediate_count(
  self : ExtOpDescriptor,
) -> String {
  if self.min_immediates == self.max_immediates {
    "\{self.min_immediates}"
  } else {
    "\{self.min_immediates}..\{self.max_immediates}"
  }
}

///|
pub fn ExtOp::ExtOp(
  dialect : String,
  opcode : String,
  immediates : FixedArray[Int],
) -> ExtOp {
  { dialect, opcode, immediates }
}

///|
pub fn ExtOp::matches_descriptor(
  self : ExtOp,
  descriptor : ExtOpDescriptor,
) -> Bool {
  self.dialect == descriptor.dialect &&
  self.opcode == descriptor.opcode &&
  descriptor.accepts_immediate_count(self.immediates.length())
}

///|
pub impl Eq for ExtOp with fn equal(self, other) {
  if self.dialect != other.dialect || self.opcode != other.opcode {
    return false
  }
  if self.immediates.length() != other.immediates.length() {
    return false
  }
  for i in 0..<self.immediates.length() {
    if self.immediates[i] != other.immediates[i] {
      return false
    }
  }
  true
}

///|
pub impl Hash for ExtOp with fn hash_combine(self, hasher) {
  self.dialect.hash_combine(hasher)
  self.opcode.hash_combine(hasher)
  self.immediates.length().hash_combine(hasher)
  for imm in self.immediates {
    imm.hash_combine(hasher)
  }
}

///|
pub struct StackSlot {
  id : Int
  size : Int
  align : Int
} derive(Eq, Debug, Hash)

///|
pub(all) enum Metadata {
  SourceLoc(String)
  Comment(String)
} derive(Eq, Debug)

///|
/// Block - represents a basic block in the control flow graph
/// A basic block is a sequence of instructions with:
/// - One entry point (the first instruction)
/// - One exit point (the last instruction, a terminator)
pub struct Block {
  id : Int // Unique block identifier
  params : Array[(Value, Type)] // Block parameters (for phi nodes)
  instructions : Array[Inst] // Instructions in this block
  mut terminator : Terminator? // How this block ends
} derive(Debug)

///|
fn Block::Block(id : Int) -> Block {
  { id, params: [], instructions: [], terminator: None }
}

///|
fn Block::new_with_params(id : Int, params : Array[Value]) -> Block {
  let block = Block(id)
  for param in params {
    block.add_param(param, param.ty)
  }
  block
}

///|
/// Add a parameter to this block (for SSA phi nodes)
fn Block::add_param(self : Block, value : Value, ty : Type) -> Unit {
  self.params.push((value, ty))
}

///|
/// Add an instruction to this block
fn Block::add_inst(self : Block, inst : Inst) -> Unit {
  self.instructions.push(inst)
}

///|
pub fn Block::append_inst(self : Block, inst : Inst) -> Unit {
  self.add_inst(inst)
}

///|
/// Set the terminator for this block
pub fn Block::set_terminator(self : Block, term : Terminator) -> Unit {
  self.terminator = Some(term)
}

///|
/// Instruction - an SSA instruction that produces a value
pub struct Inst {
  id : Int
  results : Array[Value] // Values produced (empty for void instructions)
  mut opcode : Opcode // The operation
  args : Array[Value] // Generic MilkIR spelling for operands.
  operands : Array[Value] // Input values
  metadata : Array[Metadata]
} derive(Debug)

///|
/// Hash for CSE/GVN - based on opcode, result types, and operand IDs.
/// Result IDs are definitions rather than part of expression identity.
pub impl Hash for Inst with fn hash_combine(self, hasher) {
  self.opcode.hash_combine(hasher)
  self.results.length().hash_combine(hasher)
  for result in self.results {
    result.ty.hash_combine(hasher)
  }
  for op in self.operands {
    op.id.hash_combine(hasher)
  }
}

///|
/// Eq for CSE/GVN - result types are part of expression identity.
pub impl Eq for Inst with fn equal(self, other) {
  if self.opcode != other.opcode {
    return false
  }
  if self.results.length() != other.results.length() {
    return false
  }
  for i in 0..<self.results.length() {
    if self.results[i].ty != other.results[i].ty {
      return false
    }
  }
  if self.operands.length() != other.operands.length() {
    return false
  }
  for i in 0..<self.operands.length() {
    if self.operands[i].id != other.operands[i].id {
      return false
    }
  }
  true
}

///|
fn Inst::Inst(
  result : Value?,
  opcode : Opcode,
  operands : Array[Value],
) -> Inst {
  let results = match result {
    Some(v) => [v]
    None => []
  }
  { id: -1, results, opcode, args: operands, operands, metadata: [] }
}

///|
/// Create an instruction with multiple results (for multi-value call)
fn Inst::new_multi(
  results : Array[Value],
  opcode : Opcode,
  operands : Array[Value],
) -> Inst {
  { id: -1, results, opcode, args: operands, operands, metadata: [] }
}

///|
fn Inst::new_with_id(
  id : Int,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  { id, results, opcode, args, operands: args, metadata: [] }
}

///|
pub fn Inst::add_metadata(self : Inst, metadata : Metadata) -> Unit {
  self.metadata.push(metadata)
}

///|
/// Get primary result of this instruction (first result or None)
pub fn Inst::first_result(self : Inst) -> Value? {
  if self.results.length() > 0 {
    Some(self.results[0])
  } else {
    None
  }
}

///|
/// Get all results of this instruction
pub fn Inst::all_results(self : Inst) -> Array[Value] {
  self.results
}

///|
/// Opcode - the operation performed by an instruction
pub(all) enum Opcode {
  // Constants
  Iconst(Int64) // Integer constant
  Fconst(Double) // Float constant

  // Integer arithmetic
  Iadd // Integer add
  Isub // Integer subtract
  Imul // Integer multiply
  Umulh // Unsigned multiply high
  Smulh // Signed multiply high
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
  IcmpEq

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

  // In-place sign extension 
  // These sign-extend the low N bits to fill the full register
  Sextend8 // Sign extend from 8 bits (i32 or i64)
  Sextend16 // Sign extend from 16 bits (i32 or i64)
  Sextend32 // Sign extend from 32 bits (i64 only)

  // Misc
  Select // Conditional select (cond ? a : b)
  Copy // Copy value (for register allocation)
  Load
  Store
  StackAddr(StackSlot)

  // Function calls
  Call(ExternalSymbol)
  CallIndirect(Signature)

  // Raw pointer operations (for trampolines, no bounds checking)
  // Used for host code generation
  LoadPtr(Type) // Load from pointer+offset (operand 0 = base ptr)
  StorePtr(Type) // Store to pointer+offset (operand 0 = base ptr, operand 1 = value)
  // Narrow load/store from raw pointer (result_type, bits, signed)
  LoadPtrNarrow(Type, Int, Bool) // Load narrow from pointer+offset, extend to result_type
  StorePtrNarrow(Int) // Store narrow to pointer+offset (bits)

  // Raw function pointer call (for trampolines)
  // CallPtr(num_args, num_results) - call via function pointer
  // operand 0 = function pointer, operands 1..n = context + args
  CallPtr(Int, Int)
  Trap(String)
  Custom(String)

  // Dialect extension operations. The core IR treats these conservatively;
  // dialect-owned packages define the opcode set, builders, validation rules,
  // and lowering behavior.
  Ext(ExtOp)

  // ============================================
  // SIMD operations (V128)
  // ============================================

  // V128 constant - 16 bytes stored as Bytes
  V128Const(Bytes)

  // Splat - replicate scalar to all lanes
  // operand: scalar value, result: v128
  V128Splat8 // i8x16.splat (from i32)
  V128Splat16 // i16x8.splat (from i32)
  V128Splat32 // i32x4.splat (from i32)
  V128Splat64 // i64x2.splat (from i64)
  V128SplatF32 // f32x4.splat (from f32)
  V128SplatF64 // f64x2.splat (from f64)

  // Extract lane - extract scalar from vector
  // operand: v128, result: scalar
  V128ExtractLane8S(Int) // i8x16.extract_lane_s (lane index)
  V128ExtractLane8U(Int) // i8x16.extract_lane_u
  V128ExtractLane16S(Int) // i16x8.extract_lane_s
  V128ExtractLane16U(Int) // i16x8.extract_lane_u
  V128ExtractLane32(Int) // i32x4.extract_lane
  V128ExtractLane64(Int) // i64x2.extract_lane
  V128ExtractLaneF32(Int) // f32x4.extract_lane
  V128ExtractLaneF64(Int) // f64x2.extract_lane

  // Replace lane - replace scalar in vector
  // operands: v128, scalar, result: v128
  V128ReplaceLane8(Int) // i8x16.replace_lane (lane index)
  V128ReplaceLane16(Int) // i16x8.replace_lane
  V128ReplaceLane32(Int) // i32x4.replace_lane
  V128ReplaceLane64(Int) // i64x2.replace_lane
  V128ReplaceLaneF32(Int) // f32x4.replace_lane
  V128ReplaceLaneF64(Int) // f64x2.replace_lane

  // Shuffle - select lanes from two vectors
  // operands: v128, v128, result: v128
  V128Shuffle(FixedArray[Int]) // 16 lane indices (0-31)

  // Swizzle - permute lanes based on indices vector
  // operands: v128 (values), v128 (indices), result: v128
  V128Swizzle

  // Bitwise operations - v128 -> v128
  V128Not
  // Bitwise operations - v128, v128 -> v128
  V128And
  V128AndNot
  V128Or
  V128Xor
  V128Bitselect // operands: v1, v2, mask

  // Any true / All true
  V128AnyTrue // v128 -> i32
  V128AllTrue8 // i8x16.all_true: v128 -> i32
  V128AllTrue16 // i16x8.all_true
  V128AllTrue32 // i32x4.all_true
  V128AllTrue64 // i64x2.all_true

  // Bitmask - extract sign bits
  V128Bitmask8 // i8x16.bitmask: v128 -> i32
  V128Bitmask16 // i16x8.bitmask
  V128Bitmask32 // i32x4.bitmask
  V128Bitmask64 // i64x2.bitmask

  // Integer arithmetic - v128, v128 -> v128
  V128Add8
  V128Add16
  V128Add32
  V128Add64
  V128Sub8
  V128Sub16
  V128Sub32
  V128Sub64
  V128Mul16
  V128Mul32
  V128Mul64

  // Saturating arithmetic
  V128AddSat8S
  V128AddSat8U
  V128AddSat16S
  V128AddSat16U
  V128SubSat8S
  V128SubSat8U
  V128SubSat16S
  V128SubSat16U

  // Min/Max
  V128Min8S
  V128Min8U
  V128Min16S
  V128Min16U
  V128Min32S
  V128Min32U
  V128Max8S
  V128Max8U
  V128Max16S
  V128Max16U
  V128Max32S
  V128Max32U

  // Average
  V128Avgr8U
  V128Avgr16U

  // Unary - v128 -> v128
  V128Abs8
  V128Abs16
  V128Abs32
  V128Abs64
  V128Neg8
  V128Neg16
  V128Neg32
  V128Neg64
  V128Popcnt8

  // Shifts - v128, i32 -> v128
  V128Shl8
  V128Shl16
  V128Shl32
  V128Shl64
  V128Shr8S
  V128Shr8U
  V128Shr16S
  V128Shr16U
  V128Shr32S
  V128Shr32U
  V128Shr64S
  V128Shr64U

  // Comparisons - v128, v128 -> v128 (all lanes compared)
  V128Eq8
  V128Eq16
  V128Eq32
  V128Eq64
  V128Ne8
  V128Ne16
  V128Ne32
  V128Ne64
  V128Lt8S
  V128Lt8U
  V128Lt16S
  V128Lt16U
  V128Lt32S
  V128Lt32U
  V128Lt64S
  V128Gt8S
  V128Gt8U
  V128Gt16S
  V128Gt16U
  V128Gt32S
  V128Gt32U
  V128Gt64S
  V128Le8S
  V128Le8U
  V128Le16S
  V128Le16U
  V128Le32S
  V128Le32U
  V128Le64S
  V128Ge8S
  V128Ge8U
  V128Ge16S
  V128Ge16U
  V128Ge32S
  V128Ge32U
  V128Ge64S

  // Narrow - v128, v128 -> v128 (pack to smaller lanes)
  V128Narrow16to8S
  V128Narrow16to8U
  V128Narrow32to16S
  V128Narrow32to16U

  // Extend - v128 -> v128 (widen from smaller lanes)
  V128ExtendLow8to16S
  V128ExtendHigh8to16S
  V128ExtendLow8to16U
  V128ExtendHigh8to16U
  V128ExtendLow16to32S
  V128ExtendHigh16to32S
  V128ExtendLow16to32U
  V128ExtendHigh16to32U
  V128ExtendLow32to64S
  V128ExtendHigh32to64S
  V128ExtendLow32to64U
  V128ExtendHigh32to64U

  // Extended multiply - v128, v128 -> v128
  V128ExtMulLow8to16S
  V128ExtMulHigh8to16S
  V128ExtMulLow8to16U
  V128ExtMulHigh8to16U
  V128ExtMulLow16to32S
  V128ExtMulHigh16to32S
  V128ExtMulLow16to32U
  V128ExtMulHigh16to32U
  V128ExtMulLow32to64S
  V128ExtMulHigh32to64S
  V128ExtMulLow32to64U
  V128ExtMulHigh32to64U

  // Extended add pairwise - v128 -> v128
  V128ExtAddPairwise8to16S
  V128ExtAddPairwise8to16U
  V128ExtAddPairwise16to32S
  V128ExtAddPairwise16to32U

  // Dot product
  V128Dot16to32S // i32x4.dot_i16x8_s

  // Q15 multiply
  V128Q15MulrSat16S

  // Floating point arithmetic - v128, v128 -> v128
  V128AddF32
  V128AddF64
  V128SubF32
  V128SubF64
  V128MulF32
  V128MulF64
  V128DivF32
  V128DivF64
  V128MinF32
  V128MinF64
  V128MaxF32
  V128MaxF64
  V128PMinF32
  V128PMinF64
  V128PMaxF32
  V128PMaxF64

  // Floating point unary - v128 -> v128
  V128AbsF32
  V128AbsF64
  V128NegF32
  V128NegF64
  V128SqrtF32
  V128SqrtF64
  V128CeilF32
  V128CeilF64
  V128FloorF32
  V128FloorF64
  V128TruncF32
  V128TruncF64
  V128NearestF32
  V128NearestF64

  // Floating point comparisons - v128, v128 -> v128
  V128EqF32
  V128EqF64
  V128NeF32
  V128NeF64
  V128LtF32
  V128LtF64
  V128GtF32
  V128GtF64
  V128LeF32
  V128LeF64
  V128GeF32
  V128GeF64

  // Conversions
  V128TruncSatF32toI32S
  V128TruncSatF32toI32U
  V128TruncSatF64toI32SZero
  V128TruncSatF64toI32UZero
  V128ConvertI32toF32S
  V128ConvertI32toF32U
  V128ConvertLowI32toF64S
  V128ConvertLowI32toF64U
  V128DemoteF64toF32Zero
  V128PromoteLowF32toF64

  // Memory operations (memidx, align, offset)
  V128Load8x8S(Int, Int, Int64)
  V128Load8x8U(Int, Int, Int64)
  V128Load16x4S(Int, Int, Int64)
  V128Load16x4U(Int, Int, Int64)
  V128Load32x2S(Int, Int, Int64)
  V128Load32x2U(Int, Int, Int64)
  V128Load8Splat(Int, Int, Int64)
  V128Load16Splat(Int, Int, Int64)
  V128Load32Splat(Int, Int, Int64)
  V128Load64Splat(Int, Int, Int64)
  V128Load32Zero(Int, Int, Int64)
  V128Load64Zero(Int, Int, Int64)

  // Lane memory operations (memidx, align, offset, lane)
  V128Load8Lane(Int, Int, Int64, Int)
  V128Load16Lane(Int, Int, Int64, Int)
  V128Load32Lane(Int, Int, Int64, Int)
  V128Load64Lane(Int, Int, Int64, Int)
  V128Store8Lane(Int, Int, Int64, Int)
  V128Store16Lane(Int, Int, Int64, Int)
  V128Store32Lane(Int, Int, Int64, Int)
  V128Store64Lane(Int, Int, Int64, Int)

  // Relaxed SIMD instructions
  V128RelaxedSwizzle // v128, v128 -> v128 (same as swizzle on ARM)
  V128RelaxedTruncF32toI32S // v128 -> v128
  V128RelaxedTruncF32toI32U
  V128RelaxedTruncF64toI32SZero
  V128RelaxedTruncF64toI32UZero
  V128RelaxedMaddF32 // v128, v128, v128 -> v128 (a * b + c)
  V128RelaxedNmaddF32 // v128, v128, v128 -> v128 (-a * b + c)
  V128RelaxedMaddF64
  V128RelaxedNmaddF64
  V128RelaxedLaneselect8 // v128, v128, v128 -> v128 (bitselect)
  V128RelaxedLaneselect16
  V128RelaxedLaneselect32
  V128RelaxedLaneselect64
  V128RelaxedMinF32 // v128, v128 -> v128
  V128RelaxedMaxF32
  V128RelaxedMinF64
  V128RelaxedMaxF64
  V128RelaxedQ15MulrS // v128, v128 -> v128
  V128RelaxedDot8to16S // v128, v128 -> v128
  V128RelaxedDot8to32AddS // v128, v128, v128 -> v128
} derive(Debug, Eq, Hash)

///|
pub impl Show for Opcode with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

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
} derive(Debug, Eq, Hash)

///|
/// Floating point comparison condition codes
pub(all) enum FloatCC {
  Eq // Equal (ordered)
  Ne // Not equal (unordered)
  Lt // Less than (ordered)
  Le // Less than or equal (ordered)
  Gt // Greater than (ordered)
  Ge // Greater than or equal (ordered)
} derive(Debug, Eq, Hash)

///|
/// Terminator - how a basic block ends
pub(all) enum Terminator {
  // Unconditional jump
  Jump(Int, Array[Value]) // target block, arguments

  // Conditional branch
  Branch(Value, Int, Array[Value], Int, Array[Value])
  Brz(Value, Int, Int) // condition, true block, false block
  Brnz(Value, Int, Int) // condition, true block, false block

  // Multi-way branch (for br_table)
  BrTable(Value, Array[Int], Int) // index, targets, default

  // Return from function
  Return(Array[Value]) // return values

  // Trap/Unreachable
  Trap(String) // trap reason
  TrapExit(String)
} derive(Debug)

///|
/// Function - a complete IR function
pub struct Function {
  name : String
  signature : Signature
  params : Array[(Value, Type)] // Function parameters
  results : Array[Type] // Return types
  blocks : Array[Block] // Basic blocks (block 0 is entry)
  stack_slots : Array[StackSlot]
  external_symbols : Array[ExternalSymbol]
  mut next_value_id : Int // For generating unique value IDs
  mut next_inst_id : Int
  mut next_block_id : Int // For generating unique block IDs
  mut next_stack_slot_id : Int
} derive(Debug)

///|
pub fn Function::Function(name : String, signature : Signature) -> Function {
  {
    name,
    signature,
    params: [],
    results: signature.results.copy(),
    blocks: [],
    stack_slots: [],
    external_symbols: [],
    next_value_id: 0,
    next_inst_id: 0,
    next_block_id: 0,
    next_stack_slot_id: 0,
  }
}

///|
pub fn Function::new_empty(name : String) -> Function {
  Function(name, Signature([], []))
}

///|
/// Create a new value with a unique ID
pub fn Function::new_value(self : Function, ty : Type) -> Value {
  let id = self.next_value_id
  self.next_value_id = self.next_value_id + 1
  Value(id, ty)
}

///|
/// Create a new basic block
pub fn Function::new_block(self : Function, params : Array[Value]) -> Block {
  let id = self.next_block_id
  self.next_block_id = self.next_block_id + 1
  let block = Block::new_with_params(id, params)
  self.blocks.push(block)
  block
}

///|
pub fn Function::new_block0(self : Function) -> Block {
  self.new_block([])
}

///|
pub fn Function::new_inst(
  self : Function,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  let inst = Inst::new_with_id(self.next_inst_id, opcode, args, results)
  self.next_inst_id = self.next_inst_id + 1
  inst
}

///|
/// Add a parameter to the function
pub fn Function::add_param(self : Function, ty : Type) -> Value {
  let v = self.new_value(ty)
  self.params.push((v, ty))
  self.signature.params.push(ty)
  v
}

///|
/// Add a result type to the function
pub fn Function::add_result(self : Function, ty : Type) -> Unit {
  self.results.push(ty)
  self.signature.results.push(ty)
}

///|
pub fn Function::new_stack_slot(
  self : Function,
  size : Int,
  align : Int,
) -> StackSlot {
  let slot = { id: self.next_stack_slot_id, size, align }
  self.next_stack_slot_id = self.next_stack_slot_id + 1
  self.stack_slots.push(slot)
  slot
}

///|
pub fn Function::declare_external_symbol(
  self : Function,
  name : String,
) -> ExternalSymbol {
  let symbol = ExternalSymbol::ExternalSymbol(name)
  self.external_symbols.push(symbol)
  symbol
}
