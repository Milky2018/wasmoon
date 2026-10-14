///|
pub(all) struct CoreFuncRef {
  instance : @runtime.ModuleInstance
  func_idx : Int32
  engine : CoreExecutionEngine
  debug_name : String?
  may_suspend : Bool
  native_eligible : Bool
} derive(Debug)
