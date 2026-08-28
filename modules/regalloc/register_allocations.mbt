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
  previous_order : Array[Int]
  next_order : Array[Int]
  start_block_order : Array[Int]
  start_instruction : Array[Int]
  end_block_order : Array[Int]
  end_instruction : Array[Int]
}

///|
fn program_point_block_order(
  point : ProgramPoint,
  block_order : Array[Int],
) -> Int {
  if point.block >= 0 && point.block < block_order.length() {
    block_order[point.block]
  } else {
    point.block
  }
}

///|
fn compare_cached_points(
  left_block : Int,
  left_instruction : Int,
  right_block : Int,
  right_instruction : Int,
) -> Int {
  if left_block < right_block {
    -1
  } else if left_block > right_block {
    1
  } else {
    left_instruction.compare(right_instruction)
  }
}

///|
fn RegisterAllocationIndex::new(
  register_count : Int,
  segments : Array[AllocationSegment],
  block_order : Array[Int],
) -> RegisterAllocationIndex {
  let index = {
    segments,
    block_order: block_order.copy(),
    roots: Array::make(register_count, -1),
    left: Array::make(segments.length(), -1),
    right: Array::make(segments.length(), -1),
    parent: Array::make(segments.length(), -1),
    previous_order: Array::make(segments.length(), -1),
    next_order: Array::make(segments.length(), -1),
    start_block_order: Array::make(segments.length(), 0),
    start_instruction: Array::make(segments.length(), 0),
    end_block_order: Array::make(segments.length(), 0),
    end_instruction: Array::make(segments.length(), 0),
  }
  for segment in segments {
    index.refresh_segment(segment.id)
  }
  index
}

///|
fn RegisterAllocationIndex::refresh_segment(
  self : RegisterAllocationIndex,
  segment : Int,
) -> Unit {
  let range = self.segments[segment].range
  self.start_block_order[segment] = program_point_block_order(
    range.start,
    self.block_order,
  )
  self.start_instruction[segment] = range.start.inst
  self.end_block_order[segment] = program_point_block_order(
    range.end,
    self.block_order,
  )
  self.end_instruction[segment] = range.end.inst
}

///|
fn RegisterAllocationIndex::add_segment(
  self : RegisterAllocationIndex,
  segment : Int,
) -> Unit {
  while self.left.length() <= segment {
    self.left.push(-1)
    self.right.push(-1)
    self.parent.push(-1)
    self.previous_order.push(-1)
    self.next_order.push(-1)
    self.start_block_order.push(0)
    self.start_instruction.push(0)
    self.end_block_order.push(0)
    self.end_instruction.push(0)
  }
  self.refresh_segment(segment)
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
  let by_end = compare_cached_points(
    self.end_block_order[left],
    self.end_instruction[left],
    self.end_block_order[right],
    self.end_instruction[right],
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
  self.previous_order[segment] = -1
  self.next_order[segment] = -1
  if self.roots[register] < 0 {
    self.roots[register] = segment
    return
  }
  let mut current = self.roots[register]
  let mut predecessor = -1
  let mut successor = -1
  while true {
    if self.compare_segments(segment, current) < 0 {
      successor = current
      if self.left[current] < 0 {
        self.left[current] = segment
        self.parent[segment] = current
        break
      }
      current = self.left[current]
    } else {
      predecessor = current
      if self.right[current] < 0 {
        self.right[current] = segment
        self.parent[segment] = current
        break
      }
      current = self.right[current]
    }
  }
  self.previous_order[segment] = predecessor
  self.next_order[segment] = successor
  if predecessor >= 0 {
    self.next_order[predecessor] = segment
  }
  if successor >= 0 {
    self.previous_order[successor] = segment
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
  let previous = self.previous_order[segment]
  let next = self.next_order[segment]
  if previous >= 0 {
    self.next_order[previous] = next
  }
  if next >= 0 {
    self.previous_order[next] = previous
  }
  self.previous_order[segment] = -1
  self.next_order[segment] = -1
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
  let point_block_order = program_point_block_order(point, self.block_order)
  let mut current = self.roots[register]
  let mut candidate = -1
  while current >= 0 {
    if compare_cached_points(
        self.end_block_order[current],
        self.end_instruction[current],
        point_block_order,
        point.inst,
      ) >=
      0 {
      candidate = current
      current = self.left[current]
    } else {
      current = self.right[current]
    }
  }
  if candidate >= 0 {
    stack.push(candidate)
  }
}

///|
fn RegisterAllocationIndex::segment_end_before_start(
  self : RegisterAllocationIndex,
  end_segment : Int,
  start_segment : Int,
) -> Bool {
  compare_cached_points(
    self.end_block_order[end_segment],
    self.end_instruction[end_segment],
    self.start_block_order[start_segment],
    self.start_instruction[start_segment],
  ) <
  0
}

///|
fn RegisterAllocationIndex::segment_end_before_or_equal(
  self : RegisterAllocationIndex,
  left : Int,
  right : Int,
) -> Bool {
  compare_cached_points(
    self.end_block_order[left],
    self.end_instruction[left],
    self.end_block_order[right],
    self.end_instruction[right],
  ) <=
  0
}

///|
fn RegisterAllocationIndex::next(
  self : RegisterAllocationIndex,
  stack : Array[Int],
) -> Int? {
  guard stack.pop() is Some(segment) else { return None }
  if self.next_order[segment] >= 0 {
    stack.push(self.next_order[segment])
  }
  Some(segment)
}
