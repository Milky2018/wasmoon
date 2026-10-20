///|
/// WebAssembly table with target-specific backing storage
struct Table {
  mut reservation : @jit_ffi.Reservation?
  mut binding : ResourceBinding?
  mut closed : Bool
  elem_type : @types.ValueType
  mut storage : TableStorage
  max : Int64?
  is_table64 : Bool // true for table64 (i64-indexed table)
} derive(Debug)

///|
pub fn Table::Table(
  elem_type : @types.ValueType,
  min : Int32,
  max : Int32?,
  init_value~ : @types.Value = Null,
  is_table64~ : Bool = false,
  resource_budget~ : ResourceBudget? = None,
) -> Table raise RuntimeError {
  Table::allocate(
    elem_type,
    min.to_int64() & 0xFFFF_FFFFL,
    max.map(fn(value) { value.to_int64() & 0xFFFF_FFFFL }),
    init_value,
    is_table64,
    resource_budget,
  )
}

///|
fn Table::allocate(
  elem_type : @types.ValueType,
  min : Int64,
  max : Int64?,
  init_value : @types.Value,
  is_table64 : Bool,
  resource_budget : ResourceBudget?,
) -> Table raise RuntimeError {
  if max is Some(maximum) &&
    maximum.reinterpret_as_uint64() < min.reinterpret_as_uint64() {
    raise InvalidTableType("maximum is below minimum")
  }
  // A native reference occupies one pointer-sized slot. Check multiplication
  // before narrowing to the backing MoonBit array's supported element count.
  if min.reinterpret_as_uint64() > 0x1FFF_FFFF_FFFF_FFFFUL {
    raise TableAllocationOverflow
  }
  if min > 0x7FFF_FFFFL {
    raise TableAllocationFailed
  }
  guard (match elem_type {
    I32 | I64 | F32 | F64 | V128 => false
    _ => true
  }) else {
    raise InvalidTableType("element type must be a reference type")
  }
  if min != 0L && !value_fits_kind(init_value, elem_type) {
    raise TypeMismatch
  }
  let reservation = resource_budget.map(budget => {
    budget.reservation(TableElements, min)
  })
  let size = min.to_int()
  let elements : Array[@types.Value] = []
  for _ in 0..<size {
    elements.push(init_value)
  }
  {
    elem_type,
    storage: Managed(elements),
    max,
    is_table64,
    binding: None,
    closed: false,
    reservation,
  }
}

///|
/// Allocate a module table without narrowing its declared limits.
pub fn Table::from_type(
  ty : @types.TableType,
  init_value~ : @types.Value = Null,
  resource_budget~ : ResourceBudget? = None,
) -> Table raise RuntimeError {
  Table::allocate(
    ty.elem_type,
    ty.limits.min,
    ty.limits.max,
    init_value,
    ty.is_table64,
    resource_budget,
  )
}

///|
pub fn Table::get(self : Table, idx : Int32) -> @types.Value raise RuntimeError {
  self.get_at(idx.to_int64() & 0xFFFF_FFFFL)
}

///|
fn Table::ensure_open(self : Table) -> Unit raise RuntimeError {
  check_resource_open(self.binding)
  guard !self.closed else { raise InvalidHandle }
}

///|
fn Table::check_range(
  self : Table,
  offset : Int64,
  count : Int64,
) -> Unit raise RuntimeError {
  self.ensure_open()
  let size = self.size().to_int64()
  if offset < 0L || count < 0L || count > size || offset > size - count {
    raise OutOfBoundsTableAccess
  }
}

///|
pub fn Table::get_at(
  self : Table,
  idx : Int64,
) -> @types.Value raise RuntimeError {
  self.check_range(idx, 1L)
  self.read_element(idx.to_int())
}

///|
pub fn Table::set(
  self : Table,
  idx : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.set_at(idx.to_int64() & 0xFFFF_FFFFL, value)
}

///|
pub fn Table::set_at(
  self : Table,
  idx : Int64,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.check_range(idx, 1L)
  guard value_fits_kind(value, self.elem_type) else { raise TypeMismatch }
  self.write_element(idx.to_int(), value)
}

///|
pub fn Table::size(self : Table) -> Int32 {
  self.storage_size()
}

