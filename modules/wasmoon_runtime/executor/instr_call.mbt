// Function calls share argument staging and type verification. Reference
// and table lookup retain their different null and bounds traps.

///|
fn ExecContext::invoke_callee(
  self : ExecContext,
  address : Int32,
  signature : @types.FuncType,
  tail~ : Bool = false,
) -> Unit raise {
  let args : Array[@types.Value] = Array::make(
    signature.params.length(),
    I32(0),
  )
  for i = args.length() - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }
  let func = self.store.get_func_inst(address)
  let result_count = signature.results.length()
  if tail {
    raise ControlSignal::TailCall(address, func, args, result_count)
  }
  self.call_func_inst_with_context(address, func, args, result_count)
}

///|
fn ExecContext::checked_callee_signature(
  self : ExecContext,
  address : Int32,
  expected_index : Int32,
) -> @types.FuncType raise {
  let expected = self.instance.validated_func_type_at(expected_index)
  let owner_index = self.store.get_func_owner_idx(address)
  let actual_index = self.store.get_func_type_idx(address)
  let matches = if owner_index >= 0 &&
    owner_index == self.instance.store_index() {
    @types.SubtypingContext::same_module(
      self.instance.types,
      rec_groups=self.instance.type_rec_groups,
      canonical=self.instance.canonical_type_indices,
    ).is_subtype(actual_index, expected_index)
  } else {
    match self.store.get_func_owner(address) {
      Some(owner) =>
        @types.SubtypingContext::cross_module(
          owner.types,
          self.instance.types,
          rec_groups1=owner.type_rec_groups,
          rec_groups2=self.instance.type_rec_groups,
          canonical1=owner.canonical_type_indices,
          canonical2=self.instance.canonical_type_indices,
        ).is_subtype(actual_index, expected_index)
      None =>
        @types.func_types_equal(expected, self.store.get_func_type(address))
    }
  }
  if !matches {
    raise @runtime.RuntimeError::IndirectCallTypeMismatch
  }
  expected
}

///|
fn ExecContext::pop_table_callee(
  self : ExecContext,
  table_index : Int32,
) -> Int32 raise {
  let table = self.store.get_table(self.instance.table_addrs[table_index])
  let index = if table.is_table64() {
    self.stack.pop_i64()
  } else {
    self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
  }
  let element = table.get_at(index) catch {
    OutOfBoundsTableAccess => raise @runtime.RuntimeError::UndefinedElement
    error => raise error
  }
  match element {
    FuncRef(address) => address
    Null => raise @runtime.RuntimeError::UninitializedElement
    _ => raise @runtime.RuntimeError::IndirectCallTypeMismatch
  }
}

///|
fn ExecContext::pop_reference_callee(self : ExecContext) -> Int32 raise {
  match self.stack.pop() {
    FuncRef(address) => address
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::IndirectCallTypeMismatch
  }
}

///|
fn ExecContext::exec_call(self : ExecContext, func_idx : Int32) -> Unit raise {
  let address = self.instance.func_addrs[func_idx]
  let signature = self.instance.validated_func_type_at(
    self.instance.func_type_indices[func_idx],
  )
  self.invoke_callee(address, signature)
}

///|
fn ExecContext::exec_call_indirect(
  self : ExecContext,
  type_idx : Int32,
  table_idx : Int32,
) -> Unit raise {
  let address = self.pop_table_callee(table_idx)
  self.invoke_callee(address, self.checked_callee_signature(address, type_idx))
}

///|
fn ExecContext::exec_call_ref(
  self : ExecContext,
  type_idx : Int32,
) -> Unit raise {
  let address = self.pop_reference_callee()
  self.invoke_callee(address, self.checked_callee_signature(address, type_idx))
}

///|
/// Call a function instance with proper context switching for cross-module calls
fn ExecContext::call_func_inst_with_context(
  self : ExecContext,
  store_addr : Int32,
  func_inst : @runtime.FuncInst,
  args : Array[@types.Value],
  num_results : Int32,
) -> Unit raise {
  match func_inst {
    WasmFunc(code) => {
      // Check if this function belongs to a different module
      let owner = self.store.get_func_owner(store_addr)
      if owner is Some(owner_instance) {
        // Call with the owner's context
        self.call_wasm_func_with_instance(
          owner_instance, code, args, num_results, store_addr,
        )
      } else {
        // Imported host-created function instances may not have an owning module.
        self.call_wasm_func(code, args, num_results, store_addr)
      }
    }
    HostFunc(_) | ThrowingHostFunc(_) =>
      self.invoke_host_func(store_addr, func_inst, self.instance, args)
    AsyncHostFunc(host_fn) =>
      self.invoke_async_host_func(store_addr, host_fn, self.instance, args)
  }
}

