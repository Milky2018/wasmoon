// WASM to IR Translator
// Converts WebAssembly stack-based instructions to SSA-form IR

///|
/// Translator state for converting a single WASM function to IR
pub(all) struct Translator {
  builder : IRBuilder
  // Value stack - simulates WASM's operand stack
  value_stack : Array[Value]
  // Local variables - mutable in WASM, need SSA tracking
  locals : Array[Value]
  // Block stack for control flow
  block_stack : Array[BlockFrame]
  // Function types from the module
  func_types : Array[@types.FuncType]
  // Type indices for functions
  func_type_indices : Array[Int]
  // Number of imported functions
  num_imports : Int
  // Type indices for imported functions
  import_func_type_indices : Array[Int]
  // Unreachable code flag - set after br/return/unreachable
  // When true, skip translating instructions until block end
  mut is_unreachable : Bool
  // Return continuation block - lazily created when br/br_table jumps to function level
  mut return_continuation : Block?
  // Function result types - needed for lazy return continuation creation
  func_result_types : Array[Type]
  // Memory max pages limit (None = no limit)
  memory_max : Int?
  // Memory is 64-bit indexed (for memory64 proposal)
  // memory_is_64[i] = true if memory i uses 64-bit addresses
  memory_is_64 : Array[Bool]
  // Table base offsets for multi-table support
  // table_base_offsets[i] = starting index of table i in the flattened indirect_table
  table_base_offsets : Array[Int]
  // Table sizes for bounds checking
  // table_sizes[i] = number of elements in table i
  table_sizes : Array[Int]
  // Global variable types
  // global_types[i] = type of global variable i
  global_types : Array[@types.GlobalType]
  // Number of wasm function parameters (excludes vmctx params)
  // Used to distinguish params from locals in self.locals array
  num_wasm_params : Int
  // Canonical type indices for structural type equivalence
  // Structurally equivalent types map to the same canonical index
  canonical_type_indices : Array[Int]
  // Cross-module support: base index for this module's functions
  // All function indices are offset by this value (default 0)
  func_base : Int
  // Cross-module support: maps local import indices to global indices
  // If empty, uses local indices directly
  import_remap : Array[Int]
  // Module composite types (struct/array/func types) for GC support
  module_types : Array[@types.SubType]
  // VMContext value (callee_vmctx parameter) for accessing runtime state
  vmctx : Value
  // Function environment for desugaring Wasm operations to IR primitives
  func_env : FuncEnvironment
  // Exception tags for catch handler dispatch
  tags : Array[@types.TagType]
  // Depth of nested try_table blocks - when > 0, need to spill locals before calls
  mut try_table_depth : Int
  // Table is 64-bit indexed (for table64 proposal)
  // table_is_64[i] = true if table i uses 64-bit indices
  table_is_64 : Array[Bool]
}

///|
/// Block frame for tracking control flow constructs
struct BlockFrame {
  block : Block // The continuation block
  result_types : Array[Type]
  // Stack height at block entry
  stack_height : Int
}

///|
pub fn Translator::new(
  name : String,
  func_type : @types.FuncType,
  locals : Array[@types.ValueType],
  func_types : Array[@types.FuncType],
  func_type_indices : Array[Int],
  num_imports : Int,
  import_func_type_indices : Array[Int],
  memory_max? : Int? = None,
  memory_is_64? : Array[Bool] = [],
  tables? : Array[@types.Table] = [],
  global_types? : Array[@types.GlobalType] = [],
  type_rec_groups? : Array[Int] = [],
  func_base? : Int = 0,
  import_remap? : Array[Int] = [],
  module_types? : Array[@types.SubType] = [],
  tags? : Array[@types.TagType] = [],
) -> Translator {
  let builder = IRBuilder::new(name)
  // Following Cranelift: add vmctx as explicit params
  // - params[0] = callee_vmctx (X0)
  // - params[1] = caller_vmctx (X1)
  // These are referenced for desugaring global/table/memory operations
  let vmctx = builder.add_param(Type::I64) // callee_vmctx
  builder.add_param(Type::I64) |> ignore // caller_vmctx

  // Create function environment for desugaring Wasm operations
  let func_env = FuncEnvironment::new(global_types)

  // Add wasm function parameters (starting from params[2])
  let local_values : Array[Value] = []
  for param in func_type.params {
    let p = builder.add_param(Type::from_wasm(param))
    local_values.push(p)
  }
  // Add result types
  let func_result_types : Array[Type] = []
  for result in func_type.results {
    builder.add_result(Type::from_wasm(result))
    func_result_types.push(Type::from_wasm(result))
  }
  // Initialize locals with zero values - we'll handle them specially
  for local_ty in locals {
    // Create placeholder values for locals
    // In SSA, we need to track the current value of each local
    local_values.push(
      Value::new(
        -1 - local_values.length(), // Temporary IDs for locals
        Type::from_wasm(local_ty),
      ),
    )
  }
  // Calculate table base offsets for multi-table support
  // All tables are flattened into a single indirect_table at runtime
  // table_base_offsets[i] = starting index of table i in the flattened table
  let table_base_offsets : Array[Int] = []
  let table_sizes : Array[Int] = []
  let table_is_64 : Array[Bool] = []
  let mut offset = 0
  for table in tables {
    let size = table.type_.limits.min.to_int() // Tables always use 32-bit limits
    table_base_offsets.push(offset)
    table_sizes.push(size)
    table_is_64.push(table.type_.is_table64)
    offset = offset + size
  }
  // Compute canonical type indices for structural type equivalence
  // Structurally equivalent types will map to the same canonical index
  // Use module_types if available (preserves finality and supertypes),
  // otherwise fall back to converting func_types
  let types_for_canonical = if module_types.length() > 0 {
    module_types
  } else {
    @types.func_types_to_subtypes(func_types)
  }
  let canonical_type_indices = @types.compute_canonical_type_indices(
    types_for_canonical,
    type_rec_groups~,
  )
  {
    builder,
    value_stack: [],
    locals: local_values,
    block_stack: [],
    func_types,
    func_type_indices,
    num_imports,
    import_func_type_indices,
    is_unreachable: false,
    return_continuation: None,
    func_result_types,
    memory_max,
    memory_is_64,
    table_base_offsets,
    table_sizes,
    table_is_64,
    global_types,
    num_wasm_params: func_type.params.length(),
    canonical_type_indices,
    func_base,
    import_remap,
    module_types,
    vmctx,
    func_env,
    tags,
    try_table_depth: 0,
  }
}

///|
/// Convert a local value to i64 bits for exception spilling
/// i32: zero-extend to i64
/// i64: as-is
/// f32: bitcast to i32, zero-extend to i64
/// f64: bitcast to i64
/// ref: already i64 in IR
fn Translator::local_to_i64_bits(self : Translator, loc_val : Value) -> Value {
  match loc_val.ty {
    I32 => self.builder.uextend(I64, loc_val)
    I64 | FuncRef | ExternRef => loc_val // refs are already i64
    F32 => {
      let bits32 = self.builder.bitcast(I32, loc_val)
      self.builder.uextend(I64, bits32)
    }
    F64 => self.builder.bitcast(I64, loc_val)
    V128 => abort("V128 locals not supported in exception handling spill")
  }
}

///|
/// Convert i64 bits back to the original local type
fn Translator::i64_bits_to_local(
  self : Translator,
  bits : Value,
  target_ty : Type,
) -> Value {
  match target_ty {
    I32 => self.builder.ireduce(I32, bits)
    I64 | FuncRef | ExternRef => bits // refs are already i64
    F32 => {
      let bits32 = self.builder.ireduce(I32, bits)
      self.builder.bitcast(F32, bits32)
    }
    F64 => self.builder.bitcast(F64, bits)
    V128 => abort("V128 locals not supported in exception handling restore")
  }
}

///|
/// Spill all locals before instructions that might throw
/// Called when try_table_depth > 0 and before Call/CallIndirect/CallRef/Throw/ThrowRef
fn Translator::spill_locals_if_in_try(self : Translator) -> Unit {
  if self.try_table_depth > 0 {
    let locals_bits : Array[Value] = []
    for loc in self.locals {
      locals_bits.push(self.local_to_i64_bits(loc))
    }
    self.builder.spill_locals_for_throw(locals_bits)
  }
}

///|
/// Get the number of fields in a struct type
fn Translator::get_struct_field_count(self : Translator, type_idx : Int) -> Int {
  if type_idx >= self.module_types.length() {
    abort("Invalid type index: \{type_idx}")
  }
  let subtype = self.module_types[type_idx]
  match subtype.composite {
    @types.CompositeType::Struct(st) => st.fields.length()
    _ => abort("Type \{type_idx} is not a struct type")
  }
}

///|
/// Get the IR type for an array element
fn Translator::get_array_element_ir_type(
  self : Translator,
  type_idx : Int,
) -> Type {
  if type_idx >= self.module_types.length() {
    // Default to I64 for unknown types
    return Type::I64
  }
  let subtype = self.module_types[type_idx]
  match subtype.composite {
    @types.CompositeType::Array(arr) =>
      match arr.element.storage_type {
        @types.StorageType::Val(vt) => Type::from_wasm(vt)
        // Packed types (i8, i16) are extended to i32
        @types.StorageType::Packed(_) => Type::I32
      }
    // Not an array type, default to I64
    _ => Type::I64
  }
}

///|
/// Get the IR type for a struct field
fn Translator::get_struct_field_ir_type(
  self : Translator,
  type_idx : Int,
  field_idx : Int,
) -> Type {
  if type_idx >= self.module_types.length() {
    return Type::I64
  }
  let subtype = self.module_types[type_idx]
  match subtype.composite {
    @types.CompositeType::Struct(st) => {
      if field_idx >= st.fields.length() {
        return Type::I64
      }
      match st.fields[field_idx].storage_type {
        @types.StorageType::Val(vt) => Type::from_wasm(vt)
        // Packed types (i8, i16) are extended to i32
        @types.StorageType::Packed(_) => Type::I32
      }
    }
    _ => Type::I64
  }
}

///|
/// Get the byte width for a packed struct field (for sign/zero extension)
/// Returns 1 for i8, 2 for i16, 0 for non-packed types
fn Translator::get_struct_field_byte_width(
  self : Translator,
  type_idx : Int,
  field_idx : Int,
) -> Int {
  if type_idx >= self.module_types.length() {
    return 0
  }
  let subtype = self.module_types[type_idx]
  match subtype.composite {
    @types.CompositeType::Struct(st) => {
      if field_idx >= st.fields.length() {
        return 0
      }
      match st.fields[field_idx].storage_type {
        @types.StorageType::Val(_) => 0 // Not a packed type
        @types.StorageType::Packed(packed) =>
          match packed {
            @types.PackedType::I8 => 1
            @types.PackedType::I16 => 2
          }
      }
    }
    _ => 0
  }
}

///|
/// Get the byte width for a packed array element (for sign/zero extension)
/// Returns 1 for i8, 2 for i16, 0 for non-packed types
fn Translator::get_array_element_byte_width(
  self : Translator,
  type_idx : Int,
) -> Int {
  if type_idx >= self.module_types.length() {
    return 0
  }
  let subtype = self.module_types[type_idx]
  match subtype.composite {
    @types.CompositeType::Array(arr) =>
      match arr.element.storage_type {
        @types.StorageType::Val(_) => 0 // Not a packed type
        @types.StorageType::Packed(packed) =>
          match packed {
            @types.PackedType::I8 => 1
            @types.PackedType::I16 => 2
          }
      }
    _ => 0
  }
}

///|
/// Extract type index from a ValueType (for GC reference types)
fn Translator::extract_type_idx(
  self : Translator,
  value_type : @types.ValueType,
) -> Int {
  // Ignore the self parameter - we don't need module context to extract indices
  let _ = self
  // Abstract types are encoded as negative indices:
  // -1 = anyref (any), -2 = eqref (eq), -3 = i31ref
  // -4 = structref (abstract), -5 = arrayref (abstract)
  // -6 = funcref, -7 = externref
  // -8 = nullref, -9 = nofunc, -10 = noextern
  match value_type {
    // Concrete struct types (idx >= 0) or abstract struct (-1 -> -4)
    @types.ValueType::RefStruct(idx) | @types.ValueType::RefNullStruct(idx) =>
      if idx < 0 {
        -4
      } else {
        idx
      }
    // Concrete array types (idx >= 0) or abstract array (-1 -> -5)
    @types.ValueType::RefArray(idx) | @types.ValueType::RefNullArray(idx) =>
      if idx < 0 {
        -5
      } else {
        idx
      }
    @types.ValueType::RefFuncTyped(idx)
    | @types.ValueType::RefNullFuncTyped(idx) => idx
    AnyRef | RefAny => -1
    RefEq | RefNullEq => -2
    RefI31 | RefNullI31 => -3
    FuncRef | RefFunc => -6
    ExternRef | RefExtern => -7
    NullRef => -8
    NullFuncRef => -9
    NullExternRef => -10
    // For value types or unsupported ref types, return -100 as error marker
    _ => -100
  }
}

///|
/// Push a value onto the operand stack
fn Translator::push(self : Translator, v : Value) -> Unit {
  self.value_stack.push(v)
}

