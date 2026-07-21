///|
pub suberror X64CompileError {
  TargetValidationFailed(cause~ : TargetVCodeVerifyError)
  AllocationFailed(cause~ : X64AllocationError)
  FramePlanningFailed(cause~ : X64FrameError)
  EmissionFailed(cause~ : X64EmitError)
} derive(Debug)

///|
pub impl Show for X64CompileError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
/// Compiles selected x64 VCode through allocation, frame planning, and
/// emission. Each stage validates the invariant it introduces without
/// revalidating invariants already established by this pipeline.
pub fn compile(
  function : @vcode.Function[X64Inst],
) -> (@code_object.UnlinkedCodeObject, Int) raise X64CompileError {
  verify_vcode(function) catch {
    error => raise TargetValidationFailed(cause=error)
  }
  let allocation = allocate_verified(function) catch {
    error => raise AllocationFailed(cause=error)
  }
  let frame = plan_frame_verified(function, allocation) catch {
    error => raise FramePlanningFailed(cause=error)
  }
  let object = emit_verified(function, allocation, frame) catch {
    error => raise EmissionFailed(cause=error)
  }
  (object, frame.frame_size())
}
