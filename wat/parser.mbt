///|
/// Result of parsing a func definition - can be a regular function or an inline import
priv enum FuncDefResult {
  /// Regular function definition: (type_idx, code, export_names)
  FuncDef(Int, @types.FunctionCode, Array[String])
  /// Inline import: the import definition
  InlineImport(@types.Import, Array[String]) // import, optional export names
}

///|
/// Result of parsing a global definition - can be a regular global or an inline import
priv enum GlobalDefResult {
  /// Regular global definition: (global, export_names)
  GlobalDef(@types.Global, Array[String])
  /// Inline import: the import definition
  GlobalImport(@types.Import, Array[String]) // import, optional export names
}

///|
/// Result of parsing a memory definition - can be a regular memory or an inline import
priv enum MemoryDefResult {
  /// Regular memory definition: (memory_type, export_names)
  MemoryDef(@types.MemoryType, Array[String])
  /// Inline import: the import definition
  MemoryImport(@types.Import, Array[String]) // import, optional export names
  /// Memory with inline data: (memory_type, export_names, data_bytes)
  MemoryWithData(@types.MemoryType, Array[String], Bytes)
}

///|
/// Result of parsing a tag definition - can be a regular tag or an inline import
priv enum TagDefResult {
  /// Regular tag definition: (tag_type, export_names)
  TagDef(@types.TagType, Array[String])
  /// Inline import: the import definition
  TagImport(@types.Import, Array[String]) // import, optional export names
}

///|
/// WAT Parser
priv struct Parser {
  lexer : Lexer
  mut current : LocatedToken
  // Name resolution maps
  func_names : Map[String, Int]
  type_names : Map[String, Int]
  local_names : Map[String, Int]
  global_names : Map[String, Int]
  memory_names : Map[String, Int]
  table_names : Map[String, Int]
  tag_names : Map[String, Int]
  data_names : Map[String, Int]
  elem_names : Map[String, Int]
  // Label stack for block/loop/if - stores (name, depth) pairs
  // depth is the index from the innermost block (0 = current block)
  label_stack : Array[String?]
  // Reference to module types for inline type resolution in call_indirect
  mut types : Array[@types.SubType]
  // Reference to module type_rec_groups for implicit type matching
  mut type_rec_groups : Array[Int]
  // Field names per type: type_idx -> (field_name -> field_idx)
  field_names : Map[Int, Map[String, Int]]
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
    tag_names: {},
    data_names: {},
    elem_names: {},
    label_stack: [],
    types: [],
    type_rec_groups: [],
    field_names: {},
  }
}

///|
/// Get the current token's source location
fn Parser::loc(self : Parser) -> SourceLoc {
  self.current.to_loc()
}

///|
/// Check if a type at given index is in a singleton rec group.
/// Implicit function types should only match singleton rec groups.
fn is_singleton_rec_group(type_rec_groups : Array[Int], type_idx : Int) -> Bool {
  if type_idx < 0 || type_idx >= type_rec_groups.length() {
    return true // No rec group info, assume singleton
  }
  let rec_id = type_rec_groups[type_idx]
  let mut rec_size = 0
  for id in type_rec_groups {
    if id == rec_id {
      rec_size = rec_size + 1
    }
  }
  rec_size == 1
}

///|
/// Push a label onto the label stack (for block/loop/if)
fn Parser::push_label(self : Parser, name : String?) -> Unit {
  self.label_stack.push(name)
}

///|
/// Pop a label from the label stack
fn Parser::pop_label(self : Parser) -> Unit {
  self.label_stack.pop() |> ignore
}

///|
/// Resolve a named label to its depth index
/// Returns the number of blocks we need to break out of
fn Parser::resolve_label(self : Parser, name : String) -> Int? {
  // Search from the top of the stack (most recent block)
  for i = self.label_stack.length() - 1; i >= 0; i = i - 1 {
    if self.label_stack[i] is Some(label_name) && label_name == name {
      // Depth is distance from top of stack
      return Some(self.label_stack.length() - 1 - i)
    }
  }
  None
}

///|
/// Resolve a named memory to its index
fn Parser::resolve_memory(self : Parser, name : String) -> Int raise WatError {
  match self.memory_names.get(name) {
    Some(idx) => idx
    None => raise WatError::UndefinedIdentifier("memory $\{name}", self.loc())
  }
}

///|
/// Parse field index (numeric or by name for the given type)
fn Parser::parse_field_idx(self : Parser, type_idx : Int) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_u32(s)
    }
    Id(name) =>
      match self.field_names.get(type_idx) {
        Some(names) =>
          match names.get(name) {
            Some(idx) => {
              self.advance()
              idx
            }
            None =>
              raise WatError::UndefinedIdentifier(
                "field $\{name} in type \{type_idx}",
                self.loc(),
              )
          }
        None =>
          raise WatError::UndefinedIdentifier(
            "field $\{name} in type \{type_idx}",
            self.loc(),
          )
      }
    _ =>
      raise WatError::UnexpectedToken(
        "expected field index or name",
        self.loc(),
      )
  }
}

///|
/// Parse an optional memory index (Id or Number), defaults to 0
fn Parser::parse_optional_memidx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Id(name) => {
      let idx = self.resolve_memory(name)
      self.advance()
      idx
    }
    Number(s) =>
      // Only parse as memidx if it's a plain number (not offset=N or align=N)
      if !s.has_prefix("offset=") && !s.has_prefix("align=") {
        self.advance()
        parse_int(s)
      } else {
        0 // Default to memory 0
      }
    _ => 0 // Default to memory 0
  }
}

///|
fn Parser::advance(self : Parser) -> Unit raise WatError {
  self.current = self.lexer.next_token()
}

///|
/// Skip tokens until we find the matching closing parenthesis
/// Assumes we're currently inside a parenthesized expression
fn Parser::skip_to_matching_rparen(self : Parser) -> Unit raise WatError {
  let mut depth = 1
  while depth > 0 && self.current.token != Eof {
    match self.current.token {
      LParen => {
        depth = depth + 1
        self.advance()
      }
      RParen => {
        depth = depth - 1
        if depth > 0 {
          self.advance()
        }
      }
      _ => self.advance()
    }
  }
}

