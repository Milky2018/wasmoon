///|
/// Runtime state shared by a set of host-provided component instances.
///
/// An embedding should create one value per `ComponentLinker` and use it for
/// every interface that belongs to the same host world. This preserves resource
/// identity, stream ownership, and async task state across interface imports.
struct HostRuntimeState {
  resource_table : ResourceTable
  stream_table : StreamTable
  async_state : AsyncState
}

///|
pub fn HostRuntimeState::HostRuntimeState() -> HostRuntimeState {
  let resource_table = ResourceTable()
  let stream_table = StreamTable()
  let async_state = AsyncState(stream_table)
  async_state.resource_tables.set(resource_table.id, resource_table)
  { resource_table, stream_table, async_state }
}

///|
pub fn HostRuntimeState::resource_table(
  self : HostRuntimeState,
) -> ResourceTable {
  self.resource_table
}

///|
pub fn HostRuntimeState::stream_table(self : HostRuntimeState) -> StreamTable {
  self.stream_table
}

///|
pub fn HostRuntimeState::async_state(self : HostRuntimeState) -> AsyncState {
  self.async_state
}

///|
/// Install the blocking event-loop hook used when every async host call is
/// pending. The hook returns `true` after an external event may have made
/// progress and `false` when no external work remains.
pub fn HostRuntimeState::set_event_loop(
  self : HostRuntimeState,
  event_loop : () -> Bool raise ComponentRuntimeError,
) -> Unit {
  self.async_state.host_event_loop.val = Some({ wait: event_loop })
}

///|
/// Builder for a typed component instance supplied by an embedding.
///
/// The builder deliberately exposes only component-level types, functions, and
/// nested instances. Core-module arrays and canonical runtime bookkeeping are
/// initialized by `finish`.
struct HostInstanceBuilder {
  name : String
  store : @runtime.Store
  runtime : HostRuntimeState
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  instances : Array[ComponentInstance]
  exports : Map[String, ComponentExtern]
}

///|
pub fn ComponentLinker::host_instance_builder(
  self : ComponentLinker,
  name : String,
  runtime : HostRuntimeState,
) -> HostInstanceBuilder {
  {
    name,
    store: self.get_store(),
    runtime,
    types: [],
    funcs: [],
    instances: [],
    exports: Map([]),
  }
}

///|
/// Allocate a nominal host resource type owned by this linker.
pub fn ComponentLinker::new_host_resource_type(
  self : ComponentLinker,
) -> TypeDef? {
  Some(ResourceType(self.alloc_resource_id(), 0x7f, None, HostDefined))
}

///|
fn HostInstanceBuilder::require_free_export(
  self : HostInstanceBuilder,
  name : String,
) -> Unit raise ComponentRuntimeError {
  if self.exports.get(name) is Some(_) {
    raise DuplicateHostExport(name)
  }
}

///|
fn validate_host_val_type(
  ty : ValType,
  types : Array[TypeDef?],
) -> Unit raise ComponentRuntimeError {
  match ty {
    Prim(_) => ()
    TypeIdx(idx) =>
      if idx < 0 || idx >= types.length() || types[idx] is None {
        raise InvalidHostTypeReference(idx)
      }
  }
}

///|
fn validate_host_type_def(
  ty : TypeDef,
  types : Array[TypeDef?],
) -> Unit raise ComponentRuntimeError {
  match ty {
    DefValType(_)
    | Flags(_)
    | Enum(_)
    | ResourceType(_, _, _, _)
    | InstanceTypeEmpty
    | ComponentType(_)
    | InstanceType(_) => ()
    FuncType(ft) => {
      for param in ft.params {
        validate_host_val_type(param.ty, types)
      }
      if ft.result is Some(result) {
        validate_host_val_type(result, types)
      }
    }
    List(element) | Option(element) => validate_host_val_type(element, types)
    Record(fields) =>
      for field in fields {
        validate_host_val_type(field.ty, types)
      }
    Variant(cases) =>
      for case in cases {
        if case.ty is Some(case_ty) {
          validate_host_val_type(case_ty, types)
        }
      }
    Tuple(elements) =>
      for element in elements {
        validate_host_val_type(element, types)
      }
    Result(ok, err) => {
      if ok is Some(ok_ty) {
        validate_host_val_type(ok_ty, types)
      }
      if err is Some(err_ty) {
        validate_host_val_type(err_ty, types)
      }
    }
    Own(idx) | Borrow(idx) =>
      if idx < 0 ||
        idx >= types.length() ||
        !(types[idx] is Some(ResourceType(_, _, _, _))) {
        raise InvalidHostTypeReference(idx)
      }
    Stream(element) | Future(element) =>
      if element is Some(element_ty) {
        validate_host_val_type(element_ty, types)
      }
  }
}

