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
  HostCallError(String)
  // Cooperative suspension used by sync-style async lifting (canon lift ... async).
  AsyncSuspendYield
  AsyncSuspendWait(Int64)
  InvalidStartResultCount(Int)
  OuterAliasOutOfRange(Int)
  AliasTargetMismatch(String)
} derive(Show, Eq)

///|
/// Canonical ABI host functions sometimes need to trap with a string message
/// (e.g. component-spec expects "unaligned pointer"). The core Wasm runtime
/// only supports a fixed set of traps, so we stash an optional message here and
/// surface it when catching core traps.
let canon_trap_message : Array[String?] = [None]

///|
fn clear_canon_trap_message() -> Unit {
  canon_trap_message[0] = None
}

///|
/// Cooperative suspension marker used by certain canonical intrinsics (e.g. thread.yield).
enum CanonSuspend {
  Yield
  Wait(Int64) // waitable-set key (handle_key(owner_component_id, local_index))
} derive(Show, Eq)

///|
/// When a host intrinsic wants to suspend execution, it sets this and traps.
let canon_suspend : Array[CanonSuspend?] = [None]

///| True while doing a "best-effort pre-run" of an async-lowered call.

///|
/// During this phase we must not allow sync-lowered async calls to actually
/// block/spin; otherwise the caller core code can deadlock before it has a
/// chance to make progress (component-spec/async).
let canon_in_prerun : Array[Bool] = [false]

///|
/// True while executing the "handle-less initial step" of an async-lowered call.
/// Nested sync-lowered async calls must avoid consuming the shared handle space
/// during this phase; otherwise it perturbs the outer subtask numbering
/// expected by component-spec (e.g. async-calls-sync.wast).
let canon_in_handleless_step : Array[Bool] = [false]

///|
fn trap_canon(msg : String) -> Unit raise @runtime.RuntimeError {
  canon_trap_message[0] = Some(msg)
  raise @runtime.RuntimeError::Unreachable
}

///|
/// Convert a component runtime error into the canonical trap message string.
fn canon_err_message(e : ComponentRuntimeError) -> String {
  match e {
    CanonCallError(msg) => msg
    HostCallError(msg) => msg
    _ => e.to_string()
  }
}

///|
/// Some operations are guarded by `may_leave` in the component model; for
/// example, post-return functions cannot "leave" the current component
/// instance. We model this with a global flag checked by canonical host funcs.
let canon_may_leave : Array[Bool] = [true]
