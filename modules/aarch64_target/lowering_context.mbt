///|
priv struct EnvironmentFieldBinding {
  field : @native.EnvironmentField
  offsets : Array[Int]
}

///|
pub struct LoweringContext {
  priv internal_abi : InternalAbi
  priv environment_fields : Array[EnvironmentFieldBinding]
  priv environment_field_resolver : ((@native.EnvironmentField) -> Array[Int]?)?
}

///|
pub fn LoweringContext::new(internal_abi : InternalAbi) -> LoweringContext {
  {
    internal_abi: internal_abi.copy(),
    environment_fields: [],
    environment_field_resolver: None,
  }
}

///|
pub fn LoweringContext::with_environment_field(
  self : LoweringContext,
  field : @native.EnvironmentField,
  offsets : Array[Int],
) -> LoweringContext {
  let bindings = self.environment_fields.copy()
  for index, binding in bindings {
    if binding.field == field {
      bindings[index] = { field, offsets: offsets.copy(), }
      return {
        internal_abi: self.internal_abi.copy(),
        environment_fields: bindings,
        environment_field_resolver: self.environment_field_resolver,
      }
    }
  }
  bindings.push({ field, offsets: offsets.copy(), })
  {
    internal_abi: self.internal_abi.copy(),
    environment_fields: bindings,
    environment_field_resolver: self.environment_field_resolver,
  }
}

///|
pub fn LoweringContext::with_environment_field_resolver(
  self : LoweringContext,
  resolve : (@native.EnvironmentField) -> Array[Int]?,
) -> LoweringContext {
  {
    internal_abi: self.internal_abi.copy(),
    environment_fields: self.environment_fields.copy(),
    environment_field_resolver: Some(resolve),
  }
}

///|
fn LoweringContext::environment_field_offsets(
  self : LoweringContext,
  field : @native.EnvironmentField,
) -> Array[Int]? {
  for binding in self.environment_fields {
    if binding.field == field {
      return Some(binding.offsets.copy())
    }
  }
  match self.environment_field_resolver {
    Some(resolve) => resolve(field)
    None => None
  }
}
