///|
struct HttpInvocation {
  invocation : @runtime_impl.ComponentInvocation
  mut done : Bool
  result : Ref[
    Result[
      Array[@runtime_impl.ComponentValue],
      @runtime_impl.ComponentRuntimeError,
    ]?,
  ]
}

///|
async fn HttpHost::drive(self : HttpHost) -> Unit {
  let mut budget = 0
  while true {
    let mut progressed = self.poll()
    for call in self.pending {
      if call.done {
        continue
      }
      try call.invocation.step() catch {
        error => {
          if call.result.val is Some(Ok(_)) {
            raise error
          }
          call.result.val = Some(Err(error))
          call.done = true
          progressed = true
        }
      } noraise {
        StepReady(values) => {
          call.result.val = Some(Ok(values))
          call.done = true
          progressed = true
        }
        StepProgressed => progressed = true
        StepBlocked => ()
      }
      if call.result.val is None &&
        call.invocation.published_result() is Some(values) {
        call.result.val = Some(Ok(values))
        progressed = true
      }
    }
    let pending = self.pending.filter(fn(call) { !call.done })
    self.pending.clear()
    self.pending.append(pending)
    if @runtime_impl.progress_one_subtask_intrinsic(
        self.runtime.async_state(),
        self.linker.get_store(),
      ) {
      progressed = true
    }
    if progressed {
      self.wake.broadcast()
      budget += 1
      if budget >= 64 {
        budget = 0
        @async.pause()
      }
    } else {
      budget = 0
      self.wake.wait()
    }
  }
}

///|
/// Run HTTP operations in a structured task scope. Cancellation joins network
/// tasks before returning; the linker still belongs to the embedding.
pub async fn[T] HttpHost::run(self : HttpHost, action : async () -> T) -> T {
  if self.spawn.val is Some(_) {
    raise @runtime_impl.HostCallError("HTTP host is already running")
  }
  defer {
    for call in self.pending {
      call.invocation.cancel()
    }
    self.pending.clear()
    for body in self.bodies {
      body.cancelled.val = true
    }
    (self.poll() catch { _ => false }) |> ignore
  }
  @async.with_task_group(async fn(group) {
    self.spawn.val = Some(fn(job) { group.spawn(job, no_wait=true) })
    defer {
      self.spawn.val = None
    }
    let driver = group.spawn(async fn() { self.drive() })
    defer driver.cancel()
    action()
  })
}

///|
fn HttpHost::schedule(
  self : HttpHost,
  instance : @runtime_impl.ComponentInstance,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
) -> HttpInvocation raise @runtime_impl.ComponentRuntimeError {
  let call = {
    done: false,
    invocation: instance.start_exported_func(
      name,
      args,
      caller_table=self.runtime.resource_table(),
    ),
    result: Ref(None),
  }
  self.pending.push(call)
  self.wake.broadcast()
  call
}

///|
pub async fn HttpHost::invoke(
  self : HttpHost,
  instance : @runtime_impl.ComponentInstance,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
) -> Array[@runtime_impl.ComponentValue] {
  let call = self.schedule(instance, name, args)
  defer (if call.result.val is None { call.invocation.cancel() })
  while true {
    match call.result.val {
      Some(Ok(values)) => return values
      Some(Err(error)) => raise error
      None => self.wake.wait()
    }
  }
  abort("unreachable")
}

///|
/// Provide the service world's base imports. stdin is always EOF; output is
/// supplied by async writers (process stdout/stderr by default). Timers and HTTP
/// share the same async reactor.
pub fn HttpHost::add_service_base(
  self : HttpHost,
  ctx : @wasi_component.WasiComponentCtx,
  stdout? : &@io.Writer = @stdio.stdout,
  stderr? : &@io.Writer = @stdio.stderr,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let base = @wasi_component.WasiComponentHost(self.linker, ctx)
  base.add_preview2_cli_clocks_random()
  base.add_preview2_io()
  base.add_preview3_clocks_random(wait_until=deadline => {
    guard self.spawn.val is Some(spawn) else {
      raise HostCallError("HTTP host must be running before a clock wait")
    }
    let ready = Ref(false)
    let wake = self.wake
    let task = spawn(async fn() {
      while true {
        let remaining = deadline - @wasi.native_clock_gettime_monotonic()
        if remaining <= 0L {
          break
        }
        let millis = Int64::min(remaining / 1000000L + 1L, 2147483647L).to_int()
        @async.sleep(millis)
      }
      ready.val = true
      wake.broadcast()
    })
    HostFuture(() => if ready.val { Ready([]) } else { Pending }, () => {
      task.cancel()
    })
  })
  self.add_service_stdio(stdout, stderr)
}
