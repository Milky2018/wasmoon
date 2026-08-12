// MilkIR intermediate representation.
// Based on SSA (Static Single Assignment) form

///|
priv struct FunctionOwnerContext {
  mut construction_error : VerifyError?
}

///|
fn FunctionOwnerContext::new() -> Ref[FunctionOwnerContext] {
  Ref({ construction_error: None })
}

///|
fn FunctionOwnerContext::record_construction_error(
  self : FunctionOwnerContext,
  error : VerifyError,
) -> Unit {
  if self.construction_error is None {
    self.construction_error = Some(error)
  }
}

///|
fn reject_foreign_value(
  owner : Ref[FunctionOwnerContext],
  value : Value,
) -> Bool {
  if !physical_equal(owner, value.owner) {
    owner.val.record_construction_error(ForeignValue(value_id=value.id))
    return true
  }
  false
}

///|
fn reject_foreign_values(
  owner : Ref[FunctionOwnerContext],
  values : Array[Value],
) -> Bool {
  for value in values {
    if reject_foreign_value(owner, value) {
      return true
    }
  }
  false
}

///|
fn reject_foreign_terminator_values(
  owner : Ref[FunctionOwnerContext],
  term : Terminator,
) -> Bool {
  match term {
    Jump(_, values) | Return(values) => reject_foreign_values(owner, values)
    Branch(cond, _, true_args, _, false_args) =>
      reject_foreign_value(owner, cond) ||
      reject_foreign_values(owner, true_args) ||
      reject_foreign_values(owner, false_args)
    Brz(cond, _, _) | Brnz(cond, _, _) | BrTable(cond, _, _) =>
      reject_foreign_value(owner, cond)
    Trap(_) | TrapExit(_) => false
  }
}

///|
/// IR Value - represents a virtual register in SSA form
/// Each value is defined exactly once and can be used multiple times
pub struct Value {
  priv owner : Ref[FunctionOwnerContext]
  id : Int // Unique identifier within a function
  ty : Type // The type of this value
}

///|
fn Value::new(owner : Ref[FunctionOwnerContext], id : Int, ty : Type) -> Value {
  { owner, id, ty }
}

///|
pub impl Eq for Value with fn equal(self, other) {
  physical_equal(self.owner, other.owner) &&
  self.id == other.id &&
  self.ty == other.ty
}

///|
pub impl Hash for Value with fn hash_combine(self, hasher) {
  // Owner identity deliberately does not contribute to the hash. Values from
  // different functions may collide, but equal values always hash equally.
  hasher.combine(self.id)
  hasher.combine(self.ty)
}

///|
pub impl Debug for Value with fn to_repr(self) {
  Repr::record({ "id": Repr(self.id), "ty": Repr(self.ty) })
}

///|
/// IR type system for scalar, vector, pointer, and reference-typed values.
///
/// `Ptr`, `Ref`, `CallableRef`, and `OpaqueRef` are fixed-width 64-bit
/// carriers. Their representation does not vary with the host pointer width.
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
/// Opaque embedding-context field identity.
///
/// The dialect owns the meaning of `key` and `parameters`; MilkIR only relies
/// on the declared type and optimizer-visible global-value contract.
pub struct ContextField {
  dialect : String
  key : Int
  parameters : FixedArray[Int]
  ty : Type
} derive(Debug)

///|
pub fn ContextField::new(
  dialect : String,
  key : Int,
  parameters : FixedArray[Int],
  ty : Type,
) -> ContextField {
  { dialect, key, parameters, ty }
}

///|
pub impl Eq for ContextField with fn equal(self, other) {
  if self.dialect != other.dialect ||
    self.key != other.key ||
    self.ty != other.ty ||
    self.parameters.length() != other.parameters.length() {
    return false
  }
  for i in 0..<self.parameters.length() {
    if self.parameters[i] != other.parameters[i] {
      return false
    }
  }
  true
}

