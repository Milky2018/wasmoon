///|
test "table bulk operations check bounds before 32-bit addition can wrap" {
  let table = @runtime.Table::Table(FuncRef, 1, None)
  let fill = try {
    table.fill(0x7FFF_FFFF, Null, 0x7FFF_FFFF)
    "returned"
  } catch {
    error => error.to_string()
  }
  inspect(fill, content="undefined element: out of bounds table access")
  let copy = try {
    table.copy_from(0x7FFF_FFFF, table, 0, 0x7FFF_FFFF)
    "returned"
  } catch {
    error => error.to_string()
  }
  inspect(copy, content="undefined element: out of bounds table access")
  table.fill_at(1L, Null, 0L)
  table.copy_from_at(1L, table, 1L, 0L)
  debug_inspect(table.get(0), content="Null")
}
