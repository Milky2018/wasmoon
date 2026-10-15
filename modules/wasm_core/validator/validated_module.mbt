///|
/// Protected validation evidence over an independently owned module snapshot.
/// Accessors return editable section copies, never the accepted backing arrays.
pub struct ValidatedModule {
  priv module_ : @types.Module
}

///|
pub fn ValidatedModule::new(
  module_ : @types.Module,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
) -> ValidatedModule raise ValidationError {
  let module_ = module_.snapshot()
  validate_module(module_, bulk_memory~, stack_switching~)
  { module_, }
}

///|
pub fn ValidatedModule::snapshot(self : ValidatedModule) -> @types.Module {
  self.module_.snapshot()
}

///|
pub fn ValidatedModule::function(
  self : ValidatedModule,
  index : Int32,
) -> (@types.FunctionCode, Int32, @types.FuncType)? {
  guard index >= 0 && index < self.module_.codes.length() else { return None }
  let type_index = self.module_.funcs[index]
  Some(
    (
      self.module_.codes[index],
      type_index,
      self.module_.validated_func_type_at(type_index),
    ),
  )
}

///|
/// The start index from the accepted snapshot, independent of host callbacks.
pub fn ValidatedModule::start(self : ValidatedModule) -> Int32? {
  self.module_.start
}
