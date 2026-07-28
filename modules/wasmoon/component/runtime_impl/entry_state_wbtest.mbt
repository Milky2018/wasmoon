///|
test "component instance entry state separates readiness activity and poison" {
  let entry = ComponentInstanceEntryState::new()
  debug_inspect(
    entry,
    content="{ ready: <Ref: false>, active: <Ref: false>, poisoned: <Ref: false> }",
  )
  entry.enable()
  debug_inspect(
    entry,
    content="{ ready: <Ref: true>, active: <Ref: false>, poisoned: <Ref: false> }",
  )
  entry.enter()
  debug_inspect(
    entry,
    content="{ ready: <Ref: true>, active: <Ref: true>, poisoned: <Ref: false> }",
  )
  entry.leave()
  debug_inspect(
    entry,
    content="{ ready: <Ref: true>, active: <Ref: false>, poisoned: <Ref: false> }",
  )
  entry.enter()
  entry.poison()
  debug_inspect(
    entry,
    content="{ ready: <Ref: true>, active: <Ref: false>, poisoned: <Ref: true> }",
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
