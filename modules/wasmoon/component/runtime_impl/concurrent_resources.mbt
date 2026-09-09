///|
/// Physical concurrent-resource slots shared by otherwise typed owner tables.
/// Capacity limits growth; slots freed before or after shrinking remain usable.
pub struct ConcurrentResources {
  priv closed : Ref[Bool]
  priv maximum : Ref[Int64]
  priv allocated : Ref[Int64]
  priv free : Array[Int64]
  priv live : Ref[Int64]
} derive(Debug)

///|
fn ConcurrentResources::new() -> ConcurrentResources {
  {
    closed: Ref(false),
    maximum: Ref(1000000L),
    allocated: Ref(0L),
    free: [],
    live: Ref(0L),
  }
}

///|
fn ConcurrentResources::set_capacity(
  self : ConcurrentResources,
  maximum : UInt,
) -> Unit {
  self.maximum.val = maximum.to_uint64().reinterpret_as_int64()
}

///|
struct ConcurrentResourceLease {
  pool : ConcurrentResources
  slot : Int64
  active : Ref[Bool]
} derive(Debug)

///|
fn ConcurrentResources::allocate(
  self : ConcurrentResources,
) -> ConcurrentResourceLease raise ComponentRuntimeError {
  if self.closed.val {
    raise Cancelled
  }
  let slot = match self.free.pop() {
    Some(slot) => slot
    None => {
      if self.allocated.val >= self.maximum.val {
        raise CanonCallError("resource table has no free keys")
      }
      let slot = self.allocated.val
      self.allocated.val += 1L
      slot
    }
  }
  self.live.val += 1L
  { pool: self, slot, active: Ref(true), }
}

///|
fn ConcurrentResourceLease::release(self : ConcurrentResourceLease) -> Unit {
  if !self.active.val {
    return
  }
  self.active.val = false
  self.pool.live.val -= 1L
  self.pool.free.push(self.slot)
}

///|
priv struct ConcurrentEntry[V] {
  lease : ConcurrentResourceLease
  mut value : V
}

///|
/// Owns typed entries and their shared capacity slots together.
pub struct ConcurrentMap[K, V] {
  priv pool : ConcurrentResources
  priv entries : Map[K, ConcurrentEntry[V]]
}

///|
fn[K : Hash + Eq, V] ConcurrentMap::new(
  pool : ConcurrentResources,
) -> ConcurrentMap[K, V] {
  { pool, entries: Map([]), }
}

///|
fn[K : Hash + Eq, V] ConcurrentMap::get(
  self : ConcurrentMap[K, V],
  key : K,
) -> V? {
  self.entries.get(key).map(entry => entry.value)
}

///|
fn[K : Hash + Eq, V] ConcurrentMap::set(
  self : ConcurrentMap[K, V],
  key : K,
  value : V,
) -> Unit raise ComponentRuntimeError {
  match self.entries.get(key) {
    Some(entry) => entry.value = value
    None => {
      let lease = self.pool.allocate()
      self.entries.set(key, { lease, value, })
    }
  }
}

///|
fn[K : Hash + Eq, V] ConcurrentMap::set_core(
  self : ConcurrentMap[K, V],
  key : K,
  value : V,
) -> Unit raise @runtime.RuntimeError {
  self.set(key, value) catch {
    error => trap_canon(canon_err_message(error))
  }
}

///|
/// Update an existing owner without performing an allocation.
fn[K : Hash + Eq, V] ConcurrentMap::replace(
  self : ConcurrentMap[K, V],
  key : K,
  value : V,
) -> Unit {
  self.entries.get(key).unwrap().value = value
}

///|
fn[K : Hash + Eq, V] ConcurrentMap::remove(
  self : ConcurrentMap[K, V],
  key : K,
) -> Unit {
  if self.entries.get(key) is Some(entry) {
    self.entries.remove(key)
    entry.lease.release()
  }
}

///|
fn[K, V] ConcurrentMap::clear(self : ConcurrentMap[K, V]) -> Unit {
  for _, entry in self.entries {
    entry.lease.release()
  }
  self.entries.clear()
}

///|
fn[K, V] ConcurrentMap::iter(self : ConcurrentMap[K, V]) -> Iter[(K, V)] {
  self.entries.iter().map(fn(entry) { (entry.0, entry.1.value) })
}

///|
fn[K, V] ConcurrentMap::iter2(self : ConcurrentMap[K, V]) -> Iter2[K, V] {
  Iter2(self.iter())
}

///|
impl[K : Hash + Eq + Debug, V : Debug] Debug for ConcurrentMap[K, V] with fn to_repr(
  self,
) {
  Repr(Map::from_iter(self.iter()))
}

///|
pub extend ConcurrentResources with @debug.Debug::{to_repr}

///|
pub extend ConcurrentResourceLease with @debug.Debug::{to_repr}

///|
pub fn[K, V] ConcurrentMap::length(self : ConcurrentMap[K, V]) -> Int {
  self.entries.length()
}
