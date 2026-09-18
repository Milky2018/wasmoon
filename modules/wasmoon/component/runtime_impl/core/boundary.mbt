///|
/// Canonical ABI host functions sometimes need to trap with a string message
/// (e.g. component-spec expects "unaligned pointer"). The core Wasm runtime
/// only supports a fixed set of traps, so we stash an optional message here and
/// surface it when catching core traps.
let canon_trap_message : Array[String?] = [None]

///|
let canon_host_exit : Ref[Int?] = Ref(None)

///|
pub fn clear_canon_trap_message() -> Unit {
  canon_trap_message[0] = None
  canon_host_exit.val = None
}

///|
/// Cooperative suspension marker used by certain canonical intrinsics (e.g. thread.yield).
pub(all) enum CanonSuspend {
  Yield
  Wait(Int64) // waitable-set key (handle_key(owner_component_id, local_index))
} derive(Debug, Eq)

///|
/// When a host intrinsic wants to suspend execution, it sets this and traps.
let canon_suspend : Array[CanonSuspend?] = [None]

///|
pub fn trap_canon(msg : String) -> Unit raise @runtime.RuntimeError {
  canon_trap_message[0] = Some(msg)
  raise Unreachable
}

///|
/// Convert a component runtime error into the canonical trap message string.
pub fn canon_err_message(e : ComponentRuntimeError) -> String {
  match e {
    HostExit(status) => {
      canon_host_exit.val = Some(status)
      e.to_string()
    }
    CanonCallError(msg) => msg
    UncaughtWasmException => "thrown Wasm exception"
    HostCallError(msg) => msg
    _ => e.to_string()
  }
}

///|
pub fn canon_core_boundary_error_message(e : ComponentRuntimeError) -> String {
  let message = canon_err_message(e)
  let canonical_message = if message == "realloc return: result not aligned" {
    "unaligned pointer"
  } else if message == "realloc return: beyond end of memory" {
    "list content out-of-bounds"
  } else {
    message
  }
  if canonical_message.has_prefix("wasm trap:") {
    canonical_message
  } else {
    "wasm trap: \{canonical_message}"
  }
}

///|
pub fn trap_message() -> String? {
  canon_trap_message[0]
}

///|
pub fn host_exit_status() -> Int? {
  canon_host_exit.val
}

///|
pub fn suspension() -> CanonSuspend? {
  canon_suspend[0]
}

///|
pub fn set_suspension(reason : CanonSuspend?) -> Unit {
  canon_suspend[0] = reason
}
