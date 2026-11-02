///|
/// How a hidden safepoint describes GC roots already present in its arguments.
pub(all) enum StackMapArgumentRoots {
  Fixed(Int32)
  I32ConstantOperand(Int32)
  AllocationOperands
} derive(Debug, Eq)

///|
pub struct HiddenSafepointAbi {
  priv symbol : @native.ExternalSymbol
  priv argument_roots : StackMapArgumentRoots
  priv owner : Int32?
}

///|
pub fn HiddenSafepointAbi::new(
  symbol : @native.ExternalSymbol,
  argument_roots : StackMapArgumentRoots,
  owner? : Int32,
) -> HiddenSafepointAbi {
  { symbol, argument_roots, owner, }
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
/// Optional embedding-owned link protocol for the existing 32-byte stack frame.
/// A non-null active word admits only the current, attached invocation. Other
/// states retain the checked helpers. Root and mask storage remain compiler-owned.
/// The header contains previous/roots/mask pointers at 0/8/16, an i32 count at
/// 24 and a zero reserved word at 28. All pointer fields use the 64-bit native ABI.
pub(all) struct InlineFunctionRootFrameLayout {
  execution_offset : Int32
  active_offset : Int32
  head_offset : Int32
}

///|
pub struct FunctionRootFrameAbi {
  priv enter_symbol : @native.ExternalSymbol
  priv leave_symbol : @native.ExternalSymbol
  priv environment_parameter : Int32
  priv preserves_mask : Bool
  priv inline_layout : InlineFunctionRootFrameLayout?
}

///|
/// Stack-owned ABI: 32-byte opaque header, root words and precise mask words.
/// `preserves_mask` promises that enter/leave helpers, collectors and reentry
/// never modify compiler-owned mask bytes. Parking must preserve those bytes.
/// Unknown providers keep complete writes. Returns-twice continuations and
/// unknown CFG entries always discard the builder's previous mask knowledge.
pub fn FunctionRootFrameAbi::new(
  enter_symbol : @native.ExternalSymbol,
  leave_symbol : @native.ExternalSymbol,
  environment_parameter~ : Int32 = 0,
  preserves_mask~ : Bool = false,
  inline_layout~ : InlineFunctionRootFrameLayout? = None,
) -> FunctionRootFrameAbi {
  {
    enter_symbol,
    leave_symbol,
    environment_parameter,
    preserves_mask,
    inline_layout,
  }
}

///|
pub struct CallAbiElaboration {
  priv root_scope : CallerRootScopeAbi?
  priv function_frame : FunctionRootFrameAbi?
  priv hidden_safepoints : Array[HiddenSafepointAbi]
}

///|
pub fn CallAbiElaboration::new(
  root_scope? : CallerRootScopeAbi,
  function_frame? : FunctionRootFrameAbi,
  hidden_safepoints~ : Array[HiddenSafepointAbi] = [],
) -> CallAbiElaboration {
  { root_scope, function_frame, hidden_safepoints: hidden_safepoints.copy(), }
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
