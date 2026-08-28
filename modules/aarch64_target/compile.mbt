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
pub struct CompilationSession {
  priv allocation : @vcode_regalloc.AllocationSession
  priv allocation_environment : @vcode_regalloc.VCodeAllocationEnvironment
}

///|
pub fn CompilationSession::new() -> CompilationSession {
  {
    allocation: @vcode_regalloc.AllocationSession::new(),
    allocation_environment: @vcode_regalloc.VCodeAllocationEnvironment::new(
      allocatable_physical_regs(),
      spill_scratch_regs(),
    ),
  }
}

///|
fn CompilationSession::compile_selected_function(
  self : CompilationSession,
  function : @vcode.Function[AArch64Inst],
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
  on_event(RegallocStarted)
  let allocation = allocate_verified(
    function,
    on_phase=Some(phase => {
      match phase {
        Some(name) => on_event(RegallocPhaseStarted(name))
        None => on_event(RegallocPhasesFinished)
      }
    }),
    on_statistics=Some(statistics => on_event(RegallocLoopMeasured(statistics))),
    verify_allocation~,
    allocation_session=self.allocation,
    allocation_environment=self.allocation_environment,
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

///|
/// Compile VCode produced by `select` without repeating target validation.
pub fn compile_selected(
  selected : SelectedFunction,
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
  CompilationSession::new().compile_selected_function(
    selected.constructed.function,
    on_event~,
    verify_allocation~,
  )
}

///|
/// Compile selected VCode while retaining allocator scratch capacity for the
/// next serial call on this session.
pub fn CompilationSession::compile_selected(
  self : CompilationSession,
  selected : SelectedFunction,
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
  self.compile_selected_function(
    selected.constructed.function,
    on_event~,
    verify_allocation~,
  )
}

///|
/// Compile externally supplied AArch64 VCode through the safe validated entry.
pub fn compile(
  function : @vcode.Function[AArch64Inst],
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.UnlinkedCodeObject, Int) raise AArch64CompileError {
  verify_vcode(function) catch {
    error => raise TargetValidationFailed(cause=error)
  }
  CompilationSession::new().compile_selected_function(
    function,
    on_event~,
    verify_allocation~,
  )
}