///|
/// Pop a value from the operand stack
fn Translator::pop(self : Translator) -> Value {
  match self.value_stack.pop() {
    Some(v) => v
    None => abort("Stack underflow")
  }
}

///|
/// Peek at the top of the stack
fn Translator::peek(self : Translator) -> Value {
  match self.value_stack.last() {
    Some(v) => v
    None => abort("Stack underflow")
  }
}

///|
/// Get the result types from a block type
fn get_block_result_types(
  block_type : @types.BlockType,
  func_types : Array[@types.FuncType],
) -> Array[Type] {
  match block_type {
    Empty => []
    Value(vt) => [Type::from_wasm(vt)]
    MultiValue(vts) => vts.map(Type::from_wasm)
    InlineType(_, results) => results.map(Type::from_wasm)
    TypeIndex(idx) =>
      if idx < func_types.length() {
        func_types[idx].results.map(Type::from_wasm)
      } else {
        []
      }
  }
}

///|
/// Get the parameter types from a block type
fn get_block_param_types(
  block_type : @types.BlockType,
  func_types : Array[@types.FuncType],
) -> Array[Type] {
  match block_type {
    Empty => []
    Value(_) => [] // Simple block types have no params
    MultiValue(_) => [] // MultiValue blocks have no params (result-only)
    InlineType(params, _) => params.map(Type::from_wasm)
    TypeIndex(idx) =>
      if idx < func_types.length() {
        func_types[idx].params.map(Type::from_wasm)
      } else {
        []
      }
  }
}

///|
/// Translate a sequence of WASM instructions
pub fn Translator::translate(
  self : Translator,
  instrs : Array[@types.Instruction],
) -> Function {
  // Create the entry block
  let entry = self.builder.create_block()
  self.builder.switch_to_block(entry)
  // Initialize locals with default values
  for i, loc in self.locals {
    // Skip parameters - they already have values
    // Use num_wasm_params (not IR params.length which includes vmctx)
    if i >= self.num_wasm_params {
      let zero_val = match loc.ty {
        I32 => self.builder.iconst_i32(0)
        I64 => self.builder.iconst_i64(0L)
        F32 => self.builder.fconst_f32(0.0)
        F64 => self.builder.fconst_f64(0.0)
        _ => self.builder.iconst_i32(0) // Fallback
      }
      self.locals[i] = zero_val
    }
  }

  // Translate instructions
  // Note: block_stack does NOT include a function-level frame
  // translate_br/translate_br_table handle function-level jumps specially
  for instr in instrs {
    self.translate_instruction(instr)
  }

  // Handle function end
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    // Normal fall-through: check if return_continuation was created
    if self.return_continuation is Some(ret_cont) {
      // Someone jumped to function level, need to go through continuation
      let args : Array[Value] = []
      for _ in 0..<self.func_result_types.length() {
        if self.value_stack.length() > 0 {
          args.push(self.pop())
        }
      }
      args.rev_in_place()
      for loc in self.locals {
        args.push(loc)
      }
      self.builder.jump(ret_cont, args)
    } else {
      // No one jumped to function level, just return directly
      let return_vals : Array[Value] = []
      for _ in 0..<self.func_result_types.length() {
        if self.value_stack.length() > 0 {
          return_vals.push(self.pop())
        }
      }
      return_vals.rev_in_place()
      self.builder.return_(return_vals)
    }
  }

  // If return_continuation was created, emit it
  if self.return_continuation is Some(ret_cont) {
    self.builder.switch_to_block(ret_cont)
    let return_vals : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      return_vals.push(ret_cont.params[i].0)
    }
    self.builder.return_(return_vals)
  }
  self.builder.get_function()
}

///|
/// Get or create the return continuation block for function-level jumps
fn Translator::get_or_create_return_continuation(self : Translator) -> Block {
  match self.return_continuation {
    Some(block) => block
    None => {
      let ret_cont = self.builder.create_block()
      // Add block parameters for function results
      for ty in self.func_result_types {
        self.builder.add_block_param(ret_cont, ty) |> ignore
      }
      // Add block parameters for ALL locals (SSA phi nodes)
      for loc in self.locals {
        self.builder.add_block_param(ret_cont, loc.ty) |> ignore
      }
      self.return_continuation = Some(ret_cont)
      ret_cont
    }
  }
}

