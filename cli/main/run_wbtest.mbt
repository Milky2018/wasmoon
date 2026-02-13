///|
fn minimal_i32_const_module_bytes() -> Bytes {
  Bytes::from_array([
    // Magic + version
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // Type section: (func) -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section: one local function of type 0
     0x03, 0x02, 0x01, 0x00,
    // Export section: (export "run" (func 0))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
    // Code section: i32.const 42; end
     0x0a, 0x06, 0x01, 0x04, 0x00, 0x41, 0x2a, 0x0b,
  ])
}

///|
test "compile api: emits stage progress and returns artifact" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(minimal_i32_const_module_bytes(), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="true")
  inspect(events.length() > 0, content="true")
  inspect(events[0].stage.to_string(), content="parse")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="done")
  inspect(last.compiled_funcs, content="1")
}

///|
test "compile api: parse failure emits failed stage" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(Bytes::from_array([0x00, 0x01, 0x02]), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="false")
  inspect(events.length() >= 2, content="true")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="failed")
}
