///|
priv suberror CliError {
  FileNotFound(String)
  ParseModuleError(String)
  ParseWatError(String)
  FuncArgNumError(Int, Int)
  ArgTypeError(@types.ValueType, String)
  UnsupportedArgTypeError(@types.ValueType, String)
  ModuleNotFound(String)
  NoCurrentModule
  RuntimeError(String)
  TestError(String)
}

///|
impl Show for CliError with output(self, logger) {
  let msg = match self {
    FileNotFound(path) => "file \{path} not found"
    ParseModuleError(e) => "parse wasm module error: \{e}"
    ParseWatError(e) => "parse wat file error: \{e}"
    FuncArgNumError(expected, got) =>
      "expected \{expected} arguments, got \{got}"
    ArgTypeError(ty, arg) => "invalid \{ty} value: \{arg}"
    UnsupportedArgTypeError(ty, arg) =>
      "unsupported argument type \{ty}: \{arg}"
    ModuleNotFound(name) => "module \{name} not found"
    NoCurrentModule => "no current module"
    RuntimeError(e) => "runtime error: \{e}"
    TestError(e) => "testsuite error: \{e}"
  }
  logger.write_string(msg)
}
