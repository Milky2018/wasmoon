///|
test "native function references retain closed owner code until Store retirement" {
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  store.enable_c_heap()
  let owner_module = @wat.parse(
    (
      #|(module
      #|  (type $get (func (result i32)))
      #|  (global (export "value") (mut i32) (i32.const 11))
      #|  (table (export "table") 1 funcref)
      #|  (func $get (type $get) (result i32)
      #|    global.get 0 i32.const 1 i32.add global.set 0 global.get 0)
      #|  (elem (i32.const 0) $get))
    ),
  )
  let owner = @executor.instantiate_with_linker(linker, "owner", owner_module)
  let owner_code = prepare_async_jit_context(owner_module, owner, store)
  let caller_module = @wat.parse(
    (
      #|(module
      #|  (type $get (func (result i32)))
      #|  (import "owner" "table" (table 1 funcref))
      #|  (import "owner" "value" (global (mut i32)))
      #|  (func (export "call") (result i32)
      #|    global.get 0 i32.const 10 i32.add global.set 0
      #|    i32.const 0 call_indirect (type $get)))
    ),
  )
  let caller = @executor.instantiate_with_linker(
    linker, "caller", caller_module,
  )
  let caller_code = prepare_async_jit_context(caller_module, caller, store)
  owner_code.close()
  debug_inspect(
    caller_code.call_core_func(store, caller, 0, []),
    content="[I32(22)]",
  )
  inspect(store.globals[owner.global_addrs[0]].get(), content="I32(22)")
  store.globals[owner.global_addrs[0]].set(I32(100))
  debug_inspect(
    caller_code.call_core_func(store, caller, 0, []),
    content="[I32(111)]",
  )
  caller_code.close()
  store.close()
  inspect(owner_code.jit_module.get_func_count(), content="0")
  inspect(caller_code.jit_module.get_func_count(), content="0")
  owner_code.close()
  caller_code.close()
}
