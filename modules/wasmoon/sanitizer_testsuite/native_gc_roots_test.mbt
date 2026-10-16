///|
fn build_gc_root_context(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> @wast.JITModuleContext raise {
  guard @commands.compile_module_to_jit(
      mod_,
      false,
      false,
      0,
      false,
      nan_canonicalization=store.nan_canonicalization,
      enable_cancellation=false,
      stack_switching=true,
    )
    is Some((artifact, debug_db)) else {
    fail("JIT compilation failed")
  }
  let loaded = @commands.verify_compiled_jit_artifact(artifact)
  let jit_module = @jit.JITModule::load_artifact_with_imports(
    loaded,
    @wast.build_func_signatures(mod_),
    @wast.build_external_imports_for_jit(mod_, instance, store),
    function_names=@commands.build_jit_function_names(mod_),
    debug_db~,
  )
  assert_true(jit_module.set_cooperative_scheduling(false))
  @wast.register_instance_funcrefs_for_jit(jit_module, instance, store)
  jit_module.configure_native_fiber_stack_size(1048576L) |> ignore
  @wast.init_jit_memories_from_store(instance, store, jit_module) |> ignore
  let globals_ptr = @wast.init_jit_globals_from_store(
    instance, store, jit_module,
  )
  @wast.init_elem_segments(
    mod_,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  )
  @wast.init_bulk_segments(
    mod_,
    jit_module,
    instance,
    store,
    use_subtype_indirect_check=true,
  )
  @wast.sync_tables_to_jit(
    instance,
    store,
    jit_module,
    use_subtype_indirect_check=true,
  )
  JITModuleContext(
    jit_module,
    globals_ptr,
    instance.global_addrs[:].to_owned(),
    instance.table_addrs[:].to_owned(),
    instance.func_addrs[:].to_owned(),
    instance.func_type_indices[:].to_owned(),
    instance.canonical_type_indices[:].to_owned(),
    mod_.types.copy(),
    mod_.type_rec_groups.copy(),
    true,
  )
}

///|
test "guest continuation roots retire after bound and suspended handles are dropped" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $f (func (param (ref $s)) (result i32))) (type $c (cont $f))
    #|  (type $rest (func (result i32))) (type $k (cont $rest))
    #|  (tag $yield)
    #|  (global $saved (mut (ref null $k)) (ref.null $k))
    #|  (func $body (type $f) suspend $yield local.get 0 struct.get $s 0)
    #|  (elem declare func $body)
    #|  (func (export "bind") (param (ref $s))
    #|    (global.set $saved (cont.bind $c $k (local.get 0) (cont.new $c (ref.func $body)))))
    #|  (func (export "park") (param (ref $s))
    #|    (block $suspended (result (ref $k))
    #|      (resume $c (on $yield $suspended) (local.get 0) (cont.new $c (ref.func $body)))
    #|      unreachable)
    #|    global.set $saved)
    #|  (func (export "drop") (global.set $saved (ref.null $k)))
    #|  (func (export "finish") (result i32) (resume $k (global.get $saved))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_, stack_switching=true)
  for mode in 0..<3 {
    let store = if mode == 0 {
      @runtime.Store()
    } else {
      @runtime.Store::with_c_heap()
    }
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = if mode == 2 {
      Some(build_gc_root_context(module_, instance, store))
    } else {
      None
    }
    defer (if context is Some(context) { context.close() })
    let call = fn(name, args) raise {
      if context is Some(context) {
        let index = instance.exports
          .iter()
          .find_first(e => e.name == name)
          .unwrap().desc
        guard index is Func(index) else { fail("missing function export") }
        context.call_core_func(store, instance, index, args)
      } else {
        @executor.call_exported_func(store, instance, name, args)
      }
    }
    for name in ["bind", "park"] {
      let child = store.alloc_struct(0, [I32(42)], instance~)
      call(name, [StructRef(child)]) |> ignore
      inspect(store.collect_garbage(), content="0")
      call("drop", []) |> ignore
      inspect(store.collect_garbage(), content="1")
      inspect(store.is_gc_valid(child), content="false")
      inspect(store.collect_garbage(), content="0")
    }
    let live = store.alloc_struct(0, [I32(42)], instance~)
    call("park", [StructRef(live)]) |> ignore
    inspect(store.collect_garbage(), content="0")
    debug_inspect(call("finish", []), content="[I32(42)]")
    inspect(store.collect_garbage(), content="1")
  }
}

///|
test "JIT segment drops retire Store roots and are visible to the interpreter" {
  let module_ = @wat.parse(
    (
      #|(module
      #|  (type $s (struct (field i32)))
      #|  (type $a (array (mut (ref $s))))
      #|  (elem $objects (ref $s) (item (struct.new $s (i32.const 42))))
      #|  (memory 1) (data $bytes "hello")
      #|  (func (export "drop") elem.drop $objects data.drop $bytes)
      #|  (func (export "read") (result i32)
      #|    (struct.get $s 0 (array.get $a (array.new_elem $a $objects (i32.const 0) (i32.const 1)) (i32.const 0))))
      #|  (func (export "load") (memory.init $bytes (i32.const 0) (i32.const 0) (i32.const 1))))
    ),
  )
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  inspect(store.collect_garbage(), content="0")
  context.call_core_func(store, instance, 0, []) |> ignore
  inspect(store.collect_garbage(), content="1")
  inspect(instance.element_values(0).length(), content="0")
  for name in ["read", "load"] {
    try @executor.call_exported_func(store, instance, name, []) catch {
      _ => ()
    } noraise {
      _ => fail("interpreter used a dropped native segment")
    }
  }
}

///|
test "native exception spills and scalar payloads are not conservative GC roots" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (import "host" "gc" (func $gc (result i32)))
    #|  (tag $e (param i32))
    #|  (func (export "spill") (param i32) (result i32)
    #|    (try_table (result i32) (call $gc)))
    #|  (func (export "payload") (param i32) (result i32) (local i32)
    #|    (block $caught (result i32)
    #|      (try_table (catch $e $caught) (throw $e (local.get 0))) unreachable)
    #|    local.set 1
    #|    call $gc))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for native in [false, true] {
    let store = @runtime.Store::with_c_heap()
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    linker.add_host_func(
      "host",
      "gc",
      fn(_) { [I32(store.collect_garbage())] },
      func_type={ params: [], results: [I32], },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    let context = build_gc_root_context(module_, instance, store)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    for index, name in ["spill", "payload"] {
      let child = store.alloc_struct(0, [I32(42)], instance~)
      let scalar : @types.Value = I32((child + 1) << 1)
      let results = if native {
        context.call_core_func(store, instance, index + 1, [scalar])
      } else {
        @executor.call_exported_func(store, instance, name, [scalar])
      }
      debug_inspect(results, content="[I32(1)]")
      inspect(store.is_gc_valid(child), content="false")
    }
  }
}
