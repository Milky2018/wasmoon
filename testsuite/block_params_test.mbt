///|
/// Tests for typed block parameters (multi-value extension).
/// These ensure block/if params are consumed from the outer stack and don't leak.

///|
test "typed block params: do not leak to outer stack" {
  let source =
    #|(module
    #|  (type $t (func (param f32)))
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Outer stack: [i32 8]
    #|    i32.const 8
    #|    ;; Block param: f32, should be consumed by the block and not affect return.
    #|    f32.const 0x1p-63
    #|    (block (type $t) (param f32)
    #|      ;; empty
    #|    )
    #|  )
    #|)
  let interp = run_interp_only(source, "test", [])
  inspect(interp, content="Ok([I32(8)])")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
