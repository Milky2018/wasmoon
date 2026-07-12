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
  hash_opcode_identity(self.opcode, hasher)
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
  if !opcode_identity_equal(self.opcode, other.opcode) {
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
fn hash_opcode_identity(opcode : Opcode, hasher : Hasher) -> Unit {
  match opcode {
    Scalar(ScalarOp::FloatConst(value)) => {
      "milkir.fconst.bits".hash_combine(hasher)
      value.reinterpret_as_uint64().hash_combine(hasher)
    }
    _ => opcode.hash_combine(hasher)
  }
}

///|
fn opcode_identity_equal(lhs : Opcode, rhs : Opcode) -> Bool {
  match (lhs, rhs) {
    (Scalar(ScalarOp::FloatConst(a)), Scalar(ScalarOp::FloatConst(b))) =>
      a.reinterpret_as_uint64() == b.reinterpret_as_uint64()
    (Scalar(ScalarOp::FloatConst(_)), _)
    | (_, Scalar(ScalarOp::FloatConst(_))) => false
    _ => lhs == rhs
  }
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
/// Return an instruction view with a different opcode and shared SSA data.
pub fn Inst::with_opcode(self : Inst, opcode : Opcode) -> Inst {
  { ..self, opcode, }
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
/// Generic memory semantics over an explicit address and offset operand.
pub(all) enum MemoryOp {
  Load(Type)
  Store(Type)
  LoadNarrow(Type, Int, Bool)
  StoreNarrow(Int)
} derive(Debug, Eq, Hash)

///|
/// Generic call semantics. Pointer-call operands are laid out as the callee
/// pointer followed by ordinary arguments.
pub(all) enum CallOp {
  Direct(ExternalSymbol, Signature)
  Pointer(Int, Int)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorLane {
  I8
  I16
  I32
  I64
  F32
  F64
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorExtension {
  None
  Signed
  Unsigned
} derive(Debug, Eq, Hash)

///|
/// Language-neutral vector operations. The legacy flat variants remain
/// temporarily as expand-contract compatibility forms.
pub(all) enum VectorOp {
  // ============================================
  // SIMD operations (V128)
  // ============================================

  // V128 constant - 16 bytes stored as Bytes
  V128Const(Bytes)

  // Splat - replicate scalar to all lanes
  // operand: scalar value, result: v128
  Splat(VectorLane)

  // Extract lane - extract scalar from vector
  // operand: v128, result: scalar
  ExtractLane(VectorLane, VectorExtension, Int)

  // Replace lane - replace scalar in vector
  // operands: v128, scalar, result: v128
  ReplaceLane(VectorLane, Int)

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

  // Memory operations consume an already checked effective address. Wasm
  // memory indices, alignment hints, and offsets belong to the frontend.
  LoadExtend(VectorLane, VectorExtension)
  LoadSplat(VectorLane)
  LoadZero(VectorLane)
  LoadLane(VectorLane, Int)
  StoreLane(VectorLane, Int)

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
pub fn VectorOp::to_legacy_opcode(self : VectorOp) -> Opcode {
  match self {
    VectorOp::V128Const(arg0) => Opcode::V128Const(arg0)
    VectorOp::Splat(lane) =>
      match lane {
        VectorLane::I8 => Opcode::V128Splat8
        VectorLane::I16 => Opcode::V128Splat16
        VectorLane::I32 => Opcode::V128Splat32
        VectorLane::I64 => Opcode::V128Splat64
        VectorLane::F32 => Opcode::V128SplatF32
        VectorLane::F64 => Opcode::V128SplatF64
      }
    VectorOp::ExtractLane(lane, extension, index) =>
      match (lane, extension) {
        (VectorLane::I8, VectorExtension::Signed) =>
          Opcode::V128ExtractLane8S(index)
        (VectorLane::I8, VectorExtension::Unsigned) =>
          Opcode::V128ExtractLane8U(index)
        (VectorLane::I16, VectorExtension::Signed) =>
          Opcode::V128ExtractLane16S(index)
        (VectorLane::I16, VectorExtension::Unsigned) =>
          Opcode::V128ExtractLane16U(index)
        (VectorLane::I32, VectorExtension::None) =>
          Opcode::V128ExtractLane32(index)
        (VectorLane::I64, VectorExtension::None) =>
          Opcode::V128ExtractLane64(index)
        (VectorLane::F32, VectorExtension::None) =>
          Opcode::V128ExtractLaneF32(index)
        (VectorLane::F64, VectorExtension::None) =>
          Opcode::V128ExtractLaneF64(index)
        _ => abort("invalid vector extract-lane semantics")
      }
    VectorOp::ReplaceLane(lane, index) =>
      match lane {
        VectorLane::I8 => Opcode::V128ReplaceLane8(index)
        VectorLane::I16 => Opcode::V128ReplaceLane16(index)
        VectorLane::I32 => Opcode::V128ReplaceLane32(index)
        VectorLane::I64 => Opcode::V128ReplaceLane64(index)
        VectorLane::F32 => Opcode::V128ReplaceLaneF32(index)
        VectorLane::F64 => Opcode::V128ReplaceLaneF64(index)
      }
    VectorOp::V128Shuffle(arg0) => Opcode::V128Shuffle(arg0)
    VectorOp::V128Swizzle => Opcode::V128Swizzle
    VectorOp::V128Not => Opcode::V128Not
    VectorOp::V128And => Opcode::V128And
    VectorOp::V128AndNot => Opcode::V128AndNot
    VectorOp::V128Or => Opcode::V128Or
    VectorOp::V128Xor => Opcode::V128Xor
    VectorOp::V128Bitselect => Opcode::V128Bitselect
    VectorOp::V128AnyTrue => Opcode::V128AnyTrue
    VectorOp::V128AllTrue8 => Opcode::V128AllTrue8
    VectorOp::V128AllTrue16 => Opcode::V128AllTrue16
    VectorOp::V128AllTrue32 => Opcode::V128AllTrue32
    VectorOp::V128AllTrue64 => Opcode::V128AllTrue64
    VectorOp::V128Bitmask8 => Opcode::V128Bitmask8
    VectorOp::V128Bitmask16 => Opcode::V128Bitmask16
    VectorOp::V128Bitmask32 => Opcode::V128Bitmask32
    VectorOp::V128Bitmask64 => Opcode::V128Bitmask64
    VectorOp::V128Add8 => Opcode::V128Add8
    VectorOp::V128Add16 => Opcode::V128Add16
    VectorOp::V128Add32 => Opcode::V128Add32
    VectorOp::V128Add64 => Opcode::V128Add64
    VectorOp::V128Sub8 => Opcode::V128Sub8
    VectorOp::V128Sub16 => Opcode::V128Sub16
    VectorOp::V128Sub32 => Opcode::V128Sub32
    VectorOp::V128Sub64 => Opcode::V128Sub64
    VectorOp::V128Mul16 => Opcode::V128Mul16
    VectorOp::V128Mul32 => Opcode::V128Mul32
    VectorOp::V128Mul64 => Opcode::V128Mul64
    VectorOp::V128AddSat8S => Opcode::V128AddSat8S
    VectorOp::V128AddSat8U => Opcode::V128AddSat8U
    VectorOp::V128AddSat16S => Opcode::V128AddSat16S
    VectorOp::V128AddSat16U => Opcode::V128AddSat16U
    VectorOp::V128SubSat8S => Opcode::V128SubSat8S
    VectorOp::V128SubSat8U => Opcode::V128SubSat8U
    VectorOp::V128SubSat16S => Opcode::V128SubSat16S
    VectorOp::V128SubSat16U => Opcode::V128SubSat16U
    VectorOp::V128Min8S => Opcode::V128Min8S
    VectorOp::V128Min8U => Opcode::V128Min8U
    VectorOp::V128Min16S => Opcode::V128Min16S
    VectorOp::V128Min16U => Opcode::V128Min16U
    VectorOp::V128Min32S => Opcode::V128Min32S
    VectorOp::V128Min32U => Opcode::V128Min32U
    VectorOp::V128Max8S => Opcode::V128Max8S
    VectorOp::V128Max8U => Opcode::V128Max8U
    VectorOp::V128Max16S => Opcode::V128Max16S
    VectorOp::V128Max16U => Opcode::V128Max16U
    VectorOp::V128Max32S => Opcode::V128Max32S
    VectorOp::V128Max32U => Opcode::V128Max32U
    VectorOp::V128Avgr8U => Opcode::V128Avgr8U
    VectorOp::V128Avgr16U => Opcode::V128Avgr16U
    VectorOp::V128Abs8 => Opcode::V128Abs8
    VectorOp::V128Abs16 => Opcode::V128Abs16
    VectorOp::V128Abs32 => Opcode::V128Abs32
    VectorOp::V128Abs64 => Opcode::V128Abs64
    VectorOp::V128Neg8 => Opcode::V128Neg8
    VectorOp::V128Neg16 => Opcode::V128Neg16
    VectorOp::V128Neg32 => Opcode::V128Neg32
    VectorOp::V128Neg64 => Opcode::V128Neg64
    VectorOp::V128Popcnt8 => Opcode::V128Popcnt8
    VectorOp::V128Shl8 => Opcode::V128Shl8
    VectorOp::V128Shl16 => Opcode::V128Shl16
    VectorOp::V128Shl32 => Opcode::V128Shl32
    VectorOp::V128Shl64 => Opcode::V128Shl64
    VectorOp::V128Shr8S => Opcode::V128Shr8S
    VectorOp::V128Shr8U => Opcode::V128Shr8U
    VectorOp::V128Shr16S => Opcode::V128Shr16S
    VectorOp::V128Shr16U => Opcode::V128Shr16U
    VectorOp::V128Shr32S => Opcode::V128Shr32S
    VectorOp::V128Shr32U => Opcode::V128Shr32U
    VectorOp::V128Shr64S => Opcode::V128Shr64S
    VectorOp::V128Shr64U => Opcode::V128Shr64U
    VectorOp::V128Eq8 => Opcode::V128Eq8
    VectorOp::V128Eq16 => Opcode::V128Eq16
    VectorOp::V128Eq32 => Opcode::V128Eq32
    VectorOp::V128Eq64 => Opcode::V128Eq64
    VectorOp::V128Ne8 => Opcode::V128Ne8
    VectorOp::V128Ne16 => Opcode::V128Ne16
    VectorOp::V128Ne32 => Opcode::V128Ne32
    VectorOp::V128Ne64 => Opcode::V128Ne64
    VectorOp::V128Lt8S => Opcode::V128Lt8S
    VectorOp::V128Lt8U => Opcode::V128Lt8U
    VectorOp::V128Lt16S => Opcode::V128Lt16S
    VectorOp::V128Lt16U => Opcode::V128Lt16U
    VectorOp::V128Lt32S => Opcode::V128Lt32S
    VectorOp::V128Lt32U => Opcode::V128Lt32U
    VectorOp::V128Lt64S => Opcode::V128Lt64S
    VectorOp::V128Gt8S => Opcode::V128Gt8S
    VectorOp::V128Gt8U => Opcode::V128Gt8U
    VectorOp::V128Gt16S => Opcode::V128Gt16S
    VectorOp::V128Gt16U => Opcode::V128Gt16U
    VectorOp::V128Gt32S => Opcode::V128Gt32S
    VectorOp::V128Gt32U => Opcode::V128Gt32U
    VectorOp::V128Gt64S => Opcode::V128Gt64S
    VectorOp::V128Le8S => Opcode::V128Le8S
    VectorOp::V128Le8U => Opcode::V128Le8U
    VectorOp::V128Le16S => Opcode::V128Le16S
    VectorOp::V128Le16U => Opcode::V128Le16U
    VectorOp::V128Le32S => Opcode::V128Le32S
    VectorOp::V128Le32U => Opcode::V128Le32U
    VectorOp::V128Le64S => Opcode::V128Le64S
    VectorOp::V128Ge8S => Opcode::V128Ge8S
    VectorOp::V128Ge8U => Opcode::V128Ge8U
    VectorOp::V128Ge16S => Opcode::V128Ge16S
    VectorOp::V128Ge16U => Opcode::V128Ge16U
    VectorOp::V128Ge32S => Opcode::V128Ge32S
    VectorOp::V128Ge32U => Opcode::V128Ge32U
    VectorOp::V128Ge64S => Opcode::V128Ge64S
    VectorOp::V128Narrow16to8S => Opcode::V128Narrow16to8S
    VectorOp::V128Narrow16to8U => Opcode::V128Narrow16to8U
    VectorOp::V128Narrow32to16S => Opcode::V128Narrow32to16S
    VectorOp::V128Narrow32to16U => Opcode::V128Narrow32to16U
    VectorOp::V128ExtendLow8to16S => Opcode::V128ExtendLow8to16S
    VectorOp::V128ExtendHigh8to16S => Opcode::V128ExtendHigh8to16S
    VectorOp::V128ExtendLow8to16U => Opcode::V128ExtendLow8to16U
    VectorOp::V128ExtendHigh8to16U => Opcode::V128ExtendHigh8to16U
    VectorOp::V128ExtendLow16to32S => Opcode::V128ExtendLow16to32S
    VectorOp::V128ExtendHigh16to32S => Opcode::V128ExtendHigh16to32S
    VectorOp::V128ExtendLow16to32U => Opcode::V128ExtendLow16to32U
    VectorOp::V128ExtendHigh16to32U => Opcode::V128ExtendHigh16to32U
    VectorOp::V128ExtendLow32to64S => Opcode::V128ExtendLow32to64S
    VectorOp::V128ExtendHigh32to64S => Opcode::V128ExtendHigh32to64S
    VectorOp::V128ExtendLow32to64U => Opcode::V128ExtendLow32to64U
    VectorOp::V128ExtendHigh32to64U => Opcode::V128ExtendHigh32to64U
    VectorOp::V128ExtMulLow8to16S => Opcode::V128ExtMulLow8to16S
    VectorOp::V128ExtMulHigh8to16S => Opcode::V128ExtMulHigh8to16S
    VectorOp::V128ExtMulLow8to16U => Opcode::V128ExtMulLow8to16U
    VectorOp::V128ExtMulHigh8to16U => Opcode::V128ExtMulHigh8to16U
    VectorOp::V128ExtMulLow16to32S => Opcode::V128ExtMulLow16to32S
    VectorOp::V128ExtMulHigh16to32S => Opcode::V128ExtMulHigh16to32S
    VectorOp::V128ExtMulLow16to32U => Opcode::V128ExtMulLow16to32U
    VectorOp::V128ExtMulHigh16to32U => Opcode::V128ExtMulHigh16to32U
    VectorOp::V128ExtMulLow32to64S => Opcode::V128ExtMulLow32to64S
    VectorOp::V128ExtMulHigh32to64S => Opcode::V128ExtMulHigh32to64S
    VectorOp::V128ExtMulLow32to64U => Opcode::V128ExtMulLow32to64U
    VectorOp::V128ExtMulHigh32to64U => Opcode::V128ExtMulHigh32to64U
    VectorOp::V128ExtAddPairwise8to16S => Opcode::V128ExtAddPairwise8to16S
    VectorOp::V128ExtAddPairwise8to16U => Opcode::V128ExtAddPairwise8to16U
    VectorOp::V128ExtAddPairwise16to32S => Opcode::V128ExtAddPairwise16to32S
    VectorOp::V128ExtAddPairwise16to32U => Opcode::V128ExtAddPairwise16to32U
    VectorOp::V128Dot16to32S => Opcode::V128Dot16to32S
    VectorOp::V128Q15MulrSat16S => Opcode::V128Q15MulrSat16S
    VectorOp::V128AddF32 => Opcode::V128AddF32
    VectorOp::V128AddF64 => Opcode::V128AddF64
    VectorOp::V128SubF32 => Opcode::V128SubF32
    VectorOp::V128SubF64 => Opcode::V128SubF64
    VectorOp::V128MulF32 => Opcode::V128MulF32
    VectorOp::V128MulF64 => Opcode::V128MulF64
    VectorOp::V128DivF32 => Opcode::V128DivF32
    VectorOp::V128DivF64 => Opcode::V128DivF64
    VectorOp::V128MinF32 => Opcode::V128MinF32
    VectorOp::V128MinF64 => Opcode::V128MinF64
    VectorOp::V128MaxF32 => Opcode::V128MaxF32
    VectorOp::V128MaxF64 => Opcode::V128MaxF64
    VectorOp::V128PMinF32 => Opcode::V128PMinF32
    VectorOp::V128PMinF64 => Opcode::V128PMinF64
    VectorOp::V128PMaxF32 => Opcode::V128PMaxF32
    VectorOp::V128PMaxF64 => Opcode::V128PMaxF64
    VectorOp::V128AbsF32 => Opcode::V128AbsF32
    VectorOp::V128AbsF64 => Opcode::V128AbsF64
    VectorOp::V128NegF32 => Opcode::V128NegF32
    VectorOp::V128NegF64 => Opcode::V128NegF64
    VectorOp::V128SqrtF32 => Opcode::V128SqrtF32
    VectorOp::V128SqrtF64 => Opcode::V128SqrtF64
    VectorOp::V128CeilF32 => Opcode::V128CeilF32
    VectorOp::V128CeilF64 => Opcode::V128CeilF64
    VectorOp::V128FloorF32 => Opcode::V128FloorF32
    VectorOp::V128FloorF64 => Opcode::V128FloorF64
    VectorOp::V128TruncF32 => Opcode::V128TruncF32
    VectorOp::V128TruncF64 => Opcode::V128TruncF64
    VectorOp::V128NearestF32 => Opcode::V128NearestF32
    VectorOp::V128NearestF64 => Opcode::V128NearestF64
    VectorOp::V128EqF32 => Opcode::V128EqF32
    VectorOp::V128EqF64 => Opcode::V128EqF64
    VectorOp::V128NeF32 => Opcode::V128NeF32
    VectorOp::V128NeF64 => Opcode::V128NeF64
    VectorOp::V128LtF32 => Opcode::V128LtF32
    VectorOp::V128LtF64 => Opcode::V128LtF64
    VectorOp::V128GtF32 => Opcode::V128GtF32
    VectorOp::V128GtF64 => Opcode::V128GtF64
    VectorOp::V128LeF32 => Opcode::V128LeF32
    VectorOp::V128LeF64 => Opcode::V128LeF64
    VectorOp::V128GeF32 => Opcode::V128GeF32
    VectorOp::V128GeF64 => Opcode::V128GeF64
    VectorOp::V128TruncSatF32toI32S => Opcode::V128TruncSatF32toI32S
    VectorOp::V128TruncSatF32toI32U => Opcode::V128TruncSatF32toI32U
    VectorOp::V128TruncSatF64toI32SZero => Opcode::V128TruncSatF64toI32SZero
    VectorOp::V128TruncSatF64toI32UZero => Opcode::V128TruncSatF64toI32UZero
    VectorOp::V128ConvertI32toF32S => Opcode::V128ConvertI32toF32S
    VectorOp::V128ConvertI32toF32U => Opcode::V128ConvertI32toF32U
    VectorOp::V128ConvertLowI32toF64S => Opcode::V128ConvertLowI32toF64S
    VectorOp::V128ConvertLowI32toF64U => Opcode::V128ConvertLowI32toF64U
    VectorOp::V128DemoteF64toF32Zero => Opcode::V128DemoteF64toF32Zero
    VectorOp::V128PromoteLowF32toF64 => Opcode::V128PromoteLowF32toF64
    VectorOp::LoadExtend(lane, extension) =>
      match (lane, extension) {
        (VectorLane::I8, VectorExtension::Signed) =>
          Opcode::V128Load8x8S(0, 0, 0L)
        (VectorLane::I8, VectorExtension::Unsigned) =>
          Opcode::V128Load8x8U(0, 0, 0L)
        (VectorLane::I16, VectorExtension::Signed) =>
          Opcode::V128Load16x4S(0, 0, 0L)
        (VectorLane::I16, VectorExtension::Unsigned) =>
          Opcode::V128Load16x4U(0, 0, 0L)
        (VectorLane::I32, VectorExtension::Signed) =>
          Opcode::V128Load32x2S(0, 0, 0L)
        (VectorLane::I32, VectorExtension::Unsigned) =>
          Opcode::V128Load32x2U(0, 0, 0L)
        _ => abort("invalid vector extending-load semantics")
      }
    VectorOp::LoadSplat(lane) =>
      match lane {
        VectorLane::I8 => Opcode::V128Load8Splat(0, 0, 0L)
        VectorLane::I16 => Opcode::V128Load16Splat(0, 0, 0L)
        VectorLane::I32 => Opcode::V128Load32Splat(0, 0, 0L)
        VectorLane::I64 => Opcode::V128Load64Splat(0, 0, 0L)
        _ => abort("invalid vector splat-load semantics")
      }
    VectorOp::LoadZero(lane) =>
      match lane {
        VectorLane::I32 => Opcode::V128Load32Zero(0, 0, 0L)
        VectorLane::I64 => Opcode::V128Load64Zero(0, 0, 0L)
        _ => abort("invalid vector zero-load semantics")
      }
    VectorOp::LoadLane(lane, index) =>
      match lane {
        VectorLane::I8 => Opcode::V128Load8Lane(0, 0, 0L, index)
        VectorLane::I16 => Opcode::V128Load16Lane(0, 0, 0L, index)
        VectorLane::I32 => Opcode::V128Load32Lane(0, 0, 0L, index)
        VectorLane::I64 => Opcode::V128Load64Lane(0, 0, 0L, index)
        _ => abort("invalid vector lane-load semantics")
      }
    VectorOp::StoreLane(lane, index) =>
      match lane {
        VectorLane::I8 => Opcode::V128Store8Lane(0, 0, 0L, index)
        VectorLane::I16 => Opcode::V128Store16Lane(0, 0, 0L, index)
        VectorLane::I32 => Opcode::V128Store32Lane(0, 0, 0L, index)
        VectorLane::I64 => Opcode::V128Store64Lane(0, 0, 0L, index)
        _ => abort("invalid vector lane-store semantics")
      }
    VectorOp::V128RelaxedSwizzle => Opcode::V128RelaxedSwizzle
    VectorOp::V128RelaxedTruncF32toI32S => Opcode::V128RelaxedTruncF32toI32S
    VectorOp::V128RelaxedTruncF32toI32U => Opcode::V128RelaxedTruncF32toI32U
    VectorOp::V128RelaxedTruncF64toI32SZero =>
      Opcode::V128RelaxedTruncF64toI32SZero
    VectorOp::V128RelaxedTruncF64toI32UZero =>
      Opcode::V128RelaxedTruncF64toI32UZero
    VectorOp::V128RelaxedMaddF32 => Opcode::V128RelaxedMaddF32
    VectorOp::V128RelaxedNmaddF32 => Opcode::V128RelaxedNmaddF32
    VectorOp::V128RelaxedMaddF64 => Opcode::V128RelaxedMaddF64
    VectorOp::V128RelaxedNmaddF64 => Opcode::V128RelaxedNmaddF64
    VectorOp::V128RelaxedLaneselect8 => Opcode::V128RelaxedLaneselect8
    VectorOp::V128RelaxedLaneselect16 => Opcode::V128RelaxedLaneselect16
    VectorOp::V128RelaxedLaneselect32 => Opcode::V128RelaxedLaneselect32
    VectorOp::V128RelaxedLaneselect64 => Opcode::V128RelaxedLaneselect64
    VectorOp::V128RelaxedMinF32 => Opcode::V128RelaxedMinF32
    VectorOp::V128RelaxedMaxF32 => Opcode::V128RelaxedMaxF32
    VectorOp::V128RelaxedMinF64 => Opcode::V128RelaxedMinF64
    VectorOp::V128RelaxedMaxF64 => Opcode::V128RelaxedMaxF64
    VectorOp::V128RelaxedQ15MulrS => Opcode::V128RelaxedQ15MulrS
    VectorOp::V128RelaxedDot8to16S => Opcode::V128RelaxedDot8to16S
    VectorOp::V128RelaxedDot8to32AddS => Opcode::V128RelaxedDot8to32AddS
  }
}

///|
pub(all) enum IntBinaryOp {
  Add
  Sub
  Mul
  UnsignedMulHigh
  SignedMulHigh
  SignedDiv
  UnsignedDiv
  SignedRem
  UnsignedRem
  And
  Or
  Xor
  ShiftLeft
  SignedShiftRight
  UnsignedShiftRight
  RotateLeft
  RotateRight
} derive(Debug, Eq, Hash)

///|
pub(all) enum IntUnaryOp {
  Not
  CountLeadingZeros
  CountTrailingZeros
  PopulationCount
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatBinaryOp {
  Add
  Sub
  Mul
  Div
  Min
  Max
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatUnaryOp {
  Neg
  Abs
  Sqrt
  Ceil
  Floor
  Trunc
  Nearest
} derive(Debug, Eq, Hash)

///|
pub(all) enum ConversionOp {
  IntReduce
  SignedExtend
  UnsignedExtend
  FloatPromote
  FloatDemote
  FloatToSignedInt
  FloatToUnsignedInt
  FloatToSignedIntSaturating
  FloatToUnsignedIntSaturating
  SignedIntToFloat
  UnsignedIntToFloat
  Bitcast
} derive(Debug, Eq, Hash)

///|
pub(all) enum ScalarOp {
  IntConst(Int64)
  FloatConst(Double)
  IntBinary(IntBinaryOp)
  IntUnary(IntUnaryOp)
  IntCompare(IntCC)
  FloatBinary(FloatBinaryOp)
  FloatUnary(FloatUnaryOp)
  FloatCompare(FloatCC)
  Convert(ConversionOp)
  SignExtendFrom(Int)
  Select
  Copy
} derive(Debug, Eq, Hash)

///|
/// Opcode - the operation performed by an instruction
pub(all) enum Opcode {
  // Language-neutral scalar operations.
  Scalar(ScalarOp)

  // Function calls
  Call(CallOp)

  // Raw pointer operations (for trampolines, no bounds checking)
  // Used for host code generation
  LoadPtr(Type) // Load from pointer+offset (operand 0 = base ptr)
  StorePtr(Type) // Store to pointer+offset (operand 0 = base ptr, operand 1 = value)
  // Narrow load/store from raw pointer (result_type, bits, signed)
  LoadPtrNarrow(Type, Int, Bool) // Load narrow from pointer+offset, extend to result_type
  StorePtrNarrow(Int) // Store narrow to pointer+offset (bits)

  // Generic memory operations. Legacy raw-pointer variants remain during
  // expand-contract migration and are removed after all callers move here.
  Memory(MemoryOp)

  // Dialect extension operations. The core IR treats these conservatively;
  // dialect-owned packages define the opcode set, builders, validation rules,
  // and lowering behavior.
  Ext(ExtOp, Signature)

  // Language-neutral vector operations.
  Vector(VectorOp)

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
fn Opcode::to_vector_op(self : Opcode) -> VectorOp? {
  match self {
    Opcode::V128Const(arg0) => Some(VectorOp::V128Const(arg0))
    Opcode::V128Splat8 => Some(VectorOp::Splat(VectorLane::I8))
    Opcode::V128Splat16 => Some(VectorOp::Splat(VectorLane::I16))
    Opcode::V128Splat32 => Some(VectorOp::Splat(VectorLane::I32))
    Opcode::V128Splat64 => Some(VectorOp::Splat(VectorLane::I64))
    Opcode::V128SplatF32 => Some(VectorOp::Splat(VectorLane::F32))
    Opcode::V128SplatF64 => Some(VectorOp::Splat(VectorLane::F64))
    Opcode::V128ExtractLane8S(index) =>
      Some(
        VectorOp::ExtractLane(VectorLane::I8, VectorExtension::Signed, index),
      )
    Opcode::V128ExtractLane8U(index) =>
      Some(
        VectorOp::ExtractLane(VectorLane::I8, VectorExtension::Unsigned, index),
      )
    Opcode::V128ExtractLane16S(index) =>
      Some(
        VectorOp::ExtractLane(VectorLane::I16, VectorExtension::Signed, index),
      )
    Opcode::V128ExtractLane16U(index) =>
      Some(
        VectorOp::ExtractLane(VectorLane::I16, VectorExtension::Unsigned, index),
      )
    Opcode::V128ExtractLane32(index) =>
      Some(VectorOp::ExtractLane(VectorLane::I32, VectorExtension::None, index))
    Opcode::V128ExtractLane64(index) =>
      Some(VectorOp::ExtractLane(VectorLane::I64, VectorExtension::None, index))
    Opcode::V128ExtractLaneF32(index) =>
      Some(VectorOp::ExtractLane(VectorLane::F32, VectorExtension::None, index))
    Opcode::V128ExtractLaneF64(index) =>
      Some(VectorOp::ExtractLane(VectorLane::F64, VectorExtension::None, index))
    Opcode::V128ReplaceLane8(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::I8, index))
    Opcode::V128ReplaceLane16(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::I16, index))
    Opcode::V128ReplaceLane32(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::I32, index))
    Opcode::V128ReplaceLane64(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::I64, index))
    Opcode::V128ReplaceLaneF32(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::F32, index))
    Opcode::V128ReplaceLaneF64(index) =>
      Some(VectorOp::ReplaceLane(VectorLane::F64, index))
    Opcode::V128Shuffle(arg0) => Some(VectorOp::V128Shuffle(arg0))
    Opcode::V128Swizzle => Some(VectorOp::V128Swizzle)
    Opcode::V128Not => Some(VectorOp::V128Not)
    Opcode::V128And => Some(VectorOp::V128And)
    Opcode::V128AndNot => Some(VectorOp::V128AndNot)
    Opcode::V128Or => Some(VectorOp::V128Or)
    Opcode::V128Xor => Some(VectorOp::V128Xor)
    Opcode::V128Bitselect => Some(VectorOp::V128Bitselect)
    Opcode::V128AnyTrue => Some(VectorOp::V128AnyTrue)
    Opcode::V128AllTrue8 => Some(VectorOp::V128AllTrue8)
    Opcode::V128AllTrue16 => Some(VectorOp::V128AllTrue16)
    Opcode::V128AllTrue32 => Some(VectorOp::V128AllTrue32)
    Opcode::V128AllTrue64 => Some(VectorOp::V128AllTrue64)
    Opcode::V128Bitmask8 => Some(VectorOp::V128Bitmask8)
    Opcode::V128Bitmask16 => Some(VectorOp::V128Bitmask16)
    Opcode::V128Bitmask32 => Some(VectorOp::V128Bitmask32)
    Opcode::V128Bitmask64 => Some(VectorOp::V128Bitmask64)
    Opcode::V128Add8 => Some(VectorOp::V128Add8)
    Opcode::V128Add16 => Some(VectorOp::V128Add16)
    Opcode::V128Add32 => Some(VectorOp::V128Add32)
    Opcode::V128Add64 => Some(VectorOp::V128Add64)
    Opcode::V128Sub8 => Some(VectorOp::V128Sub8)
    Opcode::V128Sub16 => Some(VectorOp::V128Sub16)
    Opcode::V128Sub32 => Some(VectorOp::V128Sub32)
    Opcode::V128Sub64 => Some(VectorOp::V128Sub64)
    Opcode::V128Mul16 => Some(VectorOp::V128Mul16)
    Opcode::V128Mul32 => Some(VectorOp::V128Mul32)
    Opcode::V128Mul64 => Some(VectorOp::V128Mul64)
    Opcode::V128AddSat8S => Some(VectorOp::V128AddSat8S)
    Opcode::V128AddSat8U => Some(VectorOp::V128AddSat8U)
    Opcode::V128AddSat16S => Some(VectorOp::V128AddSat16S)
    Opcode::V128AddSat16U => Some(VectorOp::V128AddSat16U)
    Opcode::V128SubSat8S => Some(VectorOp::V128SubSat8S)
    Opcode::V128SubSat8U => Some(VectorOp::V128SubSat8U)
    Opcode::V128SubSat16S => Some(VectorOp::V128SubSat16S)
    Opcode::V128SubSat16U => Some(VectorOp::V128SubSat16U)
    Opcode::V128Min8S => Some(VectorOp::V128Min8S)
    Opcode::V128Min8U => Some(VectorOp::V128Min8U)
    Opcode::V128Min16S => Some(VectorOp::V128Min16S)
    Opcode::V128Min16U => Some(VectorOp::V128Min16U)
    Opcode::V128Min32S => Some(VectorOp::V128Min32S)
    Opcode::V128Min32U => Some(VectorOp::V128Min32U)
    Opcode::V128Max8S => Some(VectorOp::V128Max8S)
    Opcode::V128Max8U => Some(VectorOp::V128Max8U)
    Opcode::V128Max16S => Some(VectorOp::V128Max16S)
    Opcode::V128Max16U => Some(VectorOp::V128Max16U)
    Opcode::V128Max32S => Some(VectorOp::V128Max32S)
    Opcode::V128Max32U => Some(VectorOp::V128Max32U)
    Opcode::V128Avgr8U => Some(VectorOp::V128Avgr8U)
    Opcode::V128Avgr16U => Some(VectorOp::V128Avgr16U)
    Opcode::V128Abs8 => Some(VectorOp::V128Abs8)
    Opcode::V128Abs16 => Some(VectorOp::V128Abs16)
    Opcode::V128Abs32 => Some(VectorOp::V128Abs32)
    Opcode::V128Abs64 => Some(VectorOp::V128Abs64)
    Opcode::V128Neg8 => Some(VectorOp::V128Neg8)
    Opcode::V128Neg16 => Some(VectorOp::V128Neg16)
    Opcode::V128Neg32 => Some(VectorOp::V128Neg32)
    Opcode::V128Neg64 => Some(VectorOp::V128Neg64)
    Opcode::V128Popcnt8 => Some(VectorOp::V128Popcnt8)
    Opcode::V128Shl8 => Some(VectorOp::V128Shl8)
    Opcode::V128Shl16 => Some(VectorOp::V128Shl16)
    Opcode::V128Shl32 => Some(VectorOp::V128Shl32)
    Opcode::V128Shl64 => Some(VectorOp::V128Shl64)
    Opcode::V128Shr8S => Some(VectorOp::V128Shr8S)
    Opcode::V128Shr8U => Some(VectorOp::V128Shr8U)
    Opcode::V128Shr16S => Some(VectorOp::V128Shr16S)
    Opcode::V128Shr16U => Some(VectorOp::V128Shr16U)
    Opcode::V128Shr32S => Some(VectorOp::V128Shr32S)
    Opcode::V128Shr32U => Some(VectorOp::V128Shr32U)
    Opcode::V128Shr64S => Some(VectorOp::V128Shr64S)
    Opcode::V128Shr64U => Some(VectorOp::V128Shr64U)
    Opcode::V128Eq8 => Some(VectorOp::V128Eq8)
    Opcode::V128Eq16 => Some(VectorOp::V128Eq16)
    Opcode::V128Eq32 => Some(VectorOp::V128Eq32)
    Opcode::V128Eq64 => Some(VectorOp::V128Eq64)
    Opcode::V128Ne8 => Some(VectorOp::V128Ne8)
    Opcode::V128Ne16 => Some(VectorOp::V128Ne16)
    Opcode::V128Ne32 => Some(VectorOp::V128Ne32)
    Opcode::V128Ne64 => Some(VectorOp::V128Ne64)
    Opcode::V128Lt8S => Some(VectorOp::V128Lt8S)
    Opcode::V128Lt8U => Some(VectorOp::V128Lt8U)
    Opcode::V128Lt16S => Some(VectorOp::V128Lt16S)
    Opcode::V128Lt16U => Some(VectorOp::V128Lt16U)
    Opcode::V128Lt32S => Some(VectorOp::V128Lt32S)
    Opcode::V128Lt32U => Some(VectorOp::V128Lt32U)
    Opcode::V128Lt64S => Some(VectorOp::V128Lt64S)
    Opcode::V128Gt8S => Some(VectorOp::V128Gt8S)
    Opcode::V128Gt8U => Some(VectorOp::V128Gt8U)
    Opcode::V128Gt16S => Some(VectorOp::V128Gt16S)
    Opcode::V128Gt16U => Some(VectorOp::V128Gt16U)
    Opcode::V128Gt32S => Some(VectorOp::V128Gt32S)
    Opcode::V128Gt32U => Some(VectorOp::V128Gt32U)
    Opcode::V128Gt64S => Some(VectorOp::V128Gt64S)
    Opcode::V128Le8S => Some(VectorOp::V128Le8S)
    Opcode::V128Le8U => Some(VectorOp::V128Le8U)
    Opcode::V128Le16S => Some(VectorOp::V128Le16S)
    Opcode::V128Le16U => Some(VectorOp::V128Le16U)
    Opcode::V128Le32S => Some(VectorOp::V128Le32S)
    Opcode::V128Le32U => Some(VectorOp::V128Le32U)
    Opcode::V128Le64S => Some(VectorOp::V128Le64S)
    Opcode::V128Ge8S => Some(VectorOp::V128Ge8S)
    Opcode::V128Ge8U => Some(VectorOp::V128Ge8U)
    Opcode::V128Ge16S => Some(VectorOp::V128Ge16S)
    Opcode::V128Ge16U => Some(VectorOp::V128Ge16U)
    Opcode::V128Ge32S => Some(VectorOp::V128Ge32S)
    Opcode::V128Ge32U => Some(VectorOp::V128Ge32U)
    Opcode::V128Ge64S => Some(VectorOp::V128Ge64S)
    Opcode::V128Narrow16to8S => Some(VectorOp::V128Narrow16to8S)
    Opcode::V128Narrow16to8U => Some(VectorOp::V128Narrow16to8U)
    Opcode::V128Narrow32to16S => Some(VectorOp::V128Narrow32to16S)
    Opcode::V128Narrow32to16U => Some(VectorOp::V128Narrow32to16U)
    Opcode::V128ExtendLow8to16S => Some(VectorOp::V128ExtendLow8to16S)
    Opcode::V128ExtendHigh8to16S => Some(VectorOp::V128ExtendHigh8to16S)
    Opcode::V128ExtendLow8to16U => Some(VectorOp::V128ExtendLow8to16U)
    Opcode::V128ExtendHigh8to16U => Some(VectorOp::V128ExtendHigh8to16U)
    Opcode::V128ExtendLow16to32S => Some(VectorOp::V128ExtendLow16to32S)
    Opcode::V128ExtendHigh16to32S => Some(VectorOp::V128ExtendHigh16to32S)
    Opcode::V128ExtendLow16to32U => Some(VectorOp::V128ExtendLow16to32U)
    Opcode::V128ExtendHigh16to32U => Some(VectorOp::V128ExtendHigh16to32U)
    Opcode::V128ExtendLow32to64S => Some(VectorOp::V128ExtendLow32to64S)
    Opcode::V128ExtendHigh32to64S => Some(VectorOp::V128ExtendHigh32to64S)
    Opcode::V128ExtendLow32to64U => Some(VectorOp::V128ExtendLow32to64U)
    Opcode::V128ExtendHigh32to64U => Some(VectorOp::V128ExtendHigh32to64U)
    Opcode::V128ExtMulLow8to16S => Some(VectorOp::V128ExtMulLow8to16S)
    Opcode::V128ExtMulHigh8to16S => Some(VectorOp::V128ExtMulHigh8to16S)
    Opcode::V128ExtMulLow8to16U => Some(VectorOp::V128ExtMulLow8to16U)
    Opcode::V128ExtMulHigh8to16U => Some(VectorOp::V128ExtMulHigh8to16U)
    Opcode::V128ExtMulLow16to32S => Some(VectorOp::V128ExtMulLow16to32S)
    Opcode::V128ExtMulHigh16to32S => Some(VectorOp::V128ExtMulHigh16to32S)
    Opcode::V128ExtMulLow16to32U => Some(VectorOp::V128ExtMulLow16to32U)
    Opcode::V128ExtMulHigh16to32U => Some(VectorOp::V128ExtMulHigh16to32U)
    Opcode::V128ExtMulLow32to64S => Some(VectorOp::V128ExtMulLow32to64S)
    Opcode::V128ExtMulHigh32to64S => Some(VectorOp::V128ExtMulHigh32to64S)
    Opcode::V128ExtMulLow32to64U => Some(VectorOp::V128ExtMulLow32to64U)
    Opcode::V128ExtMulHigh32to64U => Some(VectorOp::V128ExtMulHigh32to64U)
    Opcode::V128ExtAddPairwise8to16S => Some(VectorOp::V128ExtAddPairwise8to16S)
    Opcode::V128ExtAddPairwise8to16U => Some(VectorOp::V128ExtAddPairwise8to16U)
    Opcode::V128ExtAddPairwise16to32S =>
      Some(VectorOp::V128ExtAddPairwise16to32S)
    Opcode::V128ExtAddPairwise16to32U =>
      Some(VectorOp::V128ExtAddPairwise16to32U)
    Opcode::V128Dot16to32S => Some(VectorOp::V128Dot16to32S)
    Opcode::V128Q15MulrSat16S => Some(VectorOp::V128Q15MulrSat16S)
    Opcode::V128AddF32 => Some(VectorOp::V128AddF32)
    Opcode::V128AddF64 => Some(VectorOp::V128AddF64)
    Opcode::V128SubF32 => Some(VectorOp::V128SubF32)
    Opcode::V128SubF64 => Some(VectorOp::V128SubF64)
    Opcode::V128MulF32 => Some(VectorOp::V128MulF32)
    Opcode::V128MulF64 => Some(VectorOp::V128MulF64)
    Opcode::V128DivF32 => Some(VectorOp::V128DivF32)
    Opcode::V128DivF64 => Some(VectorOp::V128DivF64)
    Opcode::V128MinF32 => Some(VectorOp::V128MinF32)
    Opcode::V128MinF64 => Some(VectorOp::V128MinF64)
    Opcode::V128MaxF32 => Some(VectorOp::V128MaxF32)
    Opcode::V128MaxF64 => Some(VectorOp::V128MaxF64)
    Opcode::V128PMinF32 => Some(VectorOp::V128PMinF32)
    Opcode::V128PMinF64 => Some(VectorOp::V128PMinF64)
    Opcode::V128PMaxF32 => Some(VectorOp::V128PMaxF32)
    Opcode::V128PMaxF64 => Some(VectorOp::V128PMaxF64)
    Opcode::V128AbsF32 => Some(VectorOp::V128AbsF32)
    Opcode::V128AbsF64 => Some(VectorOp::V128AbsF64)
    Opcode::V128NegF32 => Some(VectorOp::V128NegF32)
    Opcode::V128NegF64 => Some(VectorOp::V128NegF64)
    Opcode::V128SqrtF32 => Some(VectorOp::V128SqrtF32)
    Opcode::V128SqrtF64 => Some(VectorOp::V128SqrtF64)
    Opcode::V128CeilF32 => Some(VectorOp::V128CeilF32)
    Opcode::V128CeilF64 => Some(VectorOp::V128CeilF64)
    Opcode::V128FloorF32 => Some(VectorOp::V128FloorF32)
    Opcode::V128FloorF64 => Some(VectorOp::V128FloorF64)
    Opcode::V128TruncF32 => Some(VectorOp::V128TruncF32)
    Opcode::V128TruncF64 => Some(VectorOp::V128TruncF64)
    Opcode::V128NearestF32 => Some(VectorOp::V128NearestF32)
    Opcode::V128NearestF64 => Some(VectorOp::V128NearestF64)
    Opcode::V128EqF32 => Some(VectorOp::V128EqF32)
    Opcode::V128EqF64 => Some(VectorOp::V128EqF64)
    Opcode::V128NeF32 => Some(VectorOp::V128NeF32)
    Opcode::V128NeF64 => Some(VectorOp::V128NeF64)
    Opcode::V128LtF32 => Some(VectorOp::V128LtF32)
    Opcode::V128LtF64 => Some(VectorOp::V128LtF64)
    Opcode::V128GtF32 => Some(VectorOp::V128GtF32)
    Opcode::V128GtF64 => Some(VectorOp::V128GtF64)
    Opcode::V128LeF32 => Some(VectorOp::V128LeF32)
    Opcode::V128LeF64 => Some(VectorOp::V128LeF64)
    Opcode::V128GeF32 => Some(VectorOp::V128GeF32)
    Opcode::V128GeF64 => Some(VectorOp::V128GeF64)
    Opcode::V128TruncSatF32toI32S => Some(VectorOp::V128TruncSatF32toI32S)
    Opcode::V128TruncSatF32toI32U => Some(VectorOp::V128TruncSatF32toI32U)
    Opcode::V128TruncSatF64toI32SZero =>
      Some(VectorOp::V128TruncSatF64toI32SZero)
    Opcode::V128TruncSatF64toI32UZero =>
      Some(VectorOp::V128TruncSatF64toI32UZero)
    Opcode::V128ConvertI32toF32S => Some(VectorOp::V128ConvertI32toF32S)
    Opcode::V128ConvertI32toF32U => Some(VectorOp::V128ConvertI32toF32U)
    Opcode::V128ConvertLowI32toF64S => Some(VectorOp::V128ConvertLowI32toF64S)
    Opcode::V128ConvertLowI32toF64U => Some(VectorOp::V128ConvertLowI32toF64U)
    Opcode::V128DemoteF64toF32Zero => Some(VectorOp::V128DemoteF64toF32Zero)
    Opcode::V128PromoteLowF32toF64 => Some(VectorOp::V128PromoteLowF32toF64)
    Opcode::V128Load8x8S(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I8, VectorExtension::Signed))
    Opcode::V128Load8x8U(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I8, VectorExtension::Unsigned))
    Opcode::V128Load16x4S(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I16, VectorExtension::Signed))
    Opcode::V128Load16x4U(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I16, VectorExtension::Unsigned))
    Opcode::V128Load32x2S(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I32, VectorExtension::Signed))
    Opcode::V128Load32x2U(_, _, _) =>
      Some(VectorOp::LoadExtend(VectorLane::I32, VectorExtension::Unsigned))
    Opcode::V128Load8Splat(_, _, _) => Some(VectorOp::LoadSplat(VectorLane::I8))
    Opcode::V128Load16Splat(_, _, _) =>
      Some(VectorOp::LoadSplat(VectorLane::I16))
    Opcode::V128Load32Splat(_, _, _) =>
      Some(VectorOp::LoadSplat(VectorLane::I32))
    Opcode::V128Load64Splat(_, _, _) =>
      Some(VectorOp::LoadSplat(VectorLane::I64))
    Opcode::V128Load32Zero(_, _, _) => Some(VectorOp::LoadZero(VectorLane::I32))
    Opcode::V128Load64Zero(_, _, _) => Some(VectorOp::LoadZero(VectorLane::I64))
    Opcode::V128Load8Lane(_, _, _, index) =>
      Some(VectorOp::LoadLane(VectorLane::I8, index))
    Opcode::V128Load16Lane(_, _, _, index) =>
      Some(VectorOp::LoadLane(VectorLane::I16, index))
    Opcode::V128Load32Lane(_, _, _, index) =>
      Some(VectorOp::LoadLane(VectorLane::I32, index))
    Opcode::V128Load64Lane(_, _, _, index) =>
      Some(VectorOp::LoadLane(VectorLane::I64, index))
    Opcode::V128Store8Lane(_, _, _, index) =>
      Some(VectorOp::StoreLane(VectorLane::I8, index))
    Opcode::V128Store16Lane(_, _, _, index) =>
      Some(VectorOp::StoreLane(VectorLane::I16, index))
    Opcode::V128Store32Lane(_, _, _, index) =>
      Some(VectorOp::StoreLane(VectorLane::I32, index))
    Opcode::V128Store64Lane(_, _, _, index) =>
      Some(VectorOp::StoreLane(VectorLane::I64, index))
    Opcode::V128RelaxedSwizzle => Some(VectorOp::V128RelaxedSwizzle)
    Opcode::V128RelaxedTruncF32toI32S =>
      Some(VectorOp::V128RelaxedTruncF32toI32S)
    Opcode::V128RelaxedTruncF32toI32U =>
      Some(VectorOp::V128RelaxedTruncF32toI32U)
    Opcode::V128RelaxedTruncF64toI32SZero =>
      Some(VectorOp::V128RelaxedTruncF64toI32SZero)
    Opcode::V128RelaxedTruncF64toI32UZero =>
      Some(VectorOp::V128RelaxedTruncF64toI32UZero)
    Opcode::V128RelaxedMaddF32 => Some(VectorOp::V128RelaxedMaddF32)
    Opcode::V128RelaxedNmaddF32 => Some(VectorOp::V128RelaxedNmaddF32)
    Opcode::V128RelaxedMaddF64 => Some(VectorOp::V128RelaxedMaddF64)
    Opcode::V128RelaxedNmaddF64 => Some(VectorOp::V128RelaxedNmaddF64)
    Opcode::V128RelaxedLaneselect8 => Some(VectorOp::V128RelaxedLaneselect8)
    Opcode::V128RelaxedLaneselect16 => Some(VectorOp::V128RelaxedLaneselect16)
    Opcode::V128RelaxedLaneselect32 => Some(VectorOp::V128RelaxedLaneselect32)
    Opcode::V128RelaxedLaneselect64 => Some(VectorOp::V128RelaxedLaneselect64)
    Opcode::V128RelaxedMinF32 => Some(VectorOp::V128RelaxedMinF32)
    Opcode::V128RelaxedMaxF32 => Some(VectorOp::V128RelaxedMaxF32)
    Opcode::V128RelaxedMinF64 => Some(VectorOp::V128RelaxedMinF64)
    Opcode::V128RelaxedMaxF64 => Some(VectorOp::V128RelaxedMaxF64)
    Opcode::V128RelaxedQ15MulrS => Some(VectorOp::V128RelaxedQ15MulrS)
    Opcode::V128RelaxedDot8to16S => Some(VectorOp::V128RelaxedDot8to16S)
    Opcode::V128RelaxedDot8to32AddS => Some(VectorOp::V128RelaxedDot8to32AddS)
    _ => None
  }
}

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
  params : Array[(Value, Type)] // Function parameters
  results : Array[Type] // Return types
  blocks : Array[Block] // Basic blocks (block 0 is entry)
  external_symbols : Array[ExternalSymbol]
  mut next_value_id : Int // For generating unique value IDs
  mut next_inst_id : Int
  mut next_block_id : Int // For generating unique block IDs
} derive(Debug)

