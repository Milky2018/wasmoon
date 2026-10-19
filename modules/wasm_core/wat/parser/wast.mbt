///|
/// Parse a WAST script (sequence of commands)
pub fn parse_wast(input : String) -> WastScript raise WatError {
  let parser = Parser::Parser(input)
  let commands : Array[(WastCommand, Int32)] = []

  // Check for inline module (module fields without explicit (module ...) wrapper)
  // WebAssembly spec allows this shorthand where (func) (memory 0) is equivalent to (module (func) (memory 0))
  if parser.is_inline_module() {
    // Parse as inline module - wrap in implicit module
    let line = parser.lexer.line
    let mod_ = parser.parse_inline_module()
    commands.push((Module(mod_, None), line))
  } else {
    // Parse normal WAST commands
    while parser.current.token != Eof {
      let line = parser.lexer.line
      let cmd = parser.parse_wast_command()
      commands.push((cmd, line))
    }
  }
  { commands, }
}

///|
/// Check if the input is an inline module (module fields without explicit module wrapper)
fn Parser::is_inline_module(self : Parser) -> Bool {
  // An inline module starts with ( followed by a module field keyword
  if self.current.token != LParen {
    return false
  }
  // Peek at the next token by temporarily advancing
  // Save lexer state
  let saved_pos = self.lexer.pos
  let saved_line = self.lexer.line
  let saved_column = self.lexer.column
  let saved_token_start_line = self.lexer.token_start_line
  let saved_token_start_column = self.lexer.token_start_column
  let saved_current = self.current

  // Advance and check - ignore any errors during peeking
  let is_inline = try {
    self.advance() // consume '('
    match self.current.token {
      Keyword(k) => is_module_field_keyword(k)
      _ => false
    }
  } catch {
    _ => false
  }

  // Restore state
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current
  is_inline
}

///|
/// Check if a keyword is a module field keyword
fn is_module_field_keyword(k : String) -> Bool {
  k == "type" ||
  k == "import" ||
  k == "func" ||
  k == "table" ||
  k == "memory" ||
  k == "global" ||
  k == "export" ||
  k == "start" ||
  k == "elem" ||
  k == "data" ||
  k == "tag"
}

///|
fn Parser::parse_inline_module(self : Parser) -> @types.Module raise WatError {
  // Use the same module parser for explicit and implicit wrappers.
  let module_ = parse(self.lexer.input, implicit_module=true)
  self.lexer.pos = self.lexer.input.length()
  self.current = self.lexer.next_token()
  module_
}

///|
fn Parser::parse_wast_command(self : Parser) -> WastCommand raise WatError {
  self.expect_lparen()
  self.parse_wast_command_body()
}

