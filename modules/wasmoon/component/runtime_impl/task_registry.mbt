///|
/// Stable internal task identities are independent of reusable guest handles.
pub struct TaskRegistry {
  priv records : Map[Int64, TaskRecord]
  priv aliases : Map[Int64, Int64]
  priv handles : Map[Int64, Int64]
  priv next_id : Ref[Int64]
} derive(Debug)

///|
pub extend TaskRegistry with @debug.Debug::{to_repr}

///|
priv struct TaskRecord {
  id : Int64
  mut task_results : Array[ComponentValue]?
  mut task_result_owner : Int?
  mut task_return_contracts : TaskReturnContract?
  mut core_start_tasks : Unit?
  mut task_returned : Bool?
  mut task_self_cancelled : Bool?
  mut task_cancelled : Bool?
  mut task_contexts : Map[Int, @types.Value]?
  mut task_borrows : Int?
  mut task_thread : Map[Int, Int]?
  mut thread_runnable : Array[Int]?
  mut main_thread_scheduled : Bool?
  mut task_caller : Int64?
  mut task_instance : Int?
  mut task_suspensions : TaskSuspension?
  mut waiting_ws : Int64?
  mut sync_lower_states : SyncLowerState?
  mut subtasks : Subtask?
} derive(Debug)

///|
fn TaskRegistry::new() -> TaskRegistry {
  { records: Map([]), aliases: Map([]), handles: Map([]), next_id: Ref(-1L), }
}

///|
fn TaskRegistry::resolve(self : TaskRegistry, key : Int64) -> Int64 {
  self.aliases.get(key).unwrap_or(key)
}

///|
fn TaskRegistry::allocate(self : TaskRegistry) -> Int64 {
  let id = self.next_id.val
  self.next_id.val = id - 1L
  self.records.set(id, TaskRecord::new(id))
  id
}

///|
fn TaskRegistry::ensure(self : TaskRegistry, key : Int64) -> TaskRecord {
  let resolved = self.resolve(key)
  if self.records.get(resolved) is Some(record) {
    return record
  }
  if key >= 0L {
    let id = self.allocate()
    self.bind_handle(id, key)
    return self.records.get(id).unwrap()
  }
  let record = TaskRecord::new(key)
  self.records.set(key, record)
  if key <= self.next_id.val {
    self.next_id.val = key - 1L
  }
  record
}

///|
fn TaskRegistry::bind_handle(
  self : TaskRegistry,
  task_id : Int64,
  handle : Int64,
) -> Unit {
  let id = self.resolve(task_id)
  self.aliases.set(handle, id)
  self.handles.set(id, handle)
}

///|
fn TaskRegistry::retire(self : TaskRegistry, key : Int64) -> Unit {
  let id = self.resolve(key)
  self.records.remove(id)
  if self.handles.get(id) is Some(handle) {
    self.aliases.remove(handle)
    self.handles.remove(id)
  }
}

///|
fn TaskRegistry::read_task_results(
  self : TaskRegistry,
  key : Int64,
) -> Array[ComponentValue]? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_results
    None => None
  }
}

///|
fn TaskRegistry::clear_task_results(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.task_results = None
  }
}

///|
fn TaskRegistry::write_task_results(
  self : TaskRegistry,
  key : Int64,
  value : Array[ComponentValue],
) -> Unit {
  self.ensure(key).task_results = Some(value)
}

///|
fn TaskRegistry::read_task_result_owner(
  self : TaskRegistry,
  key : Int64,
) -> Int? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_result_owner
    None => None
  }
}

///|
fn TaskRegistry::write_task_result_owner(
  self : TaskRegistry,
  key : Int64,
  value : Int,
) -> Unit {
  self.ensure(key).task_result_owner = Some(value)
}

///|
fn TaskRegistry::read_task_return_contracts(
  self : TaskRegistry,
  key : Int64,
) -> TaskReturnContract? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_return_contracts
    None => None
  }
}

///|
fn TaskRegistry::write_task_return_contracts(
  self : TaskRegistry,
  key : Int64,
  value : TaskReturnContract,
) -> Unit {
  self.ensure(key).task_return_contracts = Some(value)
}

///|
fn TaskRegistry::read_core_start_tasks(
  self : TaskRegistry,
  key : Int64,
) -> Unit? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.core_start_tasks
    None => None
  }
}

///|
fn TaskRegistry::write_core_start_tasks(
  self : TaskRegistry,
  key : Int64,
  value : Unit,
) -> Unit {
  self.ensure(key).core_start_tasks = Some(value)
}

