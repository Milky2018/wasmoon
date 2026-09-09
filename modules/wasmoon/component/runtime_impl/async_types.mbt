///|
pub(all) enum ComponentValue {
  Bool(Bool)
  S8(Int)
  U8(Int)
  S16(Int)
  U16(Int)
  S32(Int)
  U32(Int)
  S64(Int64)
  U64(Int64)
  F32(Float)
  F64(Double)
  Char(Char)
  String(String)
  /// Internal canonical transport; embedding boundaries expose String instead.
  EncodedString(String, StringEncoding, Int)
  ErrorContext(String)
  List(Array[ComponentValue])
  Tuple(Array[ComponentValue])
  /// Canonical ABI representation for variants/options/results.
  /// `tag` is the case index, and `payload` is the case payload (if any).
  Variant(Int, ComponentValue?)
  // Resource representation after a borrow crosses into the component
  // instance that implements its resource type.
  ResourceValue(Int)
} derive(Debug, Eq)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for ComponentValue with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
pub(all) struct CoreFuncRef {
  instance : @runtime.ModuleInstance
  func_idx : Int
  engine : CoreExecutionEngine
  debug_name : String?
  may_suspend : Bool
  native_eligible : Bool
} derive(Debug)

///|
/// Embedding-owned cleanup associated with an owned host resource handle.
struct HostResourceDestructor {
  drop : (Int) -> Unit
}

///|
impl Debug for HostResourceDestructor with fn to_repr(_self) {
  Repr::literal("HostResourceDestructor")
}

///|
pub fn HostResourceDestructor::HostResourceDestructor(
  drop : (Int) -> Unit,
) -> HostResourceDestructor {
  { drop, }
}

///|
pub fn HostResourceDestructor::destroy(
  self : HostResourceDestructor,
  rep : Int,
) -> Unit {
  (self.drop)(rep)
}

///|
struct TaskReturnContract {
  result : ValType?
  types : Array[TypeDef?]
  resources : CanonResources
  owner_component_id : Int
} derive(Debug)

///|
struct CanonResources {
  mem_addr : Int?
  realloc : CanonicalRealloc?
  post_return : CoreFuncRef?
  encoding : StringEncoding
} derive(Debug)

///|
pub(all) struct ResourceHandle {
  type_id : Int
  rep : Int
  dtor : CoreFuncRef?
  host_dtor : HostResourceDestructor?
  kind : ResourceKind
  impl_component_id : Int
  own : Bool
  borrow_scope : Int64?
  num_lends : Array[Int]
} derive(Debug)

///|
pub(all) struct ResourceTable {
  id : Int
  next_handle : Ref[Int]
  free_handles : Ref[Array[Int]]
  entries : Ref[Map[Int, ResourceHandle]]
  // Error contexts use a separate per-component handle namespace.
  error_contexts : Map[Int, String]
  next_error_context : Ref[Int]
} derive(Debug)

///|
let resource_table_id_counter : Array[Int] = [0]

///|
pub fn ResourceTable::ResourceTable() -> ResourceTable {
  let id = resource_table_id_counter[0]
  resource_table_id_counter[0] = id + 1
  // Resource handle 0 is invalid; error-context handles start at 0.
  {
    id,
    next_handle: Ref(1),
    free_handles: Ref([]),
    entries: Ref(Map([])),
    error_contexts: Map([]),
    next_error_context: Ref(0),
  }
}

///|
fn alloc_handle_index(
  next_handle : Ref[Int],
  free_handles : Ref[Array[Int]],
) -> (Int, Bool) {
  if free_handles.val.length() > 0 {
    (free_handles.val.remove(free_handles.val.length() - 1), true)
  } else {
    let handle = next_handle.val
    next_handle.val = handle + 1
    (handle, false)
  }
}

///|
pub fn ResourceTable::alloc(
  self : ResourceTable,
  entry : ResourceHandle,
) -> Int {
  let (handle, _from_free) = alloc_handle_index(
    self.next_handle,
    self.free_handles,
  )
  let entries = self.entries.val
  entries.set(handle, entry)
  self.entries.val = entries
  handle
}

///|
pub fn ResourceTable::get(
  self : ResourceTable,
  handle : Int,
) -> ResourceHandle? {
  self.entries.val.get(handle)
}

///|
pub fn ResourceTable::free(
  self : ResourceTable,
  handle : Int,
) -> ResourceHandle? {
  let entry = self.entries.val.get(handle)
  if entry is Some(_) {
    let entries = self.entries.val
    entries.remove(handle)
    self.entries.val = entries
    self.free_handles.val.push(handle)
  }
  entry
}

///|
fn resource_handle_index_text(handle : Int) -> String {
  handle.reinterpret_as_uint().to_string()
}

///|
fn registered_resource_table(
  async_state : AsyncState,
  table : ResourceTable,
) -> ResourceTable {
  match async_state.resource_tables.get(table.id) {
    Some(registered) => registered
    None => table
  }
}

///|
pub(all) struct StreamEndpoint {
  stream_id : Int
  is_readable : Bool
  // Set once an operation observed that the opposite end was dropped; subsequent
  // reads/writes/lifts should trap (component-spec "done" semantics).
  notified_peer_dropped : Array[Bool]
  in_waitable_set : Ref[Bool]
} derive(Debug)

///|
struct PendingStreamRead {
  // Memory where the read buffer lives (from the canonical options of stream.read).
  // Writes can come from a different component instance/memory, so we must keep
  // enough info to write into the *reader* memory.
  payload_type : CanonicalPayloadType
  mem_addr : Int?
  realloc : CanonicalRealloc?
  encoding : StringEncoding
  // Resource table of the reader component instance (used to transfer `own` resources).
  reader_table : ResourceTable
  ptr : Int64
  // Element count requested by the read.
  len : Int
  // Number of elements already written into the buffer.
  filled : Int
  // Readable endpoint handle (waitable index) that initiated this pending read.
  reader_handle : Int
  // Whether we've already enqueued a STREAM_READ event for this pending read.
  event_enqueued : Bool
} derive(Debug)