///|
fn Parser::expect_lparen(self : Parser) -> Unit raise WatError {
  match self.current.token {
    LParen => self.advance()
    _ =>
      raise WatError::UnexpectedToken(
        "expected '(', got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::expect_rparen(self : Parser) -> Unit raise WatError {
  match self.current.token {
    RParen => self.advance()
    _ =>
      raise WatError::UnexpectedToken(
        "expected ')', got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::expect_keyword(self : Parser, kw : String) -> Unit raise WatError {
  match self.current.token {
    Keyword(k) =>
      if k == kw {
        self.advance()
      } else {
        raise WatError::UnexpectedToken(
          "expected '\{kw}', got '\{k}'",
          self.loc(),
        )
      }
    _ =>
      raise WatError::UnexpectedToken(
        "expected '\{kw}', got \{self.current}",
        self.loc(),
      )
  }
}

///|
/// Skip an optional identifier (e.g., label after 'end' or 'else' in flat form)
fn Parser::skip_optional_id(self : Parser) -> Unit raise WatError {
  if self.current.token is Id(_) {
    self.advance()
  }
}

///|
fn Parser::parse_u32(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_u32(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
/// Parse a u64 number (for memory64 limits)
fn Parser::parse_u64(self : Parser) -> Int64 raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_u64(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_i32(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_i64(self : Parser) -> Int64 raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int64(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_f32(self : Parser) -> Float raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_float32(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_f64(self : Parser) -> Double raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_float64(s)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected number, got \{self.current}",
        self.loc(),
      )
  }
}

///|
/// Parse v128.const value
/// Formats: (v128.const i8x16 v0 v1 ... v15)
///          (v128.const i16x8 v0 v1 ... v7)
///          (v128.const i32x4 v0 v1 v2 v3)
///          (v128.const i64x2 v0 v1)
///          (v128.const f32x4 v0 v1 v2 v3)
///          (v128.const f64x2 v0 v1)
fn Parser::parse_v128_const(self : Parser) -> Bytes raise WatError {
  let buf : @buffer.Buffer = @buffer.new(size_hint=16)
  // Parse the lane type keyword
  match self.current.token {
    Keyword(lane_type) => {
      self.advance()
      match lane_type {
        "i8x16" =>
          for _ in 0..<16 {
            let v = self.parse_i32()
            buf.write_byte(v.to_byte())
          }
        "i16x8" =>
          for _ in 0..<8 {
            let v = self.parse_i32()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
          }
        "i32x4" =>
          for _ in 0..<4 {
            let v = self.parse_i32()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
            buf.write_byte((v >> 16).to_byte())
            buf.write_byte((v >> 24).to_byte())
          }
        "i64x2" =>
          for _ in 0..<2 {
            let v = self.parse_i64()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
            buf.write_byte((v >> 16).to_byte())
            buf.write_byte((v >> 24).to_byte())
            buf.write_byte((v >> 32).to_byte())
            buf.write_byte((v >> 40).to_byte())
            buf.write_byte((v >> 48).to_byte())
            buf.write_byte((v >> 56).to_byte())
          }
        "f32x4" =>
          for _ in 0..<4 {
            let f = self.parse_f32()
            let v = f.reinterpret_as_int()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
            buf.write_byte((v >> 16).to_byte())
            buf.write_byte((v >> 24).to_byte())
          }
        "f64x2" =>
          for _ in 0..<2 {
            let f = self.parse_f64()
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
        _ =>
          raise WatError::ParseError(
            "invalid v128.const lane type: \{lane_type}",
            self.loc(),
          )
      }
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected lane type (i8x16, i16x8, etc), got \{self.current}",
        self.loc(),
      )
  }
  buf.contents()
}

///|
fn Parser::parse_value_type(self : Parser) -> @types.ValueType raise WatError {
  match self.current.token {
    LParen => {
      // Handle (ref ...) types
      self.advance()
      self.expect_keyword("ref")
      // Check for nullable: (ref null ...) vs non-null: (ref ...)
      let is_nullable = self.current.token == Keyword("null")
      if is_nullable {
        self.advance()
      }
      // Parse heap type: func, extern, any, exn, none, nofunc, noexn, noextern, or $typeidx
      match self.current.token {
        Keyword("func") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::FuncRef
          } else {
            @types.ValueType::RefFunc
          }
        }
        Keyword("extern") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::ExternRef
          } else {
            @types.ValueType::RefExtern
          }
        }
        Keyword("any") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::AnyRef
          } else {
            @types.ValueType::RefAny
          }
        }
        Keyword("exn") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::ExnRef // exn only has nullable form in current spec
        }
        Keyword("none") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::NullRef // bottom type for any
        }
        Keyword("nofunc") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::NullFuncRef // bottom type for func
        }
        Keyword("noexn") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::NullExnRef // bottom type for exn
        }
        Keyword("noextern") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::NullExternRef // bottom type for extern
        }
        // GC abstract heap types
        Keyword("struct") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::RefNullStruct(-1) // -1 means abstract struct type
          } else {
            @types.ValueType::RefStruct(-1)
          }
        }
        Keyword("array") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::RefNullArray(-1) // -1 means abstract array type
          } else {
            @types.ValueType::RefArray(-1)
          }
        }
        Keyword("i31") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::RefNullI31
          } else {
            @types.ValueType::RefI31
          }
        }
        Keyword("eq") => {
          self.advance()
          self.expect_rparen()
          if is_nullable {
            @types.ValueType::RefNullEq
          } else {
            @types.ValueType::RefEq
          }
        }
        Id(name) => {
          // Typed reference like (ref $t)
          let type_idx = match self.type_names.get(name) {
            Some(idx) => idx
            None =>
              raise WatError::UnexpectedToken(
                "unknown type \{name}",
                self.loc(),
              )
          }
          self.advance()
          self.expect_rparen()
          self.get_typed_ref(type_idx, is_nullable)
        }
        Number(s) => {
          // Typed reference with numeric index like (ref 0)
          let type_idx = parse_int(s)
          self.advance()
          self.expect_rparen()
          self.get_typed_ref(type_idx, is_nullable)
        }
        _ => {
          self.expect_rparen()
          // Default to FuncRef/RefFunc based on nullability
          if is_nullable {
            @types.ValueType::FuncRef
          } else {
            @types.ValueType::RefFunc
          }
        }
      }
    }
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
        "anyref" => AnyRef
        "exnref" => ExnRef
        "nullref" => NullRef
        "nullfuncref" => NullFuncRef
        "nullexnref" => NullExnRef
        "nullexternref" => NullExternRef
        // GC reference type shorthands
        "eqref" => RefNullEq
        "i31ref" => RefNullI31
        "structref" => RefNullStruct(-1) // -1 means abstract struct type
        "arrayref" => RefNullArray(-1) // -1 means abstract array type
        _ =>
          raise WatError::UnexpectedToken(
            "expected value type, got '\{kw}'",
            self.loc(),
          )
      }
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected value type, got \{self.current}",
        self.loc(),
      )
  }
}

