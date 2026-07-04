///|
fn temp_pool_contains(pool : Array[Int], idx : Int) -> Bool {
  for value in pool {
    if value == idx {
      return true
    }
  }
  false
}

///|
fn temp_pool_is_used(used : Array[Bool], idx : Int) -> Bool {
  idx >= 0 && idx < used.length() && used[idx]
}

///|
fn temp_pool_push_available(
  pool : Array[Int],
  used : Array[Bool],
  idx : Int,
) -> Unit {
  if !temp_pool_is_used(used, idx) && !temp_pool_contains(pool, idx) {
    pool.push(idx)
  }
}

///|
pub fn plan_temp_register_pool(
  used : Array[Bool],
  scratch : Array[Int],
  nonpreferred : Array[Int],
  preferred : Array[Int],
) -> Array[Int] {
  let pool : Array[Int] = []
  for idx in scratch {
    pool.push(idx)
  }
  let candidates : Array[Int] = []
  for idx in nonpreferred {
    candidates.push(idx)
  }
  for idx in preferred {
    candidates.push(idx)
  }
  for idx in candidates {
    if idx >= 8 {
      temp_pool_push_available(pool, used, idx)
    }
  }
  for idx in candidates {
    if idx < 8 {
      temp_pool_push_available(pool, used, idx)
    }
  }
  pool
}
