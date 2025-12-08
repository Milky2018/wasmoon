// Function Call Instructions - call and call_indirect

///|
/// Execute call instruction: direct function call
fn ExecContext::exec_call(self : ExecContext, func_idx : Int) -> Unit raise {
  // Get the function type from the module instance
  // func_addrs[func_idx] gives us the store address
  let store_addr = self.instance.func_addrs[func_idx]
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.types[type_idx]

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
  // Pop the function index from the stack
  let func_ref_idx = self.stack.pop_i32()

  // Get the table address from instance and look up the function reference
  let table_addr = self.instance.table_addrs[table_idx]
  let table = self.store.get_table(table_addr)
  let elem = table.get(func_ref_idx)

  // The element should be a function reference
  let store_addr = match elem {
    FuncRef(idx) => idx
    Null => raise @runtime.UninitializedElement // Null function reference
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type
  let expected_type = self.instance.types[type_idx]

  // Get the actual function type and verify it matches
  let actual_type = self.store.get_func_type(store_addr)
  if expected_type != actual_type {
    raise @runtime.IndirectCallTypeMismatch
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
fn ExecContext::call_wasm_func_with_instance(
  self : ExecContext,
  target_instance : @runtime.ModuleInstance,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int,
) -> Unit raise {
  // Create locals array: params + local variables
  let locals : Array[@types.Value] = []

  // Add parameters first
  for arg in args {
    locals.push(arg)
  }

  // Add local variables (initialized to default values)
  for local_type in func.locals {
    locals.push(
      match local_type {
        I32 => I32(0)
        I64 => I64(0L)
        F32 => F32(0.0)
        F64 => F64(0.0)
        FuncRef => Null
        ExternRef => Null
        _ => Null
      },
    )
  }

  // Save current instance and switch to target instance
  let saved_instance = self.instance
  self.instance = target_instance

  // Create and push frame
  let frame = @runtime.Frame::new(-1, locals, num_results)
  self.push_frame(frame)

  // Execute function body
  self.exec_expr(func.body)

  // Pop frame
  self.pop_frame()

  // Restore original instance
  self.instance = saved_instance
}

///|
/// Call a WASM function
fn ExecContext::call_wasm_func(
  self : ExecContext,
  func : @types.FunctionCode,
  args : Array[@types.Value],
  num_results : Int,
) -> Unit raise {
  // Create locals array: params + local variables
  let locals : Array[@types.Value] = []

  // Add parameters first
  for arg in args {
    locals.push(arg)
  }

  // Add local variables (initialized to default values)
  for local_type in func.locals {
    locals.push(
      match local_type {
        I32 => I32(0)
        I64 => I64(0L)
        F32 => F32(0.0)
        F64 => F64(0.0)
        FuncRef => Null
        ExternRef => Null
        _ => Null
      },
    )
  }

  // Create and push frame (use -1 as func_idx since we don't track it here)
  let frame = @runtime.Frame::new(-1, locals, num_results)
  self.push_frame(frame)

  // Execute function body
  self.exec_expr(func.body)

  // Pop frame
  self.pop_frame()
}
