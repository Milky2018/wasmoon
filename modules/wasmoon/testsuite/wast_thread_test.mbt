///|
test "WAST nested implicit joins include child assertions" {
  let source =
    #|(thread $outer
    #| (thread $inner
    #|  (module (func (export "run") (result i32) i32.const 42))
    #|  (assert_return (invoke "run") (i32.const 42))))
  let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
  debug_inspect(
    (result.passed, result.failed, result.skipped),
    content="(1, 0, 0)",
  )
}

///|
test "WAST thread assertion failures propagate through joins" {
  let source =
    #|(thread $child
    #| (module (func (export "run") (result i32) i32.const 1))
    #| (assert_return (invoke "run") (i32.const 2)))
    #|(wait $child)
  let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
  debug_inspect(
    (result.passed, result.failed, result.skipped),
    content="(0, 1, 0)",
  )
  assert_true(result.failures[0].contains("expected I32(2), got I32(1)"))
}

///|
test "WAST thread joins reject unknown and already joined names" {
  for source in ["(wait $unknown)", "(thread $child)(wait $child)(wait $child)"] {
    let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
    debug_inspect(
      (result.passed, result.failed, result.skipped),
      content="(0, 1, 0)",
    )
    assert_true(result.failures[0].contains("no thread named"))
  }
}

///|
test "WAST shared contexts reject ordinary memory imports" {
  let source =
    #|(module $M (memory (export "memory") 1))
    #|(thread $child (shared (module $M))
    #| (module (memory (import "M" "memory") 1)))
    #|(wait $child)
  let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
  debug_inspect(
    (result.passed, result.failed, result.skipped),
    content="(0, 1, 0)",
  )
}

///|
test "WAST starts dispatch imported host and guest functions to their owners" {
  let source =
    #|(module (func $host (import "spectest" "print")) (start $host))
    #|(thread $child
    #| (module (func $host (import "spectest" "print")) (start $host)))
    #|(module $owner
    #| (global $counter (mut i32) (i32.const 0))
    #| (func (export "start")
    #|  global.get $counter i32.const 1 i32.add global.set $counter)
    #| (func (export "count") (result i32) global.get $counter))
    #|(register "owner" $owner)
    #|(module (func $start (import "owner" "start")) (start $start))
    #|(assert_return (invoke $owner "count") (i32.const 1))
  for use_jit in [false, true] {
    let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
      Ok(prepare_async_jit_context(mod_, instance, store, cooperative=true)) catch {
        error => Err("\{error}")
      }
    })
    let result = @wast.run_wast_commands(
      @wast.parse(source),
      ".",
      use_jit,
      false,
      jit_compiler=Some(compiler),
    )
    debug_inspect(
      (result.passed, result.failed, result.skipped),
      content="(1, 0, 0)",
    )
  }
}
