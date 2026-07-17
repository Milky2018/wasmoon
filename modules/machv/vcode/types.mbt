///|
pub(all) enum RegClass {
  Int
  Float
  Vector
} derive(Eq, Debug, Hash)

///|
fn RegClass::text(self : RegClass) -> String {
  match self {
    Int => "int"
    Float => "float"
    Vector => "vector"
  }
}

///|
pub type ValueType = @semantic.ValueType

///|
pub fn reg_class_for_value_type(ty : ValueType) -> RegClass {
  match ty {
    I32 | I64 | Ptr64 | GcRef64 => Int
    F32 | F64 => Float
    V128 => Vector
  }
}

///|
fn value_type_text(ty : ValueType) -> String {
  match ty {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    Ptr64 => "ptr64"
    GcRef64 => "gcref64"
  }
}

///|
pub struct PhysicalReg {
  id : Int
  class : RegClass
} derive(Eq)

///|
pub fn PhysicalReg::new(id : Int, class : RegClass) -> PhysicalReg {
  { id, class }
}

///|
pub impl Debug for PhysicalReg with fn to_repr(self) {
  Repr::literal("p\{self.id}:\{self.class.text()}")
}

///|
pub struct Value {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Value::new(owner : Ref[Unit], id : Int) -> Value {
  { owner, id }
}

///|
pub impl Eq for Value with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Debug for Value with fn to_repr(self) {
  Repr::literal("v\{self.id}")
}

///|
pub impl Show for Value with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub struct Block {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Block::new(owner : Ref[Unit], id : Int) -> Block {
  { owner, id }
}

///|
pub impl Eq for Block with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Debug for Block with fn to_repr(self) {
  Repr::literal("block\{self.id}")
}

///|
pub impl Show for Block with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub struct Instruction {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Instruction::new(owner : Ref[Unit], id : Int) -> Instruction {
  { owner, id }
}

///|
pub impl Eq for Instruction with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Debug for Instruction with fn to_repr(self) {
  Repr::literal("i\{self.id}")
}

///|
pub impl Show for Instruction with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub(all) enum PointPlacement {
  Before
  After
} derive(Eq, Debug)

///|
pub struct ProgramPoint {
  priv owner : Ref[Unit]
  priv instruction : Instruction
  priv placement : PointPlacement
}

///|
fn ProgramPoint::new(
  owner : Ref[Unit],
  instruction : Instruction,
  placement : PointPlacement,
) -> ProgramPoint {
  { owner, instruction, placement }
}

///|
pub impl Eq for ProgramPoint with fn equal(self, other) {
  physical_equal(self.owner, other.owner) &&
  self.instruction == other.instruction &&
  self.placement == other.placement
}

///|
pub impl Debug for ProgramPoint with fn to_repr(self) {
  let placement = match self.placement {
    Before => "before"
    After => "after"
  }
  Repr::literal("\{placement}(\{to_repr(self.instruction)})")
}

///|
pub(all) enum OperandTiming {
  Early
  Late
} derive(Eq, Debug)

///|
pub(all) enum OperandConstraint {
  Any
  Fixed(PhysicalReg)
  TiedTo(Int)
} derive(Eq, Debug)

///|
pub(all) enum OperandRole {
  Use
  Def
} derive(Eq, Debug)

///|
pub struct Input {
  value : Value
  constraint : OperandConstraint
  timing : OperandTiming
}

///|
pub fn Input::any(value : Value) -> Input {
  { value, constraint: Any, timing: Early }
}

///|
pub fn Input::fixed(value : Value, reg : PhysicalReg) -> Input {
  { value, constraint: Fixed(reg), timing: Early }
}

///|
pub fn Input::with_timing(self : Input, timing : OperandTiming) -> Input {
  { ..self, timing, }
}

///|
pub struct Output {
  ty : ValueType
  constraint : OperandConstraint
  timing : OperandTiming
}

///|
pub fn Output::any(ty : ValueType) -> Output {
  { ty, constraint: Any, timing: Late }
}

///|
pub fn Output::fixed(ty : ValueType, reg : PhysicalReg) -> Output {
  { ty, constraint: Fixed(reg), timing: Late }
}

///|
pub fn Output::tied(ty : ValueType, operand_index : Int) -> Output {
  { ty, constraint: TiedTo(operand_index), timing: Late }
}

///|
pub fn Output::with_timing(self : Output, timing : OperandTiming) -> Output {
  { ..self, timing, }
}

///|
priv struct OperandData {
  value : Value
  role : OperandRole
  constraint : OperandConstraint
  timing : OperandTiming
  mut tie_id : Int
}

///|
pub struct Operand {
  value : Value
  role : OperandRole
  constraint : OperandConstraint
  timing : OperandTiming
  tie_id : Int
} derive(Eq, Debug)

///|
fn OperandData::snapshot(self : OperandData) -> Operand {
  {
    value: self.value,
    role: self.role,
    constraint: self.constraint,
    timing: self.timing,
    tie_id: self.tie_id,
  }
}

///|
pub struct Edge {
  target : Block
  arguments : Array[Value]
}

///|
pub fn Edge::new(target : Block, arguments : Array[Value]) -> Edge {
  { target, arguments: arguments.copy() }
}

///|
fn Edge::copy(self : Edge) -> Edge {
  Edge::new(self.target, self.arguments)
}

///|
pub(all) enum SafepointKind {
  Gc
  Cancellation
  GcAndCancellation
} derive(Eq, Debug)

///|
pub struct InstructionMetadata {
  source_id : Int?
  trap_id : Int?
  safepoint : SafepointKind?
  live_gc_roots : Array[Value]
  symbol : String?
}

///|
pub fn InstructionMetadata::empty() -> InstructionMetadata {
  {
    source_id: None,
    trap_id: None,
    safepoint: None,
    live_gc_roots: [],
    symbol: None,
  }
}

///|
pub fn InstructionMetadata::safepoint(
  live_gc_roots : Array[Value],
) -> InstructionMetadata {
  {
    source_id: None,
    trap_id: None,
    safepoint: Some(Gc),
    live_gc_roots: live_gc_roots.copy(),
    symbol: None,
  }
}

///|
pub fn InstructionMetadata::new(
  source_id? : Int,
  trap_id? : Int,
  safepoint? : SafepointKind,
  live_gc_roots? : Array[Value] = [],
  symbol? : String,
) -> InstructionMetadata {
  { source_id, trap_id, safepoint, live_gc_roots: live_gc_roots.copy(), symbol }
}

///|
fn InstructionMetadata::copy(self : InstructionMetadata) -> InstructionMetadata {
  {
    source_id: self.source_id,
    trap_id: self.trap_id,
    safepoint: self.safepoint,
    live_gc_roots: self.live_gc_roots.copy(),
    symbol: self.symbol,
  }
}

///|
pub suberror VCodeBuildError {
  InvalidParameter(index~ : Int)
  InvalidBlockParameter(block~ : Block, index~ : Int)
  ForeignBlock(block~ : Block)
  ForeignValue(value~ : Value)
  InvalidOperandConstraint
  DuplicateTerminator(block~ : Block)
  BlockAlreadyTerminated(block~ : Block)
  InvalidLayout
} derive(Eq, Debug)

///|
pub impl Show for VCodeBuildError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub suberror VCodeVerifyError {
  EmptyFunction
  MissingTerminator(block~ : Block)
  ForeignValue(instruction~ : Instruction, value~ : Value)
  ForeignBlock(instruction~ : Instruction, block~ : Block)
  InvalidEdgeArity(instruction~ : Instruction, block~ : Block)
  EdgeClassMismatch(instruction~ : Instruction, block~ : Block, index~ : Int)
  InvalidTie(instruction~ : Instruction, operand~ : Int, tied_to~ : Int)
  FixedRegisterClassMismatch(instruction~ : Instruction, operand~ : Int)
  DuplicateClobber(instruction~ : Instruction, reg~ : PhysicalReg)
  InvalidSafepointRoot(instruction~ : Instruction, value~ : Value)
  UnreachableBlock(block~ : Block)
  UseBeforeDefinition(instruction~ : Instruction, value~ : Value)
  DefinitionDoesNotDominate(instruction~ : Instruction, value~ : Value)
  InvalidLayout
} derive(Eq, Debug)

///|
pub impl Show for VCodeVerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}