///|
struct PendingStreamWrite {
  // Resource table of the writer component instance (used to transfer `own` resources).
  writer_table : ResourceTable
  // Lifted values retain the writer type environment until rendezvous.
  buf : CanonicalPayload
  // Element count is independent of byte length for zero-sized payloads.
  count : Int
  // Number of elements already consumed by a read.
  sent : Int
  // Writable endpoint handle (waitable index) that initiated this pending write.
  writer_handle : Int
  // Whether we've already enqueued a STREAM_WRITE event for this pending write.
  event_enqueued : Bool
  // For sync (non-async) stream.write, defer completion by one cooperative yield once
  // the write becomes fully consumed. This gives the reader a chance to drop the
  // readable end before the writer observes completion (component-spec/async/sync-streams).
  defer_complete : Bool
} derive(Debug)

///|
struct StreamState {
  // Whether guest endpoints in the same component may copy this payload.
  allows_intra_component : Bool
  pending_read : PendingStreamRead?
  pending_write : PendingStreamWrite?
  readable_dropped : Bool
  writable_dropped : Bool
} derive(Debug)

///|
pub(all) enum HostValueStreamPoll {
  Pending
  Values(Array[ComponentValue])
  Closed
} derive(Debug)

///|
struct HostValueStream {
  payload_ty : ValType
  types : Array[TypeDef?]
  values : Array[ComponentValue]
  next : Ref[Int]
  pull : ((Int) -> HostValueStreamPoll raise ComponentRuntimeError)?
  cancel : (() -> Unit)?
  closed : Ref[Bool]
}

///|
impl Debug for HostValueStream with fn to_repr(_self) {
  Repr::literal("HostValueStream")
}

///|
pub(all) struct StreamTable {
  next_stream_id : Array[Int]
  // Keyed by `handle_key(component_id, local_handle)`.
  endpoints : Map[Int64, StreamEndpoint]
  streams : Map[Int, StreamState]
  host_values : Map[Int, HostValueStream]
} derive(Debug)

///|
pub fn StreamTable::StreamTable() -> StreamTable {
  {
    next_stream_id: [0],
    endpoints: Map([]),
    streams: Map([]),
    host_values: Map([]),
  }
}

///|
fn cleanup_closed_stream(table : StreamTable, stream_id : Int) -> Unit {
  guard table.streams.get(stream_id) is Some(state) &&
    state.readable_dropped &&
    state.writable_dropped else {
    return
  }
  for entry in table.endpoints {
    let (_, endpoint) = entry
    if endpoint.stream_id == stream_id {
      return
    }
  }
  table.host_values.remove(stream_id)
  table.streams.remove(stream_id)
}

///|
fn cleanup_closed_future(async_state : AsyncState, future_id : Int) -> Unit {
  guard async_state.futures.get(future_id) is Some(state) &&
    state.readable_dropped &&
    state.writable_dropped else {
    return
  }
  for entry in async_state.future_endpoints {
    let (_, endpoint) = entry
    if endpoint.future_id == future_id {
      return
    }
  }
  async_state.host_future_values.remove(future_id)
  async_state.futures.remove(future_id)
}

///|
/// Async/task/waitable state shared across a whole component instantiation tree.
///
/// Waitable/stream/future/subtask handle numbers are per component instance (resource_table.id).
/// Internally we key maps by `handle_key(component_id, local_handle)` to avoid collisions.
pub(all) struct AsyncState {
  // A core trap rejects new host calls; admitted continuations may still resume.
  trapped : Ref[Bool]
  core_engine : CoreExecutionEngine
  // Per-component handle allocator for waitables/streams/futures/subtasks/threads.
  // Handle 0 is invalid; allocation starts at 1 (matches component model ABI).
  next_handle_by_component : Map[Int, Array[Int]]
  free_handles_by_component : Map[Int, Array[Int]]
  // Shared stream table (streams share the same handle space as waitables/subtasks).
  stream_table : StreamTable
  resource_tables : Map[Int, ResourceTable]
  // Embedding-owned reactor hook for asynchronous host calls. It blocks until
  // at least one registered external operation may make progress.
  host_event_loop : Ref[HostEventLoop?]

  // Task stack + per-task state (used by canon task.return/context.*).
  task_stack : Array[Int64]
  tasks : TaskRegistry
  // Explicit guest threads keyed by `handle_key(owner_component_id, local_handle)`.
  threads : Map[Int64, GuestThread]
  // Whether the currently executing task is allowed to block.
  task_can_block : Array[Bool]
  can_block_stack : Array[Bool]

  // True while executing an async callback (used to conservatively reject re-entrancy).
  in_async_callback : Array[Bool]

  // Waitable sets and event queues.
  waitable_sets : Map[Int64, WaitableSet]
  waitable_to_set : Map[Int64, Int64]
  waitable_events : Map[Int64, Array[WaitEvent]]
  sync_waitable_users : Map[Int64, Int64]

  // Subtasks created by `canon lower ... async`.
  inflight_by_instance : Map[Int, Int]
  pending_by_instance : Map[Int, Array[Int64]]
  // Round-robin cursor for the single-threaded host task scheduler.
  scheduler_cursor : Array[Int64?]

  // Futures created by `canon future.new`.
  next_future_id : Array[Int]
  futures : Map[Int, FutureState]
  future_endpoints : Map[Int64, FutureEndpoint]
  host_future_values : Map[Int, HostFutureValue]

  // Per-component backpressure counter used by `canon backpressure.*`.
  // Matches Wasmtime behavior: enabled when > 0; valid range is u16.
  backpressure_by_instance : Map[Int, Int]
} derive(Debug)

///|
struct WaitEvent {
  // Component instance id where this waitable index is valid.
  owner_component_id : Int
  code : Int
  index : Int
  payload : Int
} derive(Debug)

///|
struct WaitableSet {
  // Local index (per component instance).
  id : Int
  members : Map[Int, Bool]
  queue : Array[WaitEvent]
  // Number of active waiters; dropping a set with waiters traps.
  waiters : Array[Int]
} derive(Debug)

///|
struct FutureEndpoint {
  future_id : Int
  is_readable : Bool
  // Component instance id where this future was created (resource_table.id).
  creator_component_id : Int
  in_waitable_set : Ref[Bool]
} derive(Debug)

