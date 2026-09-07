///|
test "component instance entry state tracks activity and poison" {
  let entry = ComponentInstanceEntryState::new()
  debug_inspect(
    entry,
    content="{ active: <Ref: false>, poisoned: <Ref: false> }",
  )
  entry.enter()
  debug_inspect(
    entry,
    content="{ active: <Ref: true>, poisoned: <Ref: false> }",
  )
  entry.leave()
  debug_inspect(
    entry,
    content="{ active: <Ref: false>, poisoned: <Ref: false> }",
  )
  entry.enter()
  entry.poison()
  debug_inspect(
    entry,
    content="{ active: <Ref: false>, poisoned: <Ref: true> }",
  )
  let rejected = try {
    entry.enter()
    None
  } catch {
    error => Some(error)
  } noraise {
    result => result
  }
  debug_inspect(
    rejected,
    content="Some(CanonCallError(\"cannot enter component instance\"))",
  )
}

///|
test "component instance rejects re-entry and preserves poison" {
  let entry = ComponentInstanceEntryState::new()
  entry.enter()
  let reentry : Array[ComponentRuntimeError?] = [None]
  entry.enter() catch {
    error => reentry[0] = Some(error)
  }
  entry.leave()
  entry.enter()
  entry.poison()
  let poisoned_entry : Array[ComponentRuntimeError?] = [None]
  entry.enter() catch {
    error => poisoned_entry[0] = Some(error)
  }
  debug_inspect(
    (reentry[0], poisoned_entry[0], entry),
    content=(
      #|(
      #|  Some(CanonCallError("cannot enter component instance")),
      #|  Some(CanonCallError("cannot enter component instance")),
      #|  { active: <Ref: false>, poisoned: <Ref: true> },
      #|)
    ),
  )
}
