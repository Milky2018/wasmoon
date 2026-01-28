///|
/// Canonical section instantiation (section id 8).

///|
fn process_canon_section(
  payload : Bytes,
  state : BuildState,
  store : @runtime.Store,
  may_enter_self : Array[Bool],
) -> Unit raise ComponentRuntimeError {
  let canons = parse_canon_section(payload) catch {
    e => raise CoreModuleInstantiateError(e.to_string())
  }
  for c in canons {
    match c {
      Canon::Lift(core_func_idx, opts, type_idx) => {
        if core_func_idx < 0 || core_func_idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(core_func_idx)
        }
        if type_idx < 0 || type_idx >= state.types.length() {
          raise InvalidTypeIndex(type_idx)
        }
        let td = state.types[type_idx]
        let func_type = match td {
          Some(TypeDef::FuncType(ft)) => ft
          _ => raise InvalidCanonFuncType(type_idx)
        }
        let resources = resolve_canon_resources(opts, state)
        let callback = resolve_canon_callback(opts, state)
        // Sync-style async functions (async + no callback) use cooperative suspension.
        let async_abi = canon_opt_is_async(opts) ||
          (func_type.is_async && callback is None)
        state.funcs.push(
          ComponentFunc::Lifted(
            state.core_funcs[core_func_idx],
            func_type,
            resources,
            state.types,
            state.resource_table,
            may_enter_self,
            callback,
            async_abi,
          ),
        )
      }
      Canon::Lower(func_idx, opts) => {
        if func_idx < 0 || func_idx >= state.funcs.length() {
          raise InvalidFuncIndex(func_idx)
        }
        let func = state.funcs[func_idx]
        let (func_type, func_types) = match func {
          ComponentFunc::Host(ft, types, _) => (ft, types)
          ComponentFunc::Lifted(_, ft, _, types, _, _, _, _) => (ft, types)
        }
        let resources = resolve_canon_resources(opts, state)
        let is_async_lower = canon_opt_is_async(opts)
        if func_type_needs_memory(func_type, func_types) &&
          resources.mem_addr is None {
          raise MissingCanonMemory
        }
        let mem = match resources.mem_addr {
          Some(addr) =>
            store.get_mem(addr) catch {
              e => raise CanonCallError(e.to_string())
            }
          None => @runtime.Memory::new(0, None)
        }
        if is_async_lower {
          // Async lowering: start a subtask and return a status code, writing
          // eventual results into the provided return pointer.
          let ptr_ty = if mem.is_memory64() {
            @types.ValueType::I64
          } else {
            @types.ValueType::I32
          }
          let flat_params : Array[@types.ValueType] = []
          for p in func_type.params {
            for t in core_types_for_valtype(p.ty, func_types, mem.is_memory64()) {
              flat_params.push(t)
            }
          }
          let params : Array[@types.ValueType] = match func_type.result {
            Some(_) => flat_params + [ptr_ty]
            None => flat_params
          }
          let core_type : @types.FuncType = {
            params,
            results: [@types.ValueType::I32],
          }
          let async_state = state.async_state
          let caller_table = state.resource_table
          let host = fn(
            args : Array[@types.Value],
          ) -> Array[@types.Value] raise @runtime.RuntimeError {
            if !canon_may_leave[0] {
              trap_canon("cannot leave component instance")
            }
            match func {
              ComponentFunc::Lifted(_, _, _, _, _, may_enter, _, _) =>
                if !may_enter[0] {
                  trap_canon("wasm trap: cannot enter component instance")
                }
              _ => ()
            }
            let cur_task_id = current_task_id(async_state)
            let cur = if async_state.call_cursor_stack.length() == 0 {
              0
            } else {
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1]
            }
            let per_task = match async_state.call_results.get(cur_task_id) {
              Some(m) => m
              None => {
                let m : Map[Int, Array[@types.Value]] = {}
                async_state.call_results.set(cur_task_id, m)
                m
              }
            }
            fn cache_and_advance(
              out : Array[@types.Value],
            ) -> Array[@types.Value] {
              per_task.set(cur, out)
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              out
            }

            match per_task.get(cur) {
              Some(v) => {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1] = cur + 1
                return v
              }
              None => ()
            }

            // Split core args into component params and optional return pointer.
            let mut retptr : Int? = None
            let param_args : Array[@types.Value] = []
            match func_type.result {
              Some(_) => {
                if args.length() == 0 {
                  trap_canon("missing retptr")
                  return cache_and_advance([@types.Value::I32(0)])
                }
                for i in 0..<(args.length() - 1) {
                  param_args.push(args[i])
                }
                retptr = match args[args.length() - 1] {
                  @types.Value::I32(n) => Some(n)
                  @types.Value::I64(n) => Some(n.to_int())
                  _ => None
                }
              }
              None =>
                for a in args {
                  param_args.push(a)
                }
            }
            let component_args = core_args_to_component(
              param_args, func_type, func_types, resources, store, caller_table,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return cache_and_advance([@types.Value::I32(0)])
              }
            }
            let inst_id = match func {
              ComponentFunc::Host(_, _, _) => caller_table.id
              ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
                callee_table.id
            }
            // Backpressure is per async-lowered core function (not per component instance).
            let bp_key = ((caller_table.id.reinterpret_as_uint() * 65537U) ^
            func_idx.reinterpret_as_uint()).reinterpret_as_int()
            let inflight = match async_state.inflight_by_instance.get(bp_key) {
              Some(n) => n
              None => 0
            }
            let task : CallbackTask = {
              func,
              args: component_args,
              started: [false],
              code: [0],
              waiting_set: [None],
              cancelled: [false],
            }
            let retp = match retptr {
              Some(p) => p
              None => 0
            }
            fn cleanup_task_id(task_id : Int) -> Unit {
              async_state.task_results.remove(task_id)
              async_state.task_returned.remove(task_id)
              async_state.task_cancelled.remove(task_id)
              async_state.task_contexts.remove(task_id)
              async_state.yield_replay_upto.remove(task_id)
              async_state.wait_results.remove(task_id)
              async_state.waiting_ws.remove(task_id)
              async_state.call_results.remove(task_id)
              async_state.sync_lower_states.remove(task_id)
            }

            fn migrate_task_id(from_id : Int, to_id : Int) -> Unit {
              match take_task_result(async_state, from_id) {
                Some(v) => set_task_result(async_state, to_id, v)
                None => ()
              }
              match async_state.task_returned.get(from_id) {
                Some(v) => {
                  async_state.task_returned.remove(from_id)
                  async_state.task_returned.set(to_id, v)
                }
                None => ()
              }
              match async_state.task_cancelled.get(from_id) {
                Some(v) => {
                  async_state.task_cancelled.remove(from_id)
                  async_state.task_cancelled.set(to_id, v)
                }
                None => ()
              }
              match async_state.task_contexts.get(from_id) {
                Some(v) => {
                  async_state.task_contexts.remove(from_id)
                  async_state.task_contexts.set(to_id, v)
                }
                None => ()
              }
              match async_state.yield_replay_upto.get(from_id) {
                Some(v) => {
                  async_state.yield_replay_upto.remove(from_id)
                  async_state.yield_replay_upto.set(to_id, v)
                }
                None => ()
              }
              match async_state.wait_results.get(from_id) {
                Some(v) => {
                  async_state.wait_results.remove(from_id)
                  async_state.wait_results.set(to_id, v)
                }
                None => ()
              }
              match async_state.waiting_ws.get(from_id) {
                Some(v) => {
                  async_state.waiting_ws.remove(from_id)
                  async_state.waiting_ws.set(to_id, v)
                }
                None => ()
              }
              match async_state.call_results.get(from_id) {
                Some(v) => {
                  async_state.call_results.remove(from_id)
                  async_state.call_results.set(to_id, v)
                }
                None => ()
              }
              match async_state.sync_lower_states.get(from_id) {
                Some(v) => {
                  async_state.sync_lower_states.remove(from_id)
                  async_state.sync_lower_states.set(to_id, v)
                }
                None => ()
              }
            }

            if inflight == 0 {
              let is_callback = match func {
                ComponentFunc::Lifted(
                  _,
                  _ft,
                  _res,
                  _tys,
                  _tbl,
                  _may_enter,
                  Some(_cb),
                  _async_abi
                ) => true
                _ => false
              }
              if is_callback {
                // Try a handle-less initial step. If it exits immediately, we must return
                // RETURNED=2 without consuming the shared handle space (otherwise it would
                // perturb handle numbering observed by the core code; see empty-wait.wast).
                let tmp_task_id = alloc_task_id(async_state)
                let mut ok = true
                canon_in_handleless_step[0] = true
                push_task(async_state, tmp_task_id, true)
                let step = step_task_once(
                  task, store, caller_table, async_state,
                ) catch {
                  _e => {
                    ok = false
                    // Reset state so the real subtask can start fresh.
                    task.started[0] = false
                    task.code[0] = 0
                    task.waiting_set[0] = None
                    TaskStep::Blocked
                  }
                }
                pop_task(async_state)
                canon_in_handleless_step[0] = false
                if ok && step == TaskStep::Done {
                  if func_type.result is Some(_) && retptr is Some(p) {
                    let vals = match
                      take_task_result(async_state, tmp_task_id) {
                      Some(v) => v
                      None => []
                    }
                    let core_vals = component_results_to_core(
                      vals,
                      func_type,
                      func_types,
                      resources,
                      store,
                      Some(p),
                    ) catch {
                      e => {
                        trap_canon(canon_err_message(e))
                        return cache_and_advance([@types.Value::I32(0)])
                      }
                    }
                    match core_vals {
                      [@types.Value::I32(n)] =>
                        mem.store_i32(p, n) catch {
                          _ => ()
                        }
                      [@types.Value::I64(n)] =>
                        mem.store_i64(p, n) catch {
                          _ => ()
                        }
                      _ => ()
                    }
                  }
                  cleanup_task_id(tmp_task_id)
                  return cache_and_advance([@types.Value::I32(2)]) // RETURNED
                }

                // Needs a real subtask handle: allocate and migrate the per-task state.
                let sub_id = alloc_shared_handle(async_state)
                migrate_task_id(tmp_task_id, sub_id)
                cleanup_task_id(tmp_task_id)
                let st : Subtask = {
                  id: sub_id,
                  detached: false,
                  phase: [SubtaskPhase::Started],
                  caller_table,
                  callee_instance_id: inst_id,
                  bp_key,
                  retptr: retp,
                  mem_addr: resources.mem_addr,
                  result_ty: func_type.result,
                  types: func_types,
                  resources,
                  driver: SubtaskDriver::CallbackLifted(task),
                }
                async_state.inflight_by_instance.set(bp_key, 1)
                async_state.subtasks.set(sub_id, st)
                return cache_and_advance([@types.Value::I32((sub_id << 4) | 1)]) // STARTED
              }

              // Non-callback async lowering: do a handle-less initial step so the task can
              // register any pending waits (e.g. future.read/stream.read) before returning STARTED.
              // If it completes immediately, return RETURNED=2 without consuming the shared handle space.
              let tmp_task_id = alloc_task_id(async_state)
              let mut ok = true
              canon_in_handleless_step[0] = true
              push_task(async_state, tmp_task_id, true)
              let step = step_task_once(task, store, caller_table, async_state) catch {
                _e => {
                  ok = false
                  task.started[0] = false
                  task.code[0] = 0
                  task.waiting_set[0] = None
                  TaskStep::Blocked
                }
              }
              pop_task(async_state)
              canon_in_handleless_step[0] = false
              if ok && step == TaskStep::Done {
                if func_type.result is Some(_) && retptr is Some(p) {
                  let vals = match take_task_result(async_state, tmp_task_id) {
                    Some(v) => v
                    None => []
                  }
                  let core_vals = component_results_to_core(
                    vals,
                    func_type,
                    func_types,
                    resources,
                    store,
                    Some(p),
                  ) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      return cache_and_advance([@types.Value::I32(0)])
                    }
                  }
                  match core_vals {
                    [@types.Value::I32(n)] =>
                      mem.store_i32(p, n) catch {
                        _ => ()
                      }
                    [@types.Value::I64(n)] =>
                      mem.store_i64(p, n) catch {
                        _ => ()
                      }
                    _ => ()
                  }
                }
                cleanup_task_id(tmp_task_id)
                return cache_and_advance([@types.Value::I32(2)]) // RETURNED
              }
              let sub_id = alloc_shared_handle(async_state)
              migrate_task_id(tmp_task_id, sub_id)
              cleanup_task_id(tmp_task_id)
              let st : Subtask = {
                id: sub_id,
                detached: false,
                phase: [SubtaskPhase::Started],
                caller_table,
                callee_instance_id: inst_id,
                bp_key,
                retptr: retp,
                mem_addr: resources.mem_addr,
                result_ty: func_type.result,
                types: func_types,
                resources,
                driver: SubtaskDriver::CallbackLifted(task),
              }
              async_state.inflight_by_instance.set(bp_key, 1)
              async_state.subtasks.set(sub_id, st)
              cache_and_advance([@types.Value::I32((sub_id << 4) | 1)]) // STARTED
            } else {
              // Backpressure: queue in STARTING state until the in-flight
              // subtask for this async-lowered core function completes.
              let sub_id = alloc_shared_handle(async_state)
              let st : Subtask = {
                id: sub_id,
                detached: false,
                phase: [SubtaskPhase::Starting],
                caller_table,
                callee_instance_id: inst_id,
                bp_key,
                retptr: retp,
                mem_addr: resources.mem_addr,
                result_ty: func_type.result,
                types: func_types,
                resources,
                driver: SubtaskDriver::CallbackLifted(task),
              }
              async_state.subtasks.set(sub_id, st)
              let q = match async_state.pending_by_instance.get(bp_key) {
                Some(xs) => xs
                None => []
              }
              q.push(sub_id)
              async_state.pending_by_instance.set(bp_key, q)
              cache_and_advance([@types.Value::I32((sub_id << 4) | 0)]) // STARTING
            }
          }
          state.core_funcs.push(alloc_host_core_func(store, core_type, host))
        } else {
          let core_type = core_func_type_from_component(
            func_type,
            func_types,
            mem.is_memory64(),
          )
          let host = fn(
            args : Array[@types.Value],
          ) -> Array[@types.Value] raise @runtime.RuntimeError {
            match func {
              ComponentFunc::Lifted(_, _, _, _, _, may_enter, _, _) =>
                if !may_enter[0] {
                  trap_canon("wasm trap: cannot enter component instance")
                }
              _ => ()
            }
            if !canon_may_leave[0] {
              trap_canon("cannot leave component instance")
            }
            let component_args = core_args_to_component(
              args,
              func_type,
              func_types,
              resources,
              store,
              state.resource_table,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                ([] : Array[ComponentValue])
              }
            }
            let async_state = state.async_state
            fn cleanup_sync_lower_task(task_id : Int) -> Unit {
              async_state.task_results.remove(task_id)
              async_state.task_returned.remove(task_id)
              async_state.task_cancelled.remove(task_id)
              async_state.task_contexts.remove(task_id)
              async_state.yield_replay_upto.remove(task_id)
              async_state.wait_results.remove(task_id)
              async_state.waiting_ws.remove(task_id)
              async_state.call_results.remove(task_id)
              async_state.sync_lower_states.remove(task_id)
              // Sync-lowering of async component functions uses a shared-handle
              // task id (to match component-spec handle numbering). Free it once
              // the call finishes or aborts.
              if task_id > 0 {
                free_shared_handle(async_state, task_id)
              }
            }

            let results : Array[ComponentValue] = if func_type.is_async {
              // Sync-lowering an async component function must be cooperative:
              // treat YIELD/WAIT as restartable suspension points instead of busy looping.
              let outer_task_id = current_task_id(async_state)
              let cur = if async_state.call_cursor_stack.length() == 0 {
                0
              } else {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1]
              }
              let per_task_calls = match
                async_state.call_results.get(outer_task_id) {
                Some(m) => m
                None => {
                  let m : Map[Int, Array[@types.Value]] = {}
                  async_state.call_results.set(outer_task_id, m)
                  m
                }
              }
              match per_task_calls.get(cur) {
                Some(v) => {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = cur + 1
                  return v
                }
                None => ()
              }
              let per_task_state = match
                async_state.sync_lower_states.get(outer_task_id) {
                Some(m) => m
                None => {
                  let m : Map[Int, SyncLowerState] = {}
                  async_state.sync_lower_states.set(outer_task_id, m)
                  m
                }
              }
              let st = match per_task_state.get(cur) {
                Some(s) => s
                None => {
                  // The task id is observable via stream/future handle numbering in
                  // component-spec/async (e.g. cancel-stream.wast), so allocate from
                  // the shared handle space. However, while the outer async-lowered
                  // wrapper is doing a handle-less initial step, avoid consuming the
                  // shared handle space so that subtask id allocation remains stable
                  // (async-calls-sync.wast).
                  let inner_task_id = if canon_in_handleless_step[0] {
                    alloc_task_id(async_state)
                  } else {
                    alloc_shared_handle(async_state)
                  }
                  let task : CallbackTask = {
                    func,
                    args: component_args,
                    started: [false],
                    code: [0],
                    waiting_set: [None],
                    cancelled: [false],
                  }
                  let s : SyncLowerState = { task_id: inner_task_id, task }
                  per_task_state.set(cur, s)
                  s
                }
              }

              // Drive at most one step, then cooperatively suspend.
              let can_block = async_state.task_can_block[0]
              if !can_block && !canon_in_prerun[0] {
                trap_canon("cannot block a synchronous task before returning")
                ([] : Array[ComponentValue])
              } else {
                push_task(async_state, st.task_id, can_block)
                let step = step_task_once(
                  st.task,
                  store,
                  state.resource_table,
                  async_state,
                ) catch {
                  e => {
                    pop_task(async_state)
                    trap_canon(canon_err_message(e))
                    return []
                  }
                }
                pop_task(async_state)
                let is_callback_task = match st.task.func {
                  ComponentFunc::Lifted(
                    _,
                    _ft,
                    _res,
                    _tys,
                    _tbl,
                    _may_enter,
                    Some(_cb),
                    _async_abi
                  ) => true
                  _ => false
                }
                // Some callback-style async functions (notably stream producers) publish their
                // results via `canon task.return` and then continue running to drive the stream.
                // Sync-lowering must return the published result immediately and keep the task
                // alive as a detached background subtask, otherwise nested components can deadlock
                // (component-spec/async/zero-length.wast).
                if is_callback_task &&
                  step != TaskStep::Done &&
                  func_type.result is Some(_) &&
                  async_state.task_returned.get(st.task_id) is Some(true) {
                  match async_state.task_results.get(st.task_id) {
                    Some(vals) => {
                      // Promote the task to a detached background subtask so the event loop can
                      // continue driving it after this sync-lowered call returns.
                      let callee_instance_id = match st.task.func {
                        ComponentFunc::Host(_, _, _) => state.resource_table.id
                        ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
                          callee_table.id
                      }
                      async_state.subtasks.set(st.task_id, {
                        id: st.task_id,
                        detached: true,
                        phase: [SubtaskPhase::Started],
                        caller_table: state.resource_table,
                        callee_instance_id,
                        bp_key: st.task_id,
                        retptr: 0,
                        mem_addr: resources.mem_addr,
                        result_ty: None,
                        types: func_types,
                        resources,
                        driver: SubtaskDriver::CallbackLifted(st.task),
                      })
                      per_task_state.remove(cur) |> ignore

                      // Cache and advance call cursor (replay-safe).
                      let mut out_ptr : Int? = None
                      match func_type.result {
                        Some(rty) => {
                          let flat = core_types_for_valtype(
                            rty,
                            func_types,
                            mem.is_memory64(),
                          ) catch {
                            _ => []
                          }
                          if flat.length() > 1 {
                            if args.length() == 0 {
                              trap_canon("missing retptr")
                            } else {
                              out_ptr = match args[args.length() - 1] {
                                @types.Value::I32(n) => Some(n)
                                @types.Value::I64(n) => Some(n.to_int())
                                _ => None
                              }
                            }
                          }
                        }
                        None => ()
                      }
                      let out = component_results_to_core(
                        vals, func_type, func_types, resources, store, out_ptr,
                      ) catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          ([] : Array[@types.Value])
                        }
                      }
                      per_task_calls.set(cur, out)
                      async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                      1] = cur + 1
                      return out
                    }
                    None => ()
                  }
                }
                match step {
                  TaskStep::Done => {
                    per_task_state.remove(cur) |> ignore
                    let vals = match take_task_result(async_state, st.task_id) {
                      Some(v) => v
                      None => []
                    }
                    cleanup_sync_lower_task(st.task_id)
                    // Cache and advance call cursor (replay-safe).
                    let mut out_ptr : Int? = None
                    match func_type.result {
                      Some(rty) => {
                        let flat = core_types_for_valtype(
                          rty,
                          func_types,
                          mem.is_memory64(),
                        ) catch {
                          _ => []
                        }
                        if flat.length() > 1 {
                          // Indirect results use the last core argument as retptr.
                          if args.length() == 0 {
                            trap_canon("missing retptr")
                          } else {
                            out_ptr = match args[args.length() - 1] {
                              @types.Value::I32(n) => Some(n)
                              @types.Value::I64(n) => Some(n.to_int())
                              _ => None
                            }
                          }
                        }
                      }
                      None => ()
                    }
                    let out = component_results_to_core(
                      vals, func_type, func_types, resources, store, out_ptr,
                    ) catch {
                      e => {
                        trap_canon(canon_err_message(e))
                        ([] : Array[@types.Value])
                      }
                    }
                    per_task_calls.set(cur, out)
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    return out
                  }
                  _ =>
                    if canon_in_prerun[0] {
                      per_task_state.remove(cur) |> ignore
                      cleanup_sync_lower_task(st.task_id)
                      trap_canon("prerun blocked")
                      ([] : Array[ComponentValue])
                    } else {
                      match st.task.waiting_set[0] {
                        Some(ws) =>
                          canon_suspend[0] = Some(CanonSuspend::Wait(ws))
                        None => canon_suspend[0] = Some(CanonSuspend::Yield)
                      }
                      raise @runtime.RuntimeError::Unreachable
                    }
                }
              }
            } else {
              call_component_func(
                func,
                component_args,
                store,
                state.resource_table,
                state.async_state,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  ([] : Array[ComponentValue])
                }
              }
            }
            let mut out_ptr : Int? = None
            match func_type.result {
              Some(rty) => {
                let flat = core_types_for_valtype(
                  rty,
                  func_types,
                  mem.is_memory64(),
                ) catch {
                  _ => []
                }
                if flat.length() > 1 {
                  // Indirect results use the last core argument as retptr.
                  if args.length() == 0 {
                    trap_canon("missing retptr")
                  } else {
                    out_ptr = match args[args.length() - 1] {
                      @types.Value::I32(n) => Some(n)
                      @types.Value::I64(n) => Some(n.to_int())
                      _ => None
                    }
                  }
                }
              }
              None => ()
            }
            component_results_to_core(
              results, func_type, func_types, resources, store, out_ptr,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                ([] : Array[@types.Value])
              }
            }
          }
          let func_addr = store.alloc_host_func(
            host,
            func_type=core_type,
            type_idx=0,
          )
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
          state.core_funcs.push({ instance, func_idx: 0 })
        }
      }
      Canon::ResourceNew(tyidx) => {
        if tyidx < 0 || tyidx >= state.types.length() {
          raise InvalidTypeIndex(tyidx)
        }
        let (type_id, kind, dtor) = match state.types[tyidx] {
          Some(TypeDef::ResourceType(id, rep, dtor_idx, kind)) => {
            if rep != 0x7f {
              raise UnsupportedComponent(
                "resources can only be represented by `i32`",
              )
            }
            let dtor_ref = match dtor_idx {
              Some(idx) =>
                if idx < 0 || idx >= state.core_funcs.length() {
                  raise InvalidCoreFuncIndex(idx)
                } else {
                  Some(state.core_funcs[idx])
                }
              None => None
            }
            (id, kind, dtor_ref)
          }
          _ => raise InvalidTypeDef(tyidx)
        }
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let table = state.resource_table
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          match args {
            [@types.Value::I32(rep)] => {
              let handle = table.alloc({ type_id, rep, dtor, kind })
              [@types.Value::I32(handle)]
            }
            _ => {
              trap_canon("type mismatch")
              []
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ResourceRep(tyidx) => {
        if tyidx < 0 || tyidx >= state.types.length() {
          raise InvalidTypeIndex(tyidx)
        }
        let (type_id, expected_kind) = match state.types[tyidx] {
          Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
          _ => raise InvalidTypeDef(tyidx)
        }
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let table = state.resource_table
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.get(handle) {
                Some(entry) =>
                  if entry.type_id < 0 {
                    trap_canon(
                      "unknown handle index \{handle}; index \{handle} is not a resource",
                    )
                    []
                  } else if entry.type_id != type_id {
                    let expected_desc = if expected_kind ==
                      ResourceKind::GuestDefined {
                      "guest-defined resource"
                    } else {
                      "host-defined resource"
                    }
                    let found_desc = if entry.kind == ResourceKind::GuestDefined {
                      "guest-defined resource"
                    } else {
                      "host-defined resource"
                    }
                    let suffix = if entry.kind == expected_kind {
                      "a different \{found_desc}"
                    } else {
                      found_desc
                    }
                    trap_canon(
                      "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
                    )
                    []
                  } else {
                    [@types.Value::I32(entry.rep)]
                  }
                None => {
                  trap_canon(
                    "unknown handle index \{handle}; index \{handle} is not a resource",
                  )
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
      Canon::ResourceDrop(tyidx) => {
        if tyidx < 0 || tyidx >= state.types.length() {
          raise InvalidTypeIndex(tyidx)
        }
        let (type_id, expected_kind) = match state.types[tyidx] {
          Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
          _ => raise InvalidTypeDef(tyidx)
        }
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [],
        }
        let table = state.resource_table
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.get(handle) {
                Some(entry) =>
                  if entry.type_id < 0 {
                    trap_canon(
                      "unknown handle index \{handle}; index \{handle} is not a resource",
                    )
                    []
                  } else if entry.type_id != type_id {
                    let expected_desc = if expected_kind ==
                      ResourceKind::GuestDefined {
                      "guest-defined resource"
                    } else {
                      "host-defined resource"
                    }
                    let found_desc = if entry.kind == ResourceKind::GuestDefined {
                      "guest-defined resource"
                    } else {
                      "host-defined resource"
                    }
                    let suffix = if entry.kind == expected_kind {
                      "a different \{found_desc}"
                    } else {
                      found_desc
                    }
                    trap_canon(
                      "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
                    )
                    []
                  } else {
                    let taken = table.free(handle)
                    match taken {
                      Some(real) =>
                        match real.dtor {
                          Some(d) => {
                            clear_canon_trap_message()
                            (@executor.call_func_by_index(
                              store,
                              d.instance,
                              d.func_idx,
                              [@types.Value::I32(real.rep)],
                            ) catch {
                              e => {
                                trap_canon(e.to_string())
                                []
                              }
                            })
                            |> ignore
                          }
                          None => ()
                        }
                      None => ()
                    }
                    []
                  }
                None => {
                  trap_canon(
                    "unknown handle index \{handle}; index \{handle} is not a resource",
                  )
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
      Canon::TaskReturn(result, opts) => {
        let resources = resolve_canon_resources(opts, state)
        let core_params : Array[@types.ValueType] = match result {
          Some(vt) =>
            core_types_for_valtype(vt, state.types, false) catch {
              _ => []
            }
          None => []
        }
        let core_type : @types.FuncType = { params: core_params, results: [] }
        let async_state = state.async_state
        let types = state.types
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          // `canon task.return` can be executed multiple times if the surrounding
          // core function is cooperatively replayed after a suspension (e.g. a
          // sync stream.read/write inside a callback-style async task).
          // Treat re-execution as idempotent as long as it returns the same value.
          match async_state.task_returned.get(task_id) {
            Some(_) =>
              match result {
                None => return []
                Some(vt) => {
                  let mem : @runtime.Memory? = match resources.mem_addr {
                    Some(addr) =>
                      Some(
                        store.get_mem(addr) catch {
                          e => {
                            trap_canon(e.to_string())
                            return []
                          }
                        },
                      )
                    None => None
                  }
                  let mem_is_64 = match mem {
                    Some(m) => m.is_memory64()
                    None => false
                  }
                  let v = lift_component_value_from_flat(
                    vt,
                    args,
                    types,
                    mem,
                    mem_is_64,
                    resources.encoding,
                  ) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      return []
                    }
                  }
                  validate_lifted_stream_future(vt, v, types, async_state) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      return []
                    }
                  }
                  match async_state.task_results.get(task_id) {
                    Some(prev) =>
                      if prev.length() == 1 && prev[0] == v {
                        return []
                      } else {
                        trap_canon("task.return called more than once")
                        return []
                      }
                    None => return []
                  }
                }
              }
            None => ()
          }
          async_state.task_returned.set(task_id, true)
          let vals : Array[ComponentValue] = match result {
            None => []
            Some(vt) => {
              let mem : @runtime.Memory? = match resources.mem_addr {
                Some(addr) =>
                  Some(
                    store.get_mem(addr) catch {
                      e => {
                        trap_canon(e.to_string())
                        return []
                      }
                    },
                  )
                None => None
              }
              let mem_is_64 = match mem {
                Some(m) => m.is_memory64()
                None => false
              }
              let v = lift_component_value_from_flat(
                vt,
                args,
                types,
                mem,
                mem_is_64,
                resources.encoding,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return []
                }
              }
              // `canon task.return` lifts core values into the component result; apply the
              // same stream/future handle validation as `canon lift`.
              validate_lifted_stream_future(vt, v, types, async_state) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return []
                }
              }
              [v]
            }
          }
          set_task_result(async_state, task_id, vals)
          []
        }
        // Stash as a core func.
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::TaskCancel => {
        let core_type : @types.FuncType = { params: [], results: [] }
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          async_state.task_cancelled.set(task_id, true)
          async_state.task_returned.set(task_id, true)
          set_task_result(async_state, task_id, [])
          []
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadIndex => {
        let core_type : @types.FuncType = {
          params: [],
          results: [@types.ValueType::I32],
        }
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          [@types.Value::I32(0)]
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadYield(_cancellable) => {
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
          // In a synchronous task, `thread.yield` is just a normal call that
          // returns a conventional code (it must not block by itself).
          if !async_state.task_can_block[0] {
            return [@types.Value::I32(1)]
          }
          let task_id = current_task_id(async_state)
          // Restartable yield points: only suspend once per ordinal.
          let cur = if async_state.yield_cursor_stack.length() == 0 {
            0
          } else {
            async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
            1]
          }
          let replay_upto = match async_state.yield_replay_upto.get(task_id) {
            Some(n) => n
            None => 0
          }
          if cur < replay_upto {
            async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
            1] = cur + 1
            // On replay, thread.yield returns 0.
            return [@types.Value::I32(0)]
          }
          async_state.yield_replay_upto.set(task_id, replay_upto + 1)
          canon_suspend[0] = Some(CanonSuspend::Yield)
          raise @runtime.RuntimeError::Unreachable
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadYieldTo(_cancellable) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          // For now, model yield-to as a regular yield.
          if !async_state.task_can_block[0] {
            return [@types.Value::I32(1)]
          }
          canon_suspend[0] = Some(CanonSuspend::Yield)
          raise @runtime.RuntimeError::Unreachable
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadSwitchTo(_cancellable) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          // For now, switching is treated as yielding.
          if !async_state.task_can_block[0] {
            return [@types.Value::I32(1)]
          }
          canon_suspend[0] = Some(CanonSuspend::Yield)
          raise @runtime.RuntimeError::Unreachable
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadResumeLater => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [],
        }
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          []
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadSuspend(_cancellable) => {
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
          if !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return [@types.Value::I32(0)]
          }
          canon_suspend[0] = Some(CanonSuspend::Yield)
          raise @runtime.RuntimeError::Unreachable
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ThreadNewIndirect(_type_idx, _table_idx) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32, @types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let id = alloc_shared_handle(async_state)
          [@types.Value::I32(id)]
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::WaitableSetNew => {
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
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              out
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::WaitableSetWait(_cancellable, memidx) => {
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
                            ComponentFunc::Lifted(
                              _,
                              func_type,
                              _,
                              types,
                              _,
                              _,
                              _,
                              _
                            ) => (func_type, types)
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
      Canon::WaitableSetPoll(_cancellable, memidx) => {
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
      Canon::WaitableSetDrop => {
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
      Canon::WaitableJoin => {
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
      Canon::SubtaskCancel(is_async_cancel) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_i32(n : Int) -> Array[@types.Value] {
            let out = [@types.Value::I32(n)]
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }

          if !is_async_cancel && !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return cache_i32(0)
          }
          match args {
            [@types.Value::I32(id)] =>
              match async_state.subtasks.get(id) {
                None => {
                  trap_canon("unknown subtask handle index \{id}")
                  cache_i32(0)
                }
                Some(st) => {
                  if st.phase[0] == SubtaskPhase::Returned {
                    // Already resolved.
                    return cache_i32(0)
                  }

                  // Mark cancellation request for callback-driven tasks.
                  match st.driver {
                    SubtaskDriver::CallbackLifted(t) => t.cancelled[0] = true
                    _ => ()
                  }

                  // Best-effort: if the subtask uses the callback-style async ABI,
                  // attempt to deliver the cancellation immediately.
                  let is_callback = match st.driver {
                    SubtaskDriver::CallbackLifted(t) =>
                      match t.func {
                        ComponentFunc::Lifted(
                          _,
                          _ft,
                          _res,
                          _tys,
                          _tbl,
                          _may_enter,
                          Some(_cb),
                          _async_abi
                        ) => true
                        _ => false
                      }
                    _ => false
                  }
                  if is_callback {
                    match st.driver {
                      SubtaskDriver::CallbackLifted(t) => {
                        push_task(async_state, id, true)
                        let step = step_task_once(
                          t,
                          store,
                          st.caller_table,
                          async_state,
                        ) catch {
                          e => {
                            pop_task(async_state)
                            trap_canon(canon_err_message(e))
                            return cache_i32(0)
                          }
                        }
                        pop_task(async_state)
                        match step {
                          TaskStep::Done => {
                            st.phase[0] = SubtaskPhase::Returned
                            async_state.inflight_by_instance.set(st.bp_key, 0)
                            enqueue_waitable_event(async_state, id, {
                              code: 1,
                              index: id,
                              payload: 2,
                            })
                            // CANCELLED_BEFORE_RETURNED=4 (component-spec convention).
                            return cache_i32(4)
                          }
                          _ => ()
                        }
                      }
                      _ => ()
                    }
                  }

                  // BLOCKED=-1 (cancellation didn't complete synchronously).
                  cache_i32(-1)
                }
              }
            _ => {
              trap_canon("type mismatch")
              cache_i32(0)
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::SubtaskDrop => {
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
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_void() -> Array[@types.Value] {
            let out : Array[@types.Value] = []
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }

          match args {
            [@types.Value::I32(id)] => {
              // Ensure this is a known subtask and it has completed.
              let st_opt = async_state.subtasks.get(id)
              match st_opt {
                Some(st) =>
                  if st.phase[0] != SubtaskPhase::Returned {
                    trap_canon(
                      "cannot drop a subtask which has not yet resolved",
                    )
                    return cache_void()
                  } else {
                    async_state.subtasks.remove(id)
                  }
                None => {
                  trap_canon("unknown subtask handle index \{id}")
                  return cache_void()
                }
              }

              // Remove from any waitable-set membership and queued events.
              match async_state.waitable_to_set.get(id) {
                Some(ws) => {
                  async_state.waitable_to_set.remove(id)
                  match async_state.waitable_sets.get(ws) {
                    Some(set) => {
                      set.members.remove(id)
                      // Purge queued events for this waitable.
                      let mut i = 0
                      while i < set.queue.length() {
                        if set.queue[i].index == id {
                          set.queue.remove(i) |> ignore
                        } else {
                          i = i + 1
                        }
                      }
                    }
                    None => ()
                  }
                }
                None => ()
              }
              async_state.waitable_events.remove(id)

              // Clear per-task bookkeeping so the handle id can be reused.
              async_state.task_results.remove(id)
              async_state.task_returned.remove(id)
              async_state.task_cancelled.remove(id)
              async_state.task_contexts.remove(id)
              async_state.yield_replay_upto.remove(id)
              async_state.wait_results.remove(id)
              async_state.waiting_ws.remove(id)
              async_state.call_results.remove(id)
              async_state.sync_lower_states.remove(id)

              // Remove from pending queues if it was still STARTING.
              let inst_ids : Array[Int] = []
              for kv in async_state.pending_by_instance.iter() {
                let (inst_id, _q) = kv
                inst_ids.push(inst_id)
              }
              for inst_id in inst_ids {
                match async_state.pending_by_instance.get(inst_id) {
                  Some(q) => {
                    let mut j = 0
                    while j < q.length() {
                      if q[j] == id {
                        q.remove(j) |> ignore
                      } else {
                        j = j + 1
                      }
                    }
                    if q.length() == 0 {
                      async_state.pending_by_instance.remove(inst_id)
                    }
                  }
                  None => ()
                }
              }
              free_shared_handle(async_state, id)
              cache_void()
            }
            _ => {
              trap_canon("type mismatch")
              cache_void()
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::StreamNew(_tyidx) => {
        let core_type : @types.FuncType = {
          params: [],
          results: [@types.ValueType::I64],
        }
        let payload_ty : ValType? = match state.types.get(_tyidx) {
          Some(Some(TypeDef::Stream(v))) => v
          _ => None
        }
        let (elem_size, own_resource_type_id) = stream_payload_info(
          payload_ty,
          state.types,
        ) catch {
          e => raise e
        }
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }

          // Replay-safe: `canon stream.new` can be executed multiple times if the
          // surrounding core function is restarted after a cooperative suspension.
          // Cache the i64 result per task/call cursor so handle numbering remains stable.
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_i64(x : Int64) -> Array[@types.Value] {
            let out = [@types.Value::I64(x)]
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }

          let sid = table.next_stream_id[0]
          table.next_stream_id[0] = sid + 1
          table.streams.set(sid, {
            elem_size,
            own_resource_type_id,
            pending_read: None,
            pending_write: None,
            readable_dropped: false,
            writable_dropped: false,
          })
          // Handle numbering is observable by component-spec/async tests.
          // Allocate in order: readable first, then writable. The shared
          // allocator already deterministically reuses the smallest freed
          // handle (when available), which is the behavior tests rely on.
          let rh = alloc_shared_handle(async_state)
          let wh = alloc_shared_handle(async_state)
          table.endpoints.set(rh, {
            stream_id: sid,
            is_readable: true,
            notified_peer_dropped: [false],
          })
          table.endpoints.set(wh, {
            stream_id: sid,
            is_readable: false,
            notified_peer_dropped: [false],
          })
          let packed = (wh.to_int64() << 32) | (rh.to_int64() & 0xFFFFFFFFL)
          cache_i64(packed)
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::StreamRead(_tyidx, opts) => {
        let core_type : @types.FuncType = {
          params: [
            @types.ValueType::I32,
            @types.ValueType::I32,
            @types.ValueType::I32,
          ],
          results: [@types.ValueType::I32],
        }
        let resources = resolve_canon_resources(opts, state) catch {
          e => raise e
        }
        let payload_ty : ValType? = match state.types.get(_tyidx) {
          Some(Some(TypeDef::Stream(v))) => v
          _ => None
        }
        let is_async = canon_opt_is_async(opts)
        let reader_table = state.resource_table
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let mem_opt : @runtime.Memory? = match payload_ty {
            Some(_) =>
              match resources.mem_addr {
                Some(addr) =>
                  Some(
                    store.get_mem(addr) catch {
                      e => {
                        trap_canon(e.to_string())
                        return [@types.Value::I32(0)]
                      }
                    },
                  )
                None => {
                  trap_canon("missing canon memory")
                  return [@types.Value::I32(0)]
                }
              }
            None => None
          }
          match args {
            [
              @types.Value::I32(handle),
              @types.Value::I32(ptr),
              @types.Value::I32(len),
            ] => {
              if !is_async && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
                return [@types.Value::I32(0)]
              }
              // BLOCKED=-1, COMPLETED=0 | (n<<4), DROPPED=1 | (n<<4)
              if len < 0 {
                trap_canon("type mismatch")
                [@types.Value::I32(0)]
              } else {
                match table.endpoints.get(handle) {
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    [@types.Value::I32(0)]
                  }
                  Some(ep) =>
                    if !ep.is_readable {
                      trap_canon("type mismatch")
                      [@types.Value::I32(0)]
                    } else {
                      if ep.notified_peer_dropped[0] {
                        trap_canon(
                          "cannot read from stream after being notified that the writable end dropped",
                        )
                        return [@types.Value::I32(0)]
                      }
                      let st0 = match table.streams.get(ep.stream_id) {
                        Some(s) => s
                        None => {
                          trap_canon("unknown stream handle index \{handle}")
                          return [@types.Value::I32(0)]
                        }
                      }
                      // If re-executing a previously blocking read, return its completion.
                      match st0.pending_read {
                        Some(pr0) =>
                          if pr0.reader_handle == handle {
                            if pr0.filled == pr0.len || st0.writable_dropped {
                              let dropped = if st0.writable_dropped {
                                1
                              } else {
                                0
                              }
                              if dropped == 1 {
                                ep.notified_peer_dropped[0] = true
                              }
                              table.streams.set(ep.stream_id, {
                                elem_size: st0.elem_size,
                                own_resource_type_id: st0.own_resource_type_id,
                                pending_read: None,
                                pending_write: st0.pending_write,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                              })
                              return [
                                @types.Value::I32(dropped | (pr0.filled << 4)),
                              ]
                            } else if is_async {
                              return [@types.Value::I32(-1)]
                            } else {
                              if !async_state.task_can_block[0] {
                                trap_canon(
                                  "cannot block a synchronous task before returning",
                                )
                                return [@types.Value::I32(0)]
                              }
                              canon_suspend[0] = Some(CanonSuspend::Yield)
                              raise @runtime.RuntimeError::Unreachable
                            }
                          } else {
                            // Another read is already in progress.
                            trap_canon("cannot remove busy stream")
                            return [@types.Value::I32(0)]
                          }
                        None => ()
                      }
                      match st0.pending_write {
                        Some(pw) => {
                          let elem_size = st0.elem_size
                          let total_elems = pw.buf.length() / elem_size
                          // Zero-length reads must block and complete via an event even when a
                          // zero-length write is already pending (component-spec/async/zero-length.wast).
                          if is_async && len == 0 && total_elems == 0 {
                            // Ensure the pending write gets a completion event.
                            let mut pw_event_enqueued = pw.event_enqueued
                            if !pw_event_enqueued {
                              enqueue_waitable_event(
                                async_state,
                                pw.writer_handle,
                                {
                                  code: 3,
                                  index: pw.writer_handle,
                                  payload: (if st0.readable_dropped {
                                    1
                                  } else {
                                    0
                                  }) |
                                  (0 << 4),
                                },
                              )
                              pw_event_enqueued = true
                            }
                            // And complete this read via an event too.
                            enqueue_waitable_event(async_state, handle, {
                              code: 2,
                              index: handle,
                              payload: (if st0.writable_dropped {
                                1
                              } else {
                                0
                              }) |
                              (0 << 4),
                            })
                            let pr = {
                              mem_addr: resources.mem_addr,
                              reader_table,
                              ptr,
                              len: 0,
                              filled: 0,
                              reader_handle: handle,
                              event_enqueued: true,
                            }
                            table.streams.set(ep.stream_id, {
                              elem_size: st0.elem_size,
                              own_resource_type_id: st0.own_resource_type_id,
                              pending_read: Some(pr),
                              pending_write: Some({
                                writer_table: pw.writer_table,
                                buf: pw.buf,
                                sent: pw.sent,
                                writer_handle: pw.writer_handle,
                                event_enqueued: pw_event_enqueued,
                              }),
                              readable_dropped: st0.readable_dropped,
                              writable_dropped: st0.writable_dropped,
                            })
                            return [@types.Value::I32(-1)]
                          }
                          let remain = total_elems - pw.sent
                          let n = if len < remain { len } else { remain }
                          let base = pw.sent * elem_size
                          match (st0.own_resource_type_id, mem_opt) {
                            (Some(expected_type_id), Some(mem)) =>
                              for i in 0..<n {
                                let off = base + i * elem_size
                                // Handle indices are encoded as i32 per element.
                                let writer_handle = read_i32_le_from_bytes(
                                  pw.buf,
                                  off,
                                )
                                let new_handle = if pw.writer_table.id ==
                                  reader_table.id {
                                  // Same component instance: no ownership transfer.
                                  writer_handle
                                } else {
                                  let entry = match
                                    pw.writer_table.free(writer_handle) {
                                    Some(e) => e
                                    None => {
                                      trap_canon(
                                        "unknown handle index \{writer_handle}",
                                      )
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  if entry.type_id != expected_type_id {
                                    trap_canon(
                                      "handle index \{writer_handle} used with the wrong type",
                                    )
                                    return [@types.Value::I32(0)]
                                  }
                                  reader_table.alloc(entry)
                                }
                                mem.store_i32(ptr + i * elem_size, new_handle) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              }
                            (Some(_), None) => {
                              trap_canon("missing canon memory")
                              return [@types.Value::I32(0)]
                            }
                            (None, Some(mem)) => {
                              let bytes_n = n * elem_size
                              for i in 0..<bytes_n {
                                mem.store_byte(ptr + i, pw.buf[base + i]) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              }
                            }
                            (None, None) => ()
                          }
                          let new_sent = pw.sent + n
                          // When a pending write has been fully consumed, emit STREAM_WRITE and
                          // keep the write around until its event is delivered (notification semantics).
                          let mut event_enqueued = pw.event_enqueued
                          if new_sent >= total_elems && !event_enqueued {
                            enqueue_waitable_event(
                              async_state,
                              pw.writer_handle,
                              {
                                code: 3,
                                index: pw.writer_handle,
                                payload: (if st0.readable_dropped {
                                  1
                                } else {
                                  0
                                }) |
                                (total_elems << 4),
                              },
                            )
                            event_enqueued = true
                          }
                          let pw2 = Some({
                            writer_table: pw.writer_table,
                            buf: pw.buf,
                            sent: new_sent,
                            writer_handle: pw.writer_handle,
                            event_enqueued,
                          })
                          table.streams.set(ep.stream_id, {
                            elem_size: st0.elem_size,
                            own_resource_type_id: st0.own_resource_type_id,
                            pending_read: st0.pending_read,
                            pending_write: pw2,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                          })
                          let dropped = if st0.writable_dropped { 1 } else { 0 }
                          [@types.Value::I32(dropped | (n << 4))]
                        }
                        None =>
                          if st0.writable_dropped {
                            ep.notified_peer_dropped[0] = true
                            [@types.Value::I32(1)]
                          } else {
                            // Register a pending read and report BLOCKED.
                            let pr = {
                              mem_addr: resources.mem_addr,
                              reader_table,
                              ptr,
                              len,
                              filled: 0,
                              reader_handle: handle,
                              event_enqueued: false,
                            }
                            table.streams.set(ep.stream_id, {
                              elem_size: st0.elem_size,
                              own_resource_type_id: st0.own_resource_type_id,
                              pending_read: Some(pr),
                              pending_write: st0.pending_write,
                              readable_dropped: st0.readable_dropped,
                              writable_dropped: st0.writable_dropped,
                            })
                            if is_async {
                              [@types.Value::I32(-1)]
                            } else {
                              if !async_state.task_can_block[0] {
                                trap_canon(
                                  "cannot block a synchronous task before returning",
                                )
                                return [@types.Value::I32(0)]
                              }
                              canon_suspend[0] = Some(CanonSuspend::Yield)
                              raise @runtime.RuntimeError::Unreachable
                            }
                          }
                      }
                    }
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
      Canon::StreamWrite(_tyidx, opts) => {
        let core_type : @types.FuncType = {
          params: [
            @types.ValueType::I32,
            @types.ValueType::I32,
            @types.ValueType::I32,
          ],
          results: [@types.ValueType::I32],
        }
        let resources = resolve_canon_resources(opts, state) catch {
          e => raise e
        }
        let payload_ty : ValType? = match state.types.get(_tyidx) {
          Some(Some(TypeDef::Stream(v))) => v
          _ => None
        }
        let is_async = canon_opt_is_async(opts)
        let writer_table = state.resource_table
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let mem_opt : @runtime.Memory? = match payload_ty {
            Some(_) =>
              match resources.mem_addr {
                Some(addr) =>
                  Some(
                    store.get_mem(addr) catch {
                      e => {
                        trap_canon(e.to_string())
                        return [@types.Value::I32(0)]
                      }
                    },
                  )
                None => {
                  trap_canon("missing canon memory")
                  return [@types.Value::I32(0)]
                }
              }
            None => None
          }
          match args {
            [
              @types.Value::I32(handle),
              @types.Value::I32(ptr),
              @types.Value::I32(len),
            ] => {
              if !is_async && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
                return [@types.Value::I32(0)]
              }
              if len < 0 {
                trap_canon("type mismatch")
                [@types.Value::I32(0)]
              } else {
                match table.endpoints.get(handle) {
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    [@types.Value::I32(0)]
                  }
                  Some(ep) =>
                    if ep.is_readable {
                      trap_canon("type mismatch")
                      [@types.Value::I32(0)]
                    } else {
                      if ep.notified_peer_dropped[0] {
                        trap_canon(
                          "cannot write to stream after being notified that the readable end dropped",
                        )
                        return [@types.Value::I32(0)]
                      }
                      let st0 = match table.streams.get(ep.stream_id) {
                        Some(s) => s
                        None => {
                          trap_canon("unknown stream handle index \{handle}")
                          return [@types.Value::I32(0)]
                        }
                      }
                      // If re-executing a previously blocking write, return its completion.
                      match st0.pending_write {
                        Some(pw0) =>
                          if pw0.writer_handle == handle {
                            let elem_size = st0.elem_size
                            let total_elems = pw0.buf.length() / elem_size
                            if st0.readable_dropped || pw0.sent >= total_elems {
                              let dropped = if st0.readable_dropped {
                                1
                              } else {
                                0
                              }
                              if dropped == 1 {
                                ep.notified_peer_dropped[0] = true
                              }
                              table.streams.set(ep.stream_id, {
                                elem_size: st0.elem_size,
                                own_resource_type_id: st0.own_resource_type_id,
                                pending_read: st0.pending_read,
                                pending_write: None,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                              })
                              return [
                                @types.Value::I32(dropped | (pw0.sent << 4)),
                              ]
                            } else if is_async {
                              return [@types.Value::I32(-1)]
                            } else {
                              if !async_state.task_can_block[0] {
                                trap_canon(
                                  "cannot block a synchronous task before returning",
                                )
                                return [@types.Value::I32(0)]
                              }
                              canon_suspend[0] = Some(CanonSuspend::Yield)
                              raise @runtime.RuntimeError::Unreachable
                            }
                          } else {
                            trap_canon("cannot drop busy stream")
                            return [@types.Value::I32(0)]
                          }
                        None => ()
                      }
                      if st0.readable_dropped {
                        ep.notified_peer_dropped[0] = true
                        return [@types.Value::I32(1)]
                      }
                      match st0.pending_read {
                        Some(pr0) => {
                          // Symmetric zero-length rendezvous: if a zero-length read is pending,
                          // a zero-length write must also complete via events (not eagerly).
                          if is_async && len == 0 && pr0.len == 0 {
                            let mut pr_event_enqueued = pr0.event_enqueued
                            if !pr_event_enqueued {
                              enqueue_waitable_event(
                                async_state,
                                pr0.reader_handle,
                                {
                                  code: 2,
                                  index: pr0.reader_handle,
                                  payload: (if st0.writable_dropped {
                                    1
                                  } else {
                                    0
                                  }) |
                                  (0 << 4),
                                },
                              )
                              pr_event_enqueued = true
                            }
                            enqueue_waitable_event(async_state, handle, {
                              code: 3,
                              index: handle,
                              payload: (if st0.readable_dropped {
                                1
                              } else {
                                0
                              }) |
                              (0 << 4),
                            })
                            table.streams.set(ep.stream_id, {
                              elem_size: st0.elem_size,
                              own_resource_type_id: st0.own_resource_type_id,
                              pending_read: Some({
                                mem_addr: pr0.mem_addr,
                                reader_table: pr0.reader_table,
                                ptr: pr0.ptr,
                                len: pr0.len,
                                filled: pr0.filled,
                                reader_handle: pr0.reader_handle,
                                event_enqueued: pr_event_enqueued,
                              }),
                              pending_write: Some({
                                writer_table,
                                buf: [],
                                sent: 0,
                                writer_handle: handle,
                                event_enqueued: true,
                              }),
                              readable_dropped: st0.readable_dropped,
                              writable_dropped: st0.writable_dropped,
                            })
                            return [@types.Value::I32(-1)]
                          }
                          let elem_size = st0.elem_size
                          let remain = pr0.len - pr0.filled
                          if remain <= 0 {
                            // The reader's buffer is full (completion not yet acknowledged): block.
                            let buf : Array[Byte] = []
                            let src_bytes = len * elem_size
                            for i in 0..<src_bytes {
                              let b = match mem_opt {
                                Some(mem) =>
                                  mem.load_byte(ptr + i) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                None => b'\x00'
                              }
                              buf.push(b)
                            }
                            table.streams.set(ep.stream_id, {
                              elem_size: st0.elem_size,
                              own_resource_type_id: st0.own_resource_type_id,
                              pending_read: st0.pending_read,
                              pending_write: Some({
                                writer_table,
                                buf,
                                sent: 0,
                                writer_handle: handle,
                                event_enqueued: false,
                              }),
                              readable_dropped: st0.readable_dropped,
                              writable_dropped: st0.writable_dropped,
                            })
                            if is_async {
                              return [@types.Value::I32(-1)]
                            } else {
                              if !async_state.task_can_block[0] {
                                trap_canon(
                                  "cannot block a synchronous task before returning",
                                )
                                return [@types.Value::I32(0)]
                              }
                              canon_suspend[0] = Some(CanonSuspend::Yield)
                              raise @runtime.RuntimeError::Unreachable
                            }
                          }
                          let n = if len < remain { len } else { remain }
                          // Snapshot src bytes first to preserve memmove semantics when regions overlap.
                          let buf : Array[Byte] = []
                          let src_bytes = len * elem_size
                          for i in 0..<src_bytes {
                            let b = match mem_opt {
                              Some(mem) =>
                                mem.load_byte(ptr + i) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => b'\x00'
                            }
                            buf.push(b)
                          }
                          // Copy into the *reader* memory/buffer, not the writer memory.
                          // For empty streams (no canon memory), `mem_opt` is None and we
                          // must not touch either pointer/memory.
                          match (st0.own_resource_type_id, mem_opt) {
                            (Some(expected_type_id), Some(src_mem)) => {
                              let dst_mem = match pr0.mem_addr {
                                Some(addr) =>
                                  store.get_mem(addr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                None => {
                                  trap_canon("missing canon memory")
                                  return [@types.Value::I32(0)]
                                }
                              }
                              for i in 0..<n {
                                let writer_handle = src_mem.load_i32(
                                  ptr + i * elem_size,
                                ) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                                let new_handle = if writer_table.id ==
                                  pr0.reader_table.id {
                                  writer_handle
                                } else {
                                  let entry = match
                                    writer_table.free(writer_handle) {
                                    Some(e) => e
                                    None => {
                                      trap_canon(
                                        "unknown handle index \{writer_handle}",
                                      )
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  if entry.type_id != expected_type_id {
                                    trap_canon(
                                      "handle index \{writer_handle} used with the wrong type",
                                    )
                                    return [@types.Value::I32(0)]
                                  }
                                  pr0.reader_table.alloc(entry)
                                }
                                dst_mem.store_i32(
                                  pr0.ptr + (pr0.filled + i) * elem_size,
                                  new_handle,
                                ) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              }
                            }
                            (Some(_), None) => {
                              trap_canon("missing canon memory")
                              return [@types.Value::I32(0)]
                            }
                            (None, Some(_src_mem)) => {
                              let dst_mem = match pr0.mem_addr {
                                Some(addr) =>
                                  store.get_mem(addr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                None => {
                                  trap_canon("missing canon memory")
                                  return [@types.Value::I32(0)]
                                }
                              }
                              let bytes_n = n * elem_size
                              let dst_base = pr0.ptr + pr0.filled * elem_size
                              for i in 0..<bytes_n {
                                dst_mem.store_byte(dst_base + i, buf[i]) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              }
                            }
                            (None, None) => ()
                          }
                          let filled1 = pr0.filled + n
                          let mut event_enqueued = pr0.event_enqueued
                          // Emit STREAM_READ once the whole read buffer is filled (or the peer is dropped).
                          if (filled1 >= pr0.len || st0.writable_dropped) &&
                            !event_enqueued {
                            enqueue_waitable_event(
                              async_state,
                              pr0.reader_handle,
                              {
                                code: 2,
                                index: pr0.reader_handle,
                                payload: (if st0.writable_dropped {
                                  1
                                } else {
                                  0
                                }) |
                                (filled1 << 4),
                              },
                            )
                            event_enqueued = true
                          }
                          let pr1 = {
                            mem_addr: pr0.mem_addr,
                            reader_table: pr0.reader_table,
                            ptr: pr0.ptr,
                            len: pr0.len,
                            filled: filled1,
                            reader_handle: pr0.reader_handle,
                            event_enqueued,
                          }
                          table.streams.set(ep.stream_id, {
                            elem_size: st0.elem_size,
                            own_resource_type_id: st0.own_resource_type_id,
                            pending_read: Some(pr1),
                            pending_write: st0.pending_write,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                          })
                          [@types.Value::I32(n << 4)]
                        }
                        None => {
                          // Register a pending write by copying bytes.
                          let buf : Array[Byte] = []
                          let elem_size = st0.elem_size
                          let src_bytes = len * elem_size
                          for i in 0..<src_bytes {
                            let b = match mem_opt {
                              Some(mem) =>
                                mem.load_byte(ptr + i) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => b'\x00'
                            }
                            buf.push(b)
                          }
                          table.streams.set(ep.stream_id, {
                            elem_size: st0.elem_size,
                            own_resource_type_id: st0.own_resource_type_id,
                            pending_read: st0.pending_read,
                            pending_write: Some({
                              writer_table,
                              buf,
                              sent: 0,
                              writer_handle: handle,
                              event_enqueued: false,
                            }),
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                          })
                          if is_async {
                            [@types.Value::I32(-1)]
                          } else {
                            if !async_state.task_can_block[0] {
                              trap_canon(
                                "cannot block a synchronous task before returning",
                              )
                              return [@types.Value::I32(0)]
                            }
                            canon_suspend[0] = Some(CanonSuspend::Yield)
                            raise @runtime.RuntimeError::Unreachable
                          }
                        }
                      }
                    }
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
      Canon::StreamCancelRead(_tyidx, is_async_cancel) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          if !is_async_cancel && !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return [@types.Value::I32(0)]
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.endpoints.get(handle) {
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  [@types.Value::I32(0)]
                }
                Some(ep) =>
                  if !ep.is_readable {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  } else {
                    let st0 = match table.streams.get(ep.stream_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        return [@types.Value::I32(0)]
                      }
                    }
                    match st0.pending_read {
                      Some(pr) => {
                        let code = if st0.writable_dropped { 1 } else { 2 }
                        let filled = pr.filled
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: None,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
                        })
                        [@types.Value::I32(code | (filled << 4))]
                      }
                      None => [@types.Value::I32(2)]
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
      Canon::StreamCancelWrite(_tyidx, is_async_cancel) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          if !is_async_cancel && !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return [@types.Value::I32(0)]
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.endpoints.get(handle) {
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  [@types.Value::I32(0)]
                }
                Some(ep) =>
                  if ep.is_readable {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  } else {
                    let st0 = match table.streams.get(ep.stream_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        return [@types.Value::I32(0)]
                      }
                    }
                    match st0.pending_write {
                      Some(pw) => {
                        let code = if st0.readable_dropped { 1 } else { 2 }
                        let sent = pw.sent
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: st0.pending_read,
                          pending_write: None,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
                        })
                        [@types.Value::I32(code | (sent << 4))]
                      }
                      None => [@types.Value::I32(2)]
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
      Canon::StreamDropReadable(_tyidx) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [],
        }
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.endpoints.get(handle) {
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  []
                }
                Some(ep) =>
                  if !ep.is_readable {
                    trap_canon("type mismatch")
                    []
                  } else {
                    let st0 = match table.streams.get(ep.stream_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        return []
                      }
                    }
                    // Dropping a readable endpoint is only invalid if there is an
                    // active read in progress on that endpoint.
                    if st0.pending_read is Some(_) {
                      trap_canon("cannot remove busy stream")
                      return []
                    }
                    // Dropping readable may resolve a pending write as DROPPED.
                    match st0.pending_write {
                      Some(pw) => {
                        let payload = 1 | (pw.sent << 4)
                        if pw.event_enqueued {
                          update_waitable_event_payload(
                            async_state,
                            pw.writer_handle,
                            3,
                            payload,
                          )
                        } else {
                          enqueue_waitable_event(
                            async_state,
                            pw.writer_handle,
                            { code: 3, index: pw.writer_handle, payload },
                          )
                        }
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: st0.pending_read,
                          pending_write: Some({
                            writer_table: pw.writer_table,
                            buf: pw.buf,
                            sent: pw.sent,
                            writer_handle: pw.writer_handle,
                            event_enqueued: true,
                          }),
                          readable_dropped: true,
                          writable_dropped: st0.writable_dropped,
                        })
                      }
                      None =>
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: st0.pending_read,
                          pending_write: st0.pending_write,
                          readable_dropped: true,
                          writable_dropped: st0.writable_dropped,
                        })
                    }
                    // Remove from any waitable-set membership and queued events.
                    remove_waitable_membership(async_state, handle)
                    table.free_endpoint(handle)
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
      Canon::StreamDropWritable(_tyidx) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [],
        }
        let table = state.stream_table
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          match args {
            [@types.Value::I32(handle)] =>
              match table.endpoints.get(handle) {
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  []
                }
                Some(ep) =>
                  if ep.is_readable {
                    trap_canon("type mismatch")
                    []
                  } else {
                    let st0 = match table.streams.get(ep.stream_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        return []
                      }
                    }
                    // Dropping a writable endpoint is only invalid if there is an
                    // active write in progress on that endpoint.
                    if st0.pending_write is Some(_) {
                      trap_canon("cannot drop busy stream")
                      return []
                    }
                    // Dropping writable may resolve a pending read as DROPPED.
                    match st0.pending_read {
                      Some(pr) => {
                        let payload = 1 | (pr.filled << 4)
                        if pr.event_enqueued {
                          update_waitable_event_payload(
                            async_state,
                            pr.reader_handle,
                            2,
                            payload,
                          )
                        } else {
                          enqueue_waitable_event(
                            async_state,
                            pr.reader_handle,
                            { code: 2, index: pr.reader_handle, payload },
                          )
                        }
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: Some({
                            mem_addr: pr.mem_addr,
                            reader_table: pr.reader_table,
                            ptr: pr.ptr,
                            len: pr.len,
                            filled: pr.filled,
                            reader_handle: pr.reader_handle,
                            event_enqueued: true,
                          }),
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: true,
                        })
                      }
                      None =>
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: st0.pending_read,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: true,
                        })
                    }
                    // Remove from any waitable-set membership and queued events.
                    remove_waitable_membership(async_state, handle)
                    table.free_endpoint(handle)
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
      Canon::FutureNew(_tyidx) => {
        let core_type : @types.FuncType = {
          params: [],
          results: [@types.ValueType::I64],
        }
        let async_state = state.async_state
        let creator_component_id = state.resource_table.id
        let payload_ty : ValType? = match state.types.get(_tyidx) {
          Some(Some(TypeDef::Future(v))) => v
          _ => None
        }
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          // Replay-safe: `canon future.new` can be re-executed when a callback-style
          // async core function is restarted after a suspension.
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_i64(x : Int64) -> Array[@types.Value] {
            let out = [@types.Value::I64(x)]
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }

          fn alloc_with_source() -> (Int, Bool) {
            if async_state.free_handles.length() > 0 {
              // Deterministic: pick smallest.
              let mut best_i = 0
              let mut best = async_state.free_handles[0]
              for i in 1..<async_state.free_handles.length() {
                let h = async_state.free_handles[i]
                if h < best {
                  best = h
                  best_i = i
                }
              }
              async_state.free_handles.remove(best_i) |> ignore
              (best, true)
            } else {
              let h = async_state.next_handle[0]
              async_state.next_handle[0] = h + 1
              (h, false)
            }
          }

          let future_id = async_state.next_future_id[0]
          async_state.next_future_id[0] = future_id + 1
          let (rh, wh) = if payload_ty is Some(_) {
            // For typed futures, prefer reusing a freed handle for the readable end.
            let (h1, f1) = alloc_with_source()
            let (h2, f2) = alloc_with_source()
            if f1 != f2 {
              if f1 {
                (h1, h2)
              } else {
                (h2, h1)
              }
            } else if h1 < h2 {
              (h2, h1)
            } else {
              (h1, h2)
            }
          } else {
            // Empty future: allocate readable then writable.
            let (rh, _fr) = alloc_with_source()
            let (wh, _fw) = alloc_with_source()
            (rh, wh)
          }
          async_state.future_endpoints.set(rh, {
            future_id,
            is_readable: true,
            creator_component_id,
          })
          async_state.future_endpoints.set(wh, {
            future_id,
            is_readable: false,
            creator_component_id,
          })
          async_state.futures.set(future_id, {
            readable_handle: rh,
            writable_handle: wh,
            payload_ty,
            pending_read: None,
            pending_write: None,
            readable_dropped: false,
            writable_dropped: false,
            read_done: false,
            write_succeeded: false,
            write_observed_readable_drop: false,
            wrote_value: false,
          })
          let packed = (wh.to_int64() << 32) | (rh.to_int64() & 0xFFFFFFFFL)
          cache_i64(packed)
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::FutureRead(_tyidx, _opts) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32, @types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let resources = resolve_canon_resources(_opts, state) catch {
          e => raise e
        }
        let async_state = state.async_state
        let caller_component_id = state.resource_table.id
        let is_async = canon_opt_is_async(_opts)
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_i32(n : Int) -> Array[@types.Value] {
            let out = [@types.Value::I32(n)]
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }
          // Sync future.read blocks the task; the async form returns BLOCKED=-1.
          if !is_async && !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return cache_i32(0)
          }
          match args {
            [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
              match async_state.future_endpoints.get(handle) {
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  cache_i32(0)
                }
                Some(ep) =>
                  if !ep.is_readable {
                    trap_canon("type mismatch")
                    cache_i32(0)
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        return cache_i32(0)
                      }
                    }
                    if st0.read_done {
                      trap_canon(
                        "cannot read from future after previous read succeeded",
                      )
                      return cache_i32(0)
                    }
                    match st0.pending_write {
                      Some(v) => {
                        // Intra-component char futures cannot rendezvous.
                        match st0.payload_ty {
                          Some(Prim(Char)) =>
                            if ep.creator_component_id == caller_component_id {
                              trap_canon(
                                "cannot read from and write to intra-component future",
                              )
                              return [@types.Value::I32(0)]
                            }
                          _ => ()
                        }

                        // Write payload (if any) to memory at `ptr`.
                        match st0.payload_ty {
                          None => ()
                          Some(Prim(U8)) => {
                            let mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            mem.store_byte(ptr, trunc_u8(v).to_byte()) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                          }
                          Some(Prim(Char)) => {
                            if ptr % 4 != 0 {
                              trap_canon("unaligned pointer")
                              return [@types.Value::I32(0)]
                            }
                            let mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            mem.store_i32(ptr, v) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                          }
                          _ => {
                            trap_canon("unsupported future type")
                            return [@types.Value::I32(0)]
                          }
                        }

                        // Completing a pending write unblocks the writer: emit FUTURE_WRITE.
                        if async_state.future_endpoints.get(st0.writable_handle)
                          is Some(_) {
                          enqueue_waitable_event(
                            async_state,
                            st0.writable_handle,
                            { code: 5, index: st0.writable_handle, payload: 0 },
                          )
                        }
                        async_state.futures.set(ep.future_id, {
                          readable_handle: st0.readable_handle,
                          writable_handle: st0.writable_handle,
                          payload_ty: st0.payload_ty,
                          pending_read: None,
                          pending_write: None,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
                          read_done: true,
                          write_succeeded: true,
                          write_observed_readable_drop: st0.write_observed_readable_drop,
                          wrote_value: st0.wrote_value,
                        })
                        cache_i32(0)
                      }
                      None =>
                        if st0.writable_dropped {
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: None,
                            pending_write: None,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                            read_done: true,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            wrote_value: st0.wrote_value,
                          })
                          cache_i32(1)
                        } else {
                          // Register a pending read and report BLOCKED=-1.
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: Some({
                              // Remember the reader-side canon memory so a writer from a different
                              // component instance can write into the correct memory.
                              mem_addr: resources.mem_addr,
                              ptr,
                            }),
                            pending_write: None,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                            read_done: st0.read_done,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            wrote_value: st0.wrote_value,
                          })
                          cache_i32(-1)
                        }
                    }
                  }
              }
            _ => {
              trap_canon("type mismatch")
              cache_i32(0)
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::FutureWrite(_tyidx, _opts) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32, @types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let resources = resolve_canon_resources(_opts, state) catch {
          e => raise e
        }
        let async_state = state.async_state
        let caller_component_id = state.resource_table.id
        let is_async = canon_opt_is_async(_opts)
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          let cur = if async_state.call_cursor_stack.length() == 0 {
            0
          } else {
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1]
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
              async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
              1] = cur + 1
              return v
            }
            None => ()
          }
          fn cache_i32(n : Int) -> Array[@types.Value] {
            let out = [@types.Value::I32(n)]
            per_task.set(cur, out)
            async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
            1] = cur + 1
            out
          }
          // Sync future.write blocks the task; the async form returns BLOCKED=-1.
          if !is_async && !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return cache_i32(0)
          }
          match args {
            [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
              match async_state.future_endpoints.get(handle) {
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  cache_i32(0)
                }
                Some(ep) =>
                  if ep.is_readable {
                    trap_canon("type mismatch")
                    cache_i32(0)
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        return cache_i32(0)
                      }
                    }
                    if st0.write_succeeded {
                      trap_canon(
                        "cannot write to future after previous write succeeded",
                      )
                      return cache_i32(0)
                    }
                    if st0.write_observed_readable_drop {
                      trap_canon(
                        "cannot write to future after previous write succeeded or readable end dropped",
                      )
                      return cache_i32(0)
                    }

                    // If the readable end was dropped before any rendezvous, report DROPPED.
                    if st0.readable_dropped {
                      async_state.futures.set(ep.future_id, {
                        readable_handle: st0.readable_handle,
                        writable_handle: st0.writable_handle,
                        payload_ty: st0.payload_ty,
                        pending_read: None,
                        pending_write: None,
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                        read_done: st0.read_done,
                        write_succeeded: false,
                        write_observed_readable_drop: true,
                        wrote_value: st0.wrote_value,
                      })
                      return cache_i32(1)
                    }
                    match st0.pending_read {
                      Some(pr) => {
                        // Intra-component char futures cannot rendezvous.
                        match st0.payload_ty {
                          Some(Prim(Char)) =>
                            if ep.creator_component_id == caller_component_id {
                              trap_canon(
                                "cannot read from and write to intra-component future",
                              )
                              return [@types.Value::I32(0)]
                            }
                          _ => ()
                        }

                        // Load payload (if any) from writer memory at `ptr` and write to the
                        // reader memory at `pr.ptr`.
                        match st0.payload_ty {
                          None => ()
                          Some(Prim(U8)) => {
                            let src_mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let dst_mem = match pr.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let b = src_mem.load_byte(ptr) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                            dst_mem.store_byte(pr.ptr, b) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                          }
                          Some(Prim(Char)) => {
                            if ptr % 4 != 0 || pr.ptr % 4 != 0 {
                              trap_canon("unaligned pointer")
                              return [@types.Value::I32(0)]
                            }
                            let src_mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let dst_mem = match pr.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let n = src_mem.load_i32(ptr) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                            // Validate scalar value.
                            (char_from_canon_i32(n) catch {
                              e => {
                                trap_canon(canon_err_message(e))
                                return [@types.Value::I32(0)]
                              }
                            })
                            |> ignore
                            dst_mem.store_i32(pr.ptr, n) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                          }
                          _ => {
                            trap_canon("unsupported future type")
                            return [@types.Value::I32(0)]
                          }
                        }

                        // Completing a pending read unblocks the reader: emit FUTURE_READ.
                        if async_state.future_endpoints.get(st0.readable_handle)
                          is Some(_) {
                          enqueue_waitable_event(
                            async_state,
                            st0.readable_handle,
                            { code: 4, index: st0.readable_handle, payload: 0 },
                          )
                        }
                        async_state.futures.set(ep.future_id, {
                          readable_handle: st0.readable_handle,
                          writable_handle: st0.writable_handle,
                          payload_ty: st0.payload_ty,
                          pending_read: None,
                          pending_write: None,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
                          read_done: true,
                          write_succeeded: true,
                          write_observed_readable_drop: st0.write_observed_readable_drop,
                          wrote_value: true,
                        })
                        cache_i32(0)
                      }
                      None => {
                        // Register a pending write by reading the payload once.
                        let write_val : Int = match st0.payload_ty {
                          None => 0
                          Some(Prim(U8)) => {
                            let mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let b = mem.load_byte(ptr) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                            b.to_int()
                          }
                          Some(Prim(Char)) => {
                            if ptr % 4 != 0 {
                              trap_canon("unaligned pointer")
                              return [@types.Value::I32(0)]
                            }
                            let mem = match resources.mem_addr {
                              Some(addr) =>
                                store.get_mem(addr) catch {
                                  e => {
                                    trap_canon(e.to_string())
                                    return [@types.Value::I32(0)]
                                  }
                                }
                              None => {
                                trap_canon("missing canon memory")
                                return [@types.Value::I32(0)]
                              }
                            }
                            let n = mem.load_i32(ptr) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [@types.Value::I32(0)]
                              }
                            }
                            (char_from_canon_i32(n) catch {
                              e => {
                                trap_canon(canon_err_message(e))
                                return [@types.Value::I32(0)]
                              }
                            })
                            |> ignore
                            n
                          }
                          _ => {
                            trap_canon("unsupported future type")
                            return [@types.Value::I32(0)]
                          }
                        }
                        async_state.futures.set(ep.future_id, {
                          readable_handle: st0.readable_handle,
                          writable_handle: st0.writable_handle,
                          payload_ty: st0.payload_ty,
                          pending_read: None,
                          pending_write: Some(write_val),
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
                          read_done: st0.read_done,
                          write_succeeded: st0.write_succeeded,
                          write_observed_readable_drop: st0.write_observed_readable_drop,
                          wrote_value: true,
                        })
                        cache_i32(-1)
                      }
                    }
                  }
              }
            _ => {
              trap_canon("type mismatch")
              cache_i32(0)
            }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::FutureCancelRead(_tyidx, _is_async) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          if !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return [@types.Value::I32(0)]
          }
          match args {
            [@types.Value::I32(handle)] =>
              match async_state.future_endpoints.get(handle) {
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  [@types.Value::I32(0)]
                }
                Some(ep) =>
                  if !ep.is_readable {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        return [@types.Value::I32(0)]
                      }
                    }
                    async_state.futures.set(ep.future_id, {
                      readable_handle: st0.readable_handle,
                      writable_handle: st0.writable_handle,
                      payload_ty: st0.payload_ty,
                      pending_read: None,
                      pending_write: st0.pending_write,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                      read_done: st0.read_done,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      wrote_value: st0.wrote_value,
                    })
                    // CANCELLED=2
                    [@types.Value::I32(2)]
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
      Canon::FutureCancelWrite(_tyidx, _is_async) => {
        let core_type : @types.FuncType = {
          params: [@types.ValueType::I32],
          results: [@types.ValueType::I32],
        }
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          if !async_state.task_can_block[0] {
            trap_canon("cannot block a synchronous task before returning")
            return [@types.Value::I32(0)]
          }
          match args {
            [@types.Value::I32(handle)] =>
              match async_state.future_endpoints.get(handle) {
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  [@types.Value::I32(0)]
                }
                Some(ep) =>
                  if ep.is_readable {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        return [@types.Value::I32(0)]
                      }
                    }
                    let had_pending = match st0.pending_write {
                      Some(_) => true
                      None => false
                    }
                    async_state.futures.set(ep.future_id, {
                      readable_handle: st0.readable_handle,
                      writable_handle: st0.writable_handle,
                      payload_ty: st0.payload_ty,
                      pending_read: st0.pending_read,
                      pending_write: None,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                      read_done: st0.read_done,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      // If we cancelled a pending write, treat as "no value written".
                      wrote_value: if had_pending {
                        false
                      } else {
                        st0.wrote_value
                      },
                    })
                    [@types.Value::I32(2)]
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
      Canon::FutureDropReadable(_tyidx) => {
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
            [@types.Value::I32(handle)] =>
              match async_state.future_endpoints.get(handle) {
                Some(ep) =>
                  if !ep.is_readable {
                    []
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => return []
                    }
                    // Dropping readable end may resolve a pending write as DROPPED.
                    if st0.pending_write is Some(_) {
                      if async_state.future_endpoints.get(st0.writable_handle)
                        is Some(_) {
                        enqueue_waitable_event(
                          async_state,
                          st0.writable_handle,
                          { code: 5, index: st0.writable_handle, payload: 1 },
                        )
                      }
                    }
                    async_state.futures.set(ep.future_id, {
                      readable_handle: st0.readable_handle,
                      writable_handle: st0.writable_handle,
                      payload_ty: st0.payload_ty,
                      pending_read: None,
                      pending_write: None,
                      readable_dropped: true,
                      writable_dropped: st0.writable_dropped,
                      read_done: true,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      wrote_value: st0.wrote_value,
                    })

                    // Remove from any waitable-set membership and queued events.
                    match async_state.waitable_to_set.get(handle) {
                      Some(ws) => {
                        async_state.waitable_to_set.remove(handle)
                        match async_state.waitable_sets.get(ws) {
                          Some(set) => {
                            set.members.remove(handle)
                            let mut i = 0
                            while i < set.queue.length() {
                              if set.queue[i].index == handle {
                                set.queue.remove(i) |> ignore
                              } else {
                                i = i + 1
                              }
                            }
                          }
                          None => ()
                        }
                      }
                      None => ()
                    }
                    async_state.waitable_events.remove(handle)
                    async_state.future_endpoints.remove(handle)
                    free_shared_handle(async_state, handle)
                    []
                  }
                None => []
              }
            _ => []
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::FutureDropWritable(_tyidx) => {
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
            [@types.Value::I32(handle)] =>
              match async_state.future_endpoints.get(handle) {
                Some(ep) =>
                  if ep.is_readable {
                    []
                  } else {
                    let st0 = match async_state.futures.get(ep.future_id) {
                      Some(s) => s
                      None => return []
                    }
                    if !st0.wrote_value && !st0.write_succeeded {
                      trap_canon(
                        "cannot drop future write end without first writing a value",
                      )
                      return []
                    }
                    async_state.futures.set(ep.future_id, {
                      readable_handle: st0.readable_handle,
                      writable_handle: st0.writable_handle,
                      payload_ty: st0.payload_ty,
                      pending_read: st0.pending_read,
                      pending_write: st0.pending_write,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: true,
                      read_done: st0.read_done,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      wrote_value: st0.wrote_value,
                    })
                    match async_state.waitable_to_set.get(handle) {
                      Some(ws) => {
                        async_state.waitable_to_set.remove(handle)
                        match async_state.waitable_sets.get(ws) {
                          Some(set) => {
                            set.members.remove(handle)
                            let mut i = 0
                            while i < set.queue.length() {
                              if set.queue[i].index == handle {
                                set.queue.remove(i) |> ignore
                              } else {
                                i = i + 1
                              }
                            }
                          }
                          None => ()
                        }
                      }
                      None => ()
                    }
                    async_state.waitable_events.remove(handle)
                    async_state.future_endpoints.remove(handle)
                    free_shared_handle(async_state, handle)
                    []
                  }
                None => []
              }
            _ => []
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ContextGet(_vt, _idx) => {
        let core_type : @types.FuncType = { params: [], results: [_vt] }
        let async_state = state.async_state
        let host = fn(
          _args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          let task_id = current_task_id(async_state)
          match async_state.task_contexts.get(task_id) {
            Some(m) =>
              match m.get(_idx) {
                Some(v) => [v]
                None =>
                  // Default 0 per value type.
                  match _vt {
                    @types.ValueType::I32 => [@types.Value::I32(0)]
                    @types.ValueType::I64 => [@types.Value::I64(0L)]
                    @types.ValueType::F32 => [@types.Value::F32(0.0)]
                    @types.ValueType::F64 => [@types.Value::F64(0.0)]
                    _ => {
                      trap_canon("unsupported context type")
                      []
                    }
                  }
              }
            None =>
              match _vt {
                @types.ValueType::I32 => [@types.Value::I32(0)]
                @types.ValueType::I64 => [@types.Value::I64(0L)]
                @types.ValueType::F32 => [@types.Value::F32(0.0)]
                @types.ValueType::F64 => [@types.Value::F64(0.0)]
                _ => {
                  trap_canon("unsupported context type")
                  []
                }
              }
          }
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      Canon::ContextSet(_vt, _idx) => {
        let core_type : @types.FuncType = { params: [_vt], results: [] }
        let async_state = state.async_state
        let host = fn(
          args : Array[@types.Value],
        ) -> Array[@types.Value] raise @runtime.RuntimeError {
          if !canon_may_leave[0] {
            trap_canon("cannot leave component instance")
          }
          if args.length() != 1 {
            trap_canon("type mismatch")
            return []
          }
          let task_id = current_task_id(async_state)
          let m = match async_state.task_contexts.get(task_id) {
            Some(m) => m
            None => {
              let m : Map[Int, @types.Value] = {}
              async_state.task_contexts.set(task_id, m)
              m
            }
          }
          m.set(_idx, args[0])
          []
        }
        state.core_funcs.push(alloc_host_core_func(store, core_type, host))
      }
      _ => ()
    }
  }
}
