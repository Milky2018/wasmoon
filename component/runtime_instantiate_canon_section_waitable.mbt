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
  let owner_component_id = state.resource_table.id
  // Component-model async ABI: even if the current task is synchronous (e.g. core start),
  // handle numbering assumes an implicit "current thread" handle slot exists.
  async_state.thread_handle_required.set(owner_component_id, true)
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
            if async_state.waitable_sets.get(handle_key(owner_component_id, id))
              is None {
              async_state.waitable_sets.set(
                handle_key(owner_component_id, id),
                { id, members: {}, queue: [], waiters: [0] },
              )
            } else {
              ()
            }
          _ => ()
        }
        v
      }
      None => {
        let id = alloc_shared_handle(async_state, owner_component_id)
        async_state.waitable_sets.set(handle_key(owner_component_id, id), {
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
        return [@types.Value::I32(0)]
      }
    }
    fn ensure_subtask_return_ready(ev : WaitEvent) -> Unit {
      // Replay can clobber the caller's return buffer; ensure it is rewritten
      // before exposing a RETURNED subtask event.
      if ev.code != 1 || ev.payload != 2 {
        return
      }
      let sub_key = handle_key(ev.owner_component_id, ev.index)
      match async_state.subtasks.get(sub_key) {
        Some(st) =>
          match st.result_ty {
            Some(_) =>
              if st.mem_addr is Some(mem_addr2) {
                let cancelled = async_state.task_cancelled.get(sub_key)
                  is Some(true)
                if cancelled {
                  return
                }
                let vals = match async_state.task_results.get(sub_key) {
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
        let ws_key = handle_key(owner_component_id, ws)
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
            let m : Map[Int, WaitResult] = {}
            async_state.wait_results.set(task_id, m)
            m
          }
        }
        match per_task.get(cur) {
          Some(cached) => {
            let ev = cached.ev
            // Replay: write cached event and return its code.
            match cached.subtask_i32 {
              Some(n) =>
                match cached.subtask_mem_addr {
                  Some(addr) =>
                    match (Some(store.get_mem(addr)) catch { _ => None }) {
                      Some(mem2) =>
                        mem2.store_i32(cached.subtask_retptr, n) catch {
                          _ => ()
                        }
                      None => ()
                    }
                  None => ()
                }
              None => ensure_subtask_return_ready(ev)
            }
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            match async_state.waiting_ws.get(task_id) {
              Some(ws0) =>
                if ws0 == ws_key {
                  async_state.waiting_ws.remove(task_id)
                  match async_state.waitable_sets.get(ws_key) {
                    Some(set) => set.waiters[0] = set.waiters[0] - 1
                    None => ()
                  }
                }
              None => ()
            }
            async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
            1] = cur + 1
            set_canon_debug_message(
              "waitable-set.wait(replay cur=\{cur} ws=\{ws})-> code=\{ev.code} index=\{ev.index} payload=\{ev.payload}\{subtask_result_dbg(ev)}",
            )
            [@types.Value::I32(ev.code)]
          }
          None => {
            // Cooperative wait: suspend the current task until an event exists.
            // (The sync-style async ABI will replay this call and consume the event.)
            if !waitable_set_has_event(async_state, ws_key) {
              // Track that this task is a waiter so `waitable-set.drop` can trap.
              if async_state.waiting_ws.get(task_id) is None {
                match async_state.waitable_sets.get(ws_key) {
                  Some(set) => set.waiters[0] = set.waiters[0] + 1
                  None => ()
                }
                async_state.waiting_ws.set(task_id, ws_key)
              }
              canon_suspend[0] = Some(CanonSuspend::Wait(ws_key))
              raise @runtime.RuntimeError::Unreachable
            }
            let ev = match pop_waitable_event(async_state, ws_key) {
              Some(ev) => ev
              None => {
                canon_suspend[0] = Some(CanonSuspend::Wait(ws_key))
                raise @runtime.RuntimeError::Unreachable
              }
            }
            ensure_subtask_return_ready(ev)
            acknowledge_waitable_event(async_state, ev)
            match async_state.waiting_ws.get(task_id) {
              Some(ws0) =>
                if ws0 == ws_key {
                  async_state.waiting_ws.remove(task_id)
                  match async_state.waitable_sets.get(ws_key) {
                    Some(set) => set.waiters[0] = set.waiters[0] - 1
                    None => ()
                  }
                }
              None => ()
            }
            // Cache event and (for SUBTASK+RETURNED) cache the scalar return value at the
            // time of delivery so replay remains correct even if handle ids are later reused.
            let mut cached_mem : Int? = None
            let mut cached_retptr = 0
            let mut cached_i32 : Int? = None
            if ev.code == 1 && ev.payload == 2 {
              let sub_key = handle_key(ev.owner_component_id, ev.index)
              match async_state.subtasks.get(sub_key) {
                Some(st) =>
                  match st.mem_addr {
                    Some(addr) => {
                      cached_mem = Some(addr)
                      cached_retptr = st.retptr
                      match (Some(store.get_mem(addr)) catch { _ => None }) {
                        Some(mem2) =>
                          cached_i32 = Some(mem2.load_i32(st.retptr)) catch {
                            _ => None
                          }
                        None => ()
                      }
                    }
                    None => ()
                  }
                None => ()
              }
            }
            per_task.set(cur, {
              ev,
              subtask_mem_addr: cached_mem,
              subtask_retptr: cached_retptr,
              subtask_i32: cached_i32,
            })
            mem.store_i32(ptr + 0, ev.index) catch {
              _ => ()
            }
            mem.store_i32(ptr + 4, ev.payload) catch {
              _ => ()
            }
            async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
            1] = cur + 1
            set_canon_debug_message(
              "waitable-set.wait(cur=\{cur} ws=\{ws})-> code=\{ev.code} index=\{ev.index} payload=\{ev.payload}\{subtask_result_dbg(ev)}",
            )
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
        return [@types.Value::I32(0)]
      }
    }
    match args {
      [@types.Value::I32(ws), @types.Value::I32(ptr)] => {
        if (ptr.reinterpret_as_uint() & 3U) != 0U {
          trap_canon("unaligned pointer")
          return [@types.Value::I32(0)]
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
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(ws)] => {
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
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(waitable), @types.Value::I32(ws)] => {
        let ws_key = handle_key(owner_component_id, ws)
        let waitable_key = handle_key(owner_component_id, waitable)
        match async_state.waitable_sets.get(ws_key) {
          Some(set) =>
            match async_state.waitable_to_set.get(waitable_key) {
              Some(prev_ws_key) =>
                if prev_ws_key == ws_key {
                  // Idempotent on replay: do not re-flush backlog.
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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
