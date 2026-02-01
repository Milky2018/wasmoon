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
