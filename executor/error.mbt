///|
/// Control flow signal for branching (not an error, but uses exception mechanism)
/// This is internal to the executor and should not be exposed to external users
priv suberror ControlSignal {
  BranchWith(Int, Array[@types.Value]) // Branch with relative depth and values
  Return // Return from function
  TailCall(Int, @runtime.FuncInst, Array[@types.Value], Int) // Tail call: (store_addr, func_inst, args, num_results)
} derive(Show)

///|
/// Control flow enum - wasmtime style
/// Replaces exception-based control flow with explicit return values
pub enum ControlFlow {
  Continue // Normal execution continues
  Return(Array[@types.Value]) // Function return with values
  Branch(Int, Array[@types.Value]) // Branch with depth and values
  TailCall(Int, @runtime.FuncInst, Array[@types.Value], Int) // Tail call: (store_addr, func_inst, args, num_results)
  Trap(@runtime.RuntimeError) // Runtime error/trap
} derive(Show)
