///|
/// Canonical section instantiation helpers.
/// (group: thread)

///|
fn current_thread_handle_opt(
  async_state : AsyncState,
  owner_component_id : Int,
  task_id : Int64,
) -> Int? {
  match async_state.task_thread.get(task_id) {
    Some(m) => m.get(owner_component_id)
    None => None
  }
}

///|
fn current_thread_info(
  async_state : AsyncState,
  owner_component_id : Int,
) -> (Int64, Int, Int64, Bool) raise ComponentRuntimeError {
  let task_id = current_task_id(async_state)
  ensure_task_thread(async_state, owner_component_id, task_id)
  let current_handle = match
    current_thread_handle_opt(async_state, owner_component_id, task_id) {
    Some(h) => h
    None => raise CanonCallError("no current thread")
  }
  let key = handle_key(owner_component_id, current_handle)
  match async_state.threads.get(key) {
    Some(t) =>
      if t.task_id == task_id {
        (task_id, current_handle, t.parent_task_id, true)
      } else {
        (task_id, current_handle, task_id, false)
      }
    None => (task_id, current_handle, task_id, false)
  }
}

///|
fn mark_main_scheduled(async_state : AsyncState, root_task_id : Int64) -> Unit {
  async_state.main_thread_scheduled.set(root_task_id, true)
}

///|
fn consume_main_scheduled(
  async_state : AsyncState,
  root_task_id : Int64,
) -> Bool {
  let scheduled = async_state.main_thread_scheduled.get(root_task_id)
    is Some(true)
  if scheduled {
    async_state.main_thread_scheduled.remove(root_task_id)
  }
  scheduled
}

///|
fn remove_from_runnable_queue(
  async_state : AsyncState,
  root_task_id : Int64,
  handle : Int,
) -> Unit {
  match async_state.thread_runnable.get(root_task_id) {
    Some(q) => {
      let mut i = 0
      while i < q.length() {
        if q[i] == handle {
          q.remove(i) |> ignore
        } else {
          i = i + 1
        }
      }
    }
    None => ()
  }
}

///|
fn schedule_explicit_thread(
  async_state : AsyncState,
  owner_component_id : Int,
  root_task_id : Int64,
  handle : Int,
) -> Bool {
  let key = handle_key(owner_component_id, handle)
  match async_state.threads.get(key) {
    Some(t) => {
      if t.parent_task_id != root_task_id || t.phase[0] == Completed {
        return false
      }
      if t.scheduled[0] {
        return true
      }
      let q = match async_state.thread_runnable.get(root_task_id) {
        Some(xs) => xs
        None => {
          let xs : Array[Int] = []
          async_state.thread_runnable.set(root_task_id, xs)
          xs
        }
      }
      t.scheduled[0] = true
      q.push(handle)
      true
    }
    None => false
  }
}

///|
fn pop_runnable_explicit_thread(
  async_state : AsyncState,
  owner_component_id : Int,
  root_task_id : Int64,
) -> Int? {
  let q = match async_state.thread_runnable.get(root_task_id) {
    Some(xs) => xs
    None => return None
  }
  while q.length() > 0 {
    let h = q[0]
    q.remove(0) |> ignore
    let key = handle_key(owner_component_id, h)
    match async_state.threads.get(key) {
      Some(t) => {
        t.scheduled[0] = false
        if t.phase[0] != Completed && t.parent_task_id == root_task_id {
          return Some(h)
        }
      }
      None => ()
    }
  }
  None
}

///|
fn wake_ready_waiting_threads(
  async_state : AsyncState,
  owner_component_id : Int,
  root_task_id : Int64,
) -> Unit {
  let to_wake : Array[Int] = []
  for kv in async_state.threads.iter() {
    let (_k, t) = kv
    if t.owner_component_id != owner_component_id ||
      t.parent_task_id != root_task_id {
      continue
    }
    match t.waiting_ws[0] {
      Some(ws) =>
        if waitable_set_has_event(async_state, ws) {
          t.waiting_ws[0] = None
          to_wake.push(t.handle)
        }
      None => ()
    }
  }
  for h in to_wake {
    schedule_explicit_thread(async_state, owner_component_id, root_task_id, h)
    |> ignore
  }
}

///|
fn cleanup_thread_task(async_state : AsyncState, task_id : Int64) -> Unit {
  async_state.task_results.remove(task_id)
  async_state.task_result_owner.remove(task_id)
  async_state.task_returned.remove(task_id)
  async_state.task_self_cancelled.remove(task_id)
  async_state.task_cancelled.remove(task_id)
  async_state.task_contexts.remove(task_id)
  drop_task_thread(async_state, task_id)
  remove_task_meta(async_state, task_id)
  async_state.yield_suspended.remove(task_id)
  async_state.waiting_ws.remove(task_id)
  async_state.sync_lower_states.remove(task_id)
}

