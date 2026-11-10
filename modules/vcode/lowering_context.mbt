///|
pub struct LoweringContext {
  internal_abi : InternalAbi
  priv environment_field_resolver : ((@native.EnvironmentField) -> Array[Int32]?)?
}

///|
pub fn LoweringContext::new(internal_abi : InternalAbi) -> LoweringContext {
  { internal_abi, environment_field_resolver: None, }
}

///|
pub fn LoweringContext::with_environment_field_resolver(
  self : LoweringContext,
  resolve : (@native.EnvironmentField) -> Array[Int32]?,
) -> LoweringContext {
  { ..self, environment_field_resolver: Some(resolve), }
}

///|
pub fn LoweringContext::environment_field_offsets(
  self : LoweringContext,
  field : @native.EnvironmentField,
) -> Array[Int32]? {
  match self.environment_field_resolver {
    Some(resolve) => resolve(field)
    None => None
  }
}