///|
fn Parser::parse_wast_command_body(self : Parser) -> WastCommand raise WatError {
  match self.current.token {
    Keyword("thread") => self.parse_wast_thread()
    Keyword("wait") => {
      self.advance()
      let name = self.parse_wast_required_id()
      self.expect_rparen()
      Wait(name)
    }
    Keyword("module") => self.parse_wast_module_command()
    Keyword("assert_return") => self.parse_wast_assert_return()
    Keyword("assert_trap") => self.parse_wast_assert_trap()
    Keyword("assert_suspension") => self.parse_wast_assert_suspension()
    Keyword("assert_exception") => self.parse_wast_assert_exception()
    Keyword("assert_exhaustion") => self.parse_wast_assert_exhaustion()
    Keyword("assert_invalid") => self.parse_wast_assert_invalid()
    Keyword("assert_malformed") => self.parse_wast_assert_malformed()
    Keyword("assert_unlinkable") => self.parse_wast_assert_unlinkable()
    Keyword("register") => self.parse_wast_register()
    Keyword("invoke") | Keyword("get") => {
      let action = self.parse_wast_action()
      self.expect_rparen()
      Action(action)
    }
    _ =>
      raise UnexpectedToken(
        "unexpected command: \{self.current.token}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_wast_required_id(self : Parser) -> String raise WatError {
  match self.parse_wast_optional_id() {
    Some(name) => name
    None => raise UnexpectedToken("expected identifier", self.loc())
  }
}

///|
fn Parser::parse_wast_thread(self : Parser) -> WastCommand raise WatError {
  self.advance()
  let name = self.parse_wast_required_id()
  let mut shared = None
  let commands : Array[(WastCommand, Int32)] = []
  while self.current.token != RParen {
    let line = self.lexer.line
    self.expect_lparen()
    if self.current.token == Keyword("shared") {
      if shared is Some(_) || !commands.is_empty() {
        raise UnexpectedToken(
          "shared module must precede thread commands",
          self.loc(),
        )
      }
      self.advance()
      self.expect_lparen()
      self.expect_keyword("module")
      shared = Some(self.parse_wast_required_id())
      self.expect_rparen()
      self.expect_rparen()
    } else {
      commands.push((self.parse_wast_command_body(), line))
    }
  }
  self.expect_rparen()
  Thread(name, shared, commands)
}

///|
fn Parser::parse_wast_module_command(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance() // consume 'module'
  let name = self.parse_wast_optional_id()
  match self.current.token {
    Keyword("binary") => {
      self.advance()
      let bytes = self.parse_wast_binary_module()
      self.expect_rparen()
      let mod_ = @binary_parser.parse_module(bytes) catch {
        e => return ModuleBinaryFailed(e.to_string())
      }
      Module(mod_, name)
    }
    Keyword("quote") => {
      self.advance()
      let parts : Array[String] = []
      while self.current.token != RParen {
        match self.current.token {
          String_(s) => {
            parts.push(s)
            self.advance()
          }
          _ => break
        }
      }
      self.expect_rparen()
      let text = decode_text(parts.join("")) catch {
        e => return ModuleBinaryFailed(e.to_string())
      }
      ModuleQuote([text])
    }
    Keyword("definition") => {
      self.advance()
      let def_name = self.parse_wast_optional_id()
      let final_name = match (name, def_name) {
        (Some(n), _) => Some(n)
        (None, Some(n)) => Some(n)
        (None, None) => None
      }
      match self.current.token {
        Keyword("binary") => {
          self.advance()
          let bytes = self.parse_wast_binary_module()
          self.expect_rparen()
          let mod_ = @binary_parser.parse_module(bytes) catch {
            e => return ModuleBinaryFailed(e.to_string())
          }
          ModuleDefinition(mod_, final_name)
        }
        _ => {
          let module_text = self.collect_wast_module_text()
          self.expect_rparen()
          let mod_ = parse("(module " + module_text + ")")
          ModuleDefinition(mod_, final_name)
        }
      }
    }
    Keyword("instance") => {
      // (module instance $instance_name $definition_name)
      self.advance() // consume 'instance'
      let instance_name = self.parse_wast_optional_id()
      let def_name = self.parse_wast_optional_id()
      self.expect_rparen()
      ModuleInstance(instance_name, def_name)
    }
    _ => {
      let module_text = self.collect_wast_module_text()
      self.expect_rparen()
      let mod_ = parse("(module " + module_text + ")")
      Module(mod_, name)
    }
  }
}

///|
fn Parser::collect_wast_module_text(self : Parser) -> String raise WatError {
  // Extract raw module text from input, preserving original formatting
  // Use token_start_pos to include the opening '(' that was already consumed
  let input = self.lexer.input
  let start_pos = self.lexer.token_start_pos
  let mut depth = 0
  let mut pos = start_pos
  while pos < input.length() {
    let c = input.code_unit_at(pos).unsafe_to_char()
    match c {
      '(' =>
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
          // Skip annotation - find matching close paren
          pos += 2
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
        if depth == 0 {
          break
        }
        depth -= 1
        pos += 1
      }
      ';' =>
        if pos + 1 < input.length() &&
          input.code_unit_at(pos + 1).unsafe_to_char() == ';' {
          while pos < input.length() {
            if input.code_unit_at(pos).unsafe_to_char() == '\n' {
              pos += 1
              break
            }
            pos += 1
          }
        } else {
          pos += 1
        }
      '"' => {
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
  let buf = StringBuilder::StringBuilder()
  for i in start_pos..<pos {
    buf.write_char(input.code_unit_at(i).unsafe_to_char())
  }
  for i in self.lexer.pos..<pos {
    if input.code_unit_at(i).unsafe_to_char() == '\n' {
      self.lexer.line += 1
    }
  }
  self.lexer.pos = pos
  self.current = self.lexer.next_token()
  buf.to_string()
}

///|
fn Parser::parse_wast_binary_module(self : Parser) -> Bytes raise WatError {
  let parts : Array[Byte] = []
  while self.current.token != RParen {
    match self.current.token {
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
fn Parser::parse_wast_optional_id(self : Parser) -> String? raise WatError {
  match self.current.token {
    Id(name) => {
      self.advance()
      Some(name)
    }
    _ => None
  }
}

///|
fn Parser::parse_wast_string(self : Parser) -> String raise WatError {
  match self.current.token {
    String_(s) => {
      self.advance()
      decode_text(s)
    }
    _ => raise UnexpectedToken("expected string", self.loc())
  }
}

///|
fn Parser::parse_wast_assert_return(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance() // consume 'assert_return'
  self.expect_lparen()
  let action = self.parse_wast_action()
  self.expect_rparen()
  let expected : Array[WastValue] = []
  while self.current.token == LParen {
    self.expect_lparen()
    let value = self.parse_wast_const_value()
    expected.push(value)
    self.expect_rparen()
  }
  self.expect_rparen()
  AssertReturn(action, expected)
}

///|
fn Parser::parse_wast_assert_trap(self : Parser) -> WastCommand raise WatError {
  self.advance() // consume 'assert_trap'
  self.expect_lparen()
  match self.current.token {
    Keyword("module") => {
      let source = self.parse_wast_module_source()
      self.expect_rparen()
      let msg = self.parse_wast_string()
      self.expect_rparen()
      AssertModuleTrap(source, msg)
    }
    _ => {
      let action = self.parse_wast_action()
      self.expect_rparen()
      let msg = self.parse_wast_string()
      self.expect_rparen()
      AssertTrap(action, msg)
    }
  }
}

///|
fn Parser::parse_wast_assert_exception(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance() // consume 'assert_exception'
  self.expect_lparen()
  let action = self.parse_wast_action()
  self.expect_rparen()
  self.expect_rparen()
  AssertException(action)
}

///|
fn Parser::parse_wast_assert_exhaustion(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance()
  self.expect_lparen()
  let action = self.parse_wast_action()
  self.expect_rparen()
  let msg = self.parse_wast_string()
  self.expect_rparen()
  AssertExhaustion(action, msg)
}

///|
fn Parser::parse_wast_assert_invalid(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance()
  self.expect_lparen()
  let source = self.parse_wast_module_source()
  self.expect_rparen()
  let msg = self.parse_wast_string()
  self.expect_rparen()
  AssertInvalid(source, msg)
}

///|
fn Parser::parse_wast_assert_malformed(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance()
  self.expect_lparen()
  let source = self.parse_wast_module_source()
  self.expect_rparen()
  let msg = self.parse_wast_string()
  self.expect_rparen()
  AssertMalformed(source, msg)
}

///|
fn Parser::parse_wast_assert_unlinkable(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance()
  self.expect_lparen()
  let source = self.parse_wast_module_source()
  self.expect_rparen()
  let msg = self.parse_wast_string()
  self.expect_rparen()
  AssertUnlinkable(source, msg)
}

///|
fn Parser::parse_wast_module_source(
  self : Parser,
) -> WastModuleSource raise WatError {
  match self.current.token {
    Keyword("module") => {
      self.advance()
      self.parse_wast_optional_id() |> ignore
      match self.current.token {
        Keyword("binary") => {
          self.advance()
          let bytes = self.parse_wast_binary_module()
          Binary(bytes)
        }
        Keyword("quote") => {
          self.advance()
          let parts : Array[String] = []
          while self.current.token != RParen {
            match self.current.token {
              String_(s) => {
                parts.push(s)
                self.advance()
              }
              _ => break
            }
          }
          let text = decode_text(parts.join("")) catch {
            e => return FailedToParse(e.to_string())
          }
          Quote([text])
        }
        _ => {
          let module_text = self.collect_wast_module_text()
          let mod_ = parse("(module " + module_text + ")") catch {
            e => return FailedToParse(e.to_string())
          }
          Inline(mod_)
        }
      }
    }
    _ => raise UnexpectedToken("expected 'module'", self.loc())
  }
}

///|
fn Parser::parse_wast_register(self : Parser) -> WastCommand raise WatError {
  self.advance()
  let name = self.parse_wast_string()
  let module_name = self.parse_wast_optional_id()
  self.expect_rparen()
  Register(name, module_name)
}

///|
fn Parser::parse_wast_action(self : Parser) -> WastAction raise WatError {
  match self.current.token {
    Keyword("invoke") => {
      self.advance()
      let module_name = self.parse_wast_optional_id()
      let func_name = self.parse_wast_string()
      let args : Array[WastValue] = []
      while self.current.token == LParen {
        self.expect_lparen()
        let value = self.parse_wast_const_value()
        args.push(value)
        self.expect_rparen()
      }
      Invoke(module_name, func_name, args)
    }
    Keyword("get") => {
      self.advance()
      let module_name = self.parse_wast_optional_id()
      let global_name = self.parse_wast_string()
      Get(module_name, global_name)
    }
    _ => raise UnexpectedToken("expected 'invoke' or 'get'", self.loc())
  }
}

///|
fn Parser::parse_wast_const_value(self : Parser) -> WastValue raise WatError {
  match self.current.token {
    Keyword("i32.const") => {
      self.advance()
      let n = self.parse_wast_i32()
      I32(n)
    }
    Keyword("i64.const") => {
      self.advance()
      let n = self.parse_wast_i64()
      I64(n)
    }
    Keyword("f32.const") => {
      self.advance()
      match self.current.token {
        Keyword("nan:canonical") => {
          self.advance()
          F32CanonicalNan
        }
        Keyword("nan:arithmetic") => {
          self.advance()
          F32ArithmeticNan
        }
        _ => F32(self.parse_wast_f32())
      }
    }
    Keyword("f64.const") => {
      self.advance()
      match self.current.token {
        Keyword("nan:canonical") => {
          self.advance()
          F64CanonicalNan
        }
        Keyword("nan:arithmetic") => {
          self.advance()
          F64ArithmeticNan
        }
        _ => F64(self.parse_wast_f64())
      }
    }
    Keyword("ref.null") => {
      self.advance()
      match self.current.token {
        Keyword(t) => {
          self.advance()
          RefNull(t)
        }
        _ => RefNull("")
      }
    }
    Keyword("ref.extern") => {
      self.advance()
      match self.current.token {
        Number(n) => {
          self.advance()
          RefExtern(parse_wast_int(n))
        }
        _ => RefExternAny // no argument means any non-null externref
      }
    }
    Keyword("ref.host") => {
      self.advance()
      match self.current.token {
        Number(n) => {
          self.advance()
          RefHost(parse_wast_int(n))
        }
        _ => RefHost(0) // no argument means any host ref
      }
    }
    Keyword("ref.func") => {
      self.advance()
      match self.current.token {
        Number(n) => {
          self.advance()
          RefFuncIndex(parse_wast_int(n))
        }
        _ => RefFunc
      }
    }
    // GC reference types
    Keyword("ref.array") => {
      self.advance()
      RefArray
    }
    Keyword("ref.struct") => {
      self.advance()
      RefStruct
    }
    Keyword("ref.eq") => {
      self.advance()
      RefEq
    }
    Keyword("ref.i31") => {
      self.advance()
      RefI31
    }
    Keyword("ref.any") => {
      self.advance()
      RefAny
    }
    Keyword("v128.const") => {
      self.advance()
      // Parse lane type and values - may contain NaN patterns
      self.parse_wast_v128_const()
    }
    Keyword("either") => {
      // Relaxed SIMD: multiple valid results
      // (either (v128.const ...) (v128.const ...) ...)
      self.advance()
      let alternatives : Array[WastValue] = []
      while self.current.token == LParen {
        self.expect_lparen()
        let value = self.parse_wast_const_value()
        alternatives.push(value)
        self.expect_rparen()
      }
      Either(alternatives)
    }
    _ => raise UnexpectedToken("expected const instruction", self.loc())
  }
}

///|
/// Parse v128.const for WAST - handles NaN patterns
fn Parser::parse_wast_v128_const(self : Parser) -> WastValue raise WatError {
  match self.current.token {
    Keyword(lane_type) => {
      self.advance()
      match lane_type {
        "i8x16" => {
          let buf : @buffer.Buffer = Buffer(size_hint=16)
          for _ in 0..<16 {
            let v = self.parse_wast_i32()
            buf.write_byte(v.to_byte())
          }
          V128(buf.contents())
        }
        "i16x8" => {
          let buf : @buffer.Buffer = Buffer(size_hint=16)
          for _ in 0..<8 {
            let v = self.parse_wast_i32()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
          }
          V128(buf.contents())
        }
        "i32x4" => {
          let buf : @buffer.Buffer = Buffer(size_hint=16)
          for _ in 0..<4 {
            let v = self.parse_wast_i32()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
            buf.write_byte((v >> 16).to_byte())
            buf.write_byte((v >> 24).to_byte())
          }
          V128(buf.contents())
        }
        "i64x2" => {
          let buf : @buffer.Buffer = Buffer(size_hint=16)
          for _ in 0..<2 {
            let v = self.parse_wast_i64()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
            buf.write_byte((v >> 16).to_byte())
            buf.write_byte((v >> 24).to_byte())
            buf.write_byte((v >> 32).to_byte())
            buf.write_byte((v >> 40).to_byte())
            buf.write_byte((v >> 48).to_byte())
            buf.write_byte((v >> 56).to_byte())
          }
          V128(buf.contents())
        }
        "f32x4" => {
          // Check if any lane has NaN pattern
          let lanes : Array[WastLaneValue] = []
          let mut has_nan = false
          for _ in 0..<4 {
            match self.current.token {
              Keyword("nan:canonical") => {
                self.advance()
                lanes.push(F32CanonicalNan)
                has_nan = true
              }
              Keyword("nan:arithmetic") => {
                self.advance()
                lanes.push(F32ArithmeticNan)
                has_nan = true
              }
              _ => {
                let f = self.parse_wast_f32()
                lanes.push(F32(f))
              }
            }
          }
          if has_nan {
            V128Pattern(lanes)
          } else {
            // Build bytes from float values
            let buf : @buffer.Buffer = Buffer(size_hint=16)
            for lane in lanes {
              match lane {
                F32(f) => {
                  let v = f.reinterpret_as_int()
                  buf.write_byte(v.to_byte())
                  buf.write_byte((v >> 8).to_byte())
                  buf.write_byte((v >> 16).to_byte())
                  buf.write_byte((v >> 24).to_byte())
                }
                _ => ()
              }
            }
            V128(buf.contents())
          }
        }
        "f64x2" => {
          // Check if any lane has NaN pattern
          let lanes : Array[WastLaneValue] = []
          let mut has_nan = false
          for _ in 0..<2 {
            match self.current.token {
              Keyword("nan:canonical") => {
                self.advance()
                lanes.push(F64CanonicalNan)
                has_nan = true
              }
              Keyword("nan:arithmetic") => {
                self.advance()
                lanes.push(F64ArithmeticNan)
                has_nan = true
              }
              _ => {
                let f = self.parse_wast_f64()
                lanes.push(F64(f))
              }
            }
          }
          if has_nan {
            V128Pattern(lanes)
          } else {
            // Build bytes from double values
            let buf : @buffer.Buffer = Buffer(size_hint=16)
            for lane in lanes {
              match lane {
                F64(f) => {
                  let v = f.reinterpret_as_int64()
                  buf.write_byte(v.to_byte())
                  buf.write_byte((v >> 8).to_byte())
                  buf.write_byte((v >> 16).to_byte())
                  buf.write_byte((v >> 24).to_byte())
                  buf.write_byte((v >> 32).to_byte())
                  buf.write_byte((v >> 40).to_byte())
                  buf.write_byte((v >> 48).to_byte())
                  buf.write_byte((v >> 56).to_byte())
                }
                _ => ()
              }
            }
            V128(buf.contents())
          }
        }
        _ =>
          raise ParseError(
            "invalid v128.const lane type: \{lane_type}",
            self.loc(),
          )
      }
    }
    _ =>
      raise UnexpectedToken(
        "expected lane type (i8x16, i16x8, etc), got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_wast_i32(self : Parser) -> Int32 raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_wast_int(s)
    }
    _ => raise UnexpectedToken("expected number", self.loc())
  }
}

///|
fn Parser::parse_wast_i64(self : Parser) -> Int64 raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_wast_int64(s)
    }
    _ => raise UnexpectedToken("expected number", self.loc())
  }
}

///|
fn Parser::parse_wast_f32(self : Parser) -> Float raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_float32(s)
    }
    Keyword(k) =>
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
        raise UnexpectedToken("expected number", self.loc())
      }
    _ => raise UnexpectedToken("expected number", self.loc())
  }
}

