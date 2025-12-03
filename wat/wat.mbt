// WAT (WebAssembly Text Format) Parser
// Parses WAT text format into WASM Module structures

///|
/// WAT Parser errors
pub(all) suberror WatError {
  UnexpectedToken(String)
  UnexpectedEof
  InvalidNumber(String)
  InvalidInstruction(String)
  UndefinedIdentifier(String)
  DuplicateIdentifier(String)
  ParseError(String)
} derive(Show)

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
  while not(self.is_eof()) {
    match self.peek_char() {
      Some(' ') | Some('\t') | Some('\n') | Some('\r') => self.pos += 1
      Some(';') =>
        // Skip line comment
        if self.pos + 1 < self.input.length() &&
          self.input.code_unit_at(self.pos + 1).unsafe_to_char() == ';' {
          while not(self.is_eof()) {
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
          while not(self.is_eof()) && depth > 0 {
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
  while not(self.is_eof()) {
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
fn Lexer::read_string(self : Lexer) -> String raise WatError {
  let buf = StringBuilder::new()
  // Skip opening quote
  self.pos += 1
  while not(self.is_eof()) {
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
                    None => raise ParseError("Invalid hex escape: \{hex}")
                  }
                }
                None => raise UnexpectedEof
              }
            } else {
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
  while not(self.is_eof()) {
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
fn Lexer::next_token(self : Lexer) -> Token raise WatError {
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
/// WAT Parser
priv struct Parser {
  lexer : Lexer
  mut current : Token
  // Name resolution maps
  func_names : Map[String, Int]
  type_names : Map[String, Int]
  local_names : Map[String, Int]
  global_names : Map[String, Int]
  memory_names : Map[String, Int]
  table_names : Map[String, Int]
}

///|
fn Parser::new(input : String) -> Parser raise WatError {
  let lexer = Lexer::new(input)
  let first_token = lexer.next_token()
  {
    lexer,
    current: first_token,
    func_names: {},
    type_names: {},
    local_names: {},
    global_names: {},
    memory_names: {},
    table_names: {},
  }
}

///|
fn Parser::advance(self : Parser) -> Unit raise WatError {
  self.current = self.lexer.next_token()
}

///|
fn Parser::expect_lparen(self : Parser) -> Unit raise WatError {
  match self.current {
    LParen => self.advance()
    _ => raise UnexpectedToken("expected '(', got \{self.current}")
  }
}

///|
fn Parser::expect_rparen(self : Parser) -> Unit raise WatError {
  match self.current {
    RParen => self.advance()
    _ => raise UnexpectedToken("expected ')', got \{self.current}")
  }
}

///|
fn Parser::expect_keyword(self : Parser, kw : String) -> Unit raise WatError {
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
fn Parser::parse_u32(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_i32(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_i64(self : Parser) -> Int64 raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int64(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_f32(self : Parser) -> Float raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float32(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn Parser::parse_f64(self : Parser) -> Double raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float64(s)
    }
    _ => raise UnexpectedToken("expected number, got \{self.current}")
  }
}

///|
fn parse_int(s : String) -> Int raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i = 2; i < trimmed.length(); i = i + 1 {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i = 3; i < trimmed.length(); i = i + 1 {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else {
    // Parse decimal
    @strconv.parse_int(trimmed) catch {
      _ => raise InvalidNumber(s)
    }
  }
}

///|
fn parse_hex_int(s : String) -> Int raise WatError {
  let mut result = 0
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    match hex_digit_value(c) {
      Some(v) => result = result * 16 + v
      None => raise InvalidNumber(s)
    }
  }
  result
}

///|
fn parse_int64(s : String) -> Int64 raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i = 2; i < trimmed.length(); i = i + 1 {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i = 3; i < trimmed.length(); i = i + 1 {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s)
    }
  } else {
    @strconv.parse_int64(trimmed) catch {
      _ => raise InvalidNumber(s)
    }
  }
}

///|
fn parse_hex_int64(s : String) -> Int64 raise WatError {
  let mut result = 0L
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    match hex_digit_value(c) {
      Some(v) => result = result * 16L + v.to_int64()
      None => raise InvalidNumber(s)
    }
  }
  result
}

///|
fn parse_float32(s : String) -> Float raise WatError {
  if s == "inf" || s == "+inf" {
    return (1.0 : Float) / (0.0 : Float) // positive infinity
  }
  if s == "-inf" {
    return (-1.0 : Float) / (0.0 : Float) // negative infinity
  }
  if s == "nan" || s == "+nan" || s == "-nan" {
    return (0.0 : Float) / (0.0 : Float) // NaN
  }
  (@strconv.parse_double(s) |> Float::from_double) catch {
    _ => raise InvalidNumber(s)
  }
}

///|
fn parse_float64(s : String) -> Double raise WatError {
  if s == "inf" || s == "+inf" {
    return 1.0 / 0.0 // positive infinity
  }
  if s == "-inf" {
    return -1.0 / 0.0 // negative infinity
  }
  if s == "nan" || s == "+nan" || s == "-nan" {
    return 0.0 / 0.0 // NaN
  }
  @strconv.parse_double(s) catch {
    _ => raise InvalidNumber(s)
  }
}

///|
fn Parser::parse_value_type(self : Parser) -> @types.ValueType raise WatError {
  match self.current {
    Keyword(kw) => {
      self.advance()
      match kw {
        "i32" => I32
        "i64" => I64
        "f32" => F32
        "f64" => F64
        "v128" => V128
        "funcref" => FuncRef
        "externref" => ExternRef
        _ => raise UnexpectedToken("expected value type, got '\{kw}'")
      }
    }
    _ => raise UnexpectedToken("expected value type, got \{self.current}")
  }
}

///|
/// Parse a WAT module from string
pub fn parse(input : String) -> @types.Module raise WatError {
  let parser = Parser::new(input)
  parser.parse_module()
}

///|
fn Parser::parse_module(self : Parser) -> @types.Module raise WatError {
  self.expect_lparen()
  self.expect_keyword("module")
  let mod_ = @types.Module::new()

  // First pass: collect type names
  // For simplicity, we'll do a single pass and handle names as we go

  while self.current != RParen && self.current != Eof {
    match self.current {
      LParen => {
        self.advance()
        match self.current {
          Keyword("type") => {
            let ft = self.parse_type_def()
            self.type_names.set("\{mod_.types.length()}", mod_.types.length())
            mod_.types.push(ft)
          }
          Keyword("func") => {
            let (type_idx, code, export_name) = self.parse_func_def(mod_)
            let func_idx = mod_.funcs.length()
            mod_.funcs.push(type_idx)
            mod_.codes.push(code)
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Func(func_idx),
              })
            }
          }
          Keyword("memory") => {
            let (mem, export_name) = self.parse_memory_def()
            let mem_idx = mod_.memories.length()
            mod_.memories.push(mem)
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Memory(mem_idx),
              })
            }
          }
          Keyword("global") => {
            let (global, export_name) = self.parse_global_def()
            let global_idx = mod_.globals.length()
            mod_.globals.push(global)
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Global(global_idx),
              })
            }
          }
          Keyword("export") => {
            let exp = self.parse_export_def(mod_)
            mod_.exports.push(exp)
          }
          Keyword("import") => {
            let imp = self.parse_import_def(mod_)
            mod_.imports.push(imp)
          }
          Keyword("table") => {
            let (table, export_name) = self.parse_table_def()
            let table_idx = mod_.tables.length()
            mod_.tables.push(table)
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Table(table_idx),
              })
            }
          }
          Keyword("start") => {
            let func_idx = self.parse_func_idx()
            mod_.start = Some(func_idx)
            self.expect_rparen()
          }
          Keyword(kw) => raise UnexpectedToken("unexpected module field: \{kw}")
          _ => raise UnexpectedToken("expected module field")
        }
      }
      _ => raise UnexpectedToken("expected '(' in module")
    }
  }
  self.expect_rparen()
  mod_
}

