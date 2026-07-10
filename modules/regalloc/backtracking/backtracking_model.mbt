///|
pub(all) enum RegallocAlgorithm {
  Backtracking
  SinglePass
}

///|
pub fn RegallocAlgorithm::enable_backtracking(self : RegallocAlgorithm) -> Bool {
  self is Backtracking
}

///|
pub(all) struct BacktrackingQueueEntry[P] {
  bundle_id : Int
  prio : Int
  hint_preg : P?
  seq : Int
}

///|
pub fn[P] backtracking_queue_entry_higher(
  a : BacktrackingQueueEntry[P],
  b : BacktrackingQueueEntry[P],
) -> Bool {
  if a.prio > b.prio {
    true
  } else if a.prio < b.prio {
    false
  } else if a.seq != b.seq {
    a.seq < b.seq
  } else {
    a.bundle_id < b.bundle_id
  }
}

///|
struct BacktrackingQueue[P] {
  mut items : Array[BacktrackingQueueEntry[P]]
  mut next_seq : Int
  in_heap : Array[Bool]
}

///|
pub fn[P] BacktrackingQueue::BacktrackingQueue(
  bundle_count : Int,
) -> BacktrackingQueue[P] {
  { items: [], next_seq: 0, in_heap: Array::make(bundle_count, false) }
}

///|
pub fn[P] BacktrackingQueue::length(self : BacktrackingQueue[P]) -> Int {
  self.items.length()
}

///|
pub fn[P] BacktrackingQueue::clear(self : BacktrackingQueue[P]) -> Unit {
  self.items = []
  self.next_seq = 0
  for i in 0..<self.in_heap.length() {
    self.in_heap[i] = false
  }
}

///|
pub fn[P] BacktrackingQueue::push_bundle_slot(
  self : BacktrackingQueue[P],
) -> Unit {
  self.in_heap.push(false)
}

