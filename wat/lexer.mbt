///|
/// Token types for WAT lexer
priv enum Token {
  LParen // (
  RParen // )
  Keyword(String) // module, func, param, etc.
  Id(String) // $name identifiers
  Number(String) // numeric literals
  String_(String) // string literals
  Eof
} derive(Show, Eq)

///|
/// Source span with start and end positions
priv struct SourceSpan {
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
} derive(Show)

///|
/// Token with source location and raw text
priv struct LocatedToken {
  token : Token
  span : SourceSpan
  raw : String // Original text representation
} derive(Show)

///|
fn LocatedToken::to_loc(self : LocatedToken) -> SourceLoc {
  { line: self.span.start_line, column: self.span.start_column }
}

///|
/// Create a synthetic LocatedToken for push-back operations during lookahead
fn LocatedToken::synthetic(token : Token) -> LocatedToken {
  {
    token,
    span: { start_line: 0, start_column: 0, end_line: 0, end_column: 0 },
    raw: "",
  }
}

///|
/// Extract substring from input without raising errors
fn extract_substring(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i in start..<end {
    buf.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  buf.to_string()
}

///|
/// WAT Lexer
priv struct Lexer {
  input : String
  mut pos : Int
  mut line : Int
  mut column : Int
  mut token_start_line : Int
  mut token_start_column : Int
  mut token_start_pos : Int
}

///|
fn Lexer::new(input : String) -> Lexer {
  {
    input,
    pos: 0,
    line: 1,
    column: 1,
    token_start_line: 1,
    token_start_column: 1,
    token_start_pos: 0,
  }
}

///|
fn Lexer::current_loc(self : Lexer) -> SourceLoc {
  { line: self.token_start_line, column: self.token_start_column }
}

///|
fn Lexer::is_eof(self : Lexer) -> Bool {
  self.pos >= self.input.length()
}

///|
fn Lexer::peek_char(self : Lexer) -> Char? {
  if self.is_eof() {
    None
  } else {
    Some(self.input.code_unit_at(self.pos).unsafe_to_char())
  }
}

///|
fn Lexer::next_char(self : Lexer) -> Char? {
  if self.is_eof() {
    None
  } else {
    let c = self.input.code_unit_at(self.pos).unsafe_to_char()
    self.pos += 1
    if c == '\n' {
      self.line += 1
      self.column = 1
    } else {
      self.column += 1
    }
    Some(c)
  }
}

///|
/// Advance position by one character, updating line/column
fn Lexer::advance_pos(self : Lexer) -> Unit {
  if !self.is_eof() {
    let c = self.input.code_unit_at(self.pos).unsafe_to_char()
    self.pos += 1
    if c == '\n' {
      self.line += 1
      self.column = 1
    } else {
      self.column += 1
    }
  }
}

///|
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => self.advance_pos()
      Some(';') =>
        // Skip line comment
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while !self.is_eof() {
            match self.peek_char() {
              Some('\n') | Some('\r') => {
                self.advance_pos()
                break
              }
              _ => self.advance_pos()
            }
          }
        } else {
          break
        }
      Some('(') =>
        // Check for block comment (; ... ;)
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          self.advance_pos()
          self.advance_pos()
          let mut depth = 1
          while !self.is_eof() && depth > 0 {
            if self.pos + 1 < self.input.length() {
              let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
              let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
              if c1 == ';' && c2 == ')' {
                depth -= 1
                self.advance_pos()
                self.advance_pos()
              } else if c1 == '(' && c2 == ';' {
                depth += 1
                self.advance_pos()
                self.advance_pos()
              } else {
                self.advance_pos()
              }
            } else {
              self.advance_pos()
            }
          }
        } else if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == '@' {
          // Skip annotation (@id ...)
          self.skip_annotation()
        } else {
          break
        }
      _ => break
    }
  }
}