///|
/// Translate a single instruction
fn Translator::translate_instruction(
  self : Translator,
  instr : @types.Instruction,
) -> Unit {
  // If we're in unreachable code, only process control flow instructions
  // that may create new reachable regions
  if self.is_unreachable {
    match instr {
      Block(block_type, body) => self.translate_block(block_type, body)
      Loop(block_type, body) => self.translate_loop(block_type, body)
      If(block_type, then_body, else_body) =>
        self.translate_if(block_type, then_body, else_body)
      // All other instructions are dead code, skip them
      _ => return
    }
    return
  }
  match instr {
    // Constants
    I32Const(n) => {
      let v = self.builder.iconst_i32(n)
      self.push(v)
    }
    I64Const(n) => {
      let v = self.builder.iconst_i64(n)
      self.push(v)
    }
    F32Const(n) => {
      let v = self.builder.fconst_f32(n)
      self.push(v)
    }
    F64Const(n) => {
      let v = self.builder.fconst_f64(n)
      self.push(v)
    }

    // Local variables
    LocalGet(idx) => {
      let v = self.locals[idx]
      self.push(v)
    }
    LocalSet(idx) => {
      let v = self.pop()
      self.locals[idx] = v
    }
    LocalTee(idx) => {
      let v = self.peek()
      self.locals[idx] = v
    }

    // Stack operations
    Drop => self.pop() |> ignore
    Select => {
      let c = self.pop() // condition
      let val2 = self.pop() // false value
      let val1 = self.pop() // true value
      let result = self.builder.select(c, val1, val2)
      self.push(result)
    }
    SelectTyped(_) => {
      // Same as Select - type annotation is for validation only
      let c = self.pop() // condition
      let val2 = self.pop() // false value
      let val1 = self.pop() // true value
      let result = self.builder.select(c, val1, val2)
      self.push(result)
    }

    // i32 arithmetic
    I32Add => self.translate_binary_i32(fn(b, a, v) { b.iadd(a, v) })
    I32Sub => self.translate_binary_i32(fn(b, a, v) { b.isub(a, v) })
    I32Mul => self.translate_binary_i32(fn(b, a, v) { b.imul(a, v) })
    I32DivS => self.translate_binary_i32(fn(b, a, v) { b.sdiv(a, v) })
    I32DivU => self.translate_binary_i32(fn(b, a, v) { b.udiv(a, v) })
    I32RemS => self.translate_binary_i32(fn(b, a, v) { b.srem(a, v) })
    I32RemU => self.translate_binary_i32(fn(b, a, v) { b.urem(a, v) })
    I32And => self.translate_binary_i32(fn(b, a, v) { b.band(a, v) })
    I32Or => self.translate_binary_i32(fn(b, a, v) { b.bor(a, v) })
    I32Xor => self.translate_binary_i32(fn(b, a, v) { b.bxor(a, v) })
    I32Shl => self.translate_binary_i32(fn(b, a, v) { b.ishl(a, v) })
    I32ShrS => self.translate_binary_i32(fn(b, a, v) { b.sshr(a, v) })
    I32ShrU => self.translate_binary_i32(fn(b, a, v) { b.ushr(a, v) })
    I32Rotl => self.translate_binary_i32(fn(b, a, v) { b.rotl(a, v) })
    I32Rotr => self.translate_binary_i32(fn(b, a, v) { b.rotr(a, v) })

    // i32 bit counting
    I32Clz => self.translate_unary_i32(fn(b, a) { b.clz(a) })
    I32Ctz => self.translate_unary_i32(fn(b, a) { b.ctz(a) })
    I32Popcnt => self.translate_unary_i32(fn(b, a) { b.popcnt(a) })

    // i32 comparisons
    I32Eqz => {
      let a = self.pop()
      let zero = self.builder.iconst_i32(0)
      let result = self.builder.icmp_eq(a, zero)
      self.push(result)
    }
    I32Eq => self.translate_icmp(IntCC::Eq)
    I32Ne => self.translate_icmp(IntCC::Ne)
    I32LtS => self.translate_icmp(IntCC::Slt)
    I32LtU => self.translate_icmp(IntCC::Ult)
    I32GtS => self.translate_icmp(IntCC::Sgt)
    I32GtU => self.translate_icmp(IntCC::Ugt)
    I32LeS => self.translate_icmp(IntCC::Sle)
    I32LeU => self.translate_icmp(IntCC::Ule)
    I32GeS => self.translate_icmp(IntCC::Sge)
    I32GeU => self.translate_icmp(IntCC::Uge)

    // i64 arithmetic
    I64Add => self.translate_binary_i64(fn(b, a, v) { b.iadd(a, v) })
    I64Sub => self.translate_binary_i64(fn(b, a, v) { b.isub(a, v) })
    I64Mul => self.translate_binary_i64(fn(b, a, v) { b.imul(a, v) })
    I64DivS => self.translate_binary_i64(fn(b, a, v) { b.sdiv(a, v) })
    I64DivU => self.translate_binary_i64(fn(b, a, v) { b.udiv(a, v) })
    I64RemS => self.translate_binary_i64(fn(b, a, v) { b.srem(a, v) })
    I64RemU => self.translate_binary_i64(fn(b, a, v) { b.urem(a, v) })
    I64And => self.translate_binary_i64(fn(b, a, v) { b.band(a, v) })
    I64Or => self.translate_binary_i64(fn(b, a, v) { b.bor(a, v) })
    I64Xor => self.translate_binary_i64(fn(b, a, v) { b.bxor(a, v) })
    I64Shl => self.translate_binary_i64(fn(b, a, v) { b.ishl(a, v) })
    I64ShrS => self.translate_binary_i64(fn(b, a, v) { b.sshr(a, v) })
    I64ShrU => self.translate_binary_i64(fn(b, a, v) { b.ushr(a, v) })
    I64Rotl => self.translate_binary_i64(fn(b, a, v) { b.rotl(a, v) })
    I64Rotr => self.translate_binary_i64(fn(b, a, v) { b.rotr(a, v) })

    // i64 bit counting
    I64Clz => self.translate_unary_i64(fn(b, a) { b.clz(a) })
    I64Ctz => self.translate_unary_i64(fn(b, a) { b.ctz(a) })
    I64Popcnt => self.translate_unary_i64(fn(b, a) { b.popcnt(a) })

    // i64 comparisons
    I64Eqz => {
      let a = self.pop()
      let zero = self.builder.iconst_i64(0L)
      let result = self.builder.icmp_eq(a, zero)
      self.push(result)
    }
    I64Eq => self.translate_icmp(IntCC::Eq)
    I64Ne => self.translate_icmp(IntCC::Ne)
    I64LtS => self.translate_icmp(IntCC::Slt)
    I64LtU => self.translate_icmp(IntCC::Ult)
    I64GtS => self.translate_icmp(IntCC::Sgt)
    I64GtU => self.translate_icmp(IntCC::Ugt)
    I64LeS => self.translate_icmp(IntCC::Sle)
    I64LeU => self.translate_icmp(IntCC::Ule)
    I64GeS => self.translate_icmp(IntCC::Sge)
    I64GeU => self.translate_icmp(IntCC::Uge)

    // f32 arithmetic
    F32Add => self.translate_binary_f32(fn(b, a, v) { b.fadd(a, v) })
    F32Sub => self.translate_binary_f32(fn(b, a, v) { b.fsub(a, v) })
    F32Mul => self.translate_binary_f32(fn(b, a, v) { b.fmul(a, v) })
    F32Div => self.translate_binary_f32(fn(b, a, v) { b.fdiv(a, v) })
    F32Min => self.translate_binary_f32(fn(b, a, v) { b.fmin(a, v) })
    F32Max => self.translate_binary_f32(fn(b, a, v) { b.fmax(a, v) })
    F32Copysign => {
      // copysign(x, y) = magnitude of x with sign of y
      let y = self.pop() // sign source
      let x = self.pop() // magnitude source
      // Use bitwise operations to implement copysign
      // result_bits = (x_bits & 0x7FFFFFFF) | (y_bits & 0x80000000)
      let x_bits = self.builder.bitcast(Type::I32, x)
      let y_bits = self.builder.bitcast(Type::I32, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i32(0x7FFFFFFF),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i32(0x80000000U.reinterpret_as_int()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(Type::F32, result_bits)
      self.push(result)
    }

    // f32 unary
    F32Neg => self.translate_unary_f32(fn(b, a) { b.fneg(a) })
    F32Abs => self.translate_unary_f32(fn(b, a) { b.fabs(a) })
    F32Sqrt => self.translate_unary_f32(fn(b, a) { b.fsqrt(a) })
    F32Ceil => self.translate_unary_f32(fn(b, a) { b.fceil(a) })
    F32Floor => self.translate_unary_f32(fn(b, a) { b.ffloor(a) })
    F32Trunc => self.translate_unary_f32(fn(b, a) { b.ftrunc(a) })
    F32Nearest => self.translate_unary_f32(fn(b, a) { b.fnearest(a) })

    // f32 comparisons
    F32Eq => self.translate_fcmp(FloatCC::Eq)
    F32Ne => self.translate_fcmp(FloatCC::Ne)
    F32Lt => self.translate_fcmp(FloatCC::Lt)
    F32Gt => self.translate_fcmp(FloatCC::Gt)
    F32Le => self.translate_fcmp(FloatCC::Le)
    F32Ge => self.translate_fcmp(FloatCC::Ge)

    // f64 arithmetic
    F64Add => self.translate_binary_f64(fn(b, a, v) { b.fadd(a, v) })
    F64Sub => self.translate_binary_f64(fn(b, a, v) { b.fsub(a, v) })
    F64Mul => self.translate_binary_f64(fn(b, a, v) { b.fmul(a, v) })
    F64Div => self.translate_binary_f64(fn(b, a, v) { b.fdiv(a, v) })
    F64Min => self.translate_binary_f64(fn(b, a, v) { b.fmin(a, v) })
    F64Max => self.translate_binary_f64(fn(b, a, v) { b.fmax(a, v) })
    F64Copysign => {
      // copysign(x, y) = magnitude of x with sign of y
      let y = self.pop() // sign source
      let x = self.pop() // magnitude source
      // Use bitwise operations to implement copysign
      // result_bits = (x_bits & 0x7FFFFFFFFFFFFFFF) | (y_bits & 0x8000000000000000)
      let x_bits = self.builder.bitcast(Type::I64, x)
      let y_bits = self.builder.bitcast(Type::I64, y)
      let magnitude = self.builder.band(
        x_bits,
        self.builder.iconst_i64(0x7FFFFFFFFFFFFFFFL),
      )
      let sign = self.builder.band(
        y_bits,
        self.builder.iconst_i64(0x8000000000000000UL.reinterpret_as_int64()),
      )
      let result_bits = self.builder.bor(magnitude, sign)
      let result = self.builder.bitcast(Type::F64, result_bits)
      self.push(result)
    }

    // f64 unary
    F64Neg => self.translate_unary_f64(fn(b, a) { b.fneg(a) })
    F64Abs => self.translate_unary_f64(fn(b, a) { b.fabs(a) })
    F64Sqrt => self.translate_unary_f64(fn(b, a) { b.fsqrt(a) })
    F64Ceil => self.translate_unary_f64(fn(b, a) { b.fceil(a) })
    F64Floor => self.translate_unary_f64(fn(b, a) { b.ffloor(a) })
    F64Trunc => self.translate_unary_f64(fn(b, a) { b.ftrunc(a) })
    F64Nearest => self.translate_unary_f64(fn(b, a) { b.fnearest(a) })

    // f64 comparisons
    F64Eq => self.translate_fcmp(FloatCC::Eq)
    F64Ne => self.translate_fcmp(FloatCC::Ne)
    F64Lt => self.translate_fcmp(FloatCC::Lt)
    F64Gt => self.translate_fcmp(FloatCC::Gt)
    F64Le => self.translate_fcmp(FloatCC::Le)
    F64Ge => self.translate_fcmp(FloatCC::Ge)

    // Conversions
    I32WrapI64 => {
      let a = self.pop()
      let result = self.builder.ireduce(Type::I32, a)
      self.push(result)
    }
    I64ExtendI32S => {
      let a = self.pop()
      let result = self.builder.sextend(Type::I64, a)
      self.push(result)
    }
    I64ExtendI32U => {
      let a = self.pop()
      let result = self.builder.uextend(Type::I64, a)
      self.push(result)
    }
    // In-place sign extension instructions (like Cranelift's ireduce + sextend)
    I32Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(Type::I32, a)
      self.push(result)
    }
    I32Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(Type::I32, a)
      self.push(result)
    }
    I64Extend8S => {
      let a = self.pop()
      let result = self.builder.sextend8(Type::I64, a)
      self.push(result)
    }
    I64Extend16S => {
      let a = self.pop()
      let result = self.builder.sextend16(Type::I64, a)
      self.push(result)
    }
    I64Extend32S => {
      let a = self.pop()
      let result = self.builder.sextend32(a)
      self.push(result)
    }
    F32DemoteF64 => {
      let a = self.pop()
      let result = self.builder.fdemote(a)
      self.push(result)
    }
    F64PromoteF32 => {
      let a = self.pop()
      let result = self.builder.fpromote(a)
      self.push(result)
    }
    I32TruncF32S | I32TruncF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint(Type::I32, a)
      self.push(result)
    }
    I32TruncF32U | I32TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(Type::I32, a)
      self.push(result)
    }
    I64TruncF32S | I64TruncF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint(Type::I64, a)
      self.push(result)
    }
    I64TruncF32U | I64TruncF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint(Type::I64, a)
      self.push(result)
    }
    F32ConvertI32S | F32ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(Type::F32, a)
      self.push(result)
    }
    F32ConvertI32U | F32ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(Type::F32, a)
      self.push(result)
    }
    F64ConvertI32S | F64ConvertI64S => {
      let a = self.pop()
      let result = self.builder.sint_to_fcvt(Type::F64, a)
      self.push(result)
    }
    F64ConvertI32U | F64ConvertI64U => {
      let a = self.pop()
      let result = self.builder.uint_to_fcvt(Type::F64, a)
      self.push(result)
    }
    // Saturating truncation operations
    I32TruncSatF32S | I32TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(Type::I32, a)
      self.push(result)
    }
    I32TruncSatF32U | I32TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(Type::I32, a)
      self.push(result)
    }
    I64TruncSatF32S | I64TruncSatF64S => {
      let a = self.pop()
      let result = self.builder.fcvt_to_sint_sat(Type::I64, a)
      self.push(result)
    }
    I64TruncSatF32U | I64TruncSatF64U => {
      let a = self.pop()
      let result = self.builder.fcvt_to_uint_sat(Type::I64, a)
      self.push(result)
    }
    I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64 => {
      let a = self.pop()
      let target_ty = match instr {
        I32ReinterpretF32 => Type::I32
        I64ReinterpretF64 => Type::I64
        F32ReinterpretI32 => Type::F32
        F64ReinterpretI64 => Type::F64
        _ => Type::I32
      }
      let result = self.builder.bitcast(target_ty, a)
      self.push(result)
    }

    // Memory operations (desugared via FuncEnvironment to LoadPtr with explicit bounds check)
    I32Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        addr,
        offset,
      )
      self.push(result)
    }
    F32Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::F32,
        addr,
        offset,
      )
      self.push(result)
    }
    F64Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::F64,
        addr,
        offset,
      )
      self.push(result)
    }

    // Narrow load operations (desugared via FuncEnvironment)
    I32Load8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        8,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        8,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load16S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        16,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I32Load16U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        16,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        8,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        8,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load16S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        16,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load16U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        16,
        false,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load32S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        32,
        true,
        addr,
        offset,
      )
      self.push(result)
    }
    I64Load32U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load_narrow(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        32,
        false,
        addr,
        offset,
      )
      self.push(result)
    }

    // Store operations (desugared via FuncEnvironment to StorePtr with explicit bounds check)
    I32Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::I32,
        addr,
        value,
        offset,
      )
    }
    I64Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::I64,
        addr,
        value,
        offset,
      )
    }
    F32Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::F32,
        addr,
        value,
        offset,
      )
    }
    F64Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::F64,
        addr,
        value,
        offset,
      )
    }

    // Narrow store operations (desugared via FuncEnvironment)
    I32Store8(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        8,
        addr,
        value,
        offset,
      )
    }
    I32Store16(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        16,
        addr,
        value,
        offset,
      )
    }
    I64Store8(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        8,
        addr,
        value,
        offset,
      )
    }
    I64Store16(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        16,
        addr,
        value,
        offset,
      )
    }
    I64Store32(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store_narrow(
        self.builder,
        self.vmctx,
        memidx,
        32,
        addr,
        value,
        offset,
      )
    }

    // Control flow
    Unreachable => {
      self.builder.trap("unreachable")
      self.is_unreachable = true
    }
    Nop => () // No operation
    Return => {
      let results = self.builder.get_function().results
      let return_vals : Array[Value] = []
      for _ in 0..<results.length() {
        return_vals.push(self.pop())
      }
      return_vals.rev_in_place()
      self.builder.return_(return_vals)
      self.is_unreachable = true
    }
    Block(block_type, body) => self.translate_block(block_type, body)
    Loop(block_type, body) => self.translate_loop(block_type, body)
    If(block_type, then_body, else_body) =>
      self.translate_if(block_type, then_body, else_body)
    Br(depth) => self.translate_br(depth)
    BrIf(depth) => self.translate_br_if(depth)
    BrTable(labels, default_) => self.translate_br_table(labels, default_)
    BrOnNull(depth) => self.translate_br_on_null(depth)
    BrOnNonNull(depth) => self.translate_br_on_non_null(depth)

    // Function calls - spill locals before call when inside try_table
    // because the callee might throw and we need caller's locals at call point
    Call(func_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call(func_idx)
    }
    CallIndirect(type_idx, table_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call_indirect(type_idx, table_idx)
    }
    CallRef(type_idx) => {
      self.spill_locals_if_in_try()
      self.translate_call_ref(type_idx)
    }
    ReturnCall(func_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call(func_idx)
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call_indirect(type_idx, table_idx)
    }
    ReturnCallRef(type_idx) => {
      self.spill_locals_if_in_try()
      self.translate_return_call_ref(type_idx)
    }

    // Memory management (multi-memory support via memidx)
    // Note: These use IR opcodes instead of desugaring because they require
    // libcalls that are handled in the VCode emit phase
    MemoryGrow(memidx) => {
      let delta = self.pop()
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]
      let result = match self.memory_max {
        Some(max) =>
          self.builder.memory_grow(
            memidx,
            delta,
            max_pages=max,
            is_memory64=is_mem64,
          )
        None => self.builder.memory_grow(memidx, delta, is_memory64=is_mem64)
      }
      self.push(result)
    }
    MemorySize(memidx) => {
      let is_mem64 = memidx < self.memory_is_64.length() &&
        self.memory_is_64[memidx]
      let result = self.builder.memory_size(memidx, is_memory64=is_mem64)
      self.push(result)
    }
    MemoryFill(memidx) => {
      let n = self.pop() // size
      let val = self.pop() // value (byte)
      let d = self.pop() // destination
      self.builder.memory_fill(memidx, d, val, n)
    }
    MemoryCopy(dst_memidx, src_memidx) => {
      let n = self.pop() // size
      let s = self.pop() // source
      let d = self.pop() // destination
      self.builder.memory_copy(dst_memidx, src_memidx, d, s, n)
    }

    // Reference types
    RefNull(_ref_type) => {
      // Null reference is represented as NULL_REF
      // (GC refs are encoded as (gc_ref << 1) where gc_ref is 1-based, so 0 is safe for null)
      let result = self.builder.iconst(Type::I64, @types.NULL_REF)
      self.push(result)
    }
    RefIsNull => {
      // Check if reference is null (compare with NULL_REF)
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(Type::I64, @types.NULL_REF)
      let result = self.builder.icmp_eq(ref_val, null_sentinel)
      self.push(result)
    }
    RefFunc(func_idx) => {
      // Create a function reference - use GetFuncRef to get tagged function pointer
      // The pointer is tagged with FUNCREF_TAG (bit 61) for ref.test detection
      let result = self.builder.get_func_ref(func_idx)
      self.push(result)
    }
    RefAsNonNull => {
      // ref.as_non_null: convert nullable ref to non-null ref
      // Pop the reference, check if null, trap if so, otherwise push back
      let ref_val = self.pop()
      let null_sentinel = self.builder.iconst(Type::I64, @types.NULL_REF)
      let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

      // Create trap block and continuation block
      let trap_block = self.builder.create_block()
      let continue_block = self.builder.create_block()

      // Branch: if is_null goto trap_block else continue_block
      self.builder.brnz(is_null, trap_block, continue_block)

      // Trap block: emit trap for null reference
      self.builder.switch_to_block(trap_block)
      self.builder.trap("null function reference")

      // Continue block: push the non-null ref back on stack
      self.builder.switch_to_block(continue_block)
      self.push(ref_val)
    }
    RefEqInstr => {
      // ref.eq: compare two references for equality
      let ref2 = self.pop()
      let ref1 = self.pop()
      let result = self.builder.ref_eq(ref1, ref2)
      self.push(result)
    }
    TableGet(table_idx) => {
      // Desugar to load from vmctx.tables[table_idx][elem_idx]
      let elem_idx = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result = self.func_env.translate_table_get(
        self.builder,
        self.vmctx,
        table_idx,
        elem_idx,
        is_table64~,
      )
      self.push(result)
    }
    TableSet(table_idx) => {
      // Desugar to store to vmctx.tables[table_idx][elem_idx]
      let value = self.pop()
      let elem_idx = self.pop()
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      self.func_env.translate_table_set(
        self.builder,
        self.vmctx,
        table_idx,
        elem_idx,
        value,
        is_table64~,
      )
    }
    TableSize(table_idx) => {
      // Desugar to load from vmctx.table_sizes[table_idx]
      let is_table64 = table_idx < self.table_is_64.length() &&
        self.table_is_64[table_idx]
      let result = self.func_env.translate_table_size(
        self.builder,
        self.vmctx,
        table_idx,
        is_table64~,
      )
      self.push(result)
    }
    TableGrow(table_idx) => {
      // Note: Uses IR opcode instead of desugaring because it requires
      // a libcall that is handled in the VCode emit phase
      // Stack: [init_value, delta] -> [result]
      let delta = self.pop()
      let init_value = self.pop()
      let result = self.builder.table_grow(table_idx, delta, init_value)
      self.push(result)
    }
    GlobalGet(idx) => {
      // Desugar to load from vmctx.globals[idx]
      let result = self.func_env.translate_global_get(
        self.builder,
        self.vmctx,
        idx,
      )
      self.push(result)
    }
    GlobalSet(idx) => {
      // Desugar to store to vmctx.globals[idx]
      let value = self.pop()
      self.func_env.translate_global_set(self.builder, self.vmctx, idx, value)
    }

    // GC instructions - struct operations
    StructNew(type_idx) => {
      // Pop field values from stack (in reverse order)
      let field_count = self.get_struct_field_count(type_idx)
      let fields : Array[Value] = []
      for i = 0; i < field_count; i = i + 1 {
        fields.push(self.pop())
      }
      // Reverse to get correct order
      fields.rev_in_place()
      let result = self.builder.struct_new(type_idx, fields)
      self.push(result)
    }
    StructNewDefault(type_idx) => {
      let result = self.builder.struct_new_default(type_idx)
      self.push(result)
    }
    StructGet(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let result = self.builder.struct_get(
        type_idx, field_idx, struct_ref, field_type,
      )
      self.push(result)
    }
    StructGetS(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = self.builder.struct_get_s(
        type_idx, field_idx, struct_ref, field_type, byte_width,
      )
      self.push(result)
    }
    StructGetU(type_idx, field_idx) => {
      let struct_ref = self.pop()
      let field_type = self.get_struct_field_ir_type(type_idx, field_idx)
      let byte_width = self.get_struct_field_byte_width(type_idx, field_idx)
      let result = self.builder.struct_get_u(
        type_idx, field_idx, struct_ref, field_type, byte_width,
      )
      self.push(result)
    }
    StructSet(type_idx, field_idx) => {
      let value = self.pop()
      let struct_ref = self.pop()
      self.builder.struct_set(type_idx, field_idx, struct_ref, value)
    }

    // GC instructions - array operations
    ArrayNew(type_idx) => {
      // Stack: [init_value, length] -> [arrayref]
      let length = self.pop()
      let init_value = self.pop()
      let result = self.builder.array_new(type_idx, init_value, length)
      self.push(result)
    }
    ArrayNewDefault(type_idx) => {
      // Stack: [length] -> [arrayref]
      let length = self.pop()
      let result = self.builder.array_new_default(type_idx, length)
      self.push(result)
    }
    ArrayNewFixed(type_idx, count) => {
      // Pop count values from stack
      let elements : Array[Value] = []
      for i = 0; i < count; i = i + 1 {
        elements.push(self.pop())
      }
      // Reverse to get correct order
      elements.rev_in_place()
      let result = self.builder.array_new_fixed(type_idx, count, elements)
      self.push(result)
    }
    ArrayGet(type_idx) => {
      // Stack: [arrayref, index] -> [value]
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let result = self.builder.array_get(type_idx, array_ref, index, elem_type)
      self.push(result)
    }
    ArrayGetS(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = self.builder.array_get_s(
        type_idx, array_ref, index, elem_type, byte_width,
      )
      self.push(result)
    }
    ArrayGetU(type_idx) => {
      let index = self.pop()
      let array_ref = self.pop()
      let elem_type = self.get_array_element_ir_type(type_idx)
      let byte_width = self.get_array_element_byte_width(type_idx)
      let result = self.builder.array_get_u(
        type_idx, array_ref, index, elem_type, byte_width,
      )
      self.push(result)
    }
    ArraySet(type_idx) => {
      // Stack: [arrayref, index, value] -> []
      let value = self.pop()
      let index = self.pop()
      let array_ref = self.pop()
      self.builder.array_set(type_idx, array_ref, index, value)
    }
    ArrayLen => {
      let array_ref = self.pop()
      let result = self.builder.array_len(array_ref)
      self.push(result)
    }
    ArrayFill(type_idx) => {
      // Stack: [arrayref, offset, value, count] -> []
      let count = self.pop()
      let value = self.pop()
      let offset = self.pop()
      let array_ref = self.pop()
      self.builder.array_fill(type_idx, array_ref, offset, value, count)
    }
    ArrayCopy(dst_type_idx, src_type_idx) => {
      // Stack: [dst, dst_offset, src, src_offset, count] -> []
      let count = self.pop()
      let src_offset = self.pop()
      let src = self.pop()
      let dst_offset = self.pop()
      let dst = self.pop()
      self.builder.array_copy(
        dst_type_idx, src_type_idx, dst, dst_offset, src, src_offset, count,
      )
    }

    // GC instructions - i31 operations
    RefI31 => {
      let value = self.pop()
      let result = self.builder.i31_new(value)
      self.push(result)
    }
    I31GetS => {
      let i31_ref = self.pop()
      let result = self.builder.i31_get_s(i31_ref)
      self.push(result)
    }
    I31GetU => {
      let i31_ref = self.pop()
      let result = self.builder.i31_get_u(i31_ref)
      self.push(result)
    }

    // GC instructions - type conversions
    AnyConvertExtern => {
      let extern_ref = self.pop()
      let result = self.builder.any_convert_extern(extern_ref)
      self.push(result)
    }
    ExternConvertAny => {
      let any_ref = self.pop()
      let result = self.builder.extern_convert_any(any_ref)
      self.push(result)
    }

    // Type testing/casting - these are more complex, need runtime support
    RefTest(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_test(type_idx, false, ref_val)
      self.push(result)
    }
    RefTestNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_test(type_idx, true, ref_val)
      self.push(result)
    }
    RefCast(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_cast(type_idx, false, ref_val)
      self.push(result)
    }
    RefCastNull(value_type) => {
      let ref_val = self.pop()
      let type_idx = self.extract_type_idx(value_type)
      let result = self.builder.ref_cast(type_idx, true, ref_val)
      self.push(result)
    }
    BrOnCast(label_depth, _from_type, to_type) =>
      self.translate_br_on_cast(label_depth, to_type)
    BrOnCastFail(label_depth, _from_type, to_type) =>
      self.translate_br_on_cast_fail(label_depth, to_type)

    // Exception handling
    // Uses setjmp/longjmp pattern in the JIT runtime
    Throw(tag_idx) => {
      // Get the tag's parameter types to know how many values to pop
      let tag_types = self.get_tag_param_types(tag_idx)

      // Pop exception values from stack (in reverse order)
      let values : Array[Value] = Array::make(
        tag_types.length(),
        self.builder.iconst_i32(0),
      )
      for i = tag_types.length() - 1; i >= 0; i = i - 1 {
        values[i] = self.pop()
      }

      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()

      // Emit Throw IR opcode with the exception values
      self.builder.emit_throw(tag_idx, values)
      self.is_unreachable = true
    }
    ThrowRef => {
      // Pop exnref from stack
      let exnref = self.pop()
      // Spill all locals before throw so catch handlers see throw-time values
      self.spill_locals_if_in_try()
      // Emit ThrowRef IR opcode
      self.builder.emit_throw_ref(exnref)
      self.is_unreachable = true
    }
    TryTable(block_type, handlers, body) => {
      // Exception handling via setjmp/longjmp
      //
      // The TryTableBegin opcode returns:
      // - 0 on normal entry (first setjmp return)
      // - non-zero on exception catch (longjmp return with handler_id)
      //
      // Flow:
      // 1. Call TryTableBegin (setjmp)
      // 2. If result != 0, branch to catch_dispatch
      // 3. Otherwise, execute try body
      // 4. In catch_dispatch: match tag and branch to handler

      let handler_id = self.block_stack.length() // Use stack depth as unique ID

      // Create blocks for control flow
      let try_body_block = self.builder.create_block()
      let catch_dispatch = self.builder.create_block()
      let try_continuation = self.builder.create_block()

      // Emit TryTableBegin - sets up exception handler and calls setjmp
      let setjmp_result = self.builder.try_table_begin(handler_id)

      // Branch based on setjmp result: 0 = normal, non-zero = exception caught
      let zero = self.builder.iconst_i32(0)
      let is_exception = self.builder.icmp_ne(setjmp_result, zero)
      self.builder.brnz(is_exception, catch_dispatch, try_body_block)

      // Save local types before translating body for proper restoration in catch
      let local_types : Array[Type] = []
      for loc in self.locals {
        local_types.push(loc.ty)
      }
      let num_locals = local_types.length()

      // === Try body block ===
      self.builder.switch_to_block(try_body_block)

      // Increment try_table_depth so spill_locals_if_in_try knows to spill
      // Note: decrement happens AFTER all catch handlers are translated,
      // so catch handlers can still spill for outer try_tables
      self.try_table_depth = self.try_table_depth + 1

      // Translate the body using normal block translation
      self.translate_block(block_type, body)

      // Save post-body locals for the normal continuation path
      // (locals modified in try body should be visible after try_table)
      let post_body_locals = self.locals.copy()

      // Emit TryTableEnd - pops exception handler
      self.builder.try_table_end(handler_id)

      // Jump to continuation after try body
      if not(self.is_unreachable) &&
        self.builder.current_block() is Some(blk) &&
        blk.terminator is None {
        self.builder.jump(try_continuation, [])
      }

      // === Catch dispatch block ===
      self.builder.switch_to_block(catch_dispatch)

      // Load locals from spilled storage (saved before throw/call)
      // and convert i64 bits back to original types
      self.locals.clear()
      for i in 0..<num_locals {
        let spilled_bits = self.builder.get_spilled_local(i)
        let restored_val = self.i64_bits_to_local(spilled_bits, local_types[i])
        self.locals.push(restored_val)
      }

      // Get exception tag for matching
      let exn_tag = self.builder.get_exception_tag()

      // Process each handler
      // Note: handlers reference labels in the OUTER block stack, not inside try_table
      for handler in handlers {
        match handler {
          Catch(tag_idx, label_depth) => {
            // Check if exception tag matches this handler
            let handler_tag = self.builder.iconst_i32(tag_idx)
            let tag_matches = self.builder.icmp_eq(exn_tag, handler_tag)

            // Create block for next handler check
            let next_check = self.builder.create_block()

            // If matches, branch to handler; otherwise continue checking
            let handler_block = self.builder.create_block()
            self.builder.brnz(tag_matches, handler_block, next_check)

            // In handler block: pop handler and branch to label
            self.builder.switch_to_block(handler_block)
            self.emit_catch_branch(tag_idx, label_depth, handler_id)
            self.builder.switch_to_block(next_check)
          }
          CatchRef(tag_idx, label_depth) => {
            // Same as Catch but also pushes exnref
            let handler_tag = self.builder.iconst_i32(tag_idx)
            let tag_matches = self.builder.icmp_eq(exn_tag, handler_tag)
            let next_check = self.builder.create_block()
            let handler_block = self.builder.create_block()
            self.builder.brnz(tag_matches, handler_block, next_check)
            self.builder.switch_to_block(handler_block)
            self.emit_catch_ref_branch(tag_idx, label_depth, handler_id)
            self.builder.switch_to_block(next_check)
          }
          CatchAll(label_depth) => {
            // Catch any exception - no tag check needed
            self.emit_catch_all_branch(label_depth, handler_id)
            // No need to continue checking after catch_all
            break
          }
          CatchAllRef(label_depth) => {
            // Catch any exception with exnref
            self.emit_catch_all_ref_branch(label_depth, handler_id)
            break
          }
        }
      }

      // If no handler matched, rethrow (delegate to outer handler)
      // Use depth=1 to skip this handler and propagate to the next outer one
      // (depth=0 would cause infinite loop by re-entering this same handler)
      if self.builder.current_block() is Some(blk) && blk.terminator is None {
        self.builder.delegate(1) // Propagate to outer handler
      }

      // Decrement try_table_depth AFTER all catch handlers are translated
      // This ensures catch handlers can still spill for outer try_tables
      self.try_table_depth = self.try_table_depth - 1

      // === Continuation block ===
      self.builder.switch_to_block(try_continuation)

      // Restore post-body locals for the normal continuation path
      // This ensures locals modified in the try body are visible after try_table
      self.locals.clear()
      for loc in post_body_locals {
        self.locals.push(loc)
      }
      self.is_unreachable = false
    }
    // ============ SIMD Instructions ============

    // V128 constant
    V128Const(bytes) => {
      let v = self.builder.v128_const(bytes)
      self.push(v)
    }

    // Splat operations (scalar -> vector)
    I8x16Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat8(val)
      self.push(result)
    }
    I16x8Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat16(val)
      self.push(result)
    }
    I32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat32(val)
      self.push(result)
    }
    I64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat64(val)
      self.push(result)
    }
    F32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f32(val)
      self.push(result)
    }
    F64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f64(val)
      self.push(result)
    }

    // Extract lane operations (vector -> scalar)
    I8x16ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8s(vec, lane)
      self.push(result)
    }
    I8x16ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8u(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16s(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16u(vec, lane)
      self.push(result)
    }
    I32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract32(vec, lane)
      self.push(result)
    }
    I64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract64(vec, lane)
      self.push(result)
    }
    F32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f32(vec, lane)
      self.push(result)
    }
    F64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f64(vec, lane)
      self.push(result)
    }

    // Replace lane operations (vector, scalar -> vector)
    I8x16ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace8(vec, val, lane)
      self.push(result)
    }
    I16x8ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace16(vec, val, lane)
      self.push(result)
    }
    I32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace32(vec, val, lane)
      self.push(result)
    }
    I64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace64(vec, val, lane)
      self.push(result)
    }
    F32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f32(vec, val, lane)
      self.push(result)
    }
    F64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f64(vec, val, lane)
      self.push(result)
    }

    // Shuffle and swizzle
    I8x16Shuffle(lanes) => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_shuffle(a, b, lanes)
      self.push(result)
    }
    I8x16Swizzle => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_swizzle(a, b)
      self.push(result)
    }

    // Bitwise operations
    V128Not => {
      let a = self.pop()
      let result = self.builder.v128_not(a)
      self.push(result)
    }
    V128And => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_and(a, b)
      self.push(result)
    }
    V128AndNot => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_andnot(a, b)
      self.push(result)
    }
    V128Or => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_or(a, b)
      self.push(result)
    }
    V128Xor => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_xor(a, b)
      self.push(result)
    }
    V128Bitselect => {
      let c = self.pop() // mask
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_bitselect(a, b, c)
      self.push(result)
    }
    V128AnyTrue => {
      let a = self.pop()
      let result = self.builder.v128_anytrue(a)
      self.push(result)
    }

    // i8x16 operations
    I8x16Eq => self.translate_simd_binary(Opcode::V128Eq8)
    I8x16Ne => self.translate_simd_binary(Opcode::V128Ne8)
    I8x16LtS => self.translate_simd_binary(Opcode::V128Lt8S)
    I8x16LtU => self.translate_simd_binary(Opcode::V128Lt8U)
    I8x16GtS => self.translate_simd_binary(Opcode::V128Gt8S)
    I8x16GtU => self.translate_simd_binary(Opcode::V128Gt8U)
    I8x16LeS => self.translate_simd_binary(Opcode::V128Le8S)
    I8x16LeU => self.translate_simd_binary(Opcode::V128Le8U)
    I8x16GeS => self.translate_simd_binary(Opcode::V128Ge8S)
    I8x16GeU => self.translate_simd_binary(Opcode::V128Ge8U)
    I8x16Abs => self.translate_simd_unary(Opcode::V128Abs8)
    I8x16Neg => self.translate_simd_unary(Opcode::V128Neg8)
    I8x16Popcnt => self.translate_simd_unary(Opcode::V128Popcnt8)
    I8x16AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue8)
    I8x16Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask8)
    I8x16NarrowI16x8S => self.translate_simd_binary(Opcode::V128Narrow16to8S)
    I8x16NarrowI16x8U => self.translate_simd_binary(Opcode::V128Narrow16to8U)
    I8x16Shl => self.translate_simd_shift(Opcode::V128Shl8)
    I8x16ShrS => self.translate_simd_shift(Opcode::V128Shr8S)
    I8x16ShrU => self.translate_simd_shift(Opcode::V128Shr8U)
    I8x16Add => self.translate_simd_binary(Opcode::V128Add8)
    I8x16AddSatS => self.translate_simd_binary(Opcode::V128AddSat8S)
    I8x16AddSatU => self.translate_simd_binary(Opcode::V128AddSat8U)
    I8x16Sub => self.translate_simd_binary(Opcode::V128Sub8)
    I8x16SubSatS => self.translate_simd_binary(Opcode::V128SubSat8S)
    I8x16SubSatU => self.translate_simd_binary(Opcode::V128SubSat8U)
    I8x16MinS => self.translate_simd_binary(Opcode::V128Min8S)
    I8x16MinU => self.translate_simd_binary(Opcode::V128Min8U)
    I8x16MaxS => self.translate_simd_binary(Opcode::V128Max8S)
    I8x16MaxU => self.translate_simd_binary(Opcode::V128Max8U)
    I8x16AvgrU => self.translate_simd_binary(Opcode::V128Avgr8U)

    // i16x8 operations
    I16x8ExtAddPairwiseI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16S)
    I16x8ExtAddPairwiseI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16U)
    I16x8Eq => self.translate_simd_binary(Opcode::V128Eq16)
    I16x8Ne => self.translate_simd_binary(Opcode::V128Ne16)
    I16x8LtS => self.translate_simd_binary(Opcode::V128Lt16S)
    I16x8LtU => self.translate_simd_binary(Opcode::V128Lt16U)
    I16x8GtS => self.translate_simd_binary(Opcode::V128Gt16S)
    I16x8GtU => self.translate_simd_binary(Opcode::V128Gt16U)
    I16x8LeS => self.translate_simd_binary(Opcode::V128Le16S)
    I16x8LeU => self.translate_simd_binary(Opcode::V128Le16U)
    I16x8GeS => self.translate_simd_binary(Opcode::V128Ge16S)
    I16x8GeU => self.translate_simd_binary(Opcode::V128Ge16U)
    I16x8Abs => self.translate_simd_unary(Opcode::V128Abs16)
    I16x8Neg => self.translate_simd_unary(Opcode::V128Neg16)
    I16x8Q15MulrSatS => self.translate_simd_binary(Opcode::V128Q15MulrSat16S)
    I16x8AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue16)
    I16x8Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask16)
    I16x8NarrowI32x4S => self.translate_simd_binary(Opcode::V128Narrow32to16S)
    I16x8NarrowI32x4U => self.translate_simd_binary(Opcode::V128Narrow32to16U)
    I16x8ExtendLowI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16S)
    I16x8ExtendHighI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16S)
    I16x8ExtendLowI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16U)
    I16x8ExtendHighI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16U)
    I16x8Shl => self.translate_simd_shift(Opcode::V128Shl16)
    I16x8ShrS => self.translate_simd_shift(Opcode::V128Shr16S)
    I16x8ShrU => self.translate_simd_shift(Opcode::V128Shr16U)
    I16x8Add => self.translate_simd_binary(Opcode::V128Add16)
    I16x8AddSatS => self.translate_simd_binary(Opcode::V128AddSat16S)
    I16x8AddSatU => self.translate_simd_binary(Opcode::V128AddSat16U)
    I16x8Sub => self.translate_simd_binary(Opcode::V128Sub16)
    I16x8SubSatS => self.translate_simd_binary(Opcode::V128SubSat16S)
    I16x8SubSatU => self.translate_simd_binary(Opcode::V128SubSat16U)
    I16x8Mul => self.translate_simd_binary(Opcode::V128Mul16)
    I16x8MinS => self.translate_simd_binary(Opcode::V128Min16S)
    I16x8MinU => self.translate_simd_binary(Opcode::V128Min16U)
    I16x8MaxS => self.translate_simd_binary(Opcode::V128Max16S)
    I16x8MaxU => self.translate_simd_binary(Opcode::V128Max16U)
    I16x8AvgrU => self.translate_simd_binary(Opcode::V128Avgr16U)
    I16x8ExtMulLowI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16S)
    I16x8ExtMulHighI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16S)
    I16x8ExtMulLowI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16U)
    I16x8ExtMulHighI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16U)

    // i32x4 operations
    I32x4ExtAddPairwiseI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32S)
    I32x4ExtAddPairwiseI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32U)
    I32x4Eq => self.translate_simd_binary(Opcode::V128Eq32)
    I32x4Ne => self.translate_simd_binary(Opcode::V128Ne32)
    I32x4LtS => self.translate_simd_binary(Opcode::V128Lt32S)
    I32x4LtU => self.translate_simd_binary(Opcode::V128Lt32U)
    I32x4GtS => self.translate_simd_binary(Opcode::V128Gt32S)
    I32x4GtU => self.translate_simd_binary(Opcode::V128Gt32U)
    I32x4LeS => self.translate_simd_binary(Opcode::V128Le32S)
    I32x4LeU => self.translate_simd_binary(Opcode::V128Le32U)
    I32x4GeS => self.translate_simd_binary(Opcode::V128Ge32S)
    I32x4GeU => self.translate_simd_binary(Opcode::V128Ge32U)
    I32x4Abs => self.translate_simd_unary(Opcode::V128Abs32)
    I32x4Neg => self.translate_simd_unary(Opcode::V128Neg32)
    I32x4AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue32)
    I32x4Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask32)
    I32x4ExtendLowI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32S)
    I32x4ExtendHighI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32S)
    I32x4ExtendLowI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32U)
    I32x4ExtendHighI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32U)
    I32x4Shl => self.translate_simd_shift(Opcode::V128Shl32)
    I32x4ShrS => self.translate_simd_shift(Opcode::V128Shr32S)
    I32x4ShrU => self.translate_simd_shift(Opcode::V128Shr32U)
    I32x4Add => self.translate_simd_binary(Opcode::V128Add32)
    I32x4Sub => self.translate_simd_binary(Opcode::V128Sub32)
    I32x4Mul => self.translate_simd_binary(Opcode::V128Mul32)
    I32x4MinS => self.translate_simd_binary(Opcode::V128Min32S)
    I32x4MinU => self.translate_simd_binary(Opcode::V128Min32U)
    I32x4MaxS => self.translate_simd_binary(Opcode::V128Max32S)
    I32x4MaxU => self.translate_simd_binary(Opcode::V128Max32U)
    I32x4DotI16x8S => self.translate_simd_binary(Opcode::V128Dot16to32S)
    I32x4ExtMulLowI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32S)
    I32x4ExtMulHighI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32S)
    I32x4ExtMulLowI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32U)
    I32x4ExtMulHighI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32U)

    // i64x2 operations
    I64x2Eq => self.translate_simd_binary(Opcode::V128Eq64)
    I64x2Ne => self.translate_simd_binary(Opcode::V128Ne64)
    I64x2LtS => self.translate_simd_binary(Opcode::V128Lt64S)
    I64x2GtS => self.translate_simd_binary(Opcode::V128Gt64S)
    I64x2LeS => self.translate_simd_binary(Opcode::V128Le64S)
    I64x2GeS => self.translate_simd_binary(Opcode::V128Ge64S)
    I64x2Abs => self.translate_simd_unary(Opcode::V128Abs64)
    I64x2Neg => self.translate_simd_unary(Opcode::V128Neg64)
    I64x2AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue64)
    I64x2Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask64)
    I64x2ExtendLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64S)
    I64x2ExtendHighI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64S)
    I64x2ExtendLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64U)
    I64x2ExtendHighI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64U)
    I64x2Shl => self.translate_simd_shift(Opcode::V128Shl64)
    I64x2ShrS => self.translate_simd_shift(Opcode::V128Shr64S)
    I64x2ShrU => self.translate_simd_shift(Opcode::V128Shr64U)
    I64x2Add => self.translate_simd_binary(Opcode::V128Add64)
    I64x2Sub => self.translate_simd_binary(Opcode::V128Sub64)
    I64x2Mul => self.translate_simd_binary(Opcode::V128Mul64)
    I64x2ExtMulLowI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64S)
    I64x2ExtMulHighI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64S)
    I64x2ExtMulLowI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64U)
    I64x2ExtMulHighI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64U)

    // f32x4 operations
    F32x4Eq => self.translate_simd_binary(Opcode::V128EqF32)
    F32x4Ne => self.translate_simd_binary(Opcode::V128NeF32)
    F32x4Lt => self.translate_simd_binary(Opcode::V128LtF32)
    F32x4Gt => self.translate_simd_binary(Opcode::V128GtF32)
    F32x4Le => self.translate_simd_binary(Opcode::V128LeF32)
    F32x4Ge => self.translate_simd_binary(Opcode::V128GeF32)
    F32x4Ceil => self.translate_simd_unary(Opcode::V128CeilF32)
    F32x4Floor => self.translate_simd_unary(Opcode::V128FloorF32)
    F32x4Trunc => self.translate_simd_unary(Opcode::V128TruncF32)
    F32x4Nearest => self.translate_simd_unary(Opcode::V128NearestF32)
    F32x4Abs => self.translate_simd_unary(Opcode::V128AbsF32)
    F32x4Neg => self.translate_simd_unary(Opcode::V128NegF32)
    F32x4Sqrt => self.translate_simd_unary(Opcode::V128SqrtF32)
    F32x4Add => self.translate_simd_binary(Opcode::V128AddF32)
    F32x4Sub => self.translate_simd_binary(Opcode::V128SubF32)
    F32x4Mul => self.translate_simd_binary(Opcode::V128MulF32)
    F32x4Div => self.translate_simd_binary(Opcode::V128DivF32)
    F32x4Min => self.translate_simd_binary(Opcode::V128MinF32)
    F32x4Max => self.translate_simd_binary(Opcode::V128MaxF32)
    F32x4Pmin => self.translate_simd_binary(Opcode::V128PMinF32)
    F32x4Pmax => self.translate_simd_binary(Opcode::V128PMaxF32)

    // f64x2 operations
    F64x2Eq => self.translate_simd_binary(Opcode::V128EqF64)
    F64x2Ne => self.translate_simd_binary(Opcode::V128NeF64)
    F64x2Lt => self.translate_simd_binary(Opcode::V128LtF64)
    F64x2Gt => self.translate_simd_binary(Opcode::V128GtF64)
    F64x2Le => self.translate_simd_binary(Opcode::V128LeF64)
    F64x2Ge => self.translate_simd_binary(Opcode::V128GeF64)
    F64x2Ceil => self.translate_simd_unary(Opcode::V128CeilF64)
    F64x2Floor => self.translate_simd_unary(Opcode::V128FloorF64)
    F64x2Trunc => self.translate_simd_unary(Opcode::V128TruncF64)
    F64x2Nearest => self.translate_simd_unary(Opcode::V128NearestF64)
    F64x2Abs => self.translate_simd_unary(Opcode::V128AbsF64)
    F64x2Neg => self.translate_simd_unary(Opcode::V128NegF64)
    F64x2Sqrt => self.translate_simd_unary(Opcode::V128SqrtF64)
    F64x2Add => self.translate_simd_binary(Opcode::V128AddF64)
    F64x2Sub => self.translate_simd_binary(Opcode::V128SubF64)
    F64x2Mul => self.translate_simd_binary(Opcode::V128MulF64)
    F64x2Div => self.translate_simd_binary(Opcode::V128DivF64)
    F64x2Min => self.translate_simd_binary(Opcode::V128MinF64)
    F64x2Max => self.translate_simd_binary(Opcode::V128MaxF64)
    F64x2Pmin => self.translate_simd_binary(Opcode::V128PMinF64)
    F64x2Pmax => self.translate_simd_binary(Opcode::V128PMaxF64)

    // SIMD conversions
    I32x4TruncSatF32x4S =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32S)
    I32x4TruncSatF32x4U =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32U)
    F32x4ConvertI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32S)
    F32x4ConvertI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32U)
    I32x4TruncSatF64x2SZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32SZero)
    I32x4TruncSatF64x2UZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32UZero)
    F64x2ConvertLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64S)
    F64x2ConvertLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64U)
    F32x4DemoteF64x2Zero =>
      self.translate_simd_unary(Opcode::V128DemoteF64toF32Zero)
    F64x2PromoteLowF32x4 =>
      self.translate_simd_unary(Opcode::V128PromoteLowF32toF64)

    // V128 load/store operations
    V128Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        offset,
      )
      self.push(result)
    }
    V128Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        value,
        offset,
      )
    }
    V128Load8x8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8x8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load8Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load16Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load32Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load64Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Store8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store8Lane(memidx, 0, offset, lane),
      )
    }
    V128Store16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store16Lane(memidx, 0, offset, lane),
      )
    }
    V128Store32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store32Lane(memidx, 0, offset, lane),
      )
    }
    V128Store64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store64Lane(memidx, 0, offset, lane),
      )
    }

    // Relaxed SIMD instructions
    I8x16RelaxedSwizzle => {
      // Same as regular swizzle on ARM
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedSwizzle,
        [a, b],
      )
      self.push(result)
    }
    I32x4RelaxedTruncF32x4S =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32S)
    I32x4RelaxedTruncF32x4U =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32U)
    I32x4RelaxedTruncF64x2SZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32SZero)
    I32x4RelaxedTruncF64x2UZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32UZero)
    F32x4RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    I8x16RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect8,
        [a, b, c],
      )
      self.push(result)
    }
    I16x8RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect16,
        [a, b, c],
      )
      self.push(result)
    }
    I32x4RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect32,
        [a, b, c],
      )
      self.push(result)
    }
    I64x2RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect64,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF32)
    F32x4RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF32)
    F64x2RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF64)
    F64x2RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF64)
    I16x8RelaxedQ15mulrS =>
      self.translate_simd_binary(Opcode::V128RelaxedQ15MulrS)
    I16x8RelaxedDotI8x16I7x16S =>
      self.translate_simd_binary(Opcode::V128RelaxedDot8to16S)
    I32x4RelaxedDotI8x16I7x16AddS => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedDot8to32AddS,
        [a, b, c],
      )
      self.push(result)
    }
    inst => abort("unimplemented ir instruction \{inst}")
  }
}

