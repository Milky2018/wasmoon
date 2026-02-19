///|
/// Parse a WAST script (sequence of commands)
pub fn parse_wast(input : String) -> WastScript raise WatError {
  let parser = Parser::new(input)
  let commands : Array[(WastCommand, Int)] = []

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
  WastScript::{ commands, }
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
/// Parse an inline module (module fields without explicit module wrapper)
fn Parser::parse_inline_module(self : Parser) -> @types.Module raise WatError {
  let mod_ = @types.Module::new()

  // First pass: collect all names (to support forward references)
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
  while self.current.token != Eof {
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
            // Skip module and name strings
            if self.current.token is String_(_) {
              self.advance()
            }
            if self.current.token is String_(_) {
              self.advance()
            }
            // Check for import kind and name
            if self.current.token == LParen {
              self.advance()
              match self.current.token {
                Keyword("func") => {
                  self.advance()
                  if self.current.token is Id(name) {
                    self.func_names.set(name, func_idx)
                    self.advance()
                  }
                  func_idx = func_idx + 1
                }
                Keyword("global") => {
                  self.advance()
                  if self.current.token is Id(name) {
                    self.global_names.set(name, global_idx)
                    self.advance()
                  }
                  global_idx = global_idx + 1
                }
                Keyword("memory") => {
                  self.advance()
                  if self.current.token is Id(name) {
                    self.memory_names.set(name, memory_idx)
                    self.advance()
                  }
                  memory_idx = memory_idx + 1
                }
                Keyword("table") => {
                  self.advance()
                  if self.current.token is Id(name) {
                    self.table_names.set(name, table_idx)
                    self.advance()
                  }
                  table_idx = table_idx + 1
                }
                Keyword("tag") => {
                  self.advance()
                  if self.current.token is Id(name) {
                    self.tag_names.set(name, tag_idx)
                    self.advance()
                  }
                  tag_idx = tag_idx + 1
                }
                _ => ()
              }
            }
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("func") => {
            self.advance()
            if self.current.token is Id(name) {
              self.func_names.set(name, func_idx)
              self.advance()
            }
            func_idx = func_idx + 1
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("global") => {
            self.advance()
            if self.current.token is Id(name) {
              self.global_names.set(name, global_idx)
              self.advance()
            }
            global_idx = global_idx + 1
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("memory") => {
            self.advance()
            if self.current.token is Id(name) {
              self.memory_names.set(name, memory_idx)
              self.advance()
            }
            memory_idx = memory_idx + 1
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("table") => {
            self.advance()
            if self.current.token is Id(name) {
              self.table_names.set(name, table_idx)
              self.advance()
            }
            table_idx = table_idx + 1
            self.skip_to_matching_rparen()
            self.advance() // Move past closing )
          }
          Keyword("tag") => {
            self.advance()
            if self.current.token is Id(name) {
              self.tag_names.set(name, tag_idx)
              self.advance()
            }
            tag_idx = tag_idx + 1
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

  // Restore state for second pass
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current

  // Intermediate pass: parse types first (needed for forward references)
  let saved_pos2 = self.lexer.pos
  let saved_line2 = self.lexer.line
  let saved_column2 = self.lexer.column
  let saved_token_start_line2 = self.lexer.token_start_line
  let saved_token_start_column2 = self.lexer.token_start_column
  let saved_current2 = self.current
  let mut curr_type_idx = 0
  while self.current.token != Eof {
    match self.current.token {
      LParen => {
        self.advance()
        if self.current.token is Keyword("type") {
          self.advance()
          let subtype = self.parse_type_def(curr_type_idx)
          mod_.types.push(subtype)
          // Standalone type is its own rec group
          mod_.type_rec_groups.push(curr_type_idx)
          curr_type_idx = curr_type_idx + 1
        } else if self.current.token is Keyword("rec") {
          self.parse_rec_group(mod_)
          curr_type_idx = mod_.types.length()
        } else {
          self.skip_to_matching_rparen()
        }
      }
      _ => self.advance()
    }
  }

  // Restore state for main pass
  self.lexer.pos = saved_pos2
  self.lexer.line = saved_line2
  self.lexer.column = saved_column2
  self.lexer.token_start_line = saved_token_start_line2
  self.lexer.token_start_column = saved_token_start_column2
  self.current = saved_current2

  // Main pass: parse all module fields
  while self.current.token != Eof {
    match self.current.token {
      LParen => {
        self.advance()
        self.parse_module_field_inner(mod_)
      }
      _ => raise WatError::UnexpectedToken("expected '(' in module", self.loc())
    }
  }
  // Populate func_names with reverse mapping (index -> name)
  for entry in self.func_names {
    let (name, idx) = entry
    mod_.func_names.set(idx, name)
  }
  mod_
}

///|
/// Parse a single module field (after the opening '(' has been consumed)
/// This is shared between parse_module and parse_inline_module
fn Parser::parse_module_field_inner(
  self : Parser,
  mod_ : @types.Module,
) -> Unit raise WatError {
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
          let func_idx = count_func_imports(mod_.imports) + mod_.funcs.length()
          mod_.funcs.push(type_idx)
          mod_.codes.push(code)
          for name in export_names {
            mod_.exports.push({ name, desc: @types.ExportDesc::Func(func_idx) })
          }
        }
        InlineImport(imp, export_names) => {
          let func_idx = count_func_imports(mod_.imports)
          mod_.imports.push(imp)
          for name in export_names {
            mod_.exports.push({ name, desc: @types.ExportDesc::Func(func_idx) })
          }
        }
      }
    Keyword("memory") =>
      match self.parse_memory_def() {
        MemoryDef(mem, export_names) => {
          let mem_idx = mod_.memories.length()
          mod_.memories.push(mem)
          for name in export_names {
            mod_.exports.push({ name, desc: @types.ExportDesc::Memory(mem_idx) })
          }
        }
        MemoryImport(imp, export_names) => {
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
            mod_.exports.push({ name, desc: @types.ExportDesc::Memory(mem_idx) })
          }
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
          let mut num_global_imports = 0
          for existing in mod_.imports {
            if existing.desc is @types.ImportDesc::Global(_) {
              num_global_imports += 1
            }
          }
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
      if tbl_name is Some(name) {
        self.table_names.set(name, table_idx)
      }
      if export_name is Some(name) {
        mod_.exports.push({ name, desc: @types.ExportDesc::Table(table_idx) })
      }
      if inline_elem is Some(elem) {
        mod_.elems.push(elem)
      }
    }
    Keyword("start") => {
      self.advance()
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
          let tag_idx = count_tag_imports(mod_.imports) + mod_.tags.length()
          mod_.tags.push(tag)
          for name in export_names {
            mod_.exports.push({ name, desc: @types.ExportDesc::Tag(tag_idx) })
          }
        }
        TagImport(imp, export_names) => {
          let tag_idx = count_tag_imports(mod_.imports)
          mod_.imports.push(imp)
          for name in export_names {
            mod_.exports.push({ name, desc: @types.ExportDesc::Tag(tag_idx) })
          }
        }
      }
    Keyword(kw) =>
      raise WatError::UnexpectedToken(
        "unexpected module field: \{kw}",
        self.loc(),
      )
    _ => raise WatError::UnexpectedToken("expected module field", self.loc())
  }
}

///|
fn Parser::parse_wast_command(self : Parser) -> WastCommand raise WatError {
  self.expect_lparen()
  match self.current.token {
    Keyword("module") => self.parse_wast_module_command()
    Keyword("assert_return") => self.parse_wast_assert_return()
    Keyword("assert_trap") => self.parse_wast_assert_trap()
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
      raise WatError::UnexpectedToken(
        "unexpected command: \{self.current.token}",
        self.loc(),
      )
  }
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
      let mod_ = @parser.parse_module(bytes) catch {
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
      ModuleQuote(parts)
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
          let mod_ = @parser.parse_module(bytes) catch {
            e => return ModuleBinaryFailed(e.to_string())
          }
          ModuleDefinition(mod_, final_name)
        }
        _ => {
          let module_text = self.collect_wast_module_text()
          self.expect_rparen()
          let mod_ = parse("(module " + module_text + ")") catch {
            e => raise e
          }
          ModuleDefinition(mod_, final_name)
        }
      }
    }
    Keyword("instance") => {
      // (module instance $instance_name $definition_name)
      self.advance() // consume 'instance'
      let instance_name = self.parse_wast_optional_id()
      // The definition name is required - parse as identifier
      let def_name = match self.current.token {
        Id(s) => {
          self.advance()
          s
        }
        _ =>
          raise WatError::UnexpectedToken(
            "expected module definition name",
            self.loc(),
          )
      }
      self.expect_rparen()
      ModuleInstance(instance_name, def_name)
    }
    _ => {
      let module_text = self.collect_wast_module_text()
      self.expect_rparen()
      let mod_ = parse("(module " + module_text + ")") catch { e => raise e }
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
  let buf = StringBuilder::new()
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
      s
    }
    _ => raise WatError::UnexpectedToken("expected string", self.loc())
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
          Quote(parts)
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
    _ => raise WatError::UnexpectedToken("expected 'module'", self.loc())
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
    _ =>
      raise WatError::UnexpectedToken("expected 'invoke' or 'get'", self.loc())
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
      RefFunc
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
    _ =>
      raise WatError::UnexpectedToken("expected const instruction", self.loc())
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
          let buf : @buffer.Buffer = @buffer.new(size_hint=16)
          for _ in 0..<16 {
            let v = self.parse_wast_i32()
            buf.write_byte(v.to_byte())
          }
          V128(buf.contents())
        }
        "i16x8" => {
          let buf : @buffer.Buffer = @buffer.new(size_hint=16)
          for _ in 0..<8 {
            let v = self.parse_wast_i32()
            buf.write_byte(v.to_byte())
            buf.write_byte((v >> 8).to_byte())
          }
          V128(buf.contents())
        }
        "i32x4" => {
          let buf : @buffer.Buffer = @buffer.new(size_hint=16)
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
          let buf : @buffer.Buffer = @buffer.new(size_hint=16)
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
                lanes.push(WastLaneValue::F32CanonicalNan)
                has_nan = true
              }
              Keyword("nan:arithmetic") => {
                self.advance()
                lanes.push(WastLaneValue::F32ArithmeticNan)
                has_nan = true
              }
              _ => {
                let f = self.parse_wast_f32()
                lanes.push(WastLaneValue::F32(f))
              }
            }
          }
          if has_nan {
            V128Pattern(lanes)
          } else {
            // Build bytes from float values
            let buf : @buffer.Buffer = @buffer.new(size_hint=16)
            for lane in lanes {
              match lane {
                WastLaneValue::F32(f) => {
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
                lanes.push(WastLaneValue::F64CanonicalNan)
                has_nan = true
              }
              Keyword("nan:arithmetic") => {
                self.advance()
                lanes.push(WastLaneValue::F64ArithmeticNan)
                has_nan = true
              }
              _ => {
                let f = self.parse_wast_f64()
                lanes.push(WastLaneValue::F64(f))
              }
            }
          }
          if has_nan {
            V128Pattern(lanes)
          } else {
            // Build bytes from double values
            let buf : @buffer.Buffer = @buffer.new(size_hint=16)
            for lane in lanes {
              match lane {
                WastLaneValue::F64(f) => {
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
}

///|
fn Parser::parse_wast_i32(self : Parser) -> Int raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_wast_int(s)
    }
    _ => raise WatError::UnexpectedToken("expected number", self.loc())
  }
}

///|
fn Parser::parse_wast_i64(self : Parser) -> Int64 raise WatError {
  match self.current.token {
    Number(s) => {
      self.advance()
      parse_wast_int64(s)
    }
    _ => raise WatError::UnexpectedToken("expected number", self.loc())
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
        raise WatError::UnexpectedToken("expected number", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected number", self.loc())
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
        raise WatError::UnexpectedToken("expected number", self.loc())
      }
    _ => raise WatError::UnexpectedToken("expected number", self.loc())
  }
}

///|
fn parse_wast_int(s : String) -> Int raise WatError {
  if s.length() == 0 {
    raise WatError::InvalidNumber(s, { line: 0, column: 0 })
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
        raise WatError::InvalidNumber(s, { line: 0, column: 0 })
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
fn parse_wast_hex_int(s : String, start : Int) -> Int raise WatError {
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
      raise WatError::InvalidNumber(s, { line: 0, column: 0 })
    }
    result = result * 16 + digit
  }
  result
}

///|
fn parse_wast_int64(s : String) -> Int64 raise WatError {
  if s.length() == 0 {
    raise WatError::InvalidNumber(s, { line: 0, column: 0 })
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
        raise WatError::InvalidNumber(s, { line: 0, column: 0 })
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
fn parse_wast_hex_int64(s : String, start : Int) -> Int64 raise WatError {
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
      raise WatError::InvalidNumber(s, { line: 0, column: 0 })
    }
    result = result * 16L + digit.to_int64()
  }
  result
}
