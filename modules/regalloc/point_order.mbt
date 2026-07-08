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

///|
pub fn lower_bound_sorted_int(values : Array[Int], target : Int) -> Int {
  let mut lo = 0
  let mut hi = values.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if values[mid] < target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
pub fn upper_bound_sorted_int(values : Array[Int], target : Int) -> Int {
  let mut lo = 0
  let mut hi = values.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if values[mid] <= target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
pub fn count_sorted_ints_in_open_range(
  values : Array[Int],
  start : Int,
  end : Int,
) -> Int {
  let first_after_start = upper_bound_sorted_int(values, start)
  let first_at_or_after_end = lower_bound_sorted_int(values, end)
  if first_after_start < first_at_or_after_end {
    first_at_or_after_end - first_after_start
  } else {
    0
  }
}
