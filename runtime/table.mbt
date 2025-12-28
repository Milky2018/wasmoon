///|
/// WebAssembly table for function references
struct Table {
  elem_type : @types.ValueType
  elements : Array[@types.Value]
  mut size : Int
  max : Int?
  is_table64 : Bool // true for table64 (i64-indexed table)
} derive(Show)

///|
pub fn Table::new(
  elem_type : @types.ValueType,
  min : Int,
  max : Int?,
  init_value? : @types.Value = @types.Value::Null,
  is_table64? : Bool = false,
) -> Table {
  let elements : Array[@types.Value] = []
  for _ in 0..<min {
    elements.push(init_value)
  }
  { elem_type, elements, size: min, max, is_table64 }
}

///|
pub fn Table::get(self : Table, idx : Int) -> @types.Value raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  self.elements[idx]
}

///|
pub fn Table::set(
  self : Table,
  idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  self.elements[idx] = value
}

///|
pub fn Table::size(self : Table) -> Int {
  self.size
}

///|
pub fn Table::grow(self : Table, delta : Int, init : @types.Value) -> Int {
  let old_size = self.size
  // Use unsigned arithmetic to check for overflow (i32 range)
  let old_size_u = old_size.reinterpret_as_uint()
  let delta_u = delta.reinterpret_as_uint()
  let new_size_u = old_size_u + delta_u
  // If overflow occurred, the result will be less than old_size
  if new_size_u < old_size_u {
    return -1
  }
  let new_size = new_size_u.reinterpret_as_int()

  // Check max limit
  if self.max is Some(max) && new_size > max {
    return -1
  }

  // Grow the table
  for _ in 0..<delta {
    self.elements.push(init)
  }
  self.size = new_size
  old_size
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
  if dest < 0 || n < 0 || dest + n > self.size {
    raise OutOfBoundsTableAccess
  }
  for i in 0..<n {
    self.elements[dest + i] = value
  }
}

///|
/// Copy elements from source table to this table
/// table.copy: copy src_table[s..s+n] to this_table[d..d+n]
pub fn Table::copy_from(
  self : Table,
  dest : Int,
  src_table : Table,
  src : Int,
  n : Int,
) -> Unit raise RuntimeError {
  if dest < 0 ||
    src < 0 ||
    n < 0 ||
    dest + n > self.size ||
    src + n > src_table.size {
    raise OutOfBoundsTableAccess
  }
  // Handle overlapping regions correctly
  if dest <= src {
    // Copy forward
    for i in 0..<n {
      self.elements[dest + i] = src_table.elements[src + i]
    }
  } else {
    // Copy backward to handle overlap
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
  (self.size, self.max)
}

///|
/// Check if this is a table64 (i64-indexed table)
pub fn Table::is_table64(self : Table) -> Bool {
  self.is_table64
}
