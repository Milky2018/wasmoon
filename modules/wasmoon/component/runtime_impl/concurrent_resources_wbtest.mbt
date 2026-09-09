///|
test "concurrent capacity bounds growth and reuses freed slots after shrinking" {
  let pool = ConcurrentResources::new()
  pool.set_capacity(0U)
  let full = try {
    pool.allocate() |> ignore
    false
  } catch {
    _ => true
  }
  inspect(full, content="true")
  pool.set_capacity(1U)
  let first = pool.allocate()
  let full = try {
    pool.allocate() |> ignore
    false
  } catch {
    _ => true
  }
  inspect(full, content="true")
  pool.set_capacity(0U)
  first.release()
  first.release()
  let reused = pool.allocate()
  inspect(reused.slot == first.slot, content="true")
  first.release()
  inspect(pool.live.val, content="1")
  reused.release()
  inspect(pool.live.val, content="0")
  pool.set_capacity(100U)
  for _ in 0..<1000 {
    let lease = pool.allocate()
    lease.release()
  }
  inspect(pool.allocated.val, content="1")
  inspect(pool.live.val, content="0")
}

///|
test "task reservations roll back and retirement returns both task and thread slots" {
  let state = AsyncState(StreamTable())
  let pool = state.concurrent_resources
  pool.set_capacity(1U)
  let full = try {
    alloc_task_id(state) |> ignore
    false
  } catch {
    _ => true
  }
  inspect(full, content="true")
  inspect(pool.live.val, content="0")
  pool.set_capacity(2U)
  for _ in 0..<1000 {
    let task = alloc_task_id(state)
    inspect(pool.live.val, content="2")
    retire_task(state, task)
  }
  inspect(pool.live.val, content="0")
  inspect(pool.allocated.val, content="2")
}

///|
test "typed concurrent maps share capacity and updates do not allocate" {
  let pool = ConcurrentResources::new()
  pool.set_capacity(1U)
  let first : ConcurrentMap[Int, String] = ConcurrentMap::new(pool)
  let second : ConcurrentMap[String, Int] = ConcurrentMap::new(pool)
  first.set(0, "first")
  let full = try {
    second.set("second", 2)
    false
  } catch {
    _ => true
  }
  inspect(full, content="true")
  first.replace(0, "updated")
  debug_inspect(first.get(0), content="Some(\"updated\")")
  inspect(pool.live.val, content="1")
  first.remove(0)
  second.set("second", 2)
  second.clear()
  inspect(pool.live.val, content="0")
  inspect(pool.allocated.val, content="1")
}

///|
test "host stream and future allocation failures return slots and handles" {
  for future in [false, true] {
    let runtime = HostRuntimeState()
    let pool = runtime.async_state.concurrent_resources
    runtime.set_max_concurrent_resources(1U)
    let failed = try {
      if future {
        runtime.new_host_value_future(
          runtime.resource_table,
          Prim(U32),
          [],
          U32(7),
        )
        |> ignore
      } else {
        runtime.new_host_byte_stream(runtime.resource_table, b"value") |> ignore
      }
      false
    } catch {
      _ => true
    }
    inspect(failed, content="true")
    inspect(pool.live.val, content="0")
    runtime.set_max_concurrent_resources(2U)
    let handle = if future {
      runtime.new_host_value_future(
        runtime.resource_table,
        Prim(U32),
        [],
        U32(7),
      )
    } else {
      runtime.new_host_byte_stream(runtime.resource_table, b"value")
    }
    inspect(handle, content="1")
    if future {
      runtime.drop_host_readable_future(runtime.resource_table, handle)
    } else {
      runtime.drop_host_readable_stream(runtime.resource_table, handle)
    }
    inspect(pool.live.val, content="0")
  }
}

///|
test "linker close cancels host producers and releases every concurrent owner" {
  let linker = ComponentLinker()
  let runtime = linker.host_runtime_state()
  let pool = runtime.async_state.concurrent_resources
  let cancelled : Array[String] = []
  runtime.new_host_value_stream_source(
    runtime.resource_table,
    Prim(U32),
    [],
    fn(_) { Pending },
    fn() { cancelled.push("stream") },
  )
  |> ignore
  runtime.new_host_value_future_source(
    runtime.resource_table,
    Prim(U32),
    [],
    fn() { Pending },
    fn() { cancelled.push("future") },
  )
  |> ignore
  runtime.resource_table.alloc_error_context("message") |> ignore
  runtime.async_state.waitable_sets.set(1L, {
    id: 1,
    members: Map([]),
    queue: [],
    waiters: [0],
  })
  inspect(pool.live.val, content="6")
  linker.close()
  linker.close()
  inspect(pool.live.val, content="0")
  debug_inspect(cancelled, content="[\"stream\", \"future\"]")
  let terminal = try {
    pool.allocate() |> ignore
    false
  } catch {
    Cancelled => true
    _ => false
  }
  inspect(terminal, content="true")
}

///|
test "explicit thread metadata is charged by its owning thread entry" {
  let state = AsyncState(StreamTable())
  state.concurrent_resources.set_capacity(0U)
  let record = state.tasks.allocate(thread_metadata=true)
  inspect(state.concurrent_resources.live.val, content="0")
  retire_task(state, record)
}
