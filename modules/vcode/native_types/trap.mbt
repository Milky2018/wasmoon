///|
/// Stable payload carried by native trap instructions on all targets.
/// Runtime embeddings decode this payload separately from host error codes.
pub fn TrapReason::native_payload(self : TrapReason) -> UInt {
  match self {
    Unreachable => 0U
    MemoryOutOfBounds => 1U
    IndirectCallTypeMismatch => 2U
    InvalidConversionToInteger => 3U
    IntegerDivisionByZero => 4U
    IntegerOverflow => 5U
    UnsupportedOperation => 6U
    TableOutOfBounds => 7U
    NullReference => 8U
    UnalignedAtomic => 9U
    StackOverflow => 10U
    UninitializedElement => 11U
    UndefinedElement => 12U
    AtomicWaitNonSharedMemory => 13U
    User(payload) => payload.reinterpret_as_uint() & 0xFFFFU
  }
}
