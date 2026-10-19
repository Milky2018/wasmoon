///|
/// Store identity without retaining the Store or creating an ownership cycle.
priv struct ResourceBinding {
  store : Ref[Bool]
  active : Ref[Bool]
} derive(Debug)

///|
fn check_resource_open(binding : ResourceBinding?) -> Unit raise RuntimeError {
  if binding is Some(binding) {
    if binding.store.val {
      raise StoreClosed
    }
    if !binding.active.val {
      raise InvalidHandle
    }
  }
}

///|
fn resource_binding(
  owner : ResourceBinding?,
  store : Ref[Bool],
) -> ResourceBinding raise RuntimeError {
  check_resource_open(owner)
  if owner is Some(owner) {
    guard physical_equal(owner.store, store) else { raise ForeignStore }
    owner
  } else {
    { store, active: Ref(true), }
  }
}

///|
fn check_resource_copy(
  destination : ResourceBinding?,
  source : ResourceBinding?,
) -> Unit raise RuntimeError {
  check_resource_open(destination)
  check_resource_open(source)
  match (destination, source) {
    (Some(destination), Some(source)) =>
      if !physical_equal(destination.store, source.store) {
        raise ForeignStore
      }
    (None, None) => ()
    _ => raise InvalidHandle
  }
}

///|
/// Shape checks at raw host mutation seams. Concrete reference subtyping is
/// checked with Store type graphs at validated Wasm and rooted-value boundaries.
fn value_fits_kind(value : @types.Value, type_ : @types.ValueType) -> Bool {
  match (value, type_) {
    (I32(_), I32) | (I64(_), I64) | (F32(_), F32) | (F64(_), F64) => true
    (V128(bytes), V128) => bytes.length() == 16
    (Null, type_) => type_.is_nullable()
    (FuncRef(_), FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_)) =>
      true
    (ExternRef(_), ExternRef | RefExtern | AnyRef | RefAny) => true
    (ExnRef(_), ExnRef) => true
    (ContRef(_), ContRef | RefCont | RefContTyped(_) | RefNullContTyped(_)) =>
      true
    (
      StructRef(_),
      StructRef
      | RefStructAbs
      | RefStruct(_)
      | RefNullStruct(_)
      | AnyRef
      | RefAny
      | RefEq
      | RefNullEq,
    ) => true
    (
      ArrayRef(_),
      ArrayRef
      | RefArrayAbs
      | RefArray(_)
      | RefNullArray(_)
      | AnyRef
      | RefAny
      | RefEq
      | RefNullEq,
    ) => true
    (I31(_), RefI31 | RefNullI31 | RefEq | RefNullEq | AnyRef | RefAny) => true
    _ => false
  }
}
