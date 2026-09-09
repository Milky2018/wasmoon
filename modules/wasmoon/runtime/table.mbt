///|
/// WebAssembly table for function references
struct Table {
  elem_type : @types.ValueType
  elements : Array[@types.Value]
  mut size : Int
  max : Int64?
  is_table64 : Bool // true for table64 (i64-indexed table)
} derive(Debug)

///|
pub fn Table::Table(
  elem_type : @types.ValueType,
  min : Int,
  max : Int?,
  init_value? : @types.Value = Null,
  is_table64? : Bool = false,
) -> Table raise RuntimeError {
  Table::allocate(
    elem_type,
    min.to_int64() & 0xFFFF_FFFFL,
    max.map(fn(value) { value.to_int64() & 0xFFFF_FFFFL }),
    init_value,
    is_table64,
  )
}

///|
fn Table::allocate(
  elem_type : @types.ValueType,
  min : Int64,
  max : Int64?,
  init_value : @types.Value,
  is_table64 : Bool,
) -> Table raise RuntimeError {
  // A native reference occupies one pointer-sized slot. Check multiplication
  // before narrowing to the backing MoonBit array's supported element count.
  if min.reinterpret_as_uint64() > 0x1FFF_FFFF_FFFF_FFFFUL {
    raise TableAllocationOverflow
  }
  if min > 0x7FFF_FFFFL {
    raise TableAllocationFailed
  }
  let size = min.to_int()
  let elements : Array[@types.Value] = []
  for _ in 0..<size {
    elements.push(init_value)
  }
  { elem_type, elements, size, max, is_table64, }
}

///|
/// Allocate a module table without narrowing its declared limits.
pub fn Table::from_type(
  ty : @types.TableType,
  init_value? : @types.Value = Null,
) -> Table raise RuntimeError {
  Table::allocate(
    ty.elem_type,
    ty.limits.min,
    ty.limits.max,
    init_value,
    ty.is_table64,
  )
}

///|
pub fn Table::get(self : Table, idx : Int) -> @types.Value raise RuntimeError {
  self.get_at(idx.to_int64() & 0xFFFF_FFFFL)
}

///|
fn Table::check_range(
  self : Table,
  offset : Int64,
  count : Int64,
) -> Unit raise RuntimeError {
  let size = self.size.to_int64()
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
  self.elements[idx.to_int()]
}

///|
pub fn Table::set(
  self : Table,
  idx : Int,
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
  self.elements[idx.to_int()] = value
}

///|
pub fn Table::size(self : Table) -> Int {
  self.size
}

///|
pub fn Table::grow(self : Table, delta : Int, init : @types.Value) -> Int {
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
  let old_size = self.size.to_uint64()
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
  // Actual tables use MoonBit arrays and signed 32-bit native size metadata.
  if new_size > 0x7FFF_FFFFUL {
    return -1L
  }
  for _ in self.size..<new_size.to_int() {
    self.elements.push(init)
  }
  self.size = new_size.to_int()
  old_size.reinterpret_as_int64()
}

///|
/// Fill a range of table elements with a value
/// table.fill: fill table[d..d+n] with value
pub fn Table::fill(
  self : Table,
  dest : Int,
  value : @types.Value,
  n : Int,
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
  self.check_range(dest, n)
  let dest = dest.to_int()
  for i in 0..<n.to_int() {
    self.elements[dest + i] = value
  }
}

///|
pub fn Table::copy_from(
  self : Table,
  dest : Int,
  src_table : Table,
  src : Int,
  n : Int,
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
  self.check_range(dest, n)
  src_table.check_range(src, n)
  let dest = dest.to_int()
  let src = src.to_int()
  let n = n.to_int()
  // Preserve memmove semantics when both handles refer to the same table.
  if dest <= src {
    for i in 0..<n {
      self.elements[dest + i] = src_table.elements[src + i]
    }
  } else {
    for i = n - 1; i >= 0; i = i - 1 {
      self.elements[dest + i] = src_table.elements[src + i]
    }
  }
}

///|
/// Get element type for type checking
pub fn Table::get_elem_type(self : Table) -> @types.ValueType {
  self.elem_type
}

///|
/// Get table limits (min, max) for type checking
pub fn Table::get_limits(self : Table) -> (Int, Int?) {
  (
    self.size,
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
  (self.size.to_int64(), self.max)
}
