///|
/// Result of polling caller-owned task state.
///
/// The runtime never stores the polling closure or the state it accesses.
pub(all) enum Poll[A] {
  Ready(A)
  Pending
} derive(Debug, Eq)

///|
/// Stable identity of one logical task.
///
/// Slot generations prevent stale wakers from targeting a later task that
/// reuses the same internal slot.
struct TaskId {
  slot : Int
  generation : Int
} derive(Debug, Eq)

///|
/// Stable identity of one pending host operation.
///
/// Reactor adapters report readiness with this value. A cancelled operation
/// remains stale even if its internal slot is reused.
struct OperationId {
  slot : Int
  generation : Int
} derive(Debug, Eq)

///|
pub suberror AsyncRuntimeError {
  TimeWentBackwards(previous~ : Int64, requested~ : Int64)
} derive(Debug, Eq)

///|
pub impl Show for AsyncRuntimeError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
priv struct TaskRecord {
  generation : Int
  mut queued : Bool
  operations : Array[OperationId]
}

///|
priv struct OperationRecord {
  generation : Int
  task : TaskId
  deadline : Int64?
}

///|
/// Single-threaded owner of task readiness and host-operation lifetimes.
///
/// This object stores identities and readiness state only. In particular, a
/// pending operation cannot retain a guest Store, a polling closure, a
/// Component Model value, or a platform descriptor.
struct Runtime {
  tasks : Array[TaskRecord?]
  task_generations : Array[Int]
  free_task_slots : Array[Int]
  operations : Array[OperationRecord?]
  operation_generations : Array[Int]
  free_operation_slots : Array[Int]
  ready : Array[TaskId]
  mut ready_head : Int
  mut now : Int64
}

///|
pub fn Runtime::Runtime() -> Runtime {
  {
    tasks: [],
    task_generations: [],
    free_task_slots: [],
    operations: [],
    operation_generations: [],
    free_operation_slots: [],
    ready: [],
    ready_head: 0,
    now: 0L,
  }
}

///|
fn Runtime::task_record(self : Runtime, id : TaskId) -> TaskRecord? {
  if id.slot < 0 || id.slot >= self.tasks.length() {
    return None
  }
  match self.tasks[id.slot] {
    Some(record) if record.generation == id.generation => Some(record)
    _ => None
  }
}

///|
fn Runtime::operation_record(
  self : Runtime,
  id : OperationId,
) -> OperationRecord? {
  if id.slot < 0 || id.slot >= self.operations.length() {
    return None
  }
  match self.operations[id.slot] {
    Some(record) if record.generation == id.generation => Some(record)
    _ => None
  }
}

///|
fn Runtime::enqueue(self : Runtime, id : TaskId) -> Bool {
  guard self.task_record(id) is Some(record) else { return false }
  if !record.queued {
    record.queued = true
    self.ready.push(id)
  }
  true
}

///|
fn Runtime::allocate_task_id(self : Runtime) -> TaskId {
  let slot = if self.free_task_slots.is_empty() {
    let slot = self.tasks.length()
    self.tasks.push(None)
    self.task_generations.push(0)
    slot
  } else {
    self.free_task_slots.remove(self.free_task_slots.length() - 1)
  }
  { slot, generation: self.task_generations[slot] }
}

///|
fn Runtime::allocate_operation_id(self : Runtime) -> OperationId {
  let slot = if self.free_operation_slots.is_empty() {
    let slot = self.operations.length()
    self.operations.push(None)
    self.operation_generations.push(0)
    slot
  } else {
    self.free_operation_slots.remove(self.free_operation_slots.length() - 1)
  }
  { slot, generation: self.operation_generations[slot] }
}

///|
/// Create a task and enqueue its first poll.
pub fn Runtime::spawn(self : Runtime) -> TaskHandle {
  let id = self.allocate_task_id()
  self.tasks[id.slot] = Some({
    generation: id.generation,
    queued: true,
    operations: [],
  })
  self.ready.push(id)
  TaskHandle(self, id)
}

///|
/// Take the next task that should be polled.
///
/// The caller owns the task state and any temporary mutable Store access. If
/// polling returns `Pending`, only a `Waker` or `OperationId` remains stored in
/// this runtime.
pub fn Runtime::next_ready(self : Runtime) -> TaskId? {
  while self.ready_head < self.ready.length() {
    let id = self.ready[self.ready_head]
    self.ready_head = self.ready_head + 1
    match self.task_record(id) {
      Some(record) if record.queued => {
        record.queued = false
        return Some(id)
      }
      _ => ()
    }
  }
  self.ready.clear()
  self.ready_head = 0
  None
}

///|
pub fn Runtime::now(self : Runtime) -> Int64 {
  self.now
}

///|
pub impl Debug for Runtime with fn to_repr(self) {
  let mut task_count = 0
  for task in self.tasks {
    if task is Some(_) {
      task_count = task_count + 1
    }
  }
  let mut operation_count = 0
  for operation in self.operations {
    if operation is Some(_) {
      operation_count = operation_count + 1
    }
  }
  let mut ready_count = 0
  for i in self.ready_head..<self.ready.length() {
    if self.task_record(self.ready[i]) is Some(record) && record.queued {
      ready_count = ready_count + 1
    }
  }
  Repr::ctor("Runtime", [
    (Some("now"), to_repr(self.now)),
    (Some("tasks"), to_repr(task_count)),
    (Some("operations"), to_repr(operation_count)),
    (Some("ready"), to_repr(ready_count)),
  ])
}

