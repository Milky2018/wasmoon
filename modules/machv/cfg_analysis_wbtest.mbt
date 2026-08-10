///|
test "CFG order handles a 100000-block chain" {
  let block_count = 100000
  let successors : Array[Array[Int]] = Array::makei(block_count, block => {
    if block + 1 < block_count {
      [block + 1]
    } else {
      []
    }
  })
  let order = reverse_postorder(successors)
  debug_inspect(
    (order.length(), order[0], order[block_count - 1]),
    content="(100000, 0, 99999)",
  )
}