///|
fn validate_host_type_space(
  types : Array[TypeDef?],
) -> Unit raise ComponentRuntimeError {
  for ty in types {
    if ty is Some(defined) {
      validate_host_type_def(defined, types)
    }
  }
}

///|
pub fn HostInstanceBuilder::set_type_space(
  self : HostInstanceBuilder,
  types : Array[TypeDef?],
) -> Unit raise ComponentRuntimeError {
  validate_host_type_space(types)
  self.types.clear()
  for ty in types {
    self.types.push(ty)
  }
}

///|
pub fn HostInstanceBuilder::add_type(
  self : HostInstanceBuilder,
  name : String,
  index : Int,
) -> Unit raise ComponentRuntimeError {
  self.require_free_export(name)
  if index < 0 || index >= self.types.length() || self.types[index] is None {
    raise InvalidHostTypeReference(index)
  }
  self.exports.set(name, Type(self.types[index]))
}

///|
pub fn HostInstanceBuilder::add_func(
  self : HostInstanceBuilder,
  name : String,
  func_type : FuncType,
  func : (Array[ComponentValue], ResourceTable) -> Array[ComponentValue] raise ComponentRuntimeError,
) -> Unit raise ComponentRuntimeError {
  self.require_free_export(name)
  for param in func_type.params {
    validate_host_val_type(param.ty, self.types)
  }
  if func_type.result is Some(result) {
    validate_host_val_type(result, self.types)
  }
  let host_func = ComponentFunc::Host(func_type, self.types.copy(), func)
  self.funcs.push(host_func)
  self.exports.set(name, Func(host_func))
}

///|
pub fn HostInstanceBuilder::add_async_func(
  self : HostInstanceBuilder,
  name : String,
  func_type : FuncType,
  start : (Array[ComponentValue], ResourceTable) -> HostFuture raise ComponentRuntimeError,
) -> Unit raise ComponentRuntimeError {
  self.require_free_export(name)
  if !func_type.is_async {
    raise HostCallError("an asynchronous host function requires an async type")
  }
  for param in func_type.params {
    validate_host_val_type(param.ty, self.types)
  }
  if func_type.result is Some(result) {
    validate_host_val_type(result, self.types)
  }
  let host_func = ComponentFunc::HostAsync(func_type, self.types.copy(), start)
  self.funcs.push(host_func)
  self.exports.set(name, Func(host_func))
}

///|
pub fn HostInstanceBuilder::add_instance(
  self : HostInstanceBuilder,
  name : String,
  instance : ComponentInstance,
) -> Unit raise ComponentRuntimeError {
  self.require_free_export(name)
  self.instances.push(instance)
  self.exports.set(name, Instance(instance))
}

///|
pub fn HostInstanceBuilder::finish(
  self : HostInstanceBuilder,
) -> ComponentInstance {
  {
    name: self.name,
    types: self.types,
    funcs: self.funcs,
    values: [],
    components: [],
    instances: self.instances,
    resource_table: self.runtime.resource_table,
    stream_table: self.runtime.stream_table,
    async_state: self.runtime.async_state,
    core_modules: [],
    core_instances: [],
    core_funcs: [],
    core_types: [],
    core_tables: [],
    core_mems: [],
    core_globals: [],
    core_tags: [],
    exports: self.exports,
    store: self.store,
  }
}
