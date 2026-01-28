///|
/// Canonical section instantiation helpers.
/// (group: lift_lower)

///|
fn instantiate_canon_lift(
  core_func_idx : Int,
  opts : Array[CanonOpt],
  type_idx : Int,
  state : BuildState,
  may_enter_self : Array[Bool],
) -> Unit raise ComponentRuntimeError {
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

///|
fn instantiate_canon_lower(
  func_idx : Int,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
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
  if func_type_needs_memory(func_type, func_types) && resources.mem_addr is None {
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
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
      }
      let per_task = match async_state.call_results.get(cur_task_id) {
        Some(m) => m
        None => {
          let m : Map[Int, Array[@types.Value]] = {}
          async_state.call_results.set(cur_task_id, m)
          m
        }
      }
      fn cache_and_advance(out : Array[@types.Value]) -> Array[@types.Value] {
        per_task.set(cur, out)
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
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
          let step = step_task_once(task, store, caller_table, async_state) catch {
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
                [@types.Value::I32(n)] => mem.store_i32(p, n) catch { _ => () }
                [@types.Value::I64(n)] => mem.store_i64(p, n) catch { _ => () }
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
              [@types.Value::I32(n)] => mem.store_i32(p, n) catch { _ => () }
              [@types.Value::I64(n)] => mem.store_i64(p, n) catch { _ => () }
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
        let per_task_calls = match async_state.call_results.get(outer_task_id) {
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
                  Some(ws) => canon_suspend[0] = Some(CanonSuspend::Wait(ws))
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
          let flat = core_types_for_valtype(rty, func_types, mem.is_memory64()) catch {
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
    state.core_funcs.push({ instance, func_idx: 0 })
  }
}