///|
fn run_explicit_thread_once(
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
  root_task_id : Int64,
  handle : Int,
) -> Unit raise ComponentRuntimeError {
  let key = handle_key(owner_component_id, handle)
  let t = match async_state.threads.get(key) {
    Some(t) => t
    None => raise CanonCallError("unknown thread handle index \{handle}")
  }
  if t.parent_task_id != root_task_id {
    raise CanonCallError("unknown thread handle index \{handle}")
  }
  if t.phase[0] == Completed {
    return
  }

  remove_from_runnable_queue(async_state, root_task_id, handle)
  t.scheduled[0] = false

  match t.waiting_ws[0] {
    Some(ws) => {
      if !waitable_set_has_event(async_state, ws) {
        return
      }
      t.waiting_ws[0] = None
    }
    None => ()
  }

  push_task(async_state, t.task_id, true)
  let outcome = try {
    match t.continuation[0] {
      Some(continuation) => {
        t.continuation[0] = None
        continuation.continue_execution()
      }
      None =>
        call_core_func_outcome(store, t.start_func, [I32(t.context)], Stackful)
    }
  } catch {
    error => {
      pop_task(async_state)
      raise error
    }
  }
  pop_task(async_state)

  match outcome {
    Returned(_) => {
      t.phase[0] = Completed
      t.waiting_ws[0] = None
      cleanup_thread_task(async_state, t.task_id)
    }
    Suspended(reason, continuation) => {
      t.continuation[0] = Some(continuation)
      t.phase[0] = Suspended
      t.waiting_ws[0] = match reason {
        Yield => None
        Wait(waitable_set) => Some(waitable_set)
      }
    }
  }
}

///|
fn dispatch_until_main_scheduled(
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
  root_task_id : Int64,
) -> Bool raise ComponentRuntimeError {
  let mut fuel = 100000
  while fuel > 0 {
    wake_ready_waiting_threads(async_state, owner_component_id, root_task_id)
    if consume_main_scheduled(async_state, root_task_id) {
      return true
    }
    let next = pop_runnable_explicit_thread(
      async_state, owner_component_id, root_task_id,
    )
    match next {
      Some(h) =>
        run_explicit_thread_once(
          async_state, store, owner_component_id, root_task_id, h,
        )
      None => return false
    }
    fuel = fuel - 1
  }
  raise CanonCallError(
    "wasm trap: deadlock detected: event loop cannot make further progress",
  )
}

///|
fn schedule_thread_or_main(
  async_state : AsyncState,
  owner_component_id : Int,
  root_task_id : Int64,
  handle : Int,
) -> Bool {
  ensure_task_thread(async_state, owner_component_id, root_task_id)
  let main_handle = current_thread_handle_opt(
    async_state, owner_component_id, root_task_id,
  )
  match main_handle {
    Some(h) =>
      if h == handle {
        mark_main_scheduled(async_state, root_task_id)
        true
      } else {
        schedule_explicit_thread(
          async_state, owner_component_id, root_task_id, handle,
        )
      }
    None =>
      schedule_explicit_thread(
        async_state, owner_component_id, root_task_id, handle,
      )
  }
}

///|
fn maybe_consume_cancelled(
  async_state : AsyncState,
  task_id : Int64,
  cancellable : Bool,
) -> Bool {
  if !cancellable {
    return false
  }
  if async_state.task_cancelled.get(task_id) is Some(true) {
    async_state.task_cancelled.remove(task_id)
    return true
  }
  false
}

///|
fn run_main_target_once(
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
  root_task_id : Int64,
  target : Int,
) -> Unit raise ComponentRuntimeError {
  if !schedule_thread_or_main(
      async_state, owner_component_id, root_task_id, target,
    ) {
    raise CanonCallError("unknown thread handle index \{target}")
  }
  let key = handle_key(owner_component_id, target)
  if async_state.threads.get(key) is Some(_) {
    run_explicit_thread_once(
      async_state, store, owner_component_id, root_task_id, target,
    )
  }
}

