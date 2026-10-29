///|
/// Store-local callable identities, built and owned by MoonBit.
pub struct NativeCallableRegistry {
  priv view : NativeCallableView
  priv mut parents : FixedArray[Int32]
  priv mut addresses : FixedArray[Int64]
  priv mut identities : FixedArray[Int32]
  priv mut ordinals : FixedArray[Int32]
  priv mut store_origin : Int32
  priv mut store_positions : FixedArray[Int32]
}

///|
#deprecated
pub extend NativeCallableRegistry with Debug::{to_repr}

///|
pub impl Debug for NativeCallableRegistry with fn to_repr(_self) {
  Repr::literal("NativeCallableRegistry")
}

///|
pub fn NativeCallableRegistry::new() -> NativeCallableRegistry {
  {
    view: new_view(),
    parents: [],
    addresses: [],
    identities: [],
    ordinals: [],
    store_origin: 0,
    store_positions: [],
  }
}

///|
/// Native consumers retain this RC-managed view; it keeps its arrays alive.
pub fn NativeCallableRegistry::native_view(
  self : NativeCallableRegistry,
) -> NativeCallableView {
  self.view
}

///|
pub fn NativeCallableRegistry::clear(self : NativeCallableRegistry) -> Unit {
  self.parents = []
  self.addresses = []
  self.identities = []
  self.ordinals = []
  self.store_origin = 0
  self.store_positions = []
  publish(
    self.view,
    self.parents,
    0,
    self.addresses,
    self.identities,
    0,
    self.store_origin,
    self.store_positions,
  )
  self.replace_functions([], [])
}

///|
/// Replace Store metadata outside concurrent guest execution. Native consumers
/// share the typed arrays; they do not own an independent copy of the metadata.
/// The Bool result is retained for compatibility. Allocation uses MoonBit's
/// allocator, so there is no separately recoverable native allocation failure.
pub fn NativeCallableRegistry::replace(
  self : NativeCallableRegistry,
  parents : Array[Int32],
  entries : Array[(Int64, Int32)],
) -> Bool {
  let mut parents_changed = parents.length() != self.parents.length()
  if !parents_changed {
    for i, parent in parents {
      if parent != self.parents[i] {
        parents_changed = true
        break
      }
    }
  }
  let mut addresses_changed = entries.length() != self.addresses.length()
  if !addresses_changed {
    for i, ordinal in self.ordinals {
      if self.addresses[i] != entries[ordinal].0 {
        addresses_changed = true
        break
      }
    }
  }
  let new_parents = if parents_changed {
    FixedArray::makei(parents.length(), i => parents[i])
  } else {
    self.parents
  }
  if addresses_changed {
    let ordinals = FixedArray::makei(entries.length(), i => i)
    // An input-position tie-break preserves the original first-duplicate rule.
    ordinals.sort_by((a, b) => {
      let order = entries[a].0
        .reinterpret_as_uint64()
        .compare(entries[b].0.reinterpret_as_uint64())
      if order == 0 {
        a.compare(b)
      } else {
        order
      }
    })
    let addresses = FixedArray::makei(entries.length(), i => {
      entries[ordinals[i]].0
    })
    let identities = FixedArray::makei(entries.length(), i => {
      entries[ordinals[i]].1
    })
    self.addresses = addresses
    self.identities = identities
    self.ordinals = ordinals
    let (origin, positions) = store_interval_index(addresses.length(), i => {
      store_address(addresses[i])
    })
    self.store_origin = origin
    self.store_positions = positions
  } else {
    for i, ordinal in self.ordinals {
      self.identities[i] = entries[ordinal].1
    }
  }
  self.parents = new_parents
  if parents_changed || addresses_changed {
    publish(
      self.view,
      self.parents,
      self.parents.length(),
      self.addresses,
      self.identities,
      self.addresses.length(),
      self.store_origin,
      self.store_positions,
    )
  }
  true
}

///|
/// Function addresses in table storage stay Store-local across JIT registrations.
/// Both sorted views are retained by the native view, without a Store callback.
pub fn NativeCallableRegistry::replace_functions(
  self : NativeCallableRegistry,
  functions : Array[(Int32, Int64)],
  references : Array[(Int64, Int32)],
) -> Unit {
  functions.sort_by((a, b) => a.0.compare(b.0))
  references.sort_by((a, b) => {
    a.0.reinterpret_as_uint64().compare(b.0.reinterpret_as_uint64())
  })
  let stores = FixedArray::makei(functions.length(), i => functions[i].0)
  let (origin, positions) = store_interval_index(stores.length(), i => stores[i])
  publish_functions(
    self.view,
    stores,
    FixedArray::makei(functions.length(), i => functions[i].1),
    functions.length(),
    FixedArray::makei(references.length(), i => references[i].0),
    FixedArray::makei(references.length(), i => references[i].1),
    references.length(),
    origin,
    positions,
  )
}
