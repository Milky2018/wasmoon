// JIT support functions for WAST runner

///|
/// Decode JIT GC reference value to @types.Value
/// JIT GC encoding: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
fn decode_gc_value(raw : Int64, store : @runtime.Store) -> @types.Value {
  if raw == 0L {
    Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1, decode by shifting right
    I31((raw >> 1).to_int())
  } else {
    // Heap reference: encoded as (gc_ref << 1), where gc_ref is 1-based.
    let heap_idx = @wasmoon_jit.decode_heap_ref(raw)
    match store.c_heap {
      Some(heap) =>
        if heap.is_array(heap_idx) {
          ArrayRef(heap_idx)
        } else {
          StructRef(heap_idx)
        }
      None => StructRef(heap_idx)
    }
  }
}

///|
/// JIT compiler function type - compiles a module to JIT if possible
/// Provided by the main package
pub struct JITCompiler {
  compile_fn : (@types.Module, @runtime.ModuleInstance, @runtime.Store) -> Result[
    JITModuleContext,
    String,
  ]
}

///|
pub fn JITCompiler::JITCompiler(
  compile_fn : (@types.Module, @runtime.ModuleInstance, @runtime.Store) -> Result[
    JITModuleContext,
    String,
  ],
) -> JITCompiler {
  { compile_fn, }
}

///|
/// Exact registry entries owned by one installed JIT module.
struct FuncrefRegistration {
  lease : @runtime.StoreFuncrefRegistration
}

///|
/// Withdraw this module's mappings without disturbing newer replacements.
pub fn FuncrefRegistration::release(self : FuncrefRegistration) -> Unit {
  self.lease.release()
}

///|
fn register_funcref_entries(
  store : @runtime.Store,
  entries : Array[@runtime.StoreFuncrefEntry],
) -> FuncrefRegistration {
  { lease: store.register_jit_funcrefs(entries), }
}

///|
fn registered_funcref_ptr(store : @runtime.Store, store_addr : Int) -> Int64? {
  store.lookup_jit_funcref_ptr(store_addr)
}

///|
fn registered_funcref_store_addr(
  store : @runtime.Store,
  func_ptr : Int64,
) -> Int? {
  store.lookup_jit_funcref_store_addr(func_ptr)
}

///|
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

///|
/// Allocate and initialize the JIT globals array from the runtime store.
///
/// Returns the globals pointer installed into the JIT module, or 0 when the
/// instance has no globals or allocation fails.
pub fn init_jit_globals_from_store(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
) -> Int64 {
  let num_globals = instance.global_addrs.length()
  if num_globals == 0 {
    return 0L
  }
  let globals_ptr = @wasmoon_jit.alloc_memory((num_globals * 16).to_int64())
  if globals_ptr == 0L {
    return 0L
  }
  for i in 0..<num_globals {
    let global_addr = instance.global_addrs[i]
    let global_inst = store.globals[global_addr]
    let value = global_inst.get()
    let raw_value = match value {
      I32(n) => @types.ToInt64::to_int64_bits(n)
      I64(n) => @types.ToInt64::to_int64_bits(n)
      F32(f) => @types.ToInt64::to_int64_bits(f)
      F64(n) => @types.ToInt64::to_int64_bits(n)
      FuncRef(store_addr) =>
        match
          lookup_funcref_ptr_for_store_addr(
            store, store_addr, jit_module, instance,
          ) {
          Some(ptr) => @wasmoon_jit.tag_funcref_ptr(ptr)
          None =>
            match store_addr_to_module_func_idx(store_addr, instance) {
              Some(func_idx) => @wasmoon_jit.encode_funcref_idx(func_idx)
              None => @wasm_milkir.NULL_REF
            }
        }
      ExternRef(idx) => idx.to_int64()
      ExnRef(idx) => idx.to_int64()
      ArrayRef(gc_ref) => @wasmoon_jit.encode_heap_ref(gc_ref)
      StructRef(gc_ref) => @wasmoon_jit.encode_heap_ref(gc_ref)
      I31(n) => @wasmoon_jit.encode_i31(n)
      Null => @wasm_milkir.NULL_REF
      V128(bytes) => {
        let offset = globals_ptr + (i * 16).to_int64()
        @wasmoon_jit.native_value_slot_write(
          offset,
          0,
          @types.bytes_to_int64_le(bytes, 0),
        )
        @wasmoon_jit.native_value_slot_write(
          offset,
          1,
          @types.bytes_to_int64_le(bytes, 8),
        )
        continue
      }
    }
    @wasmoon_jit.native_value_slot_write(globals_ptr, i * 2, raw_value)
  }
  jit_module.set_globals(globals_ptr)
  globals_ptr
}

