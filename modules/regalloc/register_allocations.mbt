///|
/// Intrusive ordered ranges assigned to physical registers.
///
/// Every allocation segment owns one node slot, regardless of how often it is
/// evicted and reinserted. The treap keeps expected logarithmic updates without
/// shifting an occupied suffix or allocating a tree node. Assigned ranges on
/// one register are disjoint, so ordering by inclusive end is also ordering by
/// start; a bundle probe can merge this stream with its ordered segments. Run
/// counts track whether all segments owned by one allocated bundle are adjacent
/// and can therefore be skipped after their first conflict.
priv struct RegisterAllocationIndex {
  segments : Array[AllocationSegment]
  segment_owner : Array[Int]
  owner_run_count : Array[Int]
  block_order : Array[Int]
  roots : Array[Int]
  left : Array[Int]
  right : Array[Int]
  parent : Array[Int]
  previous_order : Array[Int]
  next_order : Array[Int]
  starts : Array[Int64]
  ends : Array[Int64]
}

///|
fn[T] reset_dense_array(array : Array[T], length : Int, value : T) -> Unit {
  array.clear()
  for _ in 0..<length {
    array.push(value)
  }
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
fn ordered_program_point_key(
  point : ProgramPoint,
  block_order : Array[Int],
) -> Int64 {
  // Bias the signed instruction into the low 32 bits. The ordered block id in
  // the high 32 bits then preserves ProgramPoint's lexicographic order exactly.
  program_point_block_order(point, block_order).to_int64() * 4294967296L +
  point.inst.to_int64() +
  2147483648L
}

///|
fn RegisterAllocationIndex::for_session(
  session : AllocationSession,
  register_count : Int,
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  owner_run_count : Array[Int],
  block_order : Array[Int],
) -> RegisterAllocationIndex {
  session.occupied_block_order.clear()
  for order in block_order {
    session.occupied_block_order.push(order)
  }
  reset_dense_array(session.occupied_roots, register_count, -1)
  reset_dense_array(session.occupied_left, segments.length(), -1)
  reset_dense_array(session.occupied_right, segments.length(), -1)
  reset_dense_array(session.occupied_parent, segments.length(), -1)
  reset_dense_array(session.occupied_previous, segments.length(), -1)
  reset_dense_array(session.occupied_next, segments.length(), -1)
  reset_dense_array(session.occupied_starts, segments.length(), 0L)
  reset_dense_array(session.occupied_ends, segments.length(), 0L)
  let index : RegisterAllocationIndex = {
    segments,
    segment_owner,
    owner_run_count,
    block_order: session.occupied_block_order,
    roots: session.occupied_roots,
    left: session.occupied_left,
    right: session.occupied_right,
    parent: session.occupied_parent,
    previous_order: session.occupied_previous,
    next_order: session.occupied_next,
    starts: session.occupied_starts,
    ends: session.occupied_ends,
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
  self.starts[segment] = ordered_program_point_key(
    range.start,
    self.block_order,
  )
  self.ends[segment] = ordered_program_point_key(range.end, self.block_order)
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
    self.starts.push(0L)
    self.ends.push(0L)
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
  let by_end = self.ends[left].compare(self.ends[right])
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
  let owner = self.segment_owner[segment]
  while self.owner_run_count.length() <= owner {
    self.owner_run_count.push(0)
  }
  self.left[segment] = -1
  self.right[segment] = -1
  self.parent[segment] = -1
  self.previous_order[segment] = -1
  self.next_order[segment] = -1
  if self.roots[register] < 0 {
    self.roots[register] = segment
    self.owner_run_count[owner] = self.owner_run_count[owner] + 1
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
  let predecessor_same_owner = predecessor >= 0 &&
    self.segment_owner[predecessor] == owner
  let successor_same_owner = successor >= 0 &&
    self.segment_owner[successor] == owner
  if !predecessor_same_owner && !successor_same_owner {
    self.owner_run_count[owner] = self.owner_run_count[owner] + 1
  }
  if predecessor >= 0 &&
    successor >= 0 &&
    self.segment_owner[predecessor] == self.segment_owner[successor] &&
    self.segment_owner[predecessor] != owner {
    let split_owner = self.segment_owner[predecessor]
    self.owner_run_count[split_owner] = self.owner_run_count[split_owner] + 1
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
  let owner = self.segment_owner[segment]
  let previous_same_owner = previous >= 0 &&
    self.segment_owner[previous] == owner
  let next_same_owner = next >= 0 && self.segment_owner[next] == owner
  if !previous_same_owner && !next_same_owner {
    self.owner_run_count[owner] = self.owner_run_count[owner] - 1
  }
  if previous >= 0 &&
    next >= 0 &&
    self.segment_owner[previous] == self.segment_owner[next] &&
    self.segment_owner[previous] != owner {
    let joined_owner = self.segment_owner[previous]
    self.owner_run_count[joined_owner] = self.owner_run_count[joined_owner] - 1
  }
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
  let point_key = ordered_program_point_key(point, self.block_order)
  let mut current = self.roots[register]
  let mut candidate = -1
  while current >= 0 {
    if self.ends[current] >= point_key {
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
  self.ends[end_segment] < self.starts[start_segment]
}

///|
/// Find the first ordered bundle segment whose end reaches the occupied
/// segment's start. Callers use this only after a short linear prefix, so
/// small bundles retain the cheaper sequential path.
fn RegisterAllocationIndex::first_not_ending_before(
  self : RegisterAllocationIndex,
  segments : Array[Int],
  from : Int,
  occupied : Int,
) -> Int {
  let mut low = from
  let mut high = segments.length()
  while low < high {
    let middle = low + (high - low) / 2
    if self.segment_end_before_start(segments[middle], occupied) {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn RegisterAllocationIndex::segment_end_before_or_equal(
  self : RegisterAllocationIndex,
  left : Int,
  right : Int,
) -> Bool {
  self.ends[left] <= self.ends[right]
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

///|
fn RegisterAllocationIndex::owner_is_contiguous(
  self : RegisterAllocationIndex,
  owner : Int,
) -> Bool {
  self.owner_run_count[owner] == 1
}

///|
fn RegisterAllocationIndex::skip_after(
  self : RegisterAllocationIndex,
  segment : Int,
  stack : Array[Int],
) -> Unit {
  stack.clear()
  if self.next_order[segment] >= 0 {
    stack.push(self.next_order[segment])
  }
}
