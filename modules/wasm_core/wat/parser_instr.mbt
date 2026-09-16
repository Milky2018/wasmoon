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
        return [Block(bt, body)]
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
        return [Loop(bt, body)]
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
              raise UnexpectedToken("expected 'then' in folded if", self.loc())
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
        result.push(If(bt, then_body, else_body))
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
              handlers.push(Catch(tag_idx, label_idx))
              self.expect_rparen()
            }
            Keyword("catch_ref") => {
              self.advance() // skip "catch_ref"
              let tag_idx = self.parse_tag_idx()
              let label_idx = self.parse_label_idx()
              handlers.push(CatchRef(tag_idx, label_idx))
              self.expect_rparen()
            }
            Keyword("catch_all") => {
              self.advance() // skip "catch_all"
              let label_idx = self.parse_label_idx()
              handlers.push(CatchAll(label_idx))
              self.expect_rparen()
            }
            Keyword("catch_all_ref") => {
              self.advance() // skip "catch_all_ref"
              let label_idx = self.parse_label_idx()
              handlers.push(CatchAllRef(label_idx))
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
        return [TryTable(bt, handlers, body)]
      }
      let instr = self.parse_plain_instruction(kw)
      // For control instructions, we've already handled them
      // For other instructions, parse folded operands
      match instr {
        Block(_, _) | Loop(_, _) | If(_, _, _) | TryTable(_, _, _) => [instr]
        _ => {
          // Parse nested folded instructions (operands)
          let result = self.parse_instructions()
          self.expect_rparen()
          result.push(instr)
          result
        }
      }
    }
    _ => raise UnexpectedToken("expected instruction", self.loc())
  }
}

