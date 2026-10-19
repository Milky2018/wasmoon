///|
/// Compatibility exports for the shared runtime implementation.
pub using @implementation {
  alloc_exec_managed,
  exec_code_pointer,
  finalize_exec_managed,
  is_windows,
  release_exec_managed,
  stage_exec_managed,
  type GCMetadataError,
  type NativeAllocationError,
  type CleanupOwner,
  type ExecCodeHandle,
  type GCHeapHandle,
  type JITContext,
  type MemoryDescriptor,
  type NativeContinuationArena,
  type NativeExceptionArena,
  type NativeTableHandle,
  type PreparedSafepoints,
  type Quota,
  type Reservation,
  type ContextLayout,
}
