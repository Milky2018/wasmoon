///|
/// Trap preservation tests (JIT vs interpreter)

///|
test "JIT: dropped i32.load still traps" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "f") (param i32)
    #|    (drop (i32.load (local.get 0))))
    #|)
  let result = compare_jit_interp(source, "f", [I32(65536)])
  inspect(result, content="matched")
}

///|
test "JIT: dropped i32.load8_u still traps" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "f") (param i32)
    #|    (drop (i32.load8_u (local.get 0))))
    #|)
  let result = compare_jit_interp(source, "f", [I32(65536)])
  inspect(result, content="matched")
}