///|
pub fn[P] BacktrackingQueue::push(
  self : BacktrackingQueue[P],
  bundle_id : Int,
  prio : Int,
  hint_preg : P?,
) -> Unit {
  if bundle_id >= 0 &&
    bundle_id < self.in_heap.length() &&
    self.in_heap[bundle_id] {
    return
  }
  let entry : BacktrackingQueueEntry[P] = {
    bundle_id,
    prio,
    hint_preg,
    seq: self.next_seq,
  }
  self.next_seq = self.next_seq + 1
  self.items.push(entry)
  if bundle_id >= 0 && bundle_id < self.in_heap.length() {
    self.in_heap[bundle_id] = true
  }
  let mut i = self.items.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if backtracking_queue_entry_higher(self.items[i], self.items[parent]) {
      let tmp = self.items[i]
      self.items[i] = self.items[parent]
      self.items[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

///|
pub fn[P] BacktrackingQueue::pop(
  self : BacktrackingQueue[P],
) -> BacktrackingQueueEntry[P]? {
  if self.items.is_empty() {
    return None
  }
  let top = self.items[0]
  if top.bundle_id >= 0 && top.bundle_id < self.in_heap.length() {
    self.in_heap[top.bundle_id] = false
  }
  let last = self.items.pop()
  match last {
    None => None
    Some(v) => {
      if !self.items.is_empty() {
        self.items[0] = v
        let mut i = 0
        while true {
          let left = i * 2 + 1
          if left >= self.items.length() {
            break
          }
          let right = left + 1
          let mut best = left
          if right < self.items.length() &&
            backtracking_queue_entry_higher(self.items[right], self.items[left]) {
            best = right
          }
          if backtracking_queue_entry_higher(self.items[best], self.items[i]) {
            let tmp = self.items[i]
            self.items[i] = self.items[best]
            self.items[best] = tmp
            i = best
          } else {
            break
          }
        }
      }
      Some(top)
    }
  }
}

///|
pub(all) struct OrderedSpan[P] {
  start : P
  start_ord : Int
  end_ord : Int
}

///|
pub(all) struct MergeSpan[R] {
  span : R
  start_ord : Int
  start_before_ord : Int
  end_ord : Int
} derive(Debug)

///|
pub fn[P] make_backtracking_alloc_table(
  cap : Int,
) -> Array[Array[(Int, OrderedSpan[P])]] {
  let table : Array[Array[(Int, OrderedSpan[P])]] = []
  for _ in 0..<cap {
    table.push([])
  }
  table
}

///|
pub fn make_backtracking_bool_table(cap : Int) -> Array[Bool] {
  let table : Array[Bool] = []
  for _ in 0..<cap {
    table.push(false)
  }
  table
}

///|
pub fn[P] lower_bound_backtracking_span_by_end(
  occupied : Array[(Int, OrderedSpan[P])],
  point_ord : Int,
) -> Int {
  let mut lo = 0
  let mut hi = occupied.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let end_ord = occupied[mid].1.end_ord
    if end_ord <= point_ord {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
struct BacktrackingSpillsetState[P] {
  hints : Array[P?]
  split_counts : Array[Int]
  max_splits_per_spillset : Int
}

///|
pub fn[P] BacktrackingSpillsetState::BacktrackingSpillsetState(
  bundle_count : Int,
  max_splits_per_spillset? : Int = 2,
) -> BacktrackingSpillsetState[P] {
  {
    hints: Array::make(bundle_count, None),
    split_counts: Array::make(bundle_count, 0),
    max_splits_per_spillset,
  }
}

///|
pub fn[P] BacktrackingSpillsetState::push_bundle_slot(
  self : BacktrackingSpillsetState[P],
) -> Unit {
  self.hints.push(None)
  self.split_counts.push(0)
}

///|
pub fn[P] BacktrackingSpillsetState::hint(
  self : BacktrackingSpillsetState[P],
  spillset_id : Int,
) -> P? {
  if spillset_id >= 0 && spillset_id < self.hints.length() {
    self.hints[spillset_id]
  } else {
    None
  }
}

///|
pub fn[P] BacktrackingSpillsetState::record_hint(
  self : BacktrackingSpillsetState[P],
  spillset_id : Int,
  hint : P,
) -> Unit {
  if spillset_id >= 0 && spillset_id < self.hints.length() {
    self.hints[spillset_id] = Some(hint)
  }
}

///|
pub fn[P] BacktrackingSpillsetState::split_limit_reached(
  self : BacktrackingSpillsetState[P],
  spillset_id : Int,
) -> Bool {
  spillset_id >= 0 &&
  spillset_id < self.split_counts.length() &&
  self.split_counts[spillset_id] >= self.max_splits_per_spillset
}

///|
pub fn[P] BacktrackingSpillsetState::record_split(
  self : BacktrackingSpillsetState[P],
  spillset_id : Int,
) -> Unit {
  if spillset_id >= 0 && spillset_id < self.split_counts.length() {
    self.split_counts[spillset_id] = self.split_counts[spillset_id] + 1
  }
}

///|
struct BacktrackingHintCache[P] {
  hints : Array[P?]
  ready : Array[Bool]
}

///|
pub fn[P] BacktrackingHintCache::BacktrackingHintCache(
  bundle_count : Int,
) -> BacktrackingHintCache[P] {
  {
    hints: Array::make(bundle_count, None),
    ready: Array::make(bundle_count, false),
  }
}

///|
pub fn[P] BacktrackingHintCache::push_bundle_slot(
  self : BacktrackingHintCache[P],
) -> Unit {
  self.hints.push(None)
  self.ready.push(false)
}

///|
pub fn[P] BacktrackingHintCache::is_ready(
  self : BacktrackingHintCache[P],
  bundle_id : Int,
) -> Bool {
  bundle_id >= 0 && bundle_id < self.ready.length() && self.ready[bundle_id]
}

///|
pub fn[P] BacktrackingHintCache::hint(
  self : BacktrackingHintCache[P],
  bundle_id : Int,
) -> P? {
  if bundle_id >= 0 && bundle_id < self.hints.length() {
    self.hints[bundle_id]
  } else {
    None
  }
}

///|
pub fn[P] BacktrackingHintCache::set(
  self : BacktrackingHintCache[P],
  bundle_id : Int,
  hint : P?,
) -> Unit {
  if bundle_id >= 0 && bundle_id < self.ready.length() {
    self.ready[bundle_id] = true
    self.hints[bundle_id] = hint
  }
}

///|
pub(all) struct SpillSetInfo[C, R, P] {
  old_slot : Int
  reg_class : C
  spans : Array[R]
  start : P
}

///|
pub(all) struct AssignedSlot[R] {
  start : Int
  spans : Array[R]
  old_slots : Array[Int]
}
