// Entry Trampoline Generation (Standard)
// Generates JIT trampolines for calling WASM functions from host code
//
// On-demand loading:
// 1. Generate the trampoline as IR
// 2. Compile through the normal pipeline (lower → regalloc → emit)
// 3. Let the register allocator decide which registers to use
//
// The trampoline:
// 1. Accepts a simple interface from C (vmctx, values_vec, func_ptr)
// 2. Loads arguments from values_vec into correct registers per JIT ABI
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
///   Each slot is 8 bytes (int64_t), except V128 which uses 16 bytes (2 slots)
///
/// Parameters:
///   param_types: Array of parameter types (0=I32, 1=I64, 2=F32, 3=F64, 4=V128)
///   result_types: Array of result types
///
/// Approach: generate IR, then compile through the
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
  let allocated = @regalloc.allocate_registers_backtracking(vcode_func)

  // Emit machine code
  emit_function(allocated)
}

///|
/// Generate IR function for the trampoline
/// Approach: express the trampoline in IR, not machine code
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
  // V128 args are passed as two I64 values (low then high) to avoid alignment issues
  // with LDR Q which requires 16-byte aligned offsets
  let wasm_args : Array[@ir.Value] = []
  let wasm_arg_types : Array[@ir.Type] = []
  let mut current_offset = 0
  for param_type in param_types {
    let ir_type = type_code_to_ir_type(param_type)
    wasm_arg_types.push(ir_type)
    match ir_type {
      @ir.Type::V128 => {
        // Load low 64 bits
        let offset_low = builder.iconst_i64(current_offset.to_int64())
        let low = builder.load_ptr(@ir.Type::I64, values_vec, offset_low)
        // Load high 64 bits
        let offset_high = builder.iconst_i64((current_offset + 8).to_int64())
        let high = builder.load_ptr(@ir.Type::I64, values_vec, offset_high)
        // Construct V128 from two I64 values
        let vec = builder.v128_splat64(low)
        let arg = builder.v128_replace64(vec, high, 1)
        wasm_args.push(arg)
        current_offset = current_offset + 16
      }
      _ => {
        let offset = builder.iconst_i64(current_offset.to_int64())
        let arg = builder.load_ptr(ir_type, values_vec, offset)
        wasm_args.push(arg)
        current_offset = current_offset + 8
      }
    }
  }
  // Save total args size for result offset calculation
  let args_total_size = current_offset

  // Determine result types for CallPtr
  let wasm_result_types : Array[@ir.Type] = []
  for result_type in result_types {
    wasm_result_types.push(type_code_to_ir_type(result_type))
  }

  // Emit CallPtr instruction
  let results = builder.call_ptr(func_ptr, vmctx, wasm_args, wasm_result_types)

  // Store results back to values_vec
  // V128 is stored as two I64 values (low then high) to avoid alignment issues
  // with STR Q which requires 16-byte aligned offsets
  let mut result_offset = args_total_size
  for i, result_val in results {
    let ir_type = wasm_result_types[i]
    match ir_type {
      @ir.Type::V128 => {
        // Extract and store low 64 bits
        let low = builder.v128_extract64(result_val, 0)
        let offset_low = builder.iconst_i64(result_offset.to_int64())
        builder.store_ptr(@ir.Type::I64, values_vec, low, offset_low)
        // Extract and store high 64 bits
        let high = builder.v128_extract64(result_val, 1)
        let offset_high = builder.iconst_i64((result_offset + 8).to_int64())
        builder.store_ptr(@ir.Type::I64, values_vec, high, offset_high)
        result_offset = result_offset + 16
      }
      _ => {
        let offset = builder.iconst_i64(result_offset.to_int64())
        builder.store_ptr(ir_type, values_vec, result_val, offset)
        result_offset = result_offset + 8
      }
    }
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
    4 => @ir.Type::V128
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

///|
pub const TYPE_V128 : Int = 4
