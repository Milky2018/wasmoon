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
    Block(bt, body) => self.enter_control(bt, body, BlockControl)
    Loop(bt, body) => self.enter_control(bt, body, LoopControl)
    If(bt, then_body, else_body) => {
      let cond = self.stack.pop_i32()
      self.enter_control(
        bt,
        if cond != 0 {
          then_body
        } else {
          else_body
        },
        BlockControl,
      )
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
    ExecBlockCompleted => self.finish_result_stack(stack_height, arity)
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
