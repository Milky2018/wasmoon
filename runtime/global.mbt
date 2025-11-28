///|
/// Runtime representation of a global variable
struct GlobalInstance {
  type_ : @wasmoon.GlobalType
  mut value : @wasmoon.Value
} derive(Show)

///|
pub fn GlobalInstance::new(
  type_ : @wasmoon.GlobalType,
  value : @wasmoon.Value,
) -> GlobalInstance {
  { type_, value }
}

///|
pub fn GlobalInstance::get(self : GlobalInstance) -> @wasmoon.Value {
  self.value
}

///|
pub fn GlobalInstance::set(
  self : GlobalInstance,
  value : @wasmoon.Value,
) -> Unit raise RuntimeError {
  if !self.type_.mutable {
    raise RuntimeError::TypeMismatch // attempting to mutate immutable global
  }
  self.value = value
}
