///|
pub(all) suberror ComponentRuntimeError {
  UnsupportedComponent(String)
  ComponentParseError(String)
  CoreModuleParseError(String)
  CoreModuleInstantiateError(String)
  ResourceExhausted(String)
  InvalidUtf8
  UnknownImport(String)
  ImportTypeMismatch(String)
  UnknownExport(String)
  InvalidTypeIndex(Int32)
  InvalidFuncIndex(Int32)
  InvalidValueIndex(Int32)
  InvalidComponentIndex(Int32)
  InvalidInstanceIndex(Int32)
  InvalidCoreModuleIndex(Int32)
  InvalidCoreInstanceIndex(Int32)
  InvalidCoreFuncIndex(Int32)
  InvalidCoreTableIndex(Int32)
  InvalidCoreMemoryIndex(Int32)
  InvalidCoreGlobalIndex(Int32)
  InvalidCoreTagIndex(Int32)
  InvalidCoreTypeIndex(Int32)
  InvalidTypeDef(Int32)
  InvalidCanonFuncType(Int32)
  MissingCanonMemory
  MissingCanonRealloc
  UnsupportedStringEncoding
  CanonCallError(String)
  UncaughtWasmException
  HostCallError(String)
  /// Native component execution is unavailable on this host.
  NativeEngineUnavailable(String)
  /// A core module could not be compiled or installed by the native engine.
  NativeCompilationFailed(String)
  /// A resumable component invocation was cancelled.
  Cancelled
  /// Structured termination requested by an embedding-provided command host.
  HostExit(Int32)
  InvalidStartResultCount(Int32)
  OuterAliasOutOfRange(Int32)
  AliasTargetMismatch(String)
  DuplicateHostExport(String)
  InvalidHostTypeReference(Int32)
  /// A host readiness source has already been installed on this runtime.
  HostEventLoopAlreadyInstalled
  /// The same component invocation is already executing a scheduling round.
  InvocationAlreadyDriving
  /// The same linker is already instantiating another root component.
  ReentrantInstantiation
} derive(Debug, Eq)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for ComponentRuntimeError with fn output(self, logger) {
  logger.write_string(
    if self is UncaughtWasmException {
      "thrown Wasm exception"
    } else {
      @types.compact_show_repr(Repr(self).to_string())
    },
  )
}

///|
/// Preserve capacity denial and host exit while adapting core instantiation.
pub fn ComponentRuntimeError::from_core(
  error : @runtime.RuntimeError,
) -> ComponentRuntimeError {
  match error {
    OutOfMemory
    | AllocationTooLarge
    | MemoryMinimumExceedsLimits(_)
    | TableAllocationOverflow
    | TableAllocationFailed => ResourceExhausted(error.to_string())
    HostExit(code) => HostExit(code)
    AsyncHostCallCancelled => Cancelled
    _ => CoreModuleInstantiateError(error.to_string())
  }
}
