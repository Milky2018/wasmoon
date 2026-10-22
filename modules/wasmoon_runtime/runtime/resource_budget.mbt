///|
/// Units admitted by one explicitly shared embedding budget.
pub(all) enum ResourceKind {
  MemoryBytes
  TableElements
  GcBytes
  GcObjects
  Instances
  CodeBytes
  PendingWork
  InputBytes
  CompilationUnits
} derive(Debug, Eq)

///|
fn ResourceKind::index(self : ResourceKind) -> Int32 {
  match self {
    MemoryBytes => 0
    TableElements => 1
    GcBytes => 2
    GcObjects => 3
    Instances => 4
    CodeBytes => 5
    PendingWork => 6
    InputBytes => 7
    CompilationUnits => 8
  }
}

///|
/// Aggregate quotas shared by explicitly related Stores. Units are logical
/// resource sizes, not process RSS. A reservation survives its Store when an
/// independently retained native allocation still owns it.
pub struct ResourceBudget {
  priv quotas : FixedArray[@jit_ffi.Quota]
  compilation_depth : Int32
} derive(Debug)

///|
pub fn ResourceBudget::new(
  compilation_depth~ : Int32 = 512,
  memory_bytes~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  table_elements~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  gc_bytes~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  gc_objects~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  instances~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  code_bytes~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  pending_work~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  input_bytes~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
  compilation_units~ : Int64 = 0x7FFF_FFFF_FFFF_FFFFL,
) -> ResourceBudget raise RuntimeError {
  guard compilation_depth >= 0 else { raise InvalidResourceLimit }
  let limits = [
    memory_bytes, table_elements, gc_bytes, gc_objects, instances, code_bytes, pending_work,
    input_bytes, compilation_units,
  ]
  for limit in limits {
    guard limit >= 0L else { raise InvalidResourceLimit }
  }
  {
    quotas: FixedArray::makei(limits.length(), i => {
      @jit_ffi.Quota::new(limits[i])
    }),
    compilation_depth,
  }
}

///|
pub fn ResourceBudget::used(
  self : ResourceBudget,
  kind : ResourceKind,
) -> Int64 {
  self.quotas[kind.index()].used()
}

///|
/// A low-level native allocator capability. Callers must retain reservations
/// for the complete allocation lifetime; ordinary embedders use Store APIs.
pub fn ResourceBudget::native_quota(
  self : ResourceBudget,
  kind : ResourceKind,
) -> @jit_ffi.Quota {
  self.quotas[kind.index()]
}

///|
pub struct ResourceLease {
  priv reservation : @jit_ffi.Reservation
} derive(Debug)

///|
/// Reserve before side effects. Copies share one reservation and release once.
pub fn ResourceBudget::reserve(
  self : ResourceBudget,
  kind : ResourceKind,
  amount : Int64,
) -> ResourceLease raise RuntimeError {
  let reservation = @jit_ffi.Reservation::new(self.native_quota(kind), amount)
  guard reservation.valid() else { raise ResourceLimitExceeded(kind) }
  { reservation, }
}

///|
pub fn ResourceLease::release(self : ResourceLease) -> Unit {
  self.reservation.close()
}

///|
fn ResourceBudget::reservation(
  self : ResourceBudget,
  kind : ResourceKind,
  amount : Int64,
) -> @jit_ffi.Reservation raise RuntimeError {
  self.reserve(kind, amount).reservation
}

///|
pub extend ResourceKind with Debug::{to_repr}

///|
pub extend ResourceKind with Eq::{equal, not_equal}

///|
pub extend ResourceBudget with Debug::{to_repr}

///|
pub extend ResourceLease with Debug::{to_repr}

///|
#cfg(target="native")
fn Memory::bind_budget(
  self : Memory,
  budget : ResourceBudget,
) -> Unit raise RuntimeError {
  let descriptor = self.require_desc_ptr()
  let quota = budget.native_quota(MemoryBytes)
  match descriptor.matches_quota(quota) {
    1 => return
    -1 => raise ResourceLimitExceeded(MemoryBytes)
    _ => ()
  }
  let reservation = budget.reservation(MemoryBytes, self.byte_len())
  guard descriptor.bind_reservation(reservation) else { raise InvalidHandle }
}

///|
fn Table::bind_budget(
  self : Table,
  budget : ResourceBudget,
) -> Unit raise RuntimeError {
  let quota = budget.native_quota(TableElements)
  match self.reservation {
    Some(reservation) => {
      guard reservation.matches(quota) else {
        raise ResourceLimitExceeded(TableElements)
      }
    }
    None =>
      self.reservation = Some(
        budget.reservation(TableElements, self.size().to_int64()),
      )
  }
}

///|
#cfg(target="native")
fn Store::bind_gc_budget(
  self : Store,
  heap : @native_bridge.CHeap,
) -> Unit raise RuntimeError {
  if self.resource_budget is Some(budget) {
    let bytes = budget.reservation(GcBytes, 0L)
    let objects = budget.reservation(GcObjects, 0L)
    guard heap.get_ptr().bind_reservations(bytes, objects) else {
      raise InvalidHandle
    }
  }
}

