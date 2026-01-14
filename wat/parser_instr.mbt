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
      // memory.init can have one or two indices:
      // - memory.init dataidx (memidx defaults to 0)
      // - memory.init memidx dataidx
      // We need to look ahead to determine which format
      let first_idx = self.parse_index_for_memory_init()
      // Check if there's another index
      match self.current.token {
        Number(_) | Id(_) => {
          // Two indices: first is memidx, second is dataidx
          let memidx = first_idx
          let dataidx = self.parse_data_idx()
          @types.Instruction::MemoryInit(memidx, dataidx)
        }
        _ =>
          // One index: it's dataidx, memidx defaults to 0
          @types.Instruction::MemoryInit(0, first_idx)
      }
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
    "i64.mul_wide_s" => @types.Instruction::I64MulWideS
    "i64.mul_wide_u" => @types.Instruction::I64MulWideU
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
    // SIMD instructions
    "v128.const" => {
      let bytes = self.parse_v128_const()
      @types.Instruction::V128Const(bytes)
    }

    // SIMD memory operations
    "v128.load" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::V128Load(m, a, o) })
    "v128.store" =>
      parse_mem_arg(self, fn(m, a, o) { @types.Instruction::V128Store(m, a, o) })
    "v128.load8x8_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load8x8S(m, a, o)
      })
    "v128.load8x8_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load8x8U(m, a, o)
      })
    "v128.load16x4_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load16x4S(m, a, o)
      })
    "v128.load16x4_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load16x4U(m, a, o)
      })
    "v128.load32x2_s" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load32x2S(m, a, o)
      })
    "v128.load32x2_u" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load32x2U(m, a, o)
      })
    "v128.load8_splat" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load8Splat(m, a, o)
      })
    "v128.load16_splat" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load16Splat(m, a, o)
      })
    "v128.load32_splat" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load32Splat(m, a, o)
      })
    "v128.load64_splat" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load64Splat(m, a, o)
      })
    "v128.load32_zero" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load32Zero(m, a, o)
      })
    "v128.load64_zero" =>
      parse_mem_arg(self, fn(m, a, o) {
        @types.Instruction::V128Load64Zero(m, a, o)
      })
    "v128.load8_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Load8Lane(memidx, align, offset, lane)
    }
    "v128.load16_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Load16Lane(memidx, align, offset, lane)
    }
    "v128.load32_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Load32Lane(memidx, align, offset, lane)
    }
    "v128.load64_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Load64Lane(memidx, align, offset, lane)
    }
    "v128.store8_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Store8Lane(memidx, align, offset, lane)
    }
    "v128.store16_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Store16Lane(memidx, align, offset, lane)
    }
    "v128.store32_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Store32Lane(memidx, align, offset, lane)
    }
    "v128.store64_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      @types.Instruction::V128Store64Lane(memidx, align, offset, lane)
    }

    // SIMD shuffle and swizzle
    "i8x16.shuffle" => {
      // Parse 16 lane indices
      let lanes : FixedArray[Int] = FixedArray::make(16, 0)
      for i in 0..<16 {
        lanes[i] = self.parse_u32()
      }
      @types.Instruction::I8x16Shuffle(lanes)
    }
    "i8x16.swizzle" => @types.Instruction::I8x16Swizzle

    // SIMD splat
    "i8x16.splat" => @types.Instruction::I8x16Splat
    "i16x8.splat" => @types.Instruction::I16x8Splat
    "i32x4.splat" => @types.Instruction::I32x4Splat
    "i64x2.splat" => @types.Instruction::I64x2Splat
    "f32x4.splat" => @types.Instruction::F32x4Splat
    "f64x2.splat" => @types.Instruction::F64x2Splat

    // SIMD extract lane
    "i8x16.extract_lane_s" =>
      @types.Instruction::I8x16ExtractLaneS(self.parse_u32())
    "i8x16.extract_lane_u" =>
      @types.Instruction::I8x16ExtractLaneU(self.parse_u32())
    "i16x8.extract_lane_s" =>
      @types.Instruction::I16x8ExtractLaneS(self.parse_u32())
    "i16x8.extract_lane_u" =>
      @types.Instruction::I16x8ExtractLaneU(self.parse_u32())
    "i32x4.extract_lane" =>
      @types.Instruction::I32x4ExtractLane(self.parse_u32())
    "i64x2.extract_lane" =>
      @types.Instruction::I64x2ExtractLane(self.parse_u32())
    "f32x4.extract_lane" =>
      @types.Instruction::F32x4ExtractLane(self.parse_u32())
    "f64x2.extract_lane" =>
      @types.Instruction::F64x2ExtractLane(self.parse_u32())

    // SIMD replace lane
    "i8x16.replace_lane" =>
      @types.Instruction::I8x16ReplaceLane(self.parse_u32())
    "i16x8.replace_lane" =>
      @types.Instruction::I16x8ReplaceLane(self.parse_u32())
    "i32x4.replace_lane" =>
      @types.Instruction::I32x4ReplaceLane(self.parse_u32())
    "i64x2.replace_lane" =>
      @types.Instruction::I64x2ReplaceLane(self.parse_u32())
    "f32x4.replace_lane" =>
      @types.Instruction::F32x4ReplaceLane(self.parse_u32())
    "f64x2.replace_lane" =>
      @types.Instruction::F64x2ReplaceLane(self.parse_u32())

    // SIMD comparisons - i8x16
    "i8x16.eq" => @types.Instruction::I8x16Eq
    "i8x16.ne" => @types.Instruction::I8x16Ne
    "i8x16.lt_s" => @types.Instruction::I8x16LtS
    "i8x16.lt_u" => @types.Instruction::I8x16LtU
    "i8x16.gt_s" => @types.Instruction::I8x16GtS
    "i8x16.gt_u" => @types.Instruction::I8x16GtU
    "i8x16.le_s" => @types.Instruction::I8x16LeS
    "i8x16.le_u" => @types.Instruction::I8x16LeU
    "i8x16.ge_s" => @types.Instruction::I8x16GeS
    "i8x16.ge_u" => @types.Instruction::I8x16GeU

    // SIMD comparisons - i16x8
    "i16x8.eq" => @types.Instruction::I16x8Eq
    "i16x8.ne" => @types.Instruction::I16x8Ne
    "i16x8.lt_s" => @types.Instruction::I16x8LtS
    "i16x8.lt_u" => @types.Instruction::I16x8LtU
    "i16x8.gt_s" => @types.Instruction::I16x8GtS
    "i16x8.gt_u" => @types.Instruction::I16x8GtU
    "i16x8.le_s" => @types.Instruction::I16x8LeS
    "i16x8.le_u" => @types.Instruction::I16x8LeU
    "i16x8.ge_s" => @types.Instruction::I16x8GeS
    "i16x8.ge_u" => @types.Instruction::I16x8GeU

    // SIMD comparisons - i32x4
    "i32x4.eq" => @types.Instruction::I32x4Eq
    "i32x4.ne" => @types.Instruction::I32x4Ne
    "i32x4.lt_s" => @types.Instruction::I32x4LtS
    "i32x4.lt_u" => @types.Instruction::I32x4LtU
    "i32x4.gt_s" => @types.Instruction::I32x4GtS
    "i32x4.gt_u" => @types.Instruction::I32x4GtU
    "i32x4.le_s" => @types.Instruction::I32x4LeS
    "i32x4.le_u" => @types.Instruction::I32x4LeU
    "i32x4.ge_s" => @types.Instruction::I32x4GeS
    "i32x4.ge_u" => @types.Instruction::I32x4GeU

    // SIMD comparisons - i64x2
    "i64x2.eq" => @types.Instruction::I64x2Eq
    "i64x2.ne" => @types.Instruction::I64x2Ne
    "i64x2.lt_s" => @types.Instruction::I64x2LtS
    "i64x2.gt_s" => @types.Instruction::I64x2GtS
    "i64x2.le_s" => @types.Instruction::I64x2LeS
    "i64x2.ge_s" => @types.Instruction::I64x2GeS

    // SIMD comparisons - f32x4
    "f32x4.eq" => @types.Instruction::F32x4Eq
    "f32x4.ne" => @types.Instruction::F32x4Ne
    "f32x4.lt" => @types.Instruction::F32x4Lt
    "f32x4.gt" => @types.Instruction::F32x4Gt
    "f32x4.le" => @types.Instruction::F32x4Le
    "f32x4.ge" => @types.Instruction::F32x4Ge

    // SIMD comparisons - f64x2
    "f64x2.eq" => @types.Instruction::F64x2Eq
    "f64x2.ne" => @types.Instruction::F64x2Ne
    "f64x2.lt" => @types.Instruction::F64x2Lt
    "f64x2.gt" => @types.Instruction::F64x2Gt
    "f64x2.le" => @types.Instruction::F64x2Le
    "f64x2.ge" => @types.Instruction::F64x2Ge

    // SIMD bitwise
    "v128.not" => @types.Instruction::V128Not
    "v128.and" => @types.Instruction::V128And
    "v128.andnot" => @types.Instruction::V128AndNot
    "v128.or" => @types.Instruction::V128Or
    "v128.xor" => @types.Instruction::V128Xor
    "v128.bitselect" => @types.Instruction::V128Bitselect
    "v128.any_true" => @types.Instruction::V128AnyTrue

    // i8x16 operations
    "i8x16.abs" => @types.Instruction::I8x16Abs
    "i8x16.neg" => @types.Instruction::I8x16Neg
    "i8x16.popcnt" => @types.Instruction::I8x16Popcnt
    "i8x16.all_true" => @types.Instruction::I8x16AllTrue
    "i8x16.bitmask" => @types.Instruction::I8x16Bitmask
    "i8x16.narrow_i16x8_s" => @types.Instruction::I8x16NarrowI16x8S
    "i8x16.narrow_i16x8_u" => @types.Instruction::I8x16NarrowI16x8U
    "i8x16.shl" => @types.Instruction::I8x16Shl
    "i8x16.shr_s" => @types.Instruction::I8x16ShrS
    "i8x16.shr_u" => @types.Instruction::I8x16ShrU
    "i8x16.add" => @types.Instruction::I8x16Add
    "i8x16.add_sat_s" => @types.Instruction::I8x16AddSatS
    "i8x16.add_sat_u" => @types.Instruction::I8x16AddSatU
    "i8x16.sub" => @types.Instruction::I8x16Sub
    "i8x16.sub_sat_s" => @types.Instruction::I8x16SubSatS
    "i8x16.sub_sat_u" => @types.Instruction::I8x16SubSatU
    "i8x16.min_s" => @types.Instruction::I8x16MinS
    "i8x16.min_u" => @types.Instruction::I8x16MinU
    "i8x16.max_s" => @types.Instruction::I8x16MaxS
    "i8x16.max_u" => @types.Instruction::I8x16MaxU
    "i8x16.avgr_u" => @types.Instruction::I8x16AvgrU

    // i16x8 operations
    "i16x8.abs" => @types.Instruction::I16x8Abs
    "i16x8.neg" => @types.Instruction::I16x8Neg
    "i16x8.all_true" => @types.Instruction::I16x8AllTrue
    "i16x8.bitmask" => @types.Instruction::I16x8Bitmask
    "i16x8.narrow_i32x4_s" => @types.Instruction::I16x8NarrowI32x4S
    "i16x8.narrow_i32x4_u" => @types.Instruction::I16x8NarrowI32x4U
    "i16x8.extend_low_i8x16_s" => @types.Instruction::I16x8ExtendLowI8x16S
    "i16x8.extend_high_i8x16_s" => @types.Instruction::I16x8ExtendHighI8x16S
    "i16x8.extend_low_i8x16_u" => @types.Instruction::I16x8ExtendLowI8x16U
    "i16x8.extend_high_i8x16_u" => @types.Instruction::I16x8ExtendHighI8x16U
    "i16x8.shl" => @types.Instruction::I16x8Shl
    "i16x8.shr_s" => @types.Instruction::I16x8ShrS
    "i16x8.shr_u" => @types.Instruction::I16x8ShrU
    "i16x8.add" => @types.Instruction::I16x8Add
    "i16x8.add_sat_s" => @types.Instruction::I16x8AddSatS
    "i16x8.add_sat_u" => @types.Instruction::I16x8AddSatU
    "i16x8.sub" => @types.Instruction::I16x8Sub
    "i16x8.sub_sat_s" => @types.Instruction::I16x8SubSatS
    "i16x8.sub_sat_u" => @types.Instruction::I16x8SubSatU
    "i16x8.mul" => @types.Instruction::I16x8Mul
    "i16x8.min_s" => @types.Instruction::I16x8MinS
    "i16x8.min_u" => @types.Instruction::I16x8MinU
    "i16x8.max_s" => @types.Instruction::I16x8MaxS
    "i16x8.max_u" => @types.Instruction::I16x8MaxU
    "i16x8.avgr_u" => @types.Instruction::I16x8AvgrU
    "i16x8.extmul_low_i8x16_s" => @types.Instruction::I16x8ExtMulLowI8x16S
    "i16x8.extmul_high_i8x16_s" => @types.Instruction::I16x8ExtMulHighI8x16S
    "i16x8.extmul_low_i8x16_u" => @types.Instruction::I16x8ExtMulLowI8x16U
    "i16x8.extmul_high_i8x16_u" => @types.Instruction::I16x8ExtMulHighI8x16U
    "i16x8.q15mulr_sat_s" => @types.Instruction::I16x8Q15MulrSatS
    "i16x8.extadd_pairwise_i8x16_s" =>
      @types.Instruction::I16x8ExtAddPairwiseI8x16S
    "i16x8.extadd_pairwise_i8x16_u" =>
      @types.Instruction::I16x8ExtAddPairwiseI8x16U

    // i32x4 operations
    "i32x4.abs" => @types.Instruction::I32x4Abs
    "i32x4.neg" => @types.Instruction::I32x4Neg
    "i32x4.all_true" => @types.Instruction::I32x4AllTrue
    "i32x4.bitmask" => @types.Instruction::I32x4Bitmask
    "i32x4.extend_low_i16x8_s" => @types.Instruction::I32x4ExtendLowI16x8S
    "i32x4.extend_high_i16x8_s" => @types.Instruction::I32x4ExtendHighI16x8S
    "i32x4.extend_low_i16x8_u" => @types.Instruction::I32x4ExtendLowI16x8U
    "i32x4.extend_high_i16x8_u" => @types.Instruction::I32x4ExtendHighI16x8U
    "i32x4.shl" => @types.Instruction::I32x4Shl
    "i32x4.shr_s" => @types.Instruction::I32x4ShrS
    "i32x4.shr_u" => @types.Instruction::I32x4ShrU
    "i32x4.add" => @types.Instruction::I32x4Add
    "i32x4.sub" => @types.Instruction::I32x4Sub
    "i32x4.mul" => @types.Instruction::I32x4Mul
    "i32x4.min_s" => @types.Instruction::I32x4MinS
    "i32x4.min_u" => @types.Instruction::I32x4MinU
    "i32x4.max_s" => @types.Instruction::I32x4MaxS
    "i32x4.max_u" => @types.Instruction::I32x4MaxU
    "i32x4.dot_i16x8_s" => @types.Instruction::I32x4DotI16x8S
    "i32x4.extmul_low_i16x8_s" => @types.Instruction::I32x4ExtMulLowI16x8S
    "i32x4.extmul_high_i16x8_s" => @types.Instruction::I32x4ExtMulHighI16x8S
    "i32x4.extmul_low_i16x8_u" => @types.Instruction::I32x4ExtMulLowI16x8U
    "i32x4.extmul_high_i16x8_u" => @types.Instruction::I32x4ExtMulHighI16x8U
    "i32x4.extadd_pairwise_i16x8_s" =>
      @types.Instruction::I32x4ExtAddPairwiseI16x8S
    "i32x4.extadd_pairwise_i16x8_u" =>
      @types.Instruction::I32x4ExtAddPairwiseI16x8U
    "i32x4.trunc_sat_f32x4_s" => @types.Instruction::I32x4TruncSatF32x4S
    "i32x4.trunc_sat_f32x4_u" => @types.Instruction::I32x4TruncSatF32x4U
    "i32x4.trunc_sat_f64x2_s_zero" =>
      @types.Instruction::I32x4TruncSatF64x2SZero
    "i32x4.trunc_sat_f64x2_u_zero" =>
      @types.Instruction::I32x4TruncSatF64x2UZero

    // i64x2 operations
    "i64x2.abs" => @types.Instruction::I64x2Abs
    "i64x2.neg" => @types.Instruction::I64x2Neg
    "i64x2.all_true" => @types.Instruction::I64x2AllTrue
    "i64x2.bitmask" => @types.Instruction::I64x2Bitmask
    "i64x2.extend_low_i32x4_s" => @types.Instruction::I64x2ExtendLowI32x4S
    "i64x2.extend_high_i32x4_s" => @types.Instruction::I64x2ExtendHighI32x4S
    "i64x2.extend_low_i32x4_u" => @types.Instruction::I64x2ExtendLowI32x4U
    "i64x2.extend_high_i32x4_u" => @types.Instruction::I64x2ExtendHighI32x4U
    "i64x2.shl" => @types.Instruction::I64x2Shl
    "i64x2.shr_s" => @types.Instruction::I64x2ShrS
    "i64x2.shr_u" => @types.Instruction::I64x2ShrU
    "i64x2.add" => @types.Instruction::I64x2Add
    "i64x2.sub" => @types.Instruction::I64x2Sub
    "i64x2.mul" => @types.Instruction::I64x2Mul
    "i64x2.extmul_low_i32x4_s" => @types.Instruction::I64x2ExtMulLowI32x4S
    "i64x2.extmul_high_i32x4_s" => @types.Instruction::I64x2ExtMulHighI32x4S
    "i64x2.extmul_low_i32x4_u" => @types.Instruction::I64x2ExtMulLowI32x4U
    "i64x2.extmul_high_i32x4_u" => @types.Instruction::I64x2ExtMulHighI32x4U

    // f32x4 operations
    "f32x4.abs" => @types.Instruction::F32x4Abs
    "f32x4.neg" => @types.Instruction::F32x4Neg
    "f32x4.sqrt" => @types.Instruction::F32x4Sqrt
    "f32x4.add" => @types.Instruction::F32x4Add
    "f32x4.sub" => @types.Instruction::F32x4Sub
    "f32x4.mul" => @types.Instruction::F32x4Mul
    "f32x4.div" => @types.Instruction::F32x4Div
    "f32x4.min" => @types.Instruction::F32x4Min
    "f32x4.max" => @types.Instruction::F32x4Max
    "f32x4.pmin" => @types.Instruction::F32x4Pmin
    "f32x4.pmax" => @types.Instruction::F32x4Pmax
    "f32x4.ceil" => @types.Instruction::F32x4Ceil
    "f32x4.floor" => @types.Instruction::F32x4Floor
    "f32x4.trunc" => @types.Instruction::F32x4Trunc
    "f32x4.nearest" => @types.Instruction::F32x4Nearest
    "f32x4.convert_i32x4_s" => @types.Instruction::F32x4ConvertI32x4S
    "f32x4.convert_i32x4_u" => @types.Instruction::F32x4ConvertI32x4U
    "f32x4.demote_f64x2_zero" => @types.Instruction::F32x4DemoteF64x2Zero

    // f64x2 operations
    "f64x2.abs" => @types.Instruction::F64x2Abs
    "f64x2.neg" => @types.Instruction::F64x2Neg
    "f64x2.sqrt" => @types.Instruction::F64x2Sqrt
    "f64x2.add" => @types.Instruction::F64x2Add
    "f64x2.sub" => @types.Instruction::F64x2Sub
    "f64x2.mul" => @types.Instruction::F64x2Mul
    "f64x2.div" => @types.Instruction::F64x2Div
    "f64x2.min" => @types.Instruction::F64x2Min
    "f64x2.max" => @types.Instruction::F64x2Max
    "f64x2.pmin" => @types.Instruction::F64x2Pmin
    "f64x2.pmax" => @types.Instruction::F64x2Pmax
    "f64x2.ceil" => @types.Instruction::F64x2Ceil
    "f64x2.floor" => @types.Instruction::F64x2Floor
    "f64x2.trunc" => @types.Instruction::F64x2Trunc
    "f64x2.nearest" => @types.Instruction::F64x2Nearest
    "f64x2.convert_low_i32x4_s" => @types.Instruction::F64x2ConvertLowI32x4S
    "f64x2.convert_low_i32x4_u" => @types.Instruction::F64x2ConvertLowI32x4U
    "f64x2.promote_low_f32x4" => @types.Instruction::F64x2PromoteLowF32x4

    // Relaxed SIMD instructions
    "i8x16.relaxed_swizzle" => @types.Instruction::I8x16RelaxedSwizzle
    "i32x4.relaxed_trunc_f32x4_s" => @types.Instruction::I32x4RelaxedTruncF32x4S
    "i32x4.relaxed_trunc_f32x4_u" => @types.Instruction::I32x4RelaxedTruncF32x4U
    "i32x4.relaxed_trunc_f64x2_s_zero" =>
      @types.Instruction::I32x4RelaxedTruncF64x2SZero
    "i32x4.relaxed_trunc_f64x2_u_zero" =>
      @types.Instruction::I32x4RelaxedTruncF64x2UZero
    "f32x4.relaxed_madd" => @types.Instruction::F32x4RelaxedMadd
    "f32x4.relaxed_nmadd" => @types.Instruction::F32x4RelaxedNmadd
    "f64x2.relaxed_madd" => @types.Instruction::F64x2RelaxedMadd
    "f64x2.relaxed_nmadd" => @types.Instruction::F64x2RelaxedNmadd
    "i8x16.relaxed_laneselect" => @types.Instruction::I8x16RelaxedLaneselect
    "i16x8.relaxed_laneselect" => @types.Instruction::I16x8RelaxedLaneselect
    "i32x4.relaxed_laneselect" => @types.Instruction::I32x4RelaxedLaneselect
    "i64x2.relaxed_laneselect" => @types.Instruction::I64x2RelaxedLaneselect
    "f32x4.relaxed_min" => @types.Instruction::F32x4RelaxedMin
    "f32x4.relaxed_max" => @types.Instruction::F32x4RelaxedMax
    "f64x2.relaxed_min" => @types.Instruction::F64x2RelaxedMin
    "f64x2.relaxed_max" => @types.Instruction::F64x2RelaxedMax
    "i16x8.relaxed_q15mulr_s" => @types.Instruction::I16x8RelaxedQ15mulrS
    "i16x8.relaxed_dot_i8x16_i7x16_s" =>
      @types.Instruction::I16x8RelaxedDotI8x16I7x16S
    "i32x4.relaxed_dot_i8x16_i7x16_add_s" =>
      @types.Instruction::I32x4RelaxedDotI8x16I7x16AddS
    _ => raise WatError::InvalidInstruction(kw, self.loc())
  }
}

