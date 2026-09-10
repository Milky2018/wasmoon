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
          raise @runtime.GuestContinuationYield(effect, body)
        _ => raise GuestEmbeddingPause(reason, body)
      }
    }
  }
}

///|
fn guest_resumption_body(
  continuation : ExecutionContinuation,
) -> @runtime.GuestContinuationBody {
  {
    run: fn(input) raise {
      continuation.context.guest_input = Some(input)
      guest_outcome_values(continuation.continue_unchecked())
    },
    cancel: fn() { continuation.cancel() },
  }
}

///|
fn ExecContext::guest_delivery(
  self : ExecContext,
) -> @runtime.GuestContinuationInput raise {
  guard self.guest_input is Some(input) else { raise @runtime.TypeMismatch }
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
  index : Int,
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
    Null => raise @runtime.NullReference
    _ => raise @runtime.TypeMismatch
  }
}

///|
fn ExecContext::resume_guest_body(
  self : ExecContext,
  initial_body : @runtime.GuestContinuationBody,
  initial_input : @runtime.GuestContinuationInput,
  handlers : Array[@types.ResumeHandler],
) -> Unit raise {
  let mut body = initial_body
  let mut input = initial_input
  while true {
    let values = (body.run)(input) catch {
      @runtime.GuestContinuationYield(effect, suspended) => {
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
        self.set_base_resume_action(GuestEffect(effect), fn() raise {
          self.guest_pending = None
          self.resume_guest_body(suspended, self.guest_delivery(), handlers)
        })
        raise ExecutionSuspended
      }
      GuestEmbeddingPause(reason, suspended) => {
        self.guest_pending = Some(suspended)
        self.set_base_resume_action(reason, fn() raise {
          self.guest_pending = None
          self.resume_guest_body(suspended, Values([]), handlers)
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
        Null => raise @runtime.NullReference
        _ => raise @runtime.TypeMismatch
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
      let function = store.get_func_inst(address)
      let arity = store.func_types[address].results.length()
      let body : @runtime.GuestContinuationBody = {
        run: fn(input) raise {
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
          )
          let outcome = try
            context.call_func_inst_with_context(address, function, args, arity)
          catch {
            ExecutionSuspended => suspended_outcome(context, arity, [true])
            error => {
              context.discard_captured_execution()
              raise error
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
        cancel: fn() { () },
      }
      self.stack.push(ContRef(store.put_guest_continuation(body)))
    }
    ContBind(before, after) => {
      let body = self.pop_guest_body()
      let count = self.guest_function_type(before).params.length() -
        self.guest_function_type(after).params.length()
      let bound = self.stack.pop_n(count)
      let roots = self.store.pin_gc_roots(bound)
      let rebound : @runtime.GuestContinuationBody = {
        run: fn(input) raise {
          defer roots.release()
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
        cancel: fn() {
          roots.release()
          (body.cancel)()
        },
      }
      self.stack.push(ContRef(self.store.put_guest_continuation(rebound)))
    }
    Suspend(index) => {
      let tag = self.instance.tag_addrs[index]
      let values = self.stack.pop_n(
        self.store.get_tag_type(tag).params.length(),
      )
      self.suspension_roots = values.copy()
      self.set_base_resume_action(GuestEffect(Suspend(tag, values)), fn() raise {
        self.accept_guest_delivery()
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
          raise @runtime.NullReference
        }
        _ => {
          (body.cancel)()
          raise @runtime.TypeMismatch
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
      self.set_base_resume_action(GuestEffect(Switch(tag, target, args)), fn() raise {
        self.accept_guest_delivery()
      })
      raise ExecutionSuspended
    }
    _ => abort("expected a guest continuation instruction")
  }
}

///|
fn ExecContext::discard_captured_execution(self : ExecContext) -> Unit {
  if self.guest_pending is Some(body) {
    (body.cancel)()
  }
  self.guest_pending = None
  self.guest_input = None
  self.resume_action = None
  self.suspension_reason = None
  self.suspension_roots.clear()
  self.frames.clear()
  self.labels.clear()
  self.stack.clear()
}
