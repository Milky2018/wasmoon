///|
async fn main {
  let bytes = @fs.read_file_to_bytes("/Users/zhengyu/Documents/projects/moonbitlang-core/_build/wasm-gc/debug/test/cmp/cmp.blackbox_test.wasm")
  let start = @async.now()
  let module_ = @parser.parse_module(bytes)
  let parsed = @async.now()
  let validated = @validator.ValidatedModule::new(module_)
  let checked = @async.now()
  let store = @runtime.Store()
  defer store.close()
  let imports = @runtime.Imports(store)
  for import_ in module_.imports {
    match import_.desc {
      Func(index) => {
        let ty = module_.func_type_at(index).unwrap()
        let address = store.alloc_host_func(_ => raise @runtime.Unreachable, func_type=ty)
        imports.add_func(import_.mod_name, import_.name, address)
      }
      Tag(index) => {
        let address = store.alloc_tag(module_.func_type_at(index).unwrap())
        imports.add_tag(import_.mod_name, import_.name, address)
      }
      _ => fail("unexpected non-function/tag import")
    }
  }
  let ready = @async.now()
  @executor.instantiate_validated_module_with_imports_unstarted(store, validated, imports) |> ignore
  let done = @async.now()
  assert_eq(store.counts().globals, module_.globals.length())
  println("real_cmp types=\{module_.types.length()} globals=\{module_.globals.length()} parse_ms=\{parsed-start} validation_ms=\{checked-parsed} imports_ms=\{ready-checked} instantiate_ms=\{done-ready} start_executed=false")
}