///|
fn execute_thread_suspension_intrinsic(
  cancellable : Bool,
  schedule_current : Bool,
  target : Int?,
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
) -> Array[@types.Value] raise @runtime.RuntimeError {
  let (task_id, current_handle, root_task_id, is_explicit) = current_thread_info(
    async_state, owner_component_id,
  ) catch {
    e => {
      trap_canon(canon_err_message(e))
      return [I32(0)]
    }
  }

  let resuming = async_state.yield_suspended.get(task_id) is Some(true)

  if is_explicit {
    if maybe_consume_cancelled(async_state, task_id, cancellable) {
      async_state.yield_suspended.remove(task_id)
      return [I32(1)]
    }

    if resuming {
      async_state.yield_suspended.remove(task_id)
      return [I32(0)]
    }

    match target {
      Some(h) =>
        if !schedule_thread_or_main(
            async_state, owner_component_id, root_task_id, h,
          ) {
          trap_canon("unknown thread handle index \{h}")
          return [I32(0)]
        }
      None => ()
    }

    if schedule_current {
      schedule_explicit_thread(
        async_state, owner_component_id, root_task_id, current_handle,
      )
      |> ignore
    }

    async_state.yield_suspended.set(task_id, true)
    canon_suspend[0] = Some(Yield)
    raise Unreachable
  }

  // Implicit `thread.yield` is modeled as cooperative suspension. Resuming
  // retries this host instruction once and then continues at its successor.
  if maybe_consume_cancelled(async_state, task_id, cancellable) {
    async_state.yield_suspended.remove(task_id)
    return [I32(1)]
  }

  if resuming {
    async_state.yield_suspended.remove(task_id)
    return [I32(0)]
  }

  if schedule_current {
    mark_main_scheduled(async_state, root_task_id)
  }

  match target {
    Some(h) => {
      run_main_target_once(
        async_state, store, owner_component_id, root_task_id, h,
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          return [I32(0)]
        }
      }
      if schedule_current {
        consume_main_scheduled(async_state, root_task_id) |> ignore
        return [I32(0)]
      }
      let resumed = dispatch_until_main_scheduled(
        async_state, store, owner_component_id, root_task_id,
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          return [I32(0)]
        }
      }
      if !resumed {
        if !async_state.task_can_block[0] {
          trap_canon("cannot block a synchronous task before returning")
        } else {
          trap_canon(
            "wasm trap: deadlock detected: event loop cannot make further progress",
          )
        }
        return [I32(0)]
      }
      [I32(0)]
    }
    None => {
      if schedule_current {
        wake_ready_waiting_threads(
          async_state, owner_component_id, root_task_id,
        )
        let mut ran_explicit = false
        match
          pop_runnable_explicit_thread(
            async_state, owner_component_id, root_task_id,
          ) {
          Some(h) => {
            run_explicit_thread_once(
              async_state, store, owner_component_id, root_task_id, h,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return [I32(0)]
              }
            }
            ran_explicit = true
          }
          None => ()
        }
        consume_main_scheduled(async_state, root_task_id) |> ignore
        if ran_explicit {
          return [I32(0)]
        }
        if !async_state.task_can_block[0] {
          return [I32(0)]
        }
        async_state.yield_suspended.set(task_id, true)
        canon_suspend[0] = Some(Yield)
        raise Unreachable
      }
      let resumed = dispatch_until_main_scheduled(
        async_state, store, owner_component_id, root_task_id,
      ) catch {
        e => {
          trap_canon(canon_err_message(e))
          return [I32(0)]
        }
      }
      if !resumed {
        if !async_state.task_can_block[0] {
          trap_canon("cannot block a synchronous task before returning")
        } else {
          trap_canon(
            "wasm trap: deadlock detected: event loop cannot make further progress",
          )
        }
        return [I32(0)]
      }
      [I32(0)]
    }
  }
}

///|
fn resolve_start_core_func(
  store : @runtime.Store,
  table_addr : Int,
  start_func_idx : Int,
  engine : CoreExecutionEngine,
) -> CoreFuncRef raise ComponentRuntimeError {
  let table = store.get_table(table_addr) catch {
    e => raise CanonCallError(e.to_string())
  }
  let v = table.get(start_func_idx) catch {
    e => raise CanonCallError(e.to_string())
  }
  let func_addr = match v {
    FuncRef(addr) => addr
    _ => raise CanonCallError("thread start function is not a funcref")
  }
  let owner = match store.get_func_owner(func_addr) {
    Some(inst) => inst
    None => raise CanonCallError("unknown thread start function")
  }
  let mut func_idx = -1
  for i in 0..<owner.func_addrs.length() {
    if owner.func_addrs[i] == func_addr {
      func_idx = i
      break
    }
  }
  if func_idx < 0 {
    raise CanonCallError("unknown thread start function")
  }
  {
    instance: owner,
    func_idx,
    engine,
    may_suspend: true,
    native_eligible: false,
  }
}