///|
/// Count the number of function imports
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Func(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_table_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Table(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_global_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Global(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_memory_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Memory(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_tag_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Tag(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Parse a WAT module from string
pub fn parse(input : String) -> @types.Module raise WatError {
  let parser = Parser::new(input)
  let mod_ = parser.parse_module()
  if parser.current.token != Eof {
    raise WatError::UnexpectedToken("unexpected trailing tokens", parser.loc())
  }
  mod_
}

///|
fn Parser::parse_module(self : Parser) -> @types.Module raise WatError {
  self.expect_lparen()
  self.expect_keyword("module")

  // Optional module name
  if self.current.token is Id(_) {
    self.advance()
  }
  let mod_ = @types.Module::new()

  // First pass: collect all names (to support forward references)
  // Save lexer state
  let saved_pos = self.lexer.pos
  let saved_line = self.lexer.line
  let saved_column = self.lexer.column
  let saved_token_start_line = self.lexer.token_start_line
  let saved_token_start_column = self.lexer.token_start_column
  let saved_current = self.current

  // Scan for definitions to collect names (to support forward references for non-type fields)
  let mut func_idx = 0
  let mut type_idx = 0
  let mut global_idx = 0
  let mut memory_idx = 0
  let mut table_idx = 0
  let mut tag_idx = 0
  let mut data_idx = 0
  let mut elem_idx = 0
  while self.current.token != RParen && self.current.token != Eof {
    match self.current.token {
      LParen => {
        self.advance()
        match self.current.token {
          Keyword("type") => {
            self.advance()
            // Register type name if present
            if self.current.token is Id(name) {
              self.type_names.set(name, type_idx)
              self.advance()
            }
            type_idx = type_idx + 1
            // Skip to end of type and advance past closing paren
            self.skip_to_matching_rparen()
            self.advance() // Move past the closing )
          }
          Keyword("rec") => {
            // Register types in rec group
            self.advance()
            while self.current.token == LParen {
              self.advance()
              if self.current.token == Keyword("type") {
                self.advance()
                if self.current.token is Id(name) {
                  self.type_names.set(name, type_idx)
                  self.advance()
                }
                type_idx = type_idx + 1
              }
              self.skip_to_matching_rparen()
              self.advance() // Move past the closing )
            }
            self.advance() // Move past the rec closing )
          }
          Keyword("import") => {
            self.advance()
            // Skip module name and import name
            if self.current.token is String_(_) {
              self.advance()
            }
            if self.current.token is String_(_) {
              self.advance()
            }
            // Check import kind
            if self.current.token == LParen {
              self.advance()
              match self.current.token {
                Keyword("func") => {
                  self.advance()
                  // Check for function name
                  if self.current.token is Id(name) {
                    self.func_names.set(name, func_idx)
                    self.advance()
                  }
                  func_idx = func_idx + 1
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
                Keyword("global") => {
                  self.advance()
                  // Check for global name
                  if self.current.token is Id(name) {
                    self.global_names.set(name, global_idx)
                    self.advance()
                  }
                  global_idx = global_idx + 1
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
                Keyword("memory") => {
                  self.advance()
                  // Check for memory name
                  if self.current.token is Id(name) {
                    self.memory_names.set(name, memory_idx)
                    self.advance()
                  }
                  memory_idx = memory_idx + 1
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
                Keyword("table") => {
                  self.advance()
                  // Check for table name
                  if self.current.token is Id(name) {
                    self.table_names.set(name, table_idx)
                    self.advance()
                  }
                  table_idx = table_idx + 1
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
                Keyword("tag") => {
                  self.advance()
                  // Check for tag name
                  if self.current.token is Id(name) {
                    self.tag_names.set(name, tag_idx)
                    self.advance()
                  }
                  tag_idx = tag_idx + 1
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
                _ => {
                  self.skip_to_matching_rparen()
                  self.advance() // Move past inner )
                }
              }
            }
            // Skip to end of import (the outer rparen)
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("func") => {
            self.advance()
            // Check for function name
            if self.current.token is Id(name) {
              self.func_names.set(name, func_idx)
              self.advance()
            }
            func_idx = func_idx + 1
            // Skip to end of func
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("global") => {
            self.advance()
            // Check for global name
            if self.current.token is Id(name) {
              self.global_names.set(name, global_idx)
              self.advance()
            }
            global_idx = global_idx + 1
            // Skip to end of global
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("memory") => {
            self.advance()
            // Check for memory name
            if self.current.token is Id(name) {
              self.memory_names.set(name, memory_idx)
              self.advance()
            }
            memory_idx = memory_idx + 1
            // Skip to end of memory
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("table") => {
            self.advance()
            // Check for table name
            if self.current.token is Id(name) {
              self.table_names.set(name, table_idx)
              self.advance()
            }
            table_idx = table_idx + 1
            // Skip to end of table
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("tag") => {
            self.advance()
            // Check for tag name
            if self.current.token is Id(name) {
              self.tag_names.set(name, tag_idx)
              self.advance()
            }
            tag_idx = tag_idx + 1
            // Skip to end of tag
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("data") => {
            self.advance()
            // Check for data name
            if self.current.token is Id(name) {
              self.data_names.set(name, data_idx)
              self.advance()
            }
            data_idx = data_idx + 1
            // Skip to end of data
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("elem") => {
            self.advance()
            // Check for elem name
            if self.current.token is Id(name) {
              self.elem_names.set(name, elem_idx)
              self.advance()
            }
            elem_idx = elem_idx + 1
            // Skip to end of elem
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          _ => {
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
        }
      }
      _ => self.advance()
    }
  }

  // Restore lexer state for type definition pass
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current

  // Share types array with parser BEFORE parsing types
  // This allows types to reference previously parsed types during the intermediate pass
  self.types = mod_.types
  self.type_rec_groups = mod_.type_rec_groups

  // Intermediate pass: parse ONLY explicit type definitions first
  // This ensures all explicit types are available before functions create implicit types
  while self.current.token != RParen && self.current.token != Eof {
    match self.current.token {
      LParen => {
        self.advance()
        match self.current.token {
          Keyword("type") => {
            let type_idx = mod_.types.length()
            let subtype = self.parse_type_def(type_idx)
            self.type_names.set("\{type_idx}", type_idx)
            mod_.types.push(subtype)
            // Standalone type is its own rec group
            mod_.type_rec_groups.push(type_idx)
          }
          Keyword("rec") =>
            // Parse recursive type group
            self.parse_rec_group(mod_)
          _ => {
            self.skip_to_matching_rparen()
            self.advance() // Move past )
          }
        }
      }
      _ => self.advance()
    }
  }

  // Restore lexer state for main parsing pass
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current

  // Main pass: parse everything except types (already parsed)
  while self.current.token != RParen && self.current.token != Eof {
    match self.current.token {
      LParen => {
        self.advance()
        match self.current.token {
          Keyword("type") => {
            // Already parsed in intermediate pass, skip
            self.skip_to_matching_rparen()
            self.advance() // Move past )
          }
          Keyword("rec") => {
            // Already parsed in intermediate pass, skip
            self.skip_to_matching_rparen()
            self.advance() // Move past )
          }
          Keyword("func") =>
            match self.parse_func_def(mod_) {
              FuncDef(type_idx, code, export_names) => {
                // func_idx must account for imported functions
                let func_idx = count_func_imports(mod_.imports) +
                  mod_.funcs.length()
                mod_.funcs.push(type_idx)
                mod_.codes.push(code)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Func(func_idx),
                  })
                }
              }
              InlineImport(imp, export_names) => {
                // Add the import and optionally export it
                let func_idx = count_func_imports(mod_.imports)
                mod_.imports.push(imp)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Func(func_idx),
                  })
                }
              }
            }
          Keyword("memory") =>
            match self.parse_memory_def() {
              MemoryDef(mem, export_names) => {
                let mem_idx = mod_.memories.length()
                mod_.memories.push(mem)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Memory(mem_idx),
                  })
                }
              }
              MemoryImport(imp, export_names) => {
                // Count existing memory imports
                let mut memory_import_count = 0
                for existing in mod_.imports {
                  if existing.desc is @types.ImportDesc::Memory(_) {
                    memory_import_count += 1
                  }
                }
                mod_.imports.push(imp)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Memory(memory_import_count),
                  })
                }
              }
              MemoryWithData(mem, export_names, data_bytes) => {
                let mem_idx = mod_.memories.length()
                mod_.memories.push(mem)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Memory(mem_idx),
                  })
                }
                // Add inline data segment at offset 0
                mod_.datas.push({
                  memory_idx: mem_idx,
                  offset: [@types.Instruction::I32Const(0)],
                  init: data_bytes,
                })
              }
            }
          Keyword("global") =>
            match self.parse_global_def() {
              GlobalDef(global, export_names) => {
                // Count existing global imports for correct global index
                let mut num_global_imports = 0
                for existing in mod_.imports {
                  if existing.desc is @types.ImportDesc::Global(_) {
                    num_global_imports += 1
                  }
                }
                // Global index = number of imports + number of defined globals
                let global_idx = num_global_imports + mod_.globals.length()
                mod_.globals.push(global)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Global(global_idx),
                  })
                }
              }
              GlobalImport(imp, export_names) => {
                // Count existing global imports
                let mut global_import_count = 0
                for existing in mod_.imports {
                  if existing.desc is @types.ImportDesc::Global(_) {
                    global_import_count += 1
                  }
                }
                mod_.imports.push(imp)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Global(global_import_count),
                  })
                }
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
            let (table, export_name, inline_elem, tbl_name) = self.parse_table_def(
              mod_,
            )
            let table_idx = mod_.tables.length()
            mod_.tables.push(table)
            // Register table name with correct index
            if tbl_name is Some(name) {
              self.table_names.set(name, table_idx)
            }
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Table(table_idx),
              })
            }
            if inline_elem is Some(elem) {
              mod_.elems.push(elem)
            }
          }
          Keyword("start") => {
            self.advance() // skip "start"
            let func_idx = self.parse_func_idx()
            mod_.start = Some(func_idx)
            self.expect_rparen()
          }
          Keyword("data") => {
            let data_idx = mod_.datas.length()
            let data = self.parse_data_def(data_idx~)
            mod_.datas.push(data)
          }
          Keyword("elem") => {
            let elem_idx = mod_.elems.length()
            let elem = self.parse_elem_def(elem_idx~)
            mod_.elems.push(elem)
          }
          Keyword("tag") =>
            match self.parse_tag_def(mod_) {
              TagDef(tag, export_names) => {
                let tag_idx = count_tag_imports(mod_.imports) +
                  mod_.tags.length()
                mod_.tags.push(tag)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Tag(tag_idx),
                  })
                }
              }
              TagImport(imp, export_names) => {
                let tag_idx = count_tag_imports(mod_.imports)
                mod_.imports.push(imp)
                for name in export_names {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Tag(tag_idx),
                  })
                }
              }
            }
          Keyword(kw) =>
            raise WatError::UnexpectedToken(
              "unexpected module field: \{kw}",
              self.loc(),
            )
          _ =>
            raise WatError::UnexpectedToken("expected module field", self.loc())
        }
      }
      _ => raise WatError::UnexpectedToken("expected '(' in module", self.loc())
    }
  }
  self.expect_rparen()
  // Populate func_names with reverse mapping (index -> name)
  for entry in self.func_names {
    let (name, idx) = entry
    mod_.func_names.set(idx, name)
  }
  mod_
}

