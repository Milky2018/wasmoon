///|
/// One asynchronous host function registered with a Store.
pub type AsyncHostFunction = async (Caller, Array[@types.Value]) -> Result[
  Array[@types.Value],
  Error,
]

///|
/// Result of polling the host operation at the current Wasm call site.
pub(all) enum AsyncHostPoll {
  AsyncHostPending
  AsyncHostReady(Array[@types.Value])
} derive(Debug)

///|
const ASYNC_HOST_IDLE : Int = 0

///|
const ASYNC_HOST_WAITING : Int = 1

///|
const ASYNC_HOST_RESULT : Int = 2

///|
/// Invocation-local owner of one pending asynchronous host operation.
///
/// The driver is intentionally opaque. Executors poll it only at an imported
/// hostcall and wait on it only after the Wasm continuation has been parked.
pub struct AsyncHostCallDriver {
  priv spawn : (async () -> Result[Array[@types.Value], Error]) -> @async.Task[
    Result[Array[@types.Value], Error],
  ]
  priv phase : Ref[Int]
  priv func_addr : Ref[Int]
  priv task : Array[@async.Task[Result[Array[@types.Value], Error]]?]
  priv result : Array[Result[Array[@types.Value], Error]?]
}

///|
pub impl Debug for AsyncHostCallDriver with fn to_repr(_self) {
  Repr::literal("<async-host-call-driver>")
}

///|
/// Run one asynchronous Wasm invocation with structured ownership of every
/// host task it starts.
pub async fn[X] with_async_host_call_driver(
  body : async (AsyncHostCallDriver) -> X raise Error,
) -> X {
  @async.with_task_group(group => {
    let driver : AsyncHostCallDriver = {
      spawn: fn(task) { group.spawn(task) },
      phase: Ref(ASYNC_HOST_IDLE),
      func_addr: Ref(-1),
      task: [None],
      result: [None],
    }
    errdefer driver.cancel()
    body(driver)
  })
}

///|
/// Poll the operation associated with the current imported call.
///
/// The first poll starts the host task. A later poll consumes its result after
/// `wait_pending` has returned.
pub fn AsyncHostCallDriver::poll(
  self : AsyncHostCallDriver,
  func_addr : Int,
  func : AsyncHostFunction,
  caller : Caller,
  args : Array[@types.Value],
) -> AsyncHostPoll raise RuntimeError {
  match self.phase.val {
    ASYNC_HOST_IDLE => {
      let task = (self.spawn)(async fn() { func(caller, args) })
      self.phase.val = ASYNC_HOST_WAITING
      self.func_addr.val = func_addr
      self.task[0] = Some(task)
      AsyncHostPending
    }
    ASYNC_HOST_WAITING => {
      if self.func_addr.val != func_addr {
        raise AsyncHostCallInProgress
      }
      AsyncHostPending
    }
    ASYNC_HOST_RESULT => {
      if self.func_addr.val != func_addr {
        raise AsyncHostCallInProgress
      }
      guard self.result[0] is Some(result) else { raise Unreachable }
      self.phase.val = ASYNC_HOST_IDLE
      self.func_addr.val = -1
      self.result[0] = None
      match result {
        Ok(values) => AsyncHostReady(values)
        Err(error) => raise normalize_async_host_error(error)
      }
    }
    _ => raise Unreachable
  }
}

///|
pub fn normalize_async_host_error(error : Error) -> RuntimeError {
  match error {
    StackUnderflow => StackUnderflow
    StackOverflow => StackOverflow
    TypeMismatch => TypeMismatch
    StoreClosed => StoreClosed
    MemoryClosed => MemoryClosed
    OutOfBoundsMemoryAccess => OutOfBoundsMemoryAccess
    OutOfBoundsTableAccess => OutOfBoundsTableAccess
    OutOfBoundsArrayAccess => OutOfBoundsArrayAccess
    UndefinedElement => UndefinedElement
    UninitializedElement => UninitializedElement
    IndirectCallTypeMismatch => IndirectCallTypeMismatch
    DivisionByZero => DivisionByZero
    IntegerOverflow => IntegerOverflow
    InvalidConversion => InvalidConversion
    OutOfMemory => OutOfMemory
    Unreachable => Unreachable
    CallStackExhausted => CallStackExhausted
    UnknownImport(_, _) as runtime_error => runtime_error
    LinkError => LinkError
    LinkErrorDetail(_) as runtime_error => runtime_error
    NullReference => NullReference
    UnalignedAtomic => UnalignedAtomic
    InvalidConstantExpression(_) as runtime_error => runtime_error
    AsyncHostRequiresAsyncCall => AsyncHostRequiresAsyncCall
    AsyncHostCallInProgress => AsyncHostCallInProgress
    AsyncHostCallCancelled => AsyncHostCallCancelled
    AsyncHostError(_) as runtime_error => runtime_error
    _ if @async.is_cancellation_error(error) => AsyncHostCallCancelled
    _ => AsyncHostError(error.to_string())
  }
}

///|
/// Wait without blocking the host thread until the parked host operation can
/// be consumed by a retry of the same Wasm call site.
pub async fn AsyncHostCallDriver::wait_pending(
  self : AsyncHostCallDriver,
) -> Unit raise RuntimeError {
  if self.phase.val != ASYNC_HOST_WAITING {
    raise Unreachable
  }
  guard self.task[0] is Some(task) else { raise Unreachable }
  let result = task.wait() catch {
    _ => {
      self.cancel()
      raise AsyncHostCallCancelled
    }
  }
  self.task[0] = None
  self.result[0] = Some(result)
  self.phase.val = ASYNC_HOST_RESULT
}

///|
/// Cancel the pending host operation, if any.
pub fn AsyncHostCallDriver::cancel(self : AsyncHostCallDriver) -> Unit {
  if self.task[0] is Some(task) {
    task.cancel()
  }
  self.phase.val = ASYNC_HOST_IDLE
  self.func_addr.val = -1
  self.task[0] = None
  self.result[0] = None
}
