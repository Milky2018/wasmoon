// Control Flow Instructions - block, loop, if, branch, and misc

///|
/// Get the number of results for a block type
fn ExecContext::block_arity(self : ExecContext, bt : @types.BlockType) -> Int {
  match bt {
    Empty => 0
    Value(_) => 1
    TypeIndex(idx) => self.instance.types[idx].results.length()
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
    TypeIndex(idx) => self.instance.types[idx].params.length()
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
      self.exec_block(body) catch {
        BranchWith(0, values) =>
          // Push the branch values back onto the stack
          for v in values {
            self.stack.push(v)
          }
        BranchWith(n, values) => raise BranchWith(n - 1, values)
        e => raise e
      }
      // After block ends normally, top `arity` values remain on stack
      ignore(arity)
    }
    // Loop: execute body, br 0 jumps to start
    Loop(bt, body) => {
      let param_arity = self.block_param_arity(bt)
      loop () {
        _ =>
          try {
            self.exec_block(body)
            break () // Normal exit
          } catch {
            BranchWith(0, values) => {
              // For loop, branch to start: push params back and continue
              for v in values {
                self.stack.push(v)
              }
              continue ()
            }
            BranchWith(n, values) => raise BranchWith(n - 1, values)
            e => raise e
          }
      }
      ignore(param_arity)
    }
    // If-else: pop condition, execute appropriate branch
    If(bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      let body = if cond != 0 { then_body } else { else_body }
      let arity = self.block_arity(bt)
      self.exec_block(body) catch {
        BranchWith(0, values) =>
          for v in values {
            self.stack.push(v)
          }
        BranchWith(n, values) => raise BranchWith(n - 1, values)
        e => raise e
      }
      ignore(arity)
    }
    // Unconditional branch - need to collect values for multi-value
    Br(depth) => raise BranchWith(depth, [])
    // Conditional branch
    BrIf(depth) => {
      let cond = self.stack.pop_i32()
      if cond != 0 {
        raise BranchWith(depth, [])
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
      raise BranchWith(depth, [])
    }
    // Unreachable trap
    Unreachable => raise @runtime.RuntimeError::Unreachable
    // Select: ternary operator
    Select => {
      let cond = self.stack.pop_i32()
      let val2 = self.stack.pop()
      let val1 = self.stack.pop()
      self.stack.push(if cond != 0 { val1 } else { val2 })
    }
    Nop => ()
    Return => raise Return
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
    self.exec_instr(instr)
  }
}

///|
/// Execute function body (catches Return signal)
fn ExecContext::exec_expr(
  self : ExecContext,
  instrs : Array[@types.Instruction],
) -> Unit raise {
  self.exec_block(instrs) catch {
    Return => () // Normal function return
    e => raise e
  }
}
