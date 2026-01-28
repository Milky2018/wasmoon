///|
/// Canonical section instantiation helpers.
/// (group: waitable)

///|
fn instantiate_canon_waitable_set_new(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        // Replay-safe: if the waitable-set was created and later dropped in a
        // previous run (before a suspension forced replay), recreate it so the
        // cached id remains usable.
        match v {
          [@types.Value::I32(id)] =>
            if async_state.waitable_sets.get(id) is None {
              async_state.waitable_sets.set(id, {
                id,
                members: {},
                queue: [],
                waiters: [0],
              })
            } else {
              ()
            }
          _ => ()
        }
        v
      }
      None => {
        let id = alloc_shared_handle(async_state)
        async_state.waitable_sets.set(id, {
          id,
          members: {},
          queue: [],
          waiters: [0],
        })
        let out = [@types.Value::I32(id)]
        per_task.set(cur, out)
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        out
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_set_wait(
  _cancellable : Bool,
  memidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
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
        return [@types.Value::I32(0)]
      }
    }
    fn ensure_subtask_return_ready(ev : WaitEvent) -> Unit {
      // Replay can clobber the caller's return buffer; ensure it is rewritten
      // before exposing a RETURNED subtask event.
      if ev.code != 1 || ev.payload != 2 {
        return
      }
      match async_state.subtasks.get(ev.index) {
        Some(st) =>
          match st.result_ty {
            Some(_) =>
              if st.mem_addr is Some(mem_addr2) {
                let cancelled = async_state.task_cancelled.get(st.id)
                  is Some(true)
                if cancelled {
                  return
                }
                let vals = match async_state.task_results.get(st.id) {
                  Some(v) => v
                  None => []
                }
                let (ft, ftypes) = match st.driver {
                  SubtaskDriver::CallbackLifted(t) =>
                    match t.func {
                      ComponentFunc::Host(func_type, types, _) =>
                        (func_type, types)
                      ComponentFunc::Lifted(_, func_type, _, types, _, _, _, _) =>
                        (func_type, types)
                    }
                  _ => return
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
                  [@types.Value::I32(n)] =>
                    mem2.store_i32(st.retptr, n) catch {
                      _ => ()
                    }
                  [@types.Value::I64(n)] =>
                    mem2.store_i64(st.retptr, n) catch {
                      _ => ()
                    }
                  _ => ()
                }
              } else {
                ()
              }
            None => ()
          }
        None => ()
      }
    }

    match args {
      [@types.Value::I32(ws), @types.Value::I32(ptr)] => {
        if !async_state.task_can_block[0] {
          // Even if the argument is invalid (e.g. unaligned), the component-spec
          // suite expects that synchronous tasks trap before attempting to block.
          trap_canon("cannot block a synchronous task before returning")
          return [@types.Value::I32(0)]
        }
        if (ptr.reinterpret_as_uint() & 3U) != 0U {
          trap_canon("unaligned pointer")
          return [@types.Value::I32(0)]
        }
        let task_id = current_task_id(async_state)
        let cur = if async_state.wait_cursor_stack.length() == 0 {
          0
        } else {
          async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
          1]
        }
        let per_task = match async_state.wait_results.get(task_id) {
          Some(m) => m
          None => {
            let m : Map[Int, WaitEvent] = {}
            async_state.wait_results.set(task_id, m)
            m
          }
        }
        match per_task.get(cur) {
          Some(ev) => {
            // Replay: write cached event and return its code.
            ensure_subtask_return_ready(ev)
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            match async_state.waiting_ws.get(task_id) {
              Some(ws0) =>
                if ws0 == ws {
                  async_state.waiting_ws.remove(task_id)
                  match async_state.waitable_sets.get(ws) {
                    Some(set) => set.waiters[0] = set.waiters[0] - 1
                    None => ()
                  }
                }
              None => ()
            }
            async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
            1] = cur + 1
            [@types.Value::I32(ev.code)]
          }
          None => {
            // Cooperative wait: suspend the current task until an event exists.
            // (The sync-style async ABI will replay this call and consume the event.)
            if !waitable_set_has_event(async_state, ws) {
              // Track that this task is a waiter so `waitable-set.drop` can trap.
              if async_state.waiting_ws.get(task_id) is None {
                match async_state.waitable_sets.get(ws) {
                  Some(set) => set.waiters[0] = set.waiters[0] + 1
                  None => ()
                }
                async_state.waiting_ws.set(task_id, ws)
              }
              canon_suspend[0] = Some(CanonSuspend::Wait(ws))
              raise @runtime.RuntimeError::Unreachable
            }
            let ev = match pop_waitable_event(async_state, ws) {
              Some(ev) => ev
              None => {
                canon_suspend[0] = Some(CanonSuspend::Wait(ws))
                raise @runtime.RuntimeError::Unreachable
              }
            }
            ensure_subtask_return_ready(ev)
            acknowledge_waitable_event(async_state, ev)
            match async_state.waiting_ws.get(task_id) {
              Some(ws0) =>
                if ws0 == ws {
                  async_state.waiting_ws.remove(task_id)
                  match async_state.waitable_sets.get(ws) {
                    Some(set) => set.waiters[0] = set.waiters[0] - 1
                    None => ()
                  }
                }
              None => ()
            }
            per_task.set(cur, ev)
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
            1] = cur + 1
            [@types.Value::I32(ev.code)]
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        [@types.Value::I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_set_poll(
  _cancellable : Bool,
  memidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
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
        return [@types.Value::I32(0)]
      }
    }
    match args {
      [@types.Value::I32(ws), @types.Value::I32(ptr)] => {
        if (ptr.reinterpret_as_uint() & 3U) != 0U {
          trap_canon("unaligned pointer")
          return [@types.Value::I32(0)]
        }
        match pop_waitable_event(async_state, ws) {
          Some(ev) => {
            acknowledge_waitable_event(async_state, ev)
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            [@types.Value::I32(ev.code)]
          }
          None => [@types.Value::I32(0)]
        }
      }
      _ => {
        trap_canon("type mismatch")
        [@types.Value::I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_set_drop(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let async_state = state.async_state
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(ws)] =>
        match async_state.waitable_sets.get(ws) {
          Some(set) =>
            if set.waiters[0] > 0 {
              trap_canon("cannot drop waitable set with waiters")
              []
            } else {
              async_state.waitable_sets.remove(ws)
              // Clean up membership mappings.
              for kv in set.members.iter() {
                let (waitable, _v) = kv
                match async_state.waitable_to_set.get(waitable) {
                  Some(ws2) =>
                    if ws2 == ws {
                      async_state.waitable_to_set.remove(waitable)
                    }
                  None => ()
                }
              }
              free_shared_handle(async_state, ws)
              []
            }
          None => {
            trap_canon("unknown waitable set index \{ws}")
            []
          }
        }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_waitable_join(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [],
  }
  let async_state = state.async_state
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(waitable), @types.Value::I32(ws)] =>
        match async_state.waitable_sets.get(ws) {
          Some(set) =>
            match async_state.waitable_to_set.get(waitable) {
              Some(prev_ws) =>
                if prev_ws == ws {
                  // Idempotent on replay: do not re-flush backlog.
                  []
                } else {
                  // Move membership between sets.
                  match async_state.waitable_sets.get(prev_ws) {
                    Some(prev_set) => prev_set.members.remove(waitable)
                    None => ()
                  }
                  set.members.set(waitable, true)
                  async_state.waitable_to_set.set(waitable, ws)
                  // Flush any queued events that happened before join.
                  match async_state.waitable_events.get(waitable) {
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
                async_state.waitable_to_set.set(waitable, ws)
                // Flush any queued events that happened before join.
                match async_state.waitable_events.get(waitable) {
                  Some(list) =>
                    for ev in list {
                      set.queue.push(ev)
                    }
                  None => ()
                }
                []
              }
            }
          None => {
            trap_canon("unknown waitable set index \{ws}")
            []
          }
        }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
