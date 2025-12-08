// WAST (WebAssembly Test Script) Parser
// Parses WAST test format which extends WAT with test assertions
//
// WAST format includes:
// - Module definitions (same as WAT)
// - assert_return: test that a function returns expected values
// - assert_trap: test that execution traps
// - assert_invalid: test that a module fails validation
// - assert_malformed: test that a module fails parsing
// - register: register a module for imports
// - invoke: invoke a function (without assertion)

///|
/// WAST Parser errors
pub(all) suberror WastError {
  UnexpectedToken(String)
  UnexpectedEof
  InvalidNumber(String)
  InvalidInstruction(String)
  ParseError(String)
  WatError(@wat.WatError)
} derive(Show)

///|
/// Token types for WAST lexer (same as WAT)
priv enum Token {
  LParen
  RParen
  Keyword(String)
  Id(String)
  Number(String)
  String_(String)
  Eof
} derive(Show, Eq)

///|
/// WAST command types
pub enum WastCommand {
  Module(@types.Module, String?) // module and optional name
  ModuleQuote(Array[String]) // quoted module (for malformed tests)
  ModuleBinaryFailed(String) // binary module that failed to parse (skip in tests)
  AssertReturn(WastAction, Array[WastValue])
  AssertTrap(WastAction, String)
  AssertExhaustion(WastAction, String)
  AssertInvalid(WastModuleSource, String)
  AssertMalformed(WastModuleSource, String)
  AssertUnlinkable(WastModuleSource, String)
  Register(String, String?) // name, module_name
  Action(WastAction)
} derive(Show)

///|
/// Module source for assert_invalid/malformed
pub enum WastModuleSource {
  Binary(Bytes)
  Quote(Array[String])
  Inline(@types.Module)
  /// Module that failed to parse (used for assert_invalid/malformed tests)
  FailedToParse(String)
} derive(Show)

///|
/// WAST action (invoke or get)
pub enum WastAction {
  Invoke(String?, String, Array[WastValue]) // module_name, func_name, args
  Get(String?, String) // module_name, global_name
} derive(Show)

///|
/// WAST value (typed constant)
pub enum WastValue {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  // Special float values
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
  // Reference types
  RefNull(String) // type: "func" or "extern"
  RefExtern(Int)
  RefFunc
} derive(Show)

///|
/// WAST script (collection of commands)
pub struct WastScript {
  commands : Array[WastCommand]
}

///|
/// WAST Lexer
priv struct Lexer {
  input : String
  mut pos : Int
}

///|
fn Lexer::new(input : String) -> Lexer {
  { input, pos: 0 }
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
    Some(c)
  }
}

///|
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => self.pos += 1
      Some(';') =>
        // Skip line comment
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while !self.is_eof() {
            match self.peek_char() {
              Some('\n') => {
                self.pos += 1
                break
              }
              _ => self.pos += 1
            }
          }
        } else {
          break
        }
      Some('(') =>
        // Check for block comment (; ... ;)
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          self.pos += 2
          let mut depth = 1
          while !self.is_eof() && depth > 0 {
            if self.pos + 1 < self.input.length() {
              let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
              let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
              if c1 == ';' && c2 == ')' {
                depth -= 1
                self.pos += 2
              } else if c1 == '(' && c2 == ';' {
                depth += 1
                self.pos += 2
              } else {
                self.pos += 1
              }
            } else {
              self.pos += 1
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
          self.pos += 1
        } else {
          break
        }
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::read_string(self : Lexer) -> String raise WastError {
  let buf = StringBuilder::new()
  self.pos += 1 // skip opening quote
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
          Some('\'') => buf.write_char('\'')
          Some(c) =>
            // Check if this is a hex escape sequence (two hex digits)
            if (c >= '0' && c <= '9') ||
              (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F') {
              // Read second hex digit
              match self.next_char() {
                Some(c2) => {
                  let hex = String::make(1, c) + String::make(1, c2)
                  match parse_hex_byte(hex) {
                    Some(b) => buf.write_char(b.unsafe_to_char())
                    None => raise ParseError("Invalid hex escape: \{hex}")
                  }
                }
                None => raise UnexpectedEof
              }
            } else {
              // Unknown escape, just write the character
              buf.write_char(c)
            }
          None => raise UnexpectedEof
        }
      Some(c) => buf.write_char(c)
      None => raise UnexpectedEof
    }
  }
  raise UnexpectedEof
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
/// Escape a string for WAT format output
/// Converts special characters and non-printable bytes to escape sequences
fn escape_string_to(s : String, buf : StringBuilder) -> Unit {
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    if c == '"'.to_int() {
      buf.write_string("\\\"")
    } else if c == '\\'.to_int() {
      buf.write_string("\\\\")
    } else if c == '\n'.to_int() {
      buf.write_string("\\n")
    } else if c == '\r'.to_int() {
      buf.write_string("\\r")
    } else if c == '\t'.to_int() {
      buf.write_string("\\t")
    } else if c >= 0x20 && c < 0x7f {
      // Printable ASCII
      buf.write_char(c.unsafe_to_char())
    } else {
      // Non-printable: use hex escape
      buf.write_string("\\")
      buf.write_char(hex_char((c / 16) & 0x0f))
      buf.write_char(hex_char(c & 0x0f))
    }
  }
}

