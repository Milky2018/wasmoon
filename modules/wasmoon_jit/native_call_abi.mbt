///|
/// The compiler and its entry/hostcall bridges use one Wasm-internal ABI.
/// Platform C calling conventions remain local to each trampoline emitter.
fn wasm_internal_abi(
  target : NativeTarget,
) -> @vcode.InternalAbi raise @vcode.InternalAbiError {
  match target {
    AArch64 =>
      @vcode.InternalAbi::new(
        0,
        8,
        [1, 2, 3, 4, 5, 6, 7],
        [0, 1, 2, 3, 4, 5, 6, 7],
        [0, 1, 2, 3, 4, 5, 6, 7],
        [0, 1, 2, 3, 4, 5, 6, 7],
      )
    X64 =>
      @vcode.InternalAbi::new(
        7,
        12,
        [6, 2, 1, 8, 9],
        [0, 1, 2, 3, 4, 5, 6, 7],
        [0, 2, 1, 8, 9, 6, 7, 10],
        [0, 1, 2, 3, 4, 5, 6, 7],
      )
  }
}

///|
fn wasm_internal_bridge_plan(
  param_types : ArrayView[@types.ValueType],
  result_types : ArrayView[@types.ValueType],
  target : NativeTarget,
) -> @vcode.InternalCallPlan raise HostcallImportTrampolineError {
  let params : Array[@native.ValueType] = [Ptr64]
  for ty in param_types {
    params.push(wasm_value_type(ty))
  }
  let signature = @native.Signature::new(
    params,
    result_types.map(wasm_value_type),
  )
  wasm_internal_abi(target).call_plan(signature) catch {
    error =>
      raise UnsupportedHostcallImportTrampoline(message=error.to_string())
  }
}