///|
struct PendingFutureRead {
  // Memory where the read pointer lives (from the canonical options of future.read).
  // Writes can come from a different component instance/memory.
  payload_type : CanonicalPayloadType
  mem_addr : Int?
  realloc : CanonicalRealloc?
  encoding : StringEncoding
  // Resource table of the reader component instance.
  reader_table : ResourceTable
  // For typed futures, write the payload at `ptr`.
  ptr : Int64
  // The readable endpoint that initiated this pending read.
  reader_component_id : Int
  reader_handle : Int
} derive(Debug)

///|
struct PendingFutureWrite {
  // The writable endpoint that initiated this pending write.
  writer_component_id : Int
  writer_handle : Int
  // Pending write value (already loaded from memory if needed).
  payload : CanonicalPayload
} derive(Debug)

///|
struct FutureState {
  // The element type of this future; used for intra-component checks.
  payload_ty : ValType?
  pending_read : PendingFutureRead?
  pending_write : PendingFutureWrite?
  readable_dropped : Bool
  writable_dropped : Bool
  // Set once a read has completed (COMPLETED or DROPPED).
  read_done : Bool
  // Distinguish successful completion from notification that the reader dropped.
  write_succeeded : Bool
  write_observed_readable_drop : Bool
  // True once a value has been provided via `future.write` (even if it blocked).
  wrote_value : Bool
} derive(Debug)

///|
pub(all) enum HostFutureValuePoll {
  Pending
  Ready(ComponentValue)
} derive(Debug)

///|
struct HostFutureValue {
  payload_ty : ValType
  types : Array[TypeDef?]
  value : Ref[ComponentValue?]
  pull : (() -> HostFutureValuePoll raise ComponentRuntimeError)?
  cancel : (() -> Unit raise ComponentRuntimeError)?
}

///|
impl Debug for HostFutureValue with fn to_repr(_self) {
  Repr::literal("HostFutureValue")
}

///|
enum GuestThreadPhase {
  NotStarted
  Suspended
  Completed
} derive(Debug, Eq)

///|
struct GuestThread {
  owner_component_id : Int
  // Guest-visible local thread handle.
  handle : Int
  // Root task that owns this thread.
  parent_task_id : Int64
  // Internal task id that owns the explicit thread continuation.
  task_id : Int64
  start_func : CoreFuncRef
  context : Int
  phase : Array[GuestThreadPhase]
  scheduled : Array[Bool]
  waiting_ws : Array[Int64?]
  continuation : Array[CoreContinuation?]
} derive(Debug)

///|
enum SubtaskPhase {
  Starting
  Started
  Returned
} derive(Debug, Eq)

///|
enum SubtaskDriver {
  // Callback-driven: step using callback codes and waitable-set events.
  CallbackLifted(CallbackTask)
} derive(Debug)

///|
enum TaskStep {
  Blocked
  Progressed
  Done
} derive(Debug, Eq)

///|
priv enum TaskCorePoll {
  CoreReady(Array[@types.Value])
  CorePending(TaskStep)
}

///|
struct CallbackTask {
  func : ComponentFunc
  args : Array[ComponentValue]
  // The component instance id whose handle numbering `args` currently uses.
  // For nested component calls, stream/future readable handles are moved into
  // the callee's local handle space before entering core code.
  args_owner_component_id : Array[Int]
  // Whether the initial call has been made (for callback-style tasks).
  started : Array[Bool]
  // The entry function or final callback has exited; guest threads may remain.
  main_finished : Array[Bool]
  // Latest callback code from the core task or callback.
  code : Array[Int]
  // Waitable-set key (handle_key(owner_component_id, local_index)).
  waiting_set : Array[Int64?]
  // Lazily-created state for an asynchronous host function.
  host_future : Array[HostFuture?]
  cancelled : Array[Bool]
  // Exact core interpreter state captured at the suspension point.
  continuation : Array[CoreContinuation?]
} derive(Debug)

///|
struct SyncLowerState {
  task_id : Int64
  task : CallbackTask
} derive(Debug)

///|
struct Subtask {
  id : Int
  // Detached subtasks are internal background tasks (spawned by sync-lowering)
  // that are never exposed as waitables; they are auto-cleaned up on return.
  detached : Bool
  phase : Array[SubtaskPhase]
  caller_table : ResourceTable
  callee_instance_id : Int
  // Backpressure key: only one in-flight subtask per async-lowered core func.
  bp_key : Int
  retptr : Int64
  mem_addr : Int?
  result_ty : ValType?
  types : Array[TypeDef?]
  resources : CanonResources
  driver : SubtaskDriver
} derive(Debug)

///|
pub fn AsyncState::AsyncState(
  stream_table : StreamTable,
  core_engine? : CoreExecutionEngine = interpreter_core_execution_engine(),
) -> AsyncState {
  {
    core_engine,
    next_handle_by_component: Map([]),
    free_handles_by_component: Map([]),
    stream_table,
    resource_tables: Map([]),
    host_event_loop: Ref(None),
    trapped: Ref(false),
    task_stack: [0L],
    // Use negative ids for internal tasks so they don't collide with the shared handle space.
    tasks: TaskRegistry::new(),
    threads: Map([]),
    task_can_block: [false],
    can_block_stack: [false],
    in_async_callback: [false],
    waitable_sets: Map([]),
    waitable_to_set: Map([]),
    waitable_events: Map([]),
    sync_waitable_users: Map([]),
    inflight_by_instance: Map([]),
    pending_by_instance: Map([]),
    scheduler_cursor: [None],
    next_future_id: [0],
    futures: Map([]),
    future_endpoints: Map([]),
    host_future_values: Map([]),
    backpressure_by_instance: Map([]),
  }
}

///|
fn handle_key(component_id : Int, local_handle : Int) -> Int64 {
  (component_id.to_int64() << 32) | (local_handle.to_int64() & 0xFFFFFFFFL)
}

///|
fn key_local(handle_key : Int64) -> Int {
  (handle_key & 0xFFFFFFFFL).to_int()
}

///|
fn key_owner(handle_key : Int64) -> Int {
  (handle_key >> 32).to_int()
}

