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
  priv scoped_function_frame : FunctionRootFrameAbi?
  priv scoped_root_limit : Int32
  priv root_scope : CallerRootScopeAbi?
  priv function_frame : FunctionRootFrameAbi?
  priv hidden_safepoints : Array[HiddenSafepointAbi]
}

///|
/// A positive `scoped_root_limit` opts into balanced call-site use of the same
/// stack-owned frame protocol after producer cost admission. The provider must
/// preserve the complete frame through collection, parking and nonlocal unwind.
/// Zero keeps the existing whole-function lifetime.
pub fn CallAbiElaboration::new(
  root_scope? : CallerRootScopeAbi,
  function_frame? : FunctionRootFrameAbi,
  hidden_safepoints~ : Array[HiddenSafepointAbi] = [],
  scoped_root_limit~ : Int32 = 0,
) -> CallAbiElaboration {
  {
    root_scope,
    function_frame,
    scoped_function_frame: None,
    hidden_safepoints: hidden_safepoints.copy(),
    scoped_root_limit,
  }
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

///|
/// Use the existing stack-owned frame only around collecting calls for a
/// producer-admitted sparse live set. Larger or unknown sets keep the normal
/// definition-once frame. Runtime unwinding and parking use the same protocol.
pub fn CallAbiElaboration::for_root_capacity(
  self : CallAbiElaboration,
  capacity : Int32,
) -> CallAbiElaboration {
  if capacity > 0 &&
    capacity <= self.scoped_root_limit &&
    self.function_frame is Some(frame) {
    { ..self, function_frame: None, scoped_function_frame: Some(frame), }
  } else {
    self
  }
}

///|
/// Whether definitions need persistent shadow slots for this function.
pub fn CallAbiElaboration::has_function_frame(
  self : CallAbiElaboration,
) -> Bool {
  self.function_frame is Some(_)
}
