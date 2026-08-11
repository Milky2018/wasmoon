///|
/// Intrusive ordered ranges assigned to physical registers.
///
/// Every allocation segment owns one node slot, regardless of how often it is
/// evicted and reinserted. The treap keeps expected logarithmic updates without
/// shifting an occupied suffix or allocating a tree node. Assigned ranges on
/// one register are disjoint, so ordering by inclusive end is also ordering by
/// start; a bundle probe can merge this stream with its ordered segments.
priv struct RegisterAllocationIndex {
  segments : Array[AllocationSegment]
  block_order : Array[Int]
  roots : Array[Int]
  left : Array[Int]
  right : Array[Int]
  parent : Array[Int]
}

///|
fn RegisterAllocationIndex::new(
  register_count : Int,
  segments : Array[AllocationSegment],
  block_order : Array[Int],
) -> RegisterAllocationIndex {
  {
    segments,
    block_order: block_order.copy(),
    roots: Array::make(register_count, -1),
    left: Array::make(segments.length(), -1),
    right: Array::make(segments.length(), -1),
    parent: Array::make(segments.length(), -1),
  }
}

///|
fn allocation_node_priority(segment : Int) -> UInt {
  let mut value = (segment + 1).reinterpret_as_uint()
  value = value ^ (value << 13)
  value = value ^ (value >> 17)
  value ^ (value << 5)
}

///|
fn allocation_node_is_higher(left : Int, right : Int) -> Bool {
  let left_priority = allocation_node_priority(left)
  let right_priority = allocation_node_priority(right)
  left_priority > right_priority ||
  (left_priority == right_priority && left < right)
}

///|
fn RegisterAllocationIndex::compare_segments(
  self : RegisterAllocationIndex,
  left : Int,
  right : Int,
) -> Int {
  let by_end = self.segments[left].range.end.compare_with_order(
    self.segments[right].range.end,
    self.block_order,
  )
  if by_end != 0 {
    by_end
  } else {
    left - right
  }
}

///|
fn RegisterAllocationIndex::replace_parent_child(
  self : RegisterAllocationIndex,
  register : Int,
  parent : Int,
  old_child : Int,
  new_child : Int,
) -> Unit {
  if parent < 0 {
    self.roots[register] = new_child
  } else if self.left[parent] == old_child {
    self.left[parent] = new_child
  } else {
    self.right[parent] = new_child
  }
  if new_child >= 0 {
    self.parent[new_child] = parent
  }
}

///|
fn RegisterAllocationIndex::rotate_left(
  self : RegisterAllocationIndex,
  register : Int,
  node : Int,
) -> Unit {
  let child = self.right[node]
  let previous_parent = self.parent[node]
  let middle = self.left[child]
  self.replace_parent_child(register, previous_parent, node, child)
  self.left[child] = node
  self.parent[node] = child
  self.right[node] = middle
  if middle >= 0 {
    self.parent[middle] = node
  }
}

///|
fn RegisterAllocationIndex::rotate_right(
  self : RegisterAllocationIndex,
  register : Int,
  node : Int,
) -> Unit {
  let child = self.left[node]
  let previous_parent = self.parent[node]
  let middle = self.right[child]
  self.replace_parent_child(register, previous_parent, node, child)
  self.right[child] = node
  self.parent[node] = child
  self.left[node] = middle
  if middle >= 0 {
    self.parent[middle] = node
  }
}

///|
fn RegisterAllocationIndex::insert(
  self : RegisterAllocationIndex,
  register : Int,
  segment : Int,
) -> Unit {
  self.left[segment] = -1
  self.right[segment] = -1
  self.parent[segment] = -1
  if self.roots[register] < 0 {
    self.roots[register] = segment
    return
  }
  let mut current = self.roots[register]
  while true {
    if self.compare_segments(segment, current) < 0 {
      if self.left[current] < 0 {
        self.left[current] = segment
        self.parent[segment] = current
        break
      }
      current = self.left[current]
    } else {
      if self.right[current] < 0 {
        self.right[current] = segment
        self.parent[segment] = current
        break
      }
      current = self.right[current]
    }
  }
  while self.parent[segment] >= 0 &&
        allocation_node_is_higher(segment, self.parent[segment]) {
    let parent = self.parent[segment]
    if self.left[parent] == segment {
      self.rotate_right(register, parent)
    } else {
      self.rotate_left(register, parent)
    }
  }
}

///|
fn RegisterAllocationIndex::remove(
  self : RegisterAllocationIndex,
  register : Int,
  segment : Int,
) -> Unit {
  while self.left[segment] >= 0 || self.right[segment] >= 0 {
    if self.right[segment] < 0 ||
      (
        self.left[segment] >= 0 &&
        allocation_node_is_higher(self.left[segment], self.right[segment])
      ) {
      self.rotate_right(register, segment)
    } else {
      self.rotate_left(register, segment)
    }
  }
  self.replace_parent_child(register, self.parent[segment], segment, -1)
  self.parent[segment] = -1
}

///|
fn RegisterAllocationIndex::seek(
  self : RegisterAllocationIndex,
  register : Int,
  point : ProgramPoint,
  stack : Array[Int],
) -> Unit {
  stack.clear()
  let mut current = self.roots[register]
  while current >= 0 {
    if self.segments[current].range.end.compare_with_order(
        point,
        self.block_order,
      ) >=
      0 {
      stack.push(current)
      current = self.left[current]
    } else {
      current = self.right[current]
    }
  }
}

///|
fn RegisterAllocationIndex::next(
  self : RegisterAllocationIndex,
  stack : Array[Int],
) -> Int? {
  guard stack.pop() is Some(segment) else { return None }
  let mut current = self.right[segment]
  while current >= 0 {
    stack.push(current)
    current = self.left[current]
  }
  Some(segment)
}
