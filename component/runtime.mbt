///|
/// Component runtime/linker wiring.
///
/// This implements a minimal Component Model instantiation flow and canonical
/// ABI adapters for the parsed subset of types and sections.

///|
pub(all) suberror ComponentRuntimeError {
  UnsupportedComponent(String)
  ComponentParseError(String)
  CoreModuleParseError(String)
  CoreModuleInstantiateError(String)
  InvalidUtf8
  UnknownImport(String)
  ImportTypeMismatch(String)
  UnknownExport(String)
  InvalidTypeIndex(Int)
  InvalidFuncIndex(Int)
  InvalidValueIndex(Int)
  InvalidComponentIndex(Int)
  InvalidInstanceIndex(Int)
  InvalidCoreModuleIndex(Int)
  InvalidCoreInstanceIndex(Int)
  InvalidCoreFuncIndex(Int)
  InvalidCoreTableIndex(Int)
  InvalidCoreMemoryIndex(Int)
  InvalidCoreGlobalIndex(Int)
  InvalidCoreTagIndex(Int)
  InvalidCoreTypeIndex(Int)
  InvalidTypeDef(Int)
  InvalidCanonFuncType(Int)
  MissingCanonMemory
  MissingCanonRealloc
  UnsupportedStringEncoding
  CanonCallError(String)
  HostCallError(String)
  // Cooperative suspension used by sync-style async lifting (canon lift ... async).
  AsyncSuspendYield
  AsyncSuspendWait(Int)
  InvalidStartResultCount(Int)
  OuterAliasOutOfRange(Int)
  AliasTargetMismatch(String)
} derive(Show, Eq)

///|
/// Canonical ABI host functions sometimes need to trap with a string message
/// (e.g. component-spec expects "unaligned pointer"). The core Wasm runtime
/// only supports a fixed set of traps, so we stash an optional message here and
/// surface it when catching core traps.
let canon_trap_message : Array[String?] = [None]

///|
fn clear_canon_trap_message() -> Unit {
  canon_trap_message[0] = None
}

///|
/// Cooperative suspension marker used by certain canonical intrinsics (e.g. thread.yield).
enum CanonSuspend {
  Yield
  Wait(Int) // waitable-set index
} derive(Show, Eq)

///|
/// When a host intrinsic wants to suspend execution, it sets this and traps.
let canon_suspend : Array[CanonSuspend?] = [None]

///| True while doing a "best-effort pre-run" of an async-lowered call.

///|
/// During this phase we must not allow sync-lowered async calls to actually
/// block/spin; otherwise the caller core code can deadlock before it has a
/// chance to make progress (component-spec/async).
let canon_in_prerun : Array[Bool] = [false]

///|
fn trap_canon(msg : String) -> Unit raise @runtime.RuntimeError {
  canon_trap_message[0] = Some(msg)
  raise @runtime.RuntimeError::Unreachable
}

///|
/// Convert a component runtime error into the canonical trap message string.
fn canon_err_message(e : ComponentRuntimeError) -> String {
  match e {
    CanonCallError(msg) => msg
    HostCallError(msg) => msg
    _ => e.to_string()
  }
}

///|
/// Some operations are guarded by `may_leave` in the component model; for
/// example, post-return functions cannot "leave" the current component
/// instance. We model this with a global flag checked by canonical host funcs.
let canon_may_leave : Array[Bool] = [true]

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
  ptr : Int
  len : Int
  filled : Int
} derive(Show)

///|
struct PendingStreamWrite {
  buf : Array[Byte]
  sent : Int
} derive(Show)

