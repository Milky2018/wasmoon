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
test "preflight: validate_module reports parse errors" {
  let report = validate_module(Bytes::from_array([0x00, 0x01, 0x02]))
  inspect(report.ok, content="false")
  inspect(report.diagnostics.length() > 0, content="true")
  inspect(report.diagnostics[0].stage.to_string(), content="parse")
  inspect(report.checked_funcs, content="0")
}

///|
test "preflight: validate_module passes valid bytes" {
  let report = validate_module(minimal_i32_const_module_bytes())
  inspect(report.ok, content="true")
  inspect(report.total_funcs, content="1")
  inspect(report.checked_funcs, content="0")
  inspect(report.diagnostics.length(), content="0")
}

///|
test "preflight: validate_jit checks local functions" {
  let report = validate_jit(minimal_i32_const_module_bytes())
  inspect(report.ok, content="true")
  inspect(report.total_funcs, content="1")
  inspect(report.checked_funcs, content="1")
}
