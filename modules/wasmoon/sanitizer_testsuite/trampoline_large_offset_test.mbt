///|
test "native entry trampolines retain large argument frames and overflow results" {
  for
    (parameters, results, first) in [
      (16, 16, 0),
      (600, 1, 0),
      (600, 16, 0),
      (4200, 1, 4199),
    ] {
    let params = "i64 ".repeat(parameters)
    let returns = "i64 ".repeat(results)
    let body = Array::makei(results, i => "local.get \{i + first}").join(" ")
    let arguments = Array::makei(parameters, i => "(i64.const \{i + 10})").join(
      " ",
    )
    let expected = Array::makei(results, i => "(i64.const \{i + first + 10})").join(
      " ",
    )
    let source = "(module (func (export \"f\") (param \{params}) (result \{returns}) \{body})) (assert_return (invoke \"f\" \{arguments}) \{expected})"
    for opt_level in [0, 2] {
      let compiler = @wast.JITCompiler(fn(module_, instance, store) {
        Ok(build_gc_root_context(module_, instance, store, opt_level~)) catch {
          error => Err(error.to_string())
        }
      })
      for native in [false, true] {
        let result = @wast.run_wast_commands(
          @wast.parse(source),
          native,
          false,
          jit_compiler=Some(compiler),
        )
        assert_eq(result.failed, 0, msg=result.failures.join("\n"))
        assert_eq(result.passed, 1)
        assert_eq(result.skipped, 0)
      }
    }
  }
}