///|
fn Parser::parse_plain_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  self.advance()
  if kw.has_prefix("i32.") {
    return self.parse_i32_instruction(kw)
  }
  if kw.has_prefix("i64.") {
    return self.parse_i64_instruction(kw)
  }
  if kw.has_prefix("f32.") {
    return self.parse_f32_instruction(kw)
  }
  if kw.has_prefix("f64.") {
    return self.parse_f64_instruction(kw)
  }
  if kw.has_prefix("v128.") {
    return self.parse_v128_instruction(kw)
  }
  if kw.has_prefix("i8x16.") {
    return self.parse_i8x16_instruction(kw)
  }
  if kw.has_prefix("i16x8.") {
    return self.parse_i16x8_instruction(kw)
  }
  if kw.has_prefix("i32x4.") {
    return self.parse_i32x4_instruction(kw)
  }
  if kw.has_prefix("i64x2.") {
    return self.parse_i64x2_instruction(kw)
  }
  if kw.has_prefix("f32x4.") {
    return self.parse_f32x4_instruction(kw)
  }
  if kw.has_prefix("f64x2.") {
    return self.parse_f64x2_instruction(kw)
  }
  match kw {
    // Control
    "unreachable" => Unreachable
    "nop" => Nop
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
      Block(bt, body)
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
      Loop(bt, body)
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
      If(bt, then_body, else_body)
    }
    "br" => Br(self.parse_label_idx())
    "br_if" => BrIf(self.parse_label_idx())
    "br_table" => {
      let labels : Array[Int] = []
      while self.current.token != RParen && self.current.token != Eof {
        match self.current.token {
          Number(_) | Id(_) => labels.push(self.parse_label_idx())
          _ => break
        }
      }
      if labels.length() == 0 {
        raise ParseError("br_table requires at least one label", self.loc())
      }
      let default_label = labels.pop().unwrap()
      BrTable(labels, default_label)
    }
    "return" => Return
    // Exception handling instructions
    "throw" => Throw(self.parse_tag_idx())
    "throw_ref" => ThrowRef
    "cont.new" => ContNew(self.parse_type_idx())
    "cont.bind" => ContBind(self.parse_type_idx(), self.parse_type_idx())
    "suspend" => Suspend(self.parse_tag_idx())
    "resume" => Resume(self.parse_type_idx(), self.parse_resume_handlers())
    "resume_throw" =>
      ResumeThrow(
        self.parse_type_idx(),
        self.parse_tag_idx(),
        self.parse_resume_handlers(),
      )
    "resume_throw_ref" =>
      ResumeThrowRef(self.parse_type_idx(), self.parse_resume_handlers())
    "switch" => Switch(self.parse_type_idx(), self.parse_tag_idx())
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
            handlers.push(Catch(tag_idx, label_idx))
            self.expect_rparen()
          }
          Keyword("catch_ref") => {
            self.advance() // skip "catch_ref"
            let tag_idx = self.parse_tag_idx()
            let label_idx = self.parse_label_idx()
            handlers.push(CatchRef(tag_idx, label_idx))
            self.expect_rparen()
          }
          Keyword("catch_all") => {
            self.advance() // skip "catch_all"
            let label_idx = self.parse_label_idx()
            handlers.push(CatchAll(label_idx))
            self.expect_rparen()
          }
          Keyword("catch_all_ref") => {
            self.advance() // skip "catch_all_ref"
            let label_idx = self.parse_label_idx()
            handlers.push(CatchAllRef(label_idx))
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
      TryTable(bt, handlers, body)
    }
    "call" => Call(self.parse_func_idx())
    "call_ref" => {
      // call_ref $type - calls a function reference with the given type
      let type_idx = self.parse_type_idx()
      CallRef(type_idx)
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
              raise ParseError("unknown type", self.loc())
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
      CallIndirect(final_type_idx, table_idx)
    }
    "return_call" => ReturnCall(self.parse_func_idx())
    "return_call_ref" => {
      // return_call_ref $type - tail calls a function reference with the given type
      let type_idx = self.parse_type_idx()
      ReturnCallRef(type_idx)
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
              raise ParseError("unknown type", self.loc())
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
      ReturnCallIndirect(final_type_idx, table_idx)
    }

    // Parametric
    "drop" => Drop
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
        Select
      } else {
        SelectTyped(result_types)
      }
    }

    // Reference types
    "ref.null" => {
      // Parse reference type (func or extern)
      let ref_type = self.parse_ref_type()
      RefNull(ref_type)
    }
    "ref.is_null" => RefIsNull
    "ref.func" => RefFunc(self.parse_func_idx())
    "ref.as_non_null" => RefAsNonNull
    "ref.eq" => RefEqInstr
    "br_on_null" => BrOnNull(self.parse_label_idx())
    "br_on_non_null" => BrOnNonNull(self.parse_label_idx())
    "br_on_cast" => {
      let label_idx = self.parse_label_idx()
      let from_type = self.parse_ref_type()
      let to_type = self.parse_ref_type()
      BrOnCast(label_idx, from_type, to_type)
    }
    "br_on_cast_fail" => {
      let label_idx = self.parse_label_idx()
      let from_type = self.parse_ref_type()
      let to_type = self.parse_ref_type()
      BrOnCastFail(label_idx, from_type, to_type)
    }

    // Variable
    "local.get" => LocalGet(self.parse_local_idx())
    "local.set" => LocalSet(self.parse_local_idx())
    "local.tee" => LocalTee(self.parse_local_idx())
    "global.get" => GlobalGet(self.parse_global_idx())
    "global.set" => GlobalSet(self.parse_global_idx())

    // Table instructions
    "table.get" => TableGet(self.parse_table_idx())
    "table.set" => TableSet(self.parse_table_idx())
    "table.size" => TableSize(self.parse_table_idx())
    "table.grow" => TableGrow(self.parse_table_idx())
    "table.fill" => TableFill(self.parse_table_idx())
    "table.copy" => {
      let dest = self.parse_table_idx()
      let src = self.parse_table_idx()
      TableCopy(dest, src)
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
                  raise UndefinedIdentifier(
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
                None => raise UndefinedIdentifier("elem $\{name}", self.loc())
              }
            _ => 0
          }
          TableInit(first, elem_idx)
        }
        _ =>
          // One argument: first was elem index, table defaults to 0
          TableInit(0, first)
      }
    }
    "memory.size" => MemorySize(self.parse_optional_memidx())
    "memory.grow" => MemoryGrow(self.parse_optional_memidx())
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
          MemoryInit(memidx, dataidx)
        }
        _ =>
          // One index: it's dataidx, memidx defaults to 0
          MemoryInit(0, first_idx)
      }
    }
    "memory.copy" => {
      let dst = self.parse_optional_memidx()
      let src = self.parse_optional_memidx()
      MemoryCopy(dst, src)
    }
    "memory.fill" => MemoryFill(self.parse_optional_memidx())
    "data.drop" => DataDrop(self.parse_data_idx())
    "elem.drop" => ElemDrop(self.parse_elem_idx())

    // GC instructions - struct operations
    "struct.new" => StructNew(self.parse_type_idx())
    "struct.new_default" => StructNewDefault(self.parse_type_idx())
    "struct.get" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      StructGet(type_idx, field_idx)
    }
    "struct.get_s" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      StructGetS(type_idx, field_idx)
    }
    "struct.get_u" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      StructGetU(type_idx, field_idx)
    }
    "struct.set" => {
      let type_idx = self.parse_type_idx()
      let field_idx = self.parse_field_idx(type_idx)
      StructSet(type_idx, field_idx)
    }

    // GC instructions - array operations
    "array.new" => ArrayNew(self.parse_type_idx())
    "array.new_default" => ArrayNewDefault(self.parse_type_idx())
    "array.new_fixed" => {
      let type_idx = self.parse_type_idx()
      let len = self.parse_u32()
      ArrayNewFixed(type_idx, len)
    }
    "array.get" => ArrayGet(self.parse_type_idx())
    "array.get_s" => ArrayGetS(self.parse_type_idx())
    "array.get_u" => ArrayGetU(self.parse_type_idx())
    "array.set" => ArraySet(self.parse_type_idx())
    "array.len" => ArrayLen
    "array.fill" => ArrayFill(self.parse_type_idx())
    "array.copy" => {
      let dst_type_idx = self.parse_type_idx()
      let src_type_idx = self.parse_type_idx()
      ArrayCopy(dst_type_idx, src_type_idx)
    }
    "array.new_data" => {
      let type_idx = self.parse_type_idx()
      let data_idx = self.parse_data_idx()
      ArrayNewData(type_idx, data_idx)
    }
    "array.new_elem" => {
      let type_idx = self.parse_type_idx()
      let elem_idx = self.parse_elem_idx()
      ArrayNewElem(type_idx, elem_idx)
    }
    "array.init_data" => {
      let type_idx = self.parse_type_idx()
      let data_idx = self.parse_data_idx()
      ArrayInitData(type_idx, data_idx)
    }
    "array.init_elem" => {
      let type_idx = self.parse_type_idx()
      let elem_idx = self.parse_elem_idx()
      ArrayInitElem(type_idx, elem_idx)
    }

    // GC instructions - i31
    "ref.i31" => RefI31
    "i31.get_s" => I31GetS
    "i31.get_u" => I31GetU

    // GC instructions - type conversion
    "any.convert_extern" => AnyConvertExtern
    "extern.convert_any" => ExternConvertAny

    // GC instructions - type testing and casting
    "ref.test" => {
      // ref.test <heaptype> or ref.test (ref <heaptype>)
      // Uses RefTestNull if the type is nullable, otherwise RefTest
      let (vt, nullable) = self.parse_cast_type()
      if nullable {
        RefTestNull(vt)
      } else {
        RefTest(vt)
      }
    }
    "ref.cast" => {
      // ref.cast <heaptype> or ref.cast (ref <heaptype>)
      // Uses RefCastNull if the type is nullable, otherwise RefCast
      let (vt, nullable) = self.parse_cast_type()
      if nullable {
        RefCastNull(vt)
      } else {
        RefCast(vt)
      }
    }
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_atomic_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match atomic_subopcode(kw) {
    Some(3) => Atomic(3, 0, 0, 0L)
    Some(subopcode) =>
      parse_mem_arg(
        self,
        fn(memory, align, offset) { Atomic(subopcode, memory, align, offset) },
        default_align=if subopcode == 2 {
          3
        } else if subopcode < 3 {
          2
        } else {
          [2, 3, 0, 1, 0, 1, 2][(subopcode - 0x10) % 7]
        },
      )
    None => raise InvalidInstruction(kw, self.loc())
  }
}

