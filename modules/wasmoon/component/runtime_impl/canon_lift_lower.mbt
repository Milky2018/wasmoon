///|
/// Canonical section instantiation helpers.
/// (group: lift_lower)

///|
fn store_async_lower_result(
  mem : @runtime.Memory,
  retptr : Int64,
  values : Array[@types.Value],
) -> Unit raise ComponentRuntimeError {
  match values {
    [] => ()
    [value] => store_flat_value(mem, retptr, value)
    _ => raise HostCallError("async lower produced multiple direct results")
  }
}

///|
fn instantiate_canon_lift(
  core_func_idx : Int,
  opts : Array[CanonOpt],
  type_idx : Int,
  state : BuildState,
  entry_state : ComponentInstanceEntryState,
) -> Unit raise ComponentRuntimeError {
  if core_func_idx < 0 || core_func_idx >= state.core_funcs.length() {
    raise InvalidCoreFuncIndex(core_func_idx)
  }
  if type_idx < 0 || type_idx >= state.types.length() {
    raise InvalidTypeIndex(type_idx)
  }
  let td = state.types[type_idx]
  let func_type = match td {
    Some(FuncType(ft)) => ft
    _ => raise InvalidCanonFuncType(type_idx)
  }
  let resources = resolve_canon_resources(opts, state)
  let callback = resolve_canon_callback(opts, state)
  // The function type permits suspension; the canonical option selects whether
  // results arrive through task.return or the ordinary core return values.
  let async_abi = canon_opt_is_async(opts)
  state.funcs.push(
    Lifted(
      state.core_funcs[core_func_idx],
      func_type,
      resources,
      state.types,
      state.resource_table,
      entry_state,
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
    Host(ft, types, _) => (ft, types)
    HostAsync(ft, types, _) => (ft, types)
    Lifted(_, ft, _, types, _, _, _, _) => (ft, types)
  }
  let resources = resolve_canon_resources(opts, state)
  let is_async_lower = canon_opt_is_async(opts)
  if func_type_needs_memory(func_type, func_types) && resources.mem_addr is None {
    raise MissingCanonMemory
  }
  let mem_is_64 = match resources.mem_addr {
    Some(_) => require_memory(resources, store).is_memory64()
    None => false
  }
  if is_async_lower {
    // Async lowering: start a subtask and return a status code, writing
    // eventual results into the provided return pointer.
    let ptr_ty = if mem_is_64 { @types.ValueType::I64 } else { I32 }
    let flat_params : Array[@types.ValueType] = []
    for p in func_type.params {
      for t in core_types_for_valtype(p.ty, func_types, mem_is_64, max_flat=5) {
        flat_params.push(t)
      }
    }
    let lowered_params : Array[@types.ValueType] = if flat_params.length() > 4 {
      [ptr_ty]
    } else {
      flat_params
    }
    let params : Array[@types.ValueType] = match func_type.result {
      Some(_) => lowered_params + [ptr_ty]
      None => lowered_params
    }
    let core_type : @types.FuncType = { params, results: [I32], }
    let async_state = state.async_state
    let caller_table = state.resource_table
    let host = fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      if !canon_may_leave[0] {
        trap_canon("cannot leave component instance")
      }
      let live_caller_table = registered_resource_table(
        async_state, caller_table,
      )
      fn finish_call(out : Array[@types.Value]) -> Array[@types.Value] {
        set_canon_debug_message("lower.async(func=\{func_idx})-> \{Repr(out)}")
        out
      }

      // Split core args into component params and optional return pointer.
      let mut retptr : Int64? = None
      let param_args : Array[@types.Value] = []
      match func_type.result {
        Some(_) => {
          if args.length() == 0 {
            trap_canon("missing retptr")
            return finish_call([I32(0)])
          }
          for i in 0..<(args.length() - 1) {
            param_args.push(args[i])
          }
          retptr = match args[args.length() - 1] {
            I32(n) => Some(n.to_int64() & 0xffffffffL)
            I64(n) => Some(n)
            _ => None
          }
        }
        None =>
          for a in args {
            param_args.push(a)
          }
      }
      let component_args = core_args_to_component(
        param_args,
        func_type.params,
        func_types,
        resources,
        store,
        live_caller_table,
        4,
        "async lower argument",
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          return finish_call([I32(0)])
        }
      }
      validate_lifted_arguments(
        func_type,
        component_args,
        func_types,
        async_state,
        live_caller_table.id,
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          return finish_call([I32(0)])
        }
      }
      let inst_id = match func {
        Host(_, _, _) => caller_table.id
        HostAsync(_, _, _) => caller_table.id
        Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
      }
      let caller_task_id = current_task_id(async_state)
      let meta_inst_id = match func {
        Host(_, _, _) => -1
        HostAsync(_, _, _) => -1
        _ => inst_id
      }
      // Backpressure is per async-lowered core function (not per component instance).
      let bp_key = ((caller_table.id.reinterpret_as_uint() * 65537U) ^
      func_idx.reinterpret_as_uint()).reinterpret_as_int()
      let inflight = match async_state.inflight_by_instance.get(bp_key) {
        Some(n) => n
        None => 0
      }
      let instance_backpressure = backpressure_value_for_instance(
        async_state, inst_id,
      )
      let entry_available = async_call_can_enter(func, async_state)
      let task : CallbackTask = {
        func,
        args: component_args,
        args_owner_component_id: [caller_table.id],
        started: [false],
        main_finished: [false],
        code: [0],
        waiting_set: [None],
        host_future: [None],
        cancelled: [false],
        continuation: [None],
      }
      let retp = match retptr {
        Some(p) => p
        None => 0
      }

      if instance_backpressure == 0 && inflight == 0 && entry_available {
        let is_callback = match func {
          Lifted(_, _ft, _res, _tys, _tbl, _may_enter, Some(_cb), _async_abi) =>
            true
          _ => false
        }
        if is_callback {
          // Try a handle-less initial step. If it exits immediately, we must return
          // RETURNED=2 without consuming the shared handle space (otherwise it would
          // perturb handle numbering observed by the core code; see empty-wait.wast).
          let tmp_task_id = alloc_canon_task_id(async_state)
          canon_in_handleless_step[0] = true
          init_task_meta(async_state, tmp_task_id, meta_inst_id, caller_task_id)
          push_canon_task(async_state, tmp_task_id, true)
          let step = step_task_once(task, store, live_caller_table, async_state) catch {
            e => {
              pop_task(async_state)
              canon_in_handleless_step[0] = false
              abort_task_children(async_state, tmp_task_id)
              retire_task(async_state, tmp_task_id)
              trap_canon(canon_err_message(e))
              return finish_call([I32(0)])
            }
          }
          pop_task(async_state)
          canon_in_handleless_step[0] = false
          if step == Done {
            if func_type.result is Some(_) && retptr is Some(p) {
              let vals = match take_task_result(async_state, tmp_task_id) {
                Some(v) => v
                None => []
              }
              let vals0 = transfer_results_if_needed(
                vals,
                func_type.result,
                func_types,
                async_state,
                inst_id,
                caller_table.id,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
              let core_vals = component_results_to_core(
                vals0,
                func_type,
                func_types,
                resources,
                store,
                Some(p),
                live_caller_table,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
              store_async_lower_result(
                require_memory(resources, store),
                p,
                core_vals,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
            }
            retire_task(async_state, tmp_task_id)
            return finish_call([I32(2)]) // RETURNED
          }

          // Some callback-style async functions publish their results early via `canon task.return`
          // and then continue running (e.g. stream producers). For async-lowering, return
          // RETURNED=2 immediately and keep the task alive as a detached background subtask so the
          // event loop can continue driving it (component-spec/async/partial-stream-copies.wast).
          if step != Done &&
            async_state.tasks.read_task_returned(tmp_task_id) is Some(true) {
            if retptr is Some(p) {
              let vals = match
                async_state.tasks.read_task_results(tmp_task_id) {
                Some(v) => v
                None => []
              }
              let out_vals = try {
                match func_type.result {
                  Some(rty) =>
                    if vals.length() > 0 {
                      [
                        clone_stream_future_value(
                          rty,
                          vals[0],
                          func_types,
                          async_state,
                          inst_id,
                          caller_table.id,
                        ),
                      ]
                    } else {
                      vals
                    }
                  None => vals
                }
              } catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
              let core_vals = component_results_to_core(
                out_vals,
                func_type,
                func_types,
                resources,
                store,
                Some(p),
                live_caller_table,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
              store_async_lower_result(
                require_memory(resources, store),
                p,
                core_vals,
              ) catch {
                e => {
                  trap_canon(canon_err_message(e))
                  return finish_call([I32(0)])
                }
              }
            }
            async_state.tasks.write_subtasks(tmp_task_id, {
              // Detached background task: no guest-visible waitable handle.
              id: 0,
              detached: true,
              phase: [Started],
              caller_table: live_caller_table,
              callee_instance_id: inst_id,
              bp_key,
              retptr: 0,
              mem_addr: resources.mem_addr,
              result_ty: None,
              types: func_types,
              resources,
              driver: CallbackLifted(task),
            })
            // `task.return` releases the callee's automatic-backpressure slot
            // even though the detached continuation still has work to do.
            async_state.inflight_by_instance.set(bp_key, 0)
            return finish_call([I32(2)]) // RETURNED
          }

          // Publish a guest handle for the existing stable task.
          let sub_id = alloc_shared_handle(async_state, caller_table.id)
          let sub_key = handle_key(caller_table.id, sub_id)
          async_state.tasks.bind_handle(tmp_task_id, sub_key)
          let st : Subtask = {
            id: sub_id,
            detached: false,
            phase: [Started],
            caller_table: live_caller_table,
            callee_instance_id: inst_id,
            bp_key,
            retptr: retp,
            mem_addr: resources.mem_addr,
            result_ty: func_type.result,
            types: func_types,
            resources,
            driver: CallbackLifted(task),
          }
          async_state.inflight_by_instance.set(
            bp_key,
            match func {
              HostAsync(_, _, _) => 0
              Lifted(_, _, _, _, _, _, Some(_), _) =>
                if task.started[0] {
                  0
                } else {
                  1
                }
              _ => 1
            },
          )
          async_state.tasks.write_subtasks(sub_key, st)
          return finish_call([I32((sub_id << 4) | 1)]) // STARTED
        }

        // Non-callback async lowering: do a handle-less initial step so the task can
        // register any pending waits (e.g. future.read/stream.read) before returning STARTED.
        // If it completes immediately, return RETURNED=2 without consuming the shared handle space.
        let tmp_task_id = alloc_canon_task_id(async_state)
        canon_in_handleless_step[0] = true
        init_task_meta(async_state, tmp_task_id, meta_inst_id, caller_task_id)
        push_canon_task(async_state, tmp_task_id, true)
        let step = step_task_once(task, store, live_caller_table, async_state) catch {
          e => {
            pop_task(async_state)
            canon_in_handleless_step[0] = false
            abort_task_children(async_state, tmp_task_id)
            retire_task(async_state, tmp_task_id)
            trap_canon(canon_err_message(e))
            return finish_call([I32(0)])
          }
        }
        pop_task(async_state)
        canon_in_handleless_step[0] = false
        if step == Done {
          if func_type.result is Some(_) && retptr is Some(p) {
            let vals = match take_task_result(async_state, tmp_task_id) {
              Some(v) => v
              None => []
            }
            let vals0 = transfer_results_if_needed(
              vals,
              func_type.result,
              func_types,
              async_state,
              inst_id,
              caller_table.id,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return finish_call([I32(0)])
              }
            }
            let core_vals = component_results_to_core(
              vals0,
              func_type,
              func_types,
              resources,
              store,
              Some(p),
              live_caller_table,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return finish_call([I32(0)])
              }
            }
            store_async_lower_result(
              require_memory(resources, store),
              p,
              core_vals,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return finish_call([I32(0)])
              }
            }
          }
          retire_task(async_state, tmp_task_id)
          return finish_call([I32(2)]) // RETURNED
        }
        let sub_id = alloc_shared_handle(async_state, caller_table.id)
        let sub_key = handle_key(caller_table.id, sub_id)
        async_state.tasks.bind_handle(tmp_task_id, sub_key)
        let st : Subtask = {
          id: sub_id,
          detached: false,
          phase: [Started],
          caller_table: live_caller_table,
          callee_instance_id: inst_id,
          bp_key,
          retptr: retp,
          mem_addr: resources.mem_addr,
          result_ty: func_type.result,
          types: func_types,
          resources,
          driver: CallbackLifted(task),
        }
        async_state.inflight_by_instance.set(
          bp_key,
          match func {
            HostAsync(_, _, _) => 0
            Lifted(_, _, _, _, _, _, Some(_), _) =>
              if task.started[0] {
                0
              } else {
                1
              }
            _ => 1
          },
        )
        async_state.tasks.write_subtasks(sub_key, st)
        finish_call([I32((sub_id << 4) | 1)]) // STARTED
      } else {
        // Backpressure/serialization: queue in STARTING state until this
        // async-lowered call becomes eligible to start.
        let sub_id = alloc_shared_handle(async_state, caller_table.id)
        let st : Subtask = {
          id: sub_id,
          detached: false,
          phase: [Starting],
          caller_table: live_caller_table,
          callee_instance_id: inst_id,
          bp_key,
          retptr: retp,
          mem_addr: resources.mem_addr,
          result_ty: func_type.result,
          types: func_types,
          resources,
          driver: CallbackLifted(task),
        }
        let sub_key = handle_key(caller_table.id, sub_id)
        let task_id = alloc_canon_task_id(async_state)
        async_state.tasks.bind_handle(task_id, sub_key)
        init_task_meta(async_state, task_id, meta_inst_id, caller_task_id)
        async_state.tasks.write_subtasks(sub_key, st)
        let q = match async_state.pending_by_instance.get(bp_key) {
          Some(xs) => xs
          None => []
        }
        q.push(sub_key)
        async_state.pending_by_instance.set(bp_key, q)
        finish_call([I32((sub_id << 4) | 0)]) // STARTING
      }
    }
    state.core_funcs.push(
      alloc_component_host_core_func(store, core_type, host),
    )
  } else {
    let core_type = core_func_type_from_component(
      func_type, func_types, mem_is_64,
    )
    let indirect_result = func_type.result is Some(result) &&
      core_types_for_valtype(result, func_types, mem_is_64, max_flat=2).length() >
      1
    let host = fn(
      args : Array[@types.Value],
    ) -> Array[@types.Value] raise @runtime.RuntimeError {
      if !canon_may_leave[0] {
        trap_canon("cannot leave component instance")
      }
      let async_state = state.async_state
      let caller_table = registered_resource_table(
        async_state,
        state.resource_table,
      )
      let outer_task_id = current_task_id(async_state)
      if func_type.is_async &&
        async_state.tasks.read_core_start_tasks(outer_task_id) is Some(_) {
        trap_canon("cannot block a synchronous task before returning")
        return []
      }
      // A resumed lower continues the existing task. Its handles have already
      // crossed the component boundary, so do not lift the original core args twice.
      let component_args = if func_type.is_async &&
        async_state.tasks.read_sync_lower_states(outer_task_id) is Some(_) {
        []
      } else {
        let param_args = if indirect_result {
          args[:args.length() - 1].to_owned()
        } else {
          args
        }
        let values = core_args_to_component(
          param_args,
          func_type.params,
          func_types,
          resources,
          store,
          caller_table,
          16,
          "sync lower argument",
          borrow_strings=match func {
            Lifted(core, ty, _, _, _, _, None, false) =>
              !ty.is_async && !core.may_suspend
            _ => false
          },
        ) catch {
          e => {
            trap_canon(canon_err_message(e))
            ([] : Array[ComponentValue])
          }
        }
        validate_lifted_arguments(
          func_type,
          values,
          func_types,
          async_state,
          caller_table.id,
        ) catch {
          e => {
            trap_canon(canon_err_message(e))
            return []
          }
        }
        values
      }
      let owner_component_id = caller_table.id
      let inst_id = match func {
        Host(_, _, _) => owner_component_id
        HostAsync(_, _, _) => owner_component_id
        Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
      }
      let meta_inst_id = match func {
        Host(_, _, _) => -1
        HostAsync(_, _, _) => -1
        _ => inst_id
      }
      fn cleanup_sync_lower_task(task_id : Int64) -> Unit {
        retire_task(async_state, task_id)
      }

      let results : Array[ComponentValue] = if func_type.is_async {
        // Sync-lowering an async component function must be cooperative:
        // treat YIELD/WAIT as restartable suspension points instead of busy looping.
        let st = match async_state.tasks.read_sync_lower_states(outer_task_id) {
          Some(s) => s
          None => {
            // Sync-lowering does not expose a guest-visible subtask handle, so do not
            // consume the shared handle space (which would perturb stream/future numbering
            // observed by component-spec/async tests).
            let inner_task_id = alloc_canon_task_id(async_state)
            let task : CallbackTask = {
              func,
              args: component_args,
              args_owner_component_id: [owner_component_id],
              started: [false],
              main_finished: [false],
              code: [0],
              waiting_set: [None],
              host_future: [None],
              cancelled: [false],
              continuation: [None],
            }
            init_task_meta(
              async_state, inner_task_id, meta_inst_id, outer_task_id,
            )
            let s : SyncLowerState = { task_id: inner_task_id, task, }
            async_state.tasks.write_sync_lower_states(outer_task_id, s)
            s
          }
        }

        // Drive at most one step, then cooperatively suspend.
        let can_block = async_state.task_can_block[0]
        let callee_instance_id = match st.task.func {
          Host(_, _, _) => state.resource_table.id
          HostAsync(_, _, _) => state.resource_table.id
          Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
        }
        push_canon_task(async_state, st.task_id, can_block)
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
          Lifted(_, _ft, _res, _tys, _tbl, _may_enter, Some(_cb), _async_abi) =>
            true
          _ => false
        }
        // Some callback-style async functions (notably stream producers) publish their
        // results via `canon task.return` and then continue running to drive the stream.
        // Sync-lowering must return the published result immediately and keep the task
        // alive as a detached background subtask, otherwise nested components can deadlock
        // (component-spec/async/zero-length.wast).
        if is_callback_task &&
          step != Done &&
          async_state.tasks.read_task_returned(st.task_id) is Some(true) &&
          async_state.tasks.read_task_results(st.task_id) is Some(vals) {
          // Promote the task to a detached background subtask so the event loop can
          // continue driving it after this sync-lowered call returns.
          // Prefer the owner recorded by `canon task.return` if present. This avoids
          // mis-attributing stream/future handles produced by nested components.
          let result_owner = match
            async_state.tasks.read_task_result_owner(st.task_id) {
            Some(o) => o
            None => callee_instance_id
          }
          let vals0 = try {
            match func_type.result {
              Some(rty) =>
                if vals.length() > 0 {
                  [
                    transfer_stream_future_value(
                      rty,
                      vals[0],
                      func_types,
                      async_state,
                      result_owner,
                      state.resource_table.id,
                    ),
                  ]
                } else {
                  vals
                }
              None => vals
            }
          } catch {
            e => {
              trap_canon(canon_err_message(e))
              return ([] : Array[@types.Value])
            }
          }
          async_state.tasks.write_subtasks(st.task_id, {
            // Detached background task: no guest-visible waitable handle.
            id: 0,
            detached: true,
            phase: [Started],
            caller_table: state.resource_table,
            callee_instance_id,
            bp_key: 0,
            retptr: 0,
            mem_addr: resources.mem_addr,
            result_ty: None,
            types: func_types,
            resources,
            driver: CallbackLifted(st.task),
          })
          async_state.tasks.clear_sync_lower_states(outer_task_id)

          let mut out_ptr : Int64? = None
          if func_type.result is Some(rty) {
            let flat = core_types_for_valtype(
              rty,
              func_types,
              mem_is_64,
              max_flat=2,
            ) catch {
              _ => []
            }
            if flat.length() > 1 {
              if args.length() == 0 {
                trap_canon("missing retptr")
              } else {
                out_ptr = match args[args.length() - 1] {
                  I32(n) => Some(n.to_int64() & 0xffffffffL)
                  I64(n) => Some(n)
                  _ => None
                }
              }
            }
          }
          let out = component_results_to_core(
            vals0, func_type, func_types, resources, store, out_ptr, caller_table,
          ) catch {
            e => {
              trap_canon(canon_err_message(e))
              ([] : Array[@types.Value])
            }
          }
          return out
        }
        match step {
          Done => {
            async_state.tasks.clear_sync_lower_states(outer_task_id)
            let vals = match take_task_result(async_state, st.task_id) {
              Some(v) => v
              None => []
            }
            // Sync-lowering crosses a component boundary (core -> component -> core). If the
            // component returned any stream/future readable handles, move them into the caller's
            // handle space before exposing the core i32 indices.
            let callee_instance_id = match st.task.func {
              Host(_, _, _) => state.resource_table.id
              HostAsync(_, _, _) => state.resource_table.id
              Lifted(_, _, _, _, callee_table, _, _, _) => callee_table.id
            }
            let result_owner = match
              async_state.tasks.read_task_result_owner(st.task_id) {
              Some(o) => o
              None => callee_instance_id
            }
            let vals0 = transfer_results_if_needed(
              vals,
              func_type.result,
              func_types,
              async_state,
              result_owner,
              state.resource_table.id,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return ([] : Array[@types.Value])
              }
            }
            cleanup_sync_lower_task(st.task_id)
            let mut out_ptr : Int64? = None
            match func_type.result {
              Some(rty) => {
                let flat = core_types_for_valtype(
                  rty,
                  func_types,
                  mem_is_64,
                  max_flat=2,
                ) catch {
                  _ => []
                }
                if flat.length() > 1 {
                  // Indirect results use the last core argument as retptr.
                  if args.length() == 0 {
                    trap_canon("missing retptr")
                  } else {
                    out_ptr = match args[args.length() - 1] {
                      I32(n) => Some(n.to_int64() & 0xffffffffL)
                      I64(n) => Some(n)
                      _ => None
                    }
                  }
                }
              }
              None => ()
            }
            let out = component_results_to_core(
              vals0, func_type, func_types, resources, store, out_ptr, caller_table,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                ([] : Array[@types.Value])
              }
            }
            return out
          }
          _ =>
            if canon_in_prerun[0] {
              async_state.tasks.clear_sync_lower_states(outer_task_id)
              cleanup_sync_lower_task(st.task_id)
              trap_canon("prerun blocked")
              ([] : Array[ComponentValue])
            } else if !can_block {
              cancel_callback_task(st.task)
              if st.task.waiting_set[0] is Some(ws) &&
                async_state.waitable_sets.get(ws) is Some(set) {
                set.waiters[0] -= 1
                st.task.waiting_set[0] = None
              }
              async_state.tasks.clear_sync_lower_states(outer_task_id)
              cleanup_sync_lower_task(st.task_id)
              trap_canon("cannot block a synchronous task before returning")
              ([] : Array[ComponentValue])
            } else {
              match st.task.waiting_set[0] {
                Some(ws) => canon_suspend[0] = Some(Wait(ws))
                None => canon_suspend[0] = Some(Yield)
              }
              raise Unreachable
            }
        }
      } else {
        call_component_func(
          func, component_args, store, caller_table, async_state,
        ) catch {
          e => {
            trap_canon(canon_core_boundary_error_message(e))
            ([] : Array[ComponentValue])
          }
        }
      }
      let mut out_ptr : Int64? = None
      if func_type.result is Some(rty) {
        let flat = core_types_for_valtype(
          rty,
          func_types,
          mem_is_64,
          max_flat=2,
        ) catch {
          _ => []
        }
        if flat.length() > 1 {
          // Indirect results use the last core argument as retptr.
          if args.length() == 0 {
            trap_canon("missing retptr")
          } else {
            out_ptr = match args[args.length() - 1] {
              I32(n) => Some(n.to_int64() & 0xffffffffL)
              I64(n) => Some(n)
              _ => None
            }
          }
        }
      }
      let out = component_results_to_core(
        results, func_type, func_types, resources, store, out_ptr, caller_table,
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          ([] : Array[@types.Value])
        }
      }
      out
    }
    let func_addr = store.alloc_host_func(host, func_type=core_type, type_idx=0) catch {
      error => raise CoreModuleInstantiateError(error.to_string())
    }
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
      elem_values: [],
      elem_segments: [],
      data_segments: [],
      dropped_elems: [],
      dropped_datas: [],
    }
    state.core_funcs.push({
      instance,
      func_idx: 0,
      engine: interpreter_core_execution_engine(),
      debug_name: None,
      may_suspend: func_type.is_async,
      // Native activations may call this host adapter and nest another core
      // activation through the Store-scoped activation chain.
      native_eligible: true,
    })
  }
}
