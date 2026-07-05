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
fn direct_call_module_bytes() -> Bytes {
  Bytes::from_array([
    // Magic + version
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // Type section: (func) -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section: two local functions of type 0
     0x03, 0x03, 0x02, 0x00, 0x00,
    // Export section: (export "run" (func 1))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x01,
    // Code section:
    //   func0: i32.const 42
    //   func1: call 0
     0x0a, 0x0b, 0x02, 0x04, 0x00, 0x41, 0x2a, 0x0b, 0x04, 0x00, 0x10, 0x00, 0x0b,
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
  guard compiled is Some(precompiled) else { return }
  inspect(precompiled.functions.length(), content="1")
  inspect(precompiled.functions[0].name, content="run")
  inspect(precompiled.functions[0].code.length() > 0, content="true")
  inspect(precompiled.functions[0].num_results, content="1")
}

///|
test "compile api: legacy JIT pipeline lowers direct wasm calls" {
  let compiled = compile_module(direct_call_module_bytes())
  guard compiled is Some(precompiled) else { fail("compile failed") }
  inspect(precompiled.functions.length(), content="2")
  let mut call_fixup_count = -1
  for entry in precompiled.functions {
    if entry.func_idx == 1 {
      call_fixup_count = entry.call_fixups.length()
    }
  }
  inspect(call_fixup_count, content="1")
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

///|
test "jit cache bytes/ints conversion keeps unsigned bytes" {
  let source = Bytes::from_array([0x00, 0x01, 0x7f, 0x80, 0xfe, 0xff])
  let ints = bytes_to_int_array(source)
  inspect(ints[0], content="0")
  inspect(ints[3], content="128")
  inspect(ints[4], content="254")
  inspect(ints[5], content="255")
  inspect(int_array_to_bytes(ints) == source, content="true")
}
