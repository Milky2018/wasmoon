///|
test "canonical NaNs are visible inside guest execution and sign operations retain payloads" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "arithmetic") (param f32) (result i32)
    #|    i32.const 0
    #|    local.get 0 f32.const 1 f32.add
    #|    f32.store
    #|    i32.const 0 i32.load)
    #|  (func (export "promote") (param f32) (result i64)
    #|    local.get 0 f64.promote_f32 i64.reinterpret_f64)
    #|  (func (export "sign") (param f32) (result i32)
    #|    local.get 0 f32.abs f32.neg i32.reinterpret_f32)
    #|  (func (export "constant") (result i32)
    #|    f32.const nan:0x400001 i32.reinterpret_f32)
    #|  (func (export "load") (param f32) (result i32)
    #|    i32.const 0 local.get 0 f32.store
    #|    i32.const 0 f32.load i32.reinterpret_f32)
    #|  (func (export "vector") (param v128) (result i64)
    #|    local.get 0 f64x2.sqrt i64x2.extract_lane 0))
    #|(assert_return (invoke "arithmetic" (f32.const -nan:0x400001)) (i32.const 0x7fc00000))
    #|(assert_return (invoke "promote" (f32.const -nan:0x400001)) (i64.const 0x7ff8000000000000))
    #|(assert_return (invoke "sign" (f32.const nan:0x1)) (i32.const 0xff800001))
    #|(assert_return (invoke "constant") (i32.const 0x7fc00001))
    #|(assert_return (invoke "load" (f32.const -nan:0x400001)) (i32.const 0xffc00001))
    #|(assert_return (invoke "vector" (v128.const f64x2 -nan:0x8000000000001 1)) (i64.const 0x7ff8000000000000))
  let compiler = @wast.JITCompiler(fn(mod_, instance, store) {
    Ok(prepare_async_jit_context(mod_, instance, store)) catch {
      error => Err("\{error}")
    }
  })
  for use_jit in [false, true] {
    let result = @wast.run_wast_commands(
      @wast.parse(source),
      ".",
      use_jit,
      false,
      nan_canonicalization=true,
      jit_compiler=Some(compiler),
    )
    debug_inspect(result.failures, content="[]")
    inspect(result.passed, content="6")
  }
}