///|
fn Parser::parse_type_def(self : Parser) -> @types.FuncType raise WatError {
  self.advance() // skip "type"
  // Optional type name
  match self.current {
    Id(name) => {
      self.advance()
      self.type_names.set(name, self.type_names.length())
    }
    _ => ()
  }
  self.expect_lparen()
  self.expect_keyword("func")
  let ft = self.parse_func_type()
  self.expect_rparen() // close func
  self.expect_rparen() // close type
  ft
}

///|
fn Parser::parse_func_type(self : Parser) -> @types.FuncType raise WatError {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = []

  // Parse params
  while self.current == LParen {
    let saved_pos = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("param") => {
        self.advance()
        // Optional name
        match self.current {
          Id(_) => self.advance()
          _ => ()
        }
        // Parse types until )
        while self.current != RParen {
          params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current != RParen {
          results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        // Not param/result, restore and break
        self.lexer.pos = saved_pos
        self.current = LParen
        break
      }
    }
  }
  { params, results }
}

///|
fn Parser::parse_func_def(
  self : Parser,
  mod_ : @types.Module,
) -> (Int, @types.FunctionCode, String?) raise WatError {
  self.advance() // skip "func"
  let mut export_name : String? = None
  let func_idx = mod_.funcs.length()

  // Optional function name
  match self.current {
    Id(name) => {
      self.func_names.set(name, func_idx)
      self.advance()
    }
    _ => ()
  }

  // Clear local names for this function
  self.local_names.clear()

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name")
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse type reference or inline type
  let mut type_idx = -1
  let inline_params : Array[@types.ValueType] = []
  let inline_results : Array[@types.ValueType] = []

  // Parse (type $idx) or inline params/results
  while self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("type") => {
        self.advance()
        type_idx = self.parse_type_idx()
        self.expect_rparen()
      }
      Keyword("param") => {
        self.advance()
        // Optional name
        match self.current {
          Id(name) => {
            self.local_names.set(name, inline_params.length())
            self.advance()
          }
          _ => ()
        }
        while self.current != RParen {
          inline_params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current != RParen {
          inline_results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
        break
      }
    }
  }

  // If no type reference, create inline type
  if type_idx < 0 {
    let ft : @types.FuncType = {
      params: inline_params,
      results: inline_results,
    }
    // Check if this type already exists
    let mut found = -1
    for i, t in mod_.types {
      if t.params.length() == ft.params.length() &&
        t.results.length() == ft.results.length() {
        let mut match_ = true
        for j, p in t.params {
          if p != ft.params[j] {
            match_ = false
            break
          }
        }
        if match_ {
          for j, r in t.results {
            if r != ft.results[j] {
              match_ = false
              break
            }
          }
        }
        if match_ {
          found = i
          break
        }
      }
    }
    if found >= 0 {
      type_idx = found
    } else {
      type_idx = mod_.types.length()
      mod_.types.push(ft)
    }
  }

  // Parse locals
  let locals : Array[@types.ValueType] = []
  while self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("local") => {
        self.advance()
        // Optional name
        match self.current {
          Id(name) => {
            let local_idx = inline_params.length() + locals.length()
            self.local_names.set(name, local_idx)
            self.advance()
          }
          _ => ()
        }
        while self.current != RParen {
          locals.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
        break
      }
    }
  }

  // Parse body instructions
  let body = self.parse_instructions()
  self.expect_rparen() // close func
  (type_idx, { locals, body }, export_name)
}

