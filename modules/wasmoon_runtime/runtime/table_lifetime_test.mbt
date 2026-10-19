///|
test "standalone table close is terminal through aliases and Store adoption" {
  let budget = @runtime.ResourceBudget::new(table_elements=1L)
  let table = @runtime.Table::Table(
    FuncRef,
    1,
    None,
    resource_budget=Some(budget),
  )
  defer table.close()
  let retained = table
  table.close()
  retained.close()
  assert_eq(budget.used(TableElements), 0L)
  assert_eq(retained.size(), 0)
  assert_eq(retained.grow(2, Null), -1)
  try retained.grow64(0L, Null) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed table accepted zero growth")
  }
  try retained.fill_at(0L, Null, 0L) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed table accepted an empty write")
  }
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  try store.alloc_table(retained) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("Store adopted a closed table")
  }
  let healthy = @runtime.Table::Table(FuncRef, 1, None)
  store.alloc_table(healthy) |> ignore
  assert_eq(budget.used(TableElements), 1L)
  store.close()
  assert_eq(budget.used(TableElements), 0L)
}