///|
fn Runtime::register_operation(
  self : Runtime,
  task : TaskId,
  deadline : Int64?,
) -> OperationHandle? {
  guard self.task_record(task) is Some(task_record) else { return None }
  let id = self.allocate_operation_id()
  self.operations[id.slot] = Some({ generation: id.generation, task, deadline })
  task_record.operations.push(id)
  Some(OperationHandle(self, id))
}

///|
fn TaskRecord::remove_operation(
  self : TaskRecord,
  operation : OperationId,
) -> Unit {
  for i in 0..<self.operations.length() {
    if self.operations[i] == operation {
      self.operations.remove(i) |> ignore
      return
    }
  }
}

///|
fn Runtime::retire_operation(
  self : Runtime,
  id : OperationId,
  wake : Bool,
) -> Bool {
  guard self.operation_record(id) is Some(operation) else { return false }
  if self.task_record(operation.task) is Some(task) {
    task.remove_operation(id)
  }
  self.operations[id.slot] = None
  self.operation_generations[id.slot] = self.operation_generations[id.slot] + 1
  self.free_operation_slots.push(id.slot)
  if wake {
    self.enqueue(operation.task) |> ignore
  }
  true
}

///|
/// Complete a reactor operation and wake its task.
///
/// Returns `false` for cancelled, already-completed, or stale operation IDs.
pub fn Runtime::complete_operation(self : Runtime, id : OperationId) -> Bool {
  self.retire_operation(id, true)
}

///|
/// Cancel a reactor operation without waking its task.
///
/// Cancellation is idempotent.
pub fn Runtime::cancel_operation(self : Runtime, id : OperationId) -> Unit {
  self.retire_operation(id, false) |> ignore
}

///|
fn Runtime::retire_task(self : Runtime, id : TaskId) -> Unit {
  guard self.task_record(id) is Some(record) else { return }
  while !record.operations.is_empty() {
    self.cancel_operation(record.operations[record.operations.length() - 1])
  }
  self.tasks[id.slot] = None
  self.task_generations[id.slot] = self.task_generations[id.slot] + 1
  self.free_task_slots.push(id.slot)
}

///|
/// Advance deterministic runtime time and wake every expired timer.
pub fn Runtime::advance_to(
  self : Runtime,
  now : Int64,
) -> Int raise AsyncRuntimeError {
  if now < self.now {
    raise TimeWentBackwards(previous=self.now, requested=now)
  }
  self.now = now
  let expired : Array[OperationId] = []
  for slot in 0..<self.operations.length() {
    match self.operations[slot] {
      Some(operation) =>
        if operation.deadline is Some(deadline) && deadline <= now {
          expired.push({ slot, generation: operation.generation })
        }
      None => ()
    }
  }
  for id in expired {
    self.complete_operation(id) |> ignore
  }
  expired.length()
}

///|
pub fn Runtime::next_deadline(self : Runtime) -> Int64? {
  let mut result : Int64? = None
  for operation in self.operations {
    match operation {
      Some({ deadline: Some(deadline), .. }) =>
        if result is None || (result is Some(current) && deadline < current) {
          result = Some(deadline)
        }
      _ => ()
    }
  }
  result
}

///|
/// Handle owned by the caller's task table.
struct TaskHandle(Runtime, TaskId)

///|
pub fn TaskHandle::id(self : TaskHandle) -> TaskId {
  self.1
}

///|
pub fn TaskHandle::waker(self : TaskHandle) -> Waker {
  Waker(self.0, self.1)
}

///|
pub fn TaskHandle::is_active(self : TaskHandle) -> Bool {
  self.0.task_record(self.1) is Some(_)
}

///|
/// Mark a task complete and cancel all of its outstanding operations.
pub fn TaskHandle::complete(self : TaskHandle) -> Unit {
  self.0.retire_task(self.1)
}

///|
/// Cancel a task and all of its outstanding operations.
///
/// Cancellation is idempotent.
pub fn TaskHandle::cancel(self : TaskHandle) -> Unit {
  self.0.retire_task(self.1)
}

///|
/// Cloneable capability that only queues its task for another poll.
struct Waker(Runtime, TaskId)

///|
/// Queue the associated task once.
///
/// Returns `false` if the task has completed or the waker is stale.
pub fn Waker::wake(self : Waker) -> Bool {
  self.0.enqueue(self.1)
}

///|
/// Register an externally-driven host operation.
pub fn Waker::register(self : Waker) -> OperationHandle? {
  self.0.register_operation(self.1, None)
}

///|
/// Register a deterministic timer deadline.
pub fn Waker::register_timer(
  self : Waker,
  deadline : Int64,
) -> OperationHandle? {
  let operation = self.0.register_operation(self.1, Some(deadline))
  if deadline <= self.0.now && operation is Some(ready) {
    ready.complete() |> ignore
  }
  operation
}

///|
/// Handle retained by a host operation or reactor adapter.
struct OperationHandle(Runtime, OperationId)

///|
pub fn OperationHandle::id(self : OperationHandle) -> OperationId {
  self.1
}

///|
pub fn OperationHandle::complete(self : OperationHandle) -> Bool {
  self.0.complete_operation(self.1)
}

///|
/// Cancel this operation without waking its task.
///
/// Cancellation is idempotent.
pub fn OperationHandle::cancel(self : OperationHandle) -> Unit {
  self.0.cancel_operation(self.1)
}
