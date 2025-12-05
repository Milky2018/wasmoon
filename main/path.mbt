///|
/// Load a module from file path (supports both .wasm and .wat)
fn load_module_from_path(path : String) -> @types.Module raise Error {
  let is_wat = path.has_suffix(".wat")
  if is_wat {
    let content = @fs.read_file_to_string(path) catch { e => raise e }
    @wat.parse(content) catch {
      e => raise e
    }
  } else {
    let bytes = @fs.read_file_to_bytes(path) catch { e => raise e }
    @parser.parse_module(bytes) catch {
      e => raise e
    }
  }
}

///|
/// Find base directory from a file path
fn find_base_dir(path : String) -> String {
  let mut last_slash = -1
  for i in 0..<path.length() {
    if path.code_unit_at(i) == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 {
    let builder = StringBuilder::new()
    for i in 0..<last_slash {
      builder.write_char(path.code_unit_at(i).unsafe_to_char())
    }
    builder.to_string()
  } else {
    "."
  }
}
