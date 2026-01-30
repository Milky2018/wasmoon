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
  ErrorContext(String)
  List(Array[ComponentValue])
  Tuple(Array[ComponentValue])
  /// Canonical ABI representation for variants/options/results.
  /// `tag` is the case index, and `payload` is the case payload (if any).
  Variant(Int, ComponentValue?)
} derive(Show, Eq)

///|
pub(all) struct CoreFuncRef {
  instance : @runtime.ModuleInstance
  func_idx : Int
} derive(Show)

///|
struct CanonResources {
  mem_addr : Int?
  realloc : CoreFuncRef?
  post_return : CoreFuncRef?
  encoding : StringEncoding
} derive(Show)

///|
pub(all) struct ResourceHandle {
  type_id : Int
  rep : Int
  dtor : CoreFuncRef?
  kind : ResourceKind
} derive(Show)

///|
pub(all) struct ResourceTable {
  id : Int
  next_handle : Array[Int]
  free_handles : Array[Int]
  entries : Map[Int, ResourceHandle]
} derive(Show)

///|
let resource_table_id_counter : Array[Int] = [0]

///|
pub fn ResourceTable::new() -> ResourceTable {
  let id = resource_table_id_counter[0]
  resource_table_id_counter[0] = id + 1
  // Handle 0 is always invalid; the first valid allocation is 1.
  { id, next_handle: [1], free_handles: [], entries: {} }
}

///|
pub fn ResourceTable::alloc(
  self : ResourceTable,
  entry : ResourceHandle,
) -> Int {
  let handle = if self.free_handles.length() > 0 {
    self.free_handles.remove(self.free_handles.length() - 1)
  } else {
    let h = self.next_handle[0]
    self.next_handle[0] = h + 1
    h
  }
  self.entries.set(handle, entry)
  handle
}

///|
pub fn ResourceTable::get(
  self : ResourceTable,
  handle : Int,
) -> ResourceHandle? {
  self.entries.get(handle)
}

///|
pub fn ResourceTable::free(
  self : ResourceTable,
  handle : Int,
) -> ResourceHandle? {
  let entry = self.entries.get(handle)
  match entry {
    Some(_) => {
      self.entries.remove(handle)
      self.free_handles.push(handle)
    }
    None => ()
  }
  entry
}

///|
pub(all) struct StreamEndpoint {
  stream_id : Int
  is_readable : Bool
  // Set once an operation observed that the opposite end was dropped; subsequent
  // reads/writes/lifts should trap (component-spec "done" semantics).
  notified_peer_dropped : Array[Bool]
} derive(Show)

///|
struct PendingStreamRead {
  // Memory where the read buffer lives (from the canonical options of stream.read).
  // Writes can come from a different component instance/memory, so we must keep
  // enough info to write into the *reader* memory.
  mem_addr : Int?
  // Resource table of the reader component instance (used to transfer `own` resources).
  reader_table : ResourceTable
  ptr : Int
  // Element count requested by the read.
  len : Int
  // Number of elements already written into the buffer.
  filled : Int
  // Readable endpoint handle (waitable index) that initiated this pending read.
  reader_handle : Int
  // Whether we've already enqueued a STREAM_READ event for this pending read.
  event_enqueued : Bool
} derive(Show)

///|
struct PendingStreamWrite {
  // Resource table of the writer component instance (used to transfer `own` resources).
  writer_table : ResourceTable
  // Canonical payload bytes. For streams of `own` resources this encodes the original
  // writer-side handle indices (i32 little-endian per element).
  buf : Array[Byte]
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
} derive(Show)

///|
struct StreamState {
  // Size in bytes of one element in the canonical stream read/write buffers.
  elem_size : Int
  // If `Some`, the stream payload is an `own` resource of this type id and reads
  // must transfer ownership between resource tables.
  own_resource_type_id : Int?
  pending_read : PendingStreamRead?
  pending_write : PendingStreamWrite?
  readable_dropped : Bool
  writable_dropped : Bool
} derive(Show)

