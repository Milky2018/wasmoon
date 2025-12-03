// WAT (WebAssembly Text Format) Parser
// Parses WAT text format into WASM Module structures

///|
/// WAT Parser errors with location information
pub(all) suberror WatError {
  UnexpectedToken(String, SourceLoc)
  UnexpectedEof(SourceLoc)
  InvalidNumber(String, SourceLoc)
  InvalidInstruction(String, SourceLoc)
  UndefinedIdentifier(String, SourceLoc)
  DuplicateIdentifier(String, SourceLoc)
  ParseError(String, SourceLoc)
}

///|
fn WatError::to_string(self : WatError) -> String {
  match self {
    UnexpectedToken(msg, loc) => "at \{loc}: unexpected token: \{msg}"
    UnexpectedEof(loc) => "at \{loc}: unexpected end of file"
    InvalidNumber(s, loc) => "at \{loc}: invalid number: \{s}"
    InvalidInstruction(s, loc) => "at \{loc}: invalid instruction: \{s}"
    UndefinedIdentifier(s, loc) => "at \{loc}: undefined identifier: \{s}"
    DuplicateIdentifier(s, loc) => "at \{loc}: duplicate identifier: \{s}"
    ParseError(msg, loc) => "at \{loc}: \{msg}"
  }
}

///|
pub impl Show for WatError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Source location for error reporting
pub(all) struct SourceLoc {
  line : Int
  column : Int
}

///|
fn SourceLoc::to_string(self : SourceLoc) -> String {
  "\{self.line}:\{self.column}"
}

///|
pub impl Show for SourceLoc with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Default source location (for errors without specific location)
fn default_loc() -> SourceLoc {
  { line: 0, column: 0 }
}