///|
fn Parser::parse_instructions(
  self : Parser,
) -> Array[@types.Instruction] raise WatError {
  let instrs : Array[@types.Instruction] = []
  while self.current != RParen && self.current != Eof {
    match self.current {
      LParen => {
        // Folded instruction - may produce multiple instructions
        self.advance()
        for instr in self.parse_folded_instructions() {
          instrs.push(instr)
        }
      }
      Keyword(kw) => {
        // Stop on control flow terminators (they are handled by the caller)
        if kw == "end" || kw == "else" {
          break
        }
        let instr = self.parse_plain_instruction(kw)
        instrs.push(instr)
      }
      _ => break
    }
  }
  instrs
}

///|
/// Parse a folded instruction and return all resulting instructions.
/// For most instructions, returns a single instruction.
/// For folded `if`, returns condition instructions followed by the if instruction.
fn Parser::parse_folded_instructions(
  self : Parser,
) -> Array[@types.Instruction] raise WatError {
  match self.current {
    Keyword(kw) => {
      // Special handling for "if" in folded form
      if kw == "if" {
        self.advance() // skip "if"
        let bt = self.parse_block_type()
        let result : Array[@types.Instruction] = []
        // In folded form, condition operands come first as nested S-expressions
        while self.current == LParen {
          // Peek ahead to see if this is (then ...) or (else ...)
          let saved = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("then") | Keyword("else") => {
              // Restore and break to handle then/else
              self.lexer.pos = saved
              self.current = LParen
              break
            }
            _ => {
              // Restore to parse as folded operand (condition)
              self.lexer.pos = saved
              self.current = LParen
              self.advance()
              for instr in self.parse_folded_instructions() {
                result.push(instr)
              }
            }
          }
        }
        // Now parse (then ...) and optionally (else ...)
        let mut then_body : Array[@types.Instruction] = []
        let mut else_body : Array[@types.Instruction] = []
        if self.current == LParen {
          self.advance()
          match self.current {
            Keyword("then") => {
              self.advance()
              then_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ => raise UnexpectedToken("expected 'then' in folded if")
          }
        }
        if self.current == LParen {
          let saved = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("else") => {
              self.advance()
              else_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved
              self.current = LParen
            }
          }
        }
        self.expect_rparen() // close if
        result.push(@types.Instruction::If(bt, then_body, else_body))
        return result
      }
      let instr = self.parse_plain_instruction(kw)
      // For control instructions, we've already handled them
      // For other instructions, parse folded operands
      match instr {
        Block(_, _) | Loop(_, _) | If(_, _, _) => [instr]
        _ => {
          // Parse nested folded instructions (operands)
          let result : Array[@types.Instruction] = []
          while self.current == LParen {
            self.advance()
            for i in self.parse_folded_instructions() {
              result.push(i)
            }
          }
          self.expect_rparen()
          result.push(instr)
          result
        }
      }
    }
    _ => raise UnexpectedToken("expected instruction")
  }
}

