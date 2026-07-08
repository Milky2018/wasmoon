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

///|
pub(all) struct TempRegisterChoice {
  preg : PhysicalReg
  next_cursor : Int
  save_slot : Int?
  next_spill_slot : Int
} derive(Eq, Debug)

///|
fn temp_id_in_list(values : Array[Int], value : Int) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
pub fn choose_temp_register(
  class : RegClass,
  used_ids : Array[Int],
  temp_pool : Array[Int],
  fallback_candidates : Array[Int],
  reserved_ids : Array[Int],
  need_preserve : Bool,
  cursor : Int,
  next_spill_slot : Int,
) -> TempRegisterChoice {
  for i in 0..<temp_pool.length() {
    let idx = temp_pool[(cursor + i) % temp_pool.length()]
    if !temp_id_in_list(used_ids, idx) {
      return {
        preg: { id: idx, class },
        next_cursor: cursor + 1,
        save_slot: None,
        next_spill_slot,
      }
    }
  }
  for idx in fallback_candidates {
    if temp_id_in_list(reserved_ids, idx) || temp_id_in_list(used_ids, idx) {
      continue
    }
    if need_preserve {
      let reservation = reserve_spill_slot(next_spill_slot, class)
      return {
        preg: { id: idx, class },
        next_cursor: cursor + 1,
        save_slot: Some(reservation.slot),
        next_spill_slot: reservation.next_slot,
      }
    } else {
      return {
        preg: { id: idx, class },
        next_cursor: cursor + 1,
        save_slot: None,
        next_spill_slot,
      }
    }
  }
  abort("choose_temp_register: no available temporary register")
}
