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
pub(all) struct ComponentClosure {
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
  core_engine : CoreExecutionEngine
  core_execution_lifecycle : CoreExecutionLifecycle
  components : Array[(String, ComponentInstance)]
  imports : Map[String, ComponentExtern]
  host_runtime : Ref[HostRuntimeState?]
  closed : Ref[Bool]
  close_complete : Ref[Bool]
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
    core_engine: managed_core_engine,
    core_execution_lifecycle,
    components: [],
    imports: Map([]),
    host_runtime: Ref(None),
    closed: Ref(false),
    close_complete: Ref(false),
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
fn ComponentLinker::finish_close(self : ComponentLinker) -> Unit {
  if self.close_complete.val {
    return
  }
  self.close_complete.val = true
  self.components.clear()
  self.imports.clear()
  self.host_runtime.val = None
  self.core_engine.close()
  self.core_linker.close()
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
) -> Unit {
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
) -> Unit {
  self.add_import(name, Value(value))
}

///|
pub fn ComponentLinker::add_component(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> Unit {
  self.add_import(name, Component({ component, outer_stack: [] }))
}

///|
pub fn ComponentLinker::add_instance(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit {
  self.add_import(name, Instance(instance))
}

///|
pub fn ComponentLinker::add_core_module(
  self : ComponentLinker,
  name : String,
  module_ : @types.Module,
) -> Unit {
  self.add_import(name, CoreModule(module_))
}

///|
pub fn ComponentLinker::add_core_instance(
  self : ComponentLinker,
  name : String,
  instance : CoreInstance,
) -> Unit {
  self.add_import(name, CoreInstance(instance))
}

///|
pub fn ComponentLinker::instantiate(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> ComponentInstance raise ComponentRuntimeError {
  instantiate_component(self, name, component, Map([]), [])
}
