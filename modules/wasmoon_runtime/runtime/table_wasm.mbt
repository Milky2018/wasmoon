///|
priv enum TableStorage {
  Managed(Array[@types.Value])
} derive(Debug)

///|
fn Table::storage_size(self : Table) -> Int32 {
  let Managed(elements) = self.storage
  elements.length()
}

///|
fn Table::read_element(self : Table, index : Int32) -> @types.Value {
  let Managed(elements) = self.storage
  elements[index]
}

///|
fn Table::root_at(
  self : Table,
  index : Int32,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  self.read_element(index)
}

///|
fn Table::write_element(
  self : Table,
  index : Int32,
  value : @types.Value,
) -> Unit {
  let Managed(elements) = self.storage
  elements[index] = value
}

///|
fn Table::fill_elements(
  self : Table,
  offset : Int32,
  length : Int32,
  value : @types.Value,
) -> Unit {
  let Managed(elements) = self.storage
  for i in offset..<(offset + length) {
    elements[i] = value
  }
}

///|
fn Table::copy_elements(
  self : Table,
  destination : Int32,
  source : Table,
  offset : Int32,
  length : Int32,
) -> Unit {
  let Managed(elements) = self.storage
  let Managed(source) = source.storage
  if destination <= offset {
    for i in 0..<length {
      elements[destination + i] = source[offset + i]
    }
  } else {
    for i = length - 1; i >= 0; i = i - 1 {
      elements[destination + i] = source[offset + i]
    }
  }
}

///|
fn Table::grow_storage(
  self : Table,
  delta : Int64,
  init : @types.Value,
  old_size : Int64,
  new_size : Int64,
) -> Int64 {
  if self.reservation is Some(reservation) && !reservation.resize(new_size) {
    return -1L
  }
  let Managed(elements) = self.storage
  for _ in 0..<delta.to_int() {
    elements.push(init)
  }
  old_size
}

///|
fn Table::close_storage(self : Table) -> Unit {
  self.storage = Managed([])
}
