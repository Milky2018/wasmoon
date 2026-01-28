///|
/// Drive an async component function to completion (blocking the current task).
///
/// Async functions communicate their eventual results through `canon task.return`.
fn await_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let can_block = async_state.task_can_block[0]
  if !can_block {
    raise CanonCallError("cannot block a synchronous task before returning")
  }
  let task_id = alloc_task_id(async_state)
  push_task(async_state, task_id, can_block)
  take_task_result(async_state, task_id) |> ignore
  let out = try {
    match func {
      ComponentFunc::Host(_ft, _types, host) =>
        host(args, caller_table) catch {
          e => raise HostCallError(e.to_string())
        }
      ComponentFunc::Lifted(
        core_func,
        func_type,
        resources,
        types,
        callee_table,
        may_enter,
        cb_opt,
        async_abi
      ) => {
        if func_type_needs_memory(func_type, types) &&
          resources.mem_addr is None {
          raise MissingCanonMemory
        }
        let core_args = component_args_to_core(
          args, func_type, types, resources, store, caller_table, callee_table,
        )
        match cb_opt {
          None =>
            if async_abi {
              // Sync-style async ABI: the core function may suspend (thread.yield / waitable-set.wait).
              while true {
                if async_state.yield_cursor_stack.length() > 0 {
                  async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                  1] = 0
                }
                if async_state.wait_cursor_stack.length() > 0 {
                  async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                  1] = 0
                }
                if async_state.call_cursor_stack.length() > 0 {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = 0
                }
                let core_results = call_core_func_guarded(
                  store, may_enter, core_func, core_args,
                ) catch {
                  AsyncSuspendYield => {
                    if !progress_one_subtask(async_state, store) {
                      raise CanonCallError(
                        "wasm trap: deadlock detected: event loop cannot make further progress",
                      )
                    }
                    continue
                  }
                  AsyncSuspendWait(ws) => {
                    while !waitable_set_has_event(async_state, ws) {
                      if !progress_one_subtask(async_state, store) {
                        raise CanonCallError(
                          "wasm trap: deadlock detected: event loop cannot make further progress",
                        )
                      }
                    }
                    continue
                  }
                  e => raise e
                }
                // Prefer results published via `canon task.return` (used by many component-spec/async
                // tests), but fall back to interpreting the core function's direct results.
                let vals = match take_task_result(async_state, task_id) {
                  Some(v) => v
                  None =>
                    core_results_to_component(
                      core_results, func_type, types, resources, store, callee_table,
                    )
                }
                match func_type.result {
                  Some(rty) =>
                    if vals.length() > 0 {
                      validate_lifted_stream_future(
                        rty,
                        vals[0],
                        types,
                        async_state,
                      )
                    } else {
                      ()
                    }
                  None => ()
                }
                // Mirror task.return bookkeeping so other parts can uniformly query results.
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, vals)
                pop_task(async_state)
                return vals
              }
              raise CanonCallError("unreachable")
            } else {
              // Sync-style async: the core function returns results directly (no task.return).
              let core_results = call_core_func_guarded(
                store, may_enter, core_func, core_args,
              )
              let vals = core_results_to_component(
                core_results, func_type, types, resources, store, callee_table,
              )
              match func_type.result {
                Some(rty) =>
                  if vals.length() > 0 {
                    validate_lifted_stream_future(
                      rty,
                      vals[0],
                      types,
                      async_state,
                    )
                  } else {
                    ()
                  }
                None => ()
              }
              // Mirror task.return bookkeeping so other parts can uniformly query results.
              async_state.task_returned.set(task_id, true)
              set_task_result(async_state, task_id, vals)
              vals
            }
          Some(cb) => {
            let core_results = call_core_func_guarded(
              store, may_enter, core_func, core_args,
            )
            let mut code = match core_results {
              [@types.Value::I32(n)] => n
              _ => raise CanonCallError("type mismatch")
            }
            while true {
              let u = code.reinterpret_as_uint()
              let tag = (u & 0xFU).reinterpret_as_int()
              let payload = (u >> 4).reinterpret_as_int()
              if tag == 0 {
                break
              } else if tag == 1 {
                // YIELD
                progress_one_subtask(async_state, store) |> ignore
                async_state.in_async_callback[0] = true
                let r = call_core_func_guarded(store, may_enter, cb, [
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                ]) catch {
                  e => {
                    async_state.in_async_callback[0] = false
                    raise e
                  }
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [@types.Value::I32(n)] => n
                  _ => raise CanonCallError("type mismatch")
                }
              } else if tag == 2 {
                // WAIT
                if !can_block {
                  raise CanonCallError(
                    "cannot block a synchronous task before returning",
                  )
                }
                let ev = wait_for_event(async_state, store, payload)
                async_state.in_async_callback[0] = true
                let r = call_core_func_guarded(store, may_enter, cb, [
                  @types.Value::I32(ev.code),
                  @types.Value::I32(ev.index),
                  @types.Value::I32(ev.payload),
                ]) catch {
                  e => {
                    async_state.in_async_callback[0] = false
                    raise e
                  }
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [@types.Value::I32(n)] => n
                  _ => raise CanonCallError("type mismatch")
                }
              } else {
                raise CanonCallError("unsupported callback code: \{tag}")
              }
            }
            match take_task_result(async_state, task_id) {
              Some(vals) => vals
              None => []
            }
          }
        }
      }
    }
  } catch {
    e => {
      pop_task(async_state)
      raise e
    }
  }
  pop_task(async_state)
  out
}

