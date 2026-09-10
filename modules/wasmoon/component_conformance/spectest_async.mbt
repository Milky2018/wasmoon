///|
priv struct SpectestYield {
  mut ready : Bool
  mut cancelled : Bool
}

///|
fn wake_spectest_yields(queue : Array[SpectestYield]) -> Bool {
  let mut progressed = false
  for pending in queue {
    if !pending.cancelled {
      pending.ready = true
      progressed = true
    }
  }
  queue.clear()
  progressed
}

///|
// The pinned Wasmtime spectest host yields once before returning these values.
fn make_spectest_slow_func(
  echo : Bool,
  queue : Array[SpectestYield],
) -> @runtime_impl.ComponentFunc {
  let func_type : @component_types.FuncType = {
    is_async: true,
    params: if echo {
      [{ label: "val", ty: Prim(U32), }]
    } else {
      []
    },
    result: Some(if echo { Prim(U32) } else { Prim(S32) }),
  }
  HostAsync(func_type, [], fn(
    args,
    _table,
  ) raise @runtime_impl.ComponentRuntimeError {
    let values : Array[@runtime_impl.ComponentValue] = match (echo, args) {
      (true, [U32(value)]) => [U32(value)]
      (false, []) => [S32(2)]
      _ => raise HostCallError("argument type mismatch")
    }
    let pending : SpectestYield = { ready: false, cancelled: false, }
    queue.push(pending)
    HostFuture(
      fn() {
        if pending.ready && !pending.cancelled {
          Ready(values)
        } else {
          Pending
        }
      },
      fn() { pending.cancelled = true },
    )
  })
}
