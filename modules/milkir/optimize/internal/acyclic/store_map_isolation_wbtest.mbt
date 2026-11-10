///|
test "lazy indexed store maps preserve independent snapshots and defaults" {
  let first : StoreVersion = { block_id: 0, inst_id: 1, }
  let second : StoreVersion = { block_id: 0, inst_id: 2, }
  let all : StoreVersion = { block_id: 0, inst_id: 3, }
  let source = LastStoreState()
  assert_true(source.heap is None && source.table is None)
  let empty = source.clone()
  assert_true(empty.heap is None && empty.table is None)
  source.set_region_token(Heap(0), first)
  source.set_region_token(Table(1), second)
  let snapshot = source.clone()
  snapshot.set_region_token(Heap(0), second)
  snapshot.set_region_token(Heap(2), second)
  snapshot.set_region_token(Table(1), first)
  assert_true(source.get_region_token(Heap(0)) == Some(first))
  assert_true(source.get_region_token(Heap(2)) is None)
  assert_true(source.get_region_token(Table(1)) == Some(second))
  source.set_all_tokens(all)
  assert_true(source.heap is None && source.table is None)
  assert_true(source.get_region_token(Heap(99)) == Some(all))
  assert_true(source.get_region_token(Table(99)) == Some(all))
  assert_true(snapshot.get_region_token(Heap(0)) == Some(second))
  assert_true(snapshot.get_region_token(Table(1)) == Some(first))
  assert_true(empty.get_region_token(Heap(0)) is None)
}

///|
test "lazy store-map meets distinguish initial memory from unvisited paths" {
  let write : StoreVersion = { block_id: 1, inst_id: 1, }
  let join : StoreVersion = { block_id: 2, inst_id: -1, }
  let initial = LastStoreState()
  let written = initial.clone()
  written.set_region_token(Heap(0), write)
  written.set_region_token(Table(1), write)
  assert_true(initial.meet_from(written, join))
  assert_true(initial.get_region_token(Heap(0)) == Some(join))
  assert_true(initial.get_region_token(Table(1)) == Some(join))
  assert_true(initial.get_region_token(Heap(1)) is None)
  assert_true(written.get_region_token(Heap(0)) == Some(write))
  assert_false(initial.meet_from(written, join))
  let changed_all = LastStoreState()
  changed_all.set_all_tokens(write)
  assert_true(initial.meet_from(changed_all, join))
  assert_true(initial.get_region_token(Heap(1)) == Some(join))
  assert_true(initial.get_region_token(Table(99)) == Some(join))
  assert_true(changed_all.get_region_token(Heap(0)) == Some(write))
}
