///|
pub(all) struct PriorityWorkItem {
  item_id : Int
  priority : Int
  seq : Int
} derive(Eq, Debug)

///|
pub struct PriorityWorkQueue {
  items : Array[PriorityWorkItem]
  mut next_seq : Int
}

///|
pub fn PriorityWorkQueue::new() -> PriorityWorkQueue {
  { items: [], next_seq: 0 }
}

///|
pub fn PriorityWorkQueue::length(self : PriorityWorkQueue) -> Int {
  self.items.length()
}

///|
fn work_item_higher(a : PriorityWorkItem, b : PriorityWorkItem) -> Bool {
  if a.priority > b.priority {
    true
  } else if a.priority < b.priority {
    false
  } else if a.seq != b.seq {
    a.seq < b.seq
  } else {
    a.item_id < b.item_id
  }
}

///|
pub fn PriorityWorkQueue::push(
  self : PriorityWorkQueue,
  item_id : Int,
  priority : Int,
) -> Unit {
  let entry = { item_id, priority, seq: self.next_seq }
  self.next_seq = self.next_seq + 1
  self.items.push(entry)
  let mut i = self.items.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if work_item_higher(self.items[i], self.items[parent]) {
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
pub fn PriorityWorkQueue::pop(self : PriorityWorkQueue) -> PriorityWorkItem? {
  if self.items.is_empty() {
    return None
  }
  let top = self.items[0]
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
            work_item_higher(self.items[right], self.items[left]) {
            best = right
          }
          if work_item_higher(self.items[best], self.items[i]) {
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