///|
fn Parser::parse_type_def(
  self : Parser,
  type_idx : Int,
) -> @types.SubType raise WatError {
  self.advance() // skip "type"
  // Optional type name
  if self.current.token is Id(name) {
    self.advance()
    self.type_names.set(name, type_idx)
  }
  self.expect_lparen()
  // Check for sub keyword (type inheritance)
  let (is_final, supertypes, has_sub) = if self.current.token == Keyword("sub") {
    self.advance() // skip "sub"
    // Check for optional "final" keyword
    let is_final = if self.current.token == Keyword("final") {
      self.advance()
      true
    } else {
      false
    }
    // Check for optional supertype index
    let supertypes : Array[Int] = []
    if self.current.token is Id(name) {
      match self.type_names.get(name) {
        Some(idx) => {
          supertypes.push(idx)
          self.advance()
        }
        None =>
          raise WatError::UnexpectedToken(
            "unknown type identifier: \{name}",
            self.loc(),
          )
      }
    } else if self.current.token is Number(s) {
      supertypes.push(parse_int(s))
      self.advance()
    }
    self.expect_lparen() // lparen for composite type
    (is_final, supertypes, true)
  } else {
    (true, [], false) // Default: final type without supertypes
  }
  // Handle different type definition kinds: func, struct, array
  let composite = match self.current.token {
    Keyword("func") => {
      self.advance() // skip "func"
      let ft = self.parse_func_type()
      self.expect_rparen() // close func
      @types.CompositeType::Func(ft)
    }
    Keyword("struct") => {
      self.advance() // skip "struct"
      let st = self.parse_struct_type(type_idx)
      self.expect_rparen() // close struct
      @types.CompositeType::Struct(st)
    }
    Keyword("array") => {
      self.advance() // skip "array"
      let at = self.parse_array_type()
      self.expect_rparen() // close array
      @types.CompositeType::Array(at)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected 'func', 'struct', or 'array', got '\{self.current.token}'",
        self.loc(),
      )
  }
  if has_sub {
    self.expect_rparen() // close sub
  }
  self.expect_rparen() // close type
  { final_: is_final, supertypes, composite }
}