///|
fn wait_for_event(
  async_state : AsyncState,
  store : @runtime.Store,
  ws : Int,
) -> WaitEvent raise ComponentRuntimeError {
  match async_state.waitable_sets.get(ws) {
    Some(set) => set.waiters[0] = set.waiters[0] + 1
    None => raise CanonCallError("unknown waitable set index \{ws}")
  }
  while true {
    match pop_waitable_event(async_state, ws) {
      Some(ev) => {
        acknowledge_waitable_event(async_state, ev)
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] - 1
          None => ()
        }
        return ev
      }
      None => ()
    }
    if !progress_one_subtask(async_state, store) {
      raise CanonCallError(
        "wasm trap: deadlock detected: event loop cannot make further progress",
      )
    }
  }
  raise CanonCallError("unreachable")
}

///|
fn waitable_set_has_event(async_state : AsyncState, ws : Int) -> Bool {
  match async_state.waitable_sets.get(ws) {
    Some(set) => set.queue.length() > 0
    None => false
  }
}

///|
struct DecodedCallbackCode {
  tag : Int
  payload : Int
} derive(Show)

///|
fn decode_callback_code(code : Int) -> DecodedCallbackCode {
  let u = code.reinterpret_as_uint()
  let tag = (u & 0xFU).reinterpret_as_int()
  let payload = (u >> 4).reinterpret_as_int()
  { tag, payload }
}

