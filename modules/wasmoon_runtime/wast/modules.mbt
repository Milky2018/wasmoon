///|
/// Module definitions, instances, and import names for one script.
pub struct WastModules {
  priv mut current : @runtime.ModuleInstance?
  priv named : Map[String, @runtime.ModuleInstance]
  priv registered : Map[String, @runtime.ModuleInstance]
  priv definitions : Map[String, @types.Module]
  priv mut latest_definition : @types.Module?
}

///|
pub fn WastModules::new(
  registered : Map[String, @runtime.ModuleInstance],
) -> WastModules {
  {
    current: None,
    named: Map([]),
    registered,
    definitions: Map([]),
    latest_definition: None,
  }
}

///|
pub fn WastModules::clear(self : WastModules) -> Unit {
  self.current = None
  self.latest_definition = None
  self.named.clear()
  self.registered.clear()
  self.definitions.clear()
}

///|
pub fn WastModules::instance(
  self : WastModules,
  name : String?,
) -> @runtime.ModuleInstance? {
  match name {
    Some(name) => self.named.get(name)
    None => self.current
  }
}

///|
pub fn WastModules::definition(
  self : WastModules,
  name : String?,
) -> @types.Module? {
  match name {
    Some(name) => self.definitions.get(name)
    None => self.latest_definition
  }
}

///|
pub fn WastModules::inherit_definitions(
  self : WastModules,
  parent : WastModules,
) -> Unit {
  for name, definition in parent.definitions {
    self.definitions[name] = definition
  }
  self.latest_definition = parent.latest_definition
}

///|
fn WastModules::record_definition(
  self : WastModules,
  module_ : @types.Module,
  name : String?,
) -> Unit {
  self.latest_definition = Some(module_)
  if name is Some(name) {
    self.definitions[name] = module_
  }
}

///|
pub fn WastModules::publish(
  self : WastModules,
  instance : @runtime.ModuleInstance,
  name : String?,
) -> Unit {
  self.current = Some(instance)
  if name is Some(name) {
    self.named[name] = instance
  }
}

///|
pub fn WastModules::register(
  self : WastModules,
  name : String,
  instance : @runtime.ModuleInstance,
) -> Unit {
  self.registered[name] = instance
  self.named[name] = instance
}

///|
/// Build imports from registered modules
pub fn WastModules::build_imports(
  self : WastModules,
  store : @runtime.Store,
) -> @runtime.Imports {
  let imports = @runtime.Imports::Imports(store)
  for mod_name, instance in self.registered {
    imports.add_instance(mod_name, instance)
  }
  imports
}
