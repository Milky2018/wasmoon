///|
/// Runtime representation of a global variable
struct GlobalInstance {
  type_ : @types.GlobalType
  mut value : @types.Value
  mut native : NativeGlobalBinding?
} derive(Debug)

///|
pub fn GlobalInstance::GlobalInstance(
  type_ : @types.GlobalType,
  value : @types.Value,
) -> GlobalInstance {
  { type_, value, native: None, }
}

///|
pub fn GlobalInstance::get(
  self : GlobalInstance,
) -> @types.Value raise RuntimeError {
  match self.native {
    Some(binding) => (binding.read)()
    None => self.value
  }
}

///|
pub fn GlobalInstance::set(
  self : GlobalInstance,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if !self.type_.mutable {
    raise TypeMismatch // attempting to mutate immutable global
  }
  match self.native {
    Some(binding) => (binding.write)(value)
    None => self.value = value
  }
}

///|
/// Get global type for type checking
pub fn GlobalInstance::get_type(self : GlobalInstance) -> @types.GlobalType {
  self.type_
}

///|
/// Shared native storage for one store global, independent of module indices.
pub(all) struct NativeGlobalBinding {
  address : Int64
  root : () -> @types.Value
  read : () -> @types.Value raise RuntimeError
  write : (@types.Value) -> Unit raise RuntimeError
  release : () -> Unit
}

///|
pub impl Debug for NativeGlobalBinding with fn to_repr(_self) {
  Repr::literal("NativeGlobalBinding")
}

///|
pub fn GlobalInstance::native_binding(
  self : GlobalInstance,
) -> NativeGlobalBinding? {
  self.native
}

///|
pub fn GlobalInstance::bind_native(
  self : GlobalInstance,
  binding : NativeGlobalBinding,
) -> Unit {
  self.native = Some(binding)
}

///|
fn GlobalInstance::close(self : GlobalInstance) -> Unit {
  if self.native is Some(binding) {
    self.native = None
    (binding.release)()
  }
}

///|
fn GlobalInstance::root(self : GlobalInstance) -> @types.Value {
  match self.native {
    Some(binding) => (binding.root)()
    None => self.value
  }
}

///|
pub extend NativeGlobalBinding with Debug::{to_repr}
