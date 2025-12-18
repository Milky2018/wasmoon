///|
// Test for if blocks with param types (WebAssembly multi-value extension)
test "if with param - simple" {
  let source =
    #|(module
    #|  (func (export "param") (param i32) (result i32)
    #|    (i32.const 1)
    #|    (if (param i32) (result i32) (local.get 0)
    #|      (then (i32.const 2) (i32.add))
    #|      (else (i32.const -2) (i32.add))
    #|    )
    #|  )
    #|)
  // When condition is 0 (false): 1 + (-2) = -1
  let r1 = compare_jit_interp(source, "param", [I32(0)])
  inspect(r1, content="matched")
  // When condition is 1 (true): 1 + 2 = 3
  let r2 = compare_jit_interp(source, "param", [I32(1)])
  inspect(r2, content="matched")
}

///|
test "if with two params" {
  let source =
    #|(module
    #|  (func (export "params") (param i32) (result i32)
    #|    (i32.const 1)
    #|    (i32.const 2)
    #|    (if (param i32 i32) (result i32) (local.get 0)
    #|      (then (i32.add))
    #|      (else (i32.sub))
    #|    )
    #|  )
    #|)
  // When condition is 0 (false): 1 - 2 = -1
  let r1 = compare_jit_interp(source, "params", [I32(0)])
  inspect(r1, content="matched")
  // When condition is 1 (true): 1 + 2 = 3
  let r2 = compare_jit_interp(source, "params", [I32(1)])
  inspect(r2, content="matched")
}

///|
test "if with params identity" {
  let source =
    #|(module
    #|  (func (export "params-id") (param i32) (result i32)
    #|    (i32.const 1)
    #|    (i32.const 2)
    #|    (if (param i32 i32) (result i32 i32) (local.get 0) (then))
    #|    (i32.add)
    #|  )
    #|)
  // Both branches just pass through: 1 + 2 = 3
  let r1 = compare_jit_interp(source, "params-id", [I32(0)])
  inspect(r1, content="matched")
  let r2 = compare_jit_interp(source, "params-id", [I32(1)])
  inspect(r2, content="matched")
}

///|
test "if with param and break" {
  let source =
    #|(module
    #|  (func (export "param-break") (param i32) (result i32)
    #|    (i32.const 1)
    #|    (if (param i32) (result i32) (local.get 0)
    #|      (then (i32.const 2) (i32.add) (br 0))
    #|      (else (i32.const -2) (i32.add) (br 0))
    #|    )
    #|  )
    #|)
  let r1 = compare_jit_interp(source, "param-break", [I32(0)])
  inspect(r1, content="matched")
  let r2 = compare_jit_interp(source, "param-break", [I32(1)])
  inspect(r2, content="matched")
}