///|
pub(all) struct StreamTable {
  next_stream_id : Array[Int]
  // Keyed by `handle_key(component_id, local_handle)`.
  endpoints : Map[Int64, StreamEndpoint]
  streams : Map[Int, StreamState]
} derive(Show)

///|
pub fn StreamTable::new() -> StreamTable {
  { next_stream_id: [0], endpoints: {}, streams: {} }
}

///|
/// Async/task/waitable state shared across a whole component instantiation tree.
///
/// Waitable/stream/future/subtask handle numbers are per component instance (resource_table.id).
/// Internally we key maps by `handle_key(component_id, local_handle)` to avoid collisions.
pub(all) struct AsyncState {
  // Per-component handle allocator for waitables/streams/futures/subtasks/threads.
  // Handle 0 is invalid; allocation starts at 1 (matches component model ABI).
  next_handle_by_component : Map[Int, Array[Int]]
  free_handles_by_component : Map[Int, Array[Int]]
  // Shared stream table (streams share the same handle space as waitables/subtasks).
  stream_table : StreamTable

  // Task stack + per-task state (used by canon task.return/context.*).
  task_stack : Array[Int64]
  next_task_id : Array[Int64]
  task_results : Map[Int64, Array[ComponentValue]]
  // Component instance id whose handle numbering is used by `task_results`.
  // For `canon task.return`, this is the component instance where the intrinsic lives.
  task_result_owner : Map[Int64, Int]
  task_returned : Map[Int64, Bool]
  task_cancelled : Map[Int64, Bool]
  task_contexts : Map[Int64, Map[Int, @types.Value]]
  // Synthetic implicit thread handles for each running task, keyed by the
  // component instance id where the thread handle lives.
  //
  // Wasmtime inserts the current guest thread into the callee instance's handle
  // table. A single task can enter multiple component instances, so model this
  // as a per-task map.
  task_thread : Map[Int64, Map[Int, Int]]

  // Whether the currently executing task is allowed to block.
  task_can_block : Array[Bool]
  can_block_stack : Array[Bool]

  // True while executing an async callback (used to conservatively reject re-entrancy).
  in_async_callback : Array[Bool]

  // Per-invocation ordinals for restartable sync-style suspension points.
  yield_cursor_stack : Array[Int]
  wait_cursor_stack : Array[Int]
  // Per-invocation ordinal for restartable non-suspending operations that must be replay-safe.
  call_cursor_stack : Array[Int]
  // Per-invocation ordinal for stream.read/write restartability (kept separate from
  // `call_cursor_stack` to avoid collisions with non-i32 canonical calls like `stream.new`).
  stream_cursor_stack : Array[Int]

  // Task tree metadata used to prevent async re-entrancy into the same component
  // instance (mirrors Wasmtime's ConcurrentState::may_enter).
  //
  // For root (host) tasks, `task_caller[task_id] == 0`.
  task_caller : Map[Int64, Int64]
  // Component instance id (ResourceTable.id) associated with this task.
  task_instance : Map[Int64, Int]
  // Replay/memoization state keyed by task id.
  yield_replay_upto : Map[Int64, Int]
  wait_results : Map[Int64, Map[Int, WaitResult]]
  waiting_ws : Map[Int64, Int64]
  call_results : Map[Int64, Map[Int, Array[@types.Value]]]
  stream_results : Map[Int64, Map[Int, Int]]
  // Separate stream read/write memoization for callback invocations to avoid
  // colliding with the initial core function body in callback-style async ABI.
  stream_results_cb : Map[Int64, Map[Int, Int]]
  // Sync-lower resumption state (keyed by task id + call cursor).
  sync_lower_states : Map[Int64, Map[Int, SyncLowerState]]

  // Waitable sets and event queues.
  waitable_sets : Map[Int64, WaitableSet]
  waitable_to_set : Map[Int64, Int64]
  waitable_events : Map[Int64, Array[WaitEvent]]

