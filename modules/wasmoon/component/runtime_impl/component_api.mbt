///|
pub(all) enum HostFuturePoll {
  Pending
  Ready(Array[ComponentValue])
}

///|
/// A single in-flight asynchronous host call.
///
/// `poll` must not block. External readiness is driven through the
/// `HostRuntimeState` event-loop callback shared by the surrounding host world.
struct HostFuture {
  poll : () -> HostFuturePoll raise ComponentRuntimeError
  cancel : () -> Unit raise ComponentRuntimeError
}

///|
impl Debug for HostFuture with fn to_repr(_self) {
  Repr::literal("HostFuture")
}

///|
pub fn HostFuture::HostFuture(
  poll : () -> HostFuturePoll raise ComponentRuntimeError,
  cancel : () -> Unit raise ComponentRuntimeError,
) -> HostFuture {
  { poll, cancel }
}

///|
/// Entry state for one component instance.
///
/// `ready` prevents lowered imports from entering a partially-instantiated
/// instance. `active` is a dynamic execution guard and is released while a
/// stackful invocation is suspended. `poisoned` is permanent after a trap.
struct ComponentInstanceEntryState {
  ready : Ref[Bool]
  active : Ref[Bool]
  poisoned : Ref[Bool]
} derive(Debug)

///|
fn ComponentInstanceEntryState::new() -> ComponentInstanceEntryState {
  { ready: Ref(false), active: Ref(false), poisoned: Ref(false) }
}

///|
fn ComponentInstanceEntryState::enable(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.ready.val = true
}

///|
fn ComponentInstanceEntryState::may_queue(
  self : ComponentInstanceEntryState,
) -> Bool {
  self.ready.val && !self.poisoned.val
}

///|
fn ComponentInstanceEntryState::may_enter(
  self : ComponentInstanceEntryState,
) -> Bool {
  self.may_queue() && !self.active.val
}

///|
fn ComponentInstanceEntryState::enter(
  self : ComponentInstanceEntryState,
) -> Unit raise ComponentRuntimeError {
  if !self.may_enter() {
    raise CanonCallError("cannot enter component instance")
  }
  self.active.val = true
}

///|
fn ComponentInstanceEntryState::leave(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.active.val = false
}

///|
fn ComponentInstanceEntryState::poison(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.active.val = false
  self.poisoned.val = true
}

///|
struct HostEventLoop {
  poll : () -> Bool raise ComponentRuntimeError
  wait : () -> Bool raise ComponentRuntimeError
}

///|
impl Debug for HostEventLoop with fn to_repr(_self) {
  Repr::literal("HostEventLoop")
}

