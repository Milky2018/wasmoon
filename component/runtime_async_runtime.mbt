///|
/// Drive an async component function to completion (blocking the current task).
///
/// Async functions communicate their eventual results through `canon task.return`.
fn transfer_args_if_needed(
  args : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let out : Array[ComponentValue] = []
  for i, param in func_type.params {
    let v = if i < args.length() { args[i] } else { raise InvalidValueIndex(i) }
    out.push(
      transfer_stream_future_value(
        param.ty,
        v,
        types,
        async_state,
        from_component_id,
        to_component_id,
      ),
    )
  }
  out
}

///|
fn transfer_results_if_needed(
  vals : Array[ComponentValue],
  result_ty : ValType?,
  types : Array[TypeDef?],
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match result_ty {
    None => vals
    Some(rty) =>
      if vals.length() > 0 {
        [
          transfer_stream_future_value(
            rty,
            vals[0],
            types,
            async_state,
            from_component_id,
            to_component_id,
          ),
        ]
      } else {
        vals
      }
  }
}

///|
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
  let caller_task_id = current_task_id(async_state)
  let callee_instance_id = match func {
    ComponentFunc::Host(_, _, _) => -1
    ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
  }
  if callee_instance_id >= 0 &&
    caller_task_id != 0L &&
    !may_enter_instance_from_task(
      async_state, caller_task_id, callee_instance_id,
    ) {
    raise CanonCallError("wasm trap: cannot enter component instance")
  }
  let task_id = alloc_task_id(async_state)
  init_task_meta(async_state, task_id, callee_instance_id, caller_task_id)
  push_task(async_state, task_id, can_block)
  // Ensure this async task has a current thread handle in the callee instance's
  // handle space (affects stream/future numbering per component-spec/async).
  match func {
    ComponentFunc::Host(_, _, _) =>
      ensure_task_thread(async_state, caller_table.id, task_id)
    ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
      ensure_task_thread(async_state, callee_table.id, task_id)
  }
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
        let xargs = transfer_args_if_needed(
          args,
          func_type,
          types,
          async_state,
          caller_table.id,
          callee_table.id,
        )
        let core_args = component_args_to_core(
          xargs, func_type, types, resources, store, caller_table, callee_table,
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
                if async_state.stream_cursor_stack.length() > 0 {
                  async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
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
                    // Once the awaited set has an event, allow other ready tasks to make a bit
                    // more progress before restarting the core function. This matches Wasmtime's
                    // event-loop behavior where delivering one event can synchronously enable
                    // progress in other tasks (e.g. zero-length stream rendezvous).
                    let mut spins = 0
                    while spins < 32 && progress_one_subtask(async_state, store) {
                      spins = spins + 1
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
                        callee_table.id,
                      )
                    } else {
                      ()
                    }
                  None => ()
                }
                let out_vals = transfer_results_if_needed(
                  vals,
                  func_type.result,
                  types,
                  async_state,
                  callee_table.id,
                  caller_table.id,
                )
                // Mirror task.return bookkeeping so other parts can uniformly query results.
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, caller_table.id, out_vals)
                pop_task(async_state)
                drop_task_thread(async_state, task_id)
                remove_task_meta(async_state, task_id)
                return out_vals
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
                      callee_table.id,
                    )
                  } else {
                    ()
                  }
                None => ()
              }
              let out_vals = transfer_results_if_needed(
                vals,
                func_type.result,
                types,
                async_state,
                callee_table.id,
                caller_table.id,
              )
              // Mirror task.return bookkeeping so other parts can uniformly query results.
              async_state.task_returned.set(task_id, true)
              set_task_result(async_state, task_id, caller_table.id, out_vals)
              out_vals
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
                async_state.stream_results_cb.remove(
                  current_task_id(async_state),
                )
                async_state.in_async_callback[0] = true
                preset_canon_debug_message("async.callback.yield(ev=NONE)")
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
                let ws_key = handle_key(callee_table.id, payload)
                let ev = wait_for_event(async_state, store, ws_key)
                async_state.stream_results_cb.remove(
                  current_task_id(async_state),
                )
                async_state.in_async_callback[0] = true
                fn subtask_mem_dbg(ev : WaitEvent) -> String {
                  if ev.code != 1 || ev.payload != 2 {
                    return ""
                  }
                  let sub_key = handle_key(ev.owner_component_id, ev.index)
                  match async_state.subtasks.get(sub_key) {
                    Some(st) =>
                      match st.mem_addr {
                        Some(addr) => {
                          let mem = store.get_mem(addr) catch { _ => return "" }
                          let n = mem.load_i32(st.retptr) catch {
                            _ => return ""
                          }
                          " retptr=\{st.retptr} mem=\{n}"
                        }
                        None => ""
                      }
                    None => ""
                  }
                }

                preset_canon_debug_message(
                  "async.callback.wait(ev code=\{ev.code} index=\{ev.index} payload=\{ev.payload})\{subtask_mem_dbg(ev)}",
                )
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
            let vals = match take_task_result(async_state, task_id) {
              Some(v) => v
              None => []
            }
            transfer_results_if_needed(
              vals,
              func_type.result,
              types,
              async_state,
              callee_table.id,
              caller_table.id,
            )
          }
        }
      }
    }
  } catch {
    e => {
      pop_task(async_state)
      drop_task_thread(async_state, task_id)
      remove_task_meta(async_state, task_id)
      raise e
    }
  }
  pop_task(async_state)
  drop_task_thread(async_state, task_id)
  remove_task_meta(async_state, task_id)
  out
}

