///|
test "jump threading resolves transitive empty jump chain" {
  let blocks : Array[ThreadBlock] = [
    { id: 1, params: [], target: Some(2), target_args: [], is_empty: true },
    { id: 2, params: [], target: Some(3), target_args: [], is_empty: true },
    { id: 3, params: [], target: None, target_args: [], is_empty: true },
  ]
  let resolved = resolve_threaded_jump(blocks, 1, [])
  inspect(resolved.target, content="3")
  debug_inspect(resolved.args, content="[]")
  inspect(resolved.changed, content="true")
}

///|
test "jump threading forwards virtual block args" {
  let blocks : Array[ThreadBlock] = [
    {
      id: 1,
      params: [10],
      target: Some(2),
      target_args: [VirtualArg(10, 0)],
      is_empty: true,
    },
    { id: 2, params: [20], target: None, target_args: [], is_empty: true },
  ]
  let resolved = resolve_threaded_jump(blocks, 1, [VirtualArg(99, 0)])
  inspect(resolved.target, content="2")
  debug_inspect(resolved.args, content="[VirtualArg(99, 0)]")
  inspect(resolved.changed, content="true")
}

///|
test "jump threading preserves physical args" {
  let blocks : Array[ThreadBlock] = [
    {
      id: 1,
      params: [10],
      target: Some(2),
      target_args: [PhysicalArg(5, 0)],
      is_empty: true,
    },
    { id: 2, params: [], target: None, target_args: [], is_empty: true },
  ]
  let resolved = resolve_threaded_jump(blocks, 1, [VirtualArg(99, 0)])
  inspect(resolved.target, content="2")
  debug_inspect(resolved.args, content="[PhysicalArg(5, 0)]")
  inspect(resolved.changed, content="true")
}

///|
test "jump threading stops when target args are not forwarded params" {
  let blocks : Array[ThreadBlock] = [
    {
      id: 1,
      params: [10],
      target: Some(2),
      target_args: [VirtualArg(11, 0)],
      is_empty: true,
    },
    { id: 2, params: [], target: None, target_args: [], is_empty: true },
  ]
  let resolved = resolve_threaded_jump(blocks, 1, [VirtualArg(99, 0)])
  inspect(resolved.target, content="1")
  debug_inspect(resolved.args, content="[VirtualArg(99, 0)]")
  inspect(resolved.changed, content="false")
}

///|
test "jump threading keeps original jump on cycles" {
  let blocks : Array[ThreadBlock] = [
    { id: 1, params: [], target: Some(2), target_args: [], is_empty: true },
    { id: 2, params: [], target: Some(1), target_args: [], is_empty: true },
  ]
  let resolved = resolve_threaded_jump(blocks, 1, [])
  inspect(resolved.target, content="1")
  debug_inspect(resolved.args, content="[]")
  inspect(resolved.changed, content="false")
}
