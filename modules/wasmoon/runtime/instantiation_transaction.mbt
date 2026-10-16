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
  mut core_publication : Bool
}

///|
pub fn InstantiationTransaction::new() -> InstantiationTransaction {
  { rollbacks: [], finalizers: [], active: true, core_publication: false, }
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
  { transaction: self, }
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
    self.rollbacks.shrink_to_fit()
    for finalizer in self.finalizers {
      finalizer()
    }
    self.finalizers.clear()
    self.finalizers.shrink_to_fit()
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
  self.rollbacks.shrink_to_fit()
  for finalizer in self.finalizers {
    finalizer()
  }
  self.finalizers.clear()
  self.finalizers.shrink_to_fit()
}

///|
/// Join an enclosing component transaction, or own rollback for a Core entry.
pub fn[T, E : Error] Store::with_instantiation(
  self : Store,
  run : () -> T raise E,
) -> T raise E {
  if self.instantiation is Some(_) {
    return run()
  }
  let transaction = InstantiationTransaction::new()
  transaction.core_publication = true
  self.register_rollback(transaction.registrar())
  defer transaction.rollback()
  let result = run()
  transaction.commit()
  result
}

///|
pub async fn[T, E : Error] Store::with_async_instantiation(
  self : Store,
  run : async () -> T raise E,
) -> T raise E {
  if self.instantiation is Some(_) {
    return run()
  }
  let transaction = InstantiationTransaction::new()
  transaction.core_publication = true
  self.register_rollback(transaction.registrar())
  defer transaction.rollback()
  let result = run()
  transaction.commit()
  result
}

///|
/// Core segment/start traps preserve prior writes to imported resources. Once
/// an instance can escape through those writes, keep its addresses and budget
/// alive. An enclosing Component transaction keeps its own commit boundary.
pub fn Store::publish_core_instance(self : Store) -> Unit {
  if self.instantiation is Some(registrar) &&
    registrar.transaction.core_publication {
    registrar.transaction.commit()
  }
}