///|
fn Parser::parse_wast_f64(self : Parser) -> Double raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_float64(s)
    }
    Keyword(k) =>
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
        raise UnexpectedToken("expected number", self.loc())
      }
    _ => raise UnexpectedToken("expected number", self.loc())
  }
}

///|
fn parse_wast_int(s : String) -> Int32 raise WatError {
  if s.length() == 0 {
    raise InvalidNumber(s, { line: 0, column: 0, })
  }
  let mut start = 0
  let mut negative = false
  if s.code_unit_at(0) == '-' {
    negative = true
    start = 1
  } else if s.code_unit_at(0) == '+' {
    start = 1
  }
  if start + 1 < s.length() &&
    s.code_unit_at(start) == '0' &&
    (s.code_unit_at(start + 1) == 'x' || s.code_unit_at(start + 1) == 'X') {
    let hex_val = parse_wast_hex_int(s, start + 2)
    if negative {
      -hex_val
    } else {
      hex_val
    }
  } else {
    let mut result = 0
    for i in start..<s.length() {
      let c = s.code_unit_at(i).unsafe_to_char()
      if c == '_' {
        continue
      }
      if c < '0' || c > '9' {
        raise InvalidNumber(s, { line: 0, column: 0, })
      }
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
    if negative {
      -result
    } else {
      result
    }
  }
}

///|
fn parse_wast_hex_int(s : String, start : Int32) -> Int32 raise WatError {
  let mut result = 0
  for i in start..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue
    }
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      raise InvalidNumber(s, { line: 0, column: 0, })
    }
    result = result * 16 + digit
  }
  result
}

