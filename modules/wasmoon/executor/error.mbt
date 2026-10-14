///|
/// Control flow signal for branching (not an error, but uses exception mechanism)
/// This is internal to the executor and should not be exposed to external users
priv suberror ControlSignal {
  BranchWith(Int32, Array[@types.Value]) // Branch with relative depth and values
  Return // Return from function
  TailCall(Int32, @runtime.FuncInst, Array[@types.Value], Int32) // Tail call: (store_addr, func_inst, args, num_results)
  ThrowException(Int32, Array[@types.Value]) // Exception: (tag_idx, exception values)
} derive(Debug)

///|
priv enum ExecBlockResult {
  ExecBlockCompleted
  ExecBlockRaised(Error)
}

///|
/// Internal signal used to preserve host-call error provenance.
priv suberror InvocationSignal {
  HostInvocation(Error)
  Cancelled
} derive(Debug)

///|
/// Internal control signal used only while building a resumable interpreter
/// continuation. It must never escape the public resumable-call seam.
priv suberror ExecutionSuspended derive(Debug)
