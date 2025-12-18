// Entry Trampoline Generation (Cranelift-style)
// Generates JIT trampolines for calling WASM functions from host code
//
// Following Cranelift's approach:
// 1. Generate the trampoline as IR
// 2. Compile through the normal pipeline (lower → regalloc → emit)
// 3. Let the register allocator decide which registers to use
//
// The trampoline:
// 1. Accepts a simple interface from C (vmctx, values_vec, func_ptr)
// 2. Loads arguments from values_vec into correct registers per v3 ABI
// 3. Calls the target WASM function
// 4. Stores results back to values_vec
// 5. Returns trap code (0 = success)

///|
/// Generate an entry trampoline for a specific function signature
///
/// Trampoline signature (C calling convention):
///   int trampoline(vmctx: X0, values_vec: X1, func_ptr: X2) -> trap_code
///
/// The values_vec layout:
///   [arg0, arg1, ..., argN, result0, result1, ..., resultM]
///   Each slot is 8 bytes (int64_t)
///
/// Parameters:
///   param_types: Array of parameter types (0=I32, 1=I64, 2=F32, 3=F64)
///   result_types: Array of result types
///
/// This follows Cranelift's approach: generate IR, then compile through the
/// normal pipeline. The register allocator will automatically choose callee-saved
/// registers when needed, eliminating the need for hardcoded X23/X24.
pub fn emit_entry_trampoline(
  param_types : Array[Int],
  result_types : Array[Int],
) -> MachineCode {
  // Generate trampoline as IR using IRBuilder
  let ir_func = generate_trampoline_ir(param_types, result_types)

  // Compile through the normal pipeline
  let vcode_func = @lower.lower_function(ir_func)
  let allocated = @lower.allocate_registers_aarch64(vcode_func)

  // Emit machine code
  emit_function(allocated)
}

///|
/// Generate IR function for the trampoline
/// This is the Cranelift way: express the trampoline in IR, not machine code
fn generate_trampoline_ir(
  param_types : Array[Int],
  result_types : Array[Int],
) -> @ir.Function {
  let builder = @ir.IRBuilder::new("trampoline")

  // Trampoline parameters: vmctx, values_vec, func_ptr
  let vmctx = builder.add_param(@ir.Type::I64)
  let values_vec = builder.add_param(@ir.Type::I64)
  let func_ptr = builder.add_param(@ir.Type::I64)

  // Result: trap code (i64 for simplicity)
  builder.add_result(@ir.Type::I64)

  // Create entry block and switch to it
  let entry = builder.create_block()
  builder.switch_to_block(entry)

  // Load arguments from values_vec
  let wasm_args : Array[@ir.Value] = []
  let wasm_arg_types : Array[@ir.Type] = []
  for i, param_type in param_types {
    let ir_type = type_code_to_ir_type(param_type)
    wasm_arg_types.push(ir_type)
    let offset = builder.iconst_i64((i * 8).to_int64())
    let arg = builder.load_ptr(ir_type, values_vec, offset)
    wasm_args.push(arg)
  }

  // Determine result types for CallPtr
  let wasm_result_types : Array[@ir.Type] = []
  for result_type in result_types {
    wasm_result_types.push(type_code_to_ir_type(result_type))
  }

  // Emit CallPtr instruction
  // v3 ABI: callee_vmctx = caller_vmctx = vmctx (same module)
  let results = builder.call_ptr(
    func_ptr, vmctx, // callee_vmctx
     vmctx, // caller_vmctx
     wasm_args, wasm_result_types,
  )

  // Store results back to values_vec
  let results_base_offset = param_types.length() * 8
  for i, result_val in results {
    let ir_type = wasm_result_types[i]
    let offset = builder.iconst_i64((results_base_offset + i * 8).to_int64())
    builder.store_ptr(ir_type, values_vec, result_val, offset)
  }

  // Return 0 (success)
  let zero = builder.iconst_i64(0L)
  builder.return_([zero])
  builder.get_function()
}

///|
/// Convert type code to IR type
fn type_code_to_ir_type(code : Int) -> @ir.Type {
  match code {
    0 => @ir.Type::I32
    1 => @ir.Type::I64
    2 => @ir.Type::F32
    3 => @ir.Type::F64
    _ => @ir.Type::I64 // Default
  }
}

///|
/// Type codes for parameter/result types
pub const TYPE_I32 : Int = 0

///|
pub const TYPE_I64 : Int = 1

///|
pub const TYPE_F32 : Int = 2

///|
pub const TYPE_F64 : Int = 3
