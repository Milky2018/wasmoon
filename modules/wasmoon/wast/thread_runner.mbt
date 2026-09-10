///|
priv enum ThreadCall {
  Interpreter(@executor.SuspensionReason, @executor.ExecutionContinuation)
  Native(@wasmoon_jit.NativeSuspensionReason, JITCoreContinuation)
}

///|
fn ThreadCall::cancel(self : ThreadCall) -> Unit {
  match self {
    Interpreter(_, continuation) => continuation.cancel()
    Native(_, continuation) => continuation.cancel()
  }
}

///|
fn ThreadCall::waiting(self : ThreadCall) -> Bool {
  self is Interpreter(AtomicWait, _) || self is Native(AtomicWait, _)
}

///|
priv enum ThreadCallResult {
  Completed(Result[Array[@types.Value], WastRunnerError])
  Parked(ThreadCall)
}

///|
fn interpreter_thread_result(
  outcome : @executor.ResumableCallOutcome,
) -> ThreadCallResult {
  match outcome {
    Returned(values) => Completed(Ok(values))
    Suspended(GuestEffect(_), continuation) => {
      continuation.cancel()
      Completed(Err(GuestSuspension))
    }
    Suspended(HostCall(_), continuation) => {
      continuation.cancel()
      Completed(
        Err(RuntimeError("WAST thread has no asynchronous host driver")),
      )
    }
    Suspended(reason, continuation) => Parked(Interpreter(reason, continuation))
  }
}

///|
fn native_thread_result(outcome : JITCoreCallOutcome) -> ThreadCallResult {
  match outcome {
    NativeCoreReturned(values) => Completed(Ok(values))
    NativeCoreSuspended(HostCall, continuation) => {
      continuation.cancel()
      Completed(
        Err(RuntimeError("WAST thread has no asynchronous host driver")),
      )
    }
    NativeCoreSuspended(reason, continuation) =>
      Parked(Native(reason, continuation))
  }
}

///|
fn start_thread_call(
  ctx : WastContext,
  instance : @runtime.ModuleInstance,
  jit : JITModuleContext?,
  index : Int,
  args : Array[@types.Value],
) -> ThreadCallResult {
  let (instance, jit, index) = resolve_wast_call(ctx, instance, jit, index) catch {
    error => return Completed(Err(error))
  }
  match jit {
    Some(jit) => {
      let outcome = jit.call_core_func_resumable(
        ctx.store,
        instance,
        index,
        args,
      ) catch {
        error => return Completed(Err(classify_jit_failure(error)))
      }
      native_thread_result(outcome)
    }
    None => {
      let outcome = @executor.call_func_by_index_resumable(
        ctx.store,
        instance,
        index,
        args,
        _ => None,
        cooperative=true,
      ) catch {
        error => return Completed(Err(classify_runtime_failure(error)))
      }
      interpreter_thread_result(outcome)
    }
  }
}

///|
fn ThreadCall::advance(self : ThreadCall) -> ThreadCallResult {
  match self {
    Interpreter(_, continuation) => {
      let outcome = continuation.continue_execution() catch {
        error => return Completed(Err(classify_runtime_failure(error)))
      }
      interpreter_thread_result(outcome)
    }
    Native(_, continuation) => {
      let outcome = continuation.continue_execution() catch {
        error => return Completed(Err(classify_jit_failure(error)))
      }
      native_thread_result(outcome)
    }
  }
}

///|
priv enum ThreadCompletion {
  Action(@wat.WastCommand, @wat.WastAction, Int)
  Module(PreparedWastModule, Int)
  ModuleTrap(String, Int)
}

///|
priv struct WastThread {
  ctx : WastContext
  commands : Array[(@wat.WastCommand, Int)]
  children : Map[String, Int]
  child_scopes : Array[Int]
  mut pc : Int
  mut pending : (ThreadCompletion, ThreadCall)?
  mut joining : Int?
  mut done : Bool
}

///|
fn WastThread::new(
  ctx : WastContext,
  commands : Array[(@wat.WastCommand, Int)],
) -> WastThread {
  {
    ctx,
    commands,
    children: Map([]),
    child_scopes: [],
    pc: 0,
    pending: None,
    joining: None,
    done: false,
  }
}