///|
fn find_stream_endpoint_key_by_local(
  async_state : AsyncState,
  local_handle : Int,
  want_readable : Bool,
) -> Int64? {
  for kv in async_state.stream_table.endpoints.iter() {
    let (k, ep) = kv
    if key_local(k) == local_handle && ep.is_readable == want_readable {
      return Some(k)
    }
  }
  None
}

///|
fn find_future_endpoint_key_by_local(
  async_state : AsyncState,
  local_handle : Int,
  want_readable : Bool,
) -> Int64? {
  for kv in async_state.future_endpoints.iter() {
    let (k, ep) = kv
    if key_local(k) == local_handle && ep.is_readable == want_readable {
      return Some(k)
    }
  }
  None
}

///|
fn remove_waitable_membership(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
) -> Unit {
  let wkey = handle_key(owner_component_id, handle)
  if async_state.stream_table.endpoints.get(wkey) is Some(endpoint) {
    endpoint.in_waitable_set.val = false
  }
  if async_state.future_endpoints.get(wkey) is Some(endpoint) {
    endpoint.in_waitable_set.val = false
  }
  if async_state.waitable_to_set.get(wkey) is Some(ws_key) {
    async_state.waitable_to_set.remove(wkey)
    if async_state.waitable_sets.get(ws_key) is Some(set) {
      set.members.remove(handle)
      let mut i = 0
      while i < set.queue.length() {
        if set.queue[i].index == handle {
          set.queue.remove(i) |> ignore
        } else {
          i = i + 1
        }
      }
    }
  }
  async_state.waitable_events.remove(wkey)
}

///|
fn waitable_is_in_set(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
) -> Bool {
  async_state.waitable_to_set.get(handle_key(owner_component_id, handle))
  is Some(_)
}

///|
fn resume_sync_waitable_use(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
  task_id : Int64,
) -> Bool {
  let key = handle_key(owner_component_id, handle)
  if async_state.sync_waitable_users.get(key) is Some(owner_task_id) &&
    owner_task_id == task_id {
    async_state.sync_waitable_users.remove(key)
    true
  } else {
    false
  }
}

///|
fn mark_sync_waitable_blocked(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
  task_id : Int64,
) -> Unit {
  async_state.sync_waitable_users.set(
    handle_key(owner_component_id, handle),
    task_id,
  )
}

///|
fn waitable_is_in_sync_use(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
) -> Bool {
  async_state.sync_waitable_users.get(handle_key(owner_component_id, handle))
  is Some(_)
}

///|
/// Remove all queued events for the specified waitable matching `(code, index=handle)`.
/// Used to "overwrite" a previously queued completion event when a later state
/// transition (e.g. dropping the peer endpoint) must take precedence.
fn remove_waitable_events_for(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
  code : Int,
) -> Unit {
  let wkey = handle_key(owner_component_id, handle)
  if async_state.waitable_events.get(wkey) is Some(list0) {
    let list = list0
    let mut i = 0
    while i < list.length() {
      if list[i].code == code && list[i].index == handle {
        list.remove(i) |> ignore
      } else {
        i = i + 1
      }
    }
    if list.length() == 0 {
      async_state.waitable_events.remove(wkey)
    } else {
      async_state.waitable_events.set(wkey, list)
    }
  }
  if async_state.waitable_to_set.get(wkey) is Some(ws_key) &&
    async_state.waitable_sets.get(ws_key) is Some(set) {
    let mut i = 0
    while i < set.queue.length() {
      if set.queue[i].code == code && set.queue[i].index == handle {
        set.queue.remove(i) |> ignore
      } else {
        i = i + 1
      }
    }
  }
}

///|
fn acknowledge_waitable_event(async_state : AsyncState, ev : WaitEvent) -> Unit {
  // STREAM_READ=2 and STREAM_WRITE=3 use the stream endpoint handle as `index`.
  // When an event is delivered, clear the corresponding pending operation so
  // drop-readable/drop-writable can proceed and handle reuse does not see stale state.
  if ev.code == 2 {
    let ep_key = handle_key(ev.owner_component_id, ev.index)
    if async_state.stream_table.endpoints.get(ep_key) is Some(ep) {
      // If the event indicates the peer dropped, remember that this endpoint has
      // been notified so subsequent reads/lifts trap (component-spec "done" semantics).
      if (ev.payload.reinterpret_as_uint() & 1U) != 0U {
        ep.notified_peer_dropped[0] = true
      }
      if async_state.stream_table.streams.get(ep.stream_id) is Some(st0) &&
        st0.pending_read is Some(pr) &&
        pr.reader_handle == ev.index {
        async_state.stream_table.streams.set(ep.stream_id, {
          allows_intra_component: st0.allows_intra_component,
          pending_read: None,
          pending_write: st0.pending_write,
          readable_dropped: st0.readable_dropped,
          writable_dropped: st0.writable_dropped,
        })
      }
    }
  } else if ev.code == 3 {
    let ep_key = handle_key(ev.owner_component_id, ev.index)
    if async_state.stream_table.endpoints.get(ep_key) is Some(ep) {
      if (ev.payload.reinterpret_as_uint() & 1U) != 0U {
        ep.notified_peer_dropped[0] = true
      }
      if async_state.stream_table.streams.get(ep.stream_id) is Some(st0) &&
        st0.pending_write is Some(pw) &&
        pw.writer_handle == ev.index {
        async_state.stream_table.streams.set(ep.stream_id, {
          allows_intra_component: st0.allows_intra_component,
          pending_read: st0.pending_read,
          pending_write: None,
          readable_dropped: st0.readable_dropped,
          writable_dropped: st0.writable_dropped,
        })
      }
    }
  }
}

///|
fn validate_lifted_arguments(
  func_type : FuncType,
  args : Array[ComponentValue],
  types : Array[TypeDef?],
  async_state : AsyncState,
  owner_component_id : Int,
) -> Unit raise ComponentRuntimeError {
  for i, param in func_type.params {
    validate_lifted_stream_future(
      param.ty,
      args[i],
      types,
      async_state,
      owner_component_id,
    )
  }
}