///|
/// Convert a nibble (0-15) to hex character
fn hex_char(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + n - 10).unsafe_to_char()
  }
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
      return buf.to_string()
    }
    // Handle "nan" after sign (e.g., -nan, +nan, -nan:0x200000)
    if c1 == 'n' && c2 == 'a' && c3 == 'n' {
      buf.write_string("nan")
      self.pos += 3
      // Check for nan:payload format
      if !self.is_eof() && self.peek_char() == Some(':') {
        buf.write_char(':')
        self.pos += 1
        // Read payload (hex number)
        while !self.is_eof() {
          match self.peek_char() {
            Some(c) =>
              if (c >= '0' && c <= '9') ||
                (c >= 'a' && c <= 'f') ||
                (c >= 'A' && c <= 'F') ||
                c == 'x' ||
                c == 'X' {
                buf.write_char(c)
                self.pos += 1
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
      self.pos += 2
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
          self.pos += 1
        } else {
          break
        }
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::next_token(self : Lexer) -> Token raise WastError {
  self.skip_whitespace()
  if self.is_eof() {
    return Eof
  }
  match self.peek_char() {
    Some('(') => {
      self.pos += 1
      LParen
    }
    Some(')') => {
      self.pos += 1
      RParen
    }
    Some('$') => {
      self.pos += 1
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
      } else if is_idchar(c) {
        let kw = self.read_id_or_keyword()
        Keyword(kw)
      } else {
        raise UnexpectedToken(String::make(1, c))
      }
    None => Eof
  }
}

///|
/// WAST Parser
priv struct Parser {
  lexer : Lexer
  mut current : Token
}

///|
fn Parser::new(input : String) -> Parser raise WastError {
  let lexer = Lexer::new(input)
  let first_token = lexer.next_token()
  { lexer, current: first_token }
}

///|
fn Parser::advance(self : Parser) -> Unit raise WastError {
  self.current = self.lexer.next_token()
}

///|
fn Parser::expect_lparen(self : Parser) -> Unit raise WastError {
  match self.current {
    LParen => self.advance()
    _ => raise UnexpectedToken("expected '(', got \{self.current}")
  }
}

///|
fn Parser::expect_rparen(self : Parser) -> Unit raise WastError {
  match self.current {
    RParen => self.advance()
    _ => raise UnexpectedToken("expected ')', got \{self.current}")
  }
}

///|
fn Parser::expect_keyword(self : Parser, kw : String) -> Unit raise WastError {
  match self.current {
    Keyword(k) =>
      if k == kw {
        self.advance()
      } else {
        raise UnexpectedToken("expected '\{kw}', got '\{k}'")
      }
    _ => raise UnexpectedToken("expected '\{kw}', got \{self.current}")
  }
}

///|
fn Parser::parse_string(self : Parser) -> String raise WastError {
  match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected string, got \{self.current}")
  }
}

///|
fn Parser::parse_optional_id(self : Parser) -> String? raise WastError {
  match self.current {
    Id(name) => {
      self.advance()
      Some(name)
    }
    _ => None
  }
}

///|
/// Parse a WAST script (sequence of commands)
pub fn parse(input : String) -> WastScript raise WastError {
  let parser = Parser::new(input)
  let commands : Array[WastCommand] = []
  while parser.current != Eof {
    let cmd = parser.parse_command()
    commands.push(cmd)
  }
  WastScript::{ commands, }
}

///|
fn Parser::parse_command(self : Parser) -> WastCommand raise WastError {
  self.expect_lparen()
  match self.current {
    Keyword("module") => self.parse_module_command()
    Keyword("assert_return") => self.parse_assert_return()
    Keyword("assert_trap") => self.parse_assert_trap()
    Keyword("assert_exhaustion") => self.parse_assert_exhaustion()
    Keyword("assert_invalid") => self.parse_assert_invalid()
    Keyword("assert_malformed") => self.parse_assert_malformed()
    Keyword("assert_unlinkable") => self.parse_assert_unlinkable()
    Keyword("register") => self.parse_register()
    Keyword("invoke") => {
      let action = self.parse_action()
      self.expect_rparen()
      Action(action)
    }
    Keyword("get") => {
      let action = self.parse_action()
      self.expect_rparen()
      Action(action)
    }
    _ => raise UnexpectedToken("expected command, got \{self.current}")
  }
}

///|
fn Parser::parse_module_command(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "module"
  // Check for optional module name
  let name = self.parse_optional_id()
  // Check for binary or quote module
  match self.current {
    Keyword("binary") => {
      self.advance()
      let bytes = self.parse_binary_module()
      self.expect_rparen()
      // Parse binary module using parser
      let mod_ = @parser.parse_module(bytes) catch {
        e => return ModuleBinaryFailed(e.to_string())
      }
      Module(mod_, name)
    }
    Keyword("quote") => {
      self.advance()
      let parts : Array[String] = []
      while self.current != RParen {
        match self.current {
          String_(s) => {
            parts.push(s)
            self.advance()
          }
          _ => break
        }
      }
      self.expect_rparen()
      ModuleQuote(parts)
    }
    _ => {
      // Inline WAT module - collect the rest and parse with WAT parser
      let wat_text = self.collect_module_text()
      self.expect_rparen()
      let mod_ = @wat.parse(wat_text) catch { e => raise WatError(e) }
      Module(mod_, name)
    }
  }
}

///|
fn Parser::collect_module_text(self : Parser) -> String raise WastError {
  // We need to reconstruct the module text from current position
  // This is a simplified approach - collect tokens until matching rparen
  let buf = StringBuilder::new()
  buf.write_string("(module ")
  let mut depth = 1
  while depth > 0 && self.current != Eof {
    match self.current {
      LParen => {
        buf.write_string("(")
        depth += 1
        self.advance()
      }
      RParen => {
        depth -= 1
        if depth > 0 {
          buf.write_string(")")
          self.advance()
        }
      }
      Keyword(k) => {
        buf.write_string(k)
        buf.write_string(" ")
        self.advance()
      }
      Id(id) => {
        buf.write_string("$")
        buf.write_string(id)
        buf.write_string(" ")
        self.advance()
      }
      Number(n) => {
        buf.write_string(n)
        buf.write_string(" ")
        self.advance()
      }
      String_(s) => {
        buf.write_string("\"")
        // Re-escape string contents for WAT parser
        escape_string_to(s, buf)
        buf.write_string("\" ")
        self.advance()
      }
      Eof => break
    }
  }
  buf.write_string(")")
  buf.to_string()
}

///|
fn Parser::parse_binary_module(self : Parser) -> Bytes raise WastError {
  let parts : Array[Byte] = []
  while self.current != RParen {
    match self.current {
      String_(s) => {
        for i in 0..<s.length() {
          parts.push(s.code_unit_at(i).to_byte())
        }
        self.advance()
      }
      _ => break
    }
  }
  Bytes::from_array(parts)
}

///|
fn Parser::parse_assert_return(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "assert_return"
  self.expect_lparen()
  let action = self.parse_action()
  self.expect_rparen()
  // Parse expected results
  let expected : Array[WastValue] = []
  while self.current == LParen {
    self.advance()
    let val = self.parse_const_value()
    expected.push(val)
    self.expect_rparen()
  }
  self.expect_rparen()
  AssertReturn(action, expected)
}

///|
fn Parser::parse_assert_trap(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "assert_trap"
  self.expect_lparen()
  // Could be action or module
  match self.current {
    Keyword("module") => {
      let source = self.parse_module_source()
      self.expect_rparen()
      let msg = self.parse_string()
      self.expect_rparen()
      AssertUnlinkable(source, msg) // trap during instantiation
    }
    _ => {
      let action = self.parse_action()
      self.expect_rparen()
      let msg = self.parse_string()
      self.expect_rparen()
      AssertTrap(action, msg)
    }
  }
}

///|
fn Parser::parse_assert_exhaustion(
  self : Parser,
) -> WastCommand raise WastError {
  self.advance() // skip "assert_exhaustion"
  self.expect_lparen()
  let action = self.parse_action()
  self.expect_rparen()
  let msg = self.parse_string()
  self.expect_rparen()
  AssertExhaustion(action, msg)
}

///|
fn Parser::parse_assert_invalid(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "assert_invalid"
  self.expect_lparen()
  let source = self.parse_module_source()
  self.expect_rparen()
  let msg = self.parse_string()
  self.expect_rparen()
  AssertInvalid(source, msg)
}

///|
fn Parser::parse_assert_malformed(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "assert_malformed"
  self.expect_lparen()
  let source = self.parse_module_source()
  self.expect_rparen()
  let msg = self.parse_string()
  self.expect_rparen()
  AssertMalformed(source, msg)
}

///|
fn Parser::parse_assert_unlinkable(
  self : Parser,
) -> WastCommand raise WastError {
  self.advance() // skip "assert_unlinkable"
  self.expect_lparen()
  let source = self.parse_module_source()
  self.expect_rparen()
  let msg = self.parse_string()
  self.expect_rparen()
  AssertUnlinkable(source, msg)
}

///|
fn Parser::parse_module_source(
  self : Parser,
) -> WastModuleSource raise WastError {
  self.expect_keyword("module")
  // Check for optional name
  self.parse_optional_id() |> ignore
  match self.current {
    Keyword("binary") => {
      self.advance()
      let bytes = self.parse_binary_module()
      Binary(bytes)
    }
    Keyword("quote") => {
      self.advance()
      let parts : Array[String] = []
      while self.current != RParen {
        match self.current {
          String_(s) => {
            parts.push(s)
            self.advance()
          }
          _ => break
        }
      }
      Quote(parts)
    }
    _ => {
      // Inline module
      let wat_text = self.collect_module_text()
      // Try to parse; if it fails, store the error for assert_invalid/malformed
      let mod_ = @wat.parse(wat_text) catch {
        e => return FailedToParse(e.to_string())
      }
      Inline(mod_)
    }
  }
}

///|
fn Parser::parse_register(self : Parser) -> WastCommand raise WastError {
  self.advance() // skip "register"
  let name = self.parse_string()
  let module_name = self.parse_optional_id()
  self.expect_rparen()
  Register(name, module_name)
}

///|
fn Parser::parse_action(self : Parser) -> WastAction raise WastError {
  match self.current {
    Keyword("invoke") => {
      self.advance()
      let module_name = self.parse_optional_id()
      let func_name = self.parse_string()
      let args : Array[WastValue] = []
      while self.current == LParen {
        self.advance()
        let val = self.parse_const_value()
        args.push(val)
        self.expect_rparen()
      }
      Invoke(module_name, func_name, args)
    }
    Keyword("get") => {
      self.advance()
      let module_name = self.parse_optional_id()
      let global_name = self.parse_string()
      Get(module_name, global_name)
    }
    _ => raise UnexpectedToken("expected action, got \{self.current}")
  }
}

///|
fn Parser::parse_const_value(self : Parser) -> WastValue raise WastError {
  match self.current {
    Keyword("i32.const") => {
      self.advance()
      let val = self.parse_i32()
      I32(val)
    }
    Keyword("i64.const") => {
      self.advance()
      let val = self.parse_i64()
      I64(val)
    }
    Keyword("f32.const") => {
      self.advance()
      match self.current {
        Keyword("nan:canonical") => {
          self.advance()
          F32CanonicalNan
        }
        Keyword("nan:arithmetic") => {
          self.advance()
          F32ArithmeticNan
        }
        _ => {
          let val = self.parse_f32()
          F32(val)
        }
      }
    }
    Keyword("f64.const") => {
      self.advance()
      match self.current {
        Keyword("nan:canonical") => {
          self.advance()
          F64CanonicalNan
        }
        Keyword("nan:arithmetic") => {
          self.advance()
          F64ArithmeticNan
        }
        _ => {
          let val = self.parse_f64()
          F64(val)
        }
      }
    }
    Keyword("ref.null") => {
      self.advance()
      match self.current {
        Keyword(ty) => {
          self.advance()
          RefNull(ty)
        }
        _ => raise UnexpectedToken("expected ref type")
      }
    }
    Keyword("ref.extern") => {
      self.advance()
      let val = self.parse_i32()
      RefExtern(val)
    }
    Keyword("ref.func") => {
      self.advance()
      RefFunc
    }
    _ => raise UnexpectedToken("expected const value, got \{self.current}")
  }
}

///|
fn Parser::parse_i32(self : Parser) -> Int raise WastError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_i64(self : Parser) -> Int64 raise WastError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int64(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_f32(self : Parser) -> Float raise WastError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float32(s)
    }
    Keyword(k) =>
      // Handle special float values like nan, inf
      if k == "nan" || k == "inf" || k.has_prefix("nan:") {
        self.advance()
        parse_float32(k)
      } else {
        raise UnexpectedToken("expected number, got \{self.current}")
      }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_f64(self : Parser) -> Double raise WastError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float64(s)
    }
    Keyword(k) =>
      if k == "nan" || k == "inf" || k.has_prefix("nan:") {
        self.advance()
        parse_float64(k)
      } else {
        raise UnexpectedToken("expected number, got \{self.current}")
      }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn parse_int(s : String) -> Int raise WastError {
  if s.has_prefix("0x") || s.has_prefix("0X") {
    if s.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if s.has_prefix("-0x") || s.has_prefix("-0X") {
    if s.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if s.has_prefix("+0x") || s.has_prefix("+0X") {
    if s.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else {
    // Try signed first, then unsigned (for values like 4294967295 which is -1 in i32)
    let result = @strconv.parse_int(s) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(s) catch { _ => raise InvalidNumber(s) }
        // Check if it fits in u32 range
        if u64 > 0xFFFFFFFFUL {
          raise InvalidNumber(s)
        }
        u64.reinterpret_as_int64().to_int()
      }
    }
    result
  }
}

///|
fn parse_hex_int(s : String) -> Int raise WastError {
  let mut result = 0
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue // Skip underscores (WAT number separator)
    }
    match hex_digit_value(c) {
      Some(v) => result = result * 16 + v
      None => raise InvalidNumber(s)
    }
  }
  result
}

///|
fn parse_int64(s : String) -> Int64 raise WastError {
  if s.has_prefix("0x") || s.has_prefix("0X") {
    if s.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if s.has_prefix("-0x") || s.has_prefix("-0X") {
    if s.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if s.has_prefix("+0x") || s.has_prefix("+0X") {
    if s.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<s.length() {
        hex_part.write_char(s.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else {
    // Try signed first, then unsigned (for values like 18446744073709551615 which is -1 in i64)
    let result = @strconv.parse_int64(s) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(s) catch { _ => raise InvalidNumber(s) }
        u64.reinterpret_as_int64()
      }
    }
    result
  }
}

///|
fn parse_hex_int64(s : String) -> Int64 raise WastError {
  let mut result = 0L
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue // Skip underscores (WAT number separator)
    }
    match hex_digit_value(c) {
      Some(v) => result = result * 16L + v.to_int64()
      None => raise InvalidNumber(s)
    }
  }
  result
}

///|
fn parse_float32(s : String) -> Float raise WastError {
  // Handle special values
  if s == "nan" || s == "+nan" || s.has_prefix("nan:") || s.has_prefix("+nan:") {
    return (0.0 : Float) / (0.0 : Float) // positive NaN
  }
  if s == "-nan" || s.has_prefix("-nan:") {
    // Negative NaN: set sign bit on canonical NaN
    // Canonical NaN is 0x7FC00000, negative NaN is 0xFFC00000
    return Float::reinterpret_from_uint(0xFFC00000U)
  }
  if s == "inf" || s == "+inf" {
    return (1.0 : Float) / (0.0 : Float) // positive infinity
  }
  if s == "-inf" {
    return (-1.0 : Float) / (0.0 : Float) // negative infinity
  }
  // Handle hex float
  if s.has_prefix("0x") ||
    s.has_prefix("-0x") ||
    s.has_prefix("+0x") ||
    s.has_prefix("0X") ||
    s.has_prefix("-0X") ||
    s.has_prefix("+0X") {
    return parse_hex_float32(s)
  }
  // Parse decimal float
  (@strconv.parse_double(s) |> Float::from_double) catch {
    _ => raise InvalidNumber(s)
  }
}

///|
fn parse_float64(s : String) -> Double raise WastError {
  // Handle special values
  if s == "nan" || s == "+nan" || s.has_prefix("nan:") || s.has_prefix("+nan:") {
    return 0.0 / 0.0 // positive NaN
  }
  if s == "-nan" || s.has_prefix("-nan:") {
    // Negative NaN: set sign bit on canonical NaN
    // Canonical NaN is 0x7FF8000000000000, negative NaN is 0xFFF8000000000000
    return 0xFFF8000000000000UL.reinterpret_as_double()
  }
  if s == "inf" || s == "+inf" {
    return 1.0 / 0.0 // positive infinity
  }
  if s == "-inf" {
    return -1.0 / 0.0 // negative infinity
  }
  // Handle hex float
  if s.has_prefix("0x") ||
    s.has_prefix("-0x") ||
    s.has_prefix("+0x") ||
    s.has_prefix("0X") ||
    s.has_prefix("-0X") ||
    s.has_prefix("+0X") {
    return parse_hex_float64(s)
  }
  @strconv.parse_double(s) catch {
    _ => raise InvalidNumber(s)
  }
}

///|
fn parse_hex_float32(s : String) -> Float raise WastError {
  parse_hex_float64(s) |> Float::from_double
}

///|
fn parse_hex_float64(s : String) -> Double raise WastError {
  let mut neg = false
  let mut idx = 0
  // Handle sign
  if s.code_unit_at(0).unsafe_to_char() == '-' {
    neg = true
    idx = 1
  } else if s.code_unit_at(0).unsafe_to_char() == '+' {
    idx = 1
  }
  // Skip 0x
  idx += 2
  // Parse integer part
  let mut int_part = 0.0
  while idx < s.length() {
    let c = s.code_unit_at(idx).unsafe_to_char()
    if c == '.' || c == 'p' || c == 'P' {
      break
    }
    match hex_digit_value(c) {
      Some(v) => {
        int_part = int_part * 16.0 + v.to_double()
        idx += 1
      }
      None => raise InvalidNumber(s)
    }
  }
  // Parse fractional part
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '.' {
    idx += 1
    while idx < s.length() {
      let c = s.code_unit_at(idx).unsafe_to_char()
      if c == 'p' || c == 'P' {
        break
      }
      match hex_digit_value(c) {
        Some(v) => {
          frac_scale = frac_scale / 16.0
          frac_part = frac_part + v.to_double() * frac_scale
          idx += 1
        }
        None => raise InvalidNumber(s)
      }
    }
  }
  // Parse exponent
  let mut exp = 0
  let mut exp_neg = false
  if idx < s.length() &&
    (
      s.code_unit_at(idx).unsafe_to_char() == 'p' ||
      s.code_unit_at(idx).unsafe_to_char() == 'P'
    ) {
    idx += 1
    if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '-' {
      exp_neg = true
      idx += 1
    } else if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '+' {
      idx += 1
    }
    while idx < s.length() {
      let c = s.code_unit_at(idx).unsafe_to_char()
      if c >= '0' && c <= '9' {
        exp = exp * 10 + (c.to_int() - '0'.to_int())
        idx += 1
      } else {
        break
      }
    }
  }
  let mut result = int_part + frac_part
  // Apply exponent (binary)
  if exp_neg {
    for _ in 0..<exp {
      result = result / 2.0
    }
  } else {
    for _ in 0..<exp {
      result = result * 2.0
    }
  }
  if neg {
    -result
  } else {
    result
  }
}
