///|
/// How a hidden safepoint describes GC roots already present in its arguments.
pub(all) enum StackMapArgumentRoots {
  Fixed(Int)
  I32ConstantOperand(Int)
  AllocationOperands
} derive(Debug, Eq)

///|
pub struct HiddenSafepointAbi {
  priv symbol : @native.ExternalSymbol
  priv argument_roots : StackMapArgumentRoots
}

///|
pub fn HiddenSafepointAbi::new(
  symbol : @native.ExternalSymbol,
  argument_roots : StackMapArgumentRoots,
) -> HiddenSafepointAbi {
  { symbol, argument_roots, }
}

///|
pub struct CallerRootScopeAbi {
  priv push_symbol : @native.ExternalSymbol
  priv pop_symbol : @native.ExternalSymbol
}

///|
pub fn CallerRootScopeAbi::new(
  push_symbol : @native.ExternalSymbol,
  pop_symbol : @native.ExternalSymbol,
) -> CallerRootScopeAbi {
  { push_symbol, pop_symbol, }
}

///|
pub struct CallAbiElaboration {
  priv root_scope : CallerRootScopeAbi?
  priv hidden_safepoints : Array[HiddenSafepointAbi]
}

///|
pub fn CallAbiElaboration::new(
  root_scope? : CallerRootScopeAbi,
  hidden_safepoints? : Array[HiddenSafepointAbi] = [],
) -> CallAbiElaboration {
  { root_scope, hidden_safepoints: hidden_safepoints.copy(), }
}

///|
fn CallAbiElaboration::hidden_safepoint(
  self : CallAbiElaboration,
  call : @native.NativeCall,
) -> HiddenSafepointAbi? {
  guard call.callee is External(symbol) else { return None }
  for hidden in self.hidden_safepoints {
    if hidden.symbol == symbol {
      return Some(hidden)
    }
  }
  None
}

///|
fn root_scope_push_call(symbol : @native.ExternalSymbol) -> @native.NativeCall {
  @native.NativeCall::new(
    External(symbol),
    @native.Signature::new([Ptr64, Ptr64, I32], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
fn root_scope_pop_call(symbol : @native.ExternalSymbol) -> @native.NativeCall {
  @native.NativeCall::new(
    External(symbol),
    @native.Signature::new([Ptr64], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
pub suberror DirectLoweringError {
  InvalidCallAbi(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for DirectLoweringError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}
