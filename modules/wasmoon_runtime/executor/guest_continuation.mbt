///|
priv suberror GuestEmbeddingSignal {
  GuestEmbeddingPause(SuspensionReason, @runtime.GuestContinuationBody)
}

///|
fn guest_outcome_values(
  outcome : ResumableCallOutcome,
) -> Array[@types.Value] raise {
  match outcome {
    Returned(values) => values
    Suspended(reason, continuation) => {
      let body = guest_resumption_body(continuation)
      match reason {
        GuestEffect(effect) =>
          raise @runtime.GuestContinuationSignal::GuestContinuationYield(
            effect, body,
          )
        _ => raise GuestEmbeddingPause(reason, body)
      }
    }
  }
}

///|
fn guest_resumption_body(
  continuation : ExecutionContinuation,
) -> @runtime.GuestContinuationBody {
  let leases = match continuation.captured {
    Some(captured) => [captured.root_lease]
    None => []
  }
  @runtime.GuestContinuationBody::new(
    fn(input) raise {
      guard continuation.captured is Some(captured) else {
        raise @runtime.RuntimeError::ContinuationAlreadyConsumed
      }
      captured.context.guest_input = Some(input)
      let outcome = continuation.continue_unchecked() catch {
        error => raise captured.context.guest_body_failure(error)
      }
      guest_outcome_values(outcome)
    },
    fn() { continuation.cancel() },
    leases~,
  )
}

///|
fn ExecContext::guest_delivery(
  self : ExecContext,
) -> @runtime.GuestContinuationInput raise {
  guard self.guest_input is Some(input) else {
    raise @runtime.RuntimeError::TypeMismatch
  }
  self.guest_input = None
  input
}

///|
fn ExecContext::accept_guest_delivery(self : ExecContext) -> Unit raise {
  match self.guest_delivery() {
    Values(values) =>
      for value in values {
        self.stack.push(value)
      }
    Exception(tag, values) => raise ThrowException(tag, values)
  }
}

///|
fn ExecContext::guest_function_type(
  self : ExecContext,
  index : Int32,
) -> @types.FuncType {
  guard self.instance.types[index].composite is Cont(function) else {
    abort("validated instruction requires continuation type")
  }
  self.instance.validated_func_type_at(function)
}