///|
fn step_task_once(
  task : CallbackTask,
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> TaskStep raise ComponentRuntimeError {
  fn set_waiting(ws_opt : Int?) -> Unit {
    let prev = task.waiting_set[0]
    // No change.
    if prev == ws_opt {
      task.waiting_set[0] = ws_opt
      return
    }
    match prev {
      Some(ws) =>
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] - 1
          None => ()
        }
      None => ()
    }
    match ws_opt {
      Some(ws) =>
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] + 1
          None => ()
        }
      None => ()
    }
    task.waiting_set[0] = ws_opt
  }

  match task.func {
    ComponentFunc::Host(_ft, _types, host) => {
      (host(task.args, caller_table) catch {
        e => raise HostCallError(e.to_string())
      })
      |> ignore
      TaskStep::Done
    }
    ComponentFunc::Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      may_enter,
      cb_opt,
      async_abi
    ) => {
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let core_args = component_args_to_core(
        task.args,
        func_type,
        types,
        resources,
        store,
        caller_table,
        callee_table,
      )

      // Callback-style async ABI: initial call returns a callback code; resumption uses `callback`.
      if cb_opt is Some(cb) {
        // If we were suspended while waiting on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) && !task.cancelled[0] {
              return TaskStep::Blocked
            }
          None => ()
        }
        if !task.started[0] {
          task.started[0] = true
          let core_results = call_core_func_guarded(
            store, may_enter, core_func, core_args,
          ) catch {
            AsyncSuspendYield => {
              // Cooperative suspension (e.g. sync-lowering an async callee).
              task.started[0] = false
              set_waiting(None)
              // Replay from the top: reset restartable cursors for this task invocation.
              if async_state.yield_cursor_stack.length() > 0 {
                async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                1] = 0
              }
              if async_state.wait_cursor_stack.length() > 0 {
                async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                1] = 0
              }
              if async_state.call_cursor_stack.length() > 0 {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1] = 0
              }
              return TaskStep::Progressed
            }
            AsyncSuspendWait(ws) => {
              task.started[0] = false
              set_waiting(Some(ws))
              if async_state.yield_cursor_stack.length() > 0 {
                async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                1] = 0
              }
              if async_state.wait_cursor_stack.length() > 0 {
                async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                1] = 0
              }
              if async_state.call_cursor_stack.length() > 0 {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1] = 0
              }
              return TaskStep::Blocked
            }
            e => raise e
          }
          let code = match core_results {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        let d0 = decode_callback_code(task.code[0])
        if d0.tag == 0 {
          return TaskStep::Done
        }
        if d0.tag == 1 {
          // YIELD
          let args = if task.cancelled[0] {
            task.cancelled[0] = false
            // TASK_CANCELLED=6, index=0, payload=0 (component-spec convention).
            [@types.Value::I32(6), @types.Value::I32(0), @types.Value::I32(0)]
          } else {
            [@types.Value::I32(0), @types.Value::I32(0), @types.Value::I32(0)]
          }
          async_state.in_async_callback[0] = true
          let r = call_core_func_guarded(store, may_enter, cb, args)
          async_state.in_async_callback[0] = false
          let code = match r {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        if d0.tag == 2 {
          let ws = d0.payload
          set_waiting(Some(ws))
          // Cancellation preempts waiting: deliver TASK_CANCELLED immediately.
          if task.cancelled[0] {
            task.cancelled[0] = false
            set_waiting(None)
            async_state.in_async_callback[0] = true
            let r = call_core_func_guarded(store, may_enter, cb, [
              @types.Value::I32(6),
              @types.Value::I32(0),
              @types.Value::I32(0),
            ])
            async_state.in_async_callback[0] = false
            let code = match r {
              [@types.Value::I32(n)] => n
              _ => raise CanonCallError("type mismatch")
            }
            task.code[0] = code
            let d = decode_callback_code(code)
            set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
            return if d.tag == 0 {
              TaskStep::Done
            } else {
              TaskStep::Progressed
            }
          }
          if !waitable_set_has_event(async_state, ws) {
            return TaskStep::Blocked
          }
          let ev = match pop_waitable_event(async_state, ws) {
            Some(ev) => ev
            None => return TaskStep::Blocked
          }
          acknowledge_waitable_event(async_state, ev)
          // Leaving the waiting state to process one event.
          set_waiting(None)
          async_state.in_async_callback[0] = true
          let r = call_core_func_guarded(store, may_enter, cb, [
            @types.Value::I32(ev.code),
            @types.Value::I32(ev.index),
            @types.Value::I32(ev.payload),
          ])
          async_state.in_async_callback[0] = false
          let code = match r {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        raise CanonCallError("unsupported callback code: \{d0.tag}")
      }

      // Sync-style async ABI uses cooperative suspension.
      if async_abi {
        // If previously blocked on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) {
              return TaskStep::Blocked
            }
          None => ()
        }
        // Re-run from the top; intrinsics will replay completed suspension points.
        try {
          let core_results = call_core_func_guarded(
            store, may_enter, core_func, core_args,
          )
          if func_type.is_async {
            let task_id = current_task_id(async_state)
            // Prefer results published via `canon task.return` (async-lifted tasks often return
            // `[]` from the core function), but fall back to direct core results.
            match async_state.task_results.get(task_id) {
              Some(_vals) => async_state.task_returned.set(task_id, true)
              None => {
                let vals = core_results_to_component(
                  core_results, func_type, types, resources, store, callee_table,
                )
                match func_type.result {
                  Some(rty) =>
                    if vals.length() > 0 {
                      validate_lifted_stream_future(
                        rty,
                        vals[0],
                        types,
                        async_state,
                      )
                    } else {
                      ()
                    }
                  None => ()
                }
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, vals)
              }
            }
          }
          TaskStep::Done
        } catch {
          AsyncSuspendYield => {
            task.started[0] = true
            task.waiting_set[0] = None
            TaskStep::Progressed
          }
          AsyncSuspendWait(ws) => {
            task.started[0] = true
            task.waiting_set[0] = Some(ws)
            TaskStep::Progressed
          }
          e => raise e
        }
      } else {
        // No async ABI: normal call. For sync-style async funcs, results are returned directly.
        let core_results = call_core_func_guarded(
          store, may_enter, core_func, core_args,
        )
        if func_type.is_async {
          let vals = core_results_to_component(
            core_results, func_type, types, resources, store, callee_table,
          )
          match func_type.result {
            Some(rty) =>
              if vals.length() > 0 {
                validate_lifted_stream_future(rty, vals[0], types, async_state)
              } else {
                ()
              }
            None => ()
          }
          let task_id = current_task_id(async_state)
          async_state.task_returned.set(task_id, true)
          set_task_result(async_state, task_id, vals)
        }
        TaskStep::Done
      }
    }
  }
}

