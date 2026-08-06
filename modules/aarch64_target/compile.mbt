///|
pub suberror AArch64CompileError {
  TargetValidationFailed(cause~ : TargetVCodeVerifyError)
  AllocationFailed(cause~ : AArch64AllocationError)
  FramePlanningFailed(cause~ : AArch64FrameError)
  EmissionFailed(cause~ : AArch64EmitError)
} derive(Debug)

///|
pub impl Show for AArch64CompileError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
/// Compiles selected AArch64 VCode through allocation, frame planning, and
/// emission. Each stage validates the invariant it introduces without
/// revalidating invariants already established by this pipeline.
///
/// `on_event` is an observation-only seam. It must not mutate `function` or any
/// compiler object reachable while the callback runs.
pub fn compile(
  function : @vcode.Function[AArch64Inst],
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
  verify_vcode(function) catch {
    error => raise TargetValidationFailed(cause=error)
  }
  on_event(RegallocStarted)
  let allocation = allocate_verified(
    function,
    on_phase=Some(phase => {
      match phase {
        Some(name) => on_event(RegallocPhaseStarted(name))
        None => on_event(RegallocPhasesFinished)
      }
    }),
    verify_allocation~,
  ) catch {
    error => raise AllocationFailed(cause=error)
  }
  on_event(RegallocFinished(allocation.statistics()))
  on_event(FramePlanningStarted)
  let frame = plan_frame_verified(function, allocation) catch {
    error => raise FramePlanningFailed(cause=error)
  }
  on_event(FramePlanningFinished)
  on_event(EmissionStarted)
  let object = emit_with_branch_fallback(function, allocation, frame) catch {
    error => raise EmissionFailed(cause=error)
  }
  on_event(EmissionFinished)
  (object, frame.frame_size())
}
