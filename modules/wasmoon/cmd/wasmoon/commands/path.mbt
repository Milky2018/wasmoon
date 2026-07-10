///|
/// Load a module from file path (supports both .wasm and .wat)
/// Returns parsed module and optional original wasm bytes for binary inputs.
fn load_module_with_binary_from_path(
  path : String,
) -> (@types.Module, Bytes?) raise CliError {
  let is_wat = path.has_suffix(".wat") || path.has_suffix(".wast")
  if is_wat {
    let content = @fs.read_file_to_string(path) catch {
      IOError(_e) => raise FileNotFound(path)
    }
    let mod_ = @wat.parse(content) catch {
      e => raise ParseWatError(e.to_string())
    }
    (mod_, None)
  } else {
    let bytes = @fs.read_file_to_bytes(path) catch {
      IOError(_e) => raise FileNotFound(path)
    }
    if @component.sniff_binary_kind(bytes) is Some(Component) {
      raise ComponentModelNotSupported
    }
    let mod_ = @parser.parse_module(bytes) catch {
      e => raise ParseModuleError(e.to_string())
    }
    (mod_, Some(bytes))
  }
}

///|
/// Load a module from file path (supports both .wasm and .wat)
fn load_module_from_path(path : String) -> @types.Module raise CliError {
  let (mod_, _) = load_module_with_binary_from_path(path)
  mod_
}

///|
/// Validate a decoded core module before it reaches instantiation or JIT state.
fn validate_module_for_execution(mod_ : @types.Module) -> Unit raise CliError {
  @validator.validate_module_with_context(mod_) catch {
    err => {
      let message = match err {
        WithContext(ctx) => ctx.format()
        _ => @validator.format_validation_error(err)
      }
      raise ValidateModuleError(message)
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
    let builder = StringBuilder::StringBuilder()
    for i in 0..<last_slash {
      builder.write_char(path.code_unit_at(i).unsafe_to_char())
    }
    builder.to_string()
  } else {
    "."
  }
}
