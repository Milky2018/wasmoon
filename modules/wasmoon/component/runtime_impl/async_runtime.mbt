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
) -> (Array[ComponentValue], Array[Array[Int]]) raise ComponentRuntimeError {
  let lends : Array[Array[Int]] = []
  for i, param in func_type.params {
    let v = if i < args.length() { args[i] } else { raise InvalidValueIndex(i) }
    collect_direct_borrow_lends(
      param.ty,
      v,
      types,
      async_state,
      from_component_id,
      to_component_id,
      lends,
    )
  }
  fn release_lends() -> Unit {
    for counter in lends {
      counter[0] -= 1
    }
  }
  let out : Array[ComponentValue] = []
  {
    errdefer release_lends()
    for i, param in func_type.params {
      let v = if i < args.length() {
        args[i]
      } else {
        raise InvalidValueIndex(i)
      }
      let transferred = transfer_stream_future_value(
        param.ty,
        v,
        types,
        async_state,
        from_component_id,
        to_component_id,
      )
      out.push(transferred)
    }
  }
  (out, lends)
}

///|
fn release_direct_borrow_lends(lends : Array[Array[Int]]) -> Unit {
  for counter in lends {
    counter[0] -= 1
  }
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
/// Drive one suspended core invocation on the component host event loop.
///
/// This resumes the captured interpreter state; it never re-enters the
/// function from its first instruction.
fn drive_core_to_completion(
  async_state : AsyncState,
  store : @runtime.Store,
  initial : CoreExecutionOutcome,
) -> Array[@types.Value] raise ComponentRuntimeError {
  let mut outcome = initial
  while true {
    match outcome {
      Returned(results) => return results
      Suspended(reason, continuation) => {
        match reason {
          Yield =>
            if !progress_one_subtask(async_state, store) {
              continuation.cancel()
              raise CanonCallError(
                "wasm trap: deadlock detected: event loop cannot make further progress",
              )
            }
          Wait(waitable_set) =>
            while !waitable_set_has_event(async_state, waitable_set) {
              if !progress_one_subtask(async_state, store) {
                continuation.cancel()
                raise CanonCallError(
                  "wasm trap: deadlock detected: event loop cannot make further progress",
                )
              }
            }
        }
        if reason is Wait(_) {
          // Deliver one fair scheduler round before resuming the waiter. A
          // single readiness event can make a peer task runnable (for example,
          // a zero-length stream rendezvous enabling the real write).
          let turns = runnable_subtask_count(async_state)
          for _ in 0..<turns {
            if !progress_one_subtask(async_state, store) {
              break
            }
          }
        }
        outcome = continuation.continue_execution()
      }
    }
  }
  raise CanonCallError("unreachable")
}

///|
fn runnable_subtask_count(async_state : AsyncState) -> Int {
  let mut count = 0
  for entry in async_state.subtasks {
    let (_task_id, subtask) = entry
    if subtask.phase[0] == Started {
      count = count + 1
    }
  }
  count
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
    Host(_, _, _) => -1
    HostAsync(_, _, _) => -1
    Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
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
  take_task_result(async_state, task_id) |> ignore
  let out = {
    errdefer {
      pop_task(async_state)
      drop_task_thread(async_state, task_id)
      remove_task_meta(async_state, task_id)
    }
    match func {
      Host(_ft, _types, host) => host(args, caller_table)
      HostAsync(_ft, _types, start) => {
        let future = start(args, caller_table)
        let result : Ref[Array[ComponentValue]?] = Ref(None)
        while result.val is None {
          match (future.poll)() {
            Ready(values) => result.val = Some(values)
            Pending =>
              if !progress_one_subtask(async_state, store) {
                match async_state.host_event_loop.val {
                  Some(event_loop) =>
                    if !(event_loop.wait)() {
                      raise CanonCallError(
                        "wasm trap: async host event loop cannot make further progress",
                      )
                    }
                  None =>
                    raise CanonCallError(
                      "wasm trap: async host function has no event loop",
                    )
                }
              }
          }
        }
        match result.val {
          Some(values) => values
          None =>
            raise HostCallError("asynchronous host function did not finish")
        }
      }
      Lifted(
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
        let (xargs, direct_borrow_lends) = transfer_args_if_needed(
          args,
          func_type,
          types,
          async_state,
          caller_table.id,
          callee_table.id,
        )
        defer release_direct_borrow_lends(direct_borrow_lends)
        let core_args = component_args_to_core(
          xargs, func_type, types, resources, store, callee_table, callee_table,
        )
        match cb_opt {
          None =>
            if async_abi {
              let core_results = drive_core_to_completion(
                async_state,
                store,
                call_core_func_guarded_outcome(
                  store,
                  may_enter,
                  core_func,
                  core_args,
                  Stackful,
                ),
              )
              // Prefer results published via `canon task.return` (used by many
              // async-ABI functions), but fall back to direct core results.
              let vals = match take_task_result(async_state, task_id) {
                Some(values) => values
                None =>
                  core_results_to_component(
                    core_results, func_type, types, resources, store, callee_table,
                  )
              }
              match func_type.result {
                Some(result_type) =>
                  if vals.length() > 0 {
                    validate_lifted_stream_future(
                      result_type,
                      vals[0],
                      types,
                      async_state,
                      callee_table.id,
                    )
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
              async_state.task_returned.set(task_id, true)
              set_task_result(async_state, task_id, caller_table.id, out_vals)
              pop_task(async_state)
              drop_task_thread(async_state, task_id)
              remove_task_meta(async_state, task_id)
              return out_vals
            } else {
              // Sync-style async: the core function returns results directly (no task.return).
              let core_results = drive_core_to_completion(
                async_state,
                store,
                call_core_func_guarded_outcome(
                  store,
                  may_enter,
                  core_func,
                  core_args,
                  Stackful,
                ),
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
            let core_results = drive_core_to_completion(
              async_state,
              store,
              call_core_func_guarded_outcome(
                store,
                may_enter,
                core_func,
                core_args,
                CallbackStep,
              ),
            )
            let mut code = match core_results {
              [I32(n)] => n
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
                preset_canon_debug_message("async.callback.yield(ev=NONE)")
                let r = {
                  errdefer {
                    async_state.in_async_callback[0] = false
                  }
                  drive_core_to_completion(
                    async_state,
                    store,
                    call_core_func_guarded_outcome(
                      store,
                      may_enter,
                      cb,
                      [I32(0), I32(0), I32(0)],
                      CallbackStep,
                    ),
                  )
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [I32(n)] => n
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
                let r = {
                  errdefer {
                    async_state.in_async_callback[0] = false
                  }
                  drive_core_to_completion(
                    async_state,
                    store,
                    call_core_func_guarded_outcome(
                      store,
                      may_enter,
                      cb,
                      [I32(ev.code), I32(ev.index), I32(ev.payload)],
                      CallbackStep,
                    ),
                  )
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [I32(n)] => n
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
    if pop_waitable_event(async_state, ws_key) is Some(ev) {
      acknowledge_waitable_event(async_state, ev)
      if async_state.waitable_sets.get(ws_key) is Some(set) {
        set.waiters[0] = set.waiters[0] - 1
      }
      return ev
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
} derive(Debug)

///|
fn decode_callback_code(code : Int) -> DecodedCallbackCode {
  let u = code.reinterpret_as_uint()
  let tag = (u & 0xFU).reinterpret_as_int()
  let payload = (u >> 4).reinterpret_as_int()
  { tag, payload, }
}

///|
fn step_task_once(
  task : CallbackTask,
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> TaskStep raise ComponentRuntimeError {
  step_task_once_impl(task, store, caller_table, async_state)
}

///|
fn step_task_once_impl(
  task : CallbackTask,
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> TaskStep raise ComponentRuntimeError {
  fn task_owner_component_id() -> Int {
    match task.func {
      Host(_, _, _) => caller_table.id
      HostAsync(_, _, _) => caller_table.id
      Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
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
    if prev is Some(ws) && async_state.waitable_sets.get(ws) is Some(set) {
      set.waiters[0] = set.waiters[0] - 1
    }
    if ws_opt is Some(ws) && async_state.waitable_sets.get(ws) is Some(set) {
      set.waiters[0] = set.waiters[0] + 1
    }
    task.waiting_set[0] = ws_opt
  }

  fn poll_core(
    invoke : () -> CoreExecutionOutcome raise ComponentRuntimeError,
  ) -> TaskCorePoll raise ComponentRuntimeError {
    let outcome = match task.continuation[0] {
      Some(continuation) => {
        task.continuation[0] = None
        continuation.continue_execution()
      }
      None => invoke()
    }
    match outcome {
      Returned(results) => {
        set_waiting(None)
        CoreReady(results)
      }
      Suspended(reason, continuation) => {
        task.continuation[0] = Some(continuation)
        match reason {
          Yield => {
            set_waiting(None)
            CorePending(Progressed)
          }
          Wait(waitable_set) => {
            set_waiting(Some(waitable_set))
            CorePending(Blocked)
          }
        }
      }
    }
  }

  match task.func {
    Host(_ft, _types, host) => {
      let values = host(task.args, caller_table)
      set_task_result(
        async_state,
        current_task_id(async_state),
        caller_table.id,
        values,
      )
      Done
    }
    HostAsync(_ft, _types, start) => {
      if task.host_future[0] is None {
        task.host_future[0] = Some(start(task.args, caller_table))
      }
      guard task.host_future[0] is Some(future) else {
        raise HostCallError("asynchronous host future was not initialized")
      }
      if task.cancelled[0] {
        (future.cancel)()
        async_state.task_self_cancelled.set(current_task_id(async_state), true)
        Done
      } else {
        match (future.poll)() {
          Pending => Blocked
          Ready(values) => {
            set_task_result(
              async_state,
              current_task_id(async_state),
              caller_table.id,
              values,
            )
            Done
          }
        }
      }
    }
    Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      entry,
      cb_opt,
      async_abi
    ) => {
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let args_owner = task.args_owner_component_id[0]
      if args_owner != callee_table.id {
        let (xargs, direct_borrow_lends) = transfer_args_if_needed(
          task.args,
          func_type,
          types,
          async_state,
          args_owner,
          callee_table.id,
        )
        defer release_direct_borrow_lends(direct_borrow_lends)
        // Persist the renumbered handles so subsequent callback steps don't re-transfer.
        task.args.clear()
        for v in xargs {
          task.args.push(v)
        }
        task.args_owner_component_id[0] = callee_table.id
      }
      async_state.resource_tables.set(callee_table.id, callee_table)
      let core_args : Array[@types.Value] = if cb_opt is Some(_) &&
        task.started[0] {
        // Callback invocations receive only the event triple below. Re-lowering
        // the original component arguments would duplicate task-scoped borrows.
        []
      } else {
        component_args_to_core(
          task.args,
          func_type,
          types,
          resources,
          store,
          callee_table,
          callee_table,
        )
      }

      // Callback-style async ABI: initial call returns a callback code; resumption uses `callback`.
      if cb_opt is Some(cb) {
        // If we were suspended while waiting on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) && !task.cancelled[0] {
              return Blocked
            }
          None => ()
        }
        if !task.started[0] || task.continuation[0] is Some(_) {
          let polled = poll_core(fn() raise ComponentRuntimeError {
            call_core_func_guarded_outcome(
              store,
              entry,
              core_func,
              core_args,
              CallbackStep,
            )
          })
          let core_results = match polled {
            CoreReady(results) => results
            CorePending(step) => return step
          }
          // Automatic backpressure is released only after the initial call
          // actually returns a callback code. Merely entering and suspending
          // that call does not count as started.
          task.started[0] = true
          let code = match core_results {
            [I32(n)] => n
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
          return if d.tag == 0 { Done } else { Progressed }
        }
        let d0 = decode_callback_code(task.code[0])
        if d0.tag == 0 {
          return Done
        }
        if d0.tag == 1 {
          // YIELD
          let args = if task.cancelled[0] {
            task.cancelled[0] = false
            // TASK_CANCELLED=6, index=0, payload=0 (component-spec convention).
            [@types.Value::I32(6), I32(0), I32(0)]
          } else {
            [I32(0), I32(0), I32(0)]
          }
          async_state.in_async_callback[0] = true
          let polled = poll_core(fn() raise ComponentRuntimeError {
            call_core_func_guarded_outcome(store, entry, cb, args, CallbackStep)
          })
          async_state.in_async_callback[0] = false
          let r = match polled {
            CoreReady(results) => results
            CorePending(step) => return step
          }
          let code = match r {
            [I32(n)] => n
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
          return if d.tag == 0 { Done } else { Progressed }
        }
        if d0.tag == 2 {
          let ws_key = ws_key_from_local(d0.payload)
          set_waiting(Some(ws_key))
          // Cancellation preempts waiting: deliver TASK_CANCELLED immediately.
          if task.cancelled[0] {
            task.cancelled[0] = false
            set_waiting(None)
            async_state.in_async_callback[0] = true
            let polled = poll_core(fn() raise ComponentRuntimeError {
              call_core_func_guarded_outcome(
                store,
                entry,
                cb,
                [I32(6), I32(0), I32(0)],
                CallbackStep,
              )
            })
            async_state.in_async_callback[0] = false
            let r = match polled {
              CoreReady(results) => results
              CorePending(step) => return step
            }
            let code = match r {
              [I32(n)] => n
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
            return if d.tag == 0 { Done } else { Progressed }
          }
          if !waitable_set_has_event(async_state, ws_key) {
            return Blocked
          }
          let ev = match pop_waitable_event(async_state, ws_key) {
            Some(ev) => ev
            None => return Blocked
          }
          acknowledge_waitable_event(async_state, ev)
          // Leaving the waiting state to process one event.
          set_waiting(None)
          async_state.in_async_callback[0] = true
          let polled = poll_core(fn() raise ComponentRuntimeError {
            call_core_func_guarded_outcome(
              store,
              entry,
              cb,
              [I32(ev.code), I32(ev.index), I32(ev.payload)],
              CallbackStep,
            )
          })
          async_state.in_async_callback[0] = false
          let r = match polled {
            CoreReady(results) => results
            CorePending(step) => return step
          }
          let code = match r {
            [I32(n)] => n
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
          return if d.tag == 0 { Done } else { Progressed }
        }
        raise CanonCallError("unsupported callback code: \{d0.tag}")
      }

      // Sync-style async ABI uses cooperative suspension.
      if async_abi {
        // If previously blocked on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) &&
              !task.cancelled[0] &&
              !(async_state.task_cancelled.get(current_task_id(async_state))
              is Some(true)) {
              return Blocked
            }
          None => ()
        }
        let polled = poll_core(fn() raise ComponentRuntimeError {
          call_core_func_guarded_outcome(
            store,
            entry,
            core_func,
            core_args,
            if func_type.is_async || core_func.may_suspend {
              Stackful
            } else {
              RunToCompletion
            },
          )
        })
        let core_results = match polled {
          CoreReady(results) => results
          CorePending(step) => {
            task.started[0] = true
            return step
          }
        }
        let task_id = current_task_id(async_state)
        // Prefer results published via `canon task.return` (many async-abi
        // functions return `[]` from core and communicate via task.return),
        // but fall back to direct core results.
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
        Done
      } else {
        // A core function without the canonical async option can still suspend
        // through a sync-lowered async import.
        let polled = poll_core(fn() raise ComponentRuntimeError {
          call_core_func_guarded_outcome(
            store,
            entry,
            core_func,
            core_args,
            if func_type.is_async || core_func.may_suspend {
              Stackful
            } else {
              RunToCompletion
            },
          )
        })
        let core_results = match polled {
          CoreReady(results) => results
          CorePending(step) => {
            task.started[0] = true
            return step
          }
        }
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
        Done
      }
    }
  }
}

///|
fn progress_one_subtask_nonblocking(
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
    if queue0.length() > 0 {
      let next_id = queue0[0]
      let can_start = match async_state.subtasks.get(next_id) {
        Some(st) =>
          backpressure_value_for_instance(async_state, st.callee_instance_id) ==
          0 &&
          inflight == 0
        None => true
      }
      if can_start && !task_on_stack(next_id) {
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
    if async_state.subtasks.get(next_id) is Some(st) && !task_on_stack(next_id) {
      st.phase[0] = Started
      async_state.inflight_by_instance.set(key, 1)
      // Transitioned from STARTING to STARTED: notify via event.
      let owner_component_id = st.caller_table.id
      enqueue_waitable_event(
        async_state,
        handle_key(owner_component_id, st.id),
        { owner_component_id, code: 1, index: st.id, payload: 1, },
      )
      return true
    }
  }

  // Advance one runnable STARTED subtask/background task.
  let started_ids : Array[Int64] = []
  for kv in async_state.subtasks.iter() {
    let (task_id, st0) = kv
    if st0.phase[0] == Started && !task_on_stack(task_id) {
      started_ids.push(task_id)
    }
  }
  sort_i64_by_task_order(started_ids)
  // Resume after the last task that consumed a scheduler turn. This is a
  // cooperative single-threaded ready queue: a task that repeatedly yields
  // cannot starve later tasks.
  if async_state.scheduler_cursor[0] is Some(previous) {
    let mut previous_index = -1
    for i, task_id in started_ids {
      if task_id == previous {
        previous_index = i
        break
      }
    }
    for _ in 0..<(previous_index + 1) {
      let first = started_ids.remove(0)
      started_ids.push(first)
    }
  }
  for task_id in started_ids {
    let st = match async_state.subtasks.get(task_id) {
      Some(s) => s
      None => continue
    }
    if st.phase[0] != Started {
      continue
    }
    if task_on_stack(task_id) {
      continue
    }
    push_task(async_state, task_id, true)
    let step = match st.driver {
      CallbackLifted(t) =>
        step_task_once(t, store, st.caller_table, async_state)
    }
    pop_task(async_state)
    async_state.scheduler_cursor[0] = Some(task_id)
    let releases_auto_backpressure = match st.driver {
      CallbackLifted(task) =>
        match task.func {
          HostAsync(_, _, _) => true
          Lifted(_, _, _, _, _, _, Some(_), _) => task.started[0]
          _ => false
        }
    }
    match step {
      Blocked =>
        if releases_auto_backpressure {
          async_state.inflight_by_instance.set(st.bp_key, 0)
        }
      Progressed => {
        if releases_auto_backpressure {
          async_state.inflight_by_instance.set(st.bp_key, 0)
        }
        return true
      }
      Done => {
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
          async_state.task_self_cancelled.remove(task_id)
          async_state.task_cancelled.remove(task_id)
          async_state.task_contexts.remove(task_id)
          remove_task_meta(async_state, task_id)
          async_state.yield_suspended.remove(task_id)
          async_state.waiting_ws.remove(task_id)
          async_state.sync_lower_states.remove(task_id)
          free_shared_handle(async_state, owner_component_id, st.id)
          return true
        }
        // Write subtask results into the return buffer (async-lower ABI).
        // component-spec expects the return value to be materialized in memory
        // before emitting the RETURNED event.
        let cancelled = async_state.task_self_cancelled.get(task_id)
          is Some(true)
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
                  CallbackLifted(t) =>
                    match t.func {
                      Host(func_type, types, _) => (func_type, types)
                      HostAsync(func_type, types, _) => (func_type, types)
                      Lifted(_, func_type, _, types, _, _, _, _) =>
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
                  [I32(n)] => mem.store_i32(st.retptr, n) catch { _ => () }
                  [I64(n)] => mem.store_i64(st.retptr, n) catch { _ => () }
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
        st.phase[0] = Returned
        async_state.inflight_by_instance.set(st.bp_key, 0)
        let owner_component_id = st.caller_table.id
        let payload = if cancelled {
          // CANCELLED_BEFORE_RETURNED
          4
        } else {
          // RETURNED
          2
        }
        enqueue_waitable_event(
          async_state,
          handle_key(owner_component_id, st.id),
          { owner_component_id, code: 1, index: st.id, payload, },
        )
        return true
      }
    }
  }
  false
}

///|
fn wait_for_host_event(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  match async_state.host_event_loop.val {
    Some(event_loop) =>
      if (event_loop.wait)() {
        progress_host_stream_sources(async_state, store) |> ignore
        progress_host_future_sources(async_state, store) |> ignore
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn poll_host_event(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  match async_state.host_event_loop.val {
    Some(event_loop) =>
      if (event_loop.poll)() {
        progress_host_stream_sources(async_state, store) |> ignore
        progress_host_future_sources(async_state, store) |> ignore
        true
      } else {
        false
      }
    None => false
  }
}

///|
fn progress_one_subtask(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  if progress_one_subtask_nonblocking(async_state, store) {
    true
  } else {
    wait_for_host_event(async_state, store)
  }
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
  // Host calls still need a task identity for canonical borrow scopes,
  // cancellation, and continuation ownership.
  if async_state.task_stack.length() == 1 && async_state.task_stack[0] == 0 {
    let task_id = alloc_task_id(async_state)
    // A synthetic host-entry task does not belong to a component instance and
    // therefore does not participate in async re-entrancy checks.
    init_task_meta(async_state, task_id, -1, 0L)
    // Preserve the host-provided `task_can_block` flag: exported async funcs must be allowed to block.
    let can_block = async_state.task_can_block[0]
    push_task(async_state, task_id, can_block)
    let out = {
      errdefer {
        pop_task(async_state)
        drop_task_thread(async_state, task_id)
        remove_task_meta(async_state, task_id)
      }
      call_component_func_in_task(
        func, args, store, resource_table, async_state,
      )
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
    Host(func_type, _types, host) =>
      if func_type.is_async {
        await_component_func(func, args, store, resource_table, async_state)
      } else {
        host(args, resource_table)
      }
    HostAsync(func_type, _types, _) =>
      if func_type.is_async {
        await_component_func(func, args, store, resource_table, async_state)
      } else {
        raise HostCallError("asynchronous host function has a synchronous type")
      }
    Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      entry,
      cb_opt,
      async_abi
    ) => {
      if !entry.may_enter() {
        raise CanonCallError("cannot enter component instance")
      }
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
          let (xargs, direct_borrow_lends) = transfer_args_if_needed(
            args,
            func_type,
            types,
            async_state,
            resource_table.id,
            callee_table.id,
          )
          defer release_direct_borrow_lends(direct_borrow_lends)
          let core_args = component_args_to_core(
            xargs, func_type, types, resources, store, callee_table, callee_table,
          )
          // Create a dedicated task context so `canon task.return` has somewhere to put results.
          let task_id = alloc_task_id(async_state)
          let caller_task_id = current_task_id(async_state)
          init_task_meta(async_state, task_id, callee_table.id, caller_task_id)
          push_task(async_state, task_id, false)
          take_task_result(async_state, task_id) |> ignore
          let out = {
            errdefer {
              pop_task(async_state)
              remove_task_meta(async_state, task_id)
            }
            let initial_results = drive_core_to_completion(
              async_state,
              store,
              call_core_func_guarded_outcome(
                store,
                entry,
                core_func,
                core_args,
                CallbackStep,
              ),
            )
            let mut code = match initial_results {
              [I32(value)] => value
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
                let r = {
                  errdefer {
                    async_state.in_async_callback[0] = false
                  }
                  drive_core_to_completion(
                    async_state,
                    store,
                    call_core_func_guarded_outcome(
                      store,
                      entry,
                      cb,
                      [I32(0), I32(0), I32(0)],
                      CallbackStep,
                    ),
                  )
                }
                async_state.in_async_callback[0] = false
                code = match r {
                  [I32(n)] => n
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
      let (xargs, direct_borrow_lends) = transfer_args_if_needed(
        args,
        func_type,
        types,
        async_state,
        resource_table.id,
        callee_table.id,
      )
      defer release_direct_borrow_lends(direct_borrow_lends)
      let core_args = component_args_to_core(
        xargs, func_type, types, resources, store, callee_table, callee_table,
      )
      // A sync-typed lift may still reach a suspending canonical import.
      // Instance construction conservatively propagates that fact so native
      // code is never entered when a continuation may be required.
      let previous_can_block = async_state.task_can_block[0]
      async_state.task_can_block[0] = false
      let core_results = {
        errdefer {
          async_state.task_can_block[0] = previous_can_block
        }
        if core_func.may_suspend {
          drive_core_to_completion(
            async_state,
            store,
            call_core_func_guarded_outcome(
              store,
              entry,
              core_func,
              core_args,
              Stackful,
            ),
          )
        } else {
          call_core_func_guarded(store, entry, core_func, core_args)
        }
      }
      async_state.task_can_block[0] = previous_can_block
      let task_id = current_task_id(async_state)
      let component_results = if async_abi {
        match take_task_result(async_state, task_id) {
          Some(v) => v
          None =>
            core_results_to_component(
              core_results, func_type, types, resources, store, callee_table,
            )
        }
      } else {
        core_results_to_component(
          core_results, func_type, types, resources, store, callee_table,
        )
      }
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
          ({
            errdefer {
              canon_may_leave[0] = prev
            }
            call_core_func_guarded(store, entry, pr, core_results)
          })
          |> ignore
          canon_may_leave[0] = prev
        }
        None => ()
      }
      transfer_results_if_needed(
        component_results,
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
