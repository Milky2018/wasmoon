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
/// WAT Lexer
priv struct Lexer {
  input : String
  mut pos : Int
  mut line : Int
  mut column : Int
  mut token_start_line : Int
  mut token_start_column : Int
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
              Some('\n') => {
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
        } else {
          break
        }
      _ => break
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
  let buf = StringBuilder::new()
  let start_loc = self.current_loc()
  // Skip opening quote
  self.advance_pos()
  while !self.is_eof() {
    match self.next_char() {
      Some('"') => return buf.to_string()
      Some('\\') =>
        match self.next_char() {
          Some('n') => buf.write_char('\n')
          Some('t') => buf.write_char('\t')
          Some('r') => buf.write_char('\r')
          Some('"') => buf.write_char('"')
          Some('\\') => buf.write_char('\\')
          Some(c) =>
            // Hex escape \xx
            if (c >= '0' && c <= '9') ||
              (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F') {
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
              buf.write_char(c)
            }
          None => raise UnexpectedEof(self.current_loc())
        }
      Some(c) => buf.write_char(c)
      None => raise UnexpectedEof(self.current_loc())
    }
  }
  raise UnexpectedEof(self.current_loc())
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
  // Check for "nan" or "inf"
  (c1 == 'n' && c2 == 'a' && c3 == 'n') || (c1 == 'i' && c2 == 'n' && c3 == 'f')
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
      if !self.is_eof() && self.peek_char() == Some(':') {
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
fn Lexer::next_token(self : Lexer) -> Token raise WatError {
  self.skip_whitespace()
  // Save token start position
  self.token_start_line = self.line
  self.token_start_column = self.column
  if self.is_eof() {
    return Eof
  }
  match self.peek_char() {
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
      let name = self.read_id_or_keyword()
      Id(name)
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
}