///|
pub fn Table::grow(self : Table, delta : Int32, init : @types.Value) -> Int32 {
  let result = self.grow64(delta.to_int64() & 0xFFFF_FFFFL, init) catch {
    _ => -1L
  }
  result.to_int()
}

///|
/// Grow using an unsigned table64 count, preserving allocation failures.
pub fn Table::grow64(
  self : Table,
  delta : Int64,
  init : @types.Value,
) -> Int64 raise RuntimeError {
  self.ensure_open()
  guard value_fits_kind(init, self.elem_type) else { raise TypeMismatch }
  let old_size = self.size().to_uint64()
  if delta == 0L {
    return old_size.reinterpret_as_int64()
  }
  let new_size = old_size + delta.reinterpret_as_uint64()
  if new_size < old_size {
    return -1L
  }
  if self.max is Some(max) && new_size > max.reinterpret_as_uint64() {
    return -1L
  }
  if new_size > 0x1FFF_FFFF_FFFF_FFFFUL {
    raise TableAllocationFailed
  }
  if new_size > 0x7FFF_FFFFUL {
    return -1L
  }
  self.grow_storage(
    delta,
    init,
    old_size.reinterpret_as_int64(),
    new_size.reinterpret_as_int64(),
  )
}

///|
/// Fill a range of table elements with a value
/// table.fill: fill table[d..d+n] with value
pub fn Table::fill(
  self : Table,
  dest : Int32,
  value : @types.Value,
  n : Int32,
) -> Unit raise RuntimeError {
  self.fill_at(
    dest.to_int64() & 0xFFFF_FFFFL,
    value,
    n.to_int64() & 0xFFFF_FFFFL,
  )
}

///|
pub fn Table::fill_at(
  self : Table,
  dest : Int64,
  value : @types.Value,
  n : Int64,
) -> Unit raise RuntimeError {
  guard value_fits_kind(value, self.elem_type) else { raise TypeMismatch }
  self.check_range(dest, n)
  self.fill_elements(dest.to_int(), n.to_int(), value)
}

///|
pub fn Table::copy_from(
  self : Table,
  dest : Int32,
  src_table : Table,
  src : Int32,
  n : Int32,
) -> Unit raise RuntimeError {
  self.copy_from_at(
    dest.to_int64() & 0xFFFF_FFFFL,
    src_table,
    src.to_int64() & 0xFFFF_FFFFL,
    n.to_int64() & 0xFFFF_FFFFL,
  )
}

///|
pub fn Table::copy_from_at(
  self : Table,
  dest : Int64,
  src_table : Table,
  src : Int64,
  n : Int64,
) -> Unit raise RuntimeError {
  check_resource_copy(self.binding, src_table.binding)
  self.check_range(dest, n)
  src_table.check_range(src, n)
  self.copy_elements(dest.to_int(), src_table, src.to_int(), n.to_int())
}

///|
/// Get element type for type checking
pub fn Table::get_elem_type(self : Table) -> @types.ValueType {
  self.elem_type
}

///|
/// Get table limits (min, max) for type checking
pub fn Table::get_limits(self : Table) -> (Int32, Int32?) {
  (
    self.size(),
    match self.max {
      Some(max) if max.reinterpret_as_uint64() <= 0xFFFF_FFFFUL =>
        Some(max.to_int())
      _ => None
    },
  )
}

///|
/// Check if this is a table64 (i64-indexed table)
pub fn Table::is_table64(self : Table) -> Bool {
  self.is_table64
}

///|
/// Full declared limits for import compatibility and native growth checks.
pub fn Table::get_limits64(self : Table) -> (Int64, Int64?) {
  (self.size().to_int64(), self.max)
}

///|
pub fn Table::close(self : Table) -> Unit {
  self.closed = true
  if self.binding is Some(binding) {
    binding.active.val = false
  }
  self.close_storage()
  if self.reservation is Some(reservation) {
    reservation.close()
  }
  self.reservation = None
}

///|
#cfg(target="native")
priv enum TableStorage {
  Managed(Array[@types.Value])
  Native(NativeTableStorage)
} derive(Debug)

///|
#cfg(target="native")
priv struct NativeTableStorage {
  table : @native_bridge.JITTable
  references : StoreReferences
}

///|
#cfg(target="native")
impl Debug for NativeTableStorage with fn to_repr(_self) {
  Repr::literal("NativeTableStorage")
}

