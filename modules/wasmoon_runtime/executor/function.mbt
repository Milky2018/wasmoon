///|
/// A checked embedding function bound to its owning Store and instance.
/// Use RootedValue for reference arguments/results; raw Value APIs below this
/// boundary are Store-local interpreter/native integration seams.
pub struct Function {
  priv mut bound : BoundFunction?
}

///|
priv struct BoundFunction {
  store : @runtime.Store
  instance : @runtime.ModuleInstance
  index : Int32
  address : Int32
  lifetime : @runtime.FunctionIdentity
}

///|
pub fn Function::from_export(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
) -> Function raise @runtime.RuntimeError {
  store.check_instance(instance)
  guard find_export_by_name(instance.exports, name)
    is Some({ desc: Func(index), .. }) else {
    raise UndefinedElement
  }
  guard index >= 0 && index < instance.func_addrs.length() else {
    raise InvalidHandle
  }
  let address = instance.func_addrs[index]
  let lifetime = store.function_identity(address)
  { bound: Some({ store, instance, index, address, lifetime, }), }
}

///|
pub fn Function::close(self : Function) -> Unit {
  self.bound = None
}

///|
fn Function::binding(
  self : Function,
) -> BoundFunction raise @runtime.RuntimeError {
  guard self.bound is Some(bound) else { raise InvalidHandle }
  bound.store.check_instance(bound.instance)
  guard bound.instance.func_addrs.get(bound.index) is Some(address) &&
    address == bound.address &&
    bound.lifetime.is_live() else {
    raise InvalidHandle
  }
  bound
}

///|
pub fn Function::as_value(
  self : Function,
) -> @runtime.RootedValue raise @runtime.RuntimeError {
  let bound = self.binding()
  bound.store.root_raw_value(FuncRef(bound.instance.func_addrs[bound.index]))
}

///|
pub fn Function::call(
  self : Function,
  args : ArrayView[@runtime.RootedValue],
) -> Array[@runtime.RootedValue] raise @runtime.RuntimeError {
  let bound = self.binding()
  let signature = function_signature(bound.store, bound.instance, bound.index)
  guard args.length() == signature.params.length() else { raise TypeMismatch }
  let raw = args.mapi((index, value) => {
    bound.store.borrow_typed_rooted_value(
      value,
      bound.instance,
      signature.params[index],
    )
  })
  let lease = bound.store.pin_gc_roots(raw)
  defer lease.release()
  let results = call_func_by_index(
    bound.store,
    bound.instance,
    bound.index,
    raw,
  )
  root_function_results(bound.store, bound.instance, signature.results, results)
}

///|
pub async fn Function::call_async(
  self : Function,
  args : ArrayView[@runtime.RootedValue],
) -> Array[@runtime.RootedValue] raise @runtime.RuntimeError {
  let bound = self.binding()
  let signature = function_signature(bound.store, bound.instance, bound.index)
  guard args.length() == signature.params.length() else { raise TypeMismatch }
  let raw = args.mapi((index, value) => {
    bound.store.borrow_typed_rooted_value(
      value,
      bound.instance,
      signature.params[index],
    )
  })
  let lease = bound.store.pin_gc_roots(raw)
  defer lease.release()
  let results = call_func_by_index_async(
    bound.store,
    bound.instance,
    bound.index,
    raw,
  )
  root_function_results(bound.store, bound.instance, signature.results, results)
}

///|
fn root_function_results(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  types : ReadOnlyArray[@types.ValueType],
  values : Array[@types.Value],
) -> Array[@runtime.RootedValue] raise @runtime.RuntimeError {
  let transient = store.pin_gc_roots(values)
  defer transient.release()
  let roots : Array[@runtime.RootedValue] = []
  errdefer (for root in roots {
    root.close()
  })
  check_call_values(store, instance, values, types)
  for index, value in values {
    roots.push(store.root_result_value(instance, value, types[index]))
  }
  roots
}

///|
/// Validate raw embedding arguments before interpreter or native execution.
pub fn validate_call_arguments(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  index : Int32,
  args : Array[@types.Value],
) -> @types.FuncType raise @runtime.RuntimeError {
  store.check_instance(instance)
  let signature = function_signature(store, instance, index)
  check_call_values(store, instance, args, signature.params)
  signature
}

///|
fn check_call_values(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  values : Array[@types.Value],
  expected : ArrayView[@types.ValueType],
) -> Unit raise @runtime.RuntimeError {
  store.check_instance(instance)
  guard values.length() == expected.length() else { raise TypeMismatch }
  for index, value in values {
    let matches = match (value, expected[index]) {
      (I32(_), I32) | (I64(_), I64) | (F32(_), F32) | (F64(_), F64) => true
      (V128(bytes), V128) => bytes.length() == 16
      (ExnRef(reference), ExnRef) =>
        try {
          store.get_exn(reference) |> ignore
          true
        } catch {
          _ => false
        }
      (Null, target) => target.is_nullable()
      (ContRef(handle), target) =>
        store.has_guest_continuation(handle) &&
        target.is_continuation_ref() &&
        target != NullContRef &&
        target != RefNoCont
      (StructRef(reference), target) =>
        store.is_struct_reference(reference) &&
        (match target {
          StructRef | RefStructAbs | AnyRef | RefAny | RefEq | RefNullEq => true
          _ => value_matches_type(value, target, store, instance)
        })
      (ArrayRef(reference), target) =>
        store.is_array_reference(reference) &&
        (match target {
          ArrayRef | RefArrayAbs | AnyRef | RefAny | RefEq | RefNullEq => true
          _ => value_matches_type(value, target, store, instance)
        })
      (FuncRef(address), target) =>
        store.get_func_inst_opt(address) is Some(_) &&
        (match target {
          FuncRef | RefFunc => true
          RefFuncTyped(type_) | RefNullFuncTyped(type_) =>
            store.func_type_is_subtype(address, instance, type_)
          _ => false
        })
      _ => value_matches_type(value, expected[index], store, instance)
    }
    guard matches else { raise TypeMismatch }
  }
}

///|
fn function_signature(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  index : Int32,
) -> @types.FuncType raise @runtime.RuntimeError {
  guard instance.func_addrs.get(index) is Some(address) else {
    raise UndefinedElement
  }
  if instance.func_type_indices.get(index) is Some(type_index) {
    return instance.validated_func_type_at(type_index)
  }
  store.get_func_type(address)
}
