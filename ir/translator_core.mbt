// WASM to IR Translator
// Converts WebAssembly stack-based instructions to SSA-form IR

///|
/// Translator state for converting a single WASM function to IR
struct Translator {
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
  // Table sizes for bounds checking
  // table_sizes[i] = number of elements in table i
  table_sizes : Array[Int]
  // Number of wasm function parameters (excludes vmctx params)
  // Used to distinguish params from locals in self.locals array
  num_wasm_params : Int
  // Cross-module support: base index for this module's functions
  // All function indices are offset by this value (default 0)
  func_base : Int
  // Cross-module support: maps local import indices to global indices
  // If empty, uses local indices directly
  import_remap : Array[Int]
  // Module composite types (struct/array/func types) for GC support
  module_types : Array[@types.SubType]
  // VMContext value (vmctx parameter) for accessing runtime state
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
priv struct BlockFrame {
  block : Block // The continuation block
  result_types : Array[Type]
  // Stack height at block entry
  stack_height : Int
}

///|
/// Low-level constructor with explicit parameters.
/// Prefer `Translator::from_module` for normal use - it extracts all
/// parameters from the module automatically and is less error-prone.
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
  memory_page_size_log2? : Array[Int] = [],
  tables? : Array[@types.Table] = [],
  global_types? : Array[@types.GlobalType] = [],
  type_rec_groups? : Array[Int] = [],
  func_base? : Int = 0,
  import_remap? : Array[Int] = [],
  module_types? : Array[@types.SubType] = [],
  tags? : Array[@types.TagType] = [],
  memory_mins? : Array[Int64] = [],
) -> Translator {
  type_rec_groups |> ignore // Reserved for future canonical type indices
  let builder = IRBuilder::new(name)
  // Note: add vmctx as explicit param (Cranelift-style special param)
  // - params[0] = vmctx (X0)
  // This is referenced for desugaring global/table/memory operations
  let vmctx = builder.add_param(Type::I64)

  // Create function environment for desugaring Wasm operations
  let func_env = FuncEnvironment::new(
    global_types,
    memory_mins~,
    memory_is_64~,
    memory_page_size_log2~,
  )

  // Add wasm function parameters (starting from params[1])
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
  let table_sizes : Array[Int] = []
  let table_is_64 : Array[Bool] = []
  for table in tables {
    let size = table.type_.limits.min.to_int() // Tables always use 32-bit limits
    table_sizes.push(size)
    table_is_64.push(table.type_.is_table64)
  }
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
    table_sizes,
    table_is_64,
    num_wasm_params: func_type.params.length(),
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
/// Create a Translator from a module directly.
/// This is the preferred factory method as it extracts all necessary
/// information from the module automatically.
///
/// Parameters:
/// - mod_: The WASM module
/// - func_local_idx: Index of the function in mod_.codes (0-based, excludes imports)
/// - name: Optional function name override (defaults to export name or "func_N")
pub fn Translator::from_module(
  mod_ : @types.Module,
  func_local_idx : Int,
  name? : String,
  memory_max_override? : Int? = None,
) -> Translator {
  // Count function imports
  let mut num_imports = 0
  for imp in mod_.imports {
    if imp.desc is Func(_) {
      num_imports = num_imports + 1
    }
  }

  // Build import function type indices
  let import_func_type_indices : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      import_func_type_indices.push(type_idx)
    }
  }

  // Build global types array (imports + module globals)
  let global_types : Array[@types.GlobalType] = []
  for imp in mod_.imports {
    if imp.desc is Global(global_type) {
      global_types.push(global_type)
    }
  }
  for global in mod_.globals {
    global_types.push(global.type_)
  }

  // Get memory max limit - prefer override (for imported memories),
  // otherwise fall back to module's declared memory limits
  let memory_max : Int? = match memory_max_override {
    Some(_) => memory_max_override
    None =>
      if mod_.memories.length() > 0 {
        mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
      } else {
        None
      }
  }

  // Build memory metadata arrays
  let memory_is_64 = mod_.memories.map(fn(m) { m.is_memory64 })
  let memory_page_size_log2 = mod_.memories.map(fn(m) { m.page_size_log2 })

  // Calculate memory_mins (minimum guaranteed memory size in bytes)
  let memory_mins = mod_.memories.map(fn(m) {
    m.limits.min * (1L << m.page_size_log2)
  })

  // Determine function name: prefer internal name, then export name, then anonymous
  let func_idx = num_imports + func_local_idx
  let func_name = match name {
    Some(n) => n
    None =>
      // First check internal name from WAT parsing
      match mod_.func_names.get(func_idx) {
        Some(n) => n
        None => {
          // Fall back to export name
          let mut export_name = ""
          for exp in mod_.exports {
            if exp.desc is @types.ExportDesc::Func(idx) && idx == func_idx {
              export_name = exp.name
              break
            }
          }
          if export_name == "" {
            "func_\{func_idx}"
          } else {
            export_name
          }
        }
      }
  }

  // Get function type and locals
  let type_idx = mod_.funcs[func_local_idx]
  let func_type = mod_.get_func_type(type_idx)
  let code = mod_.codes[func_local_idx]

  // Call the main constructor
  Translator::new(
    func_name,
    func_type,
    code.locals,
    @types.extract_func_types(mod_.types),
    mod_.funcs,
    num_imports,
    import_func_type_indices,
    memory_max~,
    memory_is_64~,
    memory_page_size_log2~,
    tables=mod_.tables,
    global_types~,
    type_rec_groups=mod_.type_rec_groups,
    module_types=mod_.types,
    tags=mod_.tags,
    memory_mins~,
  )
}