///|
pub impl Hash for ContextField with fn hash_combine(self, hasher) {
  hasher.combine(self.dialect)
  hasher.combine(self.key)
  hasher.combine(self.ty)
  hasher.combine(self.parameters.length())
  for parameter in self.parameters {
    hasher.combine(parameter)
  }
}

///|
/// Disjoint abstract memory regions used by alias analysis.
pub(all) enum AliasRegion {
  Heap(Int)
  Table(Int)
  Context
  Other
} derive(Debug, Eq, Hash)

///|
/// Whether a context field may change while the function is executing.
///
/// `Stable` grants reuse permission for one invocation. `Mutable` requires
/// invalidation at calls and writes that may affect the context region.
pub(all) enum GlobalValueStability {
  Stable
  Mutable
} derive(Debug, Eq, Hash)

///|
/// Function-scoped global-value declaration.
pub(all) enum GlobalValueData {
  ContextField(ContextField, GlobalValueStability, AliasRegion)
} derive(Debug, Eq, Hash)

///|
pub fn GlobalValueData::context_field(
  field : ContextField,
  stability : GlobalValueStability,
  result_region : AliasRegion,
) -> GlobalValueData {
  ContextField(field, stability, result_region)
}

///|
fn GlobalValueData::result_type(self : GlobalValueData) -> Type {
  match self {
    ContextField(field, _, _) => field.ty
  }
}

///|
/// Function-owned handle to an interned global-value declaration.
pub struct GlobalValue {
  priv owner : Ref[FunctionOwnerContext]
  id : Int
}

///|
fn GlobalValue::new(owner : Ref[FunctionOwnerContext], id : Int) -> GlobalValue {
  { owner, id }
}

///|
pub impl Eq for GlobalValue with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Hash for GlobalValue with fn hash_combine(self, hasher) {
  hasher.combine(self.id)
}

