///|
/// Index existing records, not executable targets or type identities. Empty
/// slots are absent keys. Keep storage bounded even for sparse public input;
/// an empty index selects the existing sorted lookup.
#cfg(target="native")
fn store_interval_index(
  count : Int32,
  address_at : (Int32) -> Int32,
) -> (Int32, FixedArray[Int32]) {
  let mut first = 2147483647
  let mut last = -1
  let mut population = 0L
  for i in 0..<count {
    let address = address_at(i)
    if address >= 0 {
      if address < first {
        first = address
      }
      if address > last {
        last = address
      }
      population += 1L
    }
  }
  let span = last.to_int64() - first.to_int64() + 1L
  if population == 0L || span > 2147483647L || span > population * 2L {
    return (0, [])
  }
  let positions = FixedArray::make(span.to_int(), 0)
  for i in 0..<count {
    let address = address_at(i)
    if address >= 0 && positions[address - first] == 0 {
      // Preserve the first duplicate in the published sorted view.
      positions[address - first] = i + 1
    }
  }
  (first, positions)
}

///|
#cfg(target="wasm")
fn store_interval_index(
  _count : Int32,
  _address_at : (Int32) -> Int32,
) -> (Int32, FixedArray[Int32]) {
  (0, [])
}

///|
fn store_address(value : Int64) -> Int32 {
  if value <= 0L || (value & 0x7000000000000000L) != 0x3000000000000000L {
    return -1
  }
  let address = value & 0x0FFFFFFFFFFFFFFFL
  if address == 0L || address > 0x80000000L {
    -1
  } else {
    (address - 1L).to_int()
  }
}
