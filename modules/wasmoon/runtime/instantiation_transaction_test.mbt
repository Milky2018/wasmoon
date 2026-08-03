///|
test "instantiation transaction rolls back once in reverse order" {
  let transaction = @runtime.InstantiationTransaction::new()
  let registrar = transaction.registrar()
  let events : Array[String] = []
  registrar.on_rollback(fn() { events.push("first") })
  registrar.on_rollback(fn() { events.push("second") })
  registrar.on_finish(fn() { events.push("finished") })
  transaction.rollback()
  transaction.rollback()
  debug_inspect(events, content="[\"second\", \"first\", \"finished\"]")
}

///|
test "committed instantiation transaction discards rollback actions" {
  let transaction = @runtime.InstantiationTransaction::new()
  let registrar = transaction.registrar()
  let events : Array[String] = []
  registrar.on_rollback(fn() { events.push("rolled back") })
  registrar.on_finish(fn() { events.push("finished") })
  transaction.commit()
  transaction.rollback()
  debug_inspect(events, content="[\"finished\"]")
}
