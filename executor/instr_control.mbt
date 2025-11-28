// Control Flow Instructions - block, loop, if, branch, and misc

///|
/// Execute control flow instruction
fn ExecContext::exec_control(
  self : ExecContext,
  instr : @wasmoon.Instruction,
) -> Unit raise {
  match instr {
    // Block: execute body, br 0 jumps to end
    Block(_bt, body) =>
      self.exec_block(body) catch {
        @runtime.Branch(0) => () // Branch to this block = exit
        @runtime.Branch(n) => raise @runtime.Branch(n - 1) // Propagate
        e => raise e // Re-raise other errors
      }
    // Loop: execute body, br 0 jumps to start
    Loop(_bt, body) =>
      loop () {
        _ =>
          try {
            self.exec_block(body)
            break () // Normal exit
          } catch {
            @runtime.Branch(0) => continue () // Restart loop
            @runtime.Branch(n) => raise @runtime.Branch(n - 1)
            e => raise e
          }
      }
    // If-else: pop condition, execute appropriate branch
    If(_bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      let body = if cond != 0 { then_body } else { else_body }
      self.exec_block(body) catch {
        @runtime.Branch(0) => () // Branch to this if = exit
        @runtime.Branch(n) => raise @runtime.Branch(n - 1)
        e => raise e
      }
    }
    // Unconditional branch
    Br(depth) => raise @runtime.Branch(depth)
    // Conditional branch
    BrIf(depth) => {
      let cond = self.stack.pop_i32()
      if cond != 0 {
        raise @runtime.Branch(depth)
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
      raise @runtime.Branch(depth)
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
    Return => raise @runtime.Return
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute a block body (can raise ControlSignal)
fn ExecContext::exec_block(
  self : ExecContext,
  instrs : Array[@wasmoon.Instruction],
) -> Unit raise {
  for instr in instrs {
    self.exec_instr(instr)
  }
}

///|
/// Execute function body (catches Return signal)
fn ExecContext::exec_expr(
  self : ExecContext,
  instrs : Array[@wasmoon.Instruction],
) -> Unit raise {
  self.exec_block(instrs) catch {
    @runtime.Return => () // Normal function return
    e => raise e
  }
}
