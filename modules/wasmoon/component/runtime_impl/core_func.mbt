///|
pub fn alloc_host_core_func(
  store : @runtime.Store,
  core_type : @types.FuncType,
  host : (Array[@types.Value]) -> Array[@types.Value] raise @runtime.RuntimeError,
  may_suspend? : Bool = false,
  native_eligible? : Bool = true,
) -> CoreFuncRef {
  let func_addr = store.alloc_host_func(host, func_type=core_type, type_idx=0)
  let instance : @runtime.ModuleInstance = {
    types: [@types.SubType::from_func(core_type)],
    type_rec_groups: [],
    canonical_type_indices: [0],
    store_idx: -1,
    func_addrs: [func_addr],
    func_type_indices: [0],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    tag_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
  {
    instance,
    func_idx: 0,
    engine: interpreter_core_execution_engine(),
    may_suspend,
    native_eligible,
  }
}

///|
/// Debug-only mapping from `ModuleInstance.store_idx` to a human-readable name.
/// This helps diagnose which core module traps (e.g. `unreachable`) during component-spec runs.
let core_instance_names : Map[Int, String] = Map([])

///|
/// Best-effort "last interesting action" marker to aid diagnosing core traps that originate
/// from guest `unreachable` checks. This is not spec-visible (only used in error strings).
let canon_debug_message : Array[String?] = [None]

///|
/// Allows callers to set a debug marker *before* a core call, even though `call_core_func`
/// clears `canon_debug_message` at the start of each call.
let canon_debug_message_preset : Array[String?] = [None]

///|
pub fn set_canon_debug_message(msg : String) -> Unit {
  canon_debug_message[0] = Some(msg)
}

///|
pub fn preset_canon_debug_message(msg : String) -> Unit {
  canon_debug_message_preset[0] = Some(msg)
}

///|
pub fn clear_canon_debug_message() -> Unit {
  canon_debug_message[0] = None
}

///|
pub fn register_core_instance_name(store_idx : Int, name : String) -> Unit {
  core_instance_names.set(store_idx, name)
}

///|
fn call_core_func(
  store : @runtime.Store,
  core_func : CoreFuncRef,
  args : Array[@types.Value],
  mode? : CoreExecutionMode = Synchronous,
) -> Array[@types.Value] raise ComponentRuntimeError {
  let outcome = call_core_func_outcome(store, core_func, args, mode)
  match outcome {
    Returned(results) => results
    Suspended(_, continuation) => {
      continuation.cancel()
      raise CanonCallError(
        "core execution engine returned a continuation to a synchronous caller",
      )
    }
  }
}

///|
fn call_core_func_outcome(
  store : @runtime.Store,
  core_func : CoreFuncRef,
  args : Array[@types.Value],
  mode : CoreExecutionMode,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  // Reset any previous canonical trap so we don't leak messages across calls.
  clear_canon_trap_message()
  clear_canon_debug_message()
  if canon_debug_message_preset[0] is Some(msg) {
    canon_debug_message_preset[0] = None
    set_canon_debug_message(msg)
  }
  canon_suspend[0] = None
  let outcome = core_func.engine.invoke(
    store,
    core_func.instance,
    core_func.func_idx,
    args,
    mode,
  ) catch {
    e => {
      match canon_suspend[0] {
        Some(_) => {
          canon_suspend[0] = None
          raise CanonCallError(
            "core execution attempted to suspend in synchronous mode",
          )
        }
        None => ()
      }
      match canon_trap_message[0] {
        Some(msg) => raise CanonCallError(msg)
        None => {
          // Include a tiny bit of context to make debugging easier when the trap
          // originates from core wasm (e.g. `unreachable` inside a component-spec test).
          let error_message = match e {
            CanonCallError(message) => message
            _ => e.to_string()
          }
          let trap_msg = if error_message == "unreachable" ||
            error_message.contains("wasm `unreachable` instruction executed") {
            "wasm trap: wasm `unreachable` instruction executed"
          } else {
            error_message
          }
          let inst_name = match
            core_instance_names.get(core_func.instance.store_idx) {
            Some(n) => n
            None => ""
          }
          let dbg = match canon_debug_message[0] {
            Some(s) => " [last=\{s}]"
            None => ""
          }
          if inst_name == "" {
            raise CanonCallError(
              "\{trap_msg} (core store_idx=\{core_func.instance.store_idx} func_idx=\{core_func.func_idx})\{dbg}",
            )
          } else {
            raise CanonCallError(
              "\{trap_msg} (core=\{inst_name} func_idx=\{core_func.func_idx})\{dbg}",
            )
          }
        }
      }
    }
  }
  if outcome is Suspended(_, _) {
    canon_suspend[0] = None
  }
  outcome
}

///|
fn call_core_func_guarded(
  store : @runtime.Store,
  may_enter : Ref[Bool],
  core_func : CoreFuncRef,
  args : Array[@types.Value],
  mode? : CoreExecutionMode = Synchronous,
) -> Array[@types.Value] raise ComponentRuntimeError {
  let prev = may_enter.val
  // Mark this component instance as in-progress to prevent re-entrancy via
  // lowered functions (component-spec/async/trap-on-reenter.wast).
  may_enter.val = false
  let out = call_core_func(store, core_func, args, mode~) catch {
    e =>
      // A trap while executing a component instance permanently poisons that
      // instance. Subsequent entry attempts must fail instead of observing
      // partially-updated canonical ABI state.
      raise e
  }
  may_enter.val = prev
  out
}

///|
fn guard_core_outcome(
  outcome : CoreExecutionOutcome,
  may_enter : Ref[Bool],
  previous : Bool,
) -> CoreExecutionOutcome {
  match outcome {
    Returned(results) => {
      may_enter.val = previous
      Returned(results)
    }
    Suspended(reason, continuation) => {
      // A captured continuation is not actively executing guest code. Release
      // the dynamic entry guard while it waits; task ancestry still prevents
      // prohibited async re-entry. Re-acquire it immediately before resuming.
      may_enter.val = previous
      Suspended(
        reason,
        CoreContinuation(
          fn() raise ComponentRuntimeError {
            if !may_enter.val {
              raise CanonCallError("cannot enter component instance")
            }
            may_enter.val = false
            let resumed = continuation.continue_execution()
            guard_core_outcome(resumed, may_enter, previous)
          },
          fn() {
            continuation.cancel()
            may_enter.val = previous
          },
        ),
      )
    }
  }
}

///|
fn call_core_func_guarded_outcome(
  store : @runtime.Store,
  may_enter : Ref[Bool],
  core_func : CoreFuncRef,
  args : Array[@types.Value],
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  let previous = may_enter.val
  may_enter.val = false
  let outcome = call_core_func_outcome(store, core_func, args, Suspendable)
  guard_core_outcome(outcome, may_enter, previous)
}

///|