///|
fn TaskRegistry::read_task_returned(self : TaskRegistry, key : Int64) -> Bool? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_returned
    None => None
  }
}

///|
fn TaskRegistry::write_task_returned(
  self : TaskRegistry,
  key : Int64,
  value : Bool,
) -> Unit {
  self.ensure(key).task_returned = Some(value)
}

///|
fn TaskRegistry::read_task_self_cancelled(
  self : TaskRegistry,
  key : Int64,
) -> Bool? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_self_cancelled
    None => None
  }
}

///|
fn TaskRegistry::write_task_self_cancelled(
  self : TaskRegistry,
  key : Int64,
  value : Bool,
) -> Unit {
  self.ensure(key).task_self_cancelled = Some(value)
}

///|
fn TaskRegistry::read_task_cancelled(self : TaskRegistry, key : Int64) -> Bool? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_cancelled
    None => None
  }
}

///|
fn TaskRegistry::clear_task_cancelled(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.task_cancelled = None
  }
}

///|
fn TaskRegistry::write_task_cancelled(
  self : TaskRegistry,
  key : Int64,
  value : Bool,
) -> Unit {
  self.ensure(key).task_cancelled = Some(value)
}

///|
fn TaskRegistry::read_task_contexts(
  self : TaskRegistry,
  key : Int64,
) -> Map[Int, @types.Value]? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_contexts
    None => None
  }
}

///|
fn TaskRegistry::write_task_contexts(
  self : TaskRegistry,
  key : Int64,
  value : Map[Int, @types.Value],
) -> Unit {
  self.ensure(key).task_contexts = Some(value)
}

///|
fn TaskRegistry::read_task_borrows(self : TaskRegistry, key : Int64) -> Int? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_borrows
    None => None
  }
}

///|
fn TaskRegistry::clear_task_borrows(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.task_borrows = None
  }
}

///|
fn TaskRegistry::write_task_borrows(
  self : TaskRegistry,
  key : Int64,
  value : Int,
) -> Unit {
  self.ensure(key).task_borrows = Some(value)
}

///|
fn TaskRegistry::read_task_thread(
  self : TaskRegistry,
  key : Int64,
) -> Map[Int, Int]? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_thread
    None => None
  }
}

///|
fn TaskRegistry::clear_task_thread(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.task_thread = None
  }
}

///|
fn TaskRegistry::write_task_thread(
  self : TaskRegistry,
  key : Int64,
  value : Map[Int, Int],
) -> Unit {
  self.ensure(key).task_thread = Some(value)
}

///|
fn TaskRegistry::read_thread_runnable(
  self : TaskRegistry,
  key : Int64,
) -> Array[Int]? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.thread_runnable
    None => None
  }
}

///|
fn TaskRegistry::clear_thread_runnable(
  self : TaskRegistry,
  key : Int64,
) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.thread_runnable = None
  }
}

///|
fn TaskRegistry::write_thread_runnable(
  self : TaskRegistry,
  key : Int64,
  value : Array[Int],
) -> Unit {
  self.ensure(key).thread_runnable = Some(value)
}

///|
fn TaskRegistry::read_main_thread_scheduled(
  self : TaskRegistry,
  key : Int64,
) -> Bool? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.main_thread_scheduled
    None => None
  }
}

///|
fn TaskRegistry::clear_main_thread_scheduled(
  self : TaskRegistry,
  key : Int64,
) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.main_thread_scheduled = None
  }
}

///|
fn TaskRegistry::write_main_thread_scheduled(
  self : TaskRegistry,
  key : Int64,
  value : Bool,
) -> Unit {
  self.ensure(key).main_thread_scheduled = Some(value)
}

///|
fn TaskRegistry::read_task_caller(self : TaskRegistry, key : Int64) -> Int64? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_caller
    None => None
  }
}

///|
fn TaskRegistry::write_task_caller(
  self : TaskRegistry,
  key : Int64,
  value : Int64,
) -> Unit {
  self.ensure(key).task_caller = Some(self.resolve(value))
}

///|
fn TaskRegistry::entries_task_caller(
  self : TaskRegistry,
) -> Array[(Int64, Int64)] {
  let result : Array[(Int64, Int64)] = []
  for id, record in self.records {
    if record.task_caller is Some(value) {
      result.push((id, value))
    }
  }
  result
}

///|
fn TaskRegistry::read_task_instance(self : TaskRegistry, key : Int64) -> Int? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_instance
    None => None
  }
}

