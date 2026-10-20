///|
/// WebAssembly table for function references
struct Table {
  mut reservation : @jit_ffi.Reservation?
  mut binding : ResourceBinding?
  mut closed : Bool
  elem_type : @types.ValueType
  elements : Array[@types.Value]
  mut size : Int32
  max : Int64?
  is_table64 : Bool // true for table64 (i64-indexed table)
} derive(Debug)

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
    elements,
    size,
    max,
    is_table64,
    binding: None,
    closed: false,
    reservation,
  }
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
  if self.reservation is Some(reservation) &&
    !reservation.resize(new_size.reinterpret_as_int64()) {
    return -1L
  }

  for _ in self.size..<new_size.to_int() {
    self.elements.push(init)
  }
  self.size = new_size.to_int()
  old_size.reinterpret_as_int64()
}

///|
pub fn Table::close(self : Table) -> Unit {
  self.closed = true
  if self.binding is Some(binding) {
    binding.active.val = false
  }
  self.elements.clear()
  self.elements.shrink_to_fit()
  self.size = 0
  if self.reservation is Some(reservation) {
    reservation.close()
  }
  self.reservation = None
}
