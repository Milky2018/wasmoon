///|
/// The values definitely present in each physical location at a CFG point.
/// The allocator and VCode verifiers use the same transfer and join rules.
pub struct AllocationContents[V] {
  priv values : Map[(Int32, Int32), Array[V]]
}

///|
fn allocation_location_key(location : AllocationLocation) -> (Int32, Int32) {
  if location.is_register() {
    let reg = location.register_unchecked()
    match reg.class {
      Int => (0, reg.id)
      FpVector => (1, reg.id)
      Float => (1, reg.id)
      Vector => (2, reg.id)
    }
  } else {
    (3, location.spill_index_unchecked())
  }
}

///|
pub fn[V] AllocationContents::new() -> AllocationContents[V] {
  { values: Map([]), }
}

///|
pub fn[V] AllocationContents::copy(
  self : AllocationContents[V],
) -> AllocationContents[V] {
  let values : Map[(Int32, Int32), Array[V]] = Map([])
  for key, value in self.values {
    values[key] = value.copy()
  }
  { values, }
}

///|
pub fn[V : Eq] AllocationContents::equals(
  self : AllocationContents[V],
  other : AllocationContents[V],
) -> Bool {
  if self.values.length() != other.values.length() {
    return false
  }
  for key, values in self.values {
    guard other.values.get(key) is Some(other_values) else { return false }
    if values.length() != other_values.length() ||
      !values.all(value => other_values.contains(value)) {
      return false
    }
  }
  true
}

///|
pub fn[V : Eq] AllocationContents::meet_with(
  self : AllocationContents[V],
  other : AllocationContents[V],
) -> Unit {
  for key in self.values.keys().to_array() {
    match other.values.get(key) {
      None => self.values.remove(key)
      Some(other_values) => {
        let retained = self.values[key].filter(value => {
          other_values.contains(value)
        })
        if retained.is_empty() {
          self.values.remove(key)
        } else {
          self.values[key] = retained
        }
      }
    }
  }
}

///|
pub fn[V : Eq] AllocationContents::remove_value(
  self : AllocationContents[V],
  value : V,
) -> Unit {
  for key in self.values.keys().to_array() {
    self.values[key].retain(other => other != value)
    if self.values[key].is_empty() {
      self.values.remove(key)
    }
  }
}

///|
pub fn[V] AllocationContents::remove_register(
  self : AllocationContents[V],
  reg : PhysicalReg,
) -> Unit {
  self.values.remove(allocation_location_key(AllocationLocation::reg(reg)))
}

///|
pub fn[V : Eq] AllocationContents::contains(
  self : AllocationContents[V],
  value : V,
  location : AllocationLocation,
) -> Bool {
  self.values
  .get(allocation_location_key(location))
  .map(values => values.contains(value))
  .unwrap_or(false)
}

///|
pub fn[V] AllocationContents::set(
  self : AllocationContents[V],
  value : V,
  location : AllocationLocation,
) -> Unit {
  self.values[allocation_location_key(location)] = [value]
}

///|
/// Copy every alias of a location from the incoming state of a move.
pub fn[V] AllocationContents::copy_location_from(
  self : AllocationContents[V],
  source : AllocationContents[V],
  from : AllocationLocation,
  to : AllocationLocation,
) -> Unit {
  self.values[allocation_location_key(to)] = source.values[allocation_location_key(
    from,
  )].copy()
}

///|
/// Name an existing value at a block parameter's home after a parallel rename.
pub fn[V : Eq] AllocationContents::add_alias(
  self : AllocationContents[V],
  value : V,
  location : AllocationLocation,
) -> Unit {
  let key = allocation_location_key(location)
  match self.values.get(key) {
    Some(aliases) => if !aliases.contains(value) { aliases.push(value) }
    None => self.values[key] = [value]
  }
}
