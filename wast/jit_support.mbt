// JIT support functions for WAST runner

///|
/// Decode JIT GC reference value to @types.Value
/// JIT GC encoding: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
fn decode_gc_value(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1, decode by shifting right
    @types.Value::I31((raw >> 1).to_int())
  } else {
    // Heap reference: gc_ref << 1, decode by shifting right
    // Note: Could be struct or array, we use StructRef as default
    @types.Value::StructRef((raw >> 1).to_int())
  }
}

///|
/// JIT compiler function type - compiles a module to JIT if possible
/// Provided by the main package
pub struct JITCompiler {
  compile_fn : (@types.Module, @runtime.ModuleInstance, @runtime.Store) -> JITModuleContext?
}

///|
pub fn JITCompiler::new(
  compile_fn : (@types.Module, @runtime.ModuleInstance, @runtime.Store) -> JITModuleContext?,
) -> JITCompiler {
  { compile_fn, }
}

///|
/// Check if a module contains JIT-unsupported instructions
pub fn has_unsupported_instructions(mod_ : @types.Module) -> Bool {
  // Check all function bodies for unsupported instructions
  for code in mod_.codes {
    if contains_unsupported_instruction(code.body) {
      return true
    }
  }
  // Check if elem segments contain unsupported initializers
  if has_unsupported_elem_init(mod_) {
    return true
  }
  false
}

///|
/// Check if elem segments contain unsupported initializers
/// JIT doesn't support cross-module function references in elem segments
fn has_unsupported_elem_init(mod_ : @types.Module) -> Bool {
  for elem in mod_.elems {
    for init_expr in elem.init {
      // GlobalGet in elem init is not supported by JIT
      // because it may reference imported funcref globals (cross-module)
      if init_expr is [GlobalGet(_)] {
        return true
      }
    }
  }
  false
}

