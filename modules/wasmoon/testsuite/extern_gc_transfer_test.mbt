///|
test "GC transfer: externref global preserves wrapped i31" {
  let source =
    #|(module
    #|  (global $g externref (extern.convert_any (ref.i31 (i32.const 55))))
    #|  (func (export "test") (result i32)
    #|    global.get $g any.convert_extern ref.cast (ref i31) i31.get_s))
  debug_inspect(run_interp_only(source, "test", []), content="Ok([I32(55)])")
  inspect(compare_jit_interp(source, "test", []), content="matched")
}

///|
test "GC transfer: wrapped objects cross results arguments globals and tables" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (global $g (mut externref) (extern.convert_any (struct.new $s (i32.const 55))))
    #|  (table 1 externref)
    #|  (func (export "read") (result i32)
    #|    global.get $g any.convert_extern ref.cast (ref $s) struct.get $s 0)
    #|  (func (export "roundtrip") (param externref) (result externref)
    #|    local.get 0 global.set $g
    #|    i32.const 0 global.get $g table.set
    #|    i32.const 0 table.get)
    #|  (func (export "make") (result externref)
    #|    i32.const 77 struct.new $s extern.convert_any))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  debug_inspect(
    context.call_core_func(store, instance, 0, []),
    content="[I32(55)]",
  )
  let created = context.call_core_func(store, instance, 2, [])
  let returned = context.call_core_func(store, instance, 1, created)
  inspect(
    store.unwrap_extern(created[0]) == store.unwrap_extern(returned[0]),
    content="true",
  )
  debug_inspect(
    context.call_core_func(store, instance, 0, []),
    content="[I32(77)]",
  )
  let table_value = store.get_table(instance.table_addrs[0]).get(0)
  inspect(
    store.unwrap_extern(table_value) == store.unwrap_extern(created[0]),
    content="true",
  )
  debug_inspect(
    context.call_core_func(store, instance, 1, [ExternRef(0)]),
    content="[ExternRef(0)]",
  )
  debug_inspect(
    context.call_core_func(store, instance, 1, [Null]),
    content="[Null]",
  )
}
