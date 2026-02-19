///|
fn Parser::parse_memory_def(self : Parser) -> MemoryDefResult raise WatError {
  self.advance() // skip "memory"
  let export_names : Array[String] = []

  // Optional name (already registered during first pass, just skip it)
  if self.current.token is Id(_) {
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

        // Check for i64 keyword (memory64)
        let is_memory64 = match self.current.token {
          Keyword("i64") => {
            self.advance()
            true
          }
          _ => false
        }

        // Parse limits (use u64 for memory64)
        let min = if is_memory64 {
          self.parse_u64()
        } else {
          self.parse_u32().to_int64()
        }
        let max = match self.current.token {
          Number(_) =>
            Some(
              if is_memory64 {
                self.parse_u64()
              } else {
                self.parse_u32().to_int64()
              },
            )
          _ => None
        }
        self.expect_rparen() // close memory
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Memory({
            limits: { min, max },
            is_memory64,
            page_size_log2: 16,
          }),
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
              // Check for i64 keyword (memory64)
              let is_memory64 = match self.current.token {
                Keyword("i64") => {
                  self.advance()
                  true
                }
                _ => false
              }
              // Parse limits (use u64 for memory64)
              let min = if is_memory64 {
                self.parse_u64()
              } else {
                self.parse_u32().to_int64()
              }
              let max = match self.current.token {
                Number(_) =>
                  Some(
                    if is_memory64 {
                      self.parse_u64()
                    } else {
                      self.parse_u32().to_int64()
                    },
                  )
                _ => None
              }
              self.expect_rparen() // close memory
              let imp : @types.Import = {
                mod_name,
                name: import_name,
                desc: @types.ImportDesc::Memory({
                  limits: { min, max },
                  is_memory64,
                  page_size_log2: 16,
                }),
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
        let min : Int64 = (if data_len > 0 && min_pages == 0 {
          1
        } else {
          min_pages
        }).to_int64()
        return MemoryDefResult::MemoryWithData(
          {
            limits: { min, max: Some(min) },
            is_memory64: false,
            page_size_log2: 16,
          },
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

  // Check for i64 keyword (memory64)
  let is_memory64 = match self.current.token {
    Keyword("i64") => {
      self.advance()
      true
    }
    _ => false
  }

  // Check for (data) inline syntax after i64 keyword
  if self.current.token == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    if self.current.token == Keyword("data") {
      // Inline data syntax: (memory [i64] (data "..."))
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
      let min : Int64 = (if data_len > 0 && min_pages == 0 {
        1
      } else {
        min_pages
      }).to_int64()
      return MemoryDefResult::MemoryWithData(
        { limits: { min, max: Some(min) }, is_memory64, page_size_log2: 16 },
        export_names,
        Bytes::from_array(init_bytes),
      )
    } else {
      // Not (data), restore and continue to limits parsing
      self.lexer.pos = saved
      self.lexer.line = saved_line
      self.lexer.column = saved_column
      self.lexer.token_start_line = saved_token_start_line
      self.lexer.token_start_column = saved_token_start_column
      self.current = LocatedToken::synthetic(LParen)
    }
  }

  // Parse limits (use u64 for memory64)
  let min = if is_memory64 {
    self.parse_u64()
  } else {
    self.parse_u32().to_int64()
  }
  let max = match self.current.token {
    Number(_) =>
      Some(
        if is_memory64 {
          self.parse_u64()
        } else {
          self.parse_u32().to_int64()
        },
      )
    _ => None
  }
  self.expect_rparen()
  MemoryDefResult::MemoryDef(
    { limits: { min, max }, is_memory64, page_size_log2: 16 },
    export_names,
  )
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

        // Check for table64 (i64 keyword before limits)
        let is_table64 = self.current.token is Keyword("i64")
        if is_table64 {
          self.advance()
        }

        // Parse limits - use u64 for table64, u32 for table32
        let min = if is_table64 {
          self.parse_u64()
        } else {
          self.parse_u32().to_int64()
        }
        let max = match self.current.token {
          Number(_) =>
            Some(
              if is_table64 {
                self.parse_u64()
              } else {
                self.parse_u32().to_int64()
              },
            )
          _ => None
        }
        // Parse element type
        let elem_type = self.parse_value_type()
        self.expect_rparen() // close table

        // Add the import to the module
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Table({
            elem_type,
            limits: { min, max },
            is_table64,
          }),
        }
        mod_.imports.push(imp)
        // Return a placeholder table (the import is what matters)
        return (
          { type_: { elem_type, limits: { min, max }, is_table64 }, init: None },
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
                limits: {
                  min: init.length().to_int64(),
                  max: Some(init.length().to_int64()),
                },
                is_table64: false,
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
          {
            type_: {
              elem_type,
              limits: { min: 0L, max: None },
              is_table64: false,
            },
            init: None,
          },
          export_name,
          None,
          table_name,
        )
      }
    }
    _ => {
      // Standard syntax: (table [i64] MIN [MAX] elemtype [init_expr])
      // Or table64 inline elem: (table i64 elemtype (elem ...))
      // Check for table64 (i64 keyword before limits)
      let is_table64 = self.current.token is Keyword("i64")
      if is_table64 {
        self.advance()
      }

      // Check if this is table64 with inline elem (i64 followed by elem type, not a number)
      if is_table64 {
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
            // table64 with inline elem syntax: (table i64 elemtype (elem ...))
            let elem_type = self.parse_value_type()
            // Check if followed by inline elem
            if self.current.token == LParen {
              self.advance()
              match self.current.token {
                Keyword("elem") => {
                  self.advance()
                  // Parse element init expressions (can be indices or expressions)
                  let init : Array[Array[@types.Instruction]] = []
                  while self.current.token != RParen {
                    match self.current.token {
                      Id(name) =>
                        match self.func_names.get(name) {
                          Some(idx) => {
                            init.push([@types.Instruction::RefFunc(idx)])
                            self.advance()
                          }
                          None => self.advance() // Placeholder for late-bound refs
                        }
                      Number(_) => {
                        let idx = self.parse_u32()
                        init.push([@types.Instruction::RefFunc(idx)])
                      }
                      LParen => {
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
                      @types.Instruction::I64Const(0L), // Use i64 for table64
                    ]),
                    type_: elem_type,
                    init,
                  }
                  let table : @types.Table = {
                    type_: {
                      elem_type,
                      limits: {
                        min: init.length().to_int64(),
                        max: Some(init.length().to_int64()),
                      },
                      is_table64: true,
                    },
                    init: None,
                  }
                  return (table, export_name, Some(elem), table_name)
                }
                _ =>
                  raise WatError::UnexpectedToken(
                    "expected elem in inline table64",
                    self.loc(),
                  )
              }
            } else {
              // Just element type followed by closing paren (no inline elem, no limits)
              self.expect_rparen()
              return (
                {
                  type_: {
                    elem_type,
                    limits: { min: 0L, max: None },
                    is_table64: true,
                  },
                  init: None,
                },
                export_name,
                None,
                table_name,
              )
            }
          }
          _ => () // Fall through to standard limits parsing
        }
      }
      // Parse limits - use u64 for table64, u32 for table32
      let min = if is_table64 {
        self.parse_u64()
      } else {
        self.parse_u32().to_int64()
      }
      let max = match self.current.token {
        Number(_) =>
          Some(
            if is_table64 {
              self.parse_u64()
            } else {
              self.parse_u32().to_int64()
            },
          )
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
        {
          type_: { elem_type, limits: { min, max }, is_table64 },
          init: table_init,
        },
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
      // Check for i64 keyword (memory64)
      let is_memory64 = match self.current.token {
        Keyword("i64") => {
          self.advance()
          true
        }
        _ => false
      }
      // Parse limits (use u64 for memory64)
      let min = if is_memory64 {
        self.parse_u64()
      } else {
        self.parse_u32().to_int64()
      }
      let max = match self.current.token {
        Number(_) =>
          Some(
            if is_memory64 {
              self.parse_u64()
            } else {
              self.parse_u32().to_int64()
            },
          )
        _ => None
      }
      @types.ImportDesc::Memory({
        limits: { min, max },
        is_memory64,
        page_size_log2: 16,
      })
    }
    Keyword("table") => {
      self.advance()
      // Optional table name
      if self.current.token is Id(tname) {
        // Register table name - table index is count of table imports so far
        self.table_names.set(tname, count_table_imports(mod_.imports))
        self.advance()
      }
      // Check for table64 (i64 keyword before limits)
      let is_table64 = self.current.token is Keyword("i64")
      if is_table64 {
        self.advance()
      }
      // Use u64 for table64 limits, u32 for table32
      let min = if is_table64 {
        self.parse_u64()
      } else {
        self.parse_u32().to_int64()
      }
      let max = match self.current.token {
        Number(_) =>
          Some(
            if is_table64 {
              self.parse_u64()
            } else {
              self.parse_u32().to_int64()
            },
          )
        _ => None
      }
      let elem_type = self.parse_value_type()
      @types.ImportDesc::Table({ elem_type, limits: { min, max }, is_table64 })
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
