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
  parser.parse_module()
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
fn Parser::parse_instructions(
  self : Parser,
) -> Array[@types.Instruction] raise WatError {
  let instrs : Array[@types.Instruction] = []
  while self.current.token != RParen && self.current.token != Eof {
    match self.current.token {
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
  match self.current.token {
    Keyword(kw) => {
      // Special handling for "block" in folded form
      if kw == "block" {
        self.advance() // skip "block"
        // Optional label name
        let label : String? = match self.current.token {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        self.push_label(label)
        let body = self.parse_instructions()
        self.pop_label()
        self.expect_rparen() // close block in folded form (no 'end' keyword)
        return [@types.Instruction::Block(bt, body)]
      }
      // Special handling for "loop" in folded form
      if kw == "loop" {
        self.advance() // skip "loop"
        // Optional label name
        let label : String? = match self.current.token {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        self.push_label(label)
        let body = self.parse_instructions()
        self.pop_label()
        self.expect_rparen() // close loop in folded form (no 'end' keyword)
        return [@types.Instruction::Loop(bt, body)]
      }
      // Special handling for "if" in folded form
      if kw == "if" {
        self.advance() // skip "if"
        // Optional label name
        let label : String? = match self.current.token {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        let result : Array[@types.Instruction] = []
        // In folded form, condition operands come first as nested S-expressions
        while self.current.token == LParen {
          // Peek ahead to see if this is (then ...) or (else ...)
          let saved = self.lexer.pos
          self.advance()
          match self.current.token {
            Keyword("then") | Keyword("else") => {
              // Restore and break to handle then/else
              self.lexer.pos = saved
              self.current = LocatedToken::synthetic(LParen)
              break
            }
            _ => {
              // Restore to parse as folded operand (condition)
              self.lexer.pos = saved
              self.current = LocatedToken::synthetic(LParen)
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
        self.push_label(label)
        if self.current.token == LParen {
          self.advance()
          match self.current.token {
            Keyword("then") => {
              self.advance()
              then_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ =>
              raise WatError::UnexpectedToken(
                "expected 'then' in folded if",
                self.loc(),
              )
          }
        }
        if self.current.token == LParen {
          let saved = self.lexer.pos
          self.advance()
          match self.current.token {
            Keyword("else") => {
              self.advance()
              else_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved
              self.current = LocatedToken::synthetic(LParen)
            }
          }
        }
        self.pop_label()
        self.expect_rparen() // close if
        result.push(@types.Instruction::If(bt, then_body, else_body))
        return result
      }
      // Special handling for "try_table" in folded form
      if kw == "try_table" {
        self.advance() // skip "try_table"
        // Optional label name
        let label : String? = match self.current.token {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        let handlers : Array[@types.CatchHandler] = []
        // Parse catch handlers until we hit an instruction or )
        while self.current.token == LParen {
          let saved_pos = self.lexer.pos
          self.advance() // skip (
          match self.current.token {
            Keyword("catch") => {
              self.advance() // skip "catch"
              let tag_idx = self.parse_tag_idx()
              let label_idx = self.parse_label_idx()
              handlers.push(@types.CatchHandler::Catch(tag_idx, label_idx))
              self.expect_rparen()
            }
            Keyword("catch_ref") => {
              self.advance() // skip "catch_ref"
              let tag_idx = self.parse_tag_idx()
              let label_idx = self.parse_label_idx()
              handlers.push(@types.CatchHandler::CatchRef(tag_idx, label_idx))
              self.expect_rparen()
            }
            Keyword("catch_all") => {
              self.advance() // skip "catch_all"
              let label_idx = self.parse_label_idx()
              handlers.push(@types.CatchHandler::CatchAll(label_idx))
              self.expect_rparen()
            }
            Keyword("catch_all_ref") => {
              self.advance() // skip "catch_all_ref"
              let label_idx = self.parse_label_idx()
              handlers.push(@types.CatchHandler::CatchAllRef(label_idx))
              self.expect_rparen()
            }
            _ => {
              // Not a catch handler, restore and break
              self.lexer.pos = saved_pos
              self.current = LocatedToken::synthetic(LParen)
              break
            }
          }
        }
        self.push_label(label)
        let body = self.parse_instructions()
        self.pop_label()
        self.expect_rparen() // close try_table in folded form (no 'end' keyword)
        return [@types.Instruction::TryTable(bt, handlers, body)]
      }
      let instr = self.parse_plain_instruction(kw)
      // For control instructions, we've already handled them
      // For other instructions, parse folded operands
      match instr {
        Block(_, _) | Loop(_, _) | If(_, _, _) | TryTable(_, _, _) => [instr]
        _ => {
          // Parse nested folded instructions (operands)
          let result : Array[@types.Instruction] = []
          while self.current.token == LParen {
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
    _ => raise WatError::UnexpectedToken("expected instruction", self.loc())
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
      // Optional label name
      let label : String? = match self.current.token {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      self.push_label(label)
      let body = self.parse_instructions()
      self.pop_label()
      self.expect_keyword("end")
      // Skip optional label after 'end' (e.g., "end $label")
      self.skip_optional_id()
      @types.Instruction::Block(bt, body)
    }
    "loop" => {
      // Optional label name
      let label : String? = match self.current.token {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      self.push_label(label)
      let body = self.parse_instructions()
      self.pop_label()
      self.expect_keyword("end")
      // Skip optional label after 'end' (e.g., "end $label")
      self.skip_optional_id()
      @types.Instruction::Loop(bt, body)
    }
    "if" => {
      // Optional label name
      let label : String? = match self.current.token {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      // Flat form: if (result type) ... else ... end
      self.push_label(label)
      let then_body = self.parse_instructions()
      let else_body : Array[@types.Instruction] = if self.current.token ==
        Keyword("else") {
        self.advance()
        // Skip optional label after 'else' (e.g., "else $label")
        self.skip_optional_id()
        self.parse_instructions()
      } else {
        []
      }
      self.pop_label()
      self.expect_keyword("end")
      // Skip optional label after 'end' (e.g., "end $label")
      self.skip_optional_id()
      @types.Instruction::If(bt, then_body, else_body)
    }
    "br" => @types.Instruction::Br(self.parse_label_idx())
    "br_if" => @types.Instruction::BrIf(self.parse_label_idx())
    "br_table" => {
      let labels : Array[Int] = []
      while self.current.token != RParen && self.current.token != Eof {
        match self.current.token {
          Number(_) | Id(_) => labels.push(self.parse_label_idx())
          _ => break
        }
      }
      if labels.length() == 0 {
        raise WatError::ParseError(
          "br_table requires at least one label",
          self.loc(),
        )
      }
      let default_label = labels.pop().unwrap()
      @types.Instruction::BrTable(labels, default_label)
    }
    "return" => @types.Instruction::Return
    // Exception handling instructions
    "throw" => @types.Instruction::Throw(self.parse_tag_idx())
    "throw_ref" => @types.Instruction::ThrowRef
    "try_table" => {
      // try_table has a block type followed by catch handlers and a body
      // (try_table (result i32) (catch $tag $label) ... instructions end)
      let bt = self.parse_block_type()
      let handlers : Array[@types.CatchHandler] = []
      // Parse catch handlers until we hit an instruction or end
      while self.current.token == LParen {
        let saved_pos = self.lexer.pos
        self.advance() // skip (
        match self.current.token {
          Keyword("catch") => {
            self.advance() // skip "catch"
            let tag_idx = self.parse_tag_idx()
            let label_idx = self.parse_label_idx()
            handlers.push(@types.CatchHandler::Catch(tag_idx, label_idx))
            self.expect_rparen()
          }
          Keyword("catch_ref") => {
            self.advance() // skip "catch_ref"
            let tag_idx = self.parse_tag_idx()
            let label_idx = self.parse_label_idx()
            handlers.push(@types.CatchHandler::CatchRef(tag_idx, label_idx))
            self.expect_rparen()
          }
          Keyword("catch_all") => {
            self.advance() // skip "catch_all"
            let label_idx = self.parse_label_idx()
            handlers.push(@types.CatchHandler::CatchAll(label_idx))
            self.expect_rparen()
          }
          Keyword("catch_all_ref") => {
            self.advance() // skip "catch_all_ref"
            let label_idx = self.parse_label_idx()
            handlers.push(@types.CatchHandler::CatchAllRef(label_idx))
            self.expect_rparen()
          }
          _ => {
            // Not a catch handler, restore and break
            self.lexer.pos = saved_pos
            self.current = LocatedToken::synthetic(LParen)
            break
          }
        }
      }
      let body = self.parse_instructions()
      self.expect_keyword("end")
      self.skip_optional_id()
      @types.Instruction::TryTable(bt, handlers, body)
    }
    "call" => @types.Instruction::Call(self.parse_func_idx())
    "call_ref" => {
      // call_ref $type - calls a function reference with the given type
      let type_idx = self.parse_type_idx()
      @types.Instruction::CallRef(type_idx)
    }
    "call_indirect" => {
      // call_indirect can have various forms:
      // (call_indirect $table (type $t) ...)
      // (call_indirect (type $t) ...)
      // (call_indirect (param ...) (result ...) ...)
      // (call_indirect ...)  - empty type
      let mut table_idx = 0
      let mut type_idx : Int? = None
      let inline_params : Array[@types.ValueType] = []
      let inline_results : Array[@types.ValueType] = []

      // Check for optional table index/name before the type
      match self.current.token {
        Id(name) =>
          match self.table_names.get(name) {
            Some(idx) => {
              table_idx = idx
              self.advance()
            }
            None => () // Not a table name, might be something else
          }
        Number(_) => table_idx = self.parse_u32()
        _ => ()
      }

      // Parse optional type/param/result annotations
      while self.current.token == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current.token {
          Keyword("type") => {
            self.advance()
            let idx = self.parse_type_idx()
            // Validate type index is in range (0xffffffff becomes -1 after parsing)
            if idx < 0 || idx >= self.types.length() {
              raise WatError::ParseError("unknown type", self.loc())
            }
            type_idx = Some(idx)
            self.expect_rparen()
          }
          Keyword("param") => {
            // Parse inline param types
            self.advance()
            // Skip optional name
            if self.current.token is Id(_) {
              self.advance()
            }
            while self.current.token != RParen {
              inline_params.push(self.parse_value_type())
            }
            self.expect_rparen()
          }
          Keyword("result") => {
            // Parse inline result types
            self.advance()
            while self.current.token != RParen {
              inline_results.push(self.parse_value_type())
            }
            self.expect_rparen()
          }
          _ => {
            // Not a type annotation, restore state (this is an operand)
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
      let final_type_idx = match type_idx {
        Some(idx) => idx
        None =>
          // No explicit (type $t), find or create type from inline annotations
          self.find_or_create_func_type(inline_params, inline_results)
      }
      @types.Instruction::CallIndirect(final_type_idx, table_idx)
    }
    "return_call" => @types.Instruction::ReturnCall(self.parse_func_idx())
    "return_call_ref" => {
      // return_call_ref $type - tail calls a function reference with the given type
      let type_idx = self.parse_type_idx()
      @types.Instruction::ReturnCallRef(type_idx)
    }
    "return_call_indirect" => {
      // return_call_indirect follows the same parsing as call_indirect
      let mut table_idx = 0
      let mut type_idx : Int? = None
      let inline_params : Array[@types.ValueType] = []
      let inline_results : Array[@types.ValueType] = []

      // Check for optional table index/name before the type
      match self.current.token {
        Id(name) =>
          match self.table_names.get(name) {
            Some(idx) => {
              table_idx = idx
              self.advance()
            }
            None => () // Not a table name, might be something else
          }
        Number(_) => table_idx = self.parse_u32()
        _ => ()
      }

      // Parse optional type/param/result annotations
      while self.current.token == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current.token {
          Keyword("type") => {
            self.advance()
            let idx = self.parse_type_idx()
            // Validate type index is in range (0xffffffff becomes -1 after parsing)
            if idx < 0 || idx >= self.types.length() {
              raise WatError::ParseError("unknown type", self.loc())
            }
            type_idx = Some(idx)
            self.expect_rparen()
          }
          Keyword("param") => {
            self.advance() // skip "param"
            // Parse parameter types until we hit ')'
            while self.current.token != RParen {
              inline_params.push(self.parse_value_type())
            }
            self.expect_rparen()
          }
          Keyword("result") => {
            self.advance() // skip "result"
            // Parse result types until we hit ')'
            while self.current.token != RParen {
              inline_results.push(self.parse_value_type())
            }
            self.expect_rparen()
          }
          _ => {
            // Not a type annotation, restore state (this is an operand)
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
      let final_type_idx = match type_idx {
        Some(idx) => idx
        None =>
          // No explicit (type $t), find or create type from inline annotations
          self.find_or_create_func_type(inline_params, inline_results)
      }
      @types.Instruction::ReturnCallIndirect(final_type_idx, table_idx)
    }

    // Parametric
    "drop" => @types.Instruction::Drop
    "select" => {
      // select can have optional (result type) annotations
      let result_types : Array[@types.ValueType] = []
      while self.current.token == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current.token {
          Keyword("result") => {
            self.advance() // skip "result"
            // Parse result types until we hit ')'
            while self.current.token != RParen {
              result_types.push(self.parse_value_type())
            }
            self.expect_rparen()
          }
          _ => {
            // Not a type annotation, restore state
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
      if result_types.is_empty() {
        @types.Instruction::Select
      } else {
        @types.Instruction::SelectTyped(result_types)
      }
    }

    // Reference types
    "ref.null" => {
      // Parse reference type (func or extern)
      let ref_type = self.parse_ref_type()
      @types.Instruction::RefNull(ref_type)
    }
    "ref.is_null" => @types.Instruction::RefIsNull
    "ref.func" => @types.Instruction::RefFunc(self.parse_func_idx())
    "ref.as_non_null" => @types.Instruction::RefAsNonNull
    "ref.eq" => @types.Instruction::RefEqInstr
    "br_on_null" => @types.Instruction::BrOnNull(self.parse_label_idx())
    "br_on_non_null" => @types.Instruction::BrOnNonNull(self.parse_label_idx())
    "br_on_cast" => {
      let label_idx = self.parse_label_idx()
      let from_type = self.parse_ref_type()
      let to_type = self.parse_ref_type()
      @types.Instruction::BrOnCast(label_idx, from_type, to_type)
    }
    "br_on_cast_fail" => {
      let label_idx = self.parse_label_idx()
      let from_type = self.parse_ref_type()
      let to_type = self.parse_ref_type()
      @types.Instruction::BrOnCastFail(label_idx, from_type, to_type)
    }

    // Variable
    "local.get" => @types.Instruction::LocalGet(self.parse_local_idx())
    "local.set" => @types.Instruction::LocalSet(self.parse_local_idx())
    "local.tee" => @types.Instruction::LocalTee(self.parse_local_idx())
    "global.get" => @types.Instruction::GlobalGet(self.parse_global_idx())
    "global.set" => @types.Instruction::GlobalSet(self.parse_global_idx())

    // Table instructions
    "table.get" => @types.Instruction::TableGet(self.parse_table_idx())
    "table.set" => @types.Instruction::TableSet(self.parse_table_idx())
    "table.size" => @types.Instruction::TableSize(self.parse_table_idx())
    "table.grow" => @types.Instruction::TableGrow(self.parse_table_idx())
    "table.fill" => @types.Instruction::TableFill(self.parse_table_idx())
    "table.copy" => {
      let dest = self.parse_table_idx()
      let src = self.parse_table_idx()
      @types.Instruction::TableCopy(dest, src)
    }
    "table.init" => {
      // table.init can have forms: (table.init $elem) or (table.init $table $elem)
      let first = match self.current.token {
        Number(s) => {
          self.advance()
          parse_int(s)
        }
        Id(name) =>
          // Could be table name or elem name - try table first
          match self.table_names.get(name) {
            Some(idx) => {
              self.advance()
              idx
            }
            None =>
              // Not a table name, try elem name
              match self.elem_names.get(name) {
                Some(idx) => {
                  self.advance()
                  idx
                }
                None =>
                  raise WatError::UndefinedIdentifier(
                    "table or elem $\{name}",
                    self.loc(),
                  )
              }
          }
        _ => 0
      }
      match self.current.token {
        Number(_) | Id(_) => {
          // Two arguments: first was table index, second is elem index
          let elem_idx = match self.current.token {
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
                None =>
                  raise WatError::UndefinedIdentifier(
                    "elem $\{name}",
                    self.loc(),
                  )
              }
            _ => 0
          }
          @types.Instruction::TableInit(first, elem_idx)
        }
        _ =>
          // One argument: first was elem index, table defaults to 0
          @types.Instruction::TableInit(0, first)
      }
    }

    // Memory
    "i32.load" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I32Load(m, a, o) })
    "i64.load" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I64Load(m, a, o) })
    "f32.load" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::F32Load(m, a, o) })
    "f64.load" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::F64Load(m, a, o) })
    "i32.load8_s" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I32Load8S(m, a, o) })
    "i32.load8_u" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I32Load8U(m, a, o) })
    "i32.load16_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I32Load16S(m, a, o)
      })
    "i32.load16_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I32Load16U(m, a, o)
      })
    "i64.load8_s" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I64Load8S(m, a, o) })
    "i64.load8_u" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I64Load8U(m, a, o) })
    "i64.load16_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Load16S(m, a, o)
      })
    "i64.load16_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Load16U(m, a, o)
      })
    "i64.load32_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Load32S(m, a, o)
      })
    "i64.load32_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Load32U(m, a, o)
      })
    "i32.store" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I32Store(m, a, o) })
    "i64.store" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I64Store(m, a, o) })
    "f32.store" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::F32Store(m, a, o) })
    "f64.store" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::F64Store(m, a, o) })
    "i32.store8" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I32Store8(m, a, o) })
    "i32.store16" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I32Store16(m, a, o)
      })
    "i64.store8" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::I64Store8(m, a, o) })
    "i64.store16" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Store16(m, a, o)
      })
    "i64.store32" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::I64Store32(m, a, o)
      })
    "memory.size" =>
      @types.Instruction::MemorySize(self.parse_optional_memidx())
    "memory.grow" =>
      @types.Instruction::MemoryGrow(self.parse_optional_memidx())
    "memory.init" => {
      let memidx = self.parse_optional_memidx()
      let dataidx = self.parse_data_idx()
      @types.Instruction::MemoryInit(memidx, dataidx)
    }
    "memory.copy" => {
      let dst = self.parse_optional_memidx()
      let src = self.parse_optional_memidx()
      @types.Instruction::MemoryCopy(dst, src)
    }
    "memory.fill" =>
      @types.Instruction::MemoryFill(self.parse_optional_memidx())
    "data.drop" => @types.Instruction::DataDrop(self.parse_data_idx())
    "elem.drop" => @types.Instruction::ElemDrop(self.parse_elem_idx())

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
    // Sign-extension operators
    "i32.extend8_s" => @types.Instruction::I32Extend8S
    "i32.extend16_s" => @types.Instruction::I32Extend16S

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
    // Sign-extension operators
    "i64.extend8_s" => @types.Instruction::I64Extend8S
    "i64.extend16_s" => @types.Instruction::I64Extend16S
    "i64.extend32_s" => @types.Instruction::I64Extend32S

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

    // Saturating truncation instructions (nontrapping float-to-int)
    "i32.trunc_sat_f32_s" => @types.Instruction::I32TruncSatF32S
    "i32.trunc_sat_f32_u" => @types.Instruction::I32TruncSatF32U
    "i32.trunc_sat_f64_s" => @types.Instruction::I32TruncSatF64S
    "i32.trunc_sat_f64_u" => @types.Instruction::I32TruncSatF64U
    "i64.trunc_sat_f32_s" => @types.Instruction::I64TruncSatF32S
    "i64.trunc_sat_f32_u" => @types.Instruction::I64TruncSatF32U
    "i64.trunc_sat_f64_s" => @types.Instruction::I64TruncSatF64S
    "i64.trunc_sat_f64_u" => @types.Instruction::I64TruncSatF64U

    // GC instructions - struct operations
    "struct.new" => @types.Instruction::StructNew(self.parse_type_idx())
    "struct.new_default" =>
      @types.Instruction::StructNewDefault(self.parse_type_idx())
    "struct.get" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      @types.Instruction::StructGet(type_idx, field_idx)
    }
    "struct.get_s" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      @types.Instruction::StructGetS(type_idx, field_idx)
    }
    "struct.get_u" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      @types.Instruction::StructGetU(type_idx, field_idx)
    }
    "struct.set" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      @types.Instruction::StructSet(type_idx, field_idx)
    }

    // GC instructions - array operations
    "array.new" => @types.Instruction::ArrayNew(self.parse_type_idx())
    "array.new_default" =>
      @types.Instruction::ArrayNewDefault(self.parse_type_idx())
    "array.new_fixed" => {
      let type_idx = self.parse_type_idx()
      let len = self.parse_u32()
      @types.Instruction::ArrayNewFixed(type_idx, len)
    }
    "array.get" => @types.Instruction::ArrayGet(self.parse_type_idx())
    "array.get_s" => @types.Instruction::ArrayGetS(self.parse_type_idx())
    "array.get_u" => @types.Instruction::ArrayGetU(self.parse_type_idx())
    "array.set" => @types.Instruction::ArraySet(self.parse_type_idx())
    "array.len" => @types.Instruction::ArrayLen
    "array.fill" => @types.Instruction::ArrayFill(self.parse_type_idx())
    "array.copy" => {
      let dst_type_idx = self.parse_type_idx()
      let src_type_idx = self.parse_type_idx()
      @types.Instruction::ArrayCopy(dst_type_idx, src_type_idx)
    }
    "array.new_data" => {
      let type_idx = self.parse_type_idx()
      let data_idx = self.parse_data_idx()
      @types.Instruction::ArrayNewData(type_idx, data_idx)
    }
    "array.new_elem" => {
      let type_idx = self.parse_type_idx()
      let elem_idx = self.parse_elem_idx()
      @types.Instruction::ArrayNewElem(type_idx, elem_idx)
    }
    "array.init_data" => {
      let type_idx = self.parse_type_idx()
      let data_idx = self.parse_data_idx()
      @types.Instruction::ArrayInitData(type_idx, data_idx)
    }
    "array.init_elem" => {
      let type_idx = self.parse_type_idx()
      let elem_idx = self.parse_elem_idx()
      @types.Instruction::ArrayInitElem(type_idx, elem_idx)
    }

    // GC instructions - i31
    "ref.i31" => @types.Instruction::RefI31
    "i31.get_s" => @types.Instruction::I31GetS
    "i31.get_u" => @types.Instruction::I31GetU

    // GC instructions - type conversion
    "any.convert_extern" => @types.Instruction::AnyConvertExtern
    "extern.convert_any" => @types.Instruction::ExternConvertAny

    // GC instructions - type testing and casting
    "ref.test" => {
      // ref.test <heaptype> or ref.test (ref <heaptype>)
      // Uses RefTestNull if the type is nullable, otherwise RefTest
      let vt = self.parse_value_type()
      if vt.is_nullable() {
        @types.Instruction::RefTestNull(vt)
      } else {
        @types.Instruction::RefTest(vt)
      }
    }
    "ref.cast" => {
      // ref.cast <heaptype> or ref.cast (ref <heaptype>)
      // Uses RefCastNull if the type is nullable, otherwise RefCast
      let vt = self.parse_value_type()
      if vt.is_nullable() {
        @types.Instruction::RefCastNull(vt)
      } else {
        @types.Instruction::RefCast(vt)
      }
    }
    _ => raise WatError::InvalidInstruction(kw, self.loc())
  }
}