///|
fn progress_one_subtask(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  // Avoid re-entering tasks already on the call stack: sync lower wrappers may
  // "pump" the event loop while inside a task, but must never step that same task.
  fn task_on_stack(id : Int) -> Bool {
    for t in async_state.task_stack {
      if t == id {
        return true
      }
    }
    false
  }

  // Start one queued subtask when an instance has no in-flight task.
  // NOTE: avoid mutating `pending_by_instance` while iterating it; some Map
  // implementations invalidate iterators and can segfault.
  let pending_keys : Array[Int] = []
  for kv in async_state.pending_by_instance.iter() {
    let (key, _queue) = kv
    pending_keys.push(key)
  }
  for key in pending_keys {
    let queue0 = match async_state.pending_by_instance.get(key) {
      Some(q) => q
      None => continue
    }
    let inflight = match async_state.inflight_by_instance.get(key) {
      Some(n) => n
      None => 0
    }
    if inflight == 0 && queue0.length() > 0 {
      let next_id = queue0.remove(0)
      if queue0.length() == 0 {
        async_state.pending_by_instance.remove(key)
      }
      match async_state.subtasks.get(next_id) {
        Some(st) =>
          if !task_on_stack(st.id) {
            st.phase[0] = SubtaskPhase::Started
            async_state.inflight_by_instance.set(key, 1)
            // Transitioned from STARTING to STARTED: notify via event.
            enqueue_waitable_event(async_state, st.id, {
              code: 1,
              index: st.id,
              payload: 1,
            })
            return true
          }
        None => ()
      }
    }
  }

  // Advance one runnable STARTED subtask/background task.
  for kv in async_state.subtasks.iter() {
    let (_id, st) = kv
    if st.phase[0] != SubtaskPhase::Started {
      continue
    }
    if task_on_stack(st.id) {
      continue
    }
    push_task(async_state, st.id, true)
    let step = match st.driver {
      SubtaskDriver::CallbackLifted(t) =>
        step_task_once(t, store, st.caller_table, async_state)
      _ => TaskStep::Blocked
    }
    pop_task(async_state)
    match step {
      TaskStep::Blocked => ()
      TaskStep::Progressed => return true
      TaskStep::Done => {
        if st.detached {
          // Detached background tasks are not observable by core code; avoid emitting events
          // and proactively clean up so shared handles can be reused deterministically.
          remove_waitable_membership(async_state, st.id)
          async_state.waitable_events.remove(st.id)
          async_state.subtasks.remove(st.id)
          async_state.task_results.remove(st.id)
          async_state.task_returned.remove(st.id)
          async_state.task_cancelled.remove(st.id)
          async_state.task_contexts.remove(st.id)
          async_state.yield_replay_upto.remove(st.id)
          async_state.wait_results.remove(st.id)
          async_state.waiting_ws.remove(st.id)
          async_state.call_results.remove(st.id)
          async_state.sync_lower_states.remove(st.id)
          free_shared_handle(async_state, st.id)
          return true
        }
        // Write subtask results into the return buffer (async-lower ABI).
        // component-spec expects the return value to be materialized in memory
        // before emitting the RETURNED event.
        let cancelled = async_state.task_cancelled.get(st.id) is Some(true)
        match st.result_ty {
          Some(_) =>
            if st.mem_addr is Some(mem_addr) {
              let mem = store.get_mem(mem_addr) catch {
                e => raise CanonCallError(e.to_string())
              }
              let vals = if cancelled {
                // Cancelled subtasks resolve without writing a value.
                take_task_result(async_state, st.id) |> ignore
                ([] : Array[ComponentValue])
              } else {
                match async_state.task_results.get(st.id) {
                  Some(v) => v
                  None => []
                }
              }
              // Lower into core values; direct scalars come back as a single
              // value which we store at `retptr`. Indirect results are written
              // by `component_results_to_core` via `retptr`.
              if !cancelled {
                let (ft, ftypes) = match st.driver {
                  SubtaskDriver::CallbackLifted(t) =>
                    match t.func {
                      ComponentFunc::Host(func_type, types, _) =>
                        (func_type, types)
                      ComponentFunc::Lifted(_, func_type, _, types, _, _, _, _) =>
                        (func_type, types)
                    }
                  _ => raise CanonCallError("unsupported subtask driver")
                }
                let core_vals = component_results_to_core(
                  vals,
                  ft,
                  ftypes,
                  st.resources,
                  store,
                  Some(st.retptr),
                )
                match core_vals {
                  [@types.Value::I32(n)] =>
                    mem.store_i32(st.retptr, n) catch {
                      _ => ()
                    }
                  [@types.Value::I64(n)] =>
                    mem.store_i64(st.retptr, n) catch {
                      _ => ()
                    }
                  _ => ()
                }
              }
            } else {
              // Result present but no memory: validated earlier for async-lower.
              raise MissingCanonMemory
            }
          None => ()
        }
        // Mark returned and emit RETURNED event. The return value itself is written by the lower wrapper.
        st.phase[0] = SubtaskPhase::Returned
        async_state.inflight_by_instance.set(st.bp_key, 0)
        enqueue_waitable_event(async_state, st.id, {
          code: 1,
          index: st.id,
          payload: 2,
        })
        return true
      }
    }
  }
  false
}

