///|
/// Control flow signal for branching (not an error, but uses exception mechanism)
/// This is internal to the executor and should not be exposed to external users
#derive(Debug)
priv suberror ControlSignal {
  BranchWith(Int32, Array[@types.Value]) // Branch with relative depth and values
  Return // Return from function
  TailCall(Int32, @runtime.FuncInst, Array[@types.Value], Int32) // Tail call: (store_addr, func_inst, args, num_results)
  ThrowException(Int32, Array[@types.Value]) // Exception: (tag_idx, exception values)
}

///|
priv enum ExecBlockResult {
  ExecBlockCompleted
  ExecBlockRaised(Error)
}

///|
/// Internal signal used to preserve host-call error provenance.
#derive(Debug)
priv suberror InvocationSignal {
  HostInvocation(Error)
  Cancelled
}

///|
/// Internal control signal used only while building a resumable interpreter
/// continuation. It must never escape the public resumable-call seam.
#derive(Debug)
priv suberror ExecutionSuspended