///|
/// Parse memory arg and return tuple (memidx, align, offset)
fn parse_mem_arg_tuple(parser : Parser) -> (Int, Int, Int64) raise WatError {
  let mut memidx = 0
  let mut offset = 0L
  let mut align = 0
  // Multi-memory: Parse optional memory index
  match parser.current.token {
    Id(name) => {
      memidx = parser.resolve_memory(name)
      parser.advance()
    }
    Number(s) =>
      if !s.has_prefix("offset=") && !s.has_prefix("align=") {
        let saved_pos = parser.lexer.pos
        let saved_line = parser.lexer.line
        let saved_column = parser.lexer.column
        let saved_token = parser.current
        parser.advance()
        let is_memidx = match parser.current.token {
          Keyword(k) => k.has_prefix("offset=") || k.has_prefix("align=")
          RParen => true
          Number(_) => true // Could be lane index after memarg
          _ => false
        }
        if is_memidx {
          memidx = parse_int(s)
        } else {
          parser.lexer.pos = saved_pos
          parser.lexer.line = saved_line
          parser.lexer.column = saved_column
          parser.current = saved_token
        }
      }
    _ => ()
  }
  while true {
    match parser.current.token {
      Keyword(s) =>
        if s.has_prefix("offset=") {
          let offset_str = StringBuilder::new()
          for i in 7..<s.length() {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          offset = parse_u64(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::new()
          for i in 6..<s.length() {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_u32(align_str.to_string())
          align = log2(a)
          parser.advance()
        } else {
          break
        }
      _ => break
    }
  }
  (memidx, align, offset)
}

///|
fn parse_mem_arg(
  parser : Parser,
  instr : (Int, Int, Int64) -> @types.Instruction,
) -> @types.Instruction raise WatError {
  let mut memidx = 0
  let mut offset = 0L
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
          // Use parse_u64 for offset (memory64 supports 64-bit offsets)
          offset = parse_u64(offset_str.to_string())
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
