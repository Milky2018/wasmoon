///|
/// The pinned Component Model and Wasmtime snapshots use different wording for
/// the same terminal stream state. Keep these aliases narrow: direction and
/// notification are part of the assertion, not arbitrary diagnostic details.
fn component_trap_matches(actual : String, expected : String) -> Bool {
  fn normalize(message : String) -> String {
    message
    .replace_all(
      old="cannot read from stream after being notified that the writable end dropped",
      new="cannot read after being notified that the writable end dropped",
    )
    .replace_all(
      old="cannot write to stream after being notified that the readable end dropped",
      new="cannot write after being notified that the readable end dropped",
    )
  }
  if normalize(actual).contains(normalize(expected)) {
    return true
  }
  // The older future assertion deliberately covers either successful writing
  // or an observed reader drop. Newer diagnostics distinguish these states.
  expected ==
  "cannot write to future after previous write succeeded or readable end dropped" &&
  actual.contains(
    "cannot write after being notified that the readable end dropped",
  )
}