///|
/// Parse a storage type: i8, i16, or a value type
fn Parser::parse_storage_type(
  self : Parser,
) -> @types.StorageType raise WatError {
  match self.current.token {
    Keyword("i8") => {
      self.advance()
      @types.StorageType::Packed(@types.PackedType::I8)
    }
    Keyword("i16") => {
      self.advance()
      @types.StorageType::Packed(@types.PackedType::I16)
    }
    _ => @types.StorageType::Val(self.parse_value_type())
  }
}

///|
/// Parse a field type: (field [name] [mut] <storage_type>) or just <storage_type>
fn Parser::parse_field_type(self : Parser) -> @types.FieldType raise WatError {
  // Check if this is a full field definition with (field ...)
  if self.current.token == LParen {
    self.advance()
    if self.current.token == Keyword("field") {
      self.advance() // skip "field"
      // Optional field name
      if self.current.token is Id(_) {
        self.advance()
      }
      // Check for mutability
      let mutable = if self.current.token == LParen {
        self.advance()
        if self.current.token == Keyword("mut") {
          self.advance()
          let storage_type = self.parse_storage_type()
          self.expect_rparen() // close mut
          self.expect_rparen() // close field
          return { storage_type, mutable: true }
        } else {
          // Not mut, restore lparen context and parse as storage type
          // This handles (field (ref $t)) case
          let storage_type = self.parse_storage_type_after_lparen()
          self.expect_rparen() // close field
          return { storage_type, mutable: false }
        }
      } else {
        false
      }
      let storage_type = self.parse_storage_type()
      self.expect_rparen() // close field
      { storage_type, mutable }
    } else if self.current.token == Keyword("mut") {
      // Shorthand: (mut <storage_type>)
      self.advance()
      let storage_type = self.parse_storage_type()
      self.expect_rparen()
      { storage_type, mutable: true }
    } else {
      // It's a storage type starting with lparen, like (ref ...)
      let storage_type = self.parse_storage_type_after_lparen()
      { storage_type, mutable: false }
    }
  } else {
    // Just a storage type
    let storage_type = self.parse_storage_type()
    { storage_type, mutable: false }
  }
}

///|
/// Parse storage type after we've already consumed the lparen
fn Parser::parse_storage_type_after_lparen(
  self : Parser,
) -> @types.StorageType raise WatError {
  // We've already consumed the lparen, now parse (ref ...) style type
  self.expect_keyword("ref")
  let is_nullable = self.current.token == Keyword("null")
  if is_nullable {
    self.advance()
  }
  let heap_type = self.parse_heap_type(is_nullable)
  self.expect_rparen()
  @types.StorageType::Val(heap_type)
}

///|
/// Parse a heap type and return the corresponding ValueType
fn Parser::parse_heap_type(
  self : Parser,
  is_nullable : Bool,
) -> @types.ValueType raise WatError {
  match self.current.token {
    Keyword("func") => {
      self.advance()
      if is_nullable {
        @types.ValueType::FuncRef
      } else {
        @types.ValueType::RefFunc
      }
    }
    Keyword("extern") => {
      self.advance()
      if is_nullable {
        @types.ValueType::ExternRef
      } else {
        @types.ValueType::RefExtern
      }
    }
    Keyword("any") => {
      self.advance()
      if is_nullable {
        @types.ValueType::AnyRef
      } else {
        @types.ValueType::RefAny
      }
    }
    Keyword("eq") => {
      self.advance()
      if is_nullable {
        @types.ValueType::RefNullEq
      } else {
        @types.ValueType::RefEq
      }
    }
    Keyword("i31") => {
      self.advance()
      if is_nullable {
        @types.ValueType::RefNullI31
      } else {
        @types.ValueType::RefI31
      }
    }
    Keyword("struct") => {
      self.advance()
      // Abstract struct type (not a specific struct)
      if is_nullable {
        @types.ValueType::RefNullStruct(-1)
      } else {
        @types.ValueType::RefStruct(-1)
      }
    }
    Keyword("array") => {
      self.advance()
      // Abstract array type (not a specific array)
      if is_nullable {
        @types.ValueType::RefNullArray(-1)
      } else {
        @types.ValueType::RefArray(-1)
      }
    }
    Keyword("exn") => {
      self.advance()
      @types.ValueType::ExnRef
    }
    Keyword("none") => {
      self.advance()
      @types.ValueType::RefNone
    }
    Keyword("nofunc") => {
      self.advance()
      @types.ValueType::NullFuncRef
    }
    Keyword("noexn") => {
      self.advance()
      @types.ValueType::NullExnRef
    }
    Keyword("noextern") => {
      self.advance()
      @types.ValueType::NullExternRef
    }
    Id(name) => {
      let type_idx = match self.type_names.get(name) {
        Some(idx) => idx
        None =>
          raise WatError::UnexpectedToken("unknown type \{name}", self.loc())
      }
      self.advance()
      self.get_typed_ref(type_idx, is_nullable)
    }
    Number(s) => {
      let type_idx = parse_int(s)
      self.advance()
      self.get_typed_ref(type_idx, is_nullable)
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected heap type, got \{self.current.token}",
        self.loc(),
      )
  }
}

///|
/// Parse struct type: (field ...) (field ...) ...
fn Parser::parse_struct_type(
  self : Parser,
  type_idx : Int,
) -> @types.StructType raise WatError {
  let fields : Array[@types.FieldType] = []
  // Initialize field names map for this type
  self.field_names.set(type_idx, {})
  // Parse fields until we hit RParen (end of struct)
  while self.current.token != RParen {
    self.parse_field_types(type_idx, fields)
  }
  { fields, }
}

