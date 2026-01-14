// Control Flow Instructions - block, loop, if, branch, and misc

///|
/// Get the number of results for a block type
fn ExecContext::block_arity(self : ExecContext, bt : @types.BlockType) -> Int {
  match bt {
    Empty => 0
    Value(_) => 1
    MultiValue(types) => types.length()
    InlineType(_, results) => results.length()
    TypeIndex(idx) => self.instance.get_func_type(idx).results.length()
  }
}

///|
/// Get the number of params for a block type (used for loop branches)
fn ExecContext::block_param_arity(
  self : ExecContext,
  bt : @types.BlockType,
) -> Int {
  match bt {
    Empty => 0
    Value(_) => 0 // Single value blocks have no params
    MultiValue(_) => 0 // MultiValue blocks have no params (result-only)
    InlineType(params, _) => params.length()
    TypeIndex(idx) => self.instance.get_func_type(idx).params.length()
  }
}

///|
/// Execute control flow instruction
fn ExecContext::exec_control(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // Block: execute body, br 0 jumps to end
    Block(bt, body) => {
      let arity = self.block_arity(bt)
      let stack_height = self.stack.size()
      self.push_label(false, arity) // Block branches use result arity
      let result = try? self.exec_block(body)
      self.pop_label()
      if !(result is Ok(_)) {
        match result {
          Ok(_) => ()
          Err(BranchWith(0, values)) => {
            // Restore stack to block entry point (discard intermediate values)
            self.restore_stack_to(stack_height)
            // Push the branch values back onto the stack
            for v in values {
              self.stack.push(v)
            }
          }
          Err(BranchWith(n, values)) => raise BranchWith(n - 1, values)
          Err(e) => raise e
        }
      }
    }
    // Loop: execute body, br 0 jumps to start
    Loop(bt, body) => {
      let param_arity = self.block_param_arity(bt)
      let stack_height = self.stack.size()
      self.push_label(true, param_arity) // Loop branches use param arity
      loop () {
        _ => {
          let result = try? self.exec_block(body)
          match result {
            Ok(_) => {
              self.pop_label()
              break () // Normal exit
            }
            Err(BranchWith(0, values)) => {
              // For loop, branch to start: restore stack and push params back
              self.restore_stack_to(stack_height)
              for v in values {
                self.stack.push(v)
              }
              continue ()
            }
            Err(BranchWith(n, values)) => {
              self.pop_label()
              raise BranchWith(n - 1, values)
            }
            Err(e) => {
              self.pop_label()
              raise e
            }
          }
        }
      }
    }
    // If-else: pop condition, execute appropriate branch
    If(bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      let body = if cond != 0 { then_body } else { else_body }
      let arity = self.block_arity(bt)
      let stack_height = self.stack.size()
      self.push_label(false, arity) // If branches use result arity
      let result = try? self.exec_block(body)
      self.pop_label()
      match result {
        Ok(_) => () // Normal completion
        Err(BranchWith(0, values)) => {
          self.restore_stack_to(stack_height)
          for v in values {
            self.stack.push(v)
          }
        }
        Err(BranchWith(n, values)) => raise BranchWith(n - 1, values)
        Err(e) => raise e
      }
    }
    // Unconditional branch - collect values based on target block arity
    Br(depth) => {
      let arity = self.get_branch_arity(depth)
      let values = self.stack.pop_n(arity)
      raise BranchWith(depth, values)
    }
    // Conditional branch
    BrIf(depth) => {
      let cond = self.stack.pop_i32()
      if cond != 0 {
        let arity = self.get_branch_arity(depth)
        let values = self.stack.pop_n(arity)
        raise BranchWith(depth, values)
      }
    }
    // Branch if null
    BrOnNull(depth) => {
      let ref_val = self.stack.pop()
      match ref_val {
        Null => {
          // Reference is null, branch
          let arity = self.get_branch_arity(depth)
          let values = self.stack.pop_n(arity)
          raise BranchWith(depth, values)
        }
        _ =>
          // Reference is not null, push it back and continue
          self.stack.push(ref_val)
      }
    }
    // Branch if non-null
    BrOnNonNull(depth) => {
      let ref_val = self.stack.pop()
      match ref_val {
        Null =>
          // Reference is null, continue without pushing anything
          ()
        _ => {
          // Reference is not null, branch with the reference included
          // The target block expects arity values, the ref is the last one
          let arity = self.get_branch_arity(depth)
          // Pop arity-1 values from stack (ref is already popped and will be added)
          let stack_values = if arity > 1 {
            self.stack.pop_n(arity - 1)
          } else {
            []
          }
          // Branch values = stack_values + ref
          stack_values.push(ref_val)
          raise BranchWith(depth, stack_values)
        }
      }
    }
    // Table-driven branch
    BrTable(labels, default) => {
      let idx = self.stack.pop_i32()
      let depth = if idx >= 0 && idx < labels.length() {
        labels[idx]
      } else {
        default
      }
      let arity = self.get_branch_arity(depth)
      let values = self.stack.pop_n(arity)
      raise BranchWith(depth, values)
    }
    // Unreachable trap
    Unreachable => raise @runtime.RuntimeError::Unreachable
    // Select: ternary operator
    Select | SelectTyped(_) => {
      let cond = self.stack.pop_i32()
      let val2 = self.stack.pop()
      let val1 = self.stack.pop()
      self.stack.push(if cond != 0 { val1 } else { val2 })
    }
    Nop => ()
    Return => raise ControlSignal::Return
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute a block body (can raise ControlSignal)
fn ExecContext::exec_block(
  self : ExecContext,
  instrs : Array[@types.Instruction],
) -> Unit raise {
  for instr in instrs {
    self.exec_instr(instr) catch {
      @runtime.TypeMismatch => {
        @logger.debug("type mismatch at instr: \{instr}")
        raise @runtime.TypeMismatch
      }
      e => raise e
    }
  }
}

///|
/// Execute function body (catches Return signal and branch to function)
fn ExecContext::exec_expr(
  self : ExecContext,
  instrs : Array[@types.Instruction],
) -> Unit raise {
  self.exec_block(instrs) catch {
    Return => () // Explicit return
    BranchWith(0, values) =>
      // Branch to function (br 0 from outermost block) acts like return
      // Push the return values back onto the stack
      for v in values {
        self.stack.push(v)
      }
    e => raise e
  }
}
