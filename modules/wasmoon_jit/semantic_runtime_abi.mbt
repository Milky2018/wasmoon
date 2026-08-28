///|
fn hidden_safepoint_abi(
  symbol : @semantic_machv.ExternalSymbol,
) -> @semantic_machv.HiddenSafepointAbi {
  @semantic_machv.HiddenSafepointAbi::new(symbol, AllocationOperands)
}

///|
fn elaborate_wasmoon_runtime_abi(
  function : @semantic_machv.Function,
  allocation_symbols : Array[@semantic_machv.ExternalSymbol],
  root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> @semantic_machv.Function raise JitPipelineError {
  let hidden_safepoints : Array[@semantic_machv.HiddenSafepointAbi] = []
  for symbol in allocation_symbols {
    hidden_safepoints.push(hidden_safepoint_abi(symbol))
  }
  let (push_symbol, pop_symbol) = root_scope_symbols
  function.elaborate_call_abi(
    @semantic_machv.CallAbiElaboration::new(
      root_scope=@semantic_machv.CallerRootScopeAbi::new(
        push_symbol, pop_symbol,
      ),
      hidden_safepoints~,
    ),
  ) catch {
    InvalidInput(cause~) => raise RuntimeAbiInputInvalid(cause~)
    InvalidOutput(cause~) => raise RuntimeAbiOutputInvalid(cause~)
    InvalidCall(message~, ..) =>
      raise RuntimeAbiContractViolation(
        message="\{function.name()}: \{message}",
      )
  }
}
