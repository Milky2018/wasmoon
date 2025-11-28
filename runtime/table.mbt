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
