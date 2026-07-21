///|
pub(all) enum RegClass {
  Int
  FpVector
} derive(Eq, Debug, Hash)

///|
fn RegClass::text(self : RegClass) -> String {
  match self {
    Int => "int"
    FpVector => "fpvec"
  }
}

///|
pub type ValueType = @semantic.ValueType

///|
pub fn reg_class_for_value_type(ty : ValueType) -> RegClass {
  match ty {
    I32 | I64 | Ptr64 | GcRef64 => Int
    F32 | F64 | V128 => FpVector
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
pub fn ProgramPoint::instruction(self : ProgramPoint) -> Instruction {
  self.instruction
}

///|
pub fn ProgramPoint::placement(self : ProgramPoint) -> PointPlacement {
  self.placement
}

///|
pub(all) enum OperandTiming {
  Early
  Late
} derive(Eq, Debug)

///|
pub(all) enum OperandConstraint {
  Any
  AnyLocation
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
  preference : PhysicalReg?
  timing : OperandTiming
}

///|
pub fn Input::any(value : Value) -> Input {
  { value, constraint: Any, preference: None, timing: Early }
}

///|
/// Keep an input in its allocated register or spill slot. This is intended for
/// target operations, such as ABI argument setup, whose emitter can consume a
/// stack-resident value directly instead of requiring every input in a register
/// at the same program point.
pub fn Input::any_location(value : Value) -> Input {
  { value, constraint: AnyLocation, preference: None, timing: Early }
}

///|
pub fn Input::fixed(value : Value, reg : PhysicalReg) -> Input {
  { value, constraint: Fixed(reg), preference: None, timing: Early }
}

///|
/// Prefer a physical register without making it an allocation constraint.
pub fn Input::with_preference(self : Input, preference : PhysicalReg) -> Input {
  { ..self, preference: Some(preference) }
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
  preference : PhysicalReg?
  timing : OperandTiming
  mut tie_id : Int
}

///|
pub struct Operand {
  value : Value
  role : OperandRole
  constraint : OperandConstraint
  preference : PhysicalReg?
  timing : OperandTiming
  tie_id : Int
} derive(Eq, Debug)

///|
fn OperandData::snapshot(self : OperandData) -> Operand {
  {
    value: self.value,
    role: self.role,
    constraint: self.constraint,
    preference: self.preference,
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
pub type SafepointKind = @semantic.SafepointKind

///|
pub(all) enum SymbolReference {
  Code(@semantic.CodeSymbol)
  External(@semantic.ExternalSymbol)
  Data(@semantic.DataSymbol)
} derive(Eq, Debug)

///|
pub struct InstructionMetadata {
  source : @semantic.SourceLocation?
  trap : @semantic.TrapReason?
  safepoint : SafepointKind?
  live_gc_roots : Array[Value]
  symbol : SymbolReference?
  stack_map : @semantic.StackMapMetadata?
}

///|
pub fn InstructionMetadata::empty() -> InstructionMetadata {
  {
    source: None,
    trap: None,
    safepoint: None,
    live_gc_roots: [],
    symbol: None,
    stack_map: None,
  }
}

///|
pub fn InstructionMetadata::safepoint(
  live_gc_roots : Array[Value],
) -> InstructionMetadata {
  {
    source: None,
    trap: None,
    safepoint: Some(Gc),
    live_gc_roots: live_gc_roots.copy(),
    symbol: None,
    stack_map: None,
  }
}

///|
pub fn InstructionMetadata::new(
  source? : @semantic.SourceLocation,
  trap? : @semantic.TrapReason,
  safepoint? : SafepointKind,
  live_gc_roots? : Array[Value] = [],
  symbol? : SymbolReference,
  stack_map? : @semantic.StackMapMetadata,
) -> InstructionMetadata {
  {
    source,
    trap,
    safepoint,
    live_gc_roots: live_gc_roots.copy(),
    symbol,
    stack_map,
  }
}

///|
fn InstructionMetadata::copy(self : InstructionMetadata) -> InstructionMetadata {
  {
    source: self.source,
    trap: self.trap,
    safepoint: self.safepoint,
    live_gc_roots: self.live_gc_roots.copy(),
    symbol: self.symbol,
    stack_map: self.stack_map,
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
  InvalidAnyLocationConstraint(instruction~ : Instruction, operand~ : Int)
  FixedRegisterClassMismatch(instruction~ : Instruction, operand~ : Int)
  InvalidOperandPreference(instruction~ : Instruction, operand~ : Int)
  DuplicateClobber(instruction~ : Instruction, reg~ : PhysicalReg)
  InvalidSafepointRoot(instruction~ : Instruction, value~ : Value)
  InvalidStackMap(instruction~ : Instruction)
  UnreachableBlock(block~ : Block)
  UseBeforeDefinition(instruction~ : Instruction, value~ : Value)
  DefinitionDoesNotDominate(instruction~ : Instruction, value~ : Value)
  InvalidLayout
} derive(Eq, Debug)

///|
pub impl Show for VCodeVerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}
