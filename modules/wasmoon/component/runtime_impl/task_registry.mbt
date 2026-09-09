///|
/// Stable internal task identities are independent of reusable guest handles.
pub struct TaskRegistry {
  priv records : Map[Int64, TaskRecord]
  priv aliases : Map[Int64, Int64]
  priv handles : Map[Int64, Int64]
  priv next_id : Ref[Int64]
  priv closed : Ref[Bool]
} derive(Debug)

///|
pub extend TaskRegistry with @debug.Debug::{to_repr}

///|
priv struct TaskRecord {
  id : Int64
  mut root_task : CallbackTask?
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
  {
    records: Map([]),
    aliases: Map([]),
    handles: Map([]),
    next_id: Ref(-1L),
    closed: Ref(false),
  }
}

///|
fn TaskRegistry::resolve(self : TaskRegistry, key : Int64) -> Int64 {
  self.aliases.get(key).unwrap_or(key)
}

///|
fn TaskRegistry::allocate(
  self : TaskRegistry,
) -> Int64 raise ComponentRuntimeError {
  if self.closed.val {
    raise Cancelled
  }
  let id = self.next_id.val
  self.next_id.val = id - 1L
  self.records.set(id, TaskRecord::new(id))
  id
}

///|
fn TaskRegistry::bind_handle(
  self : TaskRegistry,
  task_id : Int64,
  handle : Int64,
) -> Unit {
  let id = self.resolve(task_id)
  guard !self.closed.val &&
    self.records.get(id) is Some(_) &&
    self.aliases.get(handle) is None &&
    self.handles.get(id) is None else {
    return
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_results = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_result_owner = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_return_contracts = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.core_start_tasks = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_returned = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_self_cancelled = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_cancelled = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_contexts = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_borrows = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_thread = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.thread_runnable = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.main_thread_scheduled = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_caller = Some(self.resolve(value))
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_instance = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.task_suspensions = Some(value)
  }
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.waiting_ws = Some(value)
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.sync_lower_states = Some(value)
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
  if !self.closed.val && self.records.get(self.resolve(key)) is Some(record) {
    record.subtasks = Some(value)
  }
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
    root_task: None,
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

///|
fn alloc_canon_task_id(state : AsyncState) -> Int64 raise @runtime.RuntimeError {
  alloc_task_id(state) catch {
    error => {
      trap_canon(canon_err_message(error))
      raise Unreachable
    }
  }
}

///|
fn push_canon_task(
  state : AsyncState,
  id : Int64,
  can_block : Bool,
) -> Unit raise @runtime.RuntimeError {
  push_task(state, id, can_block) catch {
    error => {
      trap_canon(canon_err_message(error))
      raise Unreachable
    }
  }
}
