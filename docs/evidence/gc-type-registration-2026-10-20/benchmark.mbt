///|
async fn main {
  for mode in ["raw", "validated"] {
    for trial in 0..<2 {
      for globals in [0, 1, 10, 100] {
        let source = StringBuilder()
        source.write_string("(module\n")
        for i in 1..<=100 {
          source.write_string("(type $t\{i} (struct")
          for _ in 0..<i { source.write_string(" (field i32)") }
          source.write_string("))\n")
        }
        for _ in 0..<globals {
          source.write_string("(global (ref $t1) (struct.new $t1 (i32.const 0)))\n")
        }
        source.write_string(")")
        let start = @async.now()
        let module_ = @wat.parse(source.to_string())
        let parsed = @async.now()
        let validated = @validator.ValidatedModule::new(module_)
        let checked = @async.now()
        let (store, _) = if mode == "raw" {
          @executor.instantiate_module(module_)
        } else {
          @executor.instantiate_validated_module(validated)
        }
        let instantiated = @async.now()
        assert_eq(store.counts().globals, globals)
        store.close()
        println("mode=\{mode} trial=\{trial} types=100 globals=\{globals} parse_ms=\{parsed-start} validation_ms=\{checked-parsed} instantiate_ms=\{instantiated-checked} close_ms=\{@async.now()-instantiated}")
      }
    }
  }
}
