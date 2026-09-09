///|
/// Only store-independent module definitions and nominal resource types are
/// reflected into later component instances, as in the upstream WAST runner.
priv struct ScriptHost {
  linker : @runtime_impl.ComponentLinker
  runtime : @runtime_impl.HostRuntimeState
  resource_types : Map[(Int, Int), @component_types.TypeDef?]
}

///|
priv struct ComponentScriptRuntime {
  use_jit : Bool
  linkers : Array[@runtime_impl.ComponentLinker]
  definitions : Map[String, @component_types.Component]
  instances : Map[String, @runtime_impl.ComponentInstance]
  resource_origins : Map[(Int, Int), (Int, Int)]
}

///|
fn ComponentScriptRuntime::new(use_jit : Bool) -> ComponentScriptRuntime {
  {
    use_jit,
    linkers: [],
    definitions: Map([]),
    instances: Map([]),
    resource_origins: Map([]),
  }
}

///|
fn ComponentScriptRuntime::close(self : ComponentScriptRuntime) -> Unit {
  for linker in self.linkers {
    linker.close()
  }
  self.linkers.clear()
  self.instances.clear()
  self.definitions.clear()
  self.resource_origins.clear()
}

///|
fn ComponentScriptRuntime::reflect_instance(
  self : ComponentScriptRuntime,
  host : ScriptHost,
  name : String,
  source : @runtime_impl.ComponentInstance,
) -> @runtime_impl.ComponentInstance {
  let exports : Map[String, @runtime_impl.ComponentExtern] = Map([])
  for export_entry in source.exports {
    let (export_name, value) = export_entry
    match value {
      CoreModule(_) => exports.set(export_name, value)
      Type(Some(ResourceType(id, _, _, _))) => {
        let source_key = (source.resource_table.id, id)
        let origin = self.resource_origins.get(source_key).unwrap_or(source_key)
        let reflected = match host.resource_types.get(origin) {
          Some(ty) => ty
          None => {
            let ty = host.linker.new_host_resource_type()
            host.resource_types.set(origin, ty)
            ty
          }
        }
        exports.set(export_name, Type(reflected))
      }
      _ => ()
    }
  }
  make_instance(name, host.linker.get_store(), exports, host.runtime)
}

///|
fn ComponentScriptRuntime::instantiate(
  self : ComponentScriptRuntime,
  name : String,
  component : @component_types.Component,
) -> Result[@runtime_impl.ComponentInstance, String] {
  let host = create_script_host(self.use_jit) catch {
    error => return Err(error.to_string())
  }
  let linker = host.linker
  for definition_entry in self.definitions {
    let (definition_name, definition) = definition_entry
    if component_import_evidence(definition) is Ok(validated) {
      try! linker.add_component(strip_identifier(definition_name), validated)
    }
  }
  for instance_entry in self.instances {
    let (instance_name, instance) = instance_entry
    let import_name = strip_identifier(instance_name)
    let reflected = self.reflect_instance(host, import_name, instance)
    try! linker.add_instance(import_name, reflected)
  }
  match instantiate_component(linker, name, component) {
    Ok(instance) => {
      self.linkers.push(linker)
      for resource_entry in host.resource_types {
        let (origin, ty) = resource_entry
        if ty is Some(ResourceType(id, _, _, _)) {
          self.resource_origins.set((instance.resource_table.id, id), origin)
        }
      }
      Ok(instance)
    }
    Err(error) => {
      linker.close()
      Err(error)
    }
  }
}
