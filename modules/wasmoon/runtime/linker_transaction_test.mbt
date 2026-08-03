///|
test "a Linker transaction does not affect another Linker" {
  let linker_a = @runtime.Linker::Linker()
  let transaction = @runtime.InstantiationTransaction::new()
  linker_a.register_rollback(transaction)
  let linker_b = @runtime.Linker::Linker()
  linker_b.register("kept", ModuleInstance())
  transaction.rollback()
  debug_inspect(linker_b.get_module("kept") is Some(_), content="true")
  linker_a.close()
  linker_b.close()
}
