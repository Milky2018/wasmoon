///|
/// Give every synchronous lift its own logical task and context slots,
/// including a nested lift that needs no canonical value conversion.
fn[T] with_sync_lift_task(
  state : AsyncState,
  callee_id : Int32,
  func : ComponentFunc,
  invoke : () -> T raise ComponentRuntimeError,
) -> T raise ComponentRuntimeError {
  let caller_task_id = current_task_id(state)
  let task_id = alloc_task_id(state)
  init_task_meta(state, task_id, callee_id, caller_task_id)
  install_task_return_contract(state, task_id, func)
  push_task(state, task_id, false)
  defer {
    pop_task(state)
    retire_task(state, task_id)
  }
  errdefer abort_task_children(state, task_id)
  invoke()
}

///|
fn invoke_sync_lift_core(
  state : AsyncState,
  store : @runtime.Store,
  entry : ComponentInstanceEntryState,
  core : CoreFuncRef,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  let previous_can_block = state.task_can_block[0]
  state.task_can_block[0] = false
  defer {
    state.task_can_block[0] = previous_can_block
  }
  // A synchronous type can still reach a suspending canonical import.
  if core.may_suspend {
    drive_core_to_completion(
      state,
      store,
      call_core_func_guarded_outcome(store, entry, core, args, Stackful),
    )
  } else {
    call_core_func_guarded(store, entry, core, args)
  }
}

///|
fn scalar_canon_resources(resources : CanonResources) -> Bool {
  resources.mem_addr is None &&
  resources.realloc is None &&
  resources.post_return is None
}

///|
fn scalar_canon_signature_matches(
  ty : FuncType,
  args : Array[@types.Value],
) -> Bool {
  if ty.is_async || args.length() != ty.params.length() || args.length() > 16 {
    return false
  }
  for i, param in ty.params {
    match (param.ty, args[i]) {
      (Prim(S32 | U32), I32(_)) | (Prim(S64 | U64), I64(_)) => ()
      _ => return false
    }
  }
  ty.result is (None | Some(Prim(S32 | U32 | S64 | U64)))
}

///|
/// These full-width integers cross the canonical boundary as identical Core
/// bits. Resource transfers, validation of narrower values and memory-backed
/// arguments keep the ordinary adapter. Invoke through the existing engine
/// and give it the same owned argument/result boundaries.
fn call_scalar_canon_adapter(
  func : ComponentFunc,
  args : Array[@types.Value],
  lower_resources : CanonResources,
  store : @runtime.Store,
  caller_table : ResourceTable,
  state : AsyncState,
) -> Array[@types.Value] raise ComponentRuntimeError {
  guard func
    is Lifted(core, ty, lift_resources, types, callee_table, entry, None, false) else {
    raise CanonCallError("expected synchronous scalar lift")
  }
  with_sync_lift_task(state, callee_table.id, func, fn() raise ComponentRuntimeError {
    let results = invoke_sync_lift_core(state, store, entry, core, args.copy())
    match (ty.result, results) {
      (None, _) => []
      (Some(Prim(S32 | U32)), [I32(_)]) | (Some(Prim(S64 | U64)), [I64(_)]) =>
        results.copy()
      _ => {
        // Preserve the ordinary diagnostics for custom core engines that
        // return an unexpected value without repeating the guest call.
        let values = core_results_to_component(
          results, ty, types, lift_resources, store, callee_table,
        )
        component_results_to_core(
          values,
          ty,
          types,
          lower_resources,
          store,
          None,
          caller_table,
        )
      }
    }
  }) catch {
    UncaughtWasmException =>
      raise CanonCallError("uncaught exception propagated out of component")
    error => raise error
  }
}
