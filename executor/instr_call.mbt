// Function Call Instructions - call and call_indirect

///|
/// Execute call instruction: direct function call
fn ExecContext::exec_call(self : ExecContext, func_idx : Int) -> Unit raise {
  // Get the function type from the module instance
  // funcs[func_idx] gives us the type index
  let type_idx = self.instance.func_addrs[func_idx]
  let func_type = self.instance.types[type_idx]
  let func = self.store.get_func(func_idx)

  // Pop arguments from stack in reverse order
  let num_params = func_type.params.length()
  let args : Array[@wasmoon.Value] = Array::make(
    num_params,
    @wasmoon.Value::I32(0),
  )
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Execute the function
  self.call_func_internal(func_idx, func, args, func_type.results.length())
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

  // Get the table and look up the function reference
  let table = self.store.get_table(table_idx)
  let elem = table.get(func_ref_idx)

  // The element should be a function reference
  let func_idx = match elem {
    FuncRef(idx) => idx
    _ => raise @runtime.IndirectCallTypeMismatch
  }

  // Get the expected type and the function
  let expected_type = self.instance.types[type_idx]
  let func = self.store.get_func(func_idx)

  // In a full implementation, we'd verify the function's actual type matches expected_type
  // For now, we trust the types match

  // Pop arguments from stack in reverse order
  let num_params = expected_type.params.length()
  let args : Array[@wasmoon.Value] = Array::make(
    num_params,
    @wasmoon.Value::I32(0),
  )
  for i = num_params - 1; i >= 0; i = i - 1 {
    args[i] = self.stack.pop()
  }

  // Execute the function
  self.call_func_internal(func_idx, func, args, expected_type.results.length())
}

///|
/// Internal function to execute a function call
fn ExecContext::call_func_internal(
  self : ExecContext,
  func_idx : Int,
  func : @wasmoon.FunctionCode,
  args : Array[@wasmoon.Value],
  num_results : Int,
) -> Unit raise {
  // Create locals array: params + local variables
  let locals : Array[@wasmoon.Value] = []

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

  // Create and push frame
  let frame = @runtime.Frame::new(func_idx, locals, num_results)
  self.push_frame(frame)

  // Execute function body
  self.exec_expr(func.body)

  // Pop frame
  self.pop_frame()
}