///|
/// Helper for emitting catch branch with exception values
/// Gets exception values for the tag and branches to handler label
fn Translator::emit_catch_branch(
  self : Translator,
  tag_idx : Int,
  label_depth : Int,
  handler_id : Int,
) -> Unit {
  // Get the tag's parameter types
  let tag_types = self.get_tag_param_types(tag_idx)

  // Get exception values BEFORE calling try_table_end (which frees them)
  let args : Array[Value] = []
  for i, ty in tag_types {
    let val_i64 = self.builder.get_exception_value(i)
    // Convert i64 to appropriate type
    let val = match ty {
      @types.ValueType::I32 => self.builder.ireduce(Type::I32, val_i64)
      @types.ValueType::I64 => val_i64
      @types.ValueType::F32 => {
        // Reinterpret bits: i64 -> i32 -> f32
        let val_i32 = self.builder.ireduce(Type::I32, val_i64)
        self.builder.bitcast(Type::F32, val_i32)
      }
      @types.ValueType::F64 => self.builder.bitcast(Type::F64, val_i64)
      _ => val_i64 // Reference types use i64 representation
    }
    args.push(val)
  }

  // Pop the exception handler AFTER reading values
  // This is required so that throw_ref doesn't loop back to the same handler
  self.builder.try_table_end(handler_id)

  // Also pass current local values (for SSA correctness)
  for loc in self.locals {
    args.push(loc)
  }

  // Branch to the handler label
  let idx = self.block_stack.length() - 1 - label_depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    self.builder.jump(frame.block, args)
  } else {
    // Function-level branch
    let ret_cont = self.get_or_create_return_continuation()
    self.builder.jump(ret_cont, args)
  }
}