///|
fn validate_lifted_stream_future(
  ty : ValType,
  v : ComponentValue,
  types : Array[TypeDef?],
  async_state : AsyncState,
  owner_component_id : Int,
) -> Unit raise ComponentRuntimeError {
  fn as_i32(v : ComponentValue) -> Int raise ComponentRuntimeError {
    match v {
      U32(n) => n
      S32(n) => n
      _ => raise HostCallError("type mismatch")
    }
  }

  match resolve_valtype(ty, types) {
    Prim(_) => ()
    TypeIdx(ti) =>
      match types.get(ti) {
        Some(Some(Tuple(tys))) =>
          match v {
            Tuple(items) =>
              for i in 0..<tys.length() {
                if i < items.length() {
                  validate_lifted_stream_future(
                    tys[i],
                    items[i],
                    types,
                    async_state,
                    owner_component_id,
                  )
                }
              }
            _ => ()
          }
        Some(Some(Record(fields))) =>
          match v {
            Tuple(items) =>
              for i in 0..<fields.length() {
                if i < items.length() {
                  validate_lifted_stream_future(
                    fields[i].ty,
                    items[i],
                    types,
                    async_state,
                    owner_component_id,
                  )
                }
              }
            _ => ()
          }
        Some(Some(List(elem_ty))) | Some(Some(FixedList(elem_ty, _))) =>
          match v {
            List(items) =>
              for it in items {
                validate_lifted_stream_future(
                  elem_ty, it, types, async_state, owner_component_id,
                )
              }
            _ => ()
          }
        Some(Some(Variant(cases))) =>
          match v {
            Variant(tag, payload) =>
              if tag >= 0 && tag < cases.length() {
                match cases[tag].ty {
                  Some(case_ty) =>
                    match payload {
                      Some(p) =>
                        validate_lifted_stream_future(
                          case_ty, p, types, async_state, owner_component_id,
                        )
                      None => ()
                    }
                  None => ()
                }
              }
            _ => ()
          }
        Some(Some(Option(elem_ty))) =>
          match v {
            Variant(tag, payload) =>
              if tag == 1 {
                match payload {
                  Some(p) =>
                    validate_lifted_stream_future(
                      elem_ty, p, types, async_state, owner_component_id,
                    )
                  None => ()
                }
              }
            _ => ()
          }
        Some(Some(Result(ok_ty, err_ty))) =>
          match v {
            Variant(tag, payload) =>
              if tag == 0 {
                match (ok_ty, payload) {
                  (Some(t), Some(p)) =>
                    validate_lifted_stream_future(
                      t, p, types, async_state, owner_component_id,
                    )
                  _ => ()
                }
              } else if tag == 1 {
                match (err_ty, payload) {
                  (Some(t), Some(p)) =>
                    validate_lifted_stream_future(
                      t, p, types, async_state, owner_component_id,
                    )
                  _ => ()
                }
              }
            _ => ()
          }
        Some(Some(Stream(_))) => {
          let h = as_i32(v)
          let k = handle_key(owner_component_id, h)
          match async_state.stream_table.endpoints.get(k) {
            None => raise CanonCallError("unknown stream handle index \{h}")
            Some(ep) =>
              if ep.notified_peer_dropped[0] {
                if ep.is_readable {
                  raise CanonCallError(
                    "cannot lift stream after being notified that the writable end dropped",
                  )
                } else {
                  raise CanonCallError(
                    "cannot lift stream after being notified that the readable end dropped",
                  )
                }
              } else if ep.in_waitable_set.val {
                raise CanonCallError(
                  "cannot lift stream while it's in a waitable set",
                )
              }
          }
        }
        Some(Some(Future(_))) => {
          let h = as_i32(v)
          let k = handle_key(owner_component_id, h)
          match async_state.future_endpoints.get(k) {
            None => raise CanonCallError("unknown future handle index \{h}")
            Some(ep) => {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => raise CanonCallError("unknown future handle index \{h}")
              }
              if ep.is_readable && st0.read_done {
                raise CanonCallError(
                  "cannot lift future after previous read succeeded",
                )
              }
              if !ep.is_readable && st0.write_succeeded {
                raise CanonCallError(
                  "cannot lift future after previous write succeeded",
                )
              }
              if ep.in_waitable_set.val {
                raise CanonCallError(
                  "cannot lift future while it's in a waitable set",
                )
              }
            }
          }
        }
        _ => ()
      }
  }
}

///|
fn transfer_stream_readable_handle(
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
  handle : Int,
) -> Int raise ComponentRuntimeError {
  if from_component_id == to_component_id {
    // Defensive: some call sites (notably sync-lowering + task.return paths) may not
    // precisely know which component instance produced a readable handle. If the
    // handle is not present in `from_component_id`'s table, search for the live
    // endpoint and move it into `to_component_id`.
    let k0 = handle_key(from_component_id, handle)
    if async_state.stream_table.endpoints.get(k0) is Some(_) {
      return handle
    }
    return match find_stream_endpoint_key_by_local(async_state, handle, true) {
      Some(found_key) => {
        let actual_from = key_owner(found_key)
        if actual_from == to_component_id {
          handle
        } else {
          transfer_stream_readable_handle(
            async_state, actual_from, to_component_id, handle,
          )
        }
      }
      None => handle
    }
  }
  let from_key = handle_key(from_component_id, handle)
  let ep = match async_state.stream_table.endpoints.get(from_key) {
    Some(e) => e
    None =>
      raise CanonCallError(
        "unknown stream handle index \{handle} (transfer from \{from_component_id} to \{to_component_id})",
      )
  }
  if ep.in_waitable_set.val {
    raise CanonCallError("cannot lift stream while it's in a waitable set")
  }
  async_state.stream_table.endpoints.remove(from_key)
  free_shared_handle(async_state, from_component_id, handle)
  let new_handle = alloc_shared_handle(async_state, to_component_id)
  async_state.stream_table.endpoints.set(
    handle_key(to_component_id, new_handle),
    {
      stream_id: ep.stream_id,
      is_readable: ep.is_readable,
      // Preserve \"done\" notification state across the move.
      notified_peer_dropped: ep.notified_peer_dropped,
      in_waitable_set: ep.in_waitable_set,
    },
  )
  new_handle
}

