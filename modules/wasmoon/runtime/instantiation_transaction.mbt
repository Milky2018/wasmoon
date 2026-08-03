///|
/// One rollback stack shared by every layer of an instantiation.
///
/// Participants register inverse operations as they acquire state. Rollback
/// runs them in reverse order; commit discards them. Both terminal operations
/// are idempotent.
struct InstantiationTransaction {
  rollbacks : Array[() -> Unit]
  finalizers : Array[() -> Unit]
  mut active : Bool
}

///|
pub fn InstantiationTransaction::new() -> InstantiationTransaction {
  { rollbacks: [], finalizers: [], active: true }
}

///|
struct RollbackRegistrar {
  transaction : InstantiationTransaction
}

///|
impl Debug for RollbackRegistrar with fn to_repr(_self) {
  Repr::literal("rollback-registrar")
}

///|
pub fn InstantiationTransaction::registrar(
  self : InstantiationTransaction,
) -> RollbackRegistrar {
  { transaction: self }
}

///|
pub fn RollbackRegistrar::on_rollback(
  self : RollbackRegistrar,
  rollback : () -> Unit,
) -> Unit {
  if self.transaction.active {
    self.transaction.rollbacks.push(rollback)
  }
}

///|
pub fn RollbackRegistrar::on_finish(
  self : RollbackRegistrar,
  finalizer : () -> Unit,
) -> Unit {
  if self.transaction.active {
    self.transaction.finalizers.push(finalizer)
  }
}

///|
pub fn InstantiationTransaction::commit(
  self : InstantiationTransaction,
) -> Unit {
  if self.active {
    self.active = false
    self.rollbacks.clear()
    for finalizer in self.finalizers {
      finalizer()
    }
    self.finalizers.clear()
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
  for finalizer in self.finalizers {
    finalizer()
  }
  self.finalizers.clear()
}