///|
fn call_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  resource_table : ResourceTable,
  async_state : AsyncState,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match func {
    ComponentFunc::Host(func_type, _types, host) =>
      if func_type.is_async {
        await_component_func(func, args, store, resource_table, async_state)
      } else {
        host(args, resource_table) catch {
          e => raise HostCallError(e.to_string())
        }
      }
    ComponentFunc::Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      may_enter,
      cb_opt,
      async_abi
    ) => {
      if func_type.is_async {
        return await_component_func(
          func, args, store, resource_table, async_state,
        )
      }
      // Sync-typed function lifted with async callback protocol.
      // These are used by component-spec/async to test yield/wait behavior.
      match cb_opt {
        Some(cb) => {
          if func_type_needs_memory(func_type, types) &&
            resources.mem_addr is None {
            raise MissingCanonMemory
          }
          let core_args = component_args_to_core(
            args, func_type, types, resources, store, resource_table, callee_table,
          )
          // Create a dedicated task context so `canon task.return` has somewhere to put results.
          let task_id = alloc_task_id(async_state)
          push_task(async_state, task_id, false)
          take_task_result(async_state, task_id) |> ignore
          let out = try {
            let core_results = call_core_func_guarded(
              store, may_enter, core_func, core_args,
            )
            let mut code = match core_results {
              [@types.Value::I32(n)] => n
              _ => raise CanonCallError("type mismatch")
            }
            while true {
              let u = code.reinterpret_as_uint()
              let tag = (u & 0xFU).reinterpret_as_int()
              if tag == 0 {
                break
              } else if tag == 1 {
                // YIELD: allowed even for synchronous tasks (must not block).
                progress_one_subtask(async_state, store) |> ignore
                async_state.in_async_callback[0] = true
                let r = call_core_func_guarded(store, may_enter, cb, [
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                ]) catch {
                  e => {
                    async_state.in_async_callback[0] = false
                    raise e
                  }
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [@types.Value::I32(n)] => n
                  _ => raise CanonCallError("type mismatch")
                }
              } else if tag == 2 {
                // WAIT would block this synchronous call.
                raise CanonCallError(
                  "cannot block a synchronous task before returning",
                )
              } else {
                raise CanonCallError("unsupported callback code: \{tag}")
              }
            }
            let vals = match take_task_result(async_state, task_id) {
              Some(v) => v
              None => []
            }
            match func_type.result {
              Some(_) =>
                if vals.length() == 0 {
                  raise CanonCallError("missing task.return")
                } else {
                  ()
                }
              None => ()
            }
            vals
          } catch {
            e => {
              pop_task(async_state)
              raise e
            }
          }
          pop_task(async_state)
          return out
        }
        None => ()
      }
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let core_args = component_args_to_core(
        args, func_type, types, resources, store, resource_table, callee_table,
      )
      let core_results = call_core_func_guarded(
        store, may_enter, core_func, core_args,
      )
      let component_results = core_results_to_component(
        core_results, func_type, types, resources, store, callee_table,
      )
      // `canon lift` must validate stream/future handles at the point they are lifted
      // from core values (component-spec "done" semantics).
      match func_type.result {
        Some(rty) =>
          if component_results.length() > 0 {
            validate_lifted_stream_future(
              rty,
              component_results[0],
              types,
              async_state,
            )
          } else {
            ()
          }
        None => ()
      }
      match resources.post_return {
        Some(pr) => {
          let prev = canon_may_leave[0]
          canon_may_leave[0] = false
          (call_core_func_guarded(store, may_enter, pr, core_results) catch {
            e => {
              canon_may_leave[0] = prev
              raise e
            }
          })
          |> ignore
          canon_may_leave[0] = prev
        }
        None => ()
      }
      // If this function belongs to a different component instance, transfer
      // owned resources into the caller's table so handles are local.
      if resource_table.id != callee_table.id {
        match func_type.result {
          Some(TypeIdx(ti)) =>
            match types.get(ti) {
              Some(Some(TypeDef::Own(_resource_tyidx))) =>
                match component_results {
                  [ComponentValue::U32(h)] => {
                    let entry = match callee_table.free(h) {
                      Some(e) => e
                      None => raise CanonCallError("unknown handle index \{h}")
                    }
                    let new_h = resource_table.alloc(entry)
                    [ComponentValue::U32(new_h)]
                  }
                  _ => component_results
                }
              _ => component_results
            }
          _ => component_results
        }
      } else {
        component_results
      }
    }
  }
}

///|
