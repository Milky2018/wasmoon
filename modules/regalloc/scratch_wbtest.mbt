///|
// Payload estimate for native scratch arrays, excluding allocator/object headers.
// White-box access is needed to distinguish an empty array from a freed buffer.
fn retained_scratch_payload(session : AllocationSession) -> Int {
  session.context_priorities.capacity() * 4 +
  session.context_weights.capacity() * 4 +
  session.context_fixed_constraints.capacity() * 4 +
  session.context_boundary_costs.capacity() * 4 +
  session.context_minimals.capacity() * 4 +
  session.context_spill_sets.capacity() * 4 +
  session.segment_owner.capacity() * 4 +
  session.segment_spill_set.capacity() * 4 +
  session.owner_run_count.capacity() * 4 +
  session.occupied_block_order.capacity() * 4 +
  session.occupied_roots.capacity() * 4 +
  session.occupied_left.capacity() * 4 +
  session.occupied_right.capacity() * 4 +
  session.occupied_parent.capacity() * 4 +
  session.occupied_previous.capacity() * 4 +
  session.occupied_next.capacity() * 4 +
  session.occupied_starts.capacity() * 8 +
  session.occupied_ends.capacity() * 8 +
  session.occupied_stack.capacity() * 4 +
  session.preferred_by_value.capacity() * 4 +
  session.conflict_marks.capacity() * 4 +
  session.probe_conflicts.capacity() * 4 +
  session.eviction_conflicts.capacity() * 4 +
  session.register_order.capacity() * 4 +
  session.register_order_marks.capacity() * 4 +
  session.physical_register_indexes.capacity() * 4 +
  session.queue_items.capacity() * 4 +
  session.queue_priorities.capacity() * 4 +
  session.queue_weights.capacity() * 4 +
  session.queue_in_queue.capacity() * 4 +
  session.queue_hints.capacity() * 4
}

///|
fn scratch_test_function(count : Int) -> VerifierCfgView {
  let operands : Array[Array[Operand]] = [
    [Operand::def({ id: 0, class: Int, })],
  ]
  for i in 1..<count {
    operands.push([
      Operand::use_reg({ id: i - 1, class: Int, }),
      Operand::def({ id: i, class: Int, }),
    ])
  }
  operands.push([Operand::use_reg({ id: count - 1, class: Int, })])
  {
    value_count: count,
    blocks: [Array::makei(count + 1, i => i)],
    operands,
    successors: [[]],
    entry_values: [],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
}

///|
test "scratch release frees retained capacity without changing returned plans" {
  let environment = MachineEnv::new(
    [{ id: 0, class: Int, }, { id: 1, class: Int, }],
    [{ id: 2, class: Int, }],
  )
  let session = AllocationSession::new()
  let large = scratch_test_function(4096)
  let plan = session.allocate_function(large, environment)
  let snapshot = plan.to_string()
  let large_capacity = retained_scratch_payload(session)
  session.allocate_function(scratch_test_function(2), environment) |> ignore
  let small_capacity = retained_scratch_payload(session)
  assert_true(large_capacity > 0)
  assert_true(small_capacity >= large_capacity)
  session.release_scratch()
  assert_eq(retained_scratch_payload(session), 0)
  assert_eq(plan.to_string(), snapshot)
  let again = session.allocate_function(large, environment)
  assert_eq(again.to_string(), snapshot)
  session.release_scratch()
  session.release_scratch()
  assert_eq(retained_scratch_payload(session), 0)
}
