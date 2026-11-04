///|
/// Lifecycle phase of a Store-owned native invocation.
#derive(Debug, Eq)
pub(all) enum NativeInvocationPhase {
  Active
  Parked
}

///|
/// Invalid transition in the Store-owned native invocation state machine.
#derive(Debug, Eq)
pub suberror NativeExecutionStateError {
  ExecutionStateSealed
  UnknownInvocation(Int64)
  InvocationNotActive(Int64)
  InvocationNotParked(Int64)
  InvocationNotCurrent(Int64)
}

///|
pub impl Show for NativeExecutionStateError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}