///|
fn Parser::parse_plain_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  self.advance()
  match kw {
    // Control
    "unreachable" => @types.Instruction::Unreachable
    "nop" => @types.Instruction::Nop
    "block" => {
      let bt = self.parse_block_type()
      let body = self.parse_instructions()
      self.expect_keyword("end")
      @types.Instruction::Block(bt, body)
    }
    "loop" => {
      let bt = self.parse_block_type()
      let body = self.parse_instructions()
      self.expect_keyword("end")
      @types.Instruction::Loop(bt, body)
    }
    "if" => {
      let bt = self.parse_block_type()
      // Flat form: if (result type) ... else ... end
      let then_body = self.parse_instructions()
      let else_body : Array[@types.Instruction] = if self.current ==
        Keyword("else") {
        self.advance()
        self.parse_instructions()
      } else {
        []
      }
      self.expect_keyword("end")
      @types.Instruction::If(bt, then_body, else_body)
    }
    "br" => @types.Instruction::Br(self.parse_label_idx())
    "br_if" => @types.Instruction::BrIf(self.parse_label_idx())
    "br_table" => {
      let labels : Array[Int] = []
      while self.current != RParen && self.current != Eof {
        match self.current {
          Number(_) | Id(_) => labels.push(self.parse_label_idx())
          _ => break
        }
      }
      if labels.length() == 0 {
        raise ParseError("br_table requires at least one label")
      }
      let default_label = labels.pop().unwrap()
      @types.Instruction::BrTable(labels, default_label)
    }
    "return" => @types.Instruction::Return
    "call" => @types.Instruction::Call(self.parse_func_idx())
    "call_indirect" => {
      // Parse (type $idx)
      self.expect_lparen()
      self.expect_keyword("type")
      let type_idx = self.parse_type_idx()
      self.expect_rparen()
      @types.Instruction::CallIndirect(type_idx, 0)
    }

    // Parametric
    "drop" => @types.Instruction::Drop
    "select" => @types.Instruction::Select

    // Variable
    "local.get" => @types.Instruction::LocalGet(self.parse_local_idx())
    "local.set" => @types.Instruction::LocalSet(self.parse_local_idx())
    "local.tee" => @types.Instruction::LocalTee(self.parse_local_idx())
    "global.get" => @types.Instruction::GlobalGet(self.parse_global_idx())
    "global.set" => @types.Instruction::GlobalSet(self.parse_global_idx())

    // Memory
    "i32.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load(a, o) })
    "i64.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load(a, o) })
    "f32.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F32Load(a, o) })
    "f64.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F64Load(a, o) })
    "i32.load8_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load8S(a, o) })
    "i32.load8_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load8U(a, o) })
    "i32.load16_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load16S(a, o) })
    "i32.load16_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load16U(a, o) })
    "i64.load8_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load8S(a, o) })
    "i64.load8_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load8U(a, o) })
    "i64.load16_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load16S(a, o) })
    "i64.load16_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load16U(a, o) })
    "i64.load32_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load32S(a, o) })
    "i64.load32_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load32U(a, o) })
    "i32.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store(a, o) })
    "i64.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store(a, o) })
    "f32.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F32Store(a, o) })
    "f64.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F64Store(a, o) })
    "i32.store8" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store8(a, o) })
    "i32.store16" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store16(a, o) })
    "i64.store8" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store8(a, o) })
    "i64.store16" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store16(a, o) })
    "i64.store32" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store32(a, o) })
    "memory.size" => @types.Instruction::MemorySize
    "memory.grow" => @types.Instruction::MemoryGrow

    // Constants
    "i32.const" => @types.Instruction::I32Const(self.parse_i32())
    "i64.const" => @types.Instruction::I64Const(self.parse_i64())
    "f32.const" => @types.Instruction::F32Const(self.parse_f32())
    "f64.const" => @types.Instruction::F64Const(self.parse_f64())

    // i32 operations
    "i32.eqz" => @types.Instruction::I32Eqz
    "i32.eq" => @types.Instruction::I32Eq
    "i32.ne" => @types.Instruction::I32Ne
    "i32.lt_s" => @types.Instruction::I32LtS
    "i32.lt_u" => @types.Instruction::I32LtU
    "i32.gt_s" => @types.Instruction::I32GtS
    "i32.gt_u" => @types.Instruction::I32GtU
    "i32.le_s" => @types.Instruction::I32LeS
    "i32.le_u" => @types.Instruction::I32LeU
    "i32.ge_s" => @types.Instruction::I32GeS
    "i32.ge_u" => @types.Instruction::I32GeU
    "i32.clz" => @types.Instruction::I32Clz
    "i32.ctz" => @types.Instruction::I32Ctz
    "i32.popcnt" => @types.Instruction::I32Popcnt
    "i32.add" => @types.Instruction::I32Add
    "i32.sub" => @types.Instruction::I32Sub
    "i32.mul" => @types.Instruction::I32Mul
    "i32.div_s" => @types.Instruction::I32DivS
    "i32.div_u" => @types.Instruction::I32DivU
    "i32.rem_s" => @types.Instruction::I32RemS
    "i32.rem_u" => @types.Instruction::I32RemU
    "i32.and" => @types.Instruction::I32And
    "i32.or" => @types.Instruction::I32Or
    "i32.xor" => @types.Instruction::I32Xor
    "i32.shl" => @types.Instruction::I32Shl
    "i32.shr_s" => @types.Instruction::I32ShrS
    "i32.shr_u" => @types.Instruction::I32ShrU
    "i32.rotl" => @types.Instruction::I32Rotl
    "i32.rotr" => @types.Instruction::I32Rotr

    // i64 operations
    "i64.eqz" => @types.Instruction::I64Eqz
    "i64.eq" => @types.Instruction::I64Eq
    "i64.ne" => @types.Instruction::I64Ne
    "i64.lt_s" => @types.Instruction::I64LtS
    "i64.lt_u" => @types.Instruction::I64LtU
    "i64.gt_s" => @types.Instruction::I64GtS
    "i64.gt_u" => @types.Instruction::I64GtU
    "i64.le_s" => @types.Instruction::I64LeS
    "i64.le_u" => @types.Instruction::I64LeU
    "i64.ge_s" => @types.Instruction::I64GeS
    "i64.ge_u" => @types.Instruction::I64GeU
    "i64.clz" => @types.Instruction::I64Clz
    "i64.ctz" => @types.Instruction::I64Ctz
    "i64.popcnt" => @types.Instruction::I64Popcnt
    "i64.add" => @types.Instruction::I64Add
    "i64.sub" => @types.Instruction::I64Sub
    "i64.mul" => @types.Instruction::I64Mul
    "i64.div_s" => @types.Instruction::I64DivS
    "i64.div_u" => @types.Instruction::I64DivU
    "i64.rem_s" => @types.Instruction::I64RemS
    "i64.rem_u" => @types.Instruction::I64RemU
    "i64.and" => @types.Instruction::I64And
    "i64.or" => @types.Instruction::I64Or
    "i64.xor" => @types.Instruction::I64Xor
    "i64.shl" => @types.Instruction::I64Shl
    "i64.shr_s" => @types.Instruction::I64ShrS
    "i64.shr_u" => @types.Instruction::I64ShrU
    "i64.rotl" => @types.Instruction::I64Rotl
    "i64.rotr" => @types.Instruction::I64Rotr

    // f32 operations
    "f32.abs" => @types.Instruction::F32Abs
    "f32.neg" => @types.Instruction::F32Neg
    "f32.ceil" => @types.Instruction::F32Ceil
    "f32.floor" => @types.Instruction::F32Floor
    "f32.trunc" => @types.Instruction::F32Trunc
    "f32.nearest" => @types.Instruction::F32Nearest
    "f32.sqrt" => @types.Instruction::F32Sqrt
    "f32.add" => @types.Instruction::F32Add
    "f32.sub" => @types.Instruction::F32Sub
    "f32.mul" => @types.Instruction::F32Mul
    "f32.div" => @types.Instruction::F32Div
    "f32.min" => @types.Instruction::F32Min
    "f32.max" => @types.Instruction::F32Max
    "f32.copysign" => @types.Instruction::F32Copysign
    "f32.eq" => @types.Instruction::F32Eq
    "f32.ne" => @types.Instruction::F32Ne
    "f32.lt" => @types.Instruction::F32Lt
    "f32.gt" => @types.Instruction::F32Gt
    "f32.le" => @types.Instruction::F32Le
    "f32.ge" => @types.Instruction::F32Ge

    // f64 operations
    "f64.abs" => @types.Instruction::F64Abs
    "f64.neg" => @types.Instruction::F64Neg
    "f64.ceil" => @types.Instruction::F64Ceil
    "f64.floor" => @types.Instruction::F64Floor
    "f64.trunc" => @types.Instruction::F64Trunc
    "f64.nearest" => @types.Instruction::F64Nearest
    "f64.sqrt" => @types.Instruction::F64Sqrt
    "f64.add" => @types.Instruction::F64Add
    "f64.sub" => @types.Instruction::F64Sub
    "f64.mul" => @types.Instruction::F64Mul
    "f64.div" => @types.Instruction::F64Div
    "f64.min" => @types.Instruction::F64Min
    "f64.max" => @types.Instruction::F64Max
    "f64.copysign" => @types.Instruction::F64Copysign
    "f64.eq" => @types.Instruction::F64Eq
    "f64.ne" => @types.Instruction::F64Ne
    "f64.lt" => @types.Instruction::F64Lt
    "f64.gt" => @types.Instruction::F64Gt
    "f64.le" => @types.Instruction::F64Le
    "f64.ge" => @types.Instruction::F64Ge

    // Conversions
    "i32.wrap_i64" => @types.Instruction::I32WrapI64
    "i32.trunc_f32_s" => @types.Instruction::I32TruncF32S
    "i32.trunc_f32_u" => @types.Instruction::I32TruncF32U
    "i32.trunc_f64_s" => @types.Instruction::I32TruncF64S
    "i32.trunc_f64_u" => @types.Instruction::I32TruncF64U
    "i64.extend_i32_s" => @types.Instruction::I64ExtendI32S
    "i64.extend_i32_u" => @types.Instruction::I64ExtendI32U
    "i64.trunc_f32_s" => @types.Instruction::I64TruncF32S
    "i64.trunc_f32_u" => @types.Instruction::I64TruncF32U
    "i64.trunc_f64_s" => @types.Instruction::I64TruncF64S
    "i64.trunc_f64_u" => @types.Instruction::I64TruncF64U
    "f32.convert_i32_s" => @types.Instruction::F32ConvertI32S
    "f32.convert_i32_u" => @types.Instruction::F32ConvertI32U
    "f32.convert_i64_s" => @types.Instruction::F32ConvertI64S
    "f32.convert_i64_u" => @types.Instruction::F32ConvertI64U
    "f32.demote_f64" => @types.Instruction::F32DemoteF64
    "f64.convert_i32_s" => @types.Instruction::F64ConvertI32S
    "f64.convert_i32_u" => @types.Instruction::F64ConvertI32U
    "f64.convert_i64_s" => @types.Instruction::F64ConvertI64S
    "f64.convert_i64_u" => @types.Instruction::F64ConvertI64U
    "f64.promote_f32" => @types.Instruction::F64PromoteF32
    "i32.reinterpret_f32" => @types.Instruction::I32ReinterpretF32
    "i64.reinterpret_f64" => @types.Instruction::I64ReinterpretF64
    "f32.reinterpret_i32" => @types.Instruction::F32ReinterpretI32
    "f64.reinterpret_i64" => @types.Instruction::F64ReinterpretI64
    _ => raise InvalidInstruction(kw)
  }
}

