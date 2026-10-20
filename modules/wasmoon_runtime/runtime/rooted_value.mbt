///|
/// An embedding value with Store provenance and an explicit GC root lifetime.
/// On native, MoonBit RC retires the root when this value is dropped. On wasm,
/// explicitly close it (normally with defer). Close invalidates all aliases;
/// Store.close also retires outstanding roots.
/// Primitive values can be passed between Stores.
pub struct RootedValue {
  priv mut state : RootedValueState?
  priv mut declared_type : (ModuleInstance, @types.ValueType)?
}

///|
priv enum RootedValueState {
  Primitive(@types.Value)
  Reference(Store, GcRootLease, @jit_ffi.CleanupOwner, @types.Value)
}

///|
pub fn RootedValue::i32(value : Int32) -> RootedValue {
  { declared_type: None, state: Some(Primitive(I32(value))), }
}

///|
pub fn RootedValue::i64(value : Int64) -> RootedValue {
  { declared_type: None, state: Some(Primitive(I64(value))), }
}

///|
pub fn RootedValue::f32(value : Float) -> RootedValue {
  { declared_type: None, state: Some(Primitive(F32(value))), }
}

///|
pub fn RootedValue::f64(value : Double) -> RootedValue {
  { declared_type: None, state: Some(Primitive(F64(value))), }
}

///|
pub fn RootedValue::null() -> RootedValue {
  { declared_type: None, state: Some(Primitive(Null)), }
}

///|
/// Read a scalar without exposing Store-local reference indices.
pub fn RootedValue::scalar(
  self : RootedValue,
) -> @types.Value raise RuntimeError {
  match self.state {
    Some(Primitive(value)) => value
    Some(Reference(_, _, _, _)) => raise TypeMismatch
    None => raise InvalidHandle
  }
}

///|
pub fn RootedValue::close(self : RootedValue) -> Unit {
  if self.state is Some(Reference(_, _roots, cleanup, _)) {
    cleanup.close()
  }
  self.state = None
  self.declared_type = None
}

///|
/// Low-level bridge from Store-local raw values. Raw reference indices must
/// originate in this Store; portable clients should use executor.Function results.
pub fn Store::root_raw_value(
  self : Store,
  value : @types.Value,
) -> RootedValue raise RuntimeError {
  self.ensure_open()
  match value {
    I32(_) | I64(_) | F32(_) | F64(_) | V128(_) | I31(_) | Null =>
      { declared_type: None, state: Some(Primitive(value)), }
    _ => {
      self.check_raw_reference(value)
      let roots = self.pin_gc_roots([value])
      self.on_instantiation_rollback(fn() { roots.release() })
      let cleanup = @jit_ffi.CleanupOwner::new(fn() { roots.release() })
      {
        declared_type: None,
        state: Some(Reference(self, roots, cleanup, value)),
      }
    }
  }
}

///|
/// Low-level execution bridge. Checks provenance and lease before revealing an index.
pub fn Store::borrow_rooted_value(
  self : Store,
  value : RootedValue,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  match value.state {
    Some(Primitive(value)) => value
    Some(Reference(owner, roots, _cleanup, value)) => {
      guard physical_equal(owner, self) else { raise ForeignStore }
      guard roots.active.val else { raise InvalidHandle }
      self.check_raw_reference(value)
      value
    }
    None => raise InvalidHandle
  }
}

///|
fn Store::check_raw_reference(
  self : Store,
  value : @types.Value,
) -> Unit raise RuntimeError {
  match value {
    FuncRef(address) => self.get_func_inst(address) |> ignore
    StructRef(index) | ArrayRef(index) =>
      if !self.is_gc_valid(index) {
        raise InvalidHandle
      }
    ExnRef(index) => self.get_exn(index) |> ignore
    ExternRef(index) => if index < 0 { self.unwrap_extern(value) |> ignore }
    ContRef(index) =>
      if !self.has_guest_continuation(index) {
        raise InvalidHandle
      }
    _ => ()
  }
}

///|
pub fn RootedValue::v128(bytes : Bytes) -> RootedValue raise RuntimeError {
  guard bytes.length() == 16 else { raise TypeMismatch }
  { declared_type: None, state: Some(Primitive(V128(bytes))), }
}

///|
/// Low-level result bridge: the caller guarantees the declared result contract.
pub fn Store::root_result_value(
  self : Store,
  instance : ModuleInstance,
  value : @types.Value,
  type_ : @types.ValueType,
) -> RootedValue raise RuntimeError {
  self.check_instance(instance)
  let rooted = self.root_raw_value(value)
  if value is ContRef(_) {
    rooted.declared_type = Some((instance, type_))
  }
  rooted
}

///|
/// Validate typed continuation transfer as well as Store/root identity.
pub fn Store::borrow_typed_rooted_value(
  self : Store,
  value : RootedValue,
  instance : ModuleInstance,
  expected : @types.ValueType,
) -> @types.Value raise RuntimeError {
  self.check_instance(instance)
  let raw = self.borrow_rooted_value(value)
  if raw is ContRef(_) {
    guard value.declared_type is Some((source, actual)) else {
      raise TypeMismatch
    }
    self.check_instance(source)
    guard @types.SubtypingContext::cross_module(
      source.types,
      instance.types,
      rec_groups1=source.type_rec_groups,
      rec_groups2=instance.type_rec_groups,
    ).value_type_subtype(actual, expected) else {
      raise TypeMismatch
    }
  }
  raw
}

///|
#cfg(target="native")
pub fn Store::has_guest_continuation(self : Store, handle : Int64) -> Bool {
  if self.closed.val {
    return false
  }
  if handle >= 0L {
    self.guest_continuations.contains(handle)
  } else {
    self.native_execution.continuations().is_live((handle << 1) | 1L)
  }
}