///|
fn WastThread::finish(
  self : WastThread,
  completion : ThreadCompletion,
  outcome : ThreadCallResult,
  result : WastResult,
  show_success : Bool,
) -> Unit {
  match outcome {
    Parked(call) => self.pending = Some((completion, call))
    Completed(values) => {
      self.pending = None
      match completion {
        Action(command, action, line) =>
          finish_wast_action(
            self.ctx,
            command,
            action,
            line,
            result,
            show_success,
            values,
          )
        Module(prepared, line) =>
          match values {
            Ok(_) => publish_wast_module(self.ctx, prepared)
            Err(error) => {
              result.failed += 1
              result.failures.push(
                "line \{line}: module start failed: \{error}",
              )
            }
          }
        ModuleTrap(expected, line) => {
          let matches = match values {
            Err(GuestTrap(message)) | Err(GuestExhaustion(message)) =>
              wast_trap_message_matches(message, expected)
            _ => false
          }
          if matches {
            result.passed += 1
            if show_success {
              println("line \{line}: assert_trap (module): PASSED")
            }
          } else {
            result.failed += 1
            result.failures.push(
              "line \{line}: assert_trap (module): expected '\{expected}'",
            )
          }
        }
      }
    }
  }
}

///|
fn start_thread_action(
  ctx : WastContext,
  action : @wat.WastAction,
) -> ThreadCallResult {
  match action {
    Get(_, _) =>
      Completed(
        try invoke_action(ctx, action) catch {
          error => Err(error)
        } noraise {
          values => Ok(values)
        },
      )
    Invoke(name, function, arguments) => {
      let instance = match name {
        Some(name) => ctx.named_modules.get(name)
        None => ctx.current_module
      }
      guard instance is Some(instance) else {
        return Completed(
          Err(
            match name {
              Some(name) => ModuleNotFound(name)
              None => NoCurrentModule
            },
          ),
        )
      }
      let jit = match name {
        Some(name) => ctx.jit_modules.get(name)
        None => ctx.current_jit
      }
      for export_ in instance.exports {
        if export_.name == function && export_.desc is Func(index) {
          let args = arguments.map(value => {
            wast_value_to_runtime(value, func_addrs=instance.func_addrs)
          }) catch {
            error => return Completed(Err(error))
          }
          return start_thread_call(ctx, instance, jit, index, args)
        }
      }
      Completed(Err(RuntimeError("unknown exported function: \{function}")))
    }
  }
}

///|
fn start_thread_module(
  thread : WastThread,
  module_ : @types.Module,
  name : String?,
  line : Int,
  result : WastResult,
  show_success : Bool,
  trap? : String? = None,
) -> Unit {
  let prepared = prepare_wast_module(
    thread.ctx,
    module_,
    name,
    cooperative=true,
  ) catch {
    error => {
      if trap is Some(expected) {
        thread.finish(
          ModuleTrap(expected, line),
          Completed(Err(error)),
          result,
          show_success,
        )
      } else {
        result.failed += 1
        result.failures.push(
          "line \{line}: module instantiation failed: \{error}",
        )
      }
      return
    }
  }
  let completion = match trap {
    Some(expected) => ModuleTrap(expected, line)
    None => Module(prepared, line)
  }
  let outcome = match module_.start {
    Some(index) =>
      start_thread_call(thread.ctx, prepared.instance, prepared.jit, index, [])
    None => Completed(Ok([]))
  }
  thread.finish(completion, outcome, result, show_success)
}

///|
fn shared_thread_context(
  parent : WastContext,
  shared : String?,
) -> WastContext raise WastRunnerError {
  let child = WastContext::WastContext(
    parent.use_jit,
    bulk_memory=parent.bulk_memory,
    stack_switching=parent.stack_switching,
    nan_canonicalization=parent.store.nan_canonicalization,
    jit_compiler=parent.jit_compiler,
    register_named_modules=parent.register_named_modules,
  )
  errdefer child.close()
  for name, definition in parent.module_definitions {
    child.module_definitions.set(name, definition)
  }
  child.current_definition = parent.current_definition
  if shared is Some(name) {
    guard parent.named_modules.get(name) is Some(original) else {
      raise ModuleNotFound(name)
    }
    let instance = @runtime.ModuleInstance::ModuleInstance()
    let memory_indices : Map[Int, Int] = Map([])
    for export_ in original.exports {
      // Store-local functions, globals and tables cannot cross the boundary.
      // Only shared memories are store-independent import capabilities.
      if export_.desc is Memory(index) {
        let memory = parent.store.get_mem(original.mem_addrs[index]) catch {
          error => raise classify_runtime_failure(error)
        }
        if !memory.is_shared() {
          continue
        }
        let local_index = match memory_indices.get(index) {
          Some(index) => index
          None => {
            let index_in_child = instance.mem_addrs.length()
            let address = child.store.alloc_shared_mem(memory) catch {
              error => raise classify_runtime_failure(error)
            }
            instance.mem_addrs.push(address)
            memory_indices.set(index, index_in_child)
            index_in_child
          }
        }
        instance.exports.push({ name: export_.name, desc: Memory(local_index), })
      }
    }
    child.named_modules.set(name, instance)
    child.registered_modules.set(name, instance)
  }
  child
}