///|
fn wait_for_event(
  async_state : AsyncState,
  store : @runtime.Store,
  ws_key : Int64,
) -> WaitEvent raise ComponentRuntimeError {
  match async_state.waitable_sets.get(ws_key) {
    Some(set) => set.waiters[0] = set.waiters[0] + 1
    None =>
      raise CanonCallError("unknown waitable set index \{key_local(ws_key)}")
  }
  while true {
    match pop_waitable_event(async_state, ws_key) {
      Some(ev) => {
        acknowledge_waitable_event(async_state, ev)
        match async_state.waitable_sets.get(ws_key) {
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
fn waitable_set_has_event(async_state : AsyncState, ws_key : Int64) -> Bool {
  match async_state.waitable_sets.get(ws_key) {
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
  fn task_owner_component_id() -> Int {
    match task.func {
      ComponentFunc::Host(_, _, _) => caller_table.id
      ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
        callee_table.id
    }
  }

  fn ws_key_from_local(ws : Int) -> Int64 {
    handle_key(task_owner_component_id(), ws)
  }

  fn set_waiting(ws_opt : Int64?) -> Unit {
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
      let args_owner = task.args_owner_component_id[0]
      if args_owner != callee_table.id {
        let xargs = transfer_args_if_needed(
          task.args,
          func_type,
          types,
          async_state,
          args_owner,
          callee_table.id,
        )
        // Persist the renumbered handles so subsequent callback steps don't re-transfer.
        task.args.clear()
        for v in xargs {
          task.args.push(v)
        }
        task.args_owner_component_id[0] = callee_table.id
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
              if async_state.stream_cursor_stack.length() > 0 {
                async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
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
              if async_state.stream_cursor_stack.length() > 0 {
                async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
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
          set_waiting(
            if d.tag == 2 {
              Some(ws_key_from_local(d.payload))
            } else {
              None
            },
          )
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
          async_state.stream_results_cb.remove(current_task_id(async_state))
          async_state.in_async_callback[0] = true
          let r = call_core_func_guarded(store, may_enter, cb, args)
          async_state.in_async_callback[0] = false
          let code = match r {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(
            if d.tag == 2 {
              Some(ws_key_from_local(d.payload))
            } else {
              None
            },
          )
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        if d0.tag == 2 {
          let ws_key = ws_key_from_local(d0.payload)
          set_waiting(Some(ws_key))
          // Cancellation preempts waiting: deliver TASK_CANCELLED immediately.
          if task.cancelled[0] {
            task.cancelled[0] = false
            set_waiting(None)
            async_state.stream_results_cb.remove(current_task_id(async_state))
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
            set_waiting(
              if d.tag == 2 {
                Some(ws_key_from_local(d.payload))
              } else {
                None
              },
            )
            return if d.tag == 0 {
              TaskStep::Done
            } else {
              TaskStep::Progressed
            }
          }
          if !waitable_set_has_event(async_state, ws_key) {
            return TaskStep::Blocked
          }
          let ev = match pop_waitable_event(async_state, ws_key) {
            Some(ev) => ev
            None => return TaskStep::Blocked
          }
          acknowledge_waitable_event(async_state, ev)
          // Leaving the waiting state to process one event.
          set_waiting(None)
          async_state.stream_results_cb.remove(current_task_id(async_state))
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
          set_waiting(
            if d.tag == 2 {
              Some(ws_key_from_local(d.payload))
            } else {
              None
            },
          )
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
                        callee_table.id,
                      )
                    } else {
                      ()
                    }
                  None => ()
                }
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, callee_table.id, vals)
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
                validate_lifted_stream_future(
                  rty,
                  vals[0],
                  types,
                  async_state,
                  callee_table.id,
                )
              } else {
                ()
              }
            None => ()
          }
          let task_id = current_task_id(async_state)
          async_state.task_returned.set(task_id, true)
          set_task_result(async_state, task_id, callee_table.id, vals)
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
  fn task_on_stack(id : Int64) -> Bool {
    for t in async_state.task_stack {
      if t == id {
        return true
      }
    }
    false
  }

  // Deterministic ordering: Map iteration order is unspecified, but component-spec/async
  // tests assume a stable event-loop schedule.
  //
  // - "Synthetic" async task ids are allocated as -1, -2, ... (older = greater).
  // - Subtask task ids are handle-keys (owner<<32 | local-handle), where smaller local
  //   handles are older (e.g. subtask 5 must start/step before subtask 6).
  fn task_sort_before(a : Int64, b : Int64) -> Bool {
    let a_is_handle = a >= 0L
    let b_is_handle = b >= 0L
    if a_is_handle != b_is_handle {
      // Prefer stepping subtasks (handle-key ids) before synthetic tasks.
      return a_is_handle && !b_is_handle
    }
    if !a_is_handle {
      // Both synthetic: older first (greater id, e.g. -1 before -2).
      return a > b
    }
    // Both handle-keys: sort by owner then local handle (ascending).
    let ao = key_owner(a)
    let bo = key_owner(b)
    if ao != bo {
      return ao < bo
    }
    key_local(a) < key_local(b)
  }

  fn sort_i64_by_task_order(xs : Array[Int64]) -> Unit {
    let n = xs.length()
    for i in 0..<n {
      let mut best_i = i
      for j in (i + 1)..<n {
        if task_sort_before(xs[j], xs[best_i]) {
          best_i = j
        }
      }
      if best_i != i {
        let tmp = xs[i]
        xs[i] = xs[best_i]
        xs[best_i] = tmp
      }
    }
  }

  // Start at most one queued subtask when its backpressure slot is free.
  // If multiple subtasks are eligible across different `bp_key`s, choose the oldest
  // (by subtask handle ordering) to match Wasmtime scheduling.
  let candidates : Array[(Int, Int64)] = []
  let pending_keys : Array[Int] = []
  for kv in async_state.pending_by_instance.iter() {
    let (key, _queue) = kv
    pending_keys.push(key)
  }
  // Stable key scan: deterministic candidates list.
  let nkeys = pending_keys.length()
  for i in 0..<nkeys {
    let mut min_i = i
    for j in (i + 1)..<nkeys {
      if pending_keys[j] < pending_keys[min_i] {
        min_i = j
      }
    }
    if min_i != i {
      let tmp = pending_keys[i]
      pending_keys[i] = pending_keys[min_i]
      pending_keys[min_i] = tmp
    }
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
      let next_id = queue0[0]
      if !task_on_stack(next_id) {
        candidates.push((key, next_id))
      }
    }
  }
  if candidates.length() > 0 {
    // Pick candidate with smallest (owner, local) handle id.
    let mut best_i = 0
    for i in 1..<candidates.length() {
      let (_k, tid) = candidates[i]
      let (_bk, best_tid) = candidates[best_i]
      if task_sort_before(tid, best_tid) {
        best_i = i
      }
    }
    let (key, next_id) = candidates[best_i]
    let queue0 = match async_state.pending_by_instance.get(key) {
      Some(q) => q
      None => ([] : Array[Int64])
    }
    if queue0.length() > 0 && queue0[0] == next_id {
      queue0.remove(0) |> ignore
      if queue0.length() == 0 {
        async_state.pending_by_instance.remove(key)
      } else {
        async_state.pending_by_instance.set(key, queue0)
      }
    } else {
      // Fallback: remove from anywhere if queue was mutated unexpectedly.
      let mut j = 0
      while j < queue0.length() {
        if queue0[j] == next_id {
          queue0.remove(j) |> ignore
        } else {
          j = j + 1
        }
      }
      if queue0.length() == 0 {
        async_state.pending_by_instance.remove(key)
      } else {
        async_state.pending_by_instance.set(key, queue0)
      }
    }
    match async_state.subtasks.get(next_id) {
      Some(st) =>
        if !task_on_stack(next_id) {
          st.phase[0] = SubtaskPhase::Started
          async_state.inflight_by_instance.set(key, 1)
          // Transitioned from STARTING to STARTED: notify via event.
          let owner_component_id = st.caller_table.id
          enqueue_waitable_event(
            async_state,
            handle_key(owner_component_id, st.id),
            { owner_component_id, code: 1, index: st.id, payload: 1 },
          )
          return true
        }
      None => ()
    }
  }

  // Advance one runnable STARTED subtask/background task.
  let started_ids : Array[Int64] = []
  for kv in async_state.subtasks.iter() {
    let (task_id, st0) = kv
    if st0.phase[0] == SubtaskPhase::Started && !task_on_stack(task_id) {
      started_ids.push(task_id)
    }
  }
  sort_i64_by_task_order(started_ids)
  for task_id in started_ids {
    let st = match async_state.subtasks.get(task_id) {
      Some(s) => s
      None => continue
    }
    if st.phase[0] != SubtaskPhase::Started {
      continue
    }
    if task_on_stack(task_id) {
      continue
    }
    ensure_task_thread(async_state, st.callee_instance_id, task_id)
    push_task(async_state, task_id, true)
    let step = match st.driver {
      SubtaskDriver::CallbackLifted(t) =>
        step_task_once(t, store, st.caller_table, async_state)
    }
    pop_task(async_state)
    match step {
      TaskStep::Blocked => ()
      TaskStep::Progressed => return true
      TaskStep::Done => {
        drop_task_thread(async_state, task_id)
        if st.detached {
          // Detached background tasks are not observable by core code; avoid emitting events
          // and proactively clean up so shared handles can be reused deterministically.
          let owner_component_id = st.caller_table.id
          let wkey = handle_key(owner_component_id, st.id)
          remove_waitable_membership(async_state, owner_component_id, st.id)
          async_state.waitable_events.remove(wkey)
          async_state.subtasks.remove(task_id)
          async_state.task_results.remove(task_id)
          async_state.task_result_owner.remove(task_id)
          async_state.task_returned.remove(task_id)
          async_state.task_cancelled.remove(task_id)
          async_state.task_contexts.remove(task_id)
          remove_task_meta(async_state, task_id)
          async_state.yield_replay_upto.remove(task_id)
          async_state.wait_results.remove(task_id)
          async_state.waiting_ws.remove(task_id)
          async_state.call_results.remove(task_id)
          async_state.stream_results.remove(task_id)
          async_state.stream_results_cb.remove(task_id)
          async_state.sync_lower_states.remove(task_id)
          async_state.inflight_by_instance.set(st.bp_key, 0)
          free_shared_handle(async_state, owner_component_id, st.id)
          return true
        }
        // Write subtask results into the return buffer (async-lower ABI).
        // component-spec expects the return value to be materialized in memory
        // before emitting the RETURNED event.
        let cancelled = async_state.task_cancelled.get(task_id) is Some(true)
        match st.result_ty {
          Some(_) =>
            if st.mem_addr is Some(mem_addr) {
              let mem = store.get_mem(mem_addr) catch {
                e => raise CanonCallError(e.to_string())
              }
              let mut vals = if cancelled {
                // Cancelled subtasks resolve without writing a value.
                take_task_result(async_state, task_id) |> ignore
                ([] : Array[ComponentValue])
              } else {
                match async_state.task_results.get(task_id) {
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
                }
                // Subtask results are observed by the caller component instance; if the task ran
                // in a nested component, move stream/future handles into the caller's local space.
                vals = transfer_results_if_needed(
                  vals,
                  ft.result,
                  ftypes,
                  async_state,
                  st.callee_instance_id,
                  st.caller_table.id,
                )
                set_task_result(async_state, task_id, st.caller_table.id, vals)
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
        let owner_component_id = st.caller_table.id
        enqueue_waitable_event(
          async_state,
          handle_key(owner_component_id, st.id),
          { owner_component_id, code: 1, index: st.id, payload: 2 },
        )
        return true
      }
    }
  }
  false
}

///|
/// Best-effort event loop pump usable from canonical intrinsics.
/// Returns `true` if at least one subtask made progress.
pub fn progress_one_subtask_intrinsic(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  progress_one_subtask(async_state, store)
}

///|
fn call_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  resource_table : ResourceTable,
  async_state : AsyncState,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  // Many canonical ops implement replay/caching keyed by `current_task_id` and
  // cursor stacks. When entering from the host (no active task context), run
  // the whole component call under a fresh synthetic task id so caches don't
  // leak across independent invocations.
  if async_state.task_stack.length() == 1 && async_state.task_stack[0] == 0 {
    let task_id = alloc_task_id(async_state)
    // This is a synthetic "host entry" task used only for replay/caching keys.
    // It must not participate in async re-entrancy checks.
    init_task_meta(async_state, task_id, -1, 0L)
    // Preserve the host-provided `task_can_block` flag: exported async funcs must be allowed to block.
    let can_block = async_state.task_can_block[0]
    push_task(async_state, task_id, can_block)
    if can_block {
      // Async tasks always maintain a current thread handle.
      ensure_task_thread(async_state, resource_table.id, task_id)
    } else {
      let inst_id = match func {
        ComponentFunc::Host(_, _, _) => resource_table.id
        ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
          callee_table.id
      }
      // Some synchronous component instances still need the implicit thread
      // handle slot reserved for component-spec/async handle numbering.
      if async_state.thread_handle_required.get(inst_id) is Some(true) {
        ensure_task_thread(async_state, inst_id, task_id)
      }
    }
    let out = call_component_func_in_task(
      func, args, store, resource_table, async_state,
    ) catch {
      e => {
        pop_task(async_state)
        drop_task_thread(async_state, task_id)
        remove_task_meta(async_state, task_id)
        raise e
      }
    }
    pop_task(async_state)
    drop_task_thread(async_state, task_id)
    remove_task_meta(async_state, task_id)
    return out
  }
  call_component_func_in_task(func, args, store, resource_table, async_state)
}

///|
fn call_component_func_in_task(
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
      _async_abi
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
          let xargs = transfer_args_if_needed(
            args,
            func_type,
            types,
            async_state,
            resource_table.id,
            callee_table.id,
          )
          let core_args = component_args_to_core(
            xargs, func_type, types, resources, store, resource_table, callee_table,
          )
          // Create a dedicated task context so `canon task.return` has somewhere to put results.
          let task_id = alloc_task_id(async_state)
          let caller_task_id = current_task_id(async_state)
          init_task_meta(async_state, task_id, callee_table.id, caller_task_id)
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
                async_state.stream_results_cb.remove(
                  current_task_id(async_state),
                )
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
            transfer_results_if_needed(
              vals,
              func_type.result,
              types,
              async_state,
              callee_table.id,
              resource_table.id,
            )
          } catch {
            e => {
              pop_task(async_state)
              remove_task_meta(async_state, task_id)
              raise e
            }
          }
          pop_task(async_state)
          remove_task_meta(async_state, task_id)
          return out
        }
        None => ()
      }
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let xargs = transfer_args_if_needed(
        args,
        func_type,
        types,
        async_state,
        resource_table.id,
        callee_table.id,
      )
      let core_args = component_args_to_core(
        xargs, func_type, types, resources, store, resource_table, callee_table,
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
              callee_table.id,
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
      let out0 = if resource_table.id != callee_table.id {
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
      transfer_results_if_needed(
        out0,
        func_type.result,
        types,
        async_state,
        callee_table.id,
        resource_table.id,
      )
    }
  }
}

///|