///|
/// Helper for emitting catch_ref branch (includes exnref on stack)
fn Translator::emit_catch_ref_branch(
  self : Translator,
  tag_idx : Int,
  label_depth : Int,
  handler_id : Int,
) -> Unit {
  // Get the tag's parameter types
  let tag_types = self.get_tag_param_types(tag_idx)

  // Get exception values BEFORE calling try_table_end (which frees them)
  let args : Array[Value] = []
  for i, ty in tag_types {
    let val_i64 = self.builder.get_exception_value(i)
    // Convert i64 to appropriate type
    let val = match ty {
      @types.ValueType::I32 => self.builder.ireduce(Type::I32, val_i64)
      @types.ValueType::I64 => val_i64
      @types.ValueType::F32 => {
        let val_i32 = self.builder.ireduce(Type::I32, val_i64)
        self.builder.bitcast(Type::F32, val_i32)
      }
      @types.ValueType::F64 => self.builder.bitcast(Type::F64, val_i64)
      _ => val_i64
    }
    args.push(val)
  }

  // Add exnref (placeholder - use exception tag as simple exnref)
  let exnref = self.builder.get_exception_tag()
  let exnref_i64 = self.builder.sextend32(exnref)
  args.push(exnref_i64)

  // Pop the exception handler AFTER reading values
  self.builder.try_table_end(handler_id)

  // Also pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Branch to the handler label
  let idx = self.block_stack.length() - 1 - label_depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    self.builder.jump(frame.block, args)
  } else {
    let ret_cont = self.get_or_create_return_continuation()
    self.builder.jump(ret_cont, args)
  }
}

