///|
test "cli jit sync: memory.grow visible after jit" {
  let source =
    #|(module
    #|  (memory (export "mem") 1 3)
    #|  (func (export "grow_and_write")
    #|    (drop (memory.grow (i32.const 1)))
    #|    (i32.store (i32.const 65536) (i32.const 123))
    #|  )
    #|)

  // Instantiate with interpreter store
  let mod_ = @wat.parse(source) catch { _ => abort("parse failed") }
  let linker = @runtime.Linker::new()
  let store = linker.get_store()
  store.enable_c_heap()
  let instance = @executor.instantiate_with_linker(linker, "test", mod_)

  // Compile module to JIT
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let func_signatures = @wast.build_func_signatures(mod_)

  // Compile all funcs
  let num_imports = @wast.count_func_imports(mod_.imports)
  for i, _ in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    let func_name = @wast.get_func_name(mod_, func_idx)
    let ir_func = @ir.translate_function(mod_, i, name=func_name)
    let vcode_func = @lower.lower_function(ir_func)
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
  guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
    abort("jit load failed")
  }

  // Init JIT memory from interpreter and execute
  guard @wast.init_jit_memories_from_store(instance, store, jm) is Some(_) else {
    abort("init jit memories failed")
  }
  let f = jm.get_func_by_name("grow_and_write").unwrap()
  let _ = jm.call_with_context(f, [])

  // Interpreter sees the write in grown page immediately
  let mem = store.get_mem(instance.mem_addrs[0]) catch {
    _ => abort("memory missing")
  }
  let v = mem.load_i32(65536) catch { _ => -1 }
  inspect(v, content="123")
}
