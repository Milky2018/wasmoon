// Tests for wasmoon runtime

///|
test "parse empty module" {
  let _ = Module::new()
  inspect(true, content="true")
}
