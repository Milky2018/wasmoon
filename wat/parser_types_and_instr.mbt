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