///|
fn parse_mem_arg(
  parser : Parser,
  instr : (Int, Int) -> @types.Instruction,
) -> @types.Instruction raise WatError {
  let mut offset = 0
  let mut align = 0
  // Parse optional offset=N and align=N
  while true {
    match parser.current {
      Keyword(s) =>
        if s.has_prefix("offset=") {
          let offset_str = StringBuilder::new()
          for i = 7; i < s.length(); i = i + 1 {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          offset = parse_int(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::new()
          for i = 6; i < s.length(); i = i + 1 {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_int(align_str.to_string())
          // Convert alignment to log2
          align = log2(a)
          parser.advance()
        } else {
          break
        }
      _ => break
    }
  }
  instr(align, offset)
}

///|
fn log2(n : Int) -> Int {
  let mut v = n
  let mut r = 0
  while v > 1 {
    v = v / 2
    r += 1
  }
  r
}

///|
fn Parser::parse_block_type(self : Parser) -> @types.BlockType raise WatError {
  // Check for (result type)
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("result") => {
        self.advance()
        let vt = self.parse_value_type()
        self.expect_rparen()
        return @types.BlockType::Value(vt)
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }
  @types.BlockType::Empty
}

///|
fn Parser::parse_type_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.type_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("type $\{name}")
      }
    _ => raise UnexpectedToken("expected type index")
  }
}