///|
#cfg(target="native")
fn Table::storage_size(self : Table) -> Int32 {
  match self.storage {
    Managed(elements) => elements.length()
    Native(storage) => storage.table.get_size()
  }
}

///|
#cfg(target="native")
fn Table::read_element(
  self : Table,
  index : Int32,
) -> @types.Value raise RuntimeError {
  match self.storage {
    Managed(elements) => elements[index]
    Native(storage) => {
      let native = storage.table.raw_ptr()
      let external = self.elem_type is ExternRef ||
        self.elem_type is RefExtern ||
        self.elem_type is NullExternRef
      let metadata = if external { native.word(index, 1).to_int() } else { -1 }
      let word = native.word(index, 0)
      let value = storage.references.decode_table_value(
        self.elem_type,
        metadata,
        word,
        false,
      )
      // Cache a wrapper created at this native-to-host boundary in the entry,
      // so later reads preserve identity without allocating another handle.
      if external && metadata < 0 && value is ExternRef(handle) && handle < 0 {
        storage.table.set(index, word, -1 - handle)
      }
      value
    }
  }
}

///|
#cfg(target="native")
fn Table::root_at(
  self : Table,
  index : Int32,
) -> @types.Value raise RuntimeError {
  match self.storage {
    Managed(elements) => elements[index]
    Native(storage) =>
      storage.references.decode_table_value(
        self.elem_type,
        storage.table.raw_ptr().word(index, 1).to_int(),
        storage.table.raw_ptr().word(index, 0),
        true,
      )
  }
}

///|
#cfg(target="native")
fn Table::write_element(
  self : Table,
  index : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  match self.storage {
    Managed(elements) => elements[index] = value
    Native(storage) => {
      let (type_index, word) = storage.references.encode_table_value(value)
      storage.table.set(index, word, type_index)
    }
  }
}

///|
#cfg(target="native")
fn Table::fill_elements(
  self : Table,
  offset : Int32,
  length : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if length == 0 {
    return
  }
  match self.storage {
    Managed(elements) =>
      for i in offset..<(offset + length) {
        elements[i] = value
      }
    Native(storage) => {
      let (metadata, word) = storage.references.encode_table_value(value)
      guard storage.table.raw_ptr().fill(offset, length, word, metadata) else {
        raise InvalidHandle
      }
    }
  }
}

///|
#cfg(target="native")
fn Table::copy_elements(
  self : Table,
  destination : Int32,
  source : Table,
  offset : Int32,
  length : Int32,
) -> Unit raise RuntimeError {
  if self.elem_type == source.elem_type &&
    self.storage is Native(target) &&
    source.storage is Native(origin) {
    guard target.table
      .raw_ptr()
      .copy_from(destination, origin.table.raw_ptr(), offset, length) else {
      raise InvalidHandle
    }
    return
  }
  if destination <= offset {
    for i in 0..<length {
      self.write_element(destination + i, source.read_element(offset + i))
    }
  } else {
    for i = length - 1; i >= 0; i = i - 1 {
      self.write_element(destination + i, source.read_element(offset + i))
    }
  }
}

///|
#cfg(target="native")
fn Table::grow_storage(
  self : Table,
  delta : Int64,
  init : @types.Value,
  old_size : Int64,
  new_size : Int64,
) -> Int64 raise RuntimeError {
  match self.storage {
    Managed(elements) => {
      if self.reservation is Some(reservation) && !reservation.resize(new_size) {
        return -1L
      }
      for _ in 0..<delta.to_int() {
        elements.push(init)
      }
    }
    Native(storage) => {
      if self.reservation is Some(reservation) && !reservation.resize(new_size) {
        return -1L
      }
      let created : Array[Int32] = []
      let mut committed = false
      defer (if !committed {
        for index in created {
          storage.references.release_native_exception(index)
        }
        if self.reservation is Some(reservation) {
          reservation.resize(old_size) |> ignore
        }
      })
      let (type_index, value) = storage.references.encode_table_value(
        init,
        created_exceptions=created,
      )
      let result = storage.table.raw_ptr().grow_value(delta, value, type_index)
      committed = result >= 0L
      return result
    }
  }
  old_size
}

///|
#cfg(target="native")
fn Table::close_storage(self : Table) -> Unit {
  if self.storage is Native(storage) {
    storage.table.raw_ptr().invalidate()
  }
  self.storage = Managed([])
}
