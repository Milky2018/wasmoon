///|
test "re-exported resources keep the type space of their defining instance" {
  let store = @runtime.Store()
  defer store.close()
  let linker = @runtime.Linker::with_store(store)
  let earlier = @executor.instantiate_module_with_imports(
    store,
    @wat.parse("(module (type (struct (field i64))))"),
    linker.build_imports(),
  )
  linker.register("earlier", earlier)
  let provider_source =
    #|(module
    #|  (type $record (struct (field i32)))
    #|  (table 1 (ref null $record))
    #|  (global (ref null $record) (ref.null $record)))
  let provider = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(provider_source),
    linker.build_imports(),
  )
  linker.add_table("earlier", "table", store.get_table(provider.table_addrs[0]))
  linker.add_global(
    "earlier",
    "global",
    store.get_global(provider.global_addrs[0]),
  )
  let imports = linker.build_imports()
  let valid_source =
    #|(module
    #|  (type $record (struct (field i32)))
    #|  (import "earlier" "table" (table 1 (ref null $record)))
    #|  (import "earlier" "global" (global (ref null $record))))
  let invalid_source =
    #|(module
    #|  (type $record (struct (field i64)))
    #|  (import "earlier" "table" (table 1 (ref null $record)))
    #|  (import "earlier" "global" (global (ref null $record))))
  let valid = @wat.parse(valid_source)
  let invalid = @wat.parse(invalid_source)
  assert_true(
    @executor.validate_imports_with_diagnostics(store, valid, imports).ok,
  )
  let linked = @executor.instantiate_module_with_imports(store, valid, imports)
  assert_eq(linked.table_addrs[0], provider.table_addrs[0])
  assert_eq(linked.global_addrs[0], provider.global_addrs[0])
  let bad = @executor.validate_imports_with_diagnostics(store, invalid, imports)
  inspect(bad.diagnostics.length(), content="2")
  try @executor.instantiate_module_with_imports(store, invalid, imports) catch {
    LinkError => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("an alias changed the type of the imported resource")
  }
}