///|
pub impl Debug for GlobalValue with fn to_repr(self) {
  Repr::record({ "id": Repr(self.id) })
}

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
/// Read-only instruction shape exposed to an extension dialect validator.
pub struct ExtensionInstView {
  op : ExtOp
  operand_types : ReadOnlyArray[Type]
  result_types : ReadOnlyArray[Type]
} derive(Debug)

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
  hasher.combine(self.dialect)
  hasher.combine(self.opcode)
  hasher.combine(self.immediates.length())
  for imm in self.immediates {
    hasher.combine(imm)
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
///
/// The public fields are exposed for zero-copy inspection. Callers must not
/// mutate `params`, `instructions`, or `terminator` directly. Use
/// `FunctionBuilder`, `append_inst`, and `set_terminator` so ownership checks
/// run, then verify the containing function before optimization or lowering.
pub struct Block {
  priv owner : Ref[FunctionOwnerContext]
  id : Int // Unique block identifier
  params : Array[(Value, Type)] // Block parameters (for phi nodes)
  mut instructions : Array[Inst] // Instructions in this block
  mut terminator : Terminator? // How this block ends
}

///|
pub impl Debug for Block with fn to_repr(self) {
  Repr::record({
    "id": Repr(self.id),
    "params": Repr(self.params),
    "instructions": Repr(self.instructions),
    "terminator": Repr(self.terminator),
  })
}

///|
fn Block::Block(owner : Ref[FunctionOwnerContext], id : Int) -> Block {
  { owner, id, params: [], instructions: [], terminator: None }
}

///|
fn Block::new_with_params(
  owner : Ref[FunctionOwnerContext],
  id : Int,
  params : Array[Value],
) -> Block {
  let block = Block(owner, id)
  for param in params {
    block.add_param(param, param.ty)
  }
  block
}

///|
/// Add a parameter to this block (for SSA phi nodes)
fn Block::add_param(self : Block, value : Value, ty : Type) -> Unit {
  if reject_foreign_value(self.owner, value) {
    return
  }
  self.params.push((value, ty))
}

///|
/// Add an instruction to this block
fn Block::add_inst(self : Block, inst : Inst) -> Unit {
  if !physical_equal(self.owner, inst.owner) {
    self.owner.val.record_construction_error(
      ForeignInstruction(inst_id=inst.id),
    )
    return
  }
  if reject_foreign_values(self.owner, inst.args) ||
    reject_foreign_values(self.owner, inst.operands) ||
    reject_foreign_values(self.owner, inst.results) ||
    reject_foreign_opcode_entities(self.owner, inst.opcode) {
    return
  }
  self.instructions.push(inst)
}

///|
pub fn Block::append_inst(self : Block, inst : Inst) -> Unit {
  self.add_inst(inst)
}

///|
/// Set the terminator for this block
pub fn Block::set_terminator(self : Block, term : Terminator) -> Unit {
  if reject_foreign_terminator_values(self.owner, term) {
    return
  }
  self.terminator = Some(term)
}

///|
/// Instruction - an SSA instruction that produces a value.
///
/// The public fields are exposed for zero-copy inspection. Callers must not
/// mutate `results`, `opcode`, `args`, `operands`, or `metadata` directly.
/// Construct instructions through `FunctionBuilder` or `Function::new_inst`
/// and add metadata through `add_metadata`.
pub struct Inst {
  priv owner : Ref[FunctionOwnerContext]
  id : Int
  results : Array[Value] // Values produced (empty for void instructions)
  mut opcode : Opcode // The operation
  args : Array[Value] // Generic MilkIR spelling for operands.
  operands : Array[Value] // Input values
  metadata : Array[Metadata]
}

///|
pub impl Debug for Inst with fn to_repr(self) {
  Repr::record({
    "id": Repr(self.id),
    "results": Repr(self.results),
    "opcode": Repr(self.opcode),
    "args": Repr(self.args),
    "operands": Repr(self.operands),
    "metadata": Repr(self.metadata),
  })
}

///|
/// Hash for CSE/GVN - based on opcode, result types, and operand IDs.
/// Result IDs are definitions rather than part of expression identity.
pub impl Hash for Inst with fn hash_combine(self, hasher) {
  hash_opcode_identity(self.opcode, hasher)
  hasher.combine(self.results.length())
  for result in self.results {
    hasher.combine(result.ty)
  }
  for op in self.operands {
    hasher.combine(op.id)
  }
}

///|
/// Eq for CSE/GVN - result types are part of expression identity.
pub impl Eq for Inst with fn equal(self, other) {
  if !physical_equal(self.owner, other.owner) {
    return false
  }
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
  hasher.combine(opcode)
}

///|
fn opcode_identity_equal(lhs : Opcode, rhs : Opcode) -> Bool {
  lhs == rhs
}

///|
fn Inst::new_with_id(
  owner : Ref[FunctionOwnerContext],
  id : Int,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  { owner, id, results, opcode, args, operands: args, metadata: [] }
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
  Vector(VectorMemoryOp)
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
pub(all) enum VectorIntLane {
  I8
  I16
  I32
  I64
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatLane {
  F32
  F64
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorSignedness {
  Signed
  Unsigned
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorHalf {
  Low
  High
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorBitwiseOp {
  Not
  And
  AndNot
  Or
  Xor
  Bitselect
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorPredicateOp {
  AnyTrue
  AllTrue(VectorIntLane)
  Bitmask(VectorIntLane)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntUnaryOp {
  Abs
  Neg
  Popcnt
  Extend(VectorHalf, VectorSignedness)
  ExtAddPairwise(VectorSignedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntBinaryOp {
  Add
  Sub
  Mul
  AddSaturating(VectorSignedness)
  SubSaturating(VectorSignedness)
  Min(VectorSignedness)
  Max(VectorSignedness)
  AverageUnsigned
  ExtMul(VectorHalf, VectorSignedness)
  Dot16To32Signed
  Q15MulrSaturating
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntShiftOp {
  Left
  Right(VectorSignedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntCompareOp {
  Eq
  Ne
  Lt(VectorSignedness)
  Gt(VectorSignedness)
  Le(VectorSignedness)
  Ge(VectorSignedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatUnaryOp {
  Abs
  Neg
  Sqrt
  Ceil
  Floor
  Trunc
  Nearest
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatBinaryOp {
  Add
  Sub
  Mul
  Div
  Min
  Max
  PseudoMin
  PseudoMax
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatCompareOp {
  Eq
  Ne
  Lt
  Gt
  Le
  Ge
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorConversionOp {
  TruncSatF32ToI32(VectorSignedness)
  TruncSatF64ToI32Zero(VectorSignedness)
  ConvertI32ToF32(VectorSignedness)
  ConvertLowI32ToF64(VectorSignedness)
  DemoteF64ToF32Zero
  PromoteLowF32ToF64
} derive(Debug, Eq, Hash)

///|
/// Vector memory operations consume an already checked effective address.
/// Source-language memory indices, alignment hints, and offsets belong to the
/// frontend.
pub(all) enum VectorMemoryOp {
  LoadExtend(VectorIntLane, VectorSignedness)
  LoadSplat(VectorIntLane)
  LoadZero(VectorIntLane)
  LoadLane(VectorIntLane, Int)
  StoreLane(VectorIntLane, Int)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFmaOp {
  Add
  NegatedAdd
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorRelaxedOp {
  Swizzle
  TruncF32ToI32(VectorSignedness)
  TruncF64ToI32Zero(VectorSignedness)
  Fma(VectorFloatLane, VectorFmaOp)
  LaneSelect(VectorIntLane)
  Min(VectorFloatLane)
  Max(VectorFloatLane)
  Q15MulrSigned
  Dot8To16Signed
  Dot8To32AddSigned
} derive(Debug, Eq, Hash)

///|
/// Language-neutral V128 operations normalized by semantic family.
pub(all) enum VectorOp {
  Const(Bytes)
  Splat(VectorLane)
  ExtractLane(VectorLane, VectorExtension, Int)
  ReplaceLane(VectorLane, Int)
  Shuffle(FixedArray[Int])
  Swizzle
  Bitwise(VectorBitwiseOp)
  Predicate(VectorPredicateOp)
  IntUnary(VectorIntUnaryOp, VectorIntLane)
  IntBinary(VectorIntBinaryOp, VectorIntLane)
  IntShift(VectorIntShiftOp, VectorIntLane)
  IntCompare(VectorIntCompareOp, VectorIntLane)
  Narrow(VectorIntLane, VectorSignedness)
  FloatUnary(VectorFloatUnaryOp, VectorFloatLane)
  FloatBinary(VectorFloatBinaryOp, VectorFloatLane)
  FloatCompare(VectorFloatCompareOp, VectorFloatLane)
  Convert(VectorConversionOp)
  Relaxed(VectorRelaxedOp)
} derive(Debug, Eq, Hash)

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
  FloatConst32(UInt)
  FloatConst64(UInt64)
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

  // Generic memory operations.
  Memory(MemoryOp)

  // Function-scoped context and embedding values.
  GlobalValue(GlobalValue)

  // Dialect extension operations. The core IR treats these conservatively;
  // dialect-owned packages define the opcode set, builders, validation rules,
  // and lowering behavior.
  Ext(ExtOp, Signature)

  // Language-neutral vector operations.
  Vector(VectorOp)
} derive(Debug, Eq, Hash)

///|
pub impl Show for Opcode with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn reject_foreign_opcode_entities(
  owner : Ref[FunctionOwnerContext],
  opcode : Opcode,
) -> Bool {
  if opcode is GlobalValue(global_value) &&
    !physical_equal(owner, global_value.owner) {
    owner.val.record_construction_error(
      ForeignGlobalValue(global_value_id=global_value.id),
    )
    return true
  }
  false
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
/// Function - a complete mutable IR function.
///
/// The public fields are exposed for zero-copy inspection. Callers must not
/// mutate `params`, `results`, `blocks`, `external_symbols`, or the ID counters
/// directly. Use `FunctionBuilder` and the checked `Function`/`Block` methods
/// for structural changes. A function must be verified after its final
/// mutation and immediately before optimization or lowering.
pub struct Function {
  priv owner : Ref[FunctionOwnerContext]
  name : String
  params : Array[(Value, Type)] // Function parameters
  results : Array[Type] // Return types
  blocks : Array[Block] // Basic blocks (block 0 is entry)
  external_symbols : Array[ExternalSymbol]
  global_values : Array[(GlobalValue, GlobalValueData)]
  mut next_value_id : Int // For generating unique value IDs
  mut next_inst_id : Int
  mut next_block_id : Int // For generating unique block IDs
  mut next_global_value_id : Int
}

///|
pub impl Debug for Function with fn to_repr(self) {
  Repr::record({
    "name": Repr(self.name),
    "params": Repr(self.params),
    "results": Repr(self.results),
    "blocks": Repr(self.blocks),
    "external_symbols": Repr(self.external_symbols),
    "global_values": Repr(self.global_values),
    "next_value_id": Repr(self.next_value_id),
    "next_inst_id": Repr(self.next_inst_id),
    "next_block_id": Repr(self.next_block_id),
    "next_global_value_id": Repr(self.next_global_value_id),
  })
}

///|
pub fn Function::new_empty(name : String) -> Function {
  {
    owner: FunctionOwnerContext::new(),
    name,
    params: [],
    results: [],
    blocks: [],
    external_symbols: [],
    global_values: [],
    next_value_id: 0,
    next_inst_id: 0,
    next_block_id: 0,
    next_global_value_id: 0,
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
  Value::new(self.owner, id, ty)
}

///|
/// Create a new basic block
pub fn Function::new_block(self : Function, params : Array[Value]) -> Block {
  if reject_foreign_values(self.owner, params) {
    return Block(self.owner, self.next_block_id)
  }
  let id = self.next_block_id
  self.next_block_id = self.next_block_id + 1
  let block = Block::new_with_params(self.owner, id, params)
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
  if reject_foreign_values(self.owner, args) ||
    reject_foreign_values(self.owner, results) ||
    reject_foreign_opcode_entities(self.owner, opcode) {
    return Inst::new_with_id(self.owner, self.next_inst_id, opcode, [], [])
  }
  let inst = Inst::new_with_id(
    self.owner,
    self.next_inst_id,
    opcode,
    args,
    results,
  )
  self.next_inst_id = self.next_inst_id + 1
  inst
}

///|
fn Function::owns_value(self : Function, value : Value) -> Bool {
  physical_equal(self.owner, value.owner)
}

///|
fn Function::owns_block(self : Function, block : Block) -> Bool {
  physical_equal(self.owner, block.owner)
}

///|
fn Function::owns_inst(self : Function, inst : Inst) -> Bool {
  physical_equal(self.owner, inst.owner)
}

///|
fn Function::owns_global_value(
  self : Function,
  global_value : GlobalValue,
) -> Bool {
  physical_equal(self.owner, global_value.owner)
}

///|
fn Function::record_construction_error(
  self : Function,
  error : VerifyError,
) -> Unit {
  self.owner.val.record_construction_error(error)
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

///|
/// Declare or reuse an identical function-scoped global value.
pub fn Function::declare_global_value(
  self : Function,
  data : GlobalValueData,
) -> GlobalValue {
  for entry in self.global_values {
    if entry.1 == data {
      return entry.0
    }
  }
  let global_value = GlobalValue::new(self.owner, self.next_global_value_id)
  self.next_global_value_id = self.next_global_value_id + 1
  self.global_values.push((global_value, data))
  global_value
}

///|
/// Return the declaration for an owned global-value handle.
pub fn Function::global_value_data(
  self : Function,
  global_value : GlobalValue,
) -> GlobalValueData? {
  if !self.owns_global_value(global_value) ||
    global_value.id < 0 ||
    global_value.id >= self.global_values.length() {
    return None
  }
  let entry = self.global_values[global_value.id]
  if entry.0.id != global_value.id {
    return None
  }
  Some(entry.1)
}
