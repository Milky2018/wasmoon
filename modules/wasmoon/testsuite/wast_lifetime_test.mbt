///|
test "WAST scripts release stores and every compiled module on success and failure" {
  let baseline = @native_test_support.shared_indirect_table_live_count()
  let source =
    #|(module $same (table 1 funcref) (func (export "f") (result i32) i32.const 7))
    #|(assert_return (invoke "f") (i32.const 7))
    #|(module $same (table 1 funcref) (func (export "f") (result i32) i32.const 8))
    #|(assert_return (invoke "f") (i32.const 8))
    #|(module (table 1 funcref) (func (export "f") (result i32) i32.const 9))
    #|(assert_return (invoke "f") (i32.const 9))
  for should_fail in [false, true] {
    let compiled : Array[@wast.JITModuleContext] = []
    let stores : Array[@runtime.Store] = []
    let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
      try {
        let context = prepare_async_jit_context(mod_, instance, store)
        compiled.push(context)
        stores.push(store)
        Ok(context)
      } catch {
        error => Err("\{error}")
      }
    })
    let script = @wast.parse(
      source +
      (if should_fail {
        "\n(assert_return (invoke \"f\") (i32.const 0))"
      } else {
        ""
      }),
    )
    let result = @wast.run_wast_commands(
      script,
      ".",
      true,
      false,
      jit_compiler=Some(compiler),
    )
    inspect(result.failed == (if should_fail { 1 } else { 0 }), content="true")
    inspect(compiled.length(), content="3")
    for context in compiled {
      inspect(context.jit_module.get_func_count(), content="0")
    }
    for store in stores {
      inspect(store.mems.length(), content="0")
    }
    inspect(
      @native_test_support.shared_indirect_table_live_count() == baseline,
      content="true",
    )
  }
}

///|
test "WAST close is idempotent and rejects subsequent commands" {
  for use_jit in [false, true] {
    let context = @wast.WastContext(use_jit)
    let store = context.get_store()
    inspect(store.mems.length() > 0, content="true")
    context.close()
    context.close()
    inspect(store.mems.length(), content="0")
    let result = @wast.WastResult()
    let script = @wast.parse("(module definition $m)")
    let (command, line) = script.commands[0]
    @wast.run_wast_command(context, command, line, result, ".", false)
    inspect(result.failed, content="1")
    inspect(result.passed, content="0")
  }
}
