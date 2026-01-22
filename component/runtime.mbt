///|
/// Minimal component runtime/linker wiring.
///
/// This only supports components that contain core module sections. Component-
/// level imports/exports/instances/aliases/canons/start are rejected for now.

///|
pub(all) suberror ComponentRuntimeError {
  UnsupportedComponent(String)
  CoreModuleParseError(String)
  CoreModuleInstantiateError(String)
} derive(Show, Eq)

///|
struct ComponentInstance {
  name : String
  core_modules : Array[@runtime.ModuleInstance]
} derive(Show)

///|
struct ComponentLinker {
  core_linker : @runtime.Linker
  components : Array[(String, ComponentInstance)]
}

///|
pub fn ComponentLinker::new() -> ComponentLinker {
  { core_linker: @runtime.Linker::new(), components: [] }
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
pub fn ComponentInstance::get_core_module(
  self : ComponentInstance,
  idx : Int,
) -> @runtime.ModuleInstance? {
  if idx < 0 || idx >= self.core_modules.length() {
    None
  } else {
    Some(self.core_modules[idx])
  }
}

///|
fn ensure_supported(component : Component) -> Unit raise ComponentRuntimeError {
  if component.imports.length() > 0 {
    raise UnsupportedComponent("imports")
  }
  if component.exports.length() > 0 {
    raise UnsupportedComponent("exports")
  }
  if component.instances.length() > 0 {
    raise UnsupportedComponent("instances")
  }
  if component.aliases.length() > 0 {
    raise UnsupportedComponent("aliases")
  }
  if component.canons.length() > 0 {
    raise UnsupportedComponent("canons")
  }
  if component.start is Some(_) {
    raise UnsupportedComponent("start")
  }
  if component.components.length() > 0 {
    raise UnsupportedComponent("nested components")
  }
  if component.core_instances.length() > 0 {
    raise UnsupportedComponent("core instances")
  }
  if component.core_types.length() > 0 {
    raise UnsupportedComponent("core types")
  }
}

///|
pub fn ComponentLinker::instantiate(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> ComponentInstance raise ComponentRuntimeError {
  ensure_supported(component)
  let core_modules : Array[@runtime.ModuleInstance] = []
  for i, bytes in component.core_modules {
    let core_module = @parser.parse_module(bytes) catch {
      e => raise CoreModuleParseError(e.to_string())
    }
    let module_name = "\{name}::core\{i}"
    let inst = @executor.instantiate_with_linker(
      self.core_linker,
      module_name,
      core_module,
    ) catch {
      e => raise CoreModuleInstantiateError(e.to_string())
    }
    core_modules.push(inst)
  }
  let instance = { name, core_modules }
  self.register(name, instance)
  instance
}
