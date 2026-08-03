///|
/// One rollback stack shared by every layer of an instantiation.
///
/// Participants register inverse operations as they acquire state. Rollback
/// runs them in reverse order; commit discards them. Both terminal operations
/// are idempotent.
struct InstantiationTransaction {
  rollbacks : Array[() -> Unit]
  mut active : Bool
}

///|
pub fn InstantiationTransaction::new() -> InstantiationTransaction {
  { rollbacks: [], active: true }
}

///|
pub fn InstantiationTransaction::on_rollback(
  self : InstantiationTransaction,
  rollback : () -> Unit,
) -> Unit {
  if self.active {
    self.rollbacks.push(rollback)
  }
}

///|
fn[T] InstantiationTransaction::truncate_on_rollback(
  self : InstantiationTransaction,
  values : Array[T],
) -> Unit {
  let length = values.length()
  self.on_rollback(fn() { values.truncate(length) })
}

///|
fn[T] InstantiationTransaction::restore_on_rollback(
  self : InstantiationTransaction,
  values : Array[T],
) -> Unit {
  let snapshot = values.copy()
  self.on_rollback(fn() {
    values.clear()
    for value in snapshot {
      values.push(value)
    }
  })
}

///|
pub fn InstantiationTransaction::commit(
  self : InstantiationTransaction,
) -> Unit {
  if self.active {
    self.active = false
    self.rollbacks.clear()
  }
}

///|
pub fn InstantiationTransaction::rollback(
  self : InstantiationTransaction,
) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  let mut index = self.rollbacks.length()
  while index > 0 {
    index -= 1
    self.rollbacks[index]()
  }
  self.rollbacks.clear()
}
