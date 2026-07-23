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
///
/// `on_event` is an observation-only seam. It must not mutate `function` or any
/// compiler object reachable while the callback runs.
pub fn compile(
  function : @vcode.Function[X64Inst],
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
) -> (@code_object.UnlinkedCodeObject, Int) raise X64CompileError {
  verify_vcode(function) catch {
    error => raise TargetValidationFailed(cause=error)
  }
  on_event(RegallocStarted)
  let allocation = allocate_verified(function) catch {
    error => raise AllocationFailed(cause=error)
  }
  on_event(RegallocFinished(allocation.statistics()))
  on_event(FramePlanningStarted)
  let frame = plan_frame_verified(function, allocation) catch {
    error => raise FramePlanningFailed(cause=error)
  }
  on_event(FramePlanningFinished)
  on_event(EmissionStarted)
  let object = emit_verified(function, allocation, frame) catch {
    error => raise EmissionFailed(cause=error)
  }
  on_event(EmissionFinished)
  (object, frame.frame_size())
}