///|
/// Parse field types - handles abbreviated form (field i32 i32) which produces multiple fields
fn Parser::parse_field_types(
  self : Parser,
  type_idx : Int,
  fields : Array[@types.FieldType],
) -> Unit raise WatError {
  // Check if this is a full field definition with (field ...)
  if self.current.token == LParen {
    self.advance()
    if self.current.token == Keyword("field") {
      self.advance() // skip "field"
      // Optional field name - only one name allowed, applied to first field
      let field_name : String? = if self.current.token is Id(name) {
        self.advance()
        Some(name)
      } else {
        None
      }
      // Register field name if present (for the first field only)
      match field_name {
        Some(name) =>
          match self.field_names.get(type_idx) {
            Some(names) => names.set(name, fields.length())
            None => ()
          }
        None => ()
      }
      // Check for (mut ...) first - this only applies to single field
      if self.current.token == LParen {
        self.advance()
        if self.current.token == Keyword("mut") {
          self.advance()
          let storage_type = self.parse_storage_type()
          self.expect_rparen() // close mut
          fields.push({ storage_type, mutable: true })
          self.expect_rparen() // close field
          return
        } else {
          // Not mut, it's a storage type like (ref ...), parse it but continue for more
          let storage_type = self.parse_storage_type_after_lparen()
          fields.push({ storage_type, mutable: false })
          // Continue parsing more types if any
          while self.current.token != RParen {
            let storage_type = self.parse_storage_type()
            fields.push({ storage_type, mutable: false })
          }
          self.expect_rparen() // close field
          return
        }
      }
      // Parse one or more storage types (abbreviated form)
      // Can include (mut <valtype>) for mutable fields
      while self.current.token != RParen {
        if self.current.token == LParen {
          self.advance()
          if self.current.token == Keyword("mut") {
            // Mutable field: (mut <storage_type>)
            self.advance()
            let storage_type = self.parse_storage_type()
            self.expect_rparen()
            fields.push({ storage_type, mutable: true })
          } else {
            // Reference type: (ref ...)
            let storage_type = self.parse_storage_type_after_lparen()
            fields.push({ storage_type, mutable: false })
          }
        } else {
          let storage_type = self.parse_storage_type()
          fields.push({ storage_type, mutable: false })
        }
      }
      self.expect_rparen() // close field
    } else if self.current.token == Keyword("mut") {
      // Shorthand: (mut <storage_type>)
      self.advance()
      let storage_type = self.parse_storage_type()
      self.expect_rparen()
      fields.push({ storage_type, mutable: true })
    } else {
      // It's a storage type starting with lparen, like (ref ...)
      let storage_type = self.parse_storage_type_after_lparen()
      fields.push({ storage_type, mutable: false })
    }
  } else {
    // Just a storage type
    let storage_type = self.parse_storage_type()
    fields.push({ storage_type, mutable: false })
  }
}

///|
/// Parse array type: [mut] <storage_type> or (field [mut] <storage_type>)
fn Parser::parse_array_type(self : Parser) -> @types.ArrayType raise WatError {
  let element = self.parse_field_type()
  { element, }
}

///|
/// Parse a recursive type group: (rec (type ...) (type ...) ...)
/// Recursive groups allow types to reference each other (forward references)
fn Parser::parse_rec_group(
  self : Parser,
  mod_ : @types.Module,
) -> Unit raise WatError {
  self.advance() // skip "rec"

  // First pass: pre-register all type names so forward references work
  // Save lexer state
  let saved_pos = self.lexer.pos
  let saved_line = self.lexer.line
  let saved_column = self.lexer.column
  let saved_token_start_line = self.lexer.token_start_line
  let saved_token_start_column = self.lexer.token_start_column
  let saved_current = self.current

  // Scan through all type definitions in this rec group to register names
  let start_type_idx = mod_.types.length()
  let mut type_count = 0
  while self.current.token == LParen {
    self.advance()
    if self.current.token == Keyword("type") {
      self.advance() // skip "type"
      // Check for type name
      if self.current.token is Id(name) {
        let type_idx = start_type_idx + type_count
        self.type_names.set(name, type_idx)
        // Also register numeric index
        self.type_names.set("\{type_idx}", type_idx)
      }
      type_count = type_count + 1
    }
    self.skip_to_matching_rparen()
    self.advance() // Move past the closing )
  }

  // Restore lexer state for second pass
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current

  // Second pass: actually parse all type definitions
  // All types in this rec group get the same rec group ID (the start index)
  let rec_group_id = start_type_idx
  while self.current.token == LParen {
    self.advance()
    if self.current.token == Keyword("type") {
      let type_idx = mod_.types.length()
      let subtype = self.parse_type_def(type_idx)
      // Name was already registered in first pass, just register numeric index
      self.type_names.set("\{type_idx}", type_idx)
      mod_.types.push(subtype)
      mod_.type_rec_groups.push(rec_group_id)
    } else {
      self.skip_to_matching_rparen()
      self.advance() // Move past the closing )
    }
  }
  self.expect_rparen() // close rec
}

