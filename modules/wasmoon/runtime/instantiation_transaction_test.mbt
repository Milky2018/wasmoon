///|
test "instantiation transaction rolls back once in reverse order" {
  let transaction = @runtime.InstantiationTransaction::new()
  let events : Array[String] = []
  transaction.on_rollback(fn() { events.push("first") })
  transaction.on_rollback(fn() { events.push("second") })
  transaction.rollback()
  transaction.rollback()
  debug_inspect(events, content="[\"second\", \"first\"]")
}

///|
test "committed instantiation transaction discards rollback actions" {
  let transaction = @runtime.InstantiationTransaction::new()
  let events : Array[String] = []
  transaction.on_rollback(fn() { events.push("rolled back") })
  transaction.commit()
  transaction.rollback()
  debug_inspect(events, content="[]")
}