///|
/// Create a new readable stream handle in `to_component_id` that aliases the same stream as
/// `handle` in `from_component_id`, without removing the original mapping.
///
/// This publishes a result early via `canon task.return` while retaining the
/// callee's original handle for the still-running producer task.
fn clone_stream_readable_handle(
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
  handle : Int,
) -> Int raise ComponentRuntimeError {
  if from_component_id == to_component_id {
    return handle
  }
  let from_key = handle_key(from_component_id, handle)
  let ep = match async_state.stream_table.endpoints.get(from_key) {
    Some(e) => e
    None => raise CanonCallError("unknown stream handle index \{handle}")
  }
  let new_handle = alloc_shared_handle(async_state, to_component_id)
  async_state.stream_table.endpoints.set(
    handle_key(to_component_id, new_handle),
    {
      stream_id: ep.stream_id,
      is_readable: ep.is_readable,
      notified_peer_dropped: ep.notified_peer_dropped,
      in_waitable_set: ep.in_waitable_set,
    },
  )
  new_handle
}

///|
fn transfer_future_readable_handle(
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
  handle : Int,
) -> Int raise ComponentRuntimeError {
  if from_component_id == to_component_id {
    let k0 = handle_key(from_component_id, handle)
    if async_state.future_endpoints.get(k0) is Some(_) {
      return handle
    }
    return match find_future_endpoint_key_by_local(async_state, handle, true) {
      Some(found_key) => {
        let actual_from = key_owner(found_key)
        if actual_from == to_component_id {
          handle
        } else {
          transfer_future_readable_handle(
            async_state, actual_from, to_component_id, handle,
          )
        }
      }
      None => handle
    }
  }
  let from_key = handle_key(from_component_id, handle)
  let ep = match async_state.future_endpoints.get(from_key) {
    Some(e) => e
    None => raise CanonCallError("unknown future handle index \{handle}")
  }
  if ep.in_waitable_set.val {
    raise CanonCallError("cannot lift future while it's in a waitable set")
  }
  async_state.future_endpoints.remove(from_key)
  free_shared_handle(async_state, from_component_id, handle)
  let new_handle = alloc_shared_handle(async_state, to_component_id)
  async_state.future_endpoints.set(handle_key(to_component_id, new_handle), ep)
  new_handle
}

///|
/// Like `clone_stream_readable_handle`, but for futures.
fn clone_future_readable_handle(
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
  handle : Int,
) -> Int raise ComponentRuntimeError {
  if from_component_id == to_component_id {
    return handle
  }
  let from_key = handle_key(from_component_id, handle)
  let ep = match async_state.future_endpoints.get(from_key) {
    Some(e) => e
    None => raise CanonCallError("unknown future handle index \{handle}")
  }
  let new_handle = alloc_shared_handle(async_state, to_component_id)
  async_state.future_endpoints.set(handle_key(to_component_id, new_handle), ep)
  new_handle
}

