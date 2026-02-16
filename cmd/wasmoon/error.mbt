///|
priv suberror CliError {
  FileNotFound(String)
  ParseModuleError(String)
  ParseWatError(String)
  ComponentModelNotSupported
  FuncArgNumError(Int, Int)
  ArgTypeError(@types.ValueType, String)
  UnsupportedArgTypeError(@types.ValueType, String)
}

///|
impl Show for CliError with output(self, logger) {
  let msg = match self {
    FileNotFound(path) => "file \{path} not found"
    ParseModuleError(e) => "parse wasm module error: \{e}"
    ParseWatError(e) => "parse wat file error: \{e}"
    ComponentModelNotSupported => "wasm component model is not supported yet"
    FuncArgNumError(expected, got) =>
      "expected \{expected} arguments, got \{got}"
    ArgTypeError(ty, arg) => "invalid \{ty} value: \{arg}"
    UnsupportedArgTypeError(ty, arg) =>
      "unsupported argument type \{ty}: \{arg}"
  }
  logger.write_string(msg)
}