///|
fn parse_mem_arg(
  parser : Parser,
  instr : (Int, Int, Int) -> @types.Instruction,
) -> @types.Instruction raise WatError {
  let mut memidx = 0
  let mut offset = 0
  let mut align = 0
  // Multi-memory: Parse optional memory index (e.g., $mem1 or 0)
  match parser.current.token {
    Id(name) => {
      // Memory name like $mem1 - resolve to index
      memidx = parser.resolve_memory(name)
      parser.advance()
    }
    Number(s) =>
      // Could be memory index or offset without = prefix
      // Check if it looks like a plain number (no = prefix) and next token is offset= or align=
      if !s.has_prefix("offset=") && !s.has_prefix("align=") {
        // Check if there's a following offset= or align= keyword
        // If so, this is a memory index; otherwise it's not a memory argument
        let saved_pos = parser.lexer.pos
        let saved_line = parser.lexer.line
        let saved_column = parser.lexer.column
        let saved_token = parser.current
        parser.advance()
        let is_memidx = match parser.current.token {
          Keyword(k) => k.has_prefix("offset=") || k.has_prefix("align=")
          RParen => true // Could be memory index followed by closing paren
          _ => false
        }
        if is_memidx {
          memidx = parse_int(s)
        } else {
          // Restore position - this wasn't a memory index
          parser.lexer.pos = saved_pos
          parser.lexer.line = saved_line
          parser.lexer.column = saved_column
          parser.current = saved_token
        }
      }
    _ => ()
  }
  // Parse optional offset=N and align=N
  while true {
    match parser.current.token {
      Keyword(s) =>
        if s.has_prefix("offset=") {
          let offset_str = StringBuilder::new()
          for i in 7..<s.length() {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          // Use parse_u32 for offset (can be up to 0xFFFFFFFF)
          offset = parse_u32(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::new()
          for i in 6..<s.length() {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_u32(align_str.to_string())
          // Convert alignment to log2
          align = log2(a)
          parser.advance()
        } else {
          break
        }
      _ => break
    }
  }
  instr(memidx, align, offset)
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
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = []
  let mut type_idx : Int? = None

  // Parse optional (type $idx) and/or (param ...) (result ...)
  while self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
      Keyword("type") => {
        // (type $idx) - explicit type reference
        self.advance()
        type_idx = Some(self.parse_type_idx())
        self.expect_rparen()
        // Continue to parse any inline param/result annotations (they are optional redundant info)
      }
      Keyword("param") => {
        self.advance()
        // Skip optional name
        if self.current.token is Id(_) {
          self.advance()
        }
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
        // Not a block type annotation, restore state
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

  // Determine the block type variant
  // If we have explicit type index, use it (param/result are just annotations)
  if type_idx is Some(idx) {
    return @types.BlockType::TypeIndex(idx)
  }
  if params.length() > 0 {
    // Has parameters - use InlineType
    @types.BlockType::InlineType(params, results)
  } else if results.length() == 0 {
    @types.BlockType::Empty
  } else if results.length() == 1 {
    @types.BlockType::Value(results[0])
  } else {
    @types.BlockType::MultiValue(results)
  }
}

///|
/// Find an existing function type that matches the given params/results,
/// or create a new one if not found.
fn Parser::find_or_create_func_type(
  self : Parser,
  params : Array[@types.ValueType],
  results : Array[@types.ValueType],
) -> Int {
  // Search existing types for a match
  for i, subtype in self.types {
    // Only match against function types
    match subtype.composite {
      Func(ft) =>
        if ft.params.length() == params.length() &&
          ft.results.length() == results.length() {
          let mut match_ = true
          for j in 0..<params.length() {
            if params[j] != ft.params[j] {
              match_ = false
              break
            }
          }
          if match_ {
            for j in 0..<results.length() {
              if results[j] != ft.results[j] {
                match_ = false
                break
              }
            }
          }
          // Implicit types should only match singleton rec groups
          if match_ && is_singleton_rec_group(self.type_rec_groups, i) {
            return i
          }
        }
      _ => ()
    }
  }
  // No match found, create a new type
  let new_type = @types.FuncType::{ params, results }
  let idx = self.types.length()
  self.types.push(@types.SubType::from_func(new_type))
  // Implicit type is its own rec group
  self.type_rec_groups.push(idx)
  idx
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
    Id(_) => {
      // Type index like $t - treat as FuncRef for now
      self.advance()
      @types.ValueType::FuncRef
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

///|
fn Parser::parse_memory_def(self : Parser) -> MemoryDefResult raise WatError {
  self.advance() // skip "memory"
  let export_names : Array[String] = []

  // Optional name
  if self.current.token is Id(name) {
    self.memory_names.set(name, 0)
    self.advance()
  }

  // Check for inline import: (memory (import "mod" "name") MIN [MAX])
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
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

        // Check for inline exports after import (can have multiple)
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

        // Parse limits
        let min = self.parse_u32()
        let max = match self.current.token {
          Number(_) => Some(self.parse_u32())
          _ => None
        }
        self.expect_rparen() // close memory
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Memory({ limits: { min, max } }),
        }
        return MemoryDefResult::MemoryImport(imp, export_names)
      }
      Keyword("export") => {
        export_names.push(
          match self.current.token {
            _ => {
              self.advance()
              match self.current.token {
                String_(s) => {
                  self.advance()
                  s
                }
                _ =>
                  raise WatError::UnexpectedToken(
                    "expected export name",
                    self.loc(),
                  )
              }
            }
          },
        )
        self.expect_rparen()
        // Check for more exports or import
        while self.current.token == LParen {
          let saved2 = self.lexer.pos
          let saved2_line = self.lexer.line
          let saved2_column = self.lexer.column
          let saved2_token_start_line = self.lexer.token_start_line
          let saved2_token_start_column = self.lexer.token_start_column
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
            Keyword("import") => {
              // Handle (memory (export ...) (import "mod" "name") limits) syntax
              self.advance()
              let mod_name = match self.current.token {
                String_(s) => {
                  self.advance()
                  s
                }
                _ =>
                  raise WatError::UnexpectedToken(
                    "expected module name",
                    self.loc(),
                  )
              }
              let import_name = match self.current.token {
                String_(s) => {
                  self.advance()
                  s
                }
                _ =>
                  raise WatError::UnexpectedToken(
                    "expected import name",
                    self.loc(),
                  )
              }
              self.expect_rparen() // close import
              // Parse limits
              let min = self.parse_u32()
              let max = match self.current.token {
                Number(_) => Some(self.parse_u32())
                _ => None
              }
              self.expect_rparen() // close memory
              let imp : @types.Import = {
                mod_name,
                name: import_name,
                desc: @types.ImportDesc::Memory({ limits: { min, max } }),
              }
              return MemoryDefResult::MemoryImport(imp, export_names)
            }
            _ => {
              self.lexer.pos = saved2
              self.lexer.line = saved2_line
              self.lexer.column = saved2_column
              self.lexer.token_start_line = saved2_token_start_line
              self.lexer.token_start_column = saved2_token_start_column
              self.current = LocatedToken::synthetic(LParen)
              break
            }
          }
        }
      }
      Keyword("data") => {
        // Inline data syntax: (memory (data "..."))
        // The memory size is automatically calculated from the data size
        self.advance() // skip "data"
        let init_bytes : Array[Byte] = []
        while self.current.token is String_(_) {
          if self.current.token is String_(s) {
            for i in 0..<s.length() {
              init_bytes.push(s.code_unit_at(i).to_byte())
            }
            self.advance()
          }
        }
        self.expect_rparen() // close data
        self.expect_rparen() // close memory
        // Calculate minimum pages needed (64KB per page)
        let page_size = 65536
        let data_len = init_bytes.length()
        let min_pages = (data_len + page_size - 1) / page_size
        // Ensure at least 1 page if there's any data
        let min = if data_len > 0 && min_pages == 0 { 1 } else { min_pages }
        return MemoryDefResult::MemoryWithData(
          { limits: { min, max: Some(min) } },
          export_names,
          Bytes::from_array(init_bytes),
        )
      }
      _ => {
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LocatedToken::synthetic(LParen)
      }
    }
  }

  // Parse limits
  let min = self.parse_u32()
  let max = match self.current.token {
    Number(_) => Some(self.parse_u32())
    _ => None
  }
  self.expect_rparen()
  MemoryDefResult::MemoryDef({ limits: { min, max } }, export_names)
}

///|
fn Parser::parse_global_def(self : Parser) -> GlobalDefResult raise WatError {
  self.advance() // skip "global"
  let export_names : Array[String] = []

  // Optional name - skip it (already registered in first pass)
  if self.current.token is Id(_) {
    self.advance()
  }

  // Check for inline import: (global $x (import "mod" "name") i32)
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
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

        // Check for inline exports after import (can have multiple)
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

        // Parse global type (mut i32) or i32 or (ref ...)
        let (value_type, mutable) = if self.current.token == LParen {
          let saved3 = self.lexer.pos
          let saved3_line = self.lexer.line
          let saved3_column = self.lexer.column
          let saved3_token_start_line = self.lexer.token_start_line
          let saved3_token_start_column = self.lexer.token_start_column
          self.advance()
          if self.current.token == Keyword("mut") {
            self.advance()
            let vt = self.parse_value_type()
            self.expect_rparen()
            (vt, true)
          } else {
            // Not (mut ...), restore and parse as ref type
            self.lexer.pos = saved3
            self.lexer.line = saved3_line
            self.lexer.column = saved3_column
            self.lexer.token_start_line = saved3_token_start_line
            self.lexer.token_start_column = saved3_token_start_column
            self.current = LocatedToken::synthetic(LParen)
            (self.parse_value_type(), false)
          }
        } else {
          (self.parse_value_type(), false)
        }
        self.expect_rparen() // close global

        // Note: global name is already registered in first pass, no need to set again
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Global({ value_type, mutable }),
        }
        return GlobalDefResult::GlobalImport(imp, export_names)
      }
      _ => {
        // Not an inline import, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LocatedToken::synthetic(LParen)
      }
    }
  }

  // Note: global name is already registered in first pass, no need to set again

  // Check for inline exports and imports (can have multiple exports, at most one import)
  // Exports can come before or after import
  while self.current.token == LParen {
    let saved = self.lexer.pos
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
        // Inline import after exports
        self.advance()
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

        // Continue checking for more exports after import
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

        // Parse global type
        let (value_type, mutable) = if self.current.token == LParen {
          let saved3 = self.lexer.pos
          let saved3_line = self.lexer.line
          let saved3_column = self.lexer.column
          let saved3_token_start_line = self.lexer.token_start_line
          let saved3_token_start_column = self.lexer.token_start_column
          self.advance()
          if self.current.token == Keyword("mut") {
            self.advance()
            let vt = self.parse_value_type()
            self.expect_rparen()
            (vt, true)
          } else {
            self.lexer.pos = saved3
            self.lexer.line = saved3_line
            self.lexer.column = saved3_column
            self.lexer.token_start_line = saved3_token_start_line
            self.lexer.token_start_column = saved3_token_start_column
            self.current = LocatedToken::synthetic(LParen)
            (self.parse_value_type(), false)
          }
        } else {
          (self.parse_value_type(), false)
        }
        self.expect_rparen() // close global
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Global({ value_type, mutable }),
        }
        return GlobalDefResult::GlobalImport(imp, export_names)
      }
      _ => {
        self.lexer.pos = saved
        self.current = LocatedToken::synthetic(LParen)
        break
      }
    }
  }

  // Parse global type (mut i32) or i32 or (ref ...)
  let (value_type, mutable) = if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    if self.current.token == Keyword("mut") {
      self.advance()
      let vt = self.parse_value_type()
      self.expect_rparen()
      (vt, true)
    } else {
      // Not (mut ...), restore and parse as ref type
      self.lexer.pos = saved
      self.lexer.line = saved_line
      self.lexer.column = saved_column
      self.lexer.token_start_line = saved_token_start_line
      self.lexer.token_start_column = saved_token_start_column
      self.current = LocatedToken::synthetic(LParen)
      (self.parse_value_type(), false)
    }
  } else {
    (self.parse_value_type(), false)
  }

  // Parse init expression
  let init = self.parse_instructions()
  self.expect_rparen()
  GlobalDefResult::GlobalDef(
    { type_: { value_type, mutable }, init },
    export_names,
  )
}