///|
/// Helper for emitting catch_all branch (no exception values)
fn Translator::emit_catch_all_branch(
  self : Translator,
  label_depth : Int,
  handler_id : Int,
) -> Unit {
  // Pop the exception handler before branching to the catch target
  self.builder.try_table_end(handler_id)

  // catch_all doesn't pass exception values, just branches
  let args : Array[Value] = []

  // Pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Branch to the handler label
  let idx = self.block_stack.length() - 1 - label_depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    self.builder.jump(frame.block, args)
  } else {
    let ret_cont = self.get_or_create_return_continuation()
    self.builder.jump(ret_cont, args)
  }
}

///|
/// Helper for emitting catch_all_ref branch (includes exnref)
fn Translator::emit_catch_all_ref_branch(
  self : Translator,
  label_depth : Int,
  handler_id : Int,
) -> Unit {
  // Pop the exception handler before branching to the catch target
  self.builder.try_table_end(handler_id)
  let args : Array[Value] = []

  // Add exnref (placeholder)
  let exnref = self.builder.get_exception_tag()
  let exnref_i64 = self.builder.sextend32(exnref)
  args.push(exnref_i64)

  // Pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Branch to the handler label
  let idx = self.block_stack.length() - 1 - label_depth
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    self.builder.jump(frame.block, args)
  } else {
    let ret_cont = self.get_or_create_return_continuation()
    self.builder.jump(ret_cont, args)
  }
}

///|
/// Get the parameter types for a tag
fn Translator::get_tag_param_types(
  self : Translator,
  tag_idx : Int,
) -> Array[@types.ValueType] {
  if tag_idx >= 0 && tag_idx < self.tags.length() {
    let tag = self.tags[tag_idx]
    if tag.type_idx >= 0 && tag.type_idx < self.func_types.length() {
      let func_type = self.func_types[tag.type_idx]
      return func_type.params
    }
  }
  [] // Default to empty array if tag not found
}

