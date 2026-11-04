///|
#cfg(target="native")
test "Store ordinal index bounds sparse storage and accepts its density boundary" {
  for addresses in [[0, 4], [0, 2147483647], [-1, -1]] {
    let (_, positions) = store_interval_index(addresses.length(), i => {
      addresses[i]
    })
    assert_eq(positions.length(), 0)
  }
  let (origin, positions) = store_interval_index(2, i => {
    if i == 0 {
      54
    } else {
      57
    }
  })
  assert_eq(origin, 54)
  assert_eq(positions, [1, 0, 0, 2])
}
