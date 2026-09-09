///|
test "numeric memory indices and SIMD lanes have distinct immediate positions" {
  let source =
    #|(module (memory 1) (memory 1)
    #| (func
    #|  i32.const 0 i32.load 1 drop
    #|  i32.const 0 i32.const 7 i32.store 1
    #|  i32.const 0 v128.const i32x4 0 0 0 0 (v128.load8_lane 0) drop
    #|  i32.const 0 v128.const i32x4 0 0 0 0 v128.load8_lane 1 2 drop))
  let mod = parse(source)
  let accesses = mod.codes[0].body.filter(fn(instruction) {
    match instruction {
      I32Load(_, _, _) | I32Store(_, _, _) | V128Load8Lane(_, _, _, _) => true
      _ => false
    }
  })
  debug_inspect(
    accesses,
    content=(
      #|[
      #|  I32Load(1, 0, 0),
      #|  I32Store(1, 0, 0),
      #|  V128Load8Lane(0, 0, 0, 0),
      #|  V128Load8Lane(1, 0, 0, 2),
      #|]
    ),
  )
}
