///|
pub using @core {
  type ComponentRuntimeError,
  type CoreCallStyle,
  type CoreBackendPolicy,
  type CoreSuspensionPolicy,
  type CoreExecutionRequest,
  type CoreSuspension,
  type CoreContinuation,
  type CoreExecutionOutcome,
  type CoreExecutionEngine,
  type CoreFuncRef,
  type ComponentInstanceEntryState,
  alloc_host_core_func,
  set_canon_debug_message,
  preset_canon_debug_message,
  clear_canon_debug_message,
  take_core_suspension,
  interpreter_core_execution_engine,
}

///|
using @core {
  type CoreExecutionLifecycle,
  clear_canon_trap_message,
  trap_canon,
  canon_err_message,
  canon_core_boundary_error_message,
  alloc_component_host_core_func,
  call_core_func,
  call_core_func_outcome,
  call_core_func_guarded,
  call_core_func_guarded_outcome,
  closed_core_execution_engine,
}