///|
fn Parser::parse_func_type(self : Parser) -> @types.FuncType raise WatError {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = []

  // Parse params
  while self.current.token == LParen {
    let saved_pos = self.lexer.pos
    self.advance()
    match self.current.token {
      Keyword("param") => {
        self.advance()
        // Optional name
        if self.current.token is Id(_) {
          self.advance()
        }
        // Parse types until )
        while self.current.token != RParen {
          params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current.token != RParen {
          results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        // Not param/result, restore and break
        self.lexer.pos = saved_pos
        self.current = LocatedToken::synthetic(LParen)
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
) -> FuncDefResult raise WatError {
  self.advance() // skip "func"
  let export_names : Array[String] = []
  let mut func_name : String? = None

  // Optional function name
  if self.current.token is Id(name) {
    func_name = Some(name)
    self.advance()
  }

  // Clear local names for this function
  self.local_names.clear()

  // Check for inline exports and imports (exports can come before or after import)
  // Pattern: (func $name (export "e1") (export "e2") (import "mod" "name") ...)
  // or:      (func $name (import "mod" "name") (export "e1") ...)
  while self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
      Keyword("export") => {
        self.advance()
        match self.current.token {
          String_(s) => {
            export_names.push(s)
            self.advance()
          }
          _ =>
            raise WatError::UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      Keyword("import") => {
        self.advance()
        // Parse module name and import name
        let mod_name = match self.current.token {
          String_(s) => {
            self.advance()
            s
          }
          _ =>
            raise WatError::UnexpectedToken("expected module name", self.loc())
        }
        let import_name = match self.current.token {
          String_(s) => {
            self.advance()
            s
          }
          _ =>
            raise WatError::UnexpectedToken("expected import name", self.loc())
        }
        self.expect_rparen() // close import

        // Check for more inline exports after import
        while self.current.token == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current.token {
            Keyword("export") => {
              self.advance()
              match self.current.token {
                String_(s) => {
                  export_names.push(s)
                  self.advance()
                }
                _ =>
                  raise WatError::UnexpectedToken(
                    "expected export name",
                    self.loc(),
                  )
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LocatedToken::synthetic(LParen)
              break
            }
          }
        }

        // Parse type reference or inline type for the import
        let mut type_idx = -1
        let inline_params : Array[@types.ValueType] = []
        let inline_results : Array[@types.ValueType] = []
        while self.current.token == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current.token {
            Keyword("type") => {
              self.advance()
              type_idx = self.parse_type_idx()
              self.expect_rparen()
            }
            Keyword("param") => {
              self.advance()
              // Optional name
              if self.current.token is Id(name) {
                self.local_names.set(name, inline_params.length())
                self.advance()
              }
              while self.current.token != RParen {
                inline_params.push(self.parse_value_type())
              }
              self.expect_rparen()
            }
            Keyword("result") => {
              self.advance()
              while self.current.token != RParen {
                inline_results.push(self.parse_value_type())
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LocatedToken::synthetic(LParen)
              break
            }
          }
        }

        // Create type if needed
        if type_idx < 0 {
          let ft : @types.FuncType = {
            params: inline_params,
            results: inline_results,
          }
          // Check if this type already exists
          let mut found = -1
          for i, subtype in mod_.types {
            // Only match against function types
            match subtype.composite {
              Func(t) =>
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
                  // Implicit types should only match singleton rec groups
                  if match_ && is_singleton_rec_group(mod_.type_rec_groups, i) {
                    found = i
                    break
                  }
                }
              _ => ()
            }
          }
          if found >= 0 {
            type_idx = found
          } else {
            type_idx = mod_.types.length()
            mod_.types.push(@types.SubType::from_func(ft))
            // Implicit type is its own rec group
            mod_.type_rec_groups.push(type_idx)
          }
        }
        self.expect_rparen() // close func

        // Register function name with index (will be assigned when import is added)
        // The func_idx for imports needs to be the count of existing function imports
        let import_func_idx = count_func_imports(mod_.imports)
        if func_name is Some(name) {
          self.func_names.set(name, import_func_idx)
        }
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Func(type_idx),
        }
        return FuncDefResult::InlineImport(imp, export_names)
      }
      _ => {
        // Not export or import, restore state and break
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LocatedToken::synthetic(LParen)
        break
      }
    }
  }

  // Regular function definition - register the name now
  // func_idx must account for imported functions
  let func_idx = count_func_imports(mod_.imports) + mod_.funcs.length()
  if func_name is Some(name) {
    self.func_names.set(name, func_idx)
  }

  // Parse type reference or inline type
  let mut type_idx = -1
  let inline_params : Array[@types.ValueType] = []
  let inline_results : Array[@types.ValueType] = []

  // Parse (type $idx) or inline params/results
  while self.current.token == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current.token {
      Keyword("type") => {
        self.advance()
        type_idx = self.parse_type_idx()
        self.expect_rparen()
      }
      Keyword("param") => {
        self.advance()
        // Optional name
        match self.current.token {
          Id(name) => {
            self.local_names.set(name, inline_params.length())
            self.advance()
          }
          _ => ()
        }
        while self.current.token != RParen {
          inline_params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current.token != RParen {
          inline_results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LocatedToken::synthetic(LParen)
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
    for i, subtype in mod_.types {
      // Only match against function types
      match subtype.composite {
        Func(t) =>
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
            // Implicit types should only match singleton rec groups
            if match_ && is_singleton_rec_group(mod_.type_rec_groups, i) {
              found = i
              break
            }
          }
        _ => ()
      }
    }
    if found >= 0 {
      type_idx = found
    } else {
      type_idx = mod_.types.length()
      mod_.types.push(@types.SubType::from_func(ft))
      // Implicit type is its own rec group
      mod_.type_rec_groups.push(type_idx)
    }
  }

  // Calculate actual param count - if type_idx was used, get params from type
  // Otherwise use inline_params
  let param_count = if type_idx >= 0 && type_idx < mod_.types.length() {
    mod_.get_func_type(type_idx).params.length()
  } else {
    inline_params.length()
  }

  // Parse locals
  let locals : Array[@types.ValueType] = []
  while self.current.token == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current.token {
      Keyword("local") => {
        self.advance()
        // Optional name
        if self.current.token is Id(name) {
          let local_idx = param_count + locals.length()
          self.local_names.set(name, local_idx)
          self.advance()
        }
        while self.current.token != RParen {
          locals.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LocatedToken::synthetic(LParen)
        break
      }
    }
  }

  // Parse body instructions
  let body = self.parse_instructions()
  self.expect_rparen() // close func
  FuncDefResult::FuncDef(type_idx, { locals, body }, export_names)
}

///|
fn Parser::parse_type_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
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
        None => raise WatError::UndefinedIdentifier("type $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected type index", self.loc())
  }
}

///|
fn Parser::parse_func_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
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
        None => raise WatError::UndefinedIdentifier("func $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected func index", self.loc())
  }
}

///|
fn Parser::parse_local_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
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
        None =>
          raise WatError::UndefinedIdentifier("local $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected local index", self.loc())
  }
}

///|
fn Parser::parse_global_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
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
        None =>
          raise WatError::UndefinedIdentifier("global $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected global index", self.loc())
  }
}

///|
fn Parser::parse_table_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.table_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None =>
          raise WatError::UndefinedIdentifier("table $\{name}", self.loc())
      }
    _ =>
      // Default to table 0 if no index specified
      0
  }
}

///|
/// Parse an index for memory.init instruction.
/// This handles the ambiguity where the first index could be either memidx or dataidx.
/// We parse it as a raw number/id and resolve based on context.
fn Parser::parse_index_for_memory_init(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) => {
      self.advance()
      // Try memory names first, then data names
      match self.memory_names.get(name) {
        Some(idx) => idx
        None =>
          match self.data_names.get(name) {
            Some(idx) => idx
            None =>
              raise WatError::UndefinedIdentifier(
                "memory or data $\{name}",
                self.loc(),
              )
          }
      }
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected memory or data index",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_data_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.data_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise WatError::UndefinedIdentifier("data $\{name}", self.loc())
      }
    _ =>
      raise WatError::UnexpectedToken("expected data segment index", self.loc())
  }
}

///|
fn Parser::parse_elem_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.elem_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise WatError::UndefinedIdentifier("elem $\{name}", self.loc())
      }
    _ =>
      raise WatError::UnexpectedToken("expected elem segment index", self.loc())
  }
}

///|
/// Get the appropriate typed reference for a type index
fn Parser::get_typed_ref(
  self : Parser,
  type_idx : Int,
  is_nullable : Bool,
) -> @types.ValueType {
  // Check if we have type info for this index
  if type_idx >= 0 && type_idx < self.types.length() {
    match self.types[type_idx].composite {
      Struct(_) =>
        if is_nullable {
          @types.ValueType::RefNullStruct(type_idx)
        } else {
          @types.ValueType::RefStruct(type_idx)
        }
      Array(_) =>
        if is_nullable {
          @types.ValueType::RefNullArray(type_idx)
        } else {
          @types.ValueType::RefArray(type_idx)
        }
      Func(_) =>
        if is_nullable {
          @types.ValueType::RefNullFuncTyped(type_idx)
        } else {
          @types.ValueType::RefFuncTyped(type_idx)
        }
    }
    // Type not yet defined, assume func type (may need forward reference handling)
  } else if is_nullable {
    @types.ValueType::RefNullFuncTyped(type_idx)
  } else {
    @types.ValueType::RefFuncTyped(type_idx)
  }
}