///|
fn transfer_stream_future_value(
  ty : ValType,
  v : ComponentValue,
  types : Array[TypeDef?],
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
) -> ComponentValue raise ComponentRuntimeError {
  map_canonical_handles(ty, v, types, (definition, v) => {
    match definition {
      Own(resource_tyidx) =>
        match v {
          U32(handle) | S32(handle) =>
            if from_component_id == to_component_id {
              v
            } else {
              let from_table = match
                async_state.resource_tables.get(from_component_id) {
                Some(table) => table
                None => raise CanonCallError("unknown resource owner instance")
              }
              let to_table = match
                async_state.resource_tables.get(to_component_id) {
                Some(table) => table
                None => raise CanonCallError("unknown resource target instance")
              }
              let entry = match from_table.get(handle) {
                Some(entry) => entry
                None =>
                  raise CanonCallError(
                    "transfer own type \{resource_tyidx}: unknown handle index \{handle} in resource table \{from_component_id} -> \{to_component_id}",
                  )
              }
              guard types.get(resource_tyidx)
                is Some(Some(ResourceType(expected, _, _, _))) &&
                entry.type_id == expected else {
                raise CanonCallError(
                  "handle index \{handle} used with the wrong type",
                )
              }
              if !entry.own || entry.num_lends[0] > 0 {
                raise CanonCallError(
                  "cannot remove owned resource while borrowed",
                )
              }
              from_table.free(handle) |> ignore
              async_state.resource_tables.set(from_component_id, from_table)
              let new_handle = to_table.alloc(entry)
              async_state.resource_tables.set(to_component_id, to_table)
              U32(new_handle)
            }
          _ => v
        }
      Borrow(resource_tyidx) =>
        match v {
          ResourceValue(_) => v
          U32(handle) | S32(handle) => {
            let from_table = match
              async_state.resource_tables.get(from_component_id) {
              Some(table) => table
              None => raise CanonCallError("unknown resource owner instance")
            }
            let entry = match from_table.get(handle) {
              Some(entry) => entry
              None =>
                raise CanonCallError(
                  "transfer borrow: unknown handle index \{handle} in resource table \{from_component_id}",
                )
            }
            guard types.get(resource_tyidx)
              is Some(Some(ResourceType(expected, _, _, _))) &&
              entry.type_id == expected else {
              raise CanonCallError(
                "handle index \{handle} used with the wrong type",
              )
            }
            if to_component_id == entry.impl_component_id {
              ResourceValue(entry.rep)
            } else if from_component_id == to_component_id {
              v
            } else {
              let to_table = match
                async_state.resource_tables.get(to_component_id) {
                Some(table) => table
                None => raise CanonCallError("unknown resource target instance")
              }
              let task_id = current_task_id(async_state)
              entry.num_lends[0] += 1
              let count = match async_state.tasks.read_task_borrows(task_id) {
                Some(n) => n
                None => 0
              }
              async_state.tasks.write_task_borrows(task_id, count + 1)
              let new_handle = to_table.alloc({
                type_id: entry.type_id,
                rep: entry.rep,
                dtor: entry.dtor,
                host_dtor: entry.host_dtor,
                kind: entry.kind,
                impl_component_id: entry.impl_component_id,
                own: false,
                borrow_scope: Some(task_id),
                num_lends: entry.num_lends,
              })
              async_state.resource_tables.set(to_component_id, to_table)
              U32(new_handle)
            }
          }
          _ => v
        }
      Stream(_) =>
        match v {
          U32(h) =>
            U32(
              transfer_stream_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          S32(h) =>
            S32(
              transfer_stream_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          _ => v
        }
      Future(_) =>
        match v {
          U32(h) =>
            U32(
              transfer_future_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          S32(h) =>
            S32(
              transfer_future_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          _ => v
        }
      _ => v
    }
  })
}

///|
fn collect_direct_borrow_lends(
  ty : ValType,
  v : ComponentValue,
  types : Array[TypeDef?],
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
  lends : Array[Array[Int]],
) -> Unit raise ComponentRuntimeError {
  map_canonical_handles(ty, v, types, (definition, v) => {
    match definition {
      Borrow(_) =>
        match v {
          U32(handle) | S32(handle) => {
            let from_table = match
              async_state.resource_tables.get(from_component_id) {
              Some(table) => table
              None => raise CanonCallError("unknown resource owner instance")
            }
            let entry = match from_table.get(handle) {
              Some(entry) => entry
              None =>
                raise CanonCallError(
                  "transfer borrow: unknown handle index \{handle} in resource table \{from_component_id}",
                )
            }
            if to_component_id == entry.impl_component_id {
              entry.num_lends[0] += 1
              lends.push(entry.num_lends)
            }
          }
          _ => ()
        }
      _ => ()
    }
    v
  })
  |> ignore
}

///|
/// Clone any stream/future readable handles found in `v` from `from_component_id` into
/// `to_component_id`, preserving the original handles in the source component.
fn clone_stream_future_value(
  ty : ValType,
  v : ComponentValue,
  types : Array[TypeDef?],
  async_state : AsyncState,
  from_component_id : Int,
  to_component_id : Int,
) -> ComponentValue raise ComponentRuntimeError {
  if from_component_id == to_component_id {
    return v
  }
  map_canonical_handles(ty, v, types, (definition, v) => {
    match definition {
      Stream(_) =>
        match v {
          U32(h) =>
            U32(
              clone_stream_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          S32(h) =>
            S32(
              clone_stream_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          _ => v
        }
      Future(_) =>
        match v {
          U32(h) =>
            U32(
              clone_future_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          S32(h) =>
            S32(
              clone_future_readable_handle(
                async_state, from_component_id, to_component_id, h,
              ),
            )
          _ => v
        }
      _ => v
    }
  })
}

///|
fn alloc_shared_handle_with_source(
  async_state : AsyncState,
  component_id : Int,
) -> (Int, Bool) {
  if async_state.resource_tables.get(component_id) is Some(table) {
    return alloc_handle_index(table.next_handle, table.free_handles)
  }
  let next = match async_state.next_handle_by_component.get(component_id) {
    Some(a) => a
    None => {
      let a = [1]
      async_state.next_handle_by_component.set(component_id, a)
      a
    }
  }
  let free = match async_state.free_handles_by_component.get(component_id) {
    Some(xs) => xs
    None => {
      let xs : Array[Int] = []
      async_state.free_handles_by_component.set(component_id, xs)
      xs
    }
  }
  if free.length() > 0 {
    // Deterministic allocation: reuse the smallest available handle so suites
    // relying on stable numbering (component-spec/async) behave consistently.
    let mut best_i = 0
    let mut best = free[0]
    for i in 1..<free.length() {
      let h = free[i]
      if h < best {
        best = h
        best_i = i
      }
    }
    free.remove(best_i) |> ignore
    (best, true)
  } else {
    let h = next[0]
    next[0] = h + 1
    (h, false)
  }
}

///|
fn backpressure_value_for_instance(
  async_state : AsyncState,
  component_id : Int,
) -> Int {
  match async_state.backpressure_by_instance.get(component_id) {
    Some(v) => v
    None => 0
  }
}

///|
fn set_backpressure_value_for_instance(
  async_state : AsyncState,
  component_id : Int,
  value : Int,
) -> Unit {
  if value <= 0 {
    async_state.backpressure_by_instance.remove(component_id)
  } else {
    async_state.backpressure_by_instance.set(component_id, value)
  }
}

///|
fn ResourceTable::alloc_error_context(
  self : ResourceTable,
  message : String,
) -> Int {
  let handle = self.next_error_context.val
  self.next_error_context.val += 1
  self.error_contexts.set(handle, message)
  handle
}

///|
fn ResourceTable::drop_error_context(
  self : ResourceTable,
  handle : Int,
) -> Bool {
  if self.error_contexts.get(handle) is Some(_) {
    self.error_contexts.remove(handle)
    true
  } else {
    false
  }
}

///|
fn alloc_shared_handle(async_state : AsyncState, component_id : Int) -> Int {
  let (h, _from_free) = alloc_shared_handle_with_source(
    async_state, component_id,
  )
  h
}

///|
fn free_shared_handle(
  async_state : AsyncState,
  component_id : Int,
  handle : Int,
) -> Unit {
  // Handle 0 is invalid; never recycle it.
  if handle > 0 {
    if async_state.resource_tables.get(component_id) is Some(table) {
      table.free_handles.val.push(handle)
      return
    }
    let free = match async_state.free_handles_by_component.get(component_id) {
      Some(xs) => xs
      None => {
        let xs : Array[Int] = []
        async_state.free_handles_by_component.set(component_id, xs)
        xs
      }
    }
    free.push(handle)
  }
}

///|
fn current_task_id(async_state : AsyncState) -> Int64 {
  if async_state.task_stack.length() == 0 {
    0L
  } else {
    async_state.task_stack[async_state.task_stack.length() - 1]
  }
}

///|
fn init_task_meta(
  async_state : AsyncState,
  task_id : Int64,
  instance_id : Int,
  caller_task_id : Int64,
) -> Unit {
  async_state.tasks.write_task_instance(task_id, instance_id)
  async_state.tasks.write_task_caller(task_id, caller_task_id)
}

///|
fn async_call_can_enter(func : ComponentFunc, async_state : AsyncState) -> Bool {
  match func {
    Lifted(_, _, _, _, table, entry, _, _) =>
      entry.may_start_async() && !instance_has_sync_wait(async_state, table.id)
    Host(_, _, _) | HostAsync(_, _, _) => true
  }
}

///|
fn instance_has_sync_wait(async_state : AsyncState, instance_id : Int) -> Bool {
  for entry in async_state.sync_waitable_users {
    let (_, task_id) = entry
    if async_state.tasks.read_task_instance(task_id) == Some(instance_id) {
      return true
    }
  }
  false
}

///|
fn sync_waitables_for_task(
  async_state : AsyncState,
  task_id : Int64,
) -> Array[Int64] {
  let keys : Array[Int64] = []
  for entry in async_state.sync_waitable_users {
    let (key, owner) = entry
    if owner == task_id {
      keys.push(key)
    }
  }
  keys
}

///|
fn ensure_task_thread(
  async_state : AsyncState,
  owner_component_id : Int,
  task_id : Int64,
) -> Unit {
  let per_task = match async_state.tasks.read_task_thread(task_id) {
    Some(m) => m
    None => {
      let m : Map[Int, Int] = Map([])
      async_state.tasks.write_task_thread(task_id, m)
      m
    }
  }
  if per_task.get(owner_component_id) is Some(_) {
    return
  }
  let th = alloc_shared_handle(async_state, owner_component_id)
  per_task.set(owner_component_id, th)
}

///|
fn drop_task_thread(async_state : AsyncState, task_id : Int64) -> Unit {
  if async_state.tasks.read_task_thread(task_id) is Some(m) {
    async_state.tasks.clear_task_thread(task_id)
    for entry in m {
      let (owner_component_id, th) = entry
      free_shared_handle(async_state, owner_component_id, th)
    }
  }
}

///|
fn alloc_task_id(async_state : AsyncState) -> Int64 raise ComponentRuntimeError {
  async_state.tasks.allocate()
}

///|
fn push_task(
  async_state : AsyncState,
  id : Int64,
  can_block : Bool,
) -> Unit raise ComponentRuntimeError {
  let id = async_state.tasks.resolve(id)
  guard !async_state.tasks.closed.val &&
    async_state.tasks.records.get(id) is Some(_) else {
    raise Cancelled
  }
  async_state.task_stack.push(id)
  async_state.can_block_stack.push(can_block)
  async_state.task_can_block[0] = can_block
}

///|
fn pop_task(async_state : AsyncState) -> Unit {
  if async_state.task_stack.length() > 0 {
    async_state.task_stack.remove(async_state.task_stack.length() - 1) |> ignore
  }
  if async_state.can_block_stack.length() > 0 {
    async_state.can_block_stack.remove(async_state.can_block_stack.length() - 1)
    |> ignore
  }
  if async_state.can_block_stack.length() == 0 {
    async_state.task_can_block[0] = false
  } else {
    async_state.task_can_block[0] = async_state.can_block_stack[async_state.can_block_stack.length() -
      1]
  }
}

///|
fn set_task_result(
  async_state : AsyncState,
  task_id : Int64,
  owner_component_id : Int,
  vals : Array[ComponentValue],
) -> Unit {
  async_state.tasks.write_task_results(task_id, vals)
  async_state.tasks.write_task_result_owner(task_id, owner_component_id)
}

///|
fn take_task_result(
  async_state : AsyncState,
  task_id : Int64,
) -> Array[ComponentValue]? {
  let v = async_state.tasks.read_task_results(task_id)
  if v is Some(_) {
    async_state.tasks.clear_task_results(task_id)
  }
  v
}

///|
fn enqueue_waitable_event(
  async_state : AsyncState,
  waitable_key : Int64,
  ev : WaitEvent,
) -> Unit {
  let list = match async_state.waitable_events.get(waitable_key) {
    Some(xs) => xs
    None => []
  }
  // A subtask exposes its latest unconsumed status, not a history of states.
  if ev.code == 1 {
    for i in 0..<list.length() {
      if list[i].code == 1 {
        list[i] = ev
        if async_state.waitable_to_set.get(waitable_key) is Some(ws_key) &&
          async_state.waitable_sets.get(ws_key) is Some(set) {
          for j in 0..<set.queue.length() {
            let previous = set.queue[j]
            if previous.code == 1 &&
              previous.owner_component_id == ev.owner_component_id &&
              previous.index == ev.index {
              set.queue[j] = ev
            }
          }
        }
        return
      }
    }
  }
  list.push(ev)
  async_state.waitable_events.set(waitable_key, list)
  if async_state.waitable_to_set.get(waitable_key) is Some(ws_key) &&
    async_state.waitable_sets.get(ws_key) is Some(set) {
    set.queue.push(ev)
  }
}

///|
fn pop_waitable_event(async_state : AsyncState, ws_key : Int64) -> WaitEvent? {
  match async_state.waitable_sets.get(ws_key) {
    None => None
    Some(set) =>
      if set.queue.length() == 0 {
        None
      } else {
        let ev = set.queue.remove(0)
        // Consume from the per-waitable backlog as well.
        let wkey = handle_key(ev.owner_component_id, ev.index)
        if async_state.waitable_events.get(wkey) is Some(list0) &&
          list0.length() > 0 {
          list0.remove(0) |> ignore
          if list0.length() == 0 {
            async_state.waitable_events.remove(wkey)
          } else {
            async_state.waitable_events.set(wkey, list0)
          }
        }
        Some(ev)
      }
  }
}

///|

///|
enum TaskSuspension {
  Yield(Bool)
  Suspend(Bool)
  Wait(Bool)
} derive(Debug)

///|
pub extend TaskSuspension with Debug::{to_repr}

///|
fn TaskSuspension::is_cancellable(self : TaskSuspension) -> Bool {
  match self {
    Yield(cancellable) | Suspend(cancellable) | Wait(cancellable) => cancellable
  }
}

///|
fn AsyncState::check_host_entry(
  self : AsyncState,
) -> Unit raise ComponentRuntimeError {
  if self.trapped.val {
    raise CanonCallError("cannot enter component instance")
  }
}
