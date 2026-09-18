///|
pub(all) suberror ComponentRuntimeError {
  UnsupportedComponent(String)
  ComponentParseError(String)
  CoreModuleParseError(String)
  CoreModuleInstantiateError(String)
  InvalidUtf8
  UnknownImport(String)
  ImportTypeMismatch(String)
  UnknownExport(String)
  InvalidTypeIndex(Int)
  InvalidFuncIndex(Int)
  InvalidValueIndex(Int)
  InvalidComponentIndex(Int)
  InvalidInstanceIndex(Int)
  InvalidCoreModuleIndex(Int)
  InvalidCoreInstanceIndex(Int)
  InvalidCoreFuncIndex(Int)
  InvalidCoreTableIndex(Int)
  InvalidCoreMemoryIndex(Int)
  InvalidCoreGlobalIndex(Int)
  InvalidCoreTagIndex(Int)
  InvalidCoreTypeIndex(Int)
  InvalidTypeDef(Int)
  InvalidCanonFuncType(Int)
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
  HostExit(Int)
  InvalidStartResultCount(Int)
  OuterAliasOutOfRange(Int)
  AliasTargetMismatch(String)
  DuplicateHostExport(String)
  InvalidHostTypeReference(Int)
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