///|
fn instantiate_canon_thread_index(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    ensure_task_thread(async_state, owner_component_id, task_id)
    match current_thread_handle_opt(async_state, owner_component_id, task_id) {
      Some(h) => [I32(h)]
      None => {
        trap_canon("no current thread")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_yield(
  cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    execute_thread_suspension_intrinsic(
      cancellable,
      true,
      None,
      async_state,
      store,
      owner_component_id,
    )
  }
  state.core_funcs.push(
    alloc_host_core_func(store, core_type, host, may_suspend=true),
  )
}

///|
fn instantiate_canon_thread_yield_then_resume(
  cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let target = match args {
      [I32(handle)] => handle
      _ => {
        trap_canon("type mismatch")
        return [I32(0)]
      }
    }
    execute_thread_suspension_intrinsic(
      cancellable,
      true,
      Some(target),
      async_state,
      store,
      owner_component_id,
    )
  }
  state.core_funcs.push(
    alloc_host_core_func(store, core_type, host, may_suspend=true),
  )
}

///|
fn instantiate_canon_thread_suspend_then_resume(
  cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let target = match args {
      [I32(handle)] => handle
      _ => {
        trap_canon("type mismatch")
        return [I32(0)]
      }
    }
    execute_thread_suspension_intrinsic(
      cancellable,
      false,
      Some(target),
      async_state,
      store,
      owner_component_id,
    )
  }
  state.core_funcs.push(
    alloc_host_core_func(store, core_type, host, may_suspend=true),
  )
}

///|
fn instantiate_unsupported_thread_promotion(
  operation : String,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    trap_canon("\{operation} is not implemented")
    [I32(0)]
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_suspend_then_promote(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  instantiate_unsupported_thread_promotion(
    "thread.suspend-then-promote", state, store,
  )
}

///|
fn instantiate_canon_thread_yield_then_promote(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  instantiate_unsupported_thread_promotion(
    "thread.yield-then-promote", state, store,
  )
}

///|
fn instantiate_canon_thread_resume_later(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let target = match args {
      [I32(h)] => h
      _ => {
        trap_canon("type mismatch")
        return []
      }
    }
    let (_task_id, _current_handle, root_task_id, _is_explicit) = current_thread_info(
      async_state, owner_component_id,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return []
      }
    }
    if !schedule_thread_or_main(
        async_state, owner_component_id, root_task_id, target,
      ) {
      trap_canon("unknown thread handle index \{target}")
      return []
    }
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_suspend(
  cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    execute_thread_suspension_intrinsic(
      cancellable,
      false,
      None,
      async_state,
      store,
      owner_component_id,
    )
  }
  state.core_funcs.push(
    alloc_host_core_func(store, core_type, host, may_suspend=true),
  )
}

///|
fn instantiate_canon_thread_new_indirect(
  _type_idx : Int,
  table_idx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let table_addr = if table_idx >= 0 && table_idx < state.core_tables.length() {
    Some(state.core_tables[table_idx])
  } else {
    None
  }
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let (start_idx, context) = match args {
      [I32(fi), I32(ctx)] => (fi, ctx)
      _ => {
        trap_canon("type mismatch")
        return [I32(0)]
      }
    }
    let table_addr = match table_addr {
      Some(addr) => addr
      None => {
        trap_canon("invalid core table index \{table_idx}")
        return [I32(0)]
      }
    }
    let start_func = resolve_start_core_func(
      store,
      table_addr,
      start_idx,
      async_state.core_engine,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return [I32(0)]
      }
    }

    let (_task_id, _current_handle, root_task_id, _is_explicit) = current_thread_info(
      async_state, owner_component_id,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return [I32(0)]
      }
    }

    let id = alloc_shared_handle(async_state, owner_component_id)
    let thread_task_id = alloc_task_id(async_state)
    init_task_meta(
      async_state, thread_task_id, owner_component_id, root_task_id,
    )
    let per_task : Map[Int, Int] = Map([])
    per_task.set(owner_component_id, id)
    async_state.task_thread.set(thread_task_id, per_task)

    async_state.threads.set(handle_key(owner_component_id, id), {
      owner_component_id,
      handle: id,
      parent_task_id: root_task_id,
      task_id: thread_task_id,
      start_func,
      context,
      phase: [NotStarted],
      scheduled: [false],
      waiting_ws: [None],
      continuation: [None],
    })

    [I32(id)]
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