///|
fn atomic_subopcode(keyword : String) -> Int? {
  match keyword {
    "memory.atomic.notify" => Some(0)
    "memory.atomic.wait32" => Some(1)
    "memory.atomic.wait64" => Some(2)
    "atomic.fence" => Some(3)
    "i32.atomic.load" => Some(16)
    "i64.atomic.load" => Some(17)
    "i32.atomic.load8_u" => Some(18)
    "i32.atomic.load16_u" => Some(19)
    "i64.atomic.load8_u" => Some(20)
    "i64.atomic.load16_u" => Some(21)
    "i64.atomic.load32_u" => Some(22)
    "i32.atomic.store" => Some(23)
    "i64.atomic.store" => Some(24)
    "i32.atomic.store8" => Some(25)
    "i32.atomic.store16" => Some(26)
    "i64.atomic.store8" => Some(27)
    "i64.atomic.store16" => Some(28)
    "i64.atomic.store32" => Some(29)
    "i32.atomic.rmw.add" => Some(30)
    "i64.atomic.rmw.add" => Some(31)
    "i32.atomic.rmw8.add_u" => Some(32)
    "i32.atomic.rmw16.add_u" => Some(33)
    "i64.atomic.rmw8.add_u" => Some(34)
    "i64.atomic.rmw16.add_u" => Some(35)
    "i64.atomic.rmw32.add_u" => Some(36)
    "i32.atomic.rmw.sub" => Some(37)
    "i64.atomic.rmw.sub" => Some(38)
    "i32.atomic.rmw8.sub_u" => Some(39)
    "i32.atomic.rmw16.sub_u" => Some(40)
    "i64.atomic.rmw8.sub_u" => Some(41)
    "i64.atomic.rmw16.sub_u" => Some(42)
    "i64.atomic.rmw32.sub_u" => Some(43)
    "i32.atomic.rmw.and" => Some(44)
    "i64.atomic.rmw.and" => Some(45)
    "i32.atomic.rmw8.and_u" => Some(46)
    "i32.atomic.rmw16.and_u" => Some(47)
    "i64.atomic.rmw8.and_u" => Some(48)
    "i64.atomic.rmw16.and_u" => Some(49)
    "i64.atomic.rmw32.and_u" => Some(50)
    "i32.atomic.rmw.or" => Some(51)
    "i64.atomic.rmw.or" => Some(52)
    "i32.atomic.rmw8.or_u" => Some(53)
    "i32.atomic.rmw16.or_u" => Some(54)
    "i64.atomic.rmw8.or_u" => Some(55)
    "i64.atomic.rmw16.or_u" => Some(56)
    "i64.atomic.rmw32.or_u" => Some(57)
    "i32.atomic.rmw.xor" => Some(58)
    "i64.atomic.rmw.xor" => Some(59)
    "i32.atomic.rmw8.xor_u" => Some(60)
    "i32.atomic.rmw16.xor_u" => Some(61)
    "i64.atomic.rmw8.xor_u" => Some(62)
    "i64.atomic.rmw16.xor_u" => Some(63)
    "i64.atomic.rmw32.xor_u" => Some(64)
    "i32.atomic.rmw.xchg" => Some(65)
    "i64.atomic.rmw.xchg" => Some(66)
    "i32.atomic.rmw8.xchg_u" => Some(67)
    "i32.atomic.rmw16.xchg_u" => Some(68)
    "i64.atomic.rmw8.xchg_u" => Some(69)
    "i64.atomic.rmw16.xchg_u" => Some(70)
    "i64.atomic.rmw32.xchg_u" => Some(71)
    "i32.atomic.rmw.cmpxchg" => Some(72)
    "i64.atomic.rmw.cmpxchg" => Some(73)
    "i32.atomic.rmw8.cmpxchg_u" => Some(74)
    "i32.atomic.rmw16.cmpxchg_u" => Some(75)
    "i64.atomic.rmw8.cmpxchg_u" => Some(76)
    "i64.atomic.rmw16.cmpxchg_u" => Some(77)
    "i64.atomic.rmw32.cmpxchg_u" => Some(78)
    _ => None
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
          let offset_str = StringBuilder::StringBuilder()
          for i in 7..<s.length() {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          offset = parse_u64(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::StringBuilder()
          for i in 6..<s.length() {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_u32(align_str.to_string())
          if a == 0 || (a & (a - 1)) != 0 {
            raise UnexpectedToken(
              "alignment must be a nonzero power of two",
              parser.loc(),
            )
          }
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
  default_align? : Int = 0,
) -> @types.Instruction raise WatError {
  let mut memidx = 0
  let mut offset = 0L
  let mut align = default_align
  // Multi-memory: Parse optional memory index (e.g., $mem1 or 0)
  match parser.current.token {
    Id(name) => {
      // Memory name like $mem1 - resolve to index
      memidx = parser.resolve_memory(name)
      parser.advance()
    }
    Number(s) => {
      // Non-lane memory instructions have no other numeric immediate here.
      memidx = parse_int(s)
      parser.advance()
    }
    _ => ()
  }
  // Parse optional offset=N and align=N
  while true {
    match parser.current.token {
      Keyword(s) =>
        if s.has_prefix("offset=") {
          let offset_str = StringBuilder::StringBuilder()
          for i in 7..<s.length() {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          // Use parse_u64 for offset (memory64 supports 64-bit offsets)
          offset = parse_u64(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::StringBuilder()
          for i in 6..<s.length() {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_u32(align_str.to_string())
          if a == 0 || (a & (a - 1)) != 0 {
            raise UnexpectedToken(
              "alignment must be a nonzero power of two",
              parser.loc(),
            )
          }
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
  let mut v = n.reinterpret_as_uint()
  let mut r = 0
  while v > 1U {
    v = v / 2U
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
    return TypeIndex(idx)
  }
  if params.length() > 0 {
    // Has parameters - use InlineType
    InlineType(params, results)
  } else if results.length() == 0 {
    Empty
  } else if results.length() == 1 {
    Value(results[0])
  } else {
    MultiValue(results)
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
    // Only if against function types
    if subtype.composite is Func(ft) &&
      ft.params.length() == params.length() &&
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
  }
  // No match found, create a new type
  let new_type = @types.FuncType::{ params, results, }
  let idx = self.types.length()
  self.types.push(@types.SubType::from_func(new_type))
  // Implicit type is its own rec group
  self.type_rec_groups.push(idx)
  idx
}

///|
fn Parser::parse_resume_handlers(
  self : Parser,
) -> Array[@types.ResumeHandler] raise WatError {
  let handlers : Array[@types.ResumeHandler] = []
  while self.current.token == LParen {
    let saved = (
      self.lexer.pos,
      self.lexer.line,
      self.lexer.column,
      self.lexer.token_start_line,
      self.lexer.token_start_column,
    )
    let next = self.lexer.next_token()
    self.lexer.pos = saved.0
    self.lexer.line = saved.1
    self.lexer.column = saved.2
    self.lexer.token_start_line = saved.3
    self.lexer.token_start_column = saved.4
    if next.token != Keyword("on") {
      break
    }
    self.advance()
    self.advance()
    let tag = self.parse_tag_idx()
    if self.current.token == Keyword("switch") {
      self.advance()
      handlers.push(OnSwitch(tag))
    } else {
      handlers.push(OnLabel(tag, self.parse_label_idx()))
    }
    self.expect_rparen()
  }
  handlers
}