///|
pub fn register_instance_funcrefs_for_jit(
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Unit {
  register_owned_instance_funcrefs_for_jit(jit_module, instance, store)
  |> ignore
}

///|
/// Register one module's mappings and return the capability that withdraws
/// exactly those mappings when the module is released.
pub fn register_owned_instance_funcrefs_for_jit(
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> FuncrefRegistration {
  let entries : Array[@runtime.StoreFuncrefEntry] = []
  for i, store_addr in instance.func_addrs {
    let func_ptr = jit_module.get_func_ptr(i)
    if store_addr >= 0 && func_ptr != 0L {
      entries.push(StoreFuncrefEntry(store_addr~, func_ptr~))
    }
  }
  register_funcref_entries(store, entries)
}

///|
/// Collect all known funcref executable pointers and their function type indices.
/// Used to build a store-wide GC funcref/type view for cross-module indirect calls.
pub fn collect_registered_funcref_entries(
  store : @runtime.Store,
) -> Array[(Int64, Int)] {
  let entries : Array[(Int64, Int)] = []
  for entry in store.jit_funcref_entries() {
    let func_ptr = entry.func_ptr
    let store_addr = entry.store_addr
    if func_ptr == 0L {
      continue
    }
    if store_addr < 0 || store_addr >= store.func_type_indices.length() {
      continue
    }
    let canonical_type_idx = store.get_func_canonical_type_idx(store_addr)
    let type_idx = if canonical_type_idx >= 0 {
      canonical_type_idx
    } else {
      store.func_type_indices[store_addr]
    }
    entries.push((func_ptr, type_idx))
  }
  entries
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
  false
}

///|
/// WAST-only JIT support check.
pub fn has_unsupported_instructions_for_wast(mod_ : @types.Module) -> Bool {
  has_unsupported_instructions(mod_)
}

///|
/// Recursively check if instruction list contains unsupported instructions
fn contains_unsupported_instruction(instrs : Array[@types.Instruction]) -> Bool {
  for instr in instrs {
    match instr {
      // All bulk memory/table + segment-based GC array ops are supported via libcalls.
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
    if !@wasmoon_jit.is_jit_supported_module(imp.mod_name) {
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
      let raw_value = @wasmoon_jit.native_value_slot_read(offset, 0)
      // Convert based on global's type
      // Note: For FuncRef, JIT stores module function index, we need to convert
      // it back to store address for the interpreter
      let new_value : @types.Value = match global_inst.get_type().value_type {
        I32 => I32(@types.FromInt64::from_int64_bits(raw_value))
        I64 => I64(@types.FromInt64::from_int64_bits(raw_value))
        F32 => F32(@types.FromInt64::from_int64_bits(raw_value))
        F64 => F64(@types.FromInt64::from_int64_bits(raw_value))
        FuncRef
        | RefFunc
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        | NullFuncRef =>
          if raw_value == 0L {
            Null
          } else if raw_value < 0L {
            // IR-encoded funcref: value = -(func_idx + 1)
            let mod_func_idx = (-(raw_value + 1L)).to_int()
            if mod_func_idx >= 0 && mod_func_idx < jit_ctx.func_addrs.length() {
              FuncRef(jit_ctx.func_addrs[mod_func_idx])
            } else {
              Null
            }
          } else if @wasmoon_jit.is_funcref_ptr(raw_value) {
            let ptr = @wasmoon_jit.untag_funcref_ptr(raw_value)
            let store_addr = match registered_funcref_store_addr(store, ptr) {
              Some(addr) => Some(addr)
              None => {
                let mut found : Int? = None
                for idx, addr in jit_ctx.func_addrs {
                  if jit_ctx.jit_module.get_func_ptr(idx) == ptr {
                    found = Some(addr)
                    break
                  }
                }
                found
              }
            }
            match store_addr {
              Some(addr) => FuncRef(addr)
              None => Null
            }
          } else {
            FuncRef(raw_value.to_int())
          }
        ExternRef | RefExtern | NullExternRef =>
          if raw_value == 0L {
            Null
          } else if (raw_value & EXTERNREF_TAG) != 0L {
            match @wasmoon_jit.decode_externref(raw_value) {
              Some(idx) => ExternRef(idx)
              None => ExternRef(raw_value.to_int())
            }
          } else {
            // Fallback: treat as raw host index
            ExternRef(raw_value.to_int())
          }
        // GC reference types - decode using JIT encoding:
        // null = 0, i31 = (value << 1) | 1, struct/array = gc_ref << 1
        AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
          decode_gc_value(raw_value, store)
        ExnRef | NullExnRef =>
          if raw_value == 0L {
            Null
          } else {
            ExnRef(raw_value.to_int())
          }
        RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs =>
          if raw_value == 0L {
            Null
          } else {
            StructRef(@wasmoon_jit.decode_heap_ref(raw_value))
          }
        RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs =>
          if raw_value == 0L {
            Null
          } else {
            ArrayRef(@wasmoon_jit.decode_heap_ref(raw_value))
          }
        RefI31 | RefNullI31 =>
          if raw_value == 0L {
            Null
          } else if (raw_value & 1L) == 1L {
            I31((raw_value >> 1).to_int())
          } else {
            Null
          }
        RefNone => Null
        V128 => {
          // Read both 64-bit halves and construct V128
          let high_value = @wasmoon_jit.native_value_slot_read(offset, 1)
          V128(@types.int64_pair_to_v128_le(raw_value, high_value))
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
fn encode_global_value_for_jit(
  value : @types.Value,
  jit_module : @jit.JITModule,
  func_addrs : Array[Int],
) -> (Int64, Int64?) {
  match value {
    I32(n) => (@types.ToInt64::to_int64_bits(n), None)
    I64(n) => (@types.ToInt64::to_int64_bits(n), None)
    F32(f) => (@types.ToInt64::to_int64_bits(f), None)
    F64(d) => (@types.ToInt64::to_int64_bits(d), None)
    FuncRef(store_addr) => {
      let mut module_func_idx : Int? = None
      for i, addr in func_addrs {
        if addr == store_addr {
          module_func_idx = Some(i)
          break
        }
      }
      match module_func_idx {
        Some(func_idx) => {
          let func_ptr = jit_module.get_func_ptr(func_idx)
          if func_ptr == 0L {
            (@wasmoon_jit.encode_funcref_idx(func_idx), None)
          } else {
            (@wasmoon_jit.tag_funcref_ptr(func_ptr), None)
          }
        }
        None => (NULL_REF, None)
      }
    }
    ExternRef(idx) => (idx.to_int64(), None)
    ExnRef(idx) => (idx.to_int64(), None)
    ArrayRef(gc_ref) => (@wasmoon_jit.encode_heap_ref(gc_ref), None)
    StructRef(gc_ref) => (@wasmoon_jit.encode_heap_ref(gc_ref), None)
    I31(n) => (@wasmoon_jit.encode_i31(n), None)
    Null => (NULL_REF, None)
    V128(bytes) =>
      if bytes.length() >= 16 {
        (
          @types.bytes_to_int64_le(bytes, 0),
          Some(@types.bytes_to_int64_le(bytes, 8)),
        )
      } else {
        (0L, Some(0L))
      }
  }
}

///|
pub fn sync_store_globals_to_jit(
  jit_ctx : JITModuleContext,
  store : @runtime.Store,
) -> Unit {
  if jit_ctx.globals_ptr == 0L || jit_ctx.global_addrs.is_empty() {
    return
  }
  for i, global_addr in jit_ctx.global_addrs {
    if global_addr < 0 || global_addr >= store.globals.length() {
      continue
    }
    let global_inst = store.globals[global_addr]
    let (low, high) = encode_global_value_for_jit(
      global_inst.get(),
      jit_ctx.jit_module,
      jit_ctx.func_addrs,
    )
    let offset = jit_ctx.globals_ptr + (i * 16).to_int64()
    @wasmoon_jit.native_value_slot_write(offset, 0, low)
    if high is Some(hi) {
      @wasmoon_jit.native_value_slot_write(offset, 1, hi)
    }
  }
}

///|
fn decode_funcref_from_jit_ctx(
  raw_value : Int64,
  jit_ctx : JITModuleContext,
  store : @runtime.Store,
) -> @types.Value {
  if raw_value == NULL_REF {
    return Null
  }
  match @wasmoon_jit.decode_funcref_idx(raw_value) {
    Some(func_idx) =>
      if func_idx >= 0 && func_idx < jit_ctx.func_addrs.length() {
        FuncRef(jit_ctx.func_addrs[func_idx])
      } else {
        Null
      }
    None =>
      if @wasmoon_jit.is_funcref_ptr(raw_value) {
        let ptr = @wasmoon_jit.untag_funcref_ptr(raw_value)
        let store_addr = match registered_funcref_store_addr(store, ptr) {
          Some(addr) => Some(addr)
          None => {
            let mut found : Int? = None
            for idx, addr in jit_ctx.func_addrs {
              if jit_ctx.jit_module.get_func_ptr(idx) == ptr {
                found = Some(addr)
                break
              }
            }
            found
          }
        }
        match store_addr {
          Some(addr) => FuncRef(addr)
          None => Null
        }
      } else {
        FuncRef(raw_value.to_int())
      }
  }
}

///|
fn decode_table_entry_value(
  elem_type : @types.ValueType,
  raw_value : Int64,
  store : @runtime.Store,
  jit_ctx : JITModuleContext,
) -> @types.Value {
  match elem_type {
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      decode_funcref_from_jit_ctx(raw_value, jit_ctx, store)
    ExternRef | RefExtern | NullExternRef =>
      if raw_value == NULL_REF {
        Null
      } else {
        match @wasmoon_jit.decode_externref(raw_value) {
          Some(idx) => ExternRef(idx)
          None => ExternRef(raw_value.to_int())
        }
      }
    AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
      if raw_value == NULL_REF {
        Null
      } else if (raw_value & EXTERNREF_TAG) != 0L {
        match @wasmoon_jit.decode_externref(raw_value) {
          Some(idx) => ExternRef(idx)
          None => ExternRef(raw_value.to_int())
        }
      } else if @wasmoon_jit.is_funcref_ptr(raw_value) || raw_value < 0L {
        decode_funcref_from_jit_ctx(raw_value, jit_ctx, store)
      } else {
        decode_gc_value(raw_value, store)
      }
    RefI31 | RefNullI31 =>
      if raw_value == NULL_REF {
        Null
      } else if (raw_value & 1L) == 1L {
        I31((raw_value >> 1).to_int())
      } else {
        Null
      }
    RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs =>
      if raw_value == NULL_REF {
        Null
      } else {
        StructRef(@wasmoon_jit.decode_heap_ref(raw_value))
      }
    RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs =>
      if raw_value == NULL_REF {
        Null
      } else {
        ArrayRef(@wasmoon_jit.decode_heap_ref(raw_value))
      }
    _ => Null
  }
}

///|
/// Sync JIT table contents back into interpreter tables.
/// Required when JIT mutates imported/shared tables and later interpreter-based
/// instantiation or evaluation needs to observe those updates.
pub fn sync_jit_tables_to_store(
  jit_ctx : JITModuleContext,
  store : @runtime.Store,
) -> Unit {
  for table_idx, table_addr in jit_ctx.table_addrs {
    let table = store.get_table(table_addr) catch { _ => continue }
    let jit_table = match store.get_jit_table(table_addr) {
      Some(t) => t
      None => continue
    }
    jit_ctx.jit_module.refresh_table_layout(table_idx) |> ignore
    let mut runtime_size = table.size()
    let jit_size = jit_table.get_size()
    if jit_size > runtime_size {
      let delta = jit_size - runtime_size
      if delta > 0 {
        if table.grow(delta, Null) < 0 {
          continue
        }
        runtime_size = table.size()
      }
    }
    let size = if runtime_size < jit_size { runtime_size } else { jit_size }
    let elem_type = table.get_elem_type()
    for i in 0..<size {
      let raw_value = jit_table.get_entry_value(i)
      let decoded = decode_table_entry_value(
        elem_type, raw_value, store, jit_ctx,
      )
      table.set(i, decoded) catch {
        _ => ()
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
  use_subtype_indirect_check? : Bool = false,
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
    sync_table_to_jit(
      table,
      jit_table,
      jit_module,
      instance,
      store,
      use_subtype_indirect_check~,
    )
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
  use_subtype_indirect_check? : Bool = false,
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

  // Build function index -> table entry type mapping.
  // - subtype mode: keep raw type indices
  // - exact mode: use canonical indices for structural equivalence
  let func_table_types : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let mapped_type = if use_subtype_indirect_check {
        type_idx
      } else if type_idx >= 0 && type_idx < canonical_types.length() {
        canonical_types[type_idx]
      } else {
        type_idx
      }
      func_table_types.push(mapped_type)
    }
  }
  for type_idx in mod_.funcs {
    let mapped_type = if use_subtype_indirect_check {
      type_idx
    } else if type_idx >= 0 && type_idx < canonical_types.length() {
      canonical_types[type_idx]
    } else {
      type_idx
    }
    func_table_types.push(mapped_type)
  }

  // Get shared JIT tables from Store (one per runtime table)
  let jit_tables : Array[@wasmoon_jit.JITTable?] = []
  for table_addr in instance.table_addrs {
    let jit_table = store.get_jit_table(table_addr)
    jit_tables.push(jit_table)
  }

  // Build store func address -> module func index map.
  let func_addr_to_idx : Map[Int, Int] = Map([])
  for i, addr in instance.func_addrs {
    func_addr_to_idx.set(addr, i)
  }

  // Initialize elements: (table_idx, elem_idx, func_idx?, canonical_type_idx)
  // Copy from instantiated runtime table state so we preserve:
  // - table declaration init expressions
  // - active element segment effects
  // - imported/exported table sharing behavior
  let elem_init : Array[(Int, Int, Int?, Int)] = []
  for table_idx, table_addr in instance.table_addrs {
    let runtime_table = store.get_table(table_addr) catch { _ => continue }
    let max_entries = match jit_tables[table_idx] {
      Some(t) => t.get_size()
      None => 0
    }
    let size = runtime_table.size().min(max_entries)
    for elem_idx in 0..<size {
      let value = runtime_table.get(elem_idx) catch { _ => continue }
      match value {
        FuncRef(store_addr) => {
          let func_idx = func_addr_to_idx.get(store_addr)
          let canonical_type_idx = match func_idx {
            Some(idx) =>
              if idx >= 0 && idx < func_table_types.length() {
                func_table_types[idx]
              } else {
                -1
              }
            None => -1
          }
          elem_init.push((table_idx, elem_idx, func_idx, canonical_type_idx))
        }
        _ => elem_init.push((table_idx, elem_idx, None, -1))
      }
    }
  }

  // Initialize shared tables
  jm.init_shared_tables(jit_tables, elem_init)
}

///|
/// Initialize per-context data/elem segments for bulk memory/table and GC segment ops.
///
/// This feeds JIT libcalls used by:
/// - memory.init / data.drop
/// - table.init / table.copy / table.fill / elem.drop
/// - array.new_data / array.init_data / array.new_elem / array.init_elem
///
/// Element segments are stored as (value, type_idx) pairs so call_indirect can
/// type-check after table.init/table.fill.
pub fn init_bulk_segments(
  mod_ : @types.Module,
  jm : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  use_subtype_indirect_check? : Bool = false,
) -> Unit raise @runtime.RuntimeError {
  // Precompute canonical indices for type equivalence.
  let canonical = @types.compute_canonical_type_indices(
    mod_.types,
    type_rec_groups=mod_.type_rec_groups,
  )

  // Build func_idx -> table entry type idx mapping in module index space.
  // - subtype mode: raw indices
  // - exact mode: canonical indices
  let func_table_types : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let mapped = if use_subtype_indirect_check {
        type_idx
      } else if type_idx >= 0 && type_idx < canonical.length() {
        canonical[type_idx]
      } else {
        -1
      }
      func_table_types.push(mapped)
    }
  }
  for type_idx in mod_.funcs {
    let mapped = if use_subtype_indirect_check {
      type_idx
    } else if type_idx >= 0 && type_idx < canonical.length() {
      canonical[type_idx]
    } else {
      -1
    }
    func_table_types.push(mapped)
  }

  // Build store func_addr -> module func_idx map (for GlobalGet funcref).
  let func_addr_to_idx : Map[Int, Int] = Map([])
  for i, addr in instance.func_addrs {
    func_addr_to_idx.set(addr, i)
  }

  // Get globals for GlobalGet evaluation.
  let globals : Array[@runtime.GlobalInstance] = []
  for addr in instance.global_addrs {
    let g = store.get_global(addr) catch { _ => continue }
    globals.push(g)
  }

  // Initial dropped flags from the instantiated instance state.
  let data_dropped : Array[Bool] = []
  for i in 0..<mod_.datas.length() {
    data_dropped.push(
      i >= 0 && i < instance.dropped_datas.length() && instance.dropped_datas[i],
    )
  }
  let elem_dropped : Array[Bool] = []
  for i, elem in mod_.elems {
    let dropped = i >= 0 &&
      i < instance.dropped_elems.length() &&
      instance.dropped_elems[i]
    // Declarative segments behave as dropped for table.init/array.new_elem.
    let declarative = elem.mode is Declarative
    elem_dropped.push(dropped || declarative)
  }

  // Build element segment (value,type) pairs.
  // We evaluate element init expressions using the executor's extended const-expr
  // evaluator so GC const exprs (array.new, struct.new, ref.i31, etc.) work.
  let elem_pairs : Array[Array[Int64]] = []
  for elem in mod_.elems {
    let pairs : Array[Int64] = []
    for init_expr in elem.init {
      // Evaluate the const expression to a runtime Value.
      let value = @executor.eval_const_expr(
        init_expr,
        func_addrs=instance.func_addrs,
        globals~,
        store=Some(store),
        types=mod_.types,
      )

      // Encode the value to the JIT segment format (value bits + type idx for funcref).
      let mut raw = @wasm_milkir.NULL_REF
      let mut ty = -1L
      match value {
        Null => ()
        I31(n) => raw = @wasmoon_jit.encode_i31(n)
        ExternRef(host_idx) => raw = @wasmoon_jit.encode_externref(host_idx)
        StructRef(idx) =>
          // JIT GC refs are encoded as (gc_ref << 1), where gc_ref = idx + 1.
          raw = (idx + 1).to_int64() << 1
        ArrayRef(idx) => raw = (idx + 1).to_int64() << 1
        FuncRef(store_addr) =>
          match func_addr_to_idx.get(store_addr) {
            Some(func_idx) => {
              let ptr = jm.get_func_ptr(func_idx)
              let t = if func_idx >= 0 && func_idx < func_table_types.length() {
                func_table_types[func_idx]
              } else {
                -1
              }
              ty = t.to_int64()
              raw = if ptr != 0L {
                @wasmoon_jit.tag_funcref_ptr(ptr)
              } else {
                @wasmoon_jit.encode_funcref_idx(func_idx)
              }
            }
            None => ()
          }
        // Numeric / unsupported values are not valid in element segments.
        _ => ()
      }
      pairs.push(raw)
      pairs.push(ty)
    }
    elem_pairs.push(pairs)
  }
  jm.setup_segments(mod_.datas, elem_pairs, data_dropped~, elem_dropped~)
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
  // Fill in signatures for import functions.
  // NOTE: import list index is not function-index space; only Func imports
  // consume function indices. Keep an explicit function-import cursor.
  let mut func_import_idx = 0
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      if func_import_idx >= 0 &&
        func_import_idx < signatures.length() &&
        type_idx >= 0 &&
        type_idx < mod_.types.length() {
        let func_type = mod_.validated_func_type_at(type_idx)
        signatures[func_import_idx] = (
          func_type.params.copy(),
          func_type.results.copy(),
        )
      }
      func_import_idx = func_import_idx + 1
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.validated_func_type_at(type_idx)
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
  jit_table : @wasmoon_jit.JITTable,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  use_subtype_indirect_check? : Bool = false,
) -> Unit {
  let runtime_size = table.size()
  let jit_size = jit_table.get_size()
  let size = if runtime_size < jit_size { runtime_size } else { jit_size }
  for i in 0..<size {
    let value = table.get(i) catch { _ => continue }
    let mut encoded : Int64 = NULL_REF
    let mut type_idx : Int = -1
    match value {
      Null => {
        encoded = NULL_REF
        type_idx = -1
      }
      I31(n) => encoded = @wasmoon_jit.encode_i31(n)
      StructRef(idx) | ArrayRef(idx) =>
        // gc_ref is 1-based for the JIT/C heap: (idx + 1) << 1
        encoded = (idx + 1).to_int64() << 1
      ExternRef(host_idx) => encoded = @wasmoon_jit.encode_externref(host_idx)
      FuncRef(store_addr) => {
        encoded = encode_store_funcref_for_jit(
          value, store, jit_module, instance,
        )
        let mut resolved_type_idx = -1
        match store_addr_to_module_func_idx(store_addr, instance) {
          Some(func_idx) =>
            if func_idx >= 0 && func_idx < instance.func_type_indices.length() {
              let raw_type_idx = instance.func_type_indices[func_idx]
              resolved_type_idx = if use_subtype_indirect_check {
                raw_type_idx
              } else if raw_type_idx >= 0 &&
                raw_type_idx < instance.canonical_type_indices.length() {
                instance.canonical_type_indices[raw_type_idx]
              } else {
                raw_type_idx
              }
            }
          None => ()
        }
        if resolved_type_idx < 0 &&
          store_addr >= 0 &&
          store_addr < store.func_type_indices.length() {
          let raw_type_idx = store.func_type_indices[store_addr]
          resolved_type_idx = if use_subtype_indirect_check {
            raw_type_idx
          } else {
            store.get_func_canonical_type_idx(store_addr)
          }
        }
        type_idx = resolved_type_idx
      }
      // Numeric types shouldn't be present in reference tables.
      _ => encoded = NULL_REF
    }
    jit_table.set(i, encoded, type_idx)
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
fn low_u32_bits(raw : Int64) -> Int {
  (raw & 0xFFFFFFFFL).to_int()
}

///|
fn lookup_funcref_ptr_for_store_addr(
  store : @runtime.Store,
  store_addr : Int,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Int64? {
  match store_addr_to_module_func_idx(store_addr, instance) {
    Some(func_idx) => {
      let ptr = jit_module.get_func_ptr(func_idx)
      if ptr != 0L {
        return Some(ptr)
      }
    }
    None => ()
  }
  registered_funcref_ptr(store, store_addr)
}

///|
fn lookup_store_addr_for_funcref_ptr(
  store : @runtime.Store,
  func_ptr : Int64,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Int? {
  match registered_funcref_store_addr(store, func_ptr) {
    Some(addr) => return Some(addr)
    None => ()
  }
  match jit_module.find_func_by_pc(func_ptr) {
    Some((func_idx, _, _)) =>
      if func_idx >= 0 && func_idx < instance.func_addrs.length() {
        let addr = instance.func_addrs[func_idx]
        return Some(addr)
      }
    None => ()
  }
  let func_count = jit_module.get_func_count()
  for func_idx in 0..<func_count {
    if func_idx >= 0 &&
      func_idx < instance.func_addrs.length() &&
      jit_module.get_func_ptr(func_idx) == func_ptr {
      let addr = instance.func_addrs[func_idx]
      return Some(addr)
    }
  }
  None
}

///|
fn decode_funcref_to_store_addr(
  raw : Int64,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> @types.Value {
  if raw == NULL_REF {
    return Null
  }
  match @wasmoon_jit.decode_funcref_idx(raw) {
    Some(mod_func_idx) =>
      if mod_func_idx >= 0 && mod_func_idx < instance.func_addrs.length() {
        FuncRef(instance.func_addrs[mod_func_idx])
      } else {
        Null
      }
    None =>
      if @wasmoon_jit.is_funcref_ptr(raw) {
        let ptr = @wasmoon_jit.untag_funcref_ptr(raw)
        match
          lookup_store_addr_for_funcref_ptr(store, ptr, jit_module, instance) {
          Some(addr) => FuncRef(addr)
          None => Null
        }
      } else {
        // Fallback: treat as a store address (best-effort).
        FuncRef(raw.to_int())
      }
  }
}

///|
fn encode_store_funcref_for_jit(
  value : @types.Value,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Int64 {
  match value {
    Null => NULL_REF
    FuncRef(store_addr) =>
      match
        lookup_funcref_ptr_for_store_addr(
          store, store_addr, jit_module, instance,
        ) {
        Some(ptr) => @wasmoon_jit.tag_funcref_ptr(ptr)
        None =>
          match store_addr_to_module_func_idx(store_addr, instance) {
            Some(func_idx) => @wasmoon_jit.encode_funcref_idx(func_idx)
            None => NULL_REF
          }
      }
    _ => NULL_REF
  }
}

///|
fn encode_exception_value_for_jit(
  value : @types.Value,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Int64? {
  match value {
    I32(n) => Some(@types.ToInt64::to_int64_bits(n))
    I64(n) => Some(@types.ToInt64::to_int64_bits(n))
    F32(n) => Some(@types.ToInt64::to_int64_bits(n))
    F64(n) => Some(@types.ToInt64::to_int64_bits(n))
    Null => Some(NULL_REF)
    FuncRef(_) =>
      Some(encode_store_funcref_for_jit(value, store, jit_module, instance))
    ExternRef(idx) => Some(@wasmoon_jit.encode_externref(idx))
    StructRef(idx) => Some(@wasmoon_jit.encode_heap_ref(idx))
    ArrayRef(idx) => Some(@wasmoon_jit.encode_heap_ref(idx))
    I31(n) => Some(@wasmoon_jit.encode_i31(n))
    ExnRef(idx) => Some(idx.to_int64())
    V128(_) => None
  }
}

///|
fn decode_ref_value(
  ty : @types.ValueType,
  raw : Int64,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> @types.Value {
  match ty {
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      decode_funcref_to_store_addr(raw, store, jit_module, instance)
    ExternRef | RefExtern | NullExternRef =>
      if raw == NULL_REF {
        Null
      } else {
        match @wasmoon_jit.decode_externref(raw) {
          Some(idx) => ExternRef(idx)
          None => ExternRef(raw.to_int())
        }
      }
    ExnRef | NullExnRef =>
      if raw == NULL_REF {
        Null
      } else {
        ExnRef(raw.to_int())
      }
    StructRef | RefStruct(_) | RefNullStruct(_) | RefStructAbs =>
      if raw == NULL_REF {
        Null
      } else {
        StructRef(@wasmoon_jit.decode_heap_ref(raw))
      }
    ArrayRef | RefArray(_) | RefNullArray(_) | RefArrayAbs =>
      if raw == NULL_REF {
        Null
      } else {
        ArrayRef(@wasmoon_jit.decode_heap_ref(raw))
      }
    AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
      if raw == NULL_REF {
        Null
      } else if (raw & 1L) == 1L {
        I31((raw >> 1).to_int())
      } else {
        let heap_idx = @wasmoon_jit.decode_heap_ref(raw)
        match store.c_heap {
          Some(heap) =>
            if heap.is_array(heap_idx) {
              ArrayRef(heap_idx)
            } else {
              StructRef(heap_idx)
            }
          None => StructRef(heap_idx)
        }
      }
    RefI31 | RefNullI31 =>
      if raw == NULL_REF {
        Null
      } else if (raw & 1L) == 1L {
        I31((raw >> 1).to_int())
      } else {
        Null
      }
    RefNone => Null

    // Non-ref types should not reach here.
    _ => Null
  }
}

///|
fn decode_value(
  ty : @types.ValueType,
  slot_idx : Int,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> (@types.Value, Int) {
  match ty {
    I32 =>
      (I32(low_u32_bits(@wasmoon_jit.hostcall_value_slot_read(slot_idx))), 1)
    I64 => (I64(@wasmoon_jit.hostcall_value_slot_read(slot_idx)), 1)
    F32 => {
      let bits = low_u32_bits(@wasmoon_jit.hostcall_value_slot_read(slot_idx))
      (F32(Float::reinterpret_from_int(bits)), 1)
    }
    F64 => {
      let raw = @wasmoon_jit.hostcall_value_slot_read(slot_idx)
      (F64(raw.reinterpret_as_double()), 1)
    }
    V128 => {
      let lo = @wasmoon_jit.hostcall_value_slot_read(slot_idx)
      let hi = @wasmoon_jit.hostcall_value_slot_read(slot_idx + 1)
      (V128(@types.int64_pair_to_v128_le(lo, hi)), 2)
    }
    _ =>
      (
        decode_ref_value(
          ty,
          @wasmoon_jit.hostcall_value_slot_read(slot_idx),
          store,
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
  store : @runtime.Store,
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
            let lo = @types.bytes_to_int64_le(bytes, 0)
            let hi = @types.bytes_to_int64_le(bytes, 8)
            Some([lo, hi])
          } else {
            None
          }
        _ => None
      }
    // References.
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      Some([encode_store_funcref_for_jit(value, store, jit_module, instance)])
    ExternRef | RefExtern | NullExternRef =>
      match value {
        Null => Some([NULL_REF])
        ExternRef(idx) => Some([@wasmoon_jit.encode_externref(idx)])
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
        StructRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)])
        ArrayRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)]) // best-effort
        _ => None
      }
    ArrayRef | RefArray(_) | RefNullArray(_) | RefArrayAbs =>
      match value {
        Null => Some([NULL_REF])
        ArrayRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)])
        StructRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)]) // best-effort
        _ => None
      }
    AnyRef | NullRef | RefAny | RefEq | RefNullEq =>
      match value {
        Null => Some([NULL_REF])
        I31(n) => Some([@wasmoon_jit.encode_i31(n)])
        StructRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)])
        ArrayRef(idx) => Some([@wasmoon_jit.encode_heap_ref(idx)])
        _ => None
      }
    RefI31 | RefNullI31 =>
      match value {
        Null => Some([NULL_REF])
        I31(n) => Some([@wasmoon_jit.encode_i31(n)])
        _ => None
      }
    RefNone => Some([NULL_REF])
  }
}

///|
fn runtime_error_to_trap_code(err : @runtime.RuntimeError) -> Int {
  match err {
    OutOfBoundsMemoryAccess => 1
    CallStackExhausted => 2
    Unreachable => 3
    IndirectCallTypeMismatch => 4
    InvalidConversion => 5
    DivisionByZero => 6
    IntegerOverflow => 7
    OutOfMemory => 9
    _ => 99
  }
}

///|
/// Build `external_imports` for `JITModule::load_artifact_with_imports`.
///
/// For function imports without built-in trampolines, we pass a special
/// negative encoding `-(addr+1)` (store function address) to instruct the JIT
/// loader to generate a hostcall trampoline that dispatches host/wasm imports.
pub fn build_external_imports_for_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Map[String, Map[String, Int64]] {
  let external : Map[String, Map[String, Int64]] = Map([])
  let mut func_imp_idx = 0
  for imp in mod_.imports {
    if imp.desc is Func(_) {
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
      if @wasmoon_jit.get_import_trampoline(imp.mod_name, imp.name) is Some(_) {
        continue
      }
      if store.get_func_inst_opt(func_addr) is None {
        continue
      }
      let encoded = -(func_addr.to_int64() + 1L)
      let m = match external.get(imp.mod_name) {
        Some(mm) => mm
        None => Map([])
      }
      m.set(imp.name, encoded)
      external.set(imp.mod_name, m)
    }
  }
  external
}

///|
fn find_local_tag_idx(
  caller_instance : @runtime.ModuleInstance,
  tag_addr : Int,
) -> Int? {
  for i, addr in caller_instance.tag_addrs {
    if addr == tag_addr {
      return Some(i)
    }
  }
  None
}

///|
priv enum ImportedCallOutcome {
  ImportedReturned(Array[@types.Value])
  ImportedThrown(Int, Array[@types.Value])
  ImportedPending
}

///|
/// Install a JIT hostcall dispatcher closure on this module context.
///
/// This enables arbitrary imported host functions (stored in `store`) to be
/// called from JIT-compiled wasm via `wasmoon_jit_hostcall`.
pub fn JITModuleContext::install_hostcall_dispatcher(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  before_dispatch? : () -> Unit = fn() { () },
  after_dispatch? : () -> Unit = fn() { () },
  classify_suspension? : (@runtime.RuntimeError) -> Bool = fn(_error) { false },
) -> Unit {
  let jit_module = self.jit_module
  fn call_func_by_addr(
    store : @runtime.Store,
    caller_instance : @runtime.ModuleInstance,
    func_addr : Int,
    args : Array[@types.Value],
  ) -> ImportedCallOutcome raise @runtime.RuntimeError {
    let inst = store.get_func_inst(func_addr)
    match inst {
      HostFunc(f) => {
        let caller = @runtime.Caller::Caller(store, caller_instance)
        ImportedReturned(f(caller, args))
      }
      AsyncHostFunc(f) => {
        guard store.native_execution_state().current_invocation()
          is Some(invocation_id) else {
          raise AsyncHostRequiresAsyncCall
        }
        guard self.async_host_drivers.get(invocation_id) is Some(driver) else {
          let error = @runtime.AsyncHostRequiresAsyncCall
          self.async_host_errors.set(invocation_id, error)
          raise error
        }
        let caller = @runtime.Caller::Caller(store, caller_instance)
        let polled = driver.poll(func_addr, f, caller, args)
        match polled {
          AsyncHostReady(values) => ImportedReturned(values)
          AsyncHostPending => ImportedPending
        }
      }
      WasmFunc(_) => {
        let owner = match store.get_func_owner(func_addr) {
          Some(owner_instance) => owner_instance
          None => raise UndefinedElement
        }
        let mut func_idx = -1
        for i, addr in owner.func_addrs {
          if addr == func_addr {
            func_idx = i
            break
          }
        }
        if func_idx < 0 {
          raise UndefinedElement
        }
        match
          @executor.call_func_by_index_with_exception(
            store, owner, func_idx, args,
          ) {
          Returned(values) => ImportedReturned(values)
          Thrown(tag_addr, values) => ImportedThrown(tag_addr, values)
        }
      }
    }
  }

  jit_module.set_hostcall_callback(fn() {
    let func_addr = @wasmoon_jit.get_hostcall_func_addr()
    let arg_slots = @wasmoon_jit.get_hostcall_num_arg_slots()
    let res_slots = @wasmoon_jit.get_hostcall_num_result_slots()
    let ft = match store.get_func_type_opt(func_addr) {
      Some(t) => t
      None => return HostcallTrap(3)
    }
    if sum_slot_count(ft.params) != arg_slots ||
      sum_slot_count(ft.results) != res_slots {
      return HostcallTrap(3)
    }

    // Decode args.
    let args : Array[@types.Value] = []
    let mut slot = 0
    for ty in ft.params {
      let (v, used) = decode_value(ty, slot, store, jit_module, instance)
      args.push(v)
      slot = slot + used
    }

    // Imported code observes interpreter-owned globals and tables. Publish the
    // caller's native state before dispatch, then pull mutations back before
    // returning to native code.
    before_dispatch()
    let invoke_result = call_func_by_addr(store, instance, func_addr, args) catch {
      e => {
        after_dispatch()
        if store.get_func_inst_opt(func_addr) is Some(AsyncHostFunc(_)) {
          if store.native_execution_state().current_invocation()
            is Some(invocation_id) {
            self.async_host_errors.set(invocation_id, e)
          }
        }
        if classify_suspension(e) {
          return HostcallSuspended
        }
        return HostcallTrap(runtime_error_to_trap_code(e))
      }
    }
    after_dispatch()
    let results : Array[@types.Value] = match invoke_result {
      ImportedReturned(values) => values
      ImportedPending => return HostcallSuspended
      ImportedThrown(tag_addr, values) => {
        let local_tag_idx = find_local_tag_idx(instance, tag_addr).unwrap_or(-1)
        // Imported wasm callees can throw; route the exception into the active
        // JIT try_table chain instead of flattening it to a generic trap.
        if values.length() == 0 {
          jit_module.throw_exception_tag(local_tag_idx)
        } else {
          let encoded_values : Array[Int64] = []
          for v in values {
            match
              encode_exception_value_for_jit(v, store, jit_module, instance) {
              Some(raw) => encoded_values.push(raw)
              None => return HostcallTrap(8)
            }
          }
          jit_module.throw_exception_values(local_tag_idx, encoded_values)
        }
        return HostcallTrap(8)
      }
    }
    if results.length() != ft.results.length() {
      return HostcallTrap(3)
    }

    // Encode results right after the arg slots region.
    let mut out_slot = arg_slots
    for i, ty in ft.results {
      let slots = encode_value(ty, results[i], store, jit_module, instance)
      match slots {
        None => return HostcallTrap(3)
        Some(encoded_slots) => {
          for j in 0..<encoded_slots.length() {
            @wasmoon_jit.hostcall_value_slot_write(
              out_slot + j,
              encoded_slots[j],
            )
          }
          out_slot = out_slot + encoded_slots.length()
        }
      }
    }
    HostcallCompleted
  })
}
