///|
#derive(Eq, Debug)
pub(all) enum NativeTarget {
  X64
  AArch64
}

///|
// One persistent allocator session belongs to exactly one target. Target-specific
// selection, validation errors, and linking rules stay behind this boundary.
priv enum NativeBackend {
  X64(@x64_target.CompilationSession)
  AArch64(@aarch64_target.CompilationSession)
}

///|
fn NativeBackend::new(
  target : NativeTarget,
  lse_atomic_add~ : Bool = false,
) -> NativeBackend {
  match target {
    X64 => X64(@x64_target.CompilationSession::new())
    AArch64 => AArch64(@aarch64_target.CompilationSession::new(lse_atomic_add~))
  }
}

///|
fn NativeBackend::target(self : NativeBackend) -> NativeTarget {
  match self {
    X64(_) => X64
    AArch64(_) => AArch64
  }
}

///|
fn native_lowering_context(
  target : NativeTarget,
) -> @vcode.LoweringContext raise JitPipelineError {
  let abi = wasm_internal_abi(target) catch {
    error =>
      match target {
        X64 => raise X64AbiInvalid(cause=error)
        AArch64 => raise AArch64AbiInvalid(cause=error)
      }
  }
  @vcode.LoweringContext::new(abi)
}

///|
fn NativeBackend::compile(
  self : NativeBackend,
  name : String,
  protocol : @native.CallProtocol,
  signature : @native.Signature,
  context : @vcode.LoweringContext,
  lower : (@native_lowering.TargetSink) -> Unit raise JitPipelineError,
  on_event~ : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
  verify~ : () -> Bool = fn() { true },
  on_diagnostics~ : ((String, String) -> Unit)? = None,
) -> (@code_object.UnlinkedCodeObject, Int32) raise JitPipelineError {
  match self {
    X64(compilation) => {
      let session = @x64_target.DirectLoweringSession::new(
        name,
        protocol,
        signature.params,
        signature.results,
        context,
        on_event~,
      ) catch {
        error => raise X64LoweringFailed(cause=error)
      }
      lower(session.sink())
      let selected = session.finish_selected(verify_selected=verify()) catch {
        error => raise X64LoweringFailed(cause=error)
      }
      compilation.compile_selected(
        selected,
        on_event~,
        verify_allocation=verify(),
        on_diagnostics~,
      ) catch {
        error => raise X64CompilationFailed(cause=error)
      }
    }
    AArch64(compilation) => {
      let session = @aarch64_target.DirectLoweringSession::new(
        name,
        protocol,
        signature.params,
        signature.results,
        context,
        on_event~,
      ) catch {
        error => raise AArch64LoweringFailed(cause=error)
      }
      lower(session.sink())
      let selected = session.finish_selected(verify_selected=verify()) catch {
        error => raise AArch64LoweringFailed(cause=error)
      }
      compilation.compile_selected(
        selected,
        on_event~,
        verify_allocation=verify(),
        on_diagnostics~,
      ) catch {
        error => raise AArch64CompilationFailed(cause=error)
      }
    }
  }
}