///|
fn Parser::parse_func_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.func_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("func $\{name}")
      }
    _ => raise UnexpectedToken("expected func index")
  }
}

///|
fn Parser::parse_local_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.local_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("local $\{name}")
      }
    _ => raise UnexpectedToken("expected local index")
  }
}

///|
fn Parser::parse_global_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.global_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("global $\{name}")
      }
    _ => raise UnexpectedToken("expected global index")
  }
}

///|
fn Parser::parse_label_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(_) =>
      // For now, just use numeric labels
      raise ParseError("named labels not yet supported")
    _ => raise UnexpectedToken("expected label index")
  }
}

///|
fn Parser::parse_memory_def(
  self : Parser,
) -> (@types.MemoryType, String?) raise WatError {
  self.advance() // skip "memory"
  let mut export_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      self.memory_names.set(name, 0)
      self.advance()
    }
    _ => ()
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name")
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse limits
  let min = self.parse_u32()
  let max = match self.current {
    Number(_) => Some(self.parse_u32())
    _ => None
  }
  self.expect_rparen()
  ({ limits: { min, max } }, export_name)
}

///|
fn Parser::parse_global_def(
  self : Parser,
) -> (@types.Global, String?) raise WatError {
  self.advance() // skip "global"
  let mut export_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      self.global_names.set(name, self.global_names.length())
      self.advance()
    }
    _ => ()
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name")
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse global type (mut i32) or i32
  let (value_type, mutable) = if self.current == LParen {
    self.advance()
    self.expect_keyword("mut")
    let vt = self.parse_value_type()
    self.expect_rparen()
    (vt, true)
  } else {
    (self.parse_value_type(), false)
  }

  // Parse init expression
  let init = self.parse_instructions()
  self.expect_rparen()
  ({ type_: { value_type, mutable }, init }, export_name)
}

