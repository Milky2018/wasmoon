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
  next_handle : Array[Int]
  free_handles : Array[Int]
  next_stream_id : Array[Int]
  endpoints : Map[Int, StreamEndpoint]
  streams : Map[Int, StreamState]
} derive(Show)

///|
pub fn StreamTable::new() -> StreamTable {
  // Shared handle space starts at 1 (0 is invalid).
  {
    next_handle: [1],
    free_handles: [],
    next_stream_id: [0],
    endpoints: {},
    streams: {},
  }
}

///|
/// Async/task/waitable state shared across a whole component instantiation tree.
///
/// component-spec assumes a single handle/index space for streams/futures/subtasks/waitable-sets,
/// so we allocate all of those IDs out of the same `next_handle/free_handles` backing arrays
/// (shared with `StreamTable`).
pub(all) struct AsyncState {
  // Shared handle allocator (points at `StreamTable.next_handle/free_handles`).
  next_handle : Array[Int]
  free_handles : Array[Int]
  // Shared stream table (streams share the same handle space as waitables/subtasks).
  stream_table : StreamTable

  // Task stack + per-task state (used by canon task.return/context.*).
  task_stack : Array[Int]
  next_task_id : Array[Int]
  task_results : Map[Int, Array[ComponentValue]]
  task_returned : Map[Int, Bool]
  task_cancelled : Map[Int, Bool]
  task_contexts : Map[Int, Map[Int, @types.Value]]

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
  // Replay/memoization state keyed by task id.
  yield_replay_upto : Map[Int, Int]
  wait_results : Map[Int, Map[Int, WaitEvent]]
  waiting_ws : Map[Int, Int]
  call_results : Map[Int, Map[Int, Array[@types.Value]]]
  // Sync-lower resumption state (keyed by task id + call cursor).
  sync_lower_states : Map[Int, Map[Int, SyncLowerState]]

  // Waitable sets and event queues.
  waitable_sets : Map[Int, WaitableSet]
  waitable_to_set : Map[Int, Int]
  waitable_events : Map[Int, Array[WaitEvent]]

  // Subtasks created by `canon lower ... async`.
  subtasks : Map[Int, Subtask]
  inflight_by_instance : Map[Int, Int]
  pending_by_instance : Map[Int, Array[Int]]

  // Futures created by `canon future.new`.
  next_future_id : Array[Int]
  futures : Map[Int, FutureState]
  future_endpoints : Map[Int, FutureEndpoint]
} derive(Show)

///|
struct WaitEvent {
  code : Int
  index : Int
  payload : Int
} derive(Show)

///|
struct WaitableSet {
  // Index in the shared handle space.
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
} derive(Show)

///|
struct FutureState {
  readable_handle : Int
  writable_handle : Int
  // The element type of this future; used for intra-component checks.
  payload_ty : ValType?
  pending_read : PendingFutureRead?
  // Pending write value (already loaded from memory if needed).
  pending_write : Int?
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
  // Whether the initial call has been made (for callback-style tasks).
  started : Array[Bool]
  // Latest callback code from the core task or callback.
  code : Array[Int]
  waiting_set : Array[Int?]
  cancelled : Array[Bool]
} derive(Show)

///|
struct SyncLowerState {
  task_id : Int
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
    next_handle: stream_table.next_handle,
    free_handles: stream_table.free_handles,
    stream_table,
    task_stack: [0],
    // Use negative ids for internal tasks so they don't collide with the shared handle space.
    next_task_id: [-1],
    task_results: {},
    task_returned: {},
    task_cancelled: {},
    task_contexts: {},
    task_can_block: [false],
    can_block_stack: [false],
    in_async_callback: [false],
    yield_cursor_stack: [0],
    wait_cursor_stack: [0],
    call_cursor_stack: [0],
    yield_replay_upto: {},
    wait_results: {},
    waiting_ws: {},
    call_results: {},
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
  }
}

