///|
priv struct StoreFuncrefMappingOwner {
  registration : Int
  store_addr : Int
  func_ptr : Int64
} derive(Debug)

///|
/// One Store-local function address and its native executable pointer.
pub struct StoreFuncrefEntry {
  store_addr : Int
  func_ptr : Int64
} derive(Debug, Eq)

///|
pub fn StoreFuncrefEntry::StoreFuncrefEntry(
  store_addr~ : Int,
  func_ptr~ : Int64,
) -> StoreFuncrefEntry {
  { store_addr, func_ptr, }
}

///|
priv struct StoreFuncrefRegistry {
  store_to_ptr : Map[Int, Array[StoreFuncrefMappingOwner]]
  ptr_to_store : Map[Int64, Array[StoreFuncrefMappingOwner]]
  next_registration : Ref[Int]
} derive(Debug)

///|
struct StoreFuncrefRegistration {
  registry : StoreFuncrefRegistry
  registration : Int
  entries : Array[StoreFuncrefEntry]
  active : Ref[Bool]
}

///|
fn StoreFuncrefRegistry::new() -> StoreFuncrefRegistry {
  { store_to_ptr: Map([]), ptr_to_store: Map([]), next_registration: Ref(0), }
}

///|
fn remove_store_funcref_owner(
  owners : Array[StoreFuncrefMappingOwner],
  registration : Int,
) -> Unit {
  for i in 0..<owners.length() {
    if owners[i].registration == registration {
      owners.remove(i) |> ignore
      return
    }
  }
}

///|
fn StoreFuncrefRegistry::register(
  self : StoreFuncrefRegistry,
  entries : Array[StoreFuncrefEntry],
) -> StoreFuncrefRegistration {
  let registration = self.next_registration.val
  self.next_registration.val = registration + 1
  for entry in entries {
    let { store_addr, func_ptr, } = entry
    if store_addr < 0 || func_ptr == 0L {
      continue
    }
    let owner = { registration, store_addr, func_ptr, }
    match self.store_to_ptr.get(store_addr) {
      Some(owners) => owners.push(owner)
      None => self.store_to_ptr.set(store_addr, [owner])
    }
    match self.ptr_to_store.get(func_ptr) {
      Some(owners) => owners.push(owner)
      None => self.ptr_to_store.set(func_ptr, [owner])
    }
  }
  { registry: self, registration, entries, active: Ref(true), }
}

///|
pub fn StoreFuncrefRegistration::release(
  self : StoreFuncrefRegistration,
) -> Unit {
  if !self.active.val {
    return
  }
  self.active.val = false
  for entry in self.entries {
    let { store_addr, func_ptr, } = entry
    if self.registry.store_to_ptr.get(store_addr) is Some(owners) {
      remove_store_funcref_owner(owners, self.registration)
      if owners.is_empty() {
        self.registry.store_to_ptr.remove(store_addr)
      }
    }
    if self.registry.ptr_to_store.get(func_ptr) is Some(owners) {
      remove_store_funcref_owner(owners, self.registration)
      if owners.is_empty() {
        self.registry.ptr_to_store.remove(func_ptr)
      }
    }
  }
}

///|
fn StoreFuncrefRegistry::lookup_ptr(
  self : StoreFuncrefRegistry,
  store_addr : Int,
) -> Int64? {
  match self.store_to_ptr.get(store_addr) {
    Some(owners) if !owners.is_empty() =>
      Some(owners[owners.length() - 1].func_ptr)
    _ => None
  }
}

///|
fn StoreFuncrefRegistry::lookup_store_addr(
  self : StoreFuncrefRegistry,
  func_ptr : Int64,
) -> Int? {
  match self.ptr_to_store.get(func_ptr) {
    Some(owners) if !owners.is_empty() =>
      Some(owners[owners.length() - 1].store_addr)
    _ => None
  }
}

///|
fn StoreFuncrefRegistry::entries(
  self : StoreFuncrefRegistry,
) -> Array[StoreFuncrefEntry] {
  let entries : Array[StoreFuncrefEntry] = []
  for func_ptr, owners in self.ptr_to_store {
    if func_ptr != 0L && !owners.is_empty() {
      entries.push({
        store_addr: owners[owners.length() - 1].store_addr,
        func_ptr,
      })
    }
  }
  entries
}

///|
fn StoreFuncrefRegistry::clear(self : StoreFuncrefRegistry) -> Unit {
  self.store_to_ptr.clear()
  self.ptr_to_store.clear()
}

///|
pub fn Store::register_jit_funcrefs(
  self : Store,
  entries : Array[StoreFuncrefEntry],
) -> StoreFuncrefRegistration {
  self.funcref_registry.register(entries)
}

///|
pub fn Store::lookup_jit_funcref_ptr(self : Store, store_addr : Int) -> Int64? {
  self.funcref_registry.lookup_ptr(store_addr)
}

///|
pub fn Store::lookup_jit_funcref_store_addr(
  self : Store,
  func_ptr : Int64,
) -> Int? {
  self.funcref_registry.lookup_store_addr(func_ptr)
}

///|
pub fn Store::jit_funcref_entries(self : Store) -> Array[StoreFuncrefEntry] {
  self.funcref_registry.entries()
}
