///|
/// An explicitly catchable guest exception with owned payload roots.
/// `throw_into_guest` transfers this one-shot handle to the invocation. Close discarded
/// handles explicitly on wasm (native RC also retires their root owner).
pub struct GuestException {
  priv mut state : HostExceptionState?
}

///|
priv struct HostExceptionState {
  binding : ResourceBinding
  tag : Int32
  values : Array[@types.Value]
  roots : GcRootLease
  owned : Ref[Bool]
  cleanup : @jit_ffi.CleanupOwner
}

///|
/// A transport signal, distinct from ordinary RuntimeError and engine traps.
pub(all) suberror HostGuestException {
  HostThrows(GuestException)
} derive(Debug)

///|
pub impl Debug for GuestException with fn to_repr(_self) {
  Repr::literal("<guest-exception>")
}

///|
pub extend GuestException with Debug::{to_repr}

///|
pub extend HostGuestException with Debug::{to_repr}

///|
pub fn HostGuestException::from_error(error : Error) -> GuestException? {
  match error {
    HostThrows(exception) => Some(exception)
    _ => None
  }
}

///|
pub fn GuestException::close(self : GuestException) -> Unit {
  if self.state is Some(state) {
    state.cleanup.close()
  }
  self.state = None
}

///|
/// Move the payload owner into the signal before host defers run. Closing an
/// alias of the original handle while unwinding therefore cannot unroot it.
pub fn[T] GuestException::throw_into_guest(
  self : GuestException,
) -> T raise HostGuestException {
  let state = self.state
  self.state = None
  raise HostThrows({ state, })
}

///|
/// Create a new exception for a Store-local tag address. Rooted inputs check
/// reference provenance; relative concrete types use the tag's owning module.
pub fn Store::guest_exception(
  self : Store,
  tag : Int32,
  payload : ArrayView[RootedValue],
) -> GuestException raise RuntimeError {
  let signature = self.get_tag_type(tag)
  guard self.tag_lifetimes.get(tag) is Some(active) && active.val else {
    raise InvalidHandle
  }
  guard payload.length() == signature.params.length() else {
    raise TypeMismatch
  }
  let owner = self.get_tag_owner(tag)
  let values = payload.mapi((index, root) => {
    self.exception_payload_value(root, signature.params[index], owner)
  })
  let roots = self.pin_gc_roots(values)
  let owned = Ref(true)
  let cleanup = @jit_ffi.CleanupOwner::new(fn() {
    if owned.val {
      owned.val = false
      roots.release()
    }
  })
  // Match rooted host handles until handoff. Once an executor owns the lease,
  // its live guest roots and normal invocation cleanup govern that lifetime.
  self.on_instantiation_rollback(fn() { if owned.val { cleanup.close() } })
  {
    state: Some({
      binding: { store: self.closed, active, },
      tag,
      values,
      roots,
      owned,
      cleanup,
    }),
  }
}

///|
fn Store::exception_payload_value(
  self : Store,
  root : RootedValue,
  expected : @types.ValueType,
  owner : ModuleInstance?,
) -> @types.Value raise RuntimeError {
  let value = match owner {
    Some(instance) => self.borrow_typed_rooted_value(root, instance, expected)
    None => self.borrow_rooted_value(root)
  }
  guard value_fits_kind(value, expected) else { raise TypeMismatch }
  match expected {
    RefStruct(index) | RefNullStruct(index) if index >= 0 => {
      guard owner is Some(instance) &&
        instance.types.get(index) is Some({ composite: Struct(_), .. }) else {
        raise TypeMismatch
      }
      if value is StructRef(reference) &&
        !self.gc_type_is_subtype(reference, instance, index) {
        raise TypeMismatch
      }
    }
    RefArray(index) | RefNullArray(index) if index >= 0 => {
      guard owner is Some(instance) &&
        instance.types.get(index) is Some({ composite: Array(_), .. }) else {
        raise TypeMismatch
      }
      if value is ArrayRef(reference) &&
        !self.gc_type_is_subtype(reference, instance, index) {
        raise TypeMismatch
      }
    }
    RefFuncTyped(index) | RefNullFuncTyped(index) => {
      guard owner is Some(instance) &&
        instance.types.get(index) is Some({ composite: Func(_), .. }) else {
        raise TypeMismatch
      }
      if value is FuncRef(address) &&
        !self.func_type_is_subtype(address, instance, index) {
        raise TypeMismatch
      }
    }
    RefContTyped(index) | RefNullContTyped(index) => {
      guard owner is Some(instance) &&
        instance.types.get(index) is Some({ composite: Cont(_), .. }) else {
        raise TypeMismatch
      }
    }
    _ => ()
  }
  value
}

///|
/// Execution bridge: consume a validated signal and transfer its root lease.
/// The caller must release the lease after guest roots incorporate the payload,
/// or on failure/cancellation. Invalid deliveries close their payload owner.
pub fn Store::take_guest_exception(
  self : Store,
  exception : GuestException,
) -> (Int32, Array[@types.Value], GcRootLease) raise RuntimeError {
  errdefer exception.close()
  self.ensure_open()
  guard exception.state is Some(state) else { raise InvalidHandle }
  guard physical_equal(state.binding.store, self.closed) else {
    raise ForeignStore
  }
  check_resource_open(Some(state.binding))
  guard state.roots.active.val else { raise InvalidHandle }
  self.get_tag_type(state.tag) |> ignore
  exception.state = None
  state.owned.val = false
  state.cleanup.close()
  (state.tag, state.values, state.roots)
}

///|
/// Register a host callback that can explicitly throw HostGuestException.
/// Ordinary RuntimeError and unrelated errors remain invocation failures.
pub fn Store::alloc_throwing_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise Error,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  self.alloc_throwing_host_func_with_caller(
    (_, args) => func(args),
    func_type~,
    type_idx~,
  )
}

///|
pub fn Store::alloc_throwing_host_func_with_caller(
  self : Store,
  func : ThrowingHostFunction,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  self.alloc_func_inst(ThrowingHostFunc(func), func_type, type_idx, HostFunc)
}

///|
pub fn normalize_host_error(error : Error) -> RuntimeError {
  RuntimeError::from_error(error).unwrap_or_else(() => {
    HostCallbackError(error.to_string())
  })
}

///|
/// Synchronous execution bridge. A thrown payload owns a root lease until the
/// interpreter/native caller incorporates it into guest roots or abandons it.
pub(all) enum HostCallOutcome {
  HostCallReturned(Array[@types.Value])
  HostCallThrown(Int32, Array[@types.Value], GcRootLease)
  HostCallFailed(RuntimeError)
} derive(Debug)

///|
pub extend HostCallOutcome with Debug::{to_repr}

///|
pub fn FuncInst::invoke_sync_host(
  self : FuncInst,
  caller : Caller,
  args : Array[@types.Value],
) -> HostCallOutcome {
  match self {
    HostFunc(func) =>
      HostCallReturned(func(caller, args)) catch {
        error => HostCallFailed(error)
      }
    ThrowingHostFunc(func) =>
      HostCallReturned(func(caller, args)) catch {
        error =>
          if HostGuestException::from_error(error) is Some(exception) {
            let (tag, values, roots) = caller
              .store()
              .take_guest_exception(exception) catch {
                error => return HostCallFailed(error)
              }
            HostCallThrown(tag, values, roots)
          } else {
            HostCallFailed(normalize_host_error(error))
          }
      }
    WasmFunc(_) | AsyncHostFunc(_) => HostCallFailed(TypeMismatch)
  }
}