///|
#cfg(target="native")
fn Store::gc_allocation_error(self : Store) -> RuntimeError {
  match self.references.native.c_heap {
    Some(heap) =>
      match heap.get_ptr().quota_denied() {
        1 => ResourceLimitExceeded(GcBytes)
        2 => ResourceLimitExceeded(GcObjects)
        _ => OutOfMemory
      }
    None => OutOfMemory
  }
}

///|
/// Admit the temporary representation before decoding/copying an array payload.
/// Release immediately before handing that payload to the heap allocator, which
/// performs the final admission. This bounds staging work, not process RSS.
#cfg(target="native")
pub fn Store::reserve_gc_array_work(
  self : Store,
  length : Int32,
) -> (ResourceLease, ResourceLease)? raise RuntimeError {
  self.ensure_open()
  guard length >= 0 && length <= (0x7FFF_FFFF - 32) / 16 else {
    raise AllocationTooLarge
  }
  if self.resource_budget is Some(budget) {
    let bytes = budget.reserve(GcBytes, 32L + length.to_int64() * 16L)
    errdefer bytes.release()
    let objects = budget.reserve(
      GcObjects,
      if self.references.native.c_heap is Some(_) ||
        self.heap.free_list.is_empty() {
        1L
      } else {
        0L
      },
    )
    Some((bytes, objects))
  } else {
    None
  }
}

///|
/// Allocate a repeated array without constructing an unadmitted temporary array.
#cfg(target="native")
pub fn Store::alloc_array_repeated(
  self : Store,
  type_idx : Int32,
  length : Int32,
  value : @types.Value,
  instance? : ModuleInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  guard length >= 0 && length <= (0x7FFF_FFFF - 32) / 16 else {
    raise AllocationTooLarge
  }
  if instance is Some(instance) {
    self.check_instance(instance)
  }
  let identity = self.allocation_type(instance, type_idx)
  let encoded = self.encode_heap_value(value)
  let reference = match self.references.native.c_heap {
    Some(heap) => {
      let runtime_type = self.allocation_layout(identity, array=true)
      heap.alloc_array(type_idx, length, encoded, runtime_type~) catch {
        OutOfMemory => raise self.gc_allocation_error()
        NullReference => raise NullReference
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
      }
    }
    None => self.heap.alloc_array_repeated(type_idx, length, value)
  }
  self.record_gc_type(reference, identity)
  reference
}

///|
fn MarkSweepHeap::alloc_array_repeated(
  self : MarkSweepHeap,
  type_idx : Int32,
  length : Int32,
  value : @types.Value,
) -> Int32 raise RuntimeError {
  self.admit_gc_object(32L + length.to_int64() * 16L)
  self.alloc_object(Array({ type_idx, elements: Array::make(length, value), }))
}

///|
/// Admission before instance initialization. A token belongs to one Store and
/// can be consumed once. Cancel unused tokens explicitly; native also releases
/// them through its last-owner finalizer.
pub struct InstanceAdmission {
  priv owner : Ref[Bool]
  priv consumed : Ref[Bool]
  priv mut lease : ResourceLease?
  priv mut compilation : ResourceLease?
  priv mut validated : @validator.ValidatedModule?
}

///|
pub fn Store::reserve_instance(
  self : Store,
  module_? : @types.Module,
) -> InstanceAdmission raise RuntimeError {
  self.ensure_open()
  let lease = self.resource_budget.map(budget => budget.reserve(Instances, 1L))
  errdefer (if lease is Some(lease) { lease.release() })
  let compilation = match (self.resource_budget, module_) {
    (Some(budget), Some(module_)) => Some(budget.admit_module(module_))
    _ => None
  }
  {
    owner: self.closed,
    consumed: Ref(false),
    lease,
    compilation,
    validated: None,
  }
}

///|
/// Return an unused admission, including when the caller retains the token.
pub fn InstanceAdmission::cancel(self : InstanceAdmission) -> Unit {
  self.consumed.val = true
  if self.lease is Some(lease) {
    lease.release()
  }
  self.lease = None
  if self.compilation is Some(lease) {
    lease.release()
  }
  self.compilation = None
  self.validated = None
}

///|
/// Admit Store-owned metadata. A failed instantiation returns its reservations
/// through the current transaction; committed metadata stays charged until close.
pub fn Store::reserve_retained_resource(
  self : Store,
  kind : ResourceKind,
  amount : Int64,
) -> Unit raise RuntimeError {
  self.ensure_open()
  if self.resource_budget is Some(budget) {
    let lease = budget.reserve(kind, amount)
    let index = self.instance_leases.length()
    self.instance_leases.push(lease)
    self.on_instantiation_rollback(fn() {
      lease.release()
      self.instance_leases.truncate(index)
      self.instance_leases.shrink_to_fit()
    })
  }
}

///|
/// Resize an explicitly owned work reservation before the next unit of work.
/// Failure preserves the previous charge. Closed reservations cannot be reused.
pub fn ResourceLease::resize(self : ResourceLease, amount : Int64) -> Bool {
  self.reservation.resize(amount)
}

///|
fn Store::release_auxiliary_handle(
  self : Store,
  kind : Int32,
  handle : Int64,
) -> Unit {
  self.references.release_auxiliary_handle(kind, handle)
}