  // Subtasks created by `canon lower ... async`.
  subtasks : Map[Int64, Subtask]
  inflight_by_instance : Map[Int, Int]
  pending_by_instance : Map[Int, Array[Int64]]

  // Futures created by `canon future.new`.
  next_future_id : Array[Int]
  futures : Map[Int, FutureState]
  future_endpoints : Map[Int64, FutureEndpoint]

  // Component instances that require reserving a "current thread" handle slot
  // even for synchronous tasks (affects stream/future handle numbering in
  // component-spec/async).
  thread_handle_required : Map[Int, Bool]
} derive(Show)

///|
struct WaitEvent {
  // Component instance id where this waitable index is valid.
  owner_component_id : Int
  code : Int
  index : Int
  payload : Int
} derive(Show)

///|
/// Cached `waitable-set.wait` result for replay.
///
/// For SUBTASK+RETURNED events we also cache the return buffer slot, so replay
/// remains correct even if subtask handles are later reused.
struct WaitResult {
  ev : WaitEvent
  subtask_mem_addr : Int?
  subtask_retptr : Int
  // Scalar return value written at `subtask_retptr` (currently only used for i32 results).
  subtask_i32 : Int?
} derive(Show)

///|
struct WaitableSet {
  // Local index (per component instance).
  id : Int
  members : Map[Int, Bool]
  queue : Array[WaitEvent]
  // Number of active waiters; dropping a set with waiters traps.
  waiters : Array[Int]
} derive(Show)

///|
struct FutureEndpoint {
  future_id : Int
  is_readable : Bool
  // Component instance id where this future was created (resource_table.id).
  creator_component_id : Int
} derive(Show)

///|
struct PendingFutureRead {
  // Memory where the read pointer lives (from the canonical options of future.read).
  // Writes can come from a different component instance/memory.
  mem_addr : Int?
  // For typed futures, write the payload at `ptr`.
  ptr : Int
  // The readable endpoint that initiated this pending read.
  reader_component_id : Int
  reader_handle : Int
} derive(Show)

///|
struct PendingFutureWrite {
  // The writable endpoint that initiated this pending write.
  writer_component_id : Int
  writer_handle : Int
  // Pending write value (already loaded from memory if needed).
  val : Int
} derive(Show)

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
  // Tracks writer state for trap-if-done:
  // - `write_succeeded` => "cannot write to future after previous write succeeded"
  // - `write_observed_readable_drop` => "cannot write to future after previous write succeeded or readable end dropped"
  write_succeeded : Bool
  write_observed_readable_drop : Bool
  // True once a value has been provided via `future.write` (even if it blocked).
  wrote_value : Bool
} derive(Show)

///|
enum SubtaskPhase {
  Starting
  Started
  Returned
} derive(Show, Eq)

///|
enum SubtaskDriver {
  // Not yet started: execute by calling `await_component_func` once.
  WaitLifted(ComponentFunc, Array[ComponentValue])
  // Callback-driven: step using callback codes and waitable-set events.
  CallbackLifted(CallbackTask)
} derive(Show)

///|
enum TaskStep {
  Blocked
  Progressed
  Done
} derive(Show, Eq)

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
  // Latest callback code from the core task or callback.
  code : Array[Int]
  // Waitable-set key (handle_key(owner_component_id, local_index)).
  waiting_set : Array[Int64?]
  cancelled : Array[Bool]
} derive(Show)

///|
struct SyncLowerState {
  task_id : Int64
  task : CallbackTask
} derive(Show)

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
  retptr : Int
  mem_addr : Int?
  result_ty : ValType?
  types : Array[TypeDef?]
  resources : CanonResources
  driver : SubtaskDriver
} derive(Show)