///|
fn parse_wast_int64(s : String) -> Int64 raise WatError {
  if s.length() == 0 {
    raise InvalidNumber(s, { line: 0, column: 0, })
  }
  let mut start = 0
  let mut negative = false
  if s.code_unit_at(0) == '-' {
    negative = true
    start = 1
  } else if s.code_unit_at(0) == '+' {
    start = 1
  }
  if start + 1 < s.length() &&
    s.code_unit_at(start) == '0' &&
    (s.code_unit_at(start + 1) == 'x' || s.code_unit_at(start + 1) == 'X') {
    let hex_val = parse_wast_hex_int64(s, start + 2)
    if negative {
      -hex_val
    } else {
      hex_val
    }
  } else {
    let mut result = 0L
    for i in start..<s.length() {
      let c = s.code_unit_at(i).unsafe_to_char()
      if c == '_' {
        continue
      }
      if c < '0' || c > '9' {
        raise InvalidNumber(s, { line: 0, column: 0, })
      }
      result = result * 10L + (c.to_int() - '0'.to_int()).to_int64()
    }
    if negative {
      -result
    } else {
      result
    }
  }
}

///|
fn parse_wast_hex_int64(s : String, start : Int32) -> Int64 raise WatError {
  let mut result = 0L
  for i in start..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue
    }
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      raise InvalidNumber(s, { line: 0, column: 0, })
    }
    result = result * 16L + digit.to_int64()
  }
  result
}

///|
fn Parser::parse_wast_assert_suspension(
  self : Parser,
) -> WastCommand raise WatError {
  self.advance()
  self.expect_lparen()
  let action = self.parse_wast_action()
  self.expect_rparen()
  let message = self.parse_wast_string()
  self.expect_rparen()
  AssertSuspension(action, message)
}
