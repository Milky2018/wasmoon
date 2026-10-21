///|
priv struct StoreReferences {
  resource_budget : ResourceBudget?
  closed : Ref[Bool]
  tags : Array[@types.FuncType]
  heap : MarkSweepHeap
  funcref_registry : StoreFuncrefRegistry
  native : NativeReferenceState
  mut instantiation : RollbackRegistrar?
  mut next_exception : Int32
  mut next_wrapped_extern : Int32
  mut exns : Map[Int32, ExnInstance]
  mut wrapped_externs : Map[Int32, @types.Value]
  auxiliary_leases : Map[(Int32, Int64), (ResourceLease, ResourceLease)]
} derive(Debug)

///|
fn StoreReferences::new(
  resource_budget : ResourceBudget?,
  closed : Ref[Bool],
  tags : Array[@types.FuncType],
  heap : MarkSweepHeap,
  funcref_registry : StoreFuncrefRegistry,
  native : NativeReferenceState,
) -> StoreReferences {
  {
    resource_budget,
    closed,
    tags,
    heap,
    funcref_registry,
    native,
    instantiation: None,
    next_exception: 0,
    next_wrapped_extern: 0,
    exns: Map([]),
    wrapped_externs: Map([]),
    auxiliary_leases: Map([]),
  }
}

///|
fn StoreReferences::ensure_open(
  self : StoreReferences,
) -> Unit raise RuntimeError {
  if self.closed.val {
    raise StoreClosed
  }
}

///|
fn StoreReferences::on_instantiation_rollback(
  self : StoreReferences,
  rollback : () -> Unit,
) -> Unit {
  if self.instantiation is Some(registrar) {
    registrar.on_rollback(rollback)
  }
}

///|
fn StoreReferences::wrap_as_extern(
  self : StoreReferences,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  if self.next_wrapped_extern == 2147483647 {
    raise AllocationTooLarge
  }
  self.reserve_auxiliary_handle(0, self.next_wrapped_extern.to_int64(), 16L)
  let idx = self.next_wrapped_extern
  self.next_wrapped_extern += 1
  self.wrapped_externs.set(idx, value)
  self.on_instantiation_rollback(fn() {
    self.wrapped_externs.remove(idx)
    self.release_auxiliary_handle(0, idx.to_int64())
  })
  ExternRef(-1 - idx) // -1 for index 0, -2 for index 1, etc.
}

///|
fn StoreReferences::unwrap_extern(
  self : StoreReferences,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  match value {
    ExternRef(idx) =>
      if idx < 0 {
        // Wrapped internal value
        let wrapped_idx = -1 - idx
        match self.wrapped_externs.get(wrapped_idx) {
          Some(value) => value
          None => raise UndefinedElement
        }
      } else {
        // Host externref - return as-is (it's already an internal representation)
        value
      }
    Null => Null
    _ => value
  }
}

///|
fn StoreReferences::alloc_exn(
  self : StoreReferences,
  tag_addr : Int32,
  values : Array[@types.Value],
) -> Int32 raise RuntimeError {
  self.ensure_open()
  if self.next_exception == 2147483647 {
    raise AllocationTooLarge
  }
  self.reserve_auxiliary_handle(
    1,
    self.next_exception.to_int64(),
    16L + values.length().to_int64() * 16L,
  )
  let index = self.next_exception
  self.next_exception += 1
  self.exns.set(index, { tag_addr, values: values.copy(), })
  self.record_exception_allocation(index)
  index
}

///|
fn StoreReferences::get_exn(
  self : StoreReferences,
  idx : Int32,
) -> ExnInstance raise RuntimeError {
  self.ensure_open()
  match self.exns.get(idx) {
    Some(exception) => { ..exception, values: exception.values.copy(), }
    None => raise UndefinedElement
  }
}

///|
#cfg(target="native")
fn StoreReferences::get_tag_type(
  self : StoreReferences,
  idx : Int32,
) -> @types.FuncType raise RuntimeError {
  self.ensure_open()
  if idx < 0 || idx >= self.tags.length() {
    raise UndefinedElement
  }
  self.tags[idx]
}

///|
fn StoreReferences::reserve_auxiliary_handle(
  self : StoreReferences,
  kind : Int32,
  handle : Int64,
  size : Int64,
) -> Unit raise RuntimeError {
  if self.resource_budget is Some(budget) {
    let bytes = budget.reserve(GcBytes, size)
    errdefer bytes.release()
    let objects = budget.reserve(GcObjects, 1L)
    self.auxiliary_leases.set((kind, handle), (bytes, objects))
  }
}

///|
#cfg(target="native")
fn StoreReferences::release_auxiliary_handle(
  self : StoreReferences,
  kind : Int32,
  handle : Int64,
) -> Unit {
  self.auxiliary_leases.remove((kind, handle))
}

///|
#cfg(target="wasm")
fn StoreReferences::release_auxiliary_handle(
  self : StoreReferences,
  kind : Int32,
  handle : Int64,
) -> Unit {
  if self.auxiliary_leases.get((kind, handle)) is Some((bytes, objects)) {
    bytes.release()
    objects.release()
  }
  self.auxiliary_leases.remove((kind, handle))
}
