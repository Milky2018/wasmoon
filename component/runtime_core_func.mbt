///|
pub fn alloc_host_core_func(
  store : @runtime.Store,
  core_type : @types.FuncType,
  host : (Array[@types.Value]) -> Array[@types.Value] raise @runtime.RuntimeError,
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
  { instance, func_idx: 0 }
}

///|
/// Debug-only mapping from `ModuleInstance.store_idx` to a human-readable name.
/// This helps diagnose which core module traps (e.g. `unreachable`) during component-spec runs.
let core_instance_names : Map[Int, String] = {}

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
) -> Array[@types.Value] raise ComponentRuntimeError {
  // Reset any previous canonical trap so we don't leak messages across calls.
  clear_canon_trap_message()
  clear_canon_debug_message()
  match canon_debug_message_preset[0] {
    Some(msg) => {
      canon_debug_message_preset[0] = None
      set_canon_debug_message(msg)
    }
    None => ()
  }
  canon_suspend[0] = None
  @executor.call_func_by_index(
    store,
    core_func.instance,
    core_func.func_idx,
    args,
  ) catch {
    e => {
      match canon_suspend[0] {
        Some(CanonSuspend::Yield) => {
          canon_suspend[0] = None
          raise AsyncSuspendYield
        }
        Some(CanonSuspend::Wait(ws)) => {
          canon_suspend[0] = None
          raise AsyncSuspendWait(ws)
        }
        None => ()
      }
      match canon_trap_message[0] {
        Some(msg) => raise CanonCallError(msg)
        None => {
          // Include a tiny bit of context to make debugging easier when the trap
          // originates from core wasm (e.g. `unreachable` inside a component-spec test).
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
              "\{e.to_string()} (core store_idx=\{core_func.instance.store_idx} func_idx=\{core_func.func_idx})\{dbg}",
            )
          } else {
            raise CanonCallError(
              "\{e.to_string()} (core=\{inst_name} func_idx=\{core_func.func_idx})\{dbg}",
            )
          }
        }
      }
    }
  }
}

///|
fn call_core_func_guarded(
  store : @runtime.Store,
  may_enter : Array[Bool],
  core_func : CoreFuncRef,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  let prev = may_enter[0]
  // Mark this component instance as in-progress to prevent re-entrancy via
  // lowered functions (component-spec/async/trap-on-reenter.wast).
  may_enter[0] = false
  let out = call_core_func(store, core_func, args) catch {
    e => {
      may_enter[0] = prev
      raise e
    }
  }
  may_enter[0] = prev
  out
}

///|
