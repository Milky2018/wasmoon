///|
/// Load a module from file path (supports both .wasm and .wat)
fn load_module_from_path(path : String) -> @types.Module raise CliError {
  let is_wat = path.has_suffix(".wat") || path.has_suffix(".wast")
  if is_wat {
    let content = @fs.read_file_to_string(path) catch {
      IOError(_e) => raise FileNotFound(path)
    }
    @wat.parse(content) catch {
      e => raise ParseWatError(e.to_string())
    }
  } else {
    let bytes = @fs.read_file_to_bytes(path) catch {
      IOError(_e) => raise FileNotFound(path)
    }
    match @component.sniff_binary_kind(bytes) {
      Some(Component) => raise ComponentModelNotSupported
      _ => ()
    }
    @parser.parse_module(bytes) catch {
      e => raise ParseModuleError(e.to_string())
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