///|
fn ExecContext::invoke_host_func(
  self : ExecContext,
  store_addr : Int32,
  host_fn : @runtime.FuncInst,
  caller_instance : @runtime.ModuleInstance,
  args : Array[@types.Value],
) -> Unit raise {
  self.store.enter_interpreter_boundary()
  defer self.store.leave_interpreter_boundary()
  // Host code can collect or reenter the Store after arguments leave the stack.
  let roots = self.collect_gc_additional_roots()
  for value in args {
    roots.push(value)
  }
  let lease = self.store.pin_gc_roots(roots)
  defer lease.release()
  let caller = @runtime.Caller::Caller(self.store, caller_instance)
  let results = match host_fn.invoke_sync_host(caller, args) {
    HostCallReturned(values) => values
    HostCallThrown(tag, values, roots) => {
      self.host_exception_root = Some(roots)
      raise ThrowException(tag, values)
    }
    HostCallFailed(error) => {
      self.suspend_host_call(
        error,
        fn(context) raise {
          context.invoke_host_func(store_addr, host_fn, caller_instance, args)
        },
        roots=args,
      )
      return
    }
  }
  check_call_values(
    self.store,
    caller_instance,
    results,
    self.store.get_func_type(store_addr).results,
  )
  for result in results {
    self.stack.push(result)
  }
}

///|
fn ExecContext::invoke_async_host_func(
  self : ExecContext,
  store_addr : Int32,
  host_fn : @runtime.AsyncHostFunction,
  caller_instance : @runtime.ModuleInstance,
  args : Array[@types.Value],
) -> Unit raise {
  guard self.async_host_driver is Some(driver) else {
    raise InvocationSignal::HostInvocation(
      @runtime.RuntimeError::AsyncHostRequiresAsyncCall,
    )
  }
  self.store.enter_interpreter_boundary()
  defer self.store.leave_interpreter_boundary()
  // Host code can collect or reenter the Store after arguments leave the stack.
  let roots = self.collect_gc_additional_roots()
  for value in args {
    roots.push(value)
  }
  let lease = self.store.pin_gc_roots(roots)
  defer lease.release()
  let caller = @runtime.Caller::Caller(self.store, caller_instance)
  let poll = driver.poll(store_addr, host_fn, caller, args) catch {
    error => raise InvocationSignal::HostInvocation(error)
  }
  match poll {
    AsyncHostThrown(tag, values) => raise ThrowException(tag, values)
    AsyncHostReady(results) => {
      check_call_values(
        self.store,
        caller_instance,
        results,
        self.store.get_func_type(store_addr).results,
      )
      for result in results {
        self.stack.push(result)
      }
    }
    AsyncHostPending => {
      self.suspension_roots = args.copy()
      self.set_base_resume_action(
        HostCall(0L),
        fn(context) raise {
          context.invoke_async_host_func(
            store_addr, host_fn, caller_instance, args,
          )
        },
        cancel=fn() { driver.cancel() },
      )
      raise ExecutionSuspended
    }
  }
}

///|
fn ExecContext::call_wasm_func_with_instance(
  self : ExecContext,
  target_instance : @runtime.ModuleInstance,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int32,
  address : Int32,
) -> Unit raise {
  self.enter_function(target_instance, func, args, num_results, address)
  if !self.running {
    self.run_execution()
  }
}

///|
fn ExecContext::call_wasm_func(
  self : ExecContext,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int32,
  address : Int32,
) -> Unit raise {
  self.call_wasm_func_with_instance(
    self.instance,
    func,
    args,
    num_results,
    address,
  )
}

///|
/// The iterative execution stack replaces the current function at its boundary.
pub fn ExecContext::exec_tail_call(
  self : ExecContext,
  func_idx : Int32,
) -> Unit raise {
  let address = self.instance.func_addrs[func_idx]
  let signature = self.instance.validated_func_type_at(
    self.instance.func_type_indices[func_idx],
  )
  self.invoke_callee(address, signature, tail=true)
}

///|
pub fn ExecContext::exec_tail_call_indirect(
  self : ExecContext,
  type_idx : Int32,
  table_idx : Int32,
) -> Unit raise {
  let address = self.pop_table_callee(table_idx)
  self.invoke_callee(
    address,
    self.checked_callee_signature(address, type_idx),
    tail=true,
  )
}

///|
pub fn ExecContext::exec_tail_call_ref(
  self : ExecContext,
  type_idx : Int32,
) -> Unit raise {
  let address = self.pop_reference_callee()
  self.invoke_callee(
    address,
    self.checked_callee_signature(address, type_idx),
    tail=true,
  )
}