///|
/// Recursively check if instruction list contains unsupported instructions
fn contains_unsupported_instruction(instrs : Array[@types.Instruction]) -> Bool {
  for instr in instrs {
    match instr {
      // Table bulk operations - not supported by JIT
      TableInit(_, _) | TableCopy(_, _) | TableFill(_) | ElemDrop(_) =>
        return true
      // Memory bulk operations with segments - not supported by JIT
      // (memory.fill and memory.copy are now supported)
      MemoryInit(_, _) | DataDrop(_) => return true
      // GC array operations with data/elem segments - not supported by JIT
      // These require runtime access to segment data which JIT doesn't have
      ArrayNewData(_, _)
      | ArrayNewElem(_, _)
      | ArrayInitData(_, _)
      | ArrayInitElem(_, _) => return true
      // Block instructions - need to check nested instructions
      Block(_, body) | Loop(_, body) =>
        if contains_unsupported_instruction(body) {
          return true
        }
      If(_, then_body, else_body) => {
        if contains_unsupported_instruction(then_body) {
          return true
        }
        if !else_body.is_empty() && contains_unsupported_instruction(else_body) {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// Check if a module has cross-module imports (imports from user modules)
/// JIT can't properly share state with interpreter for cross-module globals/memory/tables
pub fn has_cross_module_imports(mod_ : @types.Module) -> Bool {
  for imp in mod_.imports {
    // JIT-supported modules are handled by trampolines
    // Other modules are user modules that need state sharing
    if not(@jit.is_jit_supported_module(imp.mod_name)) {
      // User module import - globals and tables still need sharing.
      // Memories are descriptor-backed and can be shared safely.
      if imp.desc is (Global(_) | Table(_)) {
        return true
      }
    }
  }
  false
}

///|
/// Check if a module exports memory or tables
/// These might be imported by other modules, and JIT can't share the backing storage
pub fn exports_shared_resources(mod_ : @types.Module) -> Bool {
  for exp in mod_.exports {
    // Tables are not yet descriptor-backed/shared with the interpreter.
    if exp.desc is Table(_) {
      return true
    }
  }
  false
}

///|
/// Get function name from exports or generate default name "func_N"
pub fn get_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  for exp in mod_.exports {
    if exp.desc is Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  "func_\{func_idx}"
}

///|
/// Sync JIT globals back to the store after a JIT function call
/// This ensures that global changes made by JIT are visible to the interpreter
pub fn sync_jit_globals_to_store(
  jit_ctx : JITModuleContext,
  store : @runtime.Store,
) -> Unit {
  if jit_ctx.globals_ptr == 0L || jit_ctx.global_addrs.is_empty() {
    return
  }
  // Read each global from JIT memory and write to store
  for i, global_addr in jit_ctx.global_addrs {
    let global_inst = store.globals[global_addr]
    // Only sync mutable globals (immutable globals don't change)
    if global_inst.get_type().mutable {
      // Read raw value from JIT memory (16 bytes per global: 8 value + 8 tag)
      let offset = jit_ctx.globals_ptr + (i * 16).to_int64()
      let raw_value = @jit.c_jit_read_i64(offset)
      // Convert based on global's type
      // Note: For FuncRef, JIT stores module function index, we need to convert
      // it back to store address for the interpreter
      let new_value : @types.Value = match global_inst.get_type().value_type {
        I32 => @types.Value::I32(@types.FromInt64::from_int64_bits(raw_value))
        I64 => @types.Value::I64(@types.FromInt64::from_int64_bits(raw_value))
        F32 => @types.Value::F32(@types.FromInt64::from_int64_bits(raw_value))
        F64 => @types.Value::F64(@types.FromInt64::from_int64_bits(raw_value))
        FuncRef
        | RefFunc
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        | NullFuncRef =>
          if raw_value == 0L {
            @types.Value::Null
          } else if raw_value < 0L {
            // IR-encoded funcref: value = -(func_idx + 1)
            let mod_func_idx = (-(raw_value + 1L)).to_int()
            if mod_func_idx >= 0 && mod_func_idx < jit_ctx.func_addrs.length() {
              @types.Value::FuncRef(jit_ctx.func_addrs[mod_func_idx])
            } else {
              @types.Value::Null
            }
          } else {
            // Tagged pointer funcref is not convertible here.
            @types.Value::Null
          }
        ExternRef | RefExtern | NullExternRef =>
          if raw_value == 0L {
            @types.Value::Null
          } else if (raw_value & EXTERNREF_TAG) != 0L {
            match @jit.decode_externref(raw_value) {
              Some(idx) => @types.Value::ExternRef(idx)
              None => @types.Value::ExternRef(raw_value.to_int())
            }
          } else {
            // Fallback: treat as raw host index
            @types.Value::ExternRef(raw_value.to_int())
          }
        // GC reference types - decode using JIT encoding:
        // null = 0, i31 = (value << 1) | 1, struct/array = gc_ref << 1
        AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
          decode_gc_value(raw_value)
        ExnRef | NullExnRef =>
          if raw_value == 0L {
            @types.Value::Null
          } else {
            @types.Value::ExnRef(raw_value.to_int())
          }
        RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs =>
          if raw_value == 0L {
            @types.Value::Null
          } else {
            @types.Value::StructRef((raw_value >> 1).to_int())
          }
        RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs =>
          if raw_value == 0L {
            @types.Value::Null
          } else {
            @types.Value::ArrayRef((raw_value >> 1).to_int())
          }
        RefI31 | RefNullI31 =>
          if raw_value == 0L {
            @types.Value::Null
          } else if (raw_value & 1L) == 1L {
            @types.Value::I31((raw_value >> 1).to_int())
          } else {
            @types.Value::Null
          }
        RefNone => @types.Value::Null
        V128 => {
          // Read both 64-bit halves and construct V128
          let high_value = @jit.c_jit_read_i64(offset + 8L)
          @types.Value::V128(int64_pair_to_v128_le(raw_value, high_value))
        }
      }
      // We already checked mutability, so set should succeed
      global_inst.set(new_value) catch {
        _ => () // Should not happen since we checked mutability
      }
    }
  }
}

///|
/// Sync interpreter tables to JIT tables before JIT execution
/// This ensures that table modifications made by the interpreter are visible to JIT
pub fn sync_tables_to_jit(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
) -> Unit {
  // Iterate over all tables in the instance
  for table_addr in instance.table_addrs {
    // Get the interpreter table
    let table = store.get_table(table_addr) catch { _ => continue }
    // Get the corresponding JIT table
    let jit_table = match store.get_jit_table(table_addr) {
      Some(jt) => jt
      None => continue
    }
    // Sync the table
    sync_table_to_jit(table, jit_table, jit_module)
  }
}

///|
/// Evaluate element segment offset constant expression
/// Supports i32.const, i64.const (for table64), i32.add, i32.sub, i32.mul, global.get for computing offsets
pub fn eval_elem_offset_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      I64Const(n) => stack.push(n.to_int()) // For table64 offset expressions
      GlobalGet(idx) =>
        if idx < globals.length() {
          match globals[idx].get() {
            I32(n) => stack.push(n)
            I64(n) => stack.push(n.to_int()) // For table64
            _ => ()
          }
        }
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => () // Ignore other instructions
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    0
  }
}

///|
/// Initialize element segments for call_indirect support
pub fn init_elem_segments(
  mod_ : @types.Module,
  jm : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Unit {
  // Get global instances for evaluating offset expressions
  let globals : Array[@runtime.GlobalInstance] = []
  for global_addr in instance.global_addrs {
    // All addresses in instance.global_addrs should exist in store
    // If not, it's an internal error
    let global = store.get_global(global_addr) catch {
      _ => abort("Internal error: global address not found in store")
    }
    globals.push(global)
  }

  // Compute canonical type indices for structural type equivalence
  // Structurally equivalent types will have the same canonical index
  let canonical_types = @types.compute_canonical_type_indices(
    mod_.types,
    type_rec_groups=mod_.type_rec_groups,
  )

  // Build function index to canonical type index mapping
  let func_canonical_types : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let canonical_idx = if type_idx < canonical_types.length() {
        canonical_types[type_idx]
      } else {
        0
      }
      func_canonical_types.push(canonical_idx)
    }
  }
  for type_idx in mod_.funcs {
    let canonical_idx = if type_idx < canonical_types.length() {
      canonical_types[type_idx]
    } else {
      0
    }
    func_canonical_types.push(canonical_idx)
  }

  // Get shared JIT tables from Store (one per runtime table)
  let jit_tables : Array[@jit.JITTable?] = []
  for table_addr in instance.table_addrs {
    let jit_table = store.get_jit_table(table_addr)
    jit_tables.push(jit_table)
  }

  // Initialize elements: (table_idx, elem_idx, func_idx?, canonical_type_idx)
  let elem_init : Array[(Int, Int, Int?, Int)] = []
  for elem in mod_.elems {
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      let offset = eval_elem_offset_expr(offset_expr, globals)
      for i, init_expr in elem.init {
        let func_idx = match init_expr {
          [RefFunc(idx)] => Some(idx)
          [I32Const(idx)] => Some(idx)
          [RefNull(_)] => None
          _ => continue
        }
        let canonical_type_idx = match func_idx {
          Some(idx) =>
            if idx >= 0 && idx < func_canonical_types.length() {
              func_canonical_types[idx]
            } else {
              0
            }
          None => 0
        }
        // No flattening: use actual table_idx and elem_idx
        let elem_idx = offset + i
        elem_init.push((table_idx, elem_idx, func_idx, canonical_type_idx))
      }
    }
  }

  // Initialize shared tables
  jm.init_shared_tables(jit_tables, elem_init)
}

///|
/// Build func_signatures array for JIT module loading
/// Returns Array[(param_types, result_types)] for each function
pub fn build_func_signatures(
  mod_ : @types.Module,
) -> Array[(Array[@types.ValueType], Array[@types.ValueType])] {
  let num_imports = count_func_imports(mod_.imports)
  let total_funcs = num_imports + mod_.funcs.length()
  let signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = []
  // Pre-fill with empty signatures for all functions
  for _ in 0..<total_funcs {
    signatures.push(([], []))
  }
  // Fill in signatures for import functions
  for i, imp in mod_.imports {
    if imp.desc is Func(type_idx) && type_idx < mod_.types.length() {
      let func_type = mod_.get_func_type(type_idx)
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.get_func_type(type_idx)
      signatures[func_idx] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  signatures
}

///|
/// Count the number of function imports in the import list
pub fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Sync interpreter table values to JIT table
/// This is needed when interpreter modifies table entries that JIT will read
/// Encoding for JIT table:
/// - null = 0
/// - i31 = (value << 1) | 1 (positive odd)
/// - struct/array ref = gc_ref << 1 (positive even, gc_ref >= 1)
/// - funcref = func_ptr | FUNCREF_TAG (bit 61 set)
/// - externref = EXTERNREF_TAG | (host_idx << 1) (bit 62 set)
pub fn sync_table_to_jit(
  table : @runtime.Table,
  jit_table : @jit.JITTable,
  jit_module : @jit.JITModule,
) -> Unit {
  let size = table.size()
  for i in 0..<size {
    let value = table.get(i) catch { _ => continue }
    let encoded : Int64 = encode_value_for_jit(value, jit_module)
    // Use type_hash 0 for GC values (not used for type checking)
    jit_table.set(i, encoded, 0)
  }
}

///|
/// Encode a Value for JIT table storage
fn encode_value_for_jit(
  value : @types.Value,
  jit_module : @jit.JITModule,
) -> Int64 {
  match value {
    Null => NULL_REF
    I31(n) => {
      // i31 encoding: (value << 1) | 1
      let n64 = n.to_int64() & 0x7FFFFFFFL
      ( // 31-bit value
        n64 << 1
      ) |
      1L
    }
    StructRef(gc_ref) | ArrayRef(gc_ref) =>
      // Heap reference encoding: gc_ref << 1 (gc_ref >= 1, so result >= 2)
      gc_ref.to_int64() << 1
    FuncRef(func_idx) => {
      // Function reference: get function pointer and tag with FUNCREF_TAG
      let func_ptr = jit_module.get_func_ptr(func_idx)
      if func_ptr == 0L {
        NULL_REF // null funcref if function not found
      } else {
        // FUNCREF_TAG = 0x2000000000000000 (bit 61)
        func_ptr | FUNCREF_TAG
      }
    }
    ExternRef(host_idx) =>
      // Extern reference: EXTERNREF_TAG | (host_idx << 1)
      EXTERNREF_TAG | (host_idx.to_int64() << 1)
    // Numeric types shouldn't be in reference tables
    I32(n) => n.to_int64()
    I64(n) => n
    F32(n) => n.reinterpret_as_int().to_int64()
    F64(n) => n.reinterpret_as_int64()
    V128(_) => abort("V128 not supported in JIT")
    ExnRef(_) => NULL_REF // Exception refs not supported in tables
  }
}

// ============================================================
// JIT Hostcall Bridge (Host Closures With Caller)
// ============================================================

///|
fn slot_count_for_type(ty : @types.ValueType) -> Int {
  match ty {
    V128 => 2
    _ => 1
  }
}

///|
fn sum_slot_count(types : Array[@types.ValueType]) -> Int {
  let mut n = 0
  for ty in types {
    n = n + slot_count_for_type(ty)
  }
  n
}

///|
fn read_slot_i64(values_ptr : Int64, slot_idx : Int) -> Int64 {
  @jit.c_jit_read_i64(values_ptr + (slot_idx * 8).to_int64())
}

///|
fn write_slot_i64(values_ptr : Int64, slot_idx : Int, value : Int64) -> Unit {
  @jit.c_jit_write_i64(values_ptr + (slot_idx * 8).to_int64(), value)
}

///|
fn low_u32_bits(raw : Int64) -> Int {
  (raw & 0xFFFFFFFFL).to_int()
}

///|
fn decode_funcref_to_store_addr(
  raw : Int64,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> @types.Value {
  if raw == NULL_REF {
    return @types.Value::Null
  }
  match @jit.decode_funcref_idx(raw) {
    Some(mod_func_idx) =>
      if mod_func_idx >= 0 && mod_func_idx < instance.func_addrs.length() {
        @types.Value::FuncRef(instance.func_addrs[mod_func_idx])
      } else {
        @types.Value::Null
      }
    None =>
      if @jit.is_funcref_ptr(raw) {
        let pc = @jit.untag_funcref_ptr(raw)
        match jit_module.find_func_by_pc(pc) {
          Some((func_idx, _, _)) =>
            if func_idx >= 0 && func_idx < instance.func_addrs.length() {
              @types.Value::FuncRef(instance.func_addrs[func_idx])
            } else {
              @types.Value::Null
            }
          None => @types.Value::Null
        }
      } else {
        // Fallback: treat as a store address (best-effort).
        @types.Value::FuncRef(raw.to_int())
      }
  }
}

///|
fn encode_store_funcref_for_jit(
  value : @types.Value,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Int64 {
  // Convert the store function address back to the module function index.
  fn store_addr_to_module_func_idx(
    store_addr : Int,
    instance : @runtime.ModuleInstance,
  ) -> Int? {
    for i, addr in instance.func_addrs {
      if addr == store_addr {
        return Some(i)
      }
    }
    None
  }

  match value {
    Null => NULL_REF
    FuncRef(store_addr) =>
      match store_addr_to_module_func_idx(store_addr, instance) {
        Some(mod_func_idx) => {
          let ptr = jit_module.get_func_ptr(mod_func_idx)
          if ptr == 0L {
            NULL_REF
          } else {
            @jit.tag_funcref_ptr(ptr)
          }
        }
        None => NULL_REF
      }
    _ => NULL_REF
  }
}

///|
fn decode_ref_value(
  ty : @types.ValueType,
  raw : Int64,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> @types.Value {
  match ty {
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      decode_funcref_to_store_addr(raw, jit_module, instance)
    ExternRef | RefExtern | NullExternRef =>
      if raw == NULL_REF {
        @types.Value::Null
      } else {
        match @jit.decode_externref(raw) {
          Some(idx) => @types.Value::ExternRef(idx)
          None => @types.Value::ExternRef(raw.to_int())
        }
      }
    ExnRef | NullExnRef =>
      if raw == NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::ExnRef(raw.to_int())
      }
    StructRef | RefStruct(_) | RefNullStruct(_) | RefStructAbs =>
      if raw == NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::StructRef(@jit.decode_heap_ref(raw))
      }
    ArrayRef | RefArray(_) | RefNullArray(_) | RefArrayAbs =>
      if raw == NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::ArrayRef(@jit.decode_heap_ref(raw))
      }
    AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
      if raw == NULL_REF {
        @types.Value::Null
      } else if (raw & 1L) == 1L {
        @types.Value::I31((raw >> 1).to_int())
      } else {
        // Best-effort: we do not attempt to discriminate struct vs array here.
        @types.Value::StructRef(@jit.decode_heap_ref(raw))
      }
    RefI31 | RefNullI31 =>
      if raw == NULL_REF {
        @types.Value::Null
      } else if (raw & 1L) == 1L {
        @types.Value::I31((raw >> 1).to_int())
      } else {
        @types.Value::Null
      }
    RefNone => @types.Value::Null

    // Non-ref types should not reach here.
    _ => @types.Value::Null
  }
}

///|
fn decode_value(
  ty : @types.ValueType,
  values_ptr : Int64,
  slot_idx : Int,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> (@types.Value, Int) {
  match ty {
    I32 =>
      (@types.Value::I32(low_u32_bits(read_slot_i64(values_ptr, slot_idx))), 1)
    I64 => (@types.Value::I64(read_slot_i64(values_ptr, slot_idx)), 1)
    F32 => {
      let bits = low_u32_bits(read_slot_i64(values_ptr, slot_idx))
      (@types.Value::F32(Float::reinterpret_from_int(bits)), 1)
    }
    F64 => {
      let raw = read_slot_i64(values_ptr, slot_idx)
      (@types.Value::F64(raw.reinterpret_as_double()), 1)
    }
    V128 => {
      let lo = read_slot_i64(values_ptr, slot_idx)
      let hi = read_slot_i64(values_ptr, slot_idx + 1)
      (@types.Value::V128(int64_pair_to_v128_le(lo, hi)), 2)
    }
    _ =>
      (
        decode_ref_value(
          ty,
          read_slot_i64(values_ptr, slot_idx),
          jit_module,
          instance,
        ),
        1,
      )
  }
}

///|
fn encode_value(
  ty : @types.ValueType,
  value : @types.Value,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Array[Int64]? {
  match ty {
    I32 =>
      match value {
        I32(n) => Some([n.to_int64() & 0xFFFFFFFFL])
        _ => None
      }
    I64 =>
      match value {
        I64(n) => Some([n])
        _ => None
      }
    F32 =>
      match value {
        F32(f) => Some([f.reinterpret_as_int().to_int64() & 0xFFFFFFFFL])
        _ => None
      }
    F64 =>
      match value {
        F64(d) => Some([d.reinterpret_as_int64()])
        _ => None
      }
    V128 =>
      match value {
        V128(bytes) =>
          if bytes.length() >= 16 {
            let lo = bytes_to_int64_le(bytes, 0)
            let hi = bytes_to_int64_le(bytes, 8)
            Some([lo, hi])
          } else {
            None
          }
        _ => None
      }
    // References.
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      Some([encode_store_funcref_for_jit(value, jit_module, instance)])
    ExternRef | RefExtern | NullExternRef =>
      match value {
        Null => Some([NULL_REF])
        ExternRef(idx) => Some([@jit.encode_externref(idx)])
        _ => None
      }
    ExnRef | NullExnRef =>
      match value {
        Null => Some([NULL_REF])
        ExnRef(idx) => Some([idx.to_int64()])
        _ => None
      }
    StructRef | RefStruct(_) | RefNullStruct(_) | RefStructAbs =>
      match value {
        Null => Some([NULL_REF])
        StructRef(idx) => Some([@jit.encode_heap_ref(idx)])
        ArrayRef(idx) => Some([@jit.encode_heap_ref(idx)]) // best-effort
        _ => None
      }
    ArrayRef | RefArray(_) | RefNullArray(_) | RefArrayAbs =>
      match value {
        Null => Some([NULL_REF])
        ArrayRef(idx) => Some([@jit.encode_heap_ref(idx)])
        StructRef(idx) => Some([@jit.encode_heap_ref(idx)]) // best-effort
        _ => None
      }
    AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
      match value {
        Null => Some([NULL_REF])
        I31(n) => Some([@jit.encode_i31(n)])
        StructRef(idx) => Some([@jit.encode_heap_ref(idx)])
        ArrayRef(idx) => Some([@jit.encode_heap_ref(idx)])
        _ => None
      }
    RefI31 | RefNullI31 =>
      match value {
        Null => Some([NULL_REF])
        I31(n) => Some([@jit.encode_i31(n)])
        _ => None
      }
    RefNone => Some([NULL_REF])
  }
}

///|
fn runtime_error_to_trap_code(err : @runtime.RuntimeError) -> Int {
  match err {
    @runtime.RuntimeError::OutOfBoundsMemoryAccess => 1
    @runtime.RuntimeError::CallStackExhausted => 2
    @runtime.RuntimeError::Unreachable => 3
    @runtime.RuntimeError::IndirectCallTypeMismatch => 4
    @runtime.RuntimeError::InvalidConversion => 5
    @runtime.RuntimeError::DivisionByZero => 6
    @runtime.RuntimeError::IntegerOverflow => 7
    _ => 99
  }
}

///|
/// Build `external_imports` for `JITModule::load_with_imports`.
///
/// For function imports without built-in trampolines, if the resolved import is a
/// runtime host function, we pass a special negative encoding `-(addr+1)` to
/// instruct the JIT loader to generate a hostcall trampoline.
pub fn build_external_imports_for_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Map[String, Map[String, Int64]] {
  let external : Map[String, Map[String, Int64]] = {}
  let mut func_imp_idx = 0
  for imp in mod_.imports {
    match imp.desc {
      Func(_) => {
        let func_addr = if func_imp_idx < instance.func_addrs.length() {
          instance.func_addrs[func_imp_idx]
        } else {
          -1
        }
        func_imp_idx = func_imp_idx + 1
        if func_addr < 0 {
          continue
        }
        // Prefer built-in trampolines when available.
        if @jit.get_import_trampoline(imp.mod_name, imp.name) is Some(_) {
          continue
        }
        let inst = store.get_func_inst(func_addr) catch { _ => continue }
        if inst is @runtime.FuncInst::HostFunc(_) {
          let encoded = -(func_addr.to_int64() + 1L)
          let m = match external.get(imp.mod_name) {
            Some(mm) => mm
            None => {}
          }
          m.set(imp.name, encoded)
          external.set(imp.mod_name, m)
        }
      }
      _ => ()
    }
  }
  external
}

///|
/// Install a JIT hostcall dispatcher closure on `jit_module`.
///
/// This enables arbitrary imported host functions (stored in `store`) to be
/// called from JIT-compiled wasm via `wasmoon_jit_hostcall`.
pub fn install_jit_hostcall_dispatcher(
  jit_module : @jit.JITModule,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Unit {
  jit_module.set_hostcall_callback(fn() {
    let func_addr = @jit.get_hostcall_func_addr()
    let values_ptr = @jit.get_hostcall_values_ptr()
    let arg_slots = @jit.get_hostcall_num_arg_slots()
    let res_slots = @jit.get_hostcall_num_result_slots()
    let ft = match store.get_func_type_opt(func_addr) {
      Some(t) => t
      None => return 3
    }
    if sum_slot_count(ft.params) != arg_slots ||
      sum_slot_count(ft.results) != res_slots {
      return 3
    }

    // Decode args.
    let args : Array[@types.Value] = []
    let mut slot = 0
    for ty in ft.params {
      let (v, used) = decode_value(ty, values_ptr, slot, jit_module, instance)
      args.push(v)
      slot = slot + used
    }

    // Invoke host function.
    let caller = @runtime.Caller::new(store, instance)
    let inst = match store.get_func_inst_opt(func_addr) {
      Some(i) => i
      None => return 3
    }
    let results : Array[@types.Value] = match inst {
      @runtime.FuncInst::HostFunc(f) =>
        f(caller, args) catch {
          e => return runtime_error_to_trap_code(e)
        }
      _ => return 3
    }
    if results.length() != ft.results.length() {
      return 3
    }

    // Encode results right after the arg slots region.
    let mut out_slot = arg_slots
    for i, ty in ft.results {
      let slots = encode_value(ty, results[i], jit_module, instance)
      match slots {
        None => return 3
        Some(encoded_slots) => {
          for j in 0..<encoded_slots.length() {
            write_slot_i64(values_ptr, out_slot + j, encoded_slots[j])
          }
          out_slot = out_slot + encoded_slots.length()
        }
      }
    }
    0
  })
}
