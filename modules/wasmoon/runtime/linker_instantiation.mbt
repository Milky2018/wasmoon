///|
/// Owner-bound staging frame for one Linker instantiation.
struct LinkerInstantiation {
  owner : Linker
  store : StoreBuildState
  modules : Array[(String, ModuleInstance)]
  mut active : Bool
}

///|
pub fn Linker::begin_instantiation(
  self : Linker,
) -> LinkerInstantiation raise RuntimeError {
  if self.instantiation is Some(_) {
    raise LinkErrorDetail("linker instantiation is already active")
  }
  let frame : LinkerInstantiation = {
    owner: self,
    store: self.store.begin_instantiation(),
    modules: [],
    active: true,
  }
  self.instantiation = Some(frame)
  frame
}

///|
pub fn LinkerInstantiation::commit(self : LinkerInstantiation) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  self.owner.instantiation = None
  self.store.commit()
  for entry in self.modules {
    self.owner.modules.push(entry)
  }
}

///|
pub fn LinkerInstantiation::discard(self : LinkerInstantiation) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  self.owner.instantiation = None
  self.store.discard()
  self.modules.clear()
}
