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

///|
/// Control flow signal for branching (not an error, but uses exception mechanism)
pub(all) suberror ControlSignal {
  Branch(Int) // Branch with relative depth
  Return // Return from function
} derive(Show)
