// Control Flow Instructions - block, loop, if, branch, and misc

///|
/// Get the number of results for a block type
fn ExecContext::block_arity(self : ExecContext, bt : @types.BlockType) -> Int {
  match bt {
    Empty => 0
    Value(_) => 1
    MultiValue(types) => types.length()
    InlineType(_, results) => results.length()
    TypeIndex(idx) => self.instance.validated_func_type_at(idx).results.length()
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
    TypeIndex(idx) => self.instance.validated_func_type_at(idx).params.length()
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
      // Blocks with params consume their params from the *outer* stack (typed blocks).
      // Track the stack height after popping params so br/end unwinding discards them.
      let param_arity = self.block_param_arity(bt)
      let params = self.stack.pop_n(param_arity)
      let stack_height = self.stack.size()
      for v in params {
        self.stack.push(v)
      }
      self.push_label(false, arity) // Block branches use result arity
      let result = try self.exec_block(body) catch {
        ExecutionSuspended => {
          self.append_resume_handler(fn(result) raise {
            self.finish_block_control(result, arity, stack_height)
          })
          raise ExecutionSuspended
        }
        error => ExecBlockRaised(error)
      } noraise {
        _ => ExecBlockCompleted
      }
      self.finish_block_control(result, arity, stack_height)
    }
    // Loop: execute body, br 0 jumps to start
    Loop(bt, body) => {
      let result_arity = self.block_arity(bt)
      let param_arity = self.block_param_arity(bt)
      let params = self.stack.pop_n(param_arity)
      let stack_height = self.stack.size()
      for v in params {
        self.stack.push(v)
      }
      self.push_label(true, param_arity) // Loop branches use param arity
      self.exec_loop_body(body, result_arity, stack_height)
    }
    // If-else: pop condition, execute appropriate branch
    If(bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      let body = if cond != 0 { then_body } else { else_body }
      let arity = self.block_arity(bt)
      let param_arity = self.block_param_arity(bt)
      let params = self.stack.pop_n(param_arity)
      let stack_height = self.stack.size()
      for v in params {
        self.stack.push(v)
      }
      self.push_label(false, arity) // If branches use result arity
      let result = try self.exec_block(body) catch {
        ExecutionSuspended => {
          self.append_resume_handler(fn(result) raise {
            self.finish_block_control(result, arity, stack_height)
          })
          raise ExecutionSuspended
        }
        error => ExecBlockRaised(error)
      } noraise {
        _ => ExecBlockCompleted
      }
      self.finish_block_control(result, arity, stack_height)
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
fn ExecContext::finish_block_control(
  self : ExecContext,
  result : ExecBlockResult,
  arity : Int,
  stack_height : Int,
) -> Unit raise {
  self.pop_label()
  match result {
    ExecBlockCompleted => {
      let results = self.stack.pop_n(arity)
      self.restore_stack_to(stack_height)
      for value in results {
        self.stack.push(value)
      }
    }
    ExecBlockRaised(BranchWith(0, values)) => {
      self.restore_stack_to(stack_height)
      for value in values {
        self.stack.push(value)
      }
    }
    ExecBlockRaised(BranchWith(depth, values)) =>
      raise BranchWith(depth - 1, values)
    ExecBlockRaised(error) => raise error
  }
}

///|
fn ExecContext::exec_loop_body(
  self : ExecContext,
  body : Array[@types.Instruction],
  result_arity : Int,
  stack_height : Int,
) -> Unit raise {
  while true {
    self.check_cancellation()
    let result = try self.exec_block(body) catch {
      ExecutionSuspended => {
        self.append_resume_handler(fn(result) raise {
          self.finish_suspended_loop_iteration(
            result, body, result_arity, stack_height,
          )
        })
        raise ExecutionSuspended
      }
      error => ExecBlockRaised(error)
    } noraise {
      _ => ExecBlockCompleted
    }
    match result {
      ExecBlockCompleted => {
        self.finish_loop(result, result_arity, stack_height)
        return
      }
      ExecBlockRaised(BranchWith(0, values)) => {
        self.restore_stack_to(stack_height)
        for value in values {
          self.stack.push(value)
        }
      }
      _ => {
        self.finish_loop(result, result_arity, stack_height)
        return
      }
    }
  }
}

///|
fn ExecContext::finish_suspended_loop_iteration(
  self : ExecContext,
  result : ExecBlockResult,
  body : Array[@types.Instruction],
  result_arity : Int,
  stack_height : Int,
) -> Unit raise {
  match result {
    ExecBlockRaised(BranchWith(0, values)) => {
      self.restore_stack_to(stack_height)
      for value in values {
        self.stack.push(value)
      }
      self.exec_loop_body(body, result_arity, stack_height)
    }
    _ => self.finish_loop(result, result_arity, stack_height)
  }
}

///|
fn ExecContext::finish_loop(
  self : ExecContext,
  result : ExecBlockResult,
  result_arity : Int,
  stack_height : Int,
) -> Unit raise {
  match result {
    ExecBlockCompleted => {
      self.pop_label()
      let results = self.stack.pop_n(result_arity)
      self.restore_stack_to(stack_height)
      for value in results {
        self.stack.push(value)
      }
    }
    ExecBlockRaised(BranchWith(0, _)) =>
      abort("loop continuation did not resume the next iteration")
    ExecBlockRaised(BranchWith(depth, values)) => {
      self.pop_label()
      raise BranchWith(depth - 1, values)
    }
    ExecBlockRaised(error) => {
      self.pop_label()
      raise error
    }
  }
}

///|
/// Execute a block body (can raise ControlSignal)
fn ExecContext::exec_block(
  self : ExecContext,
  instrs : Array[@types.Instruction],
) -> Unit raise {
  self.exec_block_from(instrs, 0)
}

///|
fn ExecContext::exec_block_from(
  self : ExecContext,
  instrs : Array[@types.Instruction],
  start : Int,
) -> Unit raise {
  for i in start..<instrs.length() {
    let instr = instrs[i]
    self.exec_instr(instr) catch {
      ExecutionSuspended => {
        self.append_resume_suffix(fn() raise {
          self.exec_block_from(instrs, i + 1)
        })
        raise ExecutionSuspended
      }
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
  let result = try self.exec_block(instrs) catch {
    ExecutionSuspended => {
      self.append_resume_handler(fn(result) raise {
        self.finish_exec_expr(result)
      })
      raise ExecutionSuspended
    }
    error => ExecBlockRaised(error)
  } noraise {
    _ => ExecBlockCompleted
  }
  self.finish_exec_expr(result)
}

///|
fn ExecContext::finish_exec_expr(
  self : ExecContext,
  result : ExecBlockResult,
) -> Unit raise {
  match result {
    ExecBlockCompleted => ()
    ExecBlockRaised(Return) => () // Explicit return
    ExecBlockRaised(BranchWith(0, values)) =>
      // Branch to function (br 0 from outermost block) acts like return
      // Push the return values back onto the stack
      for v in values {
        self.stack.push(v)
      }
    ExecBlockRaised(error) => raise error
  }
}
