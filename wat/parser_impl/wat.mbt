// WAT (WebAssembly Text Format) Parser
// Parses WAT text format into WASM Module structures

///|
/// WAT Parser errors with location information and source context
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

///|
/// Format a WAT error with source code context for friendly display
/// Shows the relevant source line with a caret pointing to the error location
pub fn format_wat_error(err : WatError, source : String) -> String {
  let (msg, loc) = match err {
    UnexpectedToken(m, l) => ("unexpected token: \{m}", l)
    UnexpectedEof(l) => ("unexpected end of file", l)
    InvalidNumber(s, l) => ("invalid number: \{s}", l)
    InvalidInstruction(s, l) => ("invalid instruction: \{s}", l)
    UndefinedIdentifier(s, l) => ("undefined identifier: \{s}", l)
    DuplicateIdentifier(s, l) => ("duplicate identifier: \{s}", l)
    ParseError(m, l) => (m, l)
  }

  // Get the relevant source line
  let lines = split_lines(source)
  let line_idx = loc.line - 1
  let result = StringBuilder::new()
  result.write_string("error: ")
  result.write_string(msg)
  result.write_string("\n")
  result.write_string("  --> line \{loc.line}, column \{loc.column}\n")
  if line_idx >= 0 && line_idx < lines.length() {
    let line_content = lines[line_idx]
    let line_num_str = loc.line.to_string()
    let padding = String::make(line_num_str.length(), ' ')

    // Show line number and content
    result.write_string("   |\n")
    result.write_string(" \{line_num_str} | ")
    result.write_string(line_content)
    result.write_string("\n")

    // Show caret pointing to error
    result.write_string(" \{padding} | ")
    for _ in 1..<loc.column {
      result.write_char(' ')
    }
    result.write_string("^\n")
  }
  result.to_string()
}

///|
/// Split a string into lines
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current = StringBuilder::new()
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '\n' {
      lines.push(current.to_string())
      current.reset()
    } else if c != '\r' {
      current.write_char(c)
    }
  }

  // Add last line if not empty
  let last = current.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}