///|
/// Translate a function body from a module.
/// Convenience method that creates a Translator and translates in one step.
pub fn translate_function(
  mod_ : @types.Module,
  func_local_idx : Int,
  name? : String,
  memory_max_override? : Int? = None,
) -> Function {
  let translator = Translator::from_module(
    mod_,
    func_local_idx,
    name?,
    memory_max_override~,
  )
  let code = mod_.codes[func_local_idx]
  translator.translate(code.body)
}

///|
/// Convert a local value to i64 words for exception spilling.
///
/// Most locals spill as a single i64 word, but v128 spills as two i64 lanes.
fn Translator::local_to_spill_words(
  self : Translator,
  loc_val : Value,
) -> Array[Value] {
  match loc_val.ty {
    I32 => [self.builder.uextend(I64, loc_val)]
    I64 | FuncRef | ExternRef => [loc_val] // refs are already word-sized
    F32 => {
      let bits32 = self.builder.bitcast(I32, loc_val)
      [self.builder.uextend(I64, bits32)]
    }
    F64 => [self.builder.bitcast(I64, loc_val)]
    V128 =>
      [
        self.builder.v128_extract64(loc_val, 0),
        self.builder.v128_extract64(loc_val, 1),
      ]
  }
}

///|
/// Convert i64 bits back to the original local type (non-v128).
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
    V128 => abort("internal error: use v128 spill restore path")
  }
}

///|
/// Restore a v128 local from two i64 spill words.
fn Translator::spill_words_to_v128(
  self : Translator,
  lo : Value,
  hi : Value,
) -> Value {
  let zero = self.builder.iconst(Type::I64, 0L)
  let v0 = self.builder.v128_splat64(zero)
  let v1 = self.builder.v128_replace64(v0, lo, 0)
  self.builder.v128_replace64(v1, hi, 1)
}

///|
/// Spill all locals before instructions that might throw.
/// Called when try_table_depth > 0 and before Call/CallIndirect/CallRef/Throw/ThrowRef.
fn Translator::spill_locals_if_in_try(self : Translator) -> Unit {
  if self.try_table_depth > 0 {
    let locals_words : Array[Value] = []
    for loc in self.locals {
      for w in self.local_to_spill_words(loc) {
        locals_words.push(w)
      }
    }
    self.builder.spill_locals_for_throw(locals_words)
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
        FuncRef | ExternRef => self.builder.iconst(loc.ty, @types.NULL_REF)
        V128 => {
          let z = self.builder.iconst(Type::I64, 0L)
          self.builder.v128_splat64(z)
        }
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
  let param_types = get_block_param_types(block_type, self.func_types)
  let continuation = self.builder.create_block()

  // Typed blocks: pop params from the outer stack, then make them available in the body.
  // This mirrors validation semantics (params are not part of the outer stack height).
  let param_values : Array[Value] = []
  if !outer_is_unreachable {
    for _ in 0..<param_types.length() {
      param_values.push(self.pop())
    }
    param_values.rev_in_place()
  }
  let stack_height_after_params = self.value_stack.length()

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
    stack_height: stack_height_after_params,
  }
  self.block_stack.push(frame)

  // Reset unreachable for block body (block entry is reachable if outer is)
  // If outer is unreachable, the whole block is dead code
  self.is_unreachable = outer_is_unreachable

  // Push block params onto the value stack (they become available inside the body).
  for v in param_values {
    self.push(v)
  }

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
