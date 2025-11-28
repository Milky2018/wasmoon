///|
/// WebAssembly table for function references
struct Table {
  elem_type : @wasmoon.ValueType
  elements : Array[@wasmoon.Value]
  mut size : Int
  max : Int?
} derive(Show)

///|
pub fn Table::new(
  elem_type : @wasmoon.ValueType,
  min : Int,
  max : Int?,
) -> Table {
  let elements : Array[@wasmoon.Value] = []
  for _ in 0..<min {
    elements.push(Null)
  }
  { elem_type, elements, size: min, max }
}

///|
pub fn Table::get(self : Table, idx : Int) -> @wasmoon.Value raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  let elem = self.elements[idx]
  match elem {
    Null => raise UninitializedElement
    _ => elem
  }
}

///|
pub fn Table::set(
  self : Table,
  idx : Int,
  value : @wasmoon.Value,
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
/// Get element without checking for uninitialized (for testing)
pub fn Table::get_element(
  self : Table,
  idx : Int,
) -> @wasmoon.Value raise RuntimeError {
  if idx < 0 || idx >= self.size {
    raise OutOfBoundsTableAccess
  }
  self.elements[idx]
}

///|
pub fn Table::grow(self : Table, delta : Int, init : @wasmoon.Value) -> Int {
  let old_size = self.size
  let new_size = old_size + delta

  // Check max limit
  match self.max {
    Some(max) => if new_size > max { return -1 }
    None => ()
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
  value : @wasmoon.Value,
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
