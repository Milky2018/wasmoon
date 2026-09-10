///|
test "terminal stream trap aliases preserve direction and notification" {
  inspect(
    component_trap_matches(
      "CanonCallError(\"cannot read after being notified that the writable end dropped\")",
      "cannot read from stream after being notified that the writable end dropped",
    ),
    content="true",
  )
  inspect(
    component_trap_matches(
      "cannot write to stream after being notified that the readable end dropped",
      "cannot write after being notified that the readable end dropped",
    ),
    content="true",
  )
  inspect(
    component_trap_matches(
      "cannot read after being notified that the writable end dropped", "cannot write after being notified that the readable end dropped",
    ),
    content="false",
  )
  inspect(
    component_trap_matches(
      "cannot write to future after previous write succeeded or readable end dropped",
      "cannot write after being notified that the readable end dropped",
    ),
    content="false",
  )
  inspect(
    component_trap_matches(
      "wasm trap: unreachable", "cannot read after being notified that the writable end dropped",
    ),
    content="false",
  )
}