///|
/// Skip an annotation (@id ...) including nested parentheses
fn Lexer::skip_annotation(self : Lexer) -> Unit {
  // Skip '(@'
  self.advance_pos()
  self.advance_pos()
  // Skip annotation id (can be identifier or string)
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => break
      Some('(') | Some(')') => break
      Some('"') => {
        // Skip string in annotation id
        self.advance_pos()
        while !self.is_eof() {
          match self.peek_char() {
            Some('"') => {
              self.advance_pos()
              break
            }
            Some('\\') => {
              self.advance_pos()
              self.advance_pos() // skip escaped char
            }
            _ => self.advance_pos()
          }
        }
        break
      }
      _ => self.advance_pos()
    }
  }
  // Skip whitespace after id
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => self.advance_pos()
      _ => break
    }
  }
  // Skip content with balanced parentheses until closing ')'
  let mut depth = 1
  while !self.is_eof() && depth > 0 {
    match self.peek_char() {
      Some('(') =>
        // Check for nested annotation or block comment
        if self.pos + 1 < self.input.length() {
          let next = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
          if next == ';' {
            // Block comment inside annotation - skip it
            self.advance_pos()
            self.advance_pos()
            let mut comment_depth = 1
            while !self.is_eof() && comment_depth > 0 {
              if self.pos + 1 < self.input.length() {
                let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
                let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
                if c1 == ';' && c2 == ')' {
                  comment_depth -= 1
                  self.advance_pos()
                  self.advance_pos()
                } else if c1 == '(' && c2 == ';' {
                  comment_depth += 1
                  self.advance_pos()
                  self.advance_pos()
                } else {
                  self.advance_pos()
                }
              } else {
                self.advance_pos()
              }
            }
          } else {
            depth += 1
            self.advance_pos()
          }
        } else {
          depth += 1
          self.advance_pos()
        }
      Some(')') => {
        depth -= 1
        self.advance_pos()
      }
      Some('"') => {
        // Skip string inside annotation
        self.advance_pos()
        while !self.is_eof() {
          match self.peek_char() {
            Some('"') => {
              self.advance_pos()
              break
            }
            Some('\\') => {
              self.advance_pos()
              self.advance_pos() // skip escaped char
            }
            _ => self.advance_pos()
          }
        }
      }
      Some(';') =>
        // Check for line comment inside annotation
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while !self.is_eof() {
            match self.peek_char() {
              Some('\n') | Some('\r') => {
                self.advance_pos()
                break
              }
              _ => self.advance_pos()
            }
          }
        } else {
          self.advance_pos()
        }
      _ => self.advance_pos()
    }
  }
}

///|
fn is_idchar(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '!' ||
  c == '#' ||
  c == '$' ||
  c == '%' ||
  c == '&' ||
  c == '\'' ||
  c == '*' ||
  c == '+' ||
  c == '-' ||
  c == '.' ||
  c == '/' ||
  c == ':' ||
  c == '<' ||
  c == '=' ||
  c == '>' ||
  c == '?' ||
  c == '@' ||
  c == '\\' ||
  c == '^' ||
  c == '_' ||
  c == '`' ||
  c == '|' ||
  c == '~'
}