///|
pub fn Function::new_empty(name : String) -> Function {
  {
    name,
    params: [],
    results: [],
    blocks: [],
    external_symbols: [],
    next_value_id: 0,
    next_inst_id: 0,
    next_block_id: 0,
  }
}

///|
/// Create a function whose declared signature is materialized as explicit
/// parameter values and result types.
pub fn Function::with_signature(
  name : String,
  signature : Signature,
) -> Function {
  let func = Function::new_empty(name)
  for ty in signature.params {
    func.add_param(ty) |> ignore
  }
  for ty in signature.results {
    func.add_result(ty)
  }
  func
}

///|
/// Return a declared function parameter by position.
pub fn Function::param(self : Function, index : Int) -> Value? {
  if index >= 0 && index < self.params.length() {
    Some(self.params[index].0)
  } else {
    None
  }
}

///|
/// Return a signature snapshot derived from the explicit function contract.
pub fn Function::signature(self : Function) -> Signature {
  Signature([ for param in self.params => param.1 ], self.results.copy())
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
pub fn Opcode::canonicalize(self : Opcode) -> Opcode {
  match self.to_vector_op() {
    Some(vector_op) => Vector(vector_op)
    None => self
  }
}

///|
pub fn Function::new_inst(
  self : Function,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  let canonical_opcode = opcode.canonicalize()
  let inst = Inst::new_with_id(
    self.next_inst_id,
    canonical_opcode,
    args,
    results,
  )
  self.next_inst_id = self.next_inst_id + 1
  inst
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

///|
pub fn Function::declare_external_symbol(
  self : Function,
  name : String,
) -> ExternalSymbol {
  let symbol = ExternalSymbol::ExternalSymbol(name)
  self.external_symbols.push(symbol)
  symbol
}
