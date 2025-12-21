// JIT support functions for WAST runner

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
      // User module import - check if it's a global/memory/table
      if imp.desc is (Global(_) | Memory(_) | Table(_)) {
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
    if exp.desc is (Memory(_) | Table(_)) {
      return true
    }
  }
  false
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
        I32 => @types.Value::I32(raw_value.to_int())
        I64 => @types.Value::I64(raw_value)
        F32 =>
          @types.Value::F32(Float::reinterpret_from_int(raw_value.to_int()))
        F64 => @types.Value::F64(raw_value.reinterpret_as_double())
        FuncRef
        | RefFunc
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        | NullFuncRef =>
          if raw_value == -1L {
            @types.Value::Null
          } else {
            // Convert module function index back to store address
            let mod_func_idx = raw_value.to_int()
            if mod_func_idx >= 0 && mod_func_idx < jit_ctx.func_addrs.length() {
              @types.Value::FuncRef(jit_ctx.func_addrs[mod_func_idx])
            } else {
              // Invalid index - treat as null
              @types.Value::Null
            }
          }
        ExternRef | RefExtern | NullExternRef =>
          if raw_value == -1L {
            @types.Value::Null
          } else {
            @types.Value::ExternRef(raw_value.to_int())
          }
        // GC reference types - treat as null for now
        AnyRef | NullRef => @types.Value::Null
        ExnRef | NullExnRef => @types.Value::Null
        V128 => abort("V128 not supported in JIT global sync")
      }
      // We already checked mutability, so set should succeed
      global_inst.set(new_value) catch {
        _ => () // Should not happen since we checked mutability
      }
    }
  }
}

///|
/// Evaluate element segment offset constant expression
/// Supports i32.const, i32.add, i32.sub, i32.mul, global.get for computing offsets
pub fn eval_elem_offset_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      GlobalGet(idx) =>
        if idx < globals.length() && globals[idx].get() is I32(n) {
          stack.push(n)
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

  // Build function index to type hash mapping
  let func_type_hashes : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let type_hash = if type_idx < mod_.types.length() {
        mod_.types[type_idx].structural_hash()
      } else {
        0
      }
      func_type_hashes.push(type_hash)
    }
  }
  for type_idx in mod_.funcs {
    let type_hash = if type_idx < mod_.types.length() {
      mod_.types[type_idx].structural_hash()
    } else {
      0
    }
    func_type_hashes.push(type_hash)
  }

  // Get shared JIT tables from Store (one per runtime table)
  let jit_tables : Array[@jit.JITTable?] = []
  for table_addr in instance.table_addrs {
    let jit_table = store.get_jit_table(table_addr)
    jit_tables.push(jit_table)
  }

  // Initialize elements: (table_idx, elem_idx, func_idx, type_hash)
  let elem_init : Array[(Int, Int, Int, Int)] = []
  for elem in mod_.elems {
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      let offset = eval_elem_offset_expr(offset_expr, globals)
      for i, init_expr in elem.init {
        let func_idx = match init_expr {
          [RefFunc(idx)] => idx
          [I32Const(idx)] => idx
          [RefNull(_)] => -1 // Use -1 to represent null reference
          _ => continue
        }
        let type_hash = if func_idx >= 0 && func_idx < func_type_hashes.length() {
          func_type_hashes[func_idx]
        } else {
          0
        }
        // No flattening: use actual table_idx and elem_idx
        let elem_idx = offset + i
        elem_init.push((table_idx, elem_idx, func_idx, type_hash))
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
      let func_type = mod_.types[type_idx]
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.types[type_idx]
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
