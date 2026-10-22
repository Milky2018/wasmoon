///|
fn build_gc_root_context(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  enable_cancellation~ : Bool = false,
  opt_level~ : Int32 = 0,
) -> @wast.JITModuleContext raise {
  guard @commands.compile_module_to_jit(
      mod_,
      false,
      false,
      opt_level,
      false,
      nan_canonicalization=store.nan_canonicalization,
      enable_cancellation~,
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
    resource_budget=store.resource_budget,
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

///|
fn check_native_table_write_identity(
  instructions : String,
  index : Int32,
  non_nullable~ : Bool = false,
) -> Unit raise {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let padding = @executor.instantiate_module_with_imports(
    store,
    @wat.parse("(module (type (func (param i64))))"),
    Imports(store),
  )
  // The next module's local type zero is not Store identity zero.
  store.native_type_indices(padding) |> ignore
  let table = if non_nullable {
    "(table 1 2 (ref $result) (ref.func $two)) "
  } else {
    "(table 1 2 funcref) "
  }
  let module_ = @wat.parse(
    "(module (type $result (func (result i32))) " +
    table +
    "(func $two (type $result) i32.const 2) (elem $values func $two) " +
    "(func (export \"write\") (result i32) " +
    instructions +
    " i32.const \{index} call_indirect (type $result)) " +
    "(func (export \"read\") (result i32) i32.const \{index} call_indirect (type $result)))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  assert_eq(context.call_core_func(store, instance, 1, []), [I32(2)])
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(2)])
  assert_eq(store.get_table(instance.table_addrs[0]).size(), index + 1)
  let native = store.get_jit_table(instance.table_addrs[0]).unwrap()
  assert_eq(
    native.get_entry_type(index),
    store.get_func_canonical_type_idx(instance.func_addrs[0]),
  )
}

///|
test "table.init writes Store callable identities before an immediate indirect call" {
  check_native_table_write_identity(
    "i32.const 0 i32.const 0 i32.const 1 table.init $values", 0,
  )
}

///|
test "table.grow writes Store callable identities before an immediate indirect call" {
  check_native_table_write_identity(
    "ref.func $two i32.const 1 table.grow drop", 1,
  )
  check_native_table_write_identity(
    "ref.func $two i32.const 1 table.grow drop",
    1,
    non_nullable=true,
  )
}

///|
test "table.init preserves the actual subtype of an imported function" {
  let types = "(type $base (sub (func (result (ref null any))))) " +
    "(type $child (sub $base (func (result (ref null eq))))) "
  let source = @wat.parse(
    "(module " + types + "(func (export \"f\") (type $child) ref.null eq))",
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let original = @executor.instantiate_module_with_imports(
    store,
    source,
    Imports(store),
  )
  let original_context = build_gc_root_context(source, original, store)
  defer original_context.close()
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("a", "f", original.func_addrs[0])
  let module_ = @wat.parse(
    "(module " +
    types +
    "(import \"a\" \"f\" (func $f (type $base))) " +
    "(table 1 2 funcref) (elem $values func $f) " +
    "(func (export \"run\") (result i32) " +
    "i32.const 0 i32.const 0 i32.const 1 table.init $values " +
    "i32.const 0 call_indirect (type $child) ref.is_null) " +
    "(func (export \"grow\") (result i32) ref.func $f i32.const 1 table.grow drop " +
    "i32.const 1 call_indirect (type $child) ref.is_null))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(1)])
}