///|
fn TaskRegistry::write_task_instance(
  self : TaskRegistry,
  key : Int64,
  value : Int,
) -> Unit {
  self.ensure(key).task_instance = Some(value)
}

///|
fn TaskRegistry::read_task_suspensions(
  self : TaskRegistry,
  key : Int64,
) -> TaskSuspension? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.task_suspensions
    None => None
  }
}

///|
fn TaskRegistry::clear_task_suspensions(
  self : TaskRegistry,
  key : Int64,
) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.task_suspensions = None
  }
}

///|
fn TaskRegistry::write_task_suspensions(
  self : TaskRegistry,
  key : Int64,
  value : TaskSuspension,
) -> Unit {
  self.ensure(key).task_suspensions = Some(value)
}

///|
fn TaskRegistry::read_waiting_ws(self : TaskRegistry, key : Int64) -> Int64? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.waiting_ws
    None => None
  }
}

///|
fn TaskRegistry::clear_waiting_ws(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.waiting_ws = None
  }
}

///|
fn TaskRegistry::write_waiting_ws(
  self : TaskRegistry,
  key : Int64,
  value : Int64,
) -> Unit {
  self.ensure(key).waiting_ws = Some(value)
}

///|
fn TaskRegistry::clear_all_sync_lower_states(self : TaskRegistry) -> Unit {
  for _, record in self.records {
    record.sync_lower_states = None
  }
}

///|
fn TaskRegistry::read_sync_lower_states(
  self : TaskRegistry,
  key : Int64,
) -> SyncLowerState? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.sync_lower_states
    None => None
  }
}

///|
fn TaskRegistry::clear_sync_lower_states(
  self : TaskRegistry,
  key : Int64,
) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.sync_lower_states = None
  }
}

///|
fn TaskRegistry::write_sync_lower_states(
  self : TaskRegistry,
  key : Int64,
  value : SyncLowerState,
) -> Unit {
  self.ensure(key).sync_lower_states = Some(value)
}

///|
fn TaskRegistry::entries_sync_lower_states(
  self : TaskRegistry,
) -> Array[(Int64, SyncLowerState)] {
  let result : Array[(Int64, SyncLowerState)] = []
  for id, record in self.records {
    if record.sync_lower_states is Some(value) {
      result.push((id, value))
    }
  }
  result
}

///|
fn TaskRegistry::clear_all_subtasks(self : TaskRegistry) -> Unit {
  for _, record in self.records {
    record.subtasks = None
  }
}

///|
fn TaskRegistry::read_subtasks(self : TaskRegistry, key : Int64) -> Subtask? {
  match self.records.get(self.resolve(key)) {
    Some(record) => record.subtasks
    None => None
  }
}

///|
fn TaskRegistry::clear_subtasks(self : TaskRegistry, key : Int64) -> Unit {
  if self.records.get(self.resolve(key)) is Some(record) {
    record.subtasks = None
  }
}

///|
fn TaskRegistry::write_subtasks(
  self : TaskRegistry,
  key : Int64,
  value : Subtask,
) -> Unit {
  self.ensure(key).subtasks = Some(value)
}

///|
fn TaskRegistry::entries_subtasks(
  self : TaskRegistry,
) -> Array[(Int64, Subtask)] {
  let result : Array[(Int64, Subtask)] = []
  for id, record in self.records {
    if record.subtasks is Some(value) {
      result.push((self.handles.get(id).unwrap_or(id), value))
    }
  }
  result
}

///|
/// Number of guest-visible and detached subtasks still owned by this runtime.
pub fn TaskRegistry::subtask_count(self : TaskRegistry) -> Int {
  self.entries_subtasks().length()
}

///|
fn TaskRecord::new(id : Int64) -> TaskRecord {
  {
    id,
    task_results: None,
    task_result_owner: None,
    task_return_contracts: None,
    core_start_tasks: None,
    task_returned: None,
    task_self_cancelled: None,
    task_cancelled: None,
    task_contexts: None,
    task_borrows: None,
    task_thread: None,
    thread_runnable: None,
    main_thread_scheduled: None,
    task_caller: None,
    task_instance: None,
    task_suspensions: None,
    waiting_ws: None,
    sync_lower_states: None,
    subtasks: None,
  }
}

///|
fn retire_task(async_state : AsyncState, task_id : Int64) -> Unit {
  let task_id = async_state.tasks.resolve(task_id)
  discard_task_children(async_state, task_id)
  for key in sync_waitables_for_task(async_state, task_id) {
    async_state.sync_waitable_users.remove(key)
  }
  drop_task_thread(async_state, task_id)
  async_state.tasks.retire(task_id)
}
