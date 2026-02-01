///|
/// JIT regression tests for i32 bitcount instructions.
/// These specifically guard against incorrect constant-folding width (i32 vs i64).

///|
test "JIT: i32.clz constant folding uses 32-bit width" {
  let source =
    #|(module
    #|  (func (export "run") (result i32)
    #|    (i32.clz (i32.const 1))
    #|  )
    #|)
  let interp = run_interp_only(source, "run", [])
  inspect(interp, content="Ok([I32(31)])")
  let result = compare_jit_interp(source, "run", [])
  inspect(result, content="matched")
}

///|
test "JIT: i32.ctz constant folding clamps ctz(0) to 32" {
  let source =
    #|(module
    #|  (func (export "run") (result i32)
    #|    (i32.ctz (i32.const 0))
    #|  )
    #|)
  let interp = run_interp_only(source, "run", [])
  inspect(interp, content="Ok([I32(32)])")
  let result = compare_jit_interp(source, "run", [])
  inspect(result, content="matched")
}
