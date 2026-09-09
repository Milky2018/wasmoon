///|
/// Bound host allocations while snapshotting a guest's asynchronous payload.
/// The default matches the pinned Wasmtime component hostcall budget (128 MiB).
priv struct CanonicalCopyBudget {
  remaining : Ref[Int64]
}

///|
fn CanonicalCopyBudget::new(limit? : Int64 = 134217728L) -> CanonicalCopyBudget {
  { remaining: Ref(limit), }
}

///|
fn CanonicalCopyBudget::consume(
  self : CanonicalCopyBudget,
  count : Int,
  unit_size : Int,
) -> Unit raise ComponentRuntimeError {
  let cost = count.to_int64() * unit_size.to_int64()
  if count < 0 || unit_size < 0 || cost > self.remaining.val {
    raise CanonCallError(
      "too much data is being copied between the host and the guest: fuel allocated for hostcalls has been exhausted",
    )
  }
  self.remaining.val -= cost
}
