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
fn[T] CompilationSession::compile_selected_function(
  self : CompilationSession,
  function : @vcode.Function[AArch64Inst],
  finish : (@code_object.CodeData) -> T raise @code_object.CodeObjectVerifyError,
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (T, Int) raise AArch64CompileError {
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
  let result = finish(object) catch {
    error => raise EmissionFailed(cause=InvalidCodeObject(cause=error))
  }
  on_event(EmissionFinished)
  (result, frame.frame_size())
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
    data => data.freeze(),
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
    data => data.freeze(),
    on_event~,
    verify_allocation~,
  )
}

///|
pub(all) struct CompilationDiagnostics {
  target_vcode : String
  allocated_vcode : String
  object : @code_object.UnlinkedCodeObject
}

///|
pub fn diagnose_selected(
  selected : SelectedFunction,
) -> CompilationDiagnostics raise AArch64CompileError {
  let function = selected.constructed.function
  let allocation = allocate(function) catch {
    error => raise AllocationFailed(cause=error)
  }
  let frame = plan_frame(function, allocation) catch {
    error => raise FramePlanningFailed(cause=error)
  }
  let object = emit(function, allocation, frame) catch {
    error => raise EmissionFailed(cause=error)
  }
  {
    target_vcode: function.summary(),
    allocated_vcode: function.summary() + allocation.summary(),
    object,
  }
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
    data => data.freeze(),
    on_event~,
    verify_allocation~,
  )
}

///|
/// Compile to fresh mutable code data without an intermediate immutable snapshot.
/// The returned data is verified at return and independent of session scratch.
/// Callers that mutate it must revalidate it before installation.
pub fn CompilationSession::compile_selected_data(
  self : CompilationSession,
  selected : SelectedFunction,
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify_allocation? : Bool = true,
) -> (@code_object.CodeData, Int) raise AArch64CompileError {
  self.compile_selected_function(
    selected.constructed.function,
    data => {
      data.verify()
      data.shrink_to_fit()
      data
    },
    on_event~,
    verify_allocation~,
  )
}

///|
/// Release retained allocator buffers between serial compilations. Returned
/// results remain valid, and this session can compile again afterwards.
/// Must not be called from a compilation observer during an active job.
pub fn CompilationSession::release_scratch(self : CompilationSession) -> Unit {
  self.allocation.release_scratch()
}