///|
fn WastThread::step(
  self : WastThread,
  threads : Array[WastThread],
  result : WastResult,
  base_dir : String,
  show_success : Bool,
) -> Unit {
  if self.done {
    return
  }
  if self.pending is Some((completion, call)) {
    self.pending = None
    self.finish(completion, call.advance(), result, show_success)
    return
  }
  if self.joining is Some(index) {
    if !threads[index].done {
      return
    }
    self.joining = None
  }
  if self.pc >= self.commands.length() {
    if self.child_scopes.all(index => threads[index].done) {
      self.done = true
      self.ctx.close()
    }
    return
  }
  let (command, line) = self.commands[self.pc]
  self.pc += 1
  match command {
    Thread(name, shared, commands) => {
      let context = shared_thread_context(self.ctx, shared) catch {
        error => {
          result.failed += 1
          result.failures.push(
            "line \{line}: thread '\{name}' failed: \{error}",
          )
          return
        }
      }
      let index = threads.length()
      threads.push(WastThread::new(context, commands))
      self.children.set(name, index)
      self.child_scopes.push(index)
    }
    Wait(name) =>
      match self.children.get(name) {
        Some(index) => {
          self.children.remove(name)
          self.joining = Some(index)
        }
        None => {
          result.failed += 1
          result.failures.push("line \{line}: no thread named '\{name}'")
        }
      }
    AssertReturn(action, _)
    | AssertTrap(action, _)
    | AssertSuspension(action, _)
    | AssertException(action)
    | AssertExhaustion(action, _)
    | Action(action) =>
      self.finish(
        Action(command, action, line),
        start_thread_action(self.ctx, action),
        result,
        show_success,
      )
    Module(module_, name) =>
      start_thread_module(self, module_, name, line, result, show_success)
    ModuleInstance(name, definition_name) => {
      let definition = match definition_name {
        Some(name) => self.ctx.module_definitions.get(name)
        None => self.ctx.current_definition
      }
      match definition {
        Some(module_) =>
          start_thread_module(self, module_, name, line, result, show_success)
        None => {
          result.failed += 1
          result.failures.push("line \{line}: module definition not found")
        }
      }
    }
    ModuleQuote(parts) => {
      let module_ = @wat.parse(parts.join(""), implicit_module=true) catch {
        error => {
          result.failed += 1
          result.failures.push(
            "line \{line}: quoted module parse failed: \{error}",
          )
          return
        }
      }
      start_thread_module(self, module_, None, line, result, show_success)
    }
    AssertModuleTrap(Inline(module_), expected) =>
      start_thread_module(
        self,
        module_,
        None,
        line,
        result,
        show_success,
        trap=Some(expected),
      )
    AssertModuleTrap(Binary(bytes), expected) => {
      let module_ = @parser.parse_module(bytes) catch {
        error => {
          result.failed += 1
          result.failures.push(
            "line \{line}: binary parse failed before instantiation: \{error}",
          )
          return
        }
      }
      start_thread_module(
        self,
        module_,
        None,
        line,
        result,
        show_success,
        trap=Some(expected),
      )
    }
    _ =>
      run_wast_command(self.ctx, command, line, result, base_dir, show_success)
  }
}

///|
fn run_threaded_wast(
  ctx : WastContext,
  script : @wat.WastScript,
  result : WastResult,
  base_dir : String,
  show_success : Bool,
) -> Unit {
  let threads = [WastThread::new(ctx, script.commands)]
  defer {
    // First remove every parked invocation, then release any owning Store.
    for thread in threads {
      if thread.pending is Some((_, call)) {
        call.cancel()
        thread.pending = None
      }
    }
    for thread in threads {
      thread.ctx.close()
    }
  }
  while !threads[0].done {
    let count = threads.length()
    let mut runnable = false
    for index in 0..<count {
      let thread = threads[index]
      if thread.done {
        continue
      }
      if thread.pending is Some((_, call)) {
        if !call.waiting() {
          runnable = true
        }
      } else if thread.joining is None && thread.pc < thread.commands.length() {
        runnable = true
      }
      thread.step(threads, result, base_dir, show_success)
    }
    if !runnable && !threads[0].done {
      @wasmoon_jit.cooperative_idle()
    }
  }
}
