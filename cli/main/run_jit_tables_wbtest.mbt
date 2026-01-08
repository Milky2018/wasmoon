///|
test "run_with_jit: initializes tables for call_indirect" {
  let source =
    #|(module
    #|  (type (;0;) (func (param i32) (result i32)))
    #|  (table (;0;) 1 1 funcref)
    #|  (elem (;0;) (i32.const 0) funcref (ref.func 0))
    #|  (func (;0;) (type 0) (param i32) (result i32)
    #|    local.get 0
    #|  )
    #|  (func (;1;) (type 0) (param i32) (result i32)
    #|    local.get 0
    #|    i32.const 0
    #|    call_indirect (type 0)
    #|  )
    #|  (export "call" (func 1))
    #|)
  let mod_ = @wat.parse(source) catch { e => abort("parse failed: \{e}") }
  let linker = @runtime.Linker::new()
  let store = linker.get_store()
  store.enable_c_heap()
  let imports = linker.build_imports()
  let instance = @executor.instantiate_module_with_imports(store, mod_, imports) catch {
    e => abort("instantiation failed: \{e}")
  }
  let results = run_with_jit(
    mod_,
    instance,
    store,
    "call",
    [@types.Value::I32(42)],
    false,
    false,
    ["test.wasm"],
    [],
    [],
  )
  inspect(results, content="[I32(42)]")
}
