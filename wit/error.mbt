///|
/// Minimal WIT (WebAssembly Interface Types) text parser/printer used by `wasmoon-tools`.
///
/// This is intentionally an MVP: it targets the subset needed for basic inspection
/// and will be expanded incrementally towards wasm-tools parity.

///|
pub(all) suberror WitError {
  Error(String)
}

///|
fn WitError::to_string(self : WitError) -> String {
  match self {
    Error(msg) => msg
  }
}

///|
pub impl Show for WitError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
