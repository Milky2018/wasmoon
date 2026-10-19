///|
/// Token types for WAT lexer
priv enum Token {
  LParen // (
  RParen // )
  Keyword(String) // module, func, param, etc.
  Id(String) // $name identifiers
  Number(String) // numeric literals
  String_(String) // byte strings, one code unit per byte
  Eof
} derive(Debug, Eq)

///|
/// Source span with start and end positions
priv struct SourceSpan {
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
} derive(Debug)

///|
/// Token with source location and raw text
priv struct LocatedToken {
  token : Token
  span : SourceSpan
  raw : String // Original text representation
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
impl Show for Token with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
impl Show for LocatedToken with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
fn LocatedToken::to_loc(self : LocatedToken) -> SourceLoc {
  { line: self.span.start_line, column: self.span.start_column, }
}

///|
/// Create a synthetic LocatedToken for push-back operations during lookahead
fn LocatedToken::synthetic(token : Token) -> LocatedToken {
  {
    token,
    span: { start_line: 0, start_column: 0, end_line: 0, end_column: 0, },
    raw: "",
  }
}

///|
/// Extract substring from input without raising errors
fn extract_substring(s : String, start : Int32, end : Int32) -> String {
  let buf = StringBuilder::StringBuilder()
  for i in start..<end {
    buf.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  buf.to_string()
}

///|
/// WAT Lexer
priv struct Lexer {
  input : String
  mut pos : Int32
  mut line : Int32
  mut column : Int32
  mut token_start_line : Int32
  mut token_start_column : Int32
  mut token_start_pos : Int32
}

///|
fn Lexer::Lexer(input : String) -> Lexer {
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
  { line: self.token_start_line, column: self.token_start_column, }
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
    let first = self.input.code_unit_at(self.pos)
    let c = if first >= 0xd800 &&
      first <= 0xdbff &&
      self.pos + 1 < self.input.length() {
      let low = self.input.code_unit_at(self.pos + 1)
      if low >= 0xdc00 && low <= 0xdfff {
        self.pos += 1
        (0x10000 + ((first.to_int() - 0xd800) << 10) + low.to_int() - 0xdc00).unsafe_to_char()
      } else {
        first.unsafe_to_char()
      }
    } else {
      first.unsafe_to_char()
    }
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
fn Lexer::skip_whitespace(self : Lexer) -> Unit raise WatError {
  while !self.is_eof() {
    let c = self.peek_char()
    if c is Some(' ') || c is Some('\t') || c is Some('\n') || c is Some('\r') {
      self.advance_pos()
    } else if c is Some(';') {
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
    } else if c is Some('(') {
      // Check for block comment (; ... ;)
      if self.pos + 1 < self.input.length() &&
        self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
        self.skip_block_comment()
      } else if self.pos + 1 < self.input.length() &&
        self.input.code_unit_at(self.pos + 1).unsafe_to_char() == '@' {
        // Skip annotation (@id ...)
        self.skip_annotation()
      } else {
        break
      }
    } else {
      break
    }
  }
}

///|
fn Lexer::skip_block_comment(self : Lexer) -> Unit raise WatError {
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
  if depth != 0 {
    raise UnexpectedEof(self.current_loc())
  }
}

///|
// Annotation payloads permit arbitrary printable ASCII atoms, but strings,
// comments and balanced delimiters retain their lexical contracts.
fn Lexer::skip_annotation(self : Lexer) -> Unit raise WatError {
  self.advance_pos()
  self.advance_pos()
  let name = if self.peek_char() == Some('"') {
    self.read_id_string()
  } else {
    self.read_id_or_keyword()
  }
  if name.is_empty() {
    raise ParseError("Empty annotation identifier", self.current_loc())
  }
  let mut depth = 1
  while !self.is_eof() {
    match self.peek_char() {
      Some('"') => self.read_string() |> ignore
      Some('(') =>
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1) == 59 {
          self.skip_block_comment()
        } else {
          depth += 1
          self.advance_pos()
        }
      Some(')') => {
        self.advance_pos()
        depth -= 1
        if depth == 0 {
          return
        }
      }
      Some(';') =>
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1) == 59 {
          while !self.is_eof() &&
                self.peek_char() != Some('\n') &&
                self.peek_char() != Some('\r') {
            self.advance_pos()
          }
        } else {
          self.advance_pos()
        }
      Some(c) => {
        let cp = c.to_int()
        if (cp < 32 && c != '\t' && c != '\n' && c != '\r') || cp >= 127 {
          raise ParseError("Illegal annotation character", self.current_loc())
        }
        self.advance_pos()
      }
      None => break
    }
  }
  raise UnexpectedEof(self.current_loc())
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
  let buf = StringBuilder::StringBuilder()
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
  // Store bytes as code units; data and binary strings need not be UTF-8.
  // Text consumers decode explicitly, without Unicode normalization.
  let buf = StringBuilder::StringBuilder()
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
                let hex_buf = StringBuilder::StringBuilder()
                while !self.is_eof() {
                  match self.peek_char() {
                    Some('}') => {
                      self.advance_pos()
                      break
                    }
                    Some(c) =>
                      if is_hex_digit(c) || c == '_' {
                        hex_buf.write_char(c)
                        self.advance_pos()
                      } else {
                        raise ParseError(
                          "Invalid Unicode escape: expected hex digit or '}'",
                          self.current_loc(),
                        )
                      }
                    None => raise UnexpectedEof(self.current_loc())
                  }
                }
                let hex = hex_buf.to_string()
                if hex.is_empty() {
                  raise ParseError("Empty Unicode escape", start_loc)
                }
                match parse_hex_codepoint(hex) {
                  Some(cp) => write_string_codepoint(buf, cp)
                  None =>
                    raise ParseError(
                      "Invalid Unicode escape: \\u{\{hex}}",
                      start_loc,
                    )
                }
              }
              _ =>
                raise ParseError(
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
                      raise ParseError("Invalid hex escape: \{hex}", start_loc)
                  }
                }
                None => raise UnexpectedEof(self.current_loc())
              }
            } else {
              raise ParseError("Unknown string escape", start_loc)
            }
          None => raise UnexpectedEof(self.current_loc())
        }
      }
      Some(_) =>
        // Regular character
        match self.next_char() {
          Some(c) => {
            if c.to_int() < 0x20 ||
              c.to_int() == 0x7f ||
              (c.to_int() >= 0xd800 && c.to_int() <= 0xdfff) {
              raise ParseError("Control character in string", start_loc)
            }
            write_string_codepoint(buf, c.to_int())
          }
          None => raise UnexpectedEof(self.current_loc())
        }
      None => raise UnexpectedEof(self.current_loc())
    }
  }
  raise UnexpectedEof(self.current_loc())
}

