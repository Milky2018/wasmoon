///|
/// Runtime representation of a global variable
struct GlobalInstance {
  type_ : @types.GlobalType
  mut value : @types.Value
} derive(Show)

///|
pub fn GlobalInstance::new(
  type_ : @types.GlobalType,
  value : @types.Value,
) -> GlobalInstance {
  { type_, value }
}

///|
pub fn GlobalInstance::get(self : GlobalInstance) -> @types.Value {
  self.value
}

///|
pub fn GlobalInstance::set(
  self : GlobalInstance,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if !self.type_.mutable {
    raise RuntimeError::TypeMismatch // attempting to mutate immutable global
  }
  self.value = value
}

///|
/// Get global type for type checking
pub fn GlobalInstance::get_type(self : GlobalInstance) -> @types.GlobalType {
  self.type_
}