///|
fn Parser::parse_table_def(
  self : Parser,
) -> (@types.TableType, String?) raise WatError {
  self.advance() // skip "table"
  let mut export_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      self.table_names.set(name, 0)
      self.advance()
    }
    _ => ()
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name")
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse limits and element type
  let min = self.parse_u32()
  let max = match self.current {
    Number(_) => Some(self.parse_u32())
    _ => None
  }
  let elem_type = self.parse_value_type()
  self.expect_rparen()
  ({ elem_type, limits: { min, max } }, export_name)
}

///|
fn Parser::parse_export_def(
  self : Parser,
  mod_ : @types.Module,
) -> @types.Export raise WatError {
  self.advance() // skip "export"
  let name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected export name")
  }
  self.expect_lparen()
  let desc = match self.current {
    Keyword("func") => {
      self.advance()
      let idx = self.parse_func_idx()
      @types.ExportDesc::Func(idx)
    }
    Keyword("memory") => {
      self.advance()
      let idx = match self.current {
        Number(_) => self.parse_u32()
        _ => 0
      }
      @types.ExportDesc::Memory(idx)
    }
    Keyword("table") => {
      self.advance()
      let idx = match self.current {
        Number(_) => self.parse_u32()
        _ => 0
      }
      @types.ExportDesc::Table(idx)
    }
    Keyword("global") => {
      self.advance()
      let idx = self.parse_global_idx()
      @types.ExportDesc::Global(idx)
    }
    _ => raise UnexpectedToken("expected export kind")
  }
  ignore(mod_)
  self.expect_rparen()
  self.expect_rparen()
  { name, desc }
}

