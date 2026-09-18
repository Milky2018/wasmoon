///|
pub(all) struct CoreFuncRef {
  instance : @runtime.ModuleInstance
  func_idx : Int
  engine : CoreExecutionEngine
  debug_name : String?
  may_suspend : Bool
  native_eligible : Bool
} derive(Debug)
