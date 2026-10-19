///|
test "portable WAST rejects mismatched results and trap categories" {
  let source =
    #|(module
    #|  (func (export "zero") (result f32) f32.const -0)
    #|  (func (export "trap") unreachable))
    #|(assert_return (invoke "zero") (f32.const 0))
    #|(assert_trap (invoke "trap") "integer divide by zero")
    #|(assert_exception (invoke "trap"))
  let result = @wast.run_script(source)
  assert_eq(result.passed, 0)
  assert_eq(result.failed, 3)
  assert_eq(result.unsupported.length(), 0)
}

///|
test "portable WAST reports unsupported directives instead of passing them" {
  let result = @wast.run_script("(thread $worker (module))")
  assert_eq(result.passed, 0)
  assert_eq(result.failed, 0)
  assert_eq(result.unsupported.length(), 1)
}

///|
#cfg(target="wasm")
test "unsupported shared memory stops the script with a separate verdict" {
  let source =
    #|(module (memory 1 1 shared))
    #|(assert_return (invoke "not-executed") (i32.const 0))
  let result = @wast.run_script(source)
  assert_eq(result.passed, 0)
  assert_eq(result.failed, 0)
  assert_eq(result.unsupported.length(), 1)
  assert_true(result.unsupported[0].contains("shared memory"))
}

///|
test "well-formed quoted text cannot satisfy assert_malformed" {
  let result = @wast.run_script(
    "(assert_malformed (module quote \"(module)\") \"expected malformed text\")",
  )
  assert_eq(result.passed, 0)
  assert_eq(result.failed, 1)
  assert_eq(result.unsupported.length(), 0)
}

///|
#cfg(target="wasm")
test "host capability denial cannot satisfy assert_unlinkable" {
  let result = @wast.run_script(
    "(assert_unlinkable (module (memory 1 1 shared)) \"unknown import\")",
  )
  assert_eq(result.passed, 0)
  assert_eq(result.failed, 0)
  assert_eq(result.unsupported.length(), 1)
}

///|
test "quoted start traps are parsed and checked against the expected category" {
  let source =
    #|(assert_trap (module quote "(module (func $s unreachable) (start $s))") "unreachable")
    #|(assert_trap (module quote "(module (func $s unreachable) (start $s))") "integer divide by zero")
  let result = @wast.run_script(source)
  assert_eq(result.passed, 1)
  assert_eq(result.failed, 1)
  assert_eq(result.unsupported.length(), 0)
}
