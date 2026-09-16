///|
test "terminal transactions release callbacks capturing the registrar and transaction" {
  for rollback in [false, true] {
    let transaction = @runtime.InstantiationTransaction::new()
    let registrar = transaction.registrar()
    let events : Array[String] = []
    registrar.on_rollback(fn() {
      transaction.rollback()
      events.push("rollback")
    })
    registrar.on_finish(fn() {
      transaction.commit()
      registrar.on_finish(fn() { events.push("unexpected") })
      events.push("finish")
    })
    if rollback {
      transaction.rollback()
      debug_inspect(events, content="[\"rollback\", \"finish\"]")
    } else {
      transaction.commit()
      debug_inspect(events, content="[\"finish\"]")
    }
    transaction.commit()
    transaction.rollback()
  }
}
