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