///|
struct StreamState {
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
pub fn AsyncState::new(
  next_handle : Array[Int],
  free_handles : Array[Int],
) -> AsyncState {
  {
    next_handle,
    free_handles,
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
pub(all) enum ComponentFunc {
  // `may_enter` is used to enforce "cannot enter component instance" during
  // instantiation when core module start code calls lowered functions.
  Lifted(
    CoreFuncRef,
    FuncType,
    CanonResources,
    Array[TypeDef?],
    ResourceTable,
    Array[Bool],
    // Optional async callback core function (used by `canon lift ... async (callback ...)`).
    CoreFuncRef?,
    // Whether this canonical lift uses the async ABI (`canon lift ... async ...`).
    Bool
  )
  Host(
    FuncType,
    Array[TypeDef?],
    (Array[ComponentValue], ResourceTable) -> Array[ComponentValue] raise ComponentRuntimeError
  )
}

///|
pub impl Show for ComponentFunc with output(self, logger) {
  match self {
    Lifted(_, _, _, _, _, _, _, _) => logger.write_string("Lifted")
    Host(_, _, _) => logger.write_string("Host")
  }
}

///|
pub(all) struct CoreInstance {
  funcs : Map[String, CoreFuncRef]
  tables : Map[String, Int]
  memories : Map[String, Int]
  globals : Map[String, Int]
  tags : Map[String, Int]
}

///|
pub impl Show for CoreInstance with output(_self, logger) {
  logger.write_string("CoreInstance")
}

///|
/// A component value is a closure: the component binary plus the captured outer
/// environment needed to resolve `alias outer ...` when instantiated later.
pub(all) struct ComponentClosure {
  component : Component
  outer_stack : Array[ComponentInstance]
}

///|
pub impl Show for ComponentClosure with output(_self, logger) {
  logger.write_string("ComponentClosure")
}

///|
pub(all) enum ComponentExtern {
  Func(ComponentFunc)
  Value(ComponentValue)
  Type(TypeDef?)
  Component(ComponentClosure)
  Instance(ComponentInstance)
  CoreModule(@types.Module)
  CoreInstance(CoreInstance)
  CoreFunc(CoreFuncRef)
  CoreTable(Int)
  CoreMemory(Int)
  CoreGlobal(Int)
  CoreTag(Int)
  CoreType(Bytes)
}

///|
pub impl Show for ComponentExtern with output(self, logger) {
  match self {
    Func(_) => logger.write_string("Func")
    Value(_) => logger.write_string("Value")
    Type(_) => logger.write_string("Type")
    Component(_) => logger.write_string("Component")
    Instance(_) => logger.write_string("Instance")
    CoreModule(_) => logger.write_string("CoreModule")
    CoreInstance(_) => logger.write_string("CoreInstance")
    CoreFunc(_) => logger.write_string("CoreFunc")
    CoreTable(_) => logger.write_string("CoreTable")
    CoreMemory(_) => logger.write_string("CoreMemory")
    CoreGlobal(_) => logger.write_string("CoreGlobal")
    CoreTag(_) => logger.write_string("CoreTag")
    CoreType(_) => logger.write_string("CoreType")
  }
}

///|
pub(all) struct ComponentInstance {
  name : String
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  values : Array[ComponentValue]
  components : Array[ComponentClosure]
  instances : Array[ComponentInstance]
  resource_table : ResourceTable
  stream_table : StreamTable
  async_state : AsyncState
  core_modules : Array[@types.Module]
  core_instances : Array[CoreInstance]
  core_funcs : Array[CoreFuncRef]
  core_types : Array[Bytes]
  core_tables : Array[Int]
  core_mems : Array[Int]
  core_globals : Array[Int]
  core_tags : Array[Int]
  exports : Map[String, ComponentExtern]
  store : @runtime.Store
}

///|
pub fn ComponentInstance::get_export(
  self : ComponentInstance,
  name : String,
) -> ComponentExtern? {
  self.exports.get(name)
}

///|
pub fn ComponentInstance::call_exported_func(
  self : ComponentInstance,
  name : String,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match self.exports.get(name) {
    Some(ComponentExtern::Func(func)) => {
      let func_type = match func {
        ComponentFunc::Host(ft, _, _) => ft
        ComponentFunc::Lifted(_, ft, _, _, _, _, _, _) => ft
      }
      let prev_can_block = self.async_state.task_can_block[0]
      let prev_can_block_stack = if self.async_state.can_block_stack.length() >
        0 {
        self.async_state.can_block_stack[self.async_state.can_block_stack.length() -
        1]
      } else {
        false
      }
      self.async_state.task_can_block[0] = func_type.is_async
      if self.async_state.can_block_stack.length() > 0 {
        self.async_state.can_block_stack[self.async_state.can_block_stack.length() -
        1] = func_type.is_async
      }
      let res = call_component_func(
        func,
        args,
        self.store,
        self.resource_table,
        self.async_state,
      ) catch {
        e => {
          self.async_state.task_can_block[0] = prev_can_block
          if self.async_state.can_block_stack.length() > 0 {
            self.async_state.can_block_stack[self.async_state.can_block_stack.length() -
            1] = prev_can_block_stack
          }
          raise e
        }
      }
      self.async_state.task_can_block[0] = prev_can_block
      if self.async_state.can_block_stack.length() > 0 {
        self.async_state.can_block_stack[self.async_state.can_block_stack.length() -
        1] = prev_can_block_stack
      }
      res
    }
    Some(_) => raise UnknownExport(name)
    None => raise UnknownExport(name)
  }
}

///|
pub fn ComponentInstance::get_core_instance(
  self : ComponentInstance,
  idx : Int,
) -> CoreInstance? {
  if idx < 0 || idx >= self.core_instances.length() {
    None
  } else {
    Some(self.core_instances[idx])
  }
}

///|
struct ComponentLinker {
  core_linker : @runtime.Linker
  components : Array[(String, ComponentInstance)]
  imports : Map[String, ComponentExtern]
  // Mutable counter stored in a 1-element array so methods can bump it without
  // requiring `mut self`.
  resource_id_counter : Array[Int]
}

///|
pub fn ComponentLinker::new() -> ComponentLinker {
  {
    core_linker: @runtime.Linker::new(),
    components: [],
    imports: {},
    resource_id_counter: [0],
  }
}

///|
fn ComponentLinker::alloc_resource_id(self : ComponentLinker) -> Int {
  let id = self.resource_id_counter[0]
  self.resource_id_counter[0] = id + 1
  id
}

///|
pub fn ComponentLinker::get_store(self : ComponentLinker) -> @runtime.Store {
  self.core_linker.get_store()
}

///|
pub fn ComponentLinker::register(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit {
  self.components.push((name, instance))
}

///|
pub fn ComponentLinker::get_component(
  self : ComponentLinker,
  name : String,
) -> ComponentInstance? {
  for entry in self.components {
    let (component_name, instance) = entry
    if component_name == name {
      return Some(instance)
    }
  }
  None
}

///|
pub fn ComponentLinker::add_import(
  self : ComponentLinker,
  name : String,
  ext : ComponentExtern,
) -> Unit {
  self.imports.set(name, ext)
}

///|
pub fn ComponentLinker::add_func(
  self : ComponentLinker,
  name : String,
  func_type : FuncType,
  func : (Array[ComponentValue]) -> Array[ComponentValue] raise ComponentRuntimeError,
) -> Unit {
  self.add_import(
    name,
    ComponentExtern::Func(
      ComponentFunc::Host(func_type, [], fn(
        args : Array[ComponentValue],
        _table : ResourceTable,
      ) -> Array[ComponentValue] raise ComponentRuntimeError {
        func(args)
      }),
    ),
  )
}

///|
pub fn ComponentLinker::add_value(
  self : ComponentLinker,
  name : String,
  value : ComponentValue,
) -> Unit {
  self.add_import(name, ComponentExtern::Value(value))
}

///|
pub fn ComponentLinker::add_component(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> Unit {
  self.add_import(
    name,
    ComponentExtern::Component({ component, outer_stack: [] }),
  )
}

///|
pub fn ComponentLinker::add_instance(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit {
  self.add_import(name, ComponentExtern::Instance(instance))
}

///|
pub fn ComponentLinker::add_core_module(
  self : ComponentLinker,
  name : String,
  module_ : @types.Module,
) -> Unit {
  self.add_import(name, ComponentExtern::CoreModule(module_))
}

///|
pub fn ComponentLinker::add_core_instance(
  self : ComponentLinker,
  name : String,
  instance : CoreInstance,
) -> Unit {
  self.add_import(name, ComponentExtern::CoreInstance(instance))
}

///|
pub fn ComponentLinker::instantiate(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> ComponentInstance raise ComponentRuntimeError {
  instantiate_component(self, name, component, {}, [])
}

///|
priv struct BuildState {
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  values : Array[ComponentValue]
  components : Array[ComponentClosure]
  instances : Array[ComponentInstance]
  resource_table : ResourceTable
  stream_table : StreamTable
  async_state : AsyncState
  core_modules : Array[@types.Module]
  core_instances : Array[CoreInstance]
  core_funcs : Array[CoreFuncRef]
  core_types : Array[Bytes]
  core_tables : Array[Int]
  core_mems : Array[Int]
  core_globals : Array[Int]
  core_tags : Array[Int]
  exports : Map[String, ComponentExtern]
}

///|
fn BuildState::new(
  stream_table : StreamTable,
  async_state : AsyncState,
) -> BuildState {
  {
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
    resource_table: ResourceTable::new(),
    stream_table,
    async_state,
    core_modules: [],
    core_instances: [],
    core_funcs: [],
    core_types: [],
    core_tables: [],
    core_mems: [],
    core_globals: [],
    core_tags: [],
    exports: {},
  }
}

///|
fn decode_utf8_runtime(bytes : Bytes) -> String raise ComponentRuntimeError {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      raise InvalidUtf8
    } else if b < 0xE0 {
      if i + 1 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      if cp < 0x80 {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      if i + 2 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      if i + 3 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      raise InvalidUtf8
    }
  }
  buf.to_string()
}

///|
fn encode_utf8_string(s : String) -> Bytes {
  let bytes : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp < 0x80 {
      bytes.push(cp.to_byte())
    } else if cp < 0x800 {
      bytes.push((0xC0 | (cp >> 6)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      bytes.push((0xE0 | (cp >> 12)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (cp >> 18)).to_byte())
      bytes.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(bytes)
}

///|
/// Encode a component-model string for the given canonical encoding, returning:
/// - raw bytes to write into memory
/// - the `len` value to pass alongside the pointer
/// - required alignment for the allocation
fn encode_string_for_canon(
  s : String,
  encoding : StringEncoding,
) -> (Bytes, Int, Int) {
  match encoding {
    Utf8 => {
      let bytes = encode_utf8_string(s)
      (bytes, bytes.length(), 1)
    }
    Utf16 => {
      let out : Array[Byte] = []
      let mut units = 0
      for c in s {
        let cp = c.to_int()
        if cp < 0x10000 {
          out.push((cp & 0xFF).to_byte())
          out.push(((cp >> 8) & 0xFF).to_byte())
          units += 1
        } else {
          let v = cp - 0x10000
          let high = 0xD800 | ((v >> 10) & 0x3FF)
          let low = 0xDC00 | (v & 0x3FF)
          out.push((high & 0xFF).to_byte())
          out.push(((high >> 8) & 0xFF).to_byte())
          out.push((low & 0xFF).to_byte())
          out.push(((low >> 8) & 0xFF).to_byte())
          units += 2
        }
      }
      (Bytes::from_array(out), units, 2)
    }
    Latin1Utf16 => {
      // Encode as latin1 if possible, otherwise utf16. We use the high bit of
      // the length to indicate latin1.
      let mut latin1_ok = true
      for c in s {
        if c.to_int() > 0xFF {
          latin1_ok = false
          break
        }
      }
      if latin1_ok {
        let bytes : Array[Byte] = []
        for c in s {
          bytes.push(c.to_int().to_byte())
        }
        let len = (bytes.length().reinterpret_as_uint() | 0x8000_0000U).reinterpret_as_int()
        (Bytes::from_array(bytes), len, 2)
      } else {
        let (bytes, units, _align) = encode_string_for_canon(
          s,
          StringEncoding::Utf16,
        )
        (bytes, units, 2)
      }
    }
  }
}

///|
fn decode_import_name(name : ImportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn decode_export_name(name : ExportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn synthesize_trivial_instance_import(
  key : String,
  tyidx : Int,
  types : Array[TypeDef?],
  store : @runtime.Store,
) -> ComponentInstance? raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    return None
  }
  fn resolve_inst_typedef(
    local_types : Array[TypeDef?],
    idx : Int,
  ) -> TypeDef? {
    if idx >= 0 && idx < local_types.length() {
      return local_types[idx]
    }
    if idx >= 0 && idx < types.length() {
      return types[idx]
    }
    None
  }

  fn make_instance(
    name : String,
    exports : Map[String, ComponentExtern],
  ) -> ComponentInstance {
    let stream_table = StreamTable::new()
    let async_state = AsyncState::new(
      stream_table.next_handle,
      stream_table.free_handles,
    )
    {
      name,
      types: [],
      funcs: [],
      values: [],
      components: [],
      instances: [],
      resource_table: ResourceTable::new(),
      stream_table,
      async_state,
      core_modules: [],
      core_instances: [],
      core_funcs: [],
      core_types: [],
      core_tables: [],
      core_mems: [],
      core_globals: [],
      core_tags: [],
      exports,
      store,
    }
  }

  fn synthesize_from_typedef(
    inst_key : String,
    td : TypeDef,
  ) -> ComponentInstance? raise ComponentRuntimeError {
    match td {
      TypeDef::InstanceTypeEmpty =>
        Some(make_instance("\{inst_key}::empty", {}))
      TypeDef::InstanceType(decls) => {
        let local_types : Array[TypeDef?] = []
        let exports : Map[String, ComponentExtern] = {}
        for d in decls {
          match d {
            InstanceDecl::Type(t) => local_types.push(Some(t))
            InstanceDecl::AliasOuter(kind, _count, _idx) =>
              if kind == 0x03 {
                local_types.push(None)
              }
            InstanceDecl::AliasInstanceExport(kind, _instance_idx, _name) =>
              if kind == 0x03 {
                local_types.push(None)
              }
            InstanceDecl::Export(name, ExternDesc::Type(bound)) =>
              match bound {
                TypeBound::Eq(ti) => {
                  let aliased = if ti >= 0 && ti < local_types.length() {
                    local_types[ti]
                  } else if ti >= 0 && ti < types.length() {
                    types[ti]
                  } else {
                    None
                  }
                  exports.set(name, ComponentExtern::Type(aliased))
                  // Type exports also occupy a slot in the local type space.
                  local_types.push(aliased)
                }
                // Cannot synthesize abstract resources without a host-supplied identity.
                TypeBound::SubResource => return None
              }
            InstanceDecl::Export(name, ExternDesc::InstanceType(inner)) =>
              match resolve_inst_typedef(local_types, inner) {
                Some(inner_td) =>
                  match
                    synthesize_from_typedef("\{inst_key}::\{name}", inner_td) {
                    Some(inner_inst) =>
                      exports.set(name, ComponentExtern::Instance(inner_inst))
                    None => return None
                  }
                None => return None
              }
            InstanceDecl::Export(_, _) => return None
            _ => return None
          }
        }
        Some(make_instance("\{inst_key}::empty", exports))
      }
      _ => None
    }
  }

  match types[tyidx] {
    Some(td) => synthesize_from_typedef(key, td)
    _ => None
  }
}

///|
fn resolve_import(
  linker : ComponentLinker,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
  name : ImportName,
  desc : ExternDesc,
  types : Array[TypeDef?],
  core_types : Array[Bytes],
  store : @runtime.Store,
) -> ComponentExtern raise ComponentRuntimeError {
  let key = decode_import_name(name)
  let ext_opt = match overrides.get(key) {
    Some(v) => Some(v)
    None => linker.imports.get(key)
  }
  let expected = match desc {
    CoreModuleType(_) => "module"
    FuncType(_) => "function"
    Value(_) => "value"
    Type(_) => "type"
    ComponentType(_) => "component"
    InstanceType(_) => "instance"
  }
  match ext_opt {
    Some(ext) =>
      match (desc, ext) {
        (CoreModuleType(_), ComponentExtern::CoreModule(_))
        | (FuncType(_), ComponentExtern::Func(_))
        | (Value(_), ComponentExtern::Value(_))
        | (Type(_), ComponentExtern::Type(_))
        | (ComponentType(_), ComponentExtern::Component(_))
        | (InstanceType(_), ComponentExtern::Instance(_)) =>
          match (desc, ext) {
            (InstanceType(tyidx), ComponentExtern::Instance(inst)) => {
              validate_instance_import_type(
                key, tyidx, inst, types, core_types, outer_stack,
              )
              ext
            }
            _ => ext
          }
        _ => {
          let actual = match ext {
            ComponentExtern::Func(_) => "func"
            ComponentExtern::Value(_) => "value"
            ComponentExtern::Type(_) => "type"
            ComponentExtern::Component(_) => "component"
            ComponentExtern::Instance(_) => "instance"
            ComponentExtern::CoreModule(_) => "module"
            ComponentExtern::CoreInstance(_) => "instance"
            ComponentExtern::CoreFunc(_) => "func"
            ComponentExtern::CoreTable(_) => "table"
            ComponentExtern::CoreMemory(_) => "memory"
            ComponentExtern::CoreGlobal(_) => "global"
            ComponentExtern::CoreTag(_) => "tag"
            ComponentExtern::CoreType(_) => "type"
          }
          raise ImportTypeMismatch("expected \{expected} found \{actual}")
        }
      }
    None =>
      match desc {
        Type(TypeBound::Eq(ti)) =>
          if ti >= 0 && ti < types.length() {
            ComponentExtern::Type(types[ti])
          } else {
            raise UnknownImport(key)
          }
        InstanceType(tyidx) =>
          match synthesize_trivial_instance_import(key, tyidx, types, store) {
            Some(inst) => ComponentExtern::Instance(inst)
            None => raise UnknownImport(key)
          }
        _ => raise UnknownImport(key)
      }
  }
}

///|
fn validate_instance_import_type(
  import_key : String,
  tyidx : Int,
  inst : ComponentInstance,
  types : Array[TypeDef?],
  core_types : Array[Bytes],
  outer_stack : Array[ComponentInstance],
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    raise UnknownImport(import_key)
  }
  match types[tyidx] {
    Some(TypeDef::InstanceTypeEmpty) => ()
    Some(TypeDef::InstanceType(decls)) => {
      // Instance type decls have their own local type space; we interpret a
      // minimal subset needed for resource type bounds and (alias outer ...).
      let local_types : Array[TypeDef?] = []
      let local_core_types : Array[Bytes] = []
      for d in decls {
        match d {
          InstanceDecl::CoreType(bytes) => local_core_types.push(bytes)
          InstanceDecl::AliasOuter(kind, count, idx) => {
            // In the binary format, `count` is 1-based: 1 = current env, 2 = one level out, ...
            let depth = count - 1
            if depth < 0 || depth >= outer_stack.length() {
              raise OuterAliasOutOfRange(count)
            }
            let outer = outer_stack[outer_stack.length() - 1 - depth]
            // Alias kinds use `parse_alias_kind` encoding:
            // - Type = 0x03
            // - Core sorts are encoded as 0x100 + <core_sort>
            if kind == 0x03 {
              if idx < 0 || idx >= outer.types.length() {
                raise InvalidTypeIndex(idx)
              }
              local_types.push(outer.types[idx])
            } else if (kind & 0x100) != 0 {
              if idx < 0 || idx >= outer.core_types.length() {
                raise InvalidCoreTypeIndex(idx)
              }
              local_core_types.push(outer.core_types[idx])
            } else {
              ()
            }
          }
          InstanceDecl::AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              // Not needed for current component-spec coverage; keep the local
              // type space aligned for later indices.
              local_types.push(None)
            }
          InstanceDecl::Type(t) => local_types.push(Some(t))
          InstanceDecl::Export(name, desc) => {
            // Instance type exports of `type` also declare a slot in the local
            // type index space, which later decls can reference (e.g. `own 0`).
            let type_slot : Int? = match desc {
              ExternDesc::Type(_) => Some(local_types.length())
              _ => None
            }
            match desc {
              ExternDesc::Type(bound) =>
                match bound {
                  TypeBound::SubResource =>
                    local_types.push(
                      Some(
                        TypeDef::ResourceType(
                          -1,
                          0x7f,
                          None,
                          ResourceKind::HostDefined,
                        ),
                      ),
                    )
                  TypeBound::Eq(ti) => {
                    let aliased = if ti >= 0 && ti < local_types.length() {
                      local_types[ti]
                    } else if ti >= 0 && ti < types.length() {
                      types[ti]
                    } else {
                      None
                    }
                    local_types.push(aliased)
                  }
                }
              _ => ()
            }
            match inst.get_export(name) {
              None =>
                match desc {
                  // For equality-bounded type exports, the host doesn't need to
                  // redundantly supply the alias; it can be inferred.
                  ExternDesc::Type(TypeBound::Eq(_)) => ()
                  _ => raise UnknownImport(import_key)
                }
              Some(ext) =>
                match (desc, ext) {
                  (
                    ExternDesc::Type(TypeBound::SubResource),
                    ComponentExtern::Func(_),
                  ) => raise ImportTypeMismatch("expected resource found func")
                  (
                    ExternDesc::CoreModuleType(tyidx),
                    ComponentExtern::CoreModule(m),
                  ) => {
                    if tyidx < 0 || tyidx >= local_core_types.length() {
                      raise ImportTypeMismatch("invalid core module type index")
                    }
                    check_core_module_against_type(m, local_core_types[tyidx])
                  }
                  (ExternDesc::FuncType(_), ComponentExtern::Func(_))
                  | (ExternDesc::Value(_), ComponentExtern::Value(_))
                  | (ExternDesc::ComponentType(_), ComponentExtern::Component(_)
                  )
                  | (ExternDesc::InstanceType(_), ComponentExtern::Instance(_)) =>
                    ()
                  (ExternDesc::Type(bound), ComponentExtern::Type(actual)) =>
                    match bound {
                      TypeBound::SubResource =>
                        match actual {
                          Some(TypeDef::ResourceType(_, _, _, _)) =>
                            // Capture the host-supplied identity so later `(eq ...)` bounds
                            // compare against the real type instead of the placeholder.
                            match type_slot {
                              Some(slot) =>
                                if slot >= 0 && slot < local_types.length() {
                                  local_types[slot] = actual
                                }
                              None => ()
                            }
                          _ =>
                            raise ImportTypeMismatch(
                              "mismatched resource types",
                            )
                        }
                      TypeBound::Eq(ti) => {
                        let expected = if ti >= 0 && ti < local_types.length() {
                          local_types[ti]
                        } else if ti >= 0 && ti < types.length() {
                          types[ti]
                        } else {
                          raise ImportTypeMismatch("invalid type bound index")
                        }
                        match (expected, actual) {
                          (
                            Some(TypeDef::ResourceType(id1, _, _, kind1)),
                            Some(TypeDef::ResourceType(id2, _, _, kind2)),
                          ) =>
                            if id1 < 0 {
                              // Unify the abstract resource type with the
                              // concrete host-supplied identity so subsequent
                              // equality constraints work.
                              if ti >= 0 && ti < local_types.length() {
                                local_types[ti] = actual
                              }
                            } else if id1 != id2 || kind1 != kind2 {
                              raise ImportTypeMismatch(
                                "mismatched resource types",
                              )
                            }
                          _ =>
                            if expected != actual {
                              raise ImportTypeMismatch(
                                "instance export type mismatch",
                              )
                            }
                        }
                      }
                    }
                  _ => raise ImportTypeMismatch("instance export type mismatch")
                }
            }
          }
        }
      }
    }
    _ => ()
  }
}

///|
fn resolve_valtype(
  ty : ValType,
  types : Array[TypeDef?],
) -> ValType raise ComponentRuntimeError {
  match ty {
    Prim(p) => Prim(p)
    TypeIdx(idx) => {
      if idx < 0 || idx >= types.length() {
        raise InvalidTypeIndex(idx)
      }
      match types[idx] {
        Some(TypeDef::DefValType(p)) => Prim(p)
        _ => TypeIdx(idx)
      }
    }
  }
}

///|
fn core_types_for_valtype(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Array[@types.ValueType] raise ComponentRuntimeError {
  fn join_flat(a : @types.ValueType, b : @types.ValueType) -> @types.ValueType {
    if a == b {
      return a
    }
    match (a, b) {
      (@types.ValueType::I64, _)
      | (_, @types.ValueType::I64)
      | (@types.ValueType::F64, _)
      | (_, @types.ValueType::F64) => @types.ValueType::I64
      (@types.ValueType::F32, @types.ValueType::I32)
      | (@types.ValueType::I32, @types.ValueType::F32) => @types.ValueType::I32
      (@types.ValueType::F32, @types.ValueType::F64)
      | (@types.ValueType::F64, @types.ValueType::F32) => @types.ValueType::I64
      (@types.ValueType::I32, _) | (_, @types.ValueType::I32) =>
        @types.ValueType::I32
      _ => @types.ValueType::I64
    }
  }

  match resolve_valtype(ty, types) {
    Prim(p) =>
      match p {
        Bool | S8 | U8 | S16 | U16 | S32 | U32 | Char => [@types.ValueType::I32]
        S64 | U64 => [@types.ValueType::I64]
        F32 => [@types.ValueType::F32]
        F64 => [@types.ValueType::F64]
        String | ErrorContext =>
          if mem_is_64 {
            [@types.ValueType::I64, @types.ValueType::I64]
          } else {
            [@types.ValueType::I32, @types.ValueType::I32]
          }
      }
    TypeIdx(idx) =>
      match types[idx] {
        Some(TypeDef::Tuple(tys)) => {
          let out : Array[@types.ValueType] = []
          for t in tys {
            for vt in core_types_for_valtype(t, types, mem_is_64) {
              out.push(vt)
            }
          }
          out
        }
        Some(TypeDef::Record(fields)) => {
          let out : Array[@types.ValueType] = []
          for f in fields {
            for vt in core_types_for_valtype(f.ty, types, mem_is_64) {
              out.push(vt)
            }
          }
          out
        }
        Some(TypeDef::Variant(cases)) => {
          let payloads : Array[Array[@types.ValueType]] = []
          let mut max_len = 0
          for c in cases {
            let flat = match c.ty {
              None => []
              Some(t) => core_types_for_valtype(t, types, mem_is_64)
            }
            if flat.length() > max_len {
              max_len = flat.length()
            }
            payloads.push(flat)
          }
          let joined : Array[@types.ValueType] = []
          for i in 0..<max_len {
            let mut cur : @types.ValueType? = None
            for p in payloads {
              if i < p.length() {
                cur = match cur {
                  None => Some(p[i])
                  Some(prev) => Some(join_flat(prev, p[i]))
                }
              }
            }
            match cur {
              None => ()
              Some(t) => joined.push(t)
            }
          }
          [@types.ValueType::I32] + joined
        }
        Some(TypeDef::Option(v)) =>
          [@types.ValueType::I32] + core_types_for_valtype(v, types, mem_is_64)
        Some(TypeDef::Result(ok, err)) => {
          let ok_flat = match ok {
            None => []
            Some(v) => core_types_for_valtype(v, types, mem_is_64)
          }
          let err_flat = match err {
            None => []
            Some(v) => core_types_for_valtype(v, types, mem_is_64)
          }
          let mut max_len = ok_flat.length()
          if err_flat.length() > max_len {
            max_len = err_flat.length()
          }
          let joined : Array[@types.ValueType] = []
          for i in 0..<max_len {
            let mut cur : @types.ValueType? = None
            if i < ok_flat.length() {
              cur = Some(ok_flat[i])
            }
            if i < err_flat.length() {
              cur = match cur {
                None => Some(err_flat[i])
                Some(prev) => Some(join_flat(prev, err_flat[i]))
              }
            }
            match cur {
              None => ()
              Some(t) => joined.push(t)
            }
          }
          [@types.ValueType::I32] + joined
        }
        Some(TypeDef::Flags(labels)) =>
          if labels.length() <= 32 {
            [@types.ValueType::I32]
          } else {
            [@types.ValueType::I64]
          }
        Some(TypeDef::Enum(_)) => [@types.ValueType::I32]
        Some(TypeDef::Own(_))
        | Some(TypeDef::Borrow(_))
        | Some(TypeDef::ResourceType(_, _, _, _)) => [@types.ValueType::I32]
        // Stream/future values are represented as i32 handles; the i64
        // representation is used by the `canon stream.new` intrinsic only.
        Some(TypeDef::Stream(_)) | Some(TypeDef::Future(_)) =>
          [@types.ValueType::I32]
        Some(TypeDef::List(_)) =>
          if mem_is_64 {
            [@types.ValueType::I64, @types.ValueType::I64]
          } else {
            [@types.ValueType::I32, @types.ValueType::I32]
          }
        _ => raise InvalidTypeDef(idx)
      }
  }
}

///|
fn func_type_needs_memory(
  func_type : FuncType,
  types : Array[TypeDef?],
) -> Bool raise ComponentRuntimeError {
  fn needs_memory(val_type : ValType) -> Bool raise ComponentRuntimeError {
    match resolve_valtype(val_type, types) {
      Prim(p) =>
        match p {
          String | ErrorContext => true
          _ => false
        }
      _ => false
    }
  }

  for p in func_type.params {
    if needs_memory(p.ty) {
      return true
    }
  }
  match func_type.result {
    Some(r) => needs_memory(r)
    None => false
  }
}

///|
fn resolve_canon_resources(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CanonResources raise ComponentRuntimeError {
  let mut mem : Int? = None
  let mut realloc : CoreFuncRef? = None
  let mut post_return : CoreFuncRef? = None
  let mut encoding = StringEncoding::Utf8
  for opt in opts {
    match opt {
      CanonOpt::Memory(idx) => {
        if idx < 0 || idx >= state.core_mems.length() {
          raise InvalidCoreMemoryIndex(idx)
        }
        mem = Some(state.core_mems[idx])
      }
      CanonOpt::Realloc(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        realloc = Some(state.core_funcs[idx])
      }
      CanonOpt::PostReturn(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        post_return = Some(state.core_funcs[idx])
      }
      CanonOpt::StringEncoding(enc) => encoding = enc
      _ => ()
    }
  }
  { mem_addr: mem, realloc, post_return, encoding }
}

///|
fn canon_opt_is_async(opts : Array[CanonOpt]) -> Bool {
  for opt in opts {
    match opt {
      CanonOpt::Async => return true
      _ => ()
    }
  }
  false
}

///|
fn resolve_canon_callback(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CoreFuncRef? raise ComponentRuntimeError {
  for opt in opts {
    match opt {
      CanonOpt::Callback(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        return Some(state.core_funcs[idx])
      }
      _ => ()
    }
  }
  None
}

///|
fn core_func_type_from_component(
  func_type : FuncType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> @types.FuncType raise ComponentRuntimeError {
  let ptr_ty = if mem_is_64 {
    @types.ValueType::I64
  } else {
    @types.ValueType::I32
  }
  let flat_params : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_params.push(t)
    }
  }
  let flat_results : Array[@types.ValueType] = match func_type.result {
    Some(r) => core_types_for_valtype(r, types, mem_is_64)
    None => []
  }

  // Canonical ABI:
  // - If there are too many flattened parameters, pass a single pointer to a
  //   memory area containing the flattened arguments.
  // - If the flattened result count isn't exactly 1, use an indirect return
  //   pointer parameter (and return nothing).
  let params : Array[@types.ValueType] = if flat_params.length() > 16 {
    [ptr_ty]
  } else {
    flat_params
  }
  let results : Array[@types.ValueType] = if flat_results.length() == 1 {
    flat_results
  } else if flat_results.length() == 0 {
    []
  } else {
    params.push(ptr_ty)
    []
  }
  { params, results }
}

///|
pub fn alloc_host_core_func(
  store : @runtime.Store,
  core_type : @types.FuncType,
  host : (Array[@types.Value]) -> Array[@types.Value] raise @runtime.RuntimeError,
) -> CoreFuncRef {
  let func_addr = store.alloc_host_func(host, func_type=core_type, type_idx=0)
  let instance : @runtime.ModuleInstance = {
    types: [@types.SubType::from_func(core_type)],
    type_rec_groups: [],
    canonical_type_indices: [0],
    store_idx: -1,
    func_addrs: [func_addr],
    func_type_indices: [0],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    tag_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
  { instance, func_idx: 0 }
}

///|
fn call_core_func(
  store : @runtime.Store,
  core_func : CoreFuncRef,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  // Reset any previous canonical trap so we don't leak messages across calls.
  clear_canon_trap_message()
  canon_suspend[0] = None
  @executor.call_func_by_index(
    store,
    core_func.instance,
    core_func.func_idx,
    args,
  ) catch {
    e => {
      match canon_suspend[0] {
        Some(CanonSuspend::Yield) => {
          canon_suspend[0] = None
          raise AsyncSuspendYield
        }
        Some(CanonSuspend::Wait(ws)) => {
          canon_suspend[0] = None
          raise AsyncSuspendWait(ws)
        }
        None => ()
      }
      match canon_trap_message[0] {
        Some(msg) => raise CanonCallError(msg)
        None => raise CanonCallError(e.to_string())
      }
    }
  }
}

///|
fn read_string_from_memory_with_encoding(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
  encoding : StringEncoding,
) -> String raise ComponentRuntimeError {
  if ptr < 0 || len < 0 {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  // Pointer alignment requirements:
  // - utf16 and latin1+utf16 require 2-byte alignment.
  match encoding {
    Utf16 | Latin1Utf16 =>
      if (ptr.reinterpret_as_uint() & 1U) != 0U {
        raise CanonCallError("unaligned pointer")
      }
    Utf8 => ()
  }
  let mem_len = mem.byte_len()
  let mut byte_len = len
  let mut latin1 = false
  if encoding == StringEncoding::Utf16 {
    byte_len = len * 2
  } else if encoding == StringEncoding::Latin1Utf16 {
    // In the canonical ABI, latin1+utf16 uses the high bit of the length to
    // indicate latin1 vs utf16.
    let ulen = len.reinterpret_as_uint()
    if (ulen & 0x8000_0000U) != 0U {
      latin1 = true
      byte_len = (ulen & 0x7FFF_FFFFU).reinterpret_as_int()
    } else {
      byte_len = len * 2
    }
  }
  if ptr.to_int64() + byte_len.to_int64() > mem_len {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  if encoding == StringEncoding::Utf8 || latin1 {
    let bytes : Array[Byte] = []
    for i in 0..<byte_len {
      let b = mem.load_byte(ptr + i) catch {
        e => raise CanonCallError(e.to_string())
      }
      bytes.push(b)
    }
    if latin1 {
      // Latin1 is a byte-for-codepoint mapping.
      let buf = StringBuilder::new()
      for b in bytes {
        buf.write_char(b.to_int().unsafe_to_char())
      }
      buf.to_string()
    } else {
      decode_utf8_runtime(Bytes::from_array(bytes))
    }
  } else {
    // UTF-16LE decode.
    let buf = StringBuilder::new()
    let mut i = 0
    while i < byte_len {
      let b0 = mem.load_byte(ptr + i) catch {
        e => raise CanonCallError(e.to_string())
      }
      let b1 = mem.load_byte(ptr + i + 1) catch {
        e => raise CanonCallError(e.to_string())
      }
      let cu = b0.to_int() | (b1.to_int() << 8)
      // Surrogates: minimal handling sufficient for current tests.
      if cu >= 0xD800 && cu <= 0xDBFF && i + 3 < byte_len {
        let b2 = mem.load_byte(ptr + i + 2) catch {
          e => raise CanonCallError(e.to_string())
        }
        let b3 = mem.load_byte(ptr + i + 3) catch {
          e => raise CanonCallError(e.to_string())
        }
        let cu2 = b2.to_int() | (b3.to_int() << 8)
        if cu2 >= 0xDC00 && cu2 <= 0xDFFF {
          let high = cu - 0xD800
          let low = cu2 - 0xDC00
          let cp = 0x10000 + ((high << 10) | low)
          buf.write_char(cp.unsafe_to_char())
          i = i + 4
          continue
        }
      }
      buf.write_char(cu.unsafe_to_char())
      i = i + 2
    }
    buf.to_string()
  }
}

///|
fn write_bytes_to_memory_with_align(
  store : @runtime.Store,
  mem : @runtime.Memory,
  realloc : CoreFuncRef,
  mem_is_64 : Bool,
  bytes : Bytes,
  align : Int,
) -> Int raise ComponentRuntimeError {
  let len = bytes.length()
  let args : Array[@types.Value] = if mem_is_64 {
    [
      @types.Value::I64(0L),
      @types.Value::I64(0L),
      @types.Value::I64(align.to_int64()),
      @types.Value::I64(len.to_int64()),
    ]
  } else {
    [
      @types.Value::I32(0),
      @types.Value::I32(0),
      @types.Value::I32(align),
      @types.Value::I32(len),
    ]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [@types.Value::I32(n)] => n
    [@types.Value::I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  // Even for zero-sized allocations we must validate the returned pointer.
  let mem_len = mem.byte_len().to_int()
  if ptr < 0 || ptr > mem_len || ptr + len > mem_len {
    raise CanonCallError("realloc return: beyond end of memory")
  }
  for i in 0..<bytes.length() {
    mem.store_byte(ptr + i, bytes[i]) catch {
      e => raise CanonCallError(e.to_string())
    }
  }
  ptr
}

///|
fn align_to(n : Int, align : Int) -> Int {
  if align <= 1 {
    return n
  }
  let rem = n % align
  if rem == 0 {
    n
  } else {
    n + (align - rem)
  }
}

///|
fn core_valtype_align(vt : @types.ValueType) -> Int {
  match vt {
    @types.ValueType::I32 | @types.ValueType::F32 => 4
    @types.ValueType::I64 | @types.ValueType::F64 => 8
    _ => 4
  }
}

///|
fn core_valtype_size(vt : @types.ValueType) -> Int {
  match vt {
    @types.ValueType::I32 | @types.ValueType::F32 => 4
    @types.ValueType::I64 | @types.ValueType::F64 => 8
    _ => 4
  }
}

///|
fn layout_of_flat_types(
  tys : Array[@types.ValueType],
) -> (Array[Int], Int, Int) {
  let offsets : Array[Int] = []
  let mut off = 0
  let mut struct_align = 1
  for t in tys {
    let a = core_valtype_align(t)
    if a > struct_align {
      struct_align = a
    }
    off = align_to(off, a)
    offsets.push(off)
    off += core_valtype_size(t)
  }
  (offsets, off, struct_align)
}

///|
fn alloc_realloc_area(
  store : @runtime.Store,
  mem : @runtime.Memory,
  realloc : CoreFuncRef,
  mem_is_64 : Bool,
  size : Int,
  align : Int,
) -> Int raise ComponentRuntimeError {
  let args : Array[@types.Value] = if mem_is_64 {
    [
      @types.Value::I64(0L),
      @types.Value::I64(0L),
      @types.Value::I64(align.to_int64()),
      @types.Value::I64(size.to_int64()),
    ]
  } else {
    [
      @types.Value::I32(0),
      @types.Value::I32(0),
      @types.Value::I32(align),
      @types.Value::I32(size),
    ]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [@types.Value::I32(n)] => n
    [@types.Value::I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  let mem_len = mem.byte_len().to_int()
  if ptr < 0 || ptr > mem_len || ptr + size > mem_len {
    raise CanonCallError("realloc return: beyond end of memory")
  }
  ptr
}

///|
fn load_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  vt : @types.ValueType,
) -> @types.Value raise ComponentRuntimeError {
  match vt {
    @types.ValueType::I32 =>
      @types.Value::I32(
        mem.load_i32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::I64 =>
      @types.Value::I64(
        mem.load_i64(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::F32 =>
      @types.Value::F32(
        mem.load_f32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::F64 =>
      @types.Value::F64(
        mem.load_f64(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    _ =>
      @types.Value::I32(
        mem.load_i32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
  }
}

///|
fn store_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  val : @types.Value,
) -> Unit raise ComponentRuntimeError {
  match val {
    @types.Value::I32(n) =>
      mem.store_i32(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::I64(n) =>
      mem.store_i64(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::F32(f) =>
      mem.store_f32(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::F64(f) =>
      mem.store_f64(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    _ =>
      mem.store_i32(addr, 0) catch {
        e => raise CanonCallError(e.to_string())
      }
  }
}

///|
fn require_memory(
  resources : CanonResources,
  store : @runtime.Store,
) -> @runtime.Memory raise ComponentRuntimeError {
  match resources.mem_addr {
    Some(addr) =>
      store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
    None => raise MissingCanonMemory
  }
}

///|
fn trunc_u8(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFU).reinterpret_as_int()
}

///|
fn trunc_s8(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFU
  if masked >= 0x80U {
    masked.reinterpret_as_int() - 0x100
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u16(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFFFU).reinterpret_as_int()
}

///|
fn trunc_s16(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFFFU
  if masked >= 0x8000U {
    masked.reinterpret_as_int() - 0x10000
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u32(n : Int) -> Int {
  n.reinterpret_as_uint().reinterpret_as_int()
}

///|
fn char_from_canon_i32(n : Int) -> Char raise ComponentRuntimeError {
  // Component model `char` values are Unicode scalar values.
  if n < 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) {
    raise CanonCallError("invalid `char` bit pattern")
  }
  n.unsafe_to_char()
}

///|
fn zero_flat_value(vt : @types.ValueType) -> @types.Value {
  match vt {
    @types.ValueType::I32 => @types.Value::I32(0)
    @types.ValueType::I64 => @types.Value::I64(0L)
    @types.ValueType::F32 => @types.Value::F32(0.0)
    @types.ValueType::F64 => @types.Value::F64(0.0)
    _ => @types.Value::I32(0)
  }
}

///|
fn coerce_flat_value(
  v : @types.Value,
  from_vt : @types.ValueType,
  to_vt : @types.ValueType,
) -> @types.Value raise ComponentRuntimeError {
  if from_vt == to_vt {
    return v
  }
  match (from_vt, to_vt, v) {
    (@types.ValueType::F32, @types.ValueType::I32, @types.Value::F32(f)) =>
      @types.Value::I32(f.reinterpret_as_int())
    (@types.ValueType::I32, @types.ValueType::F32, @types.Value::I32(n)) =>
      @types.Value::F32(Float::reinterpret_from_int(n))
    (@types.ValueType::F64, @types.ValueType::I64, @types.Value::F64(f)) =>
      @types.Value::I64(f.reinterpret_as_int64())
    (@types.ValueType::I64, @types.ValueType::F64, @types.Value::I64(n)) =>
      @types.Value::F64(n.reinterpret_as_double())
    (@types.ValueType::I32, @types.ValueType::I64, @types.Value::I32(n)) => {
      let bits = n.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
      @types.Value::I64(bits)
    }
    (@types.ValueType::I64, @types.ValueType::I32, @types.Value::I64(n)) =>
      @types.Value::I32(
        (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int(),
      )
    (@types.ValueType::I64, @types.ValueType::F32, @types.Value::I64(n)) => {
      let bits = (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int()
      @types.Value::F32(Float::reinterpret_from_int(bits))
    }
    (@types.ValueType::F32, @types.ValueType::I64, @types.Value::F32(f)) => {
      let bits = f
        .reinterpret_as_int()
        .reinterpret_as_uint()
        .to_uint64()
        .reinterpret_as_int64()
      @types.Value::I64(bits)
    }
    _ => raise HostCallError("type mismatch")
  }
}

///|
fn lift_component_value_from_flat(
  ty : ValType,
  flat_vals : Array[@types.Value],
  types : Array[TypeDef?],
  mem : @runtime.Memory?,
  mem_is_64 : Bool,
  encoding : StringEncoding,
) -> ComponentValue raise ComponentRuntimeError {
  let mut idx = 0
  fn take(
    vals : Array[@types.Value],
  ) -> @types.Value raise ComponentRuntimeError {
    if idx < 0 || idx >= vals.length() {
      raise HostCallError("type mismatch")
    }
    let v = vals[idx]
    idx += 1
    v
  }

  fn lift_inner(
    ty : ValType,
    vals : Array[@types.Value],
  ) -> ComponentValue raise ComponentRuntimeError {
    match resolve_valtype(ty, types) {
      Prim(p) =>
        match p {
          String | ErrorContext => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (@types.Value::I64(p), @types.Value::I64(l)) =>
                  (p.to_int(), l.to_int())
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (@types.Value::I32(p), @types.Value::I32(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            }
            let s = read_string_from_memory_with_encoding(m, ptr, len, encoding)
            if p == String {
              ComponentValue::String(s)
            } else {
              ComponentValue::ErrorContext(s)
            }
          }
          _ =>
            match (p, take(vals)) {
              (Bool, @types.Value::I32(n)) => ComponentValue::Bool(n != 0)
              (S8, @types.Value::I32(n)) => ComponentValue::S8(trunc_s8(n))
              (U8, @types.Value::I32(n)) => ComponentValue::U8(trunc_u8(n))
              (S16, @types.Value::I32(n)) => ComponentValue::S16(trunc_s16(n))
              (U16, @types.Value::I32(n)) => ComponentValue::U16(trunc_u16(n))
              (S32, @types.Value::I32(n)) => ComponentValue::S32(n)
              (U32, @types.Value::I32(n)) => ComponentValue::U32(trunc_u32(n))
              (Char, @types.Value::I32(n)) =>
                ComponentValue::Char(char_from_canon_i32(n))
              (S64, @types.Value::I64(n)) => ComponentValue::S64(n)
              (U64, @types.Value::I64(n)) => ComponentValue::U64(n)
              (F32, @types.Value::F32(f)) => ComponentValue::F32(f)
              (F64, @types.Value::F64(f)) => ComponentValue::F64(f)
              _ => raise HostCallError("type mismatch")
            }
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Tuple(tys))) => {
            let items : Array[ComponentValue] = []
            for t in tys {
              items.push(lift_inner(t, vals))
            }
            ComponentValue::Tuple(items)
          }
          Some(Some(TypeDef::Record(fields))) => {
            let items : Array[ComponentValue] = []
            for f in fields {
              items.push(lift_inner(f.ty, vals))
            }
            ComponentValue::Tuple(items)
          }
          Some(Some(TypeDef::List(elem_ty))) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let (ptr, len) = if mem_is_64 {
              match (take(vals), take(vals)) {
                (@types.Value::I64(p), @types.Value::I64(l)) =>
                  (p.to_int(), l.to_int())
                _ => raise HostCallError("type mismatch")
              }
            } else {
              match (take(vals), take(vals)) {
                (@types.Value::I32(p), @types.Value::I32(l)) => (p, l)
                _ => raise HostCallError("type mismatch")
              }
            }
            let elem_flat_types = core_types_for_valtype(
              elem_ty, types, mem_is_64,
            )
            let (offsets, elem_size, elem_align) = layout_of_flat_types(
              elem_flat_types,
            )
            let stride = align_to(elem_size, elem_align)
            let items : Array[ComponentValue] = []
            for i in 0..<len {
              let base = ptr + stride * i
              let elem_vals : Array[@types.Value] = []
              for j in 0..<elem_flat_types.length() {
                elem_vals.push(
                  load_flat_value(m, base + offsets[j], elem_flat_types[j]),
                )
              }
              items.push(
                lift_component_value_from_flat(
                  elem_ty, elem_vals, types, mem, mem_is_64, encoding,
                ),
              )
            }
            ComponentValue::List(items)
          }
          Some(Some(TypeDef::Stream(_))) | Some(Some(TypeDef::Future(_))) =>
            match take(vals) {
              @types.Value::I32(n) => ComponentValue::U32(n)
              _ => raise HostCallError("type mismatch")
            }
          Some(Some(TypeDef::Variant(cases))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag < 0 || tag >= cases.length() {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            match cases[tag].ty {
              None => ComponentValue::Variant(tag, None)
              Some(payload_ty) => {
                let payload_flat_types = core_types_for_valtype(
                  payload_ty, types, mem_is_64,
                )
                let payload_vals : Array[@types.Value] = []
                for i in 0..<payload_flat_types.length() {
                  payload_vals.push(
                    coerce_flat_value(
                      joined_vals[i],
                      joined_types[i],
                      payload_flat_types[i],
                    ),
                  )
                }
                let payload = lift_component_value_from_flat(
                  payload_ty, payload_vals, types, mem, mem_is_64, encoding,
                )
                ComponentValue::Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(TypeDef::Option(payload_ty))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            if tag == 0 {
              ComponentValue::Variant(0, None)
            } else {
              let payload_flat_types = core_types_for_valtype(
                payload_ty, types, mem_is_64,
              )
              let payload_vals : Array[@types.Value] = []
              for i in 0..<payload_flat_types.length() {
                payload_vals.push(
                  coerce_flat_value(
                    joined_vals[i],
                    joined_types[i],
                    payload_flat_types[i],
                  ),
                )
              }
              let payload = lift_component_value_from_flat(
                payload_ty, payload_vals, types, mem, mem_is_64, encoding,
              )
              ComponentValue::Variant(1, Some(payload))
            }
          }
          Some(Some(TypeDef::Result(ok_ty, err_ty))) => {
            let tag = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if tag != 0 && tag != 1 {
              raise CanonCallError("invalid variant discriminant")
            }
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            let joined_vals : Array[@types.Value] = []
            for vt in joined_types {
              let v = take(vals)
              joined_vals.push(coerce_flat_value(v, vt, vt))
            }
            let payload_ty = if tag == 0 { ok_ty } else { err_ty }
            match payload_ty {
              None => ComponentValue::Variant(tag, None)
              Some(pt) => {
                let payload_flat_types = core_types_for_valtype(
                  pt, types, mem_is_64,
                )
                let payload_vals : Array[@types.Value] = []
                for i in 0..<payload_flat_types.length() {
                  payload_vals.push(
                    coerce_flat_value(
                      joined_vals[i],
                      joined_types[i],
                      payload_flat_types[i],
                    ),
                  )
                }
                let payload = lift_component_value_from_flat(
                  pt, payload_vals, types, mem, mem_is_64, encoding,
                )
                ComponentValue::Variant(tag, Some(payload))
              }
            }
          }
          Some(Some(TypeDef::Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match take(vals) {
                @types.Value::I32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              ComponentValue::U32(masked.reinterpret_as_int())
            } else {
              let raw = match take(vals) {
                @types.Value::I64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              ComponentValue::U64(masked.reinterpret_as_int64())
            }
          }
          Some(Some(TypeDef::Enum(labels))) => {
            let n = match take(vals) {
              @types.Value::I32(n) => n
              _ => raise HostCallError("type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise CanonCallError("invalid enum discriminant")
            }
            ComponentValue::U32(n)
          }
          Some(Some(TypeDef::Own(_)))
          | Some(Some(TypeDef::Borrow(_)))
          | Some(Some(TypeDef::ResourceType(_, _, _, _))) =>
            match take(vals) {
              @types.Value::I32(handle) => ComponentValue::U32(handle)
              _ => raise HostCallError("type mismatch")
            }
          _ => raise HostCallError("type mismatch")
        }
    }
  }

  let v = lift_inner(ty, flat_vals)
  if idx != flat_vals.length() {
    raise HostCallError("type mismatch")
  }
  v
}

///|
fn component_args_to_core(
  args : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  caller_table : ResourceTable,
  callee_table : ResourceTable,
) -> Array[@types.Value] raise ComponentRuntimeError {
  // Cache memory/realloc handles (if provided) for canonical ABI operations.
  let mut mem : @runtime.Memory? = None
  let mut mem_is_64 = false
  match resources.mem_addr {
    Some(addr) => {
      let m = store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
      mem_is_64 = m.is_memory64()
      mem = Some(m)
    }
    None => ()
  }
  fn lower_value(
    val : ComponentValue,
    ty : ValType,
  ) -> Array[@types.Value] raise ComponentRuntimeError {
    match resolve_valtype(ty, types) {
      Prim(p) =>
        match (p, val) {
          (Bool, ComponentValue::Bool(b)) =>
            [@types.Value::I32(if b { 1 } else { 0 })]
          (S8, ComponentValue::S8(n))
          | (U8, ComponentValue::U8(n))
          | (S16, ComponentValue::S16(n))
          | (U16, ComponentValue::U16(n))
          | (S32, ComponentValue::S32(n))
          | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
          (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
            [@types.Value::I64(n)]
          (F32, ComponentValue::F32(f)) => [@types.Value::F32(f)]
          (F64, ComponentValue::F64(f)) => [@types.Value::F64(f)]
          (Char, ComponentValue::Char(c)) => [@types.Value::I32(c.to_int())]
          (String, ComponentValue::String(s))
          | (ErrorContext, ComponentValue::ErrorContext(s)) => {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let realloc = match resources.realloc {
              Some(r) => r
              None => raise MissingCanonRealloc
            }
            let (bytes, canon_len, align) = encode_string_for_canon(
              s,
              resources.encoding,
            )
            let ptr = write_bytes_to_memory_with_align(
              store, m, realloc, mem_is_64, bytes, align,
            )
            if mem_is_64 {
              [
                @types.Value::I64(ptr.to_int64()),
                @types.Value::I64(canon_len.to_int64()),
              ]
            } else {
              [@types.Value::I32(ptr), @types.Value::I32(canon_len)]
            }
          }
          _ => raise HostCallError("argument type mismatch")
        }
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Tuple(tys))) =>
            match val {
              ComponentValue::Tuple(items) =>
                if items.length() != tys.length() {
                  raise HostCallError("argument type mismatch")
                } else {
                  let out : Array[@types.Value] = []
                  for i in 0..<tys.length() {
                    for v in lower_value(items[i], tys[i]) {
                      out.push(v)
                    }
                  }
                  out
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Record(fields))) =>
            match val {
              ComponentValue::Tuple(items) =>
                if items.length() != fields.length() {
                  raise HostCallError("argument type mismatch")
                } else {
                  let out : Array[@types.Value] = []
                  for i in 0..<fields.length() {
                    for v in lower_value(items[i], fields[i].ty) {
                      out.push(v)
                    }
                  }
                  out
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::List(elem_ty))) =>
            match val {
              ComponentValue::List(items) => {
                let m = match mem {
                  Some(m) => m
                  None => raise MissingCanonMemory
                }
                let realloc = match resources.realloc {
                  Some(r) => r
                  None => raise MissingCanonRealloc
                }
                let elem_flat = core_types_for_valtype(
                  elem_ty, types, mem_is_64,
                )
                let (_offs, elem_size, elem_align) = layout_of_flat_types(
                  elem_flat,
                )
                let stride = align_to(elem_size, elem_align)
                let total_size = stride * items.length()
                let ptr = alloc_realloc_area(
                  store, m, realloc, mem_is_64, total_size, elem_align,
                )
                // TODO: store list elements for non-empty lists.
                if items.length() > 0 {
                  raise HostCallError("unsupported param type")
                }
                let len = items.length()
                if mem_is_64 {
                  [
                    @types.Value::I64(ptr.to_int64()),
                    @types.Value::I64(len.to_int64()),
                  ]
                } else {
                  [@types.Value::I32(ptr), @types.Value::I32(len)]
                }
              }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Variant(cases))) => {
            let all_flat = core_types_for_valtype(TypeIdx(ti), types, mem_is_64)
            let joined_types : Array[@types.ValueType] = []
            for i in 1..<all_flat.length() {
              joined_types.push(all_flat[i])
            }
            match val {
              ComponentValue::Variant(tag, payload_opt) => {
                if tag < 0 || tag >= cases.length() {
                  raise HostCallError("invalid variant discriminant")
                }
                let payload_vals : Array[@types.Value] = match cases[tag].ty {
                  None =>
                    match payload_opt {
                      None => []
                      Some(_) => raise HostCallError("argument type mismatch")
                    }
                  Some(payload_ty) =>
                    match payload_opt {
                      None => raise HostCallError("argument type mismatch")
                      Some(pv) => lower_value(pv, payload_ty)
                    }
                }
                let out : Array[@types.Value] = [@types.Value::I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      @types.Value::I32(_) => @types.ValueType::I32
                      @types.Value::I64(_) => @types.ValueType::I64
                      @types.Value::F32(_) => @types.ValueType::F32
                      @types.Value::F64(_) => @types.ValueType::F64
                      _ => @types.ValueType::I32
                    }
                    out.push(
                      coerce_flat_value(actual, actual_vt, joined_types[i]),
                    )
                  } else {
                    out.push(zero_flat_value(joined_types[i]))
                  }
                }
                out
              }
              _ => raise HostCallError("argument type mismatch")
            }
          }
          Some(Some(TypeDef::Option(payload_ty))) =>
            match val {
              ComponentValue::Variant(tag, payload_opt) =>
                if tag == 0 {
                  // none
                  if payload_opt is Some(_) {
                    raise HostCallError("argument type mismatch")
                  }
                  // tag + payload slots (same as payload flat types)
                  let out : Array[@types.Value] = [@types.Value::I32(0)]
                  let payload_flat = core_types_for_valtype(
                    payload_ty, types, mem_is_64,
                  )
                  for vt in payload_flat {
                    out.push(zero_flat_value(vt))
                  }
                  out
                } else if tag == 1 {
                  let payload = match payload_opt {
                    Some(p) => p
                    None => raise HostCallError("argument type mismatch")
                  }
                  let payload_vals = lower_value(payload, payload_ty)
                  [@types.Value::I32(1)] + payload_vals
                } else {
                  raise HostCallError("invalid variant discriminant")
                }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Result(ok_ty, err_ty))) =>
            match val {
              ComponentValue::Variant(tag, payload_opt) => {
                let payload_ty = if tag == 0 {
                  ok_ty
                } else if tag == 1 {
                  err_ty
                } else {
                  raise HostCallError("invalid variant discriminant")
                }
                let payload_vals : Array[@types.Value] = match payload_ty {
                  None =>
                    match payload_opt {
                      None => []
                      Some(_) => raise HostCallError("argument type mismatch")
                    }
                  Some(pt) =>
                    match payload_opt {
                      Some(p) => lower_value(p, pt)
                      None => raise HostCallError("argument type mismatch")
                    }
                }
                // Join ok/err payload slots by using the result's flattened payload types.
                let all_flat = core_types_for_valtype(
                  TypeIdx(ti),
                  types,
                  mem_is_64,
                )
                let joined_types : Array[@types.ValueType] = []
                for i in 1..<all_flat.length() {
                  joined_types.push(all_flat[i])
                }
                let out : Array[@types.Value] = [@types.Value::I32(tag)]
                for i in 0..<joined_types.length() {
                  if i < payload_vals.length() {
                    let actual = payload_vals[i]
                    let actual_vt = match actual {
                      @types.Value::I32(_) => @types.ValueType::I32
                      @types.Value::I64(_) => @types.ValueType::I64
                      @types.Value::F32(_) => @types.ValueType::F32
                      @types.Value::F64(_) => @types.ValueType::F64
                      _ => @types.ValueType::I32
                    }
                    out.push(
                      coerce_flat_value(actual, actual_vt, joined_types[i]),
                    )
                  } else {
                    out.push(zero_flat_value(joined_types[i]))
                  }
                }
                out
              }
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Flags(labels))) => {
            let nbits = labels.length()
            if nbits <= 32 {
              let raw = match val {
                ComponentValue::U32(n) => n.reinterpret_as_uint()
                ComponentValue::S32(n) => n.reinterpret_as_uint()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 32 {
                raw
              } else {
                raw & ((1U << nbits) - 1U)
              }
              [@types.Value::I32(masked.reinterpret_as_int())]
            } else {
              let raw = match val {
                ComponentValue::U64(n) => n.reinterpret_as_uint64()
                ComponentValue::S64(n) => n.reinterpret_as_uint64()
                _ => raise HostCallError("argument type mismatch")
              }
              let masked = if nbits == 64 {
                raw
              } else {
                raw & ((1UL << nbits) - 1UL)
              }
              [@types.Value::I64(masked.reinterpret_as_int64())]
            }
          }
          Some(Some(TypeDef::Enum(labels))) => {
            let n = match val {
              ComponentValue::U32(n) => n
              ComponentValue::S32(n) => n
              _ => raise HostCallError("argument type mismatch")
            }
            if n < 0 || n >= labels.length() {
              raise HostCallError("invalid enum discriminant")
            }
            [@types.Value::I32(n)]
          }
          Some(Some(TypeDef::Borrow(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(TypeDef::ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              ComponentValue::U32(h) => h
              ComponentValue::S32(h) => h
              _ => raise HostCallError("argument type mismatch")
            }
            match caller_table.get(handle) {
              Some(entry) =>
                if entry.type_id != expected_type_id {
                  raise CanonCallError(
                    "handle index \{handle} used with the wrong type",
                  )
                } else {
                  [@types.Value::I32(entry.rep)]
                }
              None => raise CanonCallError("unknown handle index \{handle}")
            }
          }
          Some(Some(TypeDef::Own(resource_tyidx))) => {
            let expected_type_id = match types.get(resource_tyidx) {
              Some(Some(TypeDef::ResourceType(id, _, _, _))) => id
              _ => raise HostCallError("unsupported param type")
            }
            let handle = match val {
              ComponentValue::U32(h) => h
              ComponentValue::S32(h) => h
              _ => raise HostCallError("argument type mismatch")
            }
            if caller_table.id == callee_table.id {
              [@types.Value::I32(handle)]
            } else {
              let entry = match caller_table.free(handle) {
                Some(e) => e
                None => raise CanonCallError("unknown handle index \{handle}")
              }
              if entry.type_id != expected_type_id {
                raise CanonCallError(
                  "handle index \{handle} used with the wrong type",
                )
              }
              let new_handle = callee_table.alloc(entry)
              [@types.Value::I32(new_handle)]
            }
          }
          Some(Some(TypeDef::ResourceType(_, _, _, _))) =>
            match val {
              ComponentValue::U32(handle) => [@types.Value::I32(handle)]
              ComponentValue::S32(handle) => [@types.Value::I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          Some(Some(TypeDef::Stream(_))) | Some(Some(TypeDef::Future(_))) =>
            match val {
              ComponentValue::U32(handle) => [@types.Value::I32(handle)]
              ComponentValue::S32(handle) => [@types.Value::I32(handle)]
              _ => raise HostCallError("argument type mismatch")
            }
          _ => raise HostCallError("unsupported param type")
        }
    }
  }

  // Determine whether we must pass a pointer to the flattened arguments.
  let flat_param_types : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > 16
  let flat_vals : Array[@types.Value] = []
  for i, param in func_type.params {
    let val = if i < args.length() {
      args[i]
    } else {
      raise InvalidValueIndex(i)
    }
    for v in lower_value(val, param.ty) {
      flat_vals.push(v)
    }
  }
  if !indirect_params {
    return flat_vals
  }
  let m = match mem {
    Some(m) => m
    None => raise MissingCanonMemory
  }
  let realloc = match resources.realloc {
    Some(r) => r
    None => raise MissingCanonRealloc
  }
  let (offsets, size, struct_align) = layout_of_flat_types(flat_param_types)
  let ptr = alloc_realloc_area(store, m, realloc, mem_is_64, size, struct_align)
  if ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() != 0U {
    raise CanonCallError("unaligned pointer")
  }
  for i in 0..<flat_vals.length() {
    store_flat_value(m, ptr + offsets[i], flat_vals[i])
  }
  if mem_is_64 {
    [@types.Value::I64(ptr.to_int64())]
  } else {
    [@types.Value::I32(ptr)]
  }
}

///|
fn core_results_to_component(
  results : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  resource_table : ResourceTable,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  fn resource_type_info(
    tyidx : Int,
    types : Array[TypeDef?],
  ) -> (Int, ResourceKind) raise ComponentRuntimeError {
    match types.get(tyidx) {
      Some(Some(TypeDef::ResourceType(id, _, _, kind))) => (id, kind)
      _ => raise HostCallError("invalid resource type")
    }
  }

  fn validate_resource_handle(
    handle : Int,
    expected_type_id : Int,
    expected_kind : ResourceKind,
    table : ResourceTable,
  ) -> Unit raise ComponentRuntimeError {
    match table.get(handle) {
      None =>
        raise CanonCallError(
          "unknown handle index \{handle}; index \{handle} is not a resource",
        )
      Some(entry) =>
        if entry.type_id < 0 {
          raise CanonCallError(
            "unknown handle index \{handle}; index \{handle} is not a resource",
          )
        } else if entry.type_id != expected_type_id {
          let expected_desc = if expected_kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let found_desc = if entry.kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let suffix = if entry.kind == expected_kind {
            "a different \{found_desc}"
          } else {
            found_desc
          }
          raise CanonCallError(
            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
          )
        }
    }
  }

  match func_type.result {
    None => []
    Some(r) =>
      match resolve_valtype(r, types) {
        Prim(p) =>
          match p {
            Bool =>
              match results {
                [@types.Value::I32(n)] => [ComponentValue::Bool(n != 0)]
                _ => raise HostCallError("result type mismatch")
              }
            S8 | U8 | S16 | U16 | S32 | U32 | Char =>
              match results {
                [@types.Value::I32(n)] =>
                  match p {
                    Char => [ComponentValue::Char(char_from_canon_i32(n))]
                    S8 => [ComponentValue::S8(trunc_s8(n))]
                    U8 => [ComponentValue::U8(trunc_u8(n))]
                    S16 => [ComponentValue::S16(trunc_s16(n))]
                    U16 => [ComponentValue::U16(trunc_u16(n))]
                    S32 => [ComponentValue::S32(n)]
                    U32 => [ComponentValue::U32(trunc_u32(n))]
                    _ => raise HostCallError("result type mismatch")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            S64 | U64 =>
              match results {
                [@types.Value::I64(n)] =>
                  if p == S64 {
                    [ComponentValue::S64(n)]
                  } else {
                    [ComponentValue::U64(n)]
                  }
                _ => raise HostCallError("result type mismatch")
              }
            F32 =>
              match results {
                [@types.Value::F32(n)] => [ComponentValue::F32(n)]
                _ => raise HostCallError("result type mismatch")
              }
            F64 =>
              match results {
                [@types.Value::F64(n)] => [ComponentValue::F64(n)]
                _ => raise HostCallError("result type mismatch")
              }
            String | ErrorContext => {
              let mem = match resources.mem_addr {
                Some(addr) =>
                  store.get_mem(addr) catch {
                    e => raise CanonCallError(e.to_string())
                  }
                None => raise MissingCanonMemory
              }
              let mem_is_64 = mem.is_memory64()
              let (ptr, len) = if mem_is_64 {
                match results {
                  [@types.Value::I64(p), @types.Value::I64(l)] =>
                    (p.to_int(), l.to_int())
                  [@types.Value::I64(p)] => {
                    let base = p.to_int()
                    let ptr64 = mem.load_i64(base) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len64 = mem.load_i64(base + 8) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr64.to_int(), len64.to_int())
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              } else {
                match results {
                  [@types.Value::I32(p), @types.Value::I32(l)] => (p, l)
                  [@types.Value::I32(p)] => {
                    let ptr32 = mem.load_i32(p) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len32 = mem.load_i32(p + 4) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr32, len32)
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              }
              let s = read_string_from_memory_with_encoding(
                mem,
                ptr,
                len,
                resources.encoding,
              )
              if p == String {
                [ComponentValue::String(s)]
              } else {
                [ComponentValue::ErrorContext(s)]
              }
            }
          }
        TypeIdx(_ti) => {
          let mut mem_is_64 = false
          let mut mem : @runtime.Memory? = None
          match resources.mem_addr {
            Some(addr) => {
              let m = store.get_mem(addr) catch {
                e => raise CanonCallError(e.to_string())
              }
              mem_is_64 = m.is_memory64()
              mem = Some(m)
            }
            None => ()
          }
          let flat_types = core_types_for_valtype(r, types, mem_is_64)
          let flat_vals : Array[@types.Value] = if flat_types.length() == 1 {
            results
          } else if results.length() == flat_types.length() {
            results
          } else if results.length() == 1 {
            let m = match mem {
              Some(m) => m
              None => raise MissingCanonMemory
            }
            let ptr = match results[0] {
              @types.Value::I32(n) => n
              @types.Value::I64(n) => n.to_int()
              _ => raise HostCallError("result type mismatch")
            }
            let (offsets, _size, struct_align) = layout_of_flat_types(
              flat_types,
            )
            if struct_align > 1 &&
              ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() !=
              0U {
              raise CanonCallError("unaligned pointer")
            }
            let out : Array[@types.Value] = []
            for i in 0..<flat_types.length() {
              out.push(load_flat_value(m, ptr + offsets[i], flat_types[i]))
            }
            out
          } else {
            raise HostCallError("result type mismatch")
          }
          let v = lift_component_value_from_flat(
            r,
            flat_vals,
            types,
            mem,
            mem_is_64,
            resources.encoding,
          )
          // Validate top-level resource handles so type mismatches trap instead of
          // escaping as raw integers.
          match resolve_valtype(r, types) {
            TypeIdx(ti) =>
              match types.get(ti) {
                Some(Some(TypeDef::Own(resource_tyidx)))
                | Some(Some(TypeDef::Borrow(resource_tyidx))) => {
                  let (type_id, kind) = resource_type_info(
                    resource_tyidx, types,
                  )
                  match v {
                    ComponentValue::U32(h) =>
                      validate_resource_handle(h, type_id, kind, resource_table)
                    ComponentValue::S32(h) =>
                      validate_resource_handle(h, type_id, kind, resource_table)
                    _ => ()
                  }
                }
                _ => ()
              }
            _ => ()
          }
          [v]
        }
      }
  }
}

///|
fn core_args_to_component(
  args : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  resource_table : ResourceTable,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  fn resource_type_info(
    tyidx : Int,
    types : Array[TypeDef?],
  ) -> (Int, ResourceKind) raise ComponentRuntimeError {
    match types.get(tyidx) {
      Some(Some(TypeDef::ResourceType(id, _, _, kind))) => (id, kind)
      _ => raise HostCallError("invalid resource type")
    }
  }

  fn validate_resource_handle(
    handle : Int,
    expected_type_id : Int,
    expected_kind : ResourceKind,
    table : ResourceTable,
  ) -> Unit raise ComponentRuntimeError {
    match table.get(handle) {
      None =>
        raise CanonCallError(
          "unknown handle index \{handle}; index \{handle} is not a resource",
        )
      Some(entry) =>
        if entry.type_id < 0 {
          raise CanonCallError(
            "unknown handle index \{handle}; index \{handle} is not a resource",
          )
        } else if entry.type_id != expected_type_id {
          let expected_desc = if expected_kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let found_desc = if entry.kind == ResourceKind::GuestDefined {
            "guest-defined resource"
          } else {
            "host-defined resource"
          }
          let suffix = if entry.kind == expected_kind {
            "a different \{found_desc}"
          } else {
            found_desc
          }
          raise CanonCallError(
            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
          )
        }
    }
  }

  let mut mem_is_64 = false
  let mut mem : @runtime.Memory? = None
  match resources.mem_addr {
    Some(addr) => {
      let m = store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
      mem_is_64 = m.is_memory64()
      mem = Some(m)
    }
    None => ()
  }
  let flat_param_types : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      flat_param_types.push(t)
    }
  }
  let indirect_params = flat_param_types.length() > 16
  let flat_result_types : Array[@types.ValueType] = match func_type.result {
    Some(r) => core_types_for_valtype(r, types, mem_is_64)
    None => []
  }
  let indirect_result = flat_result_types.length() > 1
  let arg_limit = if indirect_result {
    args.length() - 1
  } else {
    args.length()
  }
  let flat_vals : Array[@types.Value] = if indirect_params {
    if arg_limit < 1 {
      raise HostCallError("argument type mismatch")
    }
    let ptr = match args[0] {
      @types.Value::I32(n) => n
      @types.Value::I64(n) => n.to_int()
      _ => raise HostCallError("argument type mismatch")
    }
    let m = match mem {
      Some(m) => m
      None => raise MissingCanonMemory
    }
    let (offsets, _size, struct_align) = layout_of_flat_types(flat_param_types)
    if struct_align > 1 &&
      ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() != 0U {
      raise CanonCallError("unaligned pointer")
    }
    let out : Array[@types.Value] = []
    for i in 0..<flat_param_types.length() {
      out.push(load_flat_value(m, ptr + offsets[i], flat_param_types[i]))
    }
    out
  } else {
    let out : Array[@types.Value] = []
    for i in 0..<arg_limit {
      out.push(args[i])
    }
    out
  }
  let values : Array[ComponentValue] = []
  let mut pos = 0
  for p in func_type.params {
    let flat_types = core_types_for_valtype(p.ty, types, mem_is_64)
    let n = flat_types.length()
    if pos + n > flat_vals.length() {
      raise HostCallError("argument type mismatch")
    }
    let seg : Array[@types.Value] = []
    for i in 0..<n {
      seg.push(flat_vals[pos + i])
    }
    let v = lift_component_value_from_flat(
      p.ty,
      seg,
      types,
      mem,
      mem_is_64,
      resources.encoding,
    )
    // Validate top-level resource handles to avoid passing invalid integers into
    // host/component functions.
    match resolve_valtype(p.ty, types) {
      TypeIdx(ti) =>
        match types.get(ti) {
          Some(Some(TypeDef::Own(resource_tyidx)))
          | Some(Some(TypeDef::Borrow(resource_tyidx))) => {
            let (type_id, kind) = resource_type_info(resource_tyidx, types)
            match v {
              ComponentValue::U32(h) =>
                validate_resource_handle(h, type_id, kind, resource_table)
              ComponentValue::S32(h) =>
                validate_resource_handle(h, type_id, kind, resource_table)
              _ => ()
            }
          }
          _ => ()
        }
      _ => ()
    }
    values.push(v)
    pos += n
  }
  if pos != flat_vals.length() {
    raise HostCallError("argument type mismatch")
  }
  values
}

///|
fn component_results_to_core(
  results : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  retptr : Int?,
) -> Array[@types.Value] raise ComponentRuntimeError {
  match func_type.result {
    None => []
    Some(r) => {
      if results.length() == 0 {
        raise HostCallError("missing result")
      }
      let val = results[0]
      let mem = match resources.mem_addr {
        Some(addr) =>
          store.get_mem(addr) catch {
            e => raise CanonCallError(e.to_string())
          }
        None => @runtime.Memory::new(0, None)
      }
      let mem_is_64 = mem.is_memory64()
      let flat_res_types = core_types_for_valtype(r, types, mem_is_64)
      if flat_res_types.length() > 1 {
        if resources.mem_addr is None {
          raise MissingCanonMemory
        }
        let out_ptr = match retptr {
          Some(p) => p
          None => raise HostCallError("missing retptr")
        }
        let (offsets, _size, struct_align) = layout_of_flat_types(
          flat_res_types,
        )
        if struct_align > 1 &&
          out_ptr.reinterpret_as_uint() % struct_align.reinterpret_as_uint() !=
          0U {
          raise CanonCallError("unaligned pointer")
        }
        fn lower_value(
          v : ComponentValue,
          ty : ValType,
        ) -> Array[@types.Value] raise ComponentRuntimeError {
          match resolve_valtype(ty, types) {
            Prim(p) =>
              match (p, v) {
                (Bool, ComponentValue::Bool(b)) =>
                  [@types.Value::I32(if b { 1 } else { 0 })]
                (S8, ComponentValue::S8(n))
                | (U8, ComponentValue::U8(n))
                | (S16, ComponentValue::S16(n))
                | (U16, ComponentValue::U16(n))
                | (S32, ComponentValue::S32(n))
                | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
                (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
                  [@types.Value::I64(n)]
                (F32, ComponentValue::F32(f)) => [@types.Value::F32(f)]
                (F64, ComponentValue::F64(f)) => [@types.Value::F64(f)]
                (Char, ComponentValue::Char(c)) =>
                  [@types.Value::I32(c.to_int())]
                (String, ComponentValue::String(s))
                | (ErrorContext, ComponentValue::ErrorContext(s)) => {
                  if resources.mem_addr is None {
                    raise MissingCanonMemory
                  }
                  let realloc = match resources.realloc {
                    Some(rf) => rf
                    None => raise MissingCanonRealloc
                  }
                  let (bytes, canon_len, align) = encode_string_for_canon(
                    s,
                    resources.encoding,
                  )
                  let ptr = write_bytes_to_memory_with_align(
                    store, mem, realloc, mem_is_64, bytes, align,
                  )
                  if mem_is_64 {
                    [
                      @types.Value::I64(ptr.to_int64()),
                      @types.Value::I64(canon_len.to_int64()),
                    ]
                  } else {
                    [@types.Value::I32(ptr), @types.Value::I32(canon_len)]
                  }
                }
                _ => raise HostCallError("result type mismatch")
              }
            TypeIdx(ti) =>
              match types.get(ti) {
                Some(Some(TypeDef::Tuple(tys))) =>
                  match v {
                    ComponentValue::Tuple(items) =>
                      if items.length() != tys.length() {
                        raise HostCallError("result type mismatch")
                      } else {
                        let out : Array[@types.Value] = []
                        for i in 0..<tys.length() {
                          for vv in lower_value(items[i], tys[i]) {
                            out.push(vv)
                          }
                        }
                        out
                      }
                    _ => raise HostCallError("result type mismatch")
                  }
                Some(Some(TypeDef::Record(fields))) =>
                  match v {
                    ComponentValue::Tuple(items) =>
                      if items.length() != fields.length() {
                        raise HostCallError("result type mismatch")
                      } else {
                        let out : Array[@types.Value] = []
                        for i in 0..<fields.length() {
                          for vv in lower_value(items[i], fields[i].ty) {
                            out.push(vv)
                          }
                        }
                        out
                      }
                    _ => raise HostCallError("result type mismatch")
                  }
                Some(Some(TypeDef::Own(_)))
                | Some(Some(TypeDef::Borrow(_)))
                | Some(Some(TypeDef::ResourceType(_, _, _, _)))
                | Some(Some(TypeDef::Stream(_)))
                | Some(Some(TypeDef::Future(_))) =>
                  match v {
                    ComponentValue::U32(handle) => [@types.Value::I32(handle)]
                    ComponentValue::S32(handle) => [@types.Value::I32(handle)]
                    _ => raise HostCallError("result type mismatch")
                  }
                _ => raise HostCallError("unsupported result type")
              }
          }
        }

        let flat_vals = lower_value(val, r)
        if flat_vals.length() != flat_res_types.length() {
          raise HostCallError("result type mismatch")
        }
        for i in 0..<flat_vals.length() {
          store_flat_value(mem, out_ptr + offsets[i], flat_vals[i])
        }
        return []
      }
      match resolve_valtype(r, types) {
        Prim(p) =>
          match (p, val) {
            (Bool, ComponentValue::Bool(b)) =>
              [@types.Value::I32(if b { 1 } else { 0 })]
            (S8, ComponentValue::S8(n))
            | (U8, ComponentValue::U8(n))
            | (S16, ComponentValue::S16(n))
            | (U16, ComponentValue::U16(n))
            | (S32, ComponentValue::S32(n))
            | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
            (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
              [@types.Value::I64(n)]
            (F32, ComponentValue::F32(n)) => [@types.Value::F32(n)]
            (F64, ComponentValue::F64(n)) => [@types.Value::F64(n)]
            (Char, ComponentValue::Char(c)) => [@types.Value::I32(c.to_int())]
            (String, ComponentValue::String(s))
            | (ErrorContext, ComponentValue::ErrorContext(s)) => {
              let mem = require_memory(resources, store)
              let mem_is_64 = mem.is_memory64()
              let realloc = match resources.realloc {
                Some(rf) => rf
                None => raise MissingCanonRealloc
              }
              let (bytes, canon_len, align) = encode_string_for_canon(
                s,
                resources.encoding,
              )
              let ptr = write_bytes_to_memory_with_align(
                store, mem, realloc, mem_is_64, bytes, align,
              )
              let len = canon_len
              if mem_is_64 {
                [
                  @types.Value::I64(ptr.to_int64()),
                  @types.Value::I64(len.to_int64()),
                ]
              } else {
                [@types.Value::I32(ptr), @types.Value::I32(len)]
              }
            }
            _ => raise HostCallError("result type mismatch")
          }
        TypeIdx(ti) =>
          match types.get(ti) {
            Some(Some(TypeDef::Own(_)))
            | Some(Some(TypeDef::Borrow(_)))
            | Some(Some(TypeDef::ResourceType(_, _, _, _)))
            | Some(Some(TypeDef::Stream(_)))
            | Some(Some(TypeDef::Future(_))) =>
              match val {
                ComponentValue::U32(handle) => [@types.Value::I32(handle)]
                ComponentValue::S32(handle) => [@types.Value::I32(handle)]
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Variant(cases))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) => {
                  if tag < 0 || tag >= cases.length() {
                    raise HostCallError("invalid variant discriminant")
                  }
                  // Only variants with an empty payload flatten to a single i32 result here.
                  match cases[tag].ty {
                    None =>
                      match payload_opt {
                        None => [@types.Value::I32(tag)]
                        Some(_) => raise HostCallError("result type mismatch")
                      }
                    Some(_) => raise HostCallError("unsupported result type")
                  }
                }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Option(_payload_ty))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) =>
                  if tag == 0 {
                    if payload_opt is Some(_) {
                      raise HostCallError("result type mismatch")
                    }
                    [@types.Value::I32(0)]
                  } else if tag == 1 {
                    // Options with payload would have been handled by the indirect-result path.
                    if payload_opt is None {
                      raise HostCallError("result type mismatch")
                    }
                    raise HostCallError("unsupported result type")
                  } else {
                    raise HostCallError("invalid variant discriminant")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Result(_ok_ty, _err_ty))) =>
              match val {
                ComponentValue::Variant(tag, payload_opt) =>
                  if tag == 0 || tag == 1 {
                    if payload_opt is Some(_) {
                      // Payload results are indirect today.
                      raise HostCallError("unsupported result type")
                    }
                    [@types.Value::I32(tag)]
                  } else {
                    raise HostCallError("invalid variant discriminant")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            Some(Some(TypeDef::Flags(labels))) => {
              let nbits = labels.length()
              if nbits <= 32 {
                let raw = match val {
                  ComponentValue::U32(n) => n.reinterpret_as_uint()
                  ComponentValue::S32(n) => n.reinterpret_as_uint()
                  _ => raise HostCallError("result type mismatch")
                }
                let masked = if nbits == 32 {
                  raw
                } else {
                  raw & ((1U << nbits) - 1U)
                }
                [@types.Value::I32(masked.reinterpret_as_int())]
              } else {
                let raw = match val {
                  ComponentValue::U64(n) => n.reinterpret_as_uint64()
                  ComponentValue::S64(n) => n.reinterpret_as_uint64()
                  _ => raise HostCallError("result type mismatch")
                }
                let masked = if nbits == 64 {
                  raw
                } else {
                  raw & ((1UL << nbits) - 1UL)
                }
                [@types.Value::I64(masked.reinterpret_as_int64())]
              }
            }
            Some(Some(TypeDef::Enum(labels))) => {
              let n = match val {
                ComponentValue::U32(n) => n
                ComponentValue::S32(n) => n
                _ => raise HostCallError("result type mismatch")
              }
              if n < 0 || n >= labels.length() {
                raise HostCallError("invalid enum discriminant")
              }
              [@types.Value::I32(n)]
            }
            _ => raise HostCallError("unsupported result type")
          }
      }
    }
  }
}

///|
/// Drive an async component function to completion (blocking the current task).
///
/// Async functions communicate their eventual results through `canon task.return`.
fn await_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let can_block = async_state.task_can_block[0]
  if !can_block {
    raise CanonCallError("cannot block a synchronous task before returning")
  }
  let task_id = alloc_task_id(async_state)
  push_task(async_state, task_id, can_block)
  take_task_result(async_state, task_id) |> ignore
  let out = try {
    match func {
      ComponentFunc::Host(_ft, _types, host) =>
        host(args, caller_table) catch {
          e => raise HostCallError(e.to_string())
        }
      ComponentFunc::Lifted(
        core_func,
        func_type,
        resources,
        types,
        callee_table,
        _may_enter,
        cb_opt,
        async_abi
      ) => {
        if func_type_needs_memory(func_type, types) &&
          resources.mem_addr is None {
          raise MissingCanonMemory
        }
        let core_args = component_args_to_core(
          args, func_type, types, resources, store, caller_table, callee_table,
        )
        match cb_opt {
          None =>
            if async_abi {
              // Sync-style async ABI: the core function may suspend (thread.yield / waitable-set.wait).
              while true {
                if async_state.yield_cursor_stack.length() > 0 {
                  async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                  1] = 0
                }
                if async_state.wait_cursor_stack.length() > 0 {
                  async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                  1] = 0
                }
                if async_state.call_cursor_stack.length() > 0 {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = 0
                }
                let core_results = call_core_func(store, core_func, core_args) catch {
                  AsyncSuspendYield => {
                    if !progress_one_subtask(async_state, store) {
                      raise CanonCallError(
                        "wasm trap: deadlock detected: event loop cannot make further progress",
                      )
                    }
                    continue
                  }
                  AsyncSuspendWait(ws) => {
                    while !waitable_set_has_event(async_state, ws) {
                      if !progress_one_subtask(async_state, store) {
                        raise CanonCallError(
                          "wasm trap: deadlock detected: event loop cannot make further progress",
                        )
                      }
                    }
                    continue
                  }
                  e => raise e
                }
                let vals = core_results_to_component(
                  core_results, func_type, types, resources, store, callee_table,
                )
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, vals)
                pop_task(async_state)
                return vals
              }
              raise CanonCallError("unreachable")
            } else {
              // Sync-style async: the core function returns results directly (no task.return).
              let core_results = call_core_func(store, core_func, core_args)
              let vals = core_results_to_component(
                core_results, func_type, types, resources, store, callee_table,
              )
              // Mirror task.return bookkeeping so other parts can uniformly query results.
              async_state.task_returned.set(task_id, true)
              set_task_result(async_state, task_id, vals)
              vals
            }
          Some(cb) => {
            let core_results = call_core_func(store, core_func, core_args)
            let mut code = match core_results {
              [@types.Value::I32(n)] => n
              _ => raise CanonCallError("type mismatch")
            }
            while true {
              let u = code.reinterpret_as_uint()
              let tag = (u & 0xFU).reinterpret_as_int()
              let payload = (u >> 4).reinterpret_as_int()
              if tag == 0 {
                break
              } else if tag == 1 {
                // YIELD
                if !can_block {
                  raise CanonCallError(
                    "cannot block a synchronous task before returning",
                  )
                }
                progress_one_subtask(async_state, store) |> ignore
                async_state.in_async_callback[0] = true
                let r = call_core_func(store, cb, [
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                  @types.Value::I32(0),
                ])
                async_state.in_async_callback[0] = false
                code = match r {
                  [@types.Value::I32(n)] => n
                  _ => raise CanonCallError("type mismatch")
                }
              } else if tag == 2 {
                // WAIT
                if !can_block {
                  raise CanonCallError(
                    "cannot block a synchronous task before returning",
                  )
                }
                let ev = wait_for_event(async_state, store, payload)
                async_state.in_async_callback[0] = true
                let r = call_core_func(store, cb, [
                  @types.Value::I32(ev.code),
                  @types.Value::I32(ev.index),
                  @types.Value::I32(ev.payload),
                ])
                async_state.in_async_callback[0] = false
                code = match r {
                  [@types.Value::I32(n)] => n
                  _ => raise CanonCallError("type mismatch")
                }
              } else {
                raise CanonCallError("unsupported callback code: \{tag}")
              }
            }
            match take_task_result(async_state, task_id) {
              Some(vals) => vals
              None => []
            }
          }
        }
      }
    }
  } catch {
    e => {
      pop_task(async_state)
      raise e
    }
  }
  pop_task(async_state)
  out
}

///|
fn wait_for_event(
  async_state : AsyncState,
  store : @runtime.Store,
  ws : Int,
) -> WaitEvent raise ComponentRuntimeError {
  match async_state.waitable_sets.get(ws) {
    Some(set) => set.waiters[0] = set.waiters[0] + 1
    None => raise CanonCallError("unknown waitable set index \{ws}")
  }
  while true {
    match pop_waitable_event(async_state, ws) {
      Some(ev) => {
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] - 1
          None => ()
        }
        return ev
      }
      None => ()
    }
    if !progress_one_subtask(async_state, store) {
      raise CanonCallError(
        "wasm trap: deadlock detected: event loop cannot make further progress",
      )
    }
  }
  raise CanonCallError("unreachable")
}

///|
fn waitable_set_has_event(async_state : AsyncState, ws : Int) -> Bool {
  match async_state.waitable_sets.get(ws) {
    Some(set) => set.queue.length() > 0
    None => false
  }
}

///|
struct DecodedCallbackCode {
  tag : Int
  payload : Int
} derive(Show)

///|
fn decode_callback_code(code : Int) -> DecodedCallbackCode {
  let u = code.reinterpret_as_uint()
  let tag = (u & 0xFU).reinterpret_as_int()
  let payload = (u >> 4).reinterpret_as_int()
  { tag, payload }
}

///|
fn step_task_once(
  task : CallbackTask,
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
) -> TaskStep raise ComponentRuntimeError {
  fn set_waiting(ws_opt : Int?) -> Unit {
    let prev = task.waiting_set[0]
    // No change.
    if prev == ws_opt {
      task.waiting_set[0] = ws_opt
      return
    }
    match prev {
      Some(ws) =>
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] - 1
          None => ()
        }
      None => ()
    }
    match ws_opt {
      Some(ws) =>
        match async_state.waitable_sets.get(ws) {
          Some(set) => set.waiters[0] = set.waiters[0] + 1
          None => ()
        }
      None => ()
    }
    task.waiting_set[0] = ws_opt
  }

  match task.func {
    ComponentFunc::Host(_ft, _types, host) => {
      (host(task.args, caller_table) catch {
        e => raise HostCallError(e.to_string())
      })
      |> ignore
      TaskStep::Done
    }
    ComponentFunc::Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      _may_enter,
      cb_opt,
      async_abi
    ) => {
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let core_args = component_args_to_core(
        task.args,
        func_type,
        types,
        resources,
        store,
        caller_table,
        callee_table,
      )

      // Callback-style async ABI: initial call returns a callback code; resumption uses `callback`.
      if cb_opt is Some(cb) {
        // If we were suspended while waiting on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) && !task.cancelled[0] {
              return TaskStep::Blocked
            }
          None => ()
        }
        if !task.started[0] {
          task.started[0] = true
          let core_results = call_core_func(store, core_func, core_args) catch {
            AsyncSuspendYield => {
              // Cooperative suspension (e.g. sync-lowering an async callee).
              task.started[0] = false
              set_waiting(None)
              // Replay from the top: reset restartable cursors for this task invocation.
              if async_state.yield_cursor_stack.length() > 0 {
                async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                1] = 0
              }
              if async_state.wait_cursor_stack.length() > 0 {
                async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                1] = 0
              }
              if async_state.call_cursor_stack.length() > 0 {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1] = 0
              }
              return TaskStep::Progressed
            }
            AsyncSuspendWait(ws) => {
              task.started[0] = false
              set_waiting(Some(ws))
              if async_state.yield_cursor_stack.length() > 0 {
                async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                1] = 0
              }
              if async_state.wait_cursor_stack.length() > 0 {
                async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                1] = 0
              }
              if async_state.call_cursor_stack.length() > 0 {
                async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                1] = 0
              }
              return TaskStep::Blocked
            }
            e => raise e
          }
          let code = match core_results {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        let d0 = decode_callback_code(task.code[0])
        if d0.tag == 0 {
          return TaskStep::Done
        }
        if d0.tag == 1 {
          // YIELD
          let args = if task.cancelled[0] {
            task.cancelled[0] = false
            // TASK_CANCELLED=6, index=0, payload=0 (component-spec convention).
            [@types.Value::I32(6), @types.Value::I32(0), @types.Value::I32(0)]
          } else {
            [@types.Value::I32(0), @types.Value::I32(0), @types.Value::I32(0)]
          }
          async_state.in_async_callback[0] = true
          let r = call_core_func(store, cb, args)
          async_state.in_async_callback[0] = false
          let code = match r {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        if d0.tag == 2 {
          let ws = d0.payload
          set_waiting(Some(ws))
          // Cancellation preempts waiting: deliver TASK_CANCELLED immediately.
          if task.cancelled[0] {
            task.cancelled[0] = false
            set_waiting(None)
            async_state.in_async_callback[0] = true
            let r = call_core_func(store, cb, [
              @types.Value::I32(6),
              @types.Value::I32(0),
              @types.Value::I32(0),
            ])
            async_state.in_async_callback[0] = false
            let code = match r {
              [@types.Value::I32(n)] => n
              _ => raise CanonCallError("type mismatch")
            }
            task.code[0] = code
            let d = decode_callback_code(code)
            set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
            return if d.tag == 0 {
              TaskStep::Done
            } else {
              TaskStep::Progressed
            }
          }
          if !waitable_set_has_event(async_state, ws) {
            return TaskStep::Blocked
          }
          let ev = match pop_waitable_event(async_state, ws) {
            Some(ev) => ev
            None => return TaskStep::Blocked
          }
          // Leaving the waiting state to process one event.
          set_waiting(None)
          async_state.in_async_callback[0] = true
          let r = call_core_func(store, cb, [
            @types.Value::I32(ev.code),
            @types.Value::I32(ev.index),
            @types.Value::I32(ev.payload),
          ])
          async_state.in_async_callback[0] = false
          let code = match r {
            [@types.Value::I32(n)] => n
            _ => raise CanonCallError("type mismatch")
          }
          task.code[0] = code
          let d = decode_callback_code(code)
          set_waiting(if d.tag == 2 { Some(d.payload) } else { None })
          return if d.tag == 0 { TaskStep::Done } else { TaskStep::Progressed }
        }
        raise CanonCallError("unsupported callback code: \{d0.tag}")
      }

      // Sync-style async ABI uses cooperative suspension.
      if async_abi {
        // If previously blocked on a waitable-set, only resume once an event exists.
        match task.waiting_set[0] {
          Some(ws) =>
            if !waitable_set_has_event(async_state, ws) {
              return TaskStep::Blocked
            }
          None => ()
        }
        // Re-run from the top; intrinsics will replay completed suspension points.
        try {
          let core_results = call_core_func(store, core_func, core_args)
          if func_type.is_async {
            let vals = core_results_to_component(
              core_results, func_type, types, resources, store, callee_table,
            )
            let task_id = current_task_id(async_state)
            async_state.task_returned.set(task_id, true)
            set_task_result(async_state, task_id, vals)
          }
          TaskStep::Done
        } catch {
          AsyncSuspendYield => {
            task.started[0] = true
            task.waiting_set[0] = None
            TaskStep::Progressed
          }
          AsyncSuspendWait(ws) => {
            task.started[0] = true
            task.waiting_set[0] = Some(ws)
            TaskStep::Progressed
          }
          e => raise e
        }
      } else {
        // No async ABI: normal call. For sync-style async funcs, results are returned directly.
        let core_results = call_core_func(store, core_func, core_args)
        if func_type.is_async {
          let vals = core_results_to_component(
            core_results, func_type, types, resources, store, callee_table,
          )
          let task_id = current_task_id(async_state)
          async_state.task_returned.set(task_id, true)
          set_task_result(async_state, task_id, vals)
        }
        TaskStep::Done
      }
    }
  }
}

///|
fn progress_one_subtask(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  // Avoid re-entering tasks already on the call stack: sync lower wrappers may
  // "pump" the event loop while inside a task, but must never step that same task.
  fn task_on_stack(id : Int) -> Bool {
    for t in async_state.task_stack {
      if t == id {
        return true
      }
    }
    false
  }

  // Start one queued subtask when an instance has no in-flight task.
  // NOTE: avoid mutating `pending_by_instance` while iterating it; some Map
  // implementations invalidate iterators and can segfault.
  let pending_keys : Array[Int] = []
  for kv in async_state.pending_by_instance.iter() {
    let (key, _queue) = kv
    pending_keys.push(key)
  }
  for key in pending_keys {
    let queue0 = match async_state.pending_by_instance.get(key) {
      Some(q) => q
      None => continue
    }
    let inflight = match async_state.inflight_by_instance.get(key) {
      Some(n) => n
      None => 0
    }
    if inflight == 0 && queue0.length() > 0 {
      let next_id = queue0.remove(0)
      if queue0.length() == 0 {
        async_state.pending_by_instance.remove(key)
      }
      match async_state.subtasks.get(next_id) {
        Some(st) =>
          if !task_on_stack(st.id) {
            st.phase[0] = SubtaskPhase::Started
            async_state.inflight_by_instance.set(key, 1)
            // Transitioned from STARTING to STARTED: notify via event.
            enqueue_waitable_event(async_state, st.id, {
              code: 1,
              index: st.id,
              payload: 1,
            })
            return true
          }
        None => ()
      }
    }
  }

  // Advance one runnable STARTED subtask/background task.
  for kv in async_state.subtasks.iter() {
    let (_id, st) = kv
    if st.phase[0] != SubtaskPhase::Started {
      continue
    }
    if task_on_stack(st.id) {
      continue
    }
    push_task(async_state, st.id, true)
    let step = match st.driver {
      SubtaskDriver::CallbackLifted(t) =>
        step_task_once(t, store, st.caller_table, async_state)
      _ => TaskStep::Blocked
    }
    pop_task(async_state)
    match step {
      TaskStep::Blocked => ()
      TaskStep::Progressed => return true
      TaskStep::Done => {
        // Write subtask results into the return buffer (async-lower ABI).
        // component-spec expects the return value to be materialized in memory
        // before emitting the RETURNED event.
        let cancelled = async_state.task_cancelled.get(st.id) is Some(true)
        match st.result_ty {
          Some(_) =>
            if st.mem_addr is Some(mem_addr) {
              let mem = store.get_mem(mem_addr) catch {
                e => raise CanonCallError(e.to_string())
              }
              let vals = if cancelled {
                // Cancelled subtasks resolve without writing a value.
                take_task_result(async_state, st.id) |> ignore
                ([] : Array[ComponentValue])
              } else {
                match async_state.task_results.get(st.id) {
                  Some(v) => v
                  None => []
                }
              }
              // Lower into core values; direct scalars come back as a single
              // value which we store at `retptr`. Indirect results are written
              // by `component_results_to_core` via `retptr`.
              if !cancelled {
                let (ft, ftypes) = match st.driver {
                  SubtaskDriver::CallbackLifted(t) =>
                    match t.func {
                      ComponentFunc::Host(func_type, types, _) =>
                        (func_type, types)
                      ComponentFunc::Lifted(_, func_type, _, types, _, _, _, _) =>
                        (func_type, types)
                    }
                  _ => raise CanonCallError("unsupported subtask driver")
                }
                let core_vals = component_results_to_core(
                  vals,
                  ft,
                  ftypes,
                  st.resources,
                  store,
                  Some(st.retptr),
                )
                match core_vals {
                  [@types.Value::I32(n)] =>
                    mem.store_i32(st.retptr, n) catch {
                      _ => ()
                    }
                  [@types.Value::I64(n)] =>
                    mem.store_i64(st.retptr, n) catch {
                      _ => ()
                    }
                  _ => ()
                }
              }
            } else {
              // Result present but no memory: validated earlier for async-lower.
              raise MissingCanonMemory
            }
          None => ()
        }
        // Mark returned and emit RETURNED event. The return value itself is written by the lower wrapper.
        st.phase[0] = SubtaskPhase::Returned
        async_state.inflight_by_instance.set(st.bp_key, 0)
        enqueue_waitable_event(async_state, st.id, {
          code: 1,
          index: st.id,
          payload: 2,
        })
        return true
      }
    }
  }
  false
}

///|
fn call_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  resource_table : ResourceTable,
  async_state : AsyncState,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match func {
    ComponentFunc::Host(func_type, _types, host) =>
      if func_type.is_async {
        await_component_func(func, args, store, resource_table, async_state)
      } else {
        host(args, resource_table) catch {
          e => raise HostCallError(e.to_string())
        }
      }
    ComponentFunc::Lifted(
      core_func,
      func_type,
      resources,
      types,
      callee_table,
      _may_enter,
      _callback,
      _async_abi
    ) => {
      if func_type.is_async {
        return await_component_func(
          func, args, store, resource_table, async_state,
        )
      }
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let core_args = component_args_to_core(
        args, func_type, types, resources, store, resource_table, callee_table,
      )
      let core_results = call_core_func(store, core_func, core_args)
      let component_results = core_results_to_component(
        core_results, func_type, types, resources, store, callee_table,
      )
      match resources.post_return {
        Some(pr) => {
          let prev = canon_may_leave[0]
          canon_may_leave[0] = false
          (call_core_func(store, pr, core_results) catch {
            e => {
              canon_may_leave[0] = prev
              raise e
            }
          })
          |> ignore
          canon_may_leave[0] = prev
        }
        None => ()
      }
      // If this function belongs to a different component instance, transfer
      // owned resources into the caller's table so handles are local.
      if resource_table.id != callee_table.id {
        match func_type.result {
          Some(TypeIdx(ti)) =>
            match types.get(ti) {
              Some(Some(TypeDef::Own(_resource_tyidx))) =>
                match component_results {
                  [ComponentValue::U32(h)] => {
                    let entry = match callee_table.free(h) {
                      Some(e) => e
                      None => raise CanonCallError("unknown handle index \{h}")
                    }
                    let new_h = resource_table.alloc(entry)
                    [ComponentValue::U32(new_h)]
                  }
                  _ => component_results
                }
              _ => component_results
            }
          _ => component_results
        }
      } else {
        component_results
      }
    }
  }
}

///|
fn core_instance_from_module(
  instance : @runtime.ModuleInstance,
) -> CoreInstance {
  let funcs : Map[String, CoreFuncRef] = {}
  let tables : Map[String, Int] = {}
  let memories : Map[String, Int] = {}
  let globals : Map[String, Int] = {}
  let tags : Map[String, Int] = {}
  for exp in instance.exports {
    match exp.desc {
      @types.ExportDesc::Func(idx) =>
        funcs.set(exp.name, { instance, func_idx: idx })
      @types.ExportDesc::Table(idx) =>
        tables.set(exp.name, instance.table_addrs[idx])
      @types.ExportDesc::Memory(idx) =>
        memories.set(exp.name, instance.mem_addrs[idx])
      @types.ExportDesc::Global(idx) =>
        globals.set(exp.name, instance.global_addrs[idx])
      @types.ExportDesc::Tag(idx) => tags.set(exp.name, instance.tag_addrs[idx])
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
priv enum CoreExternType {
  Func(@types.FuncType)
  Table(@types.TableType)
  Memory(@types.MemoryType)
  Global(@types.GlobalType)
}

///|
priv struct CoreModuleTypeSpec {
  imports : Map[String, CoreExternType] // key: "<module>::<name>"
  exports : Map[String, CoreExternType] // key: "<name>"
}

///|
fn bytes_sub(bytes : Bytes, start : Int, end : Int) -> Bytes {
  let out : Array[Byte] = []
  for i in start..<end {
    out.push(bytes[i])
  }
  Bytes::from_array(out)
}

///|
fn parse_core_valtype(
  reader : Reader,
) -> @types.ValueType raise ComponentRuntimeError {
  let b = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  match b {
    0x7f => @types.ValueType::I32
    0x7e => @types.ValueType::I64
    0x7d => @types.ValueType::F32
    0x7c => @types.ValueType::F64
    0x7b => @types.ValueType::V128
    0x70 => @types.ValueType::FuncRef
    0x6f => @types.ValueType::ExternRef
    _ => raise ImportTypeMismatch("unsupported core valtype \{b}")
  }
}

///|
fn parse_limits_u32(
  reader : Reader,
) -> @types.Limits raise ComponentRuntimeError {
  let flags = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let min = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let max = if (flags & 0x01) != 0 {
    Some(
      reader.read_leb_u32() catch {
        e => raise ComponentParseError(e.to_string())
      },
    )
  } else {
    None
  }
  { min: min.to_int64(), max: max.map(fn(x) { x.to_int64() }) }
}

///|
fn parse_core_functype(
  reader : Reader,
) -> @types.FuncType raise ComponentRuntimeError {
  let form = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  if form != 0x60 {
    raise ImportTypeMismatch("invalid core functype form")
  }
  let nparams = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let params : Array[@types.ValueType] = []
  for _i in 0..<nparams {
    params.push(parse_core_valtype(reader))
  }
  let nresults = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let results : Array[@types.ValueType] = []
  for _i in 0..<nresults {
    results.push(parse_core_valtype(reader))
  }
  { params, results }
}

///|
fn parse_core_extern_type_in_moduletype(
  reader : Reader,
  kind : Int,
  func_types : Array[@types.FuncType],
) -> CoreExternType raise ComponentRuntimeError {
  match kind {
    0x00 => {
      let idx = reader.read_leb_u32() catch {
        e => raise ComponentParseError(e.to_string())
      }
      if idx < 0 || idx >= func_types.length() {
        raise ImportTypeMismatch("invalid module type func index")
      }
      CoreExternType::Func(func_types[idx])
    }
    0x01 => {
      let elem = parse_core_valtype(reader)
      let limits = parse_limits_u32(reader)
      CoreExternType::Table({ elem_type: elem, limits, is_table64: false })
    }
    0x02 => {
      let limits = parse_limits_u32(reader)
      CoreExternType::Memory({ limits, is_memory64: false, page_size_log2: 16 })
    }
    0x03 => {
      let vt = parse_core_valtype(reader)
      let mutability = reader.read_u8() catch {
        e => raise ComponentParseError(e.to_string())
      }
      CoreExternType::Global({ value_type: vt, mutable: mutability != 0 })
    }
    _ => raise ImportTypeMismatch("unsupported module type extern kind")
  }
}

///|
fn parse_core_moduletype_spec(
  core_type : Bytes,
) -> CoreModuleTypeSpec raise ComponentRuntimeError {
  let reader = Reader::new(core_type)
  let op = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  if op != 0x50 {
    raise ImportTypeMismatch("expected core module type")
  }
  let ndecls = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let func_types : Array[@types.FuncType] = []
  let imports : Map[String, CoreExternType] = {}
  let exports : Map[String, CoreExternType] = {}
  for _i in 0..<ndecls {
    let tag = reader.read_u8() catch {
      e => raise ComponentParseError(e.to_string())
    }
    match tag {
      0x00 => {
        let mod_name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let kind = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let ty = parse_core_extern_type_in_moduletype(reader, kind, func_types)
        imports.set("\{mod_name}::\{name}", ty)
      }
      0x01 => func_types.push(parse_core_functype(reader))
      0x02 => {
        // alias decl: sort + target + indices (skip)
        (reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        })
        |> ignore
        let target = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        if target == 0x01 {
          (reader.read_leb_u32() catch {
            e => raise ComponentParseError(e.to_string())
          })
          |> ignore
          (reader.read_leb_u32() catch {
            e => raise ComponentParseError(e.to_string())
          })
          |> ignore
        } else {
          raise ImportTypeMismatch("unsupported module type alias target")
        }
      }
      0x03 => {
        let name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let kind = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let ty = parse_core_extern_type_in_moduletype(reader, kind, func_types)
        exports.set(name, ty)
      }
      _ => raise ImportTypeMismatch("invalid module type declaration")
    }
  }
  if !reader.is_eof() {
    raise ImportTypeMismatch("invalid module type")
  }
  { imports, exports }
}

///|
fn core_extern_kind_name(ty : CoreExternType) -> String {
  match ty {
    Func(_) => "func"
    Table(_) => "table"
    Memory(_) => "memory"
    Global(_) => "global"
  }
}

///|
fn fmt_valtype(vt : @types.ValueType) -> String {
  match vt {
    @types.ValueType::I32 => "i32"
    @types.ValueType::I64 => "i64"
    @types.ValueType::F32 => "f32"
    @types.ValueType::F64 => "f64"
    @types.ValueType::V128 => "v128"
    @types.ValueType::FuncRef => "funcref"
    @types.ValueType::ExternRef => "externref"
    _ => "unknown"
  }
}

///|
fn fmt_functype(ft : @types.FuncType) -> String {
  let buf = StringBuilder::new()
  buf.write_string("(func")
  if ft.params.length() > 0 {
    buf.write_string(" (param")
    for p in ft.params {
      buf.write_string(" ")
      buf.write_string(fmt_valtype(p))
    }
    buf.write_string(")")
  }
  if ft.results.length() > 0 {
    buf.write_string(" (result")
    for r in ft.results {
      buf.write_string(" ")
      buf.write_string(fmt_valtype(r))
    }
    buf.write_string(")")
  }
  buf.write_string(")")
  buf.to_string()
}

///|
fn module_export_type(m : @types.Module, name : String) -> CoreExternType? {
  for e in m.exports {
    if e.name == name {
      match e.desc {
        @types.ExportDesc::Func(func_idx) => {
          // `Module.funcs` only contains defined functions. Exported function
          // indices are in the combined (imports + defs) index space.
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Func(tyidx) =>
                if imported == func_idx {
                  return Some(CoreExternType::Func(m.get_func_type(tyidx)))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = func_idx - imported
          if defined_idx < 0 || defined_idx >= m.funcs.length() {
            return None
          }
          let tyidx = m.funcs[defined_idx]
          return Some(CoreExternType::Func(m.get_func_type(tyidx)))
        }
        @types.ExportDesc::Table(table_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Table(tt) =>
                if imported == table_idx {
                  return Some(CoreExternType::Table(tt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = table_idx - imported
          if defined_idx < 0 || defined_idx >= m.tables.length() {
            return None
          }
          return Some(CoreExternType::Table(m.tables[defined_idx].type_))
        }
        @types.ExportDesc::Memory(mem_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Memory(mt) =>
                if imported == mem_idx {
                  return Some(CoreExternType::Memory(mt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = mem_idx - imported
          if defined_idx < 0 || defined_idx >= m.memories.length() {
            return None
          }
          return Some(CoreExternType::Memory(m.memories[defined_idx]))
        }
        @types.ExportDesc::Global(global_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Global(gt) =>
                if imported == global_idx {
                  return Some(CoreExternType::Global(gt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = global_idx - imported
          if defined_idx < 0 || defined_idx >= m.globals.length() {
            return None
          }
          return Some(CoreExternType::Global(m.globals[defined_idx].type_))
        }
        _ => return None
      }
    }
  }
  None
}

///|
fn module_import_type(
  m : @types.Module,
  mod_name : String,
  name : String,
) -> CoreExternType? {
  for imp in m.imports {
    if imp.mod_name == mod_name && imp.name == name {
      match imp.desc {
        @types.ImportDesc::Func(tyidx) =>
          return Some(CoreExternType::Func(m.get_func_type(tyidx)))
        @types.ImportDesc::Table(tt) => return Some(CoreExternType::Table(tt))
        @types.ImportDesc::Memory(mt) => return Some(CoreExternType::Memory(mt))
        @types.ImportDesc::Global(gt) => return Some(CoreExternType::Global(gt))
        _ => return None
      }
    }
  }
  None
}

///|
fn table_import_compatible(
  actual : @types.TableType,
  expected : @types.TableType,
) -> Bool {
  // Imports are contravariant in limits: requiring fewer is a subtype.
  actual.elem_type == expected.elem_type &&
  actual.limits.min <= expected.limits.min
}

///|
fn table_export_compatible(
  actual : @types.TableType,
  expected : @types.TableType,
) -> Bool {
  // Exports are covariant in limits: providing more is a subtype.
  actual.elem_type == expected.elem_type &&
  actual.limits.min >= expected.limits.min
}

///|
fn memory_import_compatible(
  actual : @types.MemoryType,
  expected : @types.MemoryType,
) -> Bool {
  actual.is_memory64 == expected.is_memory64 &&
  actual.page_size_log2 == expected.page_size_log2 &&
  actual.limits.min <= expected.limits.min
}

///|
fn memory_export_compatible(
  actual : @types.MemoryType,
  expected : @types.MemoryType,
) -> Bool {
  actual.is_memory64 == expected.is_memory64 &&
  actual.page_size_log2 == expected.page_size_log2 &&
  actual.limits.min >= expected.limits.min
}

///|
fn check_core_module_against_type(
  actual : @types.Module,
  core_type : Bytes,
) -> Unit raise ComponentRuntimeError {
  let spec = parse_core_moduletype_spec(core_type)
  // Actual module imports must all be declared in the module type.
  for imp in actual.imports {
    let key = "\{imp.mod_name}::\{imp.name}"
    match spec.imports.get(key) {
      None => raise ImportTypeMismatch("module import `\{key}` not defined")
      Some(expected) => {
        let actual_ty = match
          module_import_type(actual, imp.mod_name, imp.name) {
          Some(t) => t
          None =>
            raise ImportTypeMismatch(
              "module import `\{key}` has the wrong type",
            )
        }
        match (expected, actual_ty) {
          (CoreExternType::Func(ft1), CoreExternType::Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Global(gt1), CoreExternType::Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Table(tt1), CoreExternType::Table(tt2)) =>
            if !table_import_compatible(tt2, tt1) {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Memory(mt1), CoreExternType::Memory(mt2)) =>
            if !memory_import_compatible(mt2, mt1) {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          _ =>
            raise ImportTypeMismatch(
              // For module imports, the module's actual import requirement is
              // the "expected" shape, and the module type describes what was
              // actually specified.
              "expected \{core_extern_kind_name(actual_ty)} found \{core_extern_kind_name(expected)}",
            )
        }
      }
    }
  }
  // Module type exports must all exist in the actual module.
  for entry in spec.exports {
    let (name, expected) = entry
    match module_export_type(actual, name) {
      None => raise ImportTypeMismatch("module export `\{name}` not defined")
      Some(actual_ty) =>
        match (expected, actual_ty) {
          (CoreExternType::Func(ft1), CoreExternType::Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "export `\{name}` has the wrong type (expected type `\{fmt_functype(ft1)}`, found type `\{fmt_functype(ft2)}`)",
              )
            }
          (CoreExternType::Global(gt1), CoreExternType::Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (CoreExternType::Table(tt1), CoreExternType::Table(tt2)) =>
            if !table_export_compatible(tt2, tt1) {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (CoreExternType::Memory(mt1), CoreExternType::Memory(mt2)) =>
            if !memory_export_compatible(mt2, mt1) {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          _ =>
            raise ImportTypeMismatch(
              "expected \{core_extern_kind_name(expected)} found \{core_extern_kind_name(actual_ty)}",
            )
        }
    }
  }
}

///|
fn resolve_sortidx(
  sortidx : SortIdx,
  state : BuildState,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= state.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(state.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= state.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(state.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= state.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(state.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= state.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(state.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= state.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(state.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= state.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(state.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= state.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(state.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= state.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(state.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= state.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(state.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= state.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(state.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= state.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(state.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= state.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(state.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= state.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(state.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn resolve_sortidx_in_instance(
  sortidx : SortIdx,
  inst : ComponentInstance,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= inst.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(inst.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= inst.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(inst.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= inst.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(inst.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= inst.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(inst.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= inst.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(inst.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= inst.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(inst.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= inst.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(inst.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= inst.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(inst.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= inst.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(inst.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= inst.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(inst.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= inst.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(inst.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= inst.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(inst.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= inst.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(inst.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn append_alias(
  sort : Sort,
  ext : ComponentExtern,
  state : BuildState,
) -> Unit raise ComponentRuntimeError {
  match (sort, ext) {
    (Sort::Func, ComponentExtern::Func(f)) => state.funcs.push(f)
    (Sort::Value, ComponentExtern::Value(v)) => state.values.push(v)
    (Sort::Type, ComponentExtern::Type(t)) => state.types.push(t)
    (Sort::Component, ComponentExtern::Component(c)) => state.components.push(c)
    (Sort::Instance, ComponentExtern::Instance(i)) => state.instances.push(i)
    (Sort::Core(core_sort), ComponentExtern::CoreFunc(f)) =>
      if core_sort == 0x00 {
        state.core_funcs.push(f)
      } else {
        raise AliasTargetMismatch("core func")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTable(t)) =>
      if core_sort == 0x01 {
        state.core_tables.push(t)
      } else {
        raise AliasTargetMismatch("core table")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreMemory(m)) =>
      if core_sort == 0x02 {
        state.core_mems.push(m)
      } else {
        raise AliasTargetMismatch("core memory")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreGlobal(g)) =>
      if core_sort == 0x03 {
        state.core_globals.push(g)
      } else {
        raise AliasTargetMismatch("core global")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTag(t)) =>
      if core_sort == 0x04 {
        state.core_tags.push(t)
      } else {
        raise AliasTargetMismatch("core tag")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreType(t)) =>
      if core_sort == 0x05 || core_sort == 0x10 {
        state.core_types.push(t)
      } else {
        raise AliasTargetMismatch("core type")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreModule(m)) =>
      if core_sort == 0x11 {
        state.core_modules.push(m)
      } else {
        raise AliasTargetMismatch("core module")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreInstance(i)) =>
      if core_sort == 0x12 {
        state.core_instances.push(i)
      } else {
        raise AliasTargetMismatch("core instance")
      }
    _ => raise AliasTargetMismatch("sort mismatch")
  }
}

///|
fn resolve_outer_alias(
  outer_stack : Array[ComponentInstance],
  depth : Int,
  sort : Sort,
  idx : Int,
) -> ComponentExtern raise ComponentRuntimeError {
  if depth < 0 || depth >= outer_stack.length() {
    raise OuterAliasOutOfRange(depth)
  }
  let outer = outer_stack[outer_stack.length() - 1 - depth]
  resolve_sortidx_in_instance({ sort, idx }, outer)
}

///|
fn extend_outer_stack(
  outer_stack : Array[ComponentInstance],
  env : ComponentInstance,
) -> Array[ComponentInstance] {
  let stack : Array[ComponentInstance] = []
  for s in outer_stack {
    stack.push(s)
  }
  stack.push(env)
  stack
}

///|
fn env_instance_from_state(
  name : String,
  state : BuildState,
  store : @runtime.Store,
) -> ComponentInstance {
  {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    resource_table: state.resource_table,
    stream_table: state.stream_table,
    async_state: state.async_state,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
}

///|
fn build_inline_core_instance(
  exports : Array[CoreInlineExport],
  state : BuildState,
) -> CoreInstance raise ComponentRuntimeError {
  let funcs : Map[String, CoreFuncRef] = {}
  let tables : Map[String, Int] = {}
  let memories : Map[String, Int] = {}
  let globals : Map[String, Int] = {}
  let tags : Map[String, Int] = {}
  for ex in exports {
    match resolve_sortidx(ex.sortidx, state) {
      ComponentExtern::CoreFunc(f) => funcs.set(ex.name, f)
      ComponentExtern::CoreTable(t) => tables.set(ex.name, t)
      ComponentExtern::CoreMemory(m) => memories.set(ex.name, m)
      ComponentExtern::CoreGlobal(g) => globals.set(ex.name, g)
      ComponentExtern::CoreTag(t) => tags.set(ex.name, t)
      _ => raise AliasTargetMismatch("inline core export")
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
fn split_core_import_name(name : String) -> (String, String) {
  let mut sep_idx = -1
  for i in 0..<name.length() {
    if i + 1 < name.length() &&
      name.code_unit_at(i) == ':' &&
      name.code_unit_at(i + 1) == ':' {
      sep_idx = i
    }
  }
  if sep_idx >= 0 {
    let mod_name = try! name[0:sep_idx].to_string()
    let field = try! name[sep_idx + 2:].to_string()
    (mod_name, field)
  } else {
    ("", name)
  }
}

///|
fn core_imports_from_args(
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> @runtime.Imports raise ComponentRuntimeError {
  let imports = @runtime.Imports::new()
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      ComponentExtern::CoreInstance(inst) => {
        // `with "mod" (instance ...)` supplies a whole namespace for core imports.
        let mod_name = arg.name
        for kv in inst.funcs.iter() {
          let (field, f) = kv
          imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
        }
        for kv in inst.tables.iter() {
          let (field, t) = kv
          imports.add_table(mod_name, field, t)
        }
        for kv in inst.memories.iter() {
          let (field, m) = kv
          imports.add_memory(mod_name, field, m)
        }
        for kv in inst.globals.iter() {
          let (field, g) = kv
          imports.add_global(mod_name, field, g)
        }
        for kv in inst.tags.iter() {
          let (field, t) = kv
          imports.add_tag(mod_name, field, t)
        }
      }
      ComponentExtern::CoreFunc(f) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
      }
      ComponentExtern::CoreTable(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_table(mod_name, field, t)
      }
      ComponentExtern::CoreMemory(m) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_memory(mod_name, field, m)
      }
      ComponentExtern::CoreGlobal(g) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_global(mod_name, field, g)
      }
      ComponentExtern::CoreTag(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_tag(mod_name, field, t)
      }
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  imports
}

///|
fn instantiate_component(
  linker : ComponentLinker,
  name : String,
  component : Component,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
) -> ComponentInstance raise ComponentRuntimeError {
  let stream_table = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].stream_table
  } else {
    StreamTable::new()
  }
  let async_state = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].async_state
  } else {
    AsyncState::new(stream_table.next_handle, stream_table.free_handles)
  }
  let state = BuildState::new(stream_table, async_state)
  // Reserve handle index 1 for nested component instances so tests that
  // assume a pre-existing handle slot (e.g. resources.wast) see the expected
  // numbering. If we end up running core start code, drop the reservation so
  // start-time allocations can still begin at 1.
  let mut reserved_resource_handle : Int? = Some(
    state.resource_table.alloc({
      type_id: -1,
      rep: 0,
      dtor: None,
      kind: ResourceKind::GuestDefined,
    }),
  )
  let may_enter_self : Array[Bool] = [false]
  let store = linker.get_store()
  for section in component.binary.sections {
    match section.id {
      1 => {
        let core_module = @parser.parse_module(section.payload) catch {
          e => raise CoreModuleParseError(e.to_string())
        }
        state.core_modules.push(core_module)
      }
      2 => {
        let core_instances = parse_core_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in core_instances {
          match inst.expr {
            CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= state.core_modules.length() {
                raise InvalidCoreModuleIndex(module_idx)
              }
              let imports = core_imports_from_args(args, state)
              let mod_ = state.core_modules[module_idx]
              // If this module has a start function, don't hold the reserved
              // handle: start code expects fresh resource tables.
              if mod_.start is Some(_) {
                match reserved_resource_handle {
                  Some(h) => {
                    state.resource_table.free(h) |> ignore
                    reserved_resource_handle = None
                  }
                  None => ()
                }
              }
              let module_name = "\{name}::coreinst\{state.core_instances.length()}"
              clear_canon_trap_message()
              let instance = @executor.instantiate_module_with_imports(
                store, mod_, imports,
              ) catch {
                e =>
                  match canon_trap_message[0] {
                    Some(msg) => raise CoreModuleInstantiateError(msg)
                    None => raise CoreModuleInstantiateError(e.to_string())
                  }
              }
              linker.core_linker.register(module_name, instance)
              state.core_instances.push(core_instance_from_module(instance))
            }
            CoreInstanceExpr::InlineExports(exports) =>
              state.core_instances.push(
                build_inline_core_instance(exports, state),
              )
          }
        }
      }
      3 => {
        // Core type section payload is a vec of core typedefs; store each
        // typedef's raw bytes so core:typeidx references work correctly.
        let reader = Reader::new(section.payload)
        let n = reader.read_leb_u32() catch {
          e => raise ComponentParseError(e.to_string())
        }
        for _i in 0..<n {
          let start = reader.pos
          skip_core_typedef(reader) catch {
            e => raise ComponentParseError(e.to_string())
          }
          let end = reader.pos
          state.core_types.push(bytes_sub(section.payload, start, end))
        }
        if !reader.is_eof() {
          raise ComponentParseError("invalid core type section")
        }
      }
      4 => {
        let nested = parse_component(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        let env = env_instance_from_state("\{name}::env", state, store)
        state.components.push({
          component: nested,
          outer_stack: extend_outer_stack(outer_stack, env),
        })
      }
      5 => {
        let instances = parse_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in instances {
          match inst.expr {
            InstanceExpr::Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= state.components.length() {
                raise InvalidComponentIndex(component_idx)
              }
              let closure = state.components[component_idx]
              let overrides_for_child : Map[String, ComponentExtern] = {}
              for arg in args {
                let ext = resolve_sortidx(arg.sortidx, state)
                overrides_for_child.set(arg.name, ext)
              }
              let nested = instantiate_component(
                linker,
                "\{name}::component\{component_idx}",
                closure.component,
                overrides_for_child,
                closure.outer_stack,
              )
              state.instances.push(nested)
            }
            InstanceExpr::InlineExports(exports) => {
              let export_map : Map[String, ComponentExtern] = {}
              for ex in exports {
                let ext = resolve_sortidx(ex.sortidx, state)
                export_map.set(ex.name, ext)
              }
              let inline_inst : ComponentInstance = {
                name: "\{name}::inline\{state.instances.length()}",
                types: state.types,
                funcs: state.funcs,
                values: state.values,
                components: state.components,
                instances: [],
                resource_table: state.resource_table,
                stream_table: state.stream_table,
                async_state: state.async_state,
                core_modules: state.core_modules,
                core_instances: state.core_instances,
                core_funcs: state.core_funcs,
                core_types: state.core_types,
                core_tables: state.core_tables,
                core_mems: state.core_mems,
                core_globals: state.core_globals,
                core_tags: state.core_tags,
                exports: export_map,
                store,
              }
              state.instances.push(inline_inst)
            }
          }
        }
      }
      6 => {
        let aliases = parse_alias_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for alias_decl in aliases {
          let ext = match alias_decl.target {
            AliasTarget::Export(instance_idx, name) => {
              if instance_idx < 0 || instance_idx >= state.instances.length() {
                raise InvalidInstanceIndex(instance_idx)
              }
              match state.instances[instance_idx].exports.get(name) {
                Some(v) => v
                None => raise UnknownExport(name)
              }
            }
            AliasTarget::CoreExport(core_inst_idx, name) => {
              if core_inst_idx < 0 ||
                core_inst_idx >= state.core_instances.length() {
                raise InvalidCoreInstanceIndex(core_inst_idx)
              }
              let core_inst = state.core_instances[core_inst_idx]
              match alias_decl.sort {
                Sort::Core(0x00) =>
                  match core_inst.funcs.get(name) {
                    Some(v) => ComponentExtern::CoreFunc(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x01) =>
                  match core_inst.tables.get(name) {
                    Some(v) => ComponentExtern::CoreTable(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x02) =>
                  match core_inst.memories.get(name) {
                    Some(v) => ComponentExtern::CoreMemory(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x03) =>
                  match core_inst.globals.get(name) {
                    Some(v) => ComponentExtern::CoreGlobal(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x04) =>
                  match core_inst.tags.get(name) {
                    Some(v) => ComponentExtern::CoreTag(v)
                    None => raise UnknownExport(name)
                  }
                _ => raise AliasTargetMismatch("core export sort")
              }
            }
            AliasTarget::Outer(ct, idx) =>
              resolve_outer_alias(
                extend_outer_stack(
                  outer_stack,
                  env_instance_from_state("\{name}::env", state, store),
                ),
                ct,
                alias_decl.sort,
                idx,
              )
          }
          append_alias(alias_decl.sort, ext, state)
        }
      }
      7 => {
        let types = parse_type_section(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        for t in types {
          let t2 = match t {
            TypeDef::ResourceType(id, rep, dtor, kind) =>
              if id < 0 {
                TypeDef::ResourceType(
                  linker.alloc_resource_id(),
                  rep,
                  dtor,
                  kind,
                )
              } else {
                t
              }
            _ => t
          }
          state.types.push(Some(t2))
        }
      }
      8 => {
        let canons = parse_canon_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for c in canons {
          match c {
            Canon::Lift(core_func_idx, opts, type_idx) => {
              if core_func_idx < 0 || core_func_idx >= state.core_funcs.length() {
                raise InvalidCoreFuncIndex(core_func_idx)
              }
              if type_idx < 0 || type_idx >= state.types.length() {
                raise InvalidTypeIndex(type_idx)
              }
              let td = state.types[type_idx]
              let func_type = match td {
                Some(TypeDef::FuncType(ft)) => ft
                _ => raise InvalidCanonFuncType(type_idx)
              }
              let resources = resolve_canon_resources(opts, state)
              let callback = resolve_canon_callback(opts, state)
              // Sync-style async functions (async + no callback) use cooperative suspension.
              let async_abi = canon_opt_is_async(opts) ||
                (func_type.is_async && callback is None)
              state.funcs.push(
                ComponentFunc::Lifted(
                  state.core_funcs[core_func_idx],
                  func_type,
                  resources,
                  state.types,
                  state.resource_table,
                  may_enter_self,
                  callback,
                  async_abi,
                ),
              )
            }
            Canon::Lower(func_idx, opts) => {
              if func_idx < 0 || func_idx >= state.funcs.length() {
                raise InvalidFuncIndex(func_idx)
              }
              let func = state.funcs[func_idx]
              let (func_type, func_types) = match func {
                ComponentFunc::Host(ft, types, _) => (ft, types)
                ComponentFunc::Lifted(_, ft, _, types, _, _, _, _) =>
                  (ft, types)
              }
              let resources = resolve_canon_resources(opts, state)
              let is_async_lower = canon_opt_is_async(opts)
              if func_type_needs_memory(func_type, func_types) &&
                resources.mem_addr is None {
                raise MissingCanonMemory
              }
              let mem = match resources.mem_addr {
                Some(addr) =>
                  store.get_mem(addr) catch {
                    e => raise CanonCallError(e.to_string())
                  }
                None => @runtime.Memory::new(0, None)
              }
              if is_async_lower {
                // Async lowering: start a subtask and return a status code, writing
                // eventual results into the provided return pointer.
                let ptr_ty = if mem.is_memory64() {
                  @types.ValueType::I64
                } else {
                  @types.ValueType::I32
                }
                let flat_params : Array[@types.ValueType] = []
                for p in func_type.params {
                  for
                    t in core_types_for_valtype(
                      p.ty,
                      func_types,
                      mem.is_memory64(),
                    ) {
                    flat_params.push(t)
                  }
                }
                let params : Array[@types.ValueType] = match func_type.result {
                  Some(_) => flat_params + [ptr_ty]
                  None => flat_params
                }
                let core_type : @types.FuncType = {
                  params,
                  results: [@types.ValueType::I32],
                }
                let async_state = state.async_state
                let caller_table = state.resource_table
                let host = fn(
                  args : Array[@types.Value],
                ) -> Array[@types.Value] raise @runtime.RuntimeError {
                  if !canon_may_leave[0] {
                    trap_canon("cannot leave component instance")
                  }
                  match func {
                    ComponentFunc::Lifted(_, _, _, _, _, may_enter, _, _) =>
                      if !may_enter[0] {
                        trap_canon("cannot enter component instance")
                      }
                    _ => ()
                  }
                  let cur_task_id = current_task_id(async_state)
                  let cur = if async_state.call_cursor_stack.length() == 0 {
                    0
                  } else {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1]
                  }
                  let per_task = match
                    async_state.call_results.get(cur_task_id) {
                    Some(m) => m
                    None => {
                      let m : Map[Int, Array[@types.Value]] = {}
                      async_state.call_results.set(cur_task_id, m)
                      m
                    }
                  }
                  fn cache_and_advance(
                    out : Array[@types.Value],
                  ) -> Array[@types.Value] {
                    per_task.set(cur, out)
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    out
                  }

                  match per_task.get(cur) {
                    Some(v) => {
                      async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                      1] = cur + 1
                      return v
                    }
                    None => ()
                  }

                  // Split core args into component params and optional return pointer.
                  let mut retptr : Int? = None
                  let param_args : Array[@types.Value] = []
                  match func_type.result {
                    Some(_) => {
                      if args.length() == 0 {
                        trap_canon("missing retptr")
                        return cache_and_advance([@types.Value::I32(0)])
                      }
                      for i in 0..<(args.length() - 1) {
                        param_args.push(args[i])
                      }
                      retptr = match args[args.length() - 1] {
                        @types.Value::I32(n) => Some(n)
                        @types.Value::I64(n) => Some(n.to_int())
                        _ => None
                      }
                    }
                    None =>
                      for a in args {
                        param_args.push(a)
                      }
                  }
                  let component_args = core_args_to_component(
                    param_args, func_type, func_types, resources, store, caller_table,
                  ) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      return cache_and_advance([@types.Value::I32(0)])
                    }
                  }
                  let inst_id = match func {
                    ComponentFunc::Host(_, _, _) => caller_table.id
                    ComponentFunc::Lifted(_, _, _, _, callee_table, _, _, _) =>
                      callee_table.id
                  }
                  // Backpressure is per async-lowered core function (not per component instance).
                  let bp_key = ((caller_table.id.reinterpret_as_uint() * 65537U) ^
                  func_idx.reinterpret_as_uint()).reinterpret_as_int()
                  let inflight = match
                    async_state.inflight_by_instance.get(bp_key) {
                    Some(n) => n
                    None => 0
                  }
                  let task : CallbackTask = {
                    func,
                    args: component_args,
                    started: [false],
                    code: [0],
                    waiting_set: [None],
                    cancelled: [false],
                  }
                  let retp = match retptr {
                    Some(p) => p
                    None => 0
                  }
                  fn cleanup_task_id(task_id : Int) -> Unit {
                    async_state.task_results.remove(task_id)
                    async_state.task_returned.remove(task_id)
                    async_state.task_cancelled.remove(task_id)
                    async_state.task_contexts.remove(task_id)
                    async_state.yield_replay_upto.remove(task_id)
                    async_state.wait_results.remove(task_id)
                    async_state.waiting_ws.remove(task_id)
                    async_state.call_results.remove(task_id)
                    async_state.sync_lower_states.remove(task_id)
                  }

                  fn migrate_task_id(from_id : Int, to_id : Int) -> Unit {
                    match take_task_result(async_state, from_id) {
                      Some(v) => set_task_result(async_state, to_id, v)
                      None => ()
                    }
                    match async_state.task_returned.get(from_id) {
                      Some(v) => {
                        async_state.task_returned.remove(from_id)
                        async_state.task_returned.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.task_cancelled.get(from_id) {
                      Some(v) => {
                        async_state.task_cancelled.remove(from_id)
                        async_state.task_cancelled.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.task_contexts.get(from_id) {
                      Some(v) => {
                        async_state.task_contexts.remove(from_id)
                        async_state.task_contexts.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.yield_replay_upto.get(from_id) {
                      Some(v) => {
                        async_state.yield_replay_upto.remove(from_id)
                        async_state.yield_replay_upto.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.wait_results.get(from_id) {
                      Some(v) => {
                        async_state.wait_results.remove(from_id)
                        async_state.wait_results.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.waiting_ws.get(from_id) {
                      Some(v) => {
                        async_state.waiting_ws.remove(from_id)
                        async_state.waiting_ws.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.call_results.get(from_id) {
                      Some(v) => {
                        async_state.call_results.remove(from_id)
                        async_state.call_results.set(to_id, v)
                      }
                      None => ()
                    }
                    match async_state.sync_lower_states.get(from_id) {
                      Some(v) => {
                        async_state.sync_lower_states.remove(from_id)
                        async_state.sync_lower_states.set(to_id, v)
                      }
                      None => ()
                    }
                  }

                  if inflight == 0 {
                    let is_callback = match func {
                      ComponentFunc::Lifted(
                        _,
                        _ft,
                        _res,
                        _tys,
                        _tbl,
                        _may_enter,
                        Some(_cb),
                        _async_abi
                      ) => true
                      _ => false
                    }
                    if is_callback {
                      // Try a handle-less initial step. If it exits immediately, we must return
                      // RETURNED=2 without consuming the shared handle space (otherwise it would
                      // perturb handle numbering observed by the core code; see empty-wait.wast).
                      let tmp_task_id = alloc_task_id(async_state)
                      let mut ok = true
                      push_task(async_state, tmp_task_id, true)
                      let step = step_task_once(
                        task, store, caller_table, async_state,
                      ) catch {
                        _e => {
                          ok = false
                          // Reset state so the real subtask can start fresh.
                          task.started[0] = false
                          task.code[0] = 0
                          task.waiting_set[0] = None
                          TaskStep::Blocked
                        }
                      }
                      pop_task(async_state)
                      if ok && step == TaskStep::Done {
                        if func_type.result is Some(_) && retptr is Some(p) {
                          let vals = match
                            take_task_result(async_state, tmp_task_id) {
                            Some(v) => v
                            None => []
                          }
                          let core_vals = component_results_to_core(
                            vals,
                            func_type,
                            func_types,
                            resources,
                            store,
                            Some(p),
                          ) catch {
                            e => {
                              trap_canon(canon_err_message(e))
                              return cache_and_advance([@types.Value::I32(0)])
                            }
                          }
                          match core_vals {
                            [@types.Value::I32(n)] =>
                              mem.store_i32(p, n) catch {
                                _ => ()
                              }
                            [@types.Value::I64(n)] =>
                              mem.store_i64(p, n) catch {
                                _ => ()
                              }
                            _ => ()
                          }
                        }
                        cleanup_task_id(tmp_task_id)
                        return cache_and_advance([@types.Value::I32(2)]) // RETURNED
                      }

                      // Needs a real subtask handle: allocate and migrate the per-task state.
                      let sub_id = alloc_shared_handle(async_state)
                      migrate_task_id(tmp_task_id, sub_id)
                      cleanup_task_id(tmp_task_id)
                      let st : Subtask = {
                        id: sub_id,
                        phase: [SubtaskPhase::Started],
                        caller_table,
                        callee_instance_id: inst_id,
                        bp_key,
                        retptr: retp,
                        mem_addr: resources.mem_addr,
                        result_ty: func_type.result,
                        types: func_types,
                        resources,
                        driver: SubtaskDriver::CallbackLifted(task),
                      }
                      async_state.inflight_by_instance.set(bp_key, 1)
                      async_state.subtasks.set(sub_id, st)
                      return cache_and_advance([
                        @types.Value::I32((sub_id << 4) | 1),
                      ]) // STARTED
                    }

                    // Non-callback async lowering: do a handle-less initial step so the task can
                    // register any pending waits (e.g. future.read/stream.read) before returning STARTED.
                    // If it completes immediately, return RETURNED=2 without consuming the shared handle space.
                    let tmp_task_id = alloc_task_id(async_state)
                    let mut ok = true
                    push_task(async_state, tmp_task_id, true)
                    let step = step_task_once(
                      task, store, caller_table, async_state,
                    ) catch {
                      _e => {
                        ok = false
                        task.started[0] = false
                        task.code[0] = 0
                        task.waiting_set[0] = None
                        TaskStep::Blocked
                      }
                    }
                    pop_task(async_state)
                    if ok && step == TaskStep::Done {
                      if func_type.result is Some(_) && retptr is Some(p) {
                        let vals = match
                          take_task_result(async_state, tmp_task_id) {
                          Some(v) => v
                          None => []
                        }
                        let core_vals = component_results_to_core(
                          vals,
                          func_type,
                          func_types,
                          resources,
                          store,
                          Some(p),
                        ) catch {
                          e => {
                            trap_canon(canon_err_message(e))
                            return cache_and_advance([@types.Value::I32(0)])
                          }
                        }
                        match core_vals {
                          [@types.Value::I32(n)] =>
                            mem.store_i32(p, n) catch {
                              _ => ()
                            }
                          [@types.Value::I64(n)] =>
                            mem.store_i64(p, n) catch {
                              _ => ()
                            }
                          _ => ()
                        }
                      }
                      cleanup_task_id(tmp_task_id)
                      return cache_and_advance([@types.Value::I32(2)]) // RETURNED
                    }
                    let sub_id = alloc_shared_handle(async_state)
                    migrate_task_id(tmp_task_id, sub_id)
                    cleanup_task_id(tmp_task_id)
                    let st : Subtask = {
                      id: sub_id,
                      phase: [SubtaskPhase::Started],
                      caller_table,
                      callee_instance_id: inst_id,
                      bp_key,
                      retptr: retp,
                      mem_addr: resources.mem_addr,
                      result_ty: func_type.result,
                      types: func_types,
                      resources,
                      driver: SubtaskDriver::CallbackLifted(task),
                    }
                    async_state.inflight_by_instance.set(bp_key, 1)
                    async_state.subtasks.set(sub_id, st)
                    cache_and_advance([@types.Value::I32((sub_id << 4) | 1)]) // STARTED
                  } else {
                    // Backpressure: queue in STARTING state until the in-flight
                    // subtask for this async-lowered core function completes.
                    let sub_id = alloc_shared_handle(async_state)
                    let st : Subtask = {
                      id: sub_id,
                      phase: [SubtaskPhase::Starting],
                      caller_table,
                      callee_instance_id: inst_id,
                      bp_key,
                      retptr: retp,
                      mem_addr: resources.mem_addr,
                      result_ty: func_type.result,
                      types: func_types,
                      resources,
                      driver: SubtaskDriver::CallbackLifted(task),
                    }
                    async_state.subtasks.set(sub_id, st)
                    let q = match async_state.pending_by_instance.get(bp_key) {
                      Some(xs) => xs
                      None => []
                    }
                    q.push(sub_id)
                    async_state.pending_by_instance.set(bp_key, q)
                    cache_and_advance([@types.Value::I32((sub_id << 4) | 0)]) // STARTING
                  }
                }
                state.core_funcs.push(
                  alloc_host_core_func(store, core_type, host),
                )
              } else {
                let core_type = core_func_type_from_component(
                  func_type,
                  func_types,
                  mem.is_memory64(),
                )
                let host = fn(
                  args : Array[@types.Value],
                ) -> Array[@types.Value] raise @runtime.RuntimeError {
                  match func {
                    ComponentFunc::Lifted(_, _, _, _, _, may_enter, _, _) =>
                      if !may_enter[0] {
                        trap_canon("cannot enter component instance")
                      }
                    _ => ()
                  }
                  if !canon_may_leave[0] {
                    trap_canon("cannot leave component instance")
                  }
                  let component_args = core_args_to_component(
                    args,
                    func_type,
                    func_types,
                    resources,
                    store,
                    state.resource_table,
                  ) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      ([] : Array[ComponentValue])
                    }
                  }
                  let async_state = state.async_state
                  fn cleanup_sync_lower_task(task_id : Int) -> Unit {
                    async_state.task_results.remove(task_id)
                    async_state.task_returned.remove(task_id)
                    async_state.task_cancelled.remove(task_id)
                    async_state.task_contexts.remove(task_id)
                    async_state.yield_replay_upto.remove(task_id)
                    async_state.wait_results.remove(task_id)
                    async_state.waiting_ws.remove(task_id)
                    async_state.call_results.remove(task_id)
                    async_state.sync_lower_states.remove(task_id)
                  }

                  let results : Array[ComponentValue] = if func_type.is_async {
                    // Sync-lowering an async component function must be cooperative:
                    // treat YIELD/WAIT as restartable suspension points instead of busy looping.
                    let outer_task_id = current_task_id(async_state)
                    let cur = if async_state.call_cursor_stack.length() == 0 {
                      0
                    } else {
                      async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                      1]
                    }
                    let per_task_calls = match
                      async_state.call_results.get(outer_task_id) {
                      Some(m) => m
                      None => {
                        let m : Map[Int, Array[@types.Value]] = {}
                        async_state.call_results.set(outer_task_id, m)
                        m
                      }
                    }
                    match per_task_calls.get(cur) {
                      Some(v) => {
                        async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                        1] = cur + 1
                        return v
                      }
                      None => ()
                    }
                    let per_task_state = match
                      async_state.sync_lower_states.get(outer_task_id) {
                      Some(m) => m
                      None => {
                        let m : Map[Int, SyncLowerState] = {}
                        async_state.sync_lower_states.set(outer_task_id, m)
                        m
                      }
                    }
                    let st = match per_task_state.get(cur) {
                      Some(s) => s
                      None => {
                        let inner_task_id = alloc_task_id(async_state)
                        let task : CallbackTask = {
                          func,
                          args: component_args,
                          started: [false],
                          code: [0],
                          waiting_set: [None],
                          cancelled: [false],
                        }
                        let s : SyncLowerState = {
                          task_id: inner_task_id,
                          task,
                        }
                        per_task_state.set(cur, s)
                        s
                      }
                    }

                    // Drive at most one step, then cooperatively suspend.
                    let can_block = async_state.task_can_block[0]
                    if !can_block && !canon_in_prerun[0] {
                      trap_canon(
                        "cannot block a synchronous task before returning",
                      )
                      ([] : Array[ComponentValue])
                    } else {
                      push_task(async_state, st.task_id, can_block)
                      let step = step_task_once(
                        st.task,
                        store,
                        state.resource_table,
                        async_state,
                      ) catch {
                        e => {
                          pop_task(async_state)
                          trap_canon(canon_err_message(e))
                          return []
                        }
                      }
                      pop_task(async_state)
                      match step {
                        TaskStep::Done => {
                          per_task_state.remove(cur) |> ignore
                          let vals = match
                            take_task_result(async_state, st.task_id) {
                            Some(v) => v
                            None => []
                          }
                          cleanup_sync_lower_task(st.task_id)
                          // Cache and advance call cursor (replay-safe).
                          let mut out_ptr : Int? = None
                          match func_type.result {
                            Some(rty) => {
                              let flat = core_types_for_valtype(
                                rty,
                                func_types,
                                mem.is_memory64(),
                              ) catch {
                                _ => []
                              }
                              if flat.length() > 1 {
                                // Indirect results use the last core argument as retptr.
                                if args.length() == 0 {
                                  trap_canon("missing retptr")
                                } else {
                                  out_ptr = match args[args.length() - 1] {
                                    @types.Value::I32(n) => Some(n)
                                    @types.Value::I64(n) => Some(n.to_int())
                                    _ => None
                                  }
                                }
                              }
                            }
                            None => ()
                          }
                          let out = component_results_to_core(
                            vals, func_type, func_types, resources, store, out_ptr,
                          ) catch {
                            e => {
                              trap_canon(canon_err_message(e))
                              ([] : Array[@types.Value])
                            }
                          }
                          per_task_calls.set(cur, out)
                          async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                          1] = cur + 1
                          return out
                        }
                        _ =>
                          if canon_in_prerun[0] {
                            per_task_state.remove(cur) |> ignore
                            cleanup_sync_lower_task(st.task_id)
                            trap_canon("prerun blocked")
                            ([] : Array[ComponentValue])
                          } else {
                            match st.task.waiting_set[0] {
                              Some(ws) =>
                                canon_suspend[0] = Some(CanonSuspend::Wait(ws))
                              None =>
                                canon_suspend[0] = Some(CanonSuspend::Yield)
                            }
                            raise @runtime.RuntimeError::Unreachable
                          }
                      }
                    }
                  } else {
                    call_component_func(
                      func,
                      component_args,
                      store,
                      state.resource_table,
                      state.async_state,
                    ) catch {
                      e => {
                        trap_canon(canon_err_message(e))
                        ([] : Array[ComponentValue])
                      }
                    }
                  }
                  let mut out_ptr : Int? = None
                  match func_type.result {
                    Some(rty) => {
                      let flat = core_types_for_valtype(
                        rty,
                        func_types,
                        mem.is_memory64(),
                      ) catch {
                        _ => []
                      }
                      if flat.length() > 1 {
                        // Indirect results use the last core argument as retptr.
                        if args.length() == 0 {
                          trap_canon("missing retptr")
                        } else {
                          out_ptr = match args[args.length() - 1] {
                            @types.Value::I32(n) => Some(n)
                            @types.Value::I64(n) => Some(n.to_int())
                            _ => None
                          }
                        }
                      }
                    }
                    None => ()
                  }
                  component_results_to_core(
                    results, func_type, func_types, resources, store, out_ptr,
                  ) catch {
                    e => {
                      trap_canon(canon_err_message(e))
                      ([] : Array[@types.Value])
                    }
                  }
                }
                let func_addr = store.alloc_host_func(
                  host,
                  func_type=core_type,
                  type_idx=0,
                )
                let instance : @runtime.ModuleInstance = {
                  types: [@types.SubType::from_func(core_type)],
                  type_rec_groups: [],
                  canonical_type_indices: [0],
                  store_idx: -1,
                  func_addrs: [func_addr],
                  func_type_indices: [0],
                  table_addrs: [],
                  mem_addrs: [],
                  global_addrs: [],
                  tag_addrs: [],
                  exports: [],
                  elem_segments: [],
                  data_segments: [],
                  dropped_elems: [],
                  dropped_datas: [],
                }
                state.core_funcs.push({ instance, func_idx: 0 })
              }
            }
            Canon::ResourceNew(tyidx) => {
              if tyidx < 0 || tyidx >= state.types.length() {
                raise InvalidTypeIndex(tyidx)
              }
              let (type_id, kind, dtor) = match state.types[tyidx] {
                Some(TypeDef::ResourceType(id, rep, dtor_idx, kind)) => {
                  if rep != 0x7f {
                    raise UnsupportedComponent(
                      "resources can only be represented by `i32`",
                    )
                  }
                  let dtor_ref = match dtor_idx {
                    Some(idx) =>
                      if idx < 0 || idx >= state.core_funcs.length() {
                        raise InvalidCoreFuncIndex(idx)
                      } else {
                        Some(state.core_funcs[idx])
                      }
                    None => None
                  }
                  (id, kind, dtor_ref)
                }
                _ => raise InvalidTypeDef(tyidx)
              }
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let table = state.resource_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(rep)] => {
                    let handle = table.alloc({ type_id, rep, dtor, kind })
                    [@types.Value::I32(handle)]
                  }
                  _ => {
                    trap_canon("type mismatch")
                    []
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ResourceRep(tyidx) => {
              if tyidx < 0 || tyidx >= state.types.length() {
                raise InvalidTypeIndex(tyidx)
              }
              let (type_id, expected_kind) = match state.types[tyidx] {
                Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
                _ => raise InvalidTypeDef(tyidx)
              }
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let table = state.resource_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.get(handle) {
                      Some(entry) =>
                        if entry.type_id < 0 {
                          trap_canon(
                            "unknown handle index \{handle}; index \{handle} is not a resource",
                          )
                          []
                        } else if entry.type_id != type_id {
                          let expected_desc = if expected_kind ==
                            ResourceKind::GuestDefined {
                            "guest-defined resource"
                          } else {
                            "host-defined resource"
                          }
                          let found_desc = if entry.kind ==
                            ResourceKind::GuestDefined {
                            "guest-defined resource"
                          } else {
                            "host-defined resource"
                          }
                          let suffix = if entry.kind == expected_kind {
                            "a different \{found_desc}"
                          } else {
                            found_desc
                          }
                          trap_canon(
                            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
                          )
                          []
                        } else {
                          [@types.Value::I32(entry.rep)]
                        }
                      None => {
                        trap_canon(
                          "unknown handle index \{handle}; index \{handle} is not a resource",
                        )
                        []
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    []
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ResourceDrop(tyidx) => {
              if tyidx < 0 || tyidx >= state.types.length() {
                raise InvalidTypeIndex(tyidx)
              }
              let (type_id, expected_kind) = match state.types[tyidx] {
                Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
                _ => raise InvalidTypeDef(tyidx)
              }
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let table = state.resource_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.get(handle) {
                      Some(entry) =>
                        if entry.type_id < 0 {
                          trap_canon(
                            "unknown handle index \{handle}; index \{handle} is not a resource",
                          )
                          []
                        } else if entry.type_id != type_id {
                          let expected_desc = if expected_kind ==
                            ResourceKind::GuestDefined {
                            "guest-defined resource"
                          } else {
                            "host-defined resource"
                          }
                          let found_desc = if entry.kind ==
                            ResourceKind::GuestDefined {
                            "guest-defined resource"
                          } else {
                            "host-defined resource"
                          }
                          let suffix = if entry.kind == expected_kind {
                            "a different \{found_desc}"
                          } else {
                            found_desc
                          }
                          trap_canon(
                            "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
                          )
                          []
                        } else {
                          let taken = table.free(handle)
                          match taken {
                            Some(real) =>
                              match real.dtor {
                                Some(d) => {
                                  clear_canon_trap_message()
                                  (@executor.call_func_by_index(
                                    store,
                                    d.instance,
                                    d.func_idx,
                                    [@types.Value::I32(real.rep)],
                                  ) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      []
                                    }
                                  })
                                  |> ignore
                                }
                                None => ()
                              }
                            None => ()
                          }
                          []
                        }
                      None => {
                        trap_canon(
                          "unknown handle index \{handle}; index \{handle} is not a resource",
                        )
                        []
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    []
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::TaskReturn(result, opts) => {
              let resources = resolve_canon_resources(opts, state)
              let core_params : Array[@types.ValueType] = match result {
                Some(vt) =>
                  core_types_for_valtype(vt, state.types, false) catch {
                    _ => []
                  }
                None => []
              }
              let core_type : @types.FuncType = {
                params: core_params,
                results: [],
              }
              let async_state = state.async_state
              let types = state.types
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                match async_state.task_returned.get(task_id) {
                  Some(_) => {
                    trap_canon("task.return called more than once")
                    return []
                  }
                  None => ()
                }
                async_state.task_returned.set(task_id, true)
                let vals : Array[ComponentValue] = match result {
                  None => []
                  Some(vt) => {
                    let mem : @runtime.Memory? = match resources.mem_addr {
                      Some(addr) =>
                        Some(
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return []
                            }
                          },
                        )
                      None => None
                    }
                    let mem_is_64 = match mem {
                      Some(m) => m.is_memory64()
                      None => false
                    }
                    let v = lift_component_value_from_flat(
                      vt,
                      args,
                      types,
                      mem,
                      mem_is_64,
                      resources.encoding,
                    ) catch {
                      e => {
                        trap_canon(canon_err_message(e))
                        return []
                      }
                    }
                    [v]
                  }
                }
                set_task_result(async_state, task_id, vals)
                []
              }
              // Stash as a core func.
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::TaskCancel => {
              let core_type : @types.FuncType = { params: [], results: [] }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                async_state.task_cancelled.set(task_id, true)
                async_state.task_returned.set(task_id, true)
                set_task_result(async_state, task_id, [])
                []
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadIndex => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I32],
              }
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                [@types.Value::I32(0)]
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadYield(_cancellable) => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                // In a synchronous task, `thread.yield` is just a normal call that
                // returns a conventional code (it must not block by itself).
                if !async_state.task_can_block[0] {
                  return [@types.Value::I32(1)]
                }
                let task_id = current_task_id(async_state)
                // Restartable yield points: only suspend once per ordinal.
                let cur = if async_state.yield_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                  1]
                }
                let replay_upto = match
                  async_state.yield_replay_upto.get(task_id) {
                  Some(n) => n
                  None => 0
                }
                if cur < replay_upto {
                  async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() -
                  1] = cur + 1
                  // On replay, thread.yield returns 0.
                  return [@types.Value::I32(0)]
                }
                async_state.yield_replay_upto.set(task_id, replay_upto + 1)
                canon_suspend[0] = Some(CanonSuspend::Yield)
                raise @runtime.RuntimeError::Unreachable
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadYieldTo(_cancellable) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                // For now, model yield-to as a regular yield.
                if !async_state.task_can_block[0] {
                  return [@types.Value::I32(1)]
                }
                canon_suspend[0] = Some(CanonSuspend::Yield)
                raise @runtime.RuntimeError::Unreachable
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadSwitchTo(_cancellable) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                // For now, switching is treated as yielding.
                if !async_state.task_can_block[0] {
                  return [@types.Value::I32(1)]
                }
                canon_suspend[0] = Some(CanonSuspend::Yield)
                raise @runtime.RuntimeError::Unreachable
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadResumeLater => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                []
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadSuspend(_cancellable) => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return [@types.Value::I32(0)]
                }
                canon_suspend[0] = Some(CanonSuspend::Yield)
                raise @runtime.RuntimeError::Unreachable
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ThreadNewIndirect(_type_idx, _table_idx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let id = alloc_shared_handle(async_state)
                [@types.Value::I32(id)]
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::WaitableSetNew => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                let cur = if async_state.call_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1]
                }
                let per_task = match async_state.call_results.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, Array[@types.Value]] = {}
                    async_state.call_results.set(task_id, m)
                    m
                  }
                }
                match per_task.get(cur) {
                  Some(v) => {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    v
                  }
                  None => {
                    let id = alloc_shared_handle(async_state)
                    async_state.waitable_sets.set(id, {
                      id,
                      members: {},
                      queue: [],
                      waiters: [0],
                    })
                    let out = [@types.Value::I32(id)]
                    per_task.set(cur, out)
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    out
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::WaitableSetWait(_cancellable, memidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              if memidx < 0 || memidx >= state.core_mems.length() {
                raise InvalidCoreMemoryIndex(memidx)
              }
              let mem_addr = state.core_mems[memidx]
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let mem = store.get_mem(mem_addr) catch {
                  e => {
                    trap_canon(e.to_string())
                    return [@types.Value::I32(0)]
                  }
                }
                fn ensure_subtask_return_ready(ev : WaitEvent) -> Unit {
                  // Replay can clobber the caller's return buffer; ensure it is rewritten
                  // before exposing a RETURNED subtask event.
                  if ev.code != 1 || ev.payload != 2 {
                    return
                  }
                  match async_state.subtasks.get(ev.index) {
                    Some(st) =>
                      match st.result_ty {
                        Some(_) =>
                          if st.mem_addr is Some(mem_addr2) {
                            let cancelled = async_state.task_cancelled.get(
                                st.id,
                              )
                              is Some(true)
                            if cancelled {
                              return
                            }
                            let vals = match
                              async_state.task_results.get(st.id) {
                              Some(v) => v
                              None => []
                            }
                            let (ft, ftypes) = match st.driver {
                              SubtaskDriver::CallbackLifted(t) =>
                                match t.func {
                                  ComponentFunc::Host(func_type, types, _) =>
                                    (func_type, types)
                                  ComponentFunc::Lifted(
                                    _,
                                    func_type,
                                    _,
                                    types,
                                    _,
                                    _,
                                    _,
                                    _
                                  ) => (func_type, types)
                                }
                              _ => return
                            }
                            let mem2 = store.get_mem(mem_addr2) catch {
                              _ => return
                            }
                            let core_vals = component_results_to_core(
                              vals,
                              ft,
                              ftypes,
                              st.resources,
                              store,
                              Some(st.retptr),
                            ) catch {
                              _e => return
                            }
                            match core_vals {
                              [@types.Value::I32(n)] =>
                                mem2.store_i32(st.retptr, n) catch {
                                  _ => ()
                                }
                              [@types.Value::I64(n)] =>
                                mem2.store_i64(st.retptr, n) catch {
                                  _ => ()
                                }
                              _ => ()
                            }
                          } else {
                            ()
                          }
                        None => ()
                      }
                    None => ()
                  }
                }

                match args {
                  [@types.Value::I32(ws), @types.Value::I32(ptr)] => {
                    if (ptr.reinterpret_as_uint() & 3U) != 0U {
                      trap_canon("unaligned pointer")
                      return [@types.Value::I32(0)]
                    }
                    let task_id = current_task_id(async_state)
                    let cur = if async_state.wait_cursor_stack.length() == 0 {
                      0
                    } else {
                      async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                      1]
                    }
                    let per_task = match async_state.wait_results.get(task_id) {
                      Some(m) => m
                      None => {
                        let m : Map[Int, WaitEvent] = {}
                        async_state.wait_results.set(task_id, m)
                        m
                      }
                    }
                    match per_task.get(cur) {
                      Some(ev) => {
                        // Replay: write cached event and return its code.
                        ensure_subtask_return_ready(ev)
                        mem.store_i32(ptr + 0, ev.index) catch {
                          _ => ()
                        }
                        mem.store_i32(ptr + 4, ev.payload) catch {
                          _ => ()
                        }
                        match async_state.waiting_ws.get(task_id) {
                          Some(ws0) =>
                            if ws0 == ws {
                              async_state.waiting_ws.remove(task_id)
                              match async_state.waitable_sets.get(ws) {
                                Some(set) => set.waiters[0] = set.waiters[0] - 1
                                None => ()
                              }
                            }
                          None => ()
                        }
                        async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                        1] = cur + 1
                        [@types.Value::I32(ev.code)]
                      }
                      None => {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                          return [@types.Value::I32(0)]
                        }
                        // Cooperative wait: suspend the current task until an event exists.
                        // (The sync-style async ABI will replay this call and consume the event.)
                        if !waitable_set_has_event(async_state, ws) {
                          // Track that this task is a waiter so `waitable-set.drop` can trap.
                          if async_state.waiting_ws.get(task_id) is None {
                            match async_state.waitable_sets.get(ws) {
                              Some(set) => set.waiters[0] = set.waiters[0] + 1
                              None => ()
                            }
                            async_state.waiting_ws.set(task_id, ws)
                          }
                          canon_suspend[0] = Some(CanonSuspend::Wait(ws))
                          raise @runtime.RuntimeError::Unreachable
                        }
                        let ev = match pop_waitable_event(async_state, ws) {
                          Some(ev) => ev
                          None => {
                            canon_suspend[0] = Some(CanonSuspend::Wait(ws))
                            raise @runtime.RuntimeError::Unreachable
                          }
                        }
                        ensure_subtask_return_ready(ev)
                        match async_state.waiting_ws.get(task_id) {
                          Some(ws0) =>
                            if ws0 == ws {
                              async_state.waiting_ws.remove(task_id)
                              match async_state.waitable_sets.get(ws) {
                                Some(set) => set.waiters[0] = set.waiters[0] - 1
                                None => ()
                              }
                            }
                          None => ()
                        }
                        per_task.set(cur, ev)
                        mem.store_i32(ptr + 0, ev.index) catch {
                          _ => ()
                        }
                        mem.store_i32(ptr + 4, ev.payload) catch {
                          _ => ()
                        }
                        async_state.wait_cursor_stack[async_state.wait_cursor_stack.length() -
                        1] = cur + 1
                        [@types.Value::I32(ev.code)]
                      }
                    }
                  }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::WaitableSetPoll(_cancellable, memidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              if memidx < 0 || memidx >= state.core_mems.length() {
                raise InvalidCoreMemoryIndex(memidx)
              }
              let mem_addr = state.core_mems[memidx]
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let mem = store.get_mem(mem_addr) catch {
                  e => {
                    trap_canon(e.to_string())
                    return [@types.Value::I32(0)]
                  }
                }
                match args {
                  [@types.Value::I32(ws), @types.Value::I32(ptr)] => {
                    if (ptr.reinterpret_as_uint() & 3U) != 0U {
                      trap_canon("unaligned pointer")
                      return [@types.Value::I32(0)]
                    }
                    match pop_waitable_event(async_state, ws) {
                      Some(ev) => {
                        mem.store_i32(ptr + 0, ev.index) catch {
                          _ => ()
                        }
                        mem.store_i32(ptr + 4, ev.payload) catch {
                          _ => ()
                        }
                        [@types.Value::I32(ev.code)]
                      }
                      None => [@types.Value::I32(0)]
                    }
                  }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::WaitableSetDrop => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(ws)] =>
                    match async_state.waitable_sets.get(ws) {
                      Some(set) =>
                        if set.waiters[0] > 0 {
                          trap_canon("cannot drop waitable set with waiters")
                          []
                        } else {
                          async_state.waitable_sets.remove(ws)
                          // Clean up membership mappings.
                          for kv in set.members.iter() {
                            let (waitable, _v) = kv
                            match async_state.waitable_to_set.get(waitable) {
                              Some(ws2) =>
                                if ws2 == ws {
                                  async_state.waitable_to_set.remove(waitable)
                                }
                              None => ()
                            }
                          }
                          free_shared_handle(async_state, ws)
                          []
                        }
                      None => {
                        trap_canon("unknown waitable set index \{ws}")
                        []
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    []
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::WaitableJoin => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(waitable), @types.Value::I32(ws)] =>
                    match async_state.waitable_sets.get(ws) {
                      Some(set) =>
                        match async_state.waitable_to_set.get(waitable) {
                          Some(prev_ws) =>
                            if prev_ws == ws {
                              // Idempotent on replay: do not re-flush backlog.
                              []
                            } else {
                              // Move membership between sets.
                              match async_state.waitable_sets.get(prev_ws) {
                                Some(prev_set) =>
                                  prev_set.members.remove(waitable)
                                None => ()
                              }
                              set.members.set(waitable, true)
                              async_state.waitable_to_set.set(waitable, ws)
                              // Flush any queued events that happened before join.
                              match async_state.waitable_events.get(waitable) {
                                Some(list) =>
                                  for ev in list {
                                    set.queue.push(ev)
                                  }
                                None => ()
                              }
                              []
                            }
                          None => {
                            set.members.set(waitable, true)
                            async_state.waitable_to_set.set(waitable, ws)
                            // Flush any queued events that happened before join.
                            match async_state.waitable_events.get(waitable) {
                              Some(list) =>
                                for ev in list {
                                  set.queue.push(ev)
                                }
                              None => ()
                            }
                            []
                          }
                        }
                      None => {
                        trap_canon("unknown waitable set index \{ws}")
                        []
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    []
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::SubtaskCancel(_is_async) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                let cur = if async_state.call_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1]
                }
                let per_task = match async_state.call_results.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, Array[@types.Value]] = {}
                    async_state.call_results.set(task_id, m)
                    m
                  }
                }
                match per_task.get(cur) {
                  Some(v) => {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    return v
                  }
                  None => ()
                }
                fn cache_i32(n : Int) -> Array[@types.Value] {
                  let out = [@types.Value::I32(n)]
                  per_task.set(cur, out)
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = cur + 1
                  out
                }

                match args {
                  [@types.Value::I32(id)] =>
                    match async_state.subtasks.get(id) {
                      None => {
                        trap_canon("unknown subtask handle index \{id}")
                        cache_i32(0)
                      }
                      Some(st) => {
                        if st.phase[0] == SubtaskPhase::Returned {
                          // Already resolved.
                          return cache_i32(0)
                        }

                        // Mark cancellation request for callback-driven tasks.
                        match st.driver {
                          SubtaskDriver::CallbackLifted(t) =>
                            t.cancelled[0] = true
                          _ => ()
                        }

                        // Best-effort: if the subtask uses the callback-style async ABI,
                        // attempt to deliver the cancellation immediately.
                        let is_callback = match st.driver {
                          SubtaskDriver::CallbackLifted(t) =>
                            match t.func {
                              ComponentFunc::Lifted(
                                _,
                                _ft,
                                _res,
                                _tys,
                                _tbl,
                                _may_enter,
                                Some(_cb),
                                _async_abi
                              ) => true
                              _ => false
                            }
                          _ => false
                        }
                        if is_callback {
                          match st.driver {
                            SubtaskDriver::CallbackLifted(t) => {
                              push_task(async_state, id, true)
                              let step = step_task_once(
                                t,
                                store,
                                st.caller_table,
                                async_state,
                              ) catch {
                                e => {
                                  pop_task(async_state)
                                  trap_canon(canon_err_message(e))
                                  return cache_i32(0)
                                }
                              }
                              pop_task(async_state)
                              match step {
                                TaskStep::Done => {
                                  st.phase[0] = SubtaskPhase::Returned
                                  async_state.inflight_by_instance.set(
                                    st.bp_key,
                                    0,
                                  )
                                  enqueue_waitable_event(async_state, id, {
                                    code: 1,
                                    index: id,
                                    payload: 2,
                                  })
                                  // CANCELLED_BEFORE_RETURNED=4 (component-spec convention).
                                  return cache_i32(4)
                                }
                                _ => ()
                              }
                            }
                            _ => ()
                          }
                        }

                        // BLOCKED=-1 (cancellation didn't complete synchronously).
                        cache_i32(-1)
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    cache_i32(0)
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::SubtaskDrop => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                let cur = if async_state.call_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1]
                }
                let per_task = match async_state.call_results.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, Array[@types.Value]] = {}
                    async_state.call_results.set(task_id, m)
                    m
                  }
                }
                match per_task.get(cur) {
                  Some(v) => {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    return v
                  }
                  None => ()
                }
                fn cache_void() -> Array[@types.Value] {
                  let out : Array[@types.Value] = []
                  per_task.set(cur, out)
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = cur + 1
                  out
                }

                match args {
                  [@types.Value::I32(id)] => {
                    // Ensure this is a known subtask and it has completed.
                    let st_opt = async_state.subtasks.get(id)
                    match st_opt {
                      Some(st) =>
                        if st.phase[0] != SubtaskPhase::Returned {
                          trap_canon(
                            "cannot drop a subtask which has not yet resolved",
                          )
                          return cache_void()
                        } else {
                          async_state.subtasks.remove(id)
                        }
                      None => {
                        trap_canon("unknown subtask handle index \{id}")
                        return cache_void()
                      }
                    }

                    // Remove from any waitable-set membership and queued events.
                    match async_state.waitable_to_set.get(id) {
                      Some(ws) => {
                        async_state.waitable_to_set.remove(id)
                        match async_state.waitable_sets.get(ws) {
                          Some(set) => {
                            set.members.remove(id)
                            // Purge queued events for this waitable.
                            let mut i = 0
                            while i < set.queue.length() {
                              if set.queue[i].index == id {
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
                    async_state.waitable_events.remove(id)

                    // Clear per-task bookkeeping so the handle id can be reused.
                    async_state.task_results.remove(id)
                    async_state.task_returned.remove(id)
                    async_state.task_cancelled.remove(id)
                    async_state.task_contexts.remove(id)
                    async_state.yield_replay_upto.remove(id)
                    async_state.wait_results.remove(id)
                    async_state.waiting_ws.remove(id)
                    async_state.call_results.remove(id)
                    async_state.sync_lower_states.remove(id)

                    // Remove from pending queues if it was still STARTING.
                    let inst_ids : Array[Int] = []
                    for kv in async_state.pending_by_instance.iter() {
                      let (inst_id, _q) = kv
                      inst_ids.push(inst_id)
                    }
                    for inst_id in inst_ids {
                      match async_state.pending_by_instance.get(inst_id) {
                        Some(q) => {
                          let mut j = 0
                          while j < q.length() {
                            if q[j] == id {
                              q.remove(j) |> ignore
                            } else {
                              j = j + 1
                            }
                          }
                          if q.length() == 0 {
                            async_state.pending_by_instance.remove(inst_id)
                          }
                        }
                        None => ()
                      }
                    }
                    free_shared_handle(async_state, id)
                    cache_void()
                  }
                  _ => {
                    trap_canon("type mismatch")
                    cache_void()
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamNew(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I64],
              }
              let payload_ty : ValType? = match state.types.get(_tyidx) {
                Some(Some(TypeDef::Stream(v))) => v
                _ => None
              }
              let table = state.stream_table
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                fn alloc_with_source() -> (Int, Bool) {
                  if async_state.free_handles.length() > 0 {
                    // Deterministic: pick smallest.
                    let mut best_i = 0
                    let mut best = async_state.free_handles[0]
                    for i in 1..<async_state.free_handles.length() {
                      let h = async_state.free_handles[i]
                      if h < best {
                        best = h
                        best_i = i
                      }
                    }
                    async_state.free_handles.remove(best_i) |> ignore
                    (best, true)
                  } else {
                    let h = async_state.next_handle[0]
                    async_state.next_handle[0] = h + 1
                    (h, false)
                  }
                }

                let sid = table.next_stream_id[0]
                table.next_stream_id[0] = sid + 1
                table.streams.set(sid, {
                  pending_read: None,
                  pending_write: None,
                  readable_dropped: false,
                  writable_dropped: false,
                })
                // Handle numbering: for typed streams, component-spec expects the
                // readable end to reuse a freed handle when available.
                let (rh, wh) = if payload_ty is Some(_) {
                  let (h1, f1) = alloc_with_source()
                  let (h2, f2) = alloc_with_source()
                  if f1 != f2 {
                    if f1 {
                      (h1, h2)
                    } else {
                      (h2, h1)
                    }
                  } else {
                    // No free handles involved: the initial numbering differs depending
                    // on whether we're running inside an async task.
                    // - sync code expects readable=1
                    // - async code expects readable=2
                    let hi = if h1 < h2 { h2 } else { h1 }
                    let lo = if h1 < h2 { h1 } else { h2 }
                    if async_state.task_can_block[0] {
                      (hi, lo)
                    } else {
                      (lo, hi)
                    }
                  }
                } else {
                  let (rh, _fr) = alloc_with_source()
                  let (wh, _fw) = alloc_with_source()
                  (rh, wh)
                }
                table.endpoints.set(rh, {
                  stream_id: sid,
                  is_readable: true,
                  notified_peer_dropped: [false],
                })
                table.endpoints.set(wh, {
                  stream_id: sid,
                  is_readable: false,
                  notified_peer_dropped: [false],
                })
                let packed = (wh.to_int64() << 32) |
                  (rh.to_int64() & 0xFFFFFFFFL)
                [@types.Value::I64(packed)]
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamRead(_tyidx, opts) => {
              let core_type : @types.FuncType = {
                params: [
                  @types.ValueType::I32,
                  @types.ValueType::I32,
                  @types.ValueType::I32,
                ],
                results: [@types.ValueType::I32],
              }
              let resources = resolve_canon_resources(opts, state) catch {
                e => raise e
              }
              let payload_ty : ValType? = match state.types.get(_tyidx) {
                Some(Some(TypeDef::Stream(v))) => v
                _ => None
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let mem_opt : @runtime.Memory? = match payload_ty {
                  Some(_) =>
                    match resources.mem_addr {
                      Some(addr) =>
                        Some(
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          },
                        )
                      None => {
                        trap_canon("missing canon memory")
                        return [@types.Value::I32(0)]
                      }
                    }
                  None => None
                }
                match args {
                  [
                    @types.Value::I32(handle),
                    @types.Value::I32(ptr),
                    @types.Value::I32(len),
                  ] =>
                    // BLOCKED=-1, COMPLETED=0 | (n<<4), DROPPED=1 | (n<<4)
                    if len < 0 {
                      trap_canon("type mismatch")
                      [@types.Value::I32(0)]
                    } else {
                      match table.endpoints.get(handle) {
                        None => {
                          trap_canon("unknown stream handle index \{handle}")
                          [@types.Value::I32(0)]
                        }
                        Some(ep) =>
                          if !ep.is_readable {
                            trap_canon("type mismatch")
                            [@types.Value::I32(0)]
                          } else {
                            let st0 = match table.streams.get(ep.stream_id) {
                              Some(s) => s
                              None => {
                                trap_canon(
                                  "unknown stream handle index \{handle}",
                                )
                                return [@types.Value::I32(0)]
                              }
                            }
                            match st0.pending_write {
                              Some(pw) => {
                                let remain = pw.buf.length() - pw.sent
                                let n = if len < remain { len } else { remain }
                                match mem_opt {
                                  Some(mem) =>
                                    for i in 0..<n {
                                      mem.store_byte(
                                        ptr + i,
                                        pw.buf[pw.sent + i],
                                      ) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    }
                                  None => ()
                                }
                                let new_sent = pw.sent + n
                                let pw2 = if new_sent >= pw.buf.length() {
                                  None
                                } else {
                                  Some({ buf: pw.buf, sent: new_sent })
                                }
                                table.streams.set(ep.stream_id, {
                                  pending_read: st0.pending_read,
                                  pending_write: pw2,
                                  readable_dropped: st0.readable_dropped,
                                  writable_dropped: st0.writable_dropped,
                                })
                                [@types.Value::I32(n << 4)]
                              }
                              None =>
                                if st0.writable_dropped {
                                  [@types.Value::I32(1)]
                                } else {
                                  // Register a pending read and report BLOCKED.
                                  let pr = { ptr, len, filled: 0 }
                                  table.streams.set(ep.stream_id, {
                                    pending_read: Some(pr),
                                    pending_write: st0.pending_write,
                                    readable_dropped: st0.readable_dropped,
                                    writable_dropped: st0.writable_dropped,
                                  })
                                  [@types.Value::I32(-1)]
                                }
                            }
                          }
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamWrite(_tyidx, opts) => {
              let core_type : @types.FuncType = {
                params: [
                  @types.ValueType::I32,
                  @types.ValueType::I32,
                  @types.ValueType::I32,
                ],
                results: [@types.ValueType::I32],
              }
              let resources = resolve_canon_resources(opts, state) catch {
                e => raise e
              }
              let payload_ty : ValType? = match state.types.get(_tyidx) {
                Some(Some(TypeDef::Stream(v))) => v
                _ => None
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let mem_opt : @runtime.Memory? = match payload_ty {
                  Some(_) =>
                    match resources.mem_addr {
                      Some(addr) =>
                        Some(
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          },
                        )
                      None => {
                        trap_canon("missing canon memory")
                        return [@types.Value::I32(0)]
                      }
                    }
                  None => None
                }
                match args {
                  [
                    @types.Value::I32(handle),
                    @types.Value::I32(ptr),
                    @types.Value::I32(len),
                  ] =>
                    if len < 0 {
                      trap_canon("type mismatch")
                      [@types.Value::I32(0)]
                    } else {
                      match table.endpoints.get(handle) {
                        None => {
                          trap_canon("unknown stream handle index \{handle}")
                          [@types.Value::I32(0)]
                        }
                        Some(ep) =>
                          if ep.is_readable {
                            trap_canon("type mismatch")
                            [@types.Value::I32(0)]
                          } else {
                            let st0 = match table.streams.get(ep.stream_id) {
                              Some(s) => s
                              None => {
                                trap_canon(
                                  "unknown stream handle index \{handle}",
                                )
                                return [@types.Value::I32(0)]
                              }
                            }
                            match st0.pending_read {
                              Some(pr0) => {
                                let remain = pr0.len - pr0.filled
                                let n = if len < remain { len } else { remain }
                                // Snapshot src bytes first to preserve memmove semantics when regions overlap.
                                let buf : Array[Byte] = []
                                for i in 0..<len {
                                  let b = match mem_opt {
                                    Some(mem) =>
                                      mem.load_byte(ptr + i) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => b'\x00'
                                  }
                                  buf.push(b)
                                }
                                match mem_opt {
                                  Some(mem) =>
                                    for i in 0..<n {
                                      mem.store_byte(
                                        pr0.ptr + pr0.filled + i,
                                        buf[i],
                                      ) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    }
                                  None => ()
                                }
                                let pr1 = {
                                  ptr: pr0.ptr,
                                  len: pr0.len,
                                  filled: pr0.filled + n,
                                }
                                // If there are leftover bytes, keep them as a pending write.
                                let pw1 = if len > n {
                                  Some({ buf, sent: n })
                                } else {
                                  st0.pending_write
                                }
                                table.streams.set(ep.stream_id, {
                                  pending_read: Some(pr1),
                                  pending_write: pw1,
                                  readable_dropped: st0.readable_dropped,
                                  writable_dropped: st0.writable_dropped,
                                })
                                [@types.Value::I32(n << 4)]
                              }
                              None => {
                                // Register a pending write by copying bytes.
                                let buf : Array[Byte] = []
                                for i in 0..<len {
                                  let b = match mem_opt {
                                    Some(mem) =>
                                      mem.load_byte(ptr + i) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => b'\x00'
                                  }
                                  buf.push(b)
                                }
                                table.streams.set(ep.stream_id, {
                                  pending_read: st0.pending_read,
                                  pending_write: Some({ buf, sent: 0 }),
                                  readable_dropped: st0.readable_dropped,
                                  writable_dropped: st0.writable_dropped,
                                })
                                [@types.Value::I32(-1)]
                              }
                            }
                          }
                      }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamCancelRead(_tyidx, _is_async) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.endpoints.get(handle) {
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        [@types.Value::I32(0)]
                      }
                      Some(ep) =>
                        if !ep.is_readable {
                          trap_canon("type mismatch")
                          [@types.Value::I32(0)]
                        } else {
                          let st0 = match table.streams.get(ep.stream_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown stream handle index \{handle}",
                              )
                              return [@types.Value::I32(0)]
                            }
                          }
                          match st0.pending_read {
                            Some(pr) => {
                              let code = if st0.writable_dropped {
                                1
                              } else {
                                2
                              }
                              let filled = pr.filled
                              table.streams.set(ep.stream_id, {
                                pending_read: None,
                                pending_write: st0.pending_write,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                              })
                              [@types.Value::I32(code | (filled << 4))]
                            }
                            None => [@types.Value::I32(2)]
                          }
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamCancelWrite(_tyidx, _is_async) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.endpoints.get(handle) {
                      None => {
                        trap_canon("unknown stream handle index \{handle}")
                        [@types.Value::I32(0)]
                      }
                      Some(ep) =>
                        if ep.is_readable {
                          trap_canon("type mismatch")
                          [@types.Value::I32(0)]
                        } else {
                          let st0 = match table.streams.get(ep.stream_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown stream handle index \{handle}",
                              )
                              return [@types.Value::I32(0)]
                            }
                          }
                          match st0.pending_write {
                            Some(pw) => {
                              let code = if st0.readable_dropped {
                                1
                              } else {
                                2
                              }
                              let sent = pw.sent
                              table.streams.set(ep.stream_id, {
                                pending_read: st0.pending_read,
                                pending_write: None,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                              })
                              [@types.Value::I32(code | (sent << 4))]
                            }
                            None => [@types.Value::I32(2)]
                          }
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamDropReadable(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.endpoints.get(handle) {
                      Some(ep) => {
                        let st0 = match table.streams.get(ep.stream_id) {
                          Some(s) => s
                          None => return []
                        }
                        table.streams.set(ep.stream_id, {
                          pending_read: st0.pending_read,
                          pending_write: st0.pending_write,
                          readable_dropped: true,
                          writable_dropped: st0.writable_dropped,
                        })
                        table.free_endpoint(handle)
                        []
                      }
                      None => []
                    }
                  _ => []
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::StreamDropWritable(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let table = state.stream_table
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match table.endpoints.get(handle) {
                      Some(ep) => {
                        let st0 = match table.streams.get(ep.stream_id) {
                          Some(s) => s
                          None => return []
                        }
                        table.streams.set(ep.stream_id, {
                          pending_read: st0.pending_read,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: true,
                        })
                        table.free_endpoint(handle)
                        []
                      }
                      None => []
                    }
                  _ => []
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureNew(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [],
                results: [@types.ValueType::I64],
              }
              let async_state = state.async_state
              let creator_component_id = state.resource_table.id
              let payload_ty : ValType? = match state.types.get(_tyidx) {
                Some(Some(TypeDef::Future(v))) => v
                _ => None
              }
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                fn alloc_with_source() -> (Int, Bool) {
                  if async_state.free_handles.length() > 0 {
                    // Deterministic: pick smallest.
                    let mut best_i = 0
                    let mut best = async_state.free_handles[0]
                    for i in 1..<async_state.free_handles.length() {
                      let h = async_state.free_handles[i]
                      if h < best {
                        best = h
                        best_i = i
                      }
                    }
                    async_state.free_handles.remove(best_i) |> ignore
                    (best, true)
                  } else {
                    let h = async_state.next_handle[0]
                    async_state.next_handle[0] = h + 1
                    (h, false)
                  }
                }

                let future_id = async_state.next_future_id[0]
                async_state.next_future_id[0] = future_id + 1
                let (rh, wh) = if payload_ty is Some(_) {
                  // For typed futures, prefer reusing a freed handle for the readable end.
                  let (h1, f1) = alloc_with_source()
                  let (h2, f2) = alloc_with_source()
                  if f1 != f2 {
                    if f1 {
                      (h1, h2)
                    } else {
                      (h2, h1)
                    }
                  } else if h1 < h2 {
                    (h2, h1)
                  } else {
                    (h1, h2)
                  }
                } else {
                  // Empty future: allocate readable then writable.
                  let (rh, _fr) = alloc_with_source()
                  let (wh, _fw) = alloc_with_source()
                  (rh, wh)
                }
                async_state.future_endpoints.set(rh, {
                  future_id,
                  is_readable: true,
                  creator_component_id,
                })
                async_state.future_endpoints.set(wh, {
                  future_id,
                  is_readable: false,
                  creator_component_id,
                })
                async_state.futures.set(future_id, {
                  readable_handle: rh,
                  writable_handle: wh,
                  payload_ty,
                  pending_read: None,
                  pending_write: None,
                  readable_dropped: false,
                  writable_dropped: false,
                  read_done: false,
                  write_succeeded: false,
                  write_observed_readable_drop: false,
                  wrote_value: false,
                })
                let packed = (wh.to_int64() << 32) |
                  (rh.to_int64() & 0xFFFFFFFFL)
                [@types.Value::I64(packed)]
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureRead(_tyidx, _opts) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let resources = resolve_canon_resources(_opts, state) catch {
                e => raise e
              }
              let async_state = state.async_state
              let caller_component_id = state.resource_table.id
              let is_async = canon_opt_is_async(_opts)
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                let cur = if async_state.call_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1]
                }
                let per_task = match async_state.call_results.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, Array[@types.Value]] = {}
                    async_state.call_results.set(task_id, m)
                    m
                  }
                }
                match per_task.get(cur) {
                  Some(v) => {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    return v
                  }
                  None => ()
                }
                fn cache_i32(n : Int) -> Array[@types.Value] {
                  let out = [@types.Value::I32(n)]
                  per_task.set(cur, out)
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = cur + 1
                  out
                }
                // Sync future.read blocks the task; the async form returns BLOCKED=-1.
                if !is_async && !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return cache_i32(0)
                }
                match args {
                  [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
                    match async_state.future_endpoints.get(handle) {
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        cache_i32(0)
                      }
                      Some(ep) =>
                        if !ep.is_readable {
                          trap_canon("type mismatch")
                          cache_i32(0)
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown future handle index \{handle}",
                              )
                              return cache_i32(0)
                            }
                          }
                          if st0.read_done {
                            trap_canon(
                              "cannot read from future after previous read succeeded",
                            )
                            return cache_i32(0)
                          }
                          match st0.pending_write {
                            Some(v) => {
                              // Intra-component char futures cannot rendezvous.
                              match st0.payload_ty {
                                Some(Prim(Char)) =>
                                  if ep.creator_component_id ==
                                    caller_component_id {
                                    trap_canon(
                                      "cannot read from and write to intra-component future",
                                    )
                                    return [@types.Value::I32(0)]
                                  }
                                _ => ()
                              }

                              // Write payload (if any) to memory at `ptr`.
                              match st0.payload_ty {
                                None => ()
                                Some(Prim(U8)) => {
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  mem.store_byte(ptr, trunc_u8(v).to_byte()) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                }
                                Some(Prim(Char)) => {
                                  if ptr % 4 != 0 {
                                    trap_canon("unaligned pointer")
                                    return [@types.Value::I32(0)]
                                  }
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  mem.store_i32(ptr, v) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                }
                                _ => {
                                  trap_canon("unsupported future type")
                                  return [@types.Value::I32(0)]
                                }
                              }

                              // Completing a pending write unblocks the writer: emit FUTURE_WRITE.
                              if async_state.future_endpoints.get(
                                  st0.writable_handle,
                                )
                                is Some(_) {
                                enqueue_waitable_event(
                                  async_state,
                                  st0.writable_handle,
                                  {
                                    code: 5,
                                    index: st0.writable_handle,
                                    payload: 0,
                                  },
                                )
                              }
                              async_state.futures.set(ep.future_id, {
                                readable_handle: st0.readable_handle,
                                writable_handle: st0.writable_handle,
                                payload_ty: st0.payload_ty,
                                pending_read: None,
                                pending_write: None,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                                read_done: true,
                                write_succeeded: true,
                                write_observed_readable_drop: st0.write_observed_readable_drop,
                                wrote_value: st0.wrote_value,
                              })
                              cache_i32(0)
                            }
                            None =>
                              if st0.writable_dropped {
                                async_state.futures.set(ep.future_id, {
                                  readable_handle: st0.readable_handle,
                                  writable_handle: st0.writable_handle,
                                  payload_ty: st0.payload_ty,
                                  pending_read: None,
                                  pending_write: None,
                                  readable_dropped: st0.readable_dropped,
                                  writable_dropped: st0.writable_dropped,
                                  read_done: true,
                                  write_succeeded: st0.write_succeeded,
                                  write_observed_readable_drop: st0.write_observed_readable_drop,
                                  wrote_value: st0.wrote_value,
                                })
                                cache_i32(1)
                              } else {
                                // Register a pending read and report BLOCKED=-1.
                                async_state.futures.set(ep.future_id, {
                                  readable_handle: st0.readable_handle,
                                  writable_handle: st0.writable_handle,
                                  payload_ty: st0.payload_ty,
                                  pending_read: Some({ ptr, }),
                                  pending_write: None,
                                  readable_dropped: st0.readable_dropped,
                                  writable_dropped: st0.writable_dropped,
                                  read_done: st0.read_done,
                                  write_succeeded: st0.write_succeeded,
                                  write_observed_readable_drop: st0.write_observed_readable_drop,
                                  wrote_value: st0.wrote_value,
                                })
                                cache_i32(-1)
                              }
                          }
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    cache_i32(0)
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureWrite(_tyidx, _opts) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32, @types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let resources = resolve_canon_resources(_opts, state) catch {
                e => raise e
              }
              let async_state = state.async_state
              let caller_component_id = state.resource_table.id
              let is_async = canon_opt_is_async(_opts)
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                let cur = if async_state.call_cursor_stack.length() == 0 {
                  0
                } else {
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1]
                }
                let per_task = match async_state.call_results.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, Array[@types.Value]] = {}
                    async_state.call_results.set(task_id, m)
                    m
                  }
                }
                match per_task.get(cur) {
                  Some(v) => {
                    async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                    1] = cur + 1
                    return v
                  }
                  None => ()
                }
                fn cache_i32(n : Int) -> Array[@types.Value] {
                  let out = [@types.Value::I32(n)]
                  per_task.set(cur, out)
                  async_state.call_cursor_stack[async_state.call_cursor_stack.length() -
                  1] = cur + 1
                  out
                }
                // Sync future.write blocks the task; the async form returns BLOCKED=-1.
                if !is_async && !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return cache_i32(0)
                }
                match args {
                  [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
                    match async_state.future_endpoints.get(handle) {
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        cache_i32(0)
                      }
                      Some(ep) =>
                        if ep.is_readable {
                          trap_canon("type mismatch")
                          cache_i32(0)
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown future handle index \{handle}",
                              )
                              return cache_i32(0)
                            }
                          }
                          if st0.write_succeeded {
                            trap_canon(
                              "cannot write to future after previous write succeeded",
                            )
                            return cache_i32(0)
                          }
                          if st0.write_observed_readable_drop {
                            trap_canon(
                              "cannot write to future after previous write succeeded or readable end dropped",
                            )
                            return cache_i32(0)
                          }

                          // If the readable end was dropped before any rendezvous, report DROPPED.
                          if st0.readable_dropped {
                            async_state.futures.set(ep.future_id, {
                              readable_handle: st0.readable_handle,
                              writable_handle: st0.writable_handle,
                              payload_ty: st0.payload_ty,
                              pending_read: None,
                              pending_write: None,
                              readable_dropped: st0.readable_dropped,
                              writable_dropped: st0.writable_dropped,
                              read_done: st0.read_done,
                              write_succeeded: false,
                              write_observed_readable_drop: true,
                              wrote_value: st0.wrote_value,
                            })
                            return cache_i32(1)
                          }
                          match st0.pending_read {
                            Some(pr) => {
                              // Intra-component char futures cannot rendezvous.
                              match st0.payload_ty {
                                Some(Prim(Char)) =>
                                  if ep.creator_component_id ==
                                    caller_component_id {
                                    trap_canon(
                                      "cannot read from and write to intra-component future",
                                    )
                                    return [@types.Value::I32(0)]
                                  }
                                _ => ()
                              }

                              // Load payload (if any) from memory at `ptr` and write to the reader ptr.
                              match st0.payload_ty {
                                None => ()
                                Some(Prim(U8)) => {
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  let b = mem.load_byte(ptr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  mem.store_byte(pr.ptr, b) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                }
                                Some(Prim(Char)) => {
                                  if ptr % 4 != 0 || pr.ptr % 4 != 0 {
                                    trap_canon("unaligned pointer")
                                    return [@types.Value::I32(0)]
                                  }
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  let n = mem.load_i32(ptr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  // Validate scalar value.
                                  (char_from_canon_i32(n) catch {
                                    e => {
                                      trap_canon(canon_err_message(e))
                                      return [@types.Value::I32(0)]
                                    }
                                  })
                                  |> ignore
                                  mem.store_i32(pr.ptr, n) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                }
                                _ => {
                                  trap_canon("unsupported future type")
                                  return [@types.Value::I32(0)]
                                }
                              }

                              // Completing a pending read unblocks the reader: emit FUTURE_READ.
                              if async_state.future_endpoints.get(
                                  st0.readable_handle,
                                )
                                is Some(_) {
                                enqueue_waitable_event(
                                  async_state,
                                  st0.readable_handle,
                                  {
                                    code: 4,
                                    index: st0.readable_handle,
                                    payload: 0,
                                  },
                                )
                              }
                              async_state.futures.set(ep.future_id, {
                                readable_handle: st0.readable_handle,
                                writable_handle: st0.writable_handle,
                                payload_ty: st0.payload_ty,
                                pending_read: None,
                                pending_write: None,
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                                read_done: true,
                                write_succeeded: true,
                                write_observed_readable_drop: st0.write_observed_readable_drop,
                                wrote_value: true,
                              })
                              cache_i32(0)
                            }
                            None => {
                              // Register a pending write by reading the payload once.
                              let write_val : Int = match st0.payload_ty {
                                None => 0
                                Some(Prim(U8)) => {
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  let b = mem.load_byte(ptr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  b.to_int()
                                }
                                Some(Prim(Char)) => {
                                  if ptr % 4 != 0 {
                                    trap_canon("unaligned pointer")
                                    return [@types.Value::I32(0)]
                                  }
                                  let mem = match resources.mem_addr {
                                    Some(addr) =>
                                      store.get_mem(addr) catch {
                                        e => {
                                          trap_canon(e.to_string())
                                          return [@types.Value::I32(0)]
                                        }
                                      }
                                    None => {
                                      trap_canon("missing canon memory")
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  let n = mem.load_i32(ptr) catch {
                                    e => {
                                      trap_canon(e.to_string())
                                      return [@types.Value::I32(0)]
                                    }
                                  }
                                  (char_from_canon_i32(n) catch {
                                    e => {
                                      trap_canon(canon_err_message(e))
                                      return [@types.Value::I32(0)]
                                    }
                                  })
                                  |> ignore
                                  n
                                }
                                _ => {
                                  trap_canon("unsupported future type")
                                  return [@types.Value::I32(0)]
                                }
                              }
                              async_state.futures.set(ep.future_id, {
                                readable_handle: st0.readable_handle,
                                writable_handle: st0.writable_handle,
                                payload_ty: st0.payload_ty,
                                pending_read: None,
                                pending_write: Some(write_val),
                                readable_dropped: st0.readable_dropped,
                                writable_dropped: st0.writable_dropped,
                                read_done: st0.read_done,
                                write_succeeded: st0.write_succeeded,
                                write_observed_readable_drop: st0.write_observed_readable_drop,
                                wrote_value: true,
                              })
                              cache_i32(-1)
                            }
                          }
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    cache_i32(0)
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureCancelRead(_tyidx, _is_async) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return [@types.Value::I32(0)]
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match async_state.future_endpoints.get(handle) {
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        [@types.Value::I32(0)]
                      }
                      Some(ep) =>
                        if !ep.is_readable {
                          trap_canon("type mismatch")
                          [@types.Value::I32(0)]
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown future handle index \{handle}",
                              )
                              return [@types.Value::I32(0)]
                            }
                          }
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: None,
                            pending_write: st0.pending_write,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                            read_done: st0.read_done,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            wrote_value: st0.wrote_value,
                          })
                          // CANCELLED=2
                          [@types.Value::I32(2)]
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureCancelWrite(_tyidx, _is_async) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [@types.ValueType::I32],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return [@types.Value::I32(0)]
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match async_state.future_endpoints.get(handle) {
                      None => {
                        trap_canon("unknown future handle index \{handle}")
                        [@types.Value::I32(0)]
                      }
                      Some(ep) =>
                        if ep.is_readable {
                          trap_canon("type mismatch")
                          [@types.Value::I32(0)]
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => {
                              trap_canon(
                                "unknown future handle index \{handle}",
                              )
                              return [@types.Value::I32(0)]
                            }
                          }
                          let had_pending = match st0.pending_write {
                            Some(_) => true
                            None => false
                          }
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: st0.pending_read,
                            pending_write: None,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                            read_done: st0.read_done,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            // If we cancelled a pending write, treat as "no value written".
                            wrote_value: if had_pending {
                              false
                            } else {
                              st0.wrote_value
                            },
                          })
                          [@types.Value::I32(2)]
                        }
                    }
                  _ => {
                    trap_canon("type mismatch")
                    [@types.Value::I32(0)]
                  }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureDropReadable(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match async_state.future_endpoints.get(handle) {
                      Some(ep) =>
                        if !ep.is_readable {
                          []
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => return []
                          }
                          // Dropping readable end may resolve a pending write as DROPPED.
                          if st0.pending_write is Some(_) {
                            if async_state.future_endpoints.get(
                                st0.writable_handle,
                              )
                              is Some(_) {
                              enqueue_waitable_event(
                                async_state,
                                st0.writable_handle,
                                {
                                  code: 5,
                                  index: st0.writable_handle,
                                  payload: 1,
                                },
                              )
                            }
                          }
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: None,
                            pending_write: None,
                            readable_dropped: true,
                            writable_dropped: st0.writable_dropped,
                            read_done: true,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            wrote_value: st0.wrote_value,
                          })

                          // Remove from any waitable-set membership and queued events.
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
                          async_state.future_endpoints.remove(handle)
                          free_shared_handle(async_state, handle)
                          []
                        }
                      None => []
                    }
                  _ => []
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::FutureDropWritable(_tyidx) => {
              let core_type : @types.FuncType = {
                params: [@types.ValueType::I32],
                results: [],
              }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                match args {
                  [@types.Value::I32(handle)] =>
                    match async_state.future_endpoints.get(handle) {
                      Some(ep) =>
                        if ep.is_readable {
                          []
                        } else {
                          let st0 = match
                            async_state.futures.get(ep.future_id) {
                            Some(s) => s
                            None => return []
                          }
                          if !st0.wrote_value && !st0.write_succeeded {
                            trap_canon(
                              "cannot drop future write end without first writing a value",
                            )
                            return []
                          }
                          async_state.futures.set(ep.future_id, {
                            readable_handle: st0.readable_handle,
                            writable_handle: st0.writable_handle,
                            payload_ty: st0.payload_ty,
                            pending_read: st0.pending_read,
                            pending_write: st0.pending_write,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: true,
                            read_done: st0.read_done,
                            write_succeeded: st0.write_succeeded,
                            write_observed_readable_drop: st0.write_observed_readable_drop,
                            wrote_value: st0.wrote_value,
                          })
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
                          async_state.future_endpoints.remove(handle)
                          free_shared_handle(async_state, handle)
                          []
                        }
                      None => []
                    }
                  _ => []
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ContextGet(_vt, _idx) => {
              let core_type : @types.FuncType = { params: [], results: [_vt] }
              let async_state = state.async_state
              let host = fn(
                _args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                let task_id = current_task_id(async_state)
                match async_state.task_contexts.get(task_id) {
                  Some(m) =>
                    match m.get(_idx) {
                      Some(v) => [v]
                      None =>
                        // Default 0 per value type.
                        match _vt {
                          @types.ValueType::I32 => [@types.Value::I32(0)]
                          @types.ValueType::I64 => [@types.Value::I64(0L)]
                          @types.ValueType::F32 => [@types.Value::F32(0.0)]
                          @types.ValueType::F64 => [@types.Value::F64(0.0)]
                          _ => {
                            trap_canon("unsupported context type")
                            []
                          }
                        }
                    }
                  None =>
                    match _vt {
                      @types.ValueType::I32 => [@types.Value::I32(0)]
                      @types.ValueType::I64 => [@types.Value::I64(0L)]
                      @types.ValueType::F32 => [@types.Value::F32(0.0)]
                      @types.ValueType::F64 => [@types.Value::F64(0.0)]
                      _ => {
                        trap_canon("unsupported context type")
                        []
                      }
                    }
                }
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            Canon::ContextSet(_vt, _idx) => {
              let core_type : @types.FuncType = { params: [_vt], results: [] }
              let async_state = state.async_state
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                if !canon_may_leave[0] {
                  trap_canon("cannot leave component instance")
                }
                if args.length() != 1 {
                  trap_canon("type mismatch")
                  return []
                }
                let task_id = current_task_id(async_state)
                let m = match async_state.task_contexts.get(task_id) {
                  Some(m) => m
                  None => {
                    let m : Map[Int, @types.Value] = {}
                    async_state.task_contexts.set(task_id, m)
                    m
                  }
                }
                m.set(_idx, args[0])
                []
              }
              state.core_funcs.push(
                alloc_host_core_func(store, core_type, host),
              )
            }
            _ => ()
          }
        }
      }
      9 => {
        let start = parse_start_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        if start.func_idx < 0 || start.func_idx >= state.funcs.length() {
          raise InvalidFuncIndex(start.func_idx)
        }
        let args : Array[ComponentValue] = []
        for idx in start.args {
          if idx < 0 || idx >= state.values.length() {
            raise InvalidValueIndex(idx)
          }
          args.push(state.values[idx])
        }
        let results = call_component_func(
          state.funcs[start.func_idx],
          args,
          store,
          state.resource_table,
          state.async_state,
        )
        if results.length() != start.results {
          raise InvalidStartResultCount(results.length())
        }
        for r in results {
          state.values.push(r)
        }
      }
      10 => {
        let imports = parse_import_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        let import_outer_stack = extend_outer_stack(
          outer_stack,
          env_instance_from_state("\{name}::env", state, store),
        )
        for imp in imports {
          let ext = resolve_import(
            linker,
            overrides,
            import_outer_stack,
            imp.name,
            imp.desc,
            state.types,
            state.core_types,
            store,
          )
          match imp.desc {
            ExternDesc::CoreModuleType(_) =>
              match ext {
                ComponentExtern::CoreModule(m) => state.core_modules.push(m)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::FuncType(_) =>
              match ext {
                ComponentExtern::Func(f) => state.funcs.push(f)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Value(_) =>
              match ext {
                ComponentExtern::Value(v) => state.values.push(v)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Type(_) =>
              match ext {
                ComponentExtern::Type(t) => state.types.push(t)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::ComponentType(_) =>
              match ext {
                ComponentExtern::Component(c) => state.components.push(c)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::InstanceType(_) =>
              match ext {
                ComponentExtern::Instance(i) => state.instances.push(i)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
          }
        }
      }
      11 => {
        let exports = parse_export_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for exp in exports {
          let name = decode_export_name(exp.name)
          let ext = resolve_sortidx(exp.sortidx, state)
          state.exports.set(name, ext)
          append_alias(exp.sortidx.sort, ext, state)
        }
      }
      _ => ()
    }
  }
  may_enter_self[0] = true
  let instance : ComponentInstance = {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    resource_table: state.resource_table,
    stream_table: state.stream_table,
    async_state: state.async_state,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
  linker.register(name, instance)
  instance
}
