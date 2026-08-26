///|
/// Exact target-neutral value types carried by semantic MachV SSA values.
///
/// `Ptr64` is an untraced address or opaque handle. `GcRef64` is a nullable
/// managed reference and must be reported as a root at GC safepoints.
pub(all) enum ValueType {
  I32
  I64
  F32
  F64
  V128
  Ptr64
  GcRef64
} derive(Debug, Eq, Hash)

///|
pub impl Show for ValueType with fn output(self, logger) {
  logger.write_string(
    match self {
      I32 => "i32"
      I64 => "i64"
      F32 => "f32"
      F64 => "f64"
      V128 => "v128"
      Ptr64 => "ptr64"
      GcRef64 => "gcref64"
    },
  )
}

///|
/// Ordered logical parameters and results. ABI placement is intentionally
/// absent.
pub struct Signature {
  params : Array[ValueType]
  results : Array[ValueType]
} derive(Debug, Eq, Hash)

///|
pub fn Signature::new(
  params : Array[ValueType],
  results : Array[ValueType],
) -> Signature {
  { params: params.copy(), results: results.copy(), }
}

///|
pub(all) enum CallProtocol {
  Internal
  Platform
} derive(Debug, Eq, Hash)

///|
pub struct CodeSymbol {
  name : String
} derive(Debug, Eq, Hash)

///|
pub fn CodeSymbol::new(name : String) -> CodeSymbol {
  { name, }
}

///|
pub struct ExternalSymbol {
  name : String
} derive(Debug, Eq, Hash)

///|
pub fn ExternalSymbol::new(name : String) -> ExternalSymbol {
  { name, }
}

///|
pub struct DataSymbol {
  name : String
} derive(Debug, Eq, Hash)

///|
pub fn DataSymbol::new(name : String) -> DataSymbol {
  { name, }
}

///|
/// Opaque embedding-context field identity with its semantic value type.
///
/// The identity carries no byte offset or target addressing mode. The
/// embedding target environment resolves it during target lowering.
pub struct EnvironmentField {
  name : String
  value_type : ValueType
} derive(Debug, Eq, Hash)

///|
pub fn EnvironmentField::new(
  name : String,
  value_type : ValueType,
) -> EnvironmentField {
  { name, value_type, }
}

///|
/// Whether an embedding context field may be reused during one function
/// invocation.
///
/// `Stable` grants reuse permission for the invocation. `Mutable` requires each
/// operation to observe the current field value. Target lowering may
/// rematerialize either form.
pub(all) enum EnvironmentFieldStability {
  Stable
  Mutable
} derive(Debug, Eq, Hash)

///|
pub(all) enum Signedness {
  Signed
  Unsigned
} derive(Debug, Eq, Hash)

///|
pub(all) enum IntegerType {
  I32
  I64
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatType {
  F32
  F64
} derive(Debug, Eq, Hash)

///|
pub(all) enum ConversionMode {
  Trapping
  Saturating
} derive(Debug, Eq, Hash)

///|
pub(all) enum Endianness {
  Little
  Big
} derive(Debug, Eq, Hash)

///|
pub(all) enum AccessWidth {
  W8
  W16
  W32
  W64
  W128
} derive(Debug, Eq, Hash)

///|
pub(all) enum LoadExtension {
  None
  Signed
  Unsigned
} derive(Debug, Eq, Hash)

///|
pub(all) enum MemoryEffect {
  None
  Read
  Write
  ReadWrite
} derive(Debug, Eq, Hash)

///|
/// Canonical observable behavior of one semantic operation.
pub struct OperationSemantics {
  memory : MemoryEffect
  may_trap : Bool
  may_unwind : Bool
  gc_safepoint : Bool
  cancellation_safepoint : Bool
  returns_twice : Bool
} derive(Debug, Eq, Hash)

///|
pub fn OperationSemantics::pure() -> OperationSemantics {
  {
    memory: None,
    may_trap: false,
    may_unwind: false,
    gc_safepoint: false,
    cancellation_safepoint: false,
    returns_twice: false,
  }
}

///|
pub fn OperationSemantics::must_preserve_if_unused(
  self : OperationSemantics,
) -> Bool {
  self.memory != None ||
  self.may_trap ||
  self.may_unwind ||
  self.gc_safepoint ||
  self.cancellation_safepoint ||
  self.returns_twice
}

///|
/// Explicit call behavior. Protocol and callee identity never imply effects.
pub struct CallBehavior {
  memory : MemoryEffect
  may_trap : Bool
  may_unwind : Bool
  gc_safepoint : Bool
  cancellation_safepoint : Bool
  returns_twice : Bool
} derive(Debug, Eq, Hash)

///|
pub fn CallBehavior::conservative() -> CallBehavior {
  {
    memory: ReadWrite,
    may_trap: true,
    may_unwind: true,
    gc_safepoint: true,
    cancellation_safepoint: true,
    returns_twice: false,
  }
}

///|
pub fn CallBehavior::new(
  memory : MemoryEffect,
  may_trap : Bool,
  may_unwind : Bool,
  gc_safepoint : Bool,
  cancellation_safepoint : Bool,
  returns_twice? : Bool = false,
) -> CallBehavior {
  {
    memory,
    may_trap,
    may_unwind,
    gc_safepoint,
    cancellation_safepoint,
    returns_twice,
  }
}

///|
pub fn CallBehavior::semantics(self : CallBehavior) -> OperationSemantics {
  {
    memory: self.memory,
    may_trap: self.may_trap,
    may_unwind: self.may_unwind,
    gc_safepoint: self.gc_safepoint,
    cancellation_safepoint: self.cancellation_safepoint,
    returns_twice: self.returns_twice,
  }
}

///|
pub(all) enum SafepointKind {
  Gc
  Cancellation
  GcAndCancellation
} derive(Debug, Eq, Hash)

///|
pub(all) enum TrapReason {
  Unreachable
  IntegerDivisionByZero
  IntegerOverflow
  InvalidConversionToInteger
  MemoryOutOfBounds
  TableOutOfBounds
  IndirectCallTypeMismatch
  NullReference
  UnalignedAtomic
  UnsupportedOperation
  StackOverflow
  User(Int)
} derive(Debug, Eq, Hash)

///|
pub struct SourceLocation {
  file : String
  line : Int
  column : Int
} derive(Debug, Eq, Hash)

///|
pub fn SourceLocation::new(
  file : String,
  line : Int,
  column : Int,
) -> SourceLocation {
  { file, line, column, }
}

///|
fn SourceLocation::is_valid(self : SourceLocation) -> Bool {
  !self.file.is_empty() && self.line >= 0 && self.column >= 0
}
