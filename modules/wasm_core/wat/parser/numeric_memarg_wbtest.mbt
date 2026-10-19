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
    accesses[:].to_owned(),
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

///|
test "text alignment decodes unsigned powers of two through bit 63" {
  let module_ = parse(
    (
      #|(module (memory 1 1 shared) (func
      #|  i32.const 0 i32.load align=0x8000_0000_0000_0000 drop
      #|  i32.const 0 i32.atomic.load align=0x8000_0000_0000_0000 drop
      #|  i32.const 0 v128.const i32x4 0 0 0 0
      #|  v128.load8_lane align=0x8000_0000_0000_0000 0 drop))
    ),
  )
  for instruction in module_.codes[0].body {
    match instruction {
      I32Load(_, align, _)
      | Atomic(_, _, align, _)
      | V128Load8Lane(_, align, _, _) => assert_eq(align, 63)
      _ => ()
    }
  }
  for alignment in ["0", "3", "0x1_0000_0000_0000_0000"] {
    try
      parse(
        "(module (memory 1) (func i32.const 0 i32.load align=" +
        alignment +
        " drop))",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid alignment syntax was accepted")
    }
  }
}
