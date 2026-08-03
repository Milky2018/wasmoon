///|
test "a Linker transaction does not affect another Linker" {
  let linker_a = @runtime.Linker::Linker()
  let transaction = @runtime.InstantiationTransaction::new()
  linker_a.register_rollback(transaction.registrar())
  let linker_b = @runtime.Linker::Linker()
  linker_b.register("kept", ModuleInstance())
  transaction.rollback()
  debug_inspect(linker_b.get_module("kept") is Some(_), content="true")
  linker_a.close()
  linker_b.close()
}

///|
test "Linkers sharing a Store join the active transaction" {
  let store = @runtime.Store::Store()
  let owner = @runtime.Linker::with_store(store)
  let nested = @runtime.Linker::with_store(store)
  nested.add_host_func("host", "kept", fn(_args) { [] })
  let transaction = @runtime.InstantiationTransaction::new()
  owner.register_rollback(transaction.registrar())
  nested.add_host_func("host", "rolled-back", fn(_args) { [] })
  transaction.rollback()
  guard nested.get_module("host") is Some(instance) else {
    return fail("expected pre-transaction host module")
  }
  debug_inspect(instance.exports.map(item => item.name), content="[\"kept\"]")
  owner.close()
  nested.close()
}

///|
test "transaction rollback tolerates terminal owner close" {
  let linker = @runtime.Linker::Linker()
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  linker.add_memory("host", "memory", Memory(1, None))
  linker.close()
  transaction.rollback()
  transaction.rollback()
}