///|
fn Parser::parse_table_def(
  self : Parser,
  mod_ : @types.Module,
) -> (@types.Table, String?, @types.Element?, String?) raise WatError {
  // Returns (table, export_name, inline_elem, table_name)
  self.advance() // skip "table"
  let mut export_name : String? = None
  let mut table_name : String? = None

  // Optional name
  if self.current.token is Id(name) {
    table_name = Some(name)
    // Don't set table_names here; caller will set with correct index
    self.advance()
  }

  // Check for inline export
  if self.current.token == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current.token {
      Keyword("export") => {
        self.advance()
        match self.current.token {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ =>
            raise WatError::UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LocatedToken::synthetic(LParen)
      }
    }
  }

  // Check for inline import: (table (import "mod" "name") MIN [MAX] elemtype)
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
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

        // Parse limits
        let min = self.parse_u32()
        let max = match self.current.token {
          Number(_) => Some(self.parse_u32())
          _ => None
        }
        // Parse element type
        let elem_type = self.parse_value_type()
        self.expect_rparen() // close table

        // Add the import to the module
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Table({ elem_type, limits: { min, max } }),
        }
        mod_.imports.push(imp)
        // Return a placeholder table (the import is what matters)
        return (
          { type_: { elem_type, limits: { min, max } }, init: None },
          export_name,
          None,
          table_name,
        )
      }
      _ => {
        // Not an inline import, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LocatedToken::synthetic(LParen)
      }
    }
  }

  // Check for inline elem syntax: (table elemtype (elem ...))
  // In this syntax, the element type comes first, followed by inline elem
  // Element type can be a keyword (funcref, externref, i31ref, etc.) or a reference type (ref null $t)
  match self.current.token {
    Keyword("funcref")
    | Keyword("func")
    | Keyword("externref")
    | Keyword("extern")
    | Keyword("i31ref")
    | Keyword("eqref")
    | Keyword("structref")
    | Keyword("arrayref")
    | Keyword("anyref")
    | LParen => {
      // Could be inline elem syntax or reference type followed by inline elem
      let elem_type = self.parse_value_type()
      // Check if followed by inline elem
      if self.current.token == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current.token {
          Keyword("elem") => {
            self.advance()
            // Parse element init expressions (can be indices or expressions)
            let init : Array[Array[@types.Instruction]] = []
            while self.current.token != RParen {
              match self.current.token {
                Id(name) =>
                  // Named function reference like $f
                  match self.func_names.get(name) {
                    Some(idx) => {
                      init.push([@types.Instruction::RefFunc(idx)])
                      self.advance()
                    }
                    None =>
                      // Function might be declared later, use placeholder
                      // For now, just skip - this is for assert_invalid tests
                      self.advance()
                  }
                Number(_) => {
                  let idx = self.parse_u32()
                  init.push([@types.Instruction::RefFunc(idx)])
                }
                LParen => {
                  // Expression like (ref.func $f) or (ref.null func)
                  self.advance()
                  match self.current.token {
                    Keyword("ref.func") => {
                      self.advance()
                      let idx = self.parse_func_idx()
                      self.expect_rparen()
                      init.push([@types.Instruction::RefFunc(idx)])
                    }
                    Keyword("ref.null") => {
                      self.advance()
                      let ref_type = self.parse_ref_type()
                      self.expect_rparen()
                      init.push([@types.Instruction::RefNull(ref_type)])
                    }
                    Keyword("item") => {
                      self.advance()
                      let expr = self.parse_instructions()
                      self.expect_rparen()
                      init.push(expr)
                    }
                    _ => {
                      // General expression
                      let expr = self.parse_instructions()
                      self.expect_rparen()
                      init.push(expr)
                    }
                  }
                }
                _ => break
              }
            }
            self.expect_rparen() // close elem
            self.expect_rparen() // close table
            let table_idx = mod_.tables.length()
            let elem : @types.Element = {
              mode: @types.ElemMode::Active(table_idx, [
                @types.Instruction::I32Const(0),
              ]),
              type_: elem_type,
              init,
            }
            let table : @types.Table = {
              type_: {
                elem_type,
                limits: { min: init.length(), max: Some(init.length()) },
              },
              init: None,
            }
            return (table, export_name, Some(elem), table_name)
          }
          _ => {
            // Not an inline elem, restore state and fall through to standard syntax
            // But we already parsed elem_type, so we need a different approach
            // This case shouldn't happen for valid WAT - (ref null $t) followed by something other than (elem ...)
            self.lexer.pos = saved
            self.lexer.line = saved_line
            self.lexer.column = saved_column
            self.lexer.token_start_line = saved_token_start_line
            self.lexer.token_start_column = saved_token_start_column
            self.current = LocatedToken::synthetic(LParen)
            raise WatError::UnexpectedToken(
              "expected elem in inline table",
              self.loc(),
            )
          }
        }
      } else {
        // Just element type followed by closing paren (no inline elem, no limits)
        self.expect_rparen()
        // This is a table with implicit size 0, no elements
        return (
          { type_: { elem_type, limits: { min: 0, max: None } }, init: None },
          export_name,
          None,
          table_name,
        )
      }
    }
    _ => {
      // Standard syntax: (table MIN [MAX] elemtype [init_expr])
      let min = self.parse_u32()
      let max = match self.current.token {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      let elem_type = self.parse_value_type()
      // Check for optional default init expression (ref.func $f) or (ref.null func) or (global.get $g)
      let table_init : Array[@types.Instruction]? = if self.current.token ==
        LParen {
        // Parse the init expression - validate global.get references
        // Table init expressions can only reference imported globals, not module-defined globals
        self.advance()
        match self.current.token {
          Keyword("ref.func") => {
            self.advance()
            let idx = self.parse_func_idx()
            self.expect_rparen()
            Some([@types.Instruction::RefFunc(idx)])
          }
          Keyword("ref.null") => {
            self.advance()
            let ref_type = self.parse_ref_type()
            self.expect_rparen()
            Some([@types.Instruction::RefNull(ref_type)])
          }
          Keyword("global.get") => {
            self.advance()
            // Parse and validate the global index
            let global_idx = self.parse_global_idx()
            // Check if this global is imported (only imported globals can be used in table init)
            let num_imported_globals = count_global_imports(mod_.imports)
            if global_idx >= num_imported_globals {
              raise WatError::UndefinedIdentifier(
                "unknown global (table init can only reference imported globals)",
                self.loc(),
              )
            }
            self.expect_rparen()
            Some([@types.Instruction::GlobalGet(global_idx)])
          }
          _ => {
            // General expression - parse it as a folded instruction
            // We already consumed the opening (, so parse_folded_instructions handles the rest
            let expr = self.parse_folded_instructions()
            Some(expr)
          }
        }
      } else {
        None
      }
      self.expect_rparen()
      (
        { type_: { elem_type, limits: { min, max } }, init: table_init },
        export_name,
        None,
        table_name,
      )
    }
  }
}