///|
/// Helper for binary i32 operations
fn Translator::translate_binary_i32(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary i64 operations
fn Translator::translate_binary_i64(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary f32 operations
fn Translator::translate_binary_f32(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for binary f64 operations
fn Translator::translate_binary_f64(
  self : Translator,
  op : (IRBuilder, Value, Value) -> Value,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = op(self.builder, a, b)
  self.push(result)
}

///|
/// Helper for unary f32 operations
fn Translator::translate_unary_f32(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary f64 operations
fn Translator::translate_unary_f64(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary i32 operations
fn Translator::translate_unary_i32(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for unary i64 operations
fn Translator::translate_unary_i64(
  self : Translator,
  op : (IRBuilder, Value) -> Value,
) -> Unit {
  let a = self.pop()
  let result = op(self.builder, a)
  self.push(result)
}

///|
/// Helper for integer comparisons
fn Translator::translate_icmp(self : Translator, cc : IntCC) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = self.builder.icmp(cc, a, b)
  self.push(result)
}

///|
/// Helper for float comparisons
fn Translator::translate_fcmp(self : Translator, cc : FloatCC) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = self.builder.fcmp(cc, a, b)
  self.push(result)
}

///|
/// Helper for SIMD binary operations (v128, v128 -> v128)
fn Translator::translate_simd_binary(
  self : Translator,
  opcode : Opcode,
) -> Unit {
  let b = self.pop()
  let a = self.pop()
  let result = self.builder.v128_binary(opcode, a, b)
  self.push(result)
}

///|
/// Helper for SIMD unary operations (v128 -> v128)
fn Translator::translate_simd_unary(self : Translator, opcode : Opcode) -> Unit {
  let a = self.pop()
  let result = self.builder.v128_unary(opcode, a)
  self.push(result)
}

///|
/// Helper for SIMD to i32 operations (v128 -> i32)
fn Translator::translate_simd_to_i32(
  self : Translator,
  opcode : Opcode,
) -> Unit {
  let a = self.pop()
  let result = self.builder.v128_to_i32(opcode, a)
  self.push(result)
}

///|
/// Helper for SIMD shift operations (v128, i32 -> v128)
fn Translator::translate_simd_shift(self : Translator, opcode : Opcode) -> Unit {
  let shift = self.pop()
  let vec = self.pop()
  let result = self.builder.v128_shift(opcode, vec, shift)
  self.push(result)
}

///|
/// Helper for SIMD load operations (addr -> v128)
/// Emits bounds check and load
fn Translator::translate_simd_load(
  self : Translator,
  memidx : Int,
  offset : Int64,
  addr : Value,
  opcode : Opcode,
) -> Value {
  // Determine access size based on opcode
  let access_size = match opcode {
    V128Load8x8S(_, _, _)
    | V128Load8x8U(_, _, _)
    | V128Load16x4S(_, _, _)
    | V128Load16x4U(_, _, _)
    | V128Load32x2S(_, _, _)
    | V128Load32x2U(_, _, _)
    | V128Load64Splat(_, _, _)
    | V128Load64Zero(_, _, _) => 8
    V128Load32Splat(_, _, _) | V128Load32Zero(_, _, _) => 4
    V128Load16Splat(_, _, _) => 2
    V128Load8Splat(_, _, _) => 1
    _ => 16
  }
  // Emit bounds check
  let effective_addr = self.func_env.emit_bounds_check(
    self.builder,
    self.vmctx,
    memidx,
    addr,
    offset,
    access_size,
  )
  // Emit the SIMD load instruction
  self.builder.v128_load_with_addr(opcode, effective_addr)
}

///|
/// Helper for SIMD load lane operations (addr, v128 -> v128)
fn Translator::translate_simd_load_lane(
  self : Translator,
  memidx : Int,
  offset : Int64,
  addr : Value,
  vec : Value,
  opcode : Opcode,
) -> Value {
  // Emit bounds check
  let lane_size = match opcode {
    V128Load8Lane(_, _, _, _) => 1
    V128Load16Lane(_, _, _, _) => 2
    V128Load32Lane(_, _, _, _) => 4
    V128Load64Lane(_, _, _, _) => 8
    _ => 1
  }
  let effective_addr = self.func_env.emit_bounds_check(
    self.builder,
    self.vmctx,
    memidx,
    addr,
    offset,
    lane_size,
  )
  // Emit the SIMD load lane instruction
  self.builder.v128_load_lane_with_addr(opcode, effective_addr, vec)
}

///|
/// Helper for SIMD store lane operations (addr, v128 -> void)
fn Translator::translate_simd_store_lane(
  self : Translator,
  memidx : Int,
  offset : Int64,
  addr : Value,
  vec : Value,
  opcode : Opcode,
) -> Unit {
  // Emit bounds check
  let lane_size = match opcode {
    V128Store8Lane(_, _, _, _) => 1
    V128Store16Lane(_, _, _, _) => 2
    V128Store32Lane(_, _, _, _) => 4
    V128Store64Lane(_, _, _, _) => 8
    _ => 1
  }
  let effective_addr = self.func_env.emit_bounds_check(
    self.builder,
    self.vmctx,
    memidx,
    addr,
    offset,
    lane_size,
  )
  // Emit the SIMD store lane instruction
  self.builder.v128_store_lane_with_addr(opcode, effective_addr, vec)
}

///|
/// Translate a block construct
///
/// For proper SSA form, we need to pass all mutable locals through the
/// continuation block as parameters. This ensures locals modified inside the
/// block (or nested loops) are properly threaded through phi nodes.
fn Translator::translate_block(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let continuation = self.builder.create_block()

  // Add block parameters for explicit results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Add block parameters for ALL locals (SSA phi nodes)
  let local_param_start = result_types.length()
  for loc in self.locals {
    self.builder.add_block_param(continuation, loc.ty) |> ignore
  }

  // Push block frame
  let frame : BlockFrame = {
    block: continuation,
    result_types,
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)

  // Reset unreachable for block body (block entry is reachable if outer is)
  // If outer is unreachable, the whole block is dead code
  self.is_unreachable = outer_is_unreachable

  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Fall through to continuation (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    // Collect results from stack
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Then, all locals
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(continuation, args)
  }

  // When unreachable, we need to restore stack to block entry height
  // because unreachable code may have pushed values that shouldn't persist
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable (either from fall-through or from br)
  // unless the outer context was unreachable
  self.is_unreachable = outer_is_unreachable

  // Push block results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }

  // Update locals to use the continuation's phi values
  for i, _loc in self.locals {
    self.locals[i] = continuation.params[local_param_start + i].0
  }
}

///|
/// Translate a loop construct
///
/// For proper SSA form, we need to pass all mutable locals through the loop
/// header as parameters. This creates phi nodes for loop-carried variables.
fn Translator::translate_loop(
  self : Translator,
  block_type : @types.BlockType,
  body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let param_types = get_block_param_types(block_type, self.func_types)
  let loop_header = self.builder.create_block()
  let continuation = self.builder.create_block()

  // Add loop header parameters for explicit block params
  for ty in param_types {
    self.builder.add_block_param(loop_header, ty) |> ignore
  }

  // Add loop header parameters for ALL locals (SSA phi nodes for loop-carried values)
  let local_param_start = param_types.length()
  for loc in self.locals {
    self.builder.add_block_param(loop_header, loc.ty) |> ignore
  }

  // Add continuation parameters for results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Jump to loop header with current stack values AND current local values
  // (only if not unreachable)
  if !outer_is_unreachable {
    let header_args : Array[Value] = []
    // First, explicit block params from stack
    for _ in 0..<param_types.length() {
      header_args.push(self.pop())
    }
    header_args.rev_in_place()
    // Then, all locals
    for loc in self.locals {
      header_args.push(loc)
    }
    self.builder.jump(loop_header, header_args)
  }

  // Switch to loop header
  self.builder.switch_to_block(loop_header)

  // Push header params onto stack
  for i, _ty in param_types {
    self.push(loop_header.params[i].0)
  }

  // Update locals to use the loop header's phi values
  for i, _loc in self.locals {
    self.locals[i] = loop_header.params[local_param_start + i].0
  }

  // Push block frame (br targets loop header for loops)
  // Store local_param_start so br can pass locals too
  let frame : BlockFrame = {
    block: loop_header, // Loop's br target is the header
    result_types: param_types, // For br, we need params not results
    stack_height: self.value_stack.length(),
  }
  self.block_stack.push(frame)

  // Reset unreachable for loop body
  self.is_unreachable = outer_is_unreachable

  // Translate body
  for instr in body {
    self.translate_instruction(instr)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Fall through to continuation (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    self.builder.jump(continuation, args)
  }

  // Restore stack to entry height (for unreachable code cleanup)
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable unless outer was unreachable
  self.is_unreachable = outer_is_unreachable

  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }
}

///|
/// Translate an if-else construct
///
/// Following Cranelift's approach:
/// - Support block params (multi-value extension)
/// - Pass params to both then and else blocks
/// - Pass all mutable locals through continuation for SSA phi nodes
fn Translator::translate_if(
  self : Translator,
  block_type : @types.BlockType,
  then_body : Array[@types.Instruction],
  else_body : Array[@types.Instruction],
) -> Unit {
  // Save the unreachable state from outer context
  let outer_is_unreachable = self.is_unreachable
  let result_types = get_block_result_types(block_type, self.func_types)
  let param_types = get_block_param_types(block_type, self.func_types)

  // Pop condition first (it's on top of the stack)
  let cond = if outer_is_unreachable {
    // Create a dummy value when unreachable
    self.builder.iconst_i32(0)
  } else {
    self.pop()
  }

  // Pop param values from stack (following Cranelift: params are below condition)
  let param_values : Array[Value] = []
  if !outer_is_unreachable {
    for _ in 0..<param_types.length() {
      param_values.push(self.pop())
    }
    param_values.rev_in_place()
  }
  let then_block = self.builder.create_block()
  let else_block = self.builder.create_block()
  let continuation = self.builder.create_block()

  // Add block params to then_block and else_block for the if's input params
  for ty in param_types {
    self.builder.add_block_param(then_block, ty) |> ignore
    self.builder.add_block_param(else_block, ty) |> ignore
  }

  // Add continuation parameters for explicit results
  for ty in result_types {
    self.builder.add_block_param(continuation, ty) |> ignore
  }

  // Add continuation parameters for ALL locals (SSA phi nodes)
  let local_param_start = result_types.length()
  for loc in self.locals {
    self.builder.add_block_param(continuation, loc.ty) |> ignore
  }

  // Branch with param values (only if not unreachable)
  // Following Cranelift: pass params to both then and else blocks
  if !outer_is_unreachable {
    if param_values.is_empty() {
      // No params, use simple branch
      self.builder.brnz(cond, then_block, else_block)
    } else {
      // Has params, use trampoline blocks to pass arguments
      let then_trampoline = self.builder.create_block()
      let else_trampoline = self.builder.create_block()
      self.builder.brnz(cond, then_trampoline, else_trampoline)
      // Then trampoline jumps to then_block with args
      self.builder.switch_to_block(then_trampoline)
      self.builder.jump(then_block, param_values)
      // Else trampoline jumps to else_block with args
      self.builder.switch_to_block(else_trampoline)
      self.builder.jump(else_block, param_values)
    }
  }

  // Record stack height AFTER popping params (for stack restoration)
  let stack_height_after_params = self.value_stack.length()

  // Push frame for then branch (else block as the "else" continuation)
  let frame : BlockFrame = {
    block: continuation,
    result_types,
    stack_height: stack_height_after_params,
  }
  self.block_stack.push(frame)

  // Save locals at entry for else branch
  let saved_locals = self.locals.copy()

  // Translate then body
  self.builder.switch_to_block(then_block)
  self.is_unreachable = outer_is_unreachable // Reset for then body

  // Push block params onto value stack (they become available in the then body)
  for i, _ty in param_types {
    self.push(then_block.params[i].0)
  }
  for instr in then_body {
    self.translate_instruction(instr)
  }

  // Jump to continuation from then block with locals (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Pass locals
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(continuation, args)
  }

  // Restore stack to original height for else branch
  while self.value_stack.length() > frame.stack_height {
    self.pop() |> ignore
  }

  // Restore locals to entry state for else branch
  for i, loc in saved_locals {
    self.locals[i] = loc
  }

  // Translate else body
  self.builder.switch_to_block(else_block)
  self.is_unreachable = outer_is_unreachable // Reset for else body

  // Push block params onto value stack (they become available in the else body)
  for i, _ty in param_types {
    self.push(else_block.params[i].0)
  }
  for instr in else_body {
    self.translate_instruction(instr)
  }

  // Jump to continuation from else block with locals (only if not unreachable)
  if !self.is_unreachable &&
    self.builder.current_block() is Some(block) &&
    block.terminator is None {
    let args : Array[Value] = []
    for _ in 0..<result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Pass locals
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(continuation, args)
  }

  // Pop frame
  self.block_stack.pop() |> ignore

  // Switch to continuation
  self.builder.switch_to_block(continuation)

  // Continuation is reachable if outer was reachable.
  // Even if both branches end with `br 0` (making them "unreachable" after the br),
  // those branches jump TO the continuation, so the continuation is still reachable.
  // Only mark continuation unreachable if the outer context was unreachable.
  self.is_unreachable = outer_is_unreachable

  // Push results onto stack
  for i, _ty in result_types {
    self.push(continuation.params[i].0)
  }

  // Update locals to use the continuation's phi values
  for i, _loc in self.locals {
    self.locals[i] = continuation.params[local_param_start + i].0
  }
}

///|
/// Translate a br instruction
/// We need to pass both explicit params AND current local values
fn Translator::translate_br(self : Translator, depth : Int) -> Unit {
  let idx = self.block_stack.length() - 1 - depth
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]
    let args : Array[Value] = []
    // Pop explicit block params
    for _ in 0..<frame.result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(frame.block, args)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let args : Array[Value] = []
    // Pop function result values
    for _ in 0..<self.func_result_types.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(ret_cont, args)
  }
  // After br, code is unreachable
  self.is_unreachable = true
}

///|
/// Translate a br_if instruction
/// Critical edge splitting is needed because brnz doesn't support block args
fn Translator::translate_br_if(self : Translator, depth : Int) -> Unit {
  let cond = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // For br_if, we need a fallthrough block and a taken block (critical edge split)
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    // Jump to a block within the function
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()

    // Collect values that would be passed on branch
    let args : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        self.func_result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: taken goes to intermediate block, not-taken falls through
    self.builder.brnz(cond, taken, fallthrough)

    // Critical edge split: taken block jumps to return continuation
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)

    // Continue with fallthrough
    self.builder.switch_to_block(fallthrough)
  }
}

///|
/// Translate a br_on_null instruction
/// br_on_null: pop ref, branch if null, otherwise push non-null ref and continue
fn Translator::translate_br_on_null(self : Translator, depth : Int) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // Check if reference is null (GC refs use NULL_REF for null)
  let null_sentinel = self.builder.iconst(Type::I64, @types.NULL_REF)
  let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

  // For br_on_null, we need a fallthrough block and a taken block (critical edge split)
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch (not including the ref since it's null)
    let args : Array[Value] = []
    for i in 0..<frame.result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        frame.result_types.length() +
        i],
      )
    }

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: if null, go to taken block; otherwise fall through
    self.builder.brnz(is_null, taken, fallthrough)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough - push the non-null ref back on stack
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let args : Array[Value] = []
    for i in 0..<self.func_result_types.length() {
      args.push(
        self.value_stack[self.value_stack.length() -
        self.func_result_types.length() +
        i],
      )
    }
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(is_null, taken, fallthrough)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  }
}

///|
/// Translate a br_on_non_null instruction
/// br_on_non_null: pop ref, branch with ref if non-null, otherwise continue
fn Translator::translate_br_on_non_null(self : Translator, depth : Int) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth

  // Check if reference is null (GC refs use NULL_REF for null)
  let null_sentinel = self.builder.iconst(Type::I64, @types.NULL_REF)
  let is_null = self.builder.icmp_eq(ref_val, null_sentinel)

  // For br_on_non_null, we need a fallthrough block and a taken block
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]

    // Collect values that would be passed on branch
    // For br_on_non_null, we need to collect args BEFORE the ref was popped
    // The block expects result_types.length() values, and the ref is one of them
    // Since we already popped ref_val, we need to include it manually
    let args : Array[Value] = []
    // If the block expects N results, and the ref is one of them (the last one),
    // we need N-1 values from the stack plus the ref
    let stack_values_needed = frame.result_types.length() - 1
    for i in 0..<stack_values_needed {
      args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Add the ref as the last value (the non-null ref being passed)
    args.push(ref_val)

    // Always pass current local values
    for loc in self.locals {
      args.push(loc)
    }

    // Branch: if NOT null (is_null == false), go to taken block; otherwise fall through
    // Since is_null is 1 if null, 0 if non-null, we branch to fallthrough if null
    self.builder.brnz(is_null, fallthrough, taken)

    // Critical edge split: taken block jumps to target with args
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)

    // Continue with fallthrough - reference is consumed (null), nothing pushed
    self.builder.switch_to_block(fallthrough)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()

    // Similar adjustment for function-level return
    let args : Array[Value] = []
    let stack_values_needed = self.func_result_types.length() - 1
    for i in 0..<stack_values_needed {
      args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(is_null, fallthrough, taken)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
  }
}