///|
fn Parser::parse_import_def(
  self : Parser,
  mod_ : @types.Module,
) -> @types.Import raise WatError {
  self.advance() // skip "import"
  let mod_name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected module name")
  }
  let name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected import name")
  }
  self.expect_lparen()
  let desc = match self.current {
    Keyword("func") => {
      self.advance()
      // Optional func name
      match self.current {
        Id(fname) => {
          self.func_names.set(fname, mod_.funcs.length())
          self.advance()
        }
        _ => ()
      }
      // Parse type
      self.expect_lparen()
      self.expect_keyword("type")
      let type_idx = self.parse_type_idx()
      self.expect_rparen()
      @types.ImportDesc::Func(type_idx)
    }
    Keyword("memory") => {
      self.advance()
      let min = self.parse_u32()
      let max = match self.current {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      @types.ImportDesc::Memory({ limits: { min, max } })
    }
    Keyword("global") => {
      self.advance()
      let (value_type, mutable) = if self.current == LParen {
        self.advance()
        self.expect_keyword("mut")
        let vt = self.parse_value_type()
        self.expect_rparen()
        (vt, true)
      } else {
        (self.parse_value_type(), false)
      }
      @types.ImportDesc::Global({ value_type, mutable })
    }
    _ => raise UnexpectedToken("expected import kind")
  }
  self.expect_rparen()
  self.expect_rparen()
  { mod_name, name, desc }
}
