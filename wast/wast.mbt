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
  /// WAT error with line offset adjustment (for inline modules in WAST)
  /// The Int is the line number in the original WAST file where the module starts
  WatError(@wat.WatError, Int)
}

///|
pub impl Show for WastError with output(self, logger) {
  match self {
    WatError(e, line_offset) => {
      // Adjust the line number in the error message
      let adjusted = adjust_wat_error_line(e, line_offset)
      logger.write_string(adjusted.to_string())
    }
    UnexpectedToken(s) => logger.write_string("UnexpectedToken(\{s})")
    UnexpectedEof => logger.write_string("UnexpectedEof")
    InvalidNumber(s) => logger.write_string("InvalidNumber(\{s})")
    InvalidInstruction(s) => logger.write_string("InvalidInstruction(\{s})")
    ParseError(s) => logger.write_string("ParseError(\{s})")
  }
}

///|
/// Adjust WAT error line numbers by adding an offset
fn adjust_wat_error_line(
  err : @wat.WatError,
  line_offset : Int,
) -> @wat.WatError {
  match err {
    @wat.WatError::UnexpectedToken(msg, loc) =>
      @wat.WatError::UnexpectedToken(msg, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::UnexpectedEof(loc) =>
      @wat.WatError::UnexpectedEof({
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::InvalidNumber(s, loc) =>
      @wat.WatError::InvalidNumber(s, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::InvalidInstruction(s, loc) =>
      @wat.WatError::InvalidInstruction(s, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::UndefinedIdentifier(s, loc) =>
      @wat.WatError::UndefinedIdentifier(s, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::DuplicateIdentifier(s, loc) =>
      @wat.WatError::DuplicateIdentifier(s, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
    @wat.WatError::ParseError(msg, loc) =>
      @wat.WatError::ParseError(msg, {
        line: loc.line + line_offset - 1,
        column: loc.column,
      })
  }
}

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
  ModuleDefinition(@types.Module, String?) // module definition only (not instantiated)
  ModuleQuote(Array[String]) // quoted module (for malformed tests)
  ModuleBinaryFailed(String) // binary module that failed to parse (skip in tests)
  AssertReturn(WastAction, Array[WastValue])
  AssertTrap(WastAction, String)
  AssertModuleTrap(WastModuleSource, String) // module that traps during instantiation
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
/// WAST script (collection of commands with line numbers)
pub struct WastScript {
  commands : Array[(WastCommand, Int)] // (command, line_number)
}

///|
/// WAST Lexer
priv struct Lexer {
  input : String
  mut pos : Int
  mut line : Int
  mut token_start_pos : Int // Position where the current token started
}

///|
fn Lexer::new(input : String) -> Lexer {
  { input, pos: 0, line: 1, token_start_pos: 0 }
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
    }
    Some(c)
  }
}

///|
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while !self.is_eof() {
    match self.peek_char() {
      Some('\n') => {
        self.pos += 1
        self.line += 1
      }
      Some(' ') | Some('\t') | Some('\r') => self.pos += 1
      Some(';') =>
        // Skip line comment
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while !self.is_eof() {
            match self.peek_char() {
              Some('\n') => {
                self.pos += 1
                self.line += 1
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
              } else if c1 == '\n' {
                self.pos += 1
                self.line += 1
              } else {
                self.pos += 1
              }
            } else {
              self.pos += 1
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
  self.pos += 2
  // Skip annotation id (can be identifier or string)
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\r') => break
      Some('\n') => {
        self.line += 1
        break
      }
      Some('(') | Some(')') => break
      Some('"') => {
        // Skip string in annotation id
        self.pos += 1
        while !self.is_eof() {
          match self.peek_char() {
            Some('"') => {
              self.pos += 1
              break
            }
            Some('\\') => self.pos += 2 // skip escaped char
            Some('\n') => {
              self.pos += 1
              self.line += 1
            }
            _ => self.pos += 1
          }
        }
        break
      }
      _ => self.pos += 1
    }
  }
  // Skip whitespace after id
  while !self.is_eof() {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\r') => self.pos += 1
      Some('\n') => {
        self.pos += 1
        self.line += 1
      }
      _ => break
    }
  }
  // Skip content with balanced parentheses until closing ')'
  let mut depth = 1
  while !self.is_eof() && depth > 0 {
    match self.peek_char() {
      Some('(') =>
        // Check for block comment inside annotation
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          // Block comment inside annotation - skip it
          self.pos += 2
          let mut comment_depth = 1
          while !self.is_eof() && comment_depth > 0 {
            if self.pos + 1 < self.input.length() {
              let c1 = self.input.code_unit_at(self.pos).unsafe_to_char()
              let c2 = self.input.code_unit_at(self.pos + 1).unsafe_to_char()
              if c1 == ';' && c2 == ')' {
                comment_depth -= 1
                self.pos += 2
              } else if c1 == '(' && c2 == ';' {
                comment_depth += 1
                self.pos += 2
              } else if c1 == '\n' {
                self.pos += 1
                self.line += 1
              } else {
                self.pos += 1
              }
            } else {
              self.pos += 1
            }
          }
        } else {
          depth += 1
          self.pos += 1
        }
      Some(')') => {
        depth -= 1
        self.pos += 1
      }
      Some('"') => {
        // Skip string inside annotation
        self.pos += 1
        while !self.is_eof() {
          match self.peek_char() {
            Some('"') => {
              self.pos += 1
              break
            }
            Some('\\') => self.pos += 2 // skip escaped char
            Some('\n') => {
              self.pos += 1
              self.line += 1
            }
            _ => self.pos += 1
          }
        }
      }
      Some(';') =>
        // Check for line comment inside annotation
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while !self.is_eof() {
            match self.peek_char() {
              Some('\n') => {
                self.pos += 1
                self.line += 1
                break
              }
              _ => self.pos += 1
            }
          }
        } else {
          self.pos += 1
        }
      Some('\n') => {
        self.pos += 1
        self.line += 1
      }
      _ => self.pos += 1
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
      if !self.is_eof() && self.peek_char() is Some(':') {
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
  // Record where this token starts
  self.token_start_pos = self.pos
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
fn Parser::current_line(self : Parser) -> Int {
  self.lexer.line
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
  let commands : Array[(WastCommand, Int)] = []
  while parser.current != Eof {
    let line = parser.current_line()
    let cmd = parser.parse_command()
    commands.push((cmd, line))
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
  // Record the position where module content starts (before current token)
  // We need to find where in the input the content starts
  let content_start_pos = self.find_content_start_pos()
  // Check for binary, quote, or definition module
  match self.current {
    Keyword("definition") => {
      // module definition - defines but doesn't instantiate
      self.advance()
      let module_start_line = self.current_line()
      let wat_text = self.collect_module_text(content_start_pos)
      self.expect_rparen()
      let mod_ = @wat.parse(wat_text) catch {
        e => raise WatError(e, module_start_line)
      }
      ModuleDefinition(mod_, name)
    }
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
      // Record the line number where the module starts for error reporting
      let module_start_line = self.current_line()
      let wat_text = self.collect_module_text(content_start_pos)
      self.expect_rparen()
      let mod_ = @wat.parse(wat_text) catch {
        e => raise WatError(e, module_start_line)
      }
      Module(mod_, name)
    }
  }
}

///|
/// Get the position where the current token starts in the input
fn Parser::find_content_start_pos(self : Parser) -> Int {
  self.lexer.token_start_pos
}

///|
fn Parser::collect_module_text(
  self : Parser,
  content_start_pos : Int,
) -> String raise WastError {
  // Extract raw module text from input, preserving original formatting
  // This keeps line numbers and column positions accurate for error reporting
  let input = self.lexer.input
  let start_pos = content_start_pos

  // We need to find the matching closing parenthesis
  // Track depth starting at 1 (we're inside the module)
  let mut depth = 1
  let mut pos = start_pos
  while depth > 0 && pos < input.length() {
    let c = input.code_unit_at(pos).unsafe_to_char()
    match c {
      '(' =>
        // Check for block comment
        if pos + 1 < input.length() &&
          input.code_unit_at(pos + 1).unsafe_to_char() == ';' {
          // Skip block comment
          pos += 2
          let mut comment_depth = 1
          while comment_depth > 0 && pos < input.length() {
            let c2 = input.code_unit_at(pos).unsafe_to_char()
            if c2 == ';' &&
              pos + 1 < input.length() &&
              input.code_unit_at(pos + 1).unsafe_to_char() == ')' {
              comment_depth -= 1
              pos += 2
            } else if c2 == '(' &&
              pos + 1 < input.length() &&
              input.code_unit_at(pos + 1).unsafe_to_char() == ';' {
              comment_depth += 1
              pos += 2
            } else {
              pos += 1
            }
          }
        } else if pos + 1 < input.length() &&
          input.code_unit_at(pos + 1).unsafe_to_char() == '@' {
          // Skip annotation (@id ...)
          pos += 2
          // Skip annotation id
          while pos < input.length() {
            let c2 = input.code_unit_at(pos).unsafe_to_char()
            if c2 == ' ' || c2 == '\t' || c2 == '\n' || c2 == '\r' || c2 == ')' {
              break
            }
            if c2 == '"' {
              // String annotation id
              pos += 1
              while pos < input.length() {
                let c3 = input.code_unit_at(pos).unsafe_to_char()
                if c3 == '"' {
                  pos += 1
                  break
                } else if c3 == '\\' {
                  pos += 2
                } else {
                  pos += 1
                }
              }
              break
            }
            pos += 1
          }
          // Skip annotation content with balanced parens
          let mut ann_depth = 1
          while ann_depth > 0 && pos < input.length() {
            let c2 = input.code_unit_at(pos).unsafe_to_char()
            if c2 == '(' {
              ann_depth += 1
              pos += 1
            } else if c2 == ')' {
              ann_depth -= 1
              pos += 1
            } else if c2 == '"' {
              pos += 1
              while pos < input.length() {
                let c3 = input.code_unit_at(pos).unsafe_to_char()
                if c3 == '"' {
                  pos += 1
                  break
                } else if c3 == '\\' {
                  pos += 2
                } else {
                  pos += 1
                }
              }
            } else {
              pos += 1
            }
          }
        } else {
          depth += 1
          pos += 1
        }
      ')' => {
        depth -= 1
        if depth > 0 {
          pos += 1
        }
      }
      ';' =>
        // Check for line comment
        if pos + 1 < input.length() &&
          input.code_unit_at(pos + 1).unsafe_to_char() == ';' {
          // Skip to end of line
          while pos < input.length() {
            let c2 = input.code_unit_at(pos).unsafe_to_char()
            if c2 == '\n' {
              pos += 1
              break
            }
            pos += 1
          }
        } else {
          pos += 1
        }
      '"' => {
        // Skip string
        pos += 1
        while pos < input.length() {
          let c2 = input.code_unit_at(pos).unsafe_to_char()
          if c2 == '"' {
            pos += 1
            break
          } else if c2 == '\\' {
            pos += 2
          } else {
            pos += 1
          }
        }
      }
      _ => pos += 1
    }
  }

  // Extract the raw text and build the module string
  let buf = StringBuilder::new()
  buf.write_string("(module ")
  for i in start_pos..<pos {
    buf.write_char(input.code_unit_at(i).unsafe_to_char())
  }
  buf.write_string(")")

  // Update the lexer position to point past the extracted content
  // We need to count newlines to keep line tracking accurate
  for i in self.lexer.pos..<pos {
    if input.code_unit_at(i).unsafe_to_char() == '\n' {
      self.lexer.line += 1
    }
  }
  self.lexer.pos = pos
  // Read the next token (should be RParen)
  self.current = self.lexer.next_token()
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
      AssertModuleTrap(source, msg) // trap during instantiation (start function)
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
  // Record content start position before consuming tokens
  let content_start_pos = self.find_content_start_pos()
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
      let wat_text = self.collect_module_text(content_start_pos)
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
        // Allow (ref.null) without type - in WAST assertions, the type can be inferred
        // Use empty string to indicate unspecified type
        _ => RefNull("")
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
      // Handle special float values like nan, inf, -nan:0x..., +nan:0x..., etc.
      if k == "nan" ||
        k == "inf" ||
        k == "-nan" ||
        k == "+nan" ||
        k == "-inf" ||
        k == "+inf" ||
        k.has_prefix("nan:") ||
        k.has_prefix("-nan:") ||
        k.has_prefix("+nan:") {
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
      // Handle special float values like nan, inf, -nan:0x..., +nan:0x..., etc.
      if k == "nan" ||
        k == "inf" ||
        k == "-nan" ||
        k == "+nan" ||
        k == "-inf" ||
        k == "+inf" ||
        k.has_prefix("nan:") ||
        k.has_prefix("-nan:") ||
        k.has_prefix("+nan:") {
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
  if s == "nan" || s == "+nan" {
    // Canonical positive NaN: 0x7fc00000
    return Float::reinterpret_from_int(0x7fc00000)
  }
  if s == "-nan" {
    // Canonical negative NaN: 0xffc00000 = -4194304 as signed int
    return Float::reinterpret_from_int(-4194304)
  }
  if s.has_prefix("nan:0x") || s.has_prefix("+nan:0x") {
    // Parse payload from nan:0x...
    let payload_start = if s.has_prefix("+") { 7 } else { 6 }
    let payload_str = try! s[payload_start:].to_string()
    let payload = parse_hex_int(payload_str)
    // Positive NaN: 0x7f800000 | payload
    let bits = 0x7f800000 | (payload & 0x7fffff)
    return Float::reinterpret_from_int(bits)
  }
  if s.has_prefix("-nan:0x") {
    // Parse payload from -nan:0x...
    let payload_str = try! s[7:].to_string()
    let payload = parse_hex_int(payload_str)
    // Negative NaN: 0xff800000 | payload = -8388608 | payload
    let bits = -8388608 | (payload & 0x7fffff)
    return Float::reinterpret_from_int(bits)
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
  if s == "nan" || s == "+nan" {
    // Canonical positive NaN: 0x7ff8000000000000
    return 0x7ff8000000000000L.reinterpret_as_double()
  }
  if s == "-nan" {
    // Canonical negative NaN: 0xfff8000000000000
    return 0xfff8000000000000L.reinterpret_as_double()
  }
  if s.has_prefix("nan:0x") || s.has_prefix("+nan:0x") {
    // Parse payload from nan:0x...
    let payload_start = if s.has_prefix("+") { 7 } else { 6 }
    let payload_str = try! s[payload_start:].to_string()
    let payload = parse_hex_int64(payload_str)
    // Positive NaN: 0x7ff0000000000000 | payload
    let bits = 0x7ff0000000000000L | (payload & 0xfffffffffffffL)
    return bits.reinterpret_as_double()
  }
  if s.has_prefix("-nan:0x") {
    // Parse payload from -nan:0x...
    let payload_str = try! s[7:].to_string()
    let payload = parse_hex_int64(payload_str)
    // Negative NaN: 0xfff0000000000000 | payload
    let bits = 0xfff0000000000000L | (payload & 0xfffffffffffffL)
    return bits.reinterpret_as_double()
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
