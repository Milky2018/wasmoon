///|
test "backtracking queue pops higher priority with stable ties" {
  let queue : BacktrackingQueue[Int] = BacktrackingQueue::new(4)
  queue.push(2, 10, Some(20))
  queue.push(1, 20, Some(10))
  queue.push(3, 20, Some(30))
  queue.push(1, 99, Some(99))
  let first = queue.pop().unwrap()
  inspect(first.bundle_id, content="1")
  inspect(first.prio, content="20")
  inspect(first.hint_preg == Some(10), content="true")
  let second = queue.pop().unwrap()
  inspect(second.bundle_id, content="3")
  inspect(second.prio, content="20")
  inspect(second.hint_preg == Some(30), content="true")
  let third = queue.pop().unwrap()
  inspect(third.bundle_id, content="2")
  inspect(third.prio, content="10")
  inspect(third.hint_preg == Some(20), content="true")
  inspect(queue.pop() is None, content="true")
}

///|
test "backtracking spillset state records hints and split caps" {
  let spillsets : BacktrackingSpillsetState[Int] = BacktrackingSpillsetState::new(
    2,
    max_splits_per_spillset=2,
  )
  inspect(spillsets.hint(1) is None, content="true")
  spillsets.record_hint(1, 42)
  inspect(spillsets.hint(1) == Some(42), content="true")
  inspect(spillsets.split_limit_reached(1), content="false")
  spillsets.record_split(1)
  inspect(spillsets.split_limit_reached(1), content="false")
  spillsets.record_split(1)
  inspect(spillsets.split_limit_reached(1), content="true")
}
