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
fn call_core_func(
  store : @runtime.Store,
  core_func : CoreFuncRef,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  // Reset any previous canonical trap so we don't leak messages across calls.
  clear_canon_trap_message()
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
        None => raise CanonCallError(e.to_string())
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
