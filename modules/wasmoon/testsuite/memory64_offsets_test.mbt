///|
test "memory64 data scalar SIMD and bulk accesses preserve high address bits" {
  let source =
    #|(module
    #| (memory i64 65537 65537)
    #| (memory i64 1 1)
    #| (data (i64.const 0) "\11\22\33\44")
    #| (data (i64.const 4294967296) "\01\02\03\04")
    #| (data $bytes "\aa\bb\cc\dd")
    #| (func (export "test") (result i32 i32 f64 i32 i32 i32 i32 i32 i32)
    #|  i64.const 0 i32.load
    #|  i64.const 4294967296 i32.load
    #|  i64.const 4294967304 f64.const 3.25 f64.store
    #|  i64.const 4294967304 f64.load
    #|  i64.const 4294967312 v128.const i32x4 10 20 30 40 v128.store
    #|  i64.const 4294967312 v128.load i32x4.extract_lane 3
    #|  i64.const 4294967328 i32.const 0 i32.const 4 memory.init $bytes
    #|  i64.const 4294967328 i32.load
    #|  i64.const 4294967332 i64.const 4294967328 i64.const 4 memory.copy
    #|  i64.const 4294967332 i32.load
    #|  i64.const 4294967336 i32.const 127 i64.const 4 memory.fill
    #|  i64.const 4294967336 i32.load
    #|  i64.const 0 i64.const 4294967328 i64.const 4 memory.copy 1 0
    #|  i64.const 0 i32.load 1
    #|  i64.const 8 i32.load i64.const 16 i32.load i32.or
    #|  i64.const 32 i32.load i32.or i64.const 36 i32.load i32.or
    #|  i64.const 40 i32.load i32.or))
  let result = @testsuite.compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
  inspect(
    result.to_string(),
    content=(
      #|JIT: I32(1144201745), I32(67305985), F64(3.25), I32(40), I32(-573785174), I32(-573785174), I32(2139062143), I32(-573785174), I32(0)
      #|Interpreter: I32(1144201745), I32(67305985), F64(3.25), I32(40), I32(-573785174), I32(-573785174), I32(2139062143), I32(-573785174), I32(0)
      #|Result: MATCH
    ),
  )
}

///|
test "memory64 unsigned offsets trap before accessing wrapped addresses" {
  let source =
    #|(module
    #|  (memory i64 1)
    #|  (data (i64.const 0) "A")
    #|  (func (export "load") (result i32)
    #|    i64.const 1 i32.load8_u offset=18446744073709551615)
    #|  (func (export "store")
    #|    i64.const 1 i32.const 99 i32.store8 offset=18446744073709551615)
    #|  (func (export "simd") (result i32)
    #|    i64.const 8 v128.load offset=18446744073709551608 i32x4.extract_lane 0)
    #|  (func (export "dynamic") (param i64) (result i32)
    #|    local.get 0 i32.load8_u offset=18446744073709551615)
    #|  (func (export "last") (result i32)
    #|    i64.const 65534 i32.load8_u offset=1)
    #|  (func (export "read") (result i32)
    #|    i64.const 0 i32.load8_u))
    #|(assert_trap (invoke "load") "out of bounds memory access")
    #|(assert_trap (invoke "store") "out of bounds memory access")
    #|(assert_trap (invoke "simd") "out of bounds memory access")
    #|(assert_trap (invoke "dynamic" (i64.const 1)) "out of bounds memory access")
    #|(assert_return (invoke "last") (i32.const 0))
    #|(assert_return (invoke "read") (i32.const 65))
  let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
    Ok(prepare_async_jit_context(mod_, instance, store)) catch {
      error => Err("\{error}")
    }
  })
  for jit in [false, true] {
    let result = @wast.run_wast_commands(
      @wast.parse(source),
      ".",
      jit,
      false,
      jit_compiler=Some(compiler),
    )
    assert_eq(result.failed, 0, msg=result.failures.join("\n"))
    assert_eq(result.skipped, 0)
    assert_eq(result.passed, 6)
  }
}