///|
pub(all) enum ComponentFunc {
  // The entry state separates partial instantiation, active execution, and
  // permanent poisoning.
  Lifted(
    CoreFuncRef,
    FuncType,
    CanonResources,
    Array[TypeDef?],
    ResourceTable,
    ComponentInstanceEntryState,
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
  HostAsync(
    FuncType,
    Array[TypeDef?],
    (Array[ComponentValue], ResourceTable) -> HostFuture raise ComponentRuntimeError
  )
}

///|
pub impl Debug for ComponentFunc with fn to_repr(self) {
  match self {
    Lifted(_, _, _, _, _, _, _, _) =>
      Repr::ctor("Lifted", [(None, Repr::literal("<lowered>"))])
    Host(_, _, _) => Repr::ctor("Host", [(None, Repr::literal("<native>"))])
    HostAsync(_, _, _) =>
      Repr::ctor("HostAsync", [(None, Repr::literal("<native-async>"))])
  }
}

///|
pub impl Show for ComponentFunc with fn output(self, logger) {
  match self {
    Lifted(_, _, _, _, _, _, _, _) => logger.write_string("Lifted")
    Host(_, _, _) => logger.write_string("Host")
    HostAsync(_, _, _) => logger.write_string("HostAsync")
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
pub impl Show for CoreInstance with fn output(_self, logger) {
  logger.write_string("CoreInstance")
}

///|
/// A component value is a closure: the component binary plus the captured outer
/// environment needed to resolve `alias outer ...` when instantiated later.
///
/// The type is abstract on purpose. Every closure the runtime instantiates
/// must originate from a validated boundary (`ComponentLinker::instantiate`,
/// `ComponentLinker::add_component`, or a section of an already-validated
/// component), so external code must not be able to forge a
/// `Component(closure)` extern around an unchecked component.
struct ComponentClosure {
  component : Component
  outer_stack : Array[ComponentInstance]
}

///|
pub impl Show for ComponentClosure with fn output(_self, logger) {
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
pub impl Show for ComponentExtern with fn output(self, logger) {
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
    Some(Func(func)) => {
      let func_type = match func {
        Host(ft, _, _) => ft
        HostAsync(ft, _, _) => ft
        Lifted(_, ft, _, _, _, _, _, _) => ft
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
  // Released by `finish_close`, like every other retained graph below. The
  // engine can reach embedder-supplied closures and native session state, and
  // an embedder callback that refers back to its linker would otherwise form a
  // reference cycle that outlives terminal close. Read it through
  // `ComponentLinker::core_engine`.
  core_engine_slot : Ref[CoreExecutionEngine?]
  core_execution_lifecycle : CoreExecutionLifecycle
  components : Array[(String, ComponentInstance)]
  imports : Map[String, ComponentExtern]
  host_runtime : Ref[HostRuntimeState?]
  closed : Ref[Bool]
  close_complete : Ref[Bool]
  instantiating : Ref[Bool]
  // Mutable counter stored in a 1-element array so methods can bump it without
  // requiring `mut self`.
  resource_id_counter : Array[Int]
}

///|
pub fn ComponentLinker::ComponentLinker() -> ComponentLinker {
  ComponentLinker::with_core_execution_engine(
    interpreter_core_execution_engine(),
  )
}

///|
/// Create a component linker with an embedding-provided core execution engine.
pub fn ComponentLinker::with_core_execution_engine(
  core_engine : CoreExecutionEngine,
) -> ComponentLinker {
  let core_linker = @runtime.Linker::Linker()
  let core_execution_lifecycle = CoreExecutionLifecycle::new()
  let managed_core_engine = core_engine.with_lifecycle(core_execution_lifecycle)
  managed_core_engine.prepare_store(core_linker.get_store())
  {
    core_linker,
    core_engine_slot: Ref(Some(managed_core_engine)),
    core_execution_lifecycle,
    components: [],
    imports: Map([]),
    host_runtime: Ref(None),
    closed: Ref(false),
    close_complete: Ref(false),
    instantiating: Ref(false),
    resource_id_counter: [0],
  }
}

///|
/// The core execution engine backing this linker.
///
/// After terminal close the engine is released, and this reports a closed
/// engine that rejects further work instead of resurrecting the released one.
/// Every caller below reaches the engine while the linker is still open.
fn ComponentLinker::core_engine(self : ComponentLinker) -> CoreExecutionEngine {
  match self.core_engine_slot.val {
    Some(engine) => engine
    None => closed_core_execution_engine()
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
/// Close the linker and its execution engine.
///
/// The linker is terminal as soon as this is called. Published continuations
/// are cancelled first; final engine and Store teardown waits until every
/// in-flight core execution has either returned or transferred and released
/// its continuation lease.
pub fn ComponentLinker::close(self : ComponentLinker) -> Unit {
  if self.closed.val {
    return
  }
  self.closed.val = true
  self.core_execution_lifecycle.begin_close()
  for entry in self.components {
    let (_, component) = entry
    cancel_async_state_continuations(component.async_state)
  }
  match self.host_runtime.val {
    Some(runtime) => runtime.cancel_continuations()
    None => ()
  }
  self.core_execution_lifecycle.request_close(fn() { self.finish_close() })
}

///|
/// Release one linker-owned instance at terminal close.
///
/// A component that defines a nested component stores a `ComponentClosure`
/// whose `outer_stack` holds an env instance sharing this instance's child
/// arrays — `alias outer` resolution requires the enclosing scope when the
/// nested component is instantiated later. That is a deliberate reference
/// cycle, and reference counting can never reclaim it. The cycle runs
/// through this instance's own arrays, so clearing them is what breaks it;
/// the env and inline instances of the same frame share the very same array
/// objects and die with it.
///
/// Deliberately shallow. The linker owns exactly the instances its own
/// instantiations registered — every instantiation frame registers itself,
/// so `finish_close` walks all of them directly. Recursing into children
/// would cross the ownership boundary: `instances` and `exports` also hold
/// instances supplied through `add_instance`/`add_import`, which another
/// linker or the embedder owns and may still be using. Clearing this
/// instance's arrays only drops references to those, never their state.
fn release_owned_instance(instance : ComponentInstance) -> Unit {
  instance.components.clear()
  instance.instances.clear()
  instance.funcs.clear()
  instance.values.clear()
  instance.exports.clear()
}

///|
fn ComponentLinker::finish_close(self : ComponentLinker) -> Unit {
  if self.close_complete.val {
    return
  }
  self.close_complete.val = true
  for entry in self.components {
    let (_, instance) = entry
    release_owned_instance(instance)
  }
  // Imports are not owned: dropping the table's references is the linker's
  // entire claim on them. Releasing their graphs here destroyed instances
  // shared from other linkers or built by the embedder.
  self.components.clear()
  self.imports.clear()
  self.host_runtime.val = None
  // Close the engine, then drop it. Holding it past terminal close would keep
  // embedder state alive for the lifetime of the linker, and would make an
  // embedder callback that refers back to this linker an uncollectable cycle.
  match self.core_engine_slot.val {
    Some(engine) => {
      self.core_engine_slot.val = None
      engine.close()
    }
    None => ()
  }
  self.core_linker.close()
}

///|
/// Discard the staged registrations of a failed or refused instantiation.
///
/// Staged instances were never published, so no caller can hold them:
/// release each graph's own containers (breaking its `alias outer` cycles)
/// and withdraw its resource table from the shared async state — the table
/// was added by the frame's build state and nothing can resolve it once the
/// whole tree is discarded.
fn discard_staged_registrations(
  staged : Array[(String, ComponentInstance)],
) -> Unit {
  for entry in staged {
    let (_, instance) = entry
    release_owned_instance(instance)
    instance.async_state.resource_tables.remove(instance.resource_table.id)
    |> ignore
  }
  staged.clear()
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
) -> Unit raise ComponentRuntimeError {
  // A terminally closed linker accepts no new imports. `finish_close` has
  // already walked and released the import table, so an extern added after
  // close would be retained until the linker itself dies — an uncollectable
  // cycle whenever the extern captures its own linker.
  if self.closed.val {
    raise Cancelled
  }
  self.imports.set(name, ext)
}

///|
/// Return a host import previously configured on this linker.
pub fn ComponentLinker::get_import(
  self : ComponentLinker,
  name : String,
) -> ComponentExtern? {
  self.imports.get(name)
}

///|
pub fn ComponentLinker::add_func(
  self : ComponentLinker,
  name : String,
  func_type : FuncType,
  func : (Array[ComponentValue]) -> Array[ComponentValue] raise ComponentRuntimeError,
) -> Unit raise ComponentRuntimeError {
  self.add_import(
    name,
    Func(
      Host(func_type, [], fn(
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
) -> Unit raise ComponentRuntimeError {
  self.add_import(name, Value(value))
}

///|
/// Register a component import. Like `ComponentLinker::instantiate`, the
/// boundary accepts validation evidence rather than a raw component: an
/// imported component is instantiated by the instance sections of whichever
/// component imports it, so an unchecked component here would reach
/// instantiation without ever passing validation.
pub fn ComponentLinker::add_component(
  self : ComponentLinker,
  name : String,
  component : @component_validator.ValidatedComponent,
) -> Unit raise ComponentRuntimeError {
  let isolated = @component.parse_component(component.component_bytes()) catch {
    e => raise ComponentParseError(e.to_string())
  }
  self.add_import(name, Component({ component: isolated, outer_stack: [] }))
}

///|
pub fn ComponentLinker::add_instance(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit raise ComponentRuntimeError {
  self.add_import(name, Instance(instance))
}

///|
pub fn ComponentLinker::add_core_module(
  self : ComponentLinker,
  name : String,
  module_ : @types.Module,
) -> Unit raise ComponentRuntimeError {
  self.add_import(name, CoreModule(module_))
}

///|
pub fn ComponentLinker::add_core_instance(
  self : ComponentLinker,
  name : String,
  instance : CoreInstance,
) -> Unit raise ComponentRuntimeError {
  self.add_import(name, CoreInstance(instance))
}

///|
pub fn ComponentLinker::instantiate(
  self : ComponentLinker,
  name : String,
  component : @component_validator.ValidatedComponent,
) -> ComponentInstance raise ComponentRuntimeError {
  self.core_execution_lifecycle.ensure_open()
  if self.instantiating.val {
    raise ReentrantInstantiation
  }
  self.instantiating.val = true
  defer {
    self.instantiating.val = false
  }
  // The whole instantiation runs under one lifecycle lease. The lease means
  // an embedder callback that
  // closes the linker mid-instantiation only begins the close: teardown is
  // deferred until this frame unwinds, so no section ever observes a
  // released engine or cleared imports. Every frame —
  // nested components included — stages its instance instead of publishing
  // it; only a root that succeeds on a still-open linker commits the tree,
  // and any failure or mid-flight close discards the whole staged tree, so a
  // partially instantiated graph is never observable through the linker.
  // Core Store allocations, linker names, native contexts, and component
  // instances each remain in their owning frame until the root commits.
  // A later start trap therefore discards unpublished state instead of
  // reconstructing an earlier snapshot.
  let core_instantiation : Ref[@runtime.LinkerInstantiation?] = Ref(None)
  let engine = self.core_engine()
  let engine_instantiation : Ref[CoreEngineInstantiation?] = Ref(None)
  let staged : Array[(String, ComponentInstance)] = []
  let instance = self.core_execution_lifecycle.with_lease(
    fn() raise ComponentRuntimeError {
      core_instantiation.val = Some(
        self.core_linker.begin_instantiation() catch {
          error => raise CoreModuleInstantiateError(error.to_string())
        },
      )
      engine_instantiation.val = Some(engine.begin_instantiation())
      let isolated = @component.parse_component(component.component_bytes()) catch {
        e => raise ComponentParseError(e.to_string())
      }
      instantiate_component(self, name, isolated, Map([]), [], staged)
    },
    rollback=fn() {
      discard_staged_registrations(staged)
      if engine_instantiation.val is Some(frame) {
        frame.discard()
      }
      if core_instantiation.val is Some(frame) {
        frame.discard()
      }
    },
  )
  if core_instantiation.val is Some(frame) {
    frame.commit()
  }
  if engine_instantiation.val is Some(frame) {
    frame.commit()
  }
  for entry in staged {
    self.components.push(entry)
  }
  instance
}
