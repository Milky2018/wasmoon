///|
/// Delivery at a guest suspension point, including exception injection.
pub(all) enum GuestContinuationInput {
  Values(Array[@types.Value])
  Exception(Int32, Array[@types.Value])
} derive(Debug)

///|
/// Engine-owned execution state. The Store owns its cancellation capability.
pub struct GuestContinuationBody {
  run : (GuestContinuationInput) -> Array[@types.Value] raise
  cancel : () -> Unit
  priv roots : Array[@types.Value]
  priv leases : Array[GcRootLease]
}

///|
pub fn GuestContinuationBody::new(
  run : (GuestContinuationInput) -> Array[@types.Value] raise Error,
  cancel : () -> Unit,
  roots~ : Array[@types.Value] = [],
  leases~ : Array[GcRootLease] = [],
) -> GuestContinuationBody {
  let unique_roots : Array[@types.Value] = []
  let seen : Map[(Int32, Int64), Bool] = Map([])
  for value in roots {
    if gc_root_key(value) is Some(key) && !seen.contains(key) {
      seen.set(key, true)
      unique_roots.push(value)
    }
  }
  for lease in leases {
    for value in lease.snapshot() {
      if gc_root_key(value) is Some(key) && !seen.contains(key) {
        seen.set(key, true)
        unique_roots.push(value)
      }
    }
  }
  let roots = unique_roots
  { run, cancel, roots, leases: leases.copy(), }
}

///|
/// Retained reference roots of an engine-owned continuation.
pub fn GuestContinuationBody::gc_roots(
  self : GuestContinuationBody,
) -> Array[@types.Value] {
  self.roots.copy()
}

///|
pub impl Debug for GuestContinuationBody with fn to_repr(_self) {
  Repr::literal("<guest-continuation>")
}

///|
pub fn Store::put_guest_continuation(
  self : Store,
  body : GuestContinuationBody,
) -> Int64 raise RuntimeError {
  self.ensure_open()
  errdefer (body.cancel)()
  errdefer (for lease in body.leases {
    lease.release()
  })
  guard self.next_guest_continuation < 0x7FFF_FFFF_FFFF_FFFFL else {
    raise AllocationTooLarge
  }
  let pending = self.resource_budget.map(budget => {
    budget.reserve(PendingWork, 1L)
  })
  let handle = self.next_guest_continuation
  self.next_guest_continuation += 1L
  let leases = body.leases.copy()
  let covered : Map[(Int32, Int64), Bool] = Map([])
  for lease in leases {
    for value in lease.snapshot() {
      if gc_root_key(value) is Some(key) {
        covered.set(key, true)
      }
    }
  }
  let unprotected = body.roots.filter(value => {
    match gc_root_key(value) {
      Some(key) => !covered.contains(key)
      None => false
    }
  })
  if !unprotected.is_empty() {
    leases.push(self.pin_gc_roots(unprotected))
  }
  for lease in leases {
    lease.delegate_to_guest()
  }
  let active = Ref(true)
  let owned : GuestContinuationBody = {
    roots: body.roots,
    leases,
    run: fn(input) raise {
      if !active.val {
        raise ContinuationAlreadyConsumed
      }
      active.val = false
      let roots = body.roots.copy()
      let values = match input {
        Values(values) | Exception(_, values) => values
      }
      for value in values {
        roots.push(value)
      }
      defer (if pending is Some(lease) { lease.release() })
      errdefer (body.cancel)()
      defer (for lease in leases {
        lease.release()
      })
      let lease = self.pin_gc_roots(roots)
      defer lease.release()
      (body.run)(input)
    },
    cancel: fn() {
      if active.val {
        active.val = false
        defer (if pending is Some(lease) { lease.release() })
        defer (for lease in leases {
          lease.release()
        })
        (body.cancel)()
      }
    },
  }
  self.guest_continuations.set(handle, owned)
  self.on_instantiation_rollback(fn() {
    self.guest_continuations.remove(handle)
    (owned.cancel)()
  })
  handle
}

///|
/// Consume before executing or rebinding. Handles are never reused in a Store.
/// The returned body owns its roots until run or cancel; the caller must finish
/// one of those operations, or transfer its leases to a rebound body.
pub fn Store::take_guest_continuation(
  self : Store,
  handle : Int64,
) -> GuestContinuationBody raise RuntimeError {
  self.ensure_open()
  guard self.guest_continuations.get(handle) is Some(body) else {
    raise ContinuationAlreadyConsumed
  }
  self.guest_continuations.remove(handle)
  for lease in body.leases {
    lease.retain_for_host()
  }
  body
}

///|
pub(all) enum GuestContinuationEffect {
  Suspend(Int32, Array[@types.Value])
  Switch(Int32, GuestContinuationBody, Array[@types.Value])
} derive(Debug)

///|
pub(all) suberror GuestContinuationSignal {
  GuestContinuationYield(GuestContinuationEffect, GuestContinuationBody)
} derive(Debug)

///|
pub extend GuestContinuationInput with Debug::{to_repr}

///|
pub extend GuestContinuationBody with Debug::{to_repr}

///|
pub extend GuestContinuationEffect with Debug::{to_repr}

///|
pub extend GuestContinuationSignal with Debug::{to_repr}

///|
/// Transfer root leases together with engine state when rebinding a body.
pub fn GuestContinuationBody::gc_root_leases(
  self : GuestContinuationBody,
) -> Array[GcRootLease] {
  self.leases.copy()
}
