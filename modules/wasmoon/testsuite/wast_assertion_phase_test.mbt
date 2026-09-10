///|
test "WAST invalid and unlinkable assertions reject failures from the wrong phase" {
  let sources = [
    "(assert_invalid (module quote \"(module)\") \"\")", "(assert_unlinkable (module (func (result i32))) \"type mismatch\")",
    "(assert_unlinkable (module binary \"\\00asm\\01\\00\\00\\00\\01\\05\\01\\60\\00\\01\\7f\\03\\02\\01\\00\\0a\\04\\01\\02\\00\\0b\") \"type mismatch\")",
  ]
  for source in sources {
    let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
    debug_inspect((result.passed, result.failed), content="(0, 1)")
  }
}

///|
test "WAST quoted module text executes with its original module boundary" {
  let body =
    #|(module quote "(module (func (export \"run\") (result i32) i32.const 7))")
    #|(assert_return (invoke "run") (i32.const 7))
  let implicit_body =
    #|(module quote "(@annotation) (func (export \"run\") (result i32) i32.const 7) ;; trailing comment")
    #|(assert_return (invoke "run") (i32.const 7))
  for source in [body, implicit_body, "(module)(thread $child " + body + ")"] {
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
      debug_inspect((result.passed, result.failed), content="(1, 0)")
    }
  }
}

///|
test "WAST unlinkable assertions retain pinned start-trap behavior" {
  let source =
    #|(assert_invalid (module quote "(module (func (result i32)))") "type mismatch")
    #|(assert_unlinkable (module (func (import "missing" "f"))) "unknown import")
    #|(assert_unlinkable (module (func $start unreachable) (start $start)) "unreachable")
  let result = @wast.run_wast_commands(@wast.parse(source), ".", false, false)
  debug_inspect((result.passed, result.failed), content="(3, 0)")
}