///|
/// Parse a reference type for ref.null instruction
fn Parser::parse_ref_type(self : Parser) -> @types.ValueType raise WatError {
  match self.current.token {
    LParen => {
      // Handle (ref ...) syntax
      self.advance()
      self.expect_keyword("ref")
      // Check for nullable: (ref null ...) vs non-null: (ref ...)
      let is_nullable = self.current.token == Keyword("null")
      if is_nullable {
        self.advance()
      }
      // Parse the heap type
      let result = match self.current.token {
        Keyword("func") => {
          self.advance()
          if is_nullable {
            @types.ValueType::FuncRef
          } else {
            @types.ValueType::RefFunc
          }
        }
        Keyword("extern") => {
          self.advance()
          if is_nullable {
            @types.ValueType::ExternRef
          } else {
            @types.ValueType::RefExtern
          }
        }
        Keyword("any") => {
          self.advance()
          if is_nullable {
            @types.ValueType::AnyRef
          } else {
            @types.ValueType::RefAny
          }
        }
        Keyword("eq") => {
          self.advance()
          if is_nullable {
            @types.ValueType::RefNullEq
          } else {
            @types.ValueType::RefEq
          }
        }
        Keyword("i31") => {
          self.advance()
          if is_nullable {
            @types.ValueType::RefNullI31
          } else {
            @types.ValueType::RefI31
          }
        }
        Keyword("struct") => {
          self.advance()
          if is_nullable {
            @types.ValueType::RefNullStruct(-1)
          } else {
            @types.ValueType::RefStruct(-1)
          }
        }
        Keyword("array") => {
          self.advance()
          if is_nullable {
            @types.ValueType::RefNullArray(-1)
          } else {
            @types.ValueType::RefArray(-1)
          }
        }
        Keyword("none") => {
          self.advance()
          @types.ValueType::RefNone // bottom type (always non-null when specified as ref none)
        }
        Id(name) =>
          match self.type_names.get(name) {
            Some(idx) => {
              self.advance()
              // Check what kind of type this is
              self.get_typed_ref(idx, is_nullable)
            }
            None =>
              raise WatError::UnexpectedToken(
                "unknown type \{name}",
                self.loc(),
              )
          }
        Number(s) => {
          let idx = parse_int(s)
          self.advance()
          // Check what kind of type this is
          self.get_typed_ref(idx, is_nullable)
        }
        _ => raise WatError::UnexpectedToken("expected heap type", self.loc())
      }
      self.expect_rparen()
      result
    }
    Keyword("func") | Keyword("funcref") => {
      self.advance()
      @types.ValueType::FuncRef
    }
    Keyword("extern") | Keyword("externref") => {
      self.advance()
      @types.ValueType::ExternRef
    }
    Keyword("any") | Keyword("anyref") => {
      self.advance()
      @types.ValueType::AnyRef
    }
    Keyword("exn") | Keyword("exnref") => {
      self.advance()
      @types.ValueType::ExnRef
    }
    Keyword("none") | Keyword("nullref") => {
      self.advance()
      @types.ValueType::NullRef
    }
    Keyword("nofunc") | Keyword("nullfuncref") => {
      self.advance()
      @types.ValueType::NullFuncRef
    }
    Keyword("noexn") | Keyword("nullexnref") => {
      self.advance()
      @types.ValueType::NullExnRef
    }
    Keyword("noextern") | Keyword("nullexternref") => {
      self.advance()
      @types.ValueType::NullExternRef
    }
    // GC heap types
    Keyword("i31") | Keyword("i31ref") => {
      self.advance()
      @types.ValueType::RefNullI31
    }
    Keyword("struct") | Keyword("structref") => {
      self.advance()
      @types.ValueType::RefNullStruct(-1)
    }
    Keyword("array") | Keyword("arrayref") => {
      self.advance()
      @types.ValueType::RefNullArray(-1)
    }
    Keyword("eq") | Keyword("eqref") => {
      self.advance()
      @types.ValueType::RefNullEq
    }
    Id(name) => {
      // Type index like $t - resolve to typed reference
      let type_idx = match self.type_names.get(name) {
        Some(idx) => idx
        None =>
          raise WatError::UnexpectedToken("unknown type $\{name}", self.loc())
      }
      self.advance()
      self.get_typed_ref(type_idx, true) // nullable heap type
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected reference type (func, extern, any, exn, none, nofunc, noexn, noextern, i31, struct, array, eq)",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_label_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.resolve_label(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None =>
          raise WatError::UndefinedIdentifier("label $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected label index", self.loc())
  }
}

// ============================================================================
// WAST (WebAssembly Test Script) Parsing
// ============================================================================

///|
/// WAST command types
pub enum WastCommand {
  Module(@types.Module, String?)
  ModuleDefinition(@types.Module, String?)
  ModuleInstance(String?, String) // (instance_name, definition_name)
  ModuleQuote(Array[String])
  ModuleBinaryFailed(String)
  AssertReturn(WastAction, Array[WastValue])
  AssertTrap(WastAction, String)
  AssertException(WastAction) // Exception should be thrown
  AssertModuleTrap(WastModuleSource, String)
  AssertExhaustion(WastAction, String)
  AssertInvalid(WastModuleSource, String)
  AssertMalformed(WastModuleSource, String)
  AssertUnlinkable(WastModuleSource, String)
  Register(String, String?)
  Action(WastAction)
} derive(Show)

///|
/// Module source for assert_invalid/malformed
pub enum WastModuleSource {
  Binary(Bytes)
  Quote(Array[String])
  Inline(@types.Module)
  FailedToParse(String)
} derive(Show)

///|
/// WAST action (invoke or get)
pub enum WastAction {
  Invoke(String?, String, Array[WastValue])
  Get(String?, String)
} derive(Show)

///|
/// WAST value (typed constant)
pub enum WastValue {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  V128(Bytes) // SIMD 128-bit vector (16 bytes)
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
  // SIMD lane patterns for NaN matching
  V128Pattern(Array[WastLaneValue]) // For lane-by-lane comparison with NaN patterns
  RefNull(String)
  RefExtern(Int)
  RefExternAny // (ref.extern) without number - matches any non-null externref
  RefHost(Int) // (ref.host <idx>) - host reference for testing
  RefFunc
  // GC reference types
  RefArray // (ref.array) - any array reference
  RefStruct // (ref.struct) - any struct reference
  RefEq // (ref.eq) - any eq reference
  RefI31 // (ref.i31) - any i31 reference
  RefAny // (ref.any) - any reference
  // Relaxed SIMD: multiple valid results
  Either(Array[WastValue]) // (either v1 v2 ...) - any of the alternatives is valid
} derive(Show)

///|
/// Lane value for V128 pattern matching
pub enum WastLaneValue {
  F32(Float)
  F64(Double)
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
} derive(Show)

///|
/// WAST script (collection of commands with line numbers)
pub struct WastScript {
  commands : Array[(WastCommand, Int)]
}
