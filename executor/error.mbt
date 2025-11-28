///|
/// Control flow signal for branching (not an error, but uses exception mechanism)
/// This is internal to the executor and should not be exposed to external users
priv suberror ControlSignal {
  Branch(Int) // Branch with relative depth
  Return // Return from function
} derive(Show)
