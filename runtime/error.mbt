///|
pub(all) suberror RuntimeError {
  StackUnderflow
  StackOverflow
  TypeMismatch
  OutOfBoundsMemoryAccess
  OutOfBoundsTableAccess
  UndefinedElement
  UninitializedElement
  IndirectCallTypeMismatch
  DivisionByZero
  IntegerOverflow
  InvalidConversion
  Unreachable
  CallStackExhausted
} derive(Show)
