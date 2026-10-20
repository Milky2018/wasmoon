///|
/// Lifecycle phase of a Store-owned native invocation.
pub(all) enum NativeInvocationPhase {
  Active
  Parked
} derive(Debug, Eq)

///|
/// Invalid transition in the Store-owned native invocation state machine.
pub suberror NativeExecutionStateError {
  ExecutionStateSealed
  UnknownInvocation(Int64)
  InvocationNotActive(Int64)
  InvocationNotParked(Int64)
  InvocationNotCurrent(Int64)
} derive(Debug, Eq)

///|
pub impl Show for NativeExecutionStateError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}