///|
/// Read a string used as identifier name - hex escapes are decoded as UTF-8
fn Lexer::read_id_string(self : Lexer) -> String raise WatError {
  decode_text(self.read_string())
}

///|
/// Encode a Unicode codepoint as UTF-8 bytes
fn encode_utf8_codepoint(bytes : Array[Int32], cp : Int32) -> Unit {
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
// String tokens contain bytes, including arbitrary data/binary payloads. Only
// text consumers (names and quoted source) decode them as UTF-8.
fn decode_text(bytes : String) -> String raise WatError {
  @utf8.decode(
    Bytes::from_array(bytes.iter().map(c => c.to_int().to_byte()).collect()),
    ignore_bom=false,
  ) catch {
    _ => raise ParseError("Invalid UTF-8 text", default_loc())
  }
}

///|
fn write_string_codepoint(buf : StringBuilder, cp : Int32) -> Unit {
  let bytes : Array[Int32] = []
  encode_utf8_codepoint(bytes, cp)
  for b in bytes {
    buf.write_char(b.unsafe_to_char())
  }
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn parse_hex_codepoint(s : String) -> Int32? {
  let valid = try literal_digits(s, 0, 16) == s.length() catch {
    _ => false
  }
  if !valid {
    return None
  }
  let mut value = 0
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue
    }
    match hex_digit_value(c) {
      Some(digit) => {
        if value > (0x10ffff - digit) / 16 {
          return None
        }
        value = value * 16 + digit
      }
      None => return None
    }
  }
  // Check valid Unicode codepoint range
  if value > 0x10FFFF || (value >= 0xd800 && value <= 0xdfff) {
    return None
  }
  Some(value)
}

///|
fn parse_hex_byte(s : String) -> Int32? {
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
fn hex_digit_value(c : Char) -> Int32? {
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
  self.read_id_or_keyword()
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
        if name.is_empty() {
          raise ParseError("Empty identifier", self.current_loc())
        }
        Id(name)
      } else {
        let name = self.read_id_or_keyword()
        if name.is_empty() {
          raise ParseError("Empty identifier", self.current_loc())
        }
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
          raise UnexpectedToken(String::make(1, c), self.current_loc())
        }
      } else if is_idchar(c) {
        let kw = self.read_id_or_keyword()
        Keyword(kw)
      } else {
        raise UnexpectedToken(String::make(1, c), self.current_loc())
      }
    None => Eof
  }
  match token {
    LParen | RParen | Eof => ()
    _ =>
      match self.peek_char() {
        Some(c) if c == '"' || is_idchar(c) =>
          raise ParseError("Missing token separator", self.current_loc())
        _ => ()
      }
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
