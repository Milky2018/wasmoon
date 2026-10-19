///|
async test "completed async host results remain GC roots until consumed" {
  let store = async_gc_test_store()
  defer store.close()
  let struct_type : @types.StructType = {
    fields: [{ storage_type: Val(I32), mutable: false, }],
  }
  store.set_module_types([@types.SubType::simple(Struct(struct_type))])
  let reference = store.alloc_struct(0, [I32(42)])
  let caller = @runtime.Caller(store, store.host_exports([]))
  let returned_reference = @runtime.with_async_host_call_driver(async fn(
    driver,
  ) {
    let host : @runtime.AsyncHostFunction = async fn(_caller, _args) {
      @async.sleep(0)
      Ok([StructRef(reference)])
    }
    guard driver.poll(0, host, caller, []) is AsyncHostPending else {
      fail("expected the first poll to suspend")
    }
    driver.wait_pending()
    inspect(store.collect_garbage(), content="0")
    guard driver.poll(0, host, caller, []) is AsyncHostReady(values) &&
      values is [StructRef(result)] else {
      fail("expected the completed reference result")
    }
    inspect(store.struct_get(result, 0), content="I32(42)")
    inspect(store.collect_garbage(), content="0")
    result
  })
  inspect(returned_reference, content="0")
  inspect(store.collect_garbage(), content="1")
  inspect(store.is_gc_valid(returned_reference), content="false")
}

///|
async test "cancelled async host results cannot retain GC roots" {
  let store = async_gc_test_store()
  defer store.close()
  let struct_type : @types.StructType = {
    fields: [{ storage_type: Val(I32), mutable: false, }],
  }
  store.set_module_types([@types.SubType::simple(Struct(struct_type))])
  let reference = store.alloc_struct(0, [I32(42)])
  let caller = @runtime.Caller(store, store.host_exports([]))
  @runtime.with_async_host_call_driver(async fn(driver) {
    let host : @runtime.AsyncHostFunction = async fn(_caller, _args) {
      @async.protect_from_cancel(async fn() { @async.sleep(0) })
      Ok([StructRef(reference)])
    }
    guard driver.poll(0, host, caller, []) is AsyncHostPending else {
      fail("expected the first poll to suspend")
    }
    @async.sleep(0)
  })
  inspect(store.collect_garbage(), content="1")
  inspect(store.is_gc_valid(reference), content="false")
}

///|
#cfg(target="native")
fn async_gc_test_store() -> @runtime.Store raise @runtime.RuntimeError {
  @runtime.Store::with_c_heap()
}

///|
#cfg(target="wasm")
fn async_gc_test_store() -> @runtime.Store {
  Store()
}
