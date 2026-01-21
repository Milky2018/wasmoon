///|
/// Helpers for running spec WAST scripts under the JIT in testsuite.
/// These are used to reproduce hang regressions reported in CLI runs.

///|
fn bytes_to_int64_le(bytes : Bytes, offset : Int) -> Int64 {
  let mut result : Int64 = 0L
  for i in 0..<8 {
    result = result | (bytes[offset + i].to_int64() << (i * 8))
  }
  result
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
fn init_jit_globals(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
) -> Int64 {
  let num_globals = instance.global_addrs.length()
  if num_globals == 0 {
    return 0L
  }
  let size = (num_globals * 16).to_int64()
  let globals_ptr = @jit.alloc_memory(size)
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
      F64(d) => @types.ToInt64::to_int64_bits(d)
      FuncRef(store_addr) =>
        match store_addr_to_module_func_idx(store_addr, instance) {
          Some(func_idx) => {
            let func_ptr = jit_module.get_func_ptr(func_idx)
            if func_ptr == 0L {
              @types.NULL_REF
            } else {
              @jit.tag_funcref_ptr(func_ptr)
            }
          }
          None => @types.NULL_REF
        }
      ExternRef(idx) => idx.to_int64()
      ExnRef(idx) => idx.to_int64()
      ArrayRef(gc_ref) => @jit.encode_heap_ref(gc_ref)
      StructRef(gc_ref) => @jit.encode_heap_ref(gc_ref)
      I31(n) => @jit.encode_i31(n)
      Null => @types.NULL_REF
      V128(bytes) => {
        let offset = globals_ptr + (i * 16).to_int64()
        let low = bytes_to_int64_le(bytes, 0)
        let high = bytes_to_int64_le(bytes, 8)
        @jit.c_jit_write_i64(offset, low)
        @jit.c_jit_write_i64(offset + 8L, high)
        continue
      }
    }
    let offset = globals_ptr + (i * 16).to_int64()
    @jit.c_jit_write_i64(offset, raw_value)
  }
  globals_ptr
}

///|
fn compile_module_to_jit(
  mod_ : @types.Module,
  actual_memory_max? : Int? = None,
  opt_level : Int,
) -> @cwasm.PrecompiledModule? {
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let num_imports = @wast.count_func_imports(mod_.imports)
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let func_type = mod_.get_func_type(type_idx)
      precompiled.add_import(
        imp.mod_name,
        imp.name,
        func_type.params.length(),
        func_type.results.length(),
      )
    }
  }
  for i, _ in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    let func_name = @wast.get_func_name(mod_, func_idx)
    let ir_func = @ir.translate_function(
      mod_,
      i,
      name=func_name,
      memory_max_override=actual_memory_max,
    )
    let normalized_opt_level = if opt_level < 0 {
      0
    } else if opt_level > 3 {
      3
    } else {
      opt_level
    }
    @ir.optimize_with_level(
      ir_func,
      @ir.OptLevel::from_int(normalized_opt_level),
    )
    |> ignore
    let vcode_func = @lower.lower_function(
      ir_func,
      num_imports=mod_.imports.length(),
    )
    let allocated = @regalloc.allocate_registers_backtracking(vcode_func)
    let mc = @emit.emit_function(allocated)
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    precompiled.add_function(
      func_idx,
      func_name,
      compiled,
      func_type.params.length(),
      func_type.results.length(),
    )
  }
  Some(precompiled)
}

///|
fn try_compile_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> @wast.JITModuleContext? {
  if @wast.has_unsupported_instructions(mod_) {
    return None
  }
  if @wast.has_cross_module_imports(mod_) {
    return None
  }
  if @wast.exports_shared_resources(mod_) {
    return None
  }
  for imp in mod_.imports {
    if imp.desc is Func(_) &&
      @jit.get_import_trampoline(imp.mod_name, imp.name) is None {
      return None
    }
  }
  let actual_memory_max : Int? = if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => abort("memory missing")
    }
    let (_, max) = mem.get_limits()
    max
  } else {
    None
  }
  let compiled = compile_module_to_jit(mod_, actual_memory_max~, 2)
  match compiled {
    None => None
    Some(pc) => {
      let func_signatures = @wast.build_func_signatures(mod_)
      let jit_module = @jit.JITModule::load(pc, func_signatures)
      match jit_module {
        None => abort("Failed to create JIT module")
        Some(jm) => {
          let _ = jm.alloc_wasm_stack(1048576L)
          jm.init_wasi_quiet([], [], [])
          guard @wast.init_jit_memories_from_store(instance, store, jm)
            is Some(_) else {
            return None
          }
          let globals_ptr = init_jit_globals(instance, store, jm)
          if globals_ptr != 0L {
            jm.set_globals(globals_ptr)
          }
          @wast.init_elem_segments(mod_, jm, instance, store)
          let global_addrs_copy : Array[Int] = []
          for addr in instance.global_addrs {
            global_addrs_copy.push(addr)
          }
          let func_addrs_copy : Array[Int] = []
          for addr in instance.func_addrs {
            func_addrs_copy.push(addr)
          }
          Some(
            @wast.JITModuleContext::new(
              jm, globals_ptr, global_addrs_copy, func_addrs_copy,
            ),
          )
        }
      }
    }
  }
}

///|
fn find_base_dir(path : String) -> String {
  let mut last_slash = -1
  for i in 0..<path.length() {
    if path.code_unit_at(i) == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 {
    let builder = StringBuilder::new()
    for i in 0..<last_slash {
      builder.write_char(path.code_unit_at(i).unsafe_to_char())
    }
    builder.to_string()
  } else {
    "."
  }
}

///|
fn run_wast_with_jit(path : String) -> @wast.WastResult {
  let content = @fs.read_file_to_string(path) catch {
    e => abort("failed to read \{path}: \{e}")
  }
  let script = @wast.parse(content) catch {
    e => abort("failed to parse \{path}: \{e}")
  }
  let jit_compiler = Some(@wast.JITCompiler::new(try_compile_jit))
  let base_dir = find_base_dir(path)
  @wast.run_wast_commands(script, base_dir, true, false, jit_compiler~)
}

///|
test "wast hang regression: align.wast" {
  let result = run_wast_with_jit("spec/align.wast")
  inspect(result.failed, content="0")
}

///|
test "wast hang regression: block.wast" {
  let result = run_wast_with_jit("spec/block.wast")
  inspect(result.failed, content="0")
}

///|
test "wast hang regression: br_on_non_null.wast" {
  let result = run_wast_with_jit("spec/br_on_non_null.wast")
  inspect(result.failed, content="0")
}
