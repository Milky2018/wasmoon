///|
priv enum ExecutionKind {
  BlockControl
  LoopControl
  TryControl(Array[@types.CatchHandler])
  FunctionControl(@runtime.ModuleInstance, Int)
} derive(Debug)

///|
/// A structured instruction sequence and its exit action. Function entries
/// share the same stack, so call, branch, exception and resume all unwind here.
priv struct ExecutionFrame {
  body : Array[@types.Instruction]
  mut ip : Int
  kind : ExecutionKind
  arity : Int
  height : Int
} derive(Debug)

///|
fn ExecContext::check_control_capacity(self : ExecContext) -> Unit raise {
  if self.execution.length() >= self.store.interpreter_limits.max_controls {
    raise @runtime.StackOverflow
  }
}

///|
fn ExecContext::enter_control(
  self : ExecContext,
  bt : @types.BlockType,
  body : Array[@types.Instruction],
  kind : ExecutionKind,
) -> Unit raise {
  self.check_control_capacity()
  let arity = self.block_arity(bt)
  let params = self.block_param_arity(bt)
  let height = self.stack.size() - params
  self.push_label(
    kind is LoopControl,
    if kind is LoopControl {
      params
    } else {
      arity
    },
  )
  self.execution.push({ body, ip: 0, kind, arity, height, })
  if !self.running {
    self.run_execution()
  }
}

///|
fn ExecContext::enter_function(
  self : ExecContext,
  instance : @runtime.ModuleInstance,
  code : @types.FunctionCode,
  args : Array[@types.Value],
  arity : Int,
) -> Unit raise {
  self.check_cancellation()
  self.check_control_capacity()
  if self.frames.length() >= self.store.interpreter_limits.max_frames {
    raise @runtime.CallStackExhausted
  }
  // Reserve before allocating locals, including SIMD values.
  self.stack.reserve(args.length())
  {
    errdefer self.stack.release(args.length())
    self.stack.reserve(code.locals.length())
  }
  let locals = args.copy()
  for typ in code.locals {
    locals.push(
      match typ {
        I32 => I32(0)
        I64 => I64(0L)
        F32 => F32(0.0)
        F64 => F64(0.0)
        V128 => V128(Bytes::make(16, b'\x00'))
        _ => Null
      },
    )
  }
  let saved = self.instance
  self.push_frame(@runtime.Frame::Frame(-1, locals, arity))
  self.instance = instance
  self.push_label(false, arity)
  self.execution.push({
    body: code.body,
    ip: 0,
    kind: FunctionControl(saved, locals.length()),
    arity,
    height: self.stack.size(),
  })
}

///|
fn ExecContext::finish_execution_frame(
  self : ExecContext,
  frame : ExecutionFrame,
  result : ExecBlockResult,
) -> Unit raise {
  match frame.kind {
    BlockControl | LoopControl =>
      self.finish_block_control(result, frame.arity, frame.height)
    TryControl(handlers) => {
      self.finish_try_table(result, handlers, frame.height)
      if result is ExecBlockCompleted {
        let values = self.stack.pop_n(frame.arity)
        self.restore_stack_to(frame.height)
        for value in values {
          self.stack.push(value)
        }
      }
    }
    FunctionControl(saved, locals) => {
      let caller = self.instance
      self.pop_label()
      self.pop_frame()
      self.stack.release(locals)
      self.instance = saved
      match result {
        ExecBlockCompleted | ExecBlockRaised(Return) => {
          let values = self.stack.pop_n(frame.arity)
          self.restore_stack_to(frame.height)
          for value in values {
            self.stack.push(value)
          }
        }
        ExecBlockRaised(BranchWith(0, values)) => {
          self.restore_stack_to(frame.height)
          for value in values {
            self.stack.push(value)
          }
        }
        ExecBlockRaised(TailCall(address, function, args, arity)) => {
          self.restore_stack_to(frame.height)
          match function {
            WasmFunc(code) => {
              let owner = self.store.get_func_owner(address).unwrap_or(caller)
              self.enter_function(owner, code, args, arity)
            }
            HostFunc(host) => self.invoke_host_func(host, caller, args)
            AsyncHostFunc(host) =>
              self.invoke_async_host_func(address, host, caller, args)
          }
        }
        ExecBlockRaised(error) => {
          self.restore_stack_to(frame.height)
          raise error
        }
      }
    }
  }
}

///|
/// Drain the execution stack without recursive guest calls or closure chains.
fn ExecContext::run_execution(
  self : ExecContext,
  initial_error? : Error? = None,
) -> Unit raise {
  self.running = true
  defer {
    self.running = false
  }
  let mut pending = initial_error
  while self.execution.length() > 0 {
    let frame = self.execution[self.execution.length() - 1]
    let result = try {
      if pending is Some(error) {
        pending = None
        if frame.kind is LoopControl && error is BranchWith(0, values) {
          self.restore_stack_to(frame.height)
          for value in values {
            self.stack.push(value)
          }
          frame.ip = 0
          self.check_cancellation()
        } else {
          self.execution.pop() |> ignore
          self.finish_execution_frame(frame, ExecBlockRaised(error))
        }
      } else if frame.ip == frame.body.length() {
        self.execution.pop() |> ignore
        self.finish_execution_frame(frame, ExecBlockCompleted)
      } else {
        if self.cooperative {
          if self.instructions_left == 0 {
            self.instructions_left = 1024
            self.set_base_resume_action(CooperativeYield, fn() { () })
            raise ExecutionSuspended
          }
          self.instructions_left -= 1
        }
        let instruction = frame.body[frame.ip]
        frame.ip += 1
        self.exec_instr(instruction)
      }
    } catch {
      ExecutionSuspended => raise ExecutionSuspended
      error => Some(error)
    } noraise {
      _ => None
    }
    pending = result
  }
  if pending is Some(error) {
    raise error
  }
}

///|
fn ExecContext::resume_execution(
  self : ExecContext,
  action : ResumeAction,
) -> Unit raise {
  // A resumed operation may enqueue guest work or raise into an enclosing
  // exception handler. It must not recursively enter another dispatcher.
  self.running = true
  let error = try (action.run)() catch {
    ExecutionSuspended => {
      self.running = false
      raise ExecutionSuspended
    }
    error => Some(error)
  } noraise {
    _ => None
  }
  self.running = false
  self.run_execution(initial_error=error)
}