///|
/// Translate a br_on_cast instruction
/// br_on_cast: pop ref, if it matches target type, branch with the cast value;
/// otherwise push the original value and continue
fn Translator::translate_br_on_cast(
  self : Translator,
  depth : Int,
  target_type : @types.ValueType,
) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth
  // Get the type index for the target type
  let type_idx = self.extract_type_idx(target_type)
  let nullable = target_type.is_nullable()
  // Use ref_test to check if the reference matches the target type
  let matches = self.builder.ref_test(type_idx, nullable, ref_val)
  // Create fallthrough and taken blocks
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // Collect values that would be passed on branch (excluding the ref)
    let stack_values_needed = frame.result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Branch: if matches (matches == 1), go to taken; otherwise fall through
    self.builder.brnz(matches, taken, fallthrough)
    // Critical edge split: taken block creates cast value and jumps to target
    self.builder.switch_to_block(taken)
    // Create the cast value in the taken block (we know the cast succeeded here)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(cast_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(frame.block, args)
    // Continue with fallthrough - push the original ref back
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let stack_values_needed = self.func_result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    self.builder.brnz(matches, taken, fallthrough)
    self.builder.switch_to_block(taken)
    // Create the cast value in the taken block
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(cast_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.jump(ret_cont, args)
    self.builder.switch_to_block(fallthrough)
    self.push(ref_val)
  }
}

///|
/// Translate a br_on_cast_fail instruction
/// br_on_cast_fail: pop ref, if it does NOT match target type, branch with the value;
/// otherwise push the cast value and continue
fn Translator::translate_br_on_cast_fail(
  self : Translator,
  depth : Int,
  target_type : @types.ValueType,
) -> Unit {
  let ref_val = self.pop()
  let idx = self.block_stack.length() - 1 - depth
  // Get the type index for the target type
  let type_idx = self.extract_type_idx(target_type)
  let nullable = target_type.is_nullable()
  // Use ref_test to check if the reference matches the target type
  let matches = self.builder.ref_test(type_idx, nullable, ref_val)
  // Create fallthrough and taken blocks
  let fallthrough = self.builder.create_block()
  let taken = self.builder.create_block()
  if idx >= 0 && idx < self.block_stack.length() {
    let frame = self.block_stack[idx]
    // Collect values that would be passed on branch (excluding the ref)
    let stack_values_needed = frame.result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Build args for the taken (fail) branch - uses original ref_val
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    // Branch: if NOT matches (matches == 0), go to taken; otherwise fall through
    // brnz branches if non-zero, so we invert: if matches, go to fallthrough
    self.builder.brnz(matches, fallthrough, taken)
    // Critical edge split: taken block jumps to target with original ref
    self.builder.switch_to_block(taken)
    self.builder.jump(frame.block, args)
    // Continue with fallthrough - push the cast ref (it matched)
    self.builder.switch_to_block(fallthrough)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    self.push(cast_val)
  } else if idx == -1 {
    // Jump to function level (early return)
    let ret_cont = self.get_or_create_return_continuation()
    let stack_values_needed = self.func_result_types.length() - 1
    let stack_args : Array[Value] = []
    for i in 0..<stack_values_needed {
      stack_args.push(
        self.value_stack[self.value_stack.length() - stack_values_needed + i],
      )
    }
    // Build args for the taken (fail) branch - uses original ref_val
    let args : Array[Value] = []
    for v in stack_args {
      args.push(v)
    }
    args.push(ref_val)
    for loc in self.locals {
      args.push(loc)
    }
    self.builder.brnz(matches, fallthrough, taken)
    self.builder.switch_to_block(taken)
    self.builder.jump(ret_cont, args)
    // Continue with fallthrough - push the cast ref (it matched)
    self.builder.switch_to_block(fallthrough)
    let cast_val = self.builder.ref_cast(type_idx, nullable, ref_val)
    self.push(cast_val)
  }
}

///|
/// Translate a br_table instruction
/// Uses critical edge splitting to pass block arguments properly
fn Translator::translate_br_table(
  self : Translator,
  labels : Array[Int],
  default_ : Int,
) -> Unit {
  let index = self.pop()

  // Helper to get target block and result types for a given depth
  // Returns (target_block, result_types, is_function_level)
  fn get_target(self : Translator, depth : Int) -> (Block, Array[Type], Bool) {
    let idx = self.block_stack.length() - 1 - depth
    if idx >= 0 && idx < self.block_stack.length() {
      let frame = self.block_stack[idx]
      (frame.block, frame.result_types, false)
    } else {
      // Function level
      let ret_cont = self.get_or_create_return_continuation()
      (ret_cont, self.func_result_types, true)
    }
  }

  // Get default target info
  let (default_block, default_result_types, _) = get_target(self, default_)

  // Collect arguments that would be passed on branch (same for all targets)
  // All targets must have the same result type as the default
  let args : Array[Value] = []
  let num_results = default_result_types.length()
  // Only collect results if we have enough values on the stack
  if self.value_stack.length() >= num_results {
    for i in 0..<num_results {
      args.push(self.value_stack[self.value_stack.length() - num_results + i])
    }
  }
  // Always pass current local values
  for loc in self.locals {
    args.push(loc)
  }

  // Save the original block
  let original_block = self.builder.current_block()

  // Phase 1: Create all intermediate blocks (without filling them)
  let intermediate_blocks : Array[Block] = []
  let target_blocks : Array[Block] = []
  for depth in labels {
    let (target_block, _, _) = get_target(self, depth)
    target_blocks.push(target_block)
    intermediate_blocks.push(self.builder.create_block())
  }
  // Create intermediate block for default
  let default_intermediate = self.builder.create_block()

  // Phase 2: Emit br_table in original block
  if original_block is Some(_) {
    self.builder.br_table(index, intermediate_blocks, default_intermediate)
  }

  // Phase 3: Fill in intermediate blocks with jumps to real targets
  for i, intermediate in intermediate_blocks {
    self.builder.switch_to_block(intermediate)
    self.builder.jump(target_blocks[i], args)
  }

  // Fill in default intermediate
  self.builder.switch_to_block(default_intermediate)
  self.builder.jump(default_block, args)

  // br_table is a terminator, code after it is unreachable
  // Don't switch back to original - leave current_block as the last intermediate
  self.is_unreachable = true
}

///|
/// Remap a local function index to global function index for cross-module calls
/// - For imports: use import_remap if available
/// - For local functions: add func_base
fn Translator::remap_func_idx(self : Translator, func_idx : Int) -> Int {
  if func_idx < self.num_imports {
    // Import function - use remap if available
    if self.import_remap.length() > 0 && func_idx < self.import_remap.length() {
      self.import_remap[func_idx]
    } else {
      func_idx
    }
  } else {
    // Local function - add base offset
    self.func_base + func_idx
  }
}

///|
/// Translate a direct call
fn Translator::translate_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // Look up import function type
    if func_idx < self.import_func_type_indices.length() {
      self.import_func_type_indices[func_idx]
    } else {
      0 // Fallback
    }
  } else {
    let local_idx = func_idx - self.num_imports
    if local_idx < self.func_type_indices.length() {
      self.func_type_indices[local_idx]
    } else {
      0
    }
  }
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Remap function index for cross-module calls
    let global_func_idx = self.remap_func_idx(func_idx)
    // Emit call with multi-value support
    let results = self.builder.call_multi(global_func_idx, result_types, args)
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate an indirect call
fn Translator::translate_call_indirect(
  self : Translator,
  type_idx : Int,
  table_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Use original type_idx - the JIT type check (is_subtype_cached) handles
    // canonical indices internally to support both subtyping and structural equivalence
    // Pop callee (element index within the table)
    let elem_idx = self.pop()

    // Bounds check: elem_idx must be < table_size[table_idx]
    // Generate: if (elem_idx >= table_size) trap "out of bounds table access"
    if table_idx < self.table_sizes.length() {
      let table_size = self.table_sizes[table_idx]
      let size_const = self.builder.iconst(elem_idx.ty, table_size.to_int64())
      let out_of_bounds = self.builder.icmp_uge(elem_idx, size_const)

      // Create trap block and continuation block
      let trap_block = self.builder.create_block()
      let continue_block = self.builder.create_block()

      // Branch: if out_of_bounds goto trap_block else continue_block
      self.builder.brnz(out_of_bounds, trap_block, continue_block)

      // Trap block: emit trap instruction
      self.builder.switch_to_block(trap_block)
      self.builder.trap("out of bounds table access")

      // Continue block: proceed with call
      self.builder.switch_to_block(continue_block)
    }

    // Multi-table support: use elem_idx directly (no flattening needed)
    // The lowering phase handles table access via indirect_tables[table_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)
    // Emit call_indirect with original type_idx
    // is_subtype_cached handles canonical indices for structural equivalence
    let results = self.builder.call_indirect_multi(
      type_idx, table_idx, result_types, elem_idx, args,
    )
    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate a call through function reference
fn Translator::translate_call_ref(self : Translator, type_idx : Int) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop the function reference (which is a function index stored as I64)
    let func_ref = self.pop()

    // Null check: if func_ref == FUNCREF_NULL_SENTINEL, trap
    let null_sentinel = self.builder.iconst(
      Type::I64,
      @types.FUNCREF_NULL_SENTINEL,
    )
    let is_null = self.builder.icmp_eq(func_ref, null_sentinel)

    // Create trap block and continuation block
    let trap_block = self.builder.create_block()
    let continue_block = self.builder.create_block()

    // Branch: if is_null goto trap_block else continue_block
    self.builder.brnz(is_null, trap_block, continue_block)

    // Trap block: emit trap for null reference
    self.builder.switch_to_block(trap_block)
    self.builder.trap("null function reference")

    // Continue block: proceed with call
    self.builder.switch_to_block(continue_block)

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Get result types
    let result_types : Array[Type] = func_type.results.map(Type::from_wasm)

    // Emit call_ref instruction
    let results = self.builder.call_ref_multi(
      type_idx, result_types, func_ref, args,
    )

    // Push all results onto the stack
    for v in results {
      self.push(v)
    }
  }
}

///|
/// Translate a tail call
fn Translator::translate_return_call(self : Translator, func_idx : Int) -> Unit {
  // Get function type
  let type_idx = if func_idx < self.num_imports {
    // Look up import function type
    if func_idx < self.import_func_type_indices.length() {
      self.import_func_type_indices[func_idx]
    } else {
      0 // Fallback
    }
  } else {
    let local_idx = func_idx - self.num_imports
    if local_idx < self.func_type_indices.length() {
      self.func_type_indices[local_idx]
    } else {
      0
    }
  }
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()
    // Remap function index for cross-module calls
    let global_func_idx = self.remap_func_idx(func_idx)
    // Emit return_call instruction (tail call - does not return to caller)
    // Following Cranelift: emit a single ReturnCall IR instruction, not call + return
    self.builder.return_call_multi(global_func_idx, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}

///|
/// Translate a tail call indirect
fn Translator::translate_return_call_indirect(
  self : Translator,
  type_idx : Int,
  table_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Use original type_idx - the JIT type check (is_subtype_cached) handles
    // canonical indices internally to support both subtyping and structural equivalence
    // Pop callee (element index within the table)
    let elem_idx = self.pop()

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Emit return_call_indirect instruction (tail call - does not return to caller)
    // Following Cranelift: emit a single ReturnCallIndirect IR instruction, not call + return
    self.builder.return_call_indirect_multi(type_idx, table_idx, elem_idx, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}

///|
/// Translate a tail call through function reference
fn Translator::translate_return_call_ref(
  self : Translator,
  type_idx : Int,
) -> Unit {
  if type_idx < self.func_types.length() {
    let func_type = self.func_types[type_idx]
    // Pop the function reference (which is a function index stored as I64)
    let func_ref = self.pop()

    // Null check: if func_ref == FUNCREF_NULL_SENTINEL, trap
    let null_sentinel = self.builder.iconst(
      Type::I64,
      @types.FUNCREF_NULL_SENTINEL,
    )
    let is_null = self.builder.icmp_eq(func_ref, null_sentinel)

    // Create trap block and continuation block
    let trap_block = self.builder.create_block()
    let continue_block = self.builder.create_block()

    // Branch: if is_null goto trap_block else continue_block
    self.builder.brnz(is_null, trap_block, continue_block)

    // Trap block: emit trap for null reference
    self.builder.switch_to_block(trap_block)
    self.builder.trap("null function reference")

    // Continue block: proceed with call
    self.builder.switch_to_block(continue_block)

    // Pop arguments
    let args : Array[Value] = []
    for _ in 0..<func_type.params.length() {
      args.push(self.pop())
    }
    args.rev_in_place()

    // Emit return_call_ref instruction (tail call - does not return to caller)
    // Following Cranelift: emit a single ReturnCallRef IR instruction, not call + return
    self.builder.return_call_ref_multi(type_idx, func_ref, args)
    // Mark as unreachable since this is a terminator (does not return to this function)
    self.is_unreachable = true
  }
}
