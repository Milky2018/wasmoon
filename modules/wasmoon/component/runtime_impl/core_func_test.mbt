///|
test "host core function allocation preserves a closed Store error" {
  let store = @runtime.Store::Store()
  store.close()
  try
    @runtime_impl.alloc_host_core_func(store, { params: [], results: [] }, fn(
      _args,
    ) {
      []
    })
    |> ignore
  catch {
    StoreClosed => ()
    error => fail("unexpected allocation error: \{error}")
  } noraise {
    _ => fail("expected closed Store allocation to fail")
  }
}