///|
fn ExecContext::pop_guest_body(
  self : ExecContext,
) -> @runtime.GuestContinuationBody raise {
  match self.stack.pop() {
    ContRef(handle) => self.store.take_guest_continuation(handle)
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
fn ExecContext::resume_guest_body(
  self : ExecContext,
  initial_body : @runtime.GuestContinuationBody,
  initial_input : @runtime.GuestContinuationInput,
  handlers : ArrayView[@types.ResumeHandler],
) -> Unit raise {
  let mut body = initial_body
  let mut input = initial_input
  while true {
    let values = self.invoke_guest_body(body, input) catch {
      @runtime.GuestContinuationSignal::GuestContinuationYield(
        effect,
        suspended
      ) => {
        match effect {
          Suspend(tag, values) =>
            for handler in handlers {
              if handler is OnLabel(tag_index, label) &&
                self.instance.tag_addrs[tag_index] == tag {
                let handle = self.store.put_guest_continuation(suspended)
                let branch_values = values.copy()
                branch_values.push(ContRef(handle))
                raise BranchWith(label, branch_values)
              }
            }
          Switch(tag, target, args) => {
            let matched = handlers.any(fn(handler) {
              match handler {
                OnSwitch(tag_index) => self.instance.tag_addrs[tag_index] == tag
                _ => false
              }
            })
            if matched {
              let handle = self.store.put_guest_continuation(suspended)
              let values = args.copy()
              values.push(ContRef(handle))
              body = target
              input = Values(values)
              continue
            }
          }
        }
        self.guest_pending = Some(suspended)
        self.set_base_resume_action(GuestEffect(effect), fn(context) raise {
          context.guest_pending = None
          context.resume_guest_body(
            suspended,
            context.guest_delivery(),
            handlers,
          )
        })
        raise ExecutionSuspended
      }
      GuestEmbeddingPause(reason, suspended) => {
        self.guest_pending = Some(suspended)
        self.set_base_resume_action(reason, fn(context) raise {
          context.guest_pending = None
          context.resume_guest_body(suspended, Values([]), handlers)
        })
        raise ExecutionSuspended
      }
      error => raise error
    }
    for value in values {
      self.stack.push(value)
    }
    return
  }
}

///|
fn ExecContext::exec_guest_continuation(
  self : ExecContext,
  instruction : @types.Instruction,
) -> Unit raise {
  match instruction {
    ContNew(_) => {
      let address = match self.stack.pop() {
        FuncRef(address) => address
        Null => raise @runtime.RuntimeError::NullReference
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
      let store = self.store
      let instance = self.instance
      let cancel = self.cancel.map(fn(poller) { poller.callback })
      let classify_suspension = match self.suspension_classifier {
        Some(classifier) => classifier.classify
        None => fn(_) { None }
      }
      let async_host_driver = self.async_host_driver
      let cooperative = self.cooperative
      let cooperative_quantum = self.cooperative_quantum
      let capture_diagnostics = self.capture_diagnostics
      let function = store.get_func_inst(address)
      let arity = store.get_func_type(address).results.length()
      let body = @runtime.GuestContinuationBody::new(
        fn(input) raise {
          let args = match input {
            Values(values) => values
            Exception(tag, values) => raise ThrowException(tag, values)
          }
          let context = ExecContext(
            store,
            instance,
            cancel~,
            classify_suspension~,
            async_host_driver~,
            cooperative~,
            cooperative_quantum~,
            capture_diagnostics~,
          )
          let outcome = try
            context.call_func_inst_with_context(address, function, args, arity)
          catch {
            ExecutionSuspended => suspended_outcome(context, arity)
            error => {
              context.discard_captured_execution()
              raise context.guest_body_failure(error)
            }
          } noraise {
            _ => {
              let values = context.collect_call_results(arity)
              context.discard_captured_execution()
              Returned(values)
            }
          }
          guest_outcome_values(outcome)
        },
        fn() { () },
      )
      self.stack.push(ContRef(store.put_guest_continuation(body)))
    }
    ContBind(before, after) => {
      let body = self.pop_guest_body()
      let count = self.guest_function_type(before).params.length() -
        self.guest_function_type(after).params.length()
      let bound = self.stack.pop_n(count)
      let roots = body.gc_roots()
      for value in bound {
        roots.push(value)
      }
      let rebound = @runtime.GuestContinuationBody::new(
        fn(input) raise {
          let input = match input {
            Values(values) => {
              let all = bound.copy()
              for value in values {
                all.push(value)
              }
              @runtime.GuestContinuationInput::Values(all)
            }
            Exception(_, _) => input
          }
          (body.run)(input)
        },
        fn() { (body.cancel)() },
        roots~,
        leases=body.gc_root_leases(),
      )
      self.stack.push(ContRef(self.store.put_guest_continuation(rebound)))
    }
    Suspend(index) => {
      let tag = self.instance.tag_addrs[index]
      let values = self.stack.pop_n(
        self.store.get_tag_type(tag).params.length(),
      )
      self.suspension_roots = values.copy()
      self.set_base_resume_action(GuestEffect(Suspend(tag, values)), fn(
        context,
      ) raise {
        context.accept_guest_delivery()
      })
      raise ExecutionSuspended
    }
    Resume(index, handlers) => {
      let body = self.pop_guest_body()
      let args = self.stack.pop_n(
        self.guest_function_type(index).params.length(),
      )
      self.resume_guest_body(body, Values(args), handlers)
    }
    ResumeThrow(_, tag_index, handlers) => {
      let body = self.pop_guest_body()
      let tag = self.instance.tag_addrs[tag_index]
      let values = self.stack.pop_n(
        self.store.get_tag_type(tag).params.length(),
      )
      self.resume_guest_body(body, Exception(tag, values), handlers)
    }
    ResumeThrowRef(_, handlers) => {
      let body = self.pop_guest_body()
      let exception = match self.stack.pop() {
        ExnRef(index) => self.store.get_exn(index)
        Null => {
          (body.cancel)()
          raise @runtime.RuntimeError::NullReference
        }
        _ => {
          (body.cancel)()
          raise @runtime.RuntimeError::TypeMismatch
        }
      }
      self.resume_guest_body(
        body,
        Exception(exception.tag_addr, exception.values),
        handlers,
      )
    }
    Switch(index, tag_index) => {
      let target = self.pop_guest_body()
      let args = self.stack.pop_n(
        self.guest_function_type(index).params.length() - 1,
      )
      let tag = self.instance.tag_addrs[tag_index]
      self.suspension_roots = args.copy()
      self.guest_pending = Some(target)
      self.set_base_resume_action(GuestEffect(Switch(tag, target, args)), fn(
        context,
      ) raise {
        context.accept_guest_delivery()
      })
      raise ExecutionSuspended
    }
    _ => abort("expected a guest continuation instruction")
  }
}

///|
fn ExecContext::discard_captured_execution(self : ExecContext) -> Unit {
  let pending = self.guest_pending
  self.guest_pending = None
  let action = self.resume_action
  self.resume_action = None
  if action is Some(action) {
    (action.cancel)()
  }
  if pending is Some(body) {
    (body.cancel)()
  }
  self.guest_input = None
  self.suspension_reason = None
  self.suspension_roots.clear()
  self.suspension_roots.shrink_to_fit()
  self.release_host_exception_root()
  self.execution.clear()
  self.execution.shrink_to_fit()
  self.frames.clear()
  self.frames.shrink_to_fit()
  self.current_frame = -1
  self.labels.clear()
  self.labels.shrink_to_fit()
  self.stack.clear()
}

///|
fn ExecContext::release_host_exception_root(self : ExecContext) -> Unit {
  if self.host_exception_root is Some(roots) {
    roots.release()
  }
  self.host_exception_root = None
}

///|
/// Guest continuation bodies cross an embedding callback boundary. Their
/// native nesting is bounded independently of each body's explicit guest stack.
fn ExecContext::invoke_guest_body(
  self : ExecContext,
  body : @runtime.GuestContinuationBody,
  input : @runtime.GuestContinuationInput,
) -> Array[@types.Value] raise {
  {
    errdefer (body.cancel)()
    self.store.enter_interpreter_boundary()
  }
  defer self.store.leave_interpreter_boundary()
  (body.run)(input) catch {
    GuestBodyFailed(error, frames) => {
      self.adopt_guest_failure(error, frames)
      raise error
    }
    error => raise error
  }
}
