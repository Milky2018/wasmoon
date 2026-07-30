///|
/// Canonical section instantiation helpers.
/// (group: waitable)

///|
fn release_waiter(
  async_state : AsyncState,
  task_id : Int64,
  ws_key : Int64,
) -> Unit {
  if async_state.waiting_ws.get(task_id) is Some(active_ws) &&
    active_ws == ws_key {
    async_state.waiting_ws.remove(task_id)
    if async_state.waitable_sets.get(ws_key) is Some(set) {
      set.waiters[0] = set.waiters[0] - 1
    }
  }
}

///|
fn instantiate_canon_waitable_set_new(
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let id = alloc_shared_handle(async_state, owner_component_id)
    async_state.waitable_sets.set(handle_key(owner_component_id, id), {
      id,
      members: Map([]),
      queue: [],
      waiters: [0],
    })
    [I32(id)]
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_set_wait(
  _cancellable : Bool,
  memidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  if memidx < 0 || memidx >= state.core_mems.length() {
    raise InvalidCoreMemoryIndex(memidx)
  }
  let mem_addr = state.core_mems[memidx]
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let mem = store.get_mem(mem_addr) catch {
      e => {
        trap_canon(e.to_string())
        return [I32(0)]
      }
    }
    fn ensure_subtask_return_ready(ev : WaitEvent) -> Unit {
      // Materialize the subtask result immediately before exposing RETURNED.
      if ev.code != 1 || ev.payload != 2 {
        return
      }
      let sub_key = handle_key(ev.owner_component_id, ev.index)
      if async_state.subtasks.get(sub_key) is Some(st) &&
        st.result_ty is Some(_) &&
        st.mem_addr is Some(mem_addr2) {
        let cancelled = async_state.task_self_cancelled.get(sub_key)
          is Some(true)
        if cancelled {
          return
        }
        let vals = match async_state.task_results.get(sub_key) {
          Some(v) => v
          None => []
        }
        let (ft, ftypes) = match st.driver {
          CallbackLifted(t) =>
            match t.func {
              Host(func_type, types, _) => (func_type, types)
              HostAsync(func_type, types, _) => (func_type, types)
              Lifted(_, func_type, _, types, _, _, _, _) => (func_type, types)
            }
        }
        let mem2 = store.get_mem(mem_addr2) catch { _ => return }
        let core_vals = component_results_to_core(
          vals,
          ft,
          ftypes,
          st.resources,
          store,
          Some(st.retptr),
        ) catch {
          _e => return
        }
        match core_vals {
          [I32(n)] => mem2.store_i32(st.retptr, n) catch { _ => () }
          [I64(n)] => mem2.store_i64(st.retptr, n) catch { _ => () }
          _ => ()
        }
      }
    }

    fn subtask_result_dbg(ev : WaitEvent) -> String {
      if ev.code != 1 || ev.payload != 2 {
        return ""
      }
      let sub_key = handle_key(ev.owner_component_id, ev.index)
      fn mem_dbg() -> String {
        match async_state.subtasks.get(sub_key) {
          Some(st) =>
            match st.mem_addr {
              Some(addr) => {
                let mem2 = store.get_mem(addr) catch { _ => return "" }
                let n = mem2.load_i32(st.retptr) catch { _ => return "" }
                " retptr=\{st.retptr} mem=\{n}"
              }
              None => ""
            }
          None => ""
        }
      }

      match async_state.task_results.get(sub_key) {
        Some(vals) =>
          if vals.length() > 0 {
            " result=\{vals[0]}\{mem_dbg()}"
          } else {
            "\{mem_dbg()}"
          }
        None => "\{mem_dbg()}"
      }
    }

    match args {
      [I32(ws), I32(ptr)] => {
        let ws_key = handle_key(owner_component_id, ws)
        if !async_state.task_can_block[0] {
          // Synchronous tasks generally cannot block. One exception is waiting on
          // an existing waitable membership: drive the cooperative event loop
          // and report deadlock if no progress is possible.
          if !waitable_set_has_event(async_state, ws_key) {
            let has_members = match async_state.waitable_sets.get(ws_key) {
              Some(set) => set.members.length() > 0
              None => false
            }
            if !has_members {
              // Even if the argument is invalid (e.g. unaligned), component-spec
              // expects synchronous tasks to trap before attempting to block.
              trap_canon("cannot block a synchronous task before returning")
              return [I32(0)]
            }
            while !waitable_set_has_event(async_state, ws_key) {
              let progressed = progress_one_subtask_intrinsic(
                async_state, store,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return [I32(0)]
                }
              }
              if !progressed {
                trap_canon(
                  "wasm trap: deadlock detected: event loop cannot make further progress",
                )
                return [I32(0)]
              }
            }
          }
        }
        if (ptr.reinterpret_as_uint() & 3U) != 0U {
          trap_canon("unaligned pointer")
          return [I32(0)]
        }
        let task_id = current_task_id(async_state)
        if _cancellable && async_state.task_cancelled.get(task_id) is Some(true) {
          async_state.task_cancelled.remove(task_id)
          release_waiter(async_state, task_id, ws_key)
          return [I32(6)]
        }
        if !waitable_set_has_event(async_state, ws_key) {
          // Track the dormant continuation so `waitable-set.drop` can reject
          // a set with an active waiter.
          if async_state.waiting_ws.get(task_id) is None {
            match async_state.waitable_sets.get(ws_key) {
              Some(set) => set.waiters[0] = set.waiters[0] + 1
              None => ()
            }
            async_state.waiting_ws.set(task_id, ws_key)
          }
          canon_suspend[0] = Some(Wait(ws_key))
          raise Unreachable
        }
        let ev = match pop_waitable_event(async_state, ws_key) {
          Some(ev) => ev
          None => {
            canon_suspend[0] = Some(Wait(ws_key))
            raise Unreachable
          }
        }
        ensure_subtask_return_ready(ev)
        acknowledge_waitable_event(async_state, ev)
        release_waiter(async_state, task_id, ws_key)
        mem.store_i32(ptr + 0, ev.index) catch {
          _ => ()
        }
        mem.store_i32(ptr + 4, ev.payload) catch {
          _ => ()
        }
        set_canon_debug_message(
          "waitable-set.wait(ws=\{ws})-> code=\{ev.code} index=\{ev.index} payload=\{ev.payload}\{subtask_result_dbg(ev)}",
        )
        [I32(ev.code)]
      }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(
    alloc_component_host_core_func(store, core_type, host, may_suspend=true),
  )
}

///|
fn instantiate_canon_waitable_set_poll(
  _cancellable : Bool,
  memidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  if memidx < 0 || memidx >= state.core_mems.length() {
    raise InvalidCoreMemoryIndex(memidx)
  }
  let mem_addr = state.core_mems[memidx]
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let mem = store.get_mem(mem_addr) catch {
      e => {
        trap_canon(e.to_string())
        return [I32(0)]
      }
    }
    match args {
      [I32(ws), I32(ptr)] => {
        let task_id = current_task_id(async_state)
        if _cancellable && async_state.task_cancelled.get(task_id) is Some(true) {
          async_state.task_cancelled.remove(task_id)
          return [I32(6)]
        }
        if (ptr.reinterpret_as_uint() & 3U) != 0U {
          trap_canon("unaligned pointer")
          return [I32(0)]
        }
        let ws_key = handle_key(owner_component_id, ws)
        match pop_waitable_event(async_state, ws_key) {
          Some(ev) => {
            acknowledge_waitable_event(async_state, ev)
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            [I32(ev.code)]
          }
          None => {
            mem.store_i32(ptr + 0, 0) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, 0) catch {
              _ => ()
            }
            [I32(0)]
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_set_drop(
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(ws)] => {
        let ws_key = handle_key(owner_component_id, ws)
        match async_state.waitable_sets.get(ws_key) {
          Some(set) =>
            if set.waiters[0] > 0 {
              trap_canon("cannot drop waitable set with waiters")
              []
            } else {
              async_state.waitable_sets.remove(ws_key)
              // Clean up membership mappings.
              for kv in set.members.iter() {
                let (waitable, _v) = kv
                let wkey = handle_key(owner_component_id, waitable)
                if async_state.stream_table.endpoints.get(wkey)
                  is Some(endpoint) {
                  endpoint.in_waitable_set.val = false
                }
                if async_state.future_endpoints.get(wkey) is Some(endpoint) {
                  endpoint.in_waitable_set.val = false
                }
                match async_state.waitable_to_set.get(wkey) {
                  Some(ws2_key) =>
                    if ws2_key == ws_key {
                      async_state.waitable_to_set.remove(wkey)
                    }
                  None => ()
                }
              }
              free_shared_handle(async_state, owner_component_id, ws)
              []
            }
          None => {
            trap_canon("unknown waitable set index \{ws}")
            []
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_join(
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(waitable), I32(ws)] => {
        let waitable_key = handle_key(owner_component_id, waitable)
        if ws != 0 &&
          waitable_is_in_sync_use(async_state, owner_component_id, waitable) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return []
        }
        if ws == 0 {
          if async_state.stream_table.endpoints.get(waitable_key)
            is Some(endpoint) {
            endpoint.in_waitable_set.val = false
          }
          if async_state.future_endpoints.get(waitable_key) is Some(endpoint) {
            endpoint.in_waitable_set.val = false
          }
          match async_state.waitable_to_set.get(waitable_key) {
            Some(previous_key) => {
              async_state.waitable_to_set.remove(waitable_key)
              match async_state.waitable_sets.get(previous_key) {
                Some(previous_set) => previous_set.members.remove(waitable)
                None => ()
              }
            }
            None => ()
          }
          return []
        }
        let ws_key = handle_key(owner_component_id, ws)
        match async_state.waitable_sets.get(ws_key) {
          Some(set) => {
            if async_state.stream_table.endpoints.get(waitable_key)
              is Some(endpoint) {
              endpoint.in_waitable_set.val = true
            }
            if async_state.future_endpoints.get(waitable_key) is Some(endpoint) {
              endpoint.in_waitable_set.val = true
            }
            match async_state.waitable_to_set.get(waitable_key) {
              Some(prev_ws_key) =>
                if prev_ws_key == ws_key {
                  // Joining an existing set is idempotent; do not re-flush backlog.
                  []
                } else {
                  // Move membership between sets.
                  match async_state.waitable_sets.get(prev_ws_key) {
                    Some(prev_set) => prev_set.members.remove(waitable)
                    None => ()
                  }
                  set.members.set(waitable, true)
                  async_state.waitable_to_set.set(waitable_key, ws_key)
                  // Flush any queued events that happened before join.
                  match async_state.waitable_events.get(waitable_key) {
                    Some(list) =>
                      for ev in list {
                        set.queue.push(ev)
                      }
                    None => ()
                  }
                  []
                }
              None => {
                set.members.set(waitable, true)
                async_state.waitable_to_set.set(waitable_key, ws_key)
                // Flush any queued events that happened before join.
                match async_state.waitable_events.get(waitable_key) {
                  Some(list) =>
                    for ev in list {
                      set.queue.push(ev)
                    }
                  None => ()
                }
                []
              }
            }
          }
          None => {
            trap_canon("unknown waitable set index \{ws}")
            []
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