///|
fn Parser::parse_export_def(
  self : Parser,
  mod_ : @types.Module,
) -> @types.Export raise WatError {
  self.advance() // skip "export"
  let name = match self.current.token {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise WatError::UnexpectedToken("expected export name", self.loc())
  }
  self.expect_lparen()
  let desc = match self.current.token {
    Keyword("func") => {
      self.advance()
      let idx = self.parse_func_idx()
      @types.ExportDesc::Func(idx)
    }
    Keyword("memory") => {
      self.advance()
      let idx = match self.current.token {
        Number(_) => self.parse_u32()
        Id(name) =>
          match self.memory_names.get(name) {
            Some(idx) => {
              self.advance()
              idx
            }
            None =>
              raise WatError::UndefinedIdentifier("memory $\{name}", self.loc())
          }
        _ => 0
      }
      @types.ExportDesc::Memory(idx)
    }
    Keyword("table") => {
      self.advance()
      let idx = match self.current.token {
        Number(_) => self.parse_u32()
        Id(name) =>
          match self.table_names.get(name) {
            Some(idx) => {
              self.advance()
              idx
            }
            None =>
              raise WatError::UndefinedIdentifier("table $\{name}", self.loc())
          }
        _ => 0
      }
      @types.ExportDesc::Table(idx)
    }
    Keyword("global") => {
      self.advance()
      let idx = self.parse_global_idx()
      @types.ExportDesc::Global(idx)
    }
    Keyword("tag") => {
      self.advance()
      let idx = self.parse_tag_idx()
      @types.ExportDesc::Tag(idx)
    }
    _ => raise WatError::UnexpectedToken("expected export kind", self.loc())
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
  let mod_name = match self.current.token {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise WatError::UnexpectedToken("expected module name", self.loc())
  }
  let name = match self.current.token {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise WatError::UnexpectedToken("expected import name", self.loc())
  }
  self.expect_lparen()
  let desc = match self.current.token {
    Keyword("func") => {
      self.advance()
      // Optional func name - imported function index is count of function imports so far
      match self.current.token {
        Id(fname) => {
          self.func_names.set(fname, count_func_imports(mod_.imports))
          self.advance()
        }
        _ => ()
      }
      // Parse type - either (type $idx) or inline (param ...) (result ...)
      let type_idx = if self.current.token == LParen {
        let saved_pos = self.lexer.pos
        self.advance()
        if self.current.token == Keyword("type") {
          // (type $idx) syntax
          self.advance()
          let idx = self.parse_type_idx()
          self.expect_rparen()
          idx
        } else {
          // Inline signature - restore position and parse func type
          self.lexer.pos = saved_pos
          self.current = LocatedToken::synthetic(LParen)
          let func_type = self.parse_func_type()
          // Add this type to the module and get its index
          let idx = mod_.types.length()
          mod_.types.push(@types.SubType::from_func(func_type))
          // Implicit type is its own rec group
          mod_.type_rec_groups.push(idx)
          idx
        }
      } else {
        // No type specified, use empty signature
        let func_type : @types.FuncType = { params: [], results: [] }
        let idx = mod_.types.length()
        mod_.types.push(@types.SubType::from_func(func_type))
        // Implicit type is its own rec group
        mod_.type_rec_groups.push(idx)
        idx
      }
      @types.ImportDesc::Func(type_idx)
    }
    Keyword("memory") => {
      self.advance()
      // Optional memory name
      if self.current.token is Id(mname) {
        self.memory_names.set(mname, count_memory_imports(mod_.imports))
        self.advance()
      }
      let min = self.parse_u32()
      let max = match self.current.token {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      @types.ImportDesc::Memory({ limits: { min, max } })
    }
    Keyword("table") => {
      self.advance()
      // Optional table name
      if self.current.token is Id(tname) {
        // Register table name - table index is count of table imports so far
        self.table_names.set(tname, count_table_imports(mod_.imports))
        self.advance()
      }
      let min = self.parse_u32()
      let max = match self.current.token {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      let elem_type = self.parse_value_type()
      @types.ImportDesc::Table({ elem_type, limits: { min, max } })
    }
    Keyword("global") => {
      self.advance()
      // Optional global name
      if self.current.token is Id(gname) {
        self.global_names.set(gname, count_global_imports(mod_.imports))
        self.advance()
      }
      let (value_type, mutable) = if self.current.token == LParen {
        let saved_pos = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        if self.current.token == Keyword("mut") {
          self.advance()
          let vt = self.parse_value_type()
          self.expect_rparen()
          (vt, true)
        } else {
          // Not (mut ...), restore and parse as ref type
          self.lexer.pos = saved_pos
          self.lexer.line = saved_line
          self.lexer.column = saved_column
          self.lexer.token_start_line = saved_token_start_line
          self.lexer.token_start_column = saved_token_start_column
          self.current = LocatedToken::synthetic(LParen)
          (self.parse_value_type(), false)
        }
      } else {
        (self.parse_value_type(), false)
      }
      @types.ImportDesc::Global({ value_type, mutable })
    }
    Keyword("tag") => {
      self.advance()
      // Optional tag name
      if self.current.token is Id(tname) {
        self.tag_names.set(tname, count_tag_imports(mod_.imports))
        self.advance()
      }
      // Parse type - either (type $idx) or inline (param ...)
      let type_idx = if self.current.token == LParen {
        let saved_pos = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        if self.current.token == Keyword("type") {
          // (type $idx) syntax
          self.advance()
          let idx = self.parse_type_idx()
          self.expect_rparen()
          idx
        } else {
          // Inline signature - restore position and parse func type
          self.lexer.pos = saved_pos
          self.lexer.line = saved_line
          self.lexer.column = saved_column
          self.lexer.token_start_line = saved_token_start_line
          self.lexer.token_start_column = saved_token_start_column
          self.current = LocatedToken::synthetic(LParen)
          let func_type = self.parse_func_type()
          // Tags must have no results
          if func_type.results.length() > 0 {
            raise WatError::UnexpectedToken(
              "tags cannot have results",
              self.loc(),
            )
          }
          // Add this type to the module and get its index
          let idx = mod_.types.length()
          mod_.types.push(@types.SubType::from_func(func_type))
          // Implicit type is its own rec group
          mod_.type_rec_groups.push(idx)
          idx
        }
      } else {
        // No type specified, use empty signature
        let func_type : @types.FuncType = { params: [], results: [] }
        let idx = mod_.types.length()
        mod_.types.push(@types.SubType::from_func(func_type))
        // Implicit type is its own rec group
        mod_.type_rec_groups.push(idx)
        idx
      }
      @types.ImportDesc::Tag(type_idx)
    }
    _ => raise WatError::UnexpectedToken("expected import kind", self.loc())
  }
  self.expect_rparen()
  self.expect_rparen()
  { mod_name, name, desc }
}

///|
/// Parse a data segment definition
/// Supports various syntaxes:
/// - (data (i32.const <offset>) "<string>"...)  - active with offset
/// - (data (memory <idx>) (offset ...) "<string>"...)  - active with memory
/// - (data)  - passive, empty
/// - (data "<string>"...)  - passive with init
fn Parser::parse_data_def(
  self : Parser,
  data_idx? : Int = -1,
) -> @types.Data raise WatError {
  self.advance() // skip "data"

  // Check for optional data id
  if self.current.token is Id(name) {
    if data_idx >= 0 {
      self.data_names.set(name, data_idx)
    }
    self.advance()
  }

  // Default memory index is 0
  let mut memory_idx = 0
  let mut offset : Array[@types.Instruction] = []
  let mut is_passive = true

  // Check what comes next
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current.token {
      Keyword("memory") => {
        is_passive = false
        self.advance()
        memory_idx = match self.current.token {
          Number(_) => self.parse_u32()
          Id(name) =>
            match self.memory_names.get(name) {
              Some(idx) => {
                self.advance()
                idx
              }
              None => 0
            }
          _ => 0
        }
        self.expect_rparen()
        // Now expect offset - can be (offset ...) or direct (i32.const ...)
        self.expect_lparen()
        if self.current.token == Keyword("offset") {
          self.advance()
          offset = self.parse_instructions()
          self.expect_rparen()
        } else {
          // Direct offset expression like (i32.const 0)
          offset = self.parse_instructions()
          self.expect_rparen()
        }
      }
      Keyword("offset") => {
        is_passive = false
        self.advance()
        offset = self.parse_instructions()
        self.expect_rparen()
      }
      Keyword(_) => {
        // Any keyword instruction can be an offset expression (i32.const, i32.add, global.get, etc.)
        is_passive = false
        offset = self.parse_instructions()
        self.expect_rparen()
      }
      _ => {
        // Restore - this might be something else or passive data
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LocatedToken::synthetic(LParen)
      }
    }
  }

  // Parse string literals for init data (can have multiple or none)
  let init_bytes : Array[Byte] = []
  while self.current.token is String_(_) {
    if self.current.token is String_(s) {
      for i in 0..<s.length() {
        init_bytes.push(s.code_unit_at(i).to_byte())
      }
      self.advance()
    }
  }
  self.expect_rparen() // close data
  ignore(is_passive)
  { memory_idx, offset, init: Bytes::from_array(init_bytes) }
}

///|
/// Parse an element segment definition
/// Supports various syntaxes:
/// - Passive: (elem funcref ...) or (elem func $f $g)
/// - Active: (elem (table $t) (offset ...) ...) or (elem (i32.const 0) $f $g)
/// - Declarative: (elem declare func $f $g)
fn Parser::parse_elem_def(
  self : Parser,
  elem_idx? : Int = -1,
) -> @types.Element raise WatError {
  self.advance() // skip "elem"

  // Check for optional elem id
  if self.current.token is Id(name) {
    if elem_idx >= 0 {
      self.elem_names.set(name, elem_idx)
    }
    self.advance()
  }

  // Check for declarative element segment: (elem declare ...)
  if self.current.token == Keyword("declare") {
    self.advance() // skip "declare"
    return self.parse_elem_items_and_finish(@types.ElemMode::Declarative)
  }

  // Check what comes next to determine if this is passive or active
  // Passive: starts with reftype (funcref, externref, func, (ref ...), i31ref, etc.)
  // Active: starts with ( for table/offset/i32.const
  match self.current.token {
    Keyword("funcref")
    | Keyword("externref")
    | Keyword("func")
    | Keyword("extern")
    | Keyword("i31ref")
    | Keyword("eqref")
    | Keyword("structref")
    | Keyword("arrayref")
    | Keyword("anyref") =>
      // Passive element segment
      self.parse_elem_items_and_finish(@types.ElemMode::Passive)
    LParen => {
      // Could be active segment with (table ...), (offset ...), (i32.const ...), or (ref ...)
      let saved = self.lexer.pos
      let saved_line = self.lexer.line
      let saved_column = self.lexer.column
      let saved_token_start_line = self.lexer.token_start_line
      let saved_token_start_column = self.lexer.token_start_column
      self.advance()
      match self.current.token {
        Keyword("ref") => {
          // Passive segment with (ref null func) type
          self.lexer.pos = saved
          self.lexer.line = saved_line
          self.lexer.column = saved_column
          self.lexer.token_start_line = saved_token_start_line
          self.lexer.token_start_column = saved_token_start_column
          self.current = LocatedToken::synthetic(LParen)
          self.parse_elem_items_and_finish(@types.ElemMode::Passive)
        }
        Keyword("table") => {
          // Active with explicit table
          self.advance()
          let table_idx = match self.current.token {
            Number(_) => self.parse_u32()
            Id(name) =>
              match self.table_names.get(name) {
                Some(idx) => {
                  self.advance()
                  idx
                }
                None =>
                  raise WatError::UndefinedIdentifier(
                    "table $\{name}",
                    self.loc(),
                  )
              }
            _ => 0
          }
          self.expect_rparen()
          // Now expect offset expression
          self.expect_lparen()
          let offset = if self.current.token is Keyword("offset") {
            self.advance()
            let o = self.parse_instructions()
            self.expect_rparen()
            o
          } else {
            // Direct offset expression like (i32.const 0)
            let o = self.parse_instructions()
            self.expect_rparen()
            o
          }
          self.parse_elem_items_and_finish(
            @types.ElemMode::Active(table_idx, offset),
          )
        }
        Keyword("offset") => {
          // Active with explicit offset, implicit table 0
          self.advance()
          let offset = self.parse_instructions()
          self.expect_rparen()
          self.parse_elem_items_and_finish(@types.ElemMode::Active(0, offset))
        }
        _ => {
          // Active with direct offset expression like (i32.const 0), implicit table 0
          let offset = self.parse_instructions()
          self.expect_rparen()
          self.parse_elem_items_and_finish(@types.ElemMode::Active(0, offset))
        }
      }
    }
    // Empty passive segment
    RParen => {
      self.expect_rparen()
      {
        mode: @types.ElemMode::Passive,
        type_: @types.ValueType::FuncRef,
        init: [],
      }
    }
    _ =>
      raise WatError::UnexpectedToken(
        "expected elem segment content",
        self.loc(),
      )
  }
}

///|
/// Parse element items (type and init expressions) and finish the element segment
fn Parser::parse_elem_items_and_finish(
  self : Parser,
  mode : @types.ElemMode,
) -> @types.Element raise WatError {
  // Parse element type: funcref, externref, func, (ref ...)
  let (elem_type, use_func_indices) = self.parse_elem_type()

  // Parse init expressions
  let init : Array[Array[@types.Instruction]] = []
  if use_func_indices {
    // Parse function indices directly: $f $g or 0 1 2
    while self.current.token != RParen && self.current.token != Eof {
      match self.current.token {
        Number(_) | Id(_) => {
          let idx = self.parse_func_idx()
          init.push([@types.Instruction::RefFunc(idx)])
        }
        _ => break
      }
    }
  } else {
    // Parse init expressions: (ref.func $f), (ref.null func), (item ...), or general expressions
    while self.current.token == LParen {
      self.advance()
      match self.current.token {
        Keyword("item") => {
          // (item <expr>)
          self.advance()
          let expr = self.parse_instructions()
          self.expect_rparen()
          init.push(expr)
        }
        Keyword("ref.func") => {
          // (ref.func $f)
          self.advance()
          let idx = self.parse_func_idx()
          self.expect_rparen()
          init.push([@types.Instruction::RefFunc(idx)])
        }
        Keyword("ref.null") => {
          // (ref.null func)
          self.advance()
          let ref_type = self.parse_ref_type()
          self.expect_rparen()
          init.push([@types.Instruction::RefNull(ref_type)])
        }
        _ => {
          // General expression like (array.new $bvec ...)
          // We already consumed the opening (, so parse as folded instruction
          let expr = self.parse_folded_instructions()
          init.push(expr)
        }
      }
    }
  }
  self.expect_rparen() // close elem
  { mode, type_: elem_type, init }
}

///|
/// Parse element type and return (type, use_func_indices)
/// use_func_indices is true when using "func" abbreviation (indices instead of expressions)
fn Parser::parse_elem_type(
  self : Parser,
) -> (@types.ValueType, Bool) raise WatError {
  match self.current.token {
    Keyword("funcref") => {
      self.advance()
      (@types.ValueType::FuncRef, false)
    }
    Keyword("externref") => {
      self.advance()
      (@types.ValueType::ExternRef, false)
    }
    Keyword("func") => {
      self.advance()
      (@types.ValueType::FuncRef, true) // use indices
    }
    Keyword("extern") => {
      self.advance()
      (@types.ValueType::ExternRef, true) // use indices
    }
    // GC reference type shorthands
    Keyword("i31ref") => {
      self.advance()
      (@types.ValueType::RefNullI31, false)
    }
    Keyword("eqref") => {
      self.advance()
      (@types.ValueType::RefNullEq, false)
    }
    Keyword("structref") => {
      self.advance()
      (@types.ValueType::RefNullStruct(-1), false)
    }
    Keyword("arrayref") => {
      self.advance()
      (@types.ValueType::RefNullArray(-1), false)
    }
    Keyword("anyref") => {
      self.advance()
      (@types.ValueType::AnyRef, false)
    }
    LParen => {
      // (ref null func) or similar
      let vt = self.parse_value_type()
      (vt, false)
    }
    Id(_) | Number(_) =>
      // Legacy syntax: direct function indices without type keyword
      (@types.ValueType::FuncRef, true)
    _ =>
      // Default to funcref with expressions (empty elem)
      (@types.ValueType::FuncRef, false)
  }
}

///|
/// Parse a tag definition
/// Syntax:
/// - (tag (type $idx))
/// - (tag (param i32))
/// - (tag $name (type $idx))
/// - (tag (export "name") (type $idx))
/// - (tag (import "mod" "name") (param i32))
fn Parser::parse_tag_def(
  self : Parser,
  mod_ : @types.Module,
) -> TagDefResult raise WatError {
  self.advance() // skip "tag"
  let export_names : Array[String] = []

  // Optional tag name
  if self.current.token is Id(name) {
    self.tag_names.set(
      name,
      count_tag_imports(mod_.imports) + mod_.tags.length(),
    )
    self.advance()
  }

  // Check for inline export or import
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

        // Parse type after import
        let type_idx = self.parse_tag_type_spec(mod_)
        self.expect_rparen() // close tag
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Tag(type_idx),
        }
        return TagImport(imp, export_names)
      }
      _ => {
        // Not export/import, restore and continue to parse type
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

  // Parse type - either (type $idx) or inline (param ...)
  let type_idx = self.parse_tag_type_spec(mod_)
  self.expect_rparen() // close tag
  TagDef(@types.TagType::{ type_idx, }, export_names)
}

///|
/// Parse tag type specification - (type $idx) or (param ...)
fn Parser::parse_tag_type_spec(
  self : Parser,
  mod_ : @types.Module,
) -> Int raise WatError {
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    if self.current.token == Keyword("type") {
      // (type $idx) syntax
      self.advance()
      let idx = self.parse_type_idx()
      self.expect_rparen()
      idx
    } else {
      // Inline signature - restore position and parse func type
      self.lexer.pos = saved
      self.lexer.line = saved_line
      self.lexer.column = saved_column
      self.lexer.token_start_line = saved_token_start_line
      self.lexer.token_start_column = saved_token_start_column
      self.current = LocatedToken::synthetic(LParen)
      let func_type = self.parse_func_type()
      // Tags must have no results
      if func_type.results.length() > 0 {
        raise WatError::UnexpectedToken("tags cannot have results", self.loc())
      }
      // Add this type to the module and get its index
      let idx = mod_.types.length()
      mod_.types.push(@types.SubType::from_func(func_type))
      // Implicit type is its own rec group
      mod_.type_rec_groups.push(idx)
      idx
    }
  } else {
    // No type specified, use empty signature
    let func_type : @types.FuncType = { params: [], results: [] }
    let idx = mod_.types.length()
    mod_.types.push(@types.SubType::from_func(func_type))
    // Implicit type is its own rec group
    mod_.type_rec_groups.push(idx)
    idx
  }
}

///|
/// Parse a tag index (number or $name)
fn Parser::parse_tag_idx(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(_) => self.parse_u32()
    Id(name) =>
      match self.tag_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise WatError::UndefinedIdentifier("tag $\{name}", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected tag index", self.loc())
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
  F32CanonicalNan
  F32ArithmeticNan
  F64CanonicalNan
  F64ArithmeticNan
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
} derive(Show)

///|
/// WAST script (collection of commands with line numbers)
pub struct WastScript {
  commands : Array[(WastCommand, Int)]
}
