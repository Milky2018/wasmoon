///|
test "jit hostcall: imported host func receives Caller and can access exported memory" {
  let source =
    #|(module
    #|  (import "host" "write_and_add1" (func $h (param i32) (result i32)))
    #|  (memory (export "mem") 1)
    #|  (func (export "run") (param i32) (result i32)
    #|    (call $h (local.get 0))
    #|  )
    #|)

  // Parse module.
  let mod_ = @wat.parse(source) catch { _ => abort("parse failed") }

  // Instantiate with interpreter store + linker-provided host import.
  let linker = @runtime.Linker::new()
  let store = linker.get_store()
  store.enable_c_heap()
  linker.add_host_func_with_caller(
    "host",
    "write_and_add1",
    fn(caller, args) {
      let mem = caller.get_exported_memory("mem") catch { _ => None }
      match mem {
        Some(m) => m.store_i32(0, 123) catch { e => raise e }
        None => raise @runtime.RuntimeError::UndefinedElement
      }
      if args.length() != 1 {
        raise @runtime.RuntimeError::TypeMismatch
      }
      match args[0] {
        @types.Value::I32(n) => [@types.Value::I32(n + 1)]
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
    },
    func_type={
      params: [@types.ValueType::I32],
      results: [@types.ValueType::I32],
    },
  )
  let instance = @executor.instantiate_with_linker(linker, "test", mod_)

  // Compile module to JIT.
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let func_signatures = @wast.build_func_signatures(mod_)
  let num_imports = @wast.count_func_imports(mod_.imports)

  // Record function imports in precompiled module.
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let ft = mod_.get_func_type(type_idx)
      precompiled.add_import(
        imp.mod_name,
        imp.name,
        ft.params.length(),
        ft.results.length(),
      )
    }
  }

  // Compile all funcs.
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
  let external_imports = @wast.build_external_imports_for_jit(
    mod_, instance, store,
  )
  guard @jit.JITModule::load_with_imports(
      precompiled, func_signatures, external_imports,
    )
    is Some(jm) else {
    abort("jit load failed")
  }
  @wast.install_jit_hostcall_dispatcher(jm, store, instance)

  // Init JIT memory from interpreter and execute.
  guard @wast.init_jit_memories_from_store(instance, store, jm) is Some(_) else {
    abort("init jit memories failed")
  }
  let f = jm.get_func_by_name("run").unwrap()
  let raw_results = jm.call_with_context(f, [41L])
  inspect((raw_results[0] & 0xFFFFFFFFL).to_int(), content="42")

  // Host function should have written to the caller's exported memory.
  let mem = store.get_mem(instance.mem_addrs[0]) catch {
    _ => abort("memory missing")
  }
  let v = mem.load_i32(0) catch { _ => -1 }
  inspect(v, content="123")
}
