///|
pub fn choose_fixed_reg_hint(
  available_regs : Array[@regalloc.PhysicalReg],
  fixed_regs : Array[@regalloc.PhysicalReg],
) -> @regalloc.PhysicalReg? {
  if available_regs.is_empty() || fixed_regs.is_empty() {
    return None
  }
  let mut max_id = -1
  for preg in available_regs {
    if preg.id > max_id {
      max_id = preg.id
    }
  }
  if max_id < 0 {
    return None
  }
  let available : Array[Bool] = Array::make(max_id + 1, false)
  let counts : Array[Int] = Array::make(max_id + 1, 0)
  for preg in available_regs {
    if preg.id >= 0 {
      available[preg.id] = true
    }
  }
  for preg in fixed_regs {
    if preg.id >= 0 && preg.id < available.length() && available[preg.id] {
      counts[preg.id] = counts[preg.id] + 1
    }
  }
  let mut best : @regalloc.PhysicalReg? = None
  let mut best_count = 0
  for preg in available_regs {
    let count = counts[preg.id]
    match best {
      None =>
        if count > 0 {
          best = Some(preg)
          best_count = count
        }
      Some(current) =>
        if count > best_count ||
          (count == best_count && count > 0 && preg.id < current.id) {
          best = Some(preg)
          best_count = count
        }
    }
  }
  best
}