///|
pub fn AsyncState::new(stream_table : StreamTable) -> AsyncState {
  {
    next_handle_by_component: {},
    free_handles_by_component: {},
    stream_table,
    task_stack: [0L],
    // Use negative ids for internal tasks so they don't collide with the shared handle space.
    next_task_id: [-1L],
    task_results: {},
    task_result_owner: {},
    task_returned: {},
    task_cancelled: {},
    task_contexts: {},
    task_thread: {},
    task_can_block: [false],
    can_block_stack: [false],
    in_async_callback: [false],
    yield_cursor_stack: [0],
    wait_cursor_stack: [0],
    call_cursor_stack: [0],
    stream_cursor_stack: [0],
    task_caller: {},
    task_instance: {},
    yield_replay_upto: {},
    wait_results: {},
    waiting_ws: {},
    call_results: {},
    stream_results: {},
    stream_results_cb: {},
    sync_lower_states: {},
    waitable_sets: {},
    waitable_to_set: {},
    waitable_events: {},
    subtasks: {},
    inflight_by_instance: {},
    pending_by_instance: {},
    next_future_id: [0],
    futures: {},
    future_endpoints: {},
    thread_handle_required: {},
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
fn find_future_endpoint_key(
  async_state : AsyncState,
  future_id : Int,
  want_readable : Bool,
) -> Int64? {
  for kv in async_state.future_endpoints.iter() {
    let (k, ep) = kv
    if ep.future_id == future_id && ep.is_readable == want_readable {
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
  match async_state.waitable_to_set.get(wkey) {
    Some(ws_key) => {
      async_state.waitable_to_set.remove(wkey)
      match async_state.waitable_sets.get(ws_key) {
        Some(set) => {
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
        None => ()
      }
    }
    None => ()
  }
  async_state.waitable_events.remove(wkey)
}

///|
fn update_waitable_event_payload(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
  code : Int,
  payload : Int,
) -> Unit {
  let wkey = handle_key(owner_component_id, handle)
  // Update per-waitable backlog.
  match async_state.waitable_events.get(wkey) {
    Some(list) => {
      for i in 0..<list.length() {
        if list[i].code == code && list[i].index == handle {
          list[i] = { owner_component_id, code, index: handle, payload }
        }
      }
      async_state.waitable_events.set(wkey, list)
    }
    None => ()
  }
  // Update set queue (if currently joined).
  match async_state.waitable_to_set.get(wkey) {
    Some(ws_key) =>
      match async_state.waitable_sets.get(ws_key) {
        Some(set) =>
          for i in 0..<set.queue.length() {
            if set.queue[i].code == code && set.queue[i].index == handle {
              set.queue[i] = {
                owner_component_id,
                code,
                index: handle,
                payload,
              }
            }
          }
        None => ()
      }
    None => ()
  }
}

///|
/// Ensure that the specified waitable has an event of the given `(code, index=handle)`
/// with `payload`. If it already exists, update it in-place; otherwise, enqueue it.
///
/// This mirrors Wasmtime's `ConcurrentState::update_event` behavior (single logical
/// event per waitable) while we internally represent events as per-waitable queues.
fn force_waitable_event_payload(
  async_state : AsyncState,
  owner_component_id : Int,
  handle : Int,
  code : Int,
  payload : Int,
) -> Unit {
  let wkey = handle_key(owner_component_id, handle)
  let mut found = false
  // Update per-waitable backlog.
  match async_state.waitable_events.get(wkey) {
    Some(list0) => {
      let list = list0
      for i in 0..<list.length() {
        if list[i].code == code && list[i].index == handle {
          list[i] = { owner_component_id, code, index: handle, payload }
          found = true
        }
      }
      async_state.waitable_events.set(wkey, list)
    }
    None => ()
  }
  // Update set queue (if currently joined).
  match async_state.waitable_to_set.get(wkey) {
    Some(ws_key) =>
      match async_state.waitable_sets.get(ws_key) {
        Some(set) =>
          for i in 0..<set.queue.length() {
            if set.queue[i].code == code && set.queue[i].index == handle {
              set.queue[i] = {
                owner_component_id,
                code,
                index: handle,
                payload,
              }
              found = true
            }
          }
        None => ()
      }
    None => ()
  }
  if !found {
    enqueue_waitable_event(async_state, wkey, {
      owner_component_id,
      code,
      index: handle,
      payload,
    })
  }
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
  match async_state.waitable_events.get(wkey) {
    Some(list0) => {
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
    None => ()
  }
  match async_state.waitable_to_set.get(wkey) {
    Some(ws_key) =>
      match async_state.waitable_sets.get(ws_key) {
        Some(set) => {
          let mut i = 0
          while i < set.queue.length() {
            if set.queue[i].code == code && set.queue[i].index == handle {
              set.queue.remove(i) |> ignore
            } else {
              i = i + 1
            }
          }
        }
        None => ()
      }
    None => ()
  }
}

///|
fn acknowledge_waitable_event(async_state : AsyncState, ev : WaitEvent) -> Unit {
  // STREAM_READ=2 and STREAM_WRITE=3 use the stream endpoint handle as `index`.
  // When an event is delivered, clear the corresponding pending operation so
  // drop-readable/drop-writable can proceed and handle reuse does not see stale state.
  if ev.code == 2 {
    let ep_key = handle_key(ev.owner_component_id, ev.index)
    match async_state.stream_table.endpoints.get(ep_key) {
      Some(ep) => {
        // If the event indicates the peer dropped, remember that this endpoint has
        // been notified so subsequent reads/lifts trap (component-spec "done" semantics).
        if (ev.payload.reinterpret_as_uint() & 1U) != 0U {
          ep.notified_peer_dropped[0] = true
        }
        match async_state.stream_table.streams.get(ep.stream_id) {
          Some(st0) =>
            match st0.pending_read {
              Some(pr) =>
                if pr.reader_handle == ev.index {
                  async_state.stream_table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: None,
                    pending_write: st0.pending_write,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                  })
                }
              None => ()
            }
          None => ()
        }
      }
      None => ()
    }
  } else if ev.code == 3 {
    let ep_key = handle_key(ev.owner_component_id, ev.index)
    match async_state.stream_table.endpoints.get(ep_key) {
      Some(ep) => {
        if (ev.payload.reinterpret_as_uint() & 1U) != 0U {
          ep.notified_peer_dropped[0] = true
        }
        match async_state.stream_table.streams.get(ep.stream_id) {
          Some(st0) =>
            match st0.pending_write {
              Some(pw) =>
                if pw.writer_handle == ev.index {
                  async_state.stream_table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: st0.pending_read,
                    pending_write: None,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                  })
                }
              None => ()
            }
          None => ()
        }
      }
      None => ()
    }
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
      ComponentValue::U32(n) => n
      ComponentValue::S32(n) => n
      _ => raise HostCallError("type mismatch")
    }
  }

  match resolve_valtype(ty, types) {
    Prim(_) => ()
    TypeIdx(ti) =>
      match types.get(ti) {
        Some(Some(TypeDef::Tuple(tys))) =>
          match v {
            ComponentValue::Tuple(items) =>
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
        Some(Some(TypeDef::Record(fields))) =>
          match v {
            ComponentValue::Tuple(items) =>
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
        Some(Some(TypeDef::List(elem_ty))) =>
          match v {
            ComponentValue::List(items) =>
              for it in items {
                validate_lifted_stream_future(
                  elem_ty, it, types, async_state, owner_component_id,
                )
              }
            _ => ()
          }
        Some(Some(TypeDef::Variant(cases))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
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
        Some(Some(TypeDef::Option(elem_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
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
        Some(Some(TypeDef::Result(ok_ty, err_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
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
        Some(Some(TypeDef::Stream(_))) => {
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
              }
          }
        }
        Some(Some(TypeDef::Future(_))) => {
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
  // Drop any waitable-set membership and recycle the local handle in the source component.
  remove_waitable_membership(async_state, from_component_id, handle)
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
    },
  )
  new_handle
}

///|
/// Create a new readable stream handle in `to_component_id` that aliases the same stream as
/// `handle` in `from_component_id`, without removing the original mapping.
///
/// This is used to publish results early (via `canon task.return`) while the task may still be
/// cooperatively replayed, so the callee must retain the original handle for idempotency checks.
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
  remove_waitable_membership(async_state, from_component_id, handle)
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
  match resolve_valtype(ty, types) {
    Prim(_) => v
    TypeIdx(ti) =>
      match types.get(ti) {
        Some(Some(TypeDef::Tuple(tys))) =>
          match v {
            ComponentValue::Tuple(items) => {
              let out : Array[ComponentValue] = []
              for i in 0..<items.length() {
                let ty0 = if i < tys.length() {
                  tys[i]
                } else {
                  tys[tys.length() - 1]
                }
                out.push(
                  transfer_stream_future_value(
                    ty0,
                    items[i],
                    types,
                    async_state,
                    from_component_id,
                    to_component_id,
                  ),
                )
              }
              ComponentValue::Tuple(out)
            }
            _ => v
          }
        Some(Some(TypeDef::Record(fields))) =>
          match v {
            ComponentValue::Tuple(items) => {
              let out : Array[ComponentValue] = []
              for i in 0..<items.length() {
                let ty0 = if i < fields.length() {
                  fields[i].ty
                } else {
                  fields[fields.length() - 1].ty
                }
                out.push(
                  transfer_stream_future_value(
                    ty0,
                    items[i],
                    types,
                    async_state,
                    from_component_id,
                    to_component_id,
                  ),
                )
              }
              ComponentValue::Tuple(out)
            }
            _ => v
          }
        Some(Some(TypeDef::List(elem_ty))) =>
          match v {
            ComponentValue::List(items) => {
              let out : Array[ComponentValue] = []
              for it in items {
                out.push(
                  transfer_stream_future_value(
                    elem_ty, it, types, async_state, from_component_id, to_component_id,
                  ),
                )
              }
              ComponentValue::List(out)
            }
            _ => v
          }
        Some(Some(TypeDef::Variant(cases))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag >= 0 && tag < cases.length() {
                match (cases[tag].ty, payload) {
                  (Some(t), Some(p)) =>
                    ComponentValue::Variant(
                      tag,
                      Some(
                        transfer_stream_future_value(
                          t, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              } else {
                v
              }
            _ => v
          }
        Some(Some(TypeDef::Option(elem_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag == 1 {
                match payload {
                  Some(p) =>
                    ComponentValue::Variant(
                      1,
                      Some(
                        transfer_stream_future_value(
                          elem_ty, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  None => v
                }
              } else {
                v
              }
            _ => v
          }
        Some(Some(TypeDef::Result(ok_ty, err_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag == 0 {
                match (ok_ty, payload) {
                  (Some(t), Some(p)) =>
                    ComponentValue::Variant(
                      0,
                      Some(
                        transfer_stream_future_value(
                          t, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              } else if tag == 1 {
                match (err_ty, payload) {
                  (Some(t), Some(p)) =>
                    ComponentValue::Variant(
                      1,
                      Some(
                        transfer_stream_future_value(
                          t, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              } else {
                v
              }
            _ => v
          }
        Some(Some(TypeDef::Stream(_))) =>
          match v {
            ComponentValue::U32(h) =>
              ComponentValue::U32(
                transfer_stream_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            ComponentValue::S32(h) =>
              ComponentValue::S32(
                transfer_stream_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            _ => v
          }
        Some(Some(TypeDef::Future(_))) =>
          match v {
            ComponentValue::U32(h) =>
              ComponentValue::U32(
                transfer_future_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            ComponentValue::S32(h) =>
              ComponentValue::S32(
                transfer_future_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            _ => v
          }
        _ => v
      }
  }
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
  match resolve_valtype(ty, types) {
    Prim(_) => v
    TypeIdx(ti) =>
      match types.get(ti) {
        Some(Some(TypeDef::Tuple(tys))) =>
          match v {
            ComponentValue::Tuple(items) => {
              let out : Array[ComponentValue] = []
              for i in 0..<items.length() {
                let ty0 = if i < tys.length() {
                  tys[i]
                } else {
                  tys[tys.length() - 1]
                }
                out.push(
                  clone_stream_future_value(
                    ty0,
                    items[i],
                    types,
                    async_state,
                    from_component_id,
                    to_component_id,
                  ),
                )
              }
              ComponentValue::Tuple(out)
            }
            _ => v
          }
        Some(Some(TypeDef::Record(fields))) =>
          match v {
            ComponentValue::Tuple(items) => {
              let out : Array[ComponentValue] = []
              for i in 0..<items.length() {
                let ty0 = if i < fields.length() {
                  fields[i].ty
                } else {
                  fields[fields.length() - 1].ty
                }
                out.push(
                  clone_stream_future_value(
                    ty0,
                    items[i],
                    types,
                    async_state,
                    from_component_id,
                    to_component_id,
                  ),
                )
              }
              ComponentValue::Tuple(out)
            }
            _ => v
          }
        Some(Some(TypeDef::List(elem_ty))) =>
          match v {
            ComponentValue::List(items) => {
              let out : Array[ComponentValue] = []
              for it in items {
                out.push(
                  clone_stream_future_value(
                    elem_ty, it, types, async_state, from_component_id, to_component_id,
                  ),
                )
              }
              ComponentValue::List(out)
            }
            _ => v
          }
        Some(Some(TypeDef::Variant(cases))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag < 0 || tag >= cases.length() {
                v
              } else {
                match (cases[tag].ty, payload) {
                  (Some(payload_ty), Some(p)) =>
                    ComponentValue::Variant(
                      tag,
                      Some(
                        clone_stream_future_value(
                          payload_ty, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              }
            _ => v
          }
        Some(Some(TypeDef::Option(elem_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag == 1 {
                match payload {
                  Some(p) =>
                    ComponentValue::Variant(
                      1,
                      Some(
                        clone_stream_future_value(
                          elem_ty, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  None => v
                }
              } else {
                v
              }
            _ => v
          }
        Some(Some(TypeDef::Result(ok_ty, err_ty))) =>
          match v {
            ComponentValue::Variant(tag, payload) =>
              if tag == 0 {
                match (ok_ty, payload) {
                  (Some(t), Some(p)) =>
                    ComponentValue::Variant(
                      0,
                      Some(
                        clone_stream_future_value(
                          t, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              } else if tag == 1 {
                match (err_ty, payload) {
                  (Some(t), Some(p)) =>
                    ComponentValue::Variant(
                      1,
                      Some(
                        clone_stream_future_value(
                          t, p, types, async_state, from_component_id, to_component_id,
                        ),
                      ),
                    )
                  _ => v
                }
              } else {
                v
              }
            _ => v
          }
        Some(Some(TypeDef::Stream(_))) =>
          match v {
            ComponentValue::U32(h) =>
              ComponentValue::U32(
                clone_stream_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            ComponentValue::S32(h) =>
              ComponentValue::S32(
                clone_stream_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            _ => v
          }
        Some(Some(TypeDef::Future(_))) =>
          match v {
            ComponentValue::U32(h) =>
              ComponentValue::U32(
                clone_future_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            ComponentValue::S32(h) =>
              ComponentValue::S32(
                clone_future_readable_handle(
                  async_state, from_component_id, to_component_id, h,
                ),
              )
            _ => v
          }
        _ => v
      }
  }
}

///|
fn alloc_shared_handle_with_source(
  async_state : AsyncState,
  component_id : Int,
) -> (Int, Bool) {
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
  async_state.task_instance.set(task_id, instance_id)
  async_state.task_caller.set(task_id, caller_task_id)
}

///|
fn remove_task_meta(async_state : AsyncState, task_id : Int64) -> Unit {
  async_state.task_instance.remove(task_id)
  async_state.task_caller.remove(task_id)
}

///|
fn migrate_task_meta(
  async_state : AsyncState,
  from_id : Int64,
  to_id : Int64,
) -> Unit {
  match async_state.task_instance.get(from_id) {
    Some(inst) => async_state.task_instance.set(to_id, inst)
    None => ()
  }
  match async_state.task_caller.get(from_id) {
    Some(parent) => async_state.task_caller.set(to_id, parent)
    None => ()
  }
  remove_task_meta(async_state, from_id)
}

///|
/// Returns whether `callee_instance_id` may be entered when the call originates
/// from `caller_task_id`.
///
/// This is an extra check (beyond per-instance `may_enter`) needed for
/// callback-driven async tasks where there may be no activation record on the
/// stack but the instance is still logically on the async call stack.
fn may_enter_instance_from_task(
  async_state : AsyncState,
  caller_task_id : Int64,
  callee_instance_id : Int,
) -> Bool {
  let mut t = caller_task_id
  while t != 0L {
    match async_state.task_instance.get(t) {
      Some(inst) => if inst >= 0 && inst == callee_instance_id { return false }
      None => ()
    }
    t = match async_state.task_caller.get(t) {
      Some(p) => p
      None => 0L
    }
  }
  true
}

///|
fn ensure_task_thread(
  async_state : AsyncState,
  owner_component_id : Int,
  task_id : Int64,
) -> Unit {
  let per_task = match async_state.task_thread.get(task_id) {
    Some(m) => m
    None => {
      let m : Map[Int, Int] = {}
      async_state.task_thread.set(task_id, m)
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
  match async_state.task_thread.get(task_id) {
    Some(m) => {
      async_state.task_thread.remove(task_id)
      for entry in m {
        let (owner_component_id, th) = entry
        free_shared_handle(async_state, owner_component_id, th)
      }
    }
    None => ()
  }
}

///|
fn alloc_task_id(async_state : AsyncState) -> Int64 {
  let id = async_state.next_task_id[0]
  async_state.next_task_id[0] = id - 1L
  id
}

///|
fn push_task(async_state : AsyncState, id : Int64, can_block : Bool) -> Unit {
  async_state.task_stack.push(id)
  async_state.can_block_stack.push(can_block)
  async_state.task_can_block[0] = can_block
  async_state.yield_cursor_stack.push(0)
  async_state.wait_cursor_stack.push(0)
  async_state.call_cursor_stack.push(0)
  async_state.stream_cursor_stack.push(0)
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
  if async_state.yield_cursor_stack.length() > 0 {
    async_state.yield_cursor_stack.remove(
      async_state.yield_cursor_stack.length() - 1,
    )
    |> ignore
  }
  if async_state.wait_cursor_stack.length() > 0 {
    async_state.wait_cursor_stack.remove(
      async_state.wait_cursor_stack.length() - 1,
    )
    |> ignore
  }
  if async_state.call_cursor_stack.length() > 0 {
    async_state.call_cursor_stack.remove(
      async_state.call_cursor_stack.length() - 1,
    )
    |> ignore
  }
  if async_state.stream_cursor_stack.length() > 0 {
    async_state.stream_cursor_stack.remove(
      async_state.stream_cursor_stack.length() - 1,
    )
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
  async_state.task_results.set(task_id, vals)
  async_state.task_result_owner.set(task_id, owner_component_id)
}

///|
fn take_task_result(
  async_state : AsyncState,
  task_id : Int64,
) -> Array[ComponentValue]? {
  let v = async_state.task_results.get(task_id)
  match v {
    Some(_) => async_state.task_results.remove(task_id)
    None => ()
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
  list.push(ev)
  async_state.waitable_events.set(waitable_key, list)
  match async_state.waitable_to_set.get(waitable_key) {
    Some(ws_key) =>
      match async_state.waitable_sets.get(ws_key) {
        Some(set) => set.queue.push(ev)
        None => ()
      }
    None => ()
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
        match async_state.waitable_events.get(wkey) {
          Some(list0) =>
            if list0.length() > 0 {
              list0.remove(0) |> ignore
              if list0.length() == 0 {
                async_state.waitable_events.remove(wkey)
              } else {
                async_state.waitable_events.set(wkey, list0)
              }
            }
          None => ()
        }
        Some(ev)
      }
  }
}

///|
