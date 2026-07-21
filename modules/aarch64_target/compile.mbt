///|
pub suberror AArch64CompileError {
  TargetValidationFailed(cause~ : TargetVCodeVerifyError)
  AllocationFailed(cause~ : AArch64AllocationError)
  FramePlanningFailed(cause~ : AArch64FrameError)
  EmissionFailed(cause~ : AArch64EmitError)
} derive(Debug)

///|
pub impl Show for AArch64CompileError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
/// Compiles selected AArch64 VCode through allocation, frame planning, and
/// emission. Each stage validates the invariant it introduces without
/// revalidating invariants already established by this pipeline.
pub fn compile(
  function : @vcode.Function[AArch64Inst],
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
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
