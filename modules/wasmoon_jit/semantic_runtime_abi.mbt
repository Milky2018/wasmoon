///|
fn hidden_safepoint_abi(
  symbol : @native.ExternalSymbol,
) -> @semantic_machv.HiddenSafepointAbi {
  @semantic_machv.HiddenSafepointAbi::new(symbol, AllocationOperands)
}

///|
fn elaborate_wasmoon_runtime_abi_selection_plan(
  prepared : @semantic_machv.PreparedSelection,
  allocation_symbols : Array[@native.ExternalSymbol],
  root_scope_symbols : (@native.ExternalSymbol, @native.ExternalSymbol),
) -> @semantic_machv.SelectionPlan raise JitPipelineError {
  let hidden_safepoints : Array[@semantic_machv.HiddenSafepointAbi] = []
  for symbol in allocation_symbols {
    hidden_safepoints.push(hidden_safepoint_abi(symbol))
  }
  let (push_symbol, pop_symbol) = root_scope_symbols
  let elaborated = prepared.elaborate_call_abi(
    @semantic_machv.CallAbiElaboration::new(
      root_scope=@semantic_machv.CallerRootScopeAbi::new(
        push_symbol, pop_symbol,
      ),
      hidden_safepoints~,
    ),
  ) catch {
    InvalidInput(cause~) => raise RuntimeAbiInputInvalid(cause~)
    InvalidOutput(cause~) => raise RuntimeAbiOutputInvalid(cause~)
    InvalidCall(message~, ..) => raise RuntimeAbiContractViolation(message~)
  }
  elaborated.seal() catch {
    error => raise RuntimeAbiOutputInvalid(cause=error)
  }
}