///|
fn Lexer::read_id_or_keyword(self : Lexer) -> String {
  let buf = StringBuilder::new()
  while !self.is_eof() {
    match self.peek_char() {
      Some(c) =>
        if is_idchar(c) {
          buf.write_char(c)
          self.advance_pos()
        } else {
          break
        }
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::read_string(self : Lexer) -> String raise WatError {
  // Write directly to StringBuilder - hex escapes produce raw byte values
  // that are stored as character code units (not UTF-8 interpreted)
  let buf = StringBuilder::new()
  let start_loc = self.current_loc()
  // Skip opening quote
  self.advance_pos()
  while !self.is_eof() {
    match self.peek_char() {
      Some('"') => {
        self.advance_pos()
        return buf.to_string()
      }
      Some('\\') => {
        self.advance_pos()
        match self.next_char() {
          Some('n') => buf.write_char('\n')
          Some('t') => buf.write_char('\t')
          Some('r') => buf.write_char('\r')
          Some('"') => buf.write_char('"')
          Some('\\') => buf.write_char('\\')
          Some('\'') => buf.write_char('\'')
          Some('u') =>
            // Unicode escape \u{xxxx}
            match self.next_char() {
              Some('{') => {
                let hex_buf = StringBuilder::new()
                while !self.is_eof() {
                  match self.peek_char() {
                    Some('}') => {
                      self.advance_pos()
                      break
                    }
                    Some(c) =>
                      if is_hex_digit(c) {
                        hex_buf.write_char(c)
                        self.advance_pos()
                      } else {
                        raise WatError::ParseError(
                          "Invalid Unicode escape: expected hex digit or '}'",
                          self.current_loc(),
                        )
                      }
                    None => raise WatError::UnexpectedEof(self.current_loc())
                  }
                }
                let hex = hex_buf.to_string()
                if hex.is_empty() {
                  raise WatError::ParseError("Empty Unicode escape", start_loc)
                }
                match parse_hex_codepoint(hex) {
                  Some(cp) => buf.write_char(cp.unsafe_to_char())
                  None =>
                    raise WatError::ParseError(
                      "Invalid Unicode escape: \\u{\{hex}}",
                      start_loc,
                    )
                }
              }
              _ =>
                raise WatError::ParseError(
                  "Invalid Unicode escape: expected '{'",
                  self.current_loc(),
                )
            }
          Some(c) =>
            // Hex escape \xx - produces a raw byte value as character
            if is_hex_digit(c) {
              match self.next_char() {
                Some(c2) => {
                  let hex = String::make(1, c) + String::make(1, c2)
                  match parse_hex_byte(hex) {
                    Some(b) => buf.write_char(b.unsafe_to_char())
                    None =>
                      raise WatError::ParseError(
                        "Invalid hex escape: \{hex}",
                        start_loc,
                      )
                  }
                }
                None => raise WatError::UnexpectedEof(self.current_loc())
              }
            } else {
              // Unknown escape - just output the character
              buf.write_char(c)
            }
          None => raise WatError::UnexpectedEof(self.current_loc())
        }
      }
      Some(_) =>
        // Regular character
        match self.next_char() {
          Some(c) => buf.write_char(c)
          None => raise WatError::UnexpectedEof(self.current_loc())
        }
      None => raise WatError::UnexpectedEof(self.current_loc())
    }
  }
  raise WatError::UnexpectedEof(self.current_loc())
}

///|
/// Read a string used as identifier name - hex escapes are decoded as UTF-8
fn Lexer::read_id_string(self : Lexer) -> String raise WatError {
  // Accumulate bytes, then decode as UTF-8
  // This ensures $"\ef\98\9a" matches $"" (emoji)
  let bytes : Array[Int] = []
  let start_loc = self.current_loc()
  // Skip opening quote
  self.advance_pos()
  while !self.is_eof() {
    match self.peek_char() {
      Some('"') => {
        self.advance_pos()
        return decode_utf8_bytes(bytes)
      }
      Some('\\') => {
        self.advance_pos()
        match self.next_char() {
          Some('n') => bytes.push(0x0A)
          Some('t') => bytes.push(0x09)
          Some('r') => bytes.push(0x0D)
          Some('"') => bytes.push(0x22)
          Some('\\') => bytes.push(0x5C)
          Some('\'') => bytes.push(0x27)
          Some('u') =>
            // Unicode escape \u{xxxx} - encode as UTF-8 bytes
            match self.next_char() {
              Some('{') => {
                let hex_buf = StringBuilder::new()
                while !self.is_eof() {
                  match self.peek_char() {
                    Some('}') => {
                      self.advance_pos()
                      break
                    }
                    Some(c) =>
                      if is_hex_digit(c) {
                        hex_buf.write_char(c)
                        self.advance_pos()
                      } else {
                        raise WatError::ParseError(
                          "Invalid Unicode escape: expected hex digit or '}'",
                          self.current_loc(),
                        )
                      }
                    None => raise WatError::UnexpectedEof(self.current_loc())
                  }
                }
                let hex = hex_buf.to_string()
                if hex.is_empty() {
                  raise WatError::ParseError("Empty Unicode escape", start_loc)
                }
                match parse_hex_codepoint(hex) {
                  Some(cp) => encode_utf8_codepoint(bytes, cp)
                  None =>
                    raise WatError::ParseError(
                      "Invalid Unicode escape: \\u{\{hex}}",
                      start_loc,
                    )
                }
              }
              _ =>
                raise WatError::ParseError(
                  "Invalid Unicode escape: expected '{'",
                  self.current_loc(),
                )
            }
          Some(c) =>
            // Hex escape \xx - produces a raw byte
            if is_hex_digit(c) {
              match self.next_char() {
                Some(c2) => {
                  let hex = String::make(1, c) + String::make(1, c2)
                  match parse_hex_byte(hex) {
                    Some(b) => bytes.push(b)
                    None =>
                      raise WatError::ParseError(
                        "Invalid hex escape: \{hex}",
                        start_loc,
                      )
                  }
                }
                None => raise WatError::UnexpectedEof(self.current_loc())
              }
            } else {
              // Unknown escape - encode as UTF-8
              encode_utf8_codepoint(bytes, c.to_int())
            }
          None => raise WatError::UnexpectedEof(self.current_loc())
        }
      }
      Some(_) =>
        // Regular character - encode as UTF-8
        match self.next_char() {
          Some(c) => encode_utf8_codepoint(bytes, c.to_int())
          None => raise WatError::UnexpectedEof(self.current_loc())
        }
      None => raise WatError::UnexpectedEof(self.current_loc())
    }
  }
  raise WatError::UnexpectedEof(self.current_loc())
}

///|
/// Encode a Unicode codepoint as UTF-8 bytes
fn encode_utf8_codepoint(bytes : Array[Int], cp : Int) -> Unit {
  if cp < 0x80 {
    bytes.push(cp)
  } else if cp < 0x800 {
    bytes.push(0xC0 | (cp >> 6))
    bytes.push(0x80 | (cp & 0x3F))
  } else if cp < 0x10000 {
    bytes.push(0xE0 | (cp >> 12))
    bytes.push(0x80 | ((cp >> 6) & 0x3F))
    bytes.push(0x80 | (cp & 0x3F))
  } else {
    bytes.push(0xF0 | (cp >> 18))
    bytes.push(0x80 | ((cp >> 12) & 0x3F))
    bytes.push(0x80 | ((cp >> 6) & 0x3F))
    bytes.push(0x80 | (cp & 0x3F))
  }
}

///|
/// Decode UTF-8 bytes to a string
fn decode_utf8_bytes(bytes : Array[Int]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i]
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      // Invalid leading byte, treat as raw
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xE0 {
      // 2-byte sequence
      if i + 1 < bytes.length() {
        let b2 = bytes[i + 1]
        let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
        buf.write_char(cp.unsafe_to_char())
        i = i + 2
      } else {
        buf.write_char(b.unsafe_to_char())
        i = i + 1
      }
    } else if b < 0xF0 {
      // 3-byte sequence
      if i + 2 < bytes.length() {
        let b2 = bytes[i + 1]
        let b3 = bytes[i + 2]
        let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        buf.write_char(cp.unsafe_to_char())
        i = i + 3
      } else {
        buf.write_char(b.unsafe_to_char())
        i = i + 1
      }
      // 4-byte sequence
    } else if i + 3 < bytes.length() {
      let b2 = bytes[i + 1]
      let b3 = bytes[i + 2]
      let b4 = bytes[i + 3]
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    }
  }
  buf.to_string()
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn parse_hex_codepoint(s : String) -> Int? {
  let mut value = 0
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    match hex_digit_value(c) {
      Some(digit) => value = value * 16 + digit
      None => return None
    }
  }
  // Check valid Unicode codepoint range
  if value > 0x10FFFF {
    return None
  }
  Some(value)
}

///|
fn parse_hex_byte(s : String) -> Int? {
  if s.length() != 2 {
    return None
  }
  let c1 = s.code_unit_at(0).unsafe_to_char()
  let c2 = s.code_unit_at(1).unsafe_to_char()
  let d1 = hex_digit_value(c1)
  let d2 = hex_digit_value(c2)
  match (d1, d2) {
    (Some(v1), Some(v2)) => Some(v1 * 16 + v2)
    _ => None
  }
}

///|
fn hex_digit_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Check if the next characters are "nan" or "inf" (special float literals)
fn Lexer::check_nan_or_inf(self : Lexer) -> Bool {
  if self.pos + 2 >= self.input.length() {
    return false
  }
  let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
  let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
  let c3 = self.input.code_unit_at(self.pos + 2).unsafe_to_char()
  // Check for "inf" - always treat as number
  if c1 == 'i' && c2 == 'n' && c3 == 'f' {
    return true
  }
  // Check for "nan"
  if c1 == 'n' && c2 == 'a' && c3 == 'n' {
    // Check if followed by :canonical or :arithmetic - those should be keywords
    if self.pos + 13 <= self.input.length() {
      let rest13 = extract_substring(self.input, self.pos, self.pos + 13)
      if rest13 == "nan:canonical" {
        return false // Let it be parsed as a keyword
      }
    }
    if self.pos + 14 <= self.input.length() {
      let rest14 = extract_substring(self.input, self.pos, self.pos + 14)
      if rest14 == "nan:arithmetic" {
        return false // Let it be parsed as a keyword
      }
    }
    return true
  }
  false
}

///|
fn Lexer::read_number(self : Lexer) -> String {
  let buf = StringBuilder::new()
  // Handle optional sign
  if self.peek_char() is (Some('-') | Some('+')) {
    buf.write_char(self.next_char().unwrap())
  }
  // Handle "inf" after sign (e.g., -inf, +inf)
  if self.pos + 2 < self.input.length() {
    let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
    let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
    let c3 = self.input.code_unit_at(self.pos + 2).unsafe_to_char()
    if c1 == 'i' && c2 == 'n' && c3 == 'f' {
      buf.write_string("inf")
      self.pos += 3
      self.column += 3
      return buf.to_string()
    }
    // Handle "nan" after sign (e.g., -nan, +nan, -nan:0x200000)
    if c1 == 'n' && c2 == 'a' && c3 == 'n' {
      buf.write_string("nan")
      self.pos += 3
      self.column += 3
      // Check for nan:payload format
      if !self.is_eof() && self.peek_char() is Some(':') {
        buf.write_char(':')
        self.advance_pos()
        // Read payload (hex number with optional underscores)
        while !self.is_eof() {
          match self.peek_char() {
            Some(c) =>
              if (c >= '0' && c <= '9') ||
                (c >= 'a' && c <= 'f') ||
                (c >= 'A' && c <= 'F') ||
                c == 'x' ||
                c == 'X' ||
                c == '_' {
                // Skip underscores but consume them
                if c != '_' {
                  buf.write_char(c)
                }
                self.advance_pos()
              } else {
                break
              }
            None => break
          }
        }
      }
      return buf.to_string()
    }
  }
  // Handle 0x prefix for hex
  if self.pos + 1 < self.input.length() {
    let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
    let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
    if c1 == '0' && (c2 == 'x' || c2 == 'X') {
      buf.write_char(c1)
      buf.write_char(c2)
      self.advance_pos()
      self.advance_pos()
    }
  }
  // Read digits
  while !self.is_eof() {
    match self.peek_char() {
      Some(c) =>
        if (c >= '0' && c <= '9') ||
          (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F') ||
          c == '_' ||
          c == '.' ||
          c == 'p' ||
          c == 'P' ||
          c == 'e' ||
          c == 'E' ||
          c == '+' ||
          c == '-' {
          if c != '_' {
            buf.write_char(c)
          }
          self.advance_pos()
        } else {
          break
        }
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::next_token(self : Lexer) -> LocatedToken raise WatError {
  self.skip_whitespace()
  // Save token start position
  let start_pos = self.pos
  let start_line = self.line
  let start_column = self.column
  self.token_start_line = start_line
  self.token_start_column = start_column
  self.token_start_pos = start_pos
  if self.is_eof() {
    return {
      token: Eof,
      span: {
        start_line,
        start_column,
        end_line: start_line,
        end_column: start_column,
      },
      raw: "",
    }
  }
  let token = match self.peek_char() {
    Some('(') => {
      self.advance_pos()
      LParen
    }
    Some(')') => {
      self.advance_pos()
      RParen
    }
    Some('$') => {
      self.advance_pos()
      // Check for string identifier like $"foo"
      if self.peek_char() == Some('"') {
        let name = self.read_id_string()
        Id(name)
      } else {
        let name = self.read_id_or_keyword()
        Id(name)
      }
    }
    Some('"') => {
      let s = self.read_string()
      String_(s)
    }
    Some(c) =>
      if (c >= '0' && c <= '9') || c == '-' || c == '+' {
        let num = self.read_number()
        Number(num)
      } else if c == 'n' || c == 'i' {
        // Check for nan or inf (special float literals)
        if self.check_nan_or_inf() {
          let num = self.read_number()
          Number(num)
        } else if is_idchar(c) {
          let kw = self.read_id_or_keyword()
          Keyword(kw)
        } else {
          raise WatError::UnexpectedToken(
            String::make(1, c),
            self.current_loc(),
          )
        }
      } else if is_idchar(c) {
        let kw = self.read_id_or_keyword()
        Keyword(kw)
      } else {
        raise WatError::UnexpectedToken(String::make(1, c), self.current_loc())
      }
    None => Eof
  }
  // Extract raw text
  let end_pos = self.pos
  let raw = extract_substring(self.input, start_pos, end_pos)
  {
    token,
    span: {
      start_line,
      start_column,
      end_line: self.line,
      end_column: self.column,
    },
    raw,
  }
}