///|
fn remove_waitable_membership(async_state : AsyncState, handle : Int) -> Unit {
  match async_state.waitable_to_set.get(handle) {
    Some(ws) => {
      async_state.waitable_to_set.remove(handle)
      match async_state.waitable_sets.get(ws) {
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
  async_state.waitable_events.remove(handle)
}

///|
fn update_waitable_event_payload(
  async_state : AsyncState,
  handle : Int,
  code : Int,
  payload : Int,
) -> Unit {
  // Update per-waitable backlog.
  match async_state.waitable_events.get(handle) {
    Some(list) => {
      for i in 0..<list.length() {
        if list[i].code == code && list[i].index == handle {
          list[i] = { code, index: handle, payload }
        }
      }
      async_state.waitable_events.set(handle, list)
    }
    None => ()
  }
  // Update set queue (if currently joined).
  match async_state.waitable_to_set.get(handle) {
    Some(ws) =>
      match async_state.waitable_sets.get(ws) {
        Some(set) =>
          for i in 0..<set.queue.length() {
            if set.queue[i].code == code && set.queue[i].index == handle {
              set.queue[i] = { code, index: handle, payload }
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
    match async_state.stream_table.endpoints.get(ev.index) {
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
    match async_state.stream_table.endpoints.get(ev.index) {
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
                  )
                }
              }
            _ => ()
          }
        Some(Some(TypeDef::List(elem_ty))) =>
          match v {
            ComponentValue::List(items) =>
              for it in items {
                validate_lifted_stream_future(elem_ty, it, types, async_state)
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
                          case_ty, p, types, async_state,
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
                      elem_ty, p, types, async_state,
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
                    validate_lifted_stream_future(t, p, types, async_state)
                  _ => ()
                }
              } else if tag == 1 {
                match (err_ty, payload) {
                  (Some(t), Some(p)) =>
                    validate_lifted_stream_future(t, p, types, async_state)
                  _ => ()
                }
              }
            _ => ()
          }
        Some(Some(TypeDef::Stream(_))) => {
          let h = as_i32(v)
          match async_state.stream_table.endpoints.get(h) {
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
          match async_state.future_endpoints.get(h) {
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
fn alloc_shared_handle(async_state : AsyncState) -> Int {
  if async_state.free_handles.length() > 0 {
    // Deterministic allocation: reuse the smallest available handle so suites
    // relying on stable numbering (component-spec/async) behave consistently.
    let mut best_i = 0
    let mut best = async_state.free_handles[0]
    for i in 1..<async_state.free_handles.length() {
      let h = async_state.free_handles[i]
      if h < best {
        best = h
        best_i = i
      }
    }
    async_state.free_handles.remove(best_i)
  } else {
    let h = async_state.next_handle[0]
    async_state.next_handle[0] = h + 1
    h
  }
}

///|
fn free_shared_handle(async_state : AsyncState, handle : Int) -> Unit {
  if handle > 0 {
    async_state.free_handles.push(handle)
  }
}

///|
fn current_task_id(async_state : AsyncState) -> Int {
  if async_state.task_stack.length() == 0 {
    0
  } else {
    async_state.task_stack[async_state.task_stack.length() - 1]
  }
}

///|
fn alloc_task_id(async_state : AsyncState) -> Int {
  let id = async_state.next_task_id[0]
  async_state.next_task_id[0] = id - 1
  id
}

///|
fn push_task(async_state : AsyncState, id : Int, can_block : Bool) -> Unit {
  async_state.task_stack.push(id)
  async_state.can_block_stack.push(can_block)
  async_state.task_can_block[0] = can_block
  async_state.yield_cursor_stack.push(0)
  async_state.wait_cursor_stack.push(0)
  async_state.call_cursor_stack.push(0)
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
  task_id : Int,
  vals : Array[ComponentValue],
) -> Unit {
  async_state.task_results.set(task_id, vals)
}

///|
fn take_task_result(
  async_state : AsyncState,
  task_id : Int,
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
  waitable : Int,
  ev : WaitEvent,
) -> Unit {
  let list = match async_state.waitable_events.get(waitable) {
    Some(xs) => xs
    None => []
  }
  list.push(ev)
  async_state.waitable_events.set(waitable, list)
  match async_state.waitable_to_set.get(waitable) {
    Some(ws) =>
      match async_state.waitable_sets.get(ws) {
        Some(set) => set.queue.push(ev)
        None => ()
      }
    None => ()
  }
}

///|
fn pop_waitable_event(async_state : AsyncState, ws : Int) -> WaitEvent? {
  match async_state.waitable_sets.get(ws) {
    None => None
    Some(set) =>
      if set.queue.length() == 0 {
        None
      } else {
        let ev = set.queue.remove(0)
        // Consume from the per-waitable backlog as well.
        match async_state.waitable_events.get(ev.index) {
          Some(list0) =>
            if list0.length() > 0 {
              list0.remove(0) |> ignore
              if list0.length() == 0 {
                async_state.waitable_events.remove(ev.index)
              } else {
                async_state.waitable_events.set(ev.index, list0)
              }
            }
          None => ()
        }
        Some(ev)
      }
  }
}

///|
fn StreamTable::alloc_endpoint(
  self : StreamTable,
  endpoint : StreamEndpoint,
) -> Int {
  let handle = if self.free_handles.length() > 0 {
    self.free_handles.remove(self.free_handles.length() - 1)
  } else {
    let h = self.next_handle[0]
    self.next_handle[0] = h + 1
    h
  }
  self.endpoints.set(handle, endpoint)
  handle
}

///|
fn StreamTable::free_endpoint(self : StreamTable, handle : Int) -> Unit {
  if self.endpoints.get(handle) is Some(_) {
    self.endpoints.remove(handle)
    self.free_handles.push(handle)
  }
}

///|
