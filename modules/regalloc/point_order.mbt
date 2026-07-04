///|
pub fn compute_block_point_bases(
  block_order : Array[Int],
  block_lengths : Array[Int],
) -> Array[Int] {
  let block_count = block_order.length()
  let block_idx_by_order : Array[Int] = Array::make(block_count, 0)
  for block_idx in 0..<block_count {
    let ord = block_order[block_idx]
    if ord >= 0 && ord < block_count {
      block_idx_by_order[ord] = block_idx
    }
  }
  let block_point_base : Array[Int] = Array::make(block_count, 0)
  let mut point_cursor = 0
  for ord in 0..<block_count {
    block_point_base[ord] = point_cursor
    let block_idx = block_idx_by_order[ord]
    let block_len = if block_idx >= 0 && block_idx < block_lengths.length() {
      block_lengths[block_idx]
    } else {
      0
    }
    point_cursor = point_cursor + (block_len + 2) * 2
  }
  block_point_base
}
