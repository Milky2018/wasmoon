// Function Call Instructions - call and call_indirect

///|
/// Execute call instruction: direct function call
fn ExecContext::exec_call(self : ExecContext, func_idx : Int) -> Unit raise {
  // Get the function type from the module instance
  // func_addrs[func_idx] gives us the store address
  let store_addr = self.instance.func_addrs[func_idx]
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.get_func_type(type_idx)

  // Pop arguments from stack in reverse order
  let num_params = func_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get the function instance and execute
  let func_inst = self.store.get_func_inst(store_addr)
  self.call_func_inst_with_context(
    store_addr,
    func_inst,
    args,
    func_type.results.length(),
  )
}

///|
/// Execute call_indirect instruction: indirect function call through table
fn ExecContext::exec_call_indirect(
  self : ExecContext,
  type_idx : Int,
  table_idx : Int,
) -> Unit raise {
  // Get the table address from instance
  let table_addr = self.instance.table_addrs[table_idx]
  let table = self.store.get_table(table_addr)

  // Pop the function index from the stack (i64 for table64, i32 otherwise)
  let func_ref_idx = if table.is_table64() {
    self.stack.pop_i64().to_int()
  } else {
    self.stack.pop_i32()
  }

  // Look up the function reference
  let elem = table.get(func_ref_idx)

  // The element should be a function reference
  let store_addr = match elem {
    FuncRef(idx) => idx
    Null => raise @runtime.UninitializedElement // Null function reference
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type
  let expected_type = self.instance.get_func_type(type_idx)

  // Type checking using unified subtyping API
  // For call_indirect, the actual function type must be a subtype of the expected type
  let owner_idx = self.store.get_func_owner_idx(store_addr)
  let same_module = owner_idx >= 0 && owner_idx == self.instance.store_idx
  let actual_type_idx = self.store.get_func_type_idx(store_addr)
  if same_module {
    // Same module: use subtyping context for proper rec group handling
    let ctx = @types.SubtypingContext::same_module(
      self.instance.types,
      rec_groups=self.instance.type_rec_groups,
      canonical=self.instance.canonical_type_indices,
    )
    if not(ctx.is_subtype(actual_type_idx, type_idx)) {
      raise @runtime.IndirectCallTypeMismatch
    }
  } else {
    // Cross-module or ownerless function call
    let owner = self.store.get_func_owner(store_addr)
    match owner {
      Some(o) => {
        // Cross-module call: use cross-module subtyping
        let ctx = @types.SubtypingContext::cross_module(
          o.types, // actual function's types
          self.instance.types, // expected type's types
          rec_groups1=o.type_rec_groups,
          rec_groups2=self.instance.type_rec_groups,
          canonical1=o.canonical_type_indices,
          canonical2=self.instance.canonical_type_indices,
        )
        if not(ctx.is_subtype(actual_type_idx, type_idx)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
      None => {
        // Ownerless function (host function or directly allocated):
        // Use direct type comparison (host functions don't have subtyping)
        let actual_type = self.store.get_func_type(store_addr)
        if not(@types.func_types_equal(expected_type, actual_type)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
    }
  }

  // Pop arguments from stack in reverse order
  let num_params = expected_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get the function instance and execute
  let func_inst = self.store.get_func_inst(store_addr)
  self.call_func_inst_with_context(
    store_addr,
    func_inst,
    args,
    expected_type.results.length(),
  )
}

///|
/// Execute call_ref instruction: call function through typed reference
fn ExecContext::exec_call_ref(self : ExecContext, type_idx : Int) -> Unit raise {
  // Pop the function reference from the stack
  let func_ref = self.stack.pop()

  // The function reference should be a FuncRef value, or Null
  let store_addr = match func_ref {
    FuncRef(addr) => addr
    Null => raise @runtime.RuntimeError::Unreachable // Null function reference traps
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type
  let expected_type = self.instance.get_func_type(type_idx)

  // Verify type matches using subtyping
  let actual_type_idx = self.store.get_func_type_idx(store_addr)
  let owner_idx = self.store.get_func_owner_idx(store_addr)
  let same_module = owner_idx >= 0 && owner_idx == self.instance.store_idx
  if same_module {
    // Same module: use subtyping context
    let ctx = @types.SubtypingContext::same_module(
      self.instance.types,
      rec_groups=self.instance.type_rec_groups,
      canonical=self.instance.canonical_type_indices,
    )
    if not(ctx.is_subtype(actual_type_idx, type_idx)) {
      raise @runtime.IndirectCallTypeMismatch
    }
  } else {
    let owner = self.store.get_func_owner(store_addr)
    match owner {
      Some(o) => {
        // Cross-module call: use cross-module subtyping
        let ctx = @types.SubtypingContext::cross_module(
          o.types,
          self.instance.types,
          rec_groups1=o.type_rec_groups,
          rec_groups2=self.instance.type_rec_groups,
          canonical1=o.canonical_type_indices,
          canonical2=self.instance.canonical_type_indices,
        )
        if not(ctx.is_subtype(actual_type_idx, type_idx)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
      None => {
        // Ownerless function: use direct type comparison
        let actual_type = self.store.get_func_type(store_addr)
        if not(@types.func_types_equal(expected_type, actual_type)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
    }
  }

  // Pop arguments from stack in reverse order
  let num_params = expected_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get the function instance and execute
  let func_inst = self.store.get_func_inst(store_addr)
  self.call_func_inst_with_context(
    store_addr,
    func_inst,
    args,
    expected_type.results.length(),
  )
}

///|
/// Call a function instance with proper context switching for cross-module calls
fn ExecContext::call_func_inst_with_context(
  self : ExecContext,
  store_addr : Int,
  func_inst : @runtime.FuncInst,
  args : Array[@types.Value],
  num_results : Int,
) -> Unit raise {
  match func_inst {
    WasmFunc(code) =>
      // Check if this function belongs to a different module
      match self.store.get_func_owner(store_addr) {
        Some(owner_instance) =>
          // Call with the owner's context
          self.call_wasm_func_with_instance(
            owner_instance, code, args, num_results,
          )
        None =>
          // No registered owner, use current instance (backward compatibility)
          self.call_wasm_func(code, args, num_results)
      }
    HostFunc(host_fn) => {
      // Call host function directly
      let results = host_fn(args)
      // Push results onto the stack
      for result in results {
        self.stack.push(result)
      }
    }
  }
}

///|
/// Call a WASM function with a specific module instance context
/// Uses a loop to handle tail calls without growing the native stack (wasmtime style)
fn ExecContext::call_wasm_func_with_instance(
  self : ExecContext,
  target_instance : @runtime.ModuleInstance,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int,
) -> Unit raise {
  // Save the current instance for restoration
  let saved_instance = self.instance

  // Tail call loop - wasmtime style
  // Instead of recursively calling the target, we loop here
  let mut current_instance = target_instance
  let mut current_func = func
  let mut current_args = args
  let mut should_continue = true
  while should_continue {
    // Set the context to the target function's module
    self.instance = current_instance

    // Create locals array: params + local variables
    let locals : Array[@types.Value] = []

    // Add parameters first
    for arg in current_args {
      locals.push(arg)
    }

    // Add local variables (initialized to default values)
    for local_type in current_func.locals {
      locals.push(
        match local_type {
          I32 => I32(0)
          I64 => I64(0L)
          F32 => F32(0.0)
          F64 => F64(0.0)
          FuncRef => Null
          ExternRef => Null
          V128 => V128(Bytes::make(16, b'\x00'))
          _ => Null
        },
      )
    }

    // Create and push frame
    let frame = @runtime.Frame::new(-1, locals, num_results)
    self.push_frame(frame)

    // Execute function body, catching TailCall to loop instead of recurse
    try {
      self.exec_expr(current_func.body)
      // Normal return: pop frame and exit loop
      self.pop_frame()
      should_continue = false
    } catch {
      ControlSignal::TailCall(store_addr, func_inst, tail_args, _) => {
        // Tail call detected! Pop current frame and loop with new target
        self.pop_frame()

        // Get the new target function
        match func_inst {
          WasmFunc(code) => {
            // Get the owner instance for the target function
            match self.store.get_func_owner(store_addr) {
              Some(owner) => current_instance = owner
              None => current_instance = saved_instance
            }
            current_func = code
            current_args = tail_args
            // Continue loop
            should_continue = true
          }
          HostFunc(host_fn) => {
            // Host function - call directly and exit
            let results = host_fn(tail_args)
            for result in results {
              self.stack.push(result)
            }
            should_continue = false
          }
        }
      }
      e => {
        // Other exceptions: pop frame then propagate
        self.pop_frame()
        self.instance = saved_instance
        raise e
      }
    }
  }

  // Restore original instance
  self.instance = saved_instance
}

///|
/// Call a WASM function
/// Also uses a loop to handle tail calls
fn ExecContext::call_wasm_func(
  self : ExecContext,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int,
) -> Unit raise {
  // Call with instance loop to handle tail calls
  self.call_wasm_func_with_instance(self.instance, func, args, num_results)
}

// ============ Tail Call Operations ============
// Tail calls replace the current frame instead of pushing a new one
// This keeps call depth constant, enabling deep recursion

///|
/// Execute a direct tail call (return_call)
/// Wasmtime style: raise TailCall signal instead of recursively calling
pub fn ExecContext::exec_tail_call(
  self : ExecContext,
  func_idx : Int,
) -> Unit raise {
  // Get function address and type from current module
  let store_addr = self.instance.func_addrs[func_idx]
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.get_func_type(type_idx)

  // Pop arguments from stack into array (in reverse order)
  let num_params = func_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get function instance
  let func_inst = self.store.get_func_inst(store_addr)

  // Raise TailCall signal - the loop in call_wasm_func_with_instance will handle it
  raise ControlSignal::TailCall(
    store_addr,
    func_inst,
    args,
    func_type.results.length(),
  )
}

///|
/// Execute an indirect tail call (return_call_indirect)
/// Includes type checking like call_indirect
pub fn ExecContext::exec_tail_call_indirect(
  self : ExecContext,
  type_idx : Int,
  table_idx : Int,
) -> Unit raise {
  // Get table
  let table_addr = self.instance.table_addrs[table_idx]
  let table = self.store.get_table(table_addr)

  // Pop the function reference index from stack (i64 for table64, i32 otherwise)
  let func_ref_idx = if table.is_table64() {
    self.stack.pop_i64().to_int()
  } else {
    self.stack.pop_i32()
  }

  // Look up the element
  let elem = table.get(func_ref_idx)

  // The element should be a function reference
  let store_addr = match elem {
    FuncRef(idx) => idx
    Null => raise @runtime.UninitializedElement
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type and verify type matches using subtyping
  let expected_type = self.instance.get_func_type(type_idx)
  let actual_type_idx = self.store.get_func_type_idx(store_addr)
  let owner_idx = self.store.get_func_owner_idx(store_addr)
  let same_module = owner_idx >= 0 && owner_idx == self.instance.store_idx
  if same_module {
    // Same module: use subtyping context
    let ctx = @types.SubtypingContext::same_module(
      self.instance.types,
      rec_groups=self.instance.type_rec_groups,
      canonical=self.instance.canonical_type_indices,
    )
    if not(ctx.is_subtype(actual_type_idx, type_idx)) {
      raise @runtime.IndirectCallTypeMismatch
    }
  } else {
    let owner = self.store.get_func_owner(store_addr)
    match owner {
      Some(o) => {
        // Cross-module call: use cross-module subtyping
        let ctx = @types.SubtypingContext::cross_module(
          o.types,
          self.instance.types,
          rec_groups1=o.type_rec_groups,
          rec_groups2=self.instance.type_rec_groups,
          canonical1=o.canonical_type_indices,
          canonical2=self.instance.canonical_type_indices,
        )
        if not(ctx.is_subtype(actual_type_idx, type_idx)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
      None => {
        // Ownerless function: use direct type comparison
        let actual_type = self.store.get_func_type(store_addr)
        if not(@types.func_types_equal(expected_type, actual_type)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
    }
  }

  // Pop arguments from stack
  let num_params = expected_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get the function instance
  let func_inst = self.store.get_func_inst(store_addr)

  // Raise TailCall signal - the loop will handle it
  raise ControlSignal::TailCall(
    store_addr,
    func_inst,
    args,
    expected_type.results.length(),
  )
}

///|
/// Execute a reference tail call (return_call_ref)
/// Takes a function reference from the stack and tail-calls it
pub fn ExecContext::exec_tail_call_ref(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  // Pop the function reference from stack
  let func_ref = self.stack.pop()

  // The function reference should be a FuncRef value, or Null
  let store_addr = match func_ref {
    FuncRef(addr) => addr
    Null => raise @runtime.RuntimeError::Unreachable
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type and verify type matches using subtyping
  let expected_type = self.instance.get_func_type(type_idx)
  let actual_type_idx = self.store.get_func_type_idx(store_addr)
  let owner_idx = self.store.get_func_owner_idx(store_addr)
  let same_module = owner_idx >= 0 && owner_idx == self.instance.store_idx
  if same_module {
    // Same module: use subtyping context
    let ctx = @types.SubtypingContext::same_module(
      self.instance.types,
      rec_groups=self.instance.type_rec_groups,
      canonical=self.instance.canonical_type_indices,
    )
    if not(ctx.is_subtype(actual_type_idx, type_idx)) {
      raise @runtime.IndirectCallTypeMismatch
    }
  } else {
    let owner = self.store.get_func_owner(store_addr)
    match owner {
      Some(o) => {
        // Cross-module call: use cross-module subtyping
        let ctx = @types.SubtypingContext::cross_module(
          o.types,
          self.instance.types,
          rec_groups1=o.type_rec_groups,
          rec_groups2=self.instance.type_rec_groups,
          canonical1=o.canonical_type_indices,
          canonical2=self.instance.canonical_type_indices,
        )
        if not(ctx.is_subtype(actual_type_idx, type_idx)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
      None => {
        // Ownerless function: use direct type comparison
        let actual_type = self.store.get_func_type(store_addr)
        if not(@types.func_types_equal(expected_type, actual_type)) {
          raise @runtime.IndirectCallTypeMismatch
        }
      }
    }
  }

  // Pop arguments from stack
  let num_params = expected_type.params.length()
  let args : Array[@types.Value] = Array::make(num_params, @types.Value::I32(0))
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Get the function instance
  let func_inst = self.store.get_func_inst(store_addr)

  // Raise TailCall signal - the loop will handle it
  raise ControlSignal::TailCall(
    store_addr,
    func_inst,
    args,
    expected_type.results.length(),
  )
}
